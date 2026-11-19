#requires -Version 7.2
<#
.SYNOPSIS
    Read-only: reports every hold that can block a mailbox move (litigation, retention, in-place,
    compliance-tag, delay holds) plus the Purview retention/eDiscovery policies that may cover the
    mailbox - the release decision is legal, not technical.

.DESCRIPTION
    The Migration Orchestrator doc states "mailboxes on any type of hold aren't migrated, and a
    move for those mailboxes is blocked"; standard MRS cross-tenant moves fail on them too.
    This script lists the facts. It deliberately does NOT remove anything - see the README for the
    legal/compliance process (preserve via eDiscovery export first, then release, and clean up
    DelayHold leftovers).

    Mailbox flags come from Exchange Online. Purview coverage (retention policies and eDiscovery
    case hold policies) comes from Security & Compliance PowerShell via Connect-MigrationCompliance.

.PARAMETER TenantId
    Source tenant ID (GUID).

.PARAMETER AdminUpn
    Source admin sign-in name.

.PARAMETER Identity
    Optional: only these mailboxes. Default: all user and shared/resource mailboxes.

.PARAMETER SkipPurview
    Don't connect to Security & Compliance PowerShell; mailbox flags only.

.PARAMETER Customer
    Writes the CSV under customers/<Customer>/output/06-SharedMailboxes-Holds/.

.EXAMPLE
    .\Get-HoldReport.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@contoso.com' -Customer contoso

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Sources:
      https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-mailbox-migration
      https://learn.microsoft.com/en-us/purview/ediscovery-create-holds (eDiscovery holds)
      https://learn.microsoft.com/en-us/purview/retention (retention policies)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [string[]]$Identity,

    [switch]$SkipPurview,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

$null = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn

$mbx = if ($Identity) {
    foreach ($i in $Identity) { Get-Mailbox -Identity $i -ErrorAction Stop }
}
else {
    Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox, SharedMailbox, RoomMailbox, EquipmentMailbox
}

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($m in @($mbx)) {
    $decoded = @(ConvertFrom-InPlaceHold -InPlaceHolds @($m.InPlaceHolds | ForEach-Object { "$_" }))
    $rows.Add([pscustomobject]@{
        PrimarySmtpAddress       = "$($m.PrimarySmtpAddress)".ToLower()
        RecipientTypeDetails     = "$($m.RecipientTypeDetails)"
        LitigationHoldEnabled    = [bool]$m.LitigationHoldEnabled
        RetentionHoldEnabled     = [bool]$m.RetentionHoldEnabled
        ComplianceTagHoldApplied = [bool]$m.ComplianceTagHoldApplied
        DelayHoldApplied         = [bool]$m.DelayHoldApplied
        DelayReleaseHoldApplied  = [bool]$m.DelayReleaseHoldApplied
        InPlaceHolds             = (@($m.InPlaceHolds) -join ';')
        InPlaceHoldsDecoded      = (@($decoded | ForEach-Object { "$($_.Prefix): $($_.Source)" }) -join ' | ')
        PurviewObject            = ''
        OnHold                   = ([bool]$m.LitigationHoldEnabled -or [bool]$m.RetentionHoldEnabled -or
                                    [bool]$m.ComplianceTagHoldApplied -or @($m.InPlaceHolds).Count -gt 0)
    })
}

# Purview: retention policies + eDiscovery case hold policies that could cover Exchange mailboxes.
if (-not $SkipPurview) {
    try {
        $null = Connect-MigrationCompliance -TenantId $TenantId -AdminUpn $AdminUpn
        $ret = @(Get-RetentionCompliancePolicy -ErrorAction SilentlyContinue |
            Where-Object { $_.ExchangeLocation -or "$($_.ExchangeLocationException)" })
        foreach ($p in $ret) {
            $rows.Add([pscustomobject]@{
                PrimarySmtpAddress = ''; RecipientTypeDetails = 'PurviewPolicy'
                LitigationHoldEnabled = $false; RetentionHoldEnabled = $false; ComplianceTagHoldApplied = $false
                DelayHoldApplied = $false; DelayReleaseHoldApplied = $false
                InPlaceHolds = ''; InPlaceHoldsDecoded = ''
                OnHold = $false
                PurviewObject = "Retention policy '$($p.Name)' (Exchange locations: $($p.ExchangeLocation -join ';'), exceptions: $($p.ExchangeLocationException -join ';'))"
            })
        }
        foreach ($case in @(Get-ComplianceCase -ErrorAction SilentlyContinue)) {
            foreach ($hp in @(Get-CaseHoldPolicy -Case $case.Identity -ErrorAction SilentlyContinue |
                    Where-Object { $_.ExchangeLocation -or "$($_.ExchangeLocationException)" })) {
                $rows.Add([pscustomobject]@{
                    PrimarySmtpAddress = ''; RecipientTypeDetails = 'PurviewPolicy'
                    LitigationHoldEnabled = $false; RetentionHoldEnabled = $false; ComplianceTagHoldApplied = $false
                    DelayHoldApplied = $false; DelayReleaseHoldApplied = $false
                    InPlaceHolds = ''; InPlaceHoldsDecoded = ''
                    OnHold = $false
                    PurviewObject = "eDiscovery case '$($case.Name)' hold policy '$($hp.Name)' (Exchange locations: $($hp.ExchangeLocation -join ';'))"
                })
            }
        }
    }
    catch { Write-Warning "Purview checks skipped: $($_.Exception.Message)" }
}

$onHold = @($rows | Where-Object OnHold)
$rows | Format-Table PrimarySmtpAddress, RecipientTypeDetails, OnHold, LitigationHoldEnabled, InPlaceHoldsDecoded -AutoSize | Out-Host
Write-Host "$($onHold.Count) mailbox(es) currently on hold." -ForegroundColor $(if ($onHold) { 'Yellow' } else { 'Green' })

$out = New-OutputFolder -Customer $Customer -Phase '06-SharedMailboxes-Holds'
$file = Join-Path $out 'HoldReport.csv'
$rows | Export-CsvSafe -Path $file
Write-Host "Report: $file" -ForegroundColor Cyan
