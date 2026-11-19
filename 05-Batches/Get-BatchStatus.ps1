#requires -Version 7.2
<#
.SYNOPSIS
    Read-only: shows a batch's status and per-user, per-workload status, optionally as CSV.

.DESCRIPTION
    Get-MgBetaCrossTenantMigrationJob (or all batches without -Batch) plus
    Get-MgBetaCrossTenantMigrationJobUser for the named batch. With -Customer, writes
    job-users CSV under customers/<Customer>/output/05-Batches/.

.PARAMETER TenantId
    Target tenant ID (GUID).

.PARAMETER AdminUpn
    Target migration admin sign-in.

.PARAMETER Batch
    Batch display name or job ID. Omit to list all batches.

.PARAMETER Customer
    Writes the per-user CSV under customers/<Customer>/output/05-Batches/.

.EXAMPLE
    .\Get-BatchStatus.ps1 -TenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -AdminUpn 'admin@fabrikam.com' -Batch 'wave1' -Customer fabrikam

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Source: https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-5-running-migration
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [string]$Batch,
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

$null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'CrossTenantContentMigration.ReadWrite.All'

if (-not $Batch) {
    Get-MgBetaCrossTenantMigrationJob -All | ConvertTo-Json -Depth 5 | Write-Host
    return
}

$job = Get-MgBetaCrossTenantMigrationJob -CrossTenantMigrationJobId $Batch
$job | ConvertTo-Json -Depth 5 | Write-Host

$users = @(Get-MgBetaCrossTenantMigrationJobUser -CrossTenantMigrationJobId $Batch -All)
$flat = foreach ($u in $users) {
    [pscustomobject]@{
        UserId    = "$(Get-GraphValue -Object $u -Name 'id')"
        Status    = "$(Get-GraphValue -Object $u -Name 'status')"
        Workloads = "$(@($u.Workloads ?? $u.AdditionalProperties['workloads']) -join ';')"
        Message   = "$(Get-GraphValue -Object $u -Name 'message')"
    }
}
$flat | Format-Table -AutoSize | Out-Host

if ($Customer) {
    $out = New-OutputFolder -Customer $Customer -Phase '05-Batches'
    $file = Join-Path $out "batch-users-$Batch.csv"
    $flat | Export-CsvSafe -Path $file
    Write-Host "User status written: $file" -ForegroundColor Cyan
}
