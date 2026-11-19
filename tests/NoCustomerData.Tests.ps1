BeforeAll {
    $script:Guard = Join-Path $PSScriptRoot 'Test-NoCustomerData.ps1'

    function Invoke-Guard([string[]]$Files, [string]$Denylist) {
        & $script:Guard -RepoRoot $TestDrive -DenylistPath $Denylist -Files $Files -NoExit
    }

    $script:DenylistPath = Join-Path $TestDrive 'denylist.txt'
    Set-Content -Path $script:DenylistPath -Value "Wombatcorp`n# a comment line`n" -Encoding utf8

    function New-TestFile($name, $content) {
        $p = Join-Path $TestDrive $name
        Set-Content -Path $p -Value $content -Encoding utf8
        return $p
    }

    # Planted strings are assembled at run time so this test file itself stays
    # clean when the leak guard scans the repo.
    $script:BadDomain = 'other' + 'corp.dk'
    $script:BadEmail  = 'x@' + $script:BadDomain
    $script:BadOnms   = 'foo' + '.onmicrosoft.com'
    $script:BadGuid   = '11111111-2222-3333-4444-555555555' + '555'
}

Describe 'Test-NoCustomerData' {
    It 'flags a planted denylist term' {
        $f = New-TestFile 'bad.txt' 'The customer Wombatcorp is migrating.'
        $r = @(Invoke-Guard -Files $f -Denylist $script:DenylistPath)
        @($r | Where-Object Rule -eq 'Denylist').Count | Should -Be 1
    }

    It 'reports clean contoso/fabrikam text' {
        $f = New-TestFile 'ok.txt' 'admin@contoso.com and user@fabrikam.onmicrosoft.com migrate.'
        $r = @(Invoke-Guard -Files $f -Denylist $script:DenylistPath)
        $r.Count | Should -Be 0
    }

    It 'flags an unknown GUID but not an allowlisted one' {
        $bad = New-TestFile 'guid-bad.txt' "tenant id $script:BadGuid"
        $r = @(Invoke-Guard -Files $bad -Denylist $script:DenylistPath)
        @($r | Where-Object Rule -eq 'GuidNotAllowlisted').Count | Should -Be 1

        $good = New-TestFile 'guid-good.txt' 'Microsoft tenant f8cdef31-a31e-4b4a-93e4-5f571e91255a'
        $r2 = @(Invoke-Guard -Files $good -Denylist $script:DenylistPath)
        $r2.Count | Should -Be 0
    }

    It 'flags a non-allowlisted e-mail domain but not contoso.com' {
        $bad = New-TestFile 'mail-bad.txt' "contact $script:BadEmail for details"
        $r = @(Invoke-Guard -Files $bad -Denylist $script:DenylistPath)
        @($r | Where-Object Rule -eq 'EmailAddress').Count | Should -Be 1

        $good = New-TestFile 'mail-ok.txt' 'contact x@contoso.com for details'
        $r2 = @(Invoke-Guard -Files $good -Denylist $script:DenylistPath)
        $r2.Count | Should -Be 0
    }

    It 'flags a non-allowlisted onmicrosoft.com prefix' {
        $bad = New-TestFile 'onms-bad.txt' "sign in at $script:BadOnms"
        $r = @(Invoke-Guard -Files $bad -Denylist $script:DenylistPath)
        @($r | Where-Object Rule -eq 'OnmicrosoftDomain').Count | Should -BeGreaterThan 0

        $good = New-TestFile 'onms-ok.txt' 'sign in at contoso.onmicrosoft.com'
        $r2 = @(Invoke-Guard -Files $good -Denylist $script:DenylistPath)
        $r2.Count | Should -Be 0
    }
}
