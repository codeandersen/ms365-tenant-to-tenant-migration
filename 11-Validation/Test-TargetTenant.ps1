#requires -Version 7.2
# Adapted from mezbauddin/M365_Tenant_to_Tenant_Migration_Toolkit@4de1a31 (MIT). See THIRD-PARTY-NOTICES.md.
# Changes: rewritten for the Orchestrator flow - per-user checks are mailbox type, Exchange+Teams
# licence, OneDrive presence, and all batch workloads Completed via Get-MgBetaCrossTenantMigrationJobUser
# (read with Get-GraphValue); tenant-level checks are MX/autodiscover/SPF DNS for the final domain and an
# optional source-side MailUser targetAddress pass. Guarded Connect-Migration*; -Customer output via
# New-OutputFolder + Export-CsvSafe; decision logic is the pure Test-MigratedUserState in Orchestrator.psm1.
<#
.SYNOPSIS
    Read-only post-migration validation of the target tenant against the 01-Design user list.
    Writes a Pass/Fail/Warn report so a wave can be signed off.

.DESCRIPTION
    Read-only. Run it in the TARGET after a batch completes, and again after cutover. Per user in
    migration-users.csv it checks:

      Mailbox   the target recipient exists and is a mailbox (UserMailbox)
      Licence   a licence covering Exchange AND Teams is assigned (SKU name match is
                heuristic - SkuPartNumber contains the parts)
      OneDrive  a personal site exists whose owner matches the target UPN
      Workloads every workload status for the user in their batch job reads
                Completed/CompletedWithErrors (Get-MgBetaCrossTenantMigrationJobUser, Get-GraphValue)
      TeamsChat the job user's Teams/chat status, when exposed, reads completed

    Tenant-level checks (DNS only, no tenant access): MX, autodiscover CNAME and SPF TXT for the
    final domain resolve to the target - add -FinalDomain after cutover.

    With -CheckSource it also connects to the SOURCE and confirms each source MailUser still carries
    targetAddress pointing at the target (mail routing while the domain is in transit).

.PARAMETER TenantId
    Target tenant ID (GUID).

.PARAMETER AdminUpn
    Target admin sign-in name.

.PARAMETER UserListPath
    migration-users.csv from 01-Design.

.PARAMETER SharePointAdminUrl
    Target SharePoint admin URL (e.g. https://fabrikam-admin.sharepoint.com) - turns on the OneDrive check.

.PARAMETER FinalDomain
    The moved vanity domain (e.g. contoso.com). Turns on the MX/autodiscover/SPF DNS checks.

.PARAMETER CheckSource
    Also validate source MailUsers. Requires -SourceTenantId and -SourceAdminUpn.

.PARAMETER Customer
    Output goes under customers/<Customer>/output/11-Validation/.

.EXAMPLE
    .\Test-TargetTenant.ps1 -TenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -AdminUpn 'admin@fabrikam.onmicrosoft.com' `
        -UserListPath .\customers\contoso\input\migration-users.csv -SharePointAdminUrl 'https://fabrikam-admin.sharepoint.com' -Customer contoso

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Requires: ExchangeOnlineManagement, Microsoft.Graph.Authentication, Microsoft.Graph.Beta.Migrations,
    optional Microsoft.Online.SharePoint.PowerShell. Reader roles suffice.
    Learn: https://learn.microsoft.com/en-us/microsoft-365/enterprise/migration-orchestrator-6-post-migration
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)][string]$UserListPath,

    [ValidatePattern('^https://[a-z0-9-]+-admin\.sharepoint\.com/?$')][string]$SharePointAdminUrl,

    [string]$FinalDomain,

    [switch]$CheckSource,
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })][string]$SourceTenantId,
    [string]$SourceAdminUpn,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

$users = @(Import-MigrationUserList -Path $UserListPath)
$outDir = New-OutputFolder -Customer $Customer -Phase '11-Validation'

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result($Object, $Check, $Result, $Expected, $Actual, $Detail) {
    $results.Add([pscustomobject]@{ Object = $Object; Check = $Check; Result = $Result; Expected = $Expected; Actual = $Actual; Detail = $Detail })
    if ($Result -ne 'Pass') {
        $c = @{ Warn = 'Yellow'; Fail = 'Red' }[$Result]
        Write-Host ("  [{0}] {1} {2}: expected {3}, found {4}. {5}" -f $Result, $Object, $Check, $Expected, $Actual, $Detail) -ForegroundColor $c
    }
}

# ------------------------------------------------------------ target connections
$exo = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn
$ctx = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'User.Read.All', 'Directory.Read.All', 'CrossTenantContentMigration.Read.All'
Write-Host "Target: $($exo.UserPrincipalName) (EXO), $($ctx.Account) (Graph)" -ForegroundColor Cyan

$skuNames = @{}
foreach ($s in Get-MgSubscribedSku -All) { $skuNames["$($s.SkuId)"] = "$($s.SkuPartNumber)" }

$oneDrives = $null
if ($SharePointAdminUrl) {
    try {
        $null = Connect-MigrationSharePoint -TenantId $TenantId -AdminUrl $SharePointAdminUrl
        $oneDrives = @(Get-SPOSite -IncludePersonalSite $true -Limit All -Filter "Url -like '-my.sharepoint.com/personal/'")
        Write-Host "  $($oneDrives.Count) personal site(s) read" -ForegroundColor Cyan
    }
    catch { Add-Result 'Tenant' 'OneDrive' 'Warn' 'sites read' 'not read' "SharePoint check failed ($($_.Exception.Message)) - OneDrive checks skipped" }
}
else { Add-Result 'Tenant' 'OneDrive' 'Warn' 'sites read' 'not checked' 'No -SharePointAdminUrl given' }

$allJobs = @(Get-MgBetaCrossTenantMigrationJob -All -ErrorAction SilentlyContinue)

# ------------------------------------------------------------ per user
foreach ($u in $users) {
    $upn = $u.TargetUpn.ToLower()
    $dest = Get-EXORecipient -Identity $upn -Properties EmailAddresses, ExternalDirectoryObjectId, RecipientTypeDetails -ErrorAction SilentlyContinue
    $rtype = if ($dest) { "$($dest.RecipientTypeDetails)" } else { 'missing' }
    if (-not $dest) { Add-Result $upn 'Mailbox' 'Fail' 'UserMailbox' 'missing' 'Target recipient not found' }

    $licEx = $false; $licTeams = $false
    if ($dest -and $dest.ExternalDirectoryObjectId) {
        $gu = Get-MgUser -UserId $dest.ExternalDirectoryObjectId -Property Id, AssignedLicenses -ErrorAction SilentlyContinue
        $names = @($gu.AssignedLicenses | ForEach-Object { $skuNames["$($_.SkuId)"] } | Where-Object { $_ })
        # Heuristic: Exchange coverage = a service-plan-bearing SKU; we match SkuPartNumber parts.
        $licEx = [bool]($names | Where-Object { $_ -match 'EXCHANGE|E5|E3|BUSINESS|O365|SPE_' })
        $licTeams = [bool]($names | Where-Object { $_ -match 'TEAMS|E5|E3|BUSINESS|O365|SPE_' })
        Add-Result $upn 'Licence' $(if ($licEx -and $licTeams) { 'Pass' } else { 'Fail' }) 'Exchange + Teams' ($names -join ';') 'SKU-name heuristic - verify service plans for unusual SKUs'
    }

    $odFound = $false
    if ($null -ne $oneDrives) {
        $odFound = [bool]($oneDrives | Where-Object { "$($_.Owner)".ToLower() -eq $upn } | Select-Object -First 1)
        Add-Result $upn 'OneDrive' $(if ($odFound) { 'Pass' } else { 'Fail' }) 'exists' $(if ($odFound) { 'found' } else { 'none' }) ''
    }

    $job = $allJobs | Where-Object { "$(Get-GraphValue -Object $_ -Name 'displayName')" -eq $u.Batch } | Select-Object -First 1
    $statuses = @(); $chatStatus = ''
    if ($job -and $dest) {
        $jobId = "$(Get-GraphValue -Object $job -Name 'id')"
        $urows = @(Get-MgBetaCrossTenantMigrationJobUser -CrossTenantMigrationJobId $jobId -All -ErrorAction SilentlyContinue |
            Where-Object { "$(Get-GraphValue -Object $_ -Name 'id')" -eq "$($dest.ExternalDirectoryObjectId)" -or
                           "$(Get-GraphValue -Object $_ -Name 'mail')" -eq $upn -or
                           "$(Get-GraphValue -Object $_ -Name 'userPrincipalName')" -eq $upn })
        $statuses = @($urows | ForEach-Object { "$(Get-GraphValue -Object $_ -Name 'status')" } | Where-Object { $_ })
        $chatStatus = "$(Get-GraphValue -Object ($urows | Select-Object -First 1) -Name 'teamsChatStatus')"
        Add-Result $upn 'Workloads' $(if (@($statuses | Where-Object { $_ -in 'Completed', 'CompletedWithErrors' }).Count -eq $statuses.Count -and $statuses.Count) { 'Pass' } else { 'Fail' }) 'Completed' ($statuses -join ';') "job '$($u.Batch)'"
    }
    elseif (-not $job) { Add-Result $upn 'Workloads' 'Warn' 'job found' 'none' "No migration job named '$($u.Batch)'" }
    else { Add-Result $upn 'Workloads' 'Fail' 'Completed' 'no target object' 'Cannot match the user to a job row' }

    $verdict = Test-MigratedUserState -RecipientType $rtype -LicensedExchange $licEx -LicensedTeams $licTeams `
        -OneDriveFound $odFound -WorkloadStatuses $statuses -TeamsChatStatus $chatStatus
    foreach ($p in $verdict.Problems) { Add-Result $upn 'Overall' 'Fail' 'ready' 'not ready' $p }
    if ($verdict.Pass) { Add-Result $upn 'Overall' 'Pass' 'ready' 'ready' '' }
}

# ------------------------------------------------------------ tenant-level DNS (final domain)
if ($FinalDomain) {
    Write-Host "DNS checks for $FinalDomain" -ForegroundColor Cyan
    try {
        $mx = @(Resolve-DnsName -Name $FinalDomain -Type MX -ErrorAction Stop | Where-Object Type -eq 'MX')
        $mxOk = [bool]($mx | Where-Object { "$($_.NameExchange)" -match 'mail\.protection\.outlook\.com$' })
        Add-Result 'DNS' "MX $FinalDomain" $(if ($mxOk) { 'Pass' } else { 'Fail' }) '*mail.protection.outlook.com' (($mx | ForEach-Object { $_.NameExchange }) -join ';') ''
    }
    catch { Add-Result 'DNS' "MX $FinalDomain" 'Fail' 'records' 'none' $_.Exception.Message }
    try {
        $auto = Resolve-DnsName -Name "autodiscover.$FinalDomain" -Type CNAME -ErrorAction SilentlyContinue
        $autoOk = [bool]($auto | Where-Object { "$($_.NameHost)" -match 'autodiscover\.outlook\.com$' })
        Add-Result 'DNS' "autodiscover.$FinalDomain" $(if ($autoOk) { 'Pass' } else { 'Fail' }) 'autodiscover.outlook.com' "$(@($auto | ForEach-Object { $_.NameHost }) -join ';')" ''
    }
    catch { Add-Result 'DNS' "autodiscover.$FinalDomain" 'Fail' 'CNAME' 'none' $_.Exception.Message }
    try {
        $txt = @(Resolve-DnsName -Name $FinalDomain -Type TXT -ErrorAction SilentlyContinue | Where-Object Type -eq 'TXT')
        $spf = @($txt | Where-Object { "$($_.Strings)" -match '^v=spf1' })
        Add-Result 'DNS' "SPF $FinalDomain" $(if ($spf) { 'Pass' } else { 'Warn' }) 'a v=spf1 TXT record' "$(@($txt | ForEach-Object { $_.Strings }) -join ' | ')" 'Check it includes the target tenant'
    }
    catch { Add-Result 'DNS' "SPF $FinalDomain" 'Warn' 'TXT records' 'none' $_.Exception.Message }
}
else { Add-Result 'DNS' 'Final domain' 'Warn' 'checked' 'skipped' 'Pass -FinalDomain after cutover to check MX/autodiscover/SPF' }

# ------------------------------------------------------------ optional source pass
if ($CheckSource) {
    if (-not $SourceTenantId -or -not $SourceAdminUpn) { Add-Result 'Source' 'Connection' 'Fail' 'source session' 'missing' 'Give -SourceTenantId and -SourceAdminUpn with -CheckSource' }
    else {
        try {
            $null = Connect-MigrationExchange -TenantId $SourceTenantId -AdminUpn $SourceAdminUpn
            foreach ($u in $users) {
                $mu = Get-MailUser -Identity $u.SourcePrimarySmtp -ErrorAction SilentlyContinue
                $ta = if ($mu) { "$($mu.ExternalEmailAddress)" } else { '' }
                if (-not $mu) { Add-Result $u.SourcePrimarySmtp 'SourceMailUser' 'Warn' 'targetAddress' 'missing' 'Source MailUser not found - fine if intentionally removed' }
                elseif ($ta -match 'SMTP:') { Add-Result $u.SourcePrimarySmtp 'SourceMailUser' 'Pass' 'targetAddress' $ta '' }
                else { Add-Result $u.SourcePrimarySmtp 'SourceMailUser' 'Warn' 'targetAddress' $ta 'No targetAddress - forwarding to the target may not be set' }
            }
        }
        catch { Add-Result 'Source' 'Connection' 'Warn' 'source session' 'failed' $_.Exception.Message }
    }
}

# ------------------------------------------------------------ report
$file = Join-Path $outDir "Validation-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
$results | Export-CsvSafe -Path $file
Write-Host ''
$results | Group-Object Check | Sort-Object Name | ForEach-Object {
    $g = $_.Group
    [pscustomobject]@{ Check = $_.Name; Pass = @($g | Where-Object Result -eq 'Pass').Count; Warn = @($g | Where-Object Result -eq 'Warn').Count; Fail = @($g | Where-Object Result -eq 'Fail').Count }
} | Format-Table -AutoSize | Out-String -Width 120 | Write-Host
$fails = @($results | Where-Object Result -eq 'Fail').Count
$warns = @($results | Where-Object Result -eq 'Warn').Count
Write-Host ("{0} checks: {1} pass, {2} warn, {3} fail." -f $results.Count, ($results.Count - $fails - $warns), $warns, $fails) -ForegroundColor $(if ($fails) { 'Red' } elseif ($warns) { 'Yellow' } else { 'Green' })
Write-Host "Report: $file" -ForegroundColor Cyan
