<#
.SYNOPSIS
    Builds a migration-readiness report (Readiness.md) from an inventory folder.

.DESCRIPTION
    Offline and read-only. Reads the CSV attachments produced by
    Collect-TenantInventory.ps1 and writes a markdown report with:
      1. Summary counts per workload.
      2. A recommended Microsoft migration tool per workload (method table).
      3. Required migration licences and target-licence baseline.
      4. Blockers that must be addressed before migration.
      5. Items that need a decision or a rebuild (no Microsoft tool moves them).
      6. What this report cannot see ("not inventoried").

    If a rule needs a CSV or column that the inventory did not collect, the rule
    reports "not inventoried" - it never guesses.

    Sources: https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-1-overview
             https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-mailbox-migration
             https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration
             https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration

.PARAMETER InventoryPath
    Folder produced by Collect-TenantInventory.ps1 (contains attachments\).

.PARAMETER DeviceStrategy
    Project device strategy: NewDevices (users get new PCs registered in the target
    Autopilot - phase 10 track), ExistingDevices (current PCs must move - open method
    decision, not scripted), or Unknown (default - report shows both implications and
    asks for the decision). Record the decision in 01-Design/templates/Decision-Log.md.

.PARAMETER TargetInventoryPath
    Optional target-tenant inventory folder for domain-conflict and licence checks.

.PARAMETER OutFile
    Output markdown path. Default: <InventoryPath>\Readiness.md (UTF-8 BOM).

.EXAMPLE
    .\New-MigrationReadinessReport.ps1 -InventoryPath .\inventory\contoso-source

.EXAMPLE
    .\New-MigrationReadinessReport.ps1 -InventoryPath .\inventory\contoso-source -TargetInventoryPath .\inventory\fabrikam-target
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InventoryPath,

    [string]$TargetInventoryPath,

    [ValidateSet('NewDevices', 'ExistingDevices', 'Unknown')]
    [string]$DeviceStrategy = 'Unknown',

    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
# Refuse a repo-internal output path before reading anything
Assert-CustomerDataPath -Path $(if ($OutFile) { $OutFile } else { Join-Path $InventoryPath 'Readiness.md' })

$LearnOverview  = 'https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-1-overview'
$LearnMailbox   = 'https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-mailbox-migration'
$LearnOneDrive  = 'https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration'
$LearnSharePoint= 'https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration'
$RepoDocs       = 'https://github.com/codeandersen/ms365-tenant-to-tenant-migration/blob/main/docs'

$attach = Join-Path $InventoryPath 'attachments'
$notInventoried = [System.Collections.Generic.List[string]]::new()
$script:BlockerCount = 0

function Test-DisabledArchive($m) {
    # Get-Mailbox returns the all-zero GUID when there is no disabled archive.
    $d = "$($m.DisabledArchiveGuid)".Trim()
    [bool]($d -and $d -notmatch '^0{8}-0{4}-0{4}-0{4}-0{12}$' -and $d -ne "$($m.ArchiveGuid)")
}

function Import-AttCsv {
    param([string]$Name, [string]$Base = $attach)
    $p = Join-Path $Base $Name
    if (Test-Path $p) { return (,@(Import-Csv $p)) }
    return (,@())
}

function Test-CsvPresent {
    param([string]$Name, [string]$Base = $attach)
    return (Test-Path (Join-Path $Base $Name))
}

function Test-Collected {
    # CSV present, or the collector recorded the count metric (0 items -> no CSV is written)
    param([string]$Csv, [string]$Metric)
    if (Test-CsvPresent $Csv) { return $true }
    return [bool]($invSummary -and $invSummary.PSObject.Properties[$Metric])
}

function ConvertTo-Num {
    param([object]$Value)
    if ($null -eq $Value -or "$Value" -eq '') { return 0 }
    $n = 0.0
    if ([double]::TryParse("$Value".Replace(',', '.'), [System.Globalization.NumberStyles]::Any,
            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { return $n }
    return 0
}

function Format-Table {
    param([object[]]$Rows, [string[]]$Columns)
    if ($Rows.Count -eq 0) { return '_None._' }
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine('| ' + ($Columns -join ' | ') + ' |')
    $null = $sb.AppendLine('|' + ('---|' * $Columns.Count))
    foreach ($r in $Rows) {
        $cells = foreach ($c in $Columns) { ("$($r.$c)" -replace '\|', '\|') }
        $null = $sb.AppendLine('| ' + ($cells -join ' | ') + ' |')
    }
    return $sb.ToString().TrimEnd()
}

function Measure-GbSum {
    param([object[]]$Rows, [string]$Col)
    $s = 0.0
    foreach ($x in $Rows) { $s += ConvertTo-Num $x.$Col }
    return $s
}

function Get-Top {
    param([object[]]$Rows, [string]$ItemCol, [string]$DetailCol, [int]$Take = 10)
    $sel = @($Rows | Select-Object -First $Take | ForEach-Object {
        $o = [ordered]@{ Item = "$($_.$ItemCol)" }
        if ($DetailCol) { $o.Detail = "$($_.$DetailCol)" }
        [pscustomobject]$o
    })
    $cols = if ($DetailCol) { @('Item', 'Detail') } else { @('Item') }
    $s = Format-Table $sel $cols
    if ($Rows.Count -gt $Take) { $s += "`n`n_...and $($Rows.Count - $Take) more._" }
    return $s
}

# --- Load inventory -----------------------------------------------------------

$mailboxes    = Import-AttCsv 'Mailboxes.csv'
$mbxStats     = Import-AttCsv 'MailboxStatistics.csv'
$oneDrives    = Import-AttCsv 'OneDrive.csv'
$spSites      = Import-AttCsv 'SharePointSites.csv'
$teams        = Import-AttCsv 'Teams.csv'
$teamsChan    = Import-AttCsv 'TeamsChannels.csv'
$groups       = Import-AttCsv 'Groups.csv'
$users        = Import-AttCsv 'Users.csv'
$licenses     = Import-AttCsv 'Licenses.csv'
$servicePlans = Import-AttCsv 'LicenseServicePlans.csv'
$pfMbx        = Import-AttCsv 'PublicFolderMailboxes.csv'
$bookings     = Import-AttCsv 'BookingsMailboxes.csv'
$customerKey  = Import-AttCsv 'CustomerKey.csv'
$labels       = Import-AttCsv 'SensitivityLabels.csv'
$mbxPerms     = Import-AttCsv 'MailboxPermissions.csv'
$sendAs       = Import-AttCsv 'SendAsPermissions.csv'
$devices      = Import-AttCsv 'EntraDevices.csv'
$intuneDevs   = Import-AttCsv 'IntuneDevices.csv'
$phoneUsers   = Import-AttCsv 'TeamsPhoneUsers.csv'
$dg           = Import-AttCsv 'DistributionGroups.csv'
$contacts     = Import-AttCsv 'MailContacts.csv'
$mailUsers    = Import-AttCsv 'MailUsers.csv'
$dlp          = Import-AttCsv 'DlpPolicies.csv'
$compCases    = Import-AttCsv 'ComplianceCases.csv'
$trules       = Import-AttCsv 'TransportRules.csv'
$jrules       = Import-AttCsv 'JournalRules.csv'
$inConn       = Import-AttCsv 'InboundConnectors.csv'
$outConn      = Import-AttCsv 'OutboundConnectors.csv'
$appRegs      = Import-AttCsv 'AppRegistrations.csv'
$entApps      = Import-AttCsv 'EnterpriseApps.csv'
$caPolicies   = Import-AttCsv 'ConditionalAccess.csv'
if ($caPolicies.Count -eq 0) { $caPolicies = Import-AttCsv 'ConditionalAccessPolicies.csv' }  # older inventories
$namedLocs    = Import-AttCsv 'NamedLocations.csv'
$mfaRegs      = Import-AttCsv 'MfaRegistration.csv'
$autopilot    = Import-AttCsv 'AutopilotDevices.csv'
$extUsers     = Import-AttCsv 'ExternalUsers.csv'
$appSignIns   = Import-AttCsv 'AppSignInActivity.csv'
$appPerms     = Import-AttCsv 'AppPermissions.csv'
$ppEnvs       = Import-AttCsv 'PowerPlatformEnvironments.csv'
$ppApps       = Import-AttCsv 'PowerApps.csv'
$ppFlows      = Import-AttCsv 'PowerAutomateFlows.csv'
$ppConnectors = Import-AttCsv 'PowerPlatformConnectors.csv'
$ppDlp        = Import-AttCsv 'PowerPlatformDlpPolicies.csv'
$pbiWs        = Import-AttCsv 'PowerBIWorkspaces.csv'
$teamsCustom  = Import-AttCsv 'TeamsCustomApps.csv'
$teamsInst    = Import-AttCsv 'TeamsInstalledApps.csv'
$plannerPlans = Import-AttCsv 'PlannerPlans.csv'
$outlookAddins= Import-AttCsv 'OutlookAddins.csv'
$spoAppCat    = Import-AttCsv 'SharePointAppCatalog.csv'

$invSummary = $null
$invFailed  = $null
$sumPath = Join-Path $InventoryPath 'summary.json'
if (Test-Path $sumPath) {
    try {
        $invJson = Get-Content $sumPath -Raw | ConvertFrom-Json
        if ($invJson.PSObject.Properties['metrics'])        { $invSummary = $invJson.metrics }
        if ($invJson.PSObject.Properties['failedSections']) { $invFailed  = $invJson.failedSections }
    } catch {}
}

$userMbx  = @($mailboxes | Where-Object { $_.RecipientTypeDetails -eq 'UserMailbox' })
$sharedMbx= @($mailboxes | Where-Object { $_.RecipientTypeDetails -in 'SharedMailbox', 'RoomMailbox', 'EquipmentMailbox' })
$sharedGB = Measure-GbSum $sharedMbx 'TotalItemSizeGB'
$userGB   = Measure-GbSum $userMbx 'TotalItemSizeGB'
$odGB     = Measure-GbSum $oneDrives 'StorageUsageGB'
$spGB     = Measure-GbSum $spSites 'StorageUsageGB'

# OneDrives whose owner has no user mailbox in scope -> standalone OneDrive migration
$userMbxUpn = @{}
foreach ($m in $userMbx) { $userMbxUpn[$m.UserPrincipalName.ToLower()] = $true }
$standaloneOd = @($oneDrives | Where-Object { -not $userMbxUpn.ContainsKey(("$($_.Owner)").ToLower()) })

$m365Groups = @($groups | Where-Object { $_.GroupType -match 'Microsoft 365|Unified' })
$guests     = @($users | Where-Object { $_.IsGuest -eq 'True' -or $_.UserType -eq 'Guest' })
$privCh     = Measure-GbSum $teams 'PrivateChannels'
$sharedCh   = Measure-GbSum $teams 'SharedChannels'
# Fall back to TeamsChannels.csv when Teams.csv lacks the per-team channel counts
if (($privCh + $sharedCh) -eq 0 -and $teamsChan.Count -gt 0) {
    $privCh   = @($teamsChan | Where-Object { $_.MembershipType -eq 'private' }).Count
    $sharedCh = @($teamsChan | Where-Object { $_.MembershipType -eq 'shared' }).Count
}
$pwaSites   = @($spSites | Where-Object { $_.Template -match '^(PWA#0|PROJECTSITE)' })

$target = $null
if ($TargetInventoryPath) {
    $tAttach = Join-Path $TargetInventoryPath 'attachments'
    $target = [pscustomobject]@{
        Licenses  = Import-AttCsv 'Licenses.csv' -Base $tAttach
        Domains   = Import-AttCsv 'AcceptedDomains.csv' -Base $tAttach
        OneDrives = Import-AttCsv 'OneDrive.csv' -Base $tAttach
        Sites     = Import-AttCsv 'SharePointSites.csv' -Base $tAttach
        Ca        = Import-AttCsv 'ConditionalAccess.csv' -Base $tAttach
        NamedLocs = Import-AttCsv 'NamedLocations.csv' -Base $tAttach
        AuthMethods = Import-AttCsv 'AuthMethodsPolicy.csv' -Base $tAttach
        Attach    = $tAttach
    }
    $tSum = Join-Path $TargetInventoryPath 'summary.json'
    if (Test-Path $tSum) {
        try { $target | Add-Member -NotePropertyName Metrics -NotePropertyValue ((Get-Content $tSum -Raw | ConvertFrom-Json).metrics) } catch {}
    }
}

# --- Build report --------------------------------------------------------------

$r = [System.Text.StringBuilder]::new()
$null = $r.AppendLine('# Migration readiness report')
$null = $r.AppendLine('')
$null = $r.AppendLine("Source inventory: ``$InventoryPath``")
if ($TargetInventoryPath) { $null = $r.AppendLine("Target inventory: ``$TargetInventoryPath``") }
$null = $r.AppendLine('')
$null = $r.AppendLine("Rules below quote Microsoft Learn ([Learn]) or are marked [Playbook assumption - verify in pilot] / [General Exchange Online licensing]. See [Migration-Method-Guide.md]($RepoDocs/Migration-Method-Guide.md) and [What-Doesnt-Move.md]($RepoDocs/What-Doesnt-Move.md).")
$null = $r.AppendLine('')

# 1. Summary ------------------------------------------------------------------

$null = $r.AppendLine('## 1. Summary')
$null = $r.AppendLine('')
$sumRows = @(
    [pscustomobject]@{ Workload = 'User mailboxes';              Count = $userMbx.Count;    'Size (GB)' = [math]::Round($userGB, 1) }
    [pscustomobject]@{ Workload = 'Archive-enabled mailboxes';   Count = @($mailboxes | Where-Object { $_.ArchiveStatus -eq 'Active' }).Count; 'Size (GB)' = [math]::Round((Measure-GbSum $mbxStats 'ArchiveItemSizeGB'), 1) }
    [pscustomobject]@{ Workload = 'Shared/room/equipment mailboxes'; Count = $sharedMbx.Count; 'Size (GB)' = [math]::Round($sharedGB, 1) }
    [pscustomobject]@{ Workload = 'Public folder mailboxes';     Count = $pfMbx.Count;      'Size (GB)' = '' }
    [pscustomobject]@{ Workload = 'Bookings mailboxes';          Count = $bookings.Count;   'Size (GB)' = '' }
    [pscustomobject]@{ Workload = 'OneDrive sites';              Count = $oneDrives.Count;  'Size (GB)' = [math]::Round($odGB, 1) }
    [pscustomobject]@{ Workload = 'SharePoint sites (non-personal)'; Count = $spSites.Count; 'Size (GB)' = [math]::Round($spGB, 1) }
    [pscustomobject]@{ Workload = 'Teams teams';                 Count = $teams.Count;      'Size (GB)' = '' }
    [pscustomobject]@{ Workload = 'Private / shared channels';   Count = "$([int]$privCh) / $([int]$sharedCh)"; 'Size (GB)' = '' }
    [pscustomobject]@{ Workload = 'Microsoft 365 groups';        Count = $m365Groups.Count; 'Size (GB)' = '' }
    [pscustomobject]@{ Workload = 'Guests';                      Count = $guests.Count;     'Size (GB)' = '' }
    [pscustomobject]@{ Workload = 'Devices (Entra / Intune)';    Count = "$($devices.Count) / $($intuneDevs.Count)"; 'Size (GB)' = '' }
)
$null = $r.AppendLine((Format-Table $sumRows @('Workload', 'Count', 'Size (GB)')))
$null = $r.AppendLine('')

if ($invSummary -and $invSummary.PSObject.Properties['spoDataSource'] -and $invSummary.spoDataSource -eq 'Graph-fallback') {
    $null = $r.AppendLine('> **Data quality:** OneDrive/SharePoint came from the Graph usage-report fallback (SharePoint admin access was unavailable). Site counts can be lower than the true site list - the usage report omits sites with no recent activity - and SPO-only fields (quota, lock state, sharing capability, tenant settings, external users) are empty. Re-run the inventory with a SharePoint administrator account for the full picture.')
    $null = $r.AppendLine('')
    $notInventoried.Add('SharePoint tenant settings and external users (requires SharePoint admin access - Graph fallback was used)')
}
if ($invFailed -and $invFailed.PSObject.Properties['SharePoint'] -and $spSites.Count -eq 0) {
    $notInventoried.Add("SharePoint sites (SharePointSites.csv) - collection failed: $($invFailed.SharePoint)")
}
if ($invFailed -and $invFailed.PSObject.Properties['OneDrive'] -and $oneDrives.Count -eq 0) {
    $notInventoried.Add("OneDrive sites (OneDrive.csv) - collection failed: $($invFailed.OneDrive)")
}

# 2. Archive mailboxes ----------------------------------------------------------

$archColsPresent = $mailboxes.Count -gt 0 -and
    ($mailboxes[0].PSObject.Properties.Name -contains 'AutoExpandingArchiveEnabled') -and
    ($mailboxes[0].PSObject.Properties.Name -contains 'AuxArchiveCount') -and
    ($mailboxes[0].PSObject.Properties.Name -contains 'DisabledArchiveGuid')
$archStatsMap = @{}
foreach ($s in $mbxStats) { $archStatsMap[$s.UserPrincipalName] = $s }

$archiveRows = [System.Collections.Generic.List[object]]::new()
$archiveBlocked = [System.Collections.Generic.List[object]]::new()
if ($mailboxes.Count -gt 0 -and $archColsPresent) {
    foreach ($m in $mailboxes) {
        $hasArch    = $m.ArchiveStatus -eq 'Active'
        $autoExp    = $m.AutoExpandingArchiveEnabled -eq 'True'
        $aux        = [int](ConvertTo-Num $m.AuxArchiveCount)
        $disabled   = Test-DisabledArchive $m
        if (-not ($hasArch -or $autoExp -or $aux -gt 0 -or $disabled)) { continue }
        $st = $archStatsMap[$m.UserPrincipalName]
        $archGB = if ($st) { ConvertTo-Num $st.ArchiveItemSizeGB } else { 0 }
        $archItems = if ($st) { "$($st.ArchiveItemCount)" } else { '' }
        $isShared = $m.RecipientTypeDetails -in 'SharedMailbox', 'RoomMailbox', 'EquipmentMailbox'
        $path = if ($isShared) { 'Cross-tenant mailbox migration' } else { 'Orchestrator' }
        $comes = 'Yes'
        $reason = ''
        if ($m.HasAnyHold -eq 'True') {
            $comes = 'No - blocked'; $reason = 'On hold - see section 5 blockers'
        } elseif ($aux -gt 12) {
            $comes = 'No - blocked'; $reason = "$aux auxiliary archives > max 12"
        } elseif ($disabled) {
            $comes = 'No - blocked'; $reason = 'Disabled/demoted archive present - remove it (Set-Mailbox -RemoveDisabledArchive) or re-enable it and stamp ArchiveGuid on the target MailUser'
        } elseif ($autoExp) {
            $comes = 'Yes - action needed'
            $reason = 'Auto-expanding archive - submit early and make sure it does not expand during the move (move fails if a new aux archive is created mid-move)'
        } elseif ($isShared -and $hasArch) {
            $comes = 'Yes - action needed'
            $reason = 'Shared/resource mailbox archive - needs Exchange Online Plan 2 or Plan 1 + Exchange Online Archiving in the target'
        } elseif ($aux -gt 0) {
            $comes = 'Yes - action needed'
            $reason = "$aux auxiliary archive(s) - all must be in scope when the batch starts (AuxArchiveNotFoundInTargetRecipient)"
        } elseif ($archGB -ge 100) {
            $comes = 'Yes - action needed'
            $reason = "Archive is $archGB GB - verify the target archive quota (default is 100 GB without auto-expanding) [Playbook assumption]"
        }
        if ($comes -eq 'Yes' -and -not $isShared) { $comes = 'Yes (Orchestrator - inferred, confirm in pilot)' }
        $row = [pscustomobject]@{
            Mailbox        = $m.UserPrincipalName
            Type           = $m.RecipientTypeDetails
            'Archive GB'   = $archGB
            Items          = $archItems
            'Auto-expanding' = if ($autoExp) { 'Yes' } else { '' }
            'Aux archives' = $aux
            Path           = $path
            'Comes along?' = $comes
            Reason         = $reason
        }
        $archiveRows.Add($row)
        if ($comes -like 'No*') { $archiveBlocked.Add($row) }
    }
}

$null = $r.AppendLine('## 2. Archive mailboxes')
$null = $r.AppendLine('')
if (-not (Test-CsvPresent 'Mailboxes.csv') -or -not $archColsPresent) {
    $null = $r.AppendLine('**Unknown - not inventoried.** The archive columns (AutoExpandingArchiveEnabled, DisabledArchiveGuid, ArchiveQuota, AuxArchiveCount) are not in this inventory - re-run Collect-TenantInventory.ps1.')
    $notInventoried.Add('Archive details (AutoExpandingArchiveEnabled/DisabledArchiveGuid/AuxArchiveCount in Mailboxes.csv)')
} else {
    $byType = @($archiveRows | Group-Object Type | ForEach-Object { "$($_.Name): $($_.Count)" })
    $archTotal = Measure-GbSum $archiveRows 'Archive GB'
    $autoExpN = @($archiveRows | Where-Object { $_.'Auto-expanding' -eq 'Yes' }).Count
    $auxN = @($archiveRows | Where-Object { $_.'Aux archives' -gt 0 }).Count
    $disN = @($mailboxes | Where-Object { Test-DisabledArchive $_ }).Count
    $null = $r.AppendLine("- Mailboxes with an archive/aux/disabled archive: **$($archiveRows.Count)** ($($byType -join ', ')) - $([math]::Round($archTotal,1)) GB total")
    $null = $r.AppendLine("- Auto-expanding archives: **$autoExpN** - mailboxes with auxiliary archives: **$auxN** - disabled/demoted archives: **$disN**")
    $null = $r.AppendLine("- ArchiveGUID must be stamped on the target object when the source is archive-enabled, or the move does not proceed. [Learn]($LearnMailbox)")
    $null = $r.AppendLine('')
    $toShow = @($archiveRows | Sort-Object { -(ConvertTo-Num $_.'Archive GB') })
    $cutNote = ''
    if ($toShow.Count -gt 20) {
        $blockedSet = @{}; foreach ($b in $archiveBlocked) { $blockedSet[$b.Mailbox] = $true }
        $top20 = @($toShow | Select-Object -First 20)
        $rest = @($archiveBlocked | Where-Object { -not $blockedSet.ContainsKey($_.Mailbox) -or $top20.Mailbox -notcontains $_.Mailbox })
        $rest = @($archiveBlocked | Where-Object { $top20.Mailbox -notcontains $_.Mailbox })
        $toShow = @($top20) + @($rest)
        $cutNote = "_Showing the 20 largest archives plus every blocked mailbox ($($archiveRows.Count) total)._`n`n"
    }
    if ($toShow.Count -gt 0) {
        $null = $r.AppendLine($cutNote + (Format-Table $toShow @('Mailbox','Type','Archive GB','Items','Auto-expanding','Aux archives','Path','Comes along?','Reason')))
    } else {
        $null = $r.AppendLine('_No archive mailboxes found._')
    }
}
$null = $r.AppendLine('')

# 3. Recommended migration method ----------------------------------------------

$null = $r.AppendLine('## 3. Recommended migration method per workload')
$null = $r.AppendLine('')
$methodRows = @(
    [pscustomobject]@{
        Workload = "User mailboxes + their OneDrive + Teams chats and meetings ($($userMbx.Count) mailboxes)"
        Tool = 'Cross-tenant migration orchestrator'
        Why = 'Microsoft recommends migrating all workloads in one batch; max 100 users per batch; CTIM required. [Learn]'
        Source = $LearnOverview
    }
    [pscustomobject]@{
        Workload = "Shared, room and equipment mailboxes ($($sharedMbx.Count))"
        Tool = 'Cross-tenant mailbox migration (New-MigrationBatch)'
        Why = 'Not in Orchestrator scope. [Learn]'
        Source = $LearnMailbox
    }
    [pscustomobject]@{
        Workload = "OneDrive sites with no migrating user mailbox ($($standaloneOd.Count))"
        Tool = 'Cross-tenant OneDrive migration (standalone)'
        Why = 'The orchestrator/CTIM path requires a source mailbox. [Learn]'
        Source = $LearnOneDrive
    }
)
$noTeamsLic = @()
if ($servicePlans.Count -gt 0 -and $users.Count -gt 0) {
    $teamsSkus = @($servicePlans | Where-Object { $_.ServicePlanName -match '^(TEAMS|MCO)' -and $_.ProvisioningStatus -eq 'Success' } | ForEach-Object SkuPartNumber | Sort-Object -Unique)
    if ($teamsSkus.Count -gt 0) {
        # users whose AssignedLicenses contains no Teams-capable SKU
        $noTeamsLic = @($users | Where-Object { $u = $_; $u.UserType -ne 'Guest' -and $u.AssignedLicenses -and -not ($teamsSkus | Where-Object { $u.AssignedLicenses -match [regex]::Escape($_) }) })
        if ($noTeamsLic.Count -gt 0) {
            $methodRows += [pscustomobject]@{
                Workload = "Mailbox users with no Teams service plan ($($noTeamsLic.Count))"
                Tool = 'Orchestrator, Exchange + ODSP only'
                Why = 'Teams meetings migration requires Teams + Exchange on both sides; flag these users. [Learn]'
                Source = $LearnOverview
            }
        }
    }
}
$methodRows += [pscustomobject]@{
    Workload = "SharePoint sites incl. Teams-connected ($($spSites.Count) sites, $([math]::Round($spGB,1)) GB)"
    Tool = 'Cross-tenant SharePoint migration - or third-party (decision open)'
    Why = 'Requires EA enrolment and Cross-Tenant Shared Data Migration licences per 100 GB moved. [Learn]'
    Source = $LearnSharePoint
}
$methodRows += [pscustomobject]@{
    Workload = 'Teams/channels structure, channel messages, Planner, apps'
    Tool = 'Recreate manually or third-party'
    Why = 'No Microsoft cross-tenant tool moves teams, channel posts, tabs or apps. [Learn]'
    Source = $LearnSharePoint
}
if ($pfMbx.Count -gt 0) {
    $methodRows += [pscustomobject]@{
        Workload = "Public folders ($($pfMbx.Count) mailboxes)"
        Tool = 'Not covered - third-party or PST'
        Why = 'The four cross-tenant tools do not migrate public folders. [Learn]'
        Source = $LearnMailbox
    }
}
$null = $r.AppendLine((Format-Table $methodRows @('Workload', 'Tool', 'Why', 'Source')))
$null = $r.AppendLine('')

# 4. Devices ----------------------------------------------------------------------

$joinCounts = @{}
foreach ($d in $devices) { $k = if ($d.JoinType) { $d.JoinType } else { 'unknown' }; $joinCounts[$k] = @($joinCounts[$k]) + 1 }
$entraJoined  = @($devices | Where-Object { $_.JoinType -eq 'Entra joined' }).Count
$hybridJoined = @($devices | Where-Object { $_.JoinType -eq 'Hybrid Entra joined' }).Count
$registered   = @($devices | Where-Object { $_.JoinType -eq 'Entra registered' }).Count
$mobileDev    = @($devices | Where-Object { "$($_.OperatingSystem)" -match 'Android|iOS|iPadOS' }).Count
$staleDev     = @()
if ($devices.Count -gt 0 -and ($devices[0].PSObject.Properties.Name -contains 'ApproximateLastSignInDateTime')) {
    $staleDev = @($devices | Where-Object {
        $v = "$($_.ApproximateLastSignInDateTime)"
        $v -and ([datetime]::Parse($v, [cultureinfo]::InvariantCulture) -lt [datetime]::UtcNow.AddDays(-90))
    })
}

$null = $r.AppendLine('## 4. Devices')
$null = $r.AppendLine('')
$null = $r.AppendLine("Device strategy: **$DeviceStrategy** - set with `-DeviceStrategy NewDevices|ExistingDevices` once decided (see `01-Design/templates/Decision-Log.md`, row 'Device strategy').")
$null = $r.AppendLine('')
if ($devices.Count -gt 0) {
    $devRows = @(
        [pscustomobject]@{ Metric = 'Entra devices total';                 Count = $devices.Count }
        [pscustomobject]@{ Metric = 'Entra joined';                        Count = $entraJoined }
        [pscustomobject]@{ Metric = 'Hybrid Entra joined';                 Count = $hybridJoined }
        [pscustomobject]@{ Metric = 'Entra registered (incl. mobile/BYOD)'; Count = $registered }
        [pscustomobject]@{ Metric = 'Intune-managed';                      Count = $intuneDevs.Count }
        [pscustomobject]@{ Metric = 'Autopilot-registered';                Count = $autopilot.Count }
        [pscustomobject]@{ Metric = 'Mobile OS (Android/iOS)';             Count = $mobileDev }
        [pscustomobject]@{ Metric = 'Stale (>90 days no sign-in)';         Count = $staleDev.Count }
    )
    $null = $r.AppendLine((Format-Table $devRows @('Metric', 'Count')))
} else {
    $null = $r.AppendLine('_Entra devices not inventoried (EntraDevices.csv)._')
    $notInventoried.Add('Device join types and Autopilot registrations (EntraDevices/AutopilotDevices.csv)')
}
$null = $r.AppendLine('')

switch ($DeviceStrategy) {
    'NewDevices' {
        $null = $r.AppendLine('**Track 1 - new devices (phase 10 scripts apply).**')
        $null = $r.AppendLine('')
        $null = $r.AppendLine("- Old PCs are retired per phase 10: data check -> wipe -> delete Intune, Autopilot and Entra objects - the **Entra object is deleted last** because BitLocker recovery keys are escrowed on it.")
        $null = $r.AppendLine("- $($devices.Count) source devices to retire; $mobileDev mobile devices: users remove the old work account and re-enrol in the target.")
        $null = $r.AppendLine('- Target to-dos (not blockers): Autopilot profile + Enrollment Status Page, enrollment restrictions, compliance policies, and the hardware vendor/reseller registering each new PC hash in the **target** Autopilot before handout.')
        $null = $r.AppendLine('')
    }
    'ExistingDevices' {
        $null = $r.AppendLine('**Track 2 - existing devices must move (not scripted - open method decision).**')
        $null = $r.AppendLine('')
        $null = $r.AppendLine('What must be decided/addressed before batches:')
        $null = $r.AppendLine('')
        $null = $r.AppendLine("- **$entraJoined Entra-joined devices** must leave the source tenant - a Windows device can only be Entra joined to one tenant.")
        $null = $r.AppendLine("- **$hybridJoined hybrid-joined devices** are not moved by the tenant change [Playbook assumption - verify].")
        $null = $r.AppendLine("- **$($autopilot.Count) Autopilot registrations** must be deregistered in the source before the hardware hash can be registered in the target [Playbook assumption - verify].")
        $null = $r.AppendLine('- BitLocker recovery keys are escrowed in the **source** - export them (phase 10 `Get-BitLockerKeyReport`) before anything is removed.')
        $null = $r.AppendLine('- A device reset/wipe loses data outside OneDrive; profile migration is a separate problem.')
        $null = $r.AppendLine('')
        $null = $r.AppendLine('Method is an open decision (record in `Decision-Log.md`): Microsoft-native (deregister Autopilot + register hash in target + reset/re-enrol) vs third-party/in-place rejoin. The playbook does not script this track.')
        $null = $r.AppendLine('')
    }
    default {
        $null = $r.AppendLine("- **NewDevices**: old PCs retired per phase 10; new PCs pre-registered in the target Autopilot by the vendor.")
        $null = $r.AppendLine("- **ExistingDevices**: $entraJoined Entra-joined + $hybridJoined hybrid-joined + $($autopilot.Count) Autopilot devices must be moved - method is an open decision, not scripted.")
        $null = $r.AppendLine('')
        $null = $r.AppendLine('**Decide the device strategy (Decision-Log row ''Device strategy'') and re-run with `-DeviceStrategy`.**')
        $null = $r.AppendLine('')
    }
}

# 5. Sign-in and access -----------------------------------------------------------

$null = $r.AppendLine('## 5. Sign-in and access (Conditional Access, MFA)')
$null = $r.AppendLine('')
$mfaRegCount = @($mfaRegs | Where-Object { $_.IsMfaRegistered -eq 'True' }).Count
$null = $r.AppendLine("- **MFA registration does not move between tenants** - every migrated user registers MFA in the target at first sign-in (tenant-specific registration). Source scale: **$mfaRegCount** user(s) registered for MFA.")
if ($target -and $target.AuthMethods.Count -gt 0) {
    $tap = @($target.AuthMethods | Where-Object { $_.MethodType -match 'temporaryAccessPass' -and $_.State -eq 'enabled' })
    if ($tap) {
        $null = $r.AppendLine('- Target allows **Temporary Access Pass** - recommend issuing a TAP per user for first sign-in/MFA onboarding.')
    } else {
        $null = $r.AppendLine('- Target does **not** allow Temporary Access Pass (or not inventoried) - MFA onboarding relies on the user registering methods at first sign-in; consider enabling TAP.')
    }
}
$null = $r.AppendLine('- Conditional Access policies, named locations and authentication-method settings are tenant configuration and do not migrate - recreate them in the target.')
$null = $r.AppendLine('')
$null = $r.AppendLine('**Source tenant**')
$null = $r.AppendLine('')
if ($namedLocs.Count -gt 0 -or $caPolicies.Count -gt 0) {
    $trusted = @($namedLocs | Where-Object { $_.IsTrusted -eq 'True' })
    $countries = @($namedLocs | Where-Object { $_.Type -eq 'country' })
    $caEnabled = @($caPolicies | Where-Object { $_.State -eq 'enabled' })
    $caReport  = @($caPolicies | Where-Object { $_.State -match 'report' })
    $null = $r.AppendLine("- Named locations: **$($namedLocs.Count)** ($($trusted.Count) trusted IP locations, $($countries.Count) country locations) - export for the target admin with `00-Assessment/Export-TrustedLocations.ps1`.")
    $null = $r.AppendLine("- Conditional Access policies: **$($caPolicies.Count)** ($($caEnabled.Count) enabled, $($caReport.Count) report-only) - recreate in the target after the trusted locations exist.")
    $null = $r.AppendLine('')
} else {
    $null = $r.AppendLine('- Named locations / CA policies not inventoried (or none).')
    $null = $r.AppendLine('')
}
$null = $r.AppendLine('**Target tenant**')
$null = $r.AppendLine('')
if ($target) {
    $secDef = if ($target.Metrics -and $null -ne $target.Metrics.securityDefaultsEnabled) { $target.Metrics.securityDefaultsEnabled } else { 'unknown' }
    $null = $r.AppendLine("- Security defaults enabled: **$secDef** (when enabled, CA policies are off - decide which model the target uses).")
    $tCaEnabled = @($target.Ca | Where-Object { $_.State -eq 'enabled' })
    if ($tCaEnabled.Count -gt 0) {
        $null = $r.AppendLine("- **$($tCaEnabled.Count) enabled CA policies** - likely impact on migrated users/devices:")
        $null = $r.AppendLine('')
        $impact = [ordered]@{
            'Require compliant or hybrid-joined device (blocks PCs/phones until enrolled in the target - critical for ExistingDevices, and for new PCs before the ESP completes)' =
                @($tCaEnabled | Where-Object { $_.GrantControls -match 'compliantDevice|domainJoinedDevice' })
            'Location/country conditions (needs the exported trusted locations in place first)' =
                @($tCaEnabled | Where-Object { "$($_.IncludeLocations)$($_.ExcludeLocations)" -match '\w' -or $_.ConditionsJson -match '"locations"' })
            'Require MFA / authentication strength (expected: users register MFA at first sign-in)' =
                @($tCaEnabled | Where-Object { $_.GrantControls -match 'mfa' -or "$($_.AuthenticationStrength)" })
            'Block legacy authentication (old clients/protocols will fail)' =
                @($tCaEnabled | Where-Object { $_.ClientAppTypes -match 'exchangeActiveSync|other' -and $_.GrantControls -match 'block' })
            'Require approved client app / app protection policy (mobile)' =
                @($tCaEnabled | Where-Object { $_.GrantControls -match 'approvedApplication|compliantApplication' })
            'Sign-in/user risk or session controls' =
                @($tCaEnabled | Where-Object { "$($_.ConditionsJson)" -match 'signInRiskLevels|userRiskLevels' -or "$($_.SessionControls)" -match '\w' })
        }
        $impactRows = foreach ($k in $impact.Keys) {
            if ($impact[$k].Count -gt 0) { [pscustomobject]@{ Impact = $k; Policies = (($impact[$k] | ForEach-Object DisplayName) -join ', ') } }
        }
        if ($impactRows) { $null = $r.AppendLine((Format-Table @($impactRows) @('Impact', 'Policies'))) }
    } else {
        $null = $r.AppendLine('- No enabled CA policies inventoried in the target.')
    }
    $null = $r.AppendLine('')
} else {
    $null = $r.AppendLine('- Target CA/named locations not inventoried - run `Collect-TenantInventory.ps1 -Role Target` and pass `-TargetInventoryPath`.')
    $null = $r.AppendLine('')
}

# 6. Licences -------------------------------------------------------------------

$null = $r.AppendLine('## 6. Licences')
$null = $r.AppendLine('')
$ctUserLic = $userMbx.Count + $sharedMbx.Count + $standaloneOd.Count
$sharedDataLic = if ($spGB -gt 0) { [math]::Ceiling($spGB / 100) } else { 0 }
$null = $r.AppendLine('### Migration licences')
$null = $r.AppendLine('')
$licRows = @(
    [pscustomobject]@{
        Licence = 'Cross-Tenant User Data Migration'
        Count = $ctUserLic
        Basis = "1 per migrating mailbox [Learn]: $($userMbx.Count) user mailbox(es) + $($sharedMbx.Count) shared/room/equipment mailbox(es) (confirm with Microsoft whether shared mailboxes consume this licence) + $($standaloneOd.Count) standalone OneDrive(s). One-time per migrated identity, purchased in source or target tenant."
    }
    [pscustomobject]@{
        Licence = 'Cross-Tenant Shared Data Migration'
        Count = $sharedDataLic
        Basis = "1 per 100 GB of SharePoint site data moved ($([math]::Round($spGB,1)) GB in scope, StorageUsageGB, 20% grace). Enterprise Agreement only. [Learn]"
    }
)
$null = $r.AppendLine((Format-Table $licRows @('Licence', 'Count', 'Basis')))
$null = $r.AppendLine('')
$null = $r.AppendLine('### Target user licences')
$null = $r.AppendLine('')
$null = $r.AppendLine('- Source and target users need Exchange Online and Teams during the migration (E3/E5 include both); target users need licences that include OneDrive. License only after the CTIM write step. [Learn](' + $LearnOverview + ')')
if ($licenses.Count -gt 0) {
    $null = $r.AppendLine('')
    $null = $r.AppendLine('Source SKU baseline (target purchase starts here):')
    $null = $r.AppendLine('')
    $null = $r.AppendLine((Format-Table @($licenses | Select-Object SkuPartNumber, ConsumedUnits, EnabledUnits) @('SkuPartNumber', 'ConsumedUnits', 'EnabledUnits')))
} else {
    $null = $r.AppendLine('- _Licenses.csv not inventoried - source SKU baseline unavailable._')
    $notInventoried.Add('Source SKU list (Licenses.csv)')
}
$null = $r.AppendLine('')

if ($servicePlans.Count -gt 0 -and $users.Count -gt 0) {
    $exoSkus   = @($servicePlans | Where-Object { $_.ServicePlanName -match '^EXCHANGE' -and $_.ProvisioningStatus -eq 'Success' } | ForEach-Object SkuPartNumber | Sort-Object -Unique)
    $spoSkus   = @($servicePlans | Where-Object { $_.ServicePlanName -match '^(SHAREPOINT|ONEDRIVE)' -and $_.ProvisioningStatus -eq 'Success' } | ForEach-Object SkuPartNumber | Sort-Object -Unique)
    $noExo = @($userMbx | Where-Object { $m = $_; $u = $users | Where-Object { $_.UserPrincipalName -eq $m.UserPrincipalName } | Select-Object -First 1; $u -and -not ($exoSkus | Where-Object { $u.AssignedLicenses -match [regex]::Escape($_) }) })
    $odMigUpn = @{}; foreach ($o in $oneDrives) { $odMigUpn[("$($o.Owner)").ToLower()] = $true }
    $noSpo = @($users | Where-Object { $u = $_; $odMigUpn.ContainsKey($u.UserPrincipalName.ToLower()) -and $u.AssignedLicenses -and -not ($spoSkus | Where-Object { $u.AssignedLicenses -match [regex]::Escape($_) }) })
    if ($noExo.Count -gt 0) { $null = $r.AppendLine("- **$($noExo.Count) users with a mailbox but no Exchange service plan**: " + (($noExo | Select-Object -First 10 | ForEach-Object UserPrincipalName) -join ', ')) }
    if ($noSpo.Count -gt 0) { $null = $r.AppendLine("- **$($noSpo.Count) OneDrive owners with no SharePoint/OneDrive service plan**: " + (($noSpo | Select-Object -First 10 | ForEach-Object UserPrincipalName) -join ', ')) }
    if ($noTeamsLic.Count -gt 0) { $null = $r.AppendLine("- **$($noTeamsLic.Count) users with no Teams service plan** (see method table).") }
} else {
    $notInventoried.Add('Per-user service plans (LicenseServicePlans.csv or AssignedLicenses)')
}

# Shared mailboxes needing a licence: Plan 2 for >50 GB; Plan 2 or Plan 1 + EOA for archive/Litigation Hold
$sharedLicUrl = 'https://learn.microsoft.com/en-us/microsoft-365/admin/email/about-shared-mailboxes'
$sharedNeedLic = @($sharedMbx | Where-Object {
    (ConvertTo-Num $_.TotalItemSizeGB) -gt 50 -or $_.ArchiveStatus -eq 'Active' -or $_.LitigationHoldEnabled -eq 'True'
})
if ($sharedNeedLic.Count -gt 0) {
    $null = $r.AppendLine("- **$($sharedNeedLic.Count) shared/resource mailboxes need an Exchange licence** [Learn]($sharedLicUrl): " + (($sharedNeedLic | Select-Object -First 10 | ForEach-Object PrimarySmtpAddress) -join ', '))
    $over50  = @($sharedNeedLic | Where-Object { (ConvertTo-Num $_.TotalItemSizeGB) -gt 50 })
    $archOrHold = @($sharedNeedLic | Where-Object { $_.ArchiveStatus -eq 'Active' -or $_.LitigationHoldEnabled -eq 'True' })
    if ($over50.Count -gt 0)     { $null = $r.AppendLine("  - $($over50.Count) over 50 GB - **Exchange Online Plan 2**") }
    if ($archOrHold.Count -gt 0) { $null = $r.AppendLine("  - $($archOrHold.Count) with an archive or Litigation Hold - **Plan 2 or Plan 1 + Exchange Online Archiving**") }
}
$null = $r.AppendLine('')

if ($target -and $target.Licenses.Count -gt 0) {
    $null = $r.AppendLine('### Target licence availability')
    $null = $r.AppendLine('')
    $need = @($licenses | ForEach-Object { [pscustomobject]@{ SkuPartNumber = $_.SkuPartNumber; Needed = [int](ConvertTo-Num $_.ConsumedUnits) } })
    $availRows = foreach ($n in $need) {
        $t = $target.Licenses | Where-Object { $_.SkuPartNumber -eq $n.SkuPartNumber } | Select-Object -First 1
        $free = if ($t) { [int](ConvertTo-Num $t.EnabledUnits) - [int](ConvertTo-Num $t.ConsumedUnits) } else { 0 }
        [pscustomobject]@{ SkuPartNumber = $n.SkuPartNumber; SourceNeed = $n.Needed; TargetAvailable = $free; Gap = [math]::Max(0, $n.Needed - $free) }
    }
    $null = $r.AppendLine((Format-Table $availRows @('SkuPartNumber', 'SourceNeed', 'TargetAvailable', 'Gap')))
    $null = $r.AppendLine('')
}

# 7. Blockers --------------------------------------------------------------------

$null = $r.AppendLine('## 7. Must be addressed before migration (blockers)')
$null = $r.AppendLine('')

function Add-Blocker {
    param([string]$Title, [int]$Count, [string]$Why, [string]$Action, [object[]]$Examples,
          [string]$ExampleCol, [string]$DetailCol)
    if ($Count -le 0) { return }
    $script:BlockerCount += $Count
    $null = $r.AppendLine("### $Title - $Count")
    $null = $r.AppendLine('')
    $null = $r.AppendLine("- Why: $Why")
    $null = $r.AppendLine("- Action: $Action")
    if ($Examples -and $Examples.Count -gt 0) {
        $null = $r.AppendLine('')
        $null = $r.AppendLine((Get-Top $Examples $ExampleCol $DetailCol 10))
    }
    $null = $r.AppendLine('')
}

$heldMbx = @($mailboxes | Where-Object { $_.HasAnyHold -eq 'True' })
Add-Blocker 'Mailboxes on hold' $heldMbx.Count `
    "Holds (Litigation, eDiscovery, retention, delay) block mailbox and OneDrive migration. [Learn]($LearnMailbox)" `
    'Remove or resolve the holds before the move (playbook 00/G2). Recreate holds in the target after migration.' `
    $heldMbx 'UserPrincipalName' 'HoldReasons'

if (-not (Test-CsvPresent 'Mailboxes.csv')) { $notInventoried.Add('Mailbox holds (Mailboxes.csv)') }
$notInventoried.Add('OneDrive holds - holds block OneDrive moves too but are not collected per site; check them before the move')

# Archive blockers from section 2 (aux > 12, disabled archive). Held archive
# mailboxes are already covered by 'Mailboxes on hold' above - not double-listed.
$archNonHoldBlocked = @($archiveBlocked | Where-Object { $_.Reason -notmatch 'On hold' })
if ($archNonHoldBlocked.Count -gt 0) {
    Add-Blocker 'Archive mailboxes that will fail the move' $archNonHoldBlocked.Count `
        "Auxiliary archives over 12, or a disabled/demoted archive on the mailbox, make the move fail. [Learn]($LearnMailbox)" `
        'Fix per mailbox (see section 2): reduce aux archives, or remove/re-enable the disabled archive and stamp ArchiveGuid on the target MailUser.' `
        $archNonHoldBlocked 'Mailbox' 'Reason'
}

Add-Blocker 'Customer Key enabled' $customerKey.Count `
    "Customer Key on the source blocks cross-tenant OneDrive/SharePoint moves. [Learn]($LearnOneDrive)" `
    'Disable/roll off Customer Key for the affected workloads before the move; plan re-keying in the target.' `
    $customerKey 'Service' 'State'

Add-Blocker 'Public folders' $pfMbx.Count `
    "Public folders are not migrated by any of the four cross-tenant tools. [Learn]($LearnMailbox)" `
    'Decide: third-party tool, PST export, or retire.' `
    $pfMbx 'DisplayName' 'PrimarySmtpAddress'

# Mailbox size vs quota (or 45 GB heuristic)
$nearQuota = @()
if ($mailboxes.Count -gt 0 -and ($mailboxes[0].PSObject.Properties.Name -contains 'ProhibitSendReceiveQuota')) {
    $nearQuota = @($mailboxes | Where-Object {
        $q = "$($_.ProhibitSendReceiveQuota)"
        $qm = [regex]::Match($q, '([\d.,]+)\s*GB')
        if ($qm.Success) {
            $quota = ConvertTo-Num $qm.Groups[1].Value
            $quota -gt 0 -and (ConvertTo-Num $_.TotalItemSizeGB) -ge ($quota * 0.9)
        } else { (ConvertTo-Num $_.TotalItemSizeGB) -gt 45 }
    })
    Add-Blocker 'Mailboxes near or over quota' $nearQuota.Count `
        "Mailbox within 90% of ProhibitSendReceiveQuota (or >45 GB where the quota could not be parsed - heuristic). [Playbook assumption]" `
        'Expand/reduce before the move so the target does not reject the mailbox.' `
        $nearQuota 'UserPrincipalName' 'ProhibitSendReceiveQuota'
} else {
    $notInventoried.Add('Mailbox quota usage (ProhibitSendReceiveQuota/TotalItemSizeGB)')
}

# aux archives: only "not inventoried" when the column was not collected
if (-not $archColsPresent) { $notInventoried.Add('Auxiliary archive count per mailbox (cross-tenant mailbox migration supports max 12)') }

$synced = @($users | Where-Object { $_.OnPremisesSyncEnabled -eq 'True' })
Add-Blocker 'Directory-synced users (hybrid)' $synced.Count `
    'Synced identities complicate cross-tenant moves - source objects must be un-synced or re-anchored. [Playbook assumption - verify in pilot]' `
    'Plan the sync cut-over (phase 03) before batches run.' `
    $synced 'UserPrincipalName' $null

$aposUsers = @($users | Where-Object { "$($_.UserPrincipalName)" -match "'" })
Add-Blocker "UserPrincipalName contains an apostrophe" $aposUsers.Count `
    "Cross-tenant OneDrive migration fails for users whose UPN or site URL contains an apostrophe. [Learn]($LearnOneDrive)" `
    'Change the UPN (and re-provision the OneDrive URL) in the source before the move, or migrate these OneDrives with a third-party tool.' `
    $aposUsers 'UserPrincipalName' $null

$bigOd = @($oneDrives | Where-Object { (ConvertTo-Num $_.StorageUsageGB) -gt 5000 })
Add-Blocker 'OneDrive sites over 5 TB' $bigOd.Count `
    "A OneDrive site cannot exceed 5 TB storage / 1 million items for the cross-tenant move. [Learn]($LearnOneDrive)" `
    'Reduce or split the data before the move. Item counts are not inventoried - check manually.' `
    $bigOd 'Url' 'StorageUsageGB'
$notInventoried.Add('OneDrive/SharePoint item counts (1 million item limit) and 400-character path lengths')

$bigSp = @($spSites | Where-Object { (ConvertTo-Num $_.StorageUsageGB) -gt 5000 })
Add-Blocker 'SharePoint sites over 5 TB' $bigSp.Count `
    "A site cannot exceed 5 TB / 1 million items for the cross-tenant move. [Learn]($LearnSharePoint)" `
    'Reduce or split the data before the move.' `
    $bigSp 'Url' 'StorageUsageGB'

$lockedSites = @($spSites | Where-Object { $_.LockState -in 'ReadOnly', 'NoAccess' })
Add-Blocker 'Read-only or locked SharePoint sites' $lockedSites.Count `
    "Read-only sites fail the cross-tenant site move. [Learn]($LearnSharePoint)" `
    'Unlock sites before the move.' `
    $lockedSites 'Url' 'LockState'

# Sensitivity labels with user-defined permissions
if ($labels.Count -gt 0 -and ($labels[0].PSObject.Properties.Name -contains 'EncryptionType' -or $labels[0].PSObject.Properties.Name -contains 'LabelActions')) {
    $udpLabels = @($labels | Where-Object {
        "$($_.EncryptionType)" -match 'UserDefined' -or "$($_.LabelActions)" -match '(?i)user.?defined|USER-INITIATED|DO_NOT_FORWARD'
    })
    Add-Blocker 'Sensitivity labels with user-defined permissions' $udpLabels.Count `
        "Files labelled with user-defined permissions block the SharePoint site move. [Learn]($LearnSharePoint)" `
        'Re-apply a supported label or remove the label before the move; re-label in the target.' `
        $udpLabels 'DisplayName' 'EncryptionType'
} elseif (-not (Test-CsvPresent 'SensitivityLabels.csv')) {
    $notInventoried.Add('Sensitivity labels with user-defined permissions (SensitivityLabels.csv)')
} else {
    $notInventoried.Add('Sensitivity-label encryption detail (EncryptionType/LabelActions columns empty)')
}

if ($target) {
    $srcDomains = Import-AttCsv 'AcceptedDomains.csv'
    if ($srcDomains.Count -gt 0 -and $target.Domains.Count -gt 0) {
        $tDom = @{}; foreach ($d in $target.Domains) { $tDom["$($d.DomainName)".ToLower()] = $true }
        $conflicts = @($srcDomains | Where-Object { $tDom.ContainsKey("$($_.DomainName)".ToLower()) -and $_.DomainName -notmatch 'onmicrosoft\.com$' })
        Add-Blocker 'Domain already verified in the target tenant' $conflicts.Count `
            "A custom domain cannot exist in both tenants at once - it must leave the source before verification in target. [Learn]($LearnOverview)" `
            'Plan the domain move window (playbook 09 - hypothesis).' `
            $conflicts 'DomainName' 'DomainType'
    }
    $preOd = @($target.OneDrives | Where-Object { $_.Url -match '/personal/' })
    Add-Blocker 'Pre-created OneDrive sites in target' $preOd.Count `
        "Pre-created target sites can collide with the incoming move. [Learn]($LearnOneDrive)" `
        'Check whether any incoming user already has a OneDrive in the target; delete or plan around it (phase 03 check).' `
        $preOd 'Url' $null
}

# Inactive / soft-deleted mailboxes - not moved by cross-tenant tools
$inactiveMbxB = Import-AttCsv 'InactiveMailboxes.csv'
Add-Blocker 'Inactive mailboxes' $inactiveMbxB.Count `
    'Inactive mailboxes are not moved by cross-tenant mailbox migration. [Learn]($LearnMailbox)' `
    'Decide per mailbox: restore + migrate, export to PST/archive, or leave.' `
    $inactiveMbxB 'DisplayName' 'WhenSoftDeleted'

# Third-party mail gateway evidence (Mimecast/Proofpoint etc.)
$tpeB = Import-AttCsv 'ThirdPartyEvidence.csv'
Add-Blocker 'Third-party mail gateway detected' $tpeB.Count `
    'MX/SPF/connector records point at a third-party mail gateway - the mail flow cut-over needs connector + MX rework, not just the mailbox move.' `
    'Plan gateway cut-over/rebuild in the target (see 02/09); decide whether the same vendor is kept.' `
    $tpeB 'Vendor' 'Evidence'

# Expiring app credentials - migration is a natural rotation point
$appCredsB = Import-AttCsv 'AppCredentials.csv'
$expiring60 = @($appCredsB | Where-Object { "$($_.DaysToExpiry)" -match '^-?\d+$' -and [int]$_.DaysToExpiry -le 60 })
Add-Blocker 'App credentials expiring within 60 days' $expiring60.Count `
    'App/SP secrets and certificates that expire during the migration window break apps if they are re-consented without renewal.' `
    'Renew or rotate the credential when the app is re-created in the target.' `
    $expiring60 'OwnerName' 'EndDateTime'

# 8. Decisions / rebuild ------------------------------------------------------------

$null = $r.AppendLine('## 8. Needs a decision or rebuild (not migrated by Microsoft tools)')
$null = $r.AppendLine('')
$decRows = [System.Collections.Generic.List[object]]::new()
function Add-Decision { param([string]$Item, [int]$Count, [string]$Note)
    if ($Count -gt 0) { $decRows.Add([pscustomobject]@{ Item = $Item; Count = $Count; Note = $Note }) } }

Add-Decision 'Private / shared channels' ([int]($privCh + $sharedCh)) 'Recreate teams/channels and their sites; channel posts do not move (phase 07).'
Add-Decision 'Teams Phone (users with voice config)' $phoneUsers.Count 'Numbers, auto attendants, call queues must be ported/rebuilt.'
Add-Decision 'Bookings mailboxes' $bookings.Count 'Bookings is not moved - rebuild or export.'
Add-Decision 'Project Online sites (PWA#0/PROJECTSITE)' $pwaSites.Count 'Project Online is not covered by the site move tool.'
Add-Decision 'App registrations' $appRegs.Count 'Recreate in the target tenant.'
Add-Decision 'Conditional Access policies' $caPolicies.Count 'Recreate in the target tenant.'
Add-Decision 'Intune-managed devices' $intuneDevs.Count 'Devices are not moved - new PCs enrol in the target (phase 10).'
Add-Decision 'DLP policies' $dlp.Count 'Recreate in Purview in the target.'
Add-Decision 'eDiscovery/compliance cases' $compCases.Count 'Cannot move cases - close out or rebuild in the target.'
Add-Decision 'Transport rules' $trules.Count 'Export and recreate in the target.'
Add-Decision 'Journal rules' $jrules.Count 'Recreate in the target.'
Add-Decision 'Inbound + outbound connectors' ($inConn.Count + $outConn.Count) 'Recreate in the target.'
Add-Decision 'Distribution / dynamic groups' $dg.Count 'Recreate membership in the target.'
Add-Decision 'Mail contacts / mail users' ($contacts.Count + $mailUsers.Count) 'Recreate (playbook 08).'
Add-Decision 'Mailbox Full Access permission entries' $mbxPerms.Count 'Re-apply after the mailboxes exist (phase 06/Set-TargetMailboxPermissions).'
Add-Decision 'Send As entries' $sendAs.Count 'Re-apply after the mailboxes exist (phase 06/09).'
Add-Decision 'Guests' $guests.Count 'Re-invite in the target tenant.'
Add-Decision 'External SharePoint users' $extUsers.Count 'External users in SPO sharing - re-invite or re-share in the target tenant.'
$dynDlsD = Import-AttCsv 'DynamicDistributionGroups.csv'
Add-Decision 'Dynamic distribution groups' $dynDlsD.Count 'Membership is computed - recreate the RecipientFilter in the target (no member export needed).'
$hubD = Import-AttCsv 'HubSites.csv'
Add-Decision 'Hub site associations' $hubD.Count 'Re-register hub sites and re-associate sites in the target (HubSiteId on SharePointSites.csv).'
$delOdD = Import-AttCsv 'DeletedOneDrives.csv'
Add-Decision 'Deleted OneDrives (recoverable)' $delOdD.Count 'Soft-deleted personal sites within retention - restore before the move or accept the loss.'
$samlD = Import-AttCsv 'SamlCertificates.csv'
Add-Decision 'SAML enterprise apps' $samlD.Count 'SAML SSO certificates cannot move - re-upload/re-sign in the target (check SamlCertificates.csv expiry).'
$pimD = Import-AttCsv 'PimEligibleAssignments.csv'
Add-Decision 'PIM role assignments' $pimD.Count 'PIM does not migrate - recreate eligibility/activation schedules in the target.'
$softDelD = Import-AttCsv 'SoftDeletedMailboxes.csv'
Add-Decision 'Soft-deleted mailboxes' $softDelD.Count 'Restore or purge before cut-over - they are not migrated.'
$gdapD = Import-AttCsv 'DelegatedAdminRelationships.csv'
Add-Decision 'GDAP partner relationships' $gdapD.Count 'Re-establish GDAP relationships with partners in the target tenant.'

# Service-plan indicators
if ($servicePlans.Count -gt 0) {
    $spIndicators = [ordered]@{
        'Planner (PROJECTWORKMANAGEMENT)'     = '^(PROJECTWORKMANAGEMENT|PLANNER)'
        'Microsoft Forms'                   = '^(FORMS|OFFICEFORMS)'
        'Power Apps'                        = 'POWERAPPS'
        'Power Automate (Flow)'             = '^(FLOW|POWERAUTOMATE)'
        'Microsoft Loop'                    = 'LOOP'
        'Viva Engage / Yammer'              = 'YAMMER'
        'Stream'                            = 'STREAM'
        'Bookings'                          = 'BOOKINGS'
        'Project'                           = '^(PROJECT_)'
    }
    foreach ($k in $spIndicators.Keys) {
        $skus = @($servicePlans | Where-Object { $_.ServicePlanName -match $spIndicators[$k] -and $_.ProvisioningStatus -eq 'Success' } | ForEach-Object SkuPartNumber | Sort-Object -Unique)
        if ($skus.Count -gt 0) {
            $decRows.Add([pscustomobject]@{ Item = "$k (licensed)"; Count = $skus.Count; Note = "Licensed via: $($skus -join ', ') - ask the customer whether the workload is used." })
        }
    }
} else {
    $notInventoried.Add('Service-plan usage indicators (Planner/Forms/Power Platform/Viva Engage/Stream)')
}

$notInventoried.Add('Workflows (2010/2013) and SPFx/web parts per site - must be recreated on the target')
$notInventoried.Add('Teams tabs per team')
$notInventoried.Add('Loop workspaces')

if ($decRows.Count -gt 0) {
    $null = $r.AppendLine((Format-Table @($decRows) @('Item', 'Count', 'Note')))
} else {
    $null = $r.AppendLine('_Nothing detected._')
}
$null = $r.AppendLine('')

# Enterprise app usage (AppSignInActivity.csv from the AppSignIns inventory section)
$signInListDoc = 'https://learn.microsoft.com/en-us/graph/api/signin-list?view=graph-rest-beta'
$spActDoc      = 'https://learn.microsoft.com/en-us/graph/api/reportroot-list-serviceprincipalsigninactivities?view=graph-rest-beta'
if ($appSignIns.Count -gt 0) {
    $null = $r.AppendLine('### Enterprise app usage')
    $null = $r.AppendLine('')
    $nonMs = @($appSignIns | Where-Object { $_.IsMicrosoftFirstParty -ne 'True' })
    $stCounts = @($nonMs | Group-Object Status | ForEach-Object { "$($_.Name): $($_.Count)" })
    $null = $r.AppendLine("Non-Microsoft apps by status - $($stCounts -join ' - ')")
    $null = $r.AppendLine('')
    $activeApps = @($nonMs | Where-Object { $_.Status -eq 'ActiveInWindow' } | Sort-Object { $_.LastSeenAny } -Descending | Select-Object -First 25)
    if ($activeApps.Count -gt 0) {
        $null = $r.AppendLine('**Active non-Microsoft apps** (top 25, sign-in within the lookback window):')
        $null = $r.AppendLine('')
        $null = $r.AppendLine((Format-Table $activeApps @('DisplayName','AppId','ServicePrincipalType','LastInteractiveUser','LastNonInteractiveUser','LastServicePrincipal','LastManagedIdentity','DaysSinceLastSeen')))
        $null = $r.AppendLine('')
    }
    $inactive = @($nonMs | Where-Object { $_.Status -in 'ActiveEarlier','NoActivityRecorded','Unknown' -and $_.IsManagedIdentity -ne 'True' })
    if ($inactive.Count -gt 0) {
        $null = $r.AppendLine("**Inactive non-Microsoft apps ($($inactive.Count)) - candidates not to rebuild in the target** (confirm each owner first): " + (($inactive | Select-Object -First 25 | ForEach-Object DisplayName) -join ', ') + $(if ($inactive.Count -gt 25) { ' - ...' } else { '' }))
        $null = $r.AppendLine('')
    }
    $miActive = @($appSignIns | Where-Object { $_.IsManagedIdentity -eq 'True' -and $_.Status -eq 'ActiveInWindow' })
    if ($miActive.Count -gt 0) {
        $null = $r.AppendLine("- **$($miActive.Count) managed identities active in the window** - they belong to Azure resources and stay with the subscription (not tenant content).")
    }
    $msCount = @($appSignIns | Where-Object { $_.IsMicrosoftFirstParty -eq 'True' }).Count
    if ($msCount -gt 0) {
        $null = $r.AppendLine("- $msCount first-party Microsoft apps exist in every tenant - no action needed. They are status `ReportOnly` (sign-in logs not queried by default; re-run with `-IncludeMicrosoftAppsInSignInLogs` to query them).")
    }
    $null = $r.AppendLine("- Sources: sign-in logs (beta, requires Entra ID P1) [Learn]($signInListDoc); service principal sign-in activity report (beta, **preview** - may include partial sign-ins and misclassify app-only activity) [Learn]($spActDoc).")
    $null = $r.AppendLine('- **The activity report is preview and can be stale** - observed in practice: months-old dates for apps in daily use. It is therefore never used to conclude an app is unused: only apps whose sign-in logs were queried (`SignInLogsQueried = True`) can be `ActiveEarlier`/`NoActivityRecorded`; others are `ReportOnly`.')
    $null = $r.AppendLine('')
    if ($invSummary -and $invSummary.signInLogsUnavailable -eq $true) {
        $notInventoried.Add('Sign-in logs not available (Entra ID P1 required) - only the activity report was used')
    } else {
        $w = if ($invSummary -and $invSummary.appSignInWindowDays) { $invSummary.appSignInWindowDays } else { 30 }
        $notInventoried.Add("App sign-in history older than $w days")
    }
} else {
    $notInventoried.Add('Enterprise app usage not inventoried (AppSignInActivity.csv) - re-run inventory with the AppSignIns section')
    if ($entApps.Count -gt 0) {
        $null = $r.AppendLine("- $($entApps.Count) enterprise applications - usage not inventoried; recreate/re-consent in the target.")
        $null = $r.AppendLine('')
    }
}

# 9. Apps and platform items to address --------------------------------------------------

$null = $r.AppendLine('## 9. Apps and platform items to address')
$null = $r.AppendLine('')
$null = $r.AppendLine('None of these are moved by Microsoft tools - they must be re-consented, exported or rebuilt in the target tenant.')
$null = $r.AppendLine('')

# Enterprise app permissions (AppPermissions.csv from the Apps inventory section)
if (Test-CsvPresent 'AppPermissions.csv') {
    $highPriv        = @($appPerms | Where-Object { $_.IsHighPrivilege -eq 'True' })
    $appsWithAppPerm = @($appPerms | Where-Object { $_.PermissionType -eq 'Application' } | ForEach-Object ClientServicePrincipalId | Sort-Object -Unique)
    $appsWithDelPerm = @($appPerms | Where-Object { $_.PermissionType -eq 'Delegated' }   | ForEach-Object ClientServicePrincipalId | Sort-Object -Unique)
    $unresolved      = @($appPerms | Where-Object { $_.Resolved -eq 'False' })
    $null = $r.AppendLine('### Enterprise app API permissions')
    $null = $r.AppendLine('')
    $null = $r.AppendLine("- **$($appsWithAppPerm.Count)** enterprise apps have application permissions, **$($appsWithDelPerm.Count)** have delegated grants - every consent must be re-created in the target tenant.")
    if ($unresolved.Count -gt 0) {
        $null = $r.AppendLine("- $($unresolved.Count) grant(s) could not be resolved to a permission name (the role GUID is listed) - look them up before rebuilding.")
    }
    if ($highPriv.Count -gt 0) {
        $statusByApp = @{}
        foreach ($s in $appSignIns) { $statusByApp["$($s.AppId)"] = "$($s.Status)" }
        $hpRows = @($highPriv | Group-Object ClientAppId | ForEach-Object {
            $g = $_.Group[0]
            [pscustomobject]@{
                App          = $g.ClientDisplayName
                Permissions  = (@($_.Group | ForEach-Object { "$($_.PermissionType): $($_.Permission)" }) | Sort-Object -Unique) -join '; '
                SignInStatus = $statusByApp["$($g.ClientAppId)"]
            }
        } | Sort-Object App)
        $null = $r.AppendLine("- **$($hpRows.Count) app(s) hold high-privilege grants** (broad access - review each before re-consenting):")
        $null = $r.AppendLine('')
        $null = $r.AppendLine((Format-Table @($hpRows | Select-Object -First 20) @('App', 'Permissions', 'SignInStatus')))
        if ($hpRows.Count -gt 20) { $null = $r.AppendLine("`n_...and $($hpRows.Count - 20) more - see AppPermissions.csv._") }
        $null = $r.AppendLine('')
    }
} else {
    $notInventoried.Add('Granted permissions per enterprise app (AppPermissions.csv) - re-run inventory with the Apps section')
}

# Power Platform
if ((Test-Collected 'PowerPlatformEnvironments.csv' 'powerPlatformEnvironmentCount') -or (Test-CsvPresent 'PowerApps.csv') -or (Test-CsvPresent 'PowerAutomateFlows.csv')) {
    $null = $r.AppendLine('### Power Platform')
    $null = $r.AppendLine('')
    $null = $r.AppendLine("- **$($ppEnvs.Count) environment(s), $($ppApps.Count) Power App(s), $($ppFlows.Count) flow(s), $($ppConnectors.Count) custom connector(s), $($ppDlp.Count) DLP policy/policies** - nothing moves between tenants; export/import apps and flows (solutions or per-item export) and rebuild connectors/DLP in the target.")
    if ($ppEnvs.Count -gt 0) {
        $null = $r.AppendLine('')
        $null = $r.AppendLine((Format-Table $ppEnvs @('DisplayName', 'EnvironmentType', 'Location', 'IsDefault', 'HasDataverse')))
        $null = $r.AppendLine('')
    }
} else {
    $notInventoried.Add('Power Platform environments/apps/flows - re-run inventory with the PowerPlatform section (module Microsoft.PowerApps.Administration.PowerShell)')
}
if (Test-Collected 'PowerBIWorkspaces.csv' 'powerBiWorkspaceCount') {
    $null = $r.AppendLine("- Power BI: **$($pbiWs.Count) workspace(s)** - reports/datasets must be redeployed in the target.")
    $null = $r.AppendLine('')
} else {
    $notInventoried.Add('Power BI workspaces (PowerBIWorkspaces.csv) - optional: module MicrosoftPowerBIMgmt')
}

# Teams apps, Outlook add-ins, Planner, SharePoint app catalog
$null = $r.AppendLine('### M365 workload apps')
$null = $r.AppendLine('')
if (Test-Collected 'TeamsCustomApps.csv' 'teamsCustomAppCount') {
    $names = ($teamsCustom | ForEach-Object DisplayName | Sort-Object -Unique) -join ', '
    $null = $r.AppendLine("- **$($teamsCustom.Count) org-uploaded Teams app(s)** - download the packages and upload them to the target app catalog$(if ($teamsCustom.Count -le 15) { ": $names" } else { '.' })")
} else { $notInventoried.Add('Org-uploaded Teams apps (TeamsCustomApps.csv)') }
if (Test-Collected 'TeamsInstalledApps.csv' 'teamsInstalledAppCount') {
    $null = $r.AppendLine("- $($teamsInst.Count) installed Teams app instance(s) across teams ($($teamsCustom.Count) in the org catalog) - reinstall in the target teams.")
} else { $notInventoried.Add('Installed Teams apps per team (TeamsInstalledApps.csv)') }
if (Test-Collected 'PlannerPlans.csv' 'plannerPlanCount') {
    $planGroups = @($plannerPlans | ForEach-Object GroupId | Sort-Object -Unique).Count
    $null = $r.AppendLine("- **$($plannerPlans.Count) Planner plan(s)** in $planGroups M365 group(s) - Planner does not move; export tasks or recreate plans in the target.")
} else { $notInventoried.Add('Planner plans per group (PlannerPlans.csv)') }
if (Test-Collected 'OutlookAddins.csv' 'outlookAddinCount') {
    $null = $r.AppendLine("- **$($outlookAddins.Count) organization Outlook add-in(s)** - redeploy in the target (centralized deployment / integrated apps).")
} else { $notInventoried.Add('Organization Outlook add-ins (OutlookAddins.csv)') }
if (Test-Collected 'SharePointAppCatalog.csv' 'sharePointAppCatalogCount') {
    $null = $r.AppendLine("- **$($spoAppCat.Count) app(s) in the SharePoint tenant app catalog** (add-ins/SPFx) - redeploy the packages in the target catalog.")
} else { $notInventoried.Add('SharePoint tenant app catalog apps (SharePointAppCatalog.csv)') }
$null = $r.AppendLine('')

# 10. Not inventoried --------------------------------------------------------------

$null = $r.AppendLine('## 10. Not inventoried')
$null = $r.AppendLine('')
$null = $r.AppendLine('The report cannot see the following - check them manually or add them to the customer questions ([docs/Customer-Questions.md]($RepoDocs/Customer-Questions.md)):')
$null = $r.AppendLine('')
foreach ($n in ($notInventoried | Sort-Object -Unique)) { $null = $r.AppendLine("- $n") }
$null = $r.AppendLine('')
$null = $r.AppendLine("See [docs/What-Doesnt-Move.md]($RepoDocs/What-Doesnt-Move.md) for the full list of content that does not migrate.")

# ---- Executive + workload summary (prepended before '## 1. Summary') ----------
# Collector status comes from Collectors.csv (written by newer inventories);
# the registry (Collectors.psd1, same folder) maps each collector to a workload.
$collectorsCsv = Import-AttCsv 'Collectors.csv'
$regByName = @{}
$regPath = Join-Path $PSScriptRoot 'Collectors.psd1'
if (Test-Path $regPath) {
    try {
        $regData = Import-PowerShellDataFile -Path $regPath
        $regEntries = @($regData.Collectors)
        $regP1Path = Join-Path $PSScriptRoot 'Collectors.Phase1.psd1'
        if (Test-Path $regP1Path) { $regEntries += @((Import-PowerShellDataFile -Path $regP1Path).Collectors) }
        foreach ($ce in $regEntries) { $regByName[$ce.Name] = $ce }
    } catch {}
}

function Get-CsvCount { param([object[]]$Rows, [string]$CsvName)
    if (-not (Test-CsvPresent $CsvName)) { return 'Unknown' }
    return $Rows.Count }

$enabledUsers = 'Unknown'
if ($users.Count -gt 0 -and $users[0].PSObject.Properties['AccountEnabled']) {
    $enabledUsers = @($users | Where-Object { "$($_.AccountEnabled)" -eq 'True' }).Count
}
$disabledUsers = if ($enabledUsers -is [int]) { $users.Count - $enabledUsers } else { 'Unknown' }
$licensedUsers = @($users | Where-Object { "$($_.AssignedLicenses)".Trim() }).Count
$archiveMbx = @($mailboxes | Where-Object { "$($_.ArchiveStatus)" -eq 'Active' })
$apRec = @($collectorsCsv | Where-Object { $_.Collector -eq 'AutopilotDevices' } | Select-Object -First 1) | Select-Object -First 1
$autopilotCount = $autopilot.Count
if ($apRec -and "$($apRec.Status)" -notin 'Success','NotInUse') { $autopilotCount = 'Unknown' }
$retentionPols = Import-AttCsv 'RetentionPolicies.csv'
$intunePols    = Import-AttCsv 'IntunePolicies.csv'
$manualCollectors = @($collectorsCsv | Where-Object { "$($_.Status)" -eq 'ManualDiscoveryRequired' }).Count
$manualItems = ($notInventoried | Sort-Object -Unique).Count + $manualCollectors
$inactiveMbx    = Import-AttCsv 'InactiveMailboxes.csv'
$softDelMbx     = Import-AttCsv 'SoftDeletedMailboxes.csv'
$dynDls         = Import-AttCsv 'DynamicDistributionGroups.csv'
$hubSites       = Import-AttCsv 'HubSites.csv'
$delOds         = Import-AttCsv 'DeletedOneDrives.csv'
$tpe            = Import-AttCsv 'ThirdPartyEvidence.csv'
$appCreds       = Import-AttCsv 'AppCredentials.csv'
$samlCerts      = Import-AttCsv 'SamlCertificates.csv'
$pimEligible    = Import-AttCsv 'PimEligibleAssignments.csv'
$expiringCreds  = @($appCreds | Where-Object { "$($_.DaysToExpiry)" -match '^-?\d+$' -and [int]$_.DaysToExpiry -le 60 })
$expiringSaml   = @($samlCerts | Where-Object { "$($_.DaysToExpiry)" -match '^-?\d+$' -and [int]$_.DaysToExpiry -le 60 })

$ex = [System.Text.StringBuilder]::new()
$null = $ex.AppendLine('## Executive summary')
$null = $ex.AppendLine('')
$null = $ex.AppendLine('| Metric | Value |')
$null = $ex.AppendLine('|---|---|')
$exRows = @(
    @{ M = 'Users (total)';         V = $users.Count }
    @{ M = '- enabled';             V = $enabledUsers }
    @{ M = '- guests';              V = $guests.Count }
    @{ M = '- disabled';            V = $disabledUsers }
    @{ M = '- licensed';            V = $licensedUsers }
    @{ M = 'Groups';                V = $groups.Count }
    @{ M = 'Enterprise apps';       V = $entApps.Count }
    @{ M = 'App registrations';     V = $appRegs.Count }
    @{ M = 'Mailboxes (total)';     V = $mailboxes.Count }
    @{ M = '- user mailboxes';      V = $userMbx.Count }
    @{ M = '- shared/resource';     V = $sharedMbx.Count }
    @{ M = '- with archive';        V = $archiveMbx.Count }
    @{ M = 'Exchange data (GB)';    V = [math]::Round($userGB + $sharedGB, 1) }
    @{ M = 'SharePoint data (GB)';  V = [math]::Round($spGB, 1) }
    @{ M = 'OneDrive data (GB)';    V = [math]::Round($odGB, 1) }
    @{ M = 'SharePoint sites';      V = (Get-CsvCount $spSites 'SharePointSites.csv') }
    @{ M = 'OneDrive sites';        V = (Get-CsvCount $oneDrives 'OneDrive.csv') }
    @{ M = 'Teams';                 V = (Get-CsvCount $teams 'Teams.csv') }
    @{ M = '- private channels';    V = [int]$privCh }
    @{ M = '- shared channels';     V = [int]$sharedCh }
    @{ M = 'Intune-managed devices';V = $intuneDevs.Count }
    @{ M = 'Autopilot devices';     V = $autopilotCount }
    @{ M = 'Intune policies';       V = (Get-CsvCount $intunePols 'IntunePolicies.csv') }
    @{ M = 'Conditional Access policies'; V = $caPolicies.Count }
    @{ M = 'Purview policies (retention + DLP)'; V = $retentionPols.Count + $dlp.Count }
    @{ M = 'Power Apps';            V = $ppApps.Count }
    @{ M = 'Power Automate flows';  V = $ppFlows.Count }
    @{ M = 'Power BI workspaces';   V = $pbiWs.Count }
    @{ M = 'Inactive mailboxes (not moved by cross-tenant tools)'; V = $inactiveMbx.Count }
    @{ M = 'Soft-deleted mailboxes'; V = $softDelMbx.Count }
    @{ M = 'Dynamic distribution groups'; V = $dynDls.Count }
    @{ M = 'Hub sites';             V = $hubSites.Count }
    @{ M = 'Deleted OneDrives (recoverable)'; V = $delOds.Count }
    @{ M = 'Third-party mail gateway evidence'; V = $tpe.Count }
    @{ M = 'App credentials expiring <=60 days'; V = $expiringCreds.Count }
    @{ M = 'SAML certificates expiring <=60 days'; V = $expiringSaml.Count }
    @{ M = 'PIM eligible assignments'; V = $pimEligible.Count }
    @{ M = 'Blockers (section 7)';  V = $script:BlockerCount }
    @{ M = 'Items needing manual assessment'; V = $manualItems }
)
foreach ($row in $exRows) { $null = $ex.AppendLine("| $($row.M) | $($row.V) |") }
$null = $ex.AppendLine('')
$null = $ex.AppendLine('Teams files are included in the SharePoint/OneDrive figures - they are not counted separately.')
$null = $ex.AppendLine('')

$null = $ex.AppendLine('## Workload summary')
$null = $ex.AppendLine('')
if ($collectorsCsv.Count -eq 0) {
    $null = $ex.AppendLine('This inventory has no Collectors.csv - collector status is **Not Assessed**. Re-run the assessment with a version that records collector status (see [Collector-Matrix.md]($RepoDocs/Collector-Matrix.md)).')
    $null = $ex.AppendLine('')
} else {
    $methodMap = [ordered]@{
        'Exchange|mailbox'      = 'Cross-tenant mailbox migration'
        'OneDrive'              = 'Cross-tenant OneDrive migration'
        'SharePoint'            = 'Cross-tenant SharePoint migration'
        'Teams'                 = 'Partial - export/import + rebuild'
        'Planner'               = 'Manual - Planner is not moved'
        'Devices|Intune|Autopilot' = 'Wipe and re-enrol / re-register in target'
        'Power Platform|Power BI'  = 'Export/import (manual)'
        'Licence'               = 'Assign in target'
        'Domain'                = 'Verify domain in target'
        'Identity|Group|User'   = 'Recreate / sync in target'
        'Security|Conditional'  = 'Recreate in target'
        'Compliance|Purview|Retention|DLP' = 'Recreate in target'
        'Mail flow|Transport'   = 'Recreate in target'
    }
    $null = $ex.AppendLine('| Workstream | Workload | Identified | In use | Objects | Data (GB) | Discovery status | Completeness | Suggested method | Manual assessment | Business criticality | Migration complexity |')
    $null = $ex.AppendLine('|---|---|---|---|---|---|---|---|---|---|---|---|')
    foreach ($rec in $collectorsCsv) {
        $reg = $regByName["$($rec.Collector)"]
        $ws = if ($reg) { "$($reg['Workstream'])" } else { '-' }
        $wl = if ($reg) { "$($reg['Workload'])" } else { "$($rec.Collector)" }
        $objCount = "$($rec.ObjectCount)"; if (-not $objCount) { $objCount = '0' }
        $status = "$($rec.Status)"
        $identified = if ([int]$objCount -gt 0) { 'Yes' } else { 'No' }
        $inUse = switch ($status) { 'Success' { 'Yes' } 'PartialSuccess' { 'Yes' } 'NotInUse' { 'No' } default { 'Unknown' } }
        $method = 'Manual assessment'
        foreach ($k in $methodMap.Keys) { if ($wl -match $k) { $method = $methodMap[$k]; break } }
        $manual = 'No'
        if ($status -eq 'ManualDiscoveryRequired' -or ($reg -and "$($reg['Coverage'])" -eq 'ManualDiscoveryRequired')) { $manual = 'Yes' }
        $compl = "$($rec.Completeness)"; if (-not $compl) { $compl = 'Unknown' }
        $gb = '-'
        if ($wl -match 'Exchange Online|mailbox')   { $gb = [math]::Round($userGB + $sharedGB, 1) }
        elseif ($wl -match 'SharePoint')            { $gb = [math]::Round($spGB, 1) }
        elseif ($wl -match 'OneDrive')              { $gb = [math]::Round($odGB, 1) }
        $null = $ex.AppendLine("| $ws | $wl | $identified | $inUse | $objCount | $gb | $status | $compl | $method | $manual | Not Assessed | Not Assessed |")
    }
    $null = $ex.AppendLine('')
}

$reportText = $r.ToString()
$insertAt = $reportText.IndexOf('## 1. Summary')
if ($insertAt -ge 0) {
    $reportText = $reportText.Insert($insertAt, $ex.ToString())
} else {
    $reportText += "`n" + $ex.ToString()
}

if (-not $OutFile) { $OutFile = Join-Path $InventoryPath 'Readiness.md' }
$reportText | Out-File -FilePath $OutFile -Encoding utf8BOM
Write-Host "Readiness report written to $OutFile"
