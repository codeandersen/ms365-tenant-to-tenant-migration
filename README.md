# ms365-tenant-to-tenant-migration

A public PowerShell playbook for Microsoft 365 tenant-to-tenant (T2T) migration
using **Microsoft Migration Orchestrator** — the Graph `CrossTenantMigration`
jobs — together with **Cross-Tenant Identity Mapping (CTIM)** for identity
mapping. Targeted at cloud-only tenants (no on-premises Active Directory
dependency to unwind).

Official docs: [Migration Orchestrator overview (Microsoft Learn)](https://learn.microsoft.com/microsoft-365/migration/migration-orchestrator-1-overview).

**Start at [`docs/Runbook.md`](docs/Runbook.md)** — the canonical T-30 → T+30 timeline
with go/no-go gates. Background material lives in [`docs/`](docs/) — including
[`docs/Migration-Method-Guide.md`](docs/Migration-Method-Guide.md) (which tool
moves which workload), [`docs/What-Doesnt-Move.md`](docs/What-Doesnt-Move.md)
and [`docs/After-Cutover-User-Guide.md`](docs/After-Cutover-User-Guide.md).

## Read this first

- **These scripts have not been run against a live tenant.** Treat every one
  as untested: validate them in a tech test / pilot tenant pair before any
  production use.
- Scripts that change a tenant support `-WhatIf`; run with `-WhatIf` first.
- **Nothing here may run against a real customer tenant from this repo.**
  Customer data lives under `customers/<name>/` (gitignored) — see
  `customers/README.md`.
- All examples use `contoso.com` (source) and `fabrikam.com` (target),
  `contoso.onmicrosoft.com` / `fabrikam.onmicrosoft.com`.

## The backbone order

1. **Tenant prep (both tenants):** organization relationship, migration
   endpoint, mail-enabled security group for the migration, app registration +
   admin consent, **Cross-Tenant User Data Migration** licences in target,
   SharePoint/OneDrive cross-tenant trust.
2. **Target MailUsers:** create one MailUser per source user — **no licence**,
   and OneDrive/site creation must stay blocked.
3. **CTIM (identity mapping):** `New-CtimCopyRequest` (source) →
   `Accept-CtimCopyRequest` (target) → `New-CtimMapRequest` → `Get-CtimReport`.
4. **Verify:** target MailUser carries the source `ExchangeGuid` and the X500
   proxy addresses **before** licensing.
5. **Licence** the target users (Exchange Online + Teams).
6. **Batches:** max ~100 users per migration job, created around T-14 days
   before cutover; revalidate if the validation is more than 7 days old.
7. **Cutover** via `CompleteAfterDateTime`.
8. **Validation** of mail, OneDrive, Teams chats/meetings.
9. **Decommission** the source tenant artefacts.

## Phases

| Phase                   | Purpose                                                          | Changes a tenant? |
| ----------------------- | ---------------------------------------------------------------- | ----------------- |
| `00-Assessment`         | Read-only tenant inventory + review report                       | No                |
| `01-Design`             | Mapping/batch design templates                                   | No                |
| `02-TenantPrep`         | Org relationship, migration endpoint, app/consent, licences, SPO trust | Yes (both)  |
| `03-Identities`         | Target MailUsers + CTIM identity mapping + ExchangeGuid/X500 verification | Yes (both) |
| `04-TechTest-Pilot`     | Pilot batch against a test tenant pair                           | Yes (test tenants)|
| `05-Batches`            | Create Orchestrator migration jobs (≤100 users each)             | Yes (target)      |
| `06-SharedMailboxes-Holds` | Shared/resource mailboxes and legal holds (outside Orchestrator scope) | Yes      |
| `07-SharePoint-Teams`   | SharePoint sites / Teams structures (outside Orchestrator scope) | Yes (both)        |
| `08-MailConfig`         | Connectors, transport rules, DKIM, mail-flow recreation          | Yes (target)      |
| `09-DomainCutover`      | Domain move + DNS (MX/SPF/DKIM/autodiscover)                     | Yes (both)        |
| `10-Devices`            | New PCs enrolled directly in target via Autopilot/Intune — no in-place device move | Yes (target) |
| `11-Validation`         | Post-cutover validation                                          | No                |
| `12-Decommission`       | Migration-artifact cleanup + source readiness report             | Yes (both)        |
| `tools/`                | Shared module, module health check, report reader                | No                |
| `docs/`                 | Runbook, what-doesn't-move, user guide, templates and registers  | No                |
| `customers/`            | Local per-customer working folders — **gitignored**              | n/a               |
| `tests/`                | Parse check, PSScriptAnalyzer, Pester tests, customer-data leak guard | No           |

## Conventions

- Tenant-changing scripts take `-WhatIf` and assert the connected tenant
  (`Assert-TenantContext` in `tools/Common.psm1`) before touching anything.
- All CSV output goes through `Export-CsvSafe` (UTF-8 with BOM so Excel opens
  æøå correctly).
- Never commit inventory, mapping CSVs, or anything under `customers/<name>/`.
  `tests/Test-NoCustomerData.ps1` enforces this via `customers/.denylist`.

## Attribution

This playbook was inspired by
[Mezba Uddin](https://www.linkedin.com/in/mezbauddin/) and his
[mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit](https://github.com/mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit).

Several scripts across the phases (03, 06, 08, 09, 10, 11, 12) are adapted from Mezba Uddin's
[M365_Tenant_to_Tenant_Migration_Toolkit](https://github.com/mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit)
(MIT). See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for the per-file list.
