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

    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$LearnOverview  = 'https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-1-overview'
$LearnMailbox   = 'https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-mailbox-migration'
$LearnOneDrive  = 'https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration'
$LearnSharePoint= 'https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration'
$RepoDocs       = 'https://github.com/codeandersen/ms365-tenant-to-tenant-migration/blob/main/docs'

$attach = Join-Path $InventoryPath 'attachments'
$notInventoried = [System.Collections.Generic.List[string]]::new()

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
$entApps      = Import-AttCsv 'EnterpriseApplications.csv'
$caPolicies   = Import-AttCsv 'ConditionalAccessPolicies.csv'
$extUsers     = Import-AttCsv 'ExternalUsers.csv'

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
$pwaSites   = @($spSites | Where-Object { $_.Template -match '^(PWA#0|PROJECTSITE)' })

$target = $null
if ($TargetInventoryPath) {
    $tAttach = Join-Path $TargetInventoryPath 'attachments'
    $target = [pscustomobject]@{
        Licenses  = Import-AttCsv 'Licenses.csv' -Base $tAttach
        Domains   = Import-AttCsv 'AcceptedDomains.csv' -Base $tAttach
        OneDrives = Import-AttCsv 'OneDrive.csv' -Base $tAttach
        Sites     = Import-AttCsv 'SharePointSites.csv' -Base $tAttach
        Attach    = $tAttach
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

# 3. Licences -------------------------------------------------------------------

$null = $r.AppendLine('## 4. Licences')
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

# 4. Blockers --------------------------------------------------------------------

$null = $r.AppendLine('## 5. Must be addressed before migration (blockers)')
$null = $r.AppendLine('')

function Add-Blocker {
    param([string]$Title, [int]$Count, [string]$Why, [string]$Action, [object[]]$Examples,
          [string]$ExampleCol, [string]$DetailCol)
    if ($Count -le 0) { return }
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

# 5. Decisions / rebuild ------------------------------------------------------------

$null = $r.AppendLine('## 6. Needs a decision or rebuild (not migrated by Microsoft tools)')
$null = $r.AppendLine('')
$decRows = [System.Collections.Generic.List[object]]::new()
function Add-Decision { param([string]$Item, [int]$Count, [string]$Note)
    if ($Count -gt 0) { $decRows.Add([pscustomobject]@{ Item = $Item; Count = $Count; Note = $Note }) } }

Add-Decision 'Private / shared channels' ([int]($privCh + $sharedCh)) 'Recreate teams/channels and their sites; channel posts do not move (phase 07).'
Add-Decision 'Teams Phone (users with voice config)' $phoneUsers.Count 'Numbers, auto attendants, call queues must be ported/rebuilt.'
Add-Decision 'Bookings mailboxes' $bookings.Count 'Bookings is not moved - rebuild or export.'
Add-Decision 'Project Online sites (PWA#0/PROJECTSITE)' $pwaSites.Count 'Project Online is not covered by the site move tool.'
Add-Decision 'App registrations' $appRegs.Count 'Recreate in the target tenant.'
Add-Decision 'Enterprise applications' $entApps.Count 'Recreate/re-consent in the target tenant.'
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

# Service-plan indicators
if ($servicePlans.Count -gt 0) {
    $spIndicators = [ordered]@{
        'Planner (PROJECTWORKMANAGEMENT)'     = '^(PROJECTWORKMANAGEMENT|PLANNER)'
        'Microsoft Forms'                   = '^(FORMS|OFFICEFORMS)'
        'Power Apps'                        = 'POWERAPPS'
        'Power Automate (Flow)'             = '^(FLOW|POWERAUTOMATE)'
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

$notInventoried.Add('Workflows (2010/2013), apps and Power Apps/Automate per site - must be recreated on the target')
$notInventoried.Add('Teams apps, tabs and Planner plans per team')
$notInventoried.Add('Loop workspaces')
$notInventoried.Add('Power Platform environments/apps')

if ($decRows.Count -gt 0) {
    $null = $r.AppendLine((Format-Table @($decRows) @('Item', 'Count', 'Note')))
} else {
    $null = $r.AppendLine('_Nothing detected._')
}
$null = $r.AppendLine('')

# 6. Not inventoried ----------------------------------------------------------------

$null = $r.AppendLine('## 7. Not inventoried')
$null = $r.AppendLine('')
$null = $r.AppendLine('The report cannot see the following - check them manually or add them to the customer questions ([docs/Customer-Questions.md]($RepoDocs/Customer-Questions.md)):')
$null = $r.AppendLine('')
foreach ($n in ($notInventoried | Sort-Object -Unique)) { $null = $r.AppendLine("- $n") }
$null = $r.AppendLine('')
$null = $r.AppendLine("See [docs/What-Doesnt-Move.md]($RepoDocs/What-Doesnt-Move.md) for the full list of content that does not migrate.")

if (-not $OutFile) { $OutFile = Join-Path $InventoryPath 'Readiness.md' }
$r.ToString() | Out-File -FilePath $OutFile -Encoding utf8BOM
Write-Host "Readiness report written to $OutFile"
