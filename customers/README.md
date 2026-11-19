# customers/ — local working folders (never committed)

Everything under `customers/` is gitignored except this file. Create one folder
per engagement and keep **all** customer material inside it:

```
customers/<name>/
    inventory/     output of 00-Assessment\Collect-TenantInventory.ps1
    mapping/       identity-mapping and batch CSVs (CTIM input/output)
    output/        per-run output written by New-OutputFolder
                   (<name>/output/<Phase>/<yyyyMMdd-HHmmss>)
```

Inventory and mapping files contain personal data (names, e-mail addresses,
tenant IDs). They must never be committed, pushed, or pasted into tickets or
chat. Keep them under `customers/<name>/` only.

## The denylist

`customers/.denylist` is the customer-name blocklist used by the leak guard
(`tests/Test-NoCustomerData.ps1`). It holds **one term per line**: customer
names, domains, and tenant IDs. Blank lines and lines starting with `#` are
ignored.

Maintain it: add every customer identifier before you start work for that
customer. The leak guard scans every tracked and untracked file in the repo and
fails if any denylist term appears — run `tests/Invoke-Checks.ps1` before
committing.
