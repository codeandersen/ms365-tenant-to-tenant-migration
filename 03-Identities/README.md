# 03 — Identities

**Purpose.** Create the target MailUsers, keep them unlicensed and OneDrive-free, scope the
source users, run Cross-Tenant Identity Mapping, verify the written attributes, and only then
license. **The order is load-bearing** — a licence or OneDrive before the CTIM write
provisions a mailbox/site on the target and the migration fails for that user.

## Order of operations

| # | Step | Tenant | Script |
|---|------|--------|--------|
| 1 | Create target MailUsers | Target | `New-TargetMailUsers.ps1` |
| 2 | Confirm no target OneDrive sites exist | Target | `Test-TargetOneDriveAbsent.ps1` + manual "block creation" below |
| 3 | Add source users to the scope group | Source | `Add-MigrationGroupMembers.ps1` |
| 4 | CTIM service principal (both tenants) | both | `Invoke-CtimMapping.ps1 -Step AddServicePrincipal -CtimTenantRole Source\|Target` |
| 5 | CTIM copy request | Source | `-Step Copy` — share the RequestID with the target admin |
| 6 | Accept the copy request | Target | `-Step Status` until `AwaitingTargetTenantApproval`, then `-Step Accept` |
| 7 | Map | Target | `-Step Map` (PrimarySmtpAddress matching; or Download→edit→Upload→`-Step Map -UseCsv`) |
| 8 | Write attributes | Target | `-Step Write` — stamps ExchangeGuid, ArchiveGuid, LegacyExchangeDN/x500, EmailAddresses, PrimarySmtp |
| 9 | Verify | Source then Target | `Test-IdentityMapping.ps1 -Mode ExportSource` → `-Mode Verify` |
| 10 | License | Target | `Set-TargetLicenses.ps1` (refuses unverified users) |
| 11 | Cleanup when done | both | `-Step RemoveServicePrincipal` |

## Guests, groups and the SPO identity map (before any ODSP move)

| # | Step | Tenant | Script |
|---|------|--------|--------|
| 12 | Export source guests | Source | `Export-SourceGuests.ps1` → `source-guests.csv` |
| 13 | Map/invite target guests | Target | `New-TargetGuests.ps1 -WhatIf` → `guest-map.csv` |
| 14 | Export source groups + members | Source | `Export-SourceGroups.ps1` → `source-groups.csv` + `source-group-members.csv` |
| 15 | Create site-migrating M365 groups | Target | `07 New-TargetSiteGroups.ps1` (ProvisionSiteOnDemand) |
| 16 | Build target groups + members/owners | Target | `New-TargetGroups.ps1 -WhatIf` → `group-map.csv` — **members must exist before moves** |
| 17 | Build + upload + verify SPO identity map | Target | `New-SpoIdentityMap.ps1 -Upload -Verify` — **full map, overwrites**; re-upload after every change |
| 18 | Compatibility check | Source | `New-SpoIdentityMap.ps1 -CheckCompatibility` — Incompatible stops |

**CTIM vs SPO identity map:** CTIM (steps 4–9) maps **only the migrating users** for
mailbox/OneDrive moves. The SPO identity map (step 17) is what preserves access for
**other users, guests and groups** to OneDrive/SharePoint content. Learn calls it
optional — this playbook treats it as **required**. Format:
`01-Design/templates/SPO-Identity-Map.md`.

Guest notes: a guest whose mail domain is a verified target domain and exists as a target
member is mapped to that member (no invite). Otherwise guests are invited without an
e-mail by default (they redeem on first access to a shared resource — pilot item); use
`-SendInvitationMessage` to mail them. Dynamic groups are created **paused** for review;
mail-enabled groups are owned by `08 Copy-MailConfig`; role-assignable groups are refused
(manual handling).

> ⚠️ **No licence and no OneDrive before the CTIM write is verified.** If a user was
> licensed early and now has a mailbox on the target, that user cannot migrate — remove the
> licence/mailbox and recreate the MailUser.

## CTIM session rule (documented, easy to trip over)

Run every CTIM step from a **fresh PowerShell window** with no Exchange Online or Graph
session — token acquisition breaks otherwise ("loopback redirect URI"). `Invoke-CtimMapping.ps1`
refuses to run most steps while a session is active. The exception is
`AddServicePrincipal`/`RemoveServicePrincipal`, which connect (tenant-guarded) and disconnect
themselves.

`-Step Accept -Overwrite` always downloads the current mapping file to `customers/` first —
overwritten mappings cannot be recovered.

> ⚠️ **Never run `Remove-CtimData` (`-Step RemoveData`) while any migration batches are
> running.** It removes users with completed mailbox migrations from identity mapping,
> which breaks their Teams chats/meetings experience and any failed migrations you rerun
> later. To *add* users to the mapping, rerun Identity Mapping **without**
> `Remove-CtimData`. Removing mapping data also doesn't un-write attributes already
> stamped. `[Learn](.../migration-orchestrator-7-end-user-exp)`

## Blocking OneDrive creation (manual, documented)

Microsoft documents preventing personal-site creation only via the SharePoint admin centre —
there is no documented cmdlet to disable it per-user. In the **target** tenant:

`https://<tenant>-admin.sharepoint.com` → More features → User profiles → **Manage User
Permissions** → under "Create Personal Site", remove *Everyone except external users* and add
only a group of users allowed to create OneDrive (exclude the migration users).

Ship `Test-TargetOneDriveAbsent.ps1` to verify none of the listed users already have a site.

## Passwords

`New-TargetMailUsers.ps1` sets a random per-user password that is never printed or stored —
the doc requires the object to carry a password but nothing needs to know it. Users get real
credentials later via password reset or Temporary Access Pass (pilot/cutover runbook).

## Hybrid

Cloud-only: the DirSynced-MailUser write path (`Write-CtimIdentitiesInOnPremises`) is out of
scope.

## Files

- `New-TargetMailUsers.ps1` — create MailUsers (idempotent, `-WhatIf`, adapted from the
  upstream toolkit; stamps nothing itself).
- `Test-TargetOneDriveAbsent.ps1` — read-only check for pre-provisioned personal sites.
- `Add-MigrationGroupMembers.ps1` — add source users to the scope group; warns on
  membership in a second published scope.
- `Invoke-CtimMapping.ps1` — one CTIM step per run.
- `Test-IdentityMapping.ps1` — export source identity / verify target MailUsers.
- `Set-TargetLicenses.ps1` — license verified users only.
- `Export-SourceGuests.ps1` — all source guests → `source-guests.csv` (read-only).
- `New-TargetGuests.ps1` — map to existing member/guest or invite (`-WhatIf`, no invite mail by default) → `guest-map.csv`.
- `Export-SourceGroups.ps1` — all groups + members/owners → `source-groups.csv` + `source-group-members.csv` (read-only).
- `New-TargetGroups.ps1` — create security/dynamic/M365 groups and set members/owners (`-WhatIf`) → `group-map.csv`.
- `New-SpoIdentityMap.ps1` — build the full six-column SPO identity map; `-Upload -Verify -CheckCompatibility` (`-WhatIf` on upload).

> Untested against live tenants — validate in technical test/pilot.
