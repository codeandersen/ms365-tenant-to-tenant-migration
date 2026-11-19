#requires -Version 7.2
# Adapted from mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit@4de1a31 (MIT). See THIRD-PARTY-NOTICES.md.
# Changes: guarded Connect-MigrationGraph (mandatory GUID -TenantId + -AdminUpn) instead of the local
# Connect-GraphTenant; -Customer + output under customers/<Customer>/output/10-Devices/ via
# New-OutputFolder + Export-CsvSafe; #requires -Version 7.2; Untested .NOTES.
<#
.SYNOPSIS
    Read-only. Lists every device registered in the source tenant's Entra ID - join type, OS, owner,
    last sign-in and Intune state - so the new-PC handout and old-PC retirement can be planned.

.DESCRIPTION
    Read-only. Run it against the SOURCE before ordering new PCs. It reads Entra ID devices through
    Microsoft Graph (trustType AzureAd = Entra joined, ServerAd = hybrid joined, Workplace = registered),
    their registered owners and users, approximate last sign-in, and, unless -SkipIntune, the Intune
    managed device that matches each one (compliance, last sync, serial number, model). Every row gets an
    Action. Writes DeviceInventory-<tenant>-<date>.csv under the customer output folder.

    Tip: approximateLastSignInDateTime is approximate (updated about every 14 days). Use it to find dead
    devices, not to prove a device is in use today.

.PARAMETER TenantId
    Source tenant ID (GUID).

.PARAMETER AdminUpn
    Source admin sign-in name.

.PARAMETER StaleDays
    Devices with no sign-in for this many days are marked Stale. Default 90.

.PARAMETER SkipIntune
    Don't read Intune managed devices (no DeviceManagementManagedDevices.Read.All consent needed).

.PARAMETER Customer
    Output goes under customers/<Customer>/output/10-Devices/.

.EXAMPLE
    .\Get-DeviceInventory.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@contoso.onmicrosoft.com' -Customer contoso

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Requires: Microsoft.Graph.Authentication. Scopes Device.Read.All, User.Read.All, plus
    DeviceManagementManagedDevices.Read.All for Intune. Global Reader is enough to read.
    Learn: https://learn.microsoft.com/en-us/graph/api/device-list
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [ValidateRange(1, 3650)][int]$StaleDays = 90,
    [switch]$SkipIntune,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force

$scopes = @('Device.Read.All', 'User.Read.All')
if (-not $SkipIntune) { $scopes += 'DeviceManagementManagedDevices.Read.All' }
$ctx = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes $scopes
$outDir = New-OutputFolder -Customer $Customer -Phase '10-Devices'
Write-Host "Signed in as $($ctx.Account) to tenant $($ctx.TenantId)" -ForegroundColor Cyan
$tenantName = ((Invoke-MgGraphRequest GET 'v1.0/domains').value | Where-Object { $_.isInitial }).id

Write-Host 'Reading Entra ID devices' -ForegroundColor Cyan
$select = 'id,deviceId,displayName,operatingSystem,operatingSystemVersion,trustType,accountEnabled,isManaged,isCompliant,approximateLastSignInDateTime,registrationDateTime,profileType'
$devices = @(Get-GraphAll "v1.0/devices?`$select=$select&`$expand=registeredOwners")
Write-Host "  $($devices.Count) device(s)" -ForegroundColor Cyan

$intune = @{}
if (-not $SkipIntune) {
    Write-Host 'Reading Intune managed devices' -ForegroundColor Cyan
    try {
        $sel = 'id,deviceName,azureADDeviceId,userPrincipalName,managementAgent,complianceState,lastSyncDateTime,enrolledDateTime,serialNumber,model,manufacturer'
        foreach ($m in @(Get-GraphAll "v1.0/deviceManagement/managedDevices?`$select=$sel")) {
            if ($m.azureADDeviceId -and $m.azureADDeviceId -ne '00000000-0000-0000-0000-000000000000') { $intune["$($m.azureADDeviceId)".ToLower()] = $m }
        }
        Write-Host "  $($intune.Count) Intune device(s) matched to Entra ID" -ForegroundColor Cyan
    }
    catch { Write-Warning "Couldn't read Intune ($($_.Exception.Message)). Carrying on without it. Use -SkipIntune to stop asking." }
}

$joinName = @{ AzureAd = 'Entra joined'; ServerAd = 'Hybrid joined'; Workplace = 'Registered' }
$cutoff = (Get-Date).ToUniversalTime().AddDays(-$StaleDays)
$rows = foreach ($d in $devices) {
    $users = @()
    try { $users = @((Get-GraphAll "v1.0/devices/$($d.id)/registeredUsers?`$select=userPrincipalName") | ForEach-Object { $_.userPrincipalName } | Where-Object { $_ }) }
    catch { $users = @() }
    $owners = @(@($d.registeredOwners) | ForEach-Object { $_.userPrincipalName } | Where-Object { $_ })
    $last = if ($d.approximateLastSignInDateTime) { [datetime]$d.approximateLastSignInDateTime } else { $null }
    $im = $intune["$($d.deviceId)".ToLower()]
    $trust = "$($d.trustType)"
    $os = "$($d.operatingSystem)"
    $action = switch ($trust) {
        'AzureAd'   { 'New PC: retire this one after wipe (phase order in README)' }
        'ServerAd'  { 'On-prem AD: unaffected. Hybrid registration follows Entra Connect' }
        'Workplace' { if ($os -match 'iOS|iPhone|iPad|Android') { 'Re-register: remove and re-add the work account' } else { 'Re-register: Access work or school, disconnect, connect' } }
        default     { 'Check: unknown join type' }
    }
    if (-not $last -or $last.ToUniversalTime() -lt $cutoff) { $action = "Stale (no sign-in in $StaleDays days): confirm before you spend time on it. $action" }
    if ($d.accountEnabled -eq $false) { $action = "Disabled in Entra ID. $action" }
    [pscustomobject]@{
        DisplayName     = $d.displayName
        JoinType        = $(if ($joinName[$trust]) { $joinName[$trust] } else { $trust })
        TrustType       = $trust
        OS              = $os
        OSVersion       = $d.operatingSystemVersion
        Owner           = ($owners -join ';')
        RegisteredUsers = ($users -join ';')
        LastSignIn      = $(if ($last) { $last.ToString('yyyy-MM-dd') } else { '' })
        Registered      = $(if ($d.registrationDateTime) { ([datetime]$d.registrationDateTime).ToString('yyyy-MM-dd') } else { '' })
        Enabled         = $d.accountEnabled
        EntraManaged    = $d.isManaged
        EntraCompliant  = $d.isCompliant
        IntuneManaged   = [bool]$im
        IntuneUser      = $(if ($im) { $im.userPrincipalName } else { '' })
        Compliance      = $(if ($im) { $im.complianceState } else { '' })
        IntuneLastSync  = $(if ($im -and $im.lastSyncDateTime) { ([datetime]$im.lastSyncDateTime).ToString('yyyy-MM-dd') } else { '' })
        SerialNumber    = $(if ($im) { $im.serialNumber } else { '' })
        Model           = $(if ($im) { "$($im.manufacturer) $($im.model)".Trim() } else { '' })
        DeviceId        = $d.deviceId
        Action          = $action
    }
}
$rows = @($rows | Sort-Object JoinType, Owner, DisplayName)

$file = Join-Path $outDir "DeviceInventory-$tenantName-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
$rows | Export-CsvSafe -Path $file
Write-Host ''
$rows | Group-Object JoinType | Sort-Object Name | ForEach-Object { Write-Host ("{0,-15} {1}" -f $_.Name, $_.Count) }
$rejoin = @($rows | Where-Object { $_.TrustType -eq 'AzureAd' -and $_.Action -notlike 'Stale*' -and $_.Action -notlike 'Disabled*' })
Write-Host "$($rejoin.Count) Entra joined device(s) in use to retire after the new PCs land." -ForegroundColor Yellow
Write-Host "Report: $file" -ForegroundColor Cyan
Write-Host 'Next: Get-BitLockerKeyReport.ps1 against the same tenant, before any device is wiped.' -ForegroundColor Cyan
