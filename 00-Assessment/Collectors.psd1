# Collector registry for Collect-TenantInventory.ps1
# One entry per CSV output (or sub-collection) plus manual-discovery workloads.
# Fields:
#   Name            unique collector name
#   Section         inventory section it belongs to
#   ServiceGroup    Graph | Exchange | SharePoint | Teams | PowerPlatform | Parent
#   Level           Basic | Advanced | Deep - minimum -Level that runs it
#   Workstream      Identity | Messaging | Collaboration | Endpoint | Security |
#                   Compliance | BusinessApps | Governance
#   Workload        free-text workload name for the readiness workload summary
#   Output          CSV file name in attachments\ ('' when none)
#   Endpoint/Cmdlet what the code actually calls (one of them)
#   ApiVersion      v1.0 | beta | PowerShell
#   DelegatedPermissions / ApplicationPermissions   Graph scopes or module perms
#   AdminRoles      directory roles needed beyond Global Reader
#   AppOnlySupported  $false = delegated auth only (NotSupported in app-only mode)
#   RequiredLicence e.g. 'Entra ID P1' ('' when none)
#   Coverage        Full | Partial | UsageDetectionOnly | ManualDiscoveryRequired | NotSupported
#   DocsUrl         Microsoft Learn page
#   ValidationStatus  NotValidatedLive | ValidatedLive
#   KnownLimitations  free text
@{
    Collectors = @(
        # ---- Tenant / domains / licences (Graph child) ----
        @{ Name='Organization'; Section='Tenant'; ServiceGroup='Graph'; Level='Basic'; Workstream='Identity'; Workload='Organization';
           Output='Organization.csv'; Endpoint='GET /organization'; ApiVersion='v1.0';
           DelegatedPermissions=@('Organization.Read.All'); ApplicationPermissions=@('Organization.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/organization-list'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='Domains'; Section='Tenant'; ServiceGroup='Graph'; Level='Basic'; Workstream='Identity'; Workload='Domains';
           Output='Domains.csv'; Endpoint='GET /domains'; ApiVersion='v1.0';
           DelegatedPermissions=@('Domain.Read.All'); ApplicationPermissions=@('Domain.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/domain-list'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='Licenses'; Section='Licenses'; ServiceGroup='Graph'; Level='Basic'; Workstream='Identity'; Workload='Licences';
           Output='Licenses.csv'; Endpoint='GET /subscribedSkus'; ApiVersion='v1.0';
           DelegatedPermissions=@('Directory.Read.All'); ApplicationPermissions=@('Directory.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/subscribedsku-list'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='LicenseServicePlans'; Section='Licenses'; ServiceGroup='Graph'; Level='Basic'; Workstream='Identity'; Workload='Licences';
           Output='LicenseServicePlans.csv'; Endpoint='GET /subscribedSkus (servicePlans per SKU)'; ApiVersion='v1.0';
           DelegatedPermissions=@('Directory.Read.All'); ApplicationPermissions=@('Directory.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/subscribedsku-list'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='Users'; Section='Users'; ServiceGroup='Graph'; Level='Basic'; Workstream='Identity'; Workload='Users';
           Output='Users.csv'; Endpoint='GET /users'; ApiVersion='v1.0';
           DelegatedPermissions=@('User.Read.All'); ApplicationPermissions=@('User.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/user-list'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='Groups'; Section='Groups'; ServiceGroup='Graph'; Level='Basic'; Workstream='Identity'; Workload='Groups';
           Output='Groups.csv'; Endpoint='GET /groups + /transitiveMembers/$count + /owners/$count per group'; ApiVersion='v1.0';
           DelegatedPermissions=@('Group.Read.All'); ApplicationPermissions=@('Group.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/group-list'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='AdminRoles'; Section='Roles'; ServiceGroup='Graph'; Level='Basic'; Workstream='Identity'; Workload='Roles and admins';
           Output='AdminRoles.csv'; Endpoint='GET /roleManagement/directory/roleAssignments?$expand=principal'; ApiVersion='v1.0';
           DelegatedPermissions=@('RoleManagement.Read.Directory'); ApplicationPermissions=@('RoleManagement.Read.Directory');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignments'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='PlannerPlans'; Section='Groups'; ServiceGroup='Graph'; Level='Advanced'; Workstream='Collaboration'; Workload='Planner';
           Output='PlannerPlans.csv'; Endpoint='GET /groups/{id}/planner/plans per M365 group'; ApiVersion='v1.0';
           DelegatedPermissions=@('Tasks.Read'); ApplicationPermissions=@('Tasks.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/plannergroup-list-plans'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Plans only (no tasks/buckets); skipped entirely on 403' }

        # ---- Security (Graph child) ----
        @{ Name='ConditionalAccess'; Section='Security'; ServiceGroup='Graph'; Level='Basic'; Workstream='Security'; Workload='Conditional Access';
           Output='ConditionalAccess.csv'; Endpoint='GET /identity/conditionalAccess/policies'; ApiVersion='v1.0';
           DelegatedPermissions=@('Policy.Read.All'); ApplicationPermissions=@('Policy.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence='Entra ID P1'; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-list-policies'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='NamedLocations'; Section='Security'; ServiceGroup='Graph'; Level='Basic'; Workstream='Security'; Workload='Conditional Access';
           Output='NamedLocations.csv'; Endpoint='GET /identity/conditionalAccess/namedLocations'; ApiVersion='v1.0';
           DelegatedPermissions=@('Policy.Read.All'); ApplicationPermissions=@('Policy.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-list-namedlocations'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='AuthMethodsPolicy'; Section='Security'; ServiceGroup='Graph'; Level='Basic'; Workstream='Security'; Workload='Authentication methods';
           Output='AuthMethodsPolicy.csv'; Endpoint='GET /policies/authenticationMethodsPolicy'; ApiVersion='v1.0';
           DelegatedPermissions=@('Policy.Read.All'); ApplicationPermissions=@('Policy.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/authenticationmethodspolicy-get'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='MfaRegistration'; Section='Security'; ServiceGroup='Graph'; Level='Basic'; Workstream='Security'; Workload='MFA registration';
           Output='MfaRegistration.csv'; Endpoint='GET /reports/authenticationMethods/userRegistrationDetails'; ApiVersion='v1.0';
           DelegatedPermissions=@('UserAuthenticationMethod.Read.All','AuditLog.Read.All'); ApplicationPermissions=@('UserAuthenticationMethod.Read.All','AuditLog.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence='Entra ID P1'; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/userregistrationdetails-list'; ValidationStatus='ValidatedLive'; KnownLimitations='' }

        # ---- Apps (Graph child) ----
        @{ Name='AppRegistrations'; Section='Apps'; ServiceGroup='Graph'; Level='Basic'; Workstream='Identity'; Workload='App registrations';
           Output='AppRegistrations.csv'; Endpoint='GET /applications'; ApiVersion='v1.0';
           DelegatedPermissions=@('Application.Read.All'); ApplicationPermissions=@('Application.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/application-list'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='EnterpriseApps'; Section='Apps'; ServiceGroup='Graph'; Level='Basic'; Workstream='Identity'; Workload='Enterprise applications';
           Output='EnterpriseApps.csv'; Endpoint='GET /servicePrincipals'; ApiVersion='v1.0';
           DelegatedPermissions=@('Application.Read.All','Directory.Read.All'); ApplicationPermissions=@('Application.Read.All','Directory.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/serviceprincipal-list'; ValidationStatus='ValidatedLive'; KnownLimitations='Microsoft first-party apps excluded' }
        @{ Name='AppPermissions'; Section='Apps'; ServiceGroup='Graph'; Level='Advanced'; Workstream='Security'; Workload='App permissions';
           Output='AppPermissions.csv'; Endpoint='GET /servicePrincipals/{id}/appRoleAssignments per app + GET /oauth2PermissionGrants'; ApiVersion='v1.0';
           DelegatedPermissions=@('Application.Read.All','Directory.Read.All'); ApplicationPermissions=@('Application.Read.All','Directory.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/serviceprincipal-list-approleassignments'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Resource names resolved via one extra call per resource service principal' }
        @{ Name='AppRegistrationPermissions'; Section='Apps'; ServiceGroup='Graph'; Level='Basic'; Workstream='Security'; Workload='App permissions';
           Output='AppRegistrationPermissions.csv'; Endpoint='requiredResourceAccess on GET /applications'; ApiVersion='v1.0';
           DelegatedPermissions=@('Application.Read.All'); ApplicationPermissions=@('Application.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/resources/requiredresourceaccess'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Requested, not necessarily granted, permissions' }
        @{ Name='AppSignInActivity'; Section='AppSignIns'; ServiceGroup='Graph'; Level='Basic'; Workstream='Identity'; Workload='App usage';
           Output='AppSignInActivity.csv'; Endpoint='GET /beta/reports/servicePrincipalSignInActivities + service principal list'; ApiVersion='beta';
           DelegatedPermissions=@('AuditLog.Read.All'); ApplicationPermissions=@('AuditLog.Read.All');
           AdminRoles=@('Reports Reader','Global Reader'); AppOnlySupported=$true; RequiredLicence='Entra ID P1'; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/reportroot-list-serviceprincipalsigninactivities'; ValidationStatus='ValidatedLive';
           KnownLimitations='Activity report is preview and can be stale - never used alone to call an app unused' }
        @{ Name='AppSignInLogs'; Section='AppSignIns'; ServiceGroup='Graph'; Level='Advanced'; Workstream='Identity'; Workload='App usage';
           Output=''; Endpoint='GET /beta/auditLogs/signIns per app per event type'; ApiVersion='beta';
           DelegatedPermissions=@('AuditLog.Read.All'); ApplicationPermissions=@('AuditLog.Read.All');
           AdminRoles=@('Reports Reader','Global Reader'); AppOnlySupported=$true; RequiredLicence='Entra ID P1'; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/signin-list'; ValidationStatus='ValidatedLive';
           KnownLimitations='Writes into AppSignInActivity.csv; throttled - ~14 s per query observed; Microsoft first-party apps skipped unless -IncludeMicrosoftAppsInSignInLogs' }

        # ---- Exchange (Exchange child) ----
        @{ Name='Mailboxes'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Exchange mailboxes';
           Output='Mailboxes.csv'; Cmdlet='Get-EXOMailbox / Get-Mailbox (fallbacks)'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='MailboxStatistics'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Exchange mailboxes';
           Output='MailboxStatistics.csv'; Cmdlet='Get-EXOMailboxStatistics (+Get-MailboxLocation -User for aux archives)'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailboxstatistics'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='AuxArchiveCount'; Section='Exchange'; ServiceGroup='Exchange'; Level='Advanced'; Workstream='Messaging'; Workload='Exchange mailboxes';
           Output=''; Cmdlet='Get-MailboxLocation -User <ExchangeGuid> per archive mailbox'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-maillocation'; ValidationStatus='ValidatedLive';
           KnownLimitations='Writes AuxArchiveCount into MailboxStatistics.csv/Mailboxes.csv' }
        @{ Name='MailboxHolds'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Exchange mailboxes';
           Output='MailboxHolds.csv'; Cmdlet='Get-EXOMailbox hold properties'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailbox'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='MailboxPermissions'; Section='Exchange'; ServiceGroup='Exchange'; Level='Advanced'; Workstream='Messaging'; Workload='Mailbox permissions';
           Output='MailboxPermissions.csv'; Cmdlet='Get-EXOMailboxPermission per mailbox'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailboxpermission'; ValidationStatus='ValidatedLive';
           KnownLimitations='Per-mailbox loop - slow on large tenants' }
        @{ Name='SendAsPermissions'; Section='Exchange'; ServiceGroup='Exchange'; Level='Advanced'; Workstream='Messaging'; Workload='Mailbox permissions';
           Output='SendAsPermissions.csv'; Cmdlet='Get-EXORecipientPermission per mailbox'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-exorecipientpermission'; ValidationStatus='ValidatedLive';
           KnownLimitations='Per-mailbox loop' }
        @{ Name='DistributionGroups'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Distribution groups';
           Output='DistributionGroups.csv'; Cmdlet='Get-DistributionGroup / Get-DynamicDistributionGroup'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-distributiongroup'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='MailContacts'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Contacts';
           Output='MailContacts.csv'; Cmdlet='Get-MailContact'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailcontact'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='MailUsers'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Contacts';
           Output='MailUsers.csv'; Cmdlet='Get-MailUser'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailuser'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='AcceptedDomains'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Mail flow';
           Output='AcceptedDomains.csv'; Cmdlet='Get-AcceptedDomain'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-accepteddomain'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='InboundConnectors'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Mail flow';
           Output='InboundConnectors.csv'; Cmdlet='Get-InboundConnector'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-inboundconnector'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='OutboundConnectors'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Mail flow';
           Output='OutboundConnectors.csv'; Cmdlet='Get-OutboundConnector'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-outboundconnector'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='TransportRules'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Mail flow';
           Output='TransportRules.csv'; Cmdlet='Get-TransportRule'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-transportrule'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='DkimSigningConfig'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Mail flow';
           Output='DkimSigningConfig.csv'; Cmdlet='Get-DkimSigningConfig'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-dkimsigningconfig'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='RemoteDomains'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Mail flow';
           Output='RemoteDomains.csv'; Cmdlet='Get-RemoteDomain'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-remotedomain'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='OrganizationRelationships'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Sharing';
           Output='OrganizationRelationships.csv'; Cmdlet='Get-OrganizationRelationship'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-organizationrelationship'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='PublicFolderMailboxes'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Public folders';
           Output='PublicFolderMailboxes.csv'; Cmdlet='Get-EXOMailbox -PublicFolder'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailbox'; ValidationStatus='ValidatedLive';
           KnownLimitations='Public folder mailboxes only - no folder tree or sizes' }
        @{ Name='BookingsMailboxes'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Bookings';
           Output='BookingsMailboxes.csv'; Cmdlet='Get-EXOMailbox -RecipientTypeDetails SchedulingMailbox'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailbox'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='RetentionPolicies'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Compliance'; Workload='Retention';
           Output='RetentionPolicies.csv'; Cmdlet='Get-RetentionPolicy'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Compliance Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-retentionpolicy'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='RetentionRules'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Compliance'; Workload='Retention';
           Output='RetentionRules.csv'; Cmdlet='Get-RetentionPolicyTag'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Compliance Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-retentionpolicytag'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='JournalRules'; Section='Exchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Mail flow';
           Output='JournalRules.csv'; Cmdlet='Get-JournalRule'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-journalrule'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='OutlookAddins'; Section='Exchange'; ServiceGroup='Exchange'; Level='Advanced'; Workstream='BusinessApps'; Workload='Outlook add-ins';
           Output='OutlookAddins.csv'; Cmdlet='Get-App -OrganizationApp'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-app'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Admin-deployed org apps only - per-user add-ins not listed' }
        @{ Name='MigrationEndpoints'; Section='TargetExchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Messaging'; Workload='Migration';
           Output='MigrationEndpoints.csv'; Cmdlet='Get-MigrationEndpoint'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-migrationendpoint'; ValidationStatus='NotValidatedLive'; KnownLimitations='Target role only' }
        @{ Name='CustomerKey'; Section='Exchange,SharePoint'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Compliance'; Workload='Customer Key';
           Output='CustomerKey.csv'; Cmdlet='Get-DataEncryptionPolicy (+Get-SPODataEncryptionPolicy)'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-dataencryptionpolicy'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Merged with SPO-side rows when available' }

        # ---- Purview (Exchange child, IPPS session) ----
        @{ Name='SensitivityLabels'; Section='Purview'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Compliance'; Workload='Sensitivity labels';
           Output='SensitivityLabels.csv'; Cmdlet='Get-Label'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Compliance Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-label'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='DlpPolicies'; Section='Purview'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Compliance'; Workload='DLP';
           Output='DlpPolicies.csv'; Cmdlet='Get-DlpCompliancePolicy'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Compliance Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-dlpcompliancepolicy'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='ComplianceCases'; Section='Purview'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Compliance'; Workload='eDiscovery';
           Output='ComplianceCases.csv'; Cmdlet='Get-ComplianceCase'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('eDiscovery Manager','Compliance Administrator'); AppOnlySupported=$false; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2'; ValidationStatus='NotValidatedLive';
           KnownLimitations='eDiscovery cmdlets are not supported in app-only auth (Learn)' }
        @{ Name='CaseHoldPolicies'; Section='Purview'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Compliance'; Workload='eDiscovery';
           Output='CaseHoldPolicies.csv'; Cmdlet='Get-CaseHoldPolicy'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('eDiscovery Manager','Compliance Administrator'); AppOnlySupported=$false; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2'; ValidationStatus='NotValidatedLive';
           KnownLimitations='eDiscovery cmdlets are not supported in app-only auth (Learn)' }
        @{ Name='EDiscoveryCases'; Section='Purview'; ServiceGroup='Graph'; Level='Basic'; Workstream='Compliance'; Workload='eDiscovery';
           Output='EDiscoveryCases.csv'; Endpoint='GET /security/cases/eDiscoveryCases'; ApiVersion='v1.0';
           DelegatedPermissions=@('eDiscovery.Read.All'); ApplicationPermissions=@('eDiscovery.Read.All');
           AdminRoles=@('eDiscovery Manager','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/security-ediscoverycase-list'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Graph fallback when IPPS is not connected' }
        @{ Name='EDiscoveryHolds'; Section='Purview'; ServiceGroup='Graph'; Level='Basic'; Workstream='Compliance'; Workload='eDiscovery';
           Output='EDiscoveryHolds.csv'; Endpoint='GET /security/cases/eDiscoveryCases/{id}/custodians'; ApiVersion='v1.0';
           DelegatedPermissions=@('eDiscovery.Read.All'); ApplicationPermissions=@('eDiscovery.Read.All');
           AdminRoles=@('eDiscovery Manager','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/security-ediscoverycustodian-list'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }

        # ---- OneDrive / SharePoint (SharePoint child + Graph fallback) ----
        @{ Name='OneDrive'; Section='OneDrive'; ServiceGroup='SharePoint'; Level='Basic'; Workstream='Collaboration'; Workload='OneDrive';
           Output='OneDrive.csv'; Cmdlet='Get-SPOSite -IncludePersonalSite / Graph fallback'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Sites.Read.All','Reports.Read.All'); ApplicationPermissions=@('Sites.Read.All','Reports.Read.All');
           AdminRoles=@('SharePoint Administrator','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/sharepoint/sharepoint-online/connect-sharepoint-online'; ValidationStatus='ValidatedLive';
           KnownLimitations='SPO admin has no certificate app-only auth - in app-only mode the Graph fallback runs (usage-report based)' }
        @{ Name='OneDriveUsage'; Section='Usage'; ServiceGroup='Graph'; Level='Basic'; Workstream='Collaboration'; Workload='OneDrive';
           Output='OneDriveUsage.csv'; Endpoint='GET /reports/getOneDriveUsageAccountDetail(period=D30)'; ApiVersion='v1.0';
           DelegatedPermissions=@('Reports.Read.All'); ApplicationPermissions=@('Reports.Read.All');
           AdminRoles=@('Reports Reader','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='UsageDetectionOnly';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/reportroot-getonedriveusageaccountdetail'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='SharePointSites'; Section='SharePoint'; ServiceGroup='SharePoint'; Level='Basic'; Workstream='Collaboration'; Workload='SharePoint';
           Output='SharePointSites.csv'; Cmdlet='Get-SPOSite -Limit All / Graph fallback'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Sites.Read.All','Reports.Read.All'); ApplicationPermissions=@('Sites.Read.All','Reports.Read.All');
           AdminRoles=@('SharePoint Administrator','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/sharepoint/sharepoint-online/connect-sharepoint-online'; ValidationStatus='ValidatedLive';
           KnownLimitations='SPO admin has no certificate app-only auth - in app-only mode the Graph fallback runs (may undercount sites)' }
        @{ Name='SharePointTenant'; Section='SharePoint'; ServiceGroup='SharePoint'; Level='Basic'; Workstream='Collaboration'; Workload='SharePoint';
           Output='SharePointTenant.csv'; Cmdlet='Get-SPOTenant'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('SharePoint Administrator'); AppOnlySupported=$false; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spotenant'; ValidationStatus='NotValidatedLive';
           KnownLimitations='SPO admin PowerShell only (delegated interactive)' }
        @{ Name='ExternalUsers'; Section='SharePoint'; ServiceGroup='SharePoint'; Level='Basic'; Workstream='Security'; Workload='External sharing';
           Output='ExternalUsers.csv'; Cmdlet='Get-SPOExternalUser'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('SharePoint Administrator'); AppOnlySupported=$false; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spoexternaluser'; ValidationStatus='NotValidatedLive';
           KnownLimitations='SPO admin PowerShell only' }
        @{ Name='SharePointAppCatalog'; Section='SharePoint'; ServiceGroup='SharePoint'; Level='Advanced'; Workstream='BusinessApps'; Workload='SharePoint apps';
           Output='SharePointAppCatalog.csv'; Cmdlet="Get-SPOAppInfo -Name ' '"; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('SharePoint Administrator'); AppOnlySupported=$false; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spoappinfo'; ValidationStatus='NotValidatedLive';
           KnownLimitations='SPO admin PowerShell only; installed apps, not package versions' }

        # ---- Teams (Graph child + Teams child) ----
        @{ Name='Teams'; Section='Teams'; ServiceGroup='Graph'; Level='Basic'; Workstream='Collaboration'; Workload='Teams';
           Output='Teams.csv'; Endpoint='GET /groups (Team provisioning) + /teams/{id} + member/owner counts'; ApiVersion='v1.0';
           DelegatedPermissions=@('Group.Read.All','TeamSettings.Read.All','TeamMember.Read.All'); ApplicationPermissions=@('Group.Read.All','TeamSettings.Read.All','TeamMember.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/team-get'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='TeamsChannels'; Section='Teams'; ServiceGroup='Graph'; Level='Basic'; Workstream='Collaboration'; Workload='Teams';
           Output='TeamsChannels.csv'; Endpoint='GET /teams/{id}/allChannels per team'; ApiVersion='v1.0';
           DelegatedPermissions=@('Channel.ReadBasic.All'); ApplicationPermissions=@('ChannelSettings.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/team-list-allchannels'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='TeamsCustomApps'; Section='Teams'; ServiceGroup='Graph'; Level='Basic'; Workstream='BusinessApps'; Workload='Teams apps';
           Output='TeamsCustomApps.csv'; Endpoint="GET /appCatalogs/teamsApps?`$filter=distributionMethod eq 'organization'"; ApiVersion='v1.0';
           DelegatedPermissions=@('AppCatalog.Read.All'); ApplicationPermissions=@('AppCatalog.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/appcatalogs-list-teamsapps'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Org-uploaded apps only; user-context API' }
        @{ Name='TeamsInstalledApps'; Section='Teams'; ServiceGroup='Graph'; Level='Advanced'; Workstream='BusinessApps'; Workload='Teams apps';
           Output='TeamsInstalledApps.csv'; Endpoint='GET /teams/{id}/installedApps per team'; ApiVersion='v1.0';
           DelegatedPermissions=@('TeamsAppInstallation.ReadForTeam'); ApplicationPermissions=@('TeamsAppInstallation.ReadForTeam.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/team-list-installedapps'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Includes store apps; no publisher field to filter Microsoft apps' }
        @{ Name='TeamsPhoneUsers'; Section='TeamsPhone'; ServiceGroup='Teams'; Level='Basic'; Workstream='Collaboration'; Workload='Teams Phone';
           Output='TeamsPhoneUsers.csv'; Cmdlet='Get-CsOnlineUser / Get-CsOnlineVoiceUser'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Teams Administrator'); AppOnlySupported=$true; RequiredLicence='Teams Phone licence'; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-supported-versions'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Skipped when no Teams Phone licence in the tenant' }
        @{ Name='TeamsAutoAttendants'; Section='TeamsPhone'; ServiceGroup='Teams'; Level='Basic'; Workstream='Collaboration'; Workload='Teams Phone';
           Output='TeamsAutoAttendants.csv'; Cmdlet='Get-CsAutoAttendant'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Teams Administrator'); AppOnlySupported=$true; RequiredLicence='Teams Phone licence'; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-supported-versions'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='TeamsCallQueues'; Section='TeamsPhone'; ServiceGroup='Teams'; Level='Basic'; Workstream='Collaboration'; Workload='Teams Phone';
           Output='TeamsCallQueues.csv'; Cmdlet='Get-CsCallQueue'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Teams Administrator'); AppOnlySupported=$true; RequiredLicence='Teams Phone licence'; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-supported-versions'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='TeamsPhoneGateways'; Section='TeamsPhone'; ServiceGroup='Teams'; Level='Basic'; Workstream='Collaboration'; Workload='Teams Phone';
           Output='TeamsPhoneGateways.csv'; Cmdlet='Get-CsOnlinePSTNGateway'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Teams Administrator'); AppOnlySupported=$true; RequiredLicence='Teams Phone licence'; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-supported-versions'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='TeamsPhoneNumbers'; Section='TeamsPhone'; ServiceGroup='Teams'; Level='Basic'; Workstream='Collaboration'; Workload='Teams Phone';
           Output='TeamsPhoneNumbers.csv'; Cmdlet='Get-CsPhoneNumberAssignment'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Teams Administrator'); AppOnlySupported=$true; RequiredLicence='Teams Phone licence'; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-supported-versions'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='TeamsMeetingPolicies'; Section='TeamsPhone'; ServiceGroup='Teams'; Level='Basic'; Workstream='Collaboration'; Workload='Teams Phone';
           Output='TeamsMeetingPolicies.csv'; Cmdlet='Get-CsTeamsMeetingPolicy'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Teams Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-supported-versions'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }
        @{ Name='TeamsPhoneVoiceRoutes'; Section='TeamsPhone'; ServiceGroup='Teams'; Level='Basic'; Workstream='Collaboration'; Workload='Teams Phone';
           Output='TeamsPhoneVoiceRoutes.csv'; Cmdlet='Get-CsOnlineVoiceRoute'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Teams Administrator'); AppOnlySupported=$true; RequiredLicence='Teams Phone licence'; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-supported-versions'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }

        # ---- Devices (Graph child) ----
        @{ Name='IntuneDevices'; Section='Devices'; ServiceGroup='Graph'; Level='Basic'; Workstream='Endpoint'; Workload='Devices (Intune)';
           Output='IntuneDevices.csv'; Endpoint='GET /deviceManagement/managedDevices'; ApiVersion='v1.0';
           DelegatedPermissions=@('DeviceManagementManagedDevices.Read.All'); ApplicationPermissions=@('DeviceManagementManagedDevices.Read.All');
           AdminRoles=@('Global Reader','Intune Administrator'); AppOnlySupported=$true; RequiredLicence='Intune'; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-list'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='EntraDevices'; Section='Devices'; ServiceGroup='Graph'; Level='Basic'; Workstream='Endpoint'; Workload='Devices (Entra)';
           Output='EntraDevices.csv'; Endpoint='GET /devices'; ApiVersion='v1.0';
           DelegatedPermissions=@('Directory.Read.All'); ApplicationPermissions=@('Device.Read.All','Directory.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/device-list'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='IntunePolicies'; Section='Devices'; ServiceGroup='Graph'; Level='Basic'; Workstream='Endpoint'; Workload='Intune configuration';
           Output='IntunePolicies.csv'; Endpoint='GET /deviceManagement/deviceConfigurations + compliancePolicies'; ApiVersion='v1.0';
           DelegatedPermissions=@('DeviceManagementConfiguration.Read.All'); ApplicationPermissions=@('DeviceManagementConfiguration.Read.All');
           AdminRoles=@('Global Reader','Intune Administrator'); AppOnlySupported=$true; RequiredLicence='Intune'; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/intune-deviceconfig-deviceconfiguration-list'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='AutopilotDevices'; Section='Devices'; ServiceGroup='Graph'; Level='Basic'; Workstream='Endpoint'; Workload='Autopilot';
           Output='AutopilotDevices.csv'; Endpoint='GET /deviceManagement/windowsAutopilotDeviceIdentities'; ApiVersion='v1.0';
           DelegatedPermissions=@('DeviceManagementServiceConfig.Read.All'); ApplicationPermissions=@('DeviceManagementServiceConfig.Read.All');
           AdminRoles=@('Global Reader','Intune Administrator'); AppOnlySupported=$true; RequiredLicence='Intune'; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/intune-enrollment-windowsautopilotdeviceidentity-list'; ValidationStatus='NotValidatedLive'; KnownLimitations='' }

        # ---- Usage reports (Graph child) ----
        @{ Name='UsageEmailActivity'; Section='Usage'; ServiceGroup='Graph'; Level='Basic'; Workstream='Messaging'; Workload='Exchange usage';
           Output='UsageEmailActivity.csv'; Endpoint='GET /reports/getEmailActivityUserDetail(period=D30)'; ApiVersion='v1.0';
           DelegatedPermissions=@('Reports.Read.All'); ApplicationPermissions=@('Reports.Read.All');
           AdminRoles=@('Reports Reader','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='UsageDetectionOnly';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/reportroot-getemailactivityuserdetail'; ValidationStatus='ValidatedLive';
           KnownLimitations='Usage data can be concealed (hashed) per tenant setting' }
        @{ Name='UsageTeamsActivity'; Section='Usage'; ServiceGroup='Graph'; Level='Basic'; Workstream='Collaboration'; Workload='Teams usage';
           Output='UsageTeamsActivity.csv'; Endpoint='GET /reports/getTeamsUserActivityUserDetail(period=D30)'; ApiVersion='v1.0';
           DelegatedPermissions=@('Reports.Read.All'); ApplicationPermissions=@('Reports.Read.All');
           AdminRoles=@('Reports Reader','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='UsageDetectionOnly';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/reportroot-getteamsuseractivityuserdetail'; ValidationStatus='ValidatedLive';
           KnownLimitations='Usage can be concealed' }
        @{ Name='UsageMailboxUsage'; Section='Usage'; ServiceGroup='Graph'; Level='Basic'; Workstream='Messaging'; Workload='Exchange usage';
           Output='UsageMailboxUsage.csv'; Endpoint='GET /reports/getMailboxUsageDetail(period=D30)'; ApiVersion='v1.0';
           DelegatedPermissions=@('Reports.Read.All'); ApplicationPermissions=@('Reports.Read.All');
           AdminRoles=@('Reports Reader','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='UsageDetectionOnly';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/reportroot-getmailboxusagedetail'; ValidationStatus='ValidatedLive'; KnownLimitations='' }
        @{ Name='UsageActiveUsers'; Section='Usage'; ServiceGroup='Graph'; Level='Basic'; Workstream='Identity'; Workload='M365 usage';
           Output='UsageActiveUsers.csv'; Endpoint='GET /reports/getOffice365ActiveUserDetail(period=D30)'; ApiVersion='v1.0';
           DelegatedPermissions=@('Reports.Read.All'); ApplicationPermissions=@('Reports.Read.All');
           AdminRoles=@('Reports Reader','Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='UsageDetectionOnly';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/reportroot-getoffice365activeuserdetail'; ValidationStatus='ValidatedLive';
           KnownLimitations='Usage can be concealed' }

        # ---- Cross-tenant / target (Graph/Exchange children) ----
        @{ Name='CrossTenantPartners'; Section='CrossTenant'; ServiceGroup='Graph'; Level='Basic'; Workstream='Governance'; Workload='Cross-tenant';
           Output='CrossTenantPartners.csv'; Endpoint='GET /policies/crossTenantAccessPolicy/partners'; ApiVersion='v1.0';
           DelegatedPermissions=@('Policy.Read.All'); ApplicationPermissions=@('Policy.Read.All');
           AdminRoles=@('Global Reader'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/graph/api/crosstenantaccesspolicy-list-partners'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Target role only' }
        @{ Name='DomainConflicts'; Section='TargetExchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Governance'; Workload='Cross-tenant';
           Output='DomainConflicts.csv'; Cmdlet='Get-AcceptedDomain (target, compared with source)'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-accepteddomain'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Target role only' }
        @{ Name='UserMatches'; Section='TargetExchange'; ServiceGroup='Exchange'; Level='Basic'; Workstream='Governance'; Workload='Cross-tenant';
           Output='UserMatches.csv'; Cmdlet='Get-EXORecipient (target, compared with source users)'; ApiVersion='PowerShell';
           DelegatedPermissions=@('Exchange.ManageAsApp'); ApplicationPermissions=@('Exchange.ManageAsApp');
           AdminRoles=@('Global Reader','Exchange Administrator'); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/exchange/get-exorecipient'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Target role only' }

        # ---- DNS (parent process) ----
        @{ Name='Dns'; Section='Dns'; ServiceGroup='Parent'; Level='Basic'; Workstream='Messaging'; Workload='DNS';
           Output='Dns.csv'; Cmdlet='Resolve-DnsName (MX/SPF/DMARC/DKIM/autodiscover)'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@(); AppOnlySupported=$true; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/dnsclient/resolve-dnsname'; ValidationStatus='ValidatedLive'; KnownLimitations='Public DNS only - private zones not visible' }

        # ---- Power Platform (PowerPlatform child) ----
        @{ Name='PowerPlatformEnvironments'; Section='PowerPlatform'; ServiceGroup='PowerPlatform'; Level='Basic'; Workstream='BusinessApps'; Workload='Power Platform';
           Output='PowerPlatformEnvironments.csv'; Cmdlet='Get-AdminPowerAppEnvironment'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Power Platform Administrator','Global Administrator'); AppOnlySupported=$false; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/microsoft.powerapps.administration.powershell/get-adminpowerappenvironment'; ValidationStatus='NotValidatedLive';
           KnownLimitations='App-only Add-PowerAppsAccount parameters not verified on Learn - delegated sign-in required' }
        @{ Name='PowerApps'; Section='PowerPlatform'; ServiceGroup='PowerPlatform'; Level='Basic'; Workstream='BusinessApps'; Workload='Power Apps';
           Output='PowerApps.csv'; Cmdlet='Get-AdminPowerApp per environment'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Power Platform Administrator','Global Administrator'); AppOnlySupported=$false; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/microsoft.powerapps.administration.powershell/get-adminpowerapp'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Delegated sign-in required' }
        @{ Name='PowerAutomateFlows'; Section='PowerPlatform'; ServiceGroup='PowerPlatform'; Level='Basic'; Workstream='BusinessApps'; Workload='Power Automate';
           Output='PowerAutomateFlows.csv'; Cmdlet='Get-AdminFlow per environment'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Power Platform Administrator','Global Administrator'); AppOnlySupported=$false; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/microsoft.powerapps.administration.powershell/get-adminflow'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Delegated sign-in required' }
        @{ Name='PowerPlatformConnectors'; Section='PowerPlatform'; ServiceGroup='PowerPlatform'; Level='Basic'; Workstream='BusinessApps'; Workload='Power Platform';
           Output='PowerPlatformConnectors.csv'; Cmdlet='Get-AdminPowerAppConnector per environment'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Power Platform Administrator','Global Administrator'); AppOnlySupported=$false; RequiredLicence=''; Coverage='Partial';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/microsoft.powerapps.administration.powershell/'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Custom connectors only' }
        @{ Name='PowerPlatformDlpPolicies'; Section='PowerPlatform'; ServiceGroup='PowerPlatform'; Level='Basic'; Workstream='Governance'; Workload='Power Platform DLP';
           Output='PowerPlatformDlpPolicies.csv'; Cmdlet='Get-DlpPolicy'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@('Power Platform Administrator','Global Administrator'); AppOnlySupported=$false; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/microsoft.powerapps.administration.powershell/'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Delegated sign-in required' }
        @{ Name='PowerBIWorkspaces'; Section='PowerPlatform'; ServiceGroup='PowerPlatform'; Level='Basic'; Workstream='BusinessApps'; Workload='Power BI';
           Output='PowerBIWorkspaces.csv'; Cmdlet='Get-PowerBIWorkspace -Scope Organization'; ApiVersion='PowerShell';
           DelegatedPermissions=@(); ApplicationPermissions=@('Tenant.Read.All');
           AdminRoles=@('Power BI Administrator'); AppOnlySupported=$false; RequiredLicence=''; Coverage='Full';
           DocsUrl='https://learn.microsoft.com/en-us/powershell/module/microsoftpowerbimgmt.workspaces/get-powerbiworkspace'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Optional MicrosoftPowerBIMgmt module; delegated sign-in' }

        # ---- No admin content API - manual discovery required ----
        @{ Name='Forms'; Section=''; ServiceGroup='Parent'; Level='Basic'; Workstream='Collaboration'; Workload='Microsoft Forms';
           Output=''; Endpoint=''; ApiVersion='';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@(); AppOnlySupported=$false; RequiredLicence=''; Coverage='ManualDiscoveryRequired';
           DocsUrl='https://learn.microsoft.com/en-us/microsoft-forms/'; ValidationStatus='NotValidatedLive';
           KnownLimitations='No admin content API - detect usage via FORMS* service plans; ask the customer' }
        @{ Name='Loop'; Section=''; ServiceGroup='Parent'; Level='Basic'; Workstream='Collaboration'; Workload='Microsoft Loop';
           Output=''; Endpoint=''; ApiVersion='';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@(); AppOnlySupported=$false; RequiredLicence=''; Coverage='ManualDiscoveryRequired';
           DocsUrl='https://learn.microsoft.com/en-us/microsoft-loop/'; ValidationStatus='NotValidatedLive';
           KnownLimitations='No admin API - LOOP*/service-plan indicator only' }
        @{ Name='Whiteboard'; Section=''; ServiceGroup='Parent'; Level='Basic'; Workstream='Collaboration'; Workload='Microsoft Whiteboard';
           Output=''; Endpoint=''; ApiVersion='';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@(); AppOnlySupported=$false; RequiredLicence=''; Coverage='ManualDiscoveryRequired';
           DocsUrl='https://learn.microsoft.com/en-us/microsoft-365-whiteboard/'; ValidationStatus='NotValidatedLive';
           KnownLimitations='No admin content API' }
        @{ Name='Sway'; Section=''; ServiceGroup='Parent'; Level='Basic'; Workstream='Collaboration'; Workload='Microsoft Sway';
           Output=''; Endpoint=''; ApiVersion='';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@(); AppOnlySupported=$false; RequiredLicence=''; Coverage='ManualDiscoveryRequired';
           DocsUrl='https://learn.microsoft.com/en-us/microsoft-365-sway/'; ValidationStatus='NotValidatedLive';
           KnownLimitations='No admin content API' }
        @{ Name='VivaGlint'; Section=''; ServiceGroup='Parent'; Level='Basic'; Workstream='Collaboration'; Workload='Viva Glint';
           Output=''; Endpoint=''; ApiVersion='';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@(); AppOnlySupported=$false; RequiredLicence=''; Coverage='ManualDiscoveryRequired';
           DocsUrl='https://learn.microsoft.com/en-us/viva/glint/'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Ask the customer; service-plan indicator only' }
        @{ Name='VivaPulse'; Section=''; ServiceGroup='Parent'; Level='Basic'; Workstream='Collaboration'; Workload='Viva Pulse';
           Output=''; Endpoint=''; ApiVersion='';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@(); AppOnlySupported=$false; RequiredLicence=''; Coverage='ManualDiscoveryRequired';
           DocsUrl='https://learn.microsoft.com/en-us/viva/pulse/'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Ask the customer; service-plan indicator only' }
        @{ Name='VivaAmplify'; Section=''; ServiceGroup='Parent'; Level='Basic'; Workstream='Collaboration'; Workload='Viva Amplify';
           Output=''; Endpoint=''; ApiVersion='';
           DelegatedPermissions=@(); ApplicationPermissions=@();
           AdminRoles=@(); AppOnlySupported=$false; RequiredLicence=''; Coverage='ManualDiscoveryRequired';
           DocsUrl='https://learn.microsoft.com/en-us/viva/amplify/'; ValidationStatus='NotValidatedLive';
           KnownLimitations='Ask the customer; service-plan indicator only' }
    )
}
