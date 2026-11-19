#requires -Version 7.2
<#
.SYNOPSIS
    Read-only: exports Full Access, Send As and Send on Behalf permissions for the mailboxes
    being migrated, so Set-TargetMailboxPermissions.ps1 can rebuild them on the target.

.DESCRIPTION
    Mailbox content moves; permissions don't come with it in a usable form. Exports, per mailbox:
      - Full Access    Get-MailboxPermission: non-inherited, non-deny, non-SELF/NT AUTHORITY/SID
      - Send As        Get-RecipientPermission: non-NT AUTHORITY/SID trustees
      - Send on Behalf GrantSendOnBehalfTo on the mailbox
    Trustees are resolved to SMTP addresses where possible; unresolvable ones are exported as
    'unresolved:<id>' and skipped at import - never guessed.

.PARAMETER TenantId
    Source tenant ID (GUID).

.PARAMETER AdminUpn
    Source admin sign-in name.

.PARAMETER Identity
    Optional: only these mailboxes. Default: all user and shared/resource mailboxes.

.PARAMETER Customer
    Writes the CSV under customers/<Customer>/output/06-SharedMailboxes-Holds/.

.EXAMPLE
    .\Export-MailboxPermissions.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@contoso.com' -Customer contoso

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Source: https://learn.microsoft.com/en-us/powershell/exchange/client-access (EXO cmdlets;
    see also the cross-tenant mailbox migration doc's permissions FAQ).
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

$mbx = if ($Identity) {
    foreach ($i in $Identity) { Get-Mailbox -Identity $i -ErrorAction Stop }
}
else {
    Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox, SharedMailbox, RoomMailbox, EquipmentMailbox
}

$cache = @{}
function Resolve-Smtp($id) {
    if (-not $id) { return $null }
    $k = "$id"
    if ($cache.ContainsKey($k)) { return $cache[$k] }
    $r = Get-Recipient -Identity $k -ErrorAction SilentlyContinue
    $cache[$k] = if ($r) { "$($r.PrimarySmtpAddress)".ToLower() } else { "unresolved:$k" }
    return $cache[$k]
}

$perm = [System.Collections.Generic.List[object]]::new()
foreach ($m in @($mbx)) {
    $addr = "$($m.PrimarySmtpAddress)".ToLower()
    $id = if ($m.ExternalDirectoryObjectId) { $m.ExternalDirectoryObjectId } else { $m.Identity }

    Get-MailboxPermission -Identity $id -ErrorAction SilentlyContinue |
        Where-Object { -not $_.IsInherited -and -not $_.Deny -and $_.AccessRights -contains 'FullAccess' -and
                       "$($_.User)" -notlike 'NT AUTHORITY\*' -and "$($_.User)" -notlike 'S-1-5-*' -and
                       "$($_.User)" -ne 'SELF' } |
        ForEach-Object { $perm.Add([pscustomobject]@{ Mailbox = $addr; Right = 'FullAccess'; Trustee = (Resolve-Smtp $_.User) }) }

    Get-RecipientPermission -Identity $id -ErrorAction SilentlyContinue |
        Where-Object { $_.AccessRights -contains 'SendAs' -and "$($_.Trustee)" -notlike 'NT AUTHORITY\*' -and "$($_.Trustee)" -notlike 'S-1-5-*' } |
        ForEach-Object { $perm.Add([pscustomobject]@{ Mailbox = $addr; Right = 'SendAs'; Trustee = (Resolve-Smtp $_.Trustee) }) }

    foreach ($d in @($m.GrantSendOnBehalfTo)) {
        if ($d) { $perm.Add([pscustomobject]@{ Mailbox = $addr; Right = 'SendOnBehalf'; Trustee = (Resolve-Smtp $d) }) }
    }
}

$perm | Format-Table -AutoSize | Out-Host
$out = New-OutputFolder -Customer $Customer -Phase '06-SharedMailboxes-Holds'
$file = Join-Path $out 'MailboxPermissions.csv'
$perm | Export-CsvSafe -Path $file
$un = @($perm | Where-Object Trustee -like 'unresolved:*').Count
Write-Host "Exported $($perm.Count) permission(s) to $file" -ForegroundColor Cyan
if ($un) { Write-Host "$un trustee(s) could not be resolved and will be skipped on import." -ForegroundColor Yellow }
