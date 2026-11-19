# Runbook — canonical timeline

T-30 days → T+30 days. Every phase, script and **go/no-go gate** in one place.
`<src>` = source tenant, `<tgt>` = target tenant. All tenant-changing steps support `-WhatIf`.

> **Gates** are hard stops: do not proceed until the gate item is verified *and* a named human
> has signed it off. A failed gate is not a schedule slip — it's the plan working.

## T-30 → T-21 — assessment and design

| When | What | Gate |
|---|---|---|
| T-30 | `00-Assessment` inventory (`Collect-TenantInventory`, `Get-MigrationReport`) | — |
| T-28 | `01-Design`: fill `migration-users.csv`, batches ≤100, workload mix per batch, cutover weekend | **G1** user list signed off by business |
| T-28 | `06` hold survey: `Get-HoldReport` — held mailboxes **cannot migrate** | **G2** legal decision per held mailbox |
| T-25 | `07` site survey: `Get-SiteMigrationPlan` — native vs ShareGate track | — |
| T-25 | `10` device survey: `Get-DeviceInventory`, `Get-BitLockerKeyReport`; order new PCs | — |

## T-21 → T-14 — tenant preparation and identities

| When | What | Gate |
|---|---|---|
| T-21 | `02` both tenants: `Test-OrchestratorPrereqs`, then `Set-OrchestratorTenantPrep` per step (org relationship, endpoint, Teams federation, OneDrive trust, migration apps) | **G3** prereq report all Pass/acknowledged Unknown |
| T-21 | Manual portal steps: target app registration + secret + source admin consent; EA cross-tenant licences procured | — |
| T-18 | `03 New-TargetMailUsers` → `Test-TargetOneDriveAbsent` (expect none) | **G4** zero unexpected personal sites |
| T-18 | `03 Add-MigrationGroupMembers` (scope group = exactly one scope per object) | — |
| T-17 | `03 Invoke-CtimMapping` — Copy → Accept → Map → **Download before any -Overwrite** → Write (fresh sessions!) | **G5** `Get-CtimReport` shows write Complete |
| T-16 | `03 Test-IdentityMapping -Mode Verify` — ExchangeGuid + x500s match | **G6** all rows Pass |
| T-16 | `03 Set-TargetLicenses` (24h-verification gate) | — |
| T-14 | Send user comms T-14 (`docs/Comms-Templates.md`) | — |

## T-14 → T-7 — technical test, pilot, batches

| When | What | Gate |
|---|---|---|
| T-14 | `04` pilot: small batch through the whole flow on test tenants; work the `Pilot-Test-Checklist` | **G7** pilot checklist signed off — the only place hypotheses become facts |
| T-12 | `05 New-MigrationBatches` (auto-validates on creation) | **G8** all batches ValidatePassed |
| T-10 | `06` shared/room/equipment path: `Export-SourceMailboxAttributes` → `New-SharedMailboxMailUsers` → `New-CrossTenantMailboxBatch` | — |
| T-10 | `07 New-TargetSiteGroups` (only where the native move needs pre-created groups) | — |
| T-8 | `07 Start-SiteContentMoves` for `Native` rows; `08 Copy-MailConfig -Mode Export` | — |
| T-7 | Lower DNS TTLs on moving domains; `09 Export-DomainDns` (rollback copy); comms T-7 | **G9** `Test-CutoverReadiness -BlockersOnly` clean |

## Cutover weekend — **hypothesis, not Microsoft-documented** (see 09 README)

`CompleteAfterDateTime` in each batch drives the sync completion. Hour-by-hour, assuming
completion lands early Saturday:

| Hour | Step | Gate |
|---|---|---|
| H+0 | `05 Get-BatchStatus` — every user every workload Completed | **G10** all batches terminal |
| H+1 | `09 Remove-SourceDomain -SnapshotOnly`, then `-RemoveDomain` after `Clear-DeletedUserDomain` | **G11** per-object backups written before any change (script aborts if not) |
| H+2 | `09 Add-TargetDomain` (add unverified → MS= TXT → `-WaitForDns` → `-Verify`) | **G12** domain verified in target |
| H+3 | `09 Switch-TargetAddresses` — addresses + X500s back on | — |
| H+4 | `09 Set-TargetUpn` — refuses non-Completed batches | **G13** only Completed users change |
| H+5 | `09 Set-DomainDnsRecords` — MX/SPF/DKIM/autodiscover at the provider | — |
| H+6 | `08 Copy-MailConfig -Mode Import` incl. apply-after-09 items | — |
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
| T-1 | "Old environment goes quiet <time>. Leave your old PC on." |
| T+0 | "Use the new PC. New Outlook profile builds itself. Everything's still there." |
| T+1/T+7 | "Report anything missing; here's the known-issues list." |
