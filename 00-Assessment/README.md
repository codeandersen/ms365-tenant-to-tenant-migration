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
(resume an aborted run).

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
| `Mailboxes.csv` | new columns `AutoExpandingArchiveEnabled`, `DisabledArchiveGuid` (falls back to `Get-Mailbox` if EXO doesn't return it), `ArchiveQuota`, `ArchiveWarningQuota`, `AuxArchiveCount` (`Get-MailboxLocation -MailboxLocationType AuxArchive`) | per-mailbox "does the archive come along" in `Readiness.md` |
| `MailboxStatistics.csv` | new `AuxArchiveCount` column | aux archive count per archive-enabled mailbox |
| `summary.json` | new metrics `autoExpandingArchiveCount`, `auxArchiveMailboxCount`, `disabledArchiveCount`, `orgAutoExpandingArchive` | archive overview |
| `AppSignInActivity.csv` | new `AppSignIns` section (source role): last sign-in per type per service principal from the Entra sign-in logs (beta, ≤30 days via `-SignInLookbackDays`), plus the service principal sign-in activity report (beta, preview) | roles: Reports Reader / Security Reader / Global Reader; sign-in logs need Entra ID P1 - without it the section falls back to the activity report. The section logs one line per app (query plan, result, elapsed, ETA) and a `Write-Progress` bar; everything also lands in `Collection.log`. [signIn-list](https://learn.microsoft.com/en-us/graph/api/signin-list?view=graph-rest-beta), [servicePrincipalSignInActivities](https://learn.microsoft.com/en-us/graph/api/reportroot-list-serviceprincipalsigninactivities?view=graph-rest-beta) |
| `ConditionalAccess.csv` | `GET /identity/conditionalAccess/policies` - now exports include/exclude users-groups-roles, applications, client app types, platforms, locations, grant controls, auth strength, session controls | CA policies are tenant config - recreate in the target |
| `NamedLocations.csv` | `GET /identity/conditionalAccess/namedLocations` | trusted IP ranges / countries - hand to the target admin via `Export-TrustedLocations.ps1`. Metrics `namedLocationCount`, `trustedIpLocationCount` |
| `AuthMethodsPolicy.csv` | `GET /policies/authenticationMethodsPolicy` | per-method state (microsoftAuthenticator/fido2/temporaryAccessPass/sms) + registration campaign. Metrics `authMethod_<method>` |
| `Security` section | now also runs for `-Role Target` (scopes include Policy.Read.All + AuditLog.Read.All) | target CA / named locations / auth methods feed the readiness report's sign-in section |

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
`NoActivityRecorded`, `Unknown` (neither source was reachable - e.g. no Entra ID P1).

## Requirements

- PowerShell 7.2+
- Modules: `Microsoft.Graph.Authentication`, `ExchangeOnlineManagement`,
  `Microsoft.Online.SharePoint.PowerShell`, `MicrosoftTeams` (see
  `tools\Test-ModuleHealth.ps1`)
- Roles: Global Reader or Global Admin in the tenant. A B2B guest account works
  with reduced coverage (Exchange/SharePoint fall back to Graph usage reports);
  holds, permissions and mail flow must be re-checked with a member account.

## Data handling

The inventory contains personal data (names, e-mail addresses, sign-in
activity). Keep it under `customers\<name>\` — it is gitignored — and never
commit it. `tests\Test-NoCustomerData.ps1` enforces this.
