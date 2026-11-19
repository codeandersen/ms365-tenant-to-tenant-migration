BeforeAll {
    $script:Report = Join-Path $PSScriptRoot '..\00-Assessment\New-MigrationReadinessReport.ps1'
    $script:Fixture = Join-Path $PSScriptRoot 'fixtures\contoso-readiness'
}

Describe 'New-MigrationReadinessReport' {
    BeforeEach {
        $script:Inv = Join-Path $TestDrive 'contoso-readiness'
        Remove-Item $script:Inv -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item $script:Fixture $script:Inv -Recurse
        & $script:Report -InventoryPath $script:Inv
        $script:Md = [System.IO.File]::ReadAllText((Join-Path $script:Inv 'Readiness.md'), [System.Text.Encoding]::UTF8)
    }

    It 'generates Readiness.md without errors' {
        Test-Path (Join-Path $script:Inv 'Readiness.md') | Should -BeTrue
    }

    It 'recommends the orchestrator for user mailboxes' {
        $script:Md | Should -Match 'Cross-tenant migration orchestrator'
    }

    It 'recommends cross-tenant mailbox migration for shared/room mailboxes' {
        $script:Md | Should -Match 'Shared, room and equipment mailboxes \(2\)'
        $script:Md | Should -Match 'Cross-tenant mailbox migration'
    }

    It 'recommends standalone OneDrive migration for the ownerless OneDrive' {
        $script:Md | Should -Match 'OneDrive sites with no migrating user mailbox \(1\)'
        $script:Md | Should -Match 'Cross-tenant OneDrive migration'
    }

    It 'computes licence math (250.5 GB -> 3 Shared Data Migration licences, 5 user licences)' {
        $script:Md | Should -Match 'Cross-Tenant User Data Migration\s*\|\s*5\s*\|'
        $script:Md | Should -Match 'Cross-Tenant Shared Data Migration\s*\|\s*3\s*\|'
    }

    It 'lists a mailbox hold as a blocker' {
        $script:Md | Should -Match 'Mailboxes on hold - 1'
        $script:Md | Should -Match 'søren@contoso\.com'
    }

    It 'lists a public folder mailbox as a blocker' {
        $script:Md | Should -Match 'Public folders - 1'
    }

    It 'lists Customer Key and the apostrophe UPN as blockers' {
        $script:Md | Should -Match 'Customer Key enabled - 1'
        $script:Md | Should -Match 'apostrophe'
    }

    It 'reports rebuild items that are present (Bookings, Project Online, private/shared channels)' {
        $script:Md | Should -Match 'Bookings mailboxes \| 1'
        $script:Md | Should -Match 'Project Online sites.*\| 1'
        $script:Md | Should -Match 'Private / shared channels \| 2'
    }

    It 'writes UTF-8 with BOM and keeps æøå readable' {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:Inv 'Readiness.md'))
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
        $script:Md | Should -Match 'Søren|søren'
    }

    It 'tolerates missing CSVs and marks the rule not inventoried' {
        Remove-Item (Join-Path $script:Inv 'attachments\CustomerKey.csv')
        Remove-Item (Join-Path $script:Inv 'attachments\Mailboxes.csv')
        { & $script:Report -InventoryPath $script:Inv -OutFile (Join-Path $script:Inv 'R2.md') } | Should -Not -Throw
        $md2 = [System.IO.File]::ReadAllText((Join-Path $script:Inv 'R2.md'), [System.Text.Encoding]::UTF8)
        $md2 | Should -Match 'Not inventoried'
        $md2 | Should -Match 'Mailbox holds'
    }
}
