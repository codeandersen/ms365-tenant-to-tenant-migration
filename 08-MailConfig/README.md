# 08 - Mail configuration (permissions, folders, forwarding, lists, contacts)

Mailbox **content** moves (Orchestrator for users, MRS for shared/resource). The configuration
around it does not: mailbox and calendar/folder permissions, forwarding, distribution lists,
mail contacts, transport rules. `Copy-MailConfig.ps1` (adapted from the Mezba toolkit) exports it
from the source and rebuilds it in the target.

## Run

```powershell
# Source - read-only export under customers/<Customer>/output/08-MailConfig/<stamp>/
.\Copy-MailConfig.ps1 -Export -TenantId <source-guid> -AdminUpn admin@contoso.com -Customer contoso

# Target - dry run first
.\Copy-MailConfig.ps1 -Import -TenantId <target-guid> -AdminUpn admin@fabrikam.onmicrosoft.com -Customer contoso `
    -ExportFolder .\customers\contoso\output\08-MailConfig\<stamp> -MappingFile .\UserMapping.csv `
    -AddressDomain fabrikam.onmicrosoft.com -WhatIf
```

`-AddressDomain` is the **target** domain new distribution lists get (the target onmicrosoft domain
before the domain move, the real domain after). `-AliasPrefix` avoids alias clashes.

## What it covers

| File | Export | Import |
|---|---|---|
| Permissions.csv | FullAccess, SendAs, SendOnBehalf | rebuilt via mapping; `unresolved:`/`external:` skipped |
| FolderPermissions.csv | Calendar (+Inbox/Contacts with `-IncludeFolders`), incl. delegates | `Add-/Set-MailboxFolderPermission` on the target's own folder names (localised!) |
| Forwarding.csv | internal + external forwarding | internal rebuilt; external only with `-IncludeExternalForwarding` |
| DistributionGroups(+Members).csv | lists + members | recreated tagged `CustomAttribute15='T2T:<source>'` for idempotency and cutover matching |
| DynamicGroups.csv | filters | **manual rebuild** (recipient filters can't be copied) |
| MailContacts.csv | contacts | recreated |
| TransportRules.csv/.xml | summary + full rule export | **never imported** - rebuild from the `New-TransportRule` commands in the XML, disabled until tested |
| CheckAfterCutover.csv | inbox rules + automatic replies | report only - verify after cutover |

## Timing notes (flagged for 09)

- Everything created on import uses the **target** (`onmicrosoft`/staging) addressing - nothing
  writes a source-domain SMTP address onto a target object. The **old addresses come back at
  cutover** via `09-DomainCutover/Switch-TargetAddresses.ps1`, which also finds the `T2T:`-tagged
  lists/contacts.
- Transport rules that reference source domains or source-only recipients belong to the post-09
  rebuild, enabled only after testing.
- Dynamic groups: rebuild by hand after cutover (their filters may reference source-only values).
