BeforeAll {
    $repo = (Resolve-Path "$PSScriptRoot\..").Path
    Import-Module "$repo\tools\Common.psm1" -Force
    Import-Module "$repo\07-SharePoint-Teams\TeamsExport.psm1" -Force
    $fx = "$PSScriptRoot\fixtures\teams-export"
    $script:msgs = (Get-Content "$fx\channel-messages.json" -Raw | ConvertFrom-Json).value
}

Describe 'Get-SafeExportFileName' {
    It 'replaces invalid characters' {
        Get-SafeExportFileName 'a/b:c*d?"e<f>g|h' | Should -Be 'a_b_c_d__e_f_g_h'
    }
    It 'trims trailing dots/spaces and keeps æøå' {
        Get-SafeExportFileName 'Søren - Generelt . ' | Should -Be 'Søren - Generelt'
    }
    It 'caps at 150 chars' { (Get-SafeExportFileName ('x' * 300)).Length | Should -Be 150 }
}

Describe 'ConvertTo-ChannelThreadModel' {
    BeforeAll { $script:model = ConvertTo-ChannelThreadModel -Messages $script:msgs }
    It 'excludes system messages and counts them' {
        $script:model.Stats.SystemMessagesExcluded | Should -Be 1
        $script:model.Stats.Threads | Should -Be 2
    }
    It 'orders threads and replies oldest first' {
        $script:model.Threads[0].Root.Id | Should -Be 'm1'
        ($script:model.Threads[0].Replies.Id) -join ',' | Should -Be 'r1,r2,r3'
    }
    It 'deleted reply becomes a placeholder' {
        $script:model.Threads[0].Replies[1].Deleted | Should -BeTrue
        $script:model.Stats.DeletedPlaceholders | Should -Be 1
    }
    It 'counts authors, reactions, attachments, edited' {
        $script:model.Stats.DistinctAuthors | Should -Be 3
        $script:model.Stats.MessagesWithReactions | Should -Be 1
        $script:model.Threads[0].Root.Reactions['👍'] | Should -Be 2
        $script:model.Stats.FileAttachments | Should -Be 1
        $script:model.Stats.EditedMessages | Should -Be 1
        $script:model.Stats.CardOrAppMessages | Should -Be 1
        $script:model.Stats.TotalMessages | Should -Be 5
    }
    It 'history span is oldest->newest' {
        $script:model.Stats.OldestMessageUtc.ToString('yyyy-MM-dd') | Should -Be '2025-01-02'
        $script:model.Stats.NewestMessageUtc.ToString('yyyy-MM-dd') | Should -Be '2025-01-05'
        $script:model.Stats.HistoryDays | Should -Be 3
    }
}

Describe 'Protect-TeamsHtml / ConvertTo-ChannelHtml' {
    BeforeAll {
        Add-Type -AssemblyName System.Web
        $script:model = ConvertTo-ChannelThreadModel -Messages $script:msgs
        $script:html = ConvertTo-ChannelHtml -Model $script:model -TeamName 'Contoso IT' -ChannelName 'Generelt' -ChannelType 'standard' -ExportedBy 'admin@contoso.com' -NoImages
    }
    It 'strips script, onclick and javascript: urls' {
        $script:html | Should -Not -Match '<script'
        $script:html | Should -Not -Match 'onclick'
        $script:html | Should -Not -Match 'javascript:'
        $script:html | Should -Match 'https://contoso\.com/x'
    }
    It 'renders mentions and reactions and attachments' {
        $script:html | Should -Match 'mentions: Anna Andersen'
        $script:html | Should -Match '(&#128077;|👍) 2'
        $script:html | Should -Match 'plan\.xlsx'
        $script:html | Should -Match 'source tenant link'
    }
    It 'uses [image] placeholder with -NoImages, data URI with image data' {
        $script:html | Should -Match '\[image\]'
        $withImg = ConvertTo-ChannelHtml -Model $script:model -TeamName t -ChannelName c -ImageData @{ hc1 = 'data:image/png;base64,AAAA' }
        $withImg | Should -Match 'data:image/png;base64,AAAA'
    }
    It 'deleted messages and app content are placeholders' {
        $script:html | Should -Match '\[message deleted\]'
        $script:html | Should -Match '\[card/app content - not rendered\]'
    }
    It 'front page has coverage numbers, UTF-8 meta and æøå' {
        $script:html | Should -Match 'meta charset="utf-8"'
        $script:html | Should -Match '(Søren Å|S&#248;ren &#197;)'
        $script:html | Should -Match '5 \(2 roots, 3 replies\)'
        $script:html | Should -Match 'Contoso IT'
    }
}

Describe 'Browser helpers' {
    It 'finds Edge on this machine via Auto' {
        Find-PdfBrowser -Engine Auto | Should -Not -BeNullOrEmpty
    }
    It 'None returns nothing; args are headless print-to-pdf' {
        Find-PdfBrowser -Engine None | Should -BeNull
        $a = Get-PdfBrowserArgs -HtmlPath 'c:\x.html' -PdfPath 'c:\x.pdf' -UserDataDir 'c:\tmp\udd'
        $a | Should -Match '--headless'
        $a | Should -Match '--no-pdf-header-footer'
        $a | Should -Match '--print-to-pdf="c:\\x\.pdf"'
        $a | Should -Match '--user-data-dir="c:\\tmp\\udd"'
    }
}

Describe 'Export-TeamsChannelsToPdf (mocked, -PdfEngine None)' {
    BeforeAll {
        # Invoke-MgGraphRequest is not reimported by the script - a plain global function survives
        function global:Invoke-MgGraphRequest {
            param($Method, $Uri, $ErrorAction)
            if ($Uri -match 'groups\?\$filter') {
                if ($Uri -match "Ghost") { return @{ value = @() } }
                if ($Uri -match 'Dupe') { return @{ value = @(@{id='t1'}, @{id='t2'}) } }
                return @{ value = @(@{ id = 't1'; displayName = 'Contoso IT' }) }
            }
            if ($Uri -match 'allChannels') {
                return @{ value = @(
                    @{ id = 'c1'; displayName = 'Generelt'; membershipType = 'standard' },
                    @{ id = 'c2'; displayName = 'Secret';   membershipType = 'private' }
                ) }
            }
            if ($Uri -match 'channels/c2/messages') { throw [System.Net.WebException]::new('The remote server returned an error: (403) Forbidden') }
            if ($Uri -match 'messages/m2/replies') { return Get-Content "$fx\m2-replies-page2.json" -Raw | ConvertFrom-Json }
            if ($Uri -match 'messages\?\$top') {
                $page = Get-Content "$fx\channel-messages.json" -Raw | ConvertFrom-Json
                # fixture uses replies_nextLink (leak guard); restore the real Graph property name
                $nextProp = 'replies@odata' + '.nextLink'
                foreach ($m in $page.value) {
                    if ($m.replies_nextLink) { $m | Add-Member -NotePropertyName $nextProp -NotePropertyValue $m.replies_nextLink }
                }
                return $page
            }
            throw "unmocked uri: $Uri"
        }
        function global:Connect-MigrationGraph { param($TenantId, $AdminUpn, $Scopes) }
        Mock Connect-MigrationGraph { $null }
        Mock New-OutputFolder { return $TestDrive }
        @"
TeamName,TeamId
Contoso IT,
Ghost Team,
Dupe Team,
"@ | Set-Content "$TestDrive\teams.csv" -Encoding utf8
        & "$repo\07-SharePoint-Teams\Export-TeamsChannelsToPdf.ps1" -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' `
            -AdminUpn 'admin@contoso.com' -TeamListPath "$TestDrive\teams.csv" -Customer t -PdfEngine None -NoImages 6>$null
        $script:cov = @(Import-Csv "$TestDrive\TeamsExportCoverage.csv")
        ($script:cov | ConvertTo-Json -Depth 4) | Out-File "$env:TEMP\covdbg.json" -Encoding utf8
    }
    It 'statuses: Exported, Forbidden, NotFound, Ambiguous' {
        ($script:cov | Where-Object ChannelName -eq 'Generelt').Status | Should -Be 'Exported'
        ($script:cov | Where-Object ChannelName -eq 'Secret').Status | Should -Be 'Forbidden'
        ($script:cov | Where-Object TeamName -eq 'Ghost Team').Status | Should -Be 'NotFound'
        ($script:cov | Where-Object TeamName -eq 'Dupe Team').Status | Should -Be 'Ambiguous'
        ($script:cov | Where-Object TeamName -eq 'Dupe Team').Error | Should -Match 't1'
    }
    It 'followed the >200-reply nextLink' {
        ($script:cov | Where-Object ChannelName -eq 'Generelt').ThreadsOver200Replies | Should -Be '1'
        ($script:cov | Where-Object ChannelName -eq 'Generelt').TotalMessages | Should -Be '6'
    }
    It 'wrote html + json + csv + md, HtmlOnly pdf status' {
        Test-Path "$TestDrive\html\Contoso IT - Generelt.html" | Should -BeTrue
        Test-Path "$TestDrive\json\Contoso IT - Generelt.json" | Should -BeTrue
        Test-Path "$TestDrive\TeamsExportCoverage.md" | Should -BeTrue
        ($script:cov | Where-Object ChannelName -eq 'Generelt').PdfStatus | Should -Be 'HtmlOnly'
    }
}
