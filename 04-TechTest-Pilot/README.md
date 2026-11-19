# 04 — Technical test & pilot

**Purpose.** Prove the migration end-to-end on a handful of users before the real waves,
and pin down every behaviour the docs leave open. Nothing scales until this phase is green.

## Two runs

1. **Technical test** — 2–5 throwaway users (test accounts in both tenants, e.g.
   `ttest1@contoso.com` → `ttest1@fabrikam.onmicrosoft.com`). Run the full backbone:
   prep → MailUsers → scope group → CTIM → verify → license → batch → cutover → validate.
   Goal: the mechanics work and the runbook timings are real.
2. **Pilot** — a small group of friendly real users in one production batch. Same path.
   Goal: the user experience and the open questions in `Pilot-Test-Checklist.md` are answered
   by observation, not assumption.

## Rules for this phase

- Every item on the checklist is tagged **[Documented]** (with a Learn link — still confirm
  it behaves as written) or **[Hypothesis - test]** (assumption — must be observed).
- Record outcomes in the checklist copy under `customers/<name>/` — the repo copy stays generic.
- If a documented item behaves differently, that is a finding — stop and update the runbook.
- A pilot user is just a batch of one; keep them in a `pilot` batch in migration-users.csv.

## Entry criteria

- 02-TenantPrep complete in both tenants (all Pass on `Test-OrchestratorPrereqs.ps1`)
- Test/pilot rows in `customers/<name>/migration-users.csv`
- `CompleteAfterDateTimeUtc` a real cutover slot you can staff

## Exit criteria

- Pilot users migrated `Completed` (or `CompletedWithErrors` with understood errors)
- Every checklist item has an observed answer
- Timings recorded: prep→copy→accept→map→write→sync→cutover duration per phase
