BeforeAll {
    $script:Collector = Join-Path $PSScriptRoot '..\00-Assessment\Collect-TenantInventory.ps1'

    # Load only the function definitions we need - the main body never runs.
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Collector, [ref]$null, [ref]$null)
    $names = @('Invoke-GraphFirst','Test-GraphForbidden','Get-AppSignInStatus',
               'Get-AppSignInQueryPlan','Get-AppSignInEta','Invoke-AppSignIns')
    $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        Where-Object { $names -contains $_.Name }
    foreach ($d in $defs) { . ([ScriptBlock]::Create($d.Extent.Text)) }

    # State the functions read from the collector script scope
    $script:MicrosoftTenantId = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'
    $script:SignInLookbackDays = 30
    $script:Summary = [pscustomobject]@{ metrics = @{}; skippedSections = @{} }
    $script:Exported = @{}

    # Stubs must exist before Pester can mock them
    function Write-Log { param([string]$Message, [string]$Level = 'INFO') }
    function Export-CsvSafe { param([object[]]$Data, [string]$Name) }
    function Get-GraphAll { param([string]$Uri, [hashtable]$Headers, [int]$MaxRetries = 5) }
    function Invoke-MgGraphRequest { param([hashtable]$Arguments) }

    Mock Write-Log {}
    Mock Export-CsvSafe { param($Data, $Name) $script:Exported[$Name] = @($Data) }

    function New-ForbiddenException {
        $ex = [System.Exception]::new('Forbidden')
        $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = [System.Net.HttpStatusCode]::Forbidden })
        return $ex
    }
}

Describe 'Test-GraphForbidden' {
    It 'detects HTTP 403 via the response status code' {
        $err = $null
        try { throw (New-ForbiddenException) } catch { $err = $_ }
        Test-GraphForbidden $err | Should -BeTrue
    }
    It 'detects licence errors via message text' {
        $err = $null
        try { throw "Authentication_RequestFromNonPremiumTenantOrB2CTenant: license required" } catch { $err = $_ }
        Test-GraphForbidden $err | Should -BeTrue
    }
    It 'does not match unrelated errors' {
        $err = $null
        try { throw "timeout" } catch { $err = $_ }
        Test-GraphForbidden $err | Should -BeFalse
    }
}

Describe 'Get-AppSignInStatus' {
    BeforeAll { $script:ws = [datetime]::UtcNow.AddDays(-30) }
    It 'ActiveInWindow on a log hit' {
        Get-AppSignInStatus -LogDates @([datetime]::UtcNow.AddDays(-2)) -LastReportDate $null -WindowStart $script:ws |
            Should -Be 'ActiveInWindow'
    }
    It 'ActiveInWindow when the report shows activity inside the window' {
        Get-AppSignInStatus -LogDates @() -LastReportDate ([datetime]::UtcNow.AddDays(-5)) -WindowStart $script:ws |
            Should -Be 'ActiveInWindow'
    }
    It 'ActiveEarlier when the report predates the window' {
        Get-AppSignInStatus -LogDates @() -LastReportDate ([datetime]::UtcNow.AddDays(-60)) -WindowStart $script:ws |
            Should -Be 'ActiveEarlier'
    }
    It 'NoActivityRecorded when both sources are available but empty' {
        Get-AppSignInStatus -LogDates @() -LastReportDate $null -WindowStart $script:ws |
            Should -Be 'NoActivityRecorded'
    }
    It 'Unknown when both sources are unavailable' {
        Get-AppSignInStatus -LogDates @() -LastReportDate $null -WindowStart $script:ws -LogsUnavailable -ReportUnavailable |
            Should -Be 'Unknown'
    }
}

Describe 'Get-AppSignInQueryPlan' {
    BeforeAll {
        $script:ws = [datetime]::UtcNow.AddDays(-30)
        $script:sps = @(
            [pscustomobject]@{ appId = 'a-recent'; IsManagedIdentity = $false }
            [pscustomobject]@{ appId = 'a-old';    IsManagedIdentity = $false }
            [pscustomobject]@{ appId = 'a-none';   IsManagedIdentity = $false }
            [pscustomobject]@{ appId = 'mi1';      IsManagedIdentity = $true }
        )
        $script:act = @{
            'a-recent' = [pscustomobject]@{ LastActivityDate = [datetime]::UtcNow.AddDays(-3) }
            'a-old'    = [pscustomobject]@{ LastActivityDate = [datetime]::UtcNow.AddDays(-90) }
            'mi1'      = [pscustomobject]@{ LastActivityDate = [datetime]::UtcNow.AddDays(-1) }
        }
    }
    It 'queries only apps with activity in the window' {
        $plan = Get-AppSignInQueryPlan -ServicePrincipals $script:sps -ActivityByAppId $script:act -WindowStart $script:ws
        $plan.AppId | Sort-Object -Unique | Should -Be @('a-recent', 'mi1')
    }
    It 'queries 3 event types for regular apps and only managedIdentity for managed identities' {
        $plan = Get-AppSignInQueryPlan -ServicePrincipals $script:sps -ActivityByAppId $script:act -WindowStart $script:ws
        @($plan | Where-Object AppId -eq 'a-recent').EventType | Should -Be @('interactiveUser','nonInteractiveUser','servicePrincipal')
        @($plan | Where-Object AppId -eq 'mi1').EventType | Should -Be @('managedIdentity')
    }
    It 'makes every app a candidate when the report is unavailable' {
        $plan = Get-AppSignInQueryPlan -ServicePrincipals $script:sps -ActivityByAppId @{} -WindowStart $script:ws -ReportUnavailable
        $plan.AppId | Sort-Object -Unique | Should -Be @('a-none', 'a-old', 'a-recent', 'mi1')
    }
}

Describe 'Invoke-AppSignIns (mocked)' {
    BeforeEach {
        $script:Summary.metrics = @{}
        $script:Exported = @{}
        $script:spsOut = @(
            [pscustomobject]@{ id='sp1'; appId='a-active'; displayName='Active App'; servicePrincipalType='Application'; appOwnerOrganizationId='tenant1'; accountEnabled=$true; preferredSingleSignOnMode='oauth'; tags=@() }
            [pscustomobject]@{ id='sp2'; appId='a-stale';  displayName='Stale App';  servicePrincipalType='Application'; appOwnerOrganizationId='tenant1'; accountEnabled=$true; preferredSingleSignOnMode=''; tags=@() }
        )
        $script:actsOut = @(
            [pscustomobject]@{ appId='a-active'; lastSignInActivity=[pscustomobject]@{lastSignInDateTime=([datetime]::UtcNow.AddDays(-2).ToString('o'))}; delegatedClientSignInActivity=$null; delegatedResourceSignInActivity=$null; applicationAuthenticationClientSignInActivity=$null; applicationAuthenticationResourceSignInActivity=$null }
            [pscustomobject]@{ appId='a-stale';  lastSignInActivity=[pscustomobject]@{lastSignInDateTime=([datetime]::UtcNow.AddDays(-90).ToString('o'))}; delegatedClientSignInActivity=$null; delegatedResourceSignInActivity=$null; applicationAuthenticationClientSignInActivity=$null; applicationAuthenticationResourceSignInActivity=$null }
        )
        Mock Get-GraphAll {
            param($Uri)
            if ($Uri -match 'servicePrincipalSignInActivities') { return $script:actsOut }
            return $script:spsOut
        }
        Mock Invoke-GraphFirst {
            return [pscustomobject]@{ createdDateTime = [datetime]::UtcNow.AddDays(-1).ToString('o') }
        }
    }

    It 'does not query sign-in logs for apps with no window activity' {
        Invoke-AppSignIns
        Assert-MockCalled Invoke-GraphFirst -Times 3 -Exactly -Scope It   # only a-active x3 types
        $rows = $script:Exported['AppSignInActivity.csv']
        @($rows | Where-Object AppId -eq 'a-active')[0].Status | Should -Be 'ActiveInWindow'
        @($rows | Where-Object AppId -eq 'a-stale')[0].Status | Should -Be 'ActiveEarlier'
        $script:Summary.metrics.appsActiveInWindowNonMicrosoft | Should -Be 1
    }

    It 'sets signInLogsUnavailable on a licence error and still writes the CSV' {
        Mock Invoke-GraphFirst { throw (New-ForbiddenException) }
        Invoke-AppSignIns
        $script:Summary.metrics.signInLogsUnavailable | Should -BeTrue
        Assert-MockCalled Invoke-GraphFirst -Times 1 -Exactly -Scope It   # stops after the first 403
        $rows = $script:Exported['AppSignInActivity.csv']
        $rows.Count | Should -Be 2
        @($rows | Where-Object AppId -eq 'a-stale')[0].Status | Should -Be 'ActiveEarlier'
        @($rows | Where-Object AppId -eq 'a-stale')[0].LastActivityReport | Should -Not -Be ''
    }

    It 'marks the app Unknown when both sources fail' {
        Mock Get-GraphAll {
            param($Uri)
            if ($Uri -match 'servicePrincipalSignInActivities') { throw (New-ForbiddenException) }
            return $script:spsOut
        }
        Mock Invoke-GraphFirst { throw (New-ForbiddenException) }
        Invoke-AppSignIns
        $script:Summary.metrics.spSignInActivityUnavailable | Should -BeTrue
        $script:Summary.metrics.signInLogsUnavailable | Should -BeTrue
        $rows = $script:Exported['AppSignInActivity.csv']
        $rows[0].Status | Should -Be 'Unknown'
    }
}

Describe 'Get-AppSignInEta' {
    It 'returns $null before 3 apps are done' {
        Get-AppSignInEta -Done 2 -Total 10 -Elapsed ([timespan]::FromSeconds(10)) | Should -BeNullOrEmpty
    }
    It 'estimates the remainder from the average per app' {
        # 10 of 100 done in 50 s -> 5 s/app x 90 left = 450 s
        [int](Get-AppSignInEta -Done 10 -Total 100 -Elapsed ([timespan]::FromSeconds(50))).TotalSeconds | Should -Be 450
    }
    It 'returns $null when all apps are done' {
        Get-AppSignInEta -Done 10 -Total 10 -Elapsed ([timespan]::FromSeconds(50)) | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-AppSignIns progress logging (mocked)' {
    BeforeEach {
        $script:Summary.metrics = @{}
        $script:Exported = @{}
        # 2 candidates (a1 active, mi1 active) + 1 skipped (a3 old)
        $sps = @(
            [pscustomobject]@{ id='s1'; appId='a1';  displayName='Contoso CRM'; servicePrincipalType='Application';      appOwnerOrganizationId='t'; accountEnabled=$true; preferredSingleSignOnMode=''; tags=@() }
            [pscustomobject]@{ id='s2'; appId='mi1'; displayName='Backup MI';    servicePrincipalType='ManagedIdentity'; appOwnerOrganizationId='t'; accountEnabled=$true; preferredSingleSignOnMode=''; tags=@() }
            [pscustomobject]@{ id='s3'; appId='a3';  displayName='Old App';      servicePrincipalType='Application';      appOwnerOrganizationId='t'; accountEnabled=$true; preferredSingleSignOnMode=''; tags=@() }
        )
        $acts = @(
            [pscustomobject]@{ appId='a1';  lastSignInActivity=[pscustomobject]@{lastSignInDateTime=([datetime]::UtcNow.AddDays(-2).ToString('o'))}; delegatedClientSignInActivity=$null; delegatedResourceSignInActivity=$null; applicationAuthenticationClientSignInActivity=$null; applicationAuthenticationResourceSignInActivity=$null }
            [pscustomobject]@{ appId='mi1'; lastSignInActivity=[pscustomobject]@{lastSignInDateTime=([datetime]::UtcNow.AddDays(-2).ToString('o'))}; delegatedClientSignInActivity=$null; delegatedResourceSignInActivity=$null; applicationAuthenticationClientSignInActivity=$null; applicationAuthenticationResourceSignInActivity=$null }
            [pscustomobject]@{ appId='a3';  lastSignInActivity=[pscustomobject]@{lastSignInDateTime=([datetime]::UtcNow.AddDays(-90).ToString('o'))}; delegatedClientSignInActivity=$null; delegatedResourceSignInActivity=$null; applicationAuthenticationClientSignInActivity=$null; applicationAuthenticationResourceSignInActivity=$null }
        )
        Mock Get-GraphAll { param($Uri) if ($Uri -match 'servicePrincipalSignInActivities') { return $acts } else { return $sps } }
        Mock Invoke-GraphFirst { return [pscustomobject]@{ createdDateTime = [datetime]::UtcNow.AddDays(-1).ToString('o') } }
        Mock Write-Progress {}
    }

    It 'logs step headers and per-app lines for candidates only' {
        Invoke-AppSignIns
        Should -Invoke Write-Log -ParameterFilter { $Message -match '^AppSignIns 1/4' } -Times 1
        Should -Invoke Write-Log -ParameterFilter { $Message -match '^AppSignIns 2/4' } -Times 1
        Should -Invoke Write-Log -ParameterFilter { $Message -match '^AppSignIns 3/4.*4 queries planned.*1 apps skipped' } -Times 1
        Should -Invoke Write-Log -ParameterFilter { $Message -match '^AppSignIns 4/4' } -Times 1
        Should -Invoke Write-Log -ParameterFilter { $Message -match '^\[\s*1/2\] Contoso CRM' } -Times 2   # query + result line
        Should -Invoke Write-Log -ParameterFilter { $Message -match '^\[\s*2/2\] Backup MI' } -Times 2
        Should -Invoke Write-Log -ParameterFilter { $Message -match 'Old App' } -Times 0   # skipped app: no lines
        Should -Invoke Write-Log -ParameterFilter { $Message -match 'managedIdentity' }    # MI query plan shows the type
    }

    It 'calls Write-Progress and completes it' {
        Invoke-AppSignIns
        Should -Invoke Write-Progress -ParameterFilter { $Activity -eq 'AppSignIns' -and $Completed } -Times 1
        Should -Invoke Write-Progress -ParameterFilter { $Activity -eq 'AppSignIns' -and $Status -match 'Contoso CRM - nonInteractiveUser' }
    }

    It 'throttle WARN names the app via -Context' {
        Mock Invoke-GraphFirst {
            param($Uri, $Headers, $MaxRetries, $Context)
            Write-Log "Throttled (429) on $Context - waiting 10 sec." -Level WARN
            return $null
        }
        Invoke-AppSignIns
        Should -Invoke Write-Log -ParameterFilter { $Message -match 'Throttled \(429\) on Contoso CRM / nonInteractiveUser' }
    }
}

Describe 'Invoke-GraphFirst -Context' {
    It 'names the context instead of the URI in the throttle WARN' {
        Mock Invoke-MgGraphRequest {
            $ex = [System.Exception]::new('throttled')
            $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{
                StatusCode = [System.Net.HttpStatusCode]::TooManyRequests
                Headers    = @{ 'Retry-After' = @('1') }
            })
            throw $ex
        }
        Mock Start-Sleep {}
        { Invoke-GraphFirst -Uri 'https://x' -Context 'Contoso CRM / nonInteractiveUser' -MaxRetries 1 } | Should -Throw
        Should -Invoke Write-Log -ParameterFilter { $Message -match 'on Contoso CRM / nonInteractiveUser - waiting' -and $Level -eq 'WARN' }
    }
}
