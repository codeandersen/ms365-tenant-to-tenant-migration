#requires -Version 7.2
<#
.SYNOPSIS
    Read-only: status of native cross-tenant SharePoint/OneDrive content moves towards a partner
    tenant, from the source tenant.

.DESCRIPTION
    Wraps Get-SPOCrossTenantSiteContentMoveState and Get-SPOCrossTenantGroupContentMoveState
    (the installed module's status cmdlets for the step-6 moves). Optionally filters by
    MoveState (Queued, InProgress, Success, Failed, Stopped, etc. as the service reports).

.PARAMETER TenantId
    Source tenant ID (GUID).

.PARAMETER AdminUpn
    Source SharePoint admin sign-in name.

.PARAMETER AdminUrl
    Source SharePoint admin URL, e.g. https://contoso-admin.sharepoint.com.

.PARAMETER TargetCrossTenantHostUrl
    Target tenant's cross-tenant host URL.

.PARAMETER MoveState
    Optional filter, e.g. 'Failed'.

.PARAMETER Customer
    Writes the CSV under customers/<Customer>/output/07-SharePoint-Teams/.

.EXAMPLE
    .\Get-SiteContentMoveStatus.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@contoso.com' `
        -AdminUrl 'https://contoso-admin.sharepoint.com' -TargetCrossTenantHostUrl 'https://fabrikam-my.sharepoint.com' -Customer contoso

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Sources:
      https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration-step6
      https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration-step7
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$AdminUrl,

    [Parameter(Mandatory)]
    [string]$TargetCrossTenantHostUrl,

    [string]$MoveState,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force

Connect-MigrationSharePoint -TenantId $TenantId -AdminUrl $AdminUrl

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($p in @{ Site = 'Get-SPOCrossTenantSiteContentMoveState'; Group = 'Get-SPOCrossTenantGroupContentMoveState' }.GetEnumerator()) {
    $args = @{ PartnerCrossTenantHostUrl = $TargetCrossTenantHostUrl; ErrorAction = 'SilentlyContinue' }
    if ($MoveState) { $args.MoveState = $MoveState }
    foreach ($m in @(& $p.Value @args)) {
        $rows.Add([pscustomobject]@{
            Kind       = $p.Key
            Source     = if ($m.SourceSiteUrl) { $m.SourceSiteUrl } elseif ($m.SourceGroupAlias) { $m.SourceGroupAlias } else { "$m" }
            Target     = if ($m.TargetSiteUrl) { $m.TargetSiteUrl } elseif ($m.TargetGroupAlias) { $m.TargetGroupAlias } else { '' }
            MoveId     = if ($m.SiteMoveId) { $m.SiteMoveId } else { $m.Id }
            MoveState  = "$($m.MoveState)"
            Detail     = "$($m | Out-String)".Trim()
        })
    }
}

$rows | Format-Table Kind, Source, MoveState -AutoSize | Out-Host
$rows | Group-Object MoveState | ForEach-Object { Write-Host ("{0,-12} {1}" -f $_.Name, $_.Count) }
$out = New-OutputFolder -Customer $Customer -Phase '07-SharePoint-Teams'
$rows | Export-CsvSafe -Path (Join-Path $out 'SiteContentMoveStatus.csv')
Write-Host "Report: $out" -ForegroundColor Cyan
