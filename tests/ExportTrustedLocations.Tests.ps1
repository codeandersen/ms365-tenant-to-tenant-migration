BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..\00-Assessment\Export-TrustedLocations.ps1'

    # Load only the pure helpers via AST - the script body must not execute
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Script, [ref]$null, [ref]$null)
    foreach ($name in 'Test-CidrRange', 'Test-IpV4Overlap', 'ConvertTo-NamedLocationBody') {
        $def = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)[0]
        . ([ScriptBlock]::Create($def.Extent.Text))
    }
}

Describe 'Test-CidrRange' {
    It 'accepts public IPv4 CIDRs' {
        (Test-CidrRange '192.0.2.0/24').Valid | Should -BeTrue
        (Test-CidrRange '192.0.2.0/24').PrivateOrReserved | Should -BeFalse
    }
    It 'flags private/reserved IPv4 ranges' {
        (Test-CidrRange '10.0.0.0/8').PrivateOrReserved | Should -BeTrue
        (Test-CidrRange '172.16.0.0/12').PrivateOrReserved | Should -BeTrue
        (Test-CidrRange '192.168.1.0/24').PrivateOrReserved | Should -BeTrue
        (Test-CidrRange '100.64.0.0/10').PrivateOrReserved | Should -BeTrue
        (Test-CidrRange '169.254.0.0/16').PrivateOrReserved | Should -BeTrue
        (Test-CidrRange '127.0.0.0/8').PrivateOrReserved | Should -BeTrue
    }
    It 'rejects malformed CIDRs' {
        (Test-CidrRange '192.0.2.0').Valid | Should -BeFalse
        (Test-CidrRange '192.0.2.0/33').Valid | Should -BeFalse
        (Test-CidrRange 'notanip/24').Valid | Should -BeFalse
        (Test-CidrRange '999.0.0.0/24').Valid | Should -BeFalse
    }
    It 'accepts IPv6 and flags unique-local/link-local' {
        (Test-CidrRange '2001:db8::/32').Valid | Should -BeTrue
        (Test-CidrRange 'fd00::/8').PrivateOrReserved | Should -BeTrue
        (Test-CidrRange 'fe80::/10').PrivateOrReserved | Should -BeTrue
    }
}

Describe 'Test-IpV4Overlap' {
    It 'detects overlapping and disjoint ranges' {
        Test-IpV4Overlap '192.0.2.0/24' '192.0.2.128/25' | Should -BeTrue
        Test-IpV4Overlap '192.0.2.0/24' '198.51.100.0/24' | Should -BeFalse
        Test-IpV4Overlap '192.0.2.0/25' '192.0.2.128/25' | Should -BeFalse
    }
}

Describe 'ConvertTo-NamedLocationBody' {
    It 'builds an ipNamedLocation body with v4/v6 range types' {
        $l = [pscustomobject]@{ Name = 'HQ'; Type = 'ip'; IsTrusted = $true; CidrRanges = '192.0.2.0/24; 2001:db8::/32'; Countries = ''; IncludeUnknown = $false }
        $b = ConvertTo-NamedLocationBody $l
        $b.'@odata.type' | Should -Be '#microsoft.graph.ipNamedLocation'
        $b.isTrusted | Should -BeTrue
        $b.ipRanges[0].'@odata.type' | Should -Be '#microsoft.graph.iPv4CidrRange'
        $b.ipRanges[1].'@odata.type' | Should -Be '#microsoft.graph.iPv6CidrRange'
        $b.ipRanges[0].cidrAddress | Should -Be '192.0.2.0/24'
    }
    It 'builds a countryNamedLocation body' {
        $l = [pscustomobject]@{ Name = 'Nordics'; Type = 'country'; IsTrusted = $false; CidrRanges = ''; Countries = 'DK; SE'; IncludeUnknown = $false }
        $b = ConvertTo-NamedLocationBody $l
        $b.'@odata.type' | Should -Be '#microsoft.graph.countryNamedLocation'
        @($b.countriesAndRegions) | Should -Be @('DK', 'SE')
    }
}

Describe 'Export-TrustedLocations.ps1 end-to-end (offline files)' {
    BeforeEach {
        $script:Inv = Join-Path $TestDrive 'inv'
        New-Item -ItemType Directory (Join-Path $script:Inv 'attachments') -Force | Out-Null
        @'
Id,DisplayName,Type,IsTrusted,IpRanges,CountriesAndRegions,IncludeUnknownCountriesAndRegions
n1,HQ,ip,True,192.0.2.0/24; 10.0.0.0/8,,False
n1,HQ,ip,True,198.51.100.0/24,,False
n2,Nordics,country,False,,DK;SE,False
'@ | Set-Content (Join-Path $script:Inv 'attachments\NamedLocations.csv')
        @'
Site,PublicIpCidr,IsTrusted,Notes
Headquarters,203.0.113.0/25,True,
'@ | Set-Content (Join-Path $TestDrive 'office.csv')
    }

    It 'writes csv+json+readme, merges duplicates, warns on private ranges' {
        & $script:Script -InventoryPath $script:Inv -OfficeIpPath (Join-Path $TestDrive 'office.csv')
        $csv = Import-Csv (Join-Path $script:Inv 'attachments\TrustedLocations-for-target.csv')
        $csv.Count | Should -Be 3                          # n1 merged, n2, office
        ($csv | Where-Object Name -eq 'HQ').Warnings | Should -Match '10\.0\.0\.0/8.*not usable'
        ($csv | Where-Object Name -eq 'HQ').CidrRanges | Should -Match '192\.0\.2\.0/24'
        ($csv | Where-Object Name -eq 'HQ').CidrRanges | Should -Match '198\.51\.100\.0/24'
        ($csv | Where-Object Source -eq 'OfficeList').Name | Should -Be 'Office - Headquarters'
        $json = Get-Content (Join-Path $script:Inv 'attachments\TrustedLocations-for-target.json') -Raw | ConvertFrom-Json
        $json[0].'@odata.type' | Should -Match 'NamedLocation'
        Test-Path (Join-Path $script:Inv 'attachments\TrustedLocations-README.md') | Should -BeTrue
    }

    It 'throws when nothing is found' {
        $empty = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory $empty -Force | Out-Null
        { & $script:Script -InventoryPath $empty } | Should -Throw
    }
}
