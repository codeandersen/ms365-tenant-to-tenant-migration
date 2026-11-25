BeforeAll {
    $script:RegPath   = Join-Path $PSScriptRoot '..\00-Assessment\Collectors.psd1'
    $script:CollFile  = Join-Path $PSScriptRoot '..\00-Assessment\Collect-TenantInventory.ps1'
    $script:MatrixDoc = Join-Path $PSScriptRoot '..\docs\Collector-Matrix.md'
    $script:RegData   = Import-PowerShellDataFile $script:RegPath
    $script:Reg       = @($script:RegData.Collectors)
    # Import-PowerShellDataFile caps a data file at 132 objects - phase-1 entries
    # live in a separate file
    $regP1Path = Join-Path (Split-Path $script:RegPath -Parent) 'Collectors.Phase1.psd1'
    if (Test-Path $regP1Path) { $script:Reg += @((Import-PowerShellDataFile $regP1Path).Collectors) }

    # Literal CSV names in Export-CsvSafe calls (dynamic names can't be read statically)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:CollFile, [ref]$null, [ref]$null)
    $script:Written = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
        Where-Object { $_.GetCommandName() -eq 'Export-CsvSafe' } |
        ForEach-Object {
            ($_.CommandElements | Where-Object {
                $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] } |
             Select-Object -Last 1).Value
        } | Where-Object { $_ -like '*.csv' } | Sort-Object -Unique)
    $script:RegOutputs = @($script:Reg | ForEach-Object { "$($_.Output)" } | Where-Object { $_ })
}

Describe 'Collectors.psd1 registry schema' {
    It 'loads and has at least 50 collectors' {
        $script:Reg.Count | Should -BeGreaterOrEqual 50
    }

    It 'has unique collector names' {
        $dups = @($script:Reg | Group-Object Name | Where-Object Count -gt 1)
        $dups | Should -BeNullOrEmpty
    }

    It 'every entry has the required keys and valid enum values' {
        $required = 'Name','ServiceGroup','Level','Workstream','Workload',
                    'ApiVersion','Coverage','DocsUrl','ValidationStatus'
        foreach ($c in $script:Reg) {
            foreach ($k in $required) {
                $c.Contains($k) | Should -BeTrue -Because "$($c.Name) must have key $k"
                if ($k -ne 'ApiVersion') {
                    "$($c[$k])" | Should -Not -BeNullOrEmpty -Because "$($c.Name).$k must not be empty"
                }
            }
            $c.Level | Should -BeIn 'Basic','Advanced','Deep' -Because "$($c.Name).Level"
            $c.ServiceGroup | Should -BeIn 'Graph','Exchange','SharePoint','Teams','PowerPlatform','Parent' -Because "$($c.Name).ServiceGroup"
            $c.Workstream | Should -BeIn 'Identity','Messaging','Collaboration','Endpoint','Security','Compliance','BusinessApps','Governance' -Because "$($c.Name).Workstream"
            $c.Coverage | Should -BeIn 'Full','Partial','UsageDetectionOnly','ManualDiscoveryRequired','NotSupported' -Because "$($c.Name).Coverage"
            $c.ValidationStatus | Should -BeIn 'NotValidatedLive','ValidatedLive' -Because "$($c.Name).ValidationStatus"
            if ($c.Coverage -eq 'ManualDiscoveryRequired') {
                $c.ApiVersion | Should -BeIn 'v1.0','beta','PowerShell','' -Because "$($c.Name).ApiVersion"
            } else {
                $c.ApiVersion | Should -BeIn 'v1.0','beta','PowerShell' -Because "$($c.Name).ApiVersion"
            }
            ($c.Contains('Endpoint') -or $c.Contains('Cmdlet') -or $c.Coverage -eq 'ManualDiscoveryRequired') |
                Should -BeTrue -Because "$($c.Name) must name an Endpoint or Cmdlet"
            if ($c.DocsUrl) { $c.DocsUrl | Should -Match '^https://learn\.microsoft\.com' -Because "$($c.Name).DocsUrl" }
        }
    }
}

Describe 'Registry / collector script output sync' {
    It 'every registry Output is written by the collector script' {
        # Usage*.csv are written with a dynamic -Name $r.Csv (report map in Invoke-Usage)
        $dynamic = 'UsageEmailActivity.csv','UsageTeamsActivity.csv','UsageMailboxUsage.csv','UsageActiveUsers.csv'
        $missing = @($script:RegOutputs | Where-Object { $script:Written -notcontains $_ -and $dynamic -notcontains $_ })
        $missing | Should -BeNullOrEmpty -Because "registry outputs must match an Export-CsvSafe call: $($missing -join ', ')"
    }

    It 'every CSV the script writes has a registry entry' {
        # Collectors.csv / Collectors.<Group>.csv are generated merge artifacts, not collectors
        $generated = 'Collectors.csv'
        $missing = @($script:Written | Where-Object { $script:RegOutputs -notcontains $_ -and $generated -notcontains $_ })
        $missing | Should -BeNullOrEmpty -Because "add a Collectors.psd1 entry for: $($missing -join ', ')"
    }
}

Describe 'docs/Collector-Matrix.md is in sync with the registry' {
    It 'regenerating the matrix produces the committed document' {
        $gen = Join-Path $PSScriptRoot '..\tools\New-CollectorMatrix.ps1'
        $out = Join-Path $TestDrive 'Collector-Matrix.md'
        & $gen -OutFile $out
        $a = (Get-Content $out -Raw) -replace "`r`n", "`n"
        $b = (Get-Content $script:MatrixDoc -Raw) -replace "`r`n", "`n"
        $a | Should -Be $b -Because 'run tools\New-CollectorMatrix.ps1 after changing Collectors.psd1'
    }
}

Describe 'Invoke-Collector status wrapper' {
    BeforeAll {
        # AST-load only the wrapper + helpers; the collector body never runs.
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:CollFile, [ref]$null, [ref]$null)
        $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
            Where-Object { @('Invoke-Collector','Get-CollectorRegistryEntry','Test-CollectorLevel','Test-GraphForbidden') -contains $_.Name }
        foreach ($d in $defs) { . ([ScriptBlock]::Create($d.Extent.Text)) }

        $script:CollectorRegistry    = @{}
        $script:CollectorRegistryAll = @($script:Reg)
        foreach ($c in $script:Reg) { $script:CollectorRegistry[$c.Name] = $c }
        $script:Summary = [pscustomobject]@{ metrics = @{}; skippedSections = @{}; failedSections = @{} }
        $script:Level = 'Advanced'
        $script:TenantGuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $script:ToolVersion = '1.0'
        $global:TenantName = 'Contoso'
        function Write-Log { param([string]$Message, [string]$Level = 'INFO') }
        function Export-CsvSafe { param([object[]]$Data, [string]$Name) }
        Mock Write-Log {}
    }

    BeforeEach {
        $script:CollectorRecords  = [System.Collections.Generic.List[object]]::new()
        $script:CollectorWarnings = [System.Collections.Generic.List[string]]::new()
        $script:CollectorRows     = 0
        $script:AppOnly           = $false
        $script:Summary.skippedSections = @{}
    }

    It 'records Success when the block writes rows' {
        Invoke-Collector -Name 'Users' -ScriptBlock { $script:CollectorRows += 3 }
        $script:CollectorRecords[0].Status | Should -Be 'Success'
        $script:CollectorRecords[0].ObjectCount | Should -Be 3
        $script:CollectorRecords[0].Completeness | Should -Be 'Complete'
    }

    It 'records NotInUse when the block writes no rows' {
        Invoke-Collector -Name 'Users' -ScriptBlock {}
        $script:CollectorRecords[0].Status | Should -Be 'NotInUse'
    }

    It 'records PartialSuccess when the block logs a WARN' {
        Invoke-Collector -Name 'Users' -ScriptBlock {
            $script:CollectorRows += 1
            $script:CollectorWarnings.Add('[WARN] something partial')
        }
        $script:CollectorRecords[0].Status | Should -Be 'PartialSuccess'
        $script:CollectorRecords[0].Completeness | Should -Be 'Partial'
    }

    It 'records AccessDenied on a 403 and rethrows' {
        $ex = [System.Exception]::new('Forbidden')
        $ex | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{ StatusCode = [System.Net.HttpStatusCode]::Forbidden })
        { Invoke-Collector -Name 'Users' -ScriptBlock { throw $ex } } | Should -Throw
        $script:CollectorRecords[0].Status | Should -Be 'AccessDenied'
    }

    It 'records AuthenticationFailed on auth-shaped errors' {
        { Invoke-Collector -Name 'Users' -ScriptBlock { throw 'Authentication needed - run Connect-MgGraph' } } | Should -Throw
        $script:CollectorRecords[0].Status | Should -Be 'AuthenticationFailed'
    }

    It 'records Skipped when the block adds a skippedSections entry' {
        Invoke-Collector -Name 'Users' -ScriptBlock { $script:Summary.skippedSections['X'] = 'no access' }
        $script:CollectorRecords[0].Status | Should -Be 'Skipped'
    }

    It 'records NotLicensed for a "no license" skip' {
        Invoke-Collector -Name 'Users' -ScriptBlock { $script:Summary.skippedSections['X'] = 'no license for this workload' }
        $script:CollectorRecords[0].Status | Should -Be 'NotLicensed'
    }

    It 'returns NotSupported for delegated-only collectors in app-only mode' {
        $delegatedOnly = @($script:Reg | Where-Object { $_.AppOnlySupported -eq $false } | Select-Object -First 1)[0]
        $delegatedOnly | Should -Not -BeNullOrEmpty
        $script:AppOnly = $true
        $script:ran = $false
        Invoke-Collector -Name $delegatedOnly.Name -ScriptBlock { $script:ran = $true }
        $script:ran | Should -BeFalse
        $script:CollectorRecords[0].Status | Should -Be 'NotSupported'
    }

    It 'skips collectors above the selected -Level' {
        $script:Level = 'Basic'
        $deep = @($script:Reg | Where-Object { $_.Level -eq 'Advanced' } | Select-Object -First 1)[0]
        Invoke-Collector -Name $deep.Name -ScriptBlock { $script:CollectorRows += 5 }
        $script:CollectorRecords[0].Status | Should -Be 'Skipped'
    }
}

Describe 'Collect-TenantInventory parameter sets' {
    It 'defaults to the Delegated set so a normal run never prompts for app-only parameters' {
        $cmd = Get-Command (Join-Path $PSScriptRoot '..\00-Assessment\Collect-TenantInventory.ps1')
        ($cmd.ParameterSets | Where-Object IsDefault).Name | Should -Be 'Delegated'
        ($cmd.ParameterSets.Name) | Should -Contain 'AppOnly'
    }
}
