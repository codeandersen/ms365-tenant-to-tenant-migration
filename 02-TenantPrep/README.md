# 02 — Tenant preparation

**Purpose.** Make both tenants trustworthy to the Orchestrator **before** any user object is
created or mapped. Everything here comes from the documented tenant-prep steps; the pieces
that cannot be scripted are manual portal steps listed below.

## Order (do target first where the doc says so)

1. **Manual portal step — migration app (target admin).** Register a multi-tenant app in the
   **target** tenant, redirect URI `https://office.com`, API permission `Mailbox.Migration`
   (application), create a client secret, grant admin consent in the target, and send the
   source admin the consent URL
   (`https://login.microsoftonline.com/<source>.onmicrosoft.com/adminconsent?client_id=<appId>&redirect_uri=https://office.com`).
   This is intentionally **not** scripted — no app IDs or secrets are ever written to this repo.
2. **Source admin accepts the app** via that URL (manual).
3. `Test-OrchestratorPrereqs.ps1 -Role Source` and `-Role Target` — baseline.
4. `Set-OrchestratorTenantPrep.ps1` per tenant, steps in this order:
   - **Target:** `MigrationEndpoint` (needs `-ApplicationId`, `-RemoteTenant` = source
     onmicrosoft.com, `-Credential` = app ID + secret, prompted), then `OrgRelationship`
     (Inbound, DomainNames = source tenant GUID).
   - **Source:** `OrgRelationship` (creates the mail-enabled security scope group,
     RemoteOutbound, OAuthApplicationId, MailboxMovePublishedScopes).
   - **Both:** `MigrationApps` — needs the `CrossTenantMigration` **NuGet package** downloaded
     from Microsoft Learn (not on PSGallery):
     `Expand-Archive .\CrossTenantMigration.nupkg .\CTModule`, then
     `-CrossTenantMigrationModulePath .\CTModule\CrossTenantMigration`. Runs the documented
     `Grant-CTMSAppPermissions` (target only), `Grant-OneDriveAppPermissions`,
     `Grant-CTTMAppPermissions`, `Grant-MMSAppPermissions -TenantType source|target`,
     `Set-CalendarRBACRoles` (target only).
   - **Both:** `OneDriveTrust` — `Set-SPOCrossTenantRelationship -Scenario MnA` in each tenant
     against the other's cross-tenant host URL (`Get-SPOCrossTenantHostURL`), then verify.
   - **Both:** `TeamsFederation` — `-AllowFederatedUsers $true` (`-TrialTenant` adds
     `-ExternalAccessWithTrialTenants Allowed`).
5. `Test-OrchestratorPrereqs.ps1` again — everything that matters should be Pass.

## Both-tenant checklist

| Item | Source | Target |
|------|--------|--------|
| Migration app registered + consented (portal) | consent only | ✔ (manual) |
| Mail-enabled security scope group | ✔ (script creates) | n/a |
| Org relationship | RemoteOutbound + OAuthApplicationId + scopes | Inbound |
| Migration endpoint | n/a | ✔ |
| Migration service apps (`Grant-*`, `Set-CalendarRBACRoles`) | OneDrive, CTTM, MMS(source) | CTMS, OneDrive, CTTM, MMS(target), CalendarRBAC |
| SPO cross-tenant trust | ✔ | ✔ |
| Teams federation `AllowFederatedUsers` | ✔ | ✔ |
| Graph + Graph.Beta installed, same version, Beta ≥ 2.33.0 | both | both |
| Cross-Tenant User Data Migration licences purchased | assign to source or target users later | |
| Conditional Access / named locations / auth methods | export via `00 Export-TrustedLocations.ps1` | Target admin reviews: imports the trusted locations from the export file, reviews enabled CA policies against migrated users/devices (compliance, location, MFA, legacy-auth, app-protection), decides on Temporary Access Pass for first sign-in, and considers excluding the migration admin accounts appropriately |

## Files

- `Test-OrchestratorPrereqs.ps1` — **read-only** checker (Pass/Fail/Unknown per item,
  optional CSV under `customers/<Customer>/output/02-TenantPrep/`).
- `Set-OrchestratorTenantPrep.ps1` — the scriptable steps, `-WhatIf` supported.

## Sources

- Configuring source and target tenants:
  https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-3-tenant-configuration
- Cross-tenant mailbox migration:
  https://learn.microsoft.com/en-us/microsoft-365/enterprise/cross-tenant-mailbox-migration
- Cross-tenant OneDrive migration, steps 1–3 (trust):
  https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration-step2

> Untested against live tenants — validate in technical test/pilot.
