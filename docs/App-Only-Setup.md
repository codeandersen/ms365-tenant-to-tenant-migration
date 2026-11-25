# App-only setup (certificate authentication)

`Collect-TenantInventory.ps1` can run without interactive sign-in by using an
app registration with a certificate:

```powershell
.\Collect-TenantInventory.ps1 -Role Source -TenantName "Contoso" `
    -TenantId <tenant-guid> -Customer contoso `
    -ClientId <app-registration-guid> -CertificateThumbprint <40-hex-thumbprint>
```

Both parameters are required together. The certificate must be installed in
`Cert:\CurrentUser\My` or `Cert:\LocalMachine\My` **with its private key** on the
machine running the collector; the script validates this before connecting.

## 1. Create the app registration

1. Entra admin centre > **App registrations** > **New registration** — any name,
   single-tenant.
2. **Certificates & secrets** > **Certificates** > upload the public key (`.cer`).
3. **API permissions** > **Add a permission** > **Microsoft Graph** >
   **Application permissions** — add the application permissions listed under
   "Application permissions (union for app-only runs)" in
   [Collector-Matrix.md](Collector-Matrix.md), then **Grant admin consent**.
4. For Exchange Online: add the Office 365 Exchange Online API permission
   **`Exchange.ManageAsApp`** (application) — see
   <https://learn.microsoft.com/en-us/powershell/exchange/app-only-auth-powershell-v2>.
5. Assign the service principal a directory role — **Global Reader** covers most
   collectors; the Teams `*‑Cs` cmdlets need **Teams Administrator**, Exchange
   app-only needs a role such as **Exchange Recipient** or **Global Reader**
   (see the roles union in the matrix). The tool never assigns permissions
   itself — everything above is a manual admin step.

Collectors marked `AppOnly = No` in the matrix return `NotSupported` in
`Collectors.csv` instead of running (delegated-only APIs). SharePoint admin
PowerShell (`Connect-SPOService`) does not support certificate app-only, so the
SharePoint section falls back to the Graph data path automatically.

## Notes

- `Collectors.csv` / `summary.json.collectors` records which collectors ran,
  were skipped, or are not supported under app-only.
- `-Level` still applies: `Basic` skips per-object loops regardless of auth mode.
- The thumbprint and client ID may appear in `Collection.log`; the private key
  never leaves the certificate store.
