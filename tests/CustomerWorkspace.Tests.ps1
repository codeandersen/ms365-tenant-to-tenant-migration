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
