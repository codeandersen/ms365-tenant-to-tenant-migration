#requires -Version 7.2
<#
.SYNOPSIS
    Builds a "trusted locations" hand-over file for the TARGET tenant admin from the
    source inventory - offline, no tenant connection.

.DESCRIPTION
    Conditional Access named locations (trusted IP ranges and countries) are tenant
    configuration and do not migrate. This script reads the source inventory's
    NamedLocations.csv plus an optional office-IP list and produces:

      - TrustedLocations-for-target.csv  one row per location, incl. warnings
      - TrustedLocations-for-target.json Graph POST bodies per location
      - TrustedLocations-README.md       short instructions for the target admin

    It validates CIDRs, flags private/reserved ranges (they are rejected or useless in
    named locations), merges duplicates and warns on overlapping ranges. Nothing is
    sent anywhere - the target admin reviews and creates the locations.

    Learn: https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-list-namedlocations
           https://learn.microsoft.com/en-us/entra/identity/conditional-access/location-condition

    Untested against live tenants - offline file transformation only.

.PARAMETER InventoryPath
    Source inventory folder that contains attachments\NamedLocations.csv (the
    'attachments' subfolder is used automatically when present).

.PARAMETER OfficeIpPath
    Optional CSV of office public IP ranges (template: 01-Design/templates/office-ip-ranges.csv).
    Columns: Site, PublicIpCidr, IsTrusted, Notes.

.PARAMETER OutFolder
    Output folder. Default: <InventoryPath>\attachments if it exists, else <InventoryPath>.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InventoryPath,

    [string]$OfficeIpPath,

    [string]$OutFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force -DisableNameChecking

# --- pure helpers (unit-tested) ------------------------------------------------

function Test-CidrRange {
    # Returns @{ Valid; Family; PrivateOrReserved; Reason }
    param([string]$Cidr)
    $c = "$Cidr".Trim()
    if ($c -notmatch '^([0-9a-fA-F:.]+)/(\d{1,3})$') { return @{ Valid = $false; Family = ''; PrivateOrReserved = $false; Reason = 'not CIDR syntax (need addr/prefix)' } }
    $addr = $Matches[1]; $prefix = [int]$Matches[2]
    if ($addr -match '^\d+\.\d+\.\d+\.\d+$') {
        $o = @($addr -split '\.' | ForEach-Object { [int]$_ })
        if ($o.Count -ne 4 -or @($o | Where-Object { $_ -gt 255 }).Count) { return @{ Valid = $false; Family = 'IPv4'; PrivateOrReserved = $false; Reason = 'invalid IPv4 octet' } }
        if ($prefix -gt 32) { return @{ Valid = $false; Family = 'IPv4'; PrivateOrReserved = $false; Reason = 'prefix > 32' } }
        $priv = @(
            @{ Ip = '10.0.0.0';     Name = 'private 10.0.0.0/8' },
            @{ Ip = '172.16.0.0';   Name = 'private 172.16.0.0/12' },
            @{ Ip = '192.168.0.0';  Name = 'private 192.168.0.0/16' },
            @{ Ip = '100.64.0.0';   Name = 'CGNAT 100.64.0.0/10' },
            @{ Ip = '169.254.0.0';  Name = 'link-local 169.254.0.0/16' },
            @{ Ip = '127.0.0.0';    Name = 'loopback 127.0.0.0/8' }
        )
        foreach ($p in $priv) {
            $pLen = (($p.Name -split ' ')[1] -split '/')[1]
            if (Test-IpV4Overlap "$addr/$prefix" "$($p.Ip)/$pLen") {
                return @{ Valid = $true; Family = 'IPv4'; PrivateOrReserved = $true; Reason = "$($p.Name) - not usable in a named location" }
            }
        }
        return @{ Valid = $true; Family = 'IPv4'; PrivateOrReserved = $false; Reason = '' }
    }
    if ($addr -match ':') {
        if ($prefix -gt 128) { return @{ Valid = $false; Family = 'IPv6'; PrivateOrReserved = $false; Reason = 'prefix > 128' } }
        $low = $addr.ToLower()
        $bad = if ($low -match '^(fc|fd)') { 'unique-local fc00::/7' } elseif ($low -match '^fe[89ab]') { 'link-local fe80::/10' } elseif ($low -in '::1','0:0:0:0:0:0:0:1') { 'loopback ::1' } else { '' }
        if ($bad) { return @{ Valid = $true; Family = 'IPv6'; PrivateOrReserved = $true; Reason = "$bad - not usable in a named location" } }
        return @{ Valid = $true; Family = 'IPv6'; PrivateOrReserved = $false; Reason = '' }
    }
    return @{ Valid = $false; Family = ''; PrivateOrReserved = $false; Reason = 'unrecognised address' }
}

function Test-IpV4Overlap {
    # True when two IPv4 CIDRs overlap (used to warn the target admin)
    param([string]$A, [string]$B)
    $pa = '^(\d+\.\d+\.\d+\.\d+)/(\d+)$'
    if ($A -notmatch $pa -or $B -notmatch $pa) { return $false }
    $aParts = @($A -split '[/\.]'); $bParts = @($B -split '[/\.]')
    $aIp = [uint64]$aParts[0] * 16777216 + [uint64]$aParts[1] * 65536 + [uint64]$aParts[2] * 256 + [uint64]$aParts[3]
    $bIp = [uint64]$bParts[0] * 16777216 + [uint64]$bParts[1] * 65536 + [uint64]$bParts[2] * 256 + [uint64]$bParts[3]
    $pfx = [math]::Min([int]$aParts[4], [int]$bParts[4])
    if ($pfx -le 0) { return $true }
    $mask = if ($pfx -ge 32) { [uint64]4294967295 } else { [uint64](4294967295 - ([uint64][math]::Pow(2, 32 - $pfx) - 1)) }
    return (($aIp -band $mask) -eq ($bIp -band $mask))
}

function ConvertTo-NamedLocationBody {
    # One normalized row -> Graph POST body (ipNamedLocation or countryNamedLocation)
    param([Parameter(Mandatory)][pscustomobject]$Loc)
    if ($Loc.Type -eq 'country') {
        return [ordered]@{
            '@odata.type'         = '#microsoft.graph.countryNamedLocation'
            displayName           = $Loc.Name
            countriesAndRegions   = @($Loc.Countries -split ';\s*' | Where-Object { $_ })
            includeUnknownCountriesAndRegions = [bool]$Loc.IncludeUnknown
        }
    }
    [ordered]@{
        '@odata.type' = '#microsoft.graph.ipNamedLocation'
        displayName   = $Loc.Name
        isTrusted     = [bool]$Loc.IsTrusted
        ipRanges      = @($Loc.CidrRanges -split ';\s*' | Where-Object { $_ } | ForEach-Object {
            $fam = (Test-CidrRange $_).Family
            [ordered]@{ '@odata.type' = if ($fam -eq 'IPv6') { '#microsoft.graph.iPv6CidrRange' } else { '#microsoft.graph.iPv4CidrRange' }; cidrAddress = $_ }
        })
    }
}

# --- collect locations ----------------------------------------------------------

$attach = if (Test-Path (Join-Path $InventoryPath 'attachments')) { Join-Path $InventoryPath 'attachments' } else { $InventoryPath }
if (-not $OutFolder) { $OutFolder = $attach }
Assert-CustomerDataPath -Path $OutFolder

$locs = [System.Collections.Generic.List[object]]::new()
$nlPath = Join-Path $attach 'NamedLocations.csv'
if (Test-Path $nlPath) {
    foreach ($row in @(Import-Csv $nlPath)) {
        $warn = [System.Collections.Generic.List[string]]::new()
        $ranges = @("$($row.IpRanges)" -split ';\s*' | Where-Object { $_ })
        foreach ($cidr in $ranges) {
            $t = Test-CidrRange $cidr
            if (-not $t.Valid) { $warn.Add("invalid CIDR '$cidr': $($t.Reason)") }
            elseif ($t.PrivateOrReserved) { $warn.Add("'$cidr': $($t.Reason)") }
        }
        $locs.Add([pscustomobject]@{
            Name = "$($row.DisplayName)"; Type = "$($row.Type)"
            IsTrusted = ("$($row.IsTrusted)" -eq 'True'); CidrRanges = ($ranges -join '; ')
            Countries = "$($row.CountriesAndRegions)"; IncludeUnknown = ("$($row.IncludeUnknownCountriesAndRegions)" -eq 'True')
            Source = 'NamedLocation'; Warnings = ''
            Warn = $warn
        })
    }
}

if ($OfficeIpPath -and (Test-Path $OfficeIpPath)) {
    foreach ($row in @(Import-Csv $OfficeIpPath)) {
        if (-not "$($row.PublicIpCidr)".Trim()) { continue }
        $warn = [System.Collections.Generic.List[string]]::new()
        $t = Test-CidrRange $row.PublicIpCidr
        if (-not $t.Valid) { $warn.Add("invalid CIDR '$($row.PublicIpCidr)': $($t.Reason)") }
        elseif ($t.PrivateOrReserved) { $warn.Add("'$($row.PublicIpCidr)': $($t.Reason)") }
        $locs.Add([pscustomobject]@{
            Name = "Office - $($row.Site)"; Type = 'ip'
            IsTrusted = ("$($row.IsTrusted)" -notin 'False','no','0'); CidrRanges = "$($row.PublicIpCidr)".Trim()
            Countries = ''; IncludeUnknown = $false
            Source = 'OfficeList'; Warnings = ''
            Warn = $warn
        })
    }
}
if (-not $locs.Count) { throw "No locations found - expected NamedLocations.csv under $attach and/or -OfficeIpPath." }

# merge duplicates by name+type, warn on overlapping IPv4 ranges within one location
$merged = @{}
foreach ($l in $locs) {
    $key = "$($l.Type)|$($l.Name)"
    if ($merged.ContainsKey($key)) {
        $m = $merged[$key]
        $m.CidrRanges = (@($m.CidrRanges -split ';\s*' | Where-Object { $_ }) + @($l.CidrRanges -split ';\s*' | Where-Object { $_ }) | Sort-Object -Unique) -join '; '
        $m.Countries  = (@($m.Countries  -split ';\s*' | Where-Object { $_ }) + @($l.Countries  -split ';\s*' | Where-Object { $_ }) | Sort-Object -Unique) -join '; '
        foreach ($w in $l.Warn) { $m.Warn.Add("merged duplicate: $w") }
    } else { $merged[$key] = $l }
}
$out = @($merged.Values | Sort-Object Name)
foreach ($l in $out) {
    $rs = @($l.CidrRanges -split ';\s*' | Where-Object { $_ })
    for ($i = 0; $i -lt $rs.Count; $i++) { for ($j = $i + 1; $j -lt $rs.Count; $j++) {
        if (Test-IpV4Overlap $rs[$i] $rs[$j]) { $l.Warn.Add("ranges '$($rs[$i])' and '$($rs[$j])' overlap") }
    } }
    $l.Warnings = ($l.Warn | Sort-Object -Unique) -join '; '
}

# --- write outputs ---------------------------------------------------------------

$null = New-Item -ItemType Directory -Path $OutFolder -Force
$csvRows = $out | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Type = $_.Type; IsTrusted = $_.IsTrusted; CidrRanges = $_.CidrRanges; Countries = $_.Countries; Source = $_.Source; Warnings = $_.Warnings } }
$csvPath = Join-Path $OutFolder 'TrustedLocations-for-target.csv'
$csvRows | Export-CsvSafe -Path $csvPath

$jsonPath = Join-Path $OutFolder 'TrustedLocations-for-target.json'
@($out | ForEach-Object { ConvertTo-NamedLocationBody $_ }) | ConvertTo-Json -Depth 6 | Out-File $jsonPath -Encoding utf8BOM

$mdPath = Join-Path $OutFolder 'TrustedLocations-README.md'
$md = @"
# Trusted locations - hand-over to the TARGET tenant admin

Generated by the migration project from the SOURCE tenant inventory. Review every
line in ``TrustedLocations-for-target.csv`` (check the **Warnings** column - private/
reserved ranges cannot be used in named locations) before creating anything.

Portal path: Entra admin center -> Protection -> Conditional Access -> Named locations
-> + IP ranges location / + Countries location.

Graph alternative: POST each object in ``TrustedLocations-for-target.json`` to
``https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations``
(requires Policy.ReadWrite.ConditionalAccess). Example:

    Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations' -ContentType application/json -Body (((Get-Content .\TrustedLocations-for-target.json -Raw | ConvertFrom-Json)[0]) | ConvertTo-Json -Depth 10)

Only mark a location **trusted** after confirming the range is really a fixed office
IP the organisation controls. Trusted locations relax MFA requirements - getting this
wrong weakens sign-in security. Re-check Conditional Access policies afterwards:
policies recreated in the target must reference these locations.
"@
$md | Out-File $mdPath -Encoding utf8BOM

$warnCount = @($out | Where-Object Warnings).Count
Write-Host "Trusted locations export: $($out.Count) location(s), $warnCount with warnings."
Write-Host "  $csvPath`n  $jsonPath`n  $mdPath"
