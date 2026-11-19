#requires -Version 7.2
<#
.SYNOPSIS
    Builds target security/M365 groups and fills their members/owners BEFORE any
    OneDrive/SharePoint move (Learn step-4 requirement).

.DESCRIPTION
    Input: source-groups.csv + source-group-members.csv (Export-SourceGroups.ps1),
    the 01 user list, guest-map.csv and optionally the 07 site plan.

    Kind handling:
      Security                 created (security, not mail-enabled)
      DynamicSecurity/DynamicM365 created with the source MembershipRule but
                               MembershipRuleProcessingState 'Paused' - marked Review.
                               Static members are never added.
      M365                     if the group's site migrates natively (a Native row in
                               -SitePlanPath) the group must already exist (created by
                               07 New-TargetSiteGroups with ProvisionSiteOnDemand);
                               looked up by target alias, only members/owners are set -
                               not found -> refused with a pointer at 07.
                               Other M365 groups are created (Unified, mail-enabled,
                               security-enabled, same visibility). Team-enabled groups
                               are flagged TeamRebuild - this script doesn't create Teams.
      MailEnabledSecurity /    owned by 08 Copy-MailConfig - resolved here via the
      Distribution             'T2T:<source>' CustomAttribute15 tag, else alias, so they
                               appear in the group map; unresolved -> reported.
      IsAssignableToRole       refused - flag for manual handling.

    M365 groups whose site migrates and whose alias contains '.' are refused (Learn).
    Members/owners resolve via Get-AddressMap (01 user list + shared mapping) plus
    guest-map.csv and the group map itself (second pass for nested groups).
    Unmapped members are reported and never added. Existing membership is skipped.
    Output: group-map.csv (SourceGroupId, SourceName, Kind, TargetGroupId,
    TargetAlias, Action, Note) + unresolved-members.csv.

    https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration-step4
    https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration-step4

.PARAMETER TenantId / AdminUpn
    Target tenant (GUID) + admin sign-in.

.PARAMETER GroupsCsv / MembersCsv
    Export-SourceGroups.ps1 output.

.PARAMETER UserListPath
    migration-users.csv.

.PARAMETER GuestMapPath / SharedMailboxMappingPath / SitePlanPath / NameSuffix
    Optional inputs. -SitePlanPath = Get-SiteMigrationPlan CSV (Native rows mean the
    group's site moves natively).

.EXAMPLE
    .\New-TargetGroups.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@fabrikam.com' `
        -GroupsCsv .\customers\contoso\output\03-Identities\<stamp>\source-groups.csv -MembersCsv .\customers\contoso\output\03-Identities\<stamp>\source-group-members.csv `
        -UserListPath .\customers\contoso\input\migration-users.csv -GuestMapPath .\customers\contoso\output\03-Identities\<stamp>\guest-map.csv -Customer contoso -WhatIf

.NOTES
    Untested against live tenants - validate in technical test/pilot.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$GroupsCsv,

    [Parameter(Mandatory)]
    [string]$MembersCsv,

    [Parameter(Mandatory)]
    [string]$UserListPath,

    [Parameter(Mandatory)]
    [string]$Customer,

    [string]$GuestMapPath,
    [string]$SharedMailboxMappingPath,
    [string]$SitePlanPath,
    [string]$NameSuffix = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

$groups  = @(Import-Csv $GroupsCsv)
$members = @(Import-Csv $MembersCsv)

$nativeAliases = @{}
if ($SitePlanPath) {
    foreach ($r in @(Import-Csv $SitePlanPath | Where-Object { "$($_.Method)" -match 'Native' -and "$($_.GroupAlias)".Trim() })) {
        $nativeAliases["$($r.GroupAlias)".ToLower()] = $true
    }
}

$am = Get-AddressMap -UserListPath $UserListPath -SharedMailboxMappingPath $SharedMailboxMappingPath
$identityMap = @{}
foreach ($k in $am.Map.Keys) { $identityMap[$k] = $am.Map[$k] }
if ($GuestMapPath -and (Test-Path $GuestMapPath)) {
    foreach ($g in @(Import-Csv $GuestMapPath)) {
        if ("$($g.TargetUpn)".Trim()) { $identityMap["$($g.SourceMail)".ToLower()] = "$($g.TargetUpn)".Trim() }
    }
}

$null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'Group.ReadWrite.All', 'Directory.Read.All'

$map   = [System.Collections.Generic.List[object]]::new()
$unres = [System.Collections.Generic.List[object]]::new()
$groupMap = @{}   # source group id -> target id (nested groups)

function Resolve-Identity([string]$id, [string]$upn, [string]$mail) {
    # returns a Graph @odata.id reference path, or $null when unmapped
    $g = $groupMap[$id]
    if ($g) { return "https://graph.microsoft.com/v1.0/directoryObjects/$g" }
    foreach ($k in @($upn, $mail) | Where-Object { $_ }) {
        $v = $identityMap[$k.ToLower()]
        if ($v) { return "https://graph.microsoft.com/v1.0/users/$v" }
    }
    return $null
}

function Add-GroupPeople($tgtId, $srcId, $role) {
    foreach ($m in @($members | Where-Object { $_.GroupId -eq $srcId -and $_.Role -eq $role })) {
        $t = Resolve-Identity $m.MemberId $m.MemberUpn $m.MemberMail
        if (-not $t) {
            $unres.Add([pscustomobject]@{ GroupId = $srcId; Role = $role; MemberId = $m.MemberId; MemberUpn = $m.MemberUpn; MemberMail = $m.MemberMail })
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($tgtId, "Add $role $t")) { continue }
        try {
            if ($role -eq 'Owner') { New-MgGroupOwnerByRef  -GroupId $tgtId -BodyParameter @{ '@odata.id' = $t } -ErrorAction Stop }
            else                   { New-MgGroupMemberByRef -GroupId $tgtId -BodyParameter @{ '@odata.id' = $t } -ErrorAction Stop }
        } catch {
            if ($_.Exception.Message -notmatch 'already|exist|One or more added object references') {
                Write-Warning "Add $role $t -> $tgtId : $($_.Exception.Message)"
            }
        }
    }
}

foreach ($g in $groups) {
    $alias = "$($g.MailNickname)".Trim()
    $row = [pscustomobject]@{
        SourceGroupId = $g.Id; SourceName = $g.DisplayName; Kind = $g.Kind
        TargetGroupId = ''; TargetAlias = ''; Action = ''; Note = ''
    }
    if ([bool]::Parse("$($g.IsAssignableToRole)")) {
        $row.Action = 'Refused'; $row.Note = 'Role-assignable group - handle manually'
        $map.Add($row); continue
    }

    switch -Wildcard ($g.Kind) {
        'Dynamic*' {
            if (-not $PSCmdlet.ShouldProcess($g.DisplayName, "Create dynamic group (paused)")) { $row.Action = 'WhatIf'; break }
            try {
                $unified = $g.Kind -eq 'DynamicM365'
                $ng = New-MgGroup -DisplayName "$($g.DisplayName)$NameSuffix" -MailNickname "$alias$NameSuffix" `
                    -MailEnabled:$unified -SecurityEnabled:(-not $unified) `
                    -GroupTypes $(if ($unified) { @('Unified', 'DynamicMembership') } else { @('DynamicMembership') }) `
                    -MembershipRule $g.MembershipRule -MembershipRuleProcessingState 'Paused' -ErrorAction Stop
                $row.TargetGroupId = $ng.Id; $row.TargetAlias = $ng.MailNickname
                $row.Action = 'Created'; $row.Note = 'Review - dynamic rule paused, may reference source-only values'
            } catch { $row.Action = 'Problem'; $row.Note = $_.Exception.Message }
            break
        }
        'Security' {
            if (-not $PSCmdlet.ShouldProcess($g.DisplayName, 'Create security group')) { $row.Action = 'WhatIf'; break }
            try {
                $ng = New-MgGroup -DisplayName "$($g.DisplayName)$NameSuffix" -MailNickname "$alias$NameSuffix" `
                    -MailEnabled:$false -SecurityEnabled:$true -ErrorAction Stop
                $row.TargetGroupId = $ng.Id; $row.TargetAlias = $ng.MailNickname; $row.Action = 'Created'
            } catch { $row.Action = 'Problem'; $row.Note = $_.Exception.Message }
            break
        }
        'M365' {
            $native = $nativeAliases.ContainsKey($alias.ToLower())
            if ($alias -match '\.') {
                if ($native) { $row.Action = 'Refused'; $row.Note = "Alias '$alias' contains '.' - not allowed for site-migrating groups (Learn)" }
                else { $row.Action = 'Refused'; $row.Note = "Alias '$alias' contains '.'" }
                break
            }
            if ($native) {
                $tg = $null
                try { $tg = @(Get-MgGroup -Filter "mailNickname eq '$alias'" -ErrorAction Stop) | Select-Object -First 1 } catch {}
                if (-not $tg) {
                    $row.Action = 'Refused'
                    $row.Note = "Site-migrating M365 group not found - create it first with 07 New-TargetSiteGroups (alias '$alias')"
                    break
                }
                $row.TargetGroupId = $tg.Id; $row.TargetAlias = $tg.MailNickname
                $row.Action = 'MembersOnly'; $row.Note = 'Native site move - group pre-created by 07'
                break
            }
            $team = (@($g.ResourceProvisioningOptions -split ';') -contains 'Team')
            if (-not $PSCmdlet.ShouldProcess($g.DisplayName, 'Create M365 group')) { $row.Action = 'WhatIf'; break }
            try {
                $vis = if ("$($g.Visibility)" -match 'Private|HiddenMembership') { "$($g.Visibility)" } else { 'Public' }
                $ng = New-MgGroup -DisplayName "$($g.DisplayName)$NameSuffix" -MailNickname "$alias$NameSuffix" `
                    -GroupTypes 'Unified' -MailEnabled:$true -SecurityEnabled:$false -Visibility $vis -ErrorAction Stop
                $row.TargetGroupId = $ng.Id; $row.TargetAlias = $ng.MailNickname; $row.Action = 'Created'
                if ($team) { $row.Note = 'TeamRebuild - Teams team not created by this script (manual/pilot)' }
            } catch { $row.Action = 'Problem'; $row.Note = $_.Exception.Message }
            break
        }
        default {  # MailEnabledSecurity / Distribution - owned by 08 Copy-MailConfig
            $tg = $null
            try { $tg = @(Get-MgGroup -Filter "mail eq '$($g.Mail)'" -ErrorAction SilentlyContinue) | Select-Object -First 1 } catch {}
            if (-not $tg) { try { $tg = @(Get-MgGroup -Filter "mailNickname eq '$alias'" -ErrorAction SilentlyContinue) | Select-Object -First 1 } catch {} }
            if ($tg) {
                $row.TargetGroupId = $tg.Id; $row.TargetAlias = $tg.MailNickname
                $row.Action = 'Resolved'; $row.Note = 'Mail-enabled group owned by 08 Copy-MailConfig - map only'
            } else {
                $row.Action = 'Unresolved'; $row.Note = 'Run 08 Copy-MailConfig -Import first (looks up T2T tag/alias)'
            }
            break
        }
    }
    if ($row.TargetGroupId) { $groupMap[$g.Id] = $row.TargetGroupId }
    if ($row.TargetGroupId -and $row.Kind -notmatch 'Dynamic|MailEnabledSecurity|Distribution') {
        Add-GroupPeople $row.TargetGroupId $g.Id 'Owner'
        Add-GroupPeople $row.TargetGroupId $g.Id 'Member'
    }
    $map.Add($row)
}

$out = New-OutputFolder -Customer $Customer -Phase '03-Identities'
$map | Export-CsvSafe -Path (Join-Path $out 'group-map.csv')
$unres | Export-CsvSafe -Path (Join-Path $out 'unresolved-members.csv') -Header 'GroupId','Role','MemberId','MemberUpn','MemberMail'
$map | Group-Object Action | Sort-Object Name | Format-Table Name, Count -AutoSize
if ($unres.Count) { Write-Warning "$($unres.Count) member(s)/owner(s) unresolved - see unresolved-members.csv" }
Write-Host "Group map written to $out" -ForegroundColor Green
