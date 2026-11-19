#requires -Version 7.2
<#
.SYNOPSIS
    Read-only: checks whether a tenant meets the Orchestrator tenant-prep prerequisites and reports
    Pass / Fail / Unknown per item.

.DESCRIPTION
    Run in each tenant with -Role Source or -Role Target before any prep step, and again afterwards
    to confirm. Checks (per role):
      - Organisation relationship to the partner tenant (DomainNames = partner tenant GUID,
        MailboxMoveEnabled, Inbound on target / RemoteOutbound + OAuthApplicationId +
        MailboxMovePublishedScopes on source)
      - Migration endpoint exists (target only, ExchangeRemoteMove)
      - Scope group is a mail-enabled security group listed in MailboxMovePublishedScopes (source)
      - Teams federation: AllowFederatedUsers (both tenants)
      - Microsoft.Graph / Microsoft.Graph.Beta module version alignment (doc: all same version,
        Beta >= 2.33.0)
      - Migration service principals present by display name where the Learn tenant-config page
        names them (heuristic name match - reported as Unknown when ambiguous)
      - A Cross-Tenant User Data Migration SKU exists in the tenant (heuristic on SkuPartNumber
        containing 'CROSS_TENANT' / 'USER_DATA_MIGRATION' - the exact SKU name is not documented;
        treat as Unknown-grade)
      - SPO cross-tenant trust via Verify-SPOCrossTenantRelationship (when
        -PartnerCrossTenantHostUrl is given)

    Output: a CSV row set (Check, Area, Result, Detail) written via Export-CsvSafe under
    customers/<Customer>/output/02-TenantPrep/ when -Customer is given, and echoed as a table.

.PARAMETER TenantId
    Tenant ID (GUID) of the tenant being checked (the connection is asserted against it).

.PARAMETER AdminUpn
    Admin sign-in name for Exchange Online / Graph / Teams in this tenant.

.PARAMETER Role
    Source or Target - selects which checks apply.

.PARAMETER PartnerTenantId
    The other tenant's ID (GUID); matched against the org relationship DomainNames.

.PARAMETER ScopeGroupName
    Name of the mail-enabled security group expected in MailboxMovePublishedScopes (source only).

.PARAMETER EndpointName
    Expected migration endpoint name (target only; any endpoint passes when omitted).

.PARAMETER AdminUrl
    SharePoint admin URL of this tenant, e.g. https://contoso-admin.sharepoint.com.
    Required for the SPO trust check.

.PARAMETER PartnerCrossTenantHostUrl
    The partner tenant's cross-tenant host URL (from Get-SPOCrossTenantHostURL on that tenant).
    Required for the SPO trust check.

.PARAMETER Customer
    When given, writes Test-OrchestratorPrereqs CSVs under customers/<Customer>/output/02-TenantPrep/.

.EXAMPLE
    .\Test-OrchestratorPrereqs.ps1 -Role Target -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' `
        -AdminUpn 'admin@fabrikam.com' -PartnerTenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -Customer fabrikam

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Sources:
      https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-3-tenant-configuration
      https://learn.microsoft.com/en-us/microsoft-365/enterprise/cross-tenant-mailbox-migration
      https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration-step2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [ValidateSet('Source', 'Target')]
    [string]$Role,

    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$PartnerTenantId,

    [string]$ScopeGroupName,
    [string]$EndpointName,
    [string]$AdminUrl,
    [string]$PartnerCrossTenantHostUrl,
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
$results = [System.Collections.Generic.List[object]]::new()
function Add-Check($Area, $Check, $Result, $Detail) {
    $results.Add([pscustomobject]@{ Area = $Area; Check = $Check; Result = $Result; Detail = $Detail })
    Write-Host ("[{0,-7}] {1}: {2} - {3}" -f $Result, $Area, $Check, $Detail)
}

# ------------------------------------------------------------ module versions (local, no sign-in)
$ga = @(Get-Module -ListAvailable 'Microsoft.Graph' | ForEach-Object { "$($_.Version)" } | Sort-Object {[version]$_} -Descending)
$beta = @(Get-Module -ListAvailable 'Microsoft.Graph.Beta' | ForEach-Object { "$($_.Version)" } | Sort-Object {[version]$_} -Descending)
if (-not $beta) {
    $betaAuth = @(Get-Module -ListAvailable 'Microsoft.Graph.Beta.Authentication' | ForEach-Object { "$($_.Version)" } | Sort-Object {[version]$_} -Descending)
    $beta = $betaAuth
}
if (-not $ga -or -not $beta) { Add-Check 'Modules' 'Graph/Beta alignment' 'Unknown' "Microsoft.Graph: $($ga -join ','), Beta: $($beta -join ',') - both must be installed, same version, Beta >= 2.33.0" }
elseif ($ga[0] -ne $beta[0]) { Add-Check 'Modules' 'Graph/Beta alignment' 'Fail' "Microsoft.Graph $($ga[0]) != Microsoft.Graph.Beta $($beta[0]) - the doc requires all Graph and Graph.Beta modules to be the same version" }
elseif ([version]$beta[0] -lt [version]'2.33.0') { Add-Check 'Modules' 'Graph/Beta alignment' 'Fail' "Microsoft.Graph.Beta $($beta[0]) is below the documented minimum 2.33.0" }
else { Add-Check 'Modules' 'Graph/Beta alignment' 'Pass' "Microsoft.Graph and Microsoft.Graph.Beta both $($ga[0])" }

# ------------------------------------------------------------ Exchange Online
$null = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn

$rels = @(Get-OrganizationRelationship -ErrorAction SilentlyContinue)
$rel = if ($PartnerTenantId) { $rels | Where-Object { $_.DomainNames -contains $PartnerTenantId } | Select-Object -First 1 }
       else { $rels | Where-Object { $_.MailboxMoveEnabled } | Select-Object -First 1 }
if (-not $rel) { Add-Check 'Exchange' 'Organisation relationship' 'Fail' 'None found (partner tenant GUID not present in DomainNames)' }
else {
    if ($Role -eq 'Target') {
        $capOk = "$($rel.MailboxMoveCapability)" -match 'Inbound'
        Add-Check 'Exchange' 'Organisation relationship' $(if ($rel.MailboxMoveEnabled -and $capOk) { 'Pass' } else { 'Fail' }) `
            "$($rel.Name): Enabled=$($rel.Enabled), MailboxMoveEnabled=$($rel.MailboxMoveEnabled), Capability=$($rel.MailboxMoveCapability) (target needs Inbound)"
    }
    else {
        $capOk = "$($rel.MailboxMoveCapability)" -match 'RemoteOutbound'
        $scopes = @($rel.MailboxMovePublishedScopes | ForEach-Object { "$_" })
        $oauth = "$($rel.OAuthApplicationId)"
        $ok = $rel.MailboxMoveEnabled -and $capOk -and $scopes.Count -gt 0 -and $oauth
        Add-Check 'Exchange' 'Organisation relationship' $(if ($ok) { 'Pass' } else { 'Fail' }) `
            "$($rel.Name): Capability=$($rel.MailboxMoveCapability) (source needs RemoteOutbound), OAuthApplicationId=$oauth, Scopes=$($scopes -join ',')"
        if ($ScopeGroupName) {
            $grp = Get-DistributionGroup -Identity $ScopeGroupName -ErrorAction SilentlyContinue
            if (-not $grp) { Add-Check 'Exchange' 'Scope group' 'Fail' "$ScopeGroupName not found" }
            else {
                $isSec = "$($grp.RecipientTypeDetails)" -match 'MailUniversalSecurityGroup|Security'
                $inScope = $scopes -contains $ScopeGroupName -or $scopes -contains "$($grp.PrimarySmtpAddress)"
                Add-Check 'Exchange' 'Scope group' $(if ($isSec -and $inScope) { 'Pass' } else { 'Fail' }) `
                    "${ScopeGroupName}: type=$($grp.RecipientTypeDetails), in MailboxMovePublishedScopes=$inScope"
            }
        }
    }
}

if ($Role -eq 'Target') {
    $eps = @(Get-MigrationEndpoint -ErrorAction SilentlyContinue | Where-Object { "$($_.EndpointType)" -match 'ExchangeRemoteMove' })
    if ($EndpointName) { $eps = @($eps | Where-Object { "$($_.Identity ?? $_.Name)" -eq $EndpointName }) }
    if ($eps) { Add-Check 'Exchange' 'Migration endpoint' 'Pass' "$($eps.Count) ExchangeRemoteMove endpoint(s): $(($eps | ForEach-Object { "$($_.Identity ?? $_.Name)" }) -join ', ')" }
    else { Add-Check 'Exchange' 'Migration endpoint' 'Fail' "No ExchangeRemoteMove migration endpoint$(if ($EndpointName) { " named $EndpointName" }) found" }
}

# ------------------------------------------------------------ Teams federation
try {
    $null = Connect-MigrationTeams -TenantId $TenantId -AdminUpn $AdminUpn
    $fed = Get-CsTenantFederationConfiguration -ErrorAction Stop
    Add-Check 'Teams' 'Federation' $(if ($fed.AllowFederatedUsers) { 'Pass' } else { 'Fail' }) `
        "AllowFederatedUsers=$($fed.AllowFederatedUsers), ExternalAccessWithTrialTenants=$($fed.ExternalAccessWithTrialTenants)"
}
catch { Add-Check 'Teams' 'Federation' 'Unknown' "Could not read Teams federation: $($_.Exception.Message)" }

# ------------------------------------------------------------ Graph: service principals + licence SKU
Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'Application.Read.All', 'Organization.Read.All'
$spNames = @(
    'CrossTenantMigration'          # CTMS app (target only per doc; checked in both)
    'Office 365 SharePoint Online'  # SPO resource app - always present, sanity anchor
    'Meeting Migration Service'     # MMS
    'Cross Tenant Teams Migration'  # CTTM
    'Identity Mapping'              # Resource Identity Mapping service
)
foreach ($n in $spNames) {
    $hit = Get-MgServicePrincipal -Filter "startsWith(displayName,'$n')" -All -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { Add-Check 'Graph' "SP: $n" 'Pass' "present ($($hit.DisplayName), appId $($hit.AppId))" }
    else { Add-Check 'Graph' "SP: $n" 'Unknown' "no service principal whose display name starts with '$n' - expected only after MigrationApps prep (Grant-* cmdlets); display names are heuristic" }
}
$skus = @(Get-MgSubscribedSku -All -ErrorAction SilentlyContinue | Where-Object { "$($_.SkuPartNumber)" -match 'CROSS.?TENANT|USER.?DATA.?MIGRATION|MIGRATION' })
if ($skus) { Add-Check 'Graph' 'Cross-Tenant licence SKU' 'Pass' "found: $(($skus | ForEach-Object SkuPartNumber) -join ', ')" }
else { Add-Check 'Graph' 'Cross-Tenant licence SKU' 'Unknown' "no SkuPartNumber matching a migration heuristic - the Cross-Tenant User Data Migration SKU name is not documented; verify purchase/licensing manually" }

# ------------------------------------------------------------ SPO trust
if ($AdminUrl -and $PartnerCrossTenantHostUrl) {
    try {
        Connect-MigrationSharePoint -TenantId $TenantId -AdminUrl $AdminUrl
        $partnerRole = if ($Role -eq 'Source') { 'Target' } else { 'Source' }
        $v = Verify-SPOCrossTenantRelationship -Scenario MnA -PartnerRole $partnerRole -PartnerCrossTenantHostUrl $PartnerCrossTenantHostUrl -ErrorAction Stop
        Add-Check 'SharePoint' 'Cross-tenant trust' 'Pass' "Verify-SPOCrossTenantRelationship ($partnerRole, $PartnerCrossTenantHostUrl): $v"
    }
    catch { Add-Check 'SharePoint' 'Cross-tenant trust' 'Fail' "Verify-SPOCrossTenantRelationship failed: $($_.Exception.Message)" }
}
else { Add-Check 'SharePoint' 'Cross-tenant trust' 'Unknown' 'Skipped - pass -AdminUrl and -PartnerCrossTenantHostUrl to check' }

# ------------------------------------------------------------ report
if ($Customer) {
    $out = New-OutputFolder -Customer $Customer -Phase '02-TenantPrep'
    $file = Join-Path $out "Prereqs-$Role.csv"
    $results | Export-CsvSafe -Path $file
    Write-Host "Report: $file" -ForegroundColor Cyan
}
$fails = @($results | Where-Object Result -eq 'Fail').Count
$unknowns = @($results | Where-Object Result -eq 'Unknown').Count
Write-Host ''
Write-Host "$fails Fail, $unknowns Unknown, $(@($results | Where-Object Result -eq 'Pass').Count) Pass." -ForegroundColor $(if ($fails) { 'Yellow' } else { 'Green' })
