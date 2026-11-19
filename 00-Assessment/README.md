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
.\Collect-TenantInventory.ps1 -Role Target -TenantName Fabrikam -TenantId fabrikam.com -SourceInventoryPath .\Inventory_Contoso_Source_20261022_090302
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
.\New-InventoryReport.ps1 -InventoryPath .\Inventory_Contoso_Source_20261022_090302 `
    -TargetInventoryPath .\Inventory_Fabrikam_Target_20261023_101500
```

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
