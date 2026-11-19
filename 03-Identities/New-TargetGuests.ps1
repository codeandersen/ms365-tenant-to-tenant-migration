#requires -Version 7.2
<#
.SYNOPSIS
    Creates or maps guests in the TARGET tenant from a source-guests.csv export.

.DESCRIPTION
    Per source guest (Export-SourceGuests.ps1):
      - the guest's mail domain is a verified domain of the target tenant AND a target
        member with that mail/UPN exists -> mapped to that member (TargetType=Member,
        no invitation). This covers target employees who were guests in the source.
      - an existing target guest with the same mail -> reused.
      - otherwise -> invited via New-MgInvitation (POST /invitations). No invitation
        mail is sent by default (-SendInvitationMessage $false); use the
        -SendInvitationMessage switch (and optional -InvitedUserMessage) to send it.
        Without a mail, the guest redeems on first access to a shared resource
        [Playbook assumption - verify in pilot; not all Learn sources state it].

    Writes guest-map.csv (SourceGuestUpn, SourceMail, TargetUserId, TargetUpn,
    TargetMail, TargetType Guest|Member, Action) under
    customers/<Customer>/output/03-Identities/. Consumed by New-TargetGroups.ps1 and
    New-SpoIdentityMap.ps1.

    https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration-step4
    https://learn.microsoft.com/en-us/graph/api/invitation-post

.PARAMETER TenantId
    Target tenant ID (GUID).

.PARAMETER AdminUpn
    Target admin sign-in name.

.PARAMETER GuestsCsv
    source-guests.csv from Export-SourceGuests.ps1.

.PARAMETER Customer
    Output under customers/<Customer>/output/03-Identities/.

.PARAMETER InviteRedirectUrl
    Where the guest lands after redemption. Default myapps for this tenant.

.PARAMETER SendInvitationMessage
    Actually e-mail the invitation (default: off).

.PARAMETER InvitedUserMessage
    Optional custom message text when -SendInvitationMessage is used.

.PARAMETER Only / Exclude
    Optional filters on SourceMail/UserPrincipalName.

.EXAMPLE
    .\New-TargetGuests.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@fabrikam.com' `
        -GuestsCsv .\customers\contoso\output\03-Identities\<stamp>\source-guests.csv -Customer contoso -WhatIf

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
    [string]$GuestsCsv,

    [Parameter(Mandatory)]
    [string]$Customer,

    [string]$InviteRedirectUrl,

    [switch]$SendInvitationMessage,

    [string]$InvitedUserMessage,

    [string[]]$Only,

    [string[]]$Exclude
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force

$guests = @(Import-Csv $GuestsCsv)
if ($Only)    { $keep = @($Only    | ForEach-Object { "$_".ToLower() }); $guests = @($guests | Where-Object { $keep -contains "$($_.Mail)".ToLower() -or $keep -contains "$($_.UserPrincipalName)".ToLower() }) }
if ($Exclude) { $skip = @($Exclude | ForEach-Object { "$_".ToLower() }); $guests = @($guests | Where-Object { $skip -notcontains "$($_.Mail)".ToLower() -and $skip -notcontains "$($_.UserPrincipalName)".ToLower() }) }
if (-not $guests.Count) { throw 'No guests to process.' }

$null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'User.ReadWrite.All', 'Domain.Read.All'
if (-not $InviteRedirectUrl) { $InviteRedirectUrl = "https://myapps.microsoft.com/?tenantid=$TenantId" }

$domains = @(Get-MgDomain -All | Where-Object IsVerified | ForEach-Object { "$($_.Id)".ToLower() })
$report  = [System.Collections.Generic.List[object]]::new()

foreach ($g in $guests) {
    $mail  = "$($g.Mail)".Trim()
    $dom   = ($mail -split '@')[-1].ToLower()
    $row = [pscustomobject]@{
        SourceGuestUpn = $g.UserPrincipalName
        SourceMail     = $mail
        TargetUserId   = ''
        TargetUpn      = ''
        TargetMail     = $mail
        TargetType     = ''
        Action         = ''
    }

    $existing = $null
    try { $existing = @(Get-MgUser -Filter "mail eq '$mail'" -Property 'id,userPrincipalName,mail,userType' -ErrorAction Stop) } catch {}
    if (-not $existing) { try { $existing = @(Get-MgUser -Filter "userPrincipalName eq '$mail'" -Property 'id,userPrincipalName,mail,userType' -ErrorAction Stop) } catch {} }

    if ($existing) {
        $t = $existing[0]
        $row.TargetUserId = $t.Id; $row.TargetUpn = $t.UserPrincipalName
        $row.TargetType   = $t.UserType
        $row.Action       = "MappedToExisting$($t.UserType)"
        $report.Add($row); continue
    }

    if ($domains -contains $dom) {
        $row.Action = 'Skipped'
        $row.TargetType = 'Member'
        $row.TargetUpn  = ''
        $report.Add($row)
        Write-Warning "$mail is on a verified target domain but no target user was found - skipped (should not happen)."
        continue
    }

    if (-not $PSCmdlet.ShouldProcess($mail, 'Invite guest')) {
        $row.Action = 'WhatIf'; $row.TargetType = 'Guest'
        $report.Add($row); continue
    }

    try {
        $body = @{
            invitedUserEmailAddress = $mail
            invitedUserDisplayName  = "$($g.DisplayName)"
            inviteRedirectUrl       = $InviteRedirectUrl
            sendInvitationMessage   = [bool]$SendInvitationMessage
        }
        if ($InvitedUserMessage) { $body['invitedUserMessageInfo'] = @{ customizedMessageBody = $InvitedUserMessage } }
        $inv = New-MgInvitation -BodyParameter $body -ErrorAction Stop
        $row.TargetUserId = $inv.InvitedUser.Id
        $row.TargetUpn    = $inv.InvitedUser.UserPrincipalName
        $row.TargetType   = 'Guest'
        $row.Action       = 'Invited'
    } catch {
        $row.Action = 'Problem'
        Write-Warning "Invite failed for $mail : $($_.Exception.Message)"
    }
    $report.Add($row)
}

$out = New-OutputFolder -Customer $Customer -Phase '03-Identities'
$path = Join-Path $out 'guest-map.csv'
$report | Export-CsvSafe -Path $path
$report | Format-Table TargetType, Action -AutoSize
Write-Host "Guest map written to $path" -ForegroundColor Green
