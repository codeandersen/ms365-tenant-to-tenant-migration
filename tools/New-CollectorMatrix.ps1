<#
.SYNOPSIS
    Generates docs/Collector-Matrix.md from 00-Assessment/Collectors.psd1.

.DESCRIPTION
    Two tables: an API capability matrix (what each collector calls, at which
    -Level, app-only support, licence and limitations) and a permissions matrix
    (delegated/application permissions and admin roles). Also prints the union
    of application permissions needed for certificate app-only runs
    (docs/App-Only-Setup.md). Regenerate after changing Collectors.psd1.
#>
[CmdletBinding()]
param(
    [string]$RegistryPath = (Join-Path $PSScriptRoot '..\00-Assessment\Collectors.psd1'),
    [string]$OutFile      = (Join-Path $PSScriptRoot '..\docs\Collector-Matrix.md')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$data = Import-PowerShellDataFile -Path $RegistryPath
# Collectors.Phase1.psd1: separate file - Import-PowerShellDataFile caps a data
# file at 132 objects
$phase1Path = Join-Path (Split-Path $RegistryPath -Parent) 'Collectors.Phase1.psd1'
$collectors = @($data.Collectors)
if (Test-Path $phase1Path) { $collectors += @((Import-PowerShellDataFile -Path $phase1Path).Collectors) }

function Get-E {
    # Registry entries are hashtables; Endpoint/Cmdlet are mutually exclusive keys.
    param([hashtable]$Entry, [string]$Key)
    if ($Entry.Contains($Key)) { return $Entry[$Key] }
    return $null
}
function ConvertTo-Cell {
    param([AllowNull()][object]$Value)
    $s = "$Value" -replace '\|', '\|' -replace "`r?`n", ' '
    if ([string]::IsNullOrWhiteSpace($s)) { return '-' }
    return $s
}
function ConvertTo-List {
    param([AllowNull()][object]$Items)
    $a = @($Items | Where-Object { $_ })
    if ($a.Count -eq 0) { return '-' }
    return ($a -join '<br>')
}

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine('# Collector matrix')
[void]$sb.AppendLine()
[void]$sb.AppendLine('Generated from `00-Assessment/Collectors.psd1` by `tools/New-CollectorMatrix.ps1`. Do not edit by hand.')
[void]$sb.AppendLine()
[void]$sb.AppendLine('`ValidationStatus` is `ValidatedLive` only for collectors that have run successfully against a real tenant.')
[void]$sb.AppendLine()
[void]$sb.AppendLine('## API capability matrix')
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Workstream | Workload | Collector | Level | Cmdlet/Endpoint | ApiVersion | Coverage | AppOnly | Licence | Limitations | Docs | Validation |')
[void]$sb.AppendLine('|---|---|---|---|---|---|---|---|---|---|---|---|')
foreach ($c in $collectors) {
    $call = if (Get-E $c 'Cmdlet') { "$(Get-E $c 'Cmdlet')" } else { "$(Get-E $c 'Endpoint')" }
    $appOnly = if (Get-E $c 'AppOnlySupported') { 'Yes' } else { 'No' }
    [void]$sb.AppendLine("| $(ConvertTo-Cell (Get-E $c 'Workstream')) | $(ConvertTo-Cell (Get-E $c 'Workload')) | $(ConvertTo-Cell (Get-E $c 'Name')) | $(ConvertTo-Cell (Get-E $c 'Level')) | $(ConvertTo-Cell $call) | $(ConvertTo-Cell (Get-E $c 'ApiVersion')) | $(ConvertTo-Cell (Get-E $c 'Coverage')) | $appOnly | $(ConvertTo-Cell (Get-E $c 'RequiredLicence')) | $(ConvertTo-Cell (Get-E $c 'KnownLimitations')) | $(ConvertTo-Cell (Get-E $c 'DocsUrl')) | $(ConvertTo-Cell (Get-E $c 'ValidationStatus')) |")
}
[void]$sb.AppendLine()
[void]$sb.AppendLine('## Permissions matrix')
[void]$sb.AppendLine()
[void]$sb.AppendLine('Delegated permissions are consented interactively (`Connect-MgGraph -Scopes`). Application permissions must be granted with admin consent for app-only runs - see [App-Only-Setup](App-Only-Setup.md). The tool never assigns permissions.')
[void]$sb.AppendLine()
[void]$sb.AppendLine('| Collector | Delegated | Application | Admin roles |')
[void]$sb.AppendLine('|---|---|---|---|')
foreach ($c in $collectors) {
    [void]$sb.AppendLine("| $(ConvertTo-Cell (Get-E $c 'Name')) | $(ConvertTo-List (Get-E $c 'DelegatedPermissions')) | $(ConvertTo-List (Get-E $c 'ApplicationPermissions')) | $(ConvertTo-List (Get-E $c 'AdminRoles')) |")
}
[void]$sb.AppendLine()
$appUnion = @($collectors | ForEach-Object { @(Get-E $_ 'ApplicationPermissions') } | Where-Object { $_ } | Sort-Object -Unique)
[void]$sb.AppendLine('## Application permissions (union for app-only runs)')
[void]$sb.AppendLine()
foreach ($p in $appUnion) { [void]$sb.AppendLine("- ``$p``") }
[void]$sb.AppendLine()
$roles = @($collectors | ForEach-Object { @(Get-E $_ 'AdminRoles') } | Where-Object { $_ } | Sort-Object -Unique)
[void]$sb.AppendLine("## Admin roles (union): $(($roles) -join ', ')")
[void]$sb.AppendLine()

$outDir = Split-Path $OutFile -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$sb.ToString() | Out-File -FilePath $OutFile -Encoding utf8
Write-Host "Collector matrix written to $OutFile"
