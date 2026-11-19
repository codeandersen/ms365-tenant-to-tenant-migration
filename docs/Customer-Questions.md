# Customer questions

Ask these before estimating or promising anything. Grouped by phase.

## Business & scope

- Which domains must move? Any domains staying behind?
- Hard deadline (lease end, divestiture date)? Is a cutover weekend acceptable?
- Single wave or department waves? Can a 50-user pilot group go first?
- Who signs off go/no-go gates? Who owns legal/hold decisions?

## Tenant & licensing

- Source tenant EA or CSP — is the **Cross-Tenant User Data Migration** licence available to you
  at all (Enterprise Agreement customers only)?
- Exchange Online + Teams licences for every migrated user in both tenants during migration?
- SharePoint cross-tenant migration licences (for the native site move)?
- Tenant region and data-residency constraints (Multi-Geo?)?

## Identities & mail

- Directory sync in use? (This playbook is cloud-only — sync changes everything.)
- Shared/room/equipment mailboxes: how many, which hold Send As / Full Access delegates?
- **Litigation hold, retention policies, eDiscovery cases**: which mailboxes, who owns the
  decision, and is preservation via eDiscovery export acceptable before release?
- Distribution groups, mail contacts, dynamic groups to recreate? Any hidden groups?
- Forwarding rules that must survive (service accounts, integrations)?
- Are archives in use, and may auto-expanding archives be paused/left untouched during the
  migration window? (A new aux archive created mid-move fails the move.)
- Mail flow outside Exchange Online: on-prem relay, scanners, multifunction printers, contact
  forms, third-party filtering?

## SharePoint & Teams

- Which sites matter: team sites, communication sites, OneDrives? Approximate count and size?
- Private/shared channel sites in use?
- Teams structure (channels, tabs, apps, Planner) that must be recreated — by whom?
- Third-party migration tooling (e.g. ShareGate) already licensed?

## Devices & endpoints

- How are PCs joined today (Entra joined, hybrid, BYOD-registered)? Intune-managed?
- BitLocker enabled? Who holds the process for retrieving an escrowed key?
- Device plan: new PCs via Autopilot (this playbook's assumption) — is hardware procured?
- Mobile devices / work profiles to re-enrol?

## Security & compliance

- Conditional Access policies, MFA methods, break-glass accounts (name them — they go in
  `-Exclude` lists)?
- Any Conditional Access location policies that could block cutover-weekend admin work?
- Guest users in either tenant that could collide with migrated addresses?
- Which apps with no recorded sign-ins can be dropped instead of rebuilt in the target?

## DNS & logistics

- Who controls public DNS (registrar + provider: GoDaddy, Cloudflare, other)? API access or
  manual changes during the window?
- Current TTLs — can they be lowered a week ahead?
- Who writes the comms, in which languages, and who staffs the help desk on cutover Monday?
