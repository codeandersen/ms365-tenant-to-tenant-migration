# Third-party notices

This repository incorporates code adapted from the following upstream project.

## mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit

- Repository: https://github.com/mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit
- Commit: `4de1a31` (4de1a31591a4bd2566cde70f5021a6112472b99c)
- Licence: MIT, Copyright (c) 2026 Mezba Uddin

### Files copied or adapted

| Source path (upstream)                       | Path in this repo                    | Status  |
| -------------------------------------------- | ------------------------------------ | ------- |
| `tools/Test-ModuleHealth.ps1`                | `tools/Test-ModuleHealth.ps1`        | adapted |
| `tools/Get-MigrationReport.ps1`              | `tools/Get-MigrationReport.ps1`      | adapted |
| `copy-options/A-Microsoft-native/New-TargetMailUsers.ps1` | `03-Identities/New-TargetMailUsers.ps1` | adapted |
| `copy-options/A-Microsoft-native/New-TargetMailUsers.ps1` | `06-SharedMailboxes-Holds/New-SharedMailboxMailUsers.ps1` | adapted |
| `05-MailConfig/Copy-MailConfig.ps1`              | `08-MailConfig/Copy-MailConfig.ps1`    | adapted |
| `07-DomainCutover/Export-DomainDns.ps1`          | `09-DomainCutover/Export-DomainDns.ps1` | adapted |
| `07-DomainCutover/Set-DomainDnsRecords.ps1`      | `09-DomainCutover/Set-DomainDnsRecords.ps1` | adapted |
| `07-DomainCutover/Add-TargetDomain.ps1`          | `09-DomainCutover/Add-TargetDomain.ps1` | adapted |
| `07-DomainCutover/Remove-SourceDomain.ps1`       | `09-DomainCutover/Remove-SourceDomain.ps1` | adapted |
| `07-DomainCutover/Clear-DeletedUserDomain.ps1`   | `09-DomainCutover/Clear-DeletedUserDomain.ps1` | adapted |
| `07-DomainCutover/Test-CutoverReadiness.ps1`     | `09-DomainCutover/Test-CutoverReadiness.ps1` | adapted |
| `07-DomainCutover/Switch-TargetAddresses.ps1`    | `09-DomainCutover/Switch-TargetAddresses.ps1` | adapted |
| `07-DomainCutover/Block-SourceSignIn.ps1`        | `09-DomainCutover/Block-SourceSignIn.ps1` | adapted |
| `08-Devices/Get-DeviceInventory.ps1`             | `10-Devices/Get-DeviceInventory.ps1`      | adapted |
| `08-Devices/Export-BitLockerKeys.ps1`            | `10-Devices/Get-BitLockerKeyReport.ps1`   | adapted (key values never read or written) |
| `09-Validation/Test-TargetTenant.ps1`            | `11-Validation/Test-TargetTenant.ps1`     | adapted |
| `10-Decommission/Get-DecommissionReadiness.ps1`  | `12-Decommission/Get-DecommissionReadiness.ps1` | adapted |
| `docs/*` (risk/lessons/comms structure)          | `docs/Risk-Register.md`, `docs/Lessons-Learnt.md`, `docs/Comms-Templates.md` | inspired |

Each adapted file carries a header noting the adaptation and a short list of
the changes made.

### MIT License (upstream text)

```
MIT License

Copyright (c) 2026 Mezba Uddin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
