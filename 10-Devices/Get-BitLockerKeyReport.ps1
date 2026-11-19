#requires -Version 7.2
# Adapted from mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit@4de1a31 (MIT). See THIRD-PARTY-NOTICES.md.
# Changes: reports key PRESENCE only - never reads or writes recovery key values (dropped the
# ?$select=key retrieval and BitlockerKey.Read.All); uses BitlockerKey.ReadBasic.All, the documented
# scope that reads key metadata but not the key itself. Guarded Connect-MigrationGraph, -Customer
# output via New-OutputFolder + Export-CsvSafe, #requires, Untested .NOTES.
<#
.SYNOPSIS
    Read-only. Reports WHICH devices have a BitLocker recovery key escrowed in the source tenant's
    Entra ID - never the key values - so no device is wiped while its only key copy is still there.

.DESCRIPTION
    Read-only. Run it against the SOURCE before any device leaves it. Recovery keys for Entra joined
    devices live in the tenant the device was joined to: deleting the Entra device object (or closing
    the tenant) deletes the escrowed key with it, and a laptop that then asks for its recovery key
    after a BIOS update is a laptop you can't open.

    This script lists every escrowed key through Microsoft Graph
    (informationProtection/bitlocker/recoveryKeys, metadata only), maps each deviceId to the device
    name, owner and OS, flags Entra-joined Windows devices that have NO key escrowed, and writes one
    CSV. It deliberately never requests the key value: the Graph scope BitlockerKey.ReadBasic.All
    "does not allow read of the recovery key itself".

    When a key is actually needed (a device asking for recovery), retrieve that single key in the
    Entra or Intune admin portal, where the read is audited - never bulk-export keys.

.PARAMETER TenantId
    Source tenant ID (GUID).

.PARAMETER AdminUpn
    Source admin sign-in name.

.PARAMETER Customer
    Output goes under customers/<Customer>/output/10-Devices/.

.EXAMPLE
    .\Get-BitLockerKeyReport.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@contoso.onmicrosoft.com' -Customer contoso

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Requires: Microsoft.Graph.Authentication. Scopes BitlockerKey.ReadBasic.All and Device.Read.All.
    Learn: https://learn.microsoft.com/en-us/graph/api/bitlockerrecoverykey-list
    Learn: https://learn.microsoft.com/en-us/graph/api/bitlockerrecoverykey-get
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force

$ctx = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'BitlockerKey.ReadBasic.All', 'Device.Read.All'
$outDir = New-OutputFolder -Customer $Customer -Phase '10-Devices'
Write-Host "Signed in as $($ctx.Account) to tenant $($ctx.TenantId)" -ForegroundColor Cyan
$tenantName = ((Invoke-MgGraphRequest GET 'v1.0/domains').value | Where-Object { $_.isInitial }).id

Write-Host 'Reading devices' -ForegroundColor Cyan
$devices = @{}
foreach ($d in @(Get-GraphAll "v1.0/devices?`$select=id,deviceId,displayName,operatingSystem,trustType&`$expand=registeredOwners")) {
    if ($d.deviceId) { $devices["$($d.deviceId)".ToLower()] = $d }
}
Write-Host "  $($devices.Count) device(s)" -ForegroundColor Cyan

# Metadata only: no User-Agent needed for listing, and the key value is never requested anywhere.
Write-Host 'Listing escrowed recovery keys (metadata only - key values are never read)' -ForegroundColor Cyan
$keys = @(Get-GraphAll 'v1.0/informationProtection/bitlocker/recoveryKeys')
Write-Host "  $($keys.Count) key(s)" -ForegroundColor Cyan

$rows = foreach ($k in $keys) {
    $d = $devices["$($k.deviceId)".ToLower()]
    [pscustomobject]@{
        DeviceName  = $(if ($d) { $d.displayName } else { '' })
        Owner       = $(if ($d) { (@($d.registeredOwners) | ForEach-Object { $_.userPrincipalName } | Where-Object { $_ }) -join ';' } else { '' })
        OS          = $(if ($d) { $d.operatingSystem } else { '' })
        JoinType    = $(if ($d) { $d.trustType } else { '' })
        VolumeType  = $k.volumeType
        KeyId       = $k.id
        Created     = $(if ($k.createdDateTime) { ([datetime]$k.createdDateTime).ToString('yyyy-MM-dd HH:mm') } else { '' })
        DeviceId    = $k.deviceId
        KeyEscrowed = $true
        Note        = $(if (-not $d) { 'Device no longer in Entra ID - the disk may still exist' } else { '' })
    }
}

$file = Join-Path $outDir "BitLockerKeyReport-$tenantName-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
$rows | Sort-Object DeviceName, Created | Export-CsvSafe -Path $file

$keyed = @($keys.deviceId | ForEach-Object { "$_".ToLower() } | Select-Object -Unique)
$noKeyDevices = @($devices.Values | Where-Object { $_.trustType -eq 'AzureAd' -and "$($_.operatingSystem)" -match 'Windows' -and $keyed -notcontains "$($_.deviceId)".ToLower() })
Write-Host ''
Write-Host "$($keys.Count) escrowed key(s) across $($keyed.Count) device(s). No key values were read or written." -ForegroundColor Green
if ($noKeyDevices) { Write-Host "$($noKeyDevices.Count) Entra joined Windows device(s) have NO key in Entra ID: $(($noKeyDevices.displayName | Select-Object -First 10) -join ', '). Check BitLocker on those before they leave (manage-bde -protectors -get C:)." -ForegroundColor Yellow }
Write-Host "Report: $file" -ForegroundColor Cyan
Write-Host 'If a single key is ever needed, read that one key in the Entra/Intune portal - the read is audited.' -ForegroundColor Cyan
