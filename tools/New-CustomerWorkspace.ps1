#requires -Version 7.2
<#
.SYNOPSIS
    Creates a customer workspace under customers/<name>/ (local only, no tenant).

.DESCRIPTION
    Everything for a customer lives under customers/<name>/ - which is gitignored
    (except customers/README.md). This script creates the three subfolders and
    copies every template from 01-Design/templates into input/ so the real
    user list, decision log and mapping files never live in the repo:

        customers/<name>/input/      filled-in templates (migration-users.csv, ...)
        customers/<name>/inventory/  Collect-TenantInventory output (-Customer)
        customers/<name>/output/     per-run script output (New-OutputFolder)

    Existing files are not overwritten unless -Force is given.

    Untested against live tenants - this script makes local folders only.

.PARAMETER Customer
    Workspace name: letters, digits, '.', '_' or '-'. Becomes customers/<name>/.

.PARAMETER RepoRoot
    Repository root. Default: parent of the tools\ folder. Exposed for tests.

.PARAMETER Force
    Overwrite files in input/ that already exist.

.EXAMPLE
    .\tools\New-CustomerWorkspace.ps1 -Customer contoso
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Customer,

    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Join-Path $RepoRoot "customers\$Customer"
foreach ($d in 'input', 'inventory', 'output') {
    $null = New-Item -ItemType Directory -Path (Join-Path $root $d) -Force
}

$templateDir = Join-Path $RepoRoot '01-Design\templates'
$copied = 0; $skipped = 0
foreach ($f in @(Get-ChildItem $templateDir -File)) {
    $dest = Join-Path $root "input\$($f.Name)"
    if ((Test-Path $dest) -and -not $Force) { $skipped++; continue }
    Copy-Item $f.FullName $dest -Force
    $copied++
}

$denylist = Join-Path $RepoRoot 'customers\.denylist'
if (-not (Test-Path $denylist)) {
    "# One term per line: customer names, domains, tenant IDs - used by tests/Test-NoCustomerData.ps1" | Set-Content $denylist
}

Write-Host "Workspace ready: $root"
Write-Host "  input/     $copied template(s) copied, $skipped skipped (already existed)"
Write-Host 'Next steps:'
Write-Host "  1. Fill in $root\input\migration-users.csv (and the other templates you need)."
Write-Host "  2. Add the customer's names/domains/tenant IDs to customers\.denylist"
Write-Host '     (one term per line - the leak guard uses it; keep contents private).'
Write-Host "  3. Collect inventories with -Customer $Customer - they land in $root\inventory."
