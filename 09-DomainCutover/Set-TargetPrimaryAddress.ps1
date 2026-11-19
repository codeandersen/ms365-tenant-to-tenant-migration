#requires -Version 7.2
<#
.SYNOPSIS
    Sets the final primary SMTP address on shared/resource mailboxes in the target after the
    domain move, per the 06 mapping CSV - the counterpart to Set-TargetUpn for non-user mailboxes.

.DESCRIPTION
    Cutover-weekend step, run in the TARGET tenant after the domain is verified there and the
    shared/resource mailboxes exist (the 06 cross-tenant batch has completed). For each row of
    the 06 shared-mailbox mapping CSV that has a FinalPrimarySmtp value, the script sets the
    mailbox's primary address to it (Exchange keeps the old address as an alias automatically).
    Rows without FinalPrimarySmtp are reported and skipped.

    Guards:
      1. Backup: current PrimarySmtpAddress/EmailAddresses for every mapped mailbox is written
         to customers/<Customer>/output/09-DomainCutover/ BEFORE anything changes. A failed
         backup aborts the run.
      2. Domain: every FinalPrimarySmtp domain must be an ACCEPTED domain in the target tenant.

    One owner per object type: user UPNs/primary addresses belong to Set-TargetUpn.ps1; this
    script only touches the mailboxes in the 06 mapping CSV (shared, room, equipment).
    Switch-TargetAddresses.ps1 adds aliases/X500s and never sets a primary.

.PARAMETER TenantId
    Target tenant ID (GUID).

.PARAMETER AdminUpn
    Target admin sign-in name.

.PARAMETER SharedMailboxMappingPath
    The 06 shared/resource-mailbox mapping CSV (SourcePrimarySmtp, TargetPrimarySmtp, and the
    optional FinalPrimarySmtp column).

.PARAMETER Customer
    Output goes under customers/<Customer>/output/09-DomainCutover/.

.EXAMPLE
    .\Set-TargetPrimaryAddress.ps1 -TenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -AdminUpn 'admin@fabrikam.onmicrosoft.com' `
        -SharedMailboxMappingPath .\customers\contoso\shared-mailbox-mapping.csv -Customer contoso -WhatIf

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Requires: ExchangeOnlineManagement. Same hypothesis-order caveat as the rest of phase 09.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$SharedMailboxMappingPath,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
if (-not (Test-Path $SharedMailboxMappingPath)) { throw "Mapping CSV $SharedMailboxMappingPath not found." }
$rows = @(Import-Csv $SharedMailboxMappingPath | Where-Object { "$($_.FinalPrimarySmtp)".Trim() })
$all = @(Import-Csv $SharedMailboxMappingPath)
Write-Host "$($rows.Count) of $($all.Count) mapped mailbox(es) have a FinalPrimarySmtp." -ForegroundColor Cyan
if (-not $rows) { Write-Host 'Nothing to do.'; return }

$outDir = New-OutputFolder -Customer $Customer -Phase '09-DomainCutover'
$exo = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn
Write-Host "Signed in as $($exo.UserPrincipalName) to tenant $($exo.TenantID)" -ForegroundColor Cyan

# Guard 2 first - cheap: every final domain must be accepted here.
$accepted = @((Get-AcceptedDomain).DomainName | ForEach-Object { $_.ToLower() })
foreach ($r in $rows) {
    $d = "$($r.FinalPrimarySmtp)".Split('@')[-1].ToLower()
    if ($accepted -notcontains $d) { throw "$($r.FinalPrimarySmtp): domain $d is not an accepted domain in the target. Run Add-TargetDomain first." }
}

# Guard 1: per-object backup before any change. Abort the whole run if it fails.
$backupFile = Join-Path $outDir "SharedMailbox-backup-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
try {
    $backup = foreach ($r in $rows) {
        $mbx = Get-Mailbox -Identity "$($r.TargetPrimarySmtp)".Trim() -ErrorAction SilentlyContinue
        if ($mbx) {
            [pscustomobject]@{
                SourcePrimarySmtp  = "$($r.SourcePrimarySmtp)"
                TargetPrimarySmtp  = "$($r.TargetPrimarySmtp)"
                FinalPrimarySmtp   = "$($r.FinalPrimarySmtp)".Trim()
                RecipientTypeDetails = "$($mbx.RecipientTypeDetails)"
                EmailAddresses     = (@($mbx.EmailAddresses) -join ';')
            }
        }
        else {
            [pscustomobject]@{
                SourcePrimarySmtp  = "$($r.SourcePrimarySmtp)"
                TargetPrimarySmtp  = "$($r.TargetPrimarySmtp)"
                FinalPrimarySmtp   = "$($r.FinalPrimarySmtp)".Trim()
                RecipientTypeDetails = 'NOT-FOUND'
                EmailAddresses     = ''
            }
        }
    }
    $backup | Export-CsvSafe -Path $backupFile
    Write-Host "Backup of $($backup.Count) mailbox(es) written to $backupFile" -ForegroundColor Green
}
catch { throw "Mailbox backup failed ($($_.Exception.Message)) - refusing to change anything without a backup." }

$log = [System.Collections.Generic.List[object]]::new()
function Add-Result($Object, $Status, $Detail) {
    $log.Add([pscustomobject]@{ Mailbox = $Object; Status = $Status; Detail = $Detail })
    $c = @{ Done = 'Green'; Refused = 'Yellow'; Warn = 'Yellow'; Skipped = 'Gray'; Problem = 'Red' }[$Status]
    Write-Host ("  [{0}] {1}: {2}" -f $Status, $Object, $Detail) -ForegroundColor $c
}

foreach ($r in $rows) {
    $tgt = "$($r.TargetPrimarySmtp)".Trim()
    $final = "$($r.FinalPrimarySmtp)".Trim()
    $mbx = Get-Mailbox -Identity $tgt -ErrorAction SilentlyContinue
    if (-not $mbx) { Add-Result $tgt 'Refused' 'Mailbox not found in the target - has the 06 batch completed?'; continue }
    if ("$($mbx.RecipientTypeDetails)" -eq 'UserMailbox') { Add-Result $tgt 'Refused' 'UserMailbox - user primary addresses belong to Set-TargetUpn.ps1'; continue }
    if ("$($mbx.PrimarySmtpAddress)" -eq $final) { Add-Result $tgt 'Skipped' 'Already the primary address'; continue }
    if ($PSCmdlet.ShouldProcess($tgt, "Set primary address -> $final")) {
        try {
            Set-Mailbox -Identity $mbx.Identity -PrimarySmtpAddress $final -ErrorAction Stop
            Add-Result $tgt 'Done' "Primary address -> $final"
        }
        catch { Add-Result $tgt 'Problem' $_.Exception.Message }
    }
    else { Add-Result $tgt 'Skipped' "Would set primary address -> $final" }
}

$file = Join-Path $outDir "SetTargetPrimaryAddress-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
$log | Export-CsvSafe -Path $file
Write-Host "Report: $file" -ForegroundColor Cyan
