#requires -Version 7.2
# Adapted from mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit@4de1a31 (MIT). See THIRD-PARTY-NOTICES.md.
# Changes: new script for shared/resource mailboxes (Mezba's New-TargetMailUsers is for users only);
# stamps ExchangeGuid/ArchiveGuid/x500 because these go via MRS, NOT via CTIM; uses the Common
# tenant guard; refuses existing mailboxes and non-accepted domains; writes to customers/ output.
<#
.SYNOPSIS
    Creates target MailUsers for shared/room/equipment mailboxes and stamps the source
    ExchangeGuid/ArchiveGuid/x500 attributes so MRS can connect the source mailbox to them.

.DESCRIPTION
    IMPORTANT - this is the one place where stamping ExchangeGuid, ArchiveGuid and x500 addresses
    is correct: shared/resource mailboxes do NOT go through the Migration Orchestrator or CTIM;
    they use the documented cross-tenant mailbox migration (New-MigrationBatch), which requires the
    target MailUser to carry those attributes (see the doc's example MailUser setup script).
    Do not confuse with 03-Identities/New-TargetMailUsers.ps1, where CTIM stamps everything and the
    script must NOT.

    Inputs:
      - the export from Export-SourceMailboxAttributes.ps1 (source attributes)
      - a mapping CSV: SourcePrimarySmtp -> TargetPrimarySmtp, Name

    Refuses rows whose TargetPrimarySmtp domain isn't an accepted domain in the target tenant,
    and rows where the target identity already exists as a mailbox (a licensed/reused object would
    get a conflicting ExchangeGuid - clean it up first per the doc's PreviousMailboxInfo note).
    Never stamps an SMTP address on the source domain (a single domain can't live in two tenants;
    x500: addresses are fine, smtp: ones are not).

.PARAMETER TenantId
    Target tenant ID (GUID).

.PARAMETER AdminUpn
    Target admin sign-in name.

.PARAMETER SourceAttributesCsv
    SourceMailboxAttributes.csv from Export-SourceMailboxAttributes.ps1.

.PARAMETER MappingCsv
    CSV with columns SourcePrimarySmtp, TargetPrimarySmtp, Name.

.PARAMETER Customer
    Writes the run report under customers/<Customer>/output/06-SharedMailboxes-Holds/.

.EXAMPLE
    .\New-SharedMailboxMailUsers.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@fabrikam.com' `
        -SourceAttributesCsv .\customers\contoso\output\06-SharedMailboxes-Holds\<ts>\SourceMailboxAttributes.csv `
        -MappingCsv .\customers\contoso\shared-mailbox-mapping.csv -Customer contoso -WhatIf

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Source: https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-mailbox-migration
    ("Prerequisites for target user objects" and the example MailUser setup script)
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$SourceAttributesCsv,

    [Parameter(Mandatory)]
    [string]$MappingCsv,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force

foreach ($f in $SourceAttributesCsv, $MappingCsv) { if (-not (Test-Path $f)) { throw "$f not found." } }
$attrs = @{}
foreach ($r in Import-Csv $SourceAttributesCsv) { $attrs["$($r.PrimarySmtpAddress)".ToLower()] = $r }
$mapping = @(Import-Csv $MappingCsv)
foreach ($m in $mapping) {
    if (-not $m.SourcePrimarySmtp -or -not $m.TargetPrimarySmtp) { throw "$MappingCsv needs SourcePrimarySmtp and TargetPrimarySmtp columns." }
}

$null = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn
$accepted = @((Get-AcceptedDomain).DomainName | ForEach-Object { "$_".ToLower() })

$log = [System.Collections.Generic.List[object]]::new()
function Add-Result($Obj, $Status, $Detail) {
    $log.Add([pscustomobject]@{ Object = $Obj; Status = $Status; Detail = $Detail })
    $c = @{ Created = 'Green'; Exists = 'Gray'; Refused = 'Red'; WhatIf = 'Cyan'; Problem = 'Red' }[$Status]
    Write-Host ("  [{0}] {1}: {2}" -f $Status, $Obj, $Detail) -ForegroundColor $c
}

foreach ($m in $mapping) {
    $src = $attrs["$($m.SourcePrimarySmtp)".Trim().ToLower()]
    if (-not $src) { Add-Result $m.SourcePrimarySmtp 'Refused' 'Not found in the export CSV - re-run Export-SourceMailboxAttributes.ps1'; continue }
    $tgtSmtp = "$($m.TargetPrimarySmtp)".Trim()
    $tgtDomain = $tgtSmtp.Split('@')[-1].ToLower()
    if ($accepted -notcontains $tgtDomain) { Add-Result $tgtSmtp 'Refused' "$tgtDomain is not an accepted domain in the target tenant"; continue }

    $existing = Get-Recipient -Identity $tgtSmtp -ErrorAction SilentlyContinue
    if ($existing) {
        if ("$($existing.RecipientTypeDetails)" -match 'Mailbox$') { Add-Result $tgtSmtp 'Refused' "Already a $($existing.RecipientTypeDetails) - a reused object blocks the move (see the doc's ExchangeGUID mismatch/PreviousMailboxInfo cleanup)" }
        else { Add-Result $tgtSmtp 'Exists' "Already a $($existing.RecipientTypeDetails); attributes not re-stamped" }
        continue
    }

    $x500s = @("$($src.X500Addresses)" -split ';' | Where-Object { $_ }) + @("x500:$($src.LegacyExchangeDN)")
    if ($PSCmdlet.ShouldProcess($tgtSmtp, "New-MailUser + stamp ExchangeGuid/ArchiveGuid/x500")) {
        try {
            $name = if ($m.Name) { $m.Name } else { $src.DisplayName }
            $meu = New-MailUser -Name $name -DisplayName $src.DisplayName -Alias $src.Alias `
                -MicrosoftOnlineServicesID $tgtSmtp -PrimarySmtpAddress $tgtSmtp `
                -ExternalEmailAddress "SMTP:$($src.PrimarySmtpAddress)" -ErrorAction Stop
            $set = @{ Identity = $meu.Identity; ExchangeGuid = $src.ExchangeGuid; EmailAddresses = @{ Add = $x500s }; ErrorAction = 'Stop' }
            if ($src.ArchiveStatus -eq 'Active' -and $src.ArchiveGuid) { $set.ArchiveGuid = $src.ArchiveGuid }
            Set-MailUser @set
            Add-Result $tgtSmtp 'Created' "ExchangeGuid $($src.ExchangeGuid), $($x500s.Count) x500(s) stamped"
        }
        catch { Add-Result $tgtSmtp 'Problem' $_.Exception.Message }
    }
    else { Add-Result $tgtSmtp 'WhatIf' "Would create MailUser and stamp $($x500s.Count) x500(s)" }
}

$out = New-OutputFolder -Customer $Customer -Phase '06-SharedMailboxes-Holds'
$file = Join-Path $out 'SharedMailboxMailUsers.csv'
$log | Export-CsvSafe -Path $file
Write-Host "Report: $file" -ForegroundColor Cyan
