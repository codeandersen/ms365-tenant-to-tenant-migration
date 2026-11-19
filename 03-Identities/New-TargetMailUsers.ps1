# Adapted from mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit@4de1a31 (MIT). See THIRD-PARTY-NOTICES.md.
# Changes:
#   - Reads the canonical migration-users.csv via Import-MigrationUserList instead of Mezba's
#     Source,Destination mapping file + live source read (no source connection needed here).
#   - NO attribute stamping: ExchangeGuid/ArchiveGuid/EmailAddresses/x500 are written by CTIM
#     (New-CtimWriteRequest), never by us - removed the Set-MailUser stamping pass and the
#     Enable-MailUser/Update paths to keep the object shape exactly what the Orchestrator doc wants.
#   - Connects via Connect-MigrationExchange (tenant-guarded), output via Export-CsvSafe under
#     customers/<Customer>/output/03-Identities/.
#   - New-MailUser gets only the documented parameter set plus a random password that is never
#     output (users get credentials later via reset/TAP - see README).
#requires -Version 7.2
<#
.SYNOPSIS
    Creates the target-tenant MailUser objects the Orchestrator migrates into, exactly as the
    documented MailUser contract requires - before CTIM, before licensing.

.DESCRIPTION
    For every row in the migration user list, creates a target MailUser with:
      -MicrosoftOnlineServicesID  = TargetUpn (fabrikam.onmicrosoft.com while the domain is unverified)
      -PrimarySmtpAddress         = TargetPrimarySmtp (must be an accepted domain - row refused otherwise)
      -ExternalEmailAddress       = SourcePrimarySmtp (CTIM's PrimarySmtp matching reads this)
      -Name/DisplayName/FirstName/LastName from the list
      -Password                   = per-user random SecureString, never stored or printed
    Deliberately nothing else: ExchangeGuid, ArchiveGuid, EmailAddresses and x500 addresses come from
    the CTIM write request. Setting them ourselves is the single most common cause of failed moves.

    Existing recipients are reported as Exists (idempotent); an existing mailbox is a Conflict.
    No licence is ever assigned here - licensing happens after CTIM write + verification
    (Set-TargetLicenses.ps1).

.PARAMETER TenantId
    Target tenant ID (GUID). The Exchange Online connection is asserted against it.

.PARAMETER AdminUpn
    Target tenant admin sign-in name.

.PARAMETER UserListPath
    Path to migration-users.csv.

.PARAMETER Customer
    Writes the report CSV under customers/<Customer>/output/03-Identities/.

.PARAMETER Only
    Optional list of SourceUpn values to restrict the run (first technical-test users).

.EXAMPLE
    .\New-TargetMailUsers.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@fabrikam.com' `
        -UserListPath .\customers\fabrikam\migration-users.csv -Customer fabrikam -WhatIf

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Sources:
      https://learn.microsoft.com/en-us/microsoft-365/migration/migration-orchestrator-4-user-prep
      https://learn.microsoft.com/en-us/microsoft-365/enterprise/cross-tenant-mailbox-migration
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$UserListPath,

    [Parameter(Mandatory)]
    [string]$Customer,

    [string[]]$Only
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

$users = @(Import-MigrationUserList -Path $UserListPath)
if ($Only) {
    $keep = @($Only | ForEach-Object { "$_".ToLower() })
    $users = @($users | Where-Object { $keep -contains "$($_.SourceUpn)".ToLower() })
}
if (-not $users.Count) { throw 'No users to process.' }

$conn = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn
$accepted = @(Get-AcceptedDomain | ForEach-Object { "$($_.DomainName)".ToLower() })

$report = [System.Collections.Generic.List[object]]::new()
foreach ($u in $users) {
    $row = [ordered]@{ SourceUpn = $u.SourceUpn; TargetUpn = $u.TargetUpn; Action = ''; Note = '' }
    $primDom = ("$($u.TargetPrimarySmtp)" -split '@')[-1].ToLower()
    if ($accepted -notcontains $primDom) {
        $row.Action = 'Refused'; $row.Note = "TargetPrimarySmtp domain '$primDom' is not an accepted domain in this tenant"
        $report.Add([pscustomobject]$row); continue
    }
    try {
        $existing = Get-Recipient -Identity $u.TargetUpn -ErrorAction SilentlyContinue
        if ($existing -and "$($existing.RecipientTypeDetails)" -match 'Mailbox$') {
            $row.Action = 'Conflict'
            $row.Note = "Already a $($existing.RecipientTypeDetails) - a licensed mailbox on the target makes the migration fail"
            $report.Add([pscustomobject]$row); continue
        }
        if ($existing) {
            $row.Action = 'Exists'; $row.Note = "$($existing.RecipientTypeDetails) already present - left as is (CTIM verify catches attribute problems)"
            $report.Add([pscustomobject]$row); continue
        }
        if ($PSCmdlet.ShouldProcess($u.TargetUpn, "New-MailUser -MicrosoftOnlineServicesID $($u.TargetUpn) -ExternalEmailAddress $($u.SourcePrimarySmtp)")) {
            # 24 random bytes -> Base64; meets complexity with the appended suffix. Never written anywhere.
            $bytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(24)
            $pw = [System.Security.SecureString]::new()
            foreach ($c in ([Convert]::ToBase64String($bytes) + 'aA1!').ToCharArray()) { $pw.AppendChar($c) }
            $pw.MakeReadOnly()
            New-MailUser -Name $u.DisplayName -DisplayName $u.DisplayName -FirstName $u.FirstName -LastName $u.LastName `
                -MicrosoftOnlineServicesID $u.TargetUpn -PrimarySmtpAddress $u.TargetPrimarySmtp `
                -ExternalEmailAddress $u.SourcePrimarySmtp -Password $pw | Out-Null
            $row.Action = 'Created'
        }
        else { $row.Action = 'WhatIf:Create' }
    }
    catch { $row.Action = 'Error'; $row.Note = $_.Exception.Message }
    $report.Add([pscustomobject]$row)
}

$out = New-OutputFolder -Customer $Customer -Phase '03-Identities'
$file = Join-Path $out 'TargetMailUsers.csv'
$report | Export-CsvSafe -Path $file
$report | Group-Object Action | Select-Object Name, Count | Format-Table -AutoSize | Out-Host
Write-Host "Report: $file" -ForegroundColor Green
if ($report | Where-Object Action -in 'Refused', 'Conflict', 'Error') {
    Write-Host 'Fix every Refused, Conflict and Error row before CTIM.' -ForegroundColor Yellow
}
Write-Host 'Do NOT license these users and keep them out of OneDrive until CTIM write has completed and been verified.' -ForegroundColor Yellow
