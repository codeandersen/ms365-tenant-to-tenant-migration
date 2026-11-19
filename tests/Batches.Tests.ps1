BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force
    $script:StartScript = Join-Path $PSScriptRoot '..\05-Batches\Start-BatchMigration.ps1'
    $script:TestScript = Join-Path $PSScriptRoot '..\05-Batches\Test-MigrationBatch.ps1'
    $script:NewScript = Join-Path $PSScriptRoot '..\05-Batches\New-MigrationBatches.ps1'

    # Stubs so Pester mocks can attach to Graph cmdlets that are not installed locally.
    function global:Get-MgBetaCrossTenantMigrationJob { param($CrossTenantMigrationJobId, $All, $ErrorAction) }
    function global:Get-MgBetaCrossTenantMigrationJobUser { param($CrossTenantMigrationJobId, $CrossTenantMigrationTaskId, $All) }
    function global:Move-MgBetaCrossTenantMigrationJob { param($CrossTenantMigrationJobId) }
    function global:Test-MgBetaCrossTenantMigrationJob { param($CrossTenantMigrationJobId) }
    function global:New-MgBetaCrossTenantMigrationJob { param($BodyParameter, $ErrorAction) }
    function global:Get-MgUser { param($UserId, $Property, $ErrorAction) }

    $script:Tid = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'
    $script:Sid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'

    function Write-ValidationLog($root, $batch, $daysAgo) {
        $dir = Join-Path $root 'testcust\output\05-Batches\run1'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [pscustomobject]@{ Batch = $batch; JobId = 'job1'; ValidatedAtUtc = [datetime]::UtcNow.AddDays(-$daysAgo).ToString('o') } |
            Export-Csv (Join-Path $dir 'validation-log.csv') -NoTypeInformation
    }

    function Write-UserList($path) {
        @([pscustomobject]@{
            SourceUpn = 'u1@contoso.com'; SourcePrimarySmtp = 'u1@contoso.com'; DisplayName = 'U One'
            FirstName = 'U'; LastName = 'One'; TargetUpn = 'u1@fabrikam.onmicrosoft.com'; TargetPrimarySmtp = 'u1@fabrikam.onmicrosoft.com'
            UsageLocation = 'DK'; TargetLicenseSku = 'SPE_E5'; Batch = 'wave2'
            CompleteAfterDateTimeUtc = [datetime]::UtcNow.AddDays(14).ToString('o'); Workloads = 'Exchange;ODSP;Teams;Meeting'
        }) | Export-Csv -Path $path -NoTypeInformation
    }
}

Describe 'Start-BatchMigration.ps1' {
    BeforeAll {
        Mock Connect-MigrationGraph { }
        Mock Move-MgBetaCrossTenantMigrationJob { $global:MoveCalls++ }
        Mock Get-MgUser { [pscustomobject]@{ Id = $script:Sid } }
    }
    BeforeEach { $global:MoveCalls = 0 }

    It 'starts migration when validation passed 2 days ago' {
        Mock Get-MgBetaCrossTenantMigrationJob { [pscustomobject]@{ Id = 'job1'; Status = 'ValidatePassed' } }
        Write-ValidationLog $TestDrive 'wave1' 2
        & $script:StartScript -TenantId $script:Tid -AdminUpn 'admin@fabrikam.com' -Batch 'wave1' -Customer testcust -CustomersRoot $TestDrive
        $global:MoveCalls | Should -Be 1
    }
    It 'refuses when validation is 8 days old' {
        Mock Get-MgBetaCrossTenantMigrationJob { [pscustomobject]@{ Id = 'job1'; Status = 'ValidatePassed' } }
        Write-ValidationLog $TestDrive 'wave1' 8
        { & $script:StartScript -TenantId $script:Tid -AdminUpn 'admin@fabrikam.com' -Batch 'wave1' -Customer testcust -CustomersRoot $TestDrive } | Should -Throw '*7-day*'
        $global:MoveCalls | Should -Be 0
    }
    It 'refuses when there is no validation timestamp at all' {
        Mock Get-MgBetaCrossTenantMigrationJob { [pscustomobject]@{ Id = 'job1'; Status = 'ValidatePassed' } }
        Remove-Item (Join-Path $TestDrive 'testcust') -Recurse -Force -ErrorAction SilentlyContinue
        { & $script:StartScript -TenantId $script:Tid -AdminUpn 'admin@fabrikam.com' -Batch 'wave1' -Customer testcust -CustomersRoot $TestDrive } | Should -Throw '*No validation timestamp*'
        $global:MoveCalls | Should -Be 0
    }
    It 'refuses from ValidateFailed' {
        Mock Get-MgBetaCrossTenantMigrationJob { [pscustomobject]@{ Id = 'job1'; Status = 'ValidateFailed' } }
        { & $script:StartScript -TenantId $script:Tid -AdminUpn 'admin@fabrikam.com' -Batch 'wave1' -Customer testcust -CustomersRoot $TestDrive } | Should -Throw "*ValidateFailed*"
        $global:MoveCalls | Should -Be 0
    }
    It 'allows retry from Failed' {
        Mock Get-MgBetaCrossTenantMigrationJob { [pscustomobject]@{ Id = 'job1'; Status = 'Failed' } }
        & $script:StartScript -TenantId $script:Tid -AdminUpn 'admin@fabrikam.com' -Batch 'wave1' -Customer testcust -CustomersRoot $TestDrive
        $global:MoveCalls | Should -Be 1
    }
}

Describe 'Test-MigrationBatch.ps1' {
    BeforeAll {
        Mock Connect-MigrationGraph { }
        Mock Test-MgBetaCrossTenantMigrationJob { }
        Mock Get-MgBetaCrossTenantMigrationJob { [pscustomobject]@{ Id = 'job1'; Status = 'ValidatePassed' } }
    }
    It 'writes a ValidatePassed entry to the validation log' {
        & $script:TestScript -TenantId $script:Tid -AdminUpn 'admin@fabrikam.com' -Batch 'wave1' -Customer testcust -CustomersRoot (Join-Path $TestDrive 'customers')
        $log = Get-ChildItem (Join-Path $TestDrive 'customers\testcust') -Recurse -Filter 'validation-log.csv' | Select-Object -First 1
        $log | Should -Not -BeNullOrEmpty
        $rows = Import-Csv $log.FullName
        $rows[0].Batch | Should -Be 'wave1'
        $rows[0].ValidatedAtUtc | Should -Not -BeNullOrEmpty
    }
}

Describe 'New-MigrationBatches.ps1' {
    BeforeAll {
        Mock Connect-MigrationGraph { }
        Mock New-OutputFolder { $TestDrive }
        Mock Get-MgUser { [pscustomobject]@{ Id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; UserPrincipalName = $UserId } }
        Mock New-MgBetaCrossTenantMigrationJob { $global:NewCalls++; [pscustomobject]@{ Id = 'newjob1' } }
        $script:Ucsv = Join-Path $TestDrive 'users.csv'
        Write-UserList $script:Ucsv
    }
    BeforeEach { $global:NewCalls = 0 }

    It 'refuses a batch name that already exists' {
        Mock Get-MgBetaCrossTenantMigrationJob { [pscustomobject]@{ Id = 'job1'; DisplayName = 'wave2' } }
        & $script:NewScript -TenantId $script:Tid -AdminUpn 'admin@fabrikam.com' -UserListPath $script:Ucsv `
            -SourceTenantId $script:Sid -SourceEndpoint 'ep' -TargetDeliveryDomain 'fabrikam.onmicrosoft.com' -Customer testcust
        $global:NewCalls | Should -Be 0
        $report = Import-Csv (Join-Path $TestDrive 'batches.csv')
        $report[0].Action | Should -Be 'Refused'
    }
    It 'creates a batch whose resources are the resolved user Ids' {
        Mock Get-MgBetaCrossTenantMigrationJob { $null }
        & $script:NewScript -TenantId $script:Tid -AdminUpn 'admin@fabrikam.com' -UserListPath $script:Ucsv `
            -SourceTenantId $script:Sid -SourceEndpoint 'ep' -TargetDeliveryDomain 'fabrikam.onmicrosoft.com' -Customer testcust
        $global:NewCalls | Should -Be 1
        Assert-MockCalled New-MgBetaCrossTenantMigrationJob -Times 1 -ParameterFilter {
            $BodyParameter.displayName -eq 'wave2' -and
            @($BodyParameter.resources) -contains 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -and
            $BodyParameter.exchangeSettings.targetDeliveryDomain -eq 'fabrikam.onmicrosoft.com'
        }
    }
}
