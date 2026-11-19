<#
.SYNOPSIS
    Generates an English review report (Review.md) from a tenant inventory.

.DESCRIPTION
    Reads summary.json and CSV attachments from a folder produced by Collect-TenantInventory.ps1
    and writes Review.md with a status per check (OK / Information / Note / Critical),
    key figures, top-20 tables and links to the attachments.

.PARAMETER InventoryPath
    Path to the inventory folder (the folder containing summary.json and attachments\).

.PARAMETER TargetInventoryPath
    Optional path to the target tenant's inventory folder. Used for domain conflicts,
    the migration-license check and user matches.

.PARAMETER CustomerName
    Customer name in the report header. Defaults to the tenant name from summary.json.

.EXAMPLE
    .\New-InventoryReport.ps1 -InventoryPath .\Inventory_Contoso_Source_20261022_090302

.EXAMPLE
    .\New-InventoryReport.ps1 -InventoryPath .\Inventory_Contoso_Source_20261022_090302 -TargetInventoryPath .\Inventory_Fabrikam_Target_20261023_101500
#>
#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InventoryPath,

    [string]$TargetInventoryPath,

    [string]$CustomerName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
# Review.md is written next to summary.json - refuse before reading anything
Assert-CustomerDataPath -Path (Join-Path $InventoryPath 'Review.md')

function ConvertTo-Num {
    # Tolerates both "12.5" (invariant) and "12,5" (da-DK) from older CSVs.
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [double] -or $Value -is [int] -or $Value -is [decimal]) { return [double]$Value }
    $s = "$Value".Trim()
    if ($s -eq '') { return $null }
    if ($s -match ',' -and $s -notmatch '\.') { $s = $s -replace ',', '.' }
    elseif ($s -match ',' -and $s -match '\.') {
        # Grouping symbol = whichever of , or . appears first
        if ($s.IndexOf(',') -lt $s.IndexOf('.')) { $s = $s -replace ',', '' } else { $s = $s -replace '\.', '' -replace ',', '.' }
    }
    try { return [double]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture) } catch { return $null }
}

$summaryFile = Join-Path $InventoryPath 'summary.json'
if (-not (Test-Path $summaryFile)) { throw "summary.json not found in $InventoryPath" }
$summary = Get-Content $summaryFile -Raw | ConvertFrom-Json
$attach = Join-Path $InventoryPath 'attachments'

$targetSummary = $null
$targetAttach = $null
if ($TargetInventoryPath) {
    $ts = Join-Path $TargetInventoryPath 'summary.json'
    if (Test-Path $ts) {
        $targetSummary = Get-Content $ts -Raw | ConvertFrom-Json
        $targetAttach = Join-Path $TargetInventoryPath 'attachments'
        # Copy target attachments into the source attachments for links
        foreach ($f in 'DomainConflicts.csv','UserMatches.csv','MailUsers.csv') {
            $src = Join-Path $targetAttach $f
            if (Test-Path $src) { Copy-Item $src -Destination (Join-Path $attach "Target_$f") -Force }
        }
    } else {
        Write-Warning "Target summary.json not found in $TargetInventoryPath - skipping target checks."
    }
}

if (-not $CustomerName) { $CustomerName = $summary.tenantName }

$script:CsvCache = @{}
function Import-AttCsv {
    param([string]$Name)
    if ($script:CsvCache.ContainsKey($Name)) { return $script:CsvCache[$Name] }
    $p = Join-Path $attach $Name
    $rows = $null
    if (Test-Path $p) { $rows = @(Import-Csv $p) }
    $script:CsvCache[$Name] = $rows
    return $rows
}

function Get-Metric {
    param([string]$Name, $Default = $null)
    $m = $summary.metrics
    if ($m -and $m.PSObject.Properties[$Name]) {
        $v = $m.$Name
        if ($null -ne $v) { return $v }
    }
    return $Default
}

function Get-SectionFailure {
    param([string]$Section)
    if ($summary.failedSections -and $summary.failedSections.PSObject.Properties[$Section]) {
        return $summary.failedSections.$Section
    }
    if ($summary.skippedSections -and $summary.skippedSections.PSObject.Properties[$Section]) {
        return $summary.skippedSections.$Section
    }
    return $null
}

function Test-LicenseSkipped {
    param([string]$Section)
    $r = Get-SectionFailure $Section
    return ($r -and "$r" -match 'no license')
}

function Format-MdTable {
    param([object[]]$Rows, [string[]]$Columns, [int]$MaxRows = 20)
    if (-not $Rows -or $Rows.Count -eq 0) { return "_No data._`n" }
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine('| ' + ($Columns -join ' | ') + ' |')
    $null = $sb.AppendLine('|' + (($Columns | ForEach-Object { '---' }) -join '|') + '|')
    $shown = @($Rows | Select-Object -First $MaxRows)
    foreach ($r in $shown) {
        $cells = foreach ($c in $Columns) {
            $v = "$($r.PSObject.Properties[$c].Value)"
            if ($v.Length -gt 80) { $v = $v.Substring(0,77) + '...' }
            ($v -replace '\|','\|')
        }
        $null = $sb.AppendLine('| ' + ($cells -join ' | ') + ' |')
    }
    if ($Rows.Count -gt $MaxRows) { $null = $sb.AppendLine("_... showing $MaxRows of $($Rows.Count) rows. See the attachment for all._") }
    return $sb.ToString()
}

function Get-Truncated {
    param([string]$Text, [int]$Len = 200)
    $t = ($Text -replace '\s+',' ').Trim()
    if ($t.Length -gt $Len) { return $t.Substring(0, $Len - 3) + '...' }
    return $t
}

# --- Report accumulation ---
$checks = [System.Collections.Generic.List[object]]::new()   # @{Title; Status; Conclusion}
$body = [System.Text.StringBuilder]::new()

function Add-Check {
    param(
        [int]$Number,
        [string]$Title,
        [string]$Status,
        [string]$Conclusion,
        [string]$Why,
        [string]$Commands,
        [string]$Results,
        [string[]]$Attachments
    )
    $anchor = "#$Number-check-" + (($Title -replace '[^\p{L}0-9 \-]','') -replace ' ','-').ToLower()
    $checks.Add([pscustomobject]@{ Number = $Number; Title = $Title; Status = $Status; Conclusion = (Get-Truncated $Conclusion 250); Anchor = $anchor })

    $null = $body.AppendLine("## $Number. $Title check")
    $null = $body.AppendLine()
    $null = $body.AppendLine($Why)
    $null = $body.AppendLine()
    $null = $body.AppendLine('### Commands for the check')
    $null = $body.AppendLine()
    $null = $body.AppendLine('```powershell')
    $null = $body.AppendLine($Commands.Trim())
    $null = $body.AppendLine('```')
    $null = $body.AppendLine()
    $null = $body.AppendLine('### Results')
    $null = $body.AppendLine()
    $null = $body.AppendLine($Results)
    $null = $body.AppendLine()
    $null = $body.AppendLine("**Status: $Status** — $Conclusion")
    $null = $body.AppendLine()
    if ($Attachments) {
        foreach ($a in $Attachments) { $null = $body.AppendLine("[$a](attachments/$a)") }
        $null = $body.AppendLine()
    }
}

function Add-CheckFailed {
    param([int]$Number, [string]$Title, [string]$Section, [string]$Why, [string]$Commands)
    $reason = Get-SectionFailure $Section
    if (-not $reason) { $reason = 'the section produced no data' }
    Add-Check -Number $Number -Title $Title -Status 'Information' `
        -Conclusion "Data not collected: $reason" -Why $Why -Commands $Commands -Results "_Data not collected._"
}

$m = { param($n, $d = 0) Get-Metric $n $d }

# ============================================================
# 1. Tenant and identity source
# ============================================================
$org = Import-AttCsv 'Organization.csv'
$hybridDriver = 'unknown'
if ($org) {
    $o = $org[0]
    $hybrid = [bool](Get-Metric 'hybridIdentity' $false)
    $hybridDriver = if ($hybrid) { 'Yes' } else { 'No' }
    $syncedUsers = @()
    $usersCsv1 = Import-AttCsv 'Users.csv'
    if ($usersCsv1) { $syncedUsers = @($usersCsv1 | Where-Object { $_.OnPremisesSyncEnabled -eq 'True' }) }
    $lastSync = $null; $lastSyncRaw = "$($o.OnPremisesLastSyncDateTime)"
    if ($lastSyncRaw) {
        $cultures = @([System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.CultureInfo]::GetCultureInfo('da-DK'))
        foreach ($cult in $cultures) {
            try { $lastSync = [datetime]::Parse($lastSyncRaw, $cult); break } catch {}
        }
    }
    $daysSinceSync = $null
    if ($lastSync) { $daysSinceSync = [int]((Get-Date) - $lastSync).TotalDays }
    if (-not $hybrid) {
        $status = 'OK'
        $concl = "The tenant is cloud-only - no AD Connect dependencies to unwind."
    } elseif ($lastSync -and $daysSinceSync -le 7) {
        $status = 'Note'
        $concl = "The tenant synchronises identities from on-premises Active Directory (last sync: $lastSyncRaw). AD Connect and on-prem dependencies must be handled or decommissioned as part of the migration."
    } elseif ($lastSync -and $daysSinceSync -le 90) {
        $status = 'Note'
        $concl = "Synchronisation appears to have stopped recently (last sync: $lastSyncRaw - $daysSinceSync days ago) - check with the customer whether AD Connect is still running."
    } else {
        $status = 'Note'
        $concl = "Directory synchronisation is still enabled on the tenant, but the last sync was $lastSyncRaw - AD Connect is effectively decommissioned. $($syncedUsers.Count) users are still marked as synchronised and cannot be edited in the cloud. Synchronisation should be turned off on the tenant so the objects become cloud-managed before the migration. Otherwise the tenant is effectively cloud-only."
        $hybridDriver = "No (sync enabled, but inactive since $lastSyncRaw; $($syncedUsers.Count) synced objects)"
    }
    $res = Format-MdTable -Rows $org -Columns 'Id','DisplayName','CountryLetterCode','CreatedDateTime','OnPremisesSyncEnabled','OnPremisesLastSyncDateTime'
    if ($syncedUsers -and (-not $daysSinceSync -or $daysSinceSync -gt 90)) {
        $res += "`n**Users still marked as synchronised**`n" + (Format-MdTable -Rows @($syncedUsers | Select-Object -First 20) -Columns 'UserPrincipalName','DisplayName','AccountEnabled')
    }
    Add-Check -Number 1 -Title 'Tenant and identity source' -Status $status -Conclusion $concl `
        -Why 'Checks whether the tenant''s identities are cloud-only or synchronised from on-premises Active Directory (AD Connect). A hybrid identity source affects how users are moved and whether on-prem AD must be decommissioned.' `
        -Commands "GET /organization (Microsoft Graph)`n# onPremisesSyncEnabled, onPremisesLastSyncDateTime" `
        -Results $res -Attachments @('Organization.csv')
} else {
    Add-CheckFailed -Number 1 -Title 'Tenant and identity source' -Section 'Tenant' `
        -Why 'Checks whether the tenant''s identities are cloud-only or synchronised from on-premises Active Directory.' `
        -Commands 'GET /organization (Microsoft Graph)'
}

# ============================================================
# 2. Domains
# ============================================================
$domains = Import-AttCsv 'Domains.csv'
if ($domains) {
    $conflicts = Import-AttCsv 'Target_DomainConflicts.csv'
    $conflictDomains = @()
    if ($conflicts) {
        $conflictDomains = @($conflicts | ForEach-Object {
            if (($_.PSObject -and $_.PSObject.Properties['Conflict'] -and $_.PSObject.Properties['Conflict'].Value -eq 'True') -and
                $_.PSObject.Properties['SourceDomain']) { $_.PSObject.Properties['SourceDomain'].Value }
        })
    }
    if ($conflictDomains.Count -gt 0) {
        $status = 'Note'
        $concl = "$($conflictDomains.Count) source domain(s) are already verified in the target tenant: $($conflictDomains -join ', '). The domain must be removed from Contoso before it can be added and verified in Fabrikam."
    } else {
        $status = 'Information'
        $concl = "$(@($domains | Where-Object IsVerified -eq 'True').Count) verified domains are registered. Domains that must move to Fabrikam have to be removed from Contoso and verified in Fabrikam during cutover."
    }
    $unknownDomains = @()
    if ($conflicts) { $unknownDomains = @($conflicts | Where-Object { $null -ne $_ -and $_.PSObject.Properties['Conflict'] -and $_.Conflict -eq 'Unknown' } | ForEach-Object SourceDomain) }
    if ($unknownDomains.Count -gt 0) {
        $status = 'Note'
        $concl += " Conflict status could not be determined for $($unknownDomains -join ', ') (the lookup in target failed - typically missing permissions)."
    }
    $res = Format-MdTable -Rows @($domains | Sort-Object @{e={$_.IsDefault -eq 'True'}}, Id -Descending) -Columns 'Id','AuthenticationType','IsDefault','IsInitial','IsVerified','SupportedServices'
    $att = @('Domains.csv')
    if ($conflicts) { $res += "`n**Domain conflicts against target**`n" + (Format-MdTable -Rows $conflicts -Columns @($conflicts[0].PSObject.Properties.Name)); $att += 'Target_DomainConflicts.csv' }
    Add-Check -Number 2 -Title 'Domains' -Status $status -Conclusion $concl `
        -Why 'All domains used for mail and sign-in in Contoso must move to Fabrikam. A domain can only be verified in one tenant at a time, so moving it requires the domain to be removed from Contoso first.' `
        -Commands "GET /domains (Microsoft Graph)`nGET /domains/{id} against target with -SourceInventoryPath" `
        -Results $res -Attachments $att
} else {
    Add-CheckFailed -Number 2 -Title 'Domains' -Section 'Tenant' `
        -Why 'All domains used for mail and sign-in in Contoso must move to Fabrikam.' `
        -Commands 'GET /domains (Microsoft Graph)'
}

# ============================================================
# 3. Users and licenses
# ============================================================
$users = Import-AttCsv 'Users.csv'
if ($users) {
    $memberCount = & $m 'memberCount' (@($users | Where-Object UserType -eq 'Member').Count)
    $guestCount  = & $m 'guestCount'  (@($users | Where-Object IsGuest -eq 'True').Count)
    $inactive    = & $m 'inactive90dCount' 0
    $unlicensedMembers = @($users | Where-Object { $_.UserType -eq 'Member' -and $_.IsLicensed -eq 'False' }).Count
    $concl = "$memberCount members and $guestCount guests in the tenant. $inactive members have not been active in the last 90 days (or have never signed in) and should be evaluated for whether they need to be migrated at all. $unlicensedMembers members have no license."
    $licenses = Import-AttCsv 'Licenses.csv'
    $res = "**User distribution**`n" + (Format-MdTable -Rows @(
        [pscustomobject]@{ Category = 'Members'; Count = $memberCount },
        [pscustomobject]@{ Category = 'Guests'; Count = $guestCount },
        [pscustomobject]@{ Category = 'Enabled accounts'; Count = (& $m 'enabledUserCount' 0) },
        [pscustomobject]@{ Category = 'Licensed users'; Count = (& $m 'licensedCount' 0) },
        [pscustomobject]@{ Category = 'Inactive >90 days'; Count = $inactive },
        [pscustomobject]@{ Category = 'Synced from AD'; Count = (& $m 'syncedUserCount' 0) },
        [pscustomobject]@{ Category = 'Members without a license'; Count = $unlicensedMembers }
    ) -Columns 'Category','Count')
    if ($licenses) { $res += "`n**Licenses**`n" + (Format-MdTable -Rows @($licenses | Sort-Object { -[int]$_.ConsumedUnits }) -Columns 'SkuPartNumber','ConsumedUnits','EnabledUnits','SuspendedUnits','WarningUnits') }
    $capNames = @{ teamsPhone = 'Teams Phone'; intune = 'Intune'; entraP1 = 'Entra ID P1'; exchangeArchive = 'Exchange archive'; purviewPremium = 'Purview premium' }
    $capObj = Get-Metric 'licenseCapabilities' $null
    if ($capObj) {
        $capLine = ($capNames.GetEnumerator() | ForEach-Object { "$($_.Value): $(if ($capObj.PSObject.Properties[$_.Key] -and $capObj.($_.Key)) { 'Yes' } else { 'No' })" }) -join ', '
        $res += "`n**License capabilities:** $capLine`n"
    }
    $att = @('Users.csv'); if ($licenses) { $att += 'Licenses.csv' }
    Add-Check -Number 3 -Title 'Users and licenses' -Status 'Information' -Conclusion $concl `
        -Why 'The number and type of users drives both the license requirement (Cross-Tenant User Data Migration per user) and the scope of identity mapping. Inactive accounts and guests should be evaluated for migration.' `
        -Commands "GET /users?`$select=...,signInActivity (Microsoft Graph)`nGET /subscribedSkus" `
        -Results $res -Attachments $att
} else {
    Add-CheckFailed -Number 3 -Title 'Users and licenses' -Section 'Users' `
        -Why 'The number and type of users drives the license requirement and the scope of identity mapping.' `
        -Commands "GET /users (Microsoft Graph)`nGET /subscribedSkus"
}

# ============================================================
# 4. Migration license in target
# ============================================================
if ($targetSummary) {
    $found = $false
    if ($targetSummary.metrics -and $targetSummary.metrics.PSObject.Properties['migrationLicenseFound']) {
        $found = [bool]$targetSummary.metrics.migrationLicenseFound
    }
    if ($found) {
        $status = 'OK'
        $concl = "Migration licenses (Cross-Tenant User Data Migration) were found in the Fabrikam target tenant: $($targetSummary.metrics.migrationLicenses -join ', ')."
        $res = Format-MdTable -Rows @($targetSummary.metrics.licenses | ForEach-Object { [pscustomobject]@{ License = $_ } }) -Columns 'License'
    } else {
        $status = 'Critical'
        $concl = 'No Cross-Tenant User Data Migration license (skuPartNumber containing CROSS_TENANT/MIGRATION) was found in the target tenant. The license must be assigned to every user being migrated - otherwise Orchestrator cannot run.'
        $res = "_No migration license found in target._"
    }
    Add-Check -Number 4 -Title 'Migration license in target' -Status $status -Conclusion $concl `
        -Why 'Microsoft Migration Orchestrator requires every migrated user to hold the "Cross-Tenant User Data Migration" license in the target tenant. Without it the migration cannot start.' `
        -Commands 'GET /subscribedSkus (Microsoft Graph, target tenant)'
} else {
    Add-Check -Number 4 -Title 'Migration license in target' -Status 'Information' `
        -Conclusion 'Data not collected: no target inventory was given (-TargetInventoryPath).' `
        -Why 'Microsoft Migration Orchestrator requires a Cross-Tenant User Data Migration license per user in the target tenant.' `
        -Commands 'GET /subscribedSkus (Microsoft Graph, target tenant)' -Results '_Data not collected._'
}

# ============================================================
# 5. Mailboxes and archives
# ============================================================
$mbx = Import-AttCsv 'Mailboxes.csv'
if ($mbx) {
    $totalGB = & $m 'totalMailboxGB' 0
    $archGB  = & $m 'totalArchiveGB' 0
    $over100 = & $m 'mailboxesOver100GB' 0
    $byType = @($mbx | Group-Object RecipientTypeDetails | Sort-Object Count -Descending | ForEach-Object { [pscustomobject]@{ Type = $_.Name; Count = $_.Count } })
    $top = @($mbx | Sort-Object { ConvertTo-Num $_.TotalItemSizeGB } -Descending | Select-Object -First 20)
    $res = "**Mailbox distribution**`n" + (Format-MdTable -Rows $byType -Columns 'Type','Count')
    $res += "`nTotal mailbox data: **$totalGB GB**, archive data: **$archGB GB** across $(@($mbx | Where-Object ArchiveStatus -eq 'Active').Count) archives.`n"
    $res += "`n**Largest mailboxes**`n" + (Format-MdTable -Rows $top -Columns 'UserPrincipalName','RecipientTypeDetails','TotalItemSizeGB','ArchiveStatus')
    if ($over100 -gt 0) {
        $status = 'Note'
        $concl = "The tenant has $($mbx.Count) mailboxes with a total of $totalGB GB data and $archGB GB archive. $over100 mailbox(es) are over 100 GB and can be especially time-consuming to migrate - plan them early."
    } else {
        $status = 'Information'
        $concl = "The tenant has $($mbx.Count) mailboxes with a total of $totalGB GB data and $archGB GB archive. No mailboxes over 100 GB."
    }
    Add-Check -Number 5 -Title 'Mailboxes and archives' -Status $status -Conclusion $concl `
        -Why 'Mailbox size and archives are direct estimate drivers: data volume controls migration duration, and Orchestrator moves both the primary mailbox and the archive.' `
        -Commands "Get-EXOMailbox -ResultSize Unlimited`nGet-EXOMailboxStatistics -Identity <guid>`nGet-EXOMailboxStatistics -Identity <guid> -Archive" `
        -Results $res -Attachments @('Mailboxes.csv','MailboxStatistics.csv')
} else {
    Add-CheckFailed -Number 5 -Title 'Mailboxes and archives' -Section 'Exchange' `
        -Why 'Mailbox size and archives are direct estimate drivers.' `
        -Commands "Get-EXOMailbox -ResultSize Unlimited`nGet-EXOMailboxStatistics"
}

# ============================================================
# 6. Mailboxes on hold
# ============================================================
$holdsUnknown = [bool](Get-Metric 'holdsUnknown' $false)
if ($holdsUnknown) {
    $eDisco = Import-AttCsv 'EDiscoveryHolds.csv'
    $eRes = "_Holds could not be checked._"
    if ($eDisco) { $eRes += "`n`n**eDiscovery holds via Graph:**`n" + (Format-MdTable -Rows $eDisco -Columns 'CaseName','HoldName','Enabled','Status') }
    Add-Check -Number 6 -Title 'Mailboxes on hold' -Status 'Critical' `
        -Conclusion 'Holds could not be checked (no Exchange PowerShell access). Must be checked with a member account before the estimate can be locked.' `
        -Why 'Microsoft Migration Orchestrator rejects mailboxes on Litigation Hold, eDiscovery hold or retention hold. Holds must be identified and resolved early, as they can block an entire batch.' `
        -Commands "Get-EXOMailbox -Properties LitigationHoldEnabled,InPlaceHolds`n# Fallback: GET /security/cases/ediscoveryCases (Graph)" `
        -Results $eRes
} elseif ($mbx) {
    $holds = Import-AttCsv 'MailboxHolds.csv'
    $holdCount = if ($holds) { $holds.Count } else { 0 }
    if ($holdCount -gt 0) {
        $status = 'Critical'
        $concl = "$holdCount mailbox(es) are on hold (litigation hold, eDiscovery/in-place hold or retention hold). Orchestrator blocks moving mailboxes with holds - the holds must be resolved with the customer and possibly Microsoft before these mailboxes can migrate."
        $res = Format-MdTable -Rows @($holds | Sort-Object UserPrincipalName) -Columns 'UserPrincipalName','DisplayName','HoldReasons'
        $att = @('MailboxHolds.csv')
    } else {
        $status = 'OK'
        $concl = 'No mailboxes are on hold - Orchestrator can migrate all mailboxes.'
        $res = "_No holds found._"
        $att = $null
    }
    Add-Check -Number 6 -Title 'Mailboxes on hold' -Status $status -Conclusion $concl `
        -Why 'Microsoft Migration Orchestrator rejects mailboxes on Litigation Hold, eDiscovery hold or retention hold. Holds must be identified and resolved early, as they can block an entire batch.' `
        -Commands "Get-EXOMailbox -Properties LitigationHoldEnabled,InPlaceHolds,ComplianceTagHoldApplied,RetentionHoldEnabled,DelayHoldApplied" `
        -Results $res -Attachments $att
} else {
    Add-CheckFailed -Number 6 -Title 'Mailboxes on hold' -Section 'Exchange' `
        -Why 'Orchestrator rejects mailboxes on hold - they must be identified early.' `
        -Commands 'Get-EXOMailbox -Properties LitigationHoldEnabled,InPlaceHolds'
}

# ============================================================
# 7. Shared mailboxes and permissions
# ============================================================
if ($holdsUnknown) {
    Add-CheckFailed -Number 7 -Title 'Shared mailboxes and permissions' -Section 'MailboxPermissions' `
        -Why 'Shared mailboxes and their delegated permissions (Full Access, SendAs, SendOnBehalf) are not fully covered by Orchestrator and must be planned separately.' `
        -Commands 'Get-EXOMailboxPermission; Get-EXORecipientPermission'
} elseif ($mbx) {
    $sharedCount = & $m 'sharedMailboxCount' 0
    if ($sharedCount -gt 0) {
        $status = 'Note'
        $concl = "$sharedCount shared/resource mailboxes (Shared/Room/Equipment) found. Orchestrator primarily moves user mailboxes - shared and resource mailboxes need a separate method (e.g. conversion to user in the mapping, or a third-party tool) and their delegated permissions must be re-established."
    } else {
        $status = 'OK'
        $concl = 'No shared or resource mailboxes found.'
    }
    $perms = Import-AttCsv 'MailboxPermissions.csv'
    $sendAs = Import-AttCsv 'SendAsPermissions.csv'
    $sharedRows = @($mbx | Where-Object { $_.RecipientTypeDetails -in 'SharedMailbox','RoomMailbox','EquipmentMailbox' })
    $res = Format-MdTable -Rows @($sharedRows | Sort-Object RecipientTypeDetails) -Columns 'UserPrincipalName','DisplayName','RecipientTypeDetails','TotalItemSizeGB'
    $att = @()
    if ($perms -and $perms.Count) { $res += "`n**Full Access permissions**`n" + (Format-MdTable -Rows $perms -Columns 'Mailbox','User','AccessRights'); $att += 'MailboxPermissions.csv' }
    if ($sendAs -and $sendAs.Count) { $res += "`n**SendAs permissions**`n" + (Format-MdTable -Rows $sendAs -Columns 'Mailbox','Trustee','AccessRights'); $att += 'SendAsPermissions.csv' }
    Add-Check -Number 7 -Title 'Shared mailboxes and permissions' -Status $status -Conclusion $concl `
        -Why 'Shared mailboxes and their delegated permissions (Full Access, SendAs, SendOnBehalf) are not fully covered by Orchestrator and must be planned separately.' `
        -Commands "Get-EXOMailboxPermission -Identity <shared mailboxes>`nGet-EXORecipientPermission -Identity <mailboxes>" `
        -Results $res -Attachments $att
} else {
    Add-CheckFailed -Number 7 -Title 'Shared mailboxes and permissions' -Section 'Exchange' `
        -Why 'Shared mailboxes and delegated permissions must be planned separately.' `
        -Commands 'Get-EXOMailboxPermission; Get-EXORecipientPermission'
}

# ============================================================
# 8. Mail flow
# ============================================================
$inConn  = Import-AttCsv 'InboundConnectors.csv'
$outConn = Import-AttCsv 'OutboundConnectors.csv'
$trules  = Import-AttCsv 'TransportRules.csv'
$jrules  = Import-AttCsv 'JournalRules.csv'
if ($holdsUnknown) {
    Add-CheckFailed -Number 8 -Title 'Mail flow' -Section 'Mailflow' `
        -Why 'Connectors (e.g. smarthost/scanner relay), transport rules, journaling and external forwarding do not follow the migration and must be recreated or retired in target.' `
        -Commands 'Get-TransportRule; Get-OutboundConnector; Get-JournalRule'
} elseif ($mbx) {
    $fwd = @($mbx | Where-Object { $_.ForwardingSmtpAddress -match '\S' })
    $nIn  = if ($inConn)  { $inConn.Count }  else { 0 }
    $nOut = if ($outConn) { $outConn.Count } else { 0 }
    $nTr  = if ($trules)  { $trules.Count }  else { 0 }
    $nJr  = if ($jrules)  { $jrules.Count }  else { 0 }
    $found = ($nIn + $nOut + $nTr + $nJr + $fwd.Count) -gt 0
    if ($found) {
        $status = 'Note'
        $concl = "Found $nIn inbound connector(s), $nOut outbound connector(s), $nTr transport rule(s), $nJr journal rule(s) and $($fwd.Count) mailbox(es) with external forwarding. These must be recreated or retired in Fabrikam - smarthost/relay dependencies must be clarified."
    } else {
        $status = 'OK'
        $concl = 'No connectors, transport rules, journal rules or external forwarding found.'
    }
    $res = ''
    $att = @()
    if ($inConn)  { $res += "**Inbound connectors**`n" + (Format-MdTable -Rows $inConn -Columns 'Name','Enabled','ConnectorType','SenderDomains') + "`n"; $att += 'InboundConnectors.csv' }
    if ($outConn) { $res += "**Outbound connectors**`n" + (Format-MdTable -Rows $outConn -Columns 'Name','Enabled','ConnectorType','RecipientDomains','SmartHosts') + "`n"; $att += 'OutboundConnectors.csv' }
    if ($trules)  { $res += "**Transport rules**`n" + (Format-MdTable -Rows $trules -Columns 'Name','State','Priority','Mode') + "`n"; $att += 'TransportRules.csv' }
    if ($jrules)  { $res += "**Journal rules**`n" + (Format-MdTable -Rows $jrules -Columns 'Name','Enabled','Scope','JournalEmailAddress') + "`n"; $att += 'JournalRules.csv' }
    if ($fwd)     { $res += "**External forwarding**`n" + (Format-MdTable -Rows $fwd -Columns 'UserPrincipalName','ForwardingSmtpAddress','DeliverToMailboxAndForward') + "`n" }
    if (-not $res) { $res = "_No mail flow configuration found._" }
    Add-Check -Number 8 -Title 'Mail flow' -Status $status -Conclusion $concl `
        -Why 'Connectors (e.g. smarthost/scanner relay), transport rules, journaling and external forwarding do not follow the migration and must be recreated or retired in target.' `
        -Commands "Get-InboundConnector; Get-OutboundConnector`nGet-TransportRule; Get-JournalRule`nGet-EXOMailbox -Properties ForwardingSmtpAddress" `
        -Results $res -Attachments $att
} else {
    Add-CheckFailed -Number 8 -Title 'Mail flow' -Section 'Exchange' `
        -Why 'Connectors, transport rules and forwarding do not follow the migration.' `
        -Commands 'Get-TransportRule; Get-OutboundConnector; Get-JournalRule'
}

# ============================================================
# 9. Purview / compliance
# ============================================================
$retPol  = Import-AttCsv 'RetentionPolicies.csv'
$caseHolds = Import-AttCsv 'CaseHoldPolicies.csv'
if ($retPol -or $caseHolds) {
    $eDisco = if ($caseHolds) { @($caseHolds | Where-Object { $_.Enabled -eq 'True' }).Count } else { 0 }
    if ($eDisco -gt 0) {
        $status = 'Critical'
        $concl = "$eDisco active eDiscovery case hold(s) found - mailboxes and sites under these holds cannot be migrated until legally resolved. In addition $(@($retPol).Count) retention policies must be recreated in Fabrikam."
    } elseif (@($retPol).Count -gt 0) {
        $status = 'Note'
        $concl = "$(@($retPol).Count) retention policies found - the policies do not follow the migration and must be recreated in Fabrikam (Purview) if the retention requirement still applies."
    } else {
        $status = 'Information'
        $concl = 'No retention policies or eDiscovery holds with real scope found.'
    }
    $res = ''
    $att = @()
    if ($retPol)    { $res += "**Retention policies**`n" + (Format-MdTable -Rows $retPol -Columns 'Name','Enabled','Mode','ExchangeLocation','SharePointLocation','OneDriveLocation') + "`n"; $att += 'RetentionPolicies.csv' }
    if ($caseHolds) { $res += "**eDiscovery case holds**`n" + (Format-MdTable -Rows $caseHolds -Columns 'CaseName','CaseStatus','HoldPolicyName','Enabled') + "`n"; $att += 'CaseHoldPolicies.csv' }
    $dlp = Import-AttCsv 'DlpPolicies.csv'
    if ($dlp) { $res += "**DLP policies**`n" + (Format-MdTable -Rows $dlp -Columns 'Name','Enabled','Mode') + "`n"; $att += 'DlpPolicies.csv' }
    if (-not $res) { $res = "_No compliance configuration found._" }
    Add-Check -Number 9 -Title 'Purview / compliance' -Status $status -Conclusion $concl `
        -Why 'Retention policies, eDiscovery holds, sensitivity labels and DLP do not follow the tenant migration and must be recreated. Legal holds can block migration of the affected mailboxes.' `
        -Commands "Get-RetentionCompliancePolicy -DistributionDetail`nGet-ComplianceCase; Get-CaseHoldPolicy`nGet-Label; Get-DlpCompliancePolicy" `
        -Results $res -Attachments $att
} elseif (Get-SectionFailure 'Purview') {
    Add-CheckFailed -Number 9 -Title 'Purview / compliance' -Section 'Purview' `
        -Why 'Retention and eDiscovery holds can block migration and must be recreated in target.' `
        -Commands 'Get-RetentionCompliancePolicy; Get-ComplianceCase'
} else {
    Add-Check -Number 9 -Title 'Purview / compliance' -Status 'OK' `
        -Conclusion 'No retention policies or eDiscovery holds found.' `
        -Why 'Retention policies, eDiscovery holds and DLP do not follow the tenant migration.' `
        -Commands 'Get-RetentionCompliancePolicy; Get-ComplianceCase' -Results '_No data found._'
}

# ============================================================
# 10. OneDrive
# ============================================================
$od = Import-AttCsv 'OneDrive.csv'
if ($od) {
    $totalGB = & $m 'oneDriveTotalGB' 0
    $top = @($od | Sort-Object { ConvertTo-Num $_.StorageUsageGB } -Descending | Select-Object -First 20)
    $concl = "$($od.Count) OneDrives with a total of $totalGB GB. Orchestrator moves the OneDrive content together with the user mailbox - very large OneDrives lengthen the duration of the batches."
    if ((Get-Metric 'spoDataSource' '') -match 'Graph') { $concl += ' Data was fetched from Microsoft 365 usage reports (D30) because SharePoint admin is not available as a guest.' }
    $res = "Total: **$totalGB GB** across $($od.Count) OneDrives.`n`n**Largest OneDrives**`n" + (Format-MdTable -Rows $top -Columns 'Owner','Url','StorageUsageGB','LastContentModifiedDate','LockState')
    Add-Check -Number 10 -Title 'OneDrive' -Status 'Information' -Conclusion $concl `
        -Why 'Orchestrator moves OneDrive together with the mailbox. Volume and the number of OneDrives are direct estimate drivers, and very large sites may need special handling.' `
        -Commands "Get-SPOSite -IncludePersonalSite `$true -Filter `"Url -like '-my.sharepoint.com/personal/'`"`nGET /reports/getOneDriveUsageAccountDetail(period='D30')" `
        -Results $res -Attachments @('OneDrive.csv','OneDriveUsage.csv')
} else {
    Add-CheckFailed -Number 10 -Title 'OneDrive' -Section 'OneDrive' `
        -Why 'OneDrive volume is a direct estimate driver.' `
        -Commands "Get-SPOSite -IncludePersonalSite `$true"
}

# ============================================================
# 11. SharePoint and Teams (outside Orchestrator scope)
# ============================================================
$sites = Import-AttCsv 'SharePointSites.csv'
$teams = Import-AttCsv 'Teams.csv'
if ($sites -or $teams) {
    $siteCount = if ($sites) { $sites.Count } else { 0 }
    $spGB = & $m 'sharePointTotalGB' 0
    $teamCount = & $m 'teamCount' $(if ($teams) { $teams.Count } else { 0 })
    $priv = & $m 'privateChannelCount' 0
    $shrd = & $m 'sharedChannelCount' 0
    if ($siteCount -gt 0 -or $teamCount -gt 0) {
        $status = 'Note'
        $concl = "$siteCount SharePoint sites ($spGB GB) and $teamCount teams ($priv private, $shrd shared channels) are outside Orchestrator's scope. The content requires SharePoint cross-tenant migration or a third-party tool, and team structure/membership must be recreated."
        if ((Get-Metric 'spoDataSource' '') -match 'Graph') { $concl += ' Data was fetched from Microsoft 365 usage reports (D30) because SharePoint admin is not available as a guest.' }
    } else {
        $status = 'OK'
        $concl = 'No SharePoint sites or teams found.'
    }
    $res = ''
    if ($teams) { $res += "**Teams**`n" + (Format-MdTable -Rows @($teams | Sort-Object { -(ConvertTo-Num $_.MemberCount) }) -Columns 'DisplayName','Visibility','IsArchived','MemberCount','OwnerCount','PrivateChannels','SharedChannels') + "`n" }
    if ($sites) { $res += "**Largest SharePoint sites**`n" + (Format-MdTable -Rows @($sites | Sort-Object { ConvertTo-Num $_.StorageUsageGB } -Descending) -Columns 'Url','Title','Template','StorageUsageGB','IsTeamsConnected','SharingCapability') }
    $att = @(); if ($teams) { $att += 'Teams.csv'; if (Import-AttCsv 'TeamsChannels.csv') { $att += 'TeamsChannels.csv' } }; if ($sites) { $att += 'SharePointSites.csv' }
    Add-Check -Number 11 -Title 'SharePoint and Teams (outside Orchestrator scope)' -Status $status -Conclusion $concl `
        -Why 'SharePoint sites, team channels, apps and devices are not covered by Migration Orchestrator and must be handled with SharePoint cross-tenant migration or a third-party tool.' `
        -Commands "Get-SPOSite -Limit All`nGET /groups?`$filter=resourceProvisioningOptions/Any(x:x eq 'Team')`nGET /teams/{id}/allChannels" `
        -Results $res -Attachments $att
} else {
    Add-CheckFailed -Number 11 -Title 'SharePoint and Teams (outside Orchestrator scope)' -Section 'SharePoint' `
        -Why 'SharePoint and team channels are not covered by Orchestrator.' `
        -Commands 'Get-SPOSite -Limit All; GET /teams/{id}/allChannels'
}

# ============================================================
# 12. Teams Phone
# ============================================================
$phoneUsers = Import-AttCsv 'TeamsPhoneUsers.csv'
$phoneNums  = Import-AttCsv 'TeamsPhoneNumbers.csv'
$teamsSectionFailed = Get-SectionFailure 'Teams'
if ($phoneUsers -or $phoneNums) {
    $pCount = @($phoneUsers).Count + @($phoneNums).Count
    if ($pCount -gt 0) {
        $status = 'Note'
        $concl = "Teams Phone is in use: $(@($phoneUsers).Count) user(s) with a phone number/Enterprise Voice and $(@($phoneNums).Count) number record(s). Number porting must be planned separately and can cause telephony downtime."
    } else {
        $status = 'OK'
        $concl = 'Teams Phone does not appear to be in use.'
    }
    $res = ''
    $att = @()
    if ($phoneUsers) { $res += "**Users with telephony**`n" + (Format-MdTable -Rows $phoneUsers -Columns 'UserPrincipalName','EnterpriseVoiceEnabled','LineUri','OnPremLineUri') + "`n"; $att += 'TeamsPhoneUsers.csv' }
    if ($phoneNums)  { $res += "**Phone numbers**`n" + (Format-MdTable -Rows $phoneNums -Columns 'TelephoneNumber','NumberType','AssignedPstnTargetId','PstnAssignmentStatus') + "`n"; $att += 'TeamsPhoneNumbers.csv' }
    Add-Check -Number 12 -Title 'Teams Phone' -Status $status -Conclusion $concl `
        -Why 'Teams Phone numbers do not follow the tenant migration - number porting or new numbers must be planned, and there may be SLA/downtime risks.' `
        -Commands "Get-CsOnlineUser`nGet-CsPhoneNumberAssignment`nGet-CsAutoAttendant; Get-CsCallQueue" `
        -Results $res -Attachments $att
} elseif ((Get-Metric 'teamsPhoneLicensed' $true) -eq $false -or (Get-SectionFailure 'TeamsPhone') -match 'no license') {
    Add-Check -Number 12 -Title 'Teams Phone' -Status 'OK' -Conclusion 'The tenant has no Teams Phone/Calling Plan license - telephony is not in use and is not part of the migration.' `
        -Why 'Teams Phone numbers do not follow the tenant migration - number porting or new numbers must be planned.' `
        -Commands 'Get-CsOnlineUser; Get-CsPhoneNumberAssignment' -Results '_Not collected: no Teams Phone license._'
} elseif ($teamsSectionFailed) {
    Add-CheckFailed -Number 12 -Title 'Teams Phone' -Section 'Teams' `
        -Why 'Teams Phone numbers must be ported separately.' `
        -Commands 'Get-CsOnlineUser; Get-CsPhoneNumberAssignment'
} else {
    Add-Check -Number 12 -Title 'Teams Phone' -Status 'OK' -Conclusion 'No Teams Phone users or numbers found.' `
        -Why 'Teams Phone numbers do not follow the tenant migration.' `
        -Commands 'Get-CsOnlineUser; Get-CsPhoneNumberAssignment' -Results '_No telephony data found._'
}

# ============================================================
# 13. Devices
# ============================================================
$entraDev = Import-AttCsv 'EntraDevices.csv'
$intuneDev = Import-AttCsv 'IntuneDevices.csv'
if ($entraDev -or $intuneDev) {
    $byJoin = @{}
    foreach ($g in (@($entraDev) | Group-Object JoinType)) { $byJoin[$g.Name] = $g.Count }
    $hybridJoined = if ($byJoin['Hybrid Entra joined']) { $byJoin['Hybrid Entra joined'] } else { 0 }
    $entraJoined  = if ($byJoin['Entra joined']) { $byJoin['Entra joined'] } else { 0 }
    $intuneSkipped = Test-LicenseSkipped 'Intune'
    if (($hybridJoined + $entraJoined) -gt 0) {
        $status = 'Note'
        $concl = "$($entraDev.Count) devices in Entra ID, of which $hybridJoined hybrid-joined and $entraJoined Entra-joined Windows devices. Devices must be wiped/re-enrolled in Fabrikam's Intune - that requires user handling and possibly Autopilot re-deployment."
    } else {
        $status = 'Information'
        $concl = "$($entraDev.Count) devices in Entra ID, primarily registered ones (e.g. mobile). Re-enrollment is relatively simple."
    }
    if ($intuneSkipped) { $concl += ' Intune data not collected: no Intune license in the tenant.' }
    $res = "**Devices per join type**`n" + (Format-MdTable -Rows @($byJoin.GetEnumerator() | ForEach-Object { [pscustomobject]@{ JoinType = $_.Key; Count = $_.Value } }) -Columns 'JoinType','Count')
    if ($intuneDev) {
        $byOs = @($intuneDev | Group-Object OperatingSystem | Sort-Object Count -Descending | ForEach-Object { [pscustomobject]@{ OS = $_.Name; Count = $_.Count } })
        $res += "`n**Intune devices per OS**`n" + (Format-MdTable -Rows $byOs -Columns 'OS','Count')
    }
    $att = @(); if ($intuneDev) { $att += 'IntuneDevices.csv' }; if ($entraDev) { $att += 'EntraDevices.csv' }; if (Import-AttCsv 'AutopilotDevices.csv') { $att += 'AutopilotDevices.csv' }
    Add-Check -Number 13 -Title 'Devices' -Status $status -Conclusion $concl `
        -Why 'Devices do not follow the user to the new tenant - Entra join and Intune enrollment must be established anew in Fabrikam (typically wipe or OOBE/Autopilot). Hybrid-joined devices also require AD Connect rework.' `
        -Commands "GET /deviceManagement/managedDevices`nGET /devices`nGET /deviceManagement/windowsAutopilotDeviceIdentities" `
        -Results $res -Attachments $att
} else {
    Add-CheckFailed -Number 13 -Title 'Devices' -Section 'Devices' `
        -Why 'Devices must be re-enrolled in the target tenant.' `
        -Commands 'GET /deviceManagement/managedDevices; GET /devices'
}

# ============================================================
# 14. Intune policies and apps
# ============================================================
$pol = Import-AttCsv 'IntunePolicies.csv'
if (Test-LicenseSkipped 'IntunePolicies') {
    Add-Check -Number 14 -Title 'Intune policies and apps' -Status 'Information' `
        -Conclusion 'Intune data not collected: no Intune license in the tenant. Intune is not in use and is not part of the migration.' `
        -Why 'Intune configuration is not transferred automatically.' `
        -Commands 'GET /deviceManagement/* (Microsoft Graph)' -Results '_Not collected: no Intune license._'
} elseif ($pol -or (Get-SectionFailure 'Devices')) {
    if ($pol) {
        $byType = @($pol | Group-Object PolicyType | Sort-Object Count -Descending | ForEach-Object { [pscustomobject]@{ Type = $_.Name; Count = $_.Count } })
        $concl = "$($pol.Count) Intune policies and apps across $(@($byType).Count) types. The configuration must be recreated manually or exported in Fabrikam's Intune."
        $res = Format-MdTable -Rows $byType -Columns 'Type','Count'
        $res += "`n" + (Format-MdTable -Rows @($pol | Sort-Object PolicyType, Name) -Columns 'PolicyType','Name','LastModified')
        Add-Check -Number 14 -Title 'Intune policies and apps' -Status 'Information' -Conclusion $concl `
            -Why 'Intune configuration (compliance, configuration profiles, apps, app protection) is not transferred automatically and must be recreated in target - the count is an estimate driver.' `
            -Commands "GET /deviceManagement/deviceCompliancePolicies`nGET /deviceManagement/deviceConfigurations`nGET /deviceAppManagement/mobileApps`nGET /deviceAppManagement/managedAppPolicies" `
            -Results $res -Attachments @('IntunePolicies.csv')
    } else {
        Add-CheckFailed -Number 14 -Title 'Intune policies and apps' -Section 'Devices' `
            -Why 'Intune configuration must be recreated in target.' `
            -Commands 'GET /deviceManagement/* (Microsoft Graph)'
    }
} else {
    Add-Check -Number 14 -Title 'Intune policies and apps' -Status 'Information' `
        -Conclusion 'No Intune policies or apps found - Intune is probably not in use.' `
        -Why 'Intune configuration is not transferred automatically.' `
        -Commands 'GET /deviceManagement/* (Microsoft Graph)' -Results '_No data found._'
}

# ============================================================
# 15. Enterprise apps and SSO
# ============================================================
$entApps = Import-AttCsv 'EnterpriseApps.csv'
if ($entApps) {
    $sso = @($entApps | Where-Object { $_.PreferredSingleSignOnMode -in 'saml','oidc' })
    if ($sso.Count -gt 0) {
        $status = 'Note'
        $concl = "$($entApps.Count) non-Microsoft enterprise apps, of which $($sso.Count) have SSO (SAML/OIDC). SSO apps must be reconfigured against the new tenant (new app registrations and metadata exchange)."
    } else {
        $status = 'Information'
        $concl = "$($entApps.Count) non-Microsoft enterprise apps - none with SSO configured."
    }
    $res = Format-MdTable -Rows @($entApps | Sort-Object PreferredSingleSignOnMode, DisplayName) -Columns 'DisplayName','ServicePrincipalType','PreferredSingleSignOnMode','AccountEnabled','Tags'
    Add-Check -Number 15 -Title 'Enterprise apps and SSO' -Status $status -Conclusion $concl `
        -Why 'Third-party applications with SAML or OIDC SSO against Contoso must be set up again against Fabrikam. The count is an estimate driver for the integration work.' `
        -Commands "GET /servicePrincipals (non-Microsoft-owned)`nGET /applications" `
        -Results $res -Attachments @('EnterpriseApps.csv','AppRegistrations.csv')
} else {
    Add-CheckFailed -Number 15 -Title 'Enterprise apps and SSO' -Section 'Apps' `
        -Why 'SSO applications must be reconfigured against the target tenant.' `
        -Commands 'GET /servicePrincipals; GET /applications'
}

# ============================================================
# 16. Conditional Access and MFA
# ============================================================
$ca = Import-AttCsv 'ConditionalAccess.csv'
$mfa = Import-AttCsv 'MfaRegistration.csv'
if (-not $ca -and -not $mfa -and (Test-LicenseSkipped 'ConditionalAccess')) {
    $secDef = Get-Metric 'securityDefaultsEnabled' $null
    Add-Check -Number 16 -Title 'Conditional Access and MFA' -Status 'Information' `
        -Conclusion ("Conditional Access and MFA registration not collected: no Entra ID P1 license in the tenant." + $(if ($secDef -eq $true) { ' Security Defaults is enabled.' } else { '' })) `
        -Why 'CA policies and MFA registrations are not transferred - users must register MFA again in Fabrikam.' `
        -Commands 'GET /identity/conditionalAccess/policies' -Results '_Not collected: no Entra ID P1 license._'
} elseif ($ca -or $mfa) {
    $caCount = if ($ca) { $ca.Count } else { 0 }
    $caEnabled = if ($ca) { @($ca | Where-Object State -eq 'enabled').Count } else { 0 }
    $mfaPct = 0
    if ($mfa -and $mfa.Count -gt 0) { $mfaPct = [math]::Round(100 * (@($mfa | Where-Object IsMfaRegistered -eq 'True').Count / $mfa.Count), 0) }
    $secDef = Get-Metric 'securityDefaultsEnabled' $null
    $concl = "$caCount Conditional Access policies ($caEnabled active) and $mfaPct% of users are MFA registered." + $(if ($secDef -eq $true) { ' Security Defaults is enabled.' } else { '' }) + ' CA policies must be recreated in Fabrikam.'
    $res = ''
    if ($ca)  { $res += "**Conditional Access**`n" + (Format-MdTable -Rows @($ca | Sort-Object DisplayName) -Columns 'DisplayName','State','GrantControls') + "`n" }
    if ($mfa) {
        $adminRows = @($mfa | Where-Object { $_.IsAdmin -eq 'True' } | Select-Object -First 20)
        $res += "**MFA registration: $mfaPct%**`n"
        $res += if ($adminRows) { Format-MdTable -Rows $adminRows -Columns 'UserPrincipalName','IsMfaRegistered','IsMfaCapable','MethodsRegistered' } else { "_No admin accounts in the registration data._`n" }
    }
    $att = @(); if ($ca) { $att += 'ConditionalAccess.csv' }; if ($mfa) { $att += 'MfaRegistration.csv' }
    Add-Check -Number 16 -Title 'Conditional Access and MFA' -Status 'Information' -Conclusion $concl `
        -Why 'CA policies and MFA registrations are not transferred - users must register MFA again in Fabrikam, and CA policies must be recreated. The current MFA coverage indicates the training need.' `
        -Commands "GET /identity/conditionalAccess/policies`nGET /policies/identitySecurityDefaultsEnforcementPolicy`nGET /reports/authenticationMethods/userRegistrationDetails" `
        -Results $res -Attachments $att
} else {
    Add-CheckFailed -Number 16 -Title 'Conditional Access and MFA' -Section 'Security' `
        -Why 'CA policies and MFA registrations are not transferred to target.' `
        -Commands 'GET /identity/conditionalAccess/policies'
}

# ============================================================
# 17. Guests and external sharing
# ============================================================
if ($users) {
    $guests = @($users | Where-Object IsGuest -eq 'True')
    $ext = Import-AttCsv 'ExternalUsers.csv'
    $spoSharing = Get-Metric 'spoSharingCapability' 'unknown'
    $concl = "$($guests.Count) guest accounts in Entra ID" + $(if ($ext) { " and $($ext.Count) external SharePoint users" } else { '' }) + ". Guest invitations do not follow the migration - guests must be invited again in Fabrikam. Tenant sharing is set to '$spoSharing'."
    $res = Format-MdTable -Rows @($guests | Select-Object -First 20 | Sort-Object DisplayName) -Columns 'UserPrincipalName','DisplayName','AccountEnabled'
    $att = @('Users.csv'); if ($ext) { $att += 'ExternalUsers.csv' }
    Add-Check -Number 17 -Title 'Guests and external sharing' -Status 'Information' -Conclusion $concl `
        -Why 'Guests (B2B) and externally shared content are not migrated - they must be invited again in target and external sharing links break during the migration.' `
        -Commands "GET /users?`$filter=userType eq 'Guest'`nGet-SPOExternalUser`nGet-SPOTenant" `
        -Results $res -Attachments $att
} else {
    Add-CheckFailed -Number 17 -Title 'Guests and external sharing' -Section 'Users' `
        -Why 'Guests and externally shared content are not migrated.' `
        -Commands 'GET /users; Get-SPOExternalUser'
}

# ============================================================
# 18. DNS
# ============================================================
$dns = Import-AttCsv 'Dns.csv'
if ($dns) {
    $noSpf   = @($dns | Where-Object { $_.HasSPF -ne 'True' })
    $noDmarc = @($dns | Where-Object { -not $_.DMARC })
    if ($noSpf.Count -gt 0 -or $noDmarc.Count -gt 0) {
        $status = 'Note'
        $concl = "Of $($dns.Count) domains checked, $($noSpf.Count) lack SPF and $($noDmarc.Count) lack DMARC. DNS changes (MX, autodiscover, SPF, DMARC) must be planned together with the domain move."
    } else {
        $status = 'OK'
        $concl = "All $($dns.Count) domains checked have SPF and DMARC. DNS changes must still be planned together with the domain move."
    }
    $res = Format-MdTable -Rows @($dns | Sort-Object Domain) -Columns 'Domain','MX','HasSPF','DMARC','Autodiscover','DkimSelector1','DkimSelector2'
    Add-Check -Number 18 -Title 'DNS' -Status $status -Conclusion $concl `
        -Why 'On the domain move, MX, autodiscover, SPF and DKIM/DMARC must be corrected at the same time as the verification in Fabrikam. Missing SPF/DMARC is also a mail-delivery risk during the transition.' `
        -Commands "Resolve-DnsName -Type MX,TXT,CNAME per verified domain`n# MX, SPF, DMARC, autodiscover, selector1/2._domainkey, enterpriseregistration" `
        -Results $res -Attachments @('Dns.csv')
} else {
    Add-CheckFailed -Number 18 -Title 'DNS' -Section 'Dns' `
        -Why 'MX, autodiscover, SPF and DKIM must be corrected on the domain move.' `
        -Commands 'Resolve-DnsName -Type MX,TXT,CNAME'
}

# ============================================================
# 19. Cross-tenant prerequisites (only when a target inventory is given)
# ============================================================
if ($targetSummary) {
    $orgRel = & $m 'orgRelationshipCount' 0
    $migEp  = & $m 'migrationEndpointCount' 0
    # Use target metrics when available
    if ($targetSummary.metrics) {
        if ($targetSummary.metrics.PSObject.Properties['orgRelationshipCount']) { $orgRel = $targetSummary.metrics.orgRelationshipCount }
        if ($targetSummary.metrics.PSObject.Properties['migrationEndpointCount']) { $migEp = $targetSummary.metrics.migrationEndpointCount }
    }
    $userMatches = Import-AttCsv 'Target_UserMatches.csv'
    $matchCount = if ($userMatches) { $userMatches.Count } else { 0 }
    if ($matchCount -gt 0) {
        $status = 'Note'
        $concl = "$matchCount target objects match source users (UPN prefix, mail address or displayName). Matches must be verified as MailUser objects for Orchestrator's identity mapping - user mailboxes in target can collide with the migration."
    } else {
        $status = 'Information'
        $concl = "Target has $orgRel organization relationship(s) and $migEp migration endpoint(s). No existing target objects match source users - identity mapping is expected to be uncomplicated (create MailUsers in target)."
    }
    $res = "**Cross-tenant relationships**`n" + (Format-MdTable -Rows @(
        [pscustomobject]@{ Key = 'Organization relationships in target'; Value = $orgRel },
        [pscustomobject]@{ Key = 'Migration endpoints in target'; Value = $migEp },
        [pscustomobject]@{ Key = 'MailUser objects in target'; Value = (& { if ($targetSummary.metrics -and $targetSummary.metrics.PSObject.Properties['mailUserCount']) { $targetSummary.metrics.mailUserCount } else { 'unknown' } }) },
        [pscustomobject]@{ Key = 'Users with a match between source and target'; Value = $matchCount }
    ) -Columns 'Key','Value')
    $att = @()
    if ($userMatches) { $res += "`n**User matches**`n" + (Format-MdTable -Rows $userMatches -Columns 'SourceUPN','TargetUPN','MatchType'); $att += 'Target_UserMatches.csv' }
    Add-Check -Number 19 -Title 'Cross-tenant prerequisites' -Status $status -Conclusion $concl `
        -Why 'Orchestrator requires the source users to exist as Mailboxes in Contoso and that corresponding MailUser objects exist in Fabrikam plus cross-tenant relations (organization relationship / migration endpoint).' `
        -Commands "GET /policies/crossTenantAccessPolicy`nGet-OrganizationRelationship; Get-MigrationEndpoint`nComparison of source and target Users.csv" `
        -Results $res -Attachments $att
} else {
    Add-Check -Number 19 -Title 'Cross-tenant prerequisites' -Status 'Information' `
        -Conclusion 'Data not collected: no target inventory was given (-TargetInventoryPath).' `
        -Why 'Orchestrator requires MailUser objects in target and cross-tenant relations.' `
        -Commands 'Get-OrganizationRelationship; Get-MigrationEndpoint' -Results '_Data not collected._'
}

# ============================================================
# 20. Usage data
# ============================================================
$concealed = [bool](Get-Metric 'concealedReports' $false)
$usageFiles = @('UsageEmailActivity.csv','UsageTeamsActivity.csv','UsageMailboxUsage.csv','UsageActiveUsers.csv') | Where-Object { Import-AttCsv $_ }
if ($usageFiles -or $concealed) {
    if ($concealed) {
        $status = 'Note'
        $concl = 'The usage reports are anonymised (UPNs shown as hash values). To get real user names the setting must be turned off in Microsoft 365 admin center > Settings > Org settings > Reports ("Display concealed user, group, and site names"). This tool does not change it automatically.'
    } else {
        $status = 'Information'
        $concl = "$($usageFiles.Count) usage reports collected (D30) - used to identify inactive users and realistic data volume."
    }
    $res = "**Collected reports:** " + ($usageFiles -join ', ')
    Add-Check -Number 20 -Title 'Usage data' -Status $status -Conclusion $concl `
        -Why 'Usage reports show actual activity per user and are used to separate active from inactive accounts in the estimate.' `
        -Commands "GET /reports/getEmailActivityUserDetail(period='D30')`nGET /reports/getTeamsUserActivityUserDetail(period='D30')`nGET /reports/getMailboxUsageDetail(period='D30')`nGET /reports/getOffice365ActiveUserDetail(period='D30')" `
        -Results $res -Attachments $usageFiles
} else {
    Add-CheckFailed -Number 20 -Title 'Usage data' -Section 'Usage' `
        -Why 'Usage reports show actual activity per user.' `
        -Commands 'GET /reports/get*UserDetail (Microsoft Graph)'
}

# ============================================================
# Assemble the report
# ============================================================
$report = [System.Text.StringBuilder]::new()
$null = $report.AppendLine("# Tenant Inventory - $CustomerName")
$null = $report.AppendLine()
$null = $report.AppendLine('_Review of a Microsoft 365 tenant ahead of a tenant-to-tenant migration to Fabrikam_')
$null = $report.AppendLine()
$null = $report.AppendLine('| Field | Value |')
$null = $report.AppendLine('|---|---|')
$null = $report.AppendLine("| Customer | $CustomerName |")
$null = $report.AppendLine("| Report date | $(Get-Date -Format 'yyyy-MM-dd HH\:mm') |")
$null = $report.AppendLine("| Tenant | $($summary.tenantName) |")
$null = $report.AppendLine("| Tenant ID | $(& $m 'tenantId' 'unknown') |")
$null = $report.AppendLine("| Collected by | $($summary.collectedBy) |")
$acctType = Get-Metric 'collectedByUserType' $null
$acctStr = "$($summary.collectedBy)"
if ($acctType) { $acctStr += " ($(if ($acctType -eq 'Guest') { 'Guest' } else { 'Member' }))" }
$null = $report.AppendLine("| Collection account | $acctStr |")
$tidVerified = Get-Metric 'tenantIdVerified' $null
$null = $report.AppendLine("| Tenant ID verified | $(if ($null -eq $tidVerified) { 'unknown' } elseif ($tidVerified) { 'Yes' } else { 'No' }) |")
$initDom = Get-Metric 'initialDomain' $null
if ($initDom) { $null = $report.AppendLine("| Tenant domain | $initDom |") }
$null = $report.AppendLine("| Role | $($summary.role) |")
$null = $report.AppendLine("| Tool version | $($summary.toolVersion) |")
$null = $report.AppendLine()

if ([bool](Get-Metric 'guestMode' $false)) {
    $null = $report.AppendLine('## Limitations of a guest account')
    $null = $report.AppendLine()
    $null = $report.AppendLine('Data was collected with a **B2B guest account** in the source tenant. The following areas are limited or fetched via Graph fallback (usage reports):')
    $null = $report.AppendLine()
    $null = $report.AppendLine('- **SharePoint/OneDrive:** SharePoint admin center is not supported for guests - site and size data was fetched from Microsoft 365 usage reports (D30).')
    $null = $report.AppendLine('- **Exchange:** Exchange Online PowerShell does not necessarily support B2B guests - mailbox sizes were fetched from usage reports.')
    $null = $report.AppendLine('- **Holds, permissions and mail flow** (connectors, transport rules, forwarding): CANNOT be checked without Exchange PowerShell - must be repeated with a member account before the estimate is locked.')
    $null = $report.AppendLine('- **Retention policies:** require an IPPS connection; eDiscovery cases were fetched via Graph where possible.')
    $null = $report.AppendLine()
}

$licenseSkipped = @()
if ($summary.skippedSections) {
    foreach ($p in $summary.skippedSections.PSObject.Properties) {
        if ("$($p.Value)" -match '^Not collected: no license') { $licenseSkipped += [pscustomobject]@{ Section = $p.Name; Reason = $p.Value } }
    }
}
if ($licenseSkipped) {
    $null = $report.AppendLine('## Sections not collected due to missing license')
    $null = $report.AppendLine()
    $null = $report.AppendLine('| Section | Reason |')
    $null = $report.AppendLine('|---|---|')
    foreach ($l in $licenseSkipped) { $null = $report.AppendLine("| $($l.Section) | $(Get-Truncated "$($l.Reason)" 150) |") }
    $null = $report.AppendLine()
}

if ($summary.failedSections -and @($summary.failedSections.PSObject.Properties).Count -gt 0) {
    $null = $report.AppendLine('## Sections that failed during collection')
    $null = $report.AppendLine()
    $null = $report.AppendLine('| Section | Error |')
    $null = $report.AppendLine('|---|---|')
    foreach ($p in $summary.failedSections.PSObject.Properties) {
        $null = $report.AppendLine("| $($p.Name) | $(Get-Truncated "$($p.Value)" 150) |")
    }
    $null = $report.AppendLine()
}

$null = $report.AppendLine('## Summary')
$null = $report.AppendLine()
$null = $report.AppendLine('The table below shows the status of each check. Click a check to see the details.')
$null = $report.AppendLine()
$null = $report.AppendLine('| Check | Status | Short conclusion |')
$null = $report.AppendLine('|---|---|---|')
foreach ($c in $checks) {
    $null = $report.AppendLine("| [$($c.Number). $($c.Title) check]($($c.Anchor)) | $($c.Status) | $($c.Conclusion) |")
}
$null = $report.AppendLine()
$null = $report.Append($body.ToString())

# ============================================================
# Estimate drivers
# ============================================================
$byJoinDrivers = @{}
$entra = Import-AttCsv 'EntraDevices.csv'
if ($entra) { foreach ($g in ($entra | Group-Object JoinType)) { $byJoinDrivers[$g.Name] = $g.Count } }
$joinStr = ($byJoinDrivers.GetEnumerator() | ForEach-Object { "$($_.Key): $($_.Value)" }) -join ', '

$drivers = @(
    [pscustomobject]@{ Driver = 'Active members (<90 days)';        Value = ([int](& $m 'memberCount' 0) - [int](& $m 'inactive90dCount' 0)) },
    [pscustomobject]@{ Driver = 'Mailboxes total';                   Value = (& $m 'mailboxCount' 0) },
    [pscustomobject]@{ Driver = 'Mailbox data (GB)';                 Value = (& $m 'totalMailboxGB' 0) },
    [pscustomobject]@{ Driver = 'Archive data (GB)';                     Value = (& $m 'totalArchiveGB' 0) },
    [pscustomobject]@{ Driver = 'Mailboxes on hold';                 Value = (& $m 'mailboxesWithHolds' 0) },
    [pscustomobject]@{ Driver = 'Shared/resource mailboxes';         Value = (& $m 'sharedMailboxCount' 0) },
    [pscustomobject]@{ Driver = 'Mailboxes >50 GB';                  Value = (& $m 'mailboxesOver50GB' 0) },
    [pscustomobject]@{ Driver = 'OneDrives';                          Value = (& $m 'oneDriveCount' 0) },
    [pscustomobject]@{ Driver = 'OneDrive data (GB)';                 Value = (& $m 'oneDriveTotalGB' 0) },
    [pscustomobject]@{ Driver = 'SharePoint sites';                   Value = (& $m 'sharePointSiteCount' 0) },
    [pscustomobject]@{ Driver = 'SharePoint data (GB)';               Value = (& $m 'sharePointTotalGB' 0) },
    [pscustomobject]@{ Driver = 'Teams';                              Value = (& $m 'teamCount' 0) },
    [pscustomobject]@{ Driver = 'Private/shared channels';              Value = "$( & $m 'privateChannelCount' 0 ) / $( & $m 'sharedChannelCount' 0 )" },
    [pscustomobject]@{ Driver = 'Devices per join type';              Value = $joinStr },
    [pscustomobject]@{ Driver = 'Enterprise apps (non-MS)';          Value = (& $m 'enterpriseAppCount' 0) },
    [pscustomobject]@{ Driver = 'SSO-apps (SAML/OIDC)';               Value = "$(& $m 'ssoSamlApps' 0) / $(& $m 'ssoOidcApps' 0)" },
    [pscustomobject]@{ Driver = 'Conditional Access policies';      Value = (& $m 'conditionalAccessCount' 0) },
    [pscustomobject]@{ Driver = 'Distribution groups';               Value = (& $m 'distributionGroupCount' 0) },
    [pscustomobject]@{ Driver = 'Hybrid identity (AD Connect)';      Value = $hybridDriver },
    [pscustomobject]@{ Driver = 'Teams Phone in use';                 Value = $(if (& $m 'teamsPhone' $false) { 'Yes' } else { 'No' }) },
    [pscustomobject]@{ Driver = 'Retention policies';                Value = (& $m 'retentionPolicyCount' 0) },
    [pscustomobject]@{ Driver = 'eDiscovery holds';                    Value = (& $m 'ediscoveryHoldCount' 0) }
)

$null = $report.AppendLine('## Estimate drivers')
$null = $report.AppendLine()
$null = $report.AppendLine('Key figures that drive the cost and time estimate for the migration.')
$null = $report.AppendLine()
$null = $report.AppendLine('| Driver | Value |')
$null = $report.AppendLine('|---|---|')
foreach ($d in $drivers) { $null = $report.AppendLine("| $($d.Driver) | $($d.Value) |") }
$null = $report.AppendLine()

$reviewPath = Join-Path $InventoryPath 'Review.md'
$report.ToString() | Out-File -FilePath $reviewPath -Encoding utf8BOM
Write-Host "Report written to $reviewPath" -ForegroundColor Green
