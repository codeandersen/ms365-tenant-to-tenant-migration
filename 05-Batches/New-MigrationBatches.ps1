#requires -Version 7.2
<#
.SYNOPSIS
    Creates Orchestrator migration batches from the canonical user list (target tenant).

.DESCRIPTION
    Import-MigrationUserList -> Split-MigrationBatch (≤100 per batch, documented max) -> for each
    batch: resolve every TargetUpn to the Entra object ID (Get-MgUser), refuse to reuse an existing
    batch name (names must be unique), require CompleteAfterDateTimeUtc in the future, and create
    the job with New-MgBetaCrossTenantMigrationJob -BodyParameter built by
    ConvertTo-CrossTenantMigrationJobBody - the documented request shape. Creating a batch starts
    validation automatically.

    Supports -WhatIf. Writes a batches CSV to customers/<Customer>/output/05-Batches/.

.PARAMETER TenantId
    Target tenant ID (GUID). Graph connection asserted; migration commands run from the TARGET.

.PARAMETER AdminUpn
    Target Microsoft 365 Migration Administrator or Global Administrator sign-in.

.PARAMETER UserListPath
    Path to migration-users.csv.

.PARAMETER SourceTenantId
    Source tenant ID (GUID) - goes into every job body.

.PARAMETER SourceEndpoint
    Name of the migration endpoint on the target tenant (exchangeSettings.sourceEndpoint).

.PARAMETER TargetDeliveryDomain
    Target domain for delivery, e.g. fabrikam.onmicrosoft.com.

.PARAMETER Only
    Optional list of Batch values to restrict which batches are created.

.PARAMETER Customer
    Output folder under customers/<Customer>/output/05-Batches/.

.EXAMPLE
    .\New-MigrationBatches.ps1 -TenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -AdminUpn 'admin@fabrikam.com' `
        -UserListPath .\customers\fabrikam\input\migration-users.csv -SourceTenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' `
        -SourceEndpoint 'CrossTenantMigrationEndpoint' -TargetDeliveryDomain 'fabrikam.onmicrosoft.com' `
        -Customer fabrikam -WhatIf

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Source: https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-5-running-migration
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$UserListPath,

    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$SourceTenantId,

    [Parameter(Mandatory)]
    [string]$SourceEndpoint,

    [Parameter(Mandatory)]
    [string]$TargetDeliveryDomain,

    [string[]]$Only,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

$users = @(Import-MigrationUserList -Path $UserListPath)
$batches = @(Split-MigrationBatch -Users $users)
if ($Only) {
    $wanted = @($Only | ForEach-Object { "$_".ToLower() })
    $batches = @($batches | Where-Object { $wanted -contains "$($_.Users[0].Batch)".ToLower() -or $wanted -contains $_.Name.ToLower() })
}
if (-not $batches.Count) { throw 'No batches to create.' }

$null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'CrossTenantContentMigration.ReadWrite.All', 'User.Read.All'

$existing = @{}
Get-MgBetaCrossTenantMigrationJob -All -ErrorAction SilentlyContinue | ForEach-Object {
    $n = "$(Get-GraphValue -Object $_ -Name 'displayName')"
    if ($n) { $existing[$n.ToLower()] = $true }
}

$now = [datetime]::UtcNow
$report = [System.Collections.Generic.List[object]]::new()
foreach ($b in $batches) {
    $row = [ordered]@{ Name = $b.Name; Users = $b.Users.Count; CompleteAfterDateTimeUtc = $b.CompleteAfterDateTimeUtc; Workloads = $b.Workloads -join ';'; Action = ''; JobId = ''; Note = '' }

    if ($existing.ContainsKey($b.Name.ToLower())) {
        $row.Action = 'Refused'; $row.Note = 'a batch with this name already exists (names must be unique)'
        $report.Add([pscustomobject]$row); continue
    }
    $cut = [datetime]::MinValue
    if (-not [datetime]::TryParse($b.CompleteAfterDateTimeUtc, [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$cut) -or $cut -le $now) {
        $row.Action = 'Refused'; $row.Note = "CompleteAfterDateTimeUtc '$($b.CompleteAfterDateTimeUtc)' is not in the future"
        $report.Add([pscustomobject]$row); continue
    }

    $ids = [System.Collections.Generic.List[string]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($u in $b.Users) {
        $mgUser = Get-MgUser -UserId $u.TargetUpn -Property Id -ErrorAction SilentlyContinue
        if ($mgUser) { $ids.Add($mgUser.Id) } else { $missing.Add($u.TargetUpn) }
    }
    if ($missing.Count) {
        $row.Action = 'Refused'; $row.Note = "target users not found: $($missing -join ', ')"
        $report.Add([pscustomobject]$row); continue
    }

    $body = ConvertTo-CrossTenantMigrationJobBody -Name $b.Name -CompleteAfterDateTimeUtc $b.CompleteAfterDateTimeUtc `
        -ResourceIds ([string[]]$ids) -SourceTenantId $SourceTenantId -SourceEndpoint $SourceEndpoint `
        -TargetDeliveryDomain $TargetDeliveryDomain -Workloads $b.Workloads
    if ($PSCmdlet.ShouldProcess($b.Name, "New-MgBetaCrossTenantMigrationJob ($($ids.Count) users, cutover $($b.CompleteAfterDateTimeUtc))")) {
        try {
            $job = New-MgBetaCrossTenantMigrationJob -BodyParameter $body -ErrorAction Stop
            $row.Action = 'Created'; $row.JobId = "$(Get-GraphValue -Object $job -Name 'id')"
        }
        catch { $row.Action = 'Error'; $row.Note = $_.Exception.Message }
    }
    else { $row.Action = 'WhatIf:Create' }
    $report.Add([pscustomobject]$row)
}

$out = New-OutputFolder -Customer $Customer -Phase '05-Batches'
$file = Join-Path $out 'batches.csv'
$report | Export-CsvSafe -Path $file
$report | Format-Table -AutoSize | Out-Host
Write-Host "Batches report: $file" -ForegroundColor Green
Write-Host 'Validation starts automatically on creation. Monitor with Get-BatchStatus.ps1; revalidate with Test-MigrationBatch.ps1.' -ForegroundColor Yellow
