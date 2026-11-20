# 05 — Batches

**Purpose.** Turn the verified, licensed users into Orchestrator migration batches, keep
validation fresh, and run the cutover. Everything here is **target-tenant Graph**
(`CrossTenantContentMigration.ReadWrite.All`) — the source tenant cannot run migration
commands.

## Lifecycle (documented)

1. **Create** — `New-MigrationBatches.ps1` (validation starts automatically; users feel no
   impact). Submit ~T-14 before `CompleteAfterDateTimeUtc`.
2. **Monitor / fix / revalidate** — `Get-BatchStatus.ps1`, `Test-MigrationBatch.ps1`.
   `ValidateFailed` → fix the per-user errors → revalidate the SAME batch → repeat until
   `ValidatePassed`.
3. **Migrate** — `Start-BatchMigration.ps1` — only from `ValidatePassed` with validation ≤7
   days old, or as retry from `CompletedWithErrors`/`Failed`.
4. **Changes before cutover** — `Update-BatchCutover.ps1` (any time before the date passes),
   `Stop-BatchUser.ps1 -UserUpn` (single user out), `Stop-BatchUser.ps1 -WholeBatch`
   (cancel all). Nothing is cancellable once a user's cutover has started.

## Batch status table (abridged — full table on Learn)

| Status | Meaning | Validate? | Migrate? | Cancel? |
|--------|---------|-----------|----------|---------|
| Submitted | Created, awaiting validation | Yes | No | Yes |
| ValidateInProgress | Prereq checks running | No | No | Yes |
| ValidatePassed | All checks passed — ready | No | **Yes** | Yes |
| ValidateFailed | Fix per-user errors, revalidate | Yes | No | Yes |
| InProgress | Syncing / migrating | No | No | Yes |
| CuttingOver | Cutover running | No | No | **No** |
| Completed | Done | No | No | No |
| CompletedWithErrors | Some users had errors — retryable | No | **Yes (retry)** | No |
| Failed | Failed — retryable | No | **Yes (retry)** | No |
| Canceled | Canceled | No | No | No |

Per-user workload statuses: `NotStarted → InProgress → Valid|Invalid → Syncing → Synced →
Finalizing → Completed | Failed | Canceled` (Exchange adds `Finalizing`; Teams chats report
against 80 % message / 90 % thread success thresholds).

## Key rules enforced by the scripts

- Max 100 users per batch; unique batch names; a user in one active batch.
- `CompleteAfterDateTimeUtc` must be in the future at creation/update.
- Validation freshness: `Test-MigrationBatch.ps1` stamps `ValidatePassed` into
  `customers/<name>/output/05-Batches/*/validation-log.csv`; `Start-BatchMigration.ps1`
  prefers a validation timestamp on the job object when the model exposes one and falls
  back to that log (see script notes).
- Workloads per batch: `Exchange;ODSP;Teams;Meeting` recommended; `Meeting` needs
  `Teams` + `Exchange`.

## Troubleshooting: a mailbox stuck after CompleteAfterDateTime

If one user's mailbox migration seems stalled well past `CompleteAfterDateTime` (typically
24 h+, or much longer than the rest of the batch), a Data Consistency Score (DCS) hold may
be pausing it — the Orchestrator just waits. Check in Exchange Online PowerShell:

```powershell
Get-MigrationUser -Identity user@fabrikam.com | Select BatchId, Status, DataConsistencyScore
```

- `Investigate` — the admin may approve it: `Set-MigrationUser <upn> -ApproveSkippedItems`;
  review skipped items afterwards via `Get-MigrationUserStatistics -IncludeSkippedItems`.
- `Poor` — do **not** approve; open a Microsoft Support case with the batch ID.

[Learn](.../migration-orchestrator-8-faq)

## Moving a user back (rollback)

The FAQ documents a supported move-back: mailbox + OneDrive can be returned to the source
tenant with the standalone cross-tenant mailbox/OneDrive tools, configured in the reverse
direction — no identity mapping needed. Teams meetings are **not** recreated by the
move-back and must be rebuilt manually; chat history still lives in the source tenant.
[Learn](.../migration-orchestrator-8-faq)

## Files

- `New-MigrationBatches.ps1`, `Test-MigrationBatch.ps1`, `Get-BatchStatus.ps1` (read-only),
  `Update-BatchCutover.ps1`, `Start-BatchMigration.ps1`, `Stop-BatchUser.ps1`.

> Untested against live tenants — validate in technical test/pilot.
> Source: https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-5-running-migration
