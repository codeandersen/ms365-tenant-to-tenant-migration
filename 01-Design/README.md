# 01 — Design

**Purpose.** Turn the assessment numbers into the decisions that the scripts in phases
02–05 assume are already made. Nothing in this phase touches a tenant.

## What you decide here

| Decision | Default in this playbook | Where it lands |
|----------|--------------------------|----------------|
| Waves/batches | ≤100 users per batch (documented maximum); a user may be in one active batch only | `Batch` column in `templates/migration-users.csv` |
| Cutover timing | `CompleteAfterDateTime` per batch; submit ~T-14, revalidate when validation is >7 days old | `CompleteAfterDateTimeUtc` column |
| Addressing model | Data first with `fabrikam.onmicrosoft.com` addressing; the vanity domain and UPN change happen later (phase 09) — see pilot checklist | `TargetUpn`/`TargetPrimarySmtp` |
| Workloads per batch | `Exchange;ODSP;Teams;Meeting` — Microsoft recommends all workloads in the same batch; `Meeting` requires `Teams` + `Exchange` | `Workloads` column |
| Holds | Mailboxes on any hold are not migrated — find them in 00-Assessment, resolve in 06 | Decision log |
| Shared/resource mailboxes | Not in user batches — phase 06 | Decision log |
| SharePoint sites | Not covered by the Orchestrator — separate tool decision, open | Decision log |
| Devices | No in-place device move; new PCs enrol in the target via Autopilot/Intune | Decision log |

## Files

- `templates/migration-users.csv` — **the one canonical user list**. Every script that
  works on users reads this shape via `Import-MigrationUserList` (tools/Orchestrator.psm1).
  Copy it to `customers/<name>/migration-users.csv` and fill it in there — the template
  in the repo stays Contoso/Fabrikam sample data.
- `templates/Decision-Log.md` — copy to `customers/<name>/` and fill the Decision column.
- `templates/CTIM-Mapping-CSV.md` — schema notes for the CTIM mapping file.

## Columns in migration-users.csv

`SourceUpn, SourcePrimarySmtp, DisplayName, FirstName, LastName, TargetUpn,
TargetPrimarySmtp, UsageLocation, TargetLicenseSku, Batch, CompleteAfterDateTimeUtc, Workloads`

- `TargetUpn`/`TargetPrimarySmtp` use `fabrikam.onmicrosoft.com` — accepted-domain and
  non-accepted-domain rules make a source-domain primary address impossible anyway.
- `UsageLocation` is required by `Set-MgUserLicense` before a license can be assigned.
- `TargetLicenseSku` is a SkuPartNumber (e.g. `SPE_E5`) resolved at assign time.
- `CompleteAfterDateTimeUtc` is ISO 8601 UTC (`2026-09-05T22:00:00Z`).
- `Workloads` is `;`-delimited from `Exchange, ODSP, Teams, Meeting`.

## Personal data

The real user list contains personal data. Fill it in under `customers/<name>/`
(gitignored), never in `templates/` and never commit it.
