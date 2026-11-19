# 07 - SharePoint and Teams

Two candidate tracks - no tool chosen yet:

## Track A: native cross-tenant SharePoint migration
([overview](https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration),
steps 1-7). Facts verified against the docs:

- **Licence**: Cross-Tenant Shared Data Migration, Enterprise Agreement only, per 100 GB moved (+20 %
  grace). Size estimate: sum `StorageUsageCurrent` (in the 00-Assessment SharePointSites.csv).
- **One and done**: content is *moved*; a **redirect** is left on the source URL. **No delta /
  incremental passes.**
- **Queue**: 4,000 sites max queued in advance, **shared** across the SharePoint tool, the
  OneDrive tool and the Orchestrator (FAQ).
- **Limits**: 5 TB / 1 M items per site; 400-char path limit; source sites must be read/write;
  no Customer Key service encryption on the source.
- **Target sites must NOT pre-exist** - the move fails if the target URL exists. Only target
  **M365 groups** for group-connected sites are precreated, and only via the documented
  `New-MgBetaGroup ... -ResourceBehaviorOptions ProvisionSiteOnDemand -MailEnabled:$false -SecurityEnabled:$false`
  (any other creation method fails the move; group names with '.' fail). The group alias must equal
  the last segment of the target URL.
- **Identity mapping**: six-column CSV (no headers) uploaded **on the target** via
  `Add-SPOTenantIdentityMap -IdentityMapPath` (see `01-Design/templates/CTIM-Mapping-CSV.md` for the
  columns; re-upload the whole file after any change). Then `Get-SPOCrossTenantCompatibilityStatus`
  on the source must show Compatible/Warning.
- **Site types covered**: M365 group-connected (incl. Teams-associated), modern non-group, classic,
  communication sites. **Teams content, channels and channel structure are NOT migrated** - only the
  SharePoint site content of a Teams-connected site moves. Sharing links redirect automatically;
  permissions survive only for identities in the map. Workflows, apps, Power Platform items, some
  web parts and sensitivity-labelled files need manual work (overview's feature list).
- Trust (`Set-SPOCrossTenantRelationship -Scenario MnA`) is already established in phase 02's
  OneDrive-trust step - the same MnA trust covers SharePoint sites.

## Track B: ShareGate (documentation only, no scripts)

| | Native | ShareGate |
|---|---|---|
| Cost | licence per 100 GB, EA-only | per-seat subscription |
| Delta passes | no | yes (incremental) |
| Redirect | yes | by URL mapping |
| Teams channels/messages | no | partial (re-creation options) |
| Scale | 4,000 queued, server-side | tool throughput |

## What does NOT move (either track, native-specific where noted)

| Item | Source |
|---|---|
| Teams teams, channels, channel messages | Playbook assumption (native doc: "doesn't include migration of Teams content, channels or associated structure") |
| Group mailboxes of M365 groups | Playbook assumption (native doc covers site content; group mailbox = Exchange workload, not described) |
| Planner plans/tasks | Playbook assumption (not in the doc) |
| Loop workspaces | Playbook assumption (not in the doc) |
| Public folders | Playbook assumption (not in the doc) |
| SharePoint 2010/2013 workflows | Learn (must be recreated) |
| Apps, Power Apps/Automate | Learn (republish/reconnect) |
| Sensitivity labels w/ user-defined permissions | Learn (blocks the site; unlock or remove first) |

## Order

1. `Get-SiteMigrationPlan.ps1` (offline) → `SiteMigrationPlan.csv`; fill in `TargetUrl`/`TargetGroupAlias`/`Track`.
2. `New-TargetSiteGroups.ps1` (target) - group-connected rows only.
3. `03-Identities/New-SpoIdentityMap.ps1 -Upload -Verify` on the **target** (builds the full
   six-column map from the user list + guest-map + group-map; `Add-SPOTenantIdentityMap`
   **overwrites** - always re-upload the complete map) and `-CheckCompatibility` on the **source**
   (`Get-SPOCrossTenantCompatibilityStatus`; Incompatible stops). Format and rules:
   `01-Design/templates/SPO-Identity-Map.md`.
4. `Start-SiteContentMoves.ps1` (source; `-ValidationOnly` first).
5. `Get-SiteContentMoveStatus.ps1` (source) until Success.
6. Post-migration (step 7): check site permissions on the target, republish workflows/apps,
   tell users the new URLs, decommission source sites later (redirect already in place).
