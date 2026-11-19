# Pilot test checklist

Tag legend: **[Documented]** = stated on Microsoft Learn (link included; confirm it behaves
as written). **[Hypothesis - test]** = assumption — must be observed in the technical test or
pilot before go-live. Fill the Result column per run.

| # | Scenario / assertion | Tag | How to test | Result (observed) |
|---|----------------------|-----|-------------|-------------------|
| 1 | Batches auto-validate on creation; migrate only when `ValidatePassed` and validation ≤ 7 days old | [Documented] — Running the migration | Create a batch, watch status; note the validation age at migrate time | |
| 2 | Max 100 users per batch; a user in one active batch only | [Documented] | Try adding a pilot user to a second batch | |
| 3 | Mailboxes on any hold are not migrated — move blocked | [Documented] — Cross-tenant mailbox migration | Put a test mailbox on hold, validate a batch containing it | |
| 4 | Licensed-before-CTIM target user fails (mailbox provisioned instead of MailUser) | [Documented] — User prep | Deliberately license one throwaway user early; observe failure | |
| 5 | CTIM stamps ExchangeGuid/ArchiveGuid/x500/EmailAddresses — we set none | [Documented] — CTIM | Verify with `Test-IdentityMapping.ps1 -Mode Verify` | |
| 6 | External meeting attendees receive a new invite for migrated Teams meetings | [Hypothesis - test] | External attendee in a migrated meeting — what do they receive? | |
| 7 | A meeting series with one modified occurrence keeps the old link; the series must be re-sent | [Hypothesis - test] | Create such a series before cutover; check post-migration | |
| 8 | Outlook cannot connect to the target mailbox before cutover; a new Outlook profile is needed after | [Hypothesis - test] | Try target sign-in in Outlook before/after cutover | |
| 9 | Target sign-in + MFA registration pre-cutover works, but does not create OneDrive/Teams state | [Hypothesis - test] | Pilot user signs into target early; confirm no personal site via `Test-TargetOneDriveAbsent.ps1` | |
| 10 | UPN change on a brand-new target PC — sign-in with the new UPN works on first enrolment | [Hypothesis - test] | Enrol a new Autopilot device in the target with the new UPN | |
| 11 | Order: migrate data with onmicrosoft addressing first, then move the vanity domain + UPN change in the same cutover weekend | [Hypothesis - test] | Execute the order on pilot users; note any mail-routing gaps | |
| 12 | OneDrive redirect from the source URL works after the migration (existing links keep working) | [Documented]/[Hypothesis - test] | Open pre-migration shared links to source OneDrive files | |
| 13 | AADSTS50020-style errors / stale cached identities on the client; Office account reset clears them | [Hypothesis - test] | On a used Windows profile, sign in as the target user; try Office "reset"/clearing credentials | |
| 14 | Send As / Full Access on shared mailboxes work after recreation (phase 06) | [Hypothesis - test] | Reproduce a shared-mailbox permission and send from it | |
| 15 | Teams chats and meetings land usable in the target (chat history present, meetings joinable) | [Documented]/[Hypothesis - test] | Check a pilot user's chats + meetings post-migration | |
| 16 | `Test-MgBetaCrossTenantMigrationJob` revalidation allowed when `Submitted`/`ValidateFailed` | [Documented] — status table | Revalidate a failed batch after fixing the cause | |
| 17 | Retry allowed on `CompletedWithErrors` / `Failed` | [Documented] — status table | Retry a batch that ended in either state | |
| 18 | Users feel no impact during sync; impact starts at CompleteAfterDateTime | [Documented] | Pilot user keeps working during pre-cutover sync | |
| 19 | Scope-group membership changes take up to ~1 hour to be processed | [Documented] | Add a user to the scope group and validate immediately vs. later | |
| 20 | CTIM must run in a session-free window (loopback redirect-URI error otherwise) | [Documented] — CTIM troubleshooting | Run a CTIM step in a window with an active EXO session; confirm refusal/error | |
| 21 | A mapped guest keeps access to a shared OneDrive folder after migration (SPO identity map) | [Hypothesis - test] | Share a folder with a source guest pre-move; open as the guest post-move | |
| 22 | Group-granted access to a OneDrive/SharePoint folder survives via the group map | [Hypothesis - test] | Give a source group folder access; verify a member post-move | |
| 23 | Folder/item-level unique permissions survive for internal users **and** guests | [Hypothesis - test] | Unique ACLs on one folder + one file, internal + guest; verify post-move | |
| 24 | "Anyone" links created pre-migration still work (or fail as documented) | [Hypothesis - test] — docs unclear | Open an Anyone link to a migrated file post-move | |
| 25 | SPO map M365-group row: column 1 is `Group` not `User` (Learn image/table discrepancy) | [Hypothesis - test] | Upload a map with an O365Group row; confirm the row is accepted/effective | |
| 26 | Guest invited without invitation mail redeems on first access to a shared resource | [Hypothesis - test] | Invite a pilot guest without `-SendInvitationMessage`; share a file; observe redemption | |
| 27 | A PDF archive of channel conversations is readable and complete enough to be the record | [Hypothesis - test] | Pick 2-3 pilot teams incl. a private channel + a channel with images/long threads; run `07 Export-TeamsChannelsToPdf.ps1`; hand the PDFs + `TeamsExportCoverage.md` to the source admin; admin judges readability/completeness, compares history span with live Teams; record the archive-vs-import decision in `Decision-Log.md` | |
| 28 | Pilot users' first sign-in works under the target's Conditional Access | [Hypothesis - test] | Sign in a pilot user on a new PC before/after ESP completes if a device-compliance policy exists; test a location-based CA policy with and without the trusted locations imported; try a legacy-auth client if blocking is configured; check mobile app-protection requirements | |
| 29 | MFA re-registration in the target works at first sign-in (TAP if used) | [Hypothesis - test] | Pilot user registers MFA in the target; if TAP is enabled, verify the help-desk TAP flow | |
