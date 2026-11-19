# customers/ — local working folders (never committed)

Everything under `customers/` is gitignored except this file. Create one folder
per engagement (`tools/New-CustomerWorkspace.ps1 -Customer <name>`) and keep
**all** customer material inside it:

```
customers/<name>/
    input/       filled-in copies of 01-Design/templates (migration-users.csv,
                 shared-mailbox mapping, office-ip-ranges.csv, teams-export-list.csv,
                 Decision-Log.md, ...)
    inventory/   Collect-TenantInventory output
                 (Inventory_<Tenant>_<Role>_<stamp>\ incl. Review.md, Readiness.md,
                 TrustedLocations-*)
    output/      per-run output of all other scripts:
                 output/<Phase>/<yyyyMMdd-HHmmss>/ (New-OutputFolder)
```

Inventory, mapping and export files contain personal data (names, e-mail
addresses, tenant IDs). They must never be committed, pushed, or pasted into
tickets or chat — that is why everything lives here and nowhere else. Scripts
enforce it: every write goes through `Assert-CustomerDataPath`, which refuses
any output path inside the repo outside `customers/<name>/` (paths outside the
repo are still allowed).

## The denylist

`customers/.denylist` is the customer-name blocklist used by the leak guard
(`tests/Test-NoCustomerData.ps1`). It holds **one term per line**: customer
names, domains, and tenant IDs. Blank lines and lines starting with `#` are
ignored.

Maintain it: add every customer identifier before you start work for that
customer. The leak guard scans every tracked and untracked file in the repo and
fails if any denylist term appears — run `tests/Invoke-Checks.ps1` before
committing.
