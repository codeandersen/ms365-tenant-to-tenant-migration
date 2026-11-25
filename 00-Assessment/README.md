# 00-Assessment

Read-only tenant inventory + review report. Neither script changes anything in a
tenant: `Collect-TenantInventory.ps1` only issues GET requests (Microsoft Graph)
and read cmdlets (`Get-`/`Resolve-`), and it asserts the connected tenant
matches `-TenantId` before collecting.

## Collect-TenantInventory.ps1

Collects a full inventory for estimating and planning a tenant-to-tenant
migration with Microsoft Migration Orchestrator: users, groups, licenses,
domains, mailboxes (+ sizes, holds, permissions), mail flow, Purview, OneDrive,
SharePoint, Teams (+ phone), devices, Intune, apps/SSO, Conditional Access/MFA,
DNS and cross-tenant prerequisites. With `-Role Target -SourceInventoryPath` it
also compares source domains/users against target (DomainConflicts.csv,
UserMatches.csv).

```
.\Collect-TenantInventory.ps1 -Role Source -TenantName Contoso -TenantId contoso.com
.\Collect-TenantInventory.ps1 -Role Target -TenantName Fabrikam -TenantId fabrikam.com -Customer contoso -SourceInventoryPath .\customers\contoso\inventory\Inventory_Contoso_Source_20261022_090302
```

Output: `Inventory_<TenantName>_<Role>_<timestamp>\` with `attachments\*.csv`,
`summary.json` and `Collection.log` (UTF-8 with BOM so Excel shows æøå).

Useful switches: `-Sections`/`-SkipSections`, `-SpoAdminUrl`, `-DisableWAM`
(broker sign-in issues), `-UseDeviceCode`, `-NewWindow`, `-OutputFolder`
(resume an aborted run), `-Level Basic|Advanced|Deep` (default `Advanced`;
`Basic` skips the per-object loops such as per-app sign-in queries, per-SP
appRoleAssignments, per-mailbox permission/SendAs/aux-archive queries, per-team
installed apps and per-group Planner plans), and `-ClientId` +
`-CertificateThumbprint` for certificate app-only runs — see
[docs/App-Only-Setup.md](../docs/App-Only-Setup.md). Delegated-only collectors
report `NotSupported` in app-only mode; SPO admin falls back to Graph.

Each collector records status in `Collectors.csv` (merged into
`summary.json.collectors`): Success / PartialSuccess / NotInUse / Skipped /
NotLicensed / AccessDenied / AuthenticationFailed / DiscoveryFailed /
NotSupported / ManualDiscoveryRequired, with object count, duration and the
first warnings. Section-level rows (e.g. `Apps`, `Security`) include the
sub-collectors they wrap: their `ObjectCount` counts sub-collector rows too, but
their status only reflects the section's own warnings/skips — check the
individual collector rows for the detail. The full registry lives in
`Collectors.psd1` and is rendered as
[docs/Collector-Matrix.md](../docs/Collector-Matrix.md) (regenerate with
`tools\New-CollectorMatrix.ps1`).

### Troubleshooting

- **Cmdlet errors like `The cloud file provider is not running` (0x8007016A)**:
  a module lives in an OneDrive-synced folder (e.g.
  `Documents\PowerShell\Modules`) and its files are cloud-only placeholders.
  Mark the module folder *Always keep on this device*, or reinstall with
  `Install-Module <name> -Scope AllUsers`. `tools\Test-ModuleHealth.ps1` flags
  OneDrive-resident modules.
- **A long pause between a child process starting and "connected"** is a
  sign-in window waiting for input — the module sometimes opens it behind
  other windows. Start the run with `-NewWindow` (each child in its own window)
  or `-UseDeviceCode` to get a device-code prompt in the console instead.

## New-InventoryReport.ps1

Turns an inventory folder into `Review.md`: a status (OK / Information / Note /
Critical), key figures and top-20 tables for each of 20 checks, plus links to
the CSV attachments. With `-TargetInventoryPath` it adds domain-conflict,
migration-license and user-match checks.

```
.\New-InventoryReport.ps1 -InventoryPath .\customers\contoso\inventory\Inventory_Contoso_Source_20261022_090302 `
    -TargetInventoryPath .\customers\contoso\inventory\Inventory_Fabrikam_Target_20261023_101500
```

## New-MigrationReadinessReport.ps1

Offline, read-only. Reads the same inventory folder and writes `Readiness.md`:
summary counts, the recommended Microsoft tool per workload (orchestrator /
mailbox / OneDrive / SharePoint), migration-licence math, blockers (holds,
Customer Key, public folders, apostrophe UPNs, >5 TB sites, locked sites,
user-defined-permission labels), a "decide or rebuild" list, and what the
inventory can't see ("not inventoried"). See
[`docs/Migration-Method-Guide.md`](../docs/Migration-Method-Guide.md).

```
.\New-MigrationReadinessReport.ps1 -InventoryPath .\customers\contoso\inventory\Inventory_Contoso_Source_20261022_090302 `
    -TargetInventoryPath .\customers\contoso\inventory\Inventory_Fabrikam_Target_20261023_101500
```

New/updated collections for the readiness report:

| File | Source | Notes |
|---|---|---|
| `BookingsMailboxes.csv` | `Get-EXOMailbox -RecipientTypeDetails SchedulingMailbox` | Bookings isn't moved by any Microsoft tool |
| `CustomerKey.csv` | `Get-DataEncryptionPolicy` (Exchange) + `Get-SPODataEncryptionPolicy` (SPO) | Customer Key blocks OneDrive/SharePoint moves; skipped with a warning if the SPO cmdlet isn't in the installed module |
| `SensitivityLabels.csv` | `Get-Label` — now also exports `EncryptionType`/`LabelActions` | flags user-defined-permission labels that block site moves |
| `Mailboxes.csv` | new columns `AutoExpandingArchiveEnabled`, `DisabledArchiveGuid` (falls back to `Get-Mailbox` if EXO doesn't return it), `ArchiveQuota`, `ArchiveWarningQuota`, `AuxArchiveCount` (`Get-MailboxLocation -User <ExchangeGuid>`, counted where `MailboxLocationType` = `AuxArchive`) | per-mailbox "does the archive come along" in `Readiness.md` |
| `MailboxStatistics.csv` | new `AuxArchiveCount` column | aux archive count per archive-enabled mailbox |
| `summary.json` | new metrics `autoExpandingArchiveCount`, `auxArchiveMailboxCount`, `disabledArchiveCount`, `orgAutoExpandingArchive` | archive overview |
| `AppSignInActivity.csv` | new `AppSignIns` section (source role): last sign-in per type per service principal from the Entra sign-in logs (beta, ≤30 days via `-SignInLookbackDays`), plus the service principal sign-in activity report (beta, preview) | roles: Reports Reader / Security Reader / Global Reader; sign-in logs need Entra ID P1 - without it the section falls back to the activity report. The section logs one line per app (query plan, result, elapsed, ETA) and a `Write-Progress` bar; everything also lands in `Collection.log`. [signIn-list](https://learn.microsoft.com/en-us/graph/api/signin-list?view=graph-rest-beta), [servicePrincipalSignInActivities](https://learn.microsoft.com/en-us/graph/api/reportroot-list-serviceprincipalsigninactivities?view=graph-rest-beta) |
| `ConditionalAccess.csv` | `GET /identity/conditionalAccess/policies` - now exports include/exclude users-groups-roles, applications, client app types, platforms, locations, grant controls, auth strength, session controls | CA policies are tenant config - recreate in the target |
| `NamedLocations.csv` | `GET /identity/conditionalAccess/namedLocations` | trusted IP ranges / countries - hand to the target admin via `Export-TrustedLocations.ps1`. Metrics `namedLocationCount`, `trustedIpLocationCount` |
| `AuthMethodsPolicy.csv` | `GET /policies/authenticationMethodsPolicy` | per-method state (microsoftAuthenticator/fido2/temporaryAccessPass/sms) + registration campaign. Metrics `authMethod_<method>` |
| `Security` section | now also runs for `-Role Target` (scopes include Policy.Read.All + AuditLog.Read.All) | target CA / named locations / auth methods feed the readiness report's sign-in section |
| `AppPermissions.csv` | `GET /servicePrincipals/{id}/appRoleAssignments` + `GET /oauth2PermissionGrants` per non-Microsoft service principal ([appRoleAssignments](https://learn.microsoft.com/en-us/graph/api/serviceprincipal-list-approleassignments), [oauth2PermissionGrants](https://learn.microsoft.com/en-us/graph/api/oauth2permissiongrant-list)) | one row per app+resource: `ApplicationPermissions`, `DelegatedPermissionsAdminConsent`, `DelegatedPermissionsUserConsent` (distinct scopes, `; `-joined), `UserConsentCount`, `HighPrivilegeApplication`/`HighPrivilegeDelegated` subsets, `UnresolvedPermissions`. `EnterpriseApps.csv` gains `ApplicationPermissionCount`, `DelegatedPermissionCount`, `HighPrivilegePermissions` |
| `AppDelegatedUserPermissions.csv` | `GET /oauth2PermissionGrants` + `POST /directoryObjects/getByIds` (chunks of 1000 ids, [getByIds](https://learn.microsoft.com/en-us/graph/api/directoryobject-getbyids)) | one row per app+resource+consenting user: `UserPrincipalName`, `UserDisplayName`, `UserId`, `DelegatedPermissions`, `HighPrivilegeDelegated`, plus an `All users (admin consent)` row per app+resource. Deleted/unresolved users show `(deleted or unresolved user)` |
| `AppRegistrationPermissions.csv` | `requiredResourceAccess` on `/applications` | requested (not necessarily granted) permissions per app registration, resolved to names via the resource service principals |
| `TeamsCustomApps.csv` | `GET /appCatalogs/teamsApps?$filter=distributionMethod eq 'organization'` | org-uploaded Teams apps — [Learn](https://learn.microsoft.com/en-us/graph/api/appcatalogs-list-teamsapps) |
| `TeamsInstalledApps.csv` | `GET /teams/{id}/installedApps?$expand=teamsAppDefinition` per team | added apps per team incl. third-party store apps; `IsOrgCatalogApp` marks tenant-catalog apps — [Learn](https://learn.microsoft.com/en-us/graph/api/team-list-installedapps) |
| `PlannerPlans.csv` | `GET /groups/{id}/planner/plans` per M365 group | a 403 (missing `Tasks.Read` consent) is recorded in `skippedSections` and the remaining groups are skipped — [Learn](https://learn.microsoft.com/en-us/graph/api/plannergroup-list-plans) |
| `OutlookAddins.csv` | `Get-App -OrganizationApp` (Exchange child only) | organization-wide Outlook add-ins — [Learn](https://learn.microsoft.com/en-us/powershell/module/exchange/get-app) |
| `SharePointAppCatalog.csv` | `Get-SPOAppInfo -Name ' '` (SPO child only) | apps in the tenant app catalog (add-ins/SPFx) — [Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spoappinfo) |
| `PowerPlatformEnvironments.csv`, `PowerApps.csv`, `PowerAutomateFlows.csv`, `PowerPlatformConnectors.csv`, `PowerPlatformDlpPolicies.csv` | new `PowerPlatform` section in its own child process (`Add-PowerAppsAccount`, `Get-AdminPowerAppEnvironment`, `Get-AdminPowerApp`, `Get-AdminFlow`, `Get-AdminPowerAppConnector`, `Get-DlpPolicy`) | module `Microsoft.PowerApps.Administration.PowerShell` (imported via `-UseWindowsPowerShell` like SPO; Power Platform admin / Global admin sign-in). Skipped with a reason if the module is missing — [Learn](https://learn.microsoft.com/en-us/powershell/module/microsoft.powerapps.administration.powershell/) |
| `PowerBIWorkspaces.csv` | `Get-PowerBIWorkspace -Scope Organization` inside the Power Platform child | optional module `MicrosoftPowerBIMgmt`; skipped with a reason if missing — [Learn](https://learn.microsoft.com/en-us/powershell/module/microsoftpowerbimgmt.workspaces/get-powerbiworkspace) |
| `AuthorizationPolicy.csv`, `AdminConsentRequestPolicy.csv`, `GroupSettings.csv`, `GroupLifecyclePolicies.csv`, `CrossTenantAccessPolicy.csv`, `AdministrativeUnits.csv`, `DelegatedAdminRelationships.csv` | `GET /policies/authorizationPolicy`, `/policies/adminConsentRequestPolicy`, `/groupSettings`, `/groupLifecyclePolicies`, `/policies/crossTenantAccessPolicy` (+ `/partners`), `/directory/administrativeUnits`, `/tenantRelationships/delegatedAdminRelationships` | tenant config that must be recreated: guest invite, user consent, group naming/expiry, cross-tenant B2B rules, AUs, GDAP partners — [Learn](https://learn.microsoft.com/en-us/graph/api/resources/policy-overview) |
| `GroupDetails.csv` | `/members/$count`, `/owners`, `assignedLicenses` per group (Advanced) | owner/member/nested counts, membership rule, license SKUs — [Learn](https://learn.microsoft.com/en-us/graph/api/group-get) |
| `AuthStrengths.csv`, `CustomDirectoryRoles.csv` | `GET /policies/authenticationStrengthPolicies`, `/roleManagement/directory/roleDefinitions?$filter=isBuiltIn eq false` | auth strengths used by CA, custom RBAC roles to recreate |
| `PimEligibleAssignments.csv`, `PimActiveAssignments.csv` | `GET /roleManagement/directory/roleEligibilitySchedules` + `/roleAssignmentSchedules` | requires Entra ID P2 (recorded `NotLicensed` without it) — [Learn](https://learn.microsoft.com/en-us/graph/api/rolemanagement-directory-list-roleeligibilityschedules) |
| `AppOwners.csv`, `AppRedirectUris.csv`, `AppCredentials.csv`, `SamlCertificates.csv`, `ProvisioningJobs.csv` | `/applications/{id}/owners`, `web/spa/publicClient` redirect URIs, `keyCredentials`/`passwordCredentials` (metadata only — never secrets), SAML Verify/Sign certs, `/synchronization/jobs` | expiring credentials and SAML certs are called out in `Readiness.md`; SCIM jobs must be re-created — [Learn](https://learn.microsoft.com/en-us/graph/api/synchronization-synchronization-list-jobs) |
| `InactiveMailboxes.csv`, `SoftDeletedMailboxes.csv` | `Get-EXOMailbox -InactiveMailboxOnly` / `-SoftDeletedMailbox` | inactive mailboxes are **not moved** by cross-tenant tools — blocker in `Readiness.md` |
| `DynamicDistributionGroups.csv`, `DistributionGroupMembers.csv` | `Get-DynamicDistributionGroup` (+`Get-DynamicDistributionGroupMember`), `Get-DistributionGroupMember` + `Get-Recipient` | recipient filters must be recreated; member counts + owners (full member lists only at `-Level Deep`) |
| `SmtpClientAuthOrg.csv` | `Get-TransportConfig` | SMTP AUTH organization default |
| `SmtpClientAuthMailboxes.csv` | `Get-CASMailbox` (Advanced) | Per-mailbox SMTP AUTH overrides |
| `MailboxStatistics.csv` | new `RecoverableItemsGB` column (`Get-EXOMailboxFolderStatistics -FolderScope RecoverableItems`, Advanced) | **not** included in totalMailboxGB — reported separately |
| `Mailboxes.csv` | new columns `LegacyExchangeDN`, `X500Addresses` | proxy addresses needed to re-stamp X500 in the target |
| `CalendarProcessing.csv`, `CalendarPermissions.csv`, `InboxRuleForwarding.csv` | `Get-CalendarProcessing` (room/equipment), `Get-MailboxFolderPermission` + `Get-InboxRule` (**Deep**) | room mailbox settings; forwarding rules export target **domains + count only** — never rule bodies |
| `SharingPolicies.csv`, `AddressLists.csv`, `RetentionPolicyTags.csv`, `MrmRetentionPolicies.csv`, `ApplicationAccessPolicies.csv`, `ServicePrincipalRoleAssignments.csv`, `HybridIndicators.csv` | `Get-SharingPolicy`, `Get-AddressList`/`Get-GlobalAddressList`/`Get-AddressBookPolicy`/`Get-OfflineAddressBook`, `Get-RetentionPolicyTag`/`Get-RetentionPolicy`, `Get-ApplicationAccessPolicy`, `Get-ServicePrincipal`/`Get-ManagementRoleAssignment`, `Get-IntraOrganizationConnector`/`Get-HybridConfiguration` | Exchange org config to recreate; Exchange MRM is distinct from Purview retention |
| `HubSites.csv`, `SiteAdmins.csv`, `DeletedOneDrives.csv`, `SiteLists.csv`, `SharePointSites.csv` (new `SiteType`, `HubSiteId` columns) | `Get-SPOHubSite`, `Get-SPOUser -Site` (Advanced), `Get-SPODeletedSite -IncludeOnlyPersonalSite`, `GET /sites/{id}/lists` (Deep, Graph fallback process only) | hub association via `HubSiteId`; site-type classification on every site row |
| `Dns.csv` (new `MtaSts`, `SmtpTls` columns), `ThirdPartyEvidence.csv` | `_mta-sts`/`_smtp._tls` TXT + pattern match over MX/SPF/connectors | third-party mail gateway evidence (Mimecast/Proofpoint/etc.) only on concrete records — blocker in `Readiness.md` |
| `TeamsFederation.csv`, `TeamsGuestConfig.csv`, `TeamsPolicies.csv` | `Get-CsTenantFederationConfiguration`, `Get-CsTeamsClientConfiguration`, `Get-CsTeamsGuest*Configuration`, `Get-CsTeams*Policy` (new `TeamsConfig` section — always runs in the Teams child, not licence-gated) | federation/guest settings + policy names to recreate |
| `UsageM365Apps.csv`, `UsageOfficeActivations.csv`, `UsageGroupsActivity.csv`, `UsageYammer.csv`, `UsageTeamsDevices.csv`, `UsageCopilot.csv`, `Usage*D90.csv`, `Usage*D180.csv` | additional `/reports/*` endpoints (Copilot is **beta** only); D90/D180 at `-Level Advanced` | usage indicators — [Learn](https://learn.microsoft.com/en-us/graph/api/resources/report) |

New delegated Graph scopes (source role): `Synchronization.Read.All`, `DelegatedAdminRelationship.Read.All`, `AdministrativeUnit.Read.All`, `RoleAssignmentSchedule.Read.Directory`, `RoleEligibilitySchedule.Read.Directory`.

`Export-TrustedLocations.ps1` (offline, no tenant connection): builds the
trusted-locations hand-over for the target admin from `NamedLocations.csv` + optional
`01-Design/templates/office-ip-ranges.csv` → `TrustedLocations-for-target.csv` /
`.json` (Graph POST bodies) / `TrustedLocations-README.md`. Validates CIDRs, flags
private/reserved ranges, merges duplicates, warns on overlaps.

### Hand-over to the source admin: AppSignInActivity.csv

Give this file to the source tenant admin so they can investigate each app before
deciding what to rebuild. Columns: identity first (`ServicePrincipalId`, `AppId`,
`DisplayName`, `ServicePrincipalType`, `IsMicrosoftFirstParty`,
`IsManagedIdentity`, `AccountEnabled`, `PreferredSingleSignOnMode`), then `Status`,
`LastSeenAny` and `DaysSinceLastSeen`, then the last sign-in per type
(`LastInteractiveUser`, `LastNonInteractiveUser`, `LastServicePrincipal`,
`LastManagedIdentity` - `n/a` where the type doesn't apply to the app) and the five
last-activity dates from the preview report. `EntraPortalUrl` opens the app in the
Entra portal for a closer look. `Status` values: `ActiveInWindow` (sign-in within
the lookback window), `ActiveEarlier` (last activity predates the window),
`NoActivityRecorded`, `ReportOnly` (sign-in logs were not queried - Microsoft
first-party apps by default; re-run with `-IncludeMicrosoftAppsInSignInLogs` to
query them too, `-SignInQueryThrottle 1-8` sets the parallelism), `Unknown`
(neither source was reachable - e.g. no Entra ID P1). `SignInLogsQueried` says
whether the logs were checked for the app. Note: the activity report is preview
and has shown months-old dates for apps in daily use - it is never used to call
an app unused; "inactive" verdicts come from the sign-in logs only.

## Requirements

- PowerShell 7.2+
- Modules: `Microsoft.Graph.Authentication`, `ExchangeOnlineManagement`,
  `Microsoft.Online.SharePoint.PowerShell`, `MicrosoftTeams`; optional for the
  `PowerPlatform` section: `Microsoft.PowerApps.Administration.PowerShell`
  (+ `MicrosoftPowerBIMgmt` for Power BI) (see `tools\Test-ModuleHealth.ps1`)
- Roles: Global Reader or Global Admin in the tenant. **Power Platform
  Administrator** (or Global Admin) is needed for the `PowerPlatform` section.
  **SharePoint Administrator**
  is needed for full SPO coverage (`Get-SPOSite`, tenant settings, external
  users) and for the delegated `GET /sites/getAllSites` fallback — without it the
  fallback only has the usage reports, and site counts can be lower than the true
  site list (the reports omit sites with no recent activity). A B2B guest account
  works with reduced coverage (Exchange/SharePoint fall back to Graph usage
  reports); holds, permissions and mail flow must be re-checked with a member
  account.
- If `Connect-SPOService` fails, the OneDrive/SharePoint sections are not run in
  the SharePoint child process (it has no Graph session) — the real error stays
  in `summary.json` under `SharePointAdmin`, and the orchestrator automatically
  re-runs the sections in a Graph pass. `Connect-SPOService` failing with
  "No valid OAuth 2.0 authentication session exists" is a known module sign-in
  issue — a rerun usually resolves it.

## Data handling

The inventory contains personal data (names, e-mail addresses, sign-in
activity). Keep it under `customers\<name>\` — it is gitignored — and never
commit it. `tests\Test-NoCustomerData.ps1` enforces this.
