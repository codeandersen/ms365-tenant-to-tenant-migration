# What doesn't move

Everything the Orchestrator and the native tooling **don't** carry over, what handles it instead,
and the source of the claim: `[Learn]` = documented on Microsoft Learn, `[Playbook assumption]` =
not documented — validate in the pilot.

## Orchestrator jobs (Exchange, ODSP, Teams, Meeting workloads)

| Doesn't move | Handled by | Source |
|---|---|---|
| Shared, room and equipment mailboxes | `06` — standard cross-tenant mailbox migration (MRS) with stamped ExchangeGuid/x500 | [Learn] |
| Any mailbox on any hold type — the move is blocked | `06` — legal decision first; no hold-removal script | [Learn] |
| Custom (vanity) domain and UPNs on it | `09` — domain removal, addresses, `Set-TargetUpn`, DNS | [Playbook assumption — hypothesis order] |
| Mailboxes >100 per batch; a user in two batches | `05 Split-MigrationBatch` enforces the cap | [Learn] |
| Devices / PC state | `10` — new PCs, nothing moves | [Playbook decision] |
| Mailbox permissions (Full Access, Send As, Send on Behalf), forwarding, groups, contacts, rules | `08 Copy-MailConfig` / `06` permissions pair | [Learn — not in Orchestrator scope] |
| Public folders | Manual export or third-party tool | [Learn — not in scope] |
| Compliance/hold data itself (Purview policies, eDiscovery cases) | Recreate manually; export content per legal decision | [Learn — tenant config doesn't migrate] |

## SharePoint native cross-tenant migration (`07`)

| Doesn't move | Handled by | Source |
|---|---|---|
| Teams content, channels, channel structure — the SharePoint move carries **SharePoint content only** | Recreate team/channel structure; content per track decision | [Learn] |
| Group mailboxes attached to M365 groups | `06`/`08` as applicable | [Learn] |
| Planner plans, Loop workspaces | Manual/third-party | [Learn — not in the site's content] |
| Private/shared channel **sites** | ShareGate track (channel sites aren't covered by the group-site move) | [Learn] |
| No incremental/delta pass — the move is **one-time** | Plan timing: late in the project | [Learn] |
| 4,000 queued/pending moves limit (shared with OneDrive) | Sequence batches in `Start-SiteContentMoves -MaxConcurrent` | [Learn] |
| Target sites must not be precreated (move fails) | `New-TargetSiteGroups` creates groups only | [Learn] |

## Identity and platform

| Doesn't move | Handled by | Source |
|---|---|---|
| Meeting links for series occurrences modified mid-series | Users re-send those invites | [Playbook assumption — pilot item] |
| External meeting attendees' experience (expected: new invite needed) | Pilot confirmation required | [Playbook assumption] |
| Conditional Access, MFA policies, custom branding, app registrations/consents | Recreate in target; grant flows in `02` cover migration apps only | [Learn — tenant config doesn't migrate] |
| Teams app installations, tabs, bots | Recreate manually | [Playbook assumption] |
| BitLocker recovery keys (device objects) | Keys escrow in target from new PCs; source keys die with device objects | [Learn — key is tied to the device object] |
