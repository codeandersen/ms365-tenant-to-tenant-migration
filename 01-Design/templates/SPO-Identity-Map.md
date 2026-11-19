# SharePoint/OneDrive identity map (spo-identity-map.csv)

> Built by `03-Identities/New-SpoIdentityMap.ps1` — do not hand-edit. This page documents
> the format so reviews and troubleshooting know what the file should look like.

**Why it exists:** the CTIM identity mapping (see `CTIM-Mapping-CSV.md`) covers only
migrating users' *mailboxes/OneDrives*. This SPO identity map is what preserves
**everyone else's** access — non-migrating users, guests and groups — to OneDrive and
SharePoint content. Learn calls it optional; this playbook treats it as **required**.

- Learn: https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration-step4
         https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration-step5
         https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration-step7

## Format

One comma-delimited CSV, **no header row**, **no BOM** (a BOM would corrupt the first
field — the script writes UTF-8 without BOM), exactly **six columns**:

```
User,<SourceTenantCompanyID>,<SourceUserUpn>,<TargetUserUpn>,<TargetUserEmail>,<UserType>
Group,<SourceTenantCompanyID>,<SourceGroupObjectID>,<TargetGroupObjectID>,<TargetGroupObjectID>,RegularGroup
Group,<SourceTenantCompanyID>,<SourceGroupObjectID>,<TargetGroupObjectID>,<M365GroupAlias>,O365Group
```

| Row | Column 1 | Column 6 | Notes |
|-----|----------|----------|-------|
| Member user | `User` | `RegularUser` | TargetUpn = the identity at migration time |
| Source guest → target member | `User` | `GuestUser` | Source UPN contains `#EXT#` |
| Source guest → target guest | `User` | `GuestUser` | Target guest must already exist (New-TargetGuests) |
| Security / mail-enabled / distribution group | `Group` | `RegularGroup` | Column 5 = TargetGroupObjectID again |
| M365 group | `Group` | `O365Group` | Column 5 = target group **alias** (no `.`) |

## Rules

- One-to-one: a source identity maps to exactly one target identity.
- Group aliases must not contain `.`; the M365 group's target site URL derives from the alias.
- **Full-map overwrite**: `Add-SPOTenantIdentityMap -IdentityMapPath` replaces the whole
  previous map — always regenerate and re-upload after every change to users/guests/groups.
- Pre-created target users must already be members of the relevant groups before the move
  (New-TargetGroups runs before any OneDrive/SharePoint move).
- M365 groups for migrating sites must be created with
  `New-MgBetaGroup -GroupTypes Unified -ResourceBehaviorOptions ProvisionSiteOnDemand`
  (done by `07 New-TargetSiteGroups` — New-TargetGroups refuses to create them).

## Known doc discrepancy (pilot item)

The Learn step-5 example **image** shows column 1 = `User` for an M365-group row while the
table says `Group`. The script writes `Group`; verify the observed behaviour in the pilot.

## Verify

`-Verify` samples entries with `Get-SPOTenantIdentityMappingUser -Field SourceUserKey
-Value <upn>` and `Get-SPOTenantIdentityMappingGroup`. `-CheckCompatibility` runs
`Get-SPOCrossTenantCompatibilityStatus` on the source; `Compatible`/`Warning` pass,
`Incompatible` aborts.
