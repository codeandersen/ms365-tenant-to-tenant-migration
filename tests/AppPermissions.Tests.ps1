BeforeAll {
    $script:Collector = Join-Path $PSScriptRoot '..\00-Assessment\Collect-TenantInventory.ps1'

    # Load only the function definitions we need - the main body never runs.
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Collector, [ref]$null, [ref]$null)
    $names = @('Test-HighPrivilegePermission', 'ConvertTo-AppPermissionSummaryRows',
               'ConvertTo-AppDelegatedUserRows', 'Resolve-GraphUsersById',
               'ConvertTo-AppRegistrationPermissionRows', 'Get-ObjProp', 'Invoke-PowerPlatform')
    $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        Where-Object { $names -contains $_.Name }
    foreach ($d in $defs) { . ([ScriptBlock]::Create($d.Extent.Text)) }

    $script:MicrosoftTenantId = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'
    $script:HighPrivilegePermissionPatterns = @(
        '*.ReadWrite.All', 'Mail.*', 'Files.*.All', 'Sites.*.All', 'Directory.*',
        'RoleManagement.*', 'full_access_as_app', 'Application.ReadWrite.All')
    $script:Summary = [pscustomobject]@{ metrics = @{}; skippedSections = @{}; failedSections = @{} }
    $script:PowerPlatformConnected = $false

    function Write-Log { param([string]$Message, [string]$Level = 'INFO') }
    function Export-CsvSafe { param([object[]]$Data, [string]$Name) }
    Mock Write-Log {}
    Mock Export-CsvSafe {}

    $script:graphRes = @{ DisplayName = 'Microsoft Graph'; AppId = '00000003-0000-0000-c000-000000000000';
        Roles  = @{ 'role-1' = 'Mail.ReadWrite'; 'role-2' = 'User.Read.All' }
        Scopes = @{ 'scope-1' = 'User.Read'; 'scope-2' = 'Mail.Send' } }
}

Describe 'Test-HighPrivilegePermission' {
    It 'flags broad permissions' {
        Test-HighPrivilegePermission 'Sites.ReadWrite.All'   | Should -BeTrue
        Test-HighPrivilegePermission 'Mail.ReadWrite'        | Should -BeTrue
        Test-HighPrivilegePermission 'full_access_as_app'    | Should -BeTrue
        Test-HighPrivilegePermission 'RoleManagement.Read.Directory' | Should -BeTrue
        Test-HighPrivilegePermission 'Files.Read.All'        | Should -BeTrue
    }
    It 'does not flag ordinary permissions' {
        Test-HighPrivilegePermission 'User.Read'             | Should -BeFalse
        Test-HighPrivilegePermission 'openid'                | Should -BeFalse
        Test-HighPrivilegePermission 'offline_access'        | Should -BeFalse
        Test-HighPrivilegePermission ''                      | Should -BeFalse
    }
}

Describe 'ConvertTo-AppPermissionSummaryRows' {
    BeforeAll {
        $script:clients = @([pscustomobject]@{ id = 'sp-1'; appId = 'app-1'; displayName = 'Contoso App' })
        $script:assign = @{ 'sp-1' = @(
            @{ resourceId = 'rsp-graph'; appRoleId = 'role-1' }
            @{ resourceId = 'rsp-graph'; appRoleId = 'role-unresolved' }
        ) }
        # 3 users consenting the same app+resource with overlapping scopes +
        # one AllPrincipals (admin) grant on the same pair.
        $script:grants = @(
            [pscustomobject]@{ clientId = 'sp-1'; resourceId = 'rsp-graph'; consentType = 'AllPrincipals'; principalId = $null;    scope = 'User.Read Mail.Send' }
            [pscustomobject]@{ clientId = 'sp-1'; resourceId = 'rsp-graph'; consentType = 'Principal';    principalId = 'user-a'; scope = 'Calendars.Read Mail.Send' }
            [pscustomobject]@{ clientId = 'sp-1'; resourceId = 'rsp-graph'; consentType = 'Principal';    principalId = 'user-b'; scope = 'Calendars.Read' }
            [pscustomobject]@{ clientId = 'sp-1'; resourceId = 'rsp-graph'; consentType = 'Principal';    principalId = 'user-c'; scope = 'Calendars.Read Files.Read' }
        )
        $script:resources = @{ 'rsp-graph' = $script:graphRes }
        $script:rows = @(ConvertTo-AppPermissionSummaryRows -ClientServicePrincipals $script:clients `
            -RoleAssignmentsByClientId $script:assign -PermissionGrants $script:grants `
            -ResourceServicePrincipals $script:resources)
    }

    It 'emits one row per app+resource pair' {
        $script:rows.Count | Should -Be 1
        $script:rows[0].Resource | Should -Be 'Microsoft Graph'
    }

    It 'separates application and delegated permissions into own columns' {
        $r = $script:rows[0]
        $r.ApplicationPermissions           | Should -Be 'Mail.ReadWrite; role-unresolved'
        $r.DelegatedPermissionsAdminConsent | Should -Be 'Mail.Send; User.Read'
        $r.DelegatedPermissionsUserConsent  | Should -Be 'Calendars.Read; Files.Read; Mail.Send'
        $r.UserConsentCount                 | Should -Be 3
    }

    It 'flags high-privilege subsets separately per kind' {
        $r = $script:rows[0]
        $r.HighPrivilegeApplication | Should -Match 'Mail\.ReadWrite'
        $r.HighPrivilegeDelegated   | Should -Match 'Mail\.Send'
        $r.HighPrivilegeDelegated   | Should -Not -Match 'Calendars'
    }

    It 'keeps unresolved appRoleIds in UnresolvedPermissions' {
        $script:rows[0].UnresolvedPermissions | Should -Be 'role-unresolved'
    }
}

Describe 'ConvertTo-AppDelegatedUserRows' {
    BeforeAll {
        $script:userMap = @{
            'user-a' = @{ UserPrincipalName = 'anna@contoso.com'; DisplayName = 'Anna' }
            'user-b' = @{ UserPrincipalName = 'bob@contoso.com';  DisplayName = 'Bob' }
            # user-c deliberately absent -> deleted/unresolved
        }
        $script:urows = @(ConvertTo-AppDelegatedUserRows -ClientServicePrincipals $script:clients `
            -PermissionGrants $script:grants -ResourceServicePrincipals $script:resources `
            -UsersById $script:userMap)
    }

    It 'emits one admin row + one row per consenting user per app+resource' {
        $script:urows.Count | Should -Be 4   # 1 'All users' + user-a/b/c
        @($script:urows | Where-Object { $_.UserPrincipalName -eq 'All users (admin consent)' }).Count | Should -Be 1
        @($script:urows | Where-Object { "$($_.UserId)" }).Count | Should -Be 3
    }

    It 'gives each user only their own scopes' {
        ($script:urows | Where-Object UserId -eq 'user-a').DelegatedPermissions | Should -Be 'Calendars.Read; Mail.Send'
        ($script:urows | Where-Object UserId -eq 'user-b').DelegatedPermissions | Should -Be 'Calendars.Read'
        ($script:urows | Where-Object UserId -eq 'user-c').DelegatedPermissions | Should -Be 'Calendars.Read; Files.Read'
        ($script:urows | Where-Object { $_.UserPrincipalName -eq 'All users (admin consent)' }).DelegatedPermissions |
            Should -Be 'Mail.Send; User.Read'
    }

    It 'resolves UPNs and uses a placeholder for deleted users' {
        ($script:urows | Where-Object UserId -eq 'user-a').UserPrincipalName | Should -Be 'anna@contoso.com'
        ($script:urows | Where-Object UserId -eq 'user-c').UserPrincipalName | Should -Be '(deleted or unresolved user)'
        ($script:urows | Where-Object UserId -eq 'user-c').UserId | Should -Be 'user-c'
    }
}

Describe 'Resolve-GraphUsersById' {
    It 'chunks getByIds at 1000 ids per POST' {
        $script:callCount = 0
        Mock Invoke-MgGraphRequest {
            param($Method, $Uri, $Body, $ContentType, $OutputType, $ErrorAction)
            $script:callCount++
            $ids = ($Body | ConvertFrom-Json).ids
            [pscustomobject]@{ value = @($ids | ForEach-Object {
                [pscustomobject]@{ id = $_; userPrincipalName = "$_`@contoso.com"; displayName = "U $_" }
            }) }
        }
        $map = Resolve-GraphUsersById -PrincipalIds @(1..1500 | ForEach-Object { "user-$_" })
        $script:callCount | Should -Be 2
        $map.Count | Should -Be 1500
        $map['user-42'].UserPrincipalName | Should -Be 'user-42@contoso.com'
    }
}

Describe 'ConvertTo-AppRegistrationPermissionRows' {
    It 'flattens requiredResourceAccess and resolves names' {
        $apps = @([pscustomobject]@{ id = 'obj-1'; appId = 'app-1'; displayName = 'Contoso App';
            requiredResourceAccess = @([pscustomobject]@{
                resourceAppId  = '00000003-0000-0000-c000-000000000000'
                resourceAccess = @(
                    [pscustomobject]@{ id = 'role-1'; type = 'Role' }
                    [pscustomobject]@{ id = 'scope-1'; type = 'Scope' }
                )
            })
        })
        $res = @{ '00000003-0000-0000-c000-000000000000' = $script:graphRes }
        $rows = @(ConvertTo-AppRegistrationPermissionRows -Applications $apps -ResourceByAppId $res)
        $rows.Count | Should -Be 2
        $role = @($rows | Where-Object PermissionType -eq 'Application')[0]
        $role.Permission | Should -Be 'Mail.ReadWrite'
        $role.Resource   | Should -Be 'Microsoft Graph'
        $scope = @($rows | Where-Object PermissionType -eq 'Delegated')[0]
        $scope.Permission | Should -Be 'User.Read'
        $scope.Resolved   | Should -BeTrue
    }

    It 'keeps the permission id when the resource is unknown' {
        $apps = @([pscustomobject]@{ id = 'obj-1'; appId = 'app-1'; displayName = 'Contoso App';
            requiredResourceAccess = @([pscustomobject]@{ resourceAppId = 'unknown-res';
                resourceAccess = @([pscustomobject]@{ id = 'perm-9'; type = 'Role' }) }) })
        $rows = @(ConvertTo-AppRegistrationPermissionRows -Applications $apps -ResourceByAppId @{})
        $rows[0].Permission | Should -Be 'perm-9'
        $rows[0].Resolved   | Should -BeFalse
        $rows[0].Resource   | Should -Be ''
    }
}

Describe 'Invoke-PowerPlatform' {
    It 'throws cleanly when the Power Platform session is not connected' {
        $script:PowerPlatformConnected = $false
        { Invoke-PowerPlatform } | Should -Throw '*not connected*'
    }
    It 'is skipped in the child process when the admin module is missing' {
        $src = [System.IO.File]::ReadAllText($script:Collector)
        $src | Should -Match "skippedSections\['PowerPlatform'\] = 'Module Microsoft\.PowerApps\.Administration\.PowerShell missing"
    }
}

Describe 'Get-ObjProp' {
    It 'reads nested properties safely' {
        $o = [pscustomobject]@{ Internal = [pscustomobject]@{ properties = [pscustomobject]@{ tenantId = 't-1' } } }
        Get-ObjProp (Get-ObjProp $o.Internal 'properties') 'tenantId' | Should -Be 't-1'
        Get-ObjProp $o 'missing'  | Should -BeNullOrEmpty
        Get-ObjProp $null 'x'     | Should -BeNullOrEmpty
        Get-ObjProp @{ a = 1 } 'a' | Should -Be 1
        Get-ObjProp @{ a = 1 } 'b' | Should -BeNullOrEmpty
    }
}
