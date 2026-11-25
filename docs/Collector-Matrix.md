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

## Application permissions (union for app-only runs)

- `AppCatalog.Read.All`
- `Application.Read.All`
- `AuditLog.Read.All`
- `ChannelSettings.Read.All`
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
- `RoleManagement.Read.Directory`
- `Sites.Read.All`
- `Tasks.Read.All`
- `TeamMember.Read.All`
- `TeamsAppInstallation.ReadForTeam.All`
- `TeamSettings.Read.All`
- `Tenant.Read.All`
- `User.Read.All`
- `UserAuthenticationMethod.Read.All`

## Admin roles (union): Compliance Administrator, eDiscovery Manager, Exchange Administrator, Global Administrator, Global Reader, Intune Administrator, Power BI Administrator, Power Platform Administrator, Reports Reader, SharePoint Administrator, Teams Administrator


