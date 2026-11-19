#requires -Version 7.2
<#
.SYNOPSIS
    Cancels one user's migration inside a batch, or the whole batch - only possible before
    that user's/​batch's cutover starts.

.DESCRIPTION
    -UserUpn: resolves the UPN to the target ExternalDirectoryObjectId and calls
    Stop-MgBetaCrossTenantMigrationJobUser (removes the user from the batch; identity mapping
    is untouched; the user can be added to a NEW batch, not the same one).
    -WholeBatch: Stop-MgBetaCrossTenantMigrationJob (cancels every user whose cutover has not
    started).
    Both are only possible before CompleteAfterDateTime passes / before the user's migration
    starts. Supports -WhatIf.

.PARAMETER TenantId
    Target tenant ID (GUID).

.PARAMETER AdminUpn
    Target migration admin sign-in.

.PARAMETER Batch
    Batch display name or job ID.

.PARAMETER UserUpn
    Target UPN of the single user to remove.

.PARAMETER WholeBatch
    Cancel the entire batch instead.

.EXAMPLE
    .\Stop-BatchUser.ps1 -TenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -AdminUpn 'admin@fabrikam.com' `
        -Batch 'wave1' -UserUpn 'user1@fabrikam.onmicrosoft.com'

.EXAMPLE
    .\Stop-BatchUser.ps1 -TenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -AdminUpn 'admin@fabrikam.com' `
        -Batch 'wave1' -WholeBatch -WhatIf

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Source: https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-5-running-migration
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'User')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$Batch,

    [Parameter(Mandatory, ParameterSetName = 'User')]
    [string]$UserUpn,

    [Parameter(Mandatory, ParameterSetName = 'Batch')]
    [switch]$WholeBatch
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force

$null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'CrossTenantContentMigration.ReadWrite.All', 'User.Read.All'

if ($WholeBatch) {
    if ($PSCmdlet.ShouldProcess($Batch, 'Stop-MgBetaCrossTenantMigrationJob (cancel the whole batch)')) {
        Stop-MgBetaCrossTenantMigrationJob -CrossTenantMigrationJobId $Batch
    }
    return
}

$mgUser = Get-MgUser -UserId $UserUpn -Property Id -ErrorAction Stop
if ($PSCmdlet.ShouldProcess($UserUpn, "Stop-MgBetaCrossTenantMigrationJobUser -CrossTenantMigrationJobId $Batch -CrossTenantMigrationTaskId $($mgUser.Id)")) {
    Stop-MgBetaCrossTenantMigrationJobUser -CrossTenantMigrationJobId $Batch -CrossTenantMigrationTaskId $mgUser.Id
}
Write-Host 'A removed user cannot be re-added to the SAME batch - create a new batch for them instead.' -ForegroundColor Yellow
