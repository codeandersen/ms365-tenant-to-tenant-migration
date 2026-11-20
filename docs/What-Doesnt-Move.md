# What doesn't move

Per workload: what the Microsoft cross-tenant tools **do not** carry over, what handles it
instead in this playbook, and the source of the claim.

Legend: `[Learn]` = documented on Microsoft Learn (link in the table) ·
`[Playbook assumption — verify in pilot]` = not documented, validate before production ·
`[General Exchange Online licensing]` = standard licensing rule, not migration-specific.

Learn pages referenced:

- Orchestrator overview: https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-1-overview
- End-user experience / known issues: https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-7-end-user-exp
- Orchestrator FAQ: https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-8-faq
- Cross-tenant mailbox migration: https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-mailbox-migration
- Cross-tenant OneDrive migration: https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration
- Cross-tenant SharePoint migration: https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration

## 1. Users: mailbox, OneDrive, Teams chats and meetings (Orchestrator)

### Mailbox

| Doesn't migrate | What to do instead / playbook phase | Source |
|---|---|---|
| Anything except user-visible content + Recoverable Items | Nothing — out of scope | [Learn](.../cross-tenant-mailbox-migration) |
| Outbox items | Re-send after cutover | [Learn](.../cross-tenant-mailbox-migration) |
| The hidden Teams chat folder in the mailbox | Teams chats move via the Teams workload instead | [Learn](.../cross-tenant-mailbox-migration) |
| Outlook signatures | Users recreate (After-Cutover-User-Guide) | [Learn](.../cross-tenant-mailbox-migration) |
| `publicDelegates` / Send on Behalf | Re-stamp in target (phase 08) | [Learn](.../cross-tenant-mailbox-migration) |
| Mailbox permissions (Full Access, Send As) granted cross-tenant | Re-apply in target (phase 06/09) | [Learn](.../cross-tenant-mailbox-migration) |
| Mailboxes on any hold (Litigation, eDiscovery, retention, delay) — **blocked, not skipped** | Resolve holds first (00/G2) | [Learn](.../cross-tenant-mailbox-migration) |
| eDiscovery discoverability in the source after the move | Source content stays discoverable against the source mailbox — plan closure accordingly (phase 12) | [Learn](.../cross-tenant-mailbox-migration) |
| Sensitivity labels / protection on items | Re-apply in target | [Learn](.../cross-tenant-mailbox-migration) |
| Teams calendar entries stored in the source mailbox | Meetings move via the Meeting workload; the source-side Teams calendar stops working | [Learn](.../migration-orchestrator-7-end-user-exp) |
| More than 12 auxiliary archives per mailbox — **blocked** | Reduce archives first | [Learn](.../cross-tenant-mailbox-migration) |
| Archive GUID not stamped on the target object — the move doesn't proceed | CTIM `ArchiveGUID` mapping (03); `06` stamps it for shared mailboxes | [Learn](.../cross-tenant-mailbox-migration) |
| Auto-expanding archive that creates a new aux archive mid-move — the move **fails** | Submit well ahead of cutover; remove from batch and resubmit if it expands | [Learn](.../cross-tenant-mailbox-migration) |
| Disabled/demoted archive on the mailbox — the move **fails** | `Set-Mailbox -RemoveDisabledArchive`, or re-enable and update ArchiveGuid on the target MailUser | [Learn](.../cross-tenant-mailbox-migration) |
| Archive larger than the target archive quota — the move **fails** | Check target quota before the batch (readiness report §2) | [Learn](.../cross-tenant-mailbox-migration) |
| Microsoft 365 group mailboxes | MRS doesn't support them; no Microsoft tool | [Learn](.../cross-tenant-mailbox-migration) |

### OneDrive (as part of an Orchestrator batch)

| Doesn't migrate | What to do instead | Source |
|---|---|---|
| OneDrives on hold — **blocked** | Resolve holds first | [Learn](.../cross-tenant-onedrive-migration) |
| Delta sync — the move is **one-time**, no incremental passes | Users work from target after cutover | [Learn](.../cross-tenant-onedrive-migration) |
| Content over 5 TB or 1 million items per OneDrive | Reduce/split first | [Learn](.../cross-tenant-onedrive-migration) |
| File paths over 400 characters | Shorten paths first | [Learn](.../cross-tenant-onedrive-migration) |
| Users whose UPN or site URL contains an apostrophe — **fails** | Change the UPN/URL first | [Learn](.../cross-tenant-onedrive-migration) |
| Anything if Customer Key is enabled on the source — **blocked** | Roll off Customer Key first | [Learn](.../cross-tenant-onedrive-migration) |
| Old sharing links keep working only via the redirect — until the source site is deprovisioned | Users update bookmarks/links | [Learn](.../cross-tenant-onedrive-migration) |

### Teams chats (1:1 and group chats)

The full known-issues list from the end-user-experience page `[Learn](.../migration-orchestrator-7-end-user-exp)`:

| Doesn't migrate | What to do instead |
|---|---|
| Chat with self (the pinned "You" chat) | Users copy notes/links/files to OneDrive or a document before cutover |
| Chats started by external users | Accept the gap or export |
| Chats started by users who left either tenant or lost their Teams licence | Accept the gap |
| 1:1 chats that no longer have two members | Accept the gap |
| Threads without identifiable members | Accept the gap |
| Messages from users with an unrecognized GUID, no Microsoft account, or no display name/ID — their messages don't migrate and they aren't added to target threads | Accept the gap |
| History of a chat a user was **removed from before** the migration | They don't see it in the target |
| Reactions on messages | Accept the gap |
| Apps, polls and other chat message extensions | Recreate/re-run in target |
| Forwarded messages; **scheduled** messages that hadn't been sent yet (ones already sent migrate) | Re-send |
| Messages over 4 MB | Accept the gap |
| Messages with missing body content, legacy Skype metadata or invalid source images | Accept the gap |
| Attachments without an extension, attachments with missing markers, hosted attachments that aren't .jpg/.jpeg/.png | Share again from OneDrive |
| Unsupported/decommissioned emojis and code snippets formatting | Cosmetic — accept |
| Deleted messages | Expected |
| System messages (except meeting-recap messages) | Expected |
| New messages posted in the **source** after migration | Users must stop using source Teams |
| Possible duplicate or temporary-looking chats in the target | Cosmetic — accept |

### Teams meetings

Known issues `[Learn](.../migration-orchestrator-7-end-user-exp)`:

| Doesn't migrate | What to do instead |
|---|---|
| Meeting recordings, transcripts, recaps | Stay in the source tenant |
| Attendance reports | Export before cutover if needed |
| Meeting apps, tags | Recreate |
| Channel meetings and shared-channel meetings | Recreate in the new team/channel |
| Live events, webinars, town halls, virtual appointments, controlled-content meetings, large meetings and other custom-template meetings; meetings over 250 attendees | Recreate |
| Meetings that already exist in the target tenant | Not migrated; their participant list is not updated — recreate if needed |
| Skype-to-Teams / Teams-to-Skype content | Out of scope — only Teams-to-Teams tenants are supported |
| Meeting updates once source objects/mail forwarding are removed mid-migration | Keep source MailUsers + mail forwarding until **all** batches are done (12) — deleted source objects also mean the same users can never be re-migrated |
| Canceled meetings | Expected |
| **Modified occurrences of a series keep the old (source) URL** | Organiser re-sends the series |
| Appointments without Teams join coordinates | Nothing — no link to move |
| Meetings organised by room or equipment mailboxes | Recreate |
| Room locations on meetings | Recreate |
| **RSVPs — meeting acceptances are reset** | Users re-accept meetings (After-Cutover-User-Guide) |
| Non-Default calendars | Only the Default calendar is in scope |
| Confidential / Highly Confidential meetings | Recreate |
| Meetings with distribution-group participants | Expand/recreate |
| Spoken-language setting on meetings | Resets — set again |
| Meetings older than 60 days keep the old URL and their chat becomes a group chat | Accept |

Voicemails **do** migrate `[Learn](.../migration-orchestrator-8-faq)`: received voicemails
arrive as attachments in the mailbox and as saved messages reachable by calling voicemail,
and the greeting migrates — they just aren't listed in the Teams client UI in the target.

## 2. Shared, room and equipment mailboxes (cross-tenant mailbox migration)

These mailboxes are **not in Orchestrator scope** — they move via
`New-MigrationBatch`/`Start-MigrationBatch` (playbook 06).
`[Learn](.../cross-tenant-mailbox-migration)`

| Doesn't migrate | What to do instead | Source |
|---|---|---|
| Permissions except store-level permissions — only store permissions survive | Re-apply Full Access via `Set-TargetMailboxPermissions` (06) | [Learn](.../cross-tenant-mailbox-migration) |
| Send on Behalf (`GrantSendOnBehalfTo`) | Re-stamp (08) | [Learn](.../cross-tenant-mailbox-migration) |
| Send As and Full Access granted to users **cross-tenant** | Re-apply in target | [Learn](.../cross-tenant-mailbox-migration) |
| Room booking policies and calendar-processing settings (`Set-CalendarProcessing`) | Re-apply in target | [Playbook assumption — verify in pilot] |
| Meetings organised by room/equipment mailboxes (Teams links not updated) | Recreate room meetings | [Learn](.../migration-orchestrator-7-end-user-exp) |
| Licence question: Learn's licence text covers "source recipient or target recipient" — whether shared/resource mailboxes consume a Cross-Tenant User Data Migration licence is **not explicit** | Budget one per moved shared mailbox; confirm with Microsoft (docs/Questions-For-Microsoft.md) | [Playbook assumption] |
| Shared mailboxes over 50 GB need Plan 2; an archive or Litigation Hold needs Plan 2 or Plan 1 + Exchange Online Archiving in the target | Counted per mailbox by the readiness report | [Learn](https://learn.microsoft.com/en-us/microsoft-365/admin/email/about-shared-mailboxes) |
| Microsoft 365 Groups (group mailbox) | Not supported by MRS — no Microsoft tool | [Learn](.../cross-tenant-mailbox-migration) |

## 3. Microsoft Teams teams (teams and channels — not 1:1/group chats)

Orchestrator does not move teams or channels. A SharePoint site move of a
Teams-connected site carries **SharePoint content only** — not the Teams structure.
`[Learn](.../cross-tenant-sharepoint-migration)` `[Learn](.../migration-orchestrator-1-overview)`

| Doesn't migrate | What to do instead | Source |
|---|---|---|
| Teams and channel structure itself | Recreate in target (playbook 07) | [Learn](.../migration-orchestrator-1-overview) |
| Channel messages / posts | PDF archive per channel possible (read-only export, `07 Export-TeamsChannelsToPdf.ps1`, pilot item 27); live history needs a third-party import or is lost | [Learn](.../cross-tenant-sharepoint-migration) |
| Tabs, apps, bots, connectors | Recreate or third-party | [Learn](.../cross-tenant-sharepoint-migration) |
| Channel meetings | Recreate | [Learn](.../migration-orchestrator-7-end-user-exp) |
| Private and shared channels and their sites | Recreate (channel sites not covered by the group-site move) | [Learn](.../cross-tenant-sharepoint-migration) |
| Team settings and membership | Recreate; identity mapping preserves file permissions only for mapped users/groups | [Learn](.../cross-tenant-sharepoint-migration) |
| Microsoft 365 group mailbox and calendar | Not supported by mailbox migration | [Learn](.../cross-tenant-mailbox-migration) |
| Planner, Loop, Forms, Whiteboard, wiki, OneNote notebooks | Recreate or third-party | [Playbook assumption — state source per workload] |
| Teams Phone: numbers, auto attendants, call queues, policies | Port/rebuild in target | [Playbook assumption] |

## 4. SharePoint sites (cross-tenant SharePoint migration)

`[Learn](.../cross-tenant-sharepoint-migration)` — requires Enterprise Agreement and the
**Cross-Tenant Shared Data Migration** licence (one per 100 GB moved, 20% grace).

| Doesn't migrate | What to do instead | Source |
|---|---|---|
| Teams content, channels, channel structure | Recreate (07) | [Learn] |
| Workflows (2010/2013) | Rebuild | [Learn] |
| Apps, Power Apps, Power Automate flows | Rebuild | [Learn] |
| Web parts | Rebuild | [Learn] |
| Sensitivity labels — user-defined-permission labels **block** the move | Re-label first | [Learn] |
| Pre-created target sites — the move **fails** if the site exists | Do not precreate (03 checks) | [Learn] |
| Sites over 5 TB / 1 million items; paths over 400 chars | Reduce first | [Learn] |
| Customer Key on source — **blocked** | Roll off first | [Learn] |
| Read-only/locked sites — **fail** | Unlock first | [Learn] |
| One-time move — no delta | Time the move late | [Learn] |

## 5. Tenant configuration and identity

| Doesn't migrate | What to do instead | Source |
|---|---|---|
| Conditional Access policies, named locations, auth-method settings | Tenant configuration - recreate in target (`00 Export-TrustedLocations.ps1` produces a hand-over file for named locations) | [Learn](.../conditionalaccessroot-list-namedlocations) |
| MFA registrations (users' methods) | Tenant-specific - every user registers MFA in the target at first sign-in; consider Temporary Access Pass for onboarding | [Playbook assumption] |
| Intune policies and devices | Strategy decision (Decision-Log): NewDevices - new PCs enrol in target (phase 10); ExistingDevices - devices must leave the source tenant, method not scripted | [Playbook decision] |
| App registrations / enterprise applications and consents | Recreate; grant flows in 02 cover migration apps only | [Playbook assumption] |
| Purview: labels, DLP, retention, eDiscovery cases | Recreate in target | [Playbook assumption] |
| Custom domain / vanity UPNs | Phase 09 — domain removal, addresses, `Set-TargetUpn`, DNS | [Playbook assumption — hypothesis order] |
| Cross-cloud moves (e.g. GCC → commercial) | Not supported | [Learn](.../cross-tenant-mailbox-migration) |
| Same domain verified in both tenants simultaneously | Not possible — domain must leave the source first | [Learn](.../migration-orchestrator-1-overview) |
| Project Online | Not covered — third-party | [Playbook assumption] |
| Power Platform environments/apps | Recreate | [Playbook assumption] |
| Viva Engage | Third-party/manual | [Playbook assumption] |
| Bookings | Rebuild | [Playbook assumption] |

## Questions for Microsoft

Open items live in [Questions-For-Microsoft.md](Questions-For-Microsoft.md) — including
CTIM for shared mailboxes, the shared-mailbox licence question, and OneDrive/SPO trust
removal syntax.

### Guests, groups and the SPO identity map (OneDrive/SharePoint)

| What | Playbook answer | Source |
|---|---|---|
| External guests' access to OneDrive/SharePoint content | Preserved via the SPO identity map (`03 New-SpoIdentityMap`) — guest mapped to a target guest or target member; guests are invited/reused by `New-TargetGuests` first | [Learn](https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration-step4) |
| Group-granted permissions (security, M365, mail-enabled) | Groups are recreated in the target with members/owners **before** the move (`New-TargetGroups`); the map row makes the old group's permissions follow | [Learn](.../cross-tenant-onedrive-migration-step4) |
| Guests/external users NOT in the map | They lose access — mapped guests keep it; anyone else must be re-invited by the user after migration | [Playbook assumption] — pilot item 21 |
| "Anyone" links | Behaviour after the move is not documented — verify in the pilot (item 24) | [Playbook assumption] |
| Mailbox permissions (Full Access / Send As / Send on Behalf) | Owned solely by `06-SharedMailboxes-Holds` — `08 Copy-MailConfig` no longer exports or imports them | Playbook design |
| Dynamic distribution lists | Recreated hidden by `08 Copy-MailConfig -Include DynamicGroups`; review the filter, then unhide | Playbook design |
