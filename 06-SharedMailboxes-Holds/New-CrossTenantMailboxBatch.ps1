#requires -Version 7.2
<#
.SYNOPSIS
    Starts a standard cross-tenant mailbox migration batch (MRS) for shared/room/equipment
    mailboxes, which the Migration Orchestrator does not move.

.DESCRIPTION
    Builds the CSV the documented New-MigrationBatch call expects (an EmailAddress column holding
    the target MailUser's primary address) and starts the batch against the migration endpoint
    created in phase 02 (cross-tenant mailbox migration doc, "Migration batches"):

      New-MigrationBatch -Name <name> -SourceEndpoint <endpoint> -CSVData <bytes>
          -TargetDeliveryDomain <target onmicrosoft domain> [-Autostart] [-CompleteAfter <dt>]

    Any object flagged with a hold in SourceMailboxAttributes.csv (litigation, retention,
    compliance-tag, delay or in-place hold) is refused - the Orchestrator doc states "mailboxes on
    any type of hold aren't migrated" and MRS moves fail on them the same way. Resolve holds via
    the README's legal-first process first.

.PARAMETER TenantId
    Target tenant ID (GUID) - cross-tenant moves are initiated from the target.

.PARAMETER AdminUpn
    Target admin sign-in name.

.PARAMETER Name
    Batch name (unique).

.PARAMETER SourceEndpoint
    Name of the migration endpoint created in phase 02 (target tenant, pointing at the source).

.PARAMETER TargetDeliveryDomain
    Target tenant's onmicrosoft delivery domain, e.g. fabrikam.onmicrosoft.com.

.PARAMETER SourceAttributesCsv
    SourceMailboxAttributes.csv from Export-SourceMailboxAttributes.ps1 - used for hold checks.

.PARAMETER MappingCsv
    Shared-mailbox mapping CSV (SourcePrimarySmtp -> TargetPrimarySmtp). Only rows with a target
    address are batched; holds are checked against the source row.

.PARAMETER CompleteAfter
    Optional -CompleteAfter date/time for the batch.

.PARAMETER Autostart
    Pass -Autostart to New-MigrationBatch (start syncing immediately). Off by default.

.PARAMETER Customer
    Writes the run report under customers/<Customer>/output/06-SharedMailboxes-Holds/.

.EXAMPLE
    .\New-CrossTenantMailboxBatch.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@fabrikam.com' `
        -Name shared-wave1 -SourceEndpoint ep-fabrikam-contoso -TargetDeliveryDomain fabrikam.onmicrosoft.com `
        -SourceAttributesCsv .\SourceMailboxAttributes.csv -MappingCsv .\shared-mailbox-mapping.csv -Customer contoso -WhatIf

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Source: https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-mailbox-migration
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$Name,

    [Parameter(Mandatory)]
    [string]$SourceEndpoint,

    [Parameter(Mandatory)]
    [string]$TargetDeliveryDomain,

    [Parameter(Mandatory)]
    [string]$SourceAttributesCsv,

    [Parameter(Mandatory)]
    [string]$MappingCsv,

    [datetime]$CompleteAfter,

    [switch]$Autostart,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force

$attrs = @{}
foreach ($r in Import-Csv $SourceAttributesCsv) { $attrs["$($r.PrimarySmtpAddress)".ToLower()] = $r }
$mapping = @(Import-Csv $MappingCsv)

$holdFlags = 'LitigationHoldEnabled', 'RetentionHoldEnabled', 'ComplianceTagHoldApplied', 'DelayHoldApplied', 'DelayReleaseHoldApplied'
$work = [System.Collections.Generic.List[object]]::new()
$refused = [System.Collections.Generic.List[object]]::new()
foreach ($m in $mapping) {
    $src = $attrs["$($m.SourcePrimarySmtp)".Trim().ToLower()]
    $tgt = "$($m.TargetPrimarySmtp)".Trim()
    if (-not $src) { $refused.Add([pscustomobject]@{ Target = $tgt; Reason = 'not in export CSV' }); continue }
    if (-not $tgt) { $refused.Add([pscustomobject]@{ Target = $m.SourcePrimarySmtp; Reason = 'no TargetPrimarySmtp' }); continue }
    $holds = @($holdFlags | Where-Object { "$($src.$_)" -eq 'True' })
    if ("$($src.InPlaceHolds)") { $holds += "InPlaceHolds($($src.InPlaceHolds))" }
    if ($holds) { $refused.Add([pscustomobject]@{ Target = $tgt; Reason = "on hold: $($holds -join ', ') - mailbox moves are blocked while any hold applies" }); continue }
    $work.Add([pscustomobject]@{ EmailAddress = $tgt })
}

if ($refused) {
    $refused | Format-Table -AutoSize | Out-Host
    Write-Host "$($refused.Count) row(s) refused (see table)." -ForegroundColor Yellow
}
if (-not $work.Count) { throw 'No objects to migrate.' }

# The documented batch CSV is a single EmailAddress column of the target MailUser addresses.
$csvBytes = [System.Text.Encoding]::UTF8.GetBytes((($work | ConvertTo-Csv -NoTypeInformation) -join "`r`n"))
$null = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn

$params = @{
    Name                 = $Name
    SourceEndpoint       = $SourceEndpoint
    CSVData              = $csvBytes
    TargetDeliveryDomain = $TargetDeliveryDomain
    ErrorAction          = 'Stop'
}
if ($Autostart) { $params.AutoStart = $true }
if ($CompleteAfter) { $params.CompleteAfter = $CompleteAfter }

if ($PSCmdlet.ShouldProcess($Name, "New-MigrationBatch ($($work.Count) object(s))")) {
    New-MigrationBatch @params | Out-Null
    Write-Host "Batch '$Name' created. Monitor with Get-MigrationBatch -Identity '$Name'." -ForegroundColor Green
}
else { Write-Host "WhatIf: would create batch '$Name' with $($work.Count) object(s)." -ForegroundColor Cyan }

$out = New-OutputFolder -Customer $Customer -Phase '06-SharedMailboxes-Holds'
$work | Export-CsvSafe -Path (Join-Path $out 'BatchContents.csv')
if ($refused.Count) { $refused | Export-CsvSafe -Path (Join-Path $out 'BatchRefused.csv') }
Write-Host "Report: $out" -ForegroundColor Cyan
