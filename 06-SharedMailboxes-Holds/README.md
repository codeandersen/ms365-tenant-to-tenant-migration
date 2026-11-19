# 06 - Shared mailboxes, resource mailboxes, and holds

The Migration Orchestrator moves **users** (Exchange mailbox, OneDrive, Teams chats/meetings). It
does not move **shared, room and equipment mailboxes**, and it does not move anything on hold:
"mailboxes on any type of hold aren't migrated, and a move for those mailboxes is blocked"
([Orchestrator user prep](https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-4-user-prep)).

## Shared/resource mailboxes: the path

They go via the **standard cross-tenant mailbox migration (MRS)** - the same documented feature
phase 02's migration endpoint is for
([cross-tenant mailbox migration](https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-mailbox-migration)).
CTIM is not documented for stamping these objects, so the documented manual stamping is used here:

1. **Export** (source, read-only):
   `Export-SourceMailboxAttributes.ps1` → `SourceMailboxAttributes.csv` (ExchangeGuid, ArchiveGuid,
   LegacyExchangeDN, x500s, size, hold flags).
2. **Target MailUsers** (target, `-WhatIf`):
   `New-SharedMailboxMailUsers.ps1` - *this is the one place stamping ExchangeGuid/ArchiveGuid/x500
   is correct* (unlike `03-Identities/New-TargetMailUsers.ps1`, where CTIM owns those attributes).
   Input: the export CSV + a mapping CSV (`SourcePrimarySmtp,TargetPrimarySmtp,Name`, optional
   `FinalPrimarySmtp` for the post-domain-move primary address). Refuses
   non-accepted target domains and identities that are already mailboxes.
3. **Batch** (target, `-WhatIf`):
   `New-CrossTenantMailboxBatch.ps1` - builds the `EmailAddress`-column CSV and runs the documented
   `New-MigrationBatch -Name -SourceEndpoint -CSVData -TargetDeliveryDomain [-Autostart] [-CompleteAfter]`.
   **Rows flagged with any hold are refused.**

Facts checked against the doc:

- Per-object **Cross-Tenant User Data Migration** licence (one-time fee, source or target object) is
  required for cross-tenant mailbox moves; the doc doesn't exempt shared mailboxes - treat it as
  required per object until the pilot proves otherwise.
- "Do shared mailboxes move and still work? Yes" - and store permissions survive per
  "Manage permissions for recipients in Exchange Online".
- `MailUser -> Mailbox` conversion is automatic; **conversion back to Shared/Room/Equipment type
  after the move is not described in the doc** - verify in the pilot
  (`Set-Mailbox -Type Shared|Room|Equipment` is the known mechanism) - **[pilot item]**.
- The licence note "don't license the target before the ExchangeGuid is stamped" applies here too:
  license *after* `New-SharedMailboxMailUsers.ps1` has stamped, or the target gets a stray mailbox.
  Shared mailboxes need no Exchange licence themselves but the CT-UDM licence is still required.

## Holds: process, not a script

`Get-HoldReport.ps1` (read-only) reports, per mailbox: LitigationHoldEnabled, RetentionHoldEnabled,
ComplianceTagHoldApplied, DelayHoldApplied, DelayReleaseHoldApplied, and InPlaceHolds **decoded**
(`UniH` = eDiscovery/retention, `mbx` = mailbox search, `skp` = Teams/Skype, `grp` = M365 group,
`cld` = cloud location, `exa` = eDiscovery; unknown = reported). With Security & Compliance
PowerShell (`Connect-MigrationCompliance` in Common) it also lists Purview retention policies and
eDiscovery case hold policies that may cover Exchange locations.

There is deliberately **no hold-removal script**: releasing a hold is a legal/compliance decision.
The documented process (see [eDiscovery holds](https://learn.microsoft.com/en-us/purview/ediscovery-create-holds)
and [retention](https://learn.microsoft.com/en-us/purview/retention)):

1. Preserve the data first (eDiscovery export / content search export) if legal requires it.
2. Legal signs off on releasing the hold; compliance removes the mailbox from the case hold policy
   or retention policy (`Set-CaseHoldPolicy`, `Set-RetentionCompliancePolicy` locations, or
   `Set-Mailbox -LitigationHoldEnabled $false` / `-RemoveDelayHoldApplied` / `-RemoveDelayReleaseHoldApplied`
   where documented).
3. `DelayHoldApplied`/`DelayReleaseHoldApplied` = a hold was recently removed; Exchange keeps a
   residual delay hold - check again before batching.

## Permissions

`Export-MailboxPermissions.ps1` (source, RO) → `Set-TargetMailboxPermissions.ps1` (target, `-WhatIf`).
Trustees map only through the 01 user list + shared mapping; unmapped are reported, never guessed.
**Pilot item:** Send As on shared mailboxes post-move.

## Order

`Export-SourceMailboxAttributes` → `Get-HoldReport` → resolve holds legally →
`New-SharedMailboxMailUsers` → licences (CT-UDM on each object) → `New-CrossTenantMailboxBatch` →
monitor `Get-MigrationBatch` → `Export-MailboxPermissions` (before source decom) +
`Set-TargetMailboxPermissions`.
