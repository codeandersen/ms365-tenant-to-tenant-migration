# Lessons learnt

Adapted in structure from the Mezba toolkit's lessons document. Fill the template after every
wave; the generic lessons below are starting points, not findings from any single customer.

## Template (per wave or per project)

| # | What happened | What we expected | What we changed | Where it lives now |
|---|---|---|---|---|
| L<n> | `<event>` | `<expectation>` | `<fix>` | `<script/doc>` |

## Generic lessons (validate against your own results)

- **Holds are the silent killer.** Every migration tooling generation repeats it: a held mailbox
  doesn't migrate, and the failure surfaces late. Run the hold report early and get the legal
  decision in writing.
- **The technical pilot is not optional.** Half of this playbook's design is labelled hypothesis
  precisely because Microsoft doesn't document it (domain/UPN order, meeting-link behaviour,
  OneDrive redirects). The pilot is where assumptions die cheaply.
- **Session hygiene matters.** CTIM fails when an Exchange session is open in the same window;
  EXO can't hold two tenant sessions. Fresh windows per step, always — the scripts enforce it.
- **Backups before changes beat rollbacks after.** Every phase-09 change writes a per-object
  backup first, and the scripts abort if the backup fails — the one time it caught a real
  failure, it paid for itself.
- **100 users per batch is a hard ceiling** — size waves so no batch needs a same-day
  dependency on another.
- **Start sync at least two weeks before `CompleteAfterDateTime`** — last-minute batches are
  the classic reason cutover weekends start late.
- **DNS TTLs down a week early** or you watch propagation instead of testing.
- **Write the user comms before the pilot**, not the night before cutover — the pilot's
  surprises are exactly what the comms need to answer.
