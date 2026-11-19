# CTIM mapping CSV — schema notes

The mapping file is what you download with `Download-CtimCopiedIdentities`, edit, and
upload with `Upload-CtimMappingData` when the automatic PrimarySmtpAddress matching is
not enough (or when you want explicit control of which source object maps to which
target object).

Source: Microsoft Learn — Cross-Tenant Identity Mapping
(https://learn.microsoft.com/en-us/microsoft-365/enterprise/cross-tenant-identity-mapping)

## Rules (documented)

- **Delimiter must be a comma.** If the file uses semicolons or pipes,
  `Upload-CtimMappingData` fails. Open it in a plain-text editor to verify.
- **Edit only `TargetExternalDirectoryObjectId`.** Populate it with the object ID
  (GUID) of the MailUser in the target tenant. Do not add columns, rename headers,
  or change any other field.
- Leave `TargetExternalDirectoryObjectId` empty for objects you deliberately do not
  map yet; you can map them later (the job may report `CompletedWithWarnings`).
- Close the file before uploading — a file lock prevents the upload.
- `Upload-CtimMappingData -AutoProgress` (module ≥ 0.0.1-Preview9252) uploads and
  starts the CSV map request in one step; otherwise run
  `New-CtimMapRequest -SourceTenantGuid <guid> -UseCsv` after the upload completes.
- **Always keep a downloaded copy before accepting any copy request with
  `-Overwrite`** — overwritten mappings cannot be recovered.

## Personal data

The file contains real identities (names, UPNs, object IDs). Treat it like the
inventory: keep it under `customers/<name>/` only and never commit it.
