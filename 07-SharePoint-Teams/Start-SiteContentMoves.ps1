#requires -Version 7.2
<#
.SYNOPSIS
    Starts native cross-tenant SharePoint content moves for the sites marked Track=Native in the
    plan - run from the SOURCE tenant per the documented process.

.DESCRIPTION
    Per the cross-tenant SharePoint migration step 6, a SharePoint/GA admin on the source tenant
    runs:

      Start-SPOCrossTenantSiteContentMove  -SourceSiteUrl -TargetSiteUrl -TargetCrossTenantHostUrl
      Start-SPOCrossTenantGroupContentMove -SourceGroupAlias -TargetGroupAlias -TargetCrossTenantHostUrl

    Group-connected sites use the group variant with the group ALIAS (not the URL), which must be
    the same as the last segment of the target URL. -ValidationOnly runs the built-in dry run
    instead of a real move (documented -ValidationOnly switch).

    Before queuing, the script counts pending/active moves via
    Get-SPOCrossTenantSiteContentMoveState/Get-SPOCrossTenantGroupContentMoveState and refuses to
    exceed -MaxQueued (default below the documented 4,000 queue limit, which is shared with the
    OneDrive tool and the Orchestrator). Rows without TargetUrl (sites) or TargetGroupAlias
    (groups) are refused. Each successful submission is logged.

.PARAMETER TenantId
    Source tenant ID (GUID).

.PARAMETER AdminUpn
    Source SharePoint admin sign-in name.

.PARAMETER AdminUrl
    Source SharePoint admin URL, e.g. https://contoso-admin.sharepoint.com.

.PARAMETER PlanCsv
    SiteMigrationPlan.csv; only rows with Track=Native are processed.

.PARAMETER TargetCrossTenantHostUrl
    Target tenant's cross-tenant host URL (Get-SPOCrossTenantHostUrl on the target).

.PARAMETER MaxQueued
    Maximum queued/active moves allowed including new submissions. Default 2000 (the documented
    4,000 queue is shared across all cross-tenant SPO tools - keep headroom).

.PARAMETER ValidationOnly
    Submit with -ValidationOnly (doc-supported dry run) instead of a real move.

.PARAMETER Customer
    Writes the submission log under customers/<Customer>/output/07-SharePoint-Teams/.

.EXAMPLE
    .\Start-SiteContentMoves.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@contoso.com' `
        -AdminUrl 'https://contoso-admin.sharepoint.com' -PlanCsv .\SiteMigrationPlan.csv `
        -TargetCrossTenantHostUrl 'https://fabrikam-my.sharepoint.com' -Customer contoso -WhatIf

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Sources:
      https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration-step6
      https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$AdminUrl,

    [Parameter(Mandatory)]
    [string]$PlanCsv,

    [Parameter(Mandatory)]
    [string]$TargetCrossTenantHostUrl,

    [int]$MaxQueued = 2000,

    [switch]$ValidationOnly,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

$rows = @(Import-Csv $PlanCsv | Where-Object { $_.Track -eq 'Native' })
if (-not $rows) { throw "No Track=Native rows in $PlanCsv." }

Connect-MigrationSharePoint -TenantId $TenantId -AdminUrl $AdminUrl

# Queue depth: don't exceed -MaxQueued including the new submissions.
$active = @()
try {
    $active += @(Get-SPOCrossTenantSiteContentMoveState -PartnerCrossTenantHostUrl $TargetCrossTenantHostUrl -ErrorAction SilentlyContinue |
        Where-Object { "$($_.MoveState)" -notin 'Failed', 'Succeeded', 'Success', 'Stopped' })
    $active += @(Get-SPOCrossTenantGroupContentMoveState -PartnerCrossTenantHostUrl $TargetCrossTenantHostUrl -ErrorAction SilentlyContinue |
        Where-Object { "$($_.MoveState)" -notin 'Failed', 'Succeeded', 'Success', 'Stopped' })
}
catch { Write-Warning "Couldn't count the current queue ($($_.Exception.Message)) - counting only new submissions." }
$queued = $active.Count
Write-Host "Current queue depth (this partner): $queued of max $MaxQueued" -ForegroundColor Cyan

$log = [System.Collections.Generic.List[object]]::new()
function Add-Result($Obj, $Status, $Detail) {
    $log.Add([pscustomobject]@{ Object = $Obj; Status = $Status; Detail = $Detail })
    $c = @{ Started = 'Green'; Validated = 'Green'; Refused = 'Red'; WhatIf = 'Cyan'; Problem = 'Red' }[$Status]
    Write-Host ("  [{0}] {1}: {2}" -f $Status, $Obj, $Detail) -ForegroundColor $c
}

foreach ($r in $rows) {
    $group = "$($r.GroupConnected)" -eq 'True'
    if ($group) {
        $alias = "$($r.TargetGroupAlias)".Trim()
        $srcLeaf = ("$($r.Url)" -replace '/$', '') -split '/' | Select-Object -Last 1
        if (-not $alias) { Add-Result $r.Url 'Refused' 'TargetGroupAlias empty'; continue }
        if ($queued -ge $MaxQueued) { Add-Result $r.Url 'Refused' "Queue cap $MaxQueued reached"; continue }
        $p = @{ SourceGroupAlias = $srcLeaf; TargetGroupAlias = $alias; TargetCrossTenantHostUrl = $TargetCrossTenantHostUrl; ErrorAction = 'Stop' }
        if ($ValidationOnly) { $p.ValidationOnly = $true }
        if ($PSCmdlet.ShouldProcess("$srcLeaf -> $alias", 'Start-SPOCrossTenantGroupContentMove')) {
            try { $res = Start-SPOCrossTenantGroupContentMove @p; $queued++; Add-Result $r.Url $(if ($ValidationOnly) { 'Validated' } else { 'Started' }) "$res" }
            catch { Add-Result $r.Url 'Problem' $_.Exception.Message }
        }
        else { Add-Result $r.Url 'WhatIf' "Would submit group move $srcLeaf -> $alias" }
    }
    else {
        $tgt = "$($r.TargetUrl)".Trim()
        if (-not $tgt) { Add-Result $r.Url 'Refused' 'TargetUrl empty'; continue }
        if ($queued -ge $MaxQueued) { Add-Result $r.Url 'Refused' "Queue cap $MaxQueued reached"; continue }
        $p = @{ SourceSiteUrl = $r.Url; TargetSiteUrl = $tgt; TargetCrossTenantHostUrl = $TargetCrossTenantHostUrl; ErrorAction = 'Stop' }
        if ($ValidationOnly) { $p.ValidationOnly = $true }
        if ($PSCmdlet.ShouldProcess("$($r.Url) -> $tgt", 'Start-SPOCrossTenantSiteContentMove')) {
            try { $res = Start-SPOCrossTenantSiteContentMove @p; $queued++; Add-Result $r.Url $(if ($ValidationOnly) { 'Validated' } else { 'Started' }) "$res" }
            catch { Add-Result $r.Url 'Problem' $_.Exception.Message }
        }
        else { Add-Result $r.Url 'WhatIf' "Would submit site move $($r.Url) -> $tgt" }
    }
}

$out = New-OutputFolder -Customer $Customer -Phase '07-SharePoint-Teams'
$log | Export-CsvSafe -Path (Join-Path $out 'SiteContentMoves.csv')
Write-Host "Report: $out" -ForegroundColor Cyan
