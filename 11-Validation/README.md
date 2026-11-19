# 11 - Validation

Signs off a migration wave: `Test-TargetTenant.ps1` (read-only) checks every user in the 01-Design
list against the expected post-migration state and writes a Pass/Warn/Fail CSV.

## What it checks

**Per user**

- **Mailbox** - the target recipient exists and is `UserMailbox` (shared/room/equipment go via
  phase 06 and are flagged, not failed silently).
- **Licence** - a licence covering Exchange and Teams is assigned. The match is a SkuPartNumber
  heuristic - verify service plans for unusual SKUs.
- **OneDrive** - a personal site exists whose owner is the target UPN (same owner-match approach
  as `Test-TargetOneDriveAbsent`, but *Found* is now expected).
- **Workloads** - every workload status for the user in their batch job reads
  `Completed`/`CompletedWithErrors`, read via `Get-MgBetaCrossTenantMigrationJobUser` +
  `Get-GraphValue`.
- **TeamsChat** - the job user's Teams/chat status when the API exposes it.

**Tenant level** (`-FinalDomain`, DNS only - `Resolve-DnsName`, no tenant access): MX points at
`*mail.protection.outlook.com`, `autodiscover` CNAMEs to `autodiscover.outlook.com`, a `v=spf1`
TXT record exists (check it mentions the target tenant by hand).

**Optional source pass** (`-CheckSource -SourceTenantId -SourceAdminUpn`): each source MailUser
still carries a `targetAddress` toward the target - needed for mail routing while the domain is
in transit.

## Validation checklist (wave sign-off)

Scripted: `Test-TargetTenant.ps1` green per user - plus, for shared/room/equipment mailboxes from
phase 06, mailbox type converted back and item counts reviewed in the migration batch report.

Manual (user acceptance, from `04-TechTest-Pilot/Pilot-Test-Checklist.md`):

- Sign-in + MFA works on the new PC.
- Outlook builds a new profile; recent and old mail searchable; shared mailboxes open.
- OneDrive syncs and KFM folders are present.
- Teams: chats/history, meetings join; **modified series occurrences and external invites may need
  re-sending** (pilot findings apply).
- Send As / Send on Behalf / Full Access on shared mailboxes (phase 06 note: Send As must be
  pilot-tested).
- Mail flow in and out to the final domain after DNS cutover.

Read every Warn and Fail and decide with the business owner before marking the wave done.
