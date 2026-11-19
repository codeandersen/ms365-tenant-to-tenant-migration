#requires -Version 7.2
<#
.SYNOPSIS
    Read-only, offline: turns the 00-Assessment SharePoint/Teams inventory into a per-site
    migration plan CSV (native cross-tenant move, ShareGate, or manual).

.DESCRIPTION
    Reads SharePointSites.csv (columns Url, Owner, Title, Template, SiteId, StorageUsageGB,
    LastContentModifiedDate, LockState, SharingCapability, GroupId, IsTeamsConnected,
    IsTeamsChannelConnected, Status, FileCount, Source) and, when present, TeamsChannels.csv
    from the 00-Assessment attachments, and emits one row per site:

      Url, Title, Template, StorageUsageGB, LastContentModifiedDate, LockState,
      GroupConnected, TeamsConnected, ChannelSite (Private|Shared|''), TargetUrl (blank, fill in),
      TargetGroupAlias (blank, fill in for group-connected sites), Track, Notes

    Track suggestions: Native for supported site types when a target identity exists; ShareGate
    for anything the native feature doesn't cover; Manual for edge cases. Private/shared channel
    sites and sites over the native limits (5 TB / 1M items per site) are flagged - see the README
    for what the native feature does and doesn't move.

.PARAMETER InventoryPath
    Folder containing SharePointSites.csv (e.g. an Inventory_* attachments folder from
    00-Assessment). No tenant connection needed.

.PARAMETER TargetHost
    Optional target host prefix used to pre-fill TargetUrl for simple sites, e.g. 'fabrikam'.
    Produces https://<target>.sharepoint.com/sites/<leaf>. Still review every row.

.PARAMETER Customer
    Writes the plan CSV under customers/<Customer>/output/07-SharePoint-Teams/.

.EXAMPLE
    .\Get-SiteMigrationPlan.ps1 -InventoryPath .\customers\contoso\Inventory_contoso_source_x\attachments -TargetHost fabrikam -Customer contoso

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Sources:
      https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration
      https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration-step6
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InventoryPath,

    [string]$TargetHost,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force

$siteCsv = Join-Path $InventoryPath 'SharePointSites.csv'
if (-not (Test-Path $siteCsv)) { throw "SharePointSites.csv not found in $InventoryPath - run 00-Assessment first." }
$sites = @(Import-Csv $siteCsv)

# Channel memberships from TeamsChannels.csv when the assessment collected it.
$channelHosts = @{}
$teamsCsv = Join-Path $InventoryPath 'TeamsChannels.csv'
if (Test-Path $teamsCsv) {
    foreach ($c in Import-Csv $teamsCsv) {
        $mt = "$($c.MembershipType)"
        if ($mt -match 'private|shared') {
            foreach ($u in @("$($c.SharePointUrl)", "$($c.SiteUrl)", "$($c.FilesUrl)") | Where-Object { $_ }) {
                $channelHosts[$u.ToLower()] = $mt
            }
        }
    }
}

$plan = foreach ($s in $sites) {
    if (-not "$($s.Url)") { continue }
    $url = "$($s.Url)"
    $gb = 0.0; [void][double]::TryParse("$($s.StorageUsageGB)", [ref]$gb)
    $groupConnected = "$($s.GroupId)" -match '^[0-9a-fA-F-]{36}$' -and "$($s.GroupId)" -notmatch '^0+$'
    $teamsConnected = "$($s.IsTeamsConnected)" -eq 'True'
    $channelSite = $channelHosts[$url.ToLower()]
    if (-not $channelSite -and "$($s.IsTeamsChannelConnected)" -eq 'True') { $channelSite = 'Shared/Private (flag set)' }

    $track = 'Native'; $notes = [System.Collections.Generic.List[string]]::new()
    if ($channelSite) { $track = 'ShareGate'; $notes.Add("$channelSite channel site - the native move covers the group site; channel sites and channel structure are not moved by it") }
    if ($gb -gt 5120) { $track = 'ShareGate'; $notes.Add('over the native 5 TB per-site limit') }
    if ("$($s.LockState)" -and "$($s.LockState)" -notin 'Unlock', '') { $notes.Add("LockState $($s.LockState) - the native doc requires source sites to be read/write") }
    if ("$($s.Template)" -match '^SPS|PWA|SRCH|APPCATALOG|REDIRECT') { $track = 'Manual'; $notes.Add("template $($s.Template) - verify coverage; likely not a content move") }
    if ($url -match '-my\.sharepoint\.com/personal/') { $track = 'OneDrive'; $notes.Add('personal site - handled by the Orchestrator ODSP workload') }
    if ("$($s.Status)" -match 'NotFound|Deleted') { $notes.Add("Status $($s.Status)") }

    $leaf = ($url -replace '/$', '') -split '/' | Select-Object -Last 1
    $tgt = ''
    if ($TargetHost -and $track -eq 'Native' -and $url -match '/(sites|teams)/') {
        $tgt = "https://$TargetHost.sharepoint.com/sites/$leaf"
    }

    [pscustomobject]@{
        Url                     = $url
        Title                   = $s.Title
        Template                = $s.Template
        StorageUsageGB          = $gb
        LastContentModifiedDate = $s.LastContentModifiedDate
        LockState               = $s.LockState
        GroupConnected          = $groupConnected
        TeamsConnected          = $teamsConnected
        ChannelSite             = $(if ($channelSite) { $channelSite } else { '' })
        TargetUrl               = $tgt
        TargetGroupAlias        = ''
        Track                   = $track
        Notes                   = ($notes -join '; ')
    }
}

$plan | Group-Object Track | ForEach-Object { Write-Host ("{0,-10} {1}" -f $_.Name, $_.Count) -ForegroundColor Cyan }
$out = New-OutputFolder -Customer $Customer -Phase '07-SharePoint-Teams'
$file = Join-Path $out 'SiteMigrationPlan.csv'
$plan | Export-CsvSafe -Path $file
Write-Host "Plan written to $file - review TargetUrl/TargetGroupAlias/Track before use." -ForegroundColor Green
