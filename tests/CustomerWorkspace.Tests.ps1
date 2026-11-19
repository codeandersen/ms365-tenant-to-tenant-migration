BeforeAll {
    $script:Repo = Split-Path $PSScriptRoot -Parent
    $script:Collector = Join-Path $script:Repo '00-Assessment\Collect-TenantInventory.ps1'
    $script:Workspace = Join-Path $script:Repo 'tools\New-CustomerWorkspace.ps1'

    # Load Resolve-InventoryOutputRoot from the collector via AST - the collector must not execute
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Collector, [ref]$null, [ref]$null)
    $def = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Resolve-InventoryOutputRoot' }, $true)[0]
    . ([ScriptBlock]::Create($def.Extent.Text))
}

Describe 'Resolve-InventoryOutputRoot' {
    It 'throws without -Customer and -OutputRoot' {
        { Resolve-InventoryOutputRoot -OutputRoot '' -Customer '' -RepoRoot $TestDrive } | Should -Throw '*-Customer*'
    }
    It 'explicit -OutputRoot wins' {
        Resolve-InventoryOutputRoot -OutputRoot 'D:\out' -Customer 'contoso' -RepoRoot $TestDrive | Should -Be 'D:\out'
    }
    It '-Customer maps to customers/<name>/inventory' {
        Resolve-InventoryOutputRoot -OutputRoot '' -Customer 'contoso' -RepoRoot $TestDrive |
            Should -Be (Join-Path $TestDrive 'customers\contoso\inventory')
    }
}

Describe 'Test-CustomerDataPath / Assert-CustomerDataPath' {
    BeforeAll {
        Import-Module (Join-Path $script:Repo 'tools\Common.psm1') -Force -DisableNameChecking
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Collector, [ref]$null, [ref]$null)
        $def = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-InventoryOutputPath' }, $true)[0]
        . ([ScriptBlock]::Create($def.Extent.Text))
    }
    It 'outside the repo is allowed' {
        Test-CustomerDataPath -Path (Join-Path $TestDrive 'x.csv') -RepoRoot $script:Repo | Should -BeTrue
    }
    It 'customers/<name>/<file> is allowed' {
        Test-CustomerDataPath -Path (Join-Path $script:Repo 'customers\contoso\x.csv') -RepoRoot $script:Repo | Should -BeTrue
    }
    It 'repo folders outside customers/ are refused' {
        Test-CustomerDataPath -Path (Join-Path $script:Repo '00-Assessment\x.csv') -RepoRoot $script:Repo | Should -BeFalse
        Test-CustomerDataPath -Path $script:Repo -RepoRoot $script:Repo | Should -BeFalse
        Test-CustomerDataPath -Path (Join-Path $script:Repo 'customers\README.md') -RepoRoot $script:Repo | Should -BeFalse
    }
    It 'path traversal out of customers/ is refused' {
        Test-CustomerDataPath -Path (Join-Path $script:Repo 'customers\..\00-Assessment\x.csv') -RepoRoot $script:Repo | Should -BeFalse
    }
    It 'Assert-CustomerDataPath throws inside the repo' {
        { Assert-CustomerDataPath -Path (Join-Path $script:Repo '00-Assessment\x.csv') -RepoRoot $script:Repo } |
            Should -Throw '*customers*'
    }
    It 'collector standalone copy behaves the same' {
        Test-InventoryOutputPath -Path (Join-Path $TestDrive 'x') -RepoRoot $script:Repo | Should -BeTrue
        Test-InventoryOutputPath -Path (Join-Path $script:Repo 'customers\contoso\x') -RepoRoot $script:Repo | Should -BeTrue
        Test-InventoryOutputPath -Path (Join-Path $script:Repo '00-Assessment\Inventory_x') -RepoRoot $script:Repo | Should -BeFalse
        Test-InventoryOutputPath -Path (Join-Path $script:Repo 'customers\..\00-Assessment\x') -RepoRoot $script:Repo | Should -BeFalse
    }
}

Describe 'repo-internal output paths are refused before anything is written' {
    BeforeAll {
        Import-Module (Join-Path $script:Repo 'tools\Common.psm1') -Force -DisableNameChecking
        $script:BadDir = Join-Path $script:Repo '00-Assessment\guard-test'
        New-Item -ItemType Directory $script:BadDir -Force | Out-Null
    }
    AfterAll { Remove-Item $script:BadDir -Recurse -Force -ErrorAction SilentlyContinue }

    It 'New-InventoryReport refuses a repo-internal inventory folder' {
        { & (Join-Path $script:Repo '00-Assessment\New-InventoryReport.ps1') -InventoryPath $script:BadDir } |
            Should -Throw '*customers*'
        Test-Path (Join-Path $script:BadDir 'Review.md') | Should -BeFalse
    }
    It 'New-MigrationReadinessReport refuses a repo-internal output' {
        { & (Join-Path $script:Repo '00-Assessment\New-MigrationReadinessReport.ps1') -InventoryPath $script:BadDir } |
            Should -Throw '*customers*'
        Test-Path (Join-Path $script:BadDir 'Readiness.md') | Should -BeFalse
    }
    It 'Export-TrustedLocations refuses a repo-internal -OutFolder' {
        $inv = Join-Path $TestDrive 'inv'   # valid inventory outside the repo
        New-Item -ItemType Directory $inv -Force | Out-Null
        { & (Join-Path $script:Repo '00-Assessment\Export-TrustedLocations.ps1') -InventoryPath $inv -OutFolder $script:BadDir } |
            Should -Throw '*customers*'
    }
    It 'Get-MigrationReport refuses a repo-internal -OutFile' {
        { & (Join-Path $script:Repo 'tools\Get-MigrationReport.ps1') -Folder $TestDrive -OutFile (Join-Path $script:BadDir 's.csv') } |
            Should -Throw '*customers*'
    }
    It 'Copy-MailConfig asserts -OutputFolder' {
        # static: connect happens first, so verify the assert precedes the writes in source
        $src = [IO.File]::ReadAllText((Join-Path $script:Repo '08-MailConfig\Copy-MailConfig.ps1'))
        $src.IndexOf('Assert-CustomerDataPath -Path $OutputFolder') | Should -BeGreaterThan -1
        $src.IndexOf('Assert-CustomerDataPath -Path $OutputFolder') | Should -BeLessThan $src.IndexOf("Export-CsvSafe -Path (Join-Path `$OutputFolder 'Forwarding.csv')")
    }
    It 'New-OutputFolder output passes its own assert' {
        $p = New-OutputFolder -Customer contoso -Phase '00-Assessment' -Root $TestDrive
        Test-CustomerDataPath -Path $p -RepoRoot $TestDrive | Should -BeTrue
    }
    It 'collector throws on a repo-internal -OutputRoot without writing' {
        # static check: the guard sits before any New-Item/write
        $src = [IO.File]::ReadAllText($script:Collector)
        $guard = $src.IndexOf('Test-InventoryOutputPath -Path $outDir')
        $guard | Should -BeGreaterThan -1
        $guard | Should -BeLessThan $src.IndexOf('New-Item -ItemType Directory -Path $attachDir')
    }
}

Describe 'gitignore defence-in-depth patterns' {
    It 'report artifacts are ignored, fixtures and docs are not' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $cases = @{
            '00-Assessment/Review.md'                        = $true
            'customers/contoso/output/x/Readiness.md'        = $true
            '00-Assessment/Readiness.md'                     = $true
            'x/TrustedLocations-for-target.csv'              = $true
            'x/TrustedLocations-README.md'                   = $true
            'x/TeamsExportCoverage.md'                       = $true
            'x/report.pdf'                                   = $true
            'x/summary.json'                                 = $true
            'tests/fixtures/contoso-inventory/summary.json'  = $false
            'docs/Runbook.md'                                = $false
            '01-Design/templates/Decision-Log.md'            = $false
        }
        foreach ($p in $cases.Keys) {
            git -C $script:Repo check-ignore -q $p
            ([bool]($LASTEXITCODE -eq 0)) | Should -Be $cases[$p] -Because $p
        }
    }
}

Describe 'New-CustomerWorkspace.ps1' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive 'repo'
        New-Item -ItemType Directory (Join-Path $script:Root '01-Design\templates') -Force | Out-Null
        New-Item -ItemType Directory (Join-Path $script:Root 'customers') -Force | Out-Null
        'a,b' | Set-Content (Join-Path $script:Root '01-Design\templates\t1.csv')
        'x' | Set-Content (Join-Path $script:Root '01-Design\templates\t2.md')
    }

    It 'creates input/inventory/output and copies templates' {
        & $script:Workspace -Customer contoso -RepoRoot $script:Root | Out-Null
        Test-Path (Join-Path $script:Root 'customers\contoso\input\t1.csv') | Should -BeTrue
        Test-Path (Join-Path $script:Root 'customers\contoso\inventory') | Should -BeTrue
        Test-Path (Join-Path $script:Root 'customers\contoso\output') | Should -BeTrue
        Test-Path (Join-Path $script:Root 'customers\.denylist') | Should -BeTrue
    }

    It 'does not overwrite existing input unless -Force' {
        & $script:Workspace -Customer contoso -RepoRoot $script:Root | Out-Null
        'realdata' | Set-Content (Join-Path $script:Root 'customers\contoso\input\t1.csv')
        & $script:Workspace -Customer contoso -RepoRoot $script:Root | Out-Null
        Get-Content (Join-Path $script:Root 'customers\contoso\input\t1.csv') | Should -Be 'realdata'
        & $script:Workspace -Customer contoso -RepoRoot $script:Root -Force | Out-Null
        Get-Content (Join-Path $script:Root 'customers\contoso\input\t1.csv') | Should -Be 'a,b'
    }
}

Describe 'git ignore rules for the workspace' {
    BeforeAll {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Set-ItResult -Skipped -Because 'git not available' }
    }
    It 'customers paths are ignored, customers/README.md is not' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $checks = @{
            'customers/contoso/inventory/x.csv'           = $true
            'customers/contoso/output/00-Assessment/x.md' = $true
            'customers/contoso/input/migration-users.csv' = $true
            'customers/.denylist'                         = $true
            'customers/README.md'                         = $false
        }
        foreach ($p in $checks.Keys) {
            git -C $script:Repo check-ignore -q $p
            ([bool]($LASTEXITCODE -eq 0)) | Should -Be $checks[$p] -Because "$p"
        }
    }
}
