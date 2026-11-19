#requires -Version 7.2
<#
.SYNOPSIS
    Assigns target-tenant licences to users whose CTIM write has been verified - and only those.

.DESCRIPTION
    Order is load-bearing: target users must not get an Exchange/Teams licence before Identity
    Mapping has stamped the source ExchangeGuid on the target MailUser, or Exchange provisions a
    mailbox and the migration fails for that user. This script therefore requires
    -VerificationCsv (identity-verification.csv from Test-IdentityMapping -Mode Verify) and only
    licenses users Select-LicensableUser accepts: a Pass row at most -MaxAgeHours old
    (default 24). Refused users are reported, never licensed.

    For each licensable user: sets UsageLocation when missing (Set-MgUserLicense requires it),
    resolves TargetLicenseSku (a SkuPartNumber) to a SkuId via Get-MgSubscribedSku, optionally adds
    the add-on SKU for the Cross-Tenant User Data Migration licence (-AddOnSkuPartNumber), and calls
    Set-MgUserLicense. Supports -WhatIf.

.PARAMETER TenantId
    Target tenant ID (GUID). The Graph connection is asserted against it.

.PARAMETER AdminUpn
    Target tenant admin sign-in name.

.PARAMETER UserListPath
    Path to migration-users.csv (TargetLicenseSku / UsageLocation per user).

.PARAMETER VerificationCsv
    identity-verification.csv from Test-IdentityMapping -Mode Verify. Mandatory - without a fresh
    verification this script does nothing.

.PARAMETER AddOnSkuPartNumber
    Optional SkuPartNumber of the Cross-Tenant User Data Migration add-on to assign in the same
    call. Not needed if the licence is assigned on the source user instead.

.PARAMETER MaxAgeHours
    Maximum age of the verification row. Default 24.

.PARAMETER Customer
    Writes the report CSV under customers/<Customer>/output/03-Identities/.

.EXAMPLE
    .\Set-TargetLicenses.ps1 -TenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -AdminUpn 'admin@fabrikam.com' `
        -UserListPath .\customers\fabrikam\migration-users.csv `
        -VerificationCsv .\customers\fabrikam\output\03-Identities\...\identity-verification.csv `
        -AddOnSkuPartNumber 'CROSS_TENANT_USER_DATA_MIGRATION' -Customer fabrikam -WhatIf

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Sources:
      https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-4-user-prep
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$UserListPath,

    [Parameter(Mandatory)]
    [string]$VerificationCsv,

    [string]$AddOnSkuPartNumber,
    [int]$MaxAgeHours = 24,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

$users = @(Import-MigrationUserList -Path $UserListPath)
$verification = @(Import-Csv -Path $VerificationCsv)

$null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'User.ReadWrite.All', 'Organization.Read.All'
$skus = @(Get-MgSubscribedSku -All)
$skuByPart = @{}
foreach ($s in $skus) { $skuByPart["$($s.SkuPartNumber)".ToLower()] = $s.SkuId }

$decision = Select-LicensableUser -Users $users -Verification $verification -NowUtc ([datetime]::UtcNow) -MaxAgeHours $MaxAgeHours
$report = [System.Collections.Generic.List[object]]::new()

foreach ($r in $decision.Refused) {
    $report.Add([pscustomobject]@{ TargetUpn = $r.User.TargetUpn; Action = 'Refused'; Note = $r.Reason })
}

foreach ($u in $decision.Licensable) {
    $row = [ordered]@{ TargetUpn = $u.TargetUpn; Action = ''; Note = '' }
    $part = "$($u.TargetLicenseSku)".ToLower()
    $licenses = @()
    if (-not $skuByPart.ContainsKey($part)) {
        $row.Action = 'Error'; $row.Note = "SkuPartNumber '$($u.TargetLicenseSku)' not found in this tenant"
        $report.Add([pscustomobject]$row); continue
    }
    $licenses += @{ SkuId = $skuByPart[$part] }
    if ($AddOnSkuPartNumber) {
        $addon = "$AddOnSkuPartNumber".ToLower()
        if ($skuByPart.ContainsKey($addon)) { $licenses += @{ SkuId = $skuByPart[$addon] } }
        else { $row.Note = "add-on '$AddOnSkuPartNumber' not found in tenant - skipped"; }
    }
    try {
        $mgUser = Get-MgUser -UserId $u.TargetUpn -Property Id, UserPrincipalName, UsageLocation -ErrorAction Stop
        if (-not $mgUser.UsageLocation) {
            if ($PSCmdlet.ShouldProcess($u.TargetUpn, "Update-MgUser -UsageLocation $($u.UsageLocation)")) {
                Update-MgUser -UserId $mgUser.Id -UsageLocation $u.UsageLocation
            }
        }
        $skuDesc = $u.TargetLicenseSku + $(if ($AddOnSkuPartNumber) { " + $AddOnSkuPartNumber" })
        if ($PSCmdlet.ShouldProcess($u.TargetUpn, "Set-MgUserLicense $skuDesc")) {
            Set-MgUserLicense -UserId $mgUser.Id -AddLicenses $licenses -RemoveLicenses @()
            $row.Action = 'Licensed'
        }
        else { $row.Action = 'WhatIf:License' }
    }
    catch { $row.Action = 'Error'; $row.Note = ($row.Note + ' ' + $_.Exception.Message).Trim() }
    $report.Add([pscustomobject]$row)
}

$out = New-OutputFolder -Customer $Customer -Phase '03-Identities'
$file = Join-Path $out 'TargetLicenses.csv'
$report | Export-CsvSafe -Path $file
$report | Group-Object Action | Select-Object Name, Count | Format-Table -AutoSize | Out-Host
Write-Host "Report: $file" -ForegroundColor Green
if (@($report | Where-Object Action -eq 'Refused').Count) {
    Write-Host 'Refused users were NOT licensed - re-verify them before retrying.' -ForegroundColor Yellow
}
