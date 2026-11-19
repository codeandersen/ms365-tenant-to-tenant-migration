#requires -Version 7.2
# Adapted from mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit@4de1a31 (MIT). See THIRD-PARTY-NOTICES.md.
# Changes: playbook tenant guard via tools/Common.psm1 (Connect-MigrationGraph/Connect-MigrationExchange
# with mandatory GUID -TenantId and -AdminUpn); -Customer + output under customers/<Customer>/output/
# 09-DomainCutover/; Untested-against-live-tenants .NOTES added. See the file for details.

<#
.SYNOPSIS
    Cutover in the destination: gives every migrated recipient its old addresses back as aliases,
    and adds X500 addresses so replies to old mail don't bounce. Aliases only - it never changes
    a primary address.

.DESCRIPTION
    TL;DR: Run after Add-TargetDomain has verified the domains. For each source recipient in the
    address map (the 01 user list plus the optional 06 shared/resource-mailbox mapping) and each
    list or contact Copy-MailConfig created, it adds the recipient's old addresses on the moved
    domains and an X500 address built from its old LegacyExchangeDN. Everything else, for example
    people who already lived in the destination, just gets the old addresses as aliases. Safe to
    re-run. Supports -WhatIf.

    This script changes ADDRESSES ONLY - aliases and X500s, never the primary address.
    Sign-in names (UPNs) and user primary addresses change exclusively via Set-TargetUpn.ps1,
    which guards them behind the migration-batch Completed check; shared/resource-mailbox primary
    addresses via Set-TargetPrimaryAddress.ps1. One owner per object type.

    Why X500: migrated mail, meeting invites and Outlook's autocomplete address people by their old internal Exchange
    address, not their email address. Without a matching X500 address, replying to an old message bounces with an
    IMCEAEX non-delivery report.

    Before it changes anything it checks the snapshot is the -pre one (it holds addresses on the domain and
    LegacyExchangeDN values). A snapshot taken after Remove-SourceDomain stripped the addresses has neither, and on a
    live cutover that silently cost everyone their aliases and X500s. It stops unless you add -Force.

    It also checks every old address against the destination first. If a guest, mail user, contact or someone
    else's mailbox already holds it, that address is logged as Conflict and skipped. Guests are the usual culprit:
    when people from the source were invited into the destination as guests, the guest holds their old address.
    -RemoveConflictingGuests exports a backup of each guest (Id, UPN, mail, display name, creation
    date, group memberships) to the output folder and only then deletes the guest (it goes to the
    recycle bin for 30 days) and retries. A failed guest backup aborts the run.

    Matching is strictly by the mapping file's Destination column. Same-name mailboxes on other domains, for
    example another company hosted in the same destination tenant, are never touched.

    Tip: run it with -WhatIf first and read every Conflict and Problem line.
    Paid tool: most migration tools can add X500s during the final pass if you feed them the LegacyExchangeDN. Check
    the tool does it for groups and contacts too; many only do mailboxes.
    No script: Exchange admin centre > Recipients > the mailbox > Email addresses > add the old address and an X500
    "address type" entry by hand. Fine for five people.

.PARAMETER TenantId
    Destination tenant ID (GUID). Required.

.PARAMETER UserListPath
    The 01-Design migration-users.csv (SourcePrimarySmtp -> TargetPrimarySmtp/TargetUpn).

.PARAMETER SharedMailboxMappingPath
    Optional 06 shared/resource-mailbox mapping CSV (SourcePrimarySmtp -> TargetPrimarySmtp).

.PARAMETER SourceSnapshot
    SourceRecipients-pre-<stamp>.csv from Remove-SourceDomain. Holds the old addresses and LegacyExchangeDN values.
    Use the night's file: Remove-SourceDomain -SnapshotOnly run on cutover night just before the release (the
    -RemoveDomain run's own -pre file works too). The T-1 day file is the fallback. Never a -post file.

.PARAMETER Domain
    The domains that moved. Only addresses on these (and accepted in the destination) are added.

.PARAMETER AdminUpn
    Optional destination admin account. Open Exchange or Graph sessions for another account or tenant are
    disconnected first, and the script signs in again as this account.

.PARAMETER Force
    Carry on even if the snapshot looks like it was taken after the source addresses were removed.

.PARAMETER RemoveConflictingGuests
    When a destination guest (GuestMailUser) already holds an old address, back the guest up to a CSV
    (Id, UPN, mail, display name, creation date, group memberships), then delete it through Graph (it
    goes to the recycle bin) and retry the add. A failed backup aborts the run before the delete.
    Never touches mailboxes, mail users or contacts. Supports -WhatIf.

.EXAMPLE
    .\Switch-TargetAddresses.ps1 -TenantId <destination-guid> -AdminUpn admin@fabrikam.onmicrosoft.com -UserListPath .\customers\contoso\migration-users.csv -SourceSnapshot .\SourceRecipients-pre-<stamp>.csv `
        -Domain contoso.com -Customer contoso -WhatIf

.EXAMPLE
    .\Switch-TargetAddresses.ps1 -TenantId <destination-guid> -AdminUpn admin@fabrikam.onmicrosoft.com -UserListPath .\customers\contoso\migration-users.csv `
        -SharedMailboxMappingPath .\customers\contoso\shared-mailbox-mapping.csv -SourceSnapshot .\SourceRecipients-pre-<stamp>.csv -Domain contoso.com -Customer contoso -RemoveConflictingGuests

.NOTES
    Author  : Mezba Uddin (Microsoft MVP)
    Version : 1.1.1
    Date    : 2026-11-10
    Licence : MIT
    Repo    : https://github.com/mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit
    Requires: ExchangeOnlineManagement 3.x, Microsoft.Graph.Authentication, Microsoft.Graph.Users. Global Administrator
              (or User Administrator plus Exchange Administrator) in the destination.
    Untested against live tenants - validate in technical test/pilot.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$TenantId,
    [Parameter(Mandatory)][string]$UserListPath,
    [string]$SharedMailboxMappingPath,
    [Parameter(Mandatory)][string]$SourceSnapshot,
    [Parameter(Mandatory)][string[]]$Domain,
    [Parameter(Mandatory)][string]$AdminUpn,
    [Parameter(Mandatory)][string]$Customer,
    [switch]$Force,
    [switch]$RemoveConflictingGuests
)

$ErrorActionPreference = 'Stop'
$Domain = @($Domain | ForEach-Object { $_.Trim().ToLower() })

function Get-DomainOf($a) { "$a".Split('@')[-1].ToLower() }

# ------------------------------------------------------------ snapshot sanity, before connecting to anything
if (-not (Test-Path $SourceSnapshot)) { throw "Snapshot $SourceSnapshot not found." }
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force
$addressMap = Get-AddressMap -UserListPath $UserListPath -SharedMailboxMappingPath $SharedMailboxMappingPath
if ($addressMap.Duplicates) { Write-Warning "Duplicate source rows ignored: $($addressMap.Duplicates -join ', ')" }
$snapRows = @(Import-Csv $SourceSnapshot)
$mapRows = @($addressMap.Map.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Source = $_.Key; Destination = $_.Value } })
$withDomain = @($snapRows | Where-Object { "$($_.EmailAddresses)".Split(';') | Where-Object { $_ -match '^smtp:(.+)$' -and $Domain -contains (Get-DomainOf $Matches[1]) } }).Count
$withLegDn = @($snapRows | Where-Object { $_.LegacyExchangeDN }).Count
$snapAddr = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($row in $snapRows) {
    foreach ($a in "$($row.EmailAddresses)".Split(';')) { if ($a -match '^smtp:(.+)$') { [void]$snapAddr.Add($Matches[1]) } }
    [void]$snapAddr.Add("$($row.PrimarySmtpAddress)")
}
$mapped = @($mapRows | Where-Object { $Domain -contains (Get-DomainOf $_.Source.Trim()) })
$found = @($mapped | Where-Object { $snapAddr.Contains($_.Source.Trim()) }).Count
$pct = if ($mapped.Count) { [math]::Round(100 * $found / $mapped.Count) } else { 100 }
$stageCol = @($snapRows | Select-Object -First 1 -ExpandProperty SnapshotStage -ErrorAction SilentlyContinue)
Write-Host "Snapshot: $($snapRows.Count) rows, $withDomain with addresses on $($Domain -join ', '), $withLegDn with LegacyExchangeDN; $found of $($mapped.Count) mapped sources found ($pct%)." -ForegroundColor Cyan
if ($withDomain -eq 0 -or $withLegDn -eq 0 -or $pct -lt 20 -or $stageCol -contains 'AfterRelease') {
    $msg = 'This snapshot was taken after the source addresses were removed. Use the -pre snapshot.'
    if (-not $Force) { throw $msg }
    Write-Warning "$msg Carrying on because of -Force: expect 'Not in the source snapshot' lines and no X500s."
}

# ------------------------------------------------------------ connect and guard, as the named account
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
$outDir = New-OutputFolder -Customer $Customer -Phase '09-DomainCutover'
$exo = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn
$ctx = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'User.ReadWrite.All'
Write-Host "Signed in as $($exo.UserPrincipalName) (Exchange) and $($ctx.Account) (Graph) to tenant $TenantId" -ForegroundColor Cyan

$accepted = @((Get-AcceptedDomain).DomainName | ForEach-Object { $_.ToLower() })
$usable = @($Domain | Where-Object { $accepted -contains $_ })
foreach ($d in $Domain | Where-Object { $usable -notcontains $_ }) {
    Write-Warning "$d isn't an accepted domain here yet. Addresses on it are skipped. Run Add-TargetDomain -Verify first."
}
if (-not $usable) { throw 'None of the domains are accepted in this tenant yet.' }
Write-Host "Destination confirmed. Switching addresses on: $($usable -join ', ')" -ForegroundColor Cyan

# ------------------------------------------------------------ per-object backup BEFORE any change (playbook requirement)
# Snapshot every destination recipient that will be touched (UPN, PrimarySmtp, EmailAddresses).
$backupFile = Join-Path $outDir "TargetRecipients-backup-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
try {
    $backup = @(Get-Recipient -ResultSize Unlimited | ForEach-Object {
        $u = $null
        if ($_.ExternalDirectoryObjectId) { $u = Get-MgUser -UserId $_.ExternalDirectoryObjectId -Property UserPrincipalName -ErrorAction SilentlyContinue }
        [pscustomobject]@{
            PrimarySmtpAddress   = "$($_.PrimarySmtpAddress)".ToLower()
            RecipientTypeDetails = "$($_.RecipientTypeDetails)"
            UserPrincipalName    = if ($u) { $u.UserPrincipalName } else { '' }
            EmailAddresses       = (@($_.EmailAddresses) -join ';')
            ObjectId             = $_.ExternalDirectoryObjectId
        }
    })
    $backup | Export-CsvSafe -Path $backupFile
    Write-Host "Backup of $($backup.Count) destination recipients written to $backupFile" -ForegroundColor Green
}
catch { throw "Recipient backup failed ($($_.Exception.Message)) - refusing to change anything without a backup." }

# ------------------------------------------------------------ inputs
$snapIndex = @{}
foreach ($s in $snapRows) {
    foreach ($a in "$($s.EmailAddresses)".Split(';')) {
        if ($a -match '^smtp:(.+)$') { $snapIndex[$Matches[1].ToLower()] = $s }
    }
    $snapIndex["$($s.PrimarySmtpAddress)".ToLower()] = $s
}
$work = [System.Collections.Generic.List[object]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new()
foreach ($m in $mapRows) {
    if ($m.Source -and $m.Destination -and $seen.Add($m.Source.Trim().ToLower())) {
        $work.Add([pscustomobject]@{ Source = $m.Source.Trim().ToLower(); Destination = $m.Destination.Trim(); Origin = 'Mapping' })
    }
}
# Lists and contacts Copy-MailConfig created carry their source address in CustomAttribute15
foreach ($r in Get-Recipient -Filter "CustomAttribute15 -like 'T2T:*'" -ResultSize Unlimited -ErrorAction SilentlyContinue) {
    $src = "$($r.CustomAttribute15)".Substring(4).ToLower()
    if ($seen.Add($src)) { $work.Add([pscustomobject]@{ Source = $src; Destination = "$($r.PrimarySmtpAddress)"; Origin = 'Tagged' }) }
}
Write-Host "$($work.Count) recipients to process." -ForegroundColor Cyan

$log = [System.Collections.Generic.List[object]]::new()
function Add-Result($Object, $Status, $Detail) {
    $log.Add([pscustomobject]@{ Source = $Object; Status = $Status; Detail = $Detail })
    $c = @{ Done = 'Green'; Exists = 'Gray'; WhatIf = 'Cyan'; Skipped = 'Yellow'; Problem = 'Red'; Conflict = 'Magenta' }[$Status]
    Write-Host ("  [{0}] {1}: {2}" -f $Status, $Object, $Detail) -ForegroundColor $c
}

function Get-ConflictingRecipient($Address, $Dest) {
    # Returns the recipient holding $Address if it isn't $Dest, else $null
    $r = @(Get-EXORecipient -Identity $Address -Properties ExternalDirectoryObjectId, RecipientTypeDetails -ErrorAction SilentlyContinue)
    if (-not $r) { $r = @(Get-Recipient -Identity $Address -ErrorAction SilentlyContinue) }
    foreach ($x in $r) {
        $same = ($x.ExternalDirectoryObjectId -and "$($x.ExternalDirectoryObjectId)" -eq "$($Dest.ExternalDirectoryObjectId)") -or ("$($x.Guid)" -and "$($x.Guid)" -eq "$($Dest.Guid)")
        if (-not $same) { return $x }
    }
    $null
}
function Wait-AddressFree($Address, $Dest) {
    # Directory deletes take a minute or two to reach Exchange
    for ($i = 0; $i -lt 6; $i++) {
        Start-Sleep -Seconds 30
        if (-not (Get-ConflictingRecipient $Address $Dest)) { return $true }
    }
    $false
}

# ------------------------------------------------------------ per recipient
foreach ($w in $work) {
    # Strictly the mapping file's Destination: never a lookup by display name
    $dest = Get-EXORecipient -Identity $w.Destination -Properties EmailAddresses, ExternalDirectoryObjectId, RecipientTypeDetails -ErrorAction SilentlyContinue
    if (-not $dest) { Add-Result $w.Source 'Problem' "Destination $($w.Destination) not found"; continue }
    $type = "$($dest.RecipientTypeDetails)"
    $set = switch -Regex ($type) {
        '^GroupMailbox$'                          { 'Set-UnifiedGroup'; break }
        'Mailbox$'                                { 'Set-Mailbox'; break }
        '^Mail(Universal|NonUniversal)'           { 'Set-DistributionGroup'; break }
        '^DynamicDistributionGroup$'              { 'Set-DynamicDistributionGroup'; break }
        '^(MailUser|GuestMailUser)$'              { 'Set-MailUser'; break }
        '^MailContact$'                           { 'Set-MailContact'; break }
        default                                   { $null }
    }
    if (-not $set) { Add-Result $w.Source 'Problem' "Recipient type $type not handled"; continue }

    $have = @($dest.EmailAddresses | ForEach-Object { "$_".ToLower() })
    $snap = $snapIndex[$w.Source]
    $add = [System.Collections.Generic.List[string]]::new()
    if ($snap) {
        if ($type -ne 'MailContact') {
            foreach ($a in "$($snap.EmailAddresses)".Split(';')) {
                if ($a -match '^smtp:(.+)$' -and $usable -contains (Get-DomainOf $Matches[1])) { $add.Add("smtp:$($Matches[1].ToLower())") }
            }
        }
        if ($snap.LegacyExchangeDN) { $add.Add("X500:$($snap.LegacyExchangeDN)") }
        foreach ($a in "$($snap.EmailAddresses)".Split(';')) { if ($a -match '^x500:') { $add.Add("X500:$($a.Substring(5))") } }
    }
    elseif ($usable -contains (Get-DomainOf $w.Source) -and $type -ne 'MailContact') {
        $add.Add("smtp:$($w.Source)")
        Add-Result $w.Source 'Skipped' 'Not in the source snapshot, so no X500 address. Adding the address only'
    }
    $add = @($add | Select-Object -Unique | Where-Object { $have -notcontains $_.ToLower() })

    # Conflicts: an old address already on a different object in the destination
    $sourceBlocked = $false
    foreach ($a in @($add | Where-Object { $_ -like 'smtp:*' })) {
        $addr = $a.Substring(5)
        $other = Get-ConflictingRecipient $addr $dest
        if (-not $other) { continue }
        $what = "$($other.RecipientTypeDetails) $($other.DisplayName) ($($other.ExternalDirectoryObjectId))"
        if ($RemoveConflictingGuests -and "$($other.RecipientTypeDetails)" -eq 'GuestMailUser') {
            if ($PSCmdlet.ShouldProcess($what, "Delete guest holding $addr (recycle bin)")) {
                try {
                    # Back the guest up before deleting - aborts the run if the backup fails
                    $gu = Get-MgUser -UserId $other.ExternalDirectoryObjectId -Property Id, UserPrincipalName, Mail, DisplayName, CreatedDateTime -ErrorAction Stop
                    $membership = @((Get-MgUserMemberOf -UserId $gu.Id -All -ErrorAction SilentlyContinue).Id) -join ';'
                    $gbFile = Join-Path $outDir "GuestBackup-$($gu.Id).csv"
                    [pscustomobject]@{
                        Id = $gu.Id; UserPrincipalName = $gu.UserPrincipalName; Mail = $gu.Mail
                        DisplayName = $gu.DisplayName; CreatedDateTime = $gu.CreatedDateTime; MemberOf = $membership
                    } | Export-CsvSafe -Path $gbFile
                }
                catch { throw "Guest backup failed for $what ($($_.Exception.Message)) - aborting before any delete." }
                try {
                    Remove-MgUser -UserId $other.ExternalDirectoryObjectId
                    Add-Result $w.Source 'Done' "Deleted guest $what that held $addr"
                    if (Wait-AddressFree $addr $dest) { continue }
                    Add-Result $w.Source 'Conflict' "$addr still shows on the deleted guest after 3 minutes. Run again shortly"
                }
                catch { Add-Result $w.Source 'Problem' "Couldn't delete guest $($what): $($_.Exception.Message)" }
            }
            else { Add-Result $w.Source 'WhatIf' "Would delete guest $what that holds $addr, then add it"; continue }
        }
        else {
            $hint = if ("$($other.RecipientTypeDetails)" -eq 'GuestMailUser') { ' Rerun with -RemoveConflictingGuests, or delete the guest in Entra.' } else { ' Remove it from that object by hand if it should move.' }
            Add-Result $w.Source 'Conflict' "$addr is already used by $what. Skipped.$hint"
        }
        $add = @($add | Where-Object { $_ -ne $a })
        if ($addr -eq $w.Source) { $sourceBlocked = $true }
    }

    $id = if ($dest.ExternalDirectoryObjectId) { $dest.ExternalDirectoryObjectId } else { "$($dest.Identity)" }

    try {
        if ($add) {
            if ($PSCmdlet.ShouldProcess($w.Destination, "Add $($add.Count) address(es)")) {
                & $set -Identity $id -EmailAddresses @{ Add = $add } -ErrorAction Stop
                Add-Result $w.Source 'Done' "Added $($add -join ', ')"
            }
            else { Add-Result $w.Source 'WhatIf' "Would add $($add -join ', ')" }
        }
        if (-not $add -and -not $sourceBlocked) { Add-Result $w.Source 'Exists' 'Addresses already in place' }
    }
    catch { Add-Result $w.Source 'Problem' $_.Exception.Message; continue }
}

# ------------------------------------------------------------ report
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$log | Export-CsvSafe -Path (Join-Path $outDir "SwitchTargetAddresses-$stamp.csv")
Write-Host ''
$log | Group-Object Status | Sort-Object Name | ForEach-Object { Write-Host ("{0,-8} {1}" -f $_.Name, $_.Count) }
if ($log | Where-Object Status -eq 'Conflict') { Write-Host 'Conflicts: those addresses were not added. See the report for who holds each one.' -ForegroundColor Magenta }
Write-Host "Report: $(Join-Path $outDir "SwitchTargetAddresses-$stamp.csv")" -ForegroundColor Cyan
Write-Host 'Aliases only - no primary address was changed. UPNs/user primaries: Set-TargetUpn.ps1; shared/resource primaries: Set-TargetPrimaryAddress.ps1.' -ForegroundColor Yellow
