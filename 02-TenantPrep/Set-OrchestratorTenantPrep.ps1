#requires -Version 7.2
<#
.SYNOPSIS
    Configures the tenant-side prerequisites for Microsoft Migration Orchestrator, one step at a time.

.DESCRIPTION
    Implements the documented tenant-prep steps that are scriptable:
      - OrgRelationship   Source: create/verify the mail-enabled security scope group, then set the
                          org relationship (RemoteOutbound, DomainNames = target tenant GUID,
                          OAuthApplicationId = migration app ID, MailboxMovePublishedScopes).
                          Target: org relationship Inbound, DomainNames = source tenant GUID.
                          Enables organization customization when the tenant is dehydrated.
      - MigrationEndpoint Target only: New-MigrationEndpoint -RemoteServer outlook.office.com
                          -RemoteTenant <source onmicrosoft> -Credentials <PSCredential>
                          -ExchangeRemoteMove:$true -Name <name> -ApplicationId <app id>.
                          The app registration, secret and source-tenant admin consent are a manual
                          portal step (see README) - this script never creates apps or secrets.
      - TeamsFederation   Both: Set-CsTenantFederationConfiguration -AllowFederatedUsers $true
                          (plus -ExternalAccessWithTrialTenants Allowed with -TrialTenant).
      - OneDriveTrust     Both: Set-SPOCrossTenantRelationship -Scenario MnA -PartnerRole <other>
                          -PartnerCrossTenantHostUrl <url>, then Verify-SPOCrossTenantRelationship.
      - MigrationApps     Imports the CrossTenantMigration NuGet module (expanded from the package
                          downloaded from Microsoft Learn - not on PSGallery) and runs, per role:
                          target: Grant-CTMSAppPermissions, Set-CalendarRBACRoles;
                          both: Grant-OneDriveAppPermissions, Grant-CTTMAppPermissions,
                          Grant-MMSAppPermissions -TenantType source|target.

    Everything supports -WhatIf. Mailbox prep beyond the org relationship/endpoint (the doc's
    remaining manual steps) is described in the README.

.PARAMETER TenantId
    Tenant ID (GUID) of THIS tenant (connection asserted).

.PARAMETER AdminUpn
    Admin sign-in name in this tenant.

.PARAMETER Role
    Source or Target - which side of the pair this run configures.

.PARAMETER Step
    One or more of OrgRelationship, MigrationEndpoint, TeamsFederation, OneDriveTrust, MigrationApps.

.PARAMETER PartnerTenantId
    The other tenant's ID (GUID) - used in the org relationship DomainNames.

.PARAMETER ScopeGroupName
    Mail-enabled security group name that scopes migratable users (source only). Created if absent.

.PARAMETER ApplicationId
    Application (client) ID of the migration app registered in the target tenant (manual portal step).

.PARAMETER Credential
    PSCredential for the migration endpoint: username = application ID, password = the app secret.
    Prompted when MigrationEndpoint runs without it. Never stored or logged.

.PARAMETER EndpointName
    Name for the new migration endpoint on the target (default 'CrossTenantMigrationEndpoint').

.PARAMETER RemoteTenant
    Source tenant's onmicrosoft.com domain (target only, endpoint -RemoteTenant).

.PARAMETER AdminUrl
    SharePoint admin URL of this tenant (OneDriveTrust).

.PARAMETER PartnerCrossTenantHostUrl
    The partner tenant's cross-tenant host URL from Get-SPOCrossTenantHostURL (OneDriveTrust).

.PARAMETER TrialTenant
    Also allow external access with trial tenants (TeamsFederation).

.PARAMETER CrossTenantMigrationModulePath
    Path to the expanded CrossTenantMigration module (.nupkg expanded via Expand-Archive),
    e.g. .\CTModule\CrossTenantMigration. Required for -Step MigrationApps.

.EXAMPLE
    .\Set-OrchestratorTenantPrep.ps1 -Role Source -Step OrgRelationship -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' `
        -AdminUpn 'admin@contoso.com' -PartnerTenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' `
        -ScopeGroupName 'M365MigrationScope' -ApplicationId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -WhatIf

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Sources:
      https://learn.microsoft.com/en-us/microsoft-365/enterprise/cross-tenant-mailbox-migration
      https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-3-tenant-configuration
      https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration-step2
#>
[CmdletBinding(SupportsShouldProcess)]
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
    [ValidateSet('OrgRelationship', 'MigrationEndpoint', 'TeamsFederation', 'OneDriveTrust', 'MigrationApps')]
    [string[]]$Step,

    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$PartnerTenantId,

    [string]$ScopeGroupName,
    [ValidateScript({ -not $_ -or [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$ApplicationId,
    [pscredential]$Credential,
    [string]$EndpointName = 'CrossTenantMigrationEndpoint',
    [string]$RemoteTenant,
    [string]$AdminUrl,
    [string]$PartnerCrossTenantHostUrl,
    [switch]$TrialTenant,
    [string]$CrossTenantMigrationModulePath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force

function Enable-CustomizationIfDehydrated {
    $dehydrated = (Get-OrganizationConfig -ErrorAction SilentlyContinue).IsDehydrated
    if ($dehydrated -eq $true) {
        if ($PSCmdlet.ShouldProcess('tenant', 'Enable-OrganizationCustomization')) {
            Enable-OrganizationCustomization
        }
    }
}

foreach ($s in $Step) {
    switch ($s) {

        'OrgRelationship' {
            if (-not $PartnerTenantId) { throw 'OrgRelationship needs -PartnerTenantId.' }
            $null = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn
            Enable-CustomizationIfDehydrated

            if ($Role -eq 'Source') {
                if (-not $ScopeGroupName) { throw 'Source OrgRelationship needs -ScopeGroupName.' }
                if (-not $ApplicationId) { throw 'Source OrgRelationship needs -ApplicationId (the migration app consented in the source tenant).' }
                if (-not (Get-DistributionGroup -Identity $ScopeGroupName -ErrorAction SilentlyContinue)) {
                    if ($PSCmdlet.ShouldProcess($ScopeGroupName, 'New-DistributionGroup -Type Security (migration scope group)')) {
                        New-DistributionGroup -Type Security -Name $ScopeGroupName | Out-Null
                    }
                }
                $existing = Get-OrganizationRelationship | Where-Object { $_.DomainNames -contains $PartnerTenantId } | Select-Object -First 1
                if ($existing) {
                    if ($PSCmdlet.ShouldProcess($existing.Name, "Set-OrganizationRelationship -MailboxMoveCapability RemoteOutbound -OAuthApplicationId $ApplicationId -MailboxMovePublishedScopes $ScopeGroupName")) {
                        Set-OrganizationRelationship $existing.Name -Enabled:$true -MailboxMoveEnabled:$true -MailboxMoveCapability RemoteOutbound -OAuthApplicationId $ApplicationId -MailboxMovePublishedScopes $ScopeGroupName
                    }
                }
                elseif ($PSCmdlet.ShouldProcess("OrgRel-$PartnerTenantId", "New-OrganizationRelationship -MailboxMoveCapability RemoteOutbound -DomainNames $PartnerTenantId")) {
                    New-OrganizationRelationship "OrgRel-$PartnerTenantId" -Enabled:$true -MailboxMoveEnabled:$true -MailboxMoveCapability RemoteOutbound -DomainNames $PartnerTenantId -OAuthApplicationId $ApplicationId -MailboxMovePublishedScopes $ScopeGroupName
                }
            }
            else {
                $existing = Get-OrganizationRelationship | Where-Object { $_.DomainNames -contains $PartnerTenantId } | Select-Object -First 1
                if ($existing) {
                    if ($PSCmdlet.ShouldProcess($existing.Name, 'Set-OrganizationRelationship -MailboxMoveCapability Inbound')) {
                        Set-OrganizationRelationship $existing.Name -Enabled:$true -MailboxMoveEnabled:$true -MailboxMoveCapability Inbound
                    }
                }
                elseif ($PSCmdlet.ShouldProcess("OrgRel-$PartnerTenantId", "New-OrganizationRelationship -MailboxMoveCapability Inbound -DomainNames $PartnerTenantId")) {
                    New-OrganizationRelationship "OrgRel-$PartnerTenantId" -Enabled:$true -MailboxMoveEnabled:$true -MailboxMoveCapability Inbound -DomainNames $PartnerTenantId
                }
            }
        }

        'MigrationEndpoint' {
            if ($Role -ne 'Target') { throw 'MigrationEndpoint is a target-tenant step.' }
            if (-not $ApplicationId) { throw 'MigrationEndpoint needs -ApplicationId.' }
            if (-not $RemoteTenant) { throw 'MigrationEndpoint needs -RemoteTenant (source onmicrosoft.com domain).' }
            if (-not $Credential) { $Credential = Get-Credential -UserName $ApplicationId -Message 'Migration app secret (password field). Never stored.' }
            $null = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn
            Enable-CustomizationIfDehydrated
            if (Get-MigrationEndpoint -Identity $EndpointName -ErrorAction SilentlyContinue) {
                Write-Host "Migration endpoint '$EndpointName' already exists - leaving it." -ForegroundColor Yellow
            }
            elseif ($PSCmdlet.ShouldProcess($EndpointName, "New-MigrationEndpoint -RemoteServer outlook.office.com -RemoteTenant $RemoteTenant -ExchangeRemoteMove -ApplicationId $ApplicationId")) {
                New-MigrationEndpoint -RemoteServer outlook.office.com -RemoteTenant $RemoteTenant -Credentials $Credential -ExchangeRemoteMove:$true -Name $EndpointName -ApplicationId $ApplicationId | Out-Null
            }
        }

        'TeamsFederation' {
            $null = Connect-MigrationTeams -TenantId $TenantId -AdminUpn $AdminUpn
            $fedParams = @{ AllowFederatedUsers = $true }
            if ($TrialTenant) { $fedParams.ExternalAccessWithTrialTenants = 'Allowed' }
            if ($PSCmdlet.ShouldProcess($TenantId, "Set-CsTenantFederationConfiguration $(($fedParams.GetEnumerator() | ForEach-Object { "-$($_.Key) $($_.Value)" }) -join ' ')")) {
                Set-CsTenantFederationConfiguration @fedParams
            }
            Get-CsTenantFederationConfiguration | Format-List AllowFederatedUsers, ExternalAccessWithTrialTenants
        }

        'OneDriveTrust' {
            if (-not $AdminUrl -or -not $PartnerCrossTenantHostUrl) { throw 'OneDriveTrust needs -AdminUrl and -PartnerCrossTenantHostUrl.' }
            Connect-MigrationSharePoint -TenantId $TenantId -AdminUrl $AdminUrl
            $partnerRole = if ($Role -eq 'Source') { 'Target' } else { 'Source' }
            if ($PSCmdlet.ShouldProcess($TenantId, "Set-SPOCrossTenantRelationship -Scenario MnA -PartnerRole $partnerRole -PartnerCrossTenantHostUrl $PartnerCrossTenantHostUrl")) {
                Set-SPOCrossTenantRelationship -Scenario MnA -PartnerRole $partnerRole -PartnerCrossTenantHostUrl $PartnerCrossTenantHostUrl
            }
            Write-Host 'Verify the trust (step 3) - run after BOTH sides sent the request:' -ForegroundColor Yellow
            Verify-SPOCrossTenantRelationship -Scenario MnA -PartnerRole $partnerRole -PartnerCrossTenantHostUrl $PartnerCrossTenantHostUrl
        }

        'MigrationApps' {
            if (-not $CrossTenantMigrationModulePath) { throw 'MigrationApps needs -CrossTenantMigrationModulePath (expanded CrossTenantMigration.nupkg).' }
            if (-not (Test-Path $CrossTenantMigrationModulePath)) { throw "Module path not found: $CrossTenantMigrationModulePath" }
            # The module's required Graph scopes are undocumented; the set below is an assumption
            # (app/SP management + role assignment) - confirm in the technical test.
            $null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'RoleManagement.ReadWrite.Directory'
            $null = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn  # Grant-MMSAppPermissions assigns an Exchange role group
            Import-Module $CrossTenantMigrationModulePath -Force
            if ($Role -eq 'Target') {
                if ($PSCmdlet.ShouldProcess($TenantId, 'Grant-CTMSAppPermissions (target)')) { Grant-CTMSAppPermissions }
                if ($PSCmdlet.ShouldProcess($TenantId, 'Set-CalendarRBACRoles (target)')) { Set-CalendarRBACRoles }
            }
            if ($PSCmdlet.ShouldProcess($TenantId, 'Grant-OneDriveAppPermissions')) { Grant-OneDriveAppPermissions }
            if ($PSCmdlet.ShouldProcess($TenantId, 'Grant-CTTMAppPermissions')) { Grant-CTTMAppPermissions }
            if ($PSCmdlet.ShouldProcess($TenantId, "Grant-MMSAppPermissions -TenantType $($Role.ToLower())")) {
                Grant-MMSAppPermissions -TenantType $Role.ToLower()
            }
            # The module may have reconnected underneath us - re-assert the tenant before returning.
            $ctx = Get-MgContext
            Assert-TenantContext -ExpectedTenantId $TenantId -ActualTenantId "$($ctx.TenantId)"
        }
    }
}
