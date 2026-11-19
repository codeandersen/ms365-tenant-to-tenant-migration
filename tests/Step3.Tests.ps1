BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force
    $script:Tid = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'
}

Describe 'Get-SiteMigrationPlan.ps1 (fixture)' {
    BeforeAll {
        $script:inv = Join-Path $TestDrive 'inv'
        New-Item -ItemType Directory -Path $inv -Force | Out-Null
        @(
            [pscustomobject]@{ Url = 'https://contoso.sharepoint.com/sites/sales'; Title = 'Sales'; Template = 'STS#3'; StorageUsageGB = '12.5'; LastContentModifiedDate = '2026-01-01'; LockState = 'Unlock'; GroupId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; IsTeamsConnected = 'True'; IsTeamsChannelConnected = ''; Status = ''; FileCount = '100'; Source = 'SPO' }
            [pscustomobject]@{ Url = 'https://contoso.sharepoint.com/sites/plain'; Title = 'Plain'; Template = 'STS#0'; StorageUsageGB = '1'; LastContentModifiedDate = '2026-01-01'; LockState = 'Unlock'; GroupId = ''; IsTeamsConnected = ''; IsTeamsChannelConnected = ''; Status = ''; FileCount = '10'; Source = 'SPO' }
            [pscustomobject]@{ Url = 'https://contoso.sharepoint.com/sites/huge'; Title = 'Huge'; Template = 'STS#3'; StorageUsageGB = '6000'; LastContentModifiedDate = '2026-01-01'; LockState = 'Unlock'; GroupId = ''; IsTeamsConnected = ''; IsTeamsChannelConnected = ''; Status = ''; FileCount = '10'; Source = 'SPO' }
            [pscustomobject]@{ Url = 'https://contoso.sharepoint.com/sites/privatechan'; Title = 'Priv'; Template = 'TEAMCHANNEL#0'; StorageUsageGB = '2'; LastContentModifiedDate = '2026-01-01'; LockState = 'Unlock'; GroupId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; IsTeamsConnected = 'True'; IsTeamsChannelConnected = 'True'; Status = ''; FileCount = '5'; Source = 'SPO' }
            [pscustomobject]@{ Url = 'https://contoso-my.sharepoint.com/personal/u1_contoso_com'; Title = 'OD'; Template = 'SPSPERS#10'; StorageUsageGB = '1'; LastContentModifiedDate = ''; LockState = ''; GroupId = ''; IsTeamsConnected = ''; IsTeamsChannelConnected = ''; Status = ''; FileCount = ''; Source = 'SPO' }
        ) | Export-Csv (Join-Path $inv 'SharePointSites.csv') -NoTypeInformation
        & (Join-Path $PSScriptRoot '..\07-SharePoint-Teams\Get-SiteMigrationPlan.ps1') -InventoryPath $inv -TargetHost fabrikam -Customer testcust | Out-Null
        $script:planFile = Get-ChildItem (Join-Path $PSScriptRoot '..\customers\testcust') -Recurse -Filter SiteMigrationPlan.csv |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $script:plan = @(Import-Csv $script:planFile.FullName)
    }
    It 'produces one row per site' { $plan.Count | Should -Be 5 }
    It 'flags the group-connected site Native with a pre-filled target URL' {
        $row = $plan | Where-Object Url -match 'sales'
        $row.Track | Should -Be 'Native'
        $row.GroupConnected | Should -Be 'True'
        $row.TargetUrl | Should -Be 'https://fabrikam.sharepoint.com/sites/sales'
    }
    It 'flags the channel site as non-native' {
        ($plan | Where-Object Url -match 'privatechan').Track | Should -Be 'ShareGate'
    }
    It 'flags the >5TB site as ShareGate' {
        ($plan | Where-Object Url -match 'huge').Track | Should -Be 'ShareGate'
    }
    It 'routes personal sites to the OneDrive track' {
        ($plan | Where-Object Url -match '-my.sharepoint').Track | Should -Be 'OneDrive'
    }
}

Describe 'Resolve-PermissionTrustee' {
    It 'maps through the table case-insensitively' {
        Resolve-PermissionTrustee -Trustee 'Anne@Contoso.com' -Mapping @{ 'anne@contoso.com' = 'anne@fabrikam.onmicrosoft.com' } |
            Should -Be 'anne@fabrikam.onmicrosoft.com'
    }
    It 'returns null for an unmapped trustee (never guesses)' {
        Resolve-PermissionTrustee -Trustee 'ghost@contoso.com' -Mapping @{} | Should -BeNullOrEmpty
    }
    It 'passes unresolved/external markers through' {
        Resolve-PermissionTrustee -Trustee 'unresolved:abc123' -Mapping @{} | Should -Be 'unresolved:abc123'
    }
    It 'passes Default/Anonymous through' {
        Resolve-PermissionTrustee -Trustee 'Default' -Mapping @{} | Should -Be 'Default'
    }
}

Describe 'ConvertFrom-InPlaceHold' {
    It 'decodes the documented prefixes' {
        $r = ConvertFrom-InPlaceHold -InPlaceHolds 'UniHaaaabbbb', 'mbxcccc', 'skp1', 'grp2'
        $r[0].Prefix | Should -Be 'UniH'; $r[0].Source | Should -Match 'retention'
        $r[1].Prefix | Should -Be 'mbx'
        $r[2].Prefix | Should -Be 'skp'
        $r[3].Prefix | Should -Be 'grp'
    }
    It 'reports unknown prefixes instead of guessing' {
        (ConvertFrom-InPlaceHold -InPlaceHolds 'zzz123').Prefix | Should -Be ''
    }
    It 'handles empty input' {
        @(ConvertFrom-InPlaceHold -InPlaceHolds @()).Count | Should -Be 0
    }
}

Describe 'New-CrossTenantMailboxBatch.ps1 hold refusal' {
    BeforeAll {
        function global:Connect-MigrationExchange { param($TenantId, $AdminUpn) [pscustomobject]@{ TenantID = $TenantId; UserPrincipalName = $AdminUpn } }
        function global:New-MigrationBatch { param($Name, $SourceEndpoint, $CSVData, $TargetDeliveryDomain, $AutoStart, $CompleteAfter, $ErrorAction) }
        Mock Connect-MigrationExchange { [pscustomobject]@{ TenantID = $TenantId; UserPrincipalName = $AdminUpn } }
        Mock New-MigrationBatch { $global:BatchCalls++ }
        Mock New-OutputFolder { $TestDrive }

        @(
            [pscustomobject]@{ PrimarySmtpAddress = 'shared1@contoso.com'; DisplayName = 'S1'; Alias = 's1'; RecipientTypeDetails = 'SharedMailbox'; ExchangeGuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; ArchiveGuid = ''; ArchiveStatus = 'None'; LegacyExchangeDN = '/o=ex'; X500Addresses = ''; MailboxSizeGB = '1'; LitigationHoldEnabled = 'True'; RetentionHoldEnabled = 'False'; ComplianceTagHoldApplied = 'False'; DelayHoldApplied = 'False'; DelayReleaseHoldApplied = 'False'; InPlaceHolds = '' }
            [pscustomobject]@{ PrimarySmtpAddress = 'shared2@contoso.com'; DisplayName = 'S2'; Alias = 's2'; RecipientTypeDetails = 'SharedMailbox'; ExchangeGuid = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'; ArchiveGuid = ''; ArchiveStatus = 'None'; LegacyExchangeDN = '/o=ex'; X500Addresses = ''; MailboxSizeGB = '1'; LitigationHoldEnabled = 'False'; RetentionHoldEnabled = 'False'; ComplianceTagHoldApplied = 'False'; DelayHoldApplied = 'False'; DelayReleaseHoldApplied = 'False'; InPlaceHolds = '' }
        ) | Export-Csv (Join-Path $TestDrive 'attrs.csv') -NoTypeInformation
        @(
            [pscustomobject]@{ SourcePrimarySmtp = 'shared1@contoso.com'; TargetPrimarySmtp = 'shared1@fabrikam.onmicrosoft.com'; Name = 'S1' }
            [pscustomobject]@{ SourcePrimarySmtp = 'shared2@contoso.com'; TargetPrimarySmtp = 'shared2@fabrikam.onmicrosoft.com'; Name = 'S2' }
        ) | Export-Csv (Join-Path $TestDrive 'map.csv') -NoTypeInformation
        $global:BatchCalls = 0
        & (Join-Path $PSScriptRoot '..\06-SharedMailboxes-Holds\New-CrossTenantMailboxBatch.ps1') -TenantId $script:Tid -AdminUpn 'admin@fabrikam.com' `
            -Name b1 -SourceEndpoint ep -TargetDeliveryDomain fabrikam.onmicrosoft.com `
            -SourceAttributesCsv (Join-Path $TestDrive 'attrs.csv') -MappingCsv (Join-Path $TestDrive 'map.csv') -Customer testcust
    }
    It 'batches only the unheld mailbox' {
        $global:BatchCalls | Should -Be 1
        $refused = Import-Csv (Join-Path $TestDrive 'BatchRefused.csv')
        $refused[0].Target | Should -Be 'shared1@fabrikam.onmicrosoft.com'
        $refused[0].Reason | Should -Match 'hold'
    }
}

Describe 'Set-TargetUpn.ps1 guards' {
    BeforeAll {
        function global:Get-MgUser { param($UserId, $Property, $ErrorAction) }
        function global:Get-MgDomain { param([switch]$All) }
        function global:Get-MgBetaCrossTenantMigrationJob { param([switch]$All, $ErrorAction) }
        function global:Get-MgBetaCrossTenantMigrationJobUser { param($CrossTenantMigrationJobId, $CrossTenantMigrationTaskId, [switch]$All, $ErrorAction) }
        function global:Update-MgUser { param($UserId, $UserPrincipalName, $AccountEnabled, $ErrorAction) }
        function global:Connect-MigrationGraph { param($TenantId, $AdminUpn, $Scopes) [pscustomobject]@{ TenantId = $TenantId; Account = $AdminUpn } }
        function global:Connect-MigrationExchange { param($TenantId, $AdminUpn) [pscustomobject]@{ TenantID = $TenantId; UserPrincipalName = $AdminUpn } }

        $script:csv = Join-Path $TestDrive 'users.csv'
        @([pscustomobject]@{
            SourceUpn = 'u1@contoso.com'; SourcePrimarySmtp = 'u1@contoso.com'; DisplayName = 'U One'
            FirstName = 'U'; LastName = 'One'; TargetUpn = 'u1@fabrikam.onmicrosoft.com'; TargetPrimarySmtp = 'u1@fabrikam.onmicrosoft.com'
            UsageLocation = 'DK'; TargetLicenseSku = 'SPE_E5'; Batch = 'wave1'
            CompleteAfterDateTimeUtc = '2026-09-05T22:00:00Z'; Workloads = 'Exchange'
            FinalUpn = 'u1@fabrikam.com'; FinalPrimarySmtp = ''
        }) | Export-Csv $script:csv -NoTypeInformation

        Mock Connect-MigrationGraph { [pscustomobject]@{ TenantId = $TenantId; Account = $AdminUpn } }
        Mock Connect-MigrationExchange { [pscustomobject]@{ TenantID = $TenantId; UserPrincipalName = $AdminUpn } }
        Mock New-OutputFolder { $TestDrive }
        Mock Get-MgDomain { [pscustomobject]@{ Id = 'fabrikam.com'; VerificationState = 'Verified' } }
        Mock Update-MgUser { $global:UpdateCalls++ }
    }
    BeforeEach { $global:UpdateCalls = 0 }

    It 'refuses a user whose batch is not Completed' {
        Mock Get-MgUser { [pscustomobject]@{ Id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; UserPrincipalName = 'u1@fabrikam.onmicrosoft.com' } }
        Mock Get-MgBetaCrossTenantMigrationJob { [pscustomobject]@{ Id = 'job1'; DisplayName = 'wave1'; Status = 'InProgress' } }
        Mock Get-MgBetaCrossTenantMigrationJobUser { [pscustomobject]@{ Id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; Status = 'InProgress' } }
        & (Join-Path $PSScriptRoot '..\09-DomainCutover\Set-TargetUpn.ps1') -TenantId $script:Tid -AdminUpn 'admin@fabrikam.com' -UserListPath $script:csv -Customer testcust
        $global:UpdateCalls | Should -Be 0
        $report = Get-ChildItem $TestDrive -Filter 'SetTargetUpn-*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        (Import-Csv $report.FullName | Where-Object Object -eq 'u1@fabrikam.onmicrosoft.com').Status | Should -Be 'Refused'
    }
    It 'aborts before changing anything when the backup fails' {
        Mock Get-MgUser { [pscustomobject]@{ Id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; UserPrincipalName = 'u1@fabrikam.onmicrosoft.com' } }
        Mock Export-CsvSafe -ParameterFilter { $Path -match 'Backup' } { throw 'disk full' }
        { & (Join-Path $PSScriptRoot '..\09-DomainCutover\Set-TargetUpn.ps1') -TenantId $script:Tid -AdminUpn 'admin@fabrikam.com' -UserListPath $script:csv -Customer testcust } | Should -Throw '*backup*'
        $global:UpdateCalls | Should -Be 0
    }
    It 'changes the UPN when the batch is Completed' {
        Mock Get-MgUser { [pscustomobject]@{ Id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; UserPrincipalName = 'u1@fabrikam.onmicrosoft.com' } }
        Mock Get-MgBetaCrossTenantMigrationJob { [pscustomobject]@{ Id = 'job1'; DisplayName = 'wave1'; Status = 'Completed' } }
        Mock Get-MgBetaCrossTenantMigrationJobUser { [pscustomobject]@{ Id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; Status = 'Completed' } }
        & (Join-Path $PSScriptRoot '..\09-DomainCutover\Set-TargetUpn.ps1') -TenantId $script:Tid -AdminUpn 'admin@fabrikam.com' -UserListPath $script:csv -Customer testcust
        $global:UpdateCalls | Should -Be 1
    }
}

Describe 'Remove-SourceDomain backup-before-change' {
    It 'writes the recipient snapshot before any changes (static check)' {
        $text = Get-Content (Join-Path $PSScriptRoot '..\09-DomainCutover\Remove-SourceDomain.ps1') -Raw
        ($text.IndexOf('Export-CsvSafe -Path $snapFile')) -gt 0 | Should -BeTrue
        ($text.IndexOf('Export-CsvSafe -Path $snapFile')) -lt ($text.IndexOf('Update-MgUser -UserId')) | Should -BeTrue
        ($text.IndexOf('SourceUsers-')) -gt 0 | Should -BeTrue
    }
}

Describe 'Export-CsvSafe -Header' {
    It 'writes a header-only file with BOM when input is empty' {
        $f = Join-Path $TestDrive 'empty.csv'
        @() | Export-CsvSafe -Path $f -Header 'Mailbox','Folder','AccessRights'
        $bytes = [System.IO.File]::ReadAllBytes($f)
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        (Get-Content $f -First 1) | Should -Be 'Mailbox,Folder,AccessRights'
        @(Get-Content $f).Count | Should -Be 1
    }
    It 'ignores -Header when there is input' {
        $f = Join-Path $TestDrive 'rows.csv'
        [pscustomobject]@{ A = 'æøå'; B = '1' } | Export-CsvSafe -Path $f -Header 'X','Y','Z'
        (Get-Content $f)[0] | Should -Be '"A","B"'
    }
}

Describe 'Set-TargetUpn.ps1 empty-status refusal' {
    BeforeAll {
        $script:csv2 = Join-Path $TestDrive 'users2.csv'
        @([pscustomobject]@{
            SourceUpn = 'u1@contoso.com'; SourcePrimarySmtp = 'u1@contoso.com'; DisplayName = 'U One'
            FirstName = 'U'; LastName = 'One'; TargetUpn = 'u1@fabrikam.onmicrosoft.com'; TargetPrimarySmtp = 'u1@fabrikam.onmicrosoft.com'
            UsageLocation = 'DK'; TargetLicenseSku = 'SPE_E5'; Batch = 'wave1'
            CompleteAfterDateTimeUtc = '2026-09-05T22:00:00Z'; Workloads = 'Exchange'
            FinalUpn = 'u1@fabrikam.com'; FinalPrimarySmtp = ''
        }) | Export-Csv $script:csv2 -NoTypeInformation
        Mock Connect-MigrationGraph { [pscustomobject]@{ TenantId = $TenantId; Account = $AdminUpn } }
        Mock Connect-MigrationExchange { [pscustomobject]@{ TenantID = $TenantId; UserPrincipalName = $AdminUpn } }
        Mock New-OutputFolder { $TestDrive }
        Mock Get-MgDomain { [pscustomobject]@{ Id = 'fabrikam.com'; VerificationState = 'Verified' } }
        Mock Get-MgUser { [pscustomobject]@{ Id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; UserPrincipalName = 'u1@fabrikam.onmicrosoft.com' } }
        Mock Get-MgBetaCrossTenantMigrationJob { [pscustomobject]@{ Id = 'job1'; DisplayName = 'wave1'; Status = 'Completed' } }
        Mock Get-MgBetaCrossTenantMigrationJobUser { $null }
        $global:UpdateCalls = 0
        & (Join-Path $PSScriptRoot '..\09-DomainCutover\Set-TargetUpn.ps1') -TenantId $script:Tid -AdminUpn 'admin@fabrikam.com' -UserListPath $script:csv2 -Customer testcust
    }
    It 'refuses when the job has no status rows for the user' {
        $global:UpdateCalls | Should -Be 0
    }
    It 'proceeds under -Force and logs Warn (not Refused)' {
        Mock Update-MgUser { $global:UpdateCalls++ }
        & (Join-Path $PSScriptRoot '..\09-DomainCutover\Set-TargetUpn.ps1') -TenantId $script:Tid -AdminUpn 'admin@fabrikam.com' -UserListPath $script:csv2 -Customer testcust -Force
        $global:UpdateCalls | Should -Be 1
        $report = Get-ChildItem $TestDrive -Filter 'SetTargetUpn-*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        (Import-Csv $report.FullName | Where-Object Status -eq 'Warn').Count | Should -BeGreaterThan 0
    }
}

Describe 'Switch-TargetAddresses guest backup before delete' {
    BeforeAll {
        function global:Get-Recipient { param($Identity, $Filter, $ResultSize, $Properties, $ErrorAction) }
        function global:Get-EXORecipient { param($Identity, $Properties, $ErrorAction) }
        function global:Get-AcceptedDomain { param() }
        function global:Get-MgUser { param($UserId, $Property, $Filter, $ErrorAction) }
        function global:Get-MgUserMemberOf { param($UserId, [switch]$All, $ErrorAction) }
        function global:Remove-MgUser { param($UserId) }
        function global:Connect-MigrationExchange { param($TenantId, $AdminUpn) [pscustomobject]@{ TenantID = $TenantId; UserPrincipalName = $AdminUpn } }

        $script:snap = Join-Path $TestDrive 'snap.csv'
        @([pscustomobject]@{
            PrimarySmtpAddress = 'old@contoso.com'; RecipientTypeDetails = 'UserMailbox'; DisplayName = 'Old'
            Alias = 'old'; LegacyExchangeDN = '/o=ex'; EmailAddresses = 'smtp:old@contoso.com'; ObjectId = 'x'; SnapshotStage = 'BeforeRelease'
        }) | Export-Csv $script:snap -NoTypeInformation
        $script:map = Join-Path $TestDrive 'map.csv'
        @([pscustomobject]@{ Source = 'old@contoso.com'; Destination = 'user@fabrikam.onmicrosoft.com' }) | Export-Csv $script:map -NoTypeInformation

        Mock Connect-MigrationExchange { [pscustomobject]@{ TenantID = $TenantId; UserPrincipalName = $AdminUpn } }
        Mock Connect-MigrationGraph { [pscustomobject]@{ TenantId = $TenantId; Account = $AdminUpn } }
        Mock New-OutputFolder { $TestDrive }
        Mock Get-AcceptedDomain { [pscustomobject]@{ DomainName = 'contoso.com' } }
        Mock Get-Recipient {
            if ($Filter) { return }
            [pscustomobject]@{ PrimarySmtpAddress = 'user@fabrikam.onmicrosoft.com'; RecipientTypeDetails = 'UserMailbox'; ExternalDirectoryObjectId = 'dest-id-1'; EmailAddresses = @('smtp:user@fabrikam.onmicrosoft.com'); Guid = 'g1'; DisplayName = 'U'; Identity = 'u' }
        }
        Mock Get-EXORecipient {
            if ($Identity -eq 'user@fabrikam.onmicrosoft.com') {
                [pscustomobject]@{ PrimarySmtpAddress = 'user@fabrikam.onmicrosoft.com'; RecipientTypeDetails = 'UserMailbox'; ExternalDirectoryObjectId = 'dest-id-1'; EmailAddresses = @('smtp:user@fabrikam.onmicrosoft.com'); Guid = 'g1'; DisplayName = 'U'; Identity = 'u' }
            }
            else {
                [pscustomobject]@{ PrimarySmtpAddress = 'guest@fabrikam.onmicrosoft.com'; RecipientTypeDetails = 'GuestMailUser'; ExternalDirectoryObjectId = 'guest-id-1'; Guid = 'g2'; DisplayName = 'G'; Identity = 'g' }
            }
        }
        Mock Get-MgUser { [pscustomobject]@{ Id = 'guest-id-1'; UserPrincipalName = 'guest#EXT#@fabrikam.onmicrosoft.com'; Mail = 'old@contoso.com'; DisplayName = 'G'; CreatedDateTime = '2026-01-01' } }
        Mock Get-MgUserMemberOf { $null }
        Mock Remove-MgUser { $global:RemoveCalls++ }
        Mock Export-CsvSafe -ParameterFilter { $Path -match 'GuestBackup' } { throw 'disk full' }
        Mock Get-EXORecipient -ParameterFilter { $Identity -eq 'old@contoso.com' } {
            [pscustomobject]@{ RecipientTypeDetails = 'GuestMailUser'; ExternalDirectoryObjectId = 'guest-id-1'; Guid = 'g2'; DisplayName = 'G' }
        }
        $global:RemoveCalls = 0
    }
    It 'aborts before Remove-MgUser when the guest backup fails' {
        { & (Join-Path $PSScriptRoot '..\09-DomainCutover\Switch-TargetAddresses.ps1') -TenantId $script:Tid -AdminUpn 'admin@fabrikam.com' `
            -MappingFile $script:map -SourceSnapshot $script:snap -Domain contoso.com -Customer testcust -RemoveConflictingGuests } | Should -Throw '*Guest backup*'
        $global:RemoveCalls | Should -Be 0
    }
}
