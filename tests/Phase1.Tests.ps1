BeforeAll {
    $script:Collector = Join-Path $PSScriptRoot '..\00-Assessment\Collect-TenantInventory.ps1'

    # AST-load only the function definitions we need - the main body never runs.
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Collector, [ref]$null, [ref]$null)
    $names = @('Get-SiteType','ConvertTo-ThirdPartyEvidence','ConvertTo-AppCredentialRows',
               'ConvertTo-SamlCertificateRows','ConvertTo-InboxRuleForwarding','Get-DaysToExpiry',
               'Get-UpnDomain','Invoke-Collector','Get-CollectorRegistryEntry','Test-CollectorLevel',
               'Test-GraphForbidden','Test-LicenseGate')
    $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        Where-Object { $names -contains $_.Name }
    foreach ($d in $defs) { . ([ScriptBlock]::Create($d.Extent.Text)) }

    $regFile = Join-Path $PSScriptRoot '..\00-Assessment\Collectors.psd1'
    $regP1   = Join-Path $PSScriptRoot '..\00-Assessment\Collectors.Phase1.psd1'
    $script:Reg = @((Import-PowerShellDataFile $regFile).Collectors) +
                  @((Import-PowerShellDataFile $regP1).Collectors)
    $script:CollectorRegistry    = @{}
    $script:CollectorRegistryAll = @($script:Reg)
    foreach ($c in $script:Reg) { $script:CollectorRegistry[$c.Name] = $c }

    $script:Summary     = [pscustomobject]@{ metrics = @{}; skippedSections = @{}; failedSections = @{} }
    $script:Level       = 'Advanced'
    $script:TenantGuid  = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    $script:ToolVersion = '1.0'
    $global:TenantName  = 'Contoso'
    function Write-Log { param([string]$Message, [string]$Level = 'INFO') }
    function Export-CsvSafe { param([object[]]$Data, [string]$Name) }
    Mock Write-Log {}
    Mock Export-CsvSafe {}
}

Describe 'Get-SiteType classification' {
    It 'classifies the standard templates' {
        Get-SiteType -Template 'SITEPAGEPUBLISHING#0' | Should -Be 'Communication'
        Get-SiteType -Template 'GROUP#0'             | Should -Be 'GroupConnected'
        Get-SiteType -Template 'TEAMCHANNEL#0'       | Should -Be 'PrivateChannel'
        Get-SiteType -Template 'TEAMCHANNEL#1'       | Should -Be 'SharedChannel'
        Get-SiteType -Template 'STS#0' -IsTeamsConnected $true | Should -Be 'TeamsConnected'
        Get-SiteType -Template 'STS#0' -IsTeamsConnected $false | Should -Be 'Team'
        Get-SiteType -Template 'APPCATALOG#0'        | Should -Be 'AppCatalog'
    }
    It 'falls back to Other for unknown templates' {
        Get-SiteType -Template 'FUTURETEMPLATE#9' | Should -Be 'Other'
        Get-SiteType -Template ''                 | Should -Be 'Other'
    }
}

Describe 'ConvertTo-ThirdPartyEvidence' {
    It 'flags concrete vendor records' {
        $dns = @([pscustomobject]@{ Domain = 'contoso.com'; MX = '10 eu-west-1.protection.mimecast.com'; SPF = 'v=spf1 include:_netblocks.mimecast.com include:spf.protection.outlook.com -all' })
        $rows = @(ConvertTo-ThirdPartyEvidence -DnsRows $dns)
        $rows.Count | Should -BeGreaterOrEqual 2
        $rows.Vendor | Should -Contain 'Mimecast'
        $rows | Where-Object { $_.Source -eq 'SPF' } | Should -Not -BeNullOrEmpty
    }
    It 'does NOT flag the standard Microsoft MX' {
        $dns = @([pscustomobject]@{ Domain = 'contoso.com'; MX = '0 contoso-com.mail.protection.outlook.com'; SPF = 'v=spf1 include:spf.protection.outlook.com -all' })
        @(ConvertTo-ThirdPartyEvidence -DnsRows $dns).Count | Should -Be 0
    }
    It 'flags an external non-Microsoft MX as Other external MX' {
        $dns = @([pscustomobject]@{ Domain = 'contoso.com'; MX = '10 mail.example-isp.example'; SPF = '' })
        $rows = @(ConvertTo-ThirdPartyEvidence -DnsRows $dns)
        $rows[0].Vendor | Should -Be 'Other external MX'
        $rows[0].Evidence | Should -Be 'mail.example-isp.example'
    }
    It 'matches connector smart hosts' {
        $out = @([pscustomobject]@{ Name = 'Out to Proofpoint'; SmartHosts = @('smtp.ppe-hosted.com'); SenderDomains = @() })
        $rows = @(ConvertTo-ThirdPartyEvidence -OutboundConnectors $out)
        $rows[0].Vendor  | Should -Be 'Proofpoint'
        $rows[0].Source  | Should -Be 'OutboundConnector'
    }
    It 'emits nothing for clean Microsoft-only evidence' {
        $dns = @([pscustomobject]@{ Domain = 'fabrikam.com'; MX = '0 fabrikam-com.mail.protection.outlook.com'; SPF = 'v=spf1 include:spf.protection.outlook.com -all' })
        $out = @([pscustomobject]@{ Name = 'To partner'; SmartHosts = @('mx.partner.example'); SenderDomains = @() })
        @(ConvertTo-ThirdPartyEvidence -DnsRows $dns -OutboundConnectors $out).Count | Should -Be 0
    }
}

Describe 'ConvertTo-AppCredentialRows' {
    It 'emits metadata only - never secret material' {
        $app = [pscustomobject]@{
            appId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; displayName = 'Contoso App'
            passwordCredentials = @([pscustomobject]@{ displayName = 'secret'; keyId = 'kid-1'; secretText = 'SUPERSECRET'; startDateTime = '2025-01-01'; endDateTime = (Get-Date).AddDays(30).ToString('o') })
            keyCredentials = @([pscustomobject]@{ displayName = 'cert'; keyId = 'kid-2'; key = 'BASE64KEY'; usage = 'Sign'; startDateTime = '2025-01-01'; endDateTime = (Get-Date).AddDays(10).ToString('o') })
        }
        $rows = @(ConvertTo-AppCredentialRows -Owner $app -OwnerType 'Application')
        $rows.Count | Should -Be 2
        foreach ($r in $rows) {
            ($r.PSObject.Properties.Name -join ' ') | Should -Not -Match 'secretText|key[^i]|Thumbprint'
        }
        ($rows | ConvertTo-Json -Compress) | Should -Not -Match 'SUPERSECRET|BASE64KEY'
        $rows[0].DaysToExpiry | Should -BeLessOrEqual 60
    }
}

Describe 'ConvertTo-SamlCertificateRows' {
    It 'only includes saml-mode apps and Verify/Sign usages' {
        $sps = @(
            [pscustomobject]@{ appId = 'a1'; displayName = 'SAML app'; preferredSingleSignOnMode = 'saml'
                keyCredentials = @(
                    [pscustomobject]@{ usage = 'Sign'; keyId = 'k1'; displayName = 'sig'; customKeyIdentifier = 'ab'; startDateTime = '2025-01-01'; endDateTime = (Get-Date).AddDays(5).ToString('o') },
                    [pscustomobject]@{ usage = 'Verify'; keyId = 'k2'; displayName = 'ver'; customKeyIdentifier = 'cd'; startDateTime = '2025-01-01'; endDateTime = (Get-Date).AddDays(400).ToString('o') }
                ) },
            [pscustomobject]@{ appId = 'a2'; displayName = 'OIDC app'; preferredSingleSignOnMode = 'oidc'
                keyCredentials = @([pscustomobject]@{ usage = 'Sign'; keyId = 'k3'; displayName = 'x'; startDateTime = $null; endDateTime = $null }) }
        )
        $rows = @(ConvertTo-SamlCertificateRows -ServicePrincipals $sps)
        $rows.Count | Should -Be 2
        $rows.AppId | Should -Not -Contain 'a2'
        $rows.Usage | Should -Contain 'Sign'
        ($rows | Where-Object { $_.Usage -eq 'Sign' }).DaysToExpiry | Should -BeLessOrEqual 60
    }
}

Describe 'ConvertTo-InboxRuleForwarding' {
    It 'emits target domains only - never addresses or rule bodies' {
        $rules = @(
            [pscustomobject]@{ Name = 'Forward out'; Enabled = $true
                ForwardTo = @('smtp:someone' + '@external-partner.example'); RedirectTo = @('smtp:other' + '@leak.example')
                ForwardAsAttachmentTo = @(); Description = 'forward everything from boss' },
            [pscustomobject]@{ Name = 'Internal move'; Enabled = $true
                MoveToFolder = 'Archive'; ForwardTo = @(); RedirectTo = @(); ForwardAsAttachmentTo = @() }
        )
        $rows = @(ConvertTo-InboxRuleForwarding -Mailbox 'user@contoso.com' -Rules $rules)
        $rows.Count | Should -Be 1
        $rows[0].TargetDomains | Should -Match 'external-partner\.example'
        $rows[0].TargetDomains | Should -Match 'leak\.example'
        $rows[0].TargetDomains | Should -Not -Match '@'
        ($rows[0] | ConvertTo-Json -Compress) | Should -Not -Match 'forward everything from boss'
    }
}

Describe 'Invoke-Collector - phase-1 level and licence cases' {
    BeforeEach {
        $script:CollectorRecords  = [System.Collections.Generic.List[object]]::new()
        $script:CollectorWarnings = [System.Collections.Generic.List[string]]::new()
        $script:CollectorRows     = 0
        $script:AppOnly           = $false
        $script:Summary.skippedSections = @{}
        $script:Level = 'Advanced'
    }

    It 'records Skipped for a Deep collector at -Level Advanced' {
        Invoke-Collector -Name 'CalendarPermissions' -ScriptBlock { $script:CollectorRows += 5 }
        $script:CollectorRecords[0].Status | Should -Be 'Skipped'
        $script:CollectorRows | Should -Be 0
    }

    It 'records AccessDenied on a 403 and rethrows' {
        $ex = [System.Exception]::new('Forbidden')
        $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = [System.Net.HttpStatusCode]::Forbidden })
        { Invoke-Collector -Name 'HubSites' -ScriptBlock { throw $ex } } | Should -Throw
        $script:CollectorRecords[0].Status | Should -Be 'AccessDenied'
    }

    It 'records NotLicensed when the P2 gate rejects PIM' {
        $script:LicenseCaps = @{ entraP2 = $false }
        Invoke-Collector -Name 'PimAssignments' -ScriptBlock {
            if (-not (Test-LicenseGate -Capability 'entraP2' -Section 'PIM' -What 'Entra ID P2')) { return }
            $script:CollectorRows += 1
        }
        $script:CollectorRecords[0].Status | Should -Be 'NotLicensed'
        $script:CollectorRows | Should -Be 0
    }

    It 'records Success for PIM when P2 is present' {
        $script:LicenseCaps = @{ entraP2 = $true }
        Invoke-Collector -Name 'PimAssignments' -ScriptBlock {
            if (-not (Test-LicenseGate -Capability 'entraP2' -Section 'PIM' -What 'Entra ID P2')) { return }
            $script:CollectorRows += 1
        }
        $script:CollectorRecords[0].Status | Should -Be 'Success'
    }
}
