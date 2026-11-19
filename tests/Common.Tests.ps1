BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
}

Describe 'Export-CsvSafe' {
    It 'writes UTF-8 with BOM and round-trips æøå' {
        $path = Join-Path $TestDrive 'out\sub\users.csv'
        [pscustomobject]@{ Name = 'Søren Ærø Åse'; City = 'København' } | Export-CsvSafe -Path $path
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
        $rows = Import-Csv $path
        $rows[0].Name | Should -Be 'Søren Ærø Åse'
        $rows[0].City | Should -Be 'København'
        (Get-Content $path -TotalCount 1) | Should -Not -Match '^#TYPE'
    }
}

Describe 'Assert-TenantContext' {
    It 'throws on tenant mismatch' {
        { Assert-TenantContext -ExpectedTenantId 'aaa' -ActualTenantId 'bbb' } | Should -Throw '*Tenant mismatch*'
    }
    It 'throws on UPN mismatch when both are given' {
        { Assert-TenantContext -ExpectedTenantId 'aaa' -ActualTenantId 'aaa' -ExpectedUpn 'a@contoso.com' -ActualUpn 'b@contoso.com' } | Should -Throw '*Account mismatch*'
    }
    It 'passes on case-only differences' {
        { Assert-TenantContext -ExpectedTenantId 'AAA' -ActualTenantId 'aaa' -ExpectedUpn 'A@contoso.com' -ActualUpn 'a@contoso.com' } | Should -Not -Throw
    }
}

Describe 'New-OutputFolder' {
    It 'builds customers/<name>/output/<phase>/<timestamp> under -Root' {
        $path = New-OutputFolder -Customer 'contoso' -Phase '00-Assessment' -Root $TestDrive
        $path | Should -BeLike (Join-Path $TestDrive 'customers\contoso\output\00-Assessment\*')
        Test-Path $path | Should -BeTrue
        (Split-Path -Leaf $path) | Should -Match '^\d{8}-\d{6}$'
    }
}
