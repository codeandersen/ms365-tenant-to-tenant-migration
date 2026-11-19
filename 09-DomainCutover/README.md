# 09 - Domain cutover

Moves the custom domain from the source tenant to the target, then switches addresses, UPNs and
DNS. Scripts adapted from the Mezba toolkit with the playbook's tenant guards.

## IMPORTANT - the order below is a HYPOTHESIS

Microsoft does not document a domain/UPN order for **Orchestrator** migrations (the cross-tenant
mailbox doc's domain section predates the Orchestrator). The order here assumes: **data first with
onmicrosoft addressing, domain + UPN in the same cutover weekend**. Validate every step in the
technical pilot and raise the questions below with Microsoft.

**Open questions for Microsoft** (do not cut over without answers):

1. Does the Orchestrator's OneDrive redirect survive a UPN change made after the batch completes?
2. Does changing the target UPN affect completed Orchestrator jobs (per-user states, Teams meeting
   links migrated by the Meeting workload)?
3. Timing of domain removal vs the source MailUsers the migration left behind (their
   targetAddress still points at the source domain).
4. Recommended order for onmicrosoft-first data + later custom-domain addressing.

## Order (cutover weekend)

```
T-7d   Lower DNS TTLs on the moving domains (Export-DomainDns shows what needs lowering)
T-1d   Export-DomainDns (rollback copy)            - read-only
       Remove-SourceDomain -SnapshotOnly           - recipient snapshot
       Test-CutoverReadiness -BlockersOnly         - read-only GO/NO-GO
T-0    Add-TargetDomain -Domain contoso.com        - adds unverified, prints MS= TXT
       publish the MS= TXT; Add-TargetDomain -WaitForDns confirms every NS serves it
       Clear-DeletedUserDomain                     - free domains held by deleted users
       Remove-SourceDomain -FixApplications -RemoveDomain
       Add-TargetDomain -Verify                    - verify in target (fast once released)
       Add-TargetDomain -EnableDkim                - after selector CNAMEs exist
       Switch-TargetAddresses                      - old addresses + X500s back onto targets (addresses only)
       Set-TargetUpn                               - UPN -> custom domain (guarded by batch status)
       Set-DomainDnsRecords                        - MX/SPF/DKIM/autodiscover at the provider
       Block-SourceSignIn -Exclude <breakglass>    - freeze source accounts
```

Every change writes a **backup before touching anything**:

- `Remove-SourceDomain` snapshots every recipient (addresses + LegacyExchangeDN) and every user's
  UPN to `customers/<c>/output/09-DomainCutover/`.
- `Switch-TargetAddresses` writes `TargetRecipients-backup-*.csv` first and **aborts if the backup
  fails**.
- `Set-DomainDnsRecords` exports the whole zone to JSON before a single write; API tokens only
  come from env (`GODADDY_KEY`/`GODADDY_SECRET`, `CLOUDFLARE_API_TOKEN`) or a hidden prompt.
- `Block-SourceSignIn` requires `-Exclude` (pass `@()` explicitly for "no exceptions").

## Scripts

| Script | Side | What it does |
|---|---|---|
| `Export-DomainDns.ps1` | offline | Read-only: records M365-relevant DNS + TTLs; `-FullScan` brute-forces the zone |
| `Test-CutoverReadiness.ps1` | both | Read-only GO/NO-GO checklist; `-BlockersOnly` filters to FAIL/WARN |
| `Clear-DeletedUserDomain.ps1` | source | Frees domains held by recycle-bin users (restore as `-old@onmicrosoft`, block, re-delete) |
| `Remove-SourceDomain.ps1` | source | Snapshot + blocker check (deleted users, synced users, app URIs, ProxyOnly) + moves everything off the domain + `-RemoveDomain` |
| `Add-TargetDomain.ps1` | target | Add unverified, wait for the MS= TXT, `-Verify`, `-EnableDkim` |
| `Switch-TargetAddresses.ps1` | target | Addresses only: old addresses + `X500:<LegacyExchangeDN>` back on targets (+ primary for plan rows); `-RemoveConflictingGuests` backs each guest up before deleting |
| `Set-TargetUpn.ps1` | target | The only script that changes UPNs: UPN (+primary SMTP) to the custom domain per the 01 list; refuses unverified domains and non-Completed batches (unless `-Force`) |
| `Set-DomainDnsRecords.ps1` | DNS | Writes the new records via GoDaddy/Cloudflare APIs, with a mandatory zone backup first |
| `Block-SourceSignIn.ps1` | source | `accountEnabled=false` per mapping list, verified by read-back |

## Coverage note

`Remove-SourceDomain` covers the full set of domain-holding objects: mailboxes, **MailUsers**
(including the Orchestrator-converted ones), shared/resource mailboxes, distribution and M365
groups, mail contacts, deleted users (recycle bin), app registration identifier URIs, and
ProxyOnly Entra objects (flagged for the admin-centre wizard - Graph can't edit them).

## Credentials

No script sets or writes passwords - nothing of that kind is stored in this repo or in
`customers/`. Users already sign in to the target tenant pre-cutover and register MFA; issuing
credentials afterwards is a separate admin process (a Temporary Access Pass or a self-service
password reset, per your tenant policy).
