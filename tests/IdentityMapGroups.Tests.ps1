BeforeAll {
    $repo = (Resolve-Path "$PSScriptRoot\..").Path
    Import-Module "$repo\tools\Orchestrator.psm1" -Force
    Import-Module "$repo\tools\Common.psm1" -Force
    $src = 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff'
    $tgt = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    $g1  = '00000000-0000-0000-0000-000000000000'
    $g2  = '00000003-0000-0000-c000-000000000000'
}

Describe 'ConvertTo-SpoIdentityMapRow' {
    It 'member user row' {
        ConvertTo-SpoIdentityMapRow -SourceTenantId $src -Kind User -SourceKey 'a@contoso.com' -TargetUpn 'a@fabrikam.com' -TargetEmail 'a@fabrikam.com' |
            Should -Be "User,$src,a@contoso.com,a@fabrikam.com,a@fabrikam.com,RegularUser"
    }
    It 'source guest -> target member' {
        ConvertTo-SpoIdentityMapRow -SourceTenantId $src -Kind User -SourceKey 'g_contoso.com#EXT#@contoso.onmicrosoft.com' -TargetUpn 'g@fabrikam.com' -TargetEmail 'g@fabrikam.com' -UserType GuestUser |
            Should -Be "User,$src,g_contoso.com#EXT#@contoso.onmicrosoft.com,g@fabrikam.com,g@fabrikam.com,GuestUser"
    }
    It 'source guest -> target guest' {
        ConvertTo-SpoIdentityMapRow -SourceTenantId $src -Kind User -SourceKey 'g_contoso.com#EXT#@contoso.onmicrosoft.com' -TargetUpn 'g_contoso.com#EXT#@fabrikam.onmicrosoft.com' -TargetEmail 'g.ext@contoso.com' -UserType GuestUser |
            Should -Be "User,$src,g_contoso.com#EXT#@contoso.onmicrosoft.com,g_contoso.com#EXT#@fabrikam.onmicrosoft.com,g.ext@contoso.com,GuestUser"
    }
    It 'security group: GroupName = target object id' {
        ConvertTo-SpoIdentityMapRow -SourceTenantId $src -Kind Group -SourceKey $g1 -TargetGroupId $g2 |
            Should -Be "Group,$src,$g1,$g2,$g2,RegularGroup"
    }
    It 'M365 group: col5 alias + O365Group' {
        ConvertTo-SpoIdentityMapRow -SourceTenantId $src -Kind O365Group -SourceKey $g1 -TargetGroupId $g2 -GroupAlias 'sales' |
            Should -Be "Group,$src,$g1,$g2,sales,O365Group"
    }
}

Describe 'Test-SpoIdentityMap' {
    It 'clean map returns nothing' {
        @(Test-SpoIdentityMap -Rows @("User,$src,a@contoso.com,a@fabrikam.com,a@fabrikam.com,RegularUser")) | Should -HaveCount 0
    }
    It 'reports duplicate source, duplicate target, bad GUID, missing #EXT#, dot alias - all together' {
        $rows = @(
            "User,$src,a@contoso.com,a@fabrikam.com,a@fabrikam.com,RegularUser",
            "User,$src,a@contoso.com,a@fabrikam.com,a@fabrikam.com,RegularUser",           # dup source + dup target
            "User,notaguid,b@contoso.com,b@fabrikam.com,b@fabrikam.com,RegularUser",       # bad GUID
            "User,$src,g_contoso.com@contoso.onmicrosoft.com,z@fabrikam.com,z@fabrikam.com,GuestUser",  # no #EXT#
            "Group,$src,$g1,$g2,bad.alias,O365Group"                   # dot in alias
        )
        $p = @(Test-SpoIdentityMap -Rows $rows)
        ($p -match 'duplicate source').Count | Should -BeGreaterThan 0
        ($p -match 'duplicate target').Count | Should -BeGreaterThan 0
        ($p -match 'not a GUID').Count | Should -BeGreaterThan 0
        ($p -match '#EXT#').Count | Should -BeGreaterThan 0
        ($p -match "must not contain").Count | Should -BeGreaterThan 0
    }
}

Describe 'New-SpoIdentityMap output file' {
    BeforeAll {
        $dir = New-Item -ItemType Directory -Path "$TestDrive\inputs" -Force
        @"
SourceUpn,TargetUpn,SourcePrimarySmtp,TargetPrimarySmtp,Batch,DisplayName,FirstName,LastName,UsageLocation,TargetLicenseSku,CompleteAfterDateTimeUtc,Workloads
søren@contoso.com,soren@fabrikam.onmicrosoft.com,søren@contoso.com,soren@fabrikam.onmicrosoft.com,B1,Søren Å,Søren,Å,DK,SKU,2026-09-05T22:00:00Z,Exchange
"@ | Set-Content "$dir\users.csv" -Encoding utf8
        @"
SourceGuestUpn,SourceMail,TargetUserId,TargetUpn,TargetMail,TargetType,Action
guest_contoso.com#EXT#@contoso.onmicrosoft.com,g.ext@contoso.com,$g1,g_contoso.com#EXT#@fabrikam.onmicrosoft.com,g.ext@contoso.com,Guest,Invited
"@ | Set-Content "$dir\guests.csv" -Encoding utf8
        & "$repo\03-Identities\New-SpoIdentityMap.ps1" -TenantId $tgt -AdminUpn 'admin@fabrikam.com' `
            -SourceTenantId $src -UserListPath "$dir\users.csv" -GuestMapPath "$dir\guests.csv" -Customer 'pestertest'
        $script:mapFile = Get-ChildItem "$repo\customers\pestertest\output\03-Identities\*\spo-identity-map.csv" | Sort-Object LastWriteTime | Select-Object -Last 1
    }
    AfterAll { Remove-Item "$repo\customers\pestertest" -Recurse -Force -ErrorAction SilentlyContinue }
    It 'has no header and no BOM' {
        $bytes = [IO.File]::ReadAllBytes($script:mapFile.FullName)
        $bytes[0..2] -join ',' | Should -Not -Be '239,187,191'
        (Get-Content $script:mapFile.FullName -TotalCount 1) | Should -Match '^(User|Group),'
    }
    It 'rows are comma-delimited six columns and non-ASCII survives' {
        $lines = Get-Content $script:mapFile.FullName
        $lines | ForEach-Object { ($_ -split ',').Count | Should -Be 6 }
        ($lines -match 'søren@').Count | Should -Be 1
    }
}

Describe 'New-TargetGuests (mocked)' {
    BeforeAll {
        # other test files define global stubs with narrower signatures - own the names here
        function global:Get-MgUser { param($Filter, $Property, $UserId, [switch]$All, $ErrorAction) }
        function global:Get-MgDomain { param([switch]$All) }
        function global:New-MgInvitation { param($BodyParameter, $ErrorAction) }
        Mock Connect-MigrationGraph { return [pscustomobject]@{ TenantId = $tgt; Account = 'admin@fabrikam.com' } }
        Mock New-OutputFolder { return $TestDrive }
        @"
Id,UserPrincipalName,Mail,DisplayName,ExternalUserState,CreatedDateTime,LastSignInDateTime
$g1,mem_fabrikam.com#EXT#@contoso.onmicrosoft.com,emp@fabrikam.com,Emp Guest,Accepted,2025-01-01,
$g2,g_contoso.com#EXT#@contoso.onmicrosoft.com,g.ext@contoso.com,Guest X,PendingAcceptance,2025-01-01,
00000003-0000-0ff1-ce00-000000000000,h_contoso.com#EXT#@contoso.onmicrosoft.com,h.ext@contoso.com,Guest H,PendingAcceptance,2025-01-01,
"@ | Set-Content "$TestDrive\source-guests.csv" -Encoding utf8
    }
    It 'verified-domain mail + existing member -> member mapping, no invitation' {
        Mock Get-MgDomain { [pscustomobject]@{ Id = 'fabrikam.com'; IsVerified = $true } }
        Mock Get-MgUser { [pscustomobject]@{ Id = 'u1'; UserPrincipalName = 'emp@fabrikam.com'; Mail = 'emp@fabrikam.com'; UserType = 'Member' } }
        Mock New-MgInvitation { throw 'should not be called' }
        & "$repo\03-Identities\New-TargetGuests.ps1" -TenantId $tgt -AdminUpn 'admin@fabrikam.com' -GuestsCsv "$TestDrive\source-guests.csv" -Customer t 6>$null
        $map = Import-Csv "$TestDrive\guest-map.csv"
        ($map | Where-Object SourceMail -eq 'emp@fabrikam.com').TargetType | Should -Be 'Member'
        Should -Invoke New-MgInvitation -Times 0
    }
    It 'existing target guest is reused; new guest invited without mail by default' {
        Mock Get-MgDomain { [pscustomobject]@{ Id = 'fabrikam.com'; IsVerified = $true } }
        Mock Get-MgUser {
            if ($Filter -match 'g.ext@contoso.com') { return [pscustomobject]@{ Id = 'gx'; UserPrincipalName = 'g_contoso.com#EXT#@fabrikam.onmicrosoft.com'; Mail = 'g.ext@contoso.com'; UserType = 'Guest' } }
            return @()
        }
        Mock New-MgInvitation {
            [pscustomobject]@{ InvitedUser = [pscustomobject]@{ Id = 'new1'; UserPrincipalName = 'h_contoso.com#EXT#@fabrikam.onmicrosoft.com' } }
        }
        & "$repo\03-Identities\New-TargetGuests.ps1" -TenantId $tgt -AdminUpn 'admin@fabrikam.com' -GuestsCsv "$TestDrive\source-guests.csv" -Customer t 6>$null
        $map = Import-Csv "$TestDrive\guest-map.csv"
        ($map | Where-Object SourceMail -eq 'g.ext@contoso.com').Action | Should -Be 'MappedToExistingGuest'
        ($map | Where-Object SourceMail -eq 'h.ext@contoso.com').Action | Should -Be 'Invited'
        Should -Invoke New-MgInvitation -Times 1 -ParameterFilter { $BodyParameter.SendInvitationMessage -eq $false }
    }
    It 'SendInvitationMessage switch turns the mail on' {
        Mock Get-MgDomain { @() }
        Mock Get-MgUser { @() }
        Mock New-MgInvitation {
            [pscustomobject]@{ InvitedUser = [pscustomobject]@{ Id = 'n'; UserPrincipalName = 'x' } }
        }
        & "$repo\03-Identities\New-TargetGuests.ps1" -TenantId $tgt -AdminUpn 'admin@fabrikam.com' -GuestsCsv "$TestDrive\source-guests.csv" -Customer t -SendInvitationMessage 6>$null
        Should -Invoke New-MgInvitation -Times 3 -ParameterFilter { $BodyParameter.SendInvitationMessage -eq $true }
    }
}

Describe 'New-TargetGroups (mocked)' {
    BeforeAll {
        function global:Get-MgGroup { param($Filter, $Property, $GroupId, [switch]$All, $ErrorAction) }
        function global:New-MgGroup { param($DisplayName, $MailNickname, $MailEnabled, $SecurityEnabled, $GroupTypes, $MembershipRule, $MembershipRuleProcessingState, $Visibility, $ErrorAction) }
        function global:New-MgGroupMemberByRef { param($GroupId, $BodyParameter, $ErrorAction) }
        function global:New-MgGroupOwnerByRef { param($GroupId, $BodyParameter, $ErrorAction) }
        Mock Connect-MigrationGraph { $null }
        Mock New-OutputFolder { return $TestDrive }
        @"
Id,DisplayName,MailNickname,Mail,GroupTypes,MailEnabled,SecurityEnabled,MembershipRule,MembershipRuleProcessingState,Visibility,IsAssignableToRole,ResourceProvisioningOptions,CreatedDateTime,Kind
$g1,Dynamic Sec,dynsec,,DynamicMembership,False,True,(user.country -eq ""DK""),On,,False,,2025-01-01,DynamicSecurity
$g2,Site Group,sitegroup,sitegroup@contoso.com,Unified,True,False,,,Public,False,,2025-01-01,M365
"@ | Set-Content "$TestDrive\source-groups.csv" -Encoding utf8
        @"
GroupId,Role,MemberType,MemberId,MemberUpn,MemberMail
$g2,Member,user,uu1,anna@contoso.com,anna@contoso.com
$g2,Member,user,uu2,ghost@contoso.com,ghost@contoso.com
"@ | Set-Content "$TestDrive\source-group-members.csv" -Encoding utf8
        @"
SourceUpn,TargetUpn,SourcePrimarySmtp,TargetPrimarySmtp,Batch,DisplayName,FirstName,LastName,UsageLocation,TargetLicenseSku,CompleteAfterDateTimeUtc,Workloads
anna@contoso.com,anna@fabrikam.onmicrosoft.com,anna@contoso.com,anna@fabrikam.onmicrosoft.com,B1,Anna,Anna,A,DK,SKU,2026-09-05T22:00:00Z,Exchange
"@ | Set-Content "$TestDrive\users.csv" -Encoding utf8
        @"
SiteUrl,Method,GroupAlias
https://contoso.sharepoint.com/sites/sg,Native,sitegroup
"@ | Set-Content "$TestDrive\siteplan.csv" -Encoding utf8
    }
    It 'dynamic group created paused with rule, no static members; unmapped member reported not added' {
        Mock New-MgGroup { param($DisplayName, $MailNickname) $MembershipRuleProcessingState | Should -Be 'Paused'; $MembershipRule | Should -Match 'user.country'; [pscustomobject]@{ Id = 't1'; MailNickname = $MailNickname } }
        Mock Get-MgGroup { [pscustomobject]@{ Id = 't2'; MailNickname = 'sitegroup' } }
        Mock New-MgGroupMemberByRef { }
        Mock New-MgGroupOwnerByRef { }
        & "$repo\03-Identities\New-TargetGroups.ps1" -TenantId $tgt -AdminUpn a -GroupsCsv "$TestDrive\source-groups.csv" `
            -MembersCsv "$TestDrive\source-group-members.csv" -UserListPath "$TestDrive\users.csv" -Customer t -SitePlanPath "$TestDrive\siteplan.csv" 6>$null
        $map = Import-Csv "$TestDrive\group-map.csv"
        ($map | Where-Object Kind -eq 'DynamicSecurity').Action | Should -Be 'Created'
        ($map | Where-Object Kind -eq 'M365').Action | Should -Be 'MembersOnly'
        (Import-Csv "$TestDrive\unresolved-members.csv").MemberUpn | Should -Be 'ghost@contoso.com'
        Should -Invoke New-MgGroupMemberByRef -Times 1   # only anna, never ghost, none for dynamic
    }
    It 'site-migrating M365 group missing -> refused pointing at 07' {
        Mock New-MgGroup { [pscustomobject]@{ Id = 't1'; MailNickname = 'x' } }
        Mock Get-MgGroup { @() }
        & "$repo\03-Identities\New-TargetGroups.ps1" -TenantId $tgt -AdminUpn a -GroupsCsv "$TestDrive\source-groups.csv" `
            -MembersCsv "$TestDrive\source-group-members.csv" -UserListPath "$TestDrive\users.csv" -Customer t -SitePlanPath "$TestDrive\siteplan.csv" 6>$null
        ($map = Import-Csv "$TestDrive\group-map.csv") | Out-Null
        ($map | Where-Object Kind -eq 'M365').Action | Should -Be 'Refused'
        ($map | Where-Object Kind -eq 'M365').Note | Should -Match 'New-TargetSiteGroups'
    }
    It 'role-assignable group refused' {
        @"
Id,DisplayName,MailNickname,Mail,GroupTypes,MailEnabled,SecurityEnabled,MembershipRule,MembershipRuleProcessingState,Visibility,IsAssignableToRole,ResourceProvisioningOptions,CreatedDateTime,Kind
$g1,Admins,admins,,,False,True,,On,,True,,2025-01-01,Security
"@ | Set-Content "$TestDrive\role-groups.csv" -Encoding utf8
        Mock New-MgGroup { throw 'should not create' }
        & "$repo\03-Identities\New-TargetGroups.ps1" -TenantId $tgt -AdminUpn a -GroupsCsv "$TestDrive\role-groups.csv" `
            -MembersCsv "$TestDrive\source-group-members.csv" -UserListPath "$TestDrive\users.csv" -Customer t 6>$null
        (Import-Csv "$TestDrive\group-map.csv").Action | Should -Be 'Refused'
        Should -Invoke New-MgGroup -Times 0
    }
}

Describe 'Copy-MailConfig permission ownership' {
    It 'Permissions is no longer in the -Include ValidateSet or default' {
        $srcText = Get-Content "$repo\08-MailConfig\Copy-MailConfig.ps1" -Raw
        $srcText | Should -Not -Match "ValidateSet\([^)]*'Permissions'"
        $srcText | Should -Not -Match "\bPermissions\.csv"
    }
    It 'dynamic group import creates a hidden DDG' {
        function global:Get-AcceptedDomain {}
        function global:Get-DynamicDistributionGroup { param($Identity, $ResultSize) }
        function global:New-DynamicDistributionGroup { param($Name, $Alias, $RecipientFilter, $ErrorAction) }
        function global:Set-DynamicDistributionGroup { param($Identity, $HiddenFromAddressListsEnabled, $ErrorAction) }
        Mock Connect-MigrationExchange { [pscustomobject]@{ UserPrincipalName = 'a'; TenantID = $tgt } }
        Mock Get-AcceptedDomain { [pscustomobject]@{ DomainName = 'fabrikam.onmicrosoft.com'; Default = $true } }
        Mock Get-AddressMap { [pscustomobject]@{ Map = @{}; Duplicates = @() } }
        Mock New-OutputFolder { return $TestDrive }
        Mock Get-DynamicDistributionGroup { $null }
        Mock New-DynamicDistributionGroup { }
        Mock Set-DynamicDistributionGroup { }
        $ef = New-Item -ItemType Directory "$TestDrive\exp" -Force
        foreach ($f in 'Forwarding.csv', 'DistributionGroups.csv', 'DistributionGroupMembers.csv', 'MailContacts.csv') {
            'x' | Set-Content (Join-Path $ef $f)
        }
        'DisplayName,Alias,PrimarySmtpAddress,RecipientFilter' + "`n" + 'Dyn,dyn,dyn@contoso.com,(recipientType -eq "UserMailbox")' | Set-Content (Join-Path $ef 'DynamicGroups.csv')
        & "$repo\08-MailConfig\Copy-MailConfig.ps1" -Import -TenantId $tgt -AdminUpn a -Customer t `
            -ExportFolder $ef -UserListPath "$TestDrive\users.csv" -AddressDomain fabrikam.onmicrosoft.com -Include DynamicGroups 6>$null
        Should -Invoke New-DynamicDistributionGroup -Times 1
        Should -Invoke Set-DynamicDistributionGroup -Times 1 -ParameterFilter { $HiddenFromAddressListsEnabled -eq $true }
    }
}
