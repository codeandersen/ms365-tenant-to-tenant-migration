# Adapted from mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit@4de1a31 (MIT). See THIRD-PARTY-NOTICES.md.
# Changes:
#   - Removed the ShareGate module check (no ShareGate copy path in this playbook).
#   - Added checks for CrossTenantIdentityMapping (CTIM, prerelease) and
#     Microsoft.Graph.Beta.Migrations (Orchestrator cmdlets), plus the Orchestrator tenant-config
#     prerequisites Microsoft.Graph.Applications, Microsoft.Graph.Identity.DirectoryManagement and
#     Microsoft.Graph.Beta.Authentication (>= 2.33.0, aligned with Microsoft.Graph).
#   - Optional -CrossTenantMigrationModulePath: the CrossTenantMigration NuGet module is not on
#     PSGallery; when given, checks that it imports.
#   - Added a minimum-version table (see $MinimumVersions below).
<#
.SYNOPSIS
    Checks the PowerShell modules this playbook needs for the version clashes that break a migration session, and
    optionally fixes the Microsoft Graph ones.

.DESCRIPTION
    TL;DR: Run this before you start, and again whenever a script fails with "Could not load file or assembly" or
    "Assembly with same name is already loaded". It lists every installed version of Microsoft.Graph.Authentication
    and the other Microsoft.Graph.* modules, ExchangeOnlineManagement, Microsoft.Online.SharePoint.PowerShell,
    PnP.PowerShell, MicrosoftTeams, CrossTenantIdentityMapping and
    Microsoft.Graph.Beta.Migrations, then flags:
      - Graph submodules whose newest version differs from the newest Microsoft.Graph.Authentication (the classic
        clash: Authentication 2.41.2 loaded, then an older submodule asks for Authentication 2.26.1)
      - more than one ExchangeOnlineManagement version installed
      - Exchange Online or Graph assemblies already loaded in this window (open a fresh window before a run)
      - the PowerShell edition
      - required/optional modules that are missing or older than the minimum versions listed below
    Read-only by default. -Fix installs each mismatched Microsoft.Graph.* module at the Authentication version, for
    the current user only.

    Minimum versions (current PSGallery versions at the time of writing; re-check with Find-Module):
      ExchangeOnlineManagement                       3.11.1
      Microsoft.Graph.Authentication                 2.41.2
      Microsoft.Online.SharePoint.PowerShell         16.0.27814.12015
      PnP.PowerShell                                 3.5.0
      MicrosoftTeams                                 8.0.0
      Microsoft.Graph.Applications                   2.41.2
      Microsoft.Graph.Identity.DirectoryManagement   2.41.2
      Microsoft.Graph.Beta.Authentication            2.33.0 (doc minimum: Graph.Beta >= 2.33.0,
                                                       same version as Microsoft.Graph)
      Microsoft.Graph.Beta.Migrations                2.41.2
      CrossTenantIdentityMapping                     0.0.34-Preview36668934 (prerelease:
                                                       Install-Module CrossTenantIdentityMapping -AllowPrerelease)
      CrossTenantMigration (NuGet package)           not on PSGallery - download from Microsoft
                                                       Learn and Import-Module the expanded
                                                       folder; -ModulePath checks it imports

.PARAMETER Fix
    Install-Module every mismatched Microsoft.Graph.* submodule at the newest Microsoft.Graph.Authentication version
    (-Scope CurrentUser -Force -AllowClobber). Asks before each one; supports -WhatIf. Close every PowerShell window
    afterwards and open a fresh one.

.PARAMETER CrossTenantMigrationModulePath
    Optional path to the expanded CrossTenantMigration NuGet module (e.g. .\CTModule\CrossTenantMigration)
    used by 02-TenantPrep MigrationApps. When given, the check imports it and reports the result.

.PARAMETER OutFile
    Optional CSV path for the result table.

.EXAMPLE
    .\Test-ModuleHealth.ps1

.EXAMPLE
    .\Test-ModuleHealth.ps1 -Fix -WhatIf

.EXAMPLE
    .\Test-ModuleHealth.ps1 -Fix -Confirm:$false

.NOTES
    Requires: PowerShell 7.2 or later. PowerShellGet for -Fix and for Get-InstalledModule. No tenant sign-in.
#>
#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Fix,
    [string]$CrossTenantMigrationModulePath,
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'
$results = [System.Collections.Generic.List[object]]::new()
function Add-Check($Area, $Item, $Result, $Detail) {
    $results.Add([pscustomobject]@{ Area = $Area; Item = $Item; Result = $Result; Detail = $Detail })
}
function Get-Versions($Name) {
    # Both sources: Get-Module sees every copy on PSModulePath; Get-InstalledModule only what PowerShellGet installed.
    $v = @(Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue | ForEach-Object { $_.Version })
    if (Get-Command Get-InstalledModule -ErrorAction SilentlyContinue) {
        $v += @(Get-InstalledModule -Name $Name -AllVersions -ErrorAction SilentlyContinue | ForEach-Object { [version]("$($_.Version)" -replace '-.*$', '') })
    }
    @($v | Where-Object { $_ } | Sort-Object -Unique -Descending)
}

# ------------------------------------------------------------ PowerShell edition
$edition = "$($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"
Add-Check 'PowerShell' 'Edition' 'PASS' "$edition. This playbook is developed and tested on PowerShell 7"

# ------------------------------------------------------------ required modules and minimum versions
# Values are the PSGallery versions current when this file was written (verified with Find-Module 2026).
# CrossTenantIdentityMapping ships as a prerelease only - find/install it with -AllowPrerelease.
$MinimumVersions = [ordered]@{
    'ExchangeOnlineManagement'                       = '3.11.1'
    'Microsoft.Graph.Authentication'                 = '2.41.2'
    'Microsoft.Graph.Applications'                   = '2.41.2'
    'Microsoft.Graph.Identity.DirectoryManagement'   = '2.41.2'
    'Microsoft.Graph.Beta.Authentication'            = '2.33.0'    # doc minimum for Graph.Beta; must match Microsoft.Graph version
    'Microsoft.Online.SharePoint.PowerShell'         = '16.0.27814.12015'
    'PnP.PowerShell'                                 = '3.5.0'
    'MicrosoftTeams'                                 = '8.0.0'
    'Microsoft.Graph.Beta.Migrations'                = '2.41.2'                    # Orchestrator cmdlets (New-/Get-/Test-MgBetaCrossTenantMigrationJob etc.)
    'CrossTenantIdentityMapping'                     = '0.0.34-Preview36668934'    # CTIM cmdlets - prerelease only, needs -AllowPrerelease
}
$moduleUse = [ordered]@{
    'ExchangeOnlineManagement'                       = 'Tenant prep, identities, mail config, domain cutover'
    'Microsoft.Graph.Applications'                   = 'Prereq for the CrossTenantMigration tenant-config module'
    'Microsoft.Graph.Identity.DirectoryManagement'   = 'Prereq for the CrossTenantMigration tenant-config module'
    'Microsoft.Online.SharePoint.PowerShell'         = 'SharePoint/OneDrive phases'
    'PnP.PowerShell'                                 = 'Optional: SharePoint content handling'
    'MicrosoftTeams'                                 = 'Teams federation prep + phone/voice inventory'
    'Microsoft.Graph.Beta.Migrations'                = 'Orchestrator migration jobs (05-Batches)'
    'CrossTenantIdentityMapping'                     = 'CTIM identity mapping (03-Identities)'
}

# ------------------------------------------------------------ Microsoft Graph
$authVersions = Get-Versions 'Microsoft.Graph.Authentication'
$authTop = $authVersions | Select-Object -First 1
$graphNames = @(Get-Module -ListAvailable -Name 'Microsoft.Graph.*' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
if (Get-Command Get-InstalledModule -ErrorAction SilentlyContinue) {
    $graphNames += @(Get-InstalledModule -Name 'Microsoft.Graph.*' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
}
# Covers Microsoft.Graph.Beta.Migrations (the Orchestrator cmdlets) via the Microsoft.Graph.* wildcard.
$graphNames = @($graphNames | Where-Object { $_ -ne 'Microsoft.Graph.Authentication' -and $_ -ne 'Microsoft.Graph' } | Sort-Object -Unique)

$mismatched = [System.Collections.Generic.List[string]]::new()
if (-not $authTop) {
    Add-Check 'Graph' 'Microsoft.Graph.Authentication' 'WARN' "Not installed. Install-Module Microsoft.Graph.Authentication -Scope CurrentUser (minimum $($MinimumVersions['Microsoft.Graph.Authentication']))"
}
else {
    $r = if ($authVersions.Count -gt 1) { 'WARN' } else { 'PASS' }
    $d = "Installed: $($authVersions -join ', ')"
    if ($authVersions.Count -gt 1) { $d += '. More than one version: PowerShell loads the newest unless told otherwise, and older submodules then fail' }
    if ([version]$authTop -lt [version]$MinimumVersions['Microsoft.Graph.Authentication']) { $r = 'WARN'; $d += ". Below minimum $($MinimumVersions['Microsoft.Graph.Authentication'])" }
    Add-Check 'Graph' 'Microsoft.Graph.Authentication' $r $d
    foreach ($n in $graphNames) {
        $v = Get-Versions $n
        $top = $v | Select-Object -First 1
        if ($top -ne $authTop) {
            $mismatched.Add($n)
            Add-Check 'Graph' $n 'WARN' "Newest $top, Authentication is $authTop. This is the 'Could not load file or assembly Microsoft.Graph.Authentication' clash. Fix: install $n $authTop (-Fix)"
        }
        else { Add-Check 'Graph' $n 'PASS' "Newest $top matches Authentication$(if ($v.Count -gt 1) { ". Older copies too: $(($v | Select-Object -Skip 1) -join ', ')" })" }
    }
}

# ------------------------------------------------------------ the other modules
foreach ($n in $moduleUse.Keys) {
    $v = Get-Versions $n
    $top = $v | Select-Object -First 1
    $min = $MinimumVersions[$n]
    if (-not $v) {
        $result = if ($n -eq 'PnP.PowerShell') { 'PASS' } else { 'WARN' }
        $detail = "Not installed. Used by: $($moduleUse[$n]). Minimum $min."
        $detail += if ($n -eq 'CrossTenantIdentityMapping') {
            " Install-Module $n -AllowPrerelease -Scope CurrentUser"
        } else { " Install-Module $n -Scope CurrentUser" }
        Add-Check 'Modules' $n $result $detail
        continue
    }
    if ($n -eq 'ExchangeOnlineManagement' -and $v.Count -gt 1) {
        Add-Check 'Modules' $n 'WARN' "Several versions installed: $($v -join ', '). Different windows can load different ones. Keep one: Uninstall-Module ExchangeOnlineManagement -RequiredVersion <old>"
    }
    # $min may carry a prerelease tag (CrossTenantIdentityMapping ships prerelease-only) - compare on the numeric part.
    elseif ($min -and [version]$top -lt [version]($min -replace '-.*$', '')) {
        Add-Check 'Modules' $n 'WARN' "Installed $top is below minimum $min. Update-Module $n -Scope CurrentUser"
    }
    else { Add-Check 'Modules' $n 'PASS' "Installed: $($v -join ', ')$(if ($min) { " (minimum $min)" })" }
}

# ------------------------------------------------------------ CrossTenantMigration NuGet module (02-TenantPrep MigrationApps)
if ($CrossTenantMigrationModulePath) {
    if (-not (Test-Path $CrossTenantMigrationModulePath)) {
        Add-Check 'Modules' 'CrossTenantMigration' 'WARN' "Path not found: $CrossTenantMigrationModulePath. Download the .nupkg from Microsoft Learn and Expand-Archive it first."
    }
    else {
        try {
            $m = Import-Module $CrossTenantMigrationModulePath -Force -PassThru -ErrorAction Stop
            Add-Check 'Modules' 'CrossTenantMigration' 'PASS' "Imported $($m.Name) $($m.Version) from $CrossTenantMigrationModulePath"
        }
        catch { Add-Check 'Modules' 'CrossTenantMigration' 'WARN' "Found at $CrossTenantMigrationModulePath but failed to import: $($_.Exception.Message)" }
    }
}
else {
    Add-Check 'Modules' 'CrossTenantMigration' 'PASS' 'Skipped - pass -CrossTenantMigrationModulePath to verify the expanded NuGet module imports (needed only for 02-TenantPrep -Step MigrationApps).'
}

# ------------------------------------------------------------ what this window has already loaded
$loaded = @([AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object { $_.GetName() } |
        Where-Object { $_.Name -like 'Microsoft.Graph*' -or $_.Name -like 'Microsoft.Exchange.Management*' -or $_.Name -eq 'Microsoft.Identity.Client' })
if ($loaded) {
    $list = ($loaded | Sort-Object Name -Unique | ForEach-Object { "$($_.Name) $($_.Version)" }) -join '; '
    Add-Check 'Session' 'Loaded assemblies' 'WARN' "Already loaded in this window: $list. Exchange Online and Graph share Microsoft.Identity.Client, and whichever loads first wins. Run the next script in a fresh window"
}
else { Add-Check 'Session' 'Loaded assemblies' 'PASS' 'No Exchange Online or Graph assemblies loaded yet. Good: this window is clean' }

# ------------------------------------------------------------ fix
if ($Fix) {
    if (-not $mismatched.Count) { Write-Host 'Nothing to fix: every Microsoft.Graph submodule matches Authentication.' -ForegroundColor Green }
    foreach ($n in $mismatched) {
        if ($PSCmdlet.ShouldProcess("$n $authTop", 'Install-Module -Scope CurrentUser -Force -AllowClobber')) {
            try {
                Install-Module -Name $n -RequiredVersion $authTop -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
                Add-Check 'Fix' $n 'PASS' "Installed $authTop"
            }
            catch { Add-Check 'Fix' $n 'WARN' "Install failed: $($_.Exception.Message)" }
        }
    }
    if ($mismatched.Count) { Write-Host 'Close every PowerShell window and open a fresh one before you run anything else.' -ForegroundColor Yellow }
}

# ------------------------------------------------------------ report
$results | Format-Table Result, Area, Item, Detail -AutoSize -Wrap | Out-String -Width 250 | Write-Host
if ($OutFile) { $results | Export-CsvSafe -Path $OutFile; Write-Host "Saved to $OutFile" -ForegroundColor Cyan }
$warn = @($results | Where-Object Result -eq 'WARN').Count
if ($warn) { Write-Host "$warn warning(s). Fix them before a migration run, or expect assembly errors part way through." -ForegroundColor Yellow }
else { Write-Host 'All PASS.' -ForegroundColor Green }
