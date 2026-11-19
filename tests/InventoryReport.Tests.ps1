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
