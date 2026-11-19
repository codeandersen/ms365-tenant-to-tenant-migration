BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..\03-Identities\New-TargetMailUsers.ps1'
    $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Script, [ref]$null, [ref]$null)

    # Stub the Exchange cmdlets the script calls so Pester mocks can attach and calls resolve.
    function global:New-MailUser { param($Name, $DisplayName, $FirstName, $LastName, $MicrosoftOnlineServicesID, $PrimarySmtpAddress, $ExternalEmailAddress, $Password) }
    function global:Get-Recipient { param($Identity, $ErrorAction) }
    function global:Get-AcceptedDomain { }

    $script:GoodDomain = 'fabrikam.onmicrosoft.com'
    $script:UsersCsv = Join-Path $TestDrive 'users.csv'
    @(
        [pscustomobject]@{
            SourceUpn = 'good@contoso.com'; SourcePrimarySmtp = 'good@contoso.com'; DisplayName = 'Good User'
            FirstName = 'Good'; LastName = 'User'; TargetUpn = "good@$script:GoodDomain"; TargetPrimarySmtp = "good@$script:GoodDomain"
            UsageLocation = 'DK'; TargetLicenseSku = 'SPE_E5'; Batch = 'wave1'
            CompleteAfterDateTimeUtc = '2026-09-05T22:00:00Z'; Workloads = 'Exchange'
        }
        [pscustomobject]@{
            SourceUpn = 'bad@contoso.com'; SourcePrimarySmtp = 'bad@contoso.com'; DisplayName = 'Bad Domain'
            FirstName = 'Bad'; LastName = 'Domain'; TargetUpn = ('bad@' + 'notaccepted.invalid'); TargetPrimarySmtp = ('bad@' + 'notaccepted.invalid')
            UsageLocation = 'DK'; TargetLicenseSku = 'SPE_E5'; Batch = 'wave1'
            CompleteAfterDateTimeUtc = '2026-09-05T22:00:00Z'; Workloads = 'Exchange'
        }
    ) | Export-Csv -Path $script:UsersCsv -NoTypeInformation
}

Describe 'New-TargetMailUsers.ps1 static shape' {
    It 'never calls Set-MailUser or stamps identity attributes' {
        $cmds = $script:Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
        $names = @($cmds | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
        $names | Should -Not -Contain 'Set-MailUser'
        $names | Should -Not -Contain 'Enable-MailUser'
    }
    It 'New-MailUser binds only the documented parameter set' {
        $newCalls = $script:Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'New-MailUser' }, $true)
        $newCalls.Count | Should -BeGreaterThan 0
        $allowed = 'Name', 'DisplayName', 'FirstName', 'LastName', 'MicrosoftOnlineServicesID', 'PrimarySmtpAddress', 'ExternalEmailAddress', 'Password', 'ErrorAction', 'WhatIf', 'Confirm', 'OutVariable', 'OutBuffer', 'Verbose', 'Debug', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'ProgressAction', 'PipelineVariable'
        foreach ($call in $newCalls) {
            $params = @($call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object { $_.ParameterName })
            $params | Should -Not -Contain 'ExchangeGuid'
            $params | Should -Not -Contain 'ArchiveGuid'
            $params | Should -Not -Contain 'EmailAddresses'
            foreach ($p in $params) { $allowed | Should -Contain $p }
        }
    }
    It 'never passes an x500 address to any command' {
        # x500 may appear in help text/comments; it must never be an argument on a call.
        $calls = $script:Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
        $hits = foreach ($c in $calls) {
            $c.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] -and "$($_.Value)" -match '^x500:' }
        }
        @($hits).Count | Should -Be 0
    }
}

Describe 'New-TargetMailUsers.ps1 mocked run' {
    BeforeAll {
        Mock Connect-MigrationExchange { }
        Mock Get-AcceptedDomain { [pscustomobject]@{ DomainName = 'fabrikam.onmicrosoft.com' } }
        Mock Get-Recipient { $null }
        Mock New-OutputFolder { $TestDrive }
        Mock New-MailUser { $global:Calls++ }
    }
    BeforeEach {
        $global:Calls = 0
        & $script:Script -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@fabrikam.com' `
            -UserListPath $script:UsersCsv -Customer 'testcust'
    }
    It 'creates exactly one MailUser' {
        $global:Calls | Should -Be 1
    }
    It 'bound only allowed parameters' {
        # The AST test above statically proves the parameter set; here we prove the values bind
        # where the doc puts them: ExternalEmailAddress = source SMTP, target addresses on target.
        Assert-MockCalled New-MailUser -Times 1 -ParameterFilter {
            $ExternalEmailAddress -eq 'good@contoso.com' -and
            $MicrosoftOnlineServicesID -eq 'good@fabrikam.onmicrosoft.com' -and
            $PrimarySmtpAddress -eq 'good@fabrikam.onmicrosoft.com' -and
            $Password -is [securestring] -and
            -not $PSBoundParameters.ContainsKey('ExchangeGuid') -and
            -not $PSBoundParameters.ContainsKey('ArchiveGuid') -and
            -not $PSBoundParameters.ContainsKey('EmailAddresses')
        }
    }
    It 'refuses the non-accepted-domain row' {
        $report = Import-Csv (Get-ChildItem $TestDrive -Recurse -Filter 'TargetMailUsers.csv' | Select-Object -First 1).FullName
        @($report | Where-Object Action -eq 'Refused').Count | Should -Be 1
        @($report | Where-Object Action -eq 'Created').Count | Should -Be 1
    }
}
