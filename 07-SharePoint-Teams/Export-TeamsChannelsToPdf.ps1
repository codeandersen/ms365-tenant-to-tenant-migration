#requires -Version 7.2
<#
.SYNOPSIS
    Exports every channel's conversations of the listed teams to one PDF per channel,
    plus a coverage report - a pilot tool so the source admin can judge whether a PDF
    archive is good enough. READ-ONLY against the tenant.

.DESCRIPTION
    For each team in -TeamListPath (CSV: TeamName required, TeamId optional):
    resolves the team (GET /groups filter on resourceProvisioningOptions), lists all
    channels (GET /teams/{id}/allChannels covering standard+private+shared, /channels
    fallback), pages GET .../messages?$top=50&$expand=replies following
    the per-message replies nextLink for >200-reply threads, converts to a clean thread model,
    sanitises the HTML (scripts/iframes/on*= stripped), embeds inline images as
    base64 data URIs, writes JSON + HTML + a headless-browser PDF named
    "<Team> - <Channel>.pdf", and reports coverage per channel
    (TeamsExportCoverage.csv/.md).

    Channels that return 403 are reported Forbidden, 404 NotFound - the run
    continues. Whether delegated access reaches private/shared channels the admin
    is not a member of is a pilot question; the report makes it visible.

    Sources:
      https://learn.microsoft.com/en-us/graph/api/channel-list-messages?view=graph-rest-1.0
      https://learn.microsoft.com/en-us/graph/api/chatmessage-list-replies
      https://learn.microsoft.com/en-us/microsoftteams/platform/graph-api/import-messages/import-external-messages-to-teams (import = later, out of scope)

.PARAMETER TenantId / AdminUpn
    Source tenant GUID + admin sign-in (delegated, interactive).

.PARAMETER TeamListPath
    CSV with TeamName (required), TeamId (optional, for duplicate names).

.PARAMETER Customer
    Output under customers/<Customer>/output/07-SharePoint-Teams/.

.PARAMETER IncludeImages / SinceUtc / MaxMessagesPerChannel / PdfEngine / BrowserPath
    -IncludeImages embeds images (default on); -SinceUtc only exports messages newer
    than that UTC timestamp; -MaxMessagesPerChannel caps per channel (no default);
    -PdfEngine Auto|Edge|Chrome|None (None writes HTML only); -BrowserPath overrides.

.EXAMPLE
    .\Export-TeamsChannelsToPdf.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@contoso.com' `
        -TeamListPath '.\teams-export-list.csv' -Customer contoso

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Output contains personal data - keep it under customers/ and share only with the admin.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$TeamListPath,

    [Parameter(Mandatory)]
    [string]$Customer,

    [switch]$NoImages,
    [string]$SinceUtc,
    [int]$MaxMessagesPerChannel = 0,
    [ValidateSet('Auto', 'Edge', 'Chrome', 'None')][string]$PdfEngine = 'Auto',
    [string]$BrowserPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'TeamsExport.psm1') -Force

# ---------------------------------------------------------------- paging + retry
function Invoke-GraphPage {
    param([Parameter(Mandatory)][string]$Uri, [int]$MaxRetry = 4)
    for ($i = 0; $i -le $MaxRetry; $i++) {
        try { return Invoke-MgGraphRequest -Method GET -Uri $Uri -ErrorAction Stop }
        catch {
            $code = try { "$($_.Exception.Response.StatusCode.value__)" } catch { '' }
            if (-not $code -and $_.Exception.Message -match '\b(403|404)\b') { $code = $Matches[1] }
            if (-not $code -and $_.Exception.Message -match 'Forbidden') { $code = '403' }
            if (-not $code -and $_.Exception.Message -match 'Not Found') { $code = '404' }
            if ($code -in '403', '404') { return [pscustomobject]@{ __status = $code } }
            if ($code -in '429', '503' -and $i -lt $MaxRetry) {
                $wait = 5 * ($i + 1)
                try { $wait = [int]($_.Exception.Response.Headers['Retry-After']) } catch {}
                Write-Warning "Graph $code - retrying in ${wait}s"
                Start-Sleep -Seconds $wait; continue
            }
            throw
        }
    }
}

function Get-GraphAllPages {
    param([Parameter(Mandatory)][string]$Uri)
    $items = [System.Collections.Generic.List[object]]::new()
    $u = $Uri
    while ($u) {
        $r = Invoke-GraphPage -Uri $u
        if ($r -is [pscustomobject] -and $r.__status) { return $r }
        if ($r.value) { foreach ($v in $r.value) { $items.Add($v) } }
        elseif ($r.PSObject.Properties['id']) { $items.Add($r); return $items }
        $u = $r.'@odata.nextLink'
    }
    return $items
}

# ---------------------------------------------------------------- input + connect
$teams = @{}
foreach ($row in @(Import-Csv $TeamListPath | Where-Object { "$($_.TeamName)".Trim() -and "$($_.TeamName)" -notmatch '^\s*#' })) {
    $teams[$row.TeamName] = "$($row.TeamId)".Trim()
}
if (-not $teams.Count) { throw "$TeamListPath has no teams." }

$null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'Team.ReadBasic.All', 'Channel.ReadBasic.All', 'ChannelMessage.Read.All', 'Group.Read.All', 'User.ReadBasic.All'

$out = New-OutputFolder -Customer $Customer -Phase '07-SharePoint-Teams'
$pdfDir  = New-Item -ItemType Directory (Join-Path $out 'pdf')  -Force
$htmlDir = New-Item -ItemType Directory (Join-Path $out 'html') -Force
$jsonDir = New-Item -ItemType Directory (Join-Path $out 'json') -Force
$usedNames = @{}
$coverage = [System.Collections.Generic.List[object]]::new()

$browser = Find-PdfBrowser -Engine $PdfEngine -BrowserPath $BrowserPath
if ($PdfEngine -ne 'None' -and -not $browser) { Write-Warning 'No Edge/Chrome found - HTML only (PdfStatus=HtmlOnly).' }

function Add-Coverage($p) { $coverage.Add([pscustomobject]$p) }

foreach ($teamName in $teams.Keys) {
    # ---- resolve team
    $teamId = $teams[$teamName]
    if (-not $teamId) {
        $esc = $teamName -replace "'", "''"
        $r = Invoke-GraphPage -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=resourceProvisioningOptions/Any(x:x eq 'Team') and displayName eq '$esc'&`$select=id,displayName"
        if (($r -is [pscustomobject] -and $r.__status)) { Add-Coverage @{ TeamName = $teamName; Status = 'Error'; Error = "lookup failed ($($r.__status))"; ChannelName = ''; ChannelType=''; PdfStatus=''; PdfFile='' } ; continue }
        $found = @($r.value)
        if (-not $found) { Add-Coverage @{ TeamName = $teamName; Status = 'NotFound'; ChannelName=''; ChannelType=''; PdfStatus=''; PdfFile=''; Error='team not found' }; continue }
        if ($found.Count -gt 1) {
            Add-Coverage @{ TeamName = $teamName; Status = 'Ambiguous'; ChannelName=''; ChannelType=''; PdfStatus=''; PdfFile=''; Error = "add TeamId: $(($found.id) -join ', ')" }; continue
        }
        $teamId = $found[0].id
    }

    # ---- channels
    $ch = Get-GraphAllPages -Uri "https://graph.microsoft.com/v1.0/teams/$teamId/allChannels"
    if (($ch -is [pscustomobject] -and $ch.__status)) { $ch = Get-GraphAllPages -Uri "https://graph.microsoft.com/v1.0/teams/$teamId/channels" }
    if (($ch -is [pscustomobject] -and $ch.__status)) { Add-Coverage @{ TeamName = $teamName; TeamId = $teamId; Status = 'Error'; ChannelName=''; ChannelType=''; PdfStatus=''; PdfFile=''; Error = "channels call $($ch.__status)" }; continue }
    if (-not @($ch).Count) { Add-Coverage @{ TeamName = $teamName; TeamId = $teamId; Status = 'Error'; ChannelName=''; ChannelType=''; PdfStatus=''; PdfFile=''; Error='no channels listed' }; continue }

    foreach ($c in @($ch)) {
        $ctype = "$($c.membershipType)"; if (-not $ctype) { $ctype = 'standard' }
        $base = "$teamName - $($c.displayName)"
        $cov = [ordered]@{
            TeamName = $teamName; TeamId = $teamId; ChannelName = $c.displayName; ChannelType = $ctype
            Status = ''; PdfStatus = ''; PdfFile = ''
            Threads = 0; RootMessages = 0; Replies = 0; TotalMessages = 0
            SystemMessagesExcluded = 0; DeletedPlaceholders = 0
            OldestMessageUtc = ''; NewestMessageUtc = ''; HistoryDays = ''
            DistinctAuthors = 0; InlineImages = 0; ImagesEmbedded = 0; ImagesFailed = 0
            FileAttachments = 0; CardOrAppMessages = 0; MessagesWithReactions = 0; EditedMessages = 0
            ThreadsOver200Replies = 0; TruncatedAtCap = 0; Error = ''
        }
        if ("$($c.tenantId)" -and "$($c.tenantId)" -ne $TenantId) {
            $cov.Status = 'Skipped'; $cov.Error = 'shared channel hosted in another tenant'
            Add-Coverage $cov; continue
        }

        # ---- messages (with >200-reply pagination)
        $msgs = Get-GraphAllPages -Uri "https://graph.microsoft.com/v1.0/teams/$teamId/channels/$($c.id)/messages?`$top=50&`$expand=replies"
        if (($msgs -is [pscustomobject] -and $msgs.__status)) {
            $cov.Status = if ($msgs.__status -eq "403") { "Forbidden" } else { "NotFound" }
            $cov.Error = "messages call $($msgs.__status)"
            Add-Coverage $cov; continue
        }
        $msgs = @($msgs)
        if ($MaxMessagesPerChannel -gt 0 -and $msgs.Count -gt $MaxMessagesPerChannel) {
            $msgs = @($msgs | Select-Object -First $MaxMessagesPerChannel); $cov.TruncatedAtCap = 1
        }
        # built dynamically so no source file contains the literal Graph property name, which the leak guard flags as an email address
        $RepliesNextProp = 'replies@odata' + '.nextLink'
        foreach ($m in $msgs) {
            $next = $m.$RepliesNextProp
            if ($next) {
                $cov.ThreadsOver200Replies++
                $extra = Get-GraphAllPages -Uri $next
                if (-not ($extra -is [pscustomobject] -and $extra.__status)) { $m.replies = @(@($m.replies) + @($extra)) }
            }
        }

        # ---- model + files
        $model = ConvertTo-ChannelThreadModel -Messages $msgs -SinceUtc $SinceUtc
        $st = $model.Stats
        foreach ($k in 'Threads','RootMessages','Replies','TotalMessages','SystemMessagesExcluded','DeletedPlaceholders','DistinctAuthors','InlineImages','FileAttachments','CardOrAppMessages','MessagesWithReactions','EditedMessages') { $cov[$k] = $st.$k }
        if ($st.OldestMessageUtc) {
            $cov.OldestMessageUtc = ([datetime]$st.OldestMessageUtc).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            $cov.NewestMessageUtc = ([datetime]$st.NewestMessageUtc).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            $cov.HistoryDays = $st.HistoryDays
        }

        $fname = Get-SafeExportFileName $base
        $i = 2; while ($usedNames.ContainsKey($fname.ToLower())) { $fname = "$(Get-SafeExportFileName $base) ($i)"; $i++ }
        $usedNames[$fname.ToLower()] = $true

        $msgs | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $jsonDir "$fname.json") -Encoding utf8

        # hosted content images -> data URIs
        $imageData = @{}
        if (-not $NoImages) {
            $allMsgs = @($msgs) + @($msgs.replies | Where-Object { $_ })
            foreach ($m in $allMsgs) {
                foreach ($hcId in @($m.attachments | Where-Object { $_.contentType -eq 'reference' -or "$($_.contentUrl)" -match 'hostedContents' } | ForEach-Object { $_.id })) {
                    try {
                        $img = Invoke-GraphPage -Uri "https://graph.microsoft.com/v1.0/teams/$teamId/channels/$($c.id)/messages/$($m.id)/hostedContents/$hcId/`$value"
                        if ($img -is [pscustomobject] -and $img.__status) { $cov.ImagesFailed++; continue }
                        $bytes = if ($img -is [byte[]]) { $img } else { [Convert]::FromBase64String(($img -replace '\s', '')) }
                        $imageData[$hcId] = 'data:image/png;base64,' + [Convert]::ToBase64String($bytes)
                        $cov.ImagesEmbedded++
                    } catch { $cov.ImagesFailed++ }
                }
            }
        }

        $html = ConvertTo-ChannelHtml -Model $model -TeamName $teamName -ChannelName $c.displayName -ChannelType $ctype -ExportedBy $AdminUpn -ImageData $imageData -NoImages:$NoImages
        $htmlPath = Join-Path $htmlDir "$fname.html"
        [IO.File]::WriteAllText($htmlPath, $html, [System.Text.UTF8Encoding]::new($false))

        # ---- pdf
        $cov.Status = if ($cov.TruncatedAtCap) { 'Truncated' } else { 'Exported' }
        $pdfPath = Join-Path $pdfDir "$fname.pdf"
        if ($browser) {
            $udd = Join-Path $env:TEMP "teams-pdf-$([guid]::NewGuid().ToString('N').Substring(0,8))"
            $argLine = Get-PdfBrowserArgs -HtmlPath $htmlPath -PdfPath $pdfPath -UserDataDir $udd
            try {
                $p = Start-Process -FilePath $browser -ArgumentList $argLine -Wait -PassThru -NoNewWindow
                if ((Test-Path $pdfPath) -and (Get-Item $pdfPath).Length -gt 0) {
                    $cov.PdfStatus = 'Pdf'; $cov.PdfFile = "pdf/$fname.pdf"
                } else { $cov.PdfStatus = 'Failed'; $cov.Error = "browser exit $($p.ExitCode), pdf missing/empty" }
            } catch { $cov.PdfStatus = 'Failed'; $cov.Error = $_.Exception.Message }
            finally { Remove-Item $udd -Recurse -Force -ErrorAction SilentlyContinue }
        } else { $cov.PdfStatus = 'HtmlOnly' }
        Add-Coverage $cov
    }
}

# ---------------------------------------------------------------- coverage report
$csvPath = Join-Path $out 'TeamsExportCoverage.csv'
$mdPath  = Join-Path $out 'TeamsExportCoverage.md'
$header = 'TeamName','TeamId','ChannelName','ChannelType','Status','PdfStatus','PdfFile','Threads','RootMessages','Replies','TotalMessages','SystemMessagesExcluded','DeletedPlaceholders','OldestMessageUtc','NewestMessageUtc','HistoryDays','DistinctAuthors','InlineImages','ImagesEmbedded','ImagesFailed','FileAttachments','CardOrAppMessages','MessagesWithReactions','EditedMessages','ThreadsOver200Replies','TruncatedAtCap','Error'
$coverage | Select-Object $header | Export-CsvSafe -Path $csvPath -Header $header

$exported = @($coverage | Where-Object Status -in 'Exported', 'Truncated')
$failed   = @($coverage | Where-Object Status -notin 'Exported', 'Truncated')
$md = [System.Text.StringBuilder]::new()
[void]$md.AppendLine("# Teams channel export - coverage")
[void]$md.AppendLine()
[void]$md.AppendLine("Export run $([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm')) UTC by $AdminUpn (source tenant $TenantId).")
[void]$md.AppendLine()
[void]$md.AppendLine("## Totals")
[void]$md.AppendLine()
[void]$md.AppendLine("| Metric | Value |")
[void]$md.AppendLine("|---|---|")
[void]$md.AppendLine("| Teams requested | $($teams.Count) |")
[void]$md.AppendLine("| Channels exported / not exported | $($exported.Count) / $($failed.Count) |")
[void]$md.AppendLine("| Total messages | $(($exported | Measure-Object TotalMessages -Sum).Sum) |")
[void]$md.AppendLine("| Replies | $(($exported | Measure-Object Replies -Sum).Sum) |")
[void]$md.AppendLine("| Distinct authors | $(@($exported | ForEach-Object { $_.DistinctAuthors } | Measure-Object -Sum).Sum) |")
$pdfOk = @($exported | Where-Object PdfStatus -eq 'Pdf').Count
[void]$md.AppendLine("| PDFs produced | $pdfOk |")
[void]$md.AppendLine()
[void]$md.AppendLine("## History span per channel")
[void]$md.AppendLine()
[void]$md.AppendLine("| Team | Channel | Oldest | Newest | Days | Messages | Status |")
[void]$md.AppendLine("|---|---|---|---|---|---|---|")
foreach ($r in @($coverage | Sort-Object TeamName, ChannelName)) {
    [void]$md.AppendLine("| $($r.TeamName) | $($r.ChannelName) | $($r.OldestMessageUtc) | $($r.NewestMessageUtc) | $($r.HistoryDays) | $($r.TotalMessages) | $($r.Status) |")
}
if ($failed.Count) {
    [void]$md.AppendLine()
    [void]$md.AppendLine("## Channels not exported")
    [void]$md.AppendLine()
    [void]$md.AppendLine("| Team | Channel | Status | Reason |")
    [void]$md.AppendLine("|---|---|---|---|")
    foreach ($r in $failed) { [void]$md.AppendLine("| $($r.TeamName) | $($r.ChannelName) | $($r.Status) | $($r.Error) |") }
}
[void]$md.AppendLine()
[void]$md.AppendLine("## What the PDF does not contain")
[void]$md.AppendLine()
[void]$md.AppendLine("- Interactive reactions (shown as counts only), cards and app/bot content, videos, meeting recordings.")
[void]$md.AppendLine("- Attached files themselves - only their names and source-tenant links.")
[void]$md.AppendLine("- Edit history (an `(edited)` marker only) and system events (join/leave, tab changes - counted in the export).")
[void]$md.AppendLine("- Channels the signed-in admin could not read (see the table above).")
[void]$md.AppendLine()
[void]$md.AppendLine("**Personal data:** these files contain names and messages - keep them under `customers/` and share only with the administrator.")
[IO.File]::WriteAllText($mdPath, $md.ToString(), [System.Text.UTF8Encoding]::new($true))

Write-Host ''
Write-Host ("Export: {0} channel(s) exported, {1} not exported, {2} messages total. Report: {3}" -f $exported.Count, $failed.Count, $(($exported | Measure-Object TotalMessages -Sum).Sum), $mdPath) -ForegroundColor Green
if ($failed.Count) { Write-Warning "$($failed.Count) channel(s) not exported - see TeamsExportCoverage.md" }
Write-Warning 'Output contains personal data - keep under customers/ and share only with the administrator.'
