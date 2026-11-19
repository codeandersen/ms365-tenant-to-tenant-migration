# Pure helpers for Export-TeamsChannelsToPdf.ps1 - no Graph calls, no tenant access.
# https://learn.microsoft.com/en-us/graph/api/channel-list-messages?view=graph-rest-1.0

function Get-SafeExportFileName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    $n = $Name -replace '[\\\/:*?"<>|]', '_'
    $n = ($n.ToCharArray() | ForEach-Object { if ([char]::IsControl($_)) { '_' } else { $_ } }) -join ''
    $n = $n.TrimEnd(' ', '.').Trim()
    if ($n.Length -gt 150) { $n = $n.Substring(0, 150).TrimEnd(' ', '.') }
    return $n
}

function Protect-TeamsHtml {
    <#
    .SYNOPSIS  Allowlist-sanitise message HTML (no external libraries).
    Strips <script>/<style>/<iframe>/<object> elements entirely, all on*=
    attributes, javascript:/vbscript: URLs and tags outside the allowlist.
    #>
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Html)
    if ([string]::IsNullOrWhiteSpace($Html)) { return '' }
    $h = $Html
    # drop dangerous elements with their contents
    $h = [regex]::Replace($h, '(?is)<(script|style|iframe|object|embed|form|link|meta|base)[^>]*>.*?</\s*\1\s*>', '')
    $h = [regex]::Replace($h, '(?is)<(script|style|iframe|object|embed|form|link|meta|base)[^>]*/?>', '')
    # neutralise javascript:/vbscript: URLs
    $h = [regex]::Replace($h, '(?i)(href|src)\s*=\s*([''"])(javascript|vbscript)\s*:', '$1=$2blocked:')
    # strip on*= attributes
    $h = [regex]::Replace($h, '(?i)\s+on[a-z]+\s*=\s*("[^"]*"|''[^'']*''|[^\s>]+)', '')
    # allowlist tags: replace anything else with its inner text
    $allowed = 'p|br|b|strong|i|em|u|s|del|a|ul|ol|li|blockquote|pre|code|span|div|table|thead|tbody|tr|td|th|img|h[1-6]|hr|font'
    $h = [regex]::Replace($h, '<(/?)([a-zA-Z][a-zA-Z0-9]*)((\s[^<>]*)?)/?>', {
        param($m)
        $tag = $m.Groups[2].Value.ToLower()
        if ($tag -notmatch "^($allowed)$") { return '' }
        if ($tag -eq 'img') {
            # keep only data: URIs (self-contained images we embedded)
            $attrs = $m.Groups[3].Value
            if ($attrs -match 'src\s*=\s*"data:image/[^"]+"') { return "<img $($Matches[0]) alt='image'>" }
            return '<span class="img-placeholder">[image]</span>'
        }
        if ($tag -eq 'a') {
            $attrs = $m.Groups[3].Value
            if ($m.Groups[1].Value -ne '/' -and $attrs -match 'href\s*=\s*"([^"]+)"') {
                $u = $Matches[1]
                if ($u -match '^(https?|mailto):') { return "<a href=`"$u`">" }
                return ''
            }
            return '</a>'
        }
        $close = if ($m.Groups[1].Value -eq '/') { '/' } else { '' }
        if ($tag -in 'br','hr') { return "<$tag>" }
        return "<$close$tag>"
    })
    return $h
}

function ConvertTo-ChannelThreadModel {
    <#
    .SYNOPSIS  Normalise raw channel-message JSON into a thread model + stats.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Messages,
        [string]$SinceUtc
    )
    $stats = [ordered]@{
        Threads = 0; RootMessages = 0; Replies = 0; TotalMessages = 0
        SystemMessagesExcluded = 0; DeletedPlaceholders = 0
        DistinctAuthors = 0; InlineImages = 0; FileAttachments = 0
        CardOrAppMessages = 0; MessagesWithReactions = 0; EditedMessages = 0
        OldestMessageUtc = $null; NewestMessageUtc = $null; HistoryDays = $null
    }
    $authors = @{}
    $roots = [System.Collections.Generic.List[object]]::new()
    $cutoff = $null
    if ($SinceUtc) { $cutoff = [datetime]::Parse($SinceUtc, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) }

    function Convert-One($m) {
        $deleted = $null -ne $m.deletedDateTime
        $body = if ($deleted) { '' } else { "$($m.body.content)" }
        $author = "$($m.from.user.displayName)"
        if (-not $author) { $author = "$($m.from.application.displayName)" }
        if (-not $author) { $author = '(unknown)' }
        $mentions = @($m.mentions | ForEach-Object { "$($_.mentioned.user.displayName)$($_.mentioned.application.displayName)" } | Where-Object { $_ })
        $reactions = @{}
        foreach ($r in @($m.reactions)) {
            $t = "$($r.reactionType)"
            if ($reactions.ContainsKey($t)) { $reactions[$t]++ } else { $reactions[$t] = 1 }
        }
        $atts = @($m.attachments | ForEach-Object {
            [pscustomobject]@{ Name = "$($_.name)"; ContentUrl = "$($_.contentUrl)"; ContentType = "$($_.contentType)" }
        })
        $hosted = @($m.attachments | Where-Object { $_.contentType -eq 'reference' -or "$($_.contentUrl)" -match 'hostedContents' } | ForEach-Object { "$($_.id)" })
        [pscustomobject]@{
            Id = $m.id; Created = $m.createdDateTime; Edited = $m.lastModifiedDateTime -ne $m.createdDateTime
            Author = $author; IsApp = [bool]($m.from.application.displayName -and -not $m.from.user.displayName)
            Subject = "$($m.subject)"; Body = $body; BodyType = "$($m.body.contentType)"
            Mentions = $mentions; Reactions = $reactions; Attachments = $atts; HostedContentIds = $hosted
            Deleted = $deleted
        }
    }

    foreach ($root in @($Messages)) {
        if ("$($root.messageType)" -eq 'systemEventMessage') { $stats.SystemMessagesExcluded++; continue }
        $c = [datetime]::Parse("$($root.createdDateTime)", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
        if ($cutoff -and $c -lt $cutoff) { continue }
        $mr = Convert-One $root
        $stats.RootMessages++
        $replies = [System.Collections.Generic.List[object]]::new()
        foreach ($rep in @($root.replies)) {
            if ("$($rep.messageType)" -eq 'systemEventMessage') { $stats.SystemMessagesExcluded++; continue }
            $rr = Convert-One $rep
            $replies.Add($rr); $stats.Replies++
            if ($rr.Deleted) { $stats.DeletedPlaceholders++ }
        }
        if ($mr.Deleted) { $stats.DeletedPlaceholders++ }
        $roots.Add([pscustomobject]@{ Root = $mr; Replies = @($replies | Sort-Object { [datetime]$_.Created }) })
        foreach ($x in @($mr) + @($replies)) {
            if ($x.Author -ne '(unknown)' -and -not $x.IsApp) { $authors[$x.Author] = $true }
            $stats.InlineImages += @($x.Body | Select-String '<img' -AllMatches).Matches.Count + $x.HostedContentIds.Count
            $stats.FileAttachments += @($x.Attachments | Where-Object ContentType -ne 'reference').Count
            if ($x.Reactions.Count) { $stats.MessagesWithReactions++ }
            if ($x.Edited) { $stats.EditedMessages++ }
            $d = [datetime]::Parse("$($x.Created)", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            if (-not $stats.OldestMessageUtc -or $d -lt [datetime]$stats.OldestMessageUtc) { $stats.OldestMessageUtc = $d }
            if (-not $stats.NewestMessageUtc -or $d -gt [datetime]$stats.NewestMessageUtc) { $stats.NewestMessageUtc = $d }
        }
    }
    $stats.Threads = $roots.Count
    $stats.TotalMessages = $stats.RootMessages + $stats.Replies
    $stats.DistinctAuthors = $authors.Count
    $stats.CardOrAppMessages = @($roots | ForEach-Object { @($_.Root) + @($_.Replies) } | Where-Object { $_.IsApp }).Count
    if ($stats.OldestMessageUtc) { $stats.HistoryDays = [int]([datetime]$stats.NewestMessageUtc - [datetime]$stats.OldestMessageUtc).TotalDays }
    return [pscustomobject]@{ Threads = @($roots | Sort-Object { [datetime]$_.Root.Created }); Stats = [pscustomobject]$stats }
}

function ConvertTo-ChannelHtml {
    <#
    .SYNOPSIS  Render a thread model to a self-contained HTML page (sanitised).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Model,     # from ConvertTo-ChannelThreadModel
        [Parameter(Mandatory)][string]$TeamName,
        [Parameter(Mandatory)][string]$ChannelName,
        [string]$ChannelType = 'standard',
        [string]$ExportedBy = '',
        [hashtable]$ImageData = @{},                       # hostedContentId -> base64 data URI
        [switch]$NoImages
    )

    function Encode([string]$s) { [System.Web.HttpUtility]::HtmlEncode($s) }
    if (-not ([System.Web.HttpUtility] -as [type])) { Add-Type -AssemblyName System.Web }
    function Render-Message($m) {
        $b = [System.Text.StringBuilder]::new()
        [void]$b.Append("<div class='msg'><span class='author'>$(Encode $m.Author)</span>")
        [void]$b.Append(" <span class='date'>$(Encode ([datetime]$m.Created).ToUniversalTime().ToString('yyyy-MM-dd HH:mm')) UTC</span>")
        if ($m.Edited) { [void]$b.Append(" <span class='edited'>(edited)</span>") }
        if ($m.Subject) { [void]$b.Append(" <b>$(Encode $m.Subject)</b>") }
        if ($m.Deleted) {
            [void]$b.Append("<div class='body'><i>[message deleted]</i></div>")
        } elseif ($m.IsApp) {
            [void]$b.Append("<div class='body'><i>[card/app content - not rendered]</i></div>")
        } else {
            $body = "$($m.Body)"
            # point hosted-content image URLs at the embedded data URIs BEFORE sanitising
            foreach ($hc in $m.HostedContentIds) {
                if (-not $NoImages -and $ImageData[$hc]) {
                    $body = $body -replace "src=`"[^`"]*hostedContents/$hc/\`$value`"", "src=`"$($ImageData[$hc])`""
                }
            }
            $body = Protect-TeamsHtml $body   # non-data imgs become [image] placeholders here
            if (-not $body) { $body = '<i>[no text]</i>' }
            [void]$b.Append("<div class='body'>$body</div>")
        }
        foreach ($a in $m.Attachments | Where-Object { $_.ContentType -ne 'reference' }) {
            [void]$b.Append("<div class='attach'>📎 $(Encode $a.Name) (<a href=`"$(Encode $a.ContentUrl)`">source tenant link</a>)</div>")
        }
        if ($m.Mentions.Count) { [void]$b.Append("<div class='mentions'>mentions: $(Encode ($m.Mentions -join ', '))</div>") }
        if ($m.Reactions.Count) {
            $r = ($m.Reactions.GetEnumerator() | ForEach-Object { "$(Encode $_.Key) $($_.Value)" }) -join '  '
            [void]$b.Append("<div class='reactions'>$r</div>")
        }
        [void]$b.Append('</div>')
        return $b.ToString()
    }

    $s = $Model.Stats
    $threads = [System.Text.StringBuilder]::new()
    foreach ($t in $Model.Threads) {
        [void]$threads.Append("<div class='thread'>")
        [void]$threads.Append((Render-Message $t.Root))
        foreach ($r in $t.Replies) { [void]$threads.Append("<div class='reply'>" + (Render-Message $r) + '</div>') }
        [void]$threads.Append('</div>')
    }
    $period = if ($s.OldestMessageUtc) { "$(([datetime]$s.OldestMessageUtc).ToUniversalTime().ToString('yyyy-MM-dd')) to $(([datetime]$s.NewestMessageUtc).ToUniversalTime().ToString('yyyy-MM-dd'))" } else { 'no messages' }
    $imgNote = if ($NoImages) { 'Inline images replaced by [image] placeholders (-IncludeImages off).' } else { 'Inline images are embedded as data URIs.' }
    @"
<!DOCTYPE html><html><head><meta charset="utf-8"><title>$(Encode "$TeamName - $ChannelName")</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;font-size:11pt;margin:2em;color:#222}
.cover{border-bottom:2px solid #444;padding-bottom:1em;margin-bottom:1.5em}
.cover h1{font-size:18pt}.cover td{padding:2px 10px 2px 0}
.thread{border:1px solid #ccc;margin:1em 0;padding:.6em;page-break-inside:avoid}
.msg{margin:.4em 0}.reply{margin-left:2.5em;border-left:3px solid #ddd;padding-left:.8em}
.author{font-weight:bold}.date{color:#666;font-size:9pt}.edited{color:#999;font-size:9pt}
.mentions,.reactions,.attach{color:#555;font-size:9pt;margin:.2em 0}
blockquote{border-left:3px solid #ccc;margin:.3em;padding-left:.8em;color:#555}
pre,code{background:#f4f4f4;font-family:Consolas,monospace}pre{padding:.5em}
img{max-width:600px;max-height:400px}.img-placeholder{color:#999}
.warn{background:#fff3cd;border:1px solid #e0c878;padding:.6em;margin:1em 0;font-size:9.5pt}
.footer{font-size:8pt;color:#888;text-align:center;margin-top:2em}
</style></head><body>
<div class='cover'><h1>$(Encode $TeamName) — #$(Encode $ChannelName)</h1>
<table>
<tr><td>Channel type</td><td>$(Encode $ChannelType)</td><td>Exported</td><td>$([datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm')) UTC</td></tr>
<tr><td>Period</td><td>$period</td><td>Exported by</td><td>$(Encode $ExportedBy)</td></tr>
<tr><td>Threads</td><td>$($s.Threads)</td><td>Messages</td><td>$($s.TotalMessages) ($($s.RootMessages) roots, $($s.Replies) replies)</td></tr>
<tr><td>Authors</td><td>$($s.DistinctAuthors)</td><td>Excluded</td><td>$($s.SystemMessagesExcluded) system, $($s.DeletedPlaceholders) deleted</td></tr>
</table>
<div class='warn'>This file contains personal data (names and messages). Treat it like the tenant inventory - do not share beyond the administrator. $imgNote Attachment links point at the SOURCE tenant and stop working after decommission. Reactions, cards/app content, videos and system events are not in this PDF.</div>
</div>
$threads
<div class='footer'>Exported from Microsoft Teams (read-only Graph export) - page numbers are added by the PDF viewer.</div>
</body></html>
"@
}

function Find-PdfBrowser {
    [CmdletBinding()]
    param([ValidateSet('Auto', 'Edge', 'Chrome', 'None')][string]$Engine = 'Auto', [string]$BrowserPath)
    if ($Engine -eq 'None') { return $null }
    if ($BrowserPath -and (Test-Path $BrowserPath)) { return (Resolve-Path $BrowserPath).Path }
    $candidates = @()
    if ($Engine -in 'Auto', 'Edge') {
        $candidates += "$env:ProgramFiles (x86)\Microsoft\Edge\Application\msedge.exe",
            "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
            "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    }
    if ($Engine -in 'Auto', 'Chrome') {
        $candidates += "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    }
    foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

function Get-PdfBrowserArgs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$HtmlPath, [Parameter(Mandatory)][string]$PdfPath, [Parameter(Mandatory)][string]$UserDataDir)
    return @(
        '--headless', '--disable-gpu', '--no-pdf-header-footer',
        "--user-data-dir=`"$UserDataDir`"",
        "--print-to-pdf=`"$PdfPath`"",
        "`"$HtmlPath`""
    ) -join ' '
}

Export-ModuleMember -Function Get-SafeExportFileName, Protect-TeamsHtml, ConvertTo-ChannelThreadModel,
    ConvertTo-ChannelHtml, Find-PdfBrowser, Get-PdfBrowserArgs
