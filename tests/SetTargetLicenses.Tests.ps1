BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..\03-Identities\Set-TargetLicenses.ps1'

    # Stubs so Pester mocks can attach to Graph cmdlets that are not installed locally.
    function global:Get-MgSubscribedSku { param([switch]$All) }
    function global:Get-MgUser { param($UserId, $Property, $ErrorAction) }
    function global:Update-MgUser { param($UserId, $UsageLocation) }
    function global:Set-MgUserLicense { param($UserId, $AddLicenses, $RemoveLicenses) }

    $script:UsersCsv = Join-Path $TestDrive 'users.csv'
    @(
        [pscustomobject]@{
            SourceUpn = 'fresh@contoso.com'; SourcePrimarySmtp = 'fresh@contoso.com'; DisplayName = 'Fresh'
            FirstName = 'F'; LastName = 'R'; TargetUpn = 'fresh@fabrikam.onmicrosoft.com'; TargetPrimarySmtp = 'fresh@fabrikam.onmicrosoft.com'
            UsageLocation = 'DK'; TargetLicenseSku = 'SPE_E5'; Batch = 'wave1'
            CompleteAfterDateTimeUtc = '2026-09-05T22:00:00Z'; Workloads = 'Exchange'
        }
        [pscustomobject]@{
            SourceUpn = 'stale@contoso.com'; SourcePrimarySmtp = 'stale@contoso.com'; DisplayName = 'Stale'
            FirstName = 'S'; LastName = 'T'; TargetUpn = 'stale@fabrikam.onmicrosoft.com'; TargetPrimarySmtp = 'stale@fabrikam.onmicrosoft.com'
            UsageLocation = 'DK'; TargetLicenseSku = 'SPE_E5'; Batch = 'wave1'
            CompleteAfterDateTimeUtc = '2026-09-05T22:00:00Z'; Workloads = 'Exchange'
        }
    ) | Export-Csv -Path $script:UsersCsv -NoTypeInformation

    $script:VerCsv = Join-Path $TestDrive 'verification.csv'
    @(
        [pscustomobject]@{ TargetUpn = 'fresh@fabrikam.onmicrosoft.com'; Pass = 'True'; Problems = ''; VerifiedAtUtc = [datetime]::UtcNow.AddHours(-1).ToString('o') }
        [pscustomobject]@{ TargetUpn = 'stale@fabrikam.onmicrosoft.com'; Pass = 'True'; Problems = ''; VerifiedAtUtc = [datetime]::UtcNow.AddHours(-48).ToString('o') }
    ) | Export-Csv -Path $script:VerCsv -NoTypeInformation
}

Describe 'Set-TargetLicenses.ps1 mocked run' {
    BeforeAll {
        $global:Licensed = [System.Collections.Generic.List[string]]::new()
        $global:OutDir = Join-Path ([IO.Path]::GetTempPath()) ('slout-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $global:OutDir | Out-Null
        Mock Connect-MigrationGraph { }
        Mock Get-MgSubscribedSku { [pscustomobject]@{ SkuPartNumber = 'SPE_E5'; SkuId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' } }
        Mock Get-MgUser { [pscustomobject]@{ Id = $UserId; UserPrincipalName = $UserId; UsageLocation = 'DK' } }
        Mock Set-MgUserLicense { $global:Licensed.Add($UserId) }
        Mock New-OutputFolder { $global:OutDir }
        & $script:Script -TenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -AdminUpn 'admin@fabrikam.com' `
            -UserListPath $script:UsersCsv -VerificationCsv $script:VerCsv -Customer 'testcust'
    }
    It 'licenses the freshly verified user only' {
        @($global:Licensed).Count | Should -Be 1
        $global:Licensed[0] | Should -Be 'fresh@fabrikam.onmicrosoft.com'
    }
    It 'never licenses the user whose verification is stale' {
        $report = Import-Csv (Join-Path $global:OutDir 'TargetLicenses.csv')
        @($report | Where-Object Action -eq 'Licensed').Count | Should -Be 1
        @($report | Where-Object { $_.TargetUpn -eq 'stale@fabrikam.onmicrosoft.com' -and $_.Action -eq 'Refused' }).Count | Should -Be 1
    }
}
