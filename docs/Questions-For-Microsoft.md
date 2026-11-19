# Open questions for Microsoft

Things Microsoft Learn does **not** document for the Orchestrator path. Resolve each one with
Microsoft (or prove it in the technical pilot) before the cutover they gate.

## Domain and UPN (drives the phase 09 hypothesis)

1. **Order of operations**: is migrating data with `.onmicrosoft.com` addressing and moving the
   custom domain + UPNs in the same cutover weekend the supported order for Orchestrator
   migrations? Any required minimum gap after batch completion?
2. **OneDrive redirect**: does the Orchestrator's OneDrive redirect survive a UPN change made
   after the batch completes?
3. **Completed jobs after UPN change**: does changing the target UPN affect completed
   Orchestrator job state (per-user workload status, Teams meeting links migrated by the
   Meeting workload)?
4. **Domain removal timing vs source MailUsers**: the migrated source users remain as MailUsers
   — is there a documented order for removing the domain given their targetAddress still points
   at it? Can/should the MailUsers be re-pointed or removed first?

## Identities

5. **CTIM for shared/resource mailboxes**: can CTIM write ExchangeGuid/x500 onto target
   MailUsers destined to become shared/room/equipment mailboxes via the standard cross-tenant
   mailbox migration, or is manual stamping (phase 06) the only supported route?
6. **Cross-Tenant User Data Migration licence for shared mailboxes**: is the licence required
   per shared/resource mailbox object?

## User experience

7. **External meeting attendees**: after a migrated Teams meeting, what do external guests see —
   new invite required, or does the original link still work?
8. **Modified series occurrences**: confirm that a series with a modified occurrence needs the
   invite re-sent after migration.

## Cleanup

9. **OneDrive/SPO cross-tenant trust removal**: what is the documented way to fully remove the
   SPO cross-tenant relationship set up during tenant prep? (Installed
   `Set-SPOCrossTenantRelationship` exposes no remove/disable parameter — is an org-relationship
   removal plus app-consent revocation sufficient?)
10. **OneDrive post-migration Step 7**: confirm the full checklist the OneDrive doc's Step 7
    expects beyond what the Orchestrator post-migration page lists.
