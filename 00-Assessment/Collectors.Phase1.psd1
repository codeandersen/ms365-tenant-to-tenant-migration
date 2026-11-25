# Phase 1 collector registry additions (see Collectors.psd1 for the field schema).
# Split out because Import-PowerShellDataFile caps a data file at 132 objects.
@{
    Collectors = @(
        # ---- Phase 1: Entra tenant config ----
        @{ Name='AuthorizationPolicy'; Section='Tenant'; ServiceGroup='Graph'; Level='Basic'; Workstream='Governance'; Workload='Entra ID policies';
           Output='AuthorizationPolicy.csv'; Endpoint='GET /policies/authorizationPolicy'; ApiVersion='v1.0';
           DelegatedPermissions=@('Policy.Read.All'); ApplicationPermissions=@('Policy.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/authorizationpolicy-get'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='AdminConsentRequestPolicy'; Section='Tenant'; ServiceGroup='Graph'; Level='Basic'; Workstream='Governance'; Workload='Entra ID policies';
           Output='AdminConsentRequestPolicy.csv'; Endpoint='GET /policies/adminConsentRequestPolicy'; ApiVersion='v1.0';
           DelegatedPermissions=@('Policy.Read.All'); ApplicationPermissions=@('Policy.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/adminconsentrequestpolicy-get'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='GroupSettings'; Section='Security'; ServiceGroup='Graph'; Level='Basic'; Workstream='Governance'; Workload='Entra ID policies';
           Output='GroupSettings.csv'; Endpoint='GET /groupSettings'; ApiVersion='v1.0';
           DelegatedPermissions=@('Directory.Read.All'); ApplicationPermissions=@('Directory.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/groupsetting-list'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='GroupLifecyclePolicies'; Section='Security'; ServiceGroup='Graph'; Level='Basic'; Workstream='Governance'; Workload='Groups';
           Output='GroupLifecyclePolicies.csv'; Endpoint='GET /groupLifecyclePolicies'; ApiVersion='v1.0';
           DelegatedPermissions=@('Directory.Read.All'); ApplicationPermissions=@('Directory.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/grouplifecyclepolicy-list'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='CrossTenantAccessPolicy'; Section='Tenant'; ServiceGroup='Graph'; Level='Basic'; Workstream='Security'; Workload='Cross-tenant access';
           Output='CrossTenantAccessPolicy.csv'; Endpoint='GET /policies/crossTenantAccessPolicy + /partners'; ApiVersion='v1.0';
           DelegatedPermissions=@('Policy.Read.All'); ApplicationPermissions=@('Policy.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/crosstenantaccesspolicy-list-partners'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='AdministrativeUnits'; Section='Tenant'; ServiceGroup='Graph'; Level='Basic'; Workstream='Identity'; Workload='Roles and admins';
           Output='AdministrativeUnits.csv'; Endpoint='GET /directory/administrativeUnits + /members/$count'; ApiVersion='v1.0';
           DelegatedPermissions=@('AdministrativeUnit.Read.All'); ApplicationPermissions=@('AdministrativeUnit.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/administrativeunit-list'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='DelegatedAdminRelationships'; Section='Tenant'; ServiceGroup='Graph'; Level='Basic'; Workstream='Governance'; Workload='Partner access (GDAP)';
           Output='DelegatedAdminRelationships.csv'; Endpoint='GET /tenantRelationships/delegatedAdminRelationships'; ApiVersion='v1.0';
           DelegatedPermissions=@('DelegatedAdminRelationship.Read.All'); ApplicationPermissions=@('DelegatedAdminRelationship.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/tenantrelationship-list-delegatedadminrelationships'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='GroupDetails'; Section='Groups'; ServiceGroup='Graph'; Level='Advanced'; Workstream='Collaboration'; Workload='Groups';
           Output='GroupDetails.csv'; Endpoint='GET /groups/{id}/members/$count + /owners'; ApiVersion='v1.0';
           DelegatedPermissions=@('Group.Read.All'); ApplicationPermissions=@('Group.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/group-get-members'; ValidationStatus='NotValidatedLive'; KnownLimitations='Per-group calls; owners capped at first page' }
        @{ Name='AuthStrengths'; Section='Security'; ServiceGroup='Graph'; Level='Basic'; Workstream='Security'; Workload='Authentication';
           Output='AuthStrengths.csv'; Endpoint='GET /policies/authenticationStrengthPolicies'; ApiVersion='v1.0';
           DelegatedPermissions=@('Policy.Read.All'); ApplicationPermissions=@('Policy.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/authenticationstrengthpolicy-list'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='CustomDirectoryRoles'; Section='Security'; ServiceGroup='Graph'; Level='Basic'; Workstream='Identity'; Workload='Roles and admins';
           Output='CustomDirectoryRoles.csv'; Endpoint='GET /roleManagement/directory/roleDefinitions?$filter=isBuiltIn eq false'; ApiVersion='v1.0';
           DelegatedPermissions=@('RoleManagement.Read.Directory'); ApplicationPermissions=@('RoleManagement.Read.Directory');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/unifiedroledefinition-list'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='PimAssignments'; Section='Security'; ServiceGroup='Graph'; Level='Basic'; Workstream='Security'; Workload='PIM';
           Output=''; Endpoint='GET /roleManagement/directory/roleEligibilitySchedules + /roleAssignmentSchedules'; ApiVersion='v1.0';
           DelegatedPermissions=@('RoleAssignmentSchedule.Read.Directory','RoleEligibilitySchedule.Read.Directory'); ApplicationPermissions=@('RoleAssignmentSchedule.Read.Directory','RoleEligibilitySchedule.Read.Directory');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence='Entra ID P2'; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/rolemanagement-directory-list-roleeligibilityschedules'; ValidationStatus='NotValidatedLive'; KnownLimitations='Requires Entra ID P2 (AAD_PREMIUM_P2)' }
        @{ Name='AppOwners'; Section='Apps'; ServiceGroup='Graph'; Level='Basic'; Workstream='BusinessApps'; Workload='Enterprise applications';
           Output='AppOwners.csv'; Endpoint='GET /applications/{id}/owners'; ApiVersion='v1.0';
           DelegatedPermissions=@('Application.Read.All'); ApplicationPermissions=@('Application.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/application-list-owners'; ValidationStatus='NotValidatedLive'; KnownLimitations='One call per app registration' }
        @{ Name='AppRedirectUris'; Section='Apps'; ServiceGroup='Graph'; Level='Basic'; Workstream='BusinessApps'; Workload='App registrations';
           Output='AppRedirectUris.csv'; Endpoint='GET /applications (web/spa/publicClient)'; ApiVersion='v1.0';
           DelegatedPermissions=@('Application.Read.All'); ApplicationPermissions=@('Application.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/resources/application'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='AppCredentials'; Section='Apps'; ServiceGroup='Graph'; Level='Basic'; Workstream='Security'; Workload='App credentials';
           Output='AppCredentials.csv'; Endpoint='GET /applications + /servicePrincipals (keyCredentials/passwordCredentials)'; ApiVersion='v1.0';
           DelegatedPermissions=@('Application.Read.All'); ApplicationPermissions=@('Application.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/resources/keycredential'; ValidationStatus='NotValidatedLive'; KnownLimitations='Metadata only - no secretText or key material' }
        @{ Name='SamlCertificates'; Section='Apps'; ServiceGroup='Graph'; Level='Basic'; Workstream='Security'; Workload='Enterprise applications';
           Output='SamlCertificates.csv'; Endpoint='GET /servicePrincipals (keyCredentials, preferredSingleSignOnMode=saml)'; ApiVersion='v1.0';
           DelegatedPermissions=@('Application.Read.All'); ApplicationPermissions=@('Application.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/resources/serviceprincipal'; ValidationStatus='NotValidatedLive'; KnownLimitations='Metadata only' }
        @{ Name='ProvisioningJobs'; Section='Apps'; ServiceGroup='Graph'; Level='Advanced'; Workstream='Identity'; Workload='App provisioning (SCIM)';
           Output='ProvisioningJobs.csv'; Endpoint='GET /servicePrincipals/{id}/synchronization/jobs'; ApiVersion='v1.0';
           DelegatedPermissions=@('Synchronization.Read.All'); ApplicationPermissions=@('Synchronization.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/synchronization-synchronization-list-jobs'; ValidationStatus='NotValidatedLive'; KnownLimitations='One call per enterprise app; 404 = no provisioning' }

        # ---- Phase 1: Exchange ----
        @{ Name='RecoverableItemsSize'; Section='Exchange'; ServiceGroup='Exchange'; Level='Advanced'; Workstream='Messaging'; Workload='Exchange Online';
           Output='MailboxStatistics.csv'; Cmdlet='Get-EXOMailboxFolderStatistics -FolderScope RecoverableItems'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailboxfolderstatistics'; ValidationStatus='NotValidatedLive'; KnownLimitations='Per-mailbox call; NOT included in totalMailboxGB' }
        @{ Name='SmtpClientAuth'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Exchange Online';
           Output='SmtpClientAuthOrg.csv'; Cmdlet='Get-TransportConfig'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/exchange/clients-and-mobile-in-exchange-online/authenticated-client-smtp-submission'; ValidationStatus='NotValidatedLive'; KnownLimitations='Org default only' }
        @{ Name='SmtpClientAuthPerMailbox'; Section='Exchange'; ServiceGroup='Exchange'; Level='Advanced'; Workstream='Messaging'; Workload='Exchange Online';
           Output='SmtpClientAuthMailboxes.csv'; Cmdlet='Get-CASMailbox -ResultSize Unlimited'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-casmailbox'; ValidationStatus='NotValidatedLive'; KnownLimitations='Only mailboxes with an explicit override are listed' }
        @{ Name='InactiveMailboxes'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Exchange Online';
           Output='InactiveMailboxes.csv'; Cmdlet='Get-EXOMailbox -InactiveMailboxOnly'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailbox'; ValidationStatus='NotValidatedLive'; KnownLimitations='Inactive mailboxes are not moved by cross-tenant migration tools' }
        @{ Name='SoftDeletedMailboxes'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Exchange Online';
           Output='SoftDeletedMailboxes.csv'; Cmdlet='Get-EXOMailbox -SoftDeletedMailbox'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailbox'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='DynamicDistributionGroups'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Groups';
           Output='DynamicDistributionGroups.csv'; Cmdlet='Get-DynamicDistributionGroup + Get-DynamicDistributionGroupMember'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-dynamicdistributiongroup'; ValidationStatus='NotValidatedLive'; KnownLimitations='Membership cannot be exported statically - filter must be recreated' }
        @{ Name='DistributionGroupMembers'; Section='Exchange'; ServiceGroup='Exchange'; Level='Advanced'; Workstream='Messaging'; Workload='Groups';
           Output='DistributionGroupMembers.csv'; Cmdlet='Get-DistributionGroupMember + Get-Recipient'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-distributiongroupmember'; ValidationStatus='NotValidatedLive'; KnownLimitations='Member counts + owners; full member lists only at -Level Deep' }
        @{ Name='CalendarProcessing'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Resource mailboxes';
           Output='CalendarProcessing.csv'; Cmdlet='Get-CalendarProcessing'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-calendarprocessing'; ValidationStatus='NotValidatedLive'; KnownLimitations='Room and equipment mailboxes only' }
        @{ Name='CalendarPermissions'; Section='Exchange'; ServiceGroup='Exchange'; Level='Deep'; Workstream='Messaging'; Workload='Exchange Online';
           Output='CalendarPermissions.csv'; Cmdlet='Get-MailboxFolderPermission <guid>:\Calendar'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailboxfolderpermission'; ValidationStatus='NotValidatedLive'; KnownLimitations='One call per mailbox - expensive on large tenants' }
        @{ Name='InboxRuleForwarding'; Section='Exchange'; ServiceGroup='Exchange'; Level='Deep'; Workstream='Security'; Workload='Exchange Online';
           Output='InboxRuleForwarding.csv'; Cmdlet='Get-InboxRule -Mailbox <guid>'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-inboxrule'; ValidationStatus='NotValidatedLive'; KnownLimitations='Target domains + rule name only - no rule bodies or addresses' }
        @{ Name='SharingPolicies'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Exchange Online';
           Output='SharingPolicies.csv'; Cmdlet='Get-SharingPolicy'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-sharingpolicy'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='AddressLists'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Exchange Online';
           Output='AddressLists.csv'; Cmdlet='Get-AddressList + Get-GlobalAddressList + Get-AddressBookPolicy + Get-OfflineAddressBook'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-addresslist'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='MrmRetention'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Compliance'; Workload='Exchange MRM';
           Output='RetentionPolicyTags.csv'; Cmdlet='Get-RetentionPolicyTag + Get-RetentionPolicy'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-retentionpolicytag'; ValidationStatus='NotValidatedLive'; KnownLimitations='Exchange MRM - distinct from Purview retention' }
        @{ Name='MrmRetentionPolicies'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Compliance'; Workload='Exchange MRM';
           Output='MrmRetentionPolicies.csv'; Cmdlet='Get-RetentionPolicy'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-retentionpolicy'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='ApplicationAccessPolicies'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Security'; Workload='Exchange Online';
           Output='ApplicationAccessPolicies.csv'; Cmdlet='Get-ApplicationAccessPolicy'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-applicationaccesspolicy'; ValidationStatus='NotValidatedLive'; KnownLimitations='EWS application scoping - recreate in target' }
        @{ Name='ServicePrincipalRoleAssignments'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Security'; Workload='Exchange Online';
           Output='ServicePrincipalRoleAssignments.csv'; Cmdlet='Get-ServicePrincipal + Get-ManagementRoleAssignment'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-serviceprincipal'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='HybridIndicators'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Exchange hybrid';
           Output='HybridIndicators.csv'; Cmdlet='Get-IntraOrganizationConnector + Get-HybridConfiguration'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Exchange Recipient','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-intraorganizationconnector'; ValidationStatus='NotValidatedLive'; KnownLimitations='Indicates on-prem Exchange hybrid - migration must consider free/busy and mail routing' }

        # ---- Phase 1: SharePoint ----
        @{ Name='HubSites'; Section='SharePoint'; ServiceGroup='SharePoint'; Level='Basic'; Workstream='Collaboration'; Workload='SharePoint Online';
           Output='HubSites.csv'; Cmdlet='Get-SPOHubSite'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('SharePoint Administrator'); AppOnlySupported=$false; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spohubsite'; ValidationStatus='NotValidatedLive'; KnownLimitations='Association via HubSiteId column on SharePointSites.csv' }
        @{ Name='SiteAdmins'; Section='SharePoint'; ServiceGroup='SharePoint'; Level='Advanced'; Workstream='Collaboration'; Workload='SharePoint Online';
           Output='SiteAdmins.csv'; Cmdlet='Get-SPOUser -Site <url>'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('SharePoint Administrator'); AppOnlySupported=$false; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spouser'; ValidationStatus='NotValidatedLive'; KnownLimitations='One call per site - expensive on large tenants; the account must be site collection admin on each site, otherwise Get-SPOUser is denied' }
        @{ Name='DeletedOneDrives'; Section='SharePoint'; ServiceGroup='SharePoint'; Level='Basic'; Workstream='Collaboration'; Workload='OneDrive';
           Output='DeletedOneDrives.csv'; Cmdlet='Get-SPODeletedSite -IncludeOnlyPersonalSite'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('SharePoint Administrator'); AppOnlySupported=$false; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spodeletedsite'; ValidationStatus='NotValidatedLive'; KnownLimitations='Soft-deleted personal sites within retention' }
        @{ Name='SiteLists'; Section='SharePoint'; ServiceGroup='SharePoint'; Level='Deep'; Workstream='Collaboration'; Workload='SharePoint Online';
           Output='SiteLists.csv'; Endpoint='GET /sites/{id}/lists'; ApiVersion='v1.0';
           DelegatedPermissions=@('Sites.Read.All'); ApplicationPermissions=@('Sites.Read.All');
           AdminRoles=@(); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/site-list-lists'; ValidationStatus='NotValidatedLive'; KnownLimitations='Runs only when SharePoint executes in the Graph process (fallback mode) - needs Graph site IDs' }
        @{ Name='SiteUniquePermissions'; Section='SharePoint'; ServiceGroup='Parent'; Level='Deep'; Workstream='Collaboration'; Workload='SharePoint Online';
           Output=''; Endpoint=''; ApiVersion='';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@(); AppOnlySupported=$false; RequiredLicence=''; Coverage='ManualDiscoveryRequired';
           DocsUrl='https://learn.microsoft.com/en-us/sharepoint/unique-permissions-in-sharepoint-server'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Needs PnP/per-item REST calls - out of scope; assess per-site' }
        @{ Name='OneDriveKFM'; Section='OneDrive'; ServiceGroup='Parent'; Level='Basic'; Workstream='Collaboration'; Workload='OneDrive';
           Output=''; Endpoint=''; ApiVersion='';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@(); AppOnlySupported=$false; RequiredLicence=''; Coverage='ManualDiscoveryRequired';
           DocsUrl='https://learn.microsoft.com/en-us/sharepoint/redirect-known-folders'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Known Folder Move is client-side - assess via device policies/user survey' }

        # ---- Phase 1: DNS ----
        @{ Name='ThirdPartyEvidence'; Section='Dns'; ServiceGroup='Parent'; Level='Basic'; Workstream='Messaging'; Workload='Mail flow';
           Output='ThirdPartyEvidence.csv'; Cmdlet='Resolve-DnsName (MX/SPF) + Exchange connectors CSVs'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@(); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/exchange/mail-flow-best-practices/use-connectors-to-configure-mail-flow/use-connectors-to-configure-mail-flow'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Rows only on concrete record matches (Mimecast/Proofpoint/Hornetsecurity/Barracuda/CodeTwo/Exclaimer/external MX)' }

        # ---- Phase 1: Teams ----
        @{ Name='TeamsConfig'; Section='TeamsConfig'; ServiceGroup='Teams'; Level='Basic'; Workstream='Collaboration'; Workload='Microsoft Teams';
           Output=''; Cmdlet='Get-CsTenantFederationConfiguration + Get-CsTeams*Configuration + Get-CsTeams*Policy'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Teams Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/teams/'; ValidationStatus='NotValidatedLive'; KnownLimitations='Policy inventory is names only' }
        @{ Name='TeamsFederation'; Section='TeamsConfig'; ServiceGroup='Teams'; Level='Basic'; Workstream='Collaboration'; Workload='Microsoft Teams';
           Output='TeamsFederation.csv'; Cmdlet='Get-CsTenantFederationConfiguration'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Teams Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/teams/get-cstenantfederationconfiguration'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='TeamsGuestConfig'; Section='TeamsConfig'; ServiceGroup='Teams'; Level='Basic'; Workstream='Collaboration'; Workload='Microsoft Teams';
           Output='TeamsGuestConfig.csv'; Cmdlet='Get-CsTeamsClientConfiguration + Get-CsTeamsGuestMeetingConfiguration + Get-CsTeamsGuestMessagingConfiguration'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Teams Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/teams/get-csteamsclientconfiguration'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='TeamsPolicies'; Section='TeamsConfig'; ServiceGroup='Teams'; Level='Basic'; Workstream='Collaboration'; Workload='Microsoft Teams';
           Output='TeamsPolicies.csv'; Cmdlet='Get-CsTeamsMeetingPolicy/MessagingPolicy/AppSetupPolicy/AppPermissionPolicy/CallingPolicy/UpdatePolicy'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Teams Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/teams/get-csteamsmeetingpolicy'; ValidationStatus='NotValidatedLive'; KnownLimitations='Names only - no per-policy user counts' }
        @{ Name='TeamTabs'; Section='Teams'; ServiceGroup='Parent'; Level='Deep'; Workstream='Collaboration'; Workload='Microsoft Teams';
           Output=''; Endpoint='GET /teams/{id}/channels/{id}/tabs'; ApiVersion='v1.0';
           DelegatedPermissions=@('Team.ReadBasic.All','ChannelSettings.Read.All'); ApplicationPermissions=@();
           AdminRoles=@(); AppOnlySupported=$false; RequiredLicence=''; Coverage='ManualDiscoveryRequired';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/channel-list-tabs'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Per-channel tab listing needs one call per channel - too costly for inventory; assess during migration design' }

        # ---- Phase 1: Usage reports ----
        @{ Name='UsageM365Apps'; Section='Usage'; ServiceGroup='Graph'; Level='Basic'; Workstream='Collaboration'; Workload='M365 apps usage';
           Output=''; Endpoint="GET /reports/getM365AppUserDetail(period='D30')"; ApiVersion='v1.0';
           DelegatedPermissions=@('Reports.Read.All'); ApplicationPermissions=@('Reports.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='UsageDetectionOnly';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/reportroot-getm365appuserdetail'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='UsageOfficeActivations'; Section='Usage'; ServiceGroup='Graph'; Level='Basic'; Workstream='Endpoint'; Workload='Office activations';
           Output=''; Endpoint='GET /reports/getOffice365ActivationsUserDetail'; ApiVersion='v1.0';
           DelegatedPermissions=@('Reports.Read.All'); ApplicationPermissions=@('Reports.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='UsageDetectionOnly';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/reportroot-getoffice365activationsuserdetail'; ValidationStatus='NotValidatedLive'; KnownLimitations='No period parameter' }
        @{ Name='UsageGroupsActivity'; Section='Usage'; ServiceGroup='Graph'; Level='Basic'; Workstream='Collaboration'; Workload='M365 Groups';
           Output=''; Endpoint="GET /reports/getOffice365GroupsActivityDetail(period='D30')"; ApiVersion='v1.0';
           DelegatedPermissions=@('Reports.Read.All'); ApplicationPermissions=@('Reports.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='UsageDetectionOnly';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/reportroot-getoffice365groupsactivitydetail'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='UsageYammer'; Section='Usage'; ServiceGroup='Graph'; Level='Basic'; Workstream='Collaboration'; Workload='Viva Engage (Yammer)';
           Output=''; Endpoint="GET /reports/getYammerActivityUserDetail(period='D30')"; ApiVersion='v1.0';
           DelegatedPermissions=@('Reports.Read.All'); ApplicationPermissions=@('Reports.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='UsageDetectionOnly';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/reportroot-getyammeractivityuserdetail'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='UsageTeamsDevices'; Section='Usage'; ServiceGroup='Graph'; Level='Basic'; Workstream='Endpoint'; Workload='Microsoft Teams';
           Output=''; Endpoint="GET /reports/getTeamsDeviceUsageUserDetail(period='D30')"; ApiVersion='v1.0';
           DelegatedPermissions=@('Reports.Read.All'); ApplicationPermissions=@('Reports.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='UsageDetectionOnly';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/reportroot-getteamsdeviceusageuserdetail'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='UsageCopilot'; Section='Usage'; ServiceGroup='Graph'; Level='Basic'; Workstream='BusinessApps'; Workload='Microsoft 365 Copilot';
           Output='UsageCopilot.csv'; Endpoint="GET /reports/getMicrosoft365CopilotUsageUserDetail(period='D30')"; ApiVersion='beta';
           DelegatedPermissions=@('Reports.Read.All'); ApplicationPermissions=@('Reports.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='UsageDetectionOnly';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/reportroot-getmicrosoft365copilotusageuserdetail'; ValidationStatus='NotValidatedLive';
           KnownLimitations='beta endpoint only - no v1.0 equivalent at time of writing' }
        @{ Name='UsageD90'; Section='Usage'; ServiceGroup='Graph'; Level='Advanced'; Workstream='Collaboration'; Workload='Usage (90 days)';
           Output=''; Endpoint="GET /reports/get*(period='D90')"; ApiVersion='v1.0';
           DelegatedPermissions=@('Reports.Read.All'); ApplicationPermissions=@('Reports.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='UsageDetectionOnly';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/resources/report'; ValidationStatus='NotValidatedLive'; KnownLimitations='Email/Teams/ActiveUsers/Groups reports' }
        @{ Name='UsageD180'; Section='Usage'; ServiceGroup='Graph'; Level='Advanced'; Workstream='Collaboration'; Workload='Usage (180 days)';
           Output=''; Endpoint="GET /reports/get*(period='D180')"; ApiVersion='v1.0';
           DelegatedPermissions=@('Reports.Read.All'); ApplicationPermissions=@('Reports.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='UsageDetectionOnly';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/resources/report'; ValidationStatus='NotValidatedLive'; KnownLimitations='Email/Teams/ActiveUsers/Groups reports' }
    )
}
