#requires -Version 7.2
<#
.SYNOPSIS
    Changes target users' sign-in names (and optionally their primary address) from the
    onmicrosoft domain to the moved custom domain, per the 01 user list - after a per-object
    backup, and only for users whose migration batch Completed.

.DESCRIPTION
    Cutover-weekend step, run in the TARGET tenant after the domain is verified there. For each
    row of migration-users.csv it sets the Entra UPN to FinalUpn (or the target part of
    FinalPrimarySmtp) and, when FinalPrimarySmtp is present, the mailbox's primary address.

    Guards, in order:
      1. Backup: current Id/UserPrincipalName/Mail/ProxyAddresses for every listed user is written
         to customers/<Customer>/output/09-DomainCutover/ BEFORE anything changes. A failed backup
         aborts the run.
      2. Domain: the FinalUpn domain must be a VERIFIED domain in the target tenant.
      3. Batch: the user's batch job (found by display name = the CSV Batch value) must exist and
         every workload status for that user must read 'Completed' (read via
         Get-MgBetaCrossTenantMigrationJobUser + Get-GraphValue). Anything else refuses the user;
         -Force overrides the check but still logs it.

    This order is a playbook hypothesis - Microsoft does not document a UPN-change order for
    Orchestrator migrations; see the README's open questions for Microsoft.

.PARAMETER TenantId
    Target tenant ID (GUID).

.PARAMETER AdminUpn
    Target admin sign-in name.

.PARAMETER UserListPath
    migration-users.csv (with the optional FinalUpn/FinalPrimarySmtp columns filled in).

.PARAMETER Force
    Change UPNs even where the batch/user status isn't Completed.

.PARAMETER Customer
    Output goes under customers/<Customer>/output/09-DomainCutover/.

.EXAMPLE
    .\Set-TargetUpn.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@fabrikam.onmicrosoft.com' `
        -UserListPath .\customers\contoso\migration-users.csv -Customer contoso -WhatIf

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    A UPN change renames the OneDrive URL and signs the user out of Office/Teams - cutover weekend only.
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

    [switch]$Force,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

$users = @(Import-MigrationUserList -Path $UserListPath)
$work = [System.Collections.Generic.List[object]]::new()
foreach ($u in $users) {
    $finalUpn = "$($u.FinalUpn)".Trim()
    $finalSmtp = "$($u.FinalPrimarySmtp)".Trim()
    if (-not $finalUpn -and $finalSmtp) { $finalUpn = $finalSmtp }
    if (-not $finalUpn) { continue }
    $work.Add([pscustomobject]@{ User = $u; FinalUpn = $finalUpn; FinalPrimarySmtp = $finalSmtp; Batch = $u.Batch })
}
if (-not $work.Count) { throw 'No rows with FinalUpn or FinalPrimarySmtp in the user list.' }

$outDir = New-OutputFolder -Customer $Customer -Phase '09-DomainCutover'
$null = Connect-MigrationGraph -TenantId $TenantId -AdminUpn $AdminUpn -Scopes 'User.ReadWrite.All', 'Domain.Read.All'

# ---- 1. backup before change
$backupFile = Join-Path $outDir "TargetUserBackup-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
try {
    $backup = foreach ($w in $work) {
        $mu = Get-MgUser -UserId $w.User.TargetUpn -Property Id, UserPrincipalName, Mail, ProxyAddresses -ErrorAction Stop
        [pscustomobject]@{ Id = $mu.Id; UserPrincipalName = $mu.UserPrincipalName; Mail = $mu.Mail; ProxyAddresses = (@($mu.ProxyAddresses) -join ';') }
    }
    $backup | Export-CsvSafe -Path $backupFile
    Write-Host "Backup of $($backup.Count) target user(s) written to $backupFile" -ForegroundColor Green
}
catch { throw "Backup failed ($($_.Exception.Message)) - refusing to change anything without a backup." }

# ---- 2. domain verified
$domains = @{}
foreach ($d in Get-MgDomain -All) { $domains[$d.Id.ToLower()] = "$($d.VerificationState)" }

# ---- 3. batch status lookup (lazy: jobs resolved by display name once)
$allJobs = $null
function Get-BatchJob($name) {
    if ($null -eq $allJobs) { $script:allJobs = @(Get-MgBetaCrossTenantMigrationJob -All -ErrorAction SilentlyContinue) }
    $allJobs | Where-Object { "$(Get-GraphValue -Object $_ -Name 'displayName')" -eq $name } | Select-Object -First 1
}
function Get-UserStatuses($jobId, $userId) {
    @(Get-MgBetaCrossTenantMigrationJobUser -CrossTenantMigrationJobId $jobId -All -ErrorAction SilentlyContinue |
        Where-Object { "$(Get-GraphValue -Object $_ -Name 'id')" -eq $userId -or
                       "$(Get-GraphValue -Object $_ -Name 'userPrincipalName')" -eq $userId -or
                       "$(Get-GraphValue -Object $_ -Name 'mail')" -eq $userId })
}

$log = [System.Collections.Generic.List[object]]::new()
function Add-Result($Obj, $Status, $Detail) {
    $log.Add([pscustomobject]@{ Object = $Obj; Status = $Status; Detail = $Detail })
    $c = @{ Done = 'Green'; Skipped = 'Gray'; Refused = 'Red'; Warn = 'Yellow'; WhatIf = 'Cyan'; Problem = 'Red' }[$Status]
    Write-Host ("  [{0}] {1}: {2}" -f $Status, $Obj, $Detail) -ForegroundColor $c
}

$exo = $null
foreach ($w in $work) {
    $src = $w.User.TargetUpn
    $dom = $w.FinalUpn.Split('@')[-1].ToLower()
    if ($domains[$dom] -ne 'Verified' -and "$($domains[$dom])" -ne 'Verified') {
        Add-Result $src 'Refused' "Domain $dom is not verified in the target tenant - run Add-TargetDomain -Verify first"; continue
    }

    $job = Get-BatchJob $w.Batch
    if (-not $job) {
        if (-not $Force) { Add-Result $src 'Refused' "No migration job named '$($w.Batch)' - cannot prove migration completed (use -Force to override)"; continue }
        Add-Result $src 'Warn' "No migration job named '$($w.Batch)' - proceeding anyway (-Force)"
    }
    else {
        $jobId = "$(Get-GraphValue -Object $job -Name 'id')"
        $mgUser = Get-MgUser -UserId $src -Property Id -ErrorAction SilentlyContinue
        $rows = if ($mgUser) { Get-UserStatuses $jobId $mgUser.Id } else { Get-UserStatuses $jobId $src }
        $statuses = @($rows | ForEach-Object { "$(Get-GraphValue -Object $_ -Name 'status')" })
        $jobStatus = "$(Get-GraphValue -Object $job -Name 'status')"
        if ($statuses -and (@($statuses | Where-Object { $_ -eq 'Completed' }).Count -eq $statuses.Count)) {
            # good
        }
        elseif (-not $Force) { Add-Result $src 'Refused' "Batch status: job=$jobStatus, user workloads=[$($statuses -join ',')] - not Completed (use -Force to override)"; continue }
        else { Add-Result $src 'Warn' "Batch status: job=$jobStatus, user workloads=[$($statuses -join ',')] - proceeding anyway (-Force)" }
    }

    $current = (Get-MgUser -UserId $src -Property Id, UserPrincipalName -ErrorAction Stop)
    if ("$($current.UserPrincipalName)".ToLower() -eq $w.FinalUpn.ToLower()) { Add-Result $src 'Skipped' "Already $($w.FinalUpn)" }
    elseif ($PSCmdlet.ShouldProcess($src, "UPN -> $($w.FinalUpn)")) {
        try { Update-MgUser -UserId $current.Id -UserPrincipalName $w.FinalUpn; Add-Result $src 'Done' "UPN -> $($w.FinalUpn)" }
        catch { Add-Result $src 'Problem' "UPN: $($_.Exception.Message)" }
    }
    else { Add-Result $src 'WhatIf' "Would change UPN -> $($w.FinalUpn)" }

    if ($w.FinalPrimarySmtp) {
        if (-not $exo) { $exo = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn }
        if ($PSCmdlet.ShouldProcess($src, "PrimarySmtp -> $($w.FinalPrimarySmtp)")) {
            try { Set-Mailbox -Identity $current.Id -WindowsEmailAddress $w.FinalPrimarySmtp -ErrorAction Stop; Add-Result $src 'Done' "PrimarySmtp -> $($w.FinalPrimarySmtp)" }
            catch { Add-Result $src 'Problem' "PrimarySmtp: $($_.Exception.Message)" }
        }
        else { Add-Result $src 'WhatIf' "Would change PrimarySmtp -> $($w.FinalPrimarySmtp)" }
    }
}

$file = Join-Path $outDir "SetTargetUpn-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
$log | Export-CsvSafe -Path $file
Write-Host "Report: $file" -ForegroundColor Cyan
