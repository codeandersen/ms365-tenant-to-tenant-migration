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

## Archive channel conversations to PDF — `Export-TeamsChannelsToPdf.ps1` (read-only, source)

Channel **messages** do not migrate with either track. This script gives the source
administrator a readable, self-contained PDF archive of every channel in a chosen set
of teams so they can decide whether a PDF archive is good enough — or whether live
history needs a third-party import. **Importing messages into the target is a separate
later step** (it needs target app permissions, author mapping, existing target channels
and link rewriting) and is intentionally not part of this script.

What it does, per team in `-TeamListPath` (`01-Design/templates/teams-export-list.csv`):

1. Resolves the team (`TeamId` column if given, else a display-name search on
   `resourceProvisioningOptions` — zero hits = `NotFound`, several = `Ambiguous`).
2. Lists channels via `GET /teams/{id}/allChannels` (standard + private + shared) with a
   `/channels` fallback; channels the admin cannot read are reported `Forbidden`, not fatal.
3. Pages `GET .../messages?$top=50&$expand=replies`, following the per-thread replies
   nextLink beyond 200 replies (`ThreadsOver200Replies` is recorded).
4. Downloads hosted images (embedded as data URIs unless `-NoImages`), keeps deleted
   messages as placeholders, excludes but counts system messages.
5. Renders one sanitised HTML page per channel (scripts/iframes/`on*=`/`javascript:` stripped),
   writes raw JSON, and prints a PDF via headless Edge/Chrome.

Parameters: `-TenantId` (GUID), `-AdminUpn`, `-TeamListPath`, `-Customer` (required);
`-PdfEngine Auto|Edge|Chrome|None`, `-BrowserPath`, `-SinceUtc`, `-MaxMessagesPerChannel`,
`-IncludeImages`/`-NoImages` (optional). Sign-in is interactive delegated Graph in the
**source** tenant — no tenant changes.

Output under `customers/<c>/output/07-SharePoint-Teams/<ts>/`: `pdf/` (`<Team> - <Channel>.pdf`),
`html/` (same pages, kept when no browser is found — `PdfStatus=HtmlOnly`), `json/` (raw Graph
pages per channel), `TeamsExportCoverage.csv` and `TeamsExportCoverage.md`.

Coverage columns (per channel): team/channel identity, `Status`
(`Exported|Forbidden|NotFound|Ambiguous|Error`), `PdfStatus`/`PdfFile`, thread/root/reply/total
counts, `SystemMessagesExcluded`, `DeletedPlaceholders`, oldest/newest timestamps + `HistoryDays`,
`DistinctAuthors`, `InlineImages`/`ImagesEmbedded`/`ImagesFailed`, `FileAttachments`,
`CardOrAppMessages`, `MessagesWithReactions`, `EditedMessages`, `ThreadsOver200Replies`,
`TruncatedAtCap`, `Error`.

Limits: reactions are flattened to counts, cards/app content, videos, recordings and files
themselves are not captured, edit history is not reconstructed, system events are counted only,
and attachment links point at the **source** tenant and die with decommission.

**Personal data:** PDFs/HTML/JSON contain employee names and message content. Keep them under
`customers/`, share only with the source administrator, and delete when no longer needed.

Note: the headless-browser flags must be passed from **PowerShell** (or cmd) — Git Bash mangles
`--user-data-dir`/`--print-to-pdf` arguments and Edge silently writes nothing.

Learn: [list channel messages](https://learn.microsoft.com/en-us/graph/api/channel-list-messages),
[hosting images in Teams messages](https://learn.microsoft.com/en-us/microsoftteams/platform/messaging-extensions/how-to/action-commands/respond-to-task-module-submit),
[chats/channels don't migrate natively](https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration).

> **Note - search indexing of the exported PDFs.** A PDF placed in a Teams channel (the
> channel's folder in the team's SharePoint document library) is full-text indexed by
> SharePoint search, subject to these limits ([Search limits for SharePoint](https://learn.microsoft.com/en-us/sharepoint/search-limits)):
> crawl download max 512 MB for PDF (above that only metadata is indexed); parsing stops at
> 2 million characters; only the first 1 million characters are broken into searchable words;
> max 30 seconds per item for parsing and for word breaking. Text in the exported PDFs is
> searchable; embedded images are not (no OCR unless enabled). A channel with long history can
> exceed 1 million characters in one PDF - threads are ordered oldest first, so the newest
> history would not be searchable. During the pilot: check the PDF sizes, search for a phrase
> from the end of a large PDF after it has been indexed, and record the result in the
> Decision-Log. Splitting PDFs per year is a possible later change if this becomes a problem.

*Untested against live tenants — mock-verified only.*

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
