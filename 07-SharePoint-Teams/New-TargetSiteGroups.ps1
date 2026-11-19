#requires -Version 7.2
<#
.SYNOPSIS
    Precreates the target Microsoft 365 groups that group-connected source SharePoint sites need
    for the native cross-tenant SharePoint migration - created the only way the doc allows.

.DESCRIPTION
    Cross-tenant SharePoint migration step 4 states target M365 groups for group-connected sites
    MUST be created with the Graph beta group resource and the ProvisionSiteOnDemand behaviour,
    and that the group's alias must equal the target site URL's last segment:

      New-MgBetaGroup -GroupTypes Unified -MailNickname <alias> -DisplayName <name>
          -ResourceBehaviorOptions ProvisionSiteOnDemand -MailEnabled:$false -SecurityEnabled:$false

    Groups created any other way make the migration fail. Plain (non-group) sites need NO
    precreation at all - a site that already exists on the target makes the move fail, so this
    script never calls New-SPOSite. Group names containing a '.' also fail (doc).

    Reads SiteMigrationPlan.csv rows with Track=Native and GroupConnected=True, and requires
    TargetGroupAlias (= last segment of TargetUrl).

.PARAMETER TenantId
    Target tenant ID (GUID).

.PARAMETER AdminUpn
    Target admin sign-in name.

.PARAMETER PlanCsv
    SiteMigrationPlan.csv from Get-SiteMigrationPlan.ps1, edited with TargetGroupAlias values.

.PARAMETER Customer
    Writes the run report under customers/<Customer>/output/07-SharePoint-Teams/.

.EXAMPLE
    .\New-TargetSiteGroups.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@fabrikam.com' -PlanCsv .\SiteMigrationPlan.csv -Customer contoso -WhatIf

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Sources:
      https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration-step4
      https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$PlanCsv,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

$rows = @(Import-Csv $PlanCsv | Where-Object { $_.Track -eq 'Native' -and "$($_.GroupConnected)" -eq 'True' })
if (-not $rows) { throw "No group-connected Native rows in $PlanCsv." }

$null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'Group.ReadWrite.All'

$log = [System.Collections.Generic.List[object]]::new()
function Add-Result($Obj, $Status, $Detail) {
    $log.Add([pscustomobject]@{ Object = $Obj; Status = $Status; Detail = $Detail })
    $c = @{ Created = 'Green'; Exists = 'Gray'; Refused = 'Red'; WhatIf = 'Cyan'; Problem = 'Red' }[$Status]
    Write-Host ("  [{0}] {1}: {2}" -f $Status, $Obj, $Detail) -ForegroundColor $c
}

foreach ($r in $rows) {
    $alias = "$($r.TargetGroupAlias)".Trim()
    $leaf = ("$($r.TargetUrl)" -replace '/$', '') -split '/' | Select-Object -Last 1
    if (-not $alias) { Add-Result $r.Url 'Refused' 'TargetGroupAlias is empty - set it in the plan CSV (must equal the last segment of TargetUrl)'; continue }
    if ($leaf -and $alias -ne $leaf) { Add-Result $r.Url 'Refused' "TargetGroupAlias '$alias' != last URL segment '$leaf' - the doc requires them to match"; continue }
    if ($r.Title -match '\.') { Add-Result $r.Url 'Refused' "Group display name '$($r.Title)' contains '.' - migration fails with 'Invalid character'"; continue }

    $existing = Get-MgBetaGroup -Filter "mailNickname eq '$alias'" -ErrorAction SilentlyContinue
    if ($existing) { Add-Result $r.Url 'Exists' "Group '$alias' already exists (id $($existing.Id)) - verify it was created with ProvisionSiteOnDemand"; continue }

    $display = if ($r.Title) { $r.Title } else { $alias }
    if ($PSCmdlet.ShouldProcess($alias, "New-MgBetaGroup (ProvisionSiteOnDemand) '$display'")) {
        try {
            $g = New-MgBetaGroup -GroupTypes 'Unified' -MailNickname $alias -DisplayName $display `
                -ResourceBehaviorOptions 'ProvisionSiteOnDemand' -MailEnabled:$false -SecurityEnabled:$false -ErrorAction Stop
            Add-Result $r.Url 'Created' "Group '$alias' id $($g.Id) - record it in the identity-mapping CSV (step 5)"
        }
        catch { Add-Result $r.Url 'Problem' $_.Exception.Message }
    }
    else { Add-Result $r.Url 'WhatIf' "Would create ProvisionSiteOnDemand group '$alias'" }
}

Write-Host ''
Write-Host 'Reminder: sites themselves must NOT be precreated on the target - a site that already exists makes the move fail.' -ForegroundColor Yellow
$out = New-OutputFolder -Customer $Customer -Phase '07-SharePoint-Teams'
$log | Export-CsvSafe -Path (Join-Path $out 'TargetSiteGroups.csv')
Write-Host "Report: $out" -ForegroundColor Cyan
