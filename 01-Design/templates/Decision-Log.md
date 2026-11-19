# Decision log

One row per decision that shapes the migration. Keep it with the design review;
copy it into `customers/<name>/input/` and fill the Decision column per project.

| # | Question | Options | Decision | Decided by / date | Notes |
|---|----------|---------|----------|-------------------|-------|
| 1 | How are users grouped into batches? | Per wave, ≤100 users each (Orchestrator max). One user in one active batch. | | | Batch column in migration-users.csv. |
| 2 | When is cutover? | CompleteAfterDateTime per batch; weekend evenings recommended; submit batches ~T-14. | | | Revalidate if validation is older than 7 days. |
| 3 | Initial addressing model? | Target objects get `fabrikam.onmicrosoft.com` addresses; the vanity domain and UPN change are separate (phase 09). | | | Hypothesis — verify in pilot that data-first with onmicrosoft addressing is acceptable. |
| 4 | Which workloads per batch? | Exchange, ODSP, Teams, Meeting. Microsoft recommends all workloads in the same batch; Meeting requires Teams + Exchange. | | | |
| 5 | How are mailboxes on hold handled? | Holds block moves. Identify in assessment; deal with in phase 06 before licensing/batching. | | | [Documented] mailboxes on any hold are not migrated. |
| 6 | Shared/resource mailboxes? | Not part of user batches; handled in phase 06. | | | |
| 7 | SharePoint content approach? | Orchestrator covers OneDrive (ODSP workload); site collections need a separate tool decision. | | | Open — see 07-SharePoint-Teams when added. |
| 8 | Device strategy? | **NewDevices** - users get new PCs registered in the target's Autopilot (vendor/reseller uploads hashes; old PCs retired per phase 10) — OR **ExistingDevices** - current PCs must move (Entra-joined devices can belong to one tenant only; source Autopilot registrations must be deregistered first; method is an open decision - native reset/re-enrol vs third-party/in-place rejoin; not scripted) — OR **Unknown** - decide before migration. | NewDevices | | |
| 9 | How are shared-mailbox permissions handled? | Recreate Send As / Full Access in phase 06. | | | |
| 10 | Who signs in where? | Source admin for CTIM copy + scope group; target admin for everything else (MailUsers, accept/map/write, batches). | | | |
