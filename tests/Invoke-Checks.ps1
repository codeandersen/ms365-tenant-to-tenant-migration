<#
.SYNOPSIS
    Runs all repo checks: parse check, PSScriptAnalyzer, Pester tests and the customer-data leak guard.

.DESCRIPTION
    (a) Parses every .ps1/.psm1 in the repo with [System.Management.Automation.Language.Parser]
        and fails on any parse error.
    (b) Runs Invoke-ScriptAnalyzer -Recurse and fails on Error-severity findings
        (warnings are printed but do not fail).
    (c) Runs Pester 5 over tests/*.Tests.ps1 (requires Pester >= 5.0; the module is imported
        with -MinimumVersion so an old Pester 3.x is never picked up).
    (d) Runs tests/Test-NoCustomerData.ps1 (the leak guard).

    Exits non-zero if any check fails. Read-only: nothing here touches a tenant.

.EXAMPLE
    pwsh -NoProfile -File tests\Invoke-Checks.ps1
#>
#requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failed = $false

Write-Host '=== 1. Parse check ===' -ForegroundColor Cyan
$psFiles = @(Get-ChildItem -Path $repoRoot -Recurse -File -Include '*.ps1', '*.psm1' |
             Where-Object { $_.FullName -notlike '*\customers\*' })
$parseErrors = 0
foreach ($f in $psFiles) {
    $errs = $null; $tok = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tok, [ref]$errs)
    if ($errs.Count) {
        $parseErrors += $errs.Count
        $failed = $true
        foreach ($e in $errs) { Write-Host "  PARSE ERROR $($f.FullName):$($e.Extent.StartLineNumber) $($e.Message)" -ForegroundColor Red }
    }
}
Write-Host ("  {0} file(s), {1} parse error(s)" -f $psFiles.Count, $parseErrors)

Write-Host ''
Write-Host '=== 2. PSScriptAnalyzer ===' -ForegroundColor Cyan
if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    Write-Host '  PSScriptAnalyzer not installed - skipping (install with: Install-Module PSScriptAnalyzer -Scope CurrentUser)' -ForegroundColor Yellow
}
else {
    Import-Module PSScriptAnalyzer
    $pssa = @(Invoke-ScriptAnalyzer -Path $repoRoot -Recurse -ErrorAction SilentlyContinue |
             Where-Object { $_.ScriptPath -notlike '*\customers\*' })
    $pssaErrors = @($pssa | Where-Object Severity -eq 'Error')
    $pssaWarn = @($pssa | Where-Object Severity -eq 'Warning')
    if ($pssaErrors.Count) {
        $failed = $true
        $pssaErrors | ForEach-Object { Write-Host "  ERROR $($_.ScriptName):$($_.Line) $($_.RuleName): $($_.Message)" -ForegroundColor Red }
    }
    if ($pssaWarn.Count) {
        Write-Host "  $($pssaWarn.Count) warning(s):" -ForegroundColor Yellow
        $pssaWarn | Group-Object RuleName | Sort-Object Count -Descending | ForEach-Object {
            Write-Host "    $($_.Name): $($_.Count)"
        }
    }
    Write-Host ("  {0} error(s), {1} warning(s)" -f $pssaErrors.Count, $pssaWarn.Count)
}

Write-Host ''
Write-Host '=== 3. Pester ===' -ForegroundColor Cyan
try {
    Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
    $pesterResult = Invoke-Pester -Path (Join-Path $PSScriptRoot '*.Tests.ps1') -Output Detailed -PassThru
    if ($pesterResult.FailedCount -gt 0) { $failed = $true }
    Write-Host ("  {0} passed, {1} failed, {2} skipped" -f $pesterResult.PassedCount, $pesterResult.FailedCount, $pesterResult.SkippedCount)
}
catch {
    $failed = $true
    Write-Host "  Pester run failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ''
Write-Host '=== 4. Leak guard ===' -ForegroundColor Cyan
$leakFindings = @(& (Join-Path $PSScriptRoot 'Test-NoCustomerData.ps1') -NoExit)
if ($leakFindings.Count) { $failed = $true }

Write-Host ''
if ($failed) { Write-Host 'CHECKS FAILED' -ForegroundColor Red; exit 1 }
Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
exit 0
