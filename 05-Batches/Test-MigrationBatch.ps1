#requires -Version 7.2
<#
.SYNOPSIS
    Revalidates a migration batch and, when ValidatePassed is observed, records the time so
    Start-BatchMigration can enforce the 7-day rule.

.DESCRIPTION
    Runs Test-MgBetaCrossTenantMigrationJob (documented: allowed when the batch status is
    Submitted or ValidateFailed), then reads the batch once via Get-MgBetaCrossTenantMigrationJob.
    When the status is ValidatePassed it appends {Batch, JobId, ValidatedAtUtc} to
    customers/<Customer>/output/05-Batches/validation-log.csv - the freshness ledger
    Start-BatchMigration.ps1 falls back on.

.PARAMETER TenantId
    Target tenant ID (GUID).

.PARAMETER AdminUpn
    Target migration admin sign-in.

.PARAMETER Batch
    Batch display name or job ID (the doc accepts both).

.PARAMETER Customer
    For the validation log under customers/<Customer>/output/05-Batches/.

.PARAMETER CustomersRoot
    Root of the customers tree. Default: <repo>/customers. Tests override this.

.EXAMPLE
    .\Test-MigrationBatch.ps1 -TenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -AdminUpn 'admin@fabrikam.com' `
        -Batch 'wave1' -Customer fabrikam

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

if ($PSCmdlet.ShouldProcess($Batch, 'Test-MgBetaCrossTenantMigrationJob (revalidate)')) {
    Test-MgBetaCrossTenantMigrationJob -CrossTenantMigrationJobId $Batch
}

$job = Get-MgBetaCrossTenantMigrationJob -CrossTenantMigrationJobId $Batch
$status = "$(Get-GraphValue -Object $job -Name 'status')"
$id = "$(Get-GraphValue -Object $job -Name 'id')"
Write-Host "Batch '$Batch' status: $status"

if ($status -eq 'ValidatePassed') {
    # New-OutputFolder -Root wants the repo root; CustomersRoot points at its customers/ dir.
    $out = New-OutputFolder -Customer $Customer -Phase '05-Batches' -Root (Split-Path -Parent $CustomersRoot)
    $log = Join-Path $out 'validation-log.csv'
    [pscustomobject]@{ Batch = $Batch; JobId = $id; ValidatedAtUtc = [datetime]::UtcNow.ToString('o') } |
        Export-CsvSafe -Path $log
    Write-Host "ValidatePassed recorded in $log" -ForegroundColor Green
}
elseif ($status -eq 'ValidateFailed') {
    Write-Host 'Validation failed - inspect per-user errors: Get-BatchStatus.ps1 -Batch <name>.' -ForegroundColor Yellow
}
