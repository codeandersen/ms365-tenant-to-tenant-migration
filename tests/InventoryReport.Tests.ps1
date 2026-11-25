BeforeAll {
    $script:Report = Join-Path $PSScriptRoot '..\00-Assessment\New-InventoryReport.ps1'
    $script:Fixture = Join-Path $PSScriptRoot 'fixtures\contoso-inventory'
    # Work on a copy so the run can write Review.md without dirtying the repo.
    $script:Inv = Join-Path $TestDrive 'contoso-inventory'
    Copy-Item $script:Fixture $script:Inv -Recurse
}

Describe 'New-InventoryReport' {
    It 'generates Review.md from a synthetic inventory without errors' {
        { & $script:Report -InventoryPath $script:Inv } | Should -Not -Throw
        Test-Path (Join-Path $script:Inv 'Review.md') | Should -BeTrue
    }

    It 'writes UTF-8 with BOM and keeps æøå readable' {
        & $script:Report -InventoryPath $script:Inv
        $path = Join-Path $script:Inv 'Review.md'
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
        $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        $text | Should -Match 'Søren'
    }
}

Describe 'New-InventoryReport - additional sections' {
    BeforeAll {
        $script:Inv = Join-Path $TestDrive 'contoso-inventory-full'
        Copy-Item $script:Fixture $script:Inv -Recurse
        $att = Join-Path $script:Inv 'attachments'
        $rd = Join-Path $PSScriptRoot 'fixtures\contoso-readiness\attachments'
        foreach ($f in 'OneDrive.csv','PowerApps.csv','PowerAutomateFlows.csv','PowerPlatformEnvironments.csv','PowerPlatformConnectors.csv','PowerBIWorkspaces.csv','AppPermissions.csv','AppDelegatedUserPermissions.csv','TeamsCustomApps.csv','TeamsInstalledApps.csv','OutlookAddins.csv','SharePointAppCatalog.csv','Collectors.csv','InactiveMailboxes.csv','ThirdPartyEvidence.csv','AppCredentials.csv') {
            $src = Join-Path $rd $f
            if (Test-Path $src) { Copy-Item $src $att }
        }
        'Name,Enabled,Mode,ExchangeLocation,SharePointLocation,OneDriveLocation,AdaptiveScopeLocation' | Out-File (Join-Path $att 'RetentionPolicies.csv') -Encoding utf8
        'KeepAll,True,Enforce,,,All,' | Out-File (Join-Path $att 'RetentionPolicies.csv') -Append -Encoding utf8
        & $script:Report -InventoryPath $script:Inv -CustomerName Contoso
        $script:Md = [System.IO.File]::ReadAllText((Join-Path $script:Inv 'Review.md'), [System.Text.Encoding]::UTF8)
    }

    It 'has a OneDrive holds check that flags held OneDrives' {
        $script:Md | Should -Match '## 21\. OneDrive holds check'
        $script:Md | Should -Match 'OneDrive\(s\) are under a hold policy'
    }

    It 'has a Power Platform section with owner status and connector usage' {
        $script:Md | Should -Match '## 22\. Power Platform check'
        $script:Md | Should -Match 'Orphaned owners'
        $script:Md | Should -Match 'Connector usage'
        $script:Md | Should -Match 'OwnerStatus'
    }

    It 'has a Collector status section listing non-success collectors first' {
        $script:Md | Should -Match '## 27\. Collector status check'
        $script:Md | Should -Match 'Per status:'
        $script:Md | Should -Match 'TeamsInstalledApps \| PartialSuccess'
    }

    It 'has the other new sections (Power BI, app permissions, workload apps, phase-1 detail)' {
        $script:Md | Should -Match '## 23\. Power BI workspaces check'
        $script:Md | Should -Match '## 24\. App permissions check'
        $script:Md | Should -Match '## 25\. Workload apps check'
        $script:Md | Should -Match '## 26\. Additional inventory detail check'
    }
}
