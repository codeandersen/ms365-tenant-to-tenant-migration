# Risk register

Adapted in structure from the Mezba toolkit's risk format. Score = probability x impact (1–5).

| # | Risk | P | I | Score | Mitigation | Owner |
|---|---|---|---|---|---|---|
| R1 | A mailbox on any hold silently fails its move — the batch reports it late | 3 | 4 | 12 | `Get-HoldReport` at T-28 and again at T-7; legal decision documented before batches start | `<name>` |
| R2 | Batch validation expires (>7 days) on cutover day | 3 | 3 | 9 | `Start-BatchMigration` refuses stale validation; revalidate T-2 | `<name>` |
| R3 | Domain removal from source blocked by an undiscovered object (MailUsers, deleted users, app URIs, ProxyOnly) | 3 | 4 | 12 | `Remove-SourceDomain -SnapshotOnly` + `Test-CutoverReadiness` in the pilot; recycle-bin pass | `<name>` |
| R4 | UPN/domain order for Orchestrator is undocumented (playbook hypothesis) | 3 | 4 | 12 | Pilot proves the order on test tenants; open question with Microsoft (`Questions-For-Microsoft.md`) | `<name>` |
| R5 | OneDrive redirect breaks after UPN change | 2 | 4 | 8 | Pilot item; Microsoft question open; keep source MailUsers until verified | `<name>` |
| R6 | External meeting guests can't join (old invite/organiser identity) | 3 | 2 | 6 | Pilot determines the real behaviour; comms pre-warn organisers to re-send | `<name>` |
| R7 | Teams channels/structure incomplete after SharePoint move | 3 | 3 | 9 | Track decision per site in `Get-SiteMigrationPlan`; channel recreation resourced | `<name>` |
| R8 | PC hardware late / Autopilot enrolment fails at scale | 2 | 4 | 8 | Order early; enrol a pilot batch of PCs first; ESP configured | `<name>` |
| R9 | Entra device deleted before wipe → escrowed BitLocker key lost | 2 | 4 | 8 | Fixed retirement order; `Get-BitLockerKeyReport` before any deletion | `<name>` |
| R10 | SharePoint 4,000-queue saturation stalls site/OneDrive moves | 2 | 3 | 6 | `Start-SiteContentMoves -MaxConcurrent`; stagger waves | `<name>` |
| R11 | Mail loops between tenants while domains are in transit | 2 | 3 | 6 | Keep source MailUsers + targetAddress until the domain fully moves; Test-TargetTenant `-CheckSource` | `<name>` |
| R12 | Tenant closes with a hold still in place → data destruction | 1 | 5 | 5 | Decommission gate G16: retention decision is a documented business sign-off | `<name>` |
| R13 | EA licence gate: cross-tenant licences unavailable to the customer's agreement | 2 | 5 | 10 | Confirm procurement at T-21 (gate G3) before building the plan on Orchestrator | `<name>` |
| R14 | A `-WhatIf` was skipped and a change ran blind | 1 | 4 | 4 | Convention: `-WhatIf` first, always; per-object backups in 09 abort the run if they fail | `<name>` |
| R15 | CTIM `-Overwrite` used without a downloaded mapping → unrecoverable | 1 | 5 | 5 | `Invoke-CtimMapping` forces the download to `customers/` before accepting `-Overwrite` | `<name>` |
