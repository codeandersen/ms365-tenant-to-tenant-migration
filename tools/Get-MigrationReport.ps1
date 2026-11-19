# Adapted from mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit@4de1a31 (MIT). See THIRD-PARTY-NOTICES.md.
# Changes:
#   - Reads reports from this repo's customers/<name>/output/<phase>/<timestamp> layout via -Customer
#     (recursion is the default there); -Folder still works for an arbitrary folder.
#   - Optional -OutFile writes the per-report summary via Export-CsvSafe (UTF-8 BOM) from Common.psm1.
#   - Updated the known report types to this playbook's phases (Mezba phase numbers removed).
<#
.SYNOPSIS
    Reads the report CSVs the playbook's scripts write and shows, in one place, what worked and what still needs a
    look: counts by Status or Result, and every row that isn't done.

.DESCRIPTION
    TL;DR: By cutover night you have a dozen report CSVs under customers/<name>/output/<phase>/<timestamp>, each
    with a few skips, conflicts or problems buried in it. This finds the newest report of each type (or every
    report with -All), counts the rows by Status or Result, and prints the rows that aren't Done, Exists, OK,
    WhatIf, Successful, Pass, Created, Added or Set, with the columns that matter picked out for you. -Html writes
    the same thing as one self-contained page you can attach to the handover. Read-only: it never signs in to a
    tenant.

    Any CSV in the output tree with a Status or Result column is picked up; file names are grouped by their
    report-type prefix (the part before the trailing date stamp). Files holding passwords are never read.

.PARAMETER Customer
    The customers/<name> folder to read. The newest files are found anywhere under
    customers/<Customer>/output/<phase>/<timestamp>/. Exactly one of -Customer or -Folder is required.

.PARAMETER Folder
    Explicit folder to read instead of a customer output tree.

.PARAMETER Recurse
    Look in subfolders too. Default on for -Customer (the output tree is nested); off for -Folder.

.PARAMETER All
    Include every matching CSV, not just the newest of each type.

.PARAMETER Html
    Also write MigrationReport-<date>.html into the report folder: one page, no external files.

.PARAMETER OutFile
    Optional CSV path for the summary table (written via Export-CsvSafe, UTF-8 BOM).

.PARAMETER MaxRows
    The most problem rows to show per report on screen. Default 50. The HTML shows them all.

.EXAMPLE
    .\Get-MigrationReport.ps1 -Customer contoso

.EXAMPLE
    .\Get-MigrationReport.ps1 -Customer contoso -Html -OutFile summary.csv

.EXAMPLE
    .\Get-MigrationReport.ps1 -Folder C:\T2T -Recurse -All -MaxRows 500

.NOTES
    Requires: PowerShell 7.2 or later. No modules, no sign-in (Export-CsvSafe comes from tools/Common.psm1).
    The HTML holds names and addresses from the reports. Treat it like the CSVs: keep it under customers/<name>/.
#>
#requires -Version 7.2
[CmdletBinding()]
param(
    [string]$Customer,
    [string]$Folder,
    [switch]$Recurse,
    [switch]$All,
    [switch]$Html,
    [string]$OutFile,
    [int]$MaxRows = 50
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -Force

if ($Customer -and $Folder) { throw 'Use either -Customer or -Folder, not both.' }
if ($Customer) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $Folder = Join-Path $repoRoot (Join-Path 'customers' (Join-Path $Customer 'output'))
    if (-not $Recurse) { $Recurse = [switch]::new($true) }
}
if (-not $Folder) { $Folder = '.' }
if ($OutFile) { Assert-CustomerDataPath -Path $OutFile }
if (-not (Test-Path $Folder)) { throw "$Folder not found." }
$Folder = (Resolve-Path $Folder).Path

$okValues = 'Done', 'Skip', 'SKIP', 'Info', 'INFO', 'Exists', 'OK', 'WhatIf', 'Successful', 'Success', 'Pass', 'Created', 'Added', 'Set', 'Already existed', 'Removed', 'Requested', 'Copy', 'Completed',
             'Info', 'Unchanged', 'Blocked', 'AlreadyBlocked'
$preferred = 'Computer', 'Person', 'Object', 'Source', 'User', 'Name', 'Identity', 'Address', 'PrimarySmtpAddress', 'Domain', 'Area', 'Check', 'Action',
             'Type', 'Stage', 'Status', 'Result', 'Expected', 'Actual', 'Value', 'Destination', 'DestinationSite', 'DestinationFolder',
             'Errors', 'Warnings', 'Detail', 'Note', 'Reason', 'Fix', 'Message'

# ------------------------------------------------------------ find the reports
$gci = @{ Path = $Folder; Filter = '*.csv'; File = $true }
if ($Recurse) { $gci.Recurse = $true }
$files = @(Get-ChildItem @gci | Where-Object { $_.Name -notmatch 'Password' -and $_.Name -notlike 'MigrationReport-*' })

function Get-ReportType($file) {
    # The name without its date stamp, e.g. Something-20261110-1800.csv -> Something
    $file.BaseName -replace '-\d{8}(-\d{4,6})?$', ''
}
function Get-Header($path) {
    $line = Get-Content -LiteralPath $path -TotalCount 1
    @("$line".Split(',') | ForEach-Object { $_.Trim('"', ' ') })
}

$candidates = foreach ($f in $files) {
    $type = Get-ReportType $f
    $header = Get-Header $f.FullName
    $statusCol = @('Status', 'Result') | Where-Object { $header -contains $_ } | Select-Object -First 1
    if ($statusCol) {
        [pscustomobject]@{ File = $f; Type = $type; Group = $type; StatusColumn = $statusCol }
    }
}
$candidates = @($candidates)
if (-not $candidates) { Write-Host "No playbook reports found in $Folder$(if (-not $Recurse) { '. Try -Recurse' })." -ForegroundColor Yellow; return }

# Newest by write time, then by the date stamp in the name (copied files can share a write time).
$byAge = @{ e = { $_.File.LastWriteTime } }, @{ e = { $_.File.Name } }
$chosen = if ($All) { $candidates }
          else { $candidates | Group-Object Group | ForEach-Object { $_.Group | Sort-Object $byAge -Descending | Select-Object -First 1 } }
$chosen = @($chosen | Sort-Object (@{ e = { $_.Type } }, $byAge[0], $byAge[1]))

# ------------------------------------------------------------ read each one
$sections = foreach ($c in $chosen) {
    $rows = @(Import-Csv -LiteralPath $c.File.FullName)
    $cols = @(if ($rows) { $rows[0].PSObject.Properties.Name })
    $sc = $c.StatusColumn
    $counts = @()
    $problems = @()
    if ($sc) {
        $counts = @($rows | Group-Object $sc | Sort-Object Count -Descending | ForEach-Object { [pscustomobject]@{ Value = $(if ($_.Name) { $_.Name } else { '(blank)' }); Count = $_.Count } })
        $problems = @($rows | Where-Object {
                $v = "$($_.$sc)".Trim()
                ($okValues -notcontains $v) -or ($cols -contains 'Errors' -and "$($_.Errors)" -match '^\d+$' -and [int]$_.Errors -gt 0)
            })
    }
    else {
        $problems = $rows   # no status column: show everything
    }
    # Useful columns: preferred names that exist and aren't blank in the rows we show, then up to 8 of them.
    $show = @($preferred | Where-Object { $cols -contains $_ } | Where-Object { $n = $_; @($problems | Where-Object { "$($_.$n)" }).Count })
    if (-not $show) { $show = @($cols | Select-Object -First 6) }
    $show = @($show | Select-Object -First 8)
    [pscustomobject]@{
        Type = $c.Type; File = $c.File.FullName; Written = $c.File.LastWriteTime
        StatusColumn = $sc; Total = $rows.Count; Counts = $counts; Problems = $problems; Columns = $show
    }
}

# ------------------------------------------------------------ screen
$summary = foreach ($s in $sections) {
    [pscustomobject]@{
        Report   = $s.Type
        Written  = $s.Written.ToString('yyyy-MM-dd HH:mm')
        Rows     = $s.Total
        ToReview = $(if ($s.StatusColumn) { $s.Problems.Count } else { 'all (no status)' })
        Counts   = (($s.Counts | ForEach-Object { "$($_.Value) $($_.Count)" }) -join ', ')
    }
}
Write-Host ''
Write-Host "Migration reports in $Folder" -ForegroundColor Cyan
$summary | Format-Table -AutoSize -Wrap | Out-String -Width 250 | Write-Host

foreach ($s in $sections) {
    if ($s.StatusColumn -and -not $s.Problems.Count) { continue }
    $title = if ($s.StatusColumn) { "$($s.Problems.Count) row(s) to review" } else { "$($s.Total) row(s), no status column" }
    Write-Host "== $($s.Type): $title" -ForegroundColor Yellow
    Write-Host "   $($s.File)" -ForegroundColor DarkGray
    $s.Problems | Select-Object -First $MaxRows | Select-Object $s.Columns | Format-Table -AutoSize -Wrap | Out-String -Width 250 | Write-Host
    if ($s.Problems.Count -gt $MaxRows) { Write-Host "   ...and $($s.Problems.Count - $MaxRows) more. Raise -MaxRows or use -Html." -ForegroundColor DarkGray }
}
$open = ($sections | Where-Object StatusColumn | ForEach-Object { $_.Problems.Count } | Measure-Object -Sum).Sum
if ($open) { Write-Host "$open row(s) across all reports need a look. Problem, Conflict, Blocker and Fail first; Skipped and Warn next." -ForegroundColor Yellow }
else { Write-Host 'Nothing left to review in the status reports.' -ForegroundColor Green }

if ($OutFile) {
    $summary | Export-CsvSafe -Path $OutFile
    Write-Host "Summary: $OutFile" -ForegroundColor Cyan
}

# ------------------------------------------------------------ html
if ($Html) {
    function ConvertTo-Safe($t) { [System.Net.WebUtility]::HtmlEncode("$t") }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append(@'
<!DOCTYPE html><html lang="en-GB"><head><meta charset="utf-8"><title>Migration report</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#222}h1{font-size:22px}h2{font-size:17px;margin-top:28px}
table{border-collapse:collapse;margin:8px 0;font-size:13px}th,td{border:1px solid #ccc;padding:4px 8px;text-align:left;vertical-align:top}
th{background:#f2f2f2}.ok{color:#2e7d32}.warn{color:#b26a00}.muted{color:#777;font-size:12px}
</style></head><body>
'@)
    [void]$sb.Append("<h1>Migration report</h1><p class=""muted"">Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm') from $(ConvertTo-Safe $Folder). Contains names and addresses: handle like the CSVs.</p>")
    [void]$sb.Append('<table><tr><th>Report</th><th>Written</th><th>Rows</th><th>To review</th><th>Counts</th></tr>')
    foreach ($r in $summary) {
        [void]$sb.Append("<tr><td>$(ConvertTo-Safe $r.Report)</td><td>$($r.Written)</td><td>$($r.Rows)</td><td>$(ConvertTo-Safe $r.ToReview)</td><td>$(ConvertTo-Safe $r.Counts)</td></tr>")
    }
    [void]$sb.Append('</table>')
    foreach ($s in $sections) {
        [void]$sb.Append("<h2>$(ConvertTo-Safe $s.Type)</h2><p class=""muted"">$(ConvertTo-Safe $s.File)</p>")
        if ($s.StatusColumn -and -not $s.Problems.Count) { [void]$sb.Append('<p class="ok">Nothing to review.</p>'); continue }
        [void]$sb.Append('<table><tr>')
        foreach ($c in $s.Columns) { [void]$sb.Append("<th>$(ConvertTo-Safe $c)</th>") }
        [void]$sb.Append('</tr>')
        foreach ($row in $s.Problems) {
            [void]$sb.Append('<tr>')
            foreach ($c in $s.Columns) { [void]$sb.Append("<td>$(ConvertTo-Safe $row.$c)</td>") }
            [void]$sb.Append('</tr>')
        }
        [void]$sb.Append('</table>')
    }
    $out = Join-Path $Folder "MigrationReport-$(Get-Date -Format 'yyyyMMdd-HHmm').html"
    Assert-CustomerDataPath -Path $out
    $sb.ToString() | Out-File -FilePath $out -Encoding utf8BOM
    Write-Host "HTML: $out" -ForegroundColor Cyan
}
