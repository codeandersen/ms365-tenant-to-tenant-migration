BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\00-Assessment\InventoryAnalysis.psm1') -Force

    $script:Od1 = [pscustomobject]@{ Url = 'https://contoso-my.sharepoint.com/personal/soren_contoso_com'; Owner = 'soren@contoso.com' }
    $script:Od2 = [pscustomobject]@{ Url = 'https://contoso-my.sharepoint.com/personal/anna_contoso_com/'; Owner = 'anna@contoso.com' }
    $script:Ods = @($script:Od1, $script:Od2)
}

Describe 'Get-OneDriveHoldStatus' {
    It 'marks every OneDrive when an enabled policy has OneDriveLocation All' {
        $pol = [pscustomobject]@{ Name = 'KeepAll'; Enabled = 'True'; Mode = 'Enforce'; OneDriveLocation = 'All'; AdaptiveScopeLocation = '' }
        $r = Get-OneDriveHoldStatus -OneDrives $script:Ods -RetentionPolicies @($pol) -RetentionCsvPresent $true
        $r.Evaluated | Should -BeTrue
        $r.Rows.Count | Should -Be 2
        $r.Rows[0].Reasons | Should -Match "Retention policy 'KeepAll' \(all OneDrive\)"
        $r.Rows[0].OnHold | Should -Be 'True'
    }

    It 'matches a specific URL case-insensitively and trailing-slash tolerant' {
        $pol = [pscustomobject]@{ Name = 'KeepOne'; Enabled = 'True'; Mode = 'Enforce'; OneDriveLocation = 'HTTPS://CONTOSO-MY.SHAREPOINT.COM/PERSONAL/anna_contoso_com'; AdaptiveScopeLocation = '' }
        $r = Get-OneDriveHoldStatus -OneDrives $script:Ods -RetentionPolicies @($pol) -RetentionCsvPresent $true
        $r.Rows.Count | Should -Be 1
        $r.Rows[0].Owner | Should -Be 'anna@contoso.com'
        $r.Rows[0].Reasons | Should -Match 'targeted'
    }

    It 'marks OneDrives under an enabled eDiscovery case hold' {
        $hold = [pscustomobject]@{ CaseName = 'CaseA'; CaseStatus = 'Active'; HoldPolicyName = 'Hold1'; Enabled = 'True'; SharePointLocation = 'https://contoso-my.sharepoint.com/personal/soren_contoso_com' }
        $r = Get-OneDriveHoldStatus -OneDrives $script:Ods -CaseHoldPolicies @($hold) -RetentionCsvPresent $true
        $r.Rows.Count | Should -Be 1
        $r.Rows[0].Reasons | Should -Match "eDiscovery hold 'CaseA/Hold1'"
    }

    It 'holds all OneDrives when the case hold has SharePointLocation All' {
        $hold = [pscustomobject]@{ CaseName = 'CaseA'; CaseStatus = 'Active'; HoldPolicyName = 'Hold1'; Enabled = 'True'; SharePointLocation = 'All' }
        $r = Get-OneDriveHoldStatus -OneDrives $script:Ods -CaseHoldPolicies @($hold) -RetentionCsvPresent $true
        $r.Rows.Count | Should -Be 2
    }

    It 'ignores disabled policies and policies with empty OneDrive locations' {
        $off = [pscustomobject]@{ Name = 'Off'; Enabled = 'False'; Mode = 'Enforce'; OneDriveLocation = 'All'; AdaptiveScopeLocation = '' }
        $exo = [pscustomobject]@{ Name = 'MailOnly'; Enabled = 'True'; Mode = 'Enforce'; OneDriveLocation = ''; ExchangeLocation = 'All'; AdaptiveScopeLocation = '' }
        $r = Get-OneDriveHoldStatus -OneDrives $script:Ods -RetentionPolicies @($off, $exo) -RetentionCsvPresent $true
        $r.Rows.Count | Should -Be 0
    }

    It 'reports Evaluated=false when the retention CSV is absent' {
        $r = Get-OneDriveHoldStatus -OneDrives $script:Ods -RetentionCsvPresent $false
        $r.Evaluated | Should -BeFalse
    }

    It 'flags adaptive scope policies that target OneDrive' {
        $pol = [pscustomobject]@{ Name = 'Adapt'; Enabled = 'True'; Mode = 'Enforce'; OneDriveLocation = ''; AdaptiveScopeLocation = 'OneDrive users' }
        $scope = [pscustomobject]@{ Name = 'OneDrive users'; LocationType = 'OneDriveAccounts'; FilterConditions = ''; RawQuery = '' }
        $r = Get-OneDriveHoldStatus -OneDrives $script:Ods -RetentionPolicies @($pol) -AdaptiveScopes @($scope) -RetentionCsvPresent $true -AdaptiveScopesCsvPresent $true
        $r.AdaptiveTargetsOneDrive | Should -BeTrue
        $r.AdaptiveScopesMissing | Should -BeFalse
        # OneDrive rows cannot be resolved statically -> not marked held
        $r.Rows.Count | Should -Be 0
    }

    It 'flags AdaptiveScopesMissing when scopes were not inventoried' {
        $pol = [pscustomobject]@{ Name = 'Adapt'; Enabled = 'True'; Mode = 'Enforce'; OneDriveLocation = ''; AdaptiveScopeLocation = 'ScopeX' }
        $r = Get-OneDriveHoldStatus -OneDrives $script:Ods -RetentionPolicies @($pol) -RetentionCsvPresent $true -AdaptiveScopesCsvPresent $false
        $r.AdaptiveScopesMissing | Should -BeTrue
    }
}

Describe 'Get-PowerPlatformOwnerStatus' {
    BeforeAll {
        $script:Users = @(
            [pscustomobject]@{ UserPrincipalName = 'active@contoso.com'; Mail = 'active@contoso.com'; DisplayName = 'Active User'; UserType = 'Member'; IsGuest = 'False'; AccountEnabled = 'True' },
            [pscustomobject]@{ UserPrincipalName = 'disabled@contoso.com'; Mail = ''; DisplayName = 'Gone User'; UserType = 'Member'; IsGuest = 'False'; AccountEnabled = 'False' },
            [pscustomobject]@{ UserPrincipalName = 'guest@fabrikam.com'; Mail = ''; DisplayName = 'Guest'; UserType = 'Guest'; IsGuest = 'True'; AccountEnabled = 'True' }
        )
    }
    It 'classifies Active, Disabled, Guest, NotFound and Unknown owners' {
        $items = @(
            [pscustomobject]@{ DisplayName = 'a'; Owner = 'ACTIVE@contoso.com' },
            [pscustomobject]@{ DisplayName = 'b'; Owner = 'disabled@contoso.com' },
            [pscustomobject]@{ DisplayName = 'c'; Owner = 'guest@fabrikam.com' },
            [pscustomobject]@{ DisplayName = 'd'; Owner = 'deleted@contoso.com' },
            [pscustomobject]@{ DisplayName = 'e'; Owner = '' }
        )
        $r = Get-PowerPlatformOwnerStatus -Items $items -Users $script:Users
        $r[0].OwnerStatus | Should -Be 'Active'
        $r[1].OwnerStatus | Should -Be 'Disabled'
        $r[2].OwnerStatus | Should -Be 'Guest'
        $r[3].OwnerStatus | Should -Be 'NotFound'
        $r[4].OwnerStatus | Should -Be 'Unknown'
    }
}

Describe 'Get-ConnectorUsage' {
    It 'normalizes shared_ names, strips GUID suffixes and counts per kind' {
        $apps = @(
            [pscustomobject]@{ ConnectorsUsed = 'shared_sharepointonline;shared_office365users' },
            [pscustomobject]@{ ConnectorsUsed = 'shared_sharepointonline' }
        )
        $flows = @(
            [pscustomobject]@{ ConnectorsUsed = 'shared_sql;customapi-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }
        )
        $r = Get-ConnectorUsage -Apps $apps -Flows $flows
        $spo = $r | Where-Object Connector -eq 'sharepointonline'
        $spo.Apps | Should -Be 2
        $spo.Flows | Should -Be 0
        ($r | Where-Object Connector -eq 'customapi').Flows | Should -Be 1
        ($r | Where-Object Connector -eq 'office365users').Apps | Should -Be 1
    }

    It 'flags on-prem/external/custom connectors' {
        $apps = @([pscustomobject]@{ ConnectorsUsed = 'shared_sql;shared_http;shared_filesystem;shared_sharepointonline' })
        $r = Get-ConnectorUsage -Apps $apps
        ($r | Where-Object Connector -eq 'sql').OnPremOrExternal | Should -BeTrue
        ($r | Where-Object Connector -eq 'http').OnPremOrExternal | Should -BeTrue
        ($r | Where-Object Connector -eq 'filesystem').OnPremOrExternal | Should -BeTrue
        ($r | Where-Object Connector -eq 'sharepointonline').OnPremOrExternal | Should -BeFalse
    }

    It 'flags connectors that appear in the custom connector list' {
        $apps = @([pscustomobject]@{ ConnectorsUsed = 'contosoloader' })
        $custom = @([pscustomobject]@{ Name = 'contosoloader'; DisplayName = 'Contoso Loader' })
        $r = Get-ConnectorUsage -Apps $apps -CustomConnectors $custom
        $r[0].OnPremOrExternal | Should -BeTrue
    }
}
