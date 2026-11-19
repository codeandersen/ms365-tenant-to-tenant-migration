BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

    function New-UserRow([int]$i, [string]$batch = 'wave1', [string]$date = '2026-09-05T22:00:00Z', [string]$wl = 'Exchange;ODSP;Teams;Meeting') {
        [pscustomobject]@{
            SourceUpn                = "user$i@contoso.com"
            SourcePrimarySmtp        = "user$i@contoso.com"
            DisplayName              = "User $i"
            FirstName                = "User$i"
            LastName                 = 'Test'
            TargetUpn                = "user$i@fabrikam.onmicrosoft.com"
            TargetPrimarySmtp        = "user$i@fabrikam.onmicrosoft.com"
            UsageLocation            = 'DK'
            TargetLicenseSku         = 'SPE_E5'
            Batch                    = $batch
            CompleteAfterDateTimeUtc = $date
            Workloads                = $wl
        }
    }

    function Write-UserCsv($rows, $path) { $rows | Export-Csv -Path $path -NoTypeInformation }
}

Describe 'ConvertTo-WorkloadList' {
    It 'normalises case and order' {
        ConvertTo-WorkloadList -Workloads 'exchange;teams' | Should -Be 'Exchange', 'Teams'
    }
    It 'throws when Meeting lacks Teams' {
        { ConvertTo-WorkloadList -Workloads 'Meeting;Exchange' } | Should -Throw '*Meeting*requires*'
    }
    It 'throws on an unknown workload' {
        { ConvertTo-WorkloadList 'Exchange;ShareGate' } | Should -Throw '*ShareGate*'
    }
}

Describe 'Import-MigrationUserList' {
    BeforeAll {
        $script:Good = Join-Path $TestDrive 'users.csv'
        Write-UserCsv -rows @(New-UserRow 1; New-UserRow 2) -path $script:Good
    }

    It 'imports a valid file' {
        @(Import-MigrationUserList -Path $script:Good).Count | Should -Be 2
    }
    It 'throws listing a missing column' {
        $bad = Join-Path $TestDrive 'missingcol.csv'
        Write-UserCsv -rows @([pscustomobject]@{ SourceUpn = 'a@contoso.com'; Batch = 'w1' }) -path $bad
        { Import-MigrationUserList -Path $bad } | Should -Throw "*missing column 'TargetUpn'*"
    }
    It 'throws on duplicate SourceUpn' {
        $bad = Join-Path $TestDrive 'dup.csv'
        $r1 = New-UserRow 1; $r2 = New-UserRow 1; $r2.TargetUpn = 'other@fabrikam.onmicrosoft.com'; $r2.TargetPrimarySmtp = 'other@fabrikam.onmicrosoft.com'
        Write-UserCsv -rows @($r1, $r2) -path $bad
        { Import-MigrationUserList -Path $bad } | Should -Throw '*duplicate SourceUpn*'
    }
    It 'throws on a bad CompleteAfterDateTimeUtc' {
        $bad = Join-Path $TestDrive 'baddate.csv'
        $r = New-UserRow 1; $r.CompleteAfterDateTimeUtc = 'next friday-ish'
        Write-UserCsv -rows @($r) -path $bad
        { Import-MigrationUserList -Path $bad } | Should -Throw '*CompleteAfterDateTimeUtc*'
    }
}

Describe 'Split-MigrationBatch' {
    It 'splits 250 users in one batch into 100/100/50 with unique names' {
        $users = @(1..250 | ForEach-Object { New-UserRow $_ })
        $batches = @(Split-MigrationBatch -Users $users)
        $batches.Count | Should -Be 3
        @($batches | ForEach-Object { $_.Users.Count }) | Should -Be 100, 100, 50
        $batches.Name | Should -Be 'wave1-01', 'wave1-02', 'wave1-03'
        @($batches | ForEach-Object Users).Count | Should -Be 250
        @($batches | ForEach-Object Users | ForEach-Object TargetUpn | Sort-Object -Unique).Count | Should -Be 250
    }
    It 'keeps a small group under its Batch name' {
        $b = @(Split-MigrationBatch -Users @(New-UserRow 1; New-UserRow 2))
        $b[0].Name | Should -Be 'wave1'
    }
    It 'throws when one Batch mixes CompleteAfterDateTimeUtc' {
        $users = @(New-UserRow 1; New-UserRow 2 -date '2026-09-12T22:00:00Z')
        { Split-MigrationBatch -Users $users } | Should -Throw '*mixes CompleteAfterDateTimeUtc*'
    }
}

Describe 'ConvertTo-CrossTenantMigrationJobBody' {
    It 'produces the documented request body shape' {
        $b = ConvertTo-CrossTenantMigrationJobBody -Name 'wave1' -CompleteAfterDateTimeUtc '2026-09-05T22:00:00Z' `
            -ResourceIds 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -SourceTenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' `
            -SourceEndpoint 'CTM-Endpoint' -TargetDeliveryDomain 'fabrikam.onmicrosoft.com' -Workloads 'Exchange;ODSP;Teams;Meeting'
        $b.Keys | Should -Be 'displayName', 'completeAfterDateTime', 'sourceTenantId', 'exchangeSettings', 'resources', 'resourceType', 'workloads'
        $b.exchangeSettings.targetDeliveryDomain | Should -Be 'fabrikam.onmicrosoft.com'
        $b.exchangeSettings.sourceEndpoint | Should -Be 'CTM-Endpoint'
        $b.resourceType | Should -Be 'Users'
        $b.workloads | Should -Be 'Exchange', 'ODSP', 'Teams', 'Meeting'
        $b.resources[0] | Should -Be 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    }
}

Describe 'Test-ValidationFresh' {
    BeforeAll { $script:VNow = [datetime]::SpecifyKind('2026-09-05T00:00:00', 'Utc') }
    It 'is fresh at 6d 23h' {
        Test-ValidationFresh -ValidatedAtUtc $script:VNow.AddDays(-6).AddHours(-23) -NowUtc $script:VNow | Should -BeTrue
    }
    It 'is stale at 7d 1m' {
        Test-ValidationFresh -ValidatedAtUtc $script:VNow.AddDays(-7).AddMinutes(-1) -NowUtc $script:VNow | Should -BeFalse
    }
    It 'is stale when the timestamp is in the future' {
        Test-ValidationFresh -ValidatedAtUtc $script:VNow.AddHours(1) -NowUtc $script:VNow | Should -BeFalse
    }
}

Describe 'Compare-MigrationIdentity' {
    BeforeAll {
        $script:Src = [pscustomobject]@{
            ExchangeGuid    = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            ArchiveGuid     = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'
            ArchiveStatus   = 'Active'
            LegacyExchangeDN = '/o=ExchangeLabs/ou=Exchange Administrative Group (FYDIBOHF23SPDLT)/cn=Recipients/cn=abc'
            X500Addresses   = 'x500:/o=Contoso/ou=Exchange/cn=old'
        }
        $script:OkTarget = [pscustomobject]@{
            RecipientTypeDetails = 'MailUser'
            ExchangeGuid         = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
            ArchiveGuid          = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'
            EmailAddresses       = @('SMTP:user@fabrikam.onmicrosoft.com', 'X500:/o=ExchangeLabs/ou=Exchange Administrative Group (FYDIBOHF23SPDLT)/cn=Recipients/cn=abc', 'x500:/o=Contoso/ou=Exchange/cn=old')
            PrimarySmtpAddress   = 'user@fabrikam.onmicrosoft.com'
        }
        $script:Domains = @('fabrikam.onmicrosoft.com', 'fabrikam.com')
    }
    It 'passes a correctly mapped MailUser' {
        (Compare-MigrationIdentity -Source $script:Src -Target $script:OkTarget -AcceptedDomains $script:Domains).Pass | Should -BeTrue
    }
    It 'fails when the target ExchangeGuid is empty' {
        $t = $script:OkTarget.PSObject.Copy(); $t.ExchangeGuid = '00000000-0000-0000-0000-000000000000'
        (Compare-MigrationIdentity -Source $script:Src -Target $t -AcceptedDomains $script:Domains).Pass | Should -BeFalse
    }
    It 'fails when the target is a mailbox' {
        $t = $script:OkTarget.PSObject.Copy(); $t.RecipientTypeDetails = 'UserMailbox'
        $r = Compare-MigrationIdentity -Source $script:Src -Target $t -AcceptedDomains $script:Domains
        $r.Pass | Should -BeFalse
        $r.Problems -join ' ' | Should -Match 'UserMailbox'
    }
    It 'fails on an ArchiveGuid mismatch' {
        $t = $script:OkTarget.PSObject.Copy(); $t.ArchiveGuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        (Compare-MigrationIdentity -Source $script:Src -Target $t -AcceptedDomains $script:Domains).Pass | Should -BeFalse
    }
    It 'fails on a missing x500' {
        $t = $script:OkTarget.PSObject.Copy(); $t.EmailAddresses = @('SMTP:user@fabrikam.onmicrosoft.com')
        (Compare-MigrationIdentity -Source $script:Src -Target $t -AcceptedDomains $script:Domains).Pass | Should -BeFalse
    }
    It 'fails on a non-accepted primary domain' {
        $t = $script:OkTarget.PSObject.Copy(); $t.PrimarySmtpAddress = 'user@contoso.com'
        (Compare-MigrationIdentity -Source $script:Src -Target $t -AcceptedDomains $script:Domains).Pass | Should -BeFalse
    }
}

Describe 'Get-GraphValue' {
    It 'reads a typed property' {
        Get-GraphValue -Object ([pscustomobject]@{ Status = 'ValidatePassed' }) -Name 'status' | Should -Be 'ValidatePassed'
    }
    It 'falls back to AdditionalProperties (case-insensitive)' {
        Get-GraphValue -Object ([pscustomobject]@{ AdditionalProperties = @{ STATUS = 'Failed' } }) -Name 'status' | Should -Be 'Failed'
    }
    It 'prefers the typed property over AdditionalProperties' {
        $o = [pscustomobject]@{ Status = 'A'; AdditionalProperties = @{ status = 'B' } }
        Get-GraphValue -Object $o -Name 'status' | Should -Be 'A'
    }
    It 'returns null for a missing property' {
        Get-GraphValue -Object ([pscustomobject]@{ Id = 'x' }) -Name 'status' | Should -BeNullOrEmpty
    }
    It 'returns null for a null object' {
        Get-GraphValue -Object $null -Name 'status' | Should -BeNullOrEmpty
    }
}

Describe 'Select-LicensableUser' {
    BeforeAll {
        $script:Now = [datetime]::SpecifyKind('2026-08-01T12:00:00', 'Utc')
    }
    It 'licenses only freshly verified users' {
        $users = @(
            New-UserRow 1   # verified fresh
            New-UserRow 2   # verification failed
            New-UserRow 3   # no row
            New-UserRow 4   # stale >24h
        )
        $ver = @(
            [pscustomobject]@{ TargetUpn = 'user1@fabrikam.onmicrosoft.com'; Pass = 'True'; Problems = ''; VerifiedAtUtc = '2026-08-01T10:00:00Z' }
            [pscustomobject]@{ TargetUpn = 'user2@fabrikam.onmicrosoft.com'; Pass = 'False'; Problems = 'missing x500'; VerifiedAtUtc = '2026-08-01T10:00:00Z' }
            [pscustomobject]@{ TargetUpn = 'user4@fabrikam.onmicrosoft.com'; Pass = 'True'; Problems = ''; VerifiedAtUtc = '2026-07-30T10:00:00Z' }
        )
        $r = Select-LicensableUser -Users $users -Verification $ver -NowUtc $script:Now
        @($r.Licensable).Count | Should -Be 1
        $r.Licensable[0].TargetUpn | Should -Be 'user1@fabrikam.onmicrosoft.com'
        @($r.Refused).Count | Should -Be 3
        @($r.Refused | Where-Object Reason -match 'no verification row').Count | Should -Be 1
        @($r.Refused | Where-Object Reason -match 'verification failed').Count | Should -Be 1
        @($r.Refused | Where-Object Reason -match 'old').Count | Should -Be 1
    }
}
