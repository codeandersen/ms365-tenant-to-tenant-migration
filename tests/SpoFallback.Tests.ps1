BeforeAll {
    $script:Collector = Join-Path $PSScriptRoot '..\00-Assessment\Collect-TenantInventory.ps1'

    # Load only the function definitions we need - the main body never runs.
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:Collector, [ref]$null, [ref]$null)
    $names = @('Test-GraphSession','Invoke-OneDrive','Invoke-SharePoint',
               'Invoke-OneDriveFallback','Invoke-SharePointFallback',
               'ConvertFrom-OneDriveUsageReport','ConvertFrom-SharePointUsageReport','Get-SiteType')
    $defs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        Where-Object { $names -contains $_.Name }
    foreach ($d in $defs) { . ([ScriptBlock]::Create($d.Extent.Text)) }

    # State the functions read from the collector script scope
    $script:Summary = [pscustomobject]@{ metrics = @{}; skippedSections = @{}; failedSections = @{} }
    $script:Exported = @{}

    # Stubs must exist before Pester can mock them
    function Write-Log { param([string]$Message, [string]$Level = 'INFO') }
    function Export-CsvSafe { param([object[]]$Data, [string]$Name) }
    function Get-GraphReport { param([string]$Endpoint, [string]$Period = 'D30', [string]$CsvName) }
    function Get-GraphAll { param([string]$Uri, [hashtable]$Headers, [int]$MaxRetries = 5) }
    function Get-MgContext { }
    function Get-SPOSite { }
    function Get-SPOTenant { }
    function Get-SPOExternalUser { }

    Mock Write-Log {}
    Mock Export-CsvSafe { param($Data, $Name) $script:Exported[$Name] = @($Data) }

    function New-FakeUsageRow {
        [pscustomobject]@{
            'Site URL'            = 'https://contoso.sharepoint.com/sites/team1'
            'Owner Principal Name'= 'user@contoso.com'
            'Owner Display Name'  = 'Team One'
            'Root Web Template'   = 'Team'
            'Storage Used (Byte)' = '1073741824'
            'Is Deleted'          = 'False'
            'Last Activity Date'  = '2026-01-01'
            'File Count'          = '10'
            'Active File Count'   = '5'
        }
    }
    function New-FakeOdUsageRow {
        [pscustomobject]@{
            'Site URL'            = 'https://contoso-my.sharepoint.com/personal/user1'
            'Owner Principal Name'= 'user1@contoso.com'
            'Site Display Name'   = 'User One'
            'Storage Used (Byte)' = '2147483648'
            'Last Activity Date'  = '2026-01-01'
            'File Count'          = '20'
            'Active File Count'   = '15'
        }
    }
}

Describe 'Test-GraphSession' {
    It 'returns false when no Graph context exists' {
        Mock Get-MgContext { return $null }
        Test-GraphSession | Should -BeFalse
    }
    It 'returns true when a Graph context exists' {
        Mock Get-MgContext { return [pscustomobject]@{ Account = 'a@contoso.com'; TenantId = 'x' } }
        Test-GraphSession | Should -BeTrue
    }
    It 'returns false when Get-MgContext is unavailable in the process' {
        Mock Get-MgContext { throw 'The term is not recognized' }
        Test-GraphSession | Should -BeFalse
    }
}

Describe 'Invoke-OneDrive / Invoke-SharePoint without a Graph session' {
    BeforeEach {
        $script:SpoAvailable = $false
        Mock Get-MgContext { return $null }
        Mock Get-GraphReport { throw 'Should not be called' }
        Mock Get-GraphAll { throw 'Should not be called' }
    }
    It 'OneDrive refuses the Graph fallback in a process with no Graph session' {
        { Invoke-OneDrive } | Should -Throw -ExpectedMessage '*no Graph session*'
    }
    It 'SharePoint refuses the Graph fallback in a process with no Graph session' {
        { Invoke-SharePoint } | Should -Throw -ExpectedMessage '*no Graph session*'
    }
}

Describe 'Invoke-OneDrive Graph fallback' {
    BeforeEach {
        $script:SpoAvailable = $false
        $script:Exported = @{}
        $script:Summary.metrics = @{}
        Mock Get-MgContext { return [pscustomobject]@{ Account = 'a@contoso.com' } }
        Mock Get-GraphReport { return @(New-FakeOdUsageRow) }
    }
    It 'writes OneDrive.csv and marks the data source as Graph-fallback' {
        Invoke-OneDrive
        $script:Exported.ContainsKey('OneDrive.csv') | Should -BeTrue
        $script:Exported['OneDrive.csv'].Count | Should -Be 1
        $script:Summary.metrics.spoDataSource | Should -Be 'Graph-fallback'
        $script:Summary.metrics.oneDriveCount | Should -Be 1
    }
    It 'fails when the usage report has no data' {
        Mock Get-GraphReport { return @() }
        { Invoke-OneDrive } | Should -Throw -ExpectedMessage '*no data*'
    }
}

Describe 'Invoke-SharePointFallback diagnostics' {
    BeforeEach {
        $script:Exported = @{}
        $script:Summary.metrics = @{}
        $script:Summary.skippedSections = @{}
    }
    It 'reports both endpoint reasons when nothing returns data' {
        Mock Get-GraphReport { return @() }
        Mock Get-GraphAll { throw 'Forbidden' }
        { Invoke-SharePointFallback } |
            Should -Throw -ExpectedMessage '*getAllSites*getSharePointSiteUsageDetail returned no rows*'
    }
    It 'reports the usage report error when it throws' {
        Mock Get-GraphReport { throw 'Reports permission denied' }
        Mock Get-GraphAll { throw 'Forbidden' }
        { Invoke-SharePointFallback } |
            Should -Throw -ExpectedMessage '*Reports permission denied*'
    }
    It 'writes SharePointSites.csv from the usage report alone' {
        Mock Get-GraphReport { return @(New-FakeUsageRow) }
        Mock Get-GraphAll { throw 'Forbidden' }
        Invoke-SharePointFallback
        $script:Exported.ContainsKey('SharePointSites.csv') | Should -BeTrue
        $script:Exported['SharePointSites.csv'].Count | Should -Be 1
        $script:Summary.metrics.sharePointSiteCount | Should -Be 1
        $script:Summary.metrics.spoDataSource | Should -Be 'Graph-fallback'
    }
}

Describe 'SharePoint child connect-failure handling (script text)' {
    BeforeAll { $script:raw = Get-Content $script:Collector -Raw }
    It 'clears the section list when Connect-SPOService fails so no Graph-less fallback runs' {
        ($script:raw -match '(?s)Connect-SPOService failed.{0,900}\$toRun = @\(\)') | Should -BeTrue
    }
    It 'clears the section list when the SPO admin URL cannot be derived' {
        ($script:raw -match '(?s)SPO admin URL could not be derived.{0,400}\$toRun = @\(\)') | Should -BeTrue
    }
    It 'keeps the Connect-SPOService error on a dedicated SharePointAdmin key' {
        $script:raw | Should -Match "failedSections\['SharePointAdmin'\]"
    }
}
