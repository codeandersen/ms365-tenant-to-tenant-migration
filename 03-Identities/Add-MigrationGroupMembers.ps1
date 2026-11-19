#requires -Version 7.2
<#
.SYNOPSIS
    Adds the migration users to the source tenant's mail-enabled security scope group.

.DESCRIPTION
    The source organisation relationship's MailboxMovePublishedScopes tells the migration service
    which users are allowed to move; the same group also scopes what CTIM copies. For every user in
    the list this script:
      1. Verifies -ScopeGroupName is a mail-enabled security group AND appears in the
         MailboxMovePublishedScopes of an org relationship (optionally the one whose DomainNames is
         -PartnerTenantId) - refuses otherwise.
      2. Warns when a user is already a member of a DIFFERENT published scope group (an object must
         not be in more than one scope).
      3. Add-DistributionGroupMember for each SourcePrimarySmtp (idempotent - skips members).

    Supports -WhatIf.

.PARAMETER TenantId
    Source tenant ID (GUID). The Exchange Online connection is asserted against it.

.PARAMETER AdminUpn
    Source tenant admin sign-in name.

.PARAMETER ScopeGroupName
    Name of the mail-enabled security scope group.

.PARAMETER UserListPath
    Path to migration-users.csv.

.PARAMETER PartnerTenantId
    Optional target tenant ID (GUID); when given, the scope group must be published in the org
    relationship pointing at that tenant.

.PARAMETER Customer
    Writes the report CSV under customers/<Customer>/output/03-Identities/.

.EXAMPLE
    .\Add-MigrationGroupMembers.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@contoso.com' `
        -ScopeGroupName 'M365MigrationScope' -UserListPath .\customers\fabrikam\input\migration-users.csv -Customer fabrikam

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Sources:
      https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-4-user-prep
      https://learn.microsoft.com/en-us/microsoft-365/enterprise/cross-tenant-identity-mapping
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$ScopeGroupName,

    [Parameter(Mandatory)]
    [string]$UserListPath,

    [ValidateScript({ -not $_ -or [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$PartnerTenantId,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

$users = @(Import-MigrationUserList -Path $UserListPath)
$null = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn

$grp = Get-DistributionGroup -Identity $ScopeGroupName -ErrorAction SilentlyContinue
if (-not $grp) { throw "Scope group '$ScopeGroupName' not found - create it in 02-TenantPrep (OrgRelationship step)." }
if ("$($grp.RecipientTypeDetails)" -notmatch 'MailUniversalSecurityGroup|Security') {
    throw "'$ScopeGroupName' is $($grp.RecipientTypeDetails), not a mail-enabled security group."
}

$rels = @(Get-OrganizationRelationship | Where-Object { $_.MailboxMovePublishedScopes })
if ($PartnerTenantId) { $rels = @($rels | Where-Object { $_.DomainNames -contains $PartnerTenantId }) }
$mine = @($rels | Where-Object { $_.MailboxMovePublishedScopes -contains $ScopeGroupName -or $_.MailboxMovePublishedScopes -contains "$($grp.PrimarySmtpAddress)" })
if (-not $mine) { throw "'$ScopeGroupName' is not in any organisation relationship's MailboxMovePublishedScopes." }
$otherScopes = @($rels | ForEach-Object { $_.MailboxMovePublishedScopes } | Where-Object { $_ -and $_ -ne $ScopeGroupName -and $_ -ne "$($grp.PrimarySmtpAddress)" })

$existingMembers = @{}
try { Get-DistributionGroupMember -Identity $ScopeGroupName -ResultSize Unlimited -ErrorAction Stop | ForEach-Object { $existingMembers["$($_.PrimarySmtpAddress)".ToLower()] = $true } }
catch { Write-Warning "Could not list members of ${ScopeGroupName}: $($_.Exception.Message)" }

$report = [System.Collections.Generic.List[object]]::new()
foreach ($u in $users) {
    $smtp = $u.SourcePrimarySmtp
    $row = [ordered]@{ SourcePrimarySmtp = $smtp; Action = ''; Note = '' }
    if ($existingMembers.ContainsKey($smtp.ToLower())) { $row.Action = 'Member'; $report.Add([pscustomobject]$row); continue }

    foreach ($other in $otherScopes) {
        $otherMembers = Get-DistributionGroupMember -Identity $other -ResultSize Unlimited -ErrorAction SilentlyContinue
        if ($otherMembers | Where-Object { "$($_.PrimarySmtpAddress)" -ieq $smtp }) {
            Write-Warning "$smtp is also in scope group '$other' - an object must not be in more than one published scope."
            $row.Note = "also in scope '$other'"
        }
    }
    if ($PSCmdlet.ShouldProcess($smtp, "Add-DistributionGroupMember -Identity $ScopeGroupName")) {
        try { Add-DistributionGroupMember -Identity $ScopeGroupName -Member $smtp -ErrorAction Stop; $row.Action = 'Added' }
        catch { $row.Action = 'Error'; $row.Note = ($row.Note + ' ' + $_.Exception.Message).Trim() }
    }
    else { $row.Action = 'WhatIf:Add' }
    $report.Add([pscustomobject]$row)
}

$out = New-OutputFolder -Customer $Customer -Phase '03-Identities'
$file = Join-Path $out 'ScopeGroupMembers.csv'
$report | Export-CsvSafe -Path $file
$report | Group-Object Action | Select-Object Name, Count | Format-Table -AutoSize | Out-Host
Write-Host "Report: $file" -ForegroundColor Green
