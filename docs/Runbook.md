# Runbook — canonical timeline

T-45 days → T+30 days. Every phase, script and **go/no-go gate** in one place.
`<src>` = source tenant, `<tgt>` = target tenant. All tenant-changing steps support `-WhatIf`.

> **Gates** are hard stops: do not proceed until the gate item is verified *and* a named human
> has signed it off. A failed gate is not a schedule slip — it's the plan working.

## T-45 → T-30 — assessment, design, technical test

| When | What | Gate |
|---|---|---|
| T-45 | `00-Assessment` inventory (`Collect-TenantInventory`, `Get-MigrationReport`, `New-MigrationReadinessReport` → `Readiness.md`, see `docs/Migration-Method-Guide.md`) | — |
| T-42 | `01-Design`: fill `migration-users.csv` (onmicrosoft target addresses; `FinalUpn`/`FinalPrimarySmtp` for after the domain move), batches ≤100, workload mix, cutover weekend | **G1** user list signed off by business |
| T-42 | `06` hold survey: `Get-HoldReport` — held mailboxes **cannot migrate** | **G2** legal decision per held mailbox |
| T-40 | `07` site survey: `Get-SiteMigrationPlan` — native vs ShareGate track (item still open) | — |
| T-40 | `10` device survey: `Get-DeviceInventory`, `Get-BitLockerKeyReport`; order new PCs | — |
| T-38…T-31 | `04` **technical test** on a *test tenant pair*: the full backbone end to end. The domain/UPN order can only be rehearsed here, with a test domain — a domain can't be moved partially, so this is the only place the 09 hypothesis gets a dry run | — |

## T-30 → T-21 — tenant preparation and pilot

| When | What | Gate |
|---|---|---|
| T-30 | `02` both tenants: `Test-OrchestratorPrereqs`, then `Set-OrchestratorTenantPrep` per step (org relationship, endpoint, Teams federation, OneDrive trust, migration apps) | **G3** prereq report all Pass/acknowledged Unknown |
| T-30 | Manual portal steps: target app registration + secret + source admin consent; EA cross-tenant licences procured | — |
| T-28 | `03` for **pilot users only**: `New-TargetMailUsers` → `Test-TargetOneDriveAbsent` → scope group → `Invoke-CtimMapping` (fresh sessions; download before `-Overwrite`) → `Test-IdentityMapping -Mode Verify` → `Set-TargetLicenses` | **G4** pilot rows map and license cleanly |
| T-26…T-22 | `04` **pilot**: a small batch of real pilot users through the whole flow in the production tenants; work `Pilot-Test-Checklist.md` and send the open questions to Microsoft | **G5** pilot checklist signed off — the only place hypotheses become facts |
| T-21 | `03` for all remaining production identities (same chain as T-28): MailUsers → no-OneDrive check → scope group → CTIM → Verify → licence (24h-verification gate) | **G6** `Test-IdentityMapping` all rows Pass before licences are assigned |
| T-20 | Guests + groups + SPO identity map (all before any ODSP/site move): `03 Export-SourceGuests` → `New-TargetGuests` → `Export-SourceGroups` → `07 New-TargetSiteGroups` → `New-TargetGroups` (members/owners in place **before** moves) → `New-SpoIdentityMap -Upload -Verify` → `New-SpoIdentityMap -CheckCompatibility` (source). Re-upload the **full** map after every identity change — upload overwrites | **G6b** identity map uploaded and verified; compatibility not Incompatible |

## T-14 → T-5 — batches, shared mailboxes, mail config

| When | What | Gate |
|---|---|---|
| T-14 | `05 New-MigrationBatches` — creation auto-validates each batch | **G7** all batches ValidatePassed |
| T-14 | Send user comms T-14 (`docs/Comms-Templates.md`) | — |
| T-10 | `06` shared/room/equipment path: `Export-SourceMailboxAttributes` → `New-SharedMailboxMailUsers` → `New-CrossTenantMailboxBatch -Autostart -CompleteAfter <cutover>` — the batch **pre-syncs now and completes in the cutover weekend**; holds must already be resolved (G2) | — |
| T-10 | `07 New-TargetSiteGroups` (only where the native move needs pre-created groups) | — |
| T-8 | `08 Copy-MailConfig -Mode Export`; `09 Export-DomainDns` (rollback copy); lower DNS TTLs | — |
| T-8 | `05 Test-MigrationBatch` — revalidate every batch right before the Move if its ValidatePassed would be older than 7 days at Start time (validation expires; `Start-BatchMigration` refuses stale validation) | — |
| T-7…T-5 | `05 Start-BatchMigration` (the **Move**) — must run within 7 days of ValidatePassed so Exchange pre-sync can run until `CompleteAfterDateTime` | **G8** signed off to start the move |
| daily | `05 Get-BatchStatus` — `Update-BatchCutover` only **before** `CompleteAfterDateTime` passes | — |
| T-7 | Comms T-7 | **G9** `Test-CutoverReadiness -BlockersOnly` clean |

## Cutover weekend — **hypothesis, not Microsoft-documented** (see 09 README)

`CompleteAfterDateTime` in each batch drives the sync completion. Hour-by-hour, assuming
completion lands early Saturday:

| Hour | Step | Gate |
|---|---|---|
| H+0 | `05 Get-BatchStatus` — every user every workload Completed | **G10** all batches terminal |
| H+0 | `07 Start-SiteContentMoves` for `Native` rows — source sites go read-only during the move, a redirect is left behind. (Not earlier: users still work in source until cutover) | — |
| H+1 | `09 Remove-SourceDomain -SnapshotOnly`, then `-RemoveDomain` after `Clear-DeletedUserDomain` | **G11** per-object backups written before any change (script aborts if not) |
| H+1 | `06` shared-mailbox batch completes (`-CompleteAfter`); verify the target mailboxes exist → `Set-TargetMailboxPermissions` re-applies permissions | — |
| H+2 | `09 Add-TargetDomain` (add unverified → MS= TXT → `-WaitForDns` → `-Verify`) | **G12** domain verified in target |
| H+3 | `09 Switch-TargetAddresses` — old addresses + X500s back **as aliases** (never primaries) | — |
| H+4 | `09 Set-TargetUpn` (users) + `Set-TargetPrimaryAddress` (shared/resource mailboxes) — refuses non-Completed batches | **G13** only Completed users change |
| H+5 | `09 Set-DomainDnsRecords` — MX/SPF/DKIM/autodiscover at the provider | — |
| H+6 | `06 Set-TargetMailboxPermissions` (Full Access/Send As/Send on Behalf — the only permission re-applier) + `08 Copy-MailConfig -Mode Import` incl. apply-after-09 items; DDGs are created **hidden** — review filters, then unhide | — |
| H+7 | `09 Block-SourceSignIn -Exclude <break-glass>` | — |
| H+8 | `11 Test-TargetTenant -FinalDomain <domain>` | **G14** validation green before Monday |

Users sign in to the target on their new PCs Monday morning; Outlook builds a new profile.

## T+1 → T+30 — validation and decommission

| When | What | Gate |
|---|---|---|
| T+1 | User comms T+1; service desk ready for profile/sign-in issues | — |
| T+7 | `11` re-validate; `12 Get-DecommissionReadiness` | **G15** no unexplained mail flow into source |
| T+14 | User comms T+7; confirm pilot's open questions with Microsoft | — |
| T+30 | `12 Remove-MigrationArtifacts` per step (all batches terminal); licence step-down; old-PC retirement per `Get-OldDeviceRetirementPlan`; comms + lessons learnt | **G16** retention decision documented before licences/tenant go |

## User-facing timeline (what users see)

| When | Message |
|---|---|
| T-14 | "You're moving to a new Microsoft 365 environment on <date>. You'll get a new PC." |
| T-7 | "Sign in once on your new PC with your new account to register MFA — don't open Outlook or OneDrive on it yet." |
| T-1 | "Old environment goes quiet <time>. Make sure all your work files are saved in OneDrive, not only on the old PC." |
| T+0 | "Use the new PC. New Outlook profile builds itself. Everything's still there." |
| T+1/T+7 | "Report anything missing; here's the known-issues list." |
