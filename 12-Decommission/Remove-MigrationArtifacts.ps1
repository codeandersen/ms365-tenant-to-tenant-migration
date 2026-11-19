#requires -Version 7.2
<#
.SYNOPSIS
    Removes the migration plumbing the Microsoft Learn post-migration page documents, one -Step
    at a time, after every batch has reached a terminal state.

.DESCRIPTION
    Implements the cleanup on "Post-migration steps when using migration orchestrator"
    (https://learn.microsoft.com/en-us/microsoft-365/enterprise/migration-orchestrator-6-post-migration):

      BatchData          (target) Remove-MgBetaCrossTenantMigrationJob per batch - deletes the
                         batch's migration data within 30 days. Destructive; only run when ALL
                         migrations between the tenants are complete.
      CtimData           Remove-CtimData -SourceTenantGuid (run with -Role Target) or
                         -TargetTenantGuid (run with -Role Source). Needs a session free of
                         Graph/EXO connections (the CTIM loopback issue) - the script refuses
                         while one is active, exactly like Invoke-CtimMapping.
      CtimServicePrincipal  Add-CtimServicePrincipal's counterpart Remove-CtimServicePrincipal
                         (fresh session via guarded Connect-MigrationGraph, disconnected after).
      OrgRelationship    (EXO, either role) Remove-OrganizationRelationship for the migration
                         relationship.
      MigrationEndpoint  (EXO, target) Remove-MigrationEndpoint.
      CtmsAppPermissions (target) Revoke-CTMSAppPermissions (NuGet module) + the doc's service-
                         principal cleanup for the CTMS/identity-mapping first-party apps.
      OneDriveTrust      NOT a step - see .NOTES: no removal cmdlet could be verified, so it is
                         README-documented only.

    Every destructive step first exports what it will remove to the customer output folder, and
    refuses to run while any migration job is not in a terminal state (Completed,
    CompletedWithErrors, Failed, Canceled, Deleted, PendingDelete) - Microsoft warns batch
    deletion affects future migrations, so the whole-tenant terminal check is applied to every
    step. Runs that cannot check batch state themselves (any -Role Source run, and the
    session-free CTIM steps) require -AllBatchesTerminalConfirmed instead.

.PARAMETER TenantId
    Tenant ID (GUID) of the tenant this run operates on (-Role says which side that is).

.PARAMETER AdminUpn
    Admin sign-in name for -TenantId.

.PARAMETER Role
    Source or Target - which tenant the run acts in.

.PARAMETER Step
    One or more of: BatchData, CtimData, CtimServicePrincipal, OrgRelationship,
    MigrationEndpoint, CtmsAppPermissions.

.PARAMETER SourceTenantId / TargetTenantId
    Needed by the CtimData step: the partner tenant's GUID (-SourceTenantGuid on the target side,
    -TargetTenantGuid on the source side).

.PARAMETER Customer
    Output goes under customers/<Customer>/output/12-Decommission/.

.PARAMETER AllBatchesTerminalConfirmed
    Mandatory confirmation for runs that cannot check batch state themselves: every -Role
    Source run and the session-free CTIM steps (CtimData, CtimServicePrincipal). Pass it only
    after verifying all batches are terminal - e.g. with -Role Target or
    05-Batches/Get-BatchStatus.ps1 in the target tenant.

.EXAMPLE
    .\Remove-MigrationArtifacts.ps1 -TenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -AdminUpn 'admin@fabrikam.onmicrosoft.com' `
        -Role Target -Step BatchData, CtimData, OrgRelationship, MigrationEndpoint, CtmsAppPermissions `
        -SourceTenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -Customer contoso -WhatIf

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    The doc additionally covers: Teams Meetings app and Mailbox app service principals - removed
    in the Microsoft 365 admin centre (manual, documented in the README); and source "user
    cleanup" (migrated users remain as MailUsers - remove or keep per business decision).
    OneDrive trust removal: the installed Microsoft.Online.SharePoint.PowerShell exposes
    Set-SPOCrossTenantRelationship with no -Enabled/-Remove parameter, so no verifiable cmdlet
    exists here - follow Step 7 of the cross-tenant OneDrive doc in the README instead.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [ValidateSet('Source', 'Target')]
    [string]$Role,

    [Parameter(Mandatory)]
    [ValidateSet('BatchData', 'CtimData', 'CtimServicePrincipal', 'OrgRelationship', 'MigrationEndpoint', 'CtmsAppPermissions')]
    [string[]]$Step,

    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })][string]$SourceTenantId,
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })][string]$TargetTenantId,

    [Parameter(Mandatory)]
    [string]$Customer,

    [switch]$AllBatchesTerminalConfirmed
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force
$outDir = New-OutputFolder -Customer $Customer -Phase '12-Decommission'
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'

$exoSteps = @('OrgRelationship', 'MigrationEndpoint')
$targetOnly = @('CtmsAppPermissions', 'BatchData', 'MigrationEndpoint')
foreach ($s in $Step) {
    if ($Role -eq 'Source' -and $targetOnly -contains $s) { throw "$s is a target-side step. Rerun with -Role Target against the target tenant." }
}

# ------------------------------------------------------------ terminal-state guard
# The doc: "Only batches in a terminal state can be canceled" and batch-data deletion is meant
# for after ALL migrations complete - so every step waits for every job to be terminal.
$terminal = 'Completed', 'CompletedWithErrors', 'Failed', 'Canceled', 'Deleted', 'PendingDelete'
# Runs that can't check batch state themselves (any source-side step, and the session-free CTIM
# steps) need an explicit admin confirmation instead of the self-check.
$sessionFreeSteps = 'CtimData', 'CtimServicePrincipal'
$needsConfirm = ($Role -eq 'Source') -or (@($Step | Where-Object { $sessionFreeSteps -contains $_ }).Count -gt 0)
if ($needsConfirm -and -not $AllBatchesTerminalConfirmed) {
    throw "This run cannot check migration batch state itself ($Role-side or session-free CTIM step). First confirm every batch is terminal - run this script with -Role Target, or 05-Batches/Get-BatchStatus.ps1, in the target tenant - then rerun with -AllBatchesTerminalConfirmed."
}
$selfCheckSteps = @($Step | Where-Object { $sessionFreeSteps -notcontains $_ })
if ($selfCheckSteps.Count -and $Role -eq 'Target') {
    $null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'CrossTenantContentMigration.Read.All'
    $jobs = @(Get-MgBetaCrossTenantMigrationJob -All -ErrorAction SilentlyContinue)
    $open = @($jobs | Where-Object { "$((Get-GraphValue -Object $_ -Name 'status'))" -notin $terminal })
    if ($open) {
        $names = ($open | ForEach-Object { "$(Get-GraphValue -Object $_ -Name 'displayName') ($(Get-GraphValue -Object $_ -Name 'status'))" }) -join ', '
        throw "Refusing to remove migration artifacts while batches are not terminal: $names"
    }
    Write-Host "All $($jobs.Count) migration job(s) are terminal." -ForegroundColor Green
}

# ------------------------------------------------------------ BatchData (target)
if ($Step -contains 'BatchData') {
    $null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'CrossTenantContentMigration.ReadWrite.All'
    $jobs = @(Get-MgBetaCrossTenantMigrationJob -All)
    $jobs | ForEach-Object {
        [pscustomobject]@{ DisplayName = Get-GraphValue -Object $_ -Name 'displayName'; Id = Get-GraphValue -Object $_ -Name 'id'; Status = Get-GraphValue -Object $_ -Name 'status' }
    } | Export-CsvSafe -Path (Join-Path $outDir "Export-Batches-$stamp.csv")
    foreach ($j in $jobs) {
        $jid = "$(Get-GraphValue -Object $j -Name 'id')"; $jname = "$(Get-GraphValue -Object $j -Name 'displayName')"
        if ($PSCmdlet.ShouldProcess($jname, 'Remove-MgBetaCrossTenantMigrationJob (deletes batch data within 30 days)')) {
            Remove-MgBetaCrossTenantMigrationJob -CrossTenantMigrationJobId $jid
            Write-Host "  Removed batch '$jname'" -ForegroundColor Green
        }
    }
}

# ------------------------------------------------------------ CtimData (fresh-session rule)
if ($Step -contains 'CtimData') {
    $hasSession = $false
    if (Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue) {
        $hasSession = [bool](Get-ConnectionInformation -ErrorAction SilentlyContinue | Where-Object State -eq 'Connected')
    }
    if (-not $hasSession -and (Get-Command Get-MgContext -ErrorAction SilentlyContinue)) {
        $hasSession = [bool](Get-MgContext)
    }
    if ($hasSession) { throw 'CtimData must run in a session with NO Exchange Online or Graph connection (CTIM loopback issue). Start a fresh pwsh and run this step alone.' }
    $partner = if ($Role -eq 'Target') { $SourceTenantId } else { $TargetTenantId }
    if (-not $partner) { throw "CtimData needs the partner tenant GUID: pass -SourceTenantId (target role) or -TargetTenantId (source role)." }
    if (-not (Get-Command Remove-CtimData -ErrorAction SilentlyContinue)) { throw 'CrossTenantIdentityMapping module not loaded (Install-Module CrossTenantIdentityMapping -AllowPrerelease).' }
    $p = @{ }; if ($Role -eq 'Target') { $p.SourceTenantGuid = $partner } else { $p.TargetTenantGuid = $partner }
    if ($PSCmdlet.ShouldProcess("CTIM mapping data ($Role side, partner $partner)", 'Remove-CtimData')) {
        Remove-CtimData @p
        Write-Host "  CTIM data removed ($Role side)" -ForegroundColor Green
    }
}

# ------------------------------------------------------------ CtimServicePrincipal
if ($Step -contains 'CtimServicePrincipal') {
    if (-not (Get-Command Remove-CtimServicePrincipal -ErrorAction SilentlyContinue)) { throw 'CrossTenantIdentityMapping module not loaded.' }
    $null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'Application.ReadWrite.All'
    try {
        if ($PSCmdlet.ShouldProcess("CTIM service principal ($Role)", 'Remove-CtimServicePrincipal')) {
            Remove-CtimServicePrincipal
            Write-Host '  CTIM service principal removed' -ForegroundColor Green
        }
    }
    finally { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
}

# ------------------------------------------------------------ EXO steps
if (@($Step | Where-Object { $exoSteps -contains $_ }).Count) {
    $null = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn
}
if ($Step -contains 'OrgRelationship') {
    $rels = @(Get-OrganizationRelationship -ErrorAction SilentlyContinue)
    $rels | Export-CsvSafe -Path (Join-Path $outDir "Export-OrgRelationships-$stamp.csv")
    foreach ($r in $rels) {
        if ($PSCmdlet.ShouldProcess("Organization relationship '$($r.Name)' ($($r.DomainNames -join ','))", 'Remove-OrganizationRelationship')) {
            Remove-OrganizationRelationship -Identity $r.Identity -Confirm:$false
            Write-Host "  Removed relationship '$($r.Name)'" -ForegroundColor Green
        }
    }
    if (-not $rels) { Write-Host '  No organization relationships found.' -ForegroundColor Gray }
}
if ($Step -contains 'MigrationEndpoint') {
    $eps = @(Get-MigrationEndpoint -ErrorAction SilentlyContinue)
    $eps | Export-CsvSafe -Path (Join-Path $outDir "Export-MigrationEndpoints-$stamp.csv")
    foreach ($e in $eps) {
        if ($PSCmdlet.ShouldProcess("Migration endpoint '$($e.Identity)'", 'Remove-MigrationEndpoint')) {
            Remove-MigrationEndpoint -Identity $e.Identity -Confirm:$false
            Write-Host "  Removed endpoint '$($e.Identity)'" -ForegroundColor Green
        }
    }
    if (-not $eps) { Write-Host '  No migration endpoints found.' -ForegroundColor Gray }
}

# ------------------------------------------------------------ CtmsAppPermissions (target, per the doc's sample)
if ($Step -contains 'CtmsAppPermissions') {
    if (Get-Command Revoke-CTMSAppPermissions -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess('CTMS app permissions', 'Revoke-CTMSAppPermissions')) {
            Revoke-CTMSAppPermissions
            Write-Host '  CTMS app permissions revoked' -ForegroundColor Green
        }
    }
    else { Write-Warning 'Revoke-CTMSAppPermissions not found (CrossTenantMigration NuGet module not loaded) - running the documented SP cleanup only.' }
    $null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'Application.ReadWrite.All'
    # First-party IDs published on the Learn post-migration page.
    $ctimAppId = '90fb47fc-e46d-4fc5-9833-8517359f2daf'   # Identity Mapping 1P app
    $permissionId = '42eb8f30-cb38-433e-9651-006680f3b238' # IdentityMapping-Experimental-Internal.Read
    $ctmsCandidates = '506cf32b-5cbe-4ced-84c6-c7bde303f77c', '6eda910c-74a9-491b-bda3-88692d503655'
    $fpAppSp = Get-MgServicePrincipal -Filter "appId eq '$ctimAppId'" -ErrorAction SilentlyContinue
    foreach ($ctmsAppId in $ctmsCandidates) {
        $ctmsSp = Get-MgServicePrincipal -Filter "appId eq '$ctmsAppId'" -ErrorAction SilentlyContinue
        if (-not $ctmsSp) { continue }
        if ($fpAppSp) {
            $ctmsRole = @(Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $fpAppSp.Id | Where-Object { $_.PrincipalId -eq $ctmsSp.Id -and $_.AppRoleId -eq $permissionId })
            foreach ($r in $ctmsRole) {
                if ($PSCmdlet.ShouldProcess("app role assignment $($r.Id) on Identity Mapping SP", 'Remove-MgServicePrincipalAppRoleAssignedTo')) {
                    Remove-MgServicePrincipalAppRoleAssignedTo -AppRoleAssignmentId $r.Id -ServicePrincipalId $fpAppSp.Id
                }
            }
        }
        if ($PSCmdlet.ShouldProcess("CTMS service principal $ctmsAppId", 'Remove-MgServicePrincipal')) {
            Remove-MgServicePrincipal -ServicePrincipalId $ctmsSp.Id
            Write-Host "  Removed CTMS service principal $ctmsAppId" -ForegroundColor Green
        }
    }
    Write-Warning 'Teams Meetings app and Mailbox app permissions are removed in the Microsoft 365 admin centre (manual step - see README).'
}
