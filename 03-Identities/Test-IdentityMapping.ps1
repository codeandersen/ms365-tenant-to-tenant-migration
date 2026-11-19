#requires -Version 7.2
<#
.SYNOPSIS
    Read-only: exports source mailbox identity attributes, or verifies CTIM wrote them correctly
    on the target MailUsers.

.DESCRIPTION
    Two modes:

    ExportSource (run in the SOURCE tenant): reads each user's source mailbox and writes
    source-mailboxes.csv under customers/<Customer>/output/03-Identities/ with
    SourcePrimarySmtp, ExchangeGuid, ArchiveGuid, ArchiveStatus, LegacyExchangeDN and
    X500Addresses (';'-separated). This is the "expected state" the verification compares
    against - CTIM writes these onto the target MailUsers.

    Verify (run in the TARGET tenant): for every user row, reads the target MailUser and the
    tenant's accepted domains, calls Compare-MigrationIdentity, and writes a verification CSV
    (TargetUpn, Pass, Problems, VerifiedAtUtc). Set-TargetLicenses.ps1 refuses users without a
    fresh Pass from this file.

.PARAMETER Mode
    ExportSource or Verify.

.PARAMETER TenantId
    The tenant ID (GUID) of the tenant the mode runs in (source for ExportSource, target for
    Verify). The Exchange Online connection is asserted against it.

.PARAMETER AdminUpn
    Admin sign-in name for Exchange Online in that tenant.

.PARAMETER UserListPath
    Path to migration-users.csv.

.PARAMETER SourceCsv
    Verify mode only: path to the source-mailboxes.csv produced by ExportSource.

.PARAMETER Customer
    Output goes under customers/<Customer>/output/03-Identities/.

.EXAMPLE
    .\Test-IdentityMapping.ps1 -Mode ExportSource -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' `
        -AdminUpn 'admin@contoso.com' -UserListPath .\customers\fabrikam\migration-users.csv -Customer fabrikam

.EXAMPLE
    .\Test-IdentityMapping.ps1 -Mode Verify -TenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' `
        -AdminUpn 'admin@fabrikam.com' -UserListPath .\customers\fabrikam\migration-users.csv `
        -SourceCsv .\customers\fabrikam\output\03-Identities\...\source-mailboxes.csv -Customer fabrikam

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Sources:
      https://learn.microsoft.com/en-us/microsoft-365/enterprise/cross-tenant-identity-mapping
      https://learn.microsoft.com/en-us/microsoft-365/enterprise/cross-tenant-mailbox-migration
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('ExportSource', 'Verify')]
    [string]$Mode,

    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$UserListPath,

    [string]$SourceCsv,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

$users = @(Import-MigrationUserList -Path $UserListPath)
$null = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn
$out = New-OutputFolder -Customer $Customer -Phase '03-Identities'

if ($Mode -eq 'ExportSource') {
    $rows = foreach ($u in $users) {
        $m = Get-EXOMailbox -Identity $u.SourcePrimarySmtp -Properties ExchangeGuid, ArchiveGuid, ArchiveStatus, LegacyExchangeDN, EmailAddresses -ErrorAction SilentlyContinue
        if (-not $m) {
            [pscustomobject]@{ SourcePrimarySmtp = $u.SourcePrimarySmtp; ExchangeGuid = ''; ArchiveGuid = ''; ArchiveStatus = ''; LegacyExchangeDN = ''; X500Addresses = ''; Error = 'mailbox not found' }
            continue
        }
        $x500 = @($m.EmailAddresses | ForEach-Object { "$_" } | Where-Object { $_ -match '^x500:' }) -join ';'
        [pscustomobject]@{
            SourcePrimarySmtp = $u.SourcePrimarySmtp
            ExchangeGuid      = "$($m.ExchangeGuid)"
            ArchiveGuid       = "$($m.ArchiveGuid)"
            ArchiveStatus     = "$($m.ArchiveStatus)"
            LegacyExchangeDN  = "$($m.LegacyExchangeDN)"
            X500Addresses     = $x500
            Error             = ''
        }
    }
    $file = Join-Path $out 'source-mailboxes.csv'
    $rows | Export-CsvSafe -Path $file
    Write-Host "Source identity written: $file - copy this path into -SourceCsv when you run -Mode Verify on the target." -ForegroundColor Green
    return
}

# ------------------------------------------------------------ Verify (target)
if (-not $SourceCsv) { throw 'Verify needs -SourceCsv (the source-mailboxes.csv from ExportSource).' }
$srcBySmtp = @{}
foreach ($r in (Import-Csv -Path $SourceCsv)) { $srcBySmtp["$($r.SourcePrimarySmtp)".ToLower()] = $r }
$accepted = @(Get-AcceptedDomain | ForEach-Object { "$($_.DomainName)".ToLower() })
$now = [datetime]::UtcNow.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)

$rows = foreach ($u in $users) {
    $src = $srcBySmtp["$($u.SourcePrimarySmtp)".ToLower()]
    if (-not $src) {
        [pscustomobject]@{ TargetUpn = $u.TargetUpn; Pass = 'False'; Problems = "no source identity row for $($u.SourcePrimarySmtp) - rerun ExportSource"; VerifiedAtUtc = $now }
        continue
    }
    $mu = Get-MailUser -Identity $u.TargetUpn -ErrorAction SilentlyContinue
    if (-not $mu) {
        [pscustomobject]@{ TargetUpn = $u.TargetUpn; Pass = 'False'; Problems = 'target MailUser not found - create it with New-TargetMailUsers.ps1'; VerifiedAtUtc = $now }
        continue
    }
    $target = [pscustomobject]@{
        RecipientTypeDetails = "$($mu.RecipientTypeDetails)"
        ExchangeGuid         = "$($mu.ExchangeGuid)"
        ArchiveGuid          = "$($mu.ArchiveGuid)"
        EmailAddresses       = @($mu.EmailAddresses | ForEach-Object { "$_" })
        PrimarySmtpAddress   = "$($mu.PrimarySmtpAddress)"
    }
    $r = Compare-MigrationIdentity -Source $src -Target $target -AcceptedDomains $accepted
    [pscustomobject]@{ TargetUpn = $u.TargetUpn; Pass = "$($r.Pass)"; Problems = ($r.Problems -join '; '); VerifiedAtUtc = $now }
}

$file = Join-Path $out 'identity-verification.csv'
$rows | Export-CsvSafe -Path $file
$rows | Format-Table -AutoSize | Out-Host
Write-Host "Verification written: $file" -ForegroundColor Green
$fails = @($rows | Where-Object Pass -ne 'True')
if ($fails) { Write-Host "$($fails.Count) user(s) did not verify - licensing is refused for them." -ForegroundColor Yellow }
