#requires -Version 7.2
<#
.SYNOPSIS
    Read-only: exports the attributes the target needs for shared/room/equipment mailboxes going
    via standard cross-tenant mailbox migration (MRS) instead of the Migration Orchestrator.

.DESCRIPTION
    The Orchestrator moves user workloads; shared and resource mailboxes go through the documented
    cross-tenant mailbox migration (New-MigrationBatch). For that, the target MailUser must be
    stamped with the source ExchangeGuid, ArchiveGuid (when archived), x500:LegacyExchangeDN and
    every source x500 address - this file is the source of truth for New-SharedMailboxMailUsers.ps1.

    Also exports hold flags: the Migration Orchestrator doc states "mailboxes on any type of hold
    aren't migrated, and a move for those mailboxes is blocked", and MRS moves fail on holds too.

.PARAMETER TenantId
    Source tenant ID (GUID).

.PARAMETER AdminUpn
    Source admin sign-in name.

.PARAMETER Identity
    Optional: only export these mailboxes (UPN/alias/smtp). Default: all shared, room and
    equipment mailboxes.

.PARAMETER Customer
    Writes the CSV under customers/<Customer>/output/06-SharedMailboxes-Holds/.

.EXAMPLE
    .\Export-SourceMailboxAttributes.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@contoso.com' -Customer contoso

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Source: https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-mailbox-migration
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [string[]]$Identity,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force

$null = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn

$types = 'SharedMailbox', 'RoomMailbox', 'EquipmentMailbox'
$mbx = if ($Identity) {
    foreach ($i in $Identity) {
        $m = Get-Mailbox -Identity $i -ErrorAction Stop
        if ("$($m.RecipientTypeDetails)" -notin $types) { Write-Warning "$i is a $($m.RecipientTypeDetails), not a shared/resource mailbox - exported anyway." }
        $m
    }
}
else {
    Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails $types
}

$rows = foreach ($m in @($mbx)) {
    $x500 = @($m.EmailAddresses | Where-Object { "$_" -match '^(X|x)500:' })
    $stats = Get-MailboxStatistics -Identity $m.Identity -ErrorAction SilentlyContinue
    [pscustomobject]@{
        PrimarySmtpAddress       = "$($m.PrimarySmtpAddress)".ToLower()
        DisplayName              = $m.DisplayName
        Alias                    = $m.Alias
        RecipientTypeDetails     = "$($m.RecipientTypeDetails)"
        ExchangeGuid             = $m.ExchangeGuid
        ArchiveGuid              = $m.ArchiveGuid
        ArchiveStatus            = "$($m.ArchiveStatus)"
        LegacyExchangeDN         = $m.LegacyExchangeDN
        X500Addresses            = ($x500 -join ';')
        MailboxSizeGB            = if ($stats -and $stats.TotalItemSize.Value) { [math]::Round($stats.TotalItemSize.Value.ToBytes() / 1GB, 2) } else { $null }
        LitigationHoldEnabled    = [bool]$m.LitigationHoldEnabled
        RetentionHoldEnabled     = [bool]$m.RetentionHoldEnabled
        ComplianceTagHoldApplied = [bool]$m.ComplianceTagHoldApplied
        DelayHoldApplied         = [bool]$m.DelayHoldApplied
        DelayReleaseHoldApplied  = [bool]$m.DelayReleaseHoldApplied
        InPlaceHolds             = (@($m.InPlaceHolds) -join ';')
    }
}

$rows | Format-Table PrimarySmtpAddress, RecipientTypeDetails, ArchiveStatus, LitigationHoldEnabled, InPlaceHolds -AutoSize | Out-Host
$out = New-OutputFolder -Customer $Customer -Phase '06-SharedMailboxes-Holds'
$file = Join-Path $out 'SourceMailboxAttributes.csv'
$rows | Export-CsvSafe -Path $file
Write-Host "Exported $($rows.Count) mailbox(es) to $file" -ForegroundColor Cyan
