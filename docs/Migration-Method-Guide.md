# Migration method guide

Which Microsoft tool moves which workload, its licence, prerequisites and limits —
and the decision table the readiness report (`00-Assessment\New-MigrationReadinessReport.ps1`)
implements. `MO` = Migration Orchestrator docs.

Learn pages:

- Cross-tenant migration orchestrator: https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-1-overview
- Cross-tenant mailbox migration: https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-mailbox-migration
- Cross-tenant OneDrive migration: https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration
- Cross-tenant SharePoint migration: https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-sharepoint-migration

## The four Microsoft tools

### Cross-tenant migration orchestrator

- **Moves:** user mailbox, OneDrive, Teams chats and Teams meetings for a user, in one batch.
  [Learn](.../migration-orchestrator-1-overview)
- **Licence:** Cross-Tenant User Data Migration — one per migrated user; one-time;
  purchased in source or target tenant. [Learn](.../migration-orchestrator-1-overview)
- **Prerequisites:** CTIM identity mapping in both tenants (playbook 03); Exchange Online
  and Teams licences on source *and* target users during the migration; org relationship,
  migration endpoint, scope group, Teams federation, OneDrive/SharePoint trust
  (playbook 02). [Learn](.../migration-orchestrator-1-overview)
- **Limits:** max 100 users per batch; holds block the move; a user can be in one batch only. [Learn](.../migration-orchestrator-1-overview)
- **Use when:** the object is a user mailbox whose OneDrive/chats/meetings should move together — the default for all user mailboxes. Playbook phases 03 + 05.
- **Not for:** shared/room/equipment mailboxes, SharePoint sites, teams/channels.

### Cross-tenant mailbox migration (`New-MigrationBatch`)

- **Moves:** a mailbox's user-visible content + Recoverable Items between tenants. [Learn](.../cross-tenant-mailbox-migration)
- **Licence:** Cross-Tenant User Data Migration per moved mailbox (source or target recipient). For shared/resource mailboxes the licence requirement is not explicit — budget one per mailbox and confirm with Microsoft.
- **Prerequisites:** target MailUsers/mailboxes stamped with the source ExchangeGuid, x500 addresses and **ArchiveGuid** (when the source is archive-enabled); source mailbox not on hold; max 12 auxiliary archives. Playbook 06 automates the stamping. [Learn](.../cross-tenant-mailbox-migration)
- **Archives:** archive mailboxes and aux archives are supported. Watch for: auto-expanding archives creating a new aux archive mid-move (fails — submit early), a disabled/demoted archive on the mailbox (fails — remove or re-enable first), and archives larger than the target quota (fails). [Learn](.../cross-tenant-mailbox-migration)
- **Limits:** public folders, M365 group mailboxes, Outbox, signatures and publicDelegates don't move; only store permissions survive on shared mailboxes. [Learn](.../cross-tenant-mailbox-migration)
- **Use when:** shared, room and equipment mailboxes — or any mailbox you want to move *without* the Orchestrator pipeline. Playbook 06.

### Cross-tenant OneDrive migration (standalone)

- **Moves:** a OneDrive site's content between tenants. [Learn](.../cross-tenant-onedrive-migration)
- **Licence:** Cross-Tenant User Data Migration per migrated OneDrive; eligible base SKUs required (see the Learn page). [Learn](.../cross-tenant-onedrive-migration)
- **Prerequisites:** identity map; target user licensed for OneDrive; no pre-created target site.
- **Limits:** one-time move (no delta); 5 TB / 1M items / 400-char path; apostrophe in UPN/URL fails; holds and Customer Key block; sharing links redirect only until the source is deprovisioned. [Learn](.../cross-tenant-onedrive-migration)
- **Use when:** a OneDrive has no migrating user mailbox — e.g. former employees' sites, or OneDrives moved on a different schedule than the mailbox. The Orchestrator path requires a source mailbox.
- **Playbook:** same 03/05 pipeline — the orchestrator moves the OneDrive of a migrating user; standalone moves cover the rest.

### Cross-tenant SharePoint migration

- **Moves:** a SharePoint site's content between tenants (incl. Teams-connected sites — SharePoint content only, not channels/posts/tabs). [Learn](.../cross-tenant-sharepoint-migration)
- **Licence:** Cross-Tenant Shared Data Migration — one licence per 100 GB moved, 20% grace, **Enterprise Agreement only**. [Learn](.../cross-tenant-sharepoint-migration)
- **Prerequisites:** identity mapping; no pre-created target site; supported site templates.
- **Limits:** no Teams content; workflows (2010/2013), apps, Power Apps/Automate and web parts don't move; user-defined-permission sensitivity labels block; 5 TB / 1M items / 400 chars; Customer Key blocks; read-only sites fail; one-time move. [Learn](.../cross-tenant-sharepoint-migration)
- **Use when:** non-personal SharePoint sites if the customer has an EA — otherwise a third-party tool (e.g. ShareGate). **Decision open** (playbook 07).

## Decision table

| Workload | Tool | Notes / playbook phase |
|---|---|---|
| User mailbox | Orchestrator | 03 + 05; ≤100 per batch |
| User archive | Orchestrator (with the mailbox) | inferred — Orchestrator doesn't state it; CTIM ArchiveGUID requirement implies it; confirm in pilot. Aux archives ≤12, auto-expanding and disabled archives can fail the move [Learn] |
| Shared/resource mailbox archive | Cross-tenant mailbox migration (with the mailbox) | ArchiveGuid must be stamped (06); needs Plan 2 or Plan 1 + EOA in target [Learn] |
| Shared / room / equipment mailbox | Cross-tenant mailbox migration | 06; permissions re-applied after |
| OneDrive of a migrating user | Orchestrator | moves with the user |
| OneDrive without a user mailbox | Cross-tenant OneDrive migration | standalone; needs a source mailbox for CTIM [Learn] |
| Teams chats / meetings | Orchestrator | moved with the user; long known-issues list → What-Doesnt-Move.md |
| SharePoint sites (incl. Teams-connected) | Cross-tenant SharePoint migration **or** third-party | EA licence; decision open (07) |
| Private / shared channel sites | Third-party / recreate | not covered by the site move [Learn] |
| Microsoft 365 groups | Recreate / third-party | group mailbox not supported by MRS [Learn] |
| Public folders | Third-party / PST / retire | no Microsoft tool [Learn] |
| Teams teams & channels | Recreate (+ third-party for posts) | structure + membership manual (07) |

## Licence math (what the readiness report computes)

- **Cross-Tenant User Data Migration** = user mailboxes in scope + shared/resource mailboxes
  in scope *(confirm shared-mailbox coverage with Microsoft)* + standalone OneDrives.
- **Cross-Tenant Shared Data Migration** = ceil(total non-personal SharePoint GB in scope / 100).
- **Target user licences:** Exchange Online + Teams on both sides during the migration;
  OneDrive plan for every user whose OneDrive migrates. License only after CTIM write (03). [Learn](.../migration-orchestrator-1-overview)
- **Shared mailboxes** need a licence when: >50 GB → **Exchange Online Plan 2**; archive or Litigation Hold → **Plan 2 or Plan 1 + Exchange Online Archiving**. [Learn](https://learn.microsoft.com/en-us/microsoft-365/admin/email/about-shared-mailboxes)

## Guests, groups and the SPO identity map

Before any OneDrive/SharePoint move, phase 03 builds three artefacts that the CTIM
mapping does not cover:

1. `Export-SourceGuests` → `New-TargetGuests` — guests become target members (when their
   mail domain is a verified target domain and a member exists), reused target guests,
   or new invitations (no invitation mail by default — redemption happens on first
   access, pilot item 26). Output: `guest-map.csv`.
2. `Export-SourceGroups` → `New-TargetGroups` — security groups are created, dynamic
   groups are created **paused** for review, site-migrating M365 groups are looked up
   (created by `07 New-TargetSiteGroups` with ProvisionSiteOnDemand), mail-enabled
   groups stay owned by `08 Copy-MailConfig`, role-assignable groups are refused.
   Members/owners land **before** the move. Output: `group-map.csv`.
3. `New-SpoIdentityMap` — merges users + guests + groups into the six-column,
   no-header, no-BOM map `Add-SPOTenantIdentityMap` expects. It **overwrites** the
   whole map, so always re-upload the complete file after any change; `-Verify`
   samples it, `-CheckCompatibility` gates it (Incompatible aborts).
   [Learn](https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration-step4)

Mailbox permissions (Full Access / Send As / Send on Behalf) have a single owner:
`06-SharedMailboxes-Holds` (`Export-` / `Set-TargetMailboxPermissions`).
`08 Copy-MailConfig` keeps only folder/calendar permissions, forwarding, lists,
contacts and dynamic groups (created hidden).
