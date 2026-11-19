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

> Untested against live tenants — validate in technical test/pilot.
