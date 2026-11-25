BeforeAll {
    $script:Collector = Join-Path $PSScriptRoot '..\00-Assessment\Collect-TenantInventory.ps1'

    # AST-load only the function definitions we need - the main body never runs.
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Collector, [ref]$null, [ref]$null)
    $names = @('Get-SiteType','ConvertTo-ThirdPartyEvidence','ConvertTo-AppCredentialRows',
               'ConvertTo-SamlCertificateRows','ConvertTo-InboxRuleForwarding','Get-DaysToExpiry',
               'Get-UpnDomain','Invoke-Collector','Get-CollectorRegistryEntry','Test-CollectorLevel',
               'Test-GraphForbidden','Test-LicenseGate','Merge-CollectorRecords',
               'Resolve-TeamsTenantId','Get-DuplicateDisplayNames','Test-ExoCmdlet',
               'Get-ModuleLoadHint','Test-PathUnderOneDrive')
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
        $script:CollectorStatusOverride = $null
        $script:CollectorErrorOverride  = $null
        $script:CollectorDepth = 0
        $script:CollectorNestedThrew = $false
        $script:CollectorNestedWarnRanges = [System.Collections.Generic.List[object]]::new()
        $script:CollectorNestedSkips = @{}
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

Describe 'Merge-CollectorRecords' {
    It 'merges child CSVs from attachments plus legacy root files and own records' {
        $inv = Join-Path $TestDrive 'inv'
        $att = Join-Path $inv 'attachments'
        $null = New-Item -ItemType Directory -Path $att -Force
        $hdr = 'TenantId,TenantName,CollectedAt,Collector,CollectorVersion,Endpoint,Cmdlet,ApiVersion,ObjectCount,DurationSeconds,Status,Completeness,Errors,Warnings,KnownLimitations'
        @($hdr,
          't,Contoso,2026-11-25T12:00:00,Graph,1.0,,,v1.0,5,1,Success,Complete,,,',
          't,Contoso,2026-11-25T12:00:01,Shared,1.0,,,v1.0,1,1,Success,Complete,,,') |
            Set-Content (Join-Path $att 'Collectors.Graph.csv') -Encoding UTF8
        @($hdr,
          't,Contoso,2026-11-25T12:00:00,Exchange,1.0,,Get-X,PowerShell,3,1,Success,Complete,,,',
          't,Contoso,2026-11-25T12:00:02,Shared,1.0,,,v1.0,9,1,PartialSuccess,Partial,,,') |
            Set-Content (Join-Path $att 'Collectors.Exchange.csv') -Encoding UTF8
        # Old location (inventory root) from a resume run - still merged.
        @($hdr, 't,Contoso,2026-11-25T11:00:00,Legacy,1.0,,,v1.0,2,1,Success,Complete,,,') |
            Set-Content (Join-Path $inv 'Collectors.Old.csv') -Encoding UTF8
        $own = @([pscustomobject]@{ Collector = 'ParentOnly'; CollectedAt = '2026-11-25T12:00:00' })
        $rows = @(Merge-CollectorRecords -AttachDir $att -LegacyDir $inv -OwnRecords $own)
        $rows.Collector | Sort-Object | Should -Be @('Exchange','Graph','Legacy','ParentOnly','Shared')
        # Latest record per collector wins (Shared: Exchange file has the newer CollectedAt)
        ($rows | Where-Object Collector -eq 'Shared').Status | Should -Be 'PartialSuccess'
        ($rows | Where-Object Collector -eq 'Shared').ObjectCount | Should -Be '9'
    }
}

Describe 'Resolve-TeamsTenantId' {
    It 'prefers the Connect-MicrosoftTeams result TenantId' {
        Resolve-TeamsTenantId -ConnectResult ([pscustomobject]@{ TenantId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' }) -GetCsTenant { throw 'nope' } |
            Should -Be 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    }
    It 'falls back to Get-CsTenant' {
        Resolve-TeamsTenantId -ConnectResult $null -GetCsTenant { [pscustomobject]@{ TenantId = '00000000-0000-0000-0000-000000000000' } } |
            Should -Be '00000000-0000-0000-0000-000000000000'
    }
    It 'returns $null when neither source has an id' {
        Resolve-TeamsTenantId -ConnectResult $null -GetCsTenant { throw 'Access denied' } | Should -BeNullOrEmpty
    }
}

Describe 'Get-DuplicateDisplayNames' {
    It 'returns only names used more than once' {
        Get-DuplicateDisplayNames -DisplayNames @('IT-avdelningen','Sales','IT-avdelningen','HR','Sales') |
            Sort-Object | Should -Be @('IT-avdelningen','Sales')
        Get-DuplicateDisplayNames -DisplayNames @('A','B') | Should -BeNullOrEmpty
    }
}

Describe 'Test-ExoCmdlet' {
    BeforeEach {
        $script:CollectorStatusOverride = $null
        $script:CollectorErrorOverride  = $null
        $script:CollectorDepth = 0
        $script:CollectorNestedThrew = $false
        $script:CollectorNestedWarnRanges = [System.Collections.Generic.List[object]]::new()
        $script:CollectorNestedSkips = @{}
        $script:Summary.skippedSections = @{}
    }
    It 'returns $true when the cmdlet exists' {
        Mock Get-Command { $true }
        Test-ExoCmdlet -Name 'Get-Whatever' | Should -BeTrue
    }
    It 'records AccessDenied + role hint when the cmdlet is absent' {
        Mock Get-Command { $null }
        Test-ExoCmdlet -Name 'Get-AddressList' -RoleHint 'Address Lists role not assigned' | Should -BeFalse
        $script:CollectorStatusOverride | Should -Be 'AccessDenied'
        $script:Summary.skippedSections['Cmdlet:Get-AddressList'] | Should -Match 'Address Lists role not assigned'
    }
    It 'produces an AccessDenied collector record through Invoke-Collector' {
        Mock Get-Command { $null }
        $script:CollectorRecords = [System.Collections.Generic.List[object]]::new()
        $script:CollectorWarnings = [System.Collections.Generic.List[string]]::new()
        $script:CollectorRows = 0; $script:Level = 'Deep'; $script:AppOnly = $false
        Invoke-Collector -Name 'AddressLists' -ScriptBlock {
            if (-not (Test-ExoCmdlet -Name 'Get-AddressList')) { return }
            $script:CollectorRows += 1
        }
        $script:CollectorRecords[0].Status | Should -Be 'AccessDenied'
    }
}

Describe 'Invoke-Collector - aggregated-failure and not-found classification' {
    BeforeEach {
        $script:CollectorRecords  = [System.Collections.Generic.List[object]]::new()
        $script:CollectorWarnings = [System.Collections.Generic.List[string]]::new()
        $script:CollectorRows     = 0
        $script:CollectorStatusOverride = $null
        $script:CollectorErrorOverride  = $null
        $script:CollectorDepth = 0
        $script:CollectorNestedThrew = $false
        $script:CollectorNestedWarnRanges = [System.Collections.Generic.List[object]]::new()
        $script:CollectorNestedSkips = @{}
        $script:AppOnly           = $false
        $script:Summary.skippedSections = @{}
        $script:Level = 'Deep'
    }

    It 'records AccessDenied when every per-object call was denied (override)' {
        Invoke-Collector -Name 'SiteAdmins' -ScriptBlock {
            $script:CollectorStatusOverride = 'AccessDenied'
            $script:Summary.skippedSections['SiteAdmins'] = 'denied on all sites'
        }
        $script:CollectorRecords[0].Status | Should -Be 'AccessDenied'
    }

    It 'records DiscoveryFailed with the error text via the override pair' {
        Invoke-Collector -Name 'AutopilotDevices' -ScriptBlock {
            $script:CollectorStatusOverride = 'DiscoveryFailed'
            $script:CollectorErrorOverride  = 'InternalServerError'
        }
        $script:CollectorRecords[0].Status | Should -Be 'DiscoveryFailed'
        $script:CollectorRecords[0].Errors | Should -Be 'InternalServerError'
    }

    It 'records NotInUse for the ApplicationAccessPolicy "could not be found" pattern' {
        Invoke-Collector -Name 'ApplicationAccessPolicies' -ScriptBlock {
            try { throw "The cmdlet couldn't be found on 'contoso.onmicrosoft.com\*'." } catch {
                if ("$($_.Exception.Message)" -notmatch "couldn't be found|ManagementObjectNotFound") {
                    $script:CollectorWarnings.Add('[WARN] real failure')
                }
            }
        }
        $script:CollectorRecords[0].Status | Should -Be 'NotInUse'
    }
}

Describe 'Invoke-Collector - No-data warnings and nested attribution' {
    BeforeEach {
        $script:CollectorRecords  = [System.Collections.Generic.List[object]]::new()
        $script:CollectorWarnings = [System.Collections.Generic.List[string]]::new()
        $script:CollectorRows     = 0
        $script:CollectorStatusOverride = $null
        $script:CollectorErrorOverride  = $null
        $script:CollectorDepth = 0
        $script:CollectorNestedThrew = $false
        $script:CollectorNestedWarnRanges = [System.Collections.Generic.List[object]]::new()
        $script:CollectorNestedSkips = @{}
        $script:AppOnly           = $false
        $script:Summary.skippedSections = @{}
        $script:Level = 'Deep'
    }

    It 'records NotInUse when the only warning is "No data for X.csv"' {
        Invoke-Collector -Name 'HubSites' -ScriptBlock {
            $script:CollectorWarnings.Add('[WARN] No data for HubSites.csv')
        }
        $script:CollectorRecords[0].Status | Should -Be 'NotInUse'
    }

    It 'outer section does not inherit a nested licence-gated outcome' {
        Invoke-Collector -Name 'Tenant' -ScriptBlock {
            Invoke-Collector -Name 'PimAssignments' -ScriptBlock {
                $script:Summary.skippedSections['PIM'] = 'Not collected: no license for Entra ID P2'
            }
            $script:CollectorRows += 3
        }
        ($script:CollectorRecords | Where-Object Collector -eq 'PimAssignments').Status | Should -Be 'NotLicensed'
        ($script:CollectorRecords | Where-Object Collector -eq 'Tenant').Status | Should -Be 'Success'
    }

    It 'nested throw that the outer catches -> outer PartialSuccess' {
        Invoke-Collector -Name 'Tenant' -ScriptBlock {
            try { Invoke-Collector -Name 'HubSites' -ScriptBlock { throw 'Graph broke' } } catch {}
            $script:CollectorRows += 3
        }
        ($script:CollectorRecords | Where-Object Collector -eq 'HubSites').Status | Should -Be 'DiscoveryFailed'
        ($script:CollectorRecords | Where-Object Collector -eq 'Tenant').Status | Should -Be 'PartialSuccess'
    }

    It 'nested warnings do not propagate to the outer status' {
        Invoke-Collector -Name 'Tenant' -ScriptBlock {
            Invoke-Collector -Name 'SiteAdmins' -ScriptBlock {
                $script:CollectorWarnings.Add('[WARN] Site admins: 3 of 5 sites denied')
                $script:CollectorRows += 2
            }
            $script:CollectorRows += 1
        }
        ($script:CollectorRecords | Where-Object Collector -eq 'SiteAdmins').Status | Should -Be 'PartialSuccess'
        ($script:CollectorRecords | Where-Object Collector -eq 'Tenant').Status | Should -Be 'Success'
    }
}

Describe 'Get-ModuleLoadHint' {
    It 'returns the OneDrive hint for cloud-file-provider errors' {
        Get-ModuleLoadHint -Message 'Could not load file or assembly. The cloud file provider is not running. (0x8007016A)' |
            Should -Match 'Always keep on this device'
        Get-ModuleLoadHint -Message 'error 0x8007016A' | Should -Not -BeNullOrEmpty
    }
    It 'returns $null for ordinary errors' {
        Get-ModuleLoadHint -Message 'Access is denied' | Should -BeNullOrEmpty
        Get-ModuleLoadHint -Message '' | Should -BeNullOrEmpty
    }
}

Describe 'Test-PathUnderOneDrive (Test-ModuleHealth helper)' {
    BeforeAll {
        $tool = Join-Path $PSScriptRoot '..\tools\Test-ModuleHealth.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($tool, [ref]$null, [ref]$null)
        $def = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
            Where-Object { $_.Name -eq 'Test-PathUnderOneDrive' }
        . ([ScriptBlock]::Create($def.Extent.Text))
    }
    It 'detects paths under a OneDrive root' {
        $roots = @('C:\Users\me\OneDrive - Contoso')
        Test-PathUnderOneDrive -Path 'C:\Users\me\OneDrive - Contoso\Documents\PowerShell\Modules\MicrosoftTeams' -OneDriveRoots $roots |
            Should -BeTrue
    }
    It 'rejects paths outside all roots' {
        $roots = @('C:\Users\me\OneDrive - Contoso')
        Test-PathUnderOneDrive -Path 'C:\Program Files\PowerShell\Modules\MicrosoftTeams' -OneDriveRoots $roots |
            Should -BeFalse
        Test-PathUnderOneDrive -Path 'C:\Users\me\OneDriveish\Modules' -OneDriveRoots $roots | Should -BeFalse
    }
}
