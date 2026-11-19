# 12 - Decommission

Shuts the migration down cleanly and prepares the source tenant for closure.

## Retention before tenant deletion (read this first)

Mailboxes and data under **Litigation Hold, retention policies or eDiscovery case holds stay in
the source tenant** until their owners decide otherwise. Closing the tenant deletes them -
permanently. Before any licence removal or tenant closure:

1. Re-run `06-SharedMailboxes-Holds/Get-HoldReport.ps1` and this phase's
   `Get-DecommissionReadiness.ps1` - every WARN is a business decision, not a script fix.
2. Preserve/export the content per the legal/compliance decision (eDiscovery export is the
   documented route; the hold-release cmdlets are reference only - see the phase 06 README).
3. Only then remove licences / close.

**Source MailUsers**: migrated users remain in the source as MailUsers `[Learn]` - keep them until
the domain move finishes (they carry mail routing via targetAddress), then remove or keep per
business decision.

**Licence step-down** `[Playbook advice]`: remove Cross-Tenant User Data Migration licences first
(they're only needed during migration), then user licences at ~T+30 once exports and the OneDrive
decision are done - unlicensed OneDrives start their retention timer when the licence goes.

## Cleanup order (`Remove-MigrationArtifacts.ps1`)

Implements the Learn post-migration page exactly; every step needs all batches in a terminal
state (`Completed`, `CompletedWithErrors`, `Failed`, `Canceled`, `Deleted`, `PendingDelete`),
exports what it removes first, supports `-WhatIf`, and asks for confirmation
(`ConfirmImpact = High`). Target-side non-CTIM steps check the batch state themselves;
**every `-Role Source` run and the session-free CTIM steps can't**, so they require
`-AllBatchesTerminalConfirmed` — pass it only after verifying all batches are terminal
(`-Role Target` run or `05-Batches/Get-BatchStatus.ps1` in the target tenant).

| Step | Side | What it removes `[Learn]` |
|---|---|---|
| `BatchData` | target | `Remove-MgBetaCrossTenantMigrationJob` per batch - deletes batch data within 30 days; destructive, run only when ALL migrations are done |
| `CtimData` | both | `Remove-CtimData -SourceTenantGuid` (target) / `-TargetTenantGuid` (source). **Fresh session** - refuses while Graph/EXO is connected |
| `CtimServicePrincipal` | both | `Remove-CtimServicePrincipal` |
| `OrgRelationship` | both | `Remove-OrganizationRelationship` (exported first) |
| `MigrationEndpoint` | target | `Remove-MigrationEndpoint` (exported first) |
| `CtmsAppPermissions` | target | `Revoke-CTMSAppPermissions` (NuGet module) + the doc's CTMS/Identity-Mapping first-party SP cleanup |

### Documented but NOT scripted (manual steps)

- **OneDrive trust removal** `[Learn -> OneDrive doc Step 7]`: the installed
  `Set-SPOCrossTenantRelationship` has no `-Enabled`/remove parameter, so no verifiable removal
  cmdlet exists here - follow Step 7 of the cross-tenant OneDrive documentation manually.
- **Teams Meetings app + Mailbox app permissions**: removed in the Microsoft 365 admin centre.
- **Source user cleanup** (the MailUsers above): a business decision, done in the admin centre or
  your own tooling.

## Scripts

| Script | What it does |
|---|---|
| `Get-DecommissionReadiness.ps1` | Read-only WARN/PASS/INFO report: sign-ins still enabled, licences + renewal dates, holds, mailboxes, mail flow, OneDrives, leftover domains |
| `Remove-MigrationArtifacts.ps1` | The cleanup above, step by step, with backups and a terminal-state guard |

## Final tenant closure `[Playbook advice]`

Only after: retention decided (above), `Get-DecommissionReadiness` clean of actionable WARNs,
domains removed, DNS/email references gone for the full mail-flow window, devices retired, and
the business owner signs off. Then remove subscriptions and let the tenant lapse - Microsoft
handles tenant deletion after all subscriptions end.
