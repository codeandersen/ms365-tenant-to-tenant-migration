#requires -Version 7.2
<#
.SYNOPSIS
    Starts migration for a batch - only when validation passed and is still fresh (≤7 days),
    or as a documented retry on CompletedWithErrors/Failed.

.DESCRIPTION
    The doc allows Move-MgBetaCrossTenantMigrationJob when the batch status is ValidatePassed,
    and permits a retry when it is CompletedWithErrors or Failed. Validation must have passed
    within the last 7 days or the batch must be revalidated first.

    Validation freshness source, in order:
      1. A validation timestamp on the job object itself, if the model exposes one
         (properties are probed defensively - none are documented).
      2. The newest ValidatePassed entry for this batch in
         customers/<Customer>/output/05-Batches/**/validation-log.csv (written by
         Test-MigrationBatch.ps1).
    If neither exists, a ValidatePassed batch is refused with instructions to revalidate, and
    a retry (CompletedWithErrors/Failed) proceeds with a warning - the service enforces the
    7-day rule itself.

    Supports -WhatIf.

.PARAMETER TenantId
    Target tenant ID (GUID).

.PARAMETER AdminUpn
    Target migration admin sign-in.

.PARAMETER Batch
    Batch display name or job ID.

.PARAMETER Customer
    Location of the validation log under customers/<Customer>/output/05-Batches/.

.PARAMETER CustomersRoot
    Root of the customers tree. Default: <repo>/customers. Tests override this.

.EXAMPLE
    .\Start-BatchMigration.ps1 -TenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -AdminUpn 'admin@fabrikam.com' `
        -Batch 'wave1' -Customer fabrikam -WhatIf

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
    [string]$Batch,

    [Parameter(Mandatory)]
    [string]$Customer,

    [string]$CustomersRoot = (Join-Path $PSScriptRoot '..\customers')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

$null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'CrossTenantContentMigration.ReadWrite.All'

$job = Get-MgBetaCrossTenantMigrationJob -CrossTenantMigrationJobId $Batch
$status = "$(Get-GraphValue -Object $job -Name 'status')"
Write-Host "Batch '$Batch' status: $status"

$retryStates = 'CompletedWithErrors', 'Failed'
if ($status -ne 'ValidatePassed' -and $retryStates -notcontains $status) {
    throw "Migration can't be started from status '$status' (allowed: ValidatePassed, CompletedWithErrors, Failed)."
}

# ------------------------------------------------------------ validation freshness
$validatedAt = $null

# 1. a timestamp property on the job object, if the model exposes one (none is documented)
foreach ($prop in 'ValidationCompletedDateTime', 'ValidatedDateTime', 'LastValidationDateTime', 'validationCompletedDateTime') {
    $v = $job.$prop
    if (-not $v -and $job.AdditionalProperties) { $v = $job.AdditionalProperties[$prop] }
    if ($v) {
        $d = [datetime]::MinValue
        if ([datetime]::TryParse("$v", [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$d)) { $validatedAt = $d; break }
    }
}

# 2. fallback: the validation log written by Test-MigrationBatch.ps1
if (-not $validatedAt) {
    $logDir = Join-Path (Join-Path $CustomersRoot $Customer) 'output\05-Batches'
    $logs = @(Get-ChildItem -Path $logDir -Recurse -Filter 'validation-log.csv' -ErrorAction SilentlyContinue)
    $rows = foreach ($l in $logs) { Import-Csv $l.FullName }
    $hit = $rows | Where-Object { $_.Batch -eq $Batch -or $_.JobId -eq "$($job.Id)" } |
        Sort-Object { [datetime]$_.ValidatedAtUtc } -Descending | Select-Object -First 1
    if ($hit) { $validatedAt = [datetime]$hit.ValidatedAtUtc }
}

if ($status -eq 'ValidatePassed') {
    if (-not $validatedAt) {
        throw "No validation timestamp found for '$Batch' (none on the job object and none in the validation log). Revalidate first: Test-MigrationBatch.ps1 -Batch '$Batch'."
    }
    if (-not (Test-ValidationFresh -ValidatedAtUtc $validatedAt -NowUtc ([datetime]::UtcNow))) {
        throw "Validation passed $([math]::Round(([datetime]::UtcNow - $validatedAt).TotalDays, 1)) days ago - over the 7-day limit. Revalidate: Test-MigrationBatch.ps1 -Batch '$Batch'."
    }
    Write-Host "Validation is fresh (passed $($validatedAt.ToString('u')))." -ForegroundColor Green
}
else {
    Write-Warning "Retry on status '$status'$(if ($validatedAt) { " (last validation $($validatedAt.ToString('u')))" } else { '; no validation timestamp found - the service enforces the 7-day rule' })."
}

if ($PSCmdlet.ShouldProcess($Batch, "Move-MgBetaCrossTenantMigrationJob (start migration, status $status)")) {
    Move-MgBetaCrossTenantMigrationJob -CrossTenantMigrationJobId $Batch
}
