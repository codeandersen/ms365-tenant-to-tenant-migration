<#
.SYNOPSIS
    Leak guard: scans repo files for customer data that must never be committed.

.DESCRIPTION
    Scans the tracked files (git ls-files), staged files (git diff --cached) and
    untracked-but-not-ignored files (git ls-files --others --exclude-standard) for:

      - Denylist terms   whole-word, case-insensitive. Terms come from
                         customers/.denylist (one per line; blank lines and '#'
                         comments ignored). Maintain the denylist per customer -
                         see customers/README.md.
      - GUIDs            any GUID not on tests/guid-allowlist.txt (Microsoft
                         well-known IDs only).
      - Tenant domains   any <name>.onmicrosoft.com where <name> is not
                         'contoso' or 'fabrikam'.
      - E-mail addresses any real-looking address whose domain is not one of
                         contoso.com, fabrikam.com, contoso.onmicrosoft.com,
                         fabrikam.onmicrosoft.com, example.com, microsoft.com,
                         users.noreply.github.com.

    Binary files are skipped. Findings are printed as a table and returned as
    objects - they are never written to a file. Exit code is 1 when findings
    exist, 0 otherwise (when run as a script; use -NoExit when calling from
    another script such as Invoke-Checks.ps1 or Pester tests).

.PARAMETER RepoRoot
    Repo root to scan. Default: the parent folder of this script.

.PARAMETER DenylistPath
    Path to the denylist file. Default: <RepoRoot>\customers\.denylist.
    If missing, a warning is written and scanning continues with the generic rules only.

.PARAMETER Files
    Optional explicit list of files to scan (absolute paths), for tests.
    When given, git is not used.

.PARAMETER NoExit
    Return findings without exiting (for use from Invoke-Checks.ps1 / Pester).

.EXAMPLE
    pwsh -File tests\Test-NoCustomerData.ps1
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [string]$DenylistPath,

    [string[]]$Files,

    [switch]$NoExit
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path $RepoRoot).Path
if (-not $DenylistPath) { $DenylistPath = Join-Path $RepoRoot (Join-Path 'customers' '.denylist') }

$allowedDomains = @('contoso.com', 'fabrikam.com', 'contoso.onmicrosoft.com', 'fabrikam.onmicrosoft.com',
                    'example.com', 'microsoft.com', 'users.noreply.github.com')
$allowedOnmicrosoft = @('contoso', 'fabrikam')

# ------------------------------------------------------------ denylist + GUID allowlist
$denyTerms = @()
if (Test-Path $DenylistPath) {
    $denyTerms = @(Get-Content $DenylistPath | ForEach-Object { $_.Trim() } |
                   Where-Object { $_ -and -not $_.StartsWith('#') })
}
else { Write-Warning "Denylist not found at $DenylistPath - continuing with generic rules only." }

$guidAllow = @()
$allowPath = Join-Path $PSScriptRoot 'guid-allowlist.txt'
if (Test-Path $allowPath) {
    $guidAllow = @(Get-Content $allowPath | ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
                   Where-Object { $_ } | ForEach-Object { $_.ToLower() })
}

# ------------------------------------------------------------ file set
if (-not $Files) {
    Push-Location $RepoRoot
    try {
        $tracked   = @(git ls-files 2>$null)
        $staged    = @(git diff --cached --name-only 2>$null)
        $untracked = @(git ls-files --others --exclude-standard 2>$null)
        $Files = @($tracked + $staged + $untracked | Where-Object { $_ } | Sort-Object -Unique |
                   ForEach-Object { Join-Path $RepoRoot $_ })
    }
    finally { Pop-Location }
}

function Test-BinaryFile($path) {
    try {
        $bytes = [System.IO.File]::ReadAllBytes($path)
        if ($bytes.Length -gt 8192) { $bytes = $bytes[0..8191] }
        return ($bytes -contains 0)
    }
    catch { return $true }   # unreadable: skip rather than fail closed on content we can't see
}

$guidRx  = [regex]'(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
$onmsRx  = [regex]'(?i)\b([a-z0-9-]+)\.onmicrosoft\.com\b'
$emailRx = [regex]'(?i)\b[a-z0-9._%+-]+@([a-z0-9-]+(?:\.[a-z0-9-]+)+)\b'

$findings = [System.Collections.Generic.List[object]]::new()
function Add-Finding($file, $line, $rule, $match) {
    $findings.Add([pscustomobject]@{ File = $file; Line = $line; Rule = $rule; Match = $match })
}

foreach ($f in $Files) {
    if (-not (Test-Path $f -PathType Leaf)) { continue }
    if (Test-BinaryFile $f) { continue }
    $rel = [System.IO.Path]::GetRelativePath($RepoRoot, $f)
    $ln = 0
    foreach ($line in [System.IO.File]::ReadLines($f)) {
        $ln++
        foreach ($term in $denyTerms) {
            $rx = [regex]('(?i)\b' + [regex]::Escape($term) + '\b')
            if ($rx.IsMatch($line)) { Add-Finding $rel $ln 'Denylist' $term }
        }
        foreach ($m in $guidRx.Matches($line)) {
            if ($guidAllow -notcontains $m.Value.ToLower()) { Add-Finding $rel $ln 'GuidNotAllowlisted' $m.Value }
        }
        foreach ($m in $onmsRx.Matches($line)) {
            if ($allowedOnmicrosoft -notcontains $m.Groups[1].Value.ToLower()) { Add-Finding $rel $ln 'OnmicrosoftDomain' $m.Value }
        }
        foreach ($m in $emailRx.Matches($line)) {
            if ($allowedDomains -notcontains $m.Groups[1].Value.ToLower()) { Add-Finding $rel $ln 'EmailAddress' $m.Value }
        }
    }
}

if ($findings.Count) {
    Write-Host ''
    Write-Host "LEAK GUARD: $($findings.Count) finding(s) - customer data must not be committed." -ForegroundColor Red
    $findings | Format-Table File, Line, Rule, Match -AutoSize -Wrap | Out-String -Width 200 | Write-Host
}
else {
    Write-Host "Leak guard: clean ($(@($Files).Count) file(s) scanned)." -ForegroundColor Green
}

if ($NoExit) { return $findings }
exit ([Math]::Min(1, $findings.Count))
