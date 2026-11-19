#requires -Version 7.2
<#
.SYNOPSIS
    Exports all Entra ID groups and their members/owners from the SOURCE tenant.

.DESCRIPTION
    Read-only. Writes source-groups.csv (one row per group) and
    source-group-members.csv (one row per owner/member incl. nested groups) under
    customers/<Customer>/output/03-Identities/.

    Kind classification:
      M365                 Unified group
      DynamicM365          Unified + MembershipRule
      Security             SecurityEnabled, not MailEnabled
      DynamicSecurity      Security + MembershipRule
      MailEnabledSecurity  MailEnabled + SecurityEnabled (not Unified)
      Distribution         MailEnabled, not SecurityEnabled

    New-TargetGroups.ps1 rebuilds them in the target (security/M365 only - mail-
    enabled groups are owned by 08 Copy-MailConfig) and New-SpoIdentityMap.ps1 maps
    them so SharePoint/OneDrive permissions survive.
    https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration-step4

.PARAMETER TenantId
    Source tenant ID (GUID).

.PARAMETER AdminUpn
    Source admin sign-in name.

.PARAMETER Customer
    Output under customers/<Customer>/output/03-Identities/.

.EXAMPLE
    .\Export-SourceGroups.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@contoso.com' -Customer contoso

.NOTES
    Untested against live tenants - validate in technical test/pilot.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force

$null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'Group.Read.All'

$groups = @(Get-MgGroup -All -Property 'id,displayName,mailNickname,mail,groupTypes,mailEnabled,securityEnabled,membershipRule,membershipRuleProcessingState,visibility,isAssignableToRole,resourceProvisioningOptions,createdDateTime,membershipRuleProcessingState')

function Get-GroupKind($g) {
    $unified = @($g.GroupTypes) -contains 'Unified'
    if ($unified -and $g.MembershipRule) { return 'DynamicM365' }
    if ($unified) { return 'M365' }
    if ($g.SecurityEnabled -and $g.MembershipRule) { return 'DynamicSecurity' }
    if ($g.SecurityEnabled -and -not $g.MailEnabled) { return 'Security' }
    if ($g.SecurityEnabled -and $g.MailEnabled) { return 'MailEnabledSecurity' }
    return 'Distribution'
}

$groupRows = [System.Collections.Generic.List[object]]::new()
$memberRows = [System.Collections.Generic.List[object]]::new()

function Add-MemberRow($GroupId, $Role, $m) {
    $type = 'Unknown'
    if ($m.AdditionalProperties.'@odata.type') {
        $type = $m.AdditionalProperties.'@odata.type' -replace '^#microsoft\.graph\.', ''
    }
    $memberRows.Add([pscustomobject]@{
        GroupId    = $GroupId
        Role       = $Role
        MemberType = $type
        MemberId   = $m.Id
        MemberUpn  = "$($m.AdditionalProperties.userPrincipalName)"
        MemberMail = "$($m.AdditionalProperties.mail)"
    })
}

foreach ($g in $groups) {
    $groupRows.Add([pscustomobject]@{
        Id                            = $g.Id
        DisplayName                   = $g.DisplayName
        MailNickname                  = $g.MailNickname
        Mail                          = $g.Mail
        GroupTypes                    = (@($g.GroupTypes) -join ';')
        MailEnabled                   = $g.MailEnabled
        SecurityEnabled               = $g.SecurityEnabled
        MembershipRule                = $g.MembershipRule
        MembershipRuleProcessingState = "$($g.MembershipRuleProcessingState)"
        Visibility                    = "$($g.Visibility)"
        IsAssignableToRole            = $g.IsAssignableToRole
        ResourceProvisioningOptions   = (@($g.ResourceProvisioningOptions) -join ';')
        CreatedDateTime               = $g.CreatedDateTime
        Kind                          = Get-GroupKind $g
    })

    try {
        foreach ($m in @(Get-MgGroupMember -GroupId $g.Id -All -ErrorAction Stop)) { Add-MemberRow $g.Id 'Member' $m }
    } catch { Write-Warning "Members of '$($g.DisplayName)' failed: $($_.Exception.Message)" }
    try {
        foreach ($o in @(Get-MgGroupOwner -GroupId $g.Id -All -ErrorAction Stop)) { Add-MemberRow $g.Id 'Owner' $o }
    } catch { Write-Warning "Owners of '$($g.DisplayName)' failed: $($_.Exception.Message)" }
}

$out = New-OutputFolder -Customer $Customer -Phase '03-Identities'
$gp = Join-Path $out 'source-groups.csv'
$mp = Join-Path $out 'source-group-members.csv'
$groupRows  | Export-CsvSafe -Path $gp
$memberRows | Export-CsvSafe -Path $mp -Header 'GroupId','Role','MemberType','MemberId','MemberUpn','MemberMail'
Write-Host "$($groupRows.Count) groups, $($memberRows.Count) membership rows -> $out" -ForegroundColor Green
