# Estimate template

Generic effort template — fill the placeholders per engagement. No customer figures here.

## Inputs that drive the estimate

| Input | Value | Why it matters |
|---|---|---|
| Users to migrate | `<count>` | Batches (≤100 each), licence count, per-user validation |
| Shared/room/equipment mailboxes | `<count>` | Phase 06 MRS path runs outside Orchestrator |
| Mailboxes on hold | `<count>` | Legal process — can block the whole wave |
| Total mail volume | `<size GB>` | Sync duration vs CompleteAfterDateTime |
| SharePoint sites / data | `<count>` / `<size>` | Native vs third-party track; 4,000-queue |
| Teams in scope | `<count>` | Structure recreation is manual |
| Devices (new PCs) | `<count>` | Procurement lead time + Autopilot setup |
| Domains moving | `<count>` | Cutover complexity, DNS work per domain |
| Waves | `<count>` | Everything per-wave repeats |

## Effort (person-days — placeholders)

| Phase | Activity | Estimate |
|---|---|---|
| Assessment | Inventory + review + design workshop | `<x>` |
| Tenant prep | Both tenants, apps/consents, licences, trust | `<x>` |
| Identities | MailUsers, CTIM, verification, licensing | `<x>` per `<100>` users |
| Pilot | Test-tenant pair + checklist + fixes | `<x>` |
| Shared mailboxes & holds | Export, MailUsers, batches, hold decisions | `<x>` |
| SharePoint/Teams | Plan, groups, content moves, channel recreation | `<x>` |
| Mail config | Export/import, transport rules, post-cutover items | `<x>` |
| Cutover weekend | Domain move, addresses, DNS, block sign-in | `<x>` (expect long days) |
| Devices | Autopilot/Intune setup + rollout support | `<x>` |
| Validation | Scripted + user-acceptance rounds | `<x>` per wave |
| Decommission | Readiness, artifact cleanup, closure | `<x>` |
| PM & comms | Planning, comms, help-desk brief | `<x>` |

## Cost items beyond labour

- Microsoft licences: user licences (both tenants during migration), Cross-Tenant User Data
  Migration (EA-gated), SharePoint cross-tenant licences.
- Third-party migration tooling (if the ShareGate track is chosen).
- New PC hardware + Autopilot enrolment effort.
- Contingency: `<percent>%` recommended — holds, DNS delays and Teams gaps are the usual causes.
