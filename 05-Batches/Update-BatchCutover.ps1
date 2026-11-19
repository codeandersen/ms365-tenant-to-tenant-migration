#requires -Version 7.2
<#
.SYNOPSIS
    Moves a batch's CompleteAfterDateTime - the earliest acceptable cutover time.

.DESCRIPTION
    Thin, guarded wrapper over Update-MgBetaCrossTenantMigrationJob -CompleteAfterDateTime.
    The date may be changed at any point before it passes. Requires an ISO 8601 UTC timestamp
    in the future. Supports -WhatIf.

.PARAMETER TenantId
    Target tenant ID (GUID).

.PARAMETER AdminUpn
    Target migration admin sign-in.

.PARAMETER Batch
    Batch display name or job ID.

.PARAMETER CompleteAfterDateTimeUtc
    New cutover time, ISO 8601 UTC (e.g. 2026-09-12T22:00:00Z). Must be in the future.

.EXAMPLE
    .\Update-BatchCutover.ps1 -TenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -AdminUpn 'admin@fabrikam.com' `
        -Batch 'wave1' -CompleteAfterDateTimeUtc '2026-09-12T22:00:00Z'

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
    [string]$CompleteAfterDateTimeUtc
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force

$cut = [datetime]::MinValue
if (-not [datetime]::TryParse($CompleteAfterDateTimeUtc, [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$cut)) {
    throw "'$CompleteAfterDateTimeUtc' is not a parseable UTC timestamp."
}
if ($cut -le [datetime]::UtcNow) { throw "CompleteAfterDateTimeUtc must be in the future (got $($cut.ToString('u')))." }

$null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'CrossTenantContentMigration.ReadWrite.All'

if ($PSCmdlet.ShouldProcess($Batch, "Update-MgBetaCrossTenantMigrationJob -CompleteAfterDateTime $CompleteAfterDateTimeUtc")) {
    Update-MgBetaCrossTenantMigrationJob -CrossTenantMigrationJobId $Batch -CompleteAfterDateTime $CompleteAfterDateTimeUtc
}
