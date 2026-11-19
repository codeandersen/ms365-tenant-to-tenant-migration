#requires -Version 7.2
<#
.SYNOPSIS
    Exports all guest users from the SOURCE tenant for the target guest mapping.

.DESCRIPTION
    Read-only. Lists every user with userType 'Guest' from Microsoft Graph and writes
    source-guests.csv under customers/<Customer>/output/03-Identities/: Id,
    UserPrincipalName (the #EXT# form), Mail, DisplayName, ExternalUserState,
    CreatedDateTime and LastSignInDateTime (signInActivity - blank when the tenant
    lacks Entra ID P1; same fallback as the inventory collector).

    The companion New-TargetGuests.ps1 turns this file into guest invitations or
    member mappings, and New-SpoIdentityMap.ps1 consumes guest-map.csv so guests keep
    their OneDrive/SharePoint permissions.
    https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration-step4

.PARAMETER TenantId
    Source tenant ID (GUID).

.PARAMETER AdminUpn
    Source admin sign-in name (asserted after connect).

.PARAMETER Customer
    Writes under customers/<Customer>/output/03-Identities/.

.EXAMPLE
    .\Export-SourceGuests.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@contoso.com' -Customer contoso

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

$null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'User.Read.All', 'AuditLog.Read.All'

$baseProps = 'id,displayName,userPrincipalName,mail,userType,externalUserState,externalUserStateChangeDateTime,createdDateTime'
$signInOk = $true
try {
    $guests = @(Get-GraphAll -Uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=$baseProps,signInActivity&`$top=999")
} catch {
    # signInActivity needs AuditLog.Read.All + Entra ID P1 - fall back without it
    Write-Warning "signInActivity not available ($($_.Exception.Message)) - last sign-in column left blank."
    $signInOk = $false
    $guests = @(Get-GraphAll -Uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=$baseProps&`$top=999")
}

$rows = foreach ($g in $guests) {
    $lastSignIn = $null
    if ($signInOk) {
        $lastSignIn = $g.signInActivity.lastSignInDateTime
        if (-not $lastSignIn) { $lastSignIn = $g.signInActivity.lastNonInteractiveSignInDateTime }
    }
    [pscustomobject]@{
        Id                       = $g.id
        UserPrincipalName        = $g.userPrincipalName
        Mail                     = $g.mail
        DisplayName              = $g.displayName
        ExternalUserState        = "$($g.externalUserState)"
        CreatedDateTime          = $g.createdDateTime
        LastSignInDateTime       = $lastSignIn
    }
}

$out = New-OutputFolder -Customer $Customer -Phase '03-Identities'
$path = Join-Path $out 'source-guests.csv'
$rows | Export-CsvSafe -Path $path -Header 'Id','UserPrincipalName','Mail','DisplayName','ExternalUserState','CreatedDateTime','LastSignInDateTime'
Write-Host "$($rows.Count) guest(s) written to $path" -ForegroundColor Green
