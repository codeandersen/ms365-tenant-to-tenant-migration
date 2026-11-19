BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force
}

Describe 'Test-MigratedUserState' {
    It 'passes a fully migrated user' {
        (Test-MigratedUserState -RecipientType UserMailbox -LicensedExchange $true -LicensedTeams $true `
            -OneDriveFound $true -WorkloadStatuses 'Completed', 'CompletedWithErrors').Pass | Should -BeTrue
    }
    It 'fails when the recipient is not a mailbox' {
        $r = Test-MigratedUserState -RecipientType MailUser -LicensedExchange $true -LicensedTeams $true -OneDriveFound $true -WorkloadStatuses 'Completed'
        $r.Pass | Should -BeFalse
        $r.Problems[0] | Should -Match 'mailbox'
    }
    It 'notes shared mailboxes as the 06 path' {
        (Test-MigratedUserState -RecipientType SharedMailbox -LicensedExchange $true -LicensedTeams $true -OneDriveFound $true -WorkloadStatuses 'Completed').Problems |
            Should -Match 'phase 06'
    }
    It 'fails on a missing licence' {
        (Test-MigratedUserState -RecipientType UserMailbox -LicensedExchange $false -LicensedTeams $true -OneDriveFound $true -WorkloadStatuses 'Completed').Pass | Should -BeFalse
    }
    It 'fails on a missing OneDrive' {
        (Test-MigratedUserState -RecipientType UserMailbox -LicensedExchange $true -LicensedTeams $true -OneDriveFound $false -WorkloadStatuses 'Completed').Pass | Should -BeFalse
    }
    It 'fails on a non-terminal workload status' {
        (Test-MigratedUserState -RecipientType UserMailbox -LicensedExchange $true -LicensedTeams $true -OneDriveFound $true -WorkloadStatuses 'Completed', 'InProgress').Pass | Should -BeFalse
    }
    It 'fails when no workload status rows were returned' {
        (Test-MigratedUserState -RecipientType UserMailbox -LicensedExchange $true -LicensedTeams $true -OneDriveFound $true -WorkloadStatuses @()).Pass | Should -BeFalse
    }
    It 'fails on a bad Teams chat status' {
        (Test-MigratedUserState -RecipientType UserMailbox -LicensedExchange $true -LicensedTeams $true -OneDriveFound $true -WorkloadStatuses 'Completed' -TeamsChatStatus 'Failed').Pass | Should -BeFalse
    }
}

Describe 'Get-OldDeviceRetirementPlan (fixture)' {
    BeforeAll {
        $inv = Join-Path $TestDrive 'inv.csv'
        @(
            [pscustomobject]@{ DisplayName = 'PC-1'; DeviceId = 'dev1'; JoinType = 'Entra joined'; TrustType = 'AzureAd'; OS = 'Windows'; RegisteredUsers = 'u1@contoso.com'; Owner = 'u1@contoso.com'; LastSignIn = '2026-09-01'; IntuneManaged = 'True'; Action = 'New PC: retire this one after wipe' }
            [pscustomobject]@{ DisplayName = 'PHONE-1'; DeviceId = 'dev2'; JoinType = 'Registered'; TrustType = 'Workplace'; OS = 'iPhone'; RegisteredUsers = 'nobody@contoso.com'; Owner = ''; LastSignIn = '2026-09-01'; IntuneManaged = 'False'; Action = 'Re-register' }
        ) | Export-Csv $inv -NoTypeInformation
        $ul = Join-Path $TestDrive 'users.csv'
        @([pscustomobject]@{
            SourceUpn = 'u1@contoso.com'; SourcePrimarySmtp = 'u1@contoso.com'; DisplayName = 'U'; FirstName = 'U'; LastName = 'N'
            TargetUpn = 'u1@fabrikam.onmicrosoft.com'; TargetPrimarySmtp = 'u1@fabrikam.onmicrosoft.com'; UsageLocation = 'DK'
            TargetLicenseSku = 'SPE_E5'; Batch = 'wave1'; CompleteAfterDateTimeUtc = '2026-09-05T22:00:00Z'; Workloads = 'Exchange'
        }) | Export-Csv $ul -NoTypeInformation
        $bl = Join-Path $TestDrive 'bl.csv'
        @([pscustomobject]@{ DeviceName = 'PC-1'; Owner = 'u1@contoso.com'; OS = 'Windows'; JoinType = 'AzureAd'; VolumeType = 'OperatingSystemVolume'; KeyId = 'key1'; Created = '2026-01-01'; DeviceId = 'dev1'; KeyEscrowed = 'True'; Note = '' }) | Export-Csv $bl -NoTypeInformation
        & (Join-Path $PSScriptRoot '..\10-Devices\Get-OldDeviceRetirementPlan.ps1') -DeviceInventoryCsv $inv -UserListPath $ul -BitLockerReportCsv $bl -Customer testcust | Out-Null
        $file = Get-ChildItem (Join-Path $PSScriptRoot '..\customers\testcust\output\10-Devices') -Recurse -Filter 'OldDeviceRetirementPlan-*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $script:plan = @(Import-Csv $file.FullName)
    }
    It 'produces a row per device' { $plan.Count | Should -Be 2 }
    It 'joins the source user to the target user' {
        ($plan | Where-Object DeviceName -eq 'PC-1').TargetUser | Should -Be 'u1@fabrikam.onmicrosoft.com'
    }
    It 'flags the escrowed key' {
        ($plan | Where-Object DeviceName -eq 'PC-1').KeyEscrowed | Should -Be 'True'
    }
    It 'orders Entra deletion last and warns on unknown owners' {
        ($plan | Where-Object DeviceName -eq 'PC-1').Step5_EntraDevice | Should -Match 'LAST'
        ($plan | Where-Object DeviceName -eq 'PHONE-1').Notes | Should -Match 'not in the migration list'
    }
}

Describe 'Static guardrails' {
    It 'Get-BitLockerKeyReport uses ReadBasic scope and never selects the key value' {
        $t = Get-Content (Join-Path $PSScriptRoot '..\10-Devices\Get-BitLockerKeyReport.ps1') -Raw
        $code = (($t -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#|^\s*\.' }) -join "`n"
        $t | Should -Match 'BitlockerKey\.ReadBasic\.All'
        $code | Should -Not -Match 'select=key'
        $code | Should -Not -Match 'RecoveryKey\s*='
    }
    It 'Remove-MigrationArtifacts refuses non-terminal batches (guard present before steps)' {
        $t = Get-Content (Join-Path $PSScriptRoot '..\12-Decommission\Remove-MigrationArtifacts.ps1') -Raw
        ($t.IndexOf('-notin $terminal')) -gt 0 | Should -BeTrue
        ($t.IndexOf('terminal-state guard')) -lt ($t.IndexOf("Step -contains 'BatchData'")) | Should -BeTrue
        $t | Should -Match 'Export-CsvSafe'
    }
}

Describe 'Remove-MigrationArtifacts -AllBatchesTerminalConfirmed' {
    It 'throws for -Role Source without the switch and calls no Remove-* command' {
        $script:removed = 0
        Mock Connect-MigrationExchange { } -ModuleName $null -ErrorAction SilentlyContinue
        $script = Join-Path $PSScriptRoot '..\12-Decommission\Remove-MigrationArtifacts.ps1'
        {
            & $script -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@contoso.onmicrosoft.com' `
                -Role Source -Step OrgRelationship -Customer testcust -WhatIf
        } | Should -Throw '*-AllBatchesTerminalConfirmed*'
        $script:removed | Should -Be 0
    }
    It 'throws for -Role Target -Step CtimData without the switch (session-free step)' {
        $script = Join-Path $PSScriptRoot '..\12-Decommission\Remove-MigrationArtifacts.ps1'
        {
            & $script -TenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -AdminUpn 'admin@fabrikam.onmicrosoft.com' `
                -Role Target -Step CtimData -SourceTenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -Customer testcust -WhatIf
        } | Should -Throw '*-AllBatchesTerminalConfirmed*'
    }
    It 'treats Deleted and PendingDelete as terminal (static check)' {
        (Get-Content (Join-Path $PSScriptRoot '..\12-Decommission\Remove-MigrationArtifacts.ps1') -Raw) |
            Should -Match "'Deleted'.*'PendingDelete'|'PendingDelete'.*'Deleted'"
    }
}

Describe 'Get-AddressMap' {
    BeforeAll {
        $script:ul = Join-Path $TestDrive 'users.csv'
        @(
            [pscustomobject]@{ SourceUpn = 'a@contoso.com'; SourcePrimarySmtp = 'a@contoso.com'; DisplayName = 'A'; FirstName = 'A'; LastName = 'N'; TargetUpn = 'a@fabrikam.onmicrosoft.com'; TargetPrimarySmtp = 'a@fabrikam.onmicrosoft.com'; UsageLocation = 'DK'; TargetLicenseSku = 'SPE_E5'; Batch = 'wave1'; CompleteAfterDateTimeUtc = '2026-09-05T22:00:00Z'; Workloads = 'Exchange' }
            [pscustomobject]@{ SourceUpn = 'b@contoso.com'; SourcePrimarySmtp = 'b@contoso.com'; DisplayName = 'B'; FirstName = 'B'; LastName = 'N'; TargetUpn = 'b@fabrikam.onmicrosoft.com'; TargetPrimarySmtp = 'bsmtp@fabrikam.onmicrosoft.com'; UsageLocation = 'DK'; TargetLicenseSku = 'SPE_E5'; Batch = 'wave1'; CompleteAfterDateTimeUtc = '2026-09-05T22:00:00Z'; Workloads = 'Exchange' }
        ) | Export-Csv $ul -NoTypeInformation
    }
    It 'maps SourcePrimarySmtp to TargetPrimarySmtp (validated by Import-MigrationUserList)' {
        $m = Get-AddressMap -UserListPath $script:ul
        $m.Map['a@contoso.com'] | Should -Be 'a@fabrikam.onmicrosoft.com'
        $m.Map['b@contoso.com'] | Should -Be 'bsmtp@fabrikam.onmicrosoft.com'
        $m.Duplicates.Count | Should -Be 0
    }
    It 'adds shared-mailbox mapping rows' {
        $sm = Join-Path $TestDrive 'shared.csv'
        @([pscustomobject]@{ SourcePrimarySmtp = 'info@contoso.com'; TargetPrimarySmtp = 'info@fabrikam.onmicrosoft.com'; Name = 'Info' }) | Export-Csv $sm -NoTypeInformation
        $m = Get-AddressMap -UserListPath $script:ul -SharedMailboxMappingPath $sm
        $m.Map.Count | Should -Be 3
        $m.Map['info@contoso.com'] | Should -Be 'info@fabrikam.onmicrosoft.com'
    }
    It 'first source wins and duplicates are reported' {
        $sm2 = Join-Path $TestDrive 'shared2.csv'
        @([pscustomobject]@{ SourcePrimarySmtp = 'a@contoso.com'; TargetPrimarySmtp = 'other@fabrikam.onmicrosoft.com'; Name = 'X' }) | Export-Csv $sm2 -NoTypeInformation
        $m = Get-AddressMap -UserListPath $script:ul -SharedMailboxMappingPath $sm2
        $m.Map['a@contoso.com'] | Should -Be 'a@fabrikam.onmicrosoft.com'
        $m.Duplicates | Should -Contain 'a@contoso.com'
    }
    It 'throws when the user list does not exist' {
        { Get-AddressMap -UserListPath 'C:\nope\missing.csv' } | Should -Throw '*not found*'
    }
}
