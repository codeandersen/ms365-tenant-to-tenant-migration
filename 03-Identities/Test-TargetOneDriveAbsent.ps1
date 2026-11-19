#requires -Version 7.2
<#
.SYNOPSIS
    Read-only: reports which of the listed target users already have a OneDrive (personal site)
    in the target tenant - they must have none before migration.

.DESCRIPTION
    The Orchestrator docs require that target users do not have OneDrive sites provisioned before
    migration ("You should disable OneDrive site creation for target users as soon as you create
    those users"). Microsoft documents disabling personal-site creation only via the SharePoint
    admin centre (User Profile > Manage User Permissions - see README), not via a supported
    PowerShell cmdlet, so this playbook ships a checker instead of a changer.

    It lists the tenant's personal sites once
    (Get-SPOSite -IncludePersonalSite $true -Limit All -Filter "Url -like '-my.sharepoint.com/personal/'")
    and matches each site's Owner to a TargetUpn, case-insensitively. The derived my-site URL is
    kept as an informational column only - UPN-to-URL mangling is unreliable (collisions get
    numeric suffixes).

.PARAMETER TenantId
    Target tenant ID (GUID). The SPO connection is asserted against it (via the admin URL's
    tenant prefix resolved through openid-configuration).

.PARAMETER AdminUpn
    Target SharePoint admin sign-in name. (Used for the connection context record; SPO signs in
    via Connect-SPOService's own prompt/browser flow.)

.PARAMETER AdminUrl
    SharePoint admin URL of the target tenant, e.g. https://fabrikam-admin.sharepoint.com.

.PARAMETER UserListPath
    Path to migration-users.csv.

.PARAMETER Customer
    Writes the report CSV under customers/<Customer>/output/03-Identities/.

.EXAMPLE
    .\Test-TargetOneDriveAbsent.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@fabrikam.com' `
        -AdminUrl 'https://fabrikam-admin.sharepoint.com' `
        -UserListPath .\customers\fabrikam\migration-users.csv -Customer fabrikam

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Sources:
      https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-4-user-prep
      https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$AdminUrl,

    [Parameter(Mandatory)]
    [string]$UserListPath,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

$users = @(Import-MigrationUserList -Path $UserListPath)
Connect-MigrationSharePoint -TenantId $TenantId -AdminUrl $AdminUrl

$sites = @(Get-SPOSite -IncludePersonalSite $true -Limit All -Filter "Url -like '-my.sharepoint.com/personal/'" -ErrorAction Stop)
$byOwner = @{}
foreach ($s in $sites) { $byOwner["$($s.Owner)".ToLower()] = $s }

$report = [System.Collections.Generic.List[object]]::new()
foreach ($u in $users) {
    $upn = "$($u.TargetUpn)".ToLower()
    $hit = $byOwner[$upn]
    $mangled = $upn -replace '[.@_]', '_' -replace '_+', '_'
    $myHost = $AdminUrl -replace '^https://', '' -replace '-admin\.sharepoint\.com/?$', '-my.sharepoint.com'
    $report.Add([pscustomobject]@{
        TargetUpn      = $u.TargetUpn
        OneDrive       = if ($hit) { 'Found' } else { 'NotFound' }
        InformationalUrl = "https://$myHost/personal/$mangled"
        Detail         = if ($hit) { "personal site exists ($($hit.Url)) - migration of ODSP will fail for this user" } else { '' }
    })
}

$found = @($report | Where-Object OneDrive -eq 'Found')
$report | Format-Table -AutoSize | Out-Host
if ($found) {
    Write-Host "$($found.Count) target user(s) already have a OneDrive - remove/rename those sites or exclude the users before migration." -ForegroundColor Yellow
}
else { Write-Host 'No personal sites found for the listed target users.' -ForegroundColor Green }

$out = New-OutputFolder -Customer $Customer -Phase '03-Identities'
$file = Join-Path $out 'TargetOneDriveCheck.csv'
$report | Export-CsvSafe -Path $file
Write-Host "Report: $file" -ForegroundColor Cyan
