# Working rules for this repo

- Public repo. Never commit customer names, domains, tenant IDs, UPNs or inventory data. Examples use contoso (source) / fabrikam (target) and the allowlisted placeholder GUIDs in `tests/guid-allowlist.txt`.
- Customer material lives under the gitignored `customers/<name>/`. Keep `customers/.denylist` (local only) up to date with every customer name, domain and tenant ID.
- Verify before every commit/push: `pwsh -NoProfile -File tests/Invoke-Checks.ps1` (parse check, PSScriptAnalyzer errors, Pester 5, leak guard). Must exit 0.
- Script conventions: PowerShell 7.2+, tenant-changing scripts use `SupportsShouldProcess`, a GUID `-TenantId` and the guarded `Connect-Migration*` functions in `tools/Common.psm1`. CSV output only via `Export-CsvSafe` (UTF-8 BOM). Read Graph SDK objects via `Get-GraphValue` (never `"$($a -or $b)"`). No passwords or secrets written to disk.
- Files adapted from mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit@4de1a31 keep the attribution header and are listed in `THIRD-PARTY-NOTICES.md`.
- English only.
