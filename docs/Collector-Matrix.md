# Collector matrix

Generated from `00-Assessment/Collectors.psd1` by `tools/New-CollectorMatrix.ps1`. Do not edit by hand.

`ValidationStatus` is `ValidatedLive` only for collectors that have run successfully against a real tenant.

## API capability matrix

| Workstream | Workload | Collector | Level | Cmdlet/Endpoint | ApiVersion | Coverage | AppOnly | Licence | Limitations | Docs | Validation |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Identity | Organization | Organization | Basic | GET /organization | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/organization-list | ValidatedLive |
| Identity | Domains | Domains | Basic | GET /domains | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/domain-list | ValidatedLive |
| Identity | Licences | Licenses | Basic | GET /subscribedSkus | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/subscribedsku-list | ValidatedLive |
| Identity | Licences | LicenseServicePlans | Basic | GET /subscribedSkus (servicePlans per SKU) | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/subscribedsku-list | ValidatedLive |
| Identity | Users | Users | Basic | GET /users | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/user-list | ValidatedLive |
| Identity | Groups | Groups | Basic | GET /groups + /transitiveMembers/$count + /owners/$count per group | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/group-list | ValidatedLive |
| Identity | Roles and admins | AdminRoles | Basic | GET /roleManagement/directory/roleAssignments?$expand=principal | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignments | ValidatedLive |
| Collaboration | Planner | PlannerPlans | Advanced | GET /groups/{id}/planner/plans per M365 group | v1.0 | Partial | Yes | - | Plans only (no tasks/buckets); skipped entirely on 403 | https://learn.microsoft.com/en-us/graph/api/plannergroup-list-plans | NotValidatedLive |
| Security | Conditional Access | ConditionalAccess | Basic | GET /identity/conditionalAccess/policies | v1.0 | Full | Yes | Entra ID P1 | - | https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-list-policies | ValidatedLive |
| Security | Conditional Access | NamedLocations | Basic | GET /identity/conditionalAccess/namedLocations | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-list-namedlocations | ValidatedLive |
| Security | Authentication methods | AuthMethodsPolicy | Basic | GET /policies/authenticationMethodsPolicy | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/authenticationmethodspolicy-get | ValidatedLive |
| Security | MFA registration | MfaRegistration | Basic | GET /reports/authenticationMethods/userRegistrationDetails | v1.0 | Full | Yes | Entra ID P1 | - | https://learn.microsoft.com/en-us/graph/api/userregistrationdetails-list | ValidatedLive |
| Identity | App registrations | AppRegistrations | Basic | GET /applications | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/application-list | ValidatedLive |
| Identity | Enterprise applications | EnterpriseApps | Basic | GET /servicePrincipals | v1.0 | Full | Yes | - | Microsoft first-party apps excluded | https://learn.microsoft.com/en-us/graph/api/serviceprincipal-list | ValidatedLive |
| Security | App permissions | AppPermissions | Advanced | GET /servicePrincipals/{id}/appRoleAssignments per app + GET /oauth2PermissionGrants | v1.0 | Full | Yes | - | Resource names resolved via one extra call per resource service principal | https://learn.microsoft.com/en-us/graph/api/serviceprincipal-list-approleassignments | NotValidatedLive |
| Security | App permissions | AppRegistrationPermissions | Basic | requiredResourceAccess on GET /applications | v1.0 | Full | Yes | - | Requested, not necessarily granted, permissions | https://learn.microsoft.com/en-us/graph/api/resources/requiredresourceaccess | NotValidatedLive |
| Identity | App usage | AppSignInActivity | Basic | GET /beta/reports/servicePrincipalSignInActivities + service principal list | beta | Partial | Yes | Entra ID P1 | Activity report is preview and can be stale - never used alone to call an app unused | https://learn.microsoft.com/en-us/graph/api/reportroot-list-serviceprincipalsigninactivities | ValidatedLive |
| Identity | App usage | AppSignInLogs | Advanced | GET /beta/auditLogs/signIns per app per event type | beta | Partial | Yes | Entra ID P1 | Writes into AppSignInActivity.csv; throttled - ~14 s per query observed; Microsoft first-party apps skipped unless -IncludeMicrosoftAppsInSignInLogs | https://learn.microsoft.com/en-us/graph/api/signin-list | ValidatedLive |
| Messaging | Exchange mailboxes | Mailboxes | Basic | Get-EXOMailbox / Get-Mailbox (fallbacks) | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2 | ValidatedLive |
| Messaging | Exchange mailboxes | MailboxStatistics | Basic | Get-EXOMailboxStatistics (+Get-MailboxLocation -User for aux archives) | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailboxstatistics | ValidatedLive |
| Messaging | Exchange mailboxes | AuxArchiveCount | Advanced | Get-MailboxLocation -User <ExchangeGuid> per archive mailbox | PowerShell | Partial | Yes | - | Writes AuxArchiveCount into MailboxStatistics.csv/Mailboxes.csv | https://learn.microsoft.com/en-us/powershell/module/exchange/get-maillocation | ValidatedLive |
| Messaging | Exchange mailboxes | MailboxHolds | Basic | Get-EXOMailbox hold properties | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailbox | ValidatedLive |
| Messaging | Mailbox permissions | MailboxPermissions | Advanced | Get-EXOMailboxPermission per mailbox | PowerShell | Full | Yes | - | Per-mailbox loop - slow on large tenants | https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailboxpermission | ValidatedLive |
| Messaging | Mailbox permissions | SendAsPermissions | Advanced | Get-EXORecipientPermission per mailbox | PowerShell | Full | Yes | - | Per-mailbox loop | https://learn.microsoft.com/en-us/powershell/module/exchange/get-exorecipientpermission | ValidatedLive |
| Messaging | Distribution groups | DistributionGroups | Basic | Get-DistributionGroup / Get-DynamicDistributionGroup | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-distributiongroup | ValidatedLive |
| Messaging | Contacts | MailContacts | Basic | Get-MailContact | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailcontact | ValidatedLive |
| Messaging | Contacts | MailUsers | Basic | Get-MailUser | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailuser | ValidatedLive |
| Messaging | Mail flow | AcceptedDomains | Basic | Get-AcceptedDomain | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-accepteddomain | ValidatedLive |
| Messaging | Mail flow | InboundConnectors | Basic | Get-InboundConnector | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-inboundconnector | ValidatedLive |
| Messaging | Mail flow | OutboundConnectors | Basic | Get-OutboundConnector | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-outboundconnector | ValidatedLive |
| Messaging | Mail flow | TransportRules | Basic | Get-TransportRule | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-transportrule | ValidatedLive |
| Messaging | Mail flow | DkimSigningConfig | Basic | Get-DkimSigningConfig | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-dkimsigningconfig | ValidatedLive |
| Messaging | Mail flow | RemoteDomains | Basic | Get-RemoteDomain | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-remotedomain | ValidatedLive |
| Messaging | Sharing | OrganizationRelationships | Basic | Get-OrganizationRelationship | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-organizationrelationship | ValidatedLive |
| Messaging | Public folders | PublicFolderMailboxes | Basic | Get-EXOMailbox -PublicFolder | PowerShell | Partial | Yes | - | Public folder mailboxes only - no folder tree or sizes | https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailbox | ValidatedLive |
| Messaging | Bookings | BookingsMailboxes | Basic | Get-EXOMailbox -RecipientTypeDetails SchedulingMailbox | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailbox | NotValidatedLive |
| Compliance | Retention | RetentionPolicies | Basic | Get-RetentionPolicy | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-retentionpolicy | ValidatedLive |
| Compliance | Retention | RetentionRules | Basic | Get-RetentionPolicyTag | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-retentionpolicytag | ValidatedLive |
| Messaging | Mail flow | JournalRules | Basic | Get-JournalRule | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-journalrule | NotValidatedLive |
| BusinessApps | Outlook add-ins | OutlookAddins | Advanced | Get-App -OrganizationApp | PowerShell | Partial | Yes | - | Admin-deployed org apps only - per-user add-ins not listed | https://learn.microsoft.com/en-us/powershell/module/exchange/get-app | NotValidatedLive |
| Messaging | Migration | MigrationEndpoints | Basic | Get-MigrationEndpoint | PowerShell | Full | Yes | - | Target role only | https://learn.microsoft.com/en-us/powershell/module/exchange/get-migrationendpoint | NotValidatedLive |
| Compliance | Customer Key | CustomerKey | Basic | Get-DataEncryptionPolicy (+Get-SPODataEncryptionPolicy) | PowerShell | Partial | Yes | - | Merged with SPO-side rows when available | https://learn.microsoft.com/en-us/powershell/module/exchange/get-dataencryptionpolicy | NotValidatedLive |
| Compliance | Sensitivity labels | SensitivityLabels | Basic | Get-Label | PowerShell | Partial | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-label | NotValidatedLive |
| Compliance | DLP | DlpPolicies | Basic | Get-DlpCompliancePolicy | PowerShell | Partial | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-dlpcompliancepolicy | ValidatedLive |
| Compliance | eDiscovery | ComplianceCases | Basic | Get-ComplianceCase | PowerShell | Partial | No | - | eDiscovery cmdlets are not supported in app-only auth (Learn) | https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2 | NotValidatedLive |
| Compliance | eDiscovery | CaseHoldPolicies | Basic | Get-CaseHoldPolicy | PowerShell | Partial | No | - | eDiscovery cmdlets are not supported in app-only auth (Learn) | https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2 | NotValidatedLive |
| Compliance | eDiscovery | EDiscoveryCases | Basic | GET /security/cases/eDiscoveryCases | v1.0 | Partial | Yes | - | Graph fallback when IPPS is not connected | https://learn.microsoft.com/en-us/graph/api/security-ediscoverycase-list | NotValidatedLive |
| Compliance | eDiscovery | EDiscoveryHolds | Basic | GET /security/cases/eDiscoveryCases/{id}/custodians | v1.0 | Partial | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/security-ediscoverycustodian-list | NotValidatedLive |
| Collaboration | OneDrive | OneDrive | Basic | Get-SPOSite -IncludePersonalSite / Graph fallback | PowerShell | Partial | Yes | - | SPO admin has no certificate app-only auth - in app-only mode the Graph fallback runs (usage-report based) | https://learn.microsoft.com/en-us/powershell/sharepoint/sharepoint-online/connect-sharepoint-online | ValidatedLive |
| Collaboration | OneDrive | OneDriveUsage | Basic | GET /reports/getOneDriveUsageAccountDetail(period=D30) | v1.0 | UsageDetectionOnly | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/reportroot-getonedriveusageaccountdetail | ValidatedLive |
| Collaboration | SharePoint | SharePointSites | Basic | Get-SPOSite -Limit All / Graph fallback | PowerShell | Partial | Yes | - | SPO admin has no certificate app-only auth - in app-only mode the Graph fallback runs (may undercount sites) | https://learn.microsoft.com/en-us/powershell/sharepoint/sharepoint-online/connect-sharepoint-online | ValidatedLive |
| Collaboration | SharePoint | SharePointTenant | Basic | Get-SPOTenant | PowerShell | Full | No | - | SPO admin PowerShell only (delegated interactive) | https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spotenant | NotValidatedLive |
| Security | External sharing | ExternalUsers | Basic | Get-SPOExternalUser | PowerShell | Full | No | - | SPO admin PowerShell only | https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spoexternaluser | NotValidatedLive |
| BusinessApps | SharePoint apps | SharePointAppCatalog | Advanced | Get-SPOAppInfo -Name ' ' | PowerShell | Partial | No | - | SPO admin PowerShell only; installed apps, not package versions | https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spoappinfo | NotValidatedLive |
| Collaboration | Teams | Teams | Basic | GET /groups (Team provisioning) + /teams/{id} + member/owner counts | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/team-get | ValidatedLive |
| Collaboration | Teams | TeamsChannels | Basic | GET /teams/{id}/allChannels per team | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/team-list-allchannels | ValidatedLive |
| BusinessApps | Teams apps | TeamsCustomApps | Basic | GET /appCatalogs/teamsApps?$filter=distributionMethod eq 'organization' | v1.0 | Partial | Yes | - | Org-uploaded apps only; user-context API | https://learn.microsoft.com/en-us/graph/api/appcatalogs-list-teamsapps | NotValidatedLive |
| BusinessApps | Teams apps | TeamsInstalledApps | Advanced | GET /teams/{id}/installedApps per team | v1.0 | Partial | Yes | - | Includes store apps; no publisher field to filter Microsoft apps | https://learn.microsoft.com/en-us/graph/api/team-list-installedapps | NotValidatedLive |
| Collaboration | Teams Phone | TeamsPhoneUsers | Basic | Get-CsOnlineUser / Get-CsOnlineVoiceUser | PowerShell | Partial | Yes | Teams Phone licence | Skipped when no Teams Phone licence in the tenant | https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-supported-versions | NotValidatedLive |
| Collaboration | Teams Phone | TeamsAutoAttendants | Basic | Get-CsAutoAttendant | PowerShell | Full | Yes | Teams Phone licence | - | https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-supported-versions | NotValidatedLive |
| Collaboration | Teams Phone | TeamsCallQueues | Basic | Get-CsCallQueue | PowerShell | Full | Yes | Teams Phone licence | - | https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-supported-versions | NotValidatedLive |
| Collaboration | Teams Phone | TeamsPhoneGateways | Basic | Get-CsOnlinePSTNGateway | PowerShell | Full | Yes | Teams Phone licence | - | https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-supported-versions | NotValidatedLive |
| Collaboration | Teams Phone | TeamsPhoneNumbers | Basic | Get-CsPhoneNumberAssignment | PowerShell | Full | Yes | Teams Phone licence | - | https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-supported-versions | NotValidatedLive |
| Collaboration | Teams Phone | TeamsMeetingPolicies | Basic | Get-CsTeamsMeetingPolicy | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-supported-versions | NotValidatedLive |
| Collaboration | Teams Phone | TeamsPhoneVoiceRoutes | Basic | Get-CsOnlineVoiceRoute | PowerShell | Full | Yes | Teams Phone licence | - | https://learn.microsoft.com/en-us/microsoftteams/teams-powershell-supported-versions | NotValidatedLive |
| Endpoint | Devices (Intune) | IntuneDevices | Basic | GET /deviceManagement/managedDevices | v1.0 | Full | Yes | Intune | - | https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-list | ValidatedLive |
| Endpoint | Devices (Entra) | EntraDevices | Basic | GET /devices | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/device-list | ValidatedLive |
| Endpoint | Intune configuration | IntunePolicies | Basic | GET /deviceManagement/deviceConfigurations + compliancePolicies | v1.0 | Partial | Yes | Intune | - | https://learn.microsoft.com/en-us/graph/api/intune-deviceconfig-deviceconfiguration-list | ValidatedLive |
| Endpoint | Autopilot | AutopilotDevices | Basic | GET /deviceManagement/windowsAutopilotDeviceIdentities | v1.0 | Full | Yes | Intune | - | https://learn.microsoft.com/en-us/graph/api/intune-enrollment-windowsautopilotdeviceidentity-list | NotValidatedLive |
| Messaging | Exchange usage | UsageEmailActivity | Basic | GET /reports/getEmailActivityUserDetail(period=D30) | v1.0 | UsageDetectionOnly | Yes | - | Usage data can be concealed (hashed) per tenant setting | https://learn.microsoft.com/en-us/graph/api/reportroot-getemailactivityuserdetail | ValidatedLive |
| Collaboration | Teams usage | UsageTeamsActivity | Basic | GET /reports/getTeamsUserActivityUserDetail(period=D30) | v1.0 | UsageDetectionOnly | Yes | - | Usage can be concealed | https://learn.microsoft.com/en-us/graph/api/reportroot-getteamsuseractivityuserdetail | ValidatedLive |
| Messaging | Exchange usage | UsageMailboxUsage | Basic | GET /reports/getMailboxUsageDetail(period=D30) | v1.0 | UsageDetectionOnly | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/reportroot-getmailboxusagedetail | ValidatedLive |
| Identity | M365 usage | UsageActiveUsers | Basic | GET /reports/getOffice365ActiveUserDetail(period=D30) | v1.0 | UsageDetectionOnly | Yes | - | Usage can be concealed | https://learn.microsoft.com/en-us/graph/api/reportroot-getoffice365activeuserdetail | ValidatedLive |
| Governance | Cross-tenant | CrossTenantPartners | Basic | GET /policies/crossTenantAccessPolicy/partners | v1.0 | Full | Yes | - | Target role only | https://learn.microsoft.com/en-us/graph/api/crosstenantaccesspolicy-list-partners | NotValidatedLive |
| Governance | Cross-tenant | DomainConflicts | Basic | Get-AcceptedDomain (target, compared with source) | PowerShell | Full | Yes | - | Target role only | https://learn.microsoft.com/en-us/powershell/module/exchange/get-accepteddomain | NotValidatedLive |
| Governance | Cross-tenant | UserMatches | Basic | Get-EXORecipient (target, compared with source users) | PowerShell | Full | Yes | - | Target role only | https://learn.microsoft.com/en-us/powershell/module/exchange/get-exorecipient | NotValidatedLive |
| Messaging | DNS | Dns | Basic | Resolve-DnsName (MX/SPF/DMARC/DKIM/autodiscover) | PowerShell | Full | Yes | - | Public DNS only - private zones not visible | https://learn.microsoft.com/en-us/powershell/module/dnsclient/resolve-dnsname | ValidatedLive |
| BusinessApps | Power Platform | PowerPlatformEnvironments | Basic | Get-AdminPowerAppEnvironment | PowerShell | Full | No | - | App-only Add-PowerAppsAccount parameters not verified on Learn - delegated sign-in required | https://learn.microsoft.com/en-us/powershell/module/microsoft.powerapps.administration.powershell/get-adminpowerappenvironment | NotValidatedLive |
| BusinessApps | Power Apps | PowerApps | Basic | Get-AdminPowerApp per environment | PowerShell | Full | No | - | Delegated sign-in required | https://learn.microsoft.com/en-us/powershell/module/microsoft.powerapps.administration.powershell/get-adminpowerapp | NotValidatedLive |
| BusinessApps | Power Automate | PowerAutomateFlows | Basic | Get-AdminFlow per environment | PowerShell | Full | No | - | Delegated sign-in required | https://learn.microsoft.com/en-us/powershell/module/microsoft.powerapps.administration.powershell/get-adminflow | NotValidatedLive |
| BusinessApps | Power Platform | PowerPlatformConnectors | Basic | Get-AdminPowerAppConnector per environment | PowerShell | Partial | No | - | Custom connectors only | https://learn.microsoft.com/en-us/powershell/module/microsoft.powerapps.administration.powershell/ | NotValidatedLive |
| Governance | Power Platform DLP | PowerPlatformDlpPolicies | Basic | Get-DlpPolicy | PowerShell | Full | No | - | Delegated sign-in required | https://learn.microsoft.com/en-us/powershell/module/microsoft.powerapps.administration.powershell/ | NotValidatedLive |
| BusinessApps | Power BI | PowerBIWorkspaces | Basic | Get-PowerBIWorkspace -Scope Organization | PowerShell | Full | No | - | Optional MicrosoftPowerBIMgmt module; delegated sign-in | https://learn.microsoft.com/en-us/powershell/module/microsoftpowerbimgmt.workspaces/get-powerbiworkspace | NotValidatedLive |
| Collaboration | Microsoft Forms | Forms | Basic | - | - | ManualDiscoveryRequired | No | - | No admin content API - detect usage via FORMS* service plans; ask the customer | https://learn.microsoft.com/en-us/microsoft-forms/ | NotValidatedLive |
| Collaboration | Microsoft Loop | Loop | Basic | - | - | ManualDiscoveryRequired | No | - | No admin API - LOOP*/service-plan indicator only | https://learn.microsoft.com/en-us/microsoft-loop/ | NotValidatedLive |
| Collaboration | Microsoft Whiteboard | Whiteboard | Basic | - | - | ManualDiscoveryRequired | No | - | No admin content API | https://learn.microsoft.com/en-us/microsoft-365-whiteboard/ | NotValidatedLive |
| Collaboration | Microsoft Sway | Sway | Basic | - | - | ManualDiscoveryRequired | No | - | No admin content API | https://learn.microsoft.com/en-us/microsoft-365-sway/ | NotValidatedLive |
| Collaboration | Viva Glint | VivaGlint | Basic | - | - | ManualDiscoveryRequired | No | - | Ask the customer; service-plan indicator only | https://learn.microsoft.com/en-us/viva/glint/ | NotValidatedLive |
| Collaboration | Viva Pulse | VivaPulse | Basic | - | - | ManualDiscoveryRequired | No | - | Ask the customer; service-plan indicator only | https://learn.microsoft.com/en-us/viva/pulse/ | NotValidatedLive |
| Collaboration | Viva Amplify | VivaAmplify | Basic | - | - | ManualDiscoveryRequired | No | - | Ask the customer; service-plan indicator only | https://learn.microsoft.com/en-us/viva/amplify/ | NotValidatedLive |
| Governance | Entra ID policies | AuthorizationPolicy | Basic | GET /policies/authorizationPolicy | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/authorizationpolicy-get | NotValidatedLive |
| Governance | Entra ID policies | AdminConsentRequestPolicy | Basic | GET /policies/adminConsentRequestPolicy | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/adminconsentrequestpolicy-get | NotValidatedLive |
| Governance | Entra ID policies | GroupSettings | Basic | GET /groupSettings | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/groupsetting-list | NotValidatedLive |
| Governance | Groups | GroupLifecyclePolicies | Basic | GET /groupLifecyclePolicies | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/grouplifecyclepolicy-list | NotValidatedLive |
| Security | Cross-tenant access | CrossTenantAccessPolicy | Basic | GET /policies/crossTenantAccessPolicy + /partners | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/crosstenantaccesspolicy-list-partners | NotValidatedLive |
| Identity | Roles and admins | AdministrativeUnits | Basic | GET /directory/administrativeUnits + /members/$count | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/administrativeunit-list | NotValidatedLive |
| Governance | Partner access (GDAP) | DelegatedAdminRelationships | Basic | GET /tenantRelationships/delegatedAdminRelationships | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/tenantrelationship-list-delegatedadminrelationships | NotValidatedLive |
| Collaboration | Groups | GroupDetails | Advanced | GET /groups/{id}/members/$count + /owners | v1.0 | Partial | Yes | - | Per-group calls; owners capped at first page | https://learn.microsoft.com/en-us/graph/api/group-get-members | NotValidatedLive |
| Security | Authentication | AuthStrengths | Basic | GET /policies/authenticationStrengthPolicies | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/authenticationstrengthpolicy-list | NotValidatedLive |
| Identity | Roles and admins | CustomDirectoryRoles | Basic | GET /roleManagement/directory/roleDefinitions?$filter=isBuiltIn eq false | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/unifiedroledefinition-list | NotValidatedLive |
| Security | PIM | PimAssignments | Basic | GET /roleManagement/directory/roleEligibilitySchedules + /roleAssignmentSchedules | v1.0 | Full | Yes | Entra ID P2 | Requires Entra ID P2 (AAD_PREMIUM_P2) | https://learn.microsoft.com/en-us/graph/api/rolemanagement-directory-list-roleeligibilityschedules | NotValidatedLive |
| BusinessApps | Enterprise applications | AppOwners | Basic | GET /applications/{id}/owners | v1.0 | Full | Yes | - | One call per app registration | https://learn.microsoft.com/en-us/graph/api/application-list-owners | NotValidatedLive |
| BusinessApps | App registrations | AppRedirectUris | Basic | GET /applications (web/spa/publicClient) | v1.0 | Full | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/resources/application | NotValidatedLive |
| Security | App credentials | AppCredentials | Basic | GET /applications + /servicePrincipals (keyCredentials/passwordCredentials) | v1.0 | Full | Yes | - | Metadata only - no secretText or key material | https://learn.microsoft.com/en-us/graph/api/resources/keycredential | NotValidatedLive |
| Security | Enterprise applications | SamlCertificates | Basic | GET /servicePrincipals (keyCredentials, preferredSingleSignOnMode=saml) | v1.0 | Full | Yes | - | Metadata only | https://learn.microsoft.com/en-us/graph/api/resources/serviceprincipal | NotValidatedLive |
| Identity | App provisioning (SCIM) | ProvisioningJobs | Advanced | GET /servicePrincipals/{id}/synchronization/jobs | v1.0 | Full | Yes | - | One call per enterprise app; 404 = no provisioning | https://learn.microsoft.com/en-us/graph/api/synchronization-synchronization-list-jobs | NotValidatedLive |
| Messaging | Exchange Online | RecoverableItemsSize | Advanced | Get-EXOMailboxFolderStatistics -FolderScope RecoverableItems | PowerShell | Partial | Yes | - | Per-mailbox call; NOT included in totalMailboxGB | https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailboxfolderstatistics | NotValidatedLive |
| Messaging | Exchange Online | SmtpClientAuth | Basic | Get-TransportConfig | PowerShell | Full | Yes | - | Org default only | https://learn.microsoft.com/en-us/exchange/clients-and-mobile-in-exchange-online/authenticated-client-smtp-submission | NotValidatedLive |
| Messaging | Exchange Online | SmtpClientAuthPerMailbox | Advanced | Get-CASMailbox -ResultSize Unlimited | PowerShell | Partial | Yes | - | Only mailboxes with an explicit override are listed | https://learn.microsoft.com/en-us/powershell/module/exchange/get-casmailbox | NotValidatedLive |
| Messaging | Exchange Online | InactiveMailboxes | Basic | Get-EXOMailbox -InactiveMailboxOnly | PowerShell | Full | Yes | - | Inactive mailboxes are not moved by cross-tenant migration tools | https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailbox | NotValidatedLive |
| Messaging | Exchange Online | SoftDeletedMailboxes | Basic | Get-EXOMailbox -SoftDeletedMailbox | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailbox | NotValidatedLive |
| Messaging | Groups | DynamicDistributionGroups | Basic | Get-DynamicDistributionGroup + Get-DynamicDistributionGroupMember | PowerShell | Full | Yes | - | Membership cannot be exported statically - filter must be recreated | https://learn.microsoft.com/en-us/powershell/module/exchange/get-dynamicdistributiongroup | NotValidatedLive |
| Messaging | Groups | DistributionGroupMembers | Advanced | Get-DistributionGroupMember + Get-Recipient | PowerShell | Partial | Yes | - | Member counts + owners; full member lists only at -Level Deep | https://learn.microsoft.com/en-us/powershell/module/exchange/get-distributiongroupmember | NotValidatedLive |
| Messaging | Resource mailboxes | CalendarProcessing | Basic | Get-CalendarProcessing | PowerShell | Full | Yes | - | Room and equipment mailboxes only | https://learn.microsoft.com/en-us/powershell/module/exchange/get-calendarprocessing | NotValidatedLive |
| Messaging | Exchange Online | CalendarPermissions | Deep | Get-MailboxFolderPermission <guid>:\Calendar | PowerShell | Partial | Yes | - | One call per mailbox - expensive on large tenants | https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailboxfolderpermission | NotValidatedLive |
| Security | Exchange Online | InboxRuleForwarding | Deep | Get-InboxRule -Mailbox <guid> | PowerShell | Partial | Yes | - | Target domains + rule name only - no rule bodies or addresses | https://learn.microsoft.com/en-us/powershell/module/exchange/get-inboxrule | NotValidatedLive |
| Messaging | Exchange Online | SharingPolicies | Basic | Get-SharingPolicy | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-sharingpolicy | NotValidatedLive |
| Messaging | Exchange Online | AddressLists | Basic | Get-AddressList + Get-GlobalAddressList + Get-AddressBookPolicy + Get-OfflineAddressBook | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-addresslist | NotValidatedLive |
| Compliance | Exchange MRM | MrmRetention | Basic | Get-RetentionPolicyTag + Get-RetentionPolicy | PowerShell | Full | Yes | - | Exchange MRM - distinct from Purview retention | https://learn.microsoft.com/en-us/powershell/module/exchange/get-retentionpolicytag | NotValidatedLive |
| Compliance | Exchange MRM | MrmRetentionPolicies | Basic | Get-RetentionPolicy | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-retentionpolicy | NotValidatedLive |
| Security | Exchange Online | ApplicationAccessPolicies | Basic | Get-ApplicationAccessPolicy | PowerShell | Full | Yes | - | EWS application scoping - recreate in target | https://learn.microsoft.com/en-us/powershell/module/exchange/get-applicationaccesspolicy | NotValidatedLive |
| Security | Exchange Online | ServicePrincipalRoleAssignments | Basic | Get-ServicePrincipal + Get-ManagementRoleAssignment | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/exchange/get-serviceprincipal | NotValidatedLive |
| Messaging | Exchange hybrid | HybridIndicators | Basic | Get-IntraOrganizationConnector + Get-HybridConfiguration | PowerShell | Partial | Yes | - | Indicates on-prem Exchange hybrid - migration must consider free/busy and mail routing | https://learn.microsoft.com/en-us/powershell/module/exchange/get-intraorganizationconnector | NotValidatedLive |
| Collaboration | SharePoint Online | HubSites | Basic | Get-SPOHubSite | PowerShell | Full | No | - | Association via HubSiteId column on SharePointSites.csv | https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spohubsite | NotValidatedLive |
| Collaboration | SharePoint Online | SiteAdmins | Advanced | Get-SPOUser -Site <url> | PowerShell | Partial | No | - | One call per site - expensive on large tenants | https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spouser | NotValidatedLive |
| Collaboration | OneDrive | DeletedOneDrives | Basic | Get-SPODeletedSite -IncludeOnlyPersonalSite | PowerShell | Full | No | - | Soft-deleted personal sites within retention | https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spodeletedsite | NotValidatedLive |
| Collaboration | SharePoint Online | SiteLists | Deep | GET /sites/{id}/lists | v1.0 | Partial | Yes | - | Runs only when SharePoint executes in the Graph process (fallback mode) - needs Graph site IDs | https://learn.microsoft.com/en-us/graph/api/site-list-lists | NotValidatedLive |
| Collaboration | SharePoint Online | SiteUniquePermissions | Deep | - | - | ManualDiscoveryRequired | No | - | Needs PnP/per-item REST calls - out of scope; assess per-site | https://learn.microsoft.com/en-us/sharepoint/unique-permissions-in-sharepoint-server | NotValidatedLive |
| Collaboration | OneDrive | OneDriveKFM | Basic | - | - | ManualDiscoveryRequired | No | - | Known Folder Move is client-side - assess via device policies/user survey | https://learn.microsoft.com/en-us/sharepoint/redirect-known-folders | NotValidatedLive |
| Messaging | Mail flow | ThirdPartyEvidence | Basic | Resolve-DnsName (MX/SPF) + Exchange connectors CSVs | PowerShell | Partial | Yes | - | Rows only on concrete record matches (Mimecast/Proofpoint/Hornetsecurity/Barracuda/CodeTwo/Exclaimer/external MX) | https://learn.microsoft.com/en-us/exchange/mail-flow-best-practices/use-connectors-to-configure-mail-flow/use-connectors-to-configure-mail-flow | NotValidatedLive |
| Collaboration | Microsoft Teams | TeamsConfig | Basic | Get-CsTenantFederationConfiguration + Get-CsTeams*Configuration + Get-CsTeams*Policy | PowerShell | Partial | Yes | - | Policy inventory is names only | https://learn.microsoft.com/en-us/powershell/module/teams/ | NotValidatedLive |
| Collaboration | Microsoft Teams | TeamsFederation | Basic | Get-CsTenantFederationConfiguration | PowerShell | Full | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/teams/get-cstenantfederationconfiguration | NotValidatedLive |
| Collaboration | Microsoft Teams | TeamsGuestConfig | Basic | Get-CsTeamsClientConfiguration + Get-CsTeamsGuestMeetingConfiguration + Get-CsTeamsGuestMessagingConfiguration | PowerShell | Partial | Yes | - | - | https://learn.microsoft.com/en-us/powershell/module/teams/get-csteamsclientconfiguration | NotValidatedLive |
| Collaboration | Microsoft Teams | TeamsPolicies | Basic | Get-CsTeamsMeetingPolicy/MessagingPolicy/AppSetupPolicy/AppPermissionPolicy/CallingPolicy/UpdatePolicy | PowerShell | Partial | Yes | - | Names only - no per-policy user counts | https://learn.microsoft.com/en-us/powershell/module/teams/get-csteamsmeetingpolicy | NotValidatedLive |
| Collaboration | Microsoft Teams | TeamTabs | Deep | GET /teams/{id}/channels/{id}/tabs | v1.0 | ManualDiscoveryRequired | No | - | Per-channel tab listing needs one call per channel - too costly for inventory; assess during migration design | https://learn.microsoft.com/en-us/graph/api/channel-list-tabs | NotValidatedLive |
| Collaboration | M365 apps usage | UsageM365Apps | Basic | GET /reports/getM365AppUserDetail(period='D30') | v1.0 | UsageDetectionOnly | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/reportroot-getm365appuserdetail | NotValidatedLive |
| Endpoint | Office activations | UsageOfficeActivations | Basic | GET /reports/getOffice365ActivationsUserDetail | v1.0 | UsageDetectionOnly | Yes | - | No period parameter | https://learn.microsoft.com/en-us/graph/api/reportroot-getoffice365activationsuserdetail | NotValidatedLive |
| Collaboration | M365 Groups | UsageGroupsActivity | Basic | GET /reports/getOffice365GroupsActivityDetail(period='D30') | v1.0 | UsageDetectionOnly | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/reportroot-getoffice365groupsactivitydetail | NotValidatedLive |
| Collaboration | Viva Engage (Yammer) | UsageYammer | Basic | GET /reports/getYammerActivityUserDetail(period='D30') | v1.0 | UsageDetectionOnly | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/reportroot-getyammeractivityuserdetail | NotValidatedLive |
| Endpoint | Microsoft Teams | UsageTeamsDevices | Basic | GET /reports/getTeamsDeviceUsageUserDetail(period='D30') | v1.0 | UsageDetectionOnly | Yes | - | - | https://learn.microsoft.com/en-us/graph/api/reportroot-getteamsdeviceusageuserdetail | NotValidatedLive |
| BusinessApps | Microsoft 365 Copilot | UsageCopilot | Basic | GET /reports/getMicrosoft365CopilotUsageUserDetail(period='D30') | beta | UsageDetectionOnly | Yes | - | beta endpoint only - no v1.0 equivalent at time of writing | https://learn.microsoft.com/en-us/graph/api/reportroot-getmicrosoft365copilotusageuserdetail | NotValidatedLive |
| Collaboration | Usage (90 days) | UsageD90 | Advanced | GET /reports/get*(period='D90') | v1.0 | UsageDetectionOnly | Yes | - | Email/Teams/ActiveUsers/Groups reports | https://learn.microsoft.com/en-us/graph/api/resources/report | NotValidatedLive |
| Collaboration | Usage (180 days) | UsageD180 | Advanced | GET /reports/get*(period='D180') | v1.0 | UsageDetectionOnly | Yes | - | Email/Teams/ActiveUsers/Groups reports | https://learn.microsoft.com/en-us/graph/api/resources/report | NotValidatedLive |

## Permissions matrix

Delegated permissions are consented interactively (`Connect-MgGraph -Scopes`). Application permissions must be granted with admin consent for app-only runs - see [App-Only-Setup](App-Only-Setup.md). The tool never assigns permissions.

| Collector | Delegated | Application | Admin roles |
|---|---|---|---|
| Organization | Organization.Read.All | Organization.Read.All | Global Reader |
| Domains | Domain.Read.All | Domain.Read.All | Global Reader |
| Licenses | Directory.Read.All | Directory.Read.All | Global Reader |
| LicenseServicePlans | Directory.Read.All | Directory.Read.All | Global Reader |
| Users | User.Read.All | User.Read.All | Global Reader |
| Groups | Group.Read.All | Group.Read.All | Global Reader |
| AdminRoles | RoleManagement.Read.Directory | RoleManagement.Read.Directory | Global Reader |
| PlannerPlans | Tasks.Read | Tasks.Read.All | Global Reader |
| ConditionalAccess | Policy.Read.All | Policy.Read.All | Global Reader |
| NamedLocations | Policy.Read.All | Policy.Read.All | Global Reader |
| AuthMethodsPolicy | Policy.Read.All | Policy.Read.All | Global Reader |
| MfaRegistration | UserAuthenticationMethod.Read.All<br>AuditLog.Read.All | UserAuthenticationMethod.Read.All<br>AuditLog.Read.All | Global Reader |
| AppRegistrations | Application.Read.All | Application.Read.All | Global Reader |
| EnterpriseApps | Application.Read.All<br>Directory.Read.All | Application.Read.All<br>Directory.Read.All | Global Reader |
| AppPermissions | Application.Read.All<br>Directory.Read.All | Application.Read.All<br>Directory.Read.All | Global Reader |
| AppRegistrationPermissions | Application.Read.All | Application.Read.All | Global Reader |
| AppSignInActivity | AuditLog.Read.All | AuditLog.Read.All | Reports Reader<br>Global Reader |
| AppSignInLogs | AuditLog.Read.All | AuditLog.Read.All | Reports Reader<br>Global Reader |
| Mailboxes | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| MailboxStatistics | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| AuxArchiveCount | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| MailboxHolds | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| MailboxPermissions | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| SendAsPermissions | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| DistributionGroups | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| MailContacts | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| MailUsers | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| AcceptedDomains | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| InboundConnectors | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| OutboundConnectors | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| TransportRules | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| DkimSigningConfig | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| RemoteDomains | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| OrganizationRelationships | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| PublicFolderMailboxes | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| BookingsMailboxes | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| RetentionPolicies | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Compliance Administrator |
| RetentionRules | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Compliance Administrator |
| JournalRules | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| OutlookAddins | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| MigrationEndpoints | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| CustomerKey | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| SensitivityLabels | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Compliance Administrator |
| DlpPolicies | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Compliance Administrator |
| ComplianceCases | Exchange.ManageAsApp | Exchange.ManageAsApp | eDiscovery Manager<br>Compliance Administrator |
| CaseHoldPolicies | Exchange.ManageAsApp | Exchange.ManageAsApp | eDiscovery Manager<br>Compliance Administrator |
| EDiscoveryCases | eDiscovery.Read.All | eDiscovery.Read.All | eDiscovery Manager<br>Global Reader |
| EDiscoveryHolds | eDiscovery.Read.All | eDiscovery.Read.All | eDiscovery Manager<br>Global Reader |
| OneDrive | Sites.Read.All<br>Reports.Read.All | Sites.Read.All<br>Reports.Read.All | SharePoint Administrator<br>Global Reader |
| OneDriveUsage | Reports.Read.All | Reports.Read.All | Reports Reader<br>Global Reader |
| SharePointSites | Sites.Read.All<br>Reports.Read.All | Sites.Read.All<br>Reports.Read.All | SharePoint Administrator<br>Global Reader |
| SharePointTenant | - | - | SharePoint Administrator |
| ExternalUsers | - | - | SharePoint Administrator |
| SharePointAppCatalog | - | - | SharePoint Administrator |
| Teams | Group.Read.All<br>TeamSettings.Read.All<br>TeamMember.Read.All | Group.Read.All<br>TeamSettings.Read.All<br>TeamMember.Read.All | Global Reader |
| TeamsChannels | Channel.ReadBasic.All | ChannelSettings.Read.All | Global Reader |
| TeamsCustomApps | AppCatalog.Read.All | AppCatalog.Read.All | Global Reader |
| TeamsInstalledApps | TeamsAppInstallation.ReadForTeam | TeamsAppInstallation.ReadForTeam.All | Global Reader |
| TeamsPhoneUsers | - | - | Teams Administrator |
| TeamsAutoAttendants | - | - | Teams Administrator |
| TeamsCallQueues | - | - | Teams Administrator |
| TeamsPhoneGateways | - | - | Teams Administrator |
| TeamsPhoneNumbers | - | - | Teams Administrator |
| TeamsMeetingPolicies | - | - | Teams Administrator |
| TeamsPhoneVoiceRoutes | - | - | Teams Administrator |
| IntuneDevices | DeviceManagementManagedDevices.Read.All | DeviceManagementManagedDevices.Read.All | Global Reader<br>Intune Administrator |
| EntraDevices | Directory.Read.All | Device.Read.All<br>Directory.Read.All | Global Reader |
| IntunePolicies | DeviceManagementConfiguration.Read.All | DeviceManagementConfiguration.Read.All | Global Reader<br>Intune Administrator |
| AutopilotDevices | DeviceManagementServiceConfig.Read.All | DeviceManagementServiceConfig.Read.All | Global Reader<br>Intune Administrator |
| UsageEmailActivity | Reports.Read.All | Reports.Read.All | Reports Reader<br>Global Reader |
| UsageTeamsActivity | Reports.Read.All | Reports.Read.All | Reports Reader<br>Global Reader |
| UsageMailboxUsage | Reports.Read.All | Reports.Read.All | Reports Reader<br>Global Reader |
| UsageActiveUsers | Reports.Read.All | Reports.Read.All | Reports Reader<br>Global Reader |
| CrossTenantPartners | Policy.Read.All | Policy.Read.All | Global Reader |
| DomainConflicts | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| UserMatches | Exchange.ManageAsApp | Exchange.ManageAsApp | Global Reader<br>Exchange Administrator |
| Dns | - | - | - |
| PowerPlatformEnvironments | - | - | Power Platform Administrator<br>Global Administrator |
| PowerApps | - | - | Power Platform Administrator<br>Global Administrator |
| PowerAutomateFlows | - | - | Power Platform Administrator<br>Global Administrator |
| PowerPlatformConnectors | - | - | Power Platform Administrator<br>Global Administrator |
| PowerPlatformDlpPolicies | - | - | Power Platform Administrator<br>Global Administrator |
| PowerBIWorkspaces | - | Tenant.Read.All | Power BI Administrator |
| Forms | - | - | - |
| Loop | - | - | - |
| Whiteboard | - | - | - |
| Sway | - | - | - |
| VivaGlint | - | - | - |
| VivaPulse | - | - | - |
| VivaAmplify | - | - | - |
| AuthorizationPolicy | Policy.Read.All | Policy.Read.All | Global Reader |
| AdminConsentRequestPolicy | Policy.Read.All | Policy.Read.All | Global Reader |
| GroupSettings | Directory.Read.All | Directory.Read.All | Global Reader |
| GroupLifecyclePolicies | Directory.Read.All | Directory.Read.All | Global Reader |
| CrossTenantAccessPolicy | Policy.Read.All | Policy.Read.All | Global Reader |
| AdministrativeUnits | AdministrativeUnit.Read.All | AdministrativeUnit.Read.All | Global Reader |
| DelegatedAdminRelationships | DelegatedAdminRelationship.Read.All | DelegatedAdminRelationship.Read.All | Global Reader |
| GroupDetails | Group.Read.All | Group.Read.All | Global Reader |
| AuthStrengths | Policy.Read.All | Policy.Read.All | Global Reader |
| CustomDirectoryRoles | RoleManagement.Read.Directory | RoleManagement.Read.Directory | Global Reader |
| PimAssignments | RoleAssignmentSchedule.Read.Directory<br>RoleEligibilitySchedule.Read.Directory | RoleAssignmentSchedule.Read.Directory<br>RoleEligibilitySchedule.Read.Directory | Global Reader |
| AppOwners | Application.Read.All | Application.Read.All | Global Reader |
| AppRedirectUris | Application.Read.All | Application.Read.All | Global Reader |
| AppCredentials | Application.Read.All | Application.Read.All | Global Reader |
| SamlCertificates | Application.Read.All | Application.Read.All | Global Reader |
| ProvisioningJobs | Synchronization.Read.All | Synchronization.Read.All | Global Reader |
| RecoverableItemsSize | - | - | Exchange Recipient<br>Global Reader |
| SmtpClientAuth | - | - | Exchange Recipient<br>Global Reader |
| SmtpClientAuthPerMailbox | - | - | Exchange Recipient<br>Global Reader |
| InactiveMailboxes | - | - | Exchange Recipient<br>Global Reader |
| SoftDeletedMailboxes | - | - | Exchange Recipient<br>Global Reader |
| DynamicDistributionGroups | - | - | Exchange Recipient<br>Global Reader |
| DistributionGroupMembers | - | - | Exchange Recipient<br>Global Reader |
| CalendarProcessing | - | - | Exchange Recipient<br>Global Reader |
| CalendarPermissions | - | - | Exchange Recipient<br>Global Reader |
| InboxRuleForwarding | - | - | Exchange Recipient<br>Global Reader |
| SharingPolicies | - | - | Exchange Recipient<br>Global Reader |
| AddressLists | - | - | Exchange Recipient<br>Global Reader |
| MrmRetention | - | - | Exchange Recipient<br>Global Reader |
| MrmRetentionPolicies | - | - | Exchange Recipient<br>Global Reader |
| ApplicationAccessPolicies | - | - | Exchange Recipient<br>Global Reader |
| ServicePrincipalRoleAssignments | - | - | Exchange Recipient<br>Global Reader |
| HybridIndicators | - | - | Exchange Recipient<br>Global Reader |
| HubSites | - | - | SharePoint Administrator |
| SiteAdmins | - | - | SharePoint Administrator |
| DeletedOneDrives | - | - | SharePoint Administrator |
| SiteLists | Sites.Read.All | Sites.Read.All | - |
| SiteUniquePermissions | - | - | - |
| OneDriveKFM | - | - | - |
| ThirdPartyEvidence | - | - | - |
| TeamsConfig | - | - | Teams Administrator |
| TeamsFederation | - | - | Teams Administrator |
| TeamsGuestConfig | - | - | Teams Administrator |
| TeamsPolicies | - | - | Teams Administrator |
| TeamTabs | Team.ReadBasic.All<br>ChannelSettings.Read.All | - | - |
| UsageM365Apps | Reports.Read.All | Reports.Read.All | Global Reader |
| UsageOfficeActivations | Reports.Read.All | Reports.Read.All | Global Reader |
| UsageGroupsActivity | Reports.Read.All | Reports.Read.All | Global Reader |
| UsageYammer | Reports.Read.All | Reports.Read.All | Global Reader |
| UsageTeamsDevices | Reports.Read.All | Reports.Read.All | Global Reader |
| UsageCopilot | Reports.Read.All | Reports.Read.All | Global Reader |
| UsageD90 | Reports.Read.All | Reports.Read.All | Global Reader |
| UsageD180 | Reports.Read.All | Reports.Read.All | Global Reader |

## Application permissions (union for app-only runs)

- `AdministrativeUnit.Read.All`
- `AppCatalog.Read.All`
- `Application.Read.All`
- `AuditLog.Read.All`
- `ChannelSettings.Read.All`
- `DelegatedAdminRelationship.Read.All`
- `Device.Read.All`
- `DeviceManagementConfiguration.Read.All`
- `DeviceManagementManagedDevices.Read.All`
- `DeviceManagementServiceConfig.Read.All`
- `Directory.Read.All`
- `Domain.Read.All`
- `eDiscovery.Read.All`
- `Exchange.ManageAsApp`
- `Group.Read.All`
- `Organization.Read.All`
- `Policy.Read.All`
- `Reports.Read.All`
- `RoleAssignmentSchedule.Read.Directory`
- `RoleEligibilitySchedule.Read.Directory`
- `RoleManagement.Read.Directory`
- `Sites.Read.All`
- `Synchronization.Read.All`
- `Tasks.Read.All`
- `TeamMember.Read.All`
- `TeamsAppInstallation.ReadForTeam.All`
- `TeamSettings.Read.All`
- `Tenant.Read.All`
- `User.Read.All`
- `UserAuthenticationMethod.Read.All`

## Admin roles (union): Compliance Administrator, eDiscovery Manager, Exchange Administrator, Exchange Recipient, Global Administrator, Global Reader, Intune Administrator, Power BI Administrator, Power Platform Administrator, Reports Reader, SharePoint Administrator, Teams Administrator


