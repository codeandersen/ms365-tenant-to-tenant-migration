#requires -Version 7.2
<#
.SYNOPSIS
    Read-only, offline. Joins the device inventory with the migration user list and the BitLocker
    key report into a per-device retirement plan for the old PCs.

.DESCRIPTION
    Read-only, offline - reads CSVs, writes one CSV, touches no tenant. For every device in the
    DeviceInventory CSV it finds the primary user's migration row (SourceUpn -> TargetUpn), flags
    whether a recovery key is escrowed in the source (BitLockerKeyReport CSV), and gives a suggested
    retirement order:

      1. Check local data (files outside OneDrive/KFM on the old PC)
      2. Wipe / retire the device
      3. Remove the Intune managed-device record
      4. Remove the Autopilot registration
      5. Delete the Entra ID device object LAST - it deletes the escrowed BitLocker
         recovery key with it

    There is deliberately no deletion script in this phase: the plan is executed by hand or with
    your own tooling after the checks.

.PARAMETER DeviceInventoryCsv
    DeviceInventory-*.csv from Get-DeviceInventory.ps1.

.PARAMETER UserListPath
    migration-users.csv from 01-Design (SourceUpn / TargetUpn join).

.PARAMETER BitLockerReportCsv
    Optional BitLockerKeyReport-*.csv from Get-BitLockerKeyReport.ps1 - adds the KeyEscrowed flag.

.PARAMETER Customer
    Output goes under customers/<Customer>/output/10-Devices/.

.EXAMPLE
    .\Get-OldDeviceRetirementPlan.ps1 -DeviceInventoryCsv .\customers\contoso\output\10-Devices\DeviceInventory-contoso.com-20260901-1200.csv `
        -UserListPath .\customers\contoso\migration-users.csv -Customer contoso

.NOTES
    Untested against live tenants - validate in technical test/pilot.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DeviceInventoryCsv,
    [Parameter(Mandatory)][string]$UserListPath,
    [string]$BitLockerReportCsv,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force
foreach ($f in $DeviceInventoryCsv, $UserListPath) { if (-not (Test-Path $f)) { throw "$f not found." } }

$users = @{}
foreach ($u in @(Import-MigrationUserList -Path $UserListPath)) { $users[$u.SourceUpn.ToLower()] = $u }

$escrowed = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if ($BitLockerReportCsv) {
    if (-not (Test-Path $BitLockerReportCsv)) { throw "$BitLockerReportCsv not found." }
    foreach ($k in @(Import-Csv $BitLockerReportCsv)) { if ($k.DeviceId) { [void]$escrowed.Add("$($k.DeviceId)") } }
}

$rows = foreach ($d in @(Import-Csv $DeviceInventoryCsv)) {
    $primary = @("$($d.RegisteredUsers)" -split ';' | Where-Object { $_ }) | Select-Object -First 1
    if (-not $primary) { $primary = @("$($d.Owner)" -split ';' | Where-Object { $_ }) | Select-Object -First 1 }
    $u = if ($primary) { $users[$primary.ToLower()] } else { $null }
    $isSourceJoined = "$($d.TrustType)" -eq 'AzureAd'
    $key = "$($d.DeviceId)" -and $escrowed.Contains("$($d.DeviceId)")
    $notes = [System.Collections.Generic.List[string]]::new()
    if (-not $isSourceJoined) { $notes.Add('not Entra joined in the source - re-register path, no tenant device object to retire') }
    if (-not $u) { $notes.Add('primary user not in the migration list - confirm owner before wipe') }
    if ("$($d.Action)" -match '^Stale') { $notes.Add('stale - confirm before spending time') }
    if ($BitLockerReportCsv -and $isSourceJoined -and -not $key -and "$($d.OS)" -match 'Windows') { $notes.Add('no escrowed key found - check manage-bde on the device itself') }
    [pscustomobject]@{
        DeviceName        = $d.DisplayName
        DeviceId          = $d.DeviceId
        JoinType          = $d.JoinType
        OS                = $d.OS
        PrimaryUser       = $primary
        TargetUser        = $(if ($u) { $u.TargetUpn } else { '' })
        LastSignIn        = $d.LastSignIn
        IntuneManaged     = $d.IntuneManaged
        KeyEscrowed       = $key
        Step1_DataCheck   = 'Check local files outside OneDrive/KFM, browser profiles, PSTs'
        Step2_Wipe        = 'Wipe or reset the PC after the data check'
        Step3_Intune      = $(if ("$($d.IntuneManaged)" -eq 'True') { 'Remove Intune managed-device record' } else { 'n/a - not Intune managed' })
        Step4_Autopilot   = 'Remove the Autopilot registration (check it exists first)'
        Step5_EntraDevice = 'Delete the Entra device object LAST - deletion removes the escrowed BitLocker key'
        Notes             = ($notes -join '; ')
    }
}

$outDir = New-OutputFolder -Customer $Customer -Phase '10-Devices'
$file = Join-Path $outDir "OldDeviceRetirementPlan-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
$rows | Export-CsvSafe -Path $file
Write-Host "$($rows.Count) device(s) planned. Report: $file" -ForegroundColor Cyan
Write-Host 'Rule: wipe/retire BEFORE deleting anything, and delete the Entra device object LAST.' -ForegroundColor Yellow
