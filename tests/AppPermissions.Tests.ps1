BeforeAll {
    $script:Collector = Join-Path $PSScriptRoot '..\00-Assessment\Collect-TenantInventory.ps1'

    # Load only the function definitions we need - the main body never runs.
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Collector, [ref]$null, [ref]$null)
    $names = @('Test-HighPrivilegePermission', 'ConvertTo-AppPermissionRows',
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

Describe 'ConvertTo-AppPermissionRows' {
    BeforeAll {
        $script:clients = @([pscustomobject]@{ id = 'sp-1'; appId = 'app-1'; displayName = 'Contoso App' })
        $script:assign = @{ 'sp-1' = @(
            @{ resourceId = 'rsp-graph'; appRoleId = 'role-1' }
            @{ resourceId = 'rsp-graph'; appRoleId = 'role-unresolved' }
        ) }
        $script:grants = @(
            [pscustomobject]@{ clientId = 'sp-1'; resourceId = 'rsp-graph'; consentType = 'AllPrincipals'; principalId = $null; scope = 'User.Read Mail.Send' }
            [pscustomobject]@{ clientId = 'sp-1'; resourceId = 'rsp-graph'; consentType = 'Principal';    principalId = 'user-a';   scope = 'Calendars.Read' }
            [pscustomobject]@{ clientId = 'sp-1'; resourceId = 'rsp-graph'; consentType = 'Principal';    principalId = 'user-b';   scope = 'Calendars.Read' }
        )
        $script:resources = @{ 'rsp-graph' = $script:graphRes }
        $script:rows = @(ConvertTo-AppPermissionRows -ClientServicePrincipals $script:clients `
            -RoleAssignmentsByClientId $script:assign -PermissionGrants $script:grants `
            -ResourceServicePrincipals $script:resources)
    }

    It 'resolves application grants to permission names' {
        $r = @($script:rows | Where-Object { $_.PermissionType -eq 'Application' -and $_.Permission -eq 'Mail.ReadWrite' })
        $r.Count | Should -Be 1
        $r[0].Resource      | Should -Be 'Microsoft Graph'
        $r[0].Resolved      | Should -BeTrue
        $r[0].IsHighPrivilege | Should -BeTrue
        $r[0].ConsentType   | Should -Be 'Admin'
    }

    It 'keeps the GUID and marks Resolved=False for unknown appRoleIds' {
        $r = @($script:rows | Where-Object { $_.PermissionType -eq 'Application' -and -not $_.Resolved })
        $r.Count | Should -Be 1
        $r[0].Permission | Should -Be 'role-unresolved'
    }

    It 'splits delegated grants into one row per scope' {
        $delegated = @($script:rows | Where-Object PermissionType -eq 'Delegated')
        $delegated.Count | Should -Be 4   # User.Read + Mail.Send (admin) + 2x Calendars.Read (user)
        @($delegated | Where-Object { $_.Permission -eq 'Mail.Send' }).Count | Should -Be 1
    }

    It 'maps consent types and counts users without exposing IDs' {
        $admin = @($script:rows | Where-Object { $_.PermissionType -eq 'Delegated' -and $_.ConsentType -eq 'Admin' })
        $admin.Count | Should -Be 2   # User.Read + Mail.Send from the AllPrincipals grant
        $admin[0].ConsentedUserCount | Should -Be ''
        $user = @($script:rows | Where-Object { $_.Permission -eq 'Calendars.Read' })
        $user.Count | Should -Be 2    # one row per principal grant
        $user[0].ConsentType | Should -Be 'User'
        $user[0].ConsentedUserCount | Should -Be 2   # user-a + user-b
        ($script:rows | ConvertTo-Json) | Should -Not -Match 'user-[ab]'
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
