<#
.SYNOPSIS
    Collects a read-only inventory of a Microsoft 365 tenant ahead of a tenant-to-tenant migration.

.DESCRIPTION
    The script connects to Microsoft Graph, Exchange Online, SharePoint Online,
    Microsoft Teams and Purview (Security & Compliance) and collects a full inventory for
    estimating and planning a tenant-to-tenant migration with Microsoft Migration
    Orchestrator.

    The script is strictly read-only: it only issues GET requests against Microsoft Graph and
    read cmdlets (Get-/Resolve-) against the other services. No tenant configuration is changed.

    Output is written to .\Inventory_<TenantName>_<Role>_<timestamp>\ with CSV files under
    attachments\, a summary.json with key figures, and Collection.log.

.PARAMETER Role
    The tenant's role in the migration: Source (e.g. Contoso) or Target (e.g. Fabrikam).

.PARAMETER TenantName
    Short name for the tenant, used in the folder name and report. E.g. Contoso or Fabrikam.

.PARAMETER OutputRoot
    Root folder for output. Defaults to the folder the script is run from.

.PARAMETER Sections
    Optional list of sections to collect. If omitted, all sections for the selected role run.

.PARAMETER SkipSections
    Optional list of sections to skip.

.PARAMETER SpoAdminUrl
    Optional override of the SharePoint admin URL. If not given it is derived from the tenant's
    initial *.onmicrosoft.com domain: https://<prefix>-admin.sharepoint.com.

.PARAMETER SourceInventoryPath
    Only with -Role Target: path to a previously collected source inventory folder. The script
    then compares source domains and users against target and writes DomainConflicts.csv and
    UserMatches.csv.

.PARAMETER SignInLookbackDays
    How far back the AppSignIns section looks in the Entra sign-in logs (1-30 days,
    default 30). Sign-in logs require Entra ID P1/P2 (30-day retention; Free keeps
    7 days) and one of the roles Reports Reader, Security Reader or Global Reader
    (permission AuditLog.Read.All - already requested). Without P1 the section
    falls back to the service principal sign-in activity report (beta, preview).
    https://learn.microsoft.com/en-us/graph/api/signin-list?view=graph-rest-beta
    https://learn.microsoft.com/en-us/graph/api/reportroot-list-serviceprincipalsigninactivities?view=graph-rest-beta

.PARAMETER TenantId
    Mandatory. Tenant ID (GUID) or a verified domain (e.g. contoso.com or
    contoso.onmicrosoft.com) of the tenant to collect from. Domains are resolved to a GUID
    via the tenant's openid-configuration (unauthenticated GET). The script aborts with an
    error if the connected tenant does not match -TenantId - collecting from the wrong tenant
    is impossible.

.EXAMPLE
    .\Collect-TenantInventory.ps1 -Role Source -TenantName Contoso -TenantId contoso.com
    Collects a complete inventory from the Contoso tenant. When signing in with a B2B guest
    account (guest with an admin role in Contoso) the sign-in is directed into Contoso via
    -TenantId, and the script verifies the connected tenant really is Contoso before
    collecting data.

.PARAMETER DisableWAM
    Disables Web Account Manager (broker) for the Exchange Online, IPPS and Teams
    connections. Use if sign-in fails with a WAM/broker error.

.EXAMPLE
    .\Collect-TenantInventory.ps1 -Role Source -TenantName Contoso -TenantId contoso.com
    Collects a complete inventory from the Contoso tenant (sign in as Global Admin for Contoso).

.EXAMPLE
    .\Collect-TenantInventory.ps1 -Role Target -TenantName Fabrikam -SourceInventoryPath .\Inventory_Contoso_Source_20261022_090302
    Collects the target inventory from Fabrikam and compares it with the Contoso inventory.

.EXAMPLE
    .\Collect-TenantInventory.ps1 -Role Source -TenantName Contoso -Sections Exchange,Users -SkipSections Dns
    Runs only the Exchange and Users sections and skips DNS.

.NOTES
    Version: 1.0
    Requires: Microsoft.Graph.Authentication, ExchangeOnlineManagement,
            Microsoft.Online.SharePoint.PowerShell, MicrosoftTeams
#>
#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Source','Target')]
    [string]$Role,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantName,

    [string]$OutputRoot = $PSScriptRoot,

    [string[]]$Sections,

    [string[]]$SkipSections,

    [string]$SpoAdminUrl,

    [string]$SourceInventoryPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(DontShow)]
    [ValidateSet('Graph','Exchange','SharePoint','Teams')]
    [string]$ServiceGroup,

    [Parameter(DontShow)]
    [string]$OutputFolder,

    [switch]$DisableWAM,

    [switch]$UseDeviceCode,

    [switch]$NewWindow,

    [Parameter(DontShow)]
    [switch]$ChildPauseOnError,

    [ValidateRange(1,30)]
    [int]$SignInLookbackDays = 30
)

Set-StrictMode -Version 1
$ErrorActionPreference = 'Stop'
# Invariant culture for output - otherwise Export-Csv writes decimals with a comma (da-DK),
# which gives wrong sums when the CSVs are read back.
[System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::InvariantCulture

# Child processes get -Sections as one comma-separated string via -File
$Sections     = @($Sections     | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$SkipSections = @($SkipSections | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$script:ToolVersion = '1.0'
if ($ServiceGroup) {
    # Child process: reuses the existing inventory folder from the orchestrator
    $outDir    = $OutputFolder
    $attachDir = Join-Path $outDir 'attachments'
} elseif ($OutputFolder) {
    # Resume in an existing inventory folder (e.g. after an aborted run)
    if (-not (Test-Path $OutputFolder)) { throw "-OutputFolder not found: $OutputFolder" }
    $outDir      = (Resolve-Path $OutputFolder).Path
    $attachDir   = Join-Path $outDir 'attachments'
    $null        = New-Item -ItemType Directory -Path $attachDir -Force
} else {
    $timestamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outDir      = Join-Path $OutputRoot "Inventory_${TenantName}_${Role}_$timestamp"
    $attachDir   = Join-Path $outDir 'attachments'
    $null        = New-Item -ItemType Directory -Path $attachDir -Force
}
$logPath     = Join-Path $outDir 'Collection.log'

$script:Summary = [ordered]@{
    toolVersion     = $script:ToolVersion
    tenantName      = $TenantName
    role            = $Role
    collectedBy     = $null
    collectedAt     = (Get-Date).ToString('o')
    outputFolder    = $outDir
    metrics         = [ordered]@{}
    failedSections  = [ordered]@{}
    skippedSections = [ordered]@{}
}
$script:ConcealedReports = $false

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $line | Out-File -FilePath $logPath -Append -Encoding utf8BOM
    switch ($Level) {
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        default { Write-Host $line }
    }
}

function Export-CsvSafe {
    param([object[]]$Data, [string]$Name)
    $path = Join-Path $attachDir $Name
    if ($null -eq $Data -or $Data.Count -eq 0) {
        Write-Log "Ingen data til $Name" -Level WARN
        return
    }
    $Data | Export-Csv -Path $path -NoTypeInformation -Encoding utf8BOM
    Write-Log "Wrote $($Data.Count) rows to attachments\$Name"
}

# ---------- Graph helpers ----------

function Get-GraphAll {
    # Fetches all pages from a Graph GET URI, with retry on 429/503 and @odata.nextLink following.
    param(
        [Parameter(Mandatory)][string]$Uri,
        [hashtable]$Headers,
        [int]$MaxRetries = 5
    )
    $results = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $attempt = 0
        while ($true) {
            try {
                $params = @{ Method = 'GET'; Uri = $next; OutputType = 'PSObject' }
                if ($Headers) { $params['Headers'] = $Headers }
                $resp = Invoke-MgGraphRequest @params
                break
            }
            catch {
                $attempt++
                $status = $null
                if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
                if (($status -eq 429 -or $status -eq 503) -and $attempt -le $MaxRetries) {
                    $retryAfter = 10
                    try {
                        $ra = $_.Exception.Response.Headers['Retry-After']
                        if ($ra) { $retryAfter = [int]($ra | Select-Object -First 1) }
                    } catch {}
                    Write-Log "Throttled ($status) on $next - waiting $retryAfter sec. (attempt $attempt/$MaxRetries)" -Level WARN
                    Start-Sleep -Seconds $retryAfter
                    continue
                }
                throw
            }
        }
        if ($null -eq $resp) { break }
        if ($resp.PSObject.Properties.Name -contains 'value') {
            foreach ($item in $resp.value) { $results.Add($item) }
            $nl = $resp.PSObject.Properties['@odata.nextLink']
            $next = if ($nl) { $nl.Value } else { $null }
        }
        else {
            $results.Add($resp)
            $next = $null
        }
    }
    return $results.ToArray()
}

function Invoke-GraphFirst {
    # One-request variant of Get-GraphAll: returns the first item of 'value' (or the
    # response itself when it is not paged). Same 429/503 retry. Errors are rethrown.
    param(
        [Parameter(Mandatory)][string]$Uri,
        [hashtable]$Headers,
        [int]$MaxRetries = 5
    )
    $attempt = 0
    while ($true) {
        try {
            $params = @{ Method = 'GET'; Uri = $Uri; OutputType = 'PSObject' }
            if ($Headers) { $params['Headers'] = $Headers }
            $resp = Invoke-MgGraphRequest @params
            break
        }
        catch {
            $attempt++
            $status = $null
            if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
            if (($status -eq 429 -or $status -eq 503) -and $attempt -le $MaxRetries) {
                $retryAfter = 10
                try {
                    $ra = $_.Exception.Response.Headers['Retry-After']
                    if ($ra) { $retryAfter = [int]($ra | Select-Object -First 1) }
                } catch {}
                Write-Log "Throttled ($status) on $Uri - waiting $retryAfter sec. (attempt $attempt/$MaxRetries)" -Level WARN
                Start-Sleep -Seconds $retryAfter
                continue
            }
            throw
        }
    }
    if ($null -eq $resp) { return $null }
    if ($resp.PSObject.Properties.Name -contains 'value') {
        return @($resp.value)[0]
    }
    return $resp
}

function Test-GraphForbidden {
    # True when a Graph error means "no access / no P1 licence" - distinct from other errors.
    param([Parameter(Mandatory)]$Err)
    $status = $null
    try { if ($Err.Exception.Response) { $status = [int]$Err.Exception.Response.StatusCode } } catch {}
    if ($status -eq 403) { return $true }
    return ("$($Err.Exception.Message)" -match '(?i)Authentication_RequestFromNonPremiumTenantOrB2CTenant|license')
}

function Get-AppSignInStatus {
    # Pure: status for one service principal.
    #   ActiveInWindow     - a sign-in log hit in the window, or report activity inside the window
    #   ActiveEarlier      - last activity (report) predates the window
    #   NoActivityRecorded - sources available, nothing found
    #   Unknown            - both sources unavailable
    param(
        [object[]]$LogDates,
        [object]$LastReportDate,
        [datetime]$WindowStart,
        [switch]$LogsUnavailable,
        [switch]$ReportUnavailable
    )
    if ($LogsUnavailable -and $ReportUnavailable) { return 'Unknown' }
    if (-not $LogsUnavailable -and $LogDates -and @($LogDates).Count -gt 0) { return 'ActiveInWindow' }
    if (-not $ReportUnavailable -and $LastReportDate) {
        if ([datetime]$LastReportDate -ge $WindowStart) { return 'ActiveInWindow' }
        return 'ActiveEarlier'
    }
    return 'NoActivityRecorded'
}

function Get-AppSignInQueryPlan {
    # Pure: which (appId, eventType) sign-in log queries to run for the window.
    # Candidates: apps with report activity on/after WindowStart - or every app when
    # the activity report is unavailable. Managed identities are queried only for
    # the 'managedIdentity' event type.
    param(
        [object[]]$ServicePrincipals,
        [hashtable]$ActivityByAppId,
        [datetime]$WindowStart,
        [switch]$ReportUnavailable
    )
    $plan = [System.Collections.Generic.List[object]]::new()
    foreach ($sp in $ServicePrincipals) {
        $candidate = [bool]$ReportUnavailable
        if (-not $candidate) {
            $act = $ActivityByAppId[$sp.appId]
            $candidate = ($act -and $act.LastActivityDate -and [datetime]$act.LastActivityDate -ge $WindowStart)
        }
        if (-not $candidate) { continue }
        $types = if ($sp.IsManagedIdentity) { @('managedIdentity') } else { @('interactiveUser','nonInteractiveUser','servicePrincipal') }
        foreach ($t in $types) { $plan.Add([pscustomobject]@{ AppId = $sp.appId; EventType = $t }) }
    }
    return $plan.ToArray()
}

function Get-GraphReport {
    # Fetches a Microsoft 365 usage report (CSV). Returns rows as objects.
    param(
        [Parameter(Mandatory)][string]$Endpoint,   # e.g. getEmailActivityUserDetail
        [string]$Period = 'D30',
        [string]$CsvName
    )
    $tmp = Join-Path $env:TEMP ("{0}_{1}.csv" -f $Endpoint, ([guid]::NewGuid().ToString('N')))
    try {
        $uri = "https://graph.microsoft.com/v1.0/reports/${Endpoint}(period='$Period')"
        try {
            Invoke-MgGraphRequest -Method GET -Uri $uri -OutputFilePath $tmp
        }
        catch {
            # Fallback: some versions return the CSV content directly
            $resp = Invoke-MgGraphRequest -Method GET -Uri $uri
            if ($resp -is [string]) { $resp | Out-File -FilePath $tmp -Encoding utf8BOM }
            elseif ($resp) { ($resp | ConvertTo-Json -Depth 5) | Out-File -FilePath $tmp -Encoding utf8BOM }
        }
        if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -eq 0) { return @() }
        $rows = Import-Csv -Path $tmp
        if ($CsvName -and $rows) {
            Export-CsvSafe -Data $rows -Name $CsvName
            $upnCol = $rows[0].PSObject.Properties.Name | Where-Object { $_ -match 'User Principal Name' } | Select-Object -First 1
            if ($upnCol) {
                $sample = ($rows | Select-Object -First 5 | ForEach-Object { $_.$upnCol }) -join ' '
                if ($sample -match '\b[0-9A-F]{32,}\b' -and $sample -notmatch '@') {
                    $script:ConcealedReports = $true
                    Write-Log "Report $Endpoint appears to be anonymised (UPN shows hash values). Turn off 'Display concealed user, group, and site names' in the M365 admin center to get real names." -Level WARN
                }
            }
        }
        return $rows
    }
    finally {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
}

function ConvertTo-GB {
    param([object]$Value)
    if ($null -eq $Value -or "$Value" -eq '') { return 0 }
    $s = "$Value"
    if ($s -match '\(([\d,\.]+) bytes\)') { return [math]::Round([double]($Matches[1] -replace ',','') / 1GB, 2) }
    try { return [math]::Round([double]$s / 1GB, 2) } catch { return 0 }
}

function Resolve-TenantId {
    # Resolves a GUID or domain to the tenant GUID via openid-configuration (unauthenticated GET).
    param([Parameter(Mandatory)][string]$TenantIdOrDomain)
    if ($TenantIdOrDomain -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        return $TenantIdOrDomain.ToLower()
    }
    $url = "https://login.microsoftonline.com/$TenantIdOrDomain/v2.0/.well-known/openid-configuration"
    $cfg = Invoke-RestMethod -Method GET -Uri $url -ErrorAction Stop
    if ($cfg.issuer -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
        return $Matches[1].ToLower()
    }
    throw "Could not derive tenant GUID from openid-configuration for '$TenantIdOrDomain' (issuer: $($cfg.issuer))"
}

$script:LicenseCaps = $null

function Test-LicenseGate {
    # Returns $false if the capability is known-absent (the section is skipped).
    # Unknown license status => collect anyway.
    param(
        [Parameter(Mandatory)][string]$Capability,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$What
    )
    # $caps can be an (ordered) hashtable from Invoke-Licenses in the same process or a PSObject from a partial file
    $caps = $script:LicenseCaps
    if ($null -eq $caps -and $script:Summary.metrics.Contains('licenseCapabilities')) {
        $caps = $script:Summary.metrics['licenseCapabilities']
    }
    $known = $false; $value = $null
    if ($caps -is [System.Collections.IDictionary]) {
        if ($caps.Contains($Capability)) { $known = $true; $value = $caps[$Capability] }
    } elseif ($null -ne $caps -and $caps.PSObject.Properties[$Capability]) {
        $known = $true; $value = $caps.$Capability
    }
    if (-not $known) {
        Write-Log "License status for '$Capability' unknown - collecting $Section anyway."
        return $true
    }
    if (-not [bool]$value) {
        $reason = "Not collected: no license for $What in the tenant (servicePlan not found among active licenses)"
        $script:Summary.skippedSections[$Section] = $reason
        if (-not $script:Summary.metrics.Contains('licenseSkipped')) {
            $script:Summary.metrics.licenseSkipped = @()
        }
        $script:Summary.metrics.licenseSkipped = @($script:Summary.metrics.licenseSkipped) + $Section
        Write-Log "$Section skipped: no license for $What." -Level WARN
        return $false
    }
    return $true
}

function ConvertFrom-OneDriveUsageReport {
    # Maps rows from getOneDriveUsageAccountDetail (CSV) to the OneDrive.csv format.
    param([Parameter(Mandatory)][object[]]$Rows)
    $out = foreach ($r in $Rows) {
        $bytes = 0.0
        try { $bytes = [double]($r.'Storage Used (Byte)' -replace ',','') } catch {}
        [pscustomobject]@{
            Url                    = $r.'Site URL'
            Owner                  = $r.'Owner Principal Name'
            Title                  = $r.'Site Display Name'
            StorageUsageGB         = [math]::Round($bytes / 1GB, 2)
            StorageUsageMB         = [math]::Round($bytes / 1MB, 0)
            StorageQuotaGB         = $null
            LastContentModifiedDate= $r.'Last Activity Date'
            LockState              = ''
            SharingCapability      = ''
            Status                 = ''
            FileCount              = $r.'File Count'
            ActiveFileCount        = $r.'Active File Count'
            Source                 = 'Graph-fallback'
        }
    }
    return @($out)
}

function ConvertFrom-SharePointUsageReport {
    # Maps rows from getSharePointSiteUsageDetail (CSV) to the SharePointSites.csv format.
    param([Parameter(Mandatory)][object[]]$Rows)
    $out = foreach ($r in $Rows) {
        if ($r.'Is Deleted' -eq 'True') { continue }
        $bytes = 0.0
        try { $bytes = [double]($r.'Storage Used (Byte)' -replace ',','') } catch {}
        [pscustomobject]@{
            Url                     = $r.'Site URL'
            Owner                   = $r.'Owner Principal Name'
            Title                   = $r.'Owner Display Name'
            Template                = $r.'Root Web Template'
            SiteId                  = $r.'Site Id'
            StorageUsageGB          = [math]::Round($bytes / 1GB, 2)
            StorageQuotaGB          = $null
            LastContentModifiedDate = $r.'Last Activity Date'
            LockState               = ''
            SharingCapability       = ''
            GroupId                 = ''
            IsTeamsConnected        = ''
            IsTeamsChannelConnected = ''
            Status                  = ''
            FileCount               = $r.'File Count'
            ActiveFileCount         = $r.'Active File Count'
            Source                  = 'Graph-fallback'
        }
    }
    return @($out)
}

function Invoke-OneDriveFallback {
    Write-Log "OneDrive: using the Graph usage report as fallback (SPO admin not available)."
    $usage = Get-GraphReport -Endpoint 'getOneDriveUsageAccountDetail'
    if (-not $usage -or $usage.Count -eq 0) { throw "getOneDriveUsageAccountDetail returned no data" }
    $rows = ConvertFrom-OneDriveUsageReport -Rows $usage
    Export-CsvSafe -Data $rows -Name 'OneDrive.csv'
    # The raw report with all columns is also saved as an attachment
    Export-CsvSafe -Data $usage -Name 'OneDriveUsage.csv'
    $script:Summary.metrics.spoDataSource   = 'Graph-fallback'
    $script:Summary.metrics.fallbackUsed    = $true
    $script:Summary.metrics.oneDriveCount   = $rows.Count
    $script:Summary.metrics.oneDriveTotalGB = [math]::Round(($rows | Measure-Object StorageUsageGB -Sum).Sum, 2)
}

function Invoke-SharePointFallback {
    Write-Log "SharePoint: using Graph /sites/getAllSites + usage report as fallback (SPO admin not available)."
    $usage = Get-GraphReport -Endpoint 'getSharePointSiteUsageDetail'
    $usageByUrl = @{}
    foreach ($u in @($usage)) {
        if ($u.'Site URL' -and $u.'Is Deleted' -ne 'True') { $usageByUrl[$u.'Site URL'.ToLower()] = $u }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    $sites = $null
    try {
        $sites = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/sites/getAllSites?$select=id,webUrl,displayName,createdDateTime,lastModifiedDateTime,isPersonalSite&$top=999'
    } catch {
        Write-Log "/sites/getAllSites failed: $($_.Exception.Message)" -Level WARN
    }
    if ($sites) {
        foreach ($s in ($sites | Where-Object { -not $_.isPersonalSite -and $_.webUrl -notmatch '-my\.sharepoint\.com/personal/' })) {
            $u = $usageByUrl[$s.webUrl.ToLower()]
            $bytes = 0.0
            if ($u) { try { $bytes = [double]($u.'Storage Used (Byte)' -replace ',','') } catch {} }
            $rows.Add([pscustomobject]@{
                Url                     = $s.webUrl
                Owner                   = if ($u) { $u.'Owner Principal Name' } else { '' }
                Title                   = $s.displayName
                Template                = if ($u) { $u.'Root Web Template' } else { '' }
                SiteId                  = $s.id
                StorageUsageGB          = [math]::Round($bytes / 1GB, 2)
                StorageQuotaGB          = $null
                LastContentModifiedDate = if ($u) { $u.'Last Activity Date' } else { $s.lastModifiedDateTime }
                LockState               = ''
                SharingCapability       = ''
                GroupId                 = ''
                IsTeamsConnected        = ''
                IsTeamsChannelConnected = ''
                Status                  = ''
                FileCount               = if ($u) { $u.'File Count' } else { '' }
                ActiveFileCount         = if ($u) { $u.'Active File Count' } else { '' }
                CreatedDateTime         = $s.createdDateTime
                Source                  = 'Graph-fallback'
            })
            if ($u) { $usageByUrl.Remove($s.webUrl.ToLower()) }
        }
    }
    # Sites that only exist in the usage report (e.g. no access via /sites)
    foreach ($key in @($usageByUrl.Keys)) {
        $u = $usageByUrl[$key]
        foreach ($r in (ConvertFrom-SharePointUsageReport -Rows @($u))) { $rows.Add($r) }
    }
    if ($rows.Count -eq 0) { throw "Neither /sites/getAllSites nor getSharePointSiteUsageDetail returned data" }
    Export-CsvSafe -Data $rows.ToArray() -Name 'SharePointSites.csv'
    $script:Summary.metrics.spoDataSource       = 'Graph-fallback'
    $script:Summary.metrics.fallbackUsed        = $true
    $script:Summary.metrics.sharePointSiteCount = $rows.Count
    $script:Summary.metrics.sharePointTotalGB   = [math]::Round(($rows | Measure-Object StorageUsageGB -Sum).Sum, 2)
    $script:Summary.skippedSections['SharePointTenant'] = 'Requires SharePoint admin (not possible as a guest)'
    $script:Summary.skippedSections['ExternalUsers']    = 'Requires SharePoint admin (not possible as a guest)'
}

function Invoke-ExchangeFallback {
    # Fallback when Exchange Online PowerShell cannot be used (e.g. B2B guest).
    Write-Log "Exchange: using the Graph usage report as fallback (EXO PowerShell not available)."
    $usage = Get-GraphReport -Endpoint 'getMailboxUsageDetail'
    if (-not $usage -or $usage.Count -eq 0) { throw "getMailboxUsageDetail returned no data" }
    $rows = foreach ($r in $usage) {
        if ($r.'Is Deleted' -eq 'True') { continue }
        $bytes = 0.0
        try { $bytes = [double]($r.'Storage Used (Byte)' -replace ',','') } catch {}
        [pscustomobject]@{
            UserPrincipalName  = $r.'User Principal Name'
            DisplayName        = $r.'Display Name'
            RecipientTypeDetails = $r.'Recipient Type'
            TotalItemSizeGB    = [math]::Round($bytes / 1GB, 2)
            ItemCount          = $r.'Item Count'
            HasArchive         = $r.'Has Archive'
            LastUserActionTime = $r.'Last Activity Date'
            DeletedItemSizeGB  = $null
            Source             = 'Graph-fallback'
        }
    }
    Export-CsvSafe -Data @($rows) -Name 'MailboxStatistics.csv'
    # Limited Mailboxes.csv from the same report (only the columns the report provides)
    $mbxRows = foreach ($r in $rows) {
        [pscustomobject]@{
            UserPrincipalName  = $r.UserPrincipalName
            DisplayName        = $r.DisplayName
            RecipientTypeDetails = $r.RecipientTypeDetails
            PrimarySmtpAddress = ''
            TotalItemSizeGB    = $r.TotalItemSizeGB
            ArchiveStatus      = $r.HasArchive
            HasAnyHold         = ''
            HoldReasons        = ''
            ForwardingSmtpAddress = ''
            IsLarge50GB        = ($r.TotalItemSizeGB -gt 50)
            IsLarge100GB       = ($r.TotalItemSizeGB -gt 100)
            Source             = 'Graph-fallback'
        }
    }
    Export-CsvSafe -Data @($mbxRows) -Name 'Mailboxes.csv'
    $script:Summary.metrics.mailboxCount        = @($rows).Count
    $script:Summary.metrics.totalMailboxGB      = [math]::Round((@($rows) | Measure-Object TotalItemSizeGB -Sum).Sum, 2)
    $script:Summary.metrics.archiveMailboxCount = @($rows | Where-Object { $_.HasArchive -eq 'True' }).Count
    $script:Summary.metrics.mailboxesOver50GB   = @($mbxRows | Where-Object IsLarge50GB).Count
    $script:Summary.metrics.mailboxesOver100GB  = @($mbxRows | Where-Object IsLarge100GB).Count
    $script:Summary.metrics.holdsUnknown        = $true
    $script:Summary.metrics.fallbackUsed        = $true
    $script:Summary.skippedSections['MailboxHolds']      = 'Not available via Graph fallback (requires Exchange PowerShell)'
    $script:Summary.skippedSections['MailboxPermissions']= 'Not available via Graph fallback (requires Exchange PowerShell)'
    $script:Summary.skippedSections['Mailflow']          = 'Not available via Graph fallback (requires Exchange PowerShell)'
    Write-Log "Exchange fallback: holds, permissions, connectors, transport rules and forwarding are NOT covered (holdsUnknown=true)." -Level WARN
}

# ---------- Section definitions ----------

$script:SectionService = @{
    Tenant      = 'Graph'
    Licenses    = 'Graph'
    Users       = 'Graph'
    Groups      = 'Graph'
    Roles       = 'Graph'
    Security    = 'Graph'
    Apps        = 'Graph'
    Exchange    = 'EXO'
    Purview     = 'IPPS'
    OneDrive    = 'SPO'
    SharePoint  = 'SPO'
    Teams       = 'Graph+Teams'
    Devices     = 'Graph'
    Usage       = 'Graph'
    Dns         = 'None'
    CrossTenant = 'Graph+EXO'
    AppSignIns  = 'Graph'
}

$SourceSections = @('Tenant','Licenses','Users','Groups','Roles','Security','Apps','AppSignIns','Exchange','Purview','OneDrive','SharePoint','Teams','Devices','Usage','Dns')
$TargetSections = @('Tenant','Licenses','Users','Security','CrossTenant','TargetExchange')

# ---------- Source sections ----------

function Invoke-Tenant {
    $org = (Invoke-MgGraphRequest -OutputType PSObject -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization').value | Select-Object -First 1
    $orgRow = [pscustomobject]@{
        Id                       = $org.id
        DisplayName              = $org.displayName
        CountryLetterCode        = $org.countryLetterCode
        CreatedDateTime          = $org.createdDateTime
        OnPremisesSyncEnabled    = [bool]$org.onPremisesSyncEnabled
        OnPremisesLastSyncDateTime = $org.onPremisesLastSyncDateTime
        VerifiedDomains          = ($org.verifiedDomains | Where-Object isVerified | ForEach-Object name) -join '; '
        InitialDomain            = ($org.verifiedDomains | Where-Object isInitial | ForEach-Object name) -join '; '
    }
    Export-CsvSafe -Data @($orgRow) -Name 'Organization.csv'

    $domains = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/domains?$select=id,authenticationType,isDefault,isInitial,isVerified,supportedServices'
    $domRows = foreach ($d in $domains) {
        [pscustomobject]@{
            Id                 = $d.id
            AuthenticationType = $d.authenticationType
            IsDefault          = $d.isDefault
            IsInitial          = $d.isInitial
            IsVerified         = $d.isVerified
            SupportedServices  = ($d.supportedServices -join '; ')
        }
    }
    Export-CsvSafe -Data $domRows -Name 'Domains.csv'

    $script:Summary.metrics.tenantId               = $org.id
    $script:Summary.metrics.tenantDisplayName      = $org.displayName
    $script:Summary.metrics.hybridIdentity         = [bool]$org.onPremisesSyncEnabled
    $script:Summary.metrics.onPremisesLastSync     = $org.onPremisesLastSyncDateTime
    $script:Summary.metrics.domains                = @($domRows | Where-Object IsVerified | ForEach-Object Id)
    $script:Summary.metrics.verifiedDomainCount    = @($domRows | Where-Object IsVerified).Count
    $script:InitialDomain = ($org.verifiedDomains | Where-Object isInitial | Select-Object -First 1).name
}

function Invoke-Licenses {
    $skus = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/subscribedSkus'
    $rows = foreach ($s in $skus) {
        [pscustomobject]@{
            SkuId           = $s.skuId
            SkuPartNumber   = $s.skuPartNumber
            ConsumedUnits   = $s.consumedUnits
            EnabledUnits    = $s.prepaidUnits.enabled
            SuspendedUnits  = $s.prepaidUnits.suspended
            WarningUnits    = $s.prepaidUnits.warning
            AppliesTo       = $s.appliesTo
            CapabilityStatus= $s.capabilityStatus
        }
    }
    Export-CsvSafe -Data $rows -Name 'Licenses.csv'
    $script:Summary.metrics.licenses = @($rows | ForEach-Object { "$($_.SkuPartNumber) ($($_.ConsumedUnits)/$($_.EnabledUnits))" })

    # Service plan overview as an attachment
    $planRows = foreach ($s in $skus) {
        foreach ($p in @($s.servicePlans)) {
            [pscustomobject]@{
                SkuPartNumber      = $s.skuPartNumber
                ServicePlanName    = $p.servicePlanName
                ProvisioningStatus = "$($p.provisioningStatus)"
                AppliesTo          = $s.appliesTo
            }
        }
    }
    if ($planRows) { Export-CsvSafe -Data $planRows -Name 'LicenseServicePlans.csv' }

    # Derive license capabilities (only active SKUs with enabled units and active service plans)
    $capPatterns = [ordered]@{
        teamsPhone      = '^(MCOEV|MCOPSTN|MCOCAP)'
        intune          = '^INTUNE_A$'
        entraP1         = '^AAD_PREMIUM'
        exchangeArchive = '^(EXCHANGE_S_ARCHIVE|EXCHANGE_S_ENTERPRISE)$'
        purviewPremium  = '^(LOCKBOX_ENTERPRISE|EQUIVIO_ANALYTICS|INFO_GOVERNANCE|M365_ADVANCED_AUDITING)'
    }
    $caps  = [ordered]@{}
    $capSkus = [ordered]@{}
    foreach ($cap in $capPatterns.Keys) {
        $hits = [System.Collections.Generic.List[string]]::new()
        foreach ($s in $skus) {
            if ($s.capabilityStatus -ne 'Enabled' -or [int]$s.prepaidUnits.enabled -le 0) { continue }
            if (@($s.servicePlans | Where-Object { $_.servicePlanName -match $capPatterns[$cap] -and $_.provisioningStatus -ne 'Disabled' })) {
                $hits.Add($s.skuPartNumber)
            }
        }
        $caps[$cap]    = ($hits.Count -gt 0)
        $capSkus[$cap] = @($hits)
    }
    $script:LicenseCaps = $caps
    $script:Summary.metrics.licenseCapabilities  = $caps
    $script:Summary.metrics.licenseCapabilitySkus = $capSkus
    Write-Log ("Licens-capabilities: " + (($caps.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '))

    if ($Role -eq 'Target') {
        $mig = @($rows | Where-Object { $_.SkuPartNumber -match 'CROSS_TENANT|MIGRATION' })
        $script:Summary.metrics.migrationLicenseFound = ($mig.Count -gt 0)
        $script:Summary.metrics.migrationLicenses     = @($mig | ForEach-Object SkuPartNumber)
    }
}

function Invoke-Users {
    $baseProps = 'id,displayName,userPrincipalName,mail,proxyAddresses,userType,accountEnabled,onPremisesSyncEnabled,onPremisesImmutableId,usageLocation,createdDateTime,assignedLicenses,jobTitle,department,companyName,officeLocation,country'
    $signInAvailable = $true
    if (-not (Test-LicenseGate -Capability 'entraP1' -Section 'SignInActivity' -What 'sign-in aktivitet (Entra ID P1)')) {
        $signInAvailable = $false
        $script:Summary.metrics.signInActivityUnavailable = $true
    }
    try {
        if ($signInAvailable) {
            $users = Get-GraphAll -Uri "https://graph.microsoft.com/v1.0/users?`$select=$baseProps,signInActivity&`$top=999"
        } else {
            $users = Get-GraphAll -Uri "https://graph.microsoft.com/v1.0/users?`$select=$baseProps&`$top=999"
        }
    }
    catch {
        if ($_.Exception.Message -match '403|Authorization_RequestDenied|premium|license') {
            Write-Log "signInActivity requires Entra ID P1 - fetching users without signInActivity." -Level WARN
            $signInAvailable = $false
            $script:Summary.metrics.signInActivityUnavailable = $true
            $users = Get-GraphAll -Uri "https://graph.microsoft.com/v1.0/users?`$select=$baseProps&`$top=999"
        } else { throw }
    }
    $skus = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/subscribedSkus?$select=skuId,skuPartNumber'
    $skuMap = @{}; foreach ($s in $skus) { $skuMap[$s.skuId] = $s.skuPartNumber }
    $now = Get-Date
    $rows = foreach ($u in $users) {
        $lastSignIn = $u.signInActivity.lastSignInDateTime
        if (-not $lastSignIn) { $lastSignIn = $u.signInActivity.lastNonInteractiveSignInDateTime }
        $inactiveDays = $null
        if ($lastSignIn) { $inactiveDays = [int](($now - [datetime]$lastSignIn).TotalDays) }
        $lic = @($u.assignedLicenses | ForEach-Object { $skuMap[$_.skuId] } | Where-Object { $_ })
        [pscustomobject]@{
            Id                      = $u.id
            DisplayName             = $u.displayName
            UserPrincipalName       = $u.userPrincipalName
            Mail                    = $u.mail
            ProxyAddresses          = ($u.proxyAddresses -join '; ')
            UserType                = $u.userType
            IsGuest                 = ($u.userType -eq 'Guest')
            AccountEnabled          = $u.accountEnabled
            OnPremisesSyncEnabled   = [bool]$u.onPremisesSyncEnabled
            HasOnPremisesImmutableId= [bool]$u.onPremisesImmutableId
            UsageLocation           = $u.usageLocation
            CreatedDateTime         = $u.createdDateTime
            AssignedLicenses        = ($lic -join '; ')
            IsLicensed              = ($lic.Count -gt 0)
            LastSignInDateTime      = $lastSignIn
            InactiveDays            = $inactiveDays
            IsInactive              = ($null -eq $inactiveDays -or $inactiveDays -gt 90)
            JobTitle                = $u.jobTitle
            Department              = $u.department
            CompanyName             = $u.companyName
            OfficeLocation          = $u.officeLocation
            Country                 = $u.country
        }
    }
    Export-CsvSafe -Data $rows -Name 'Users.csv'
    $members = @($rows | Where-Object UserType -eq 'Member')
    $script:Summary.metrics.userCount        = $rows.Count
    $script:Summary.metrics.memberCount      = $members.Count
    $script:Summary.metrics.guestCount       = @($rows | Where-Object IsGuest).Count
    $script:Summary.metrics.enabledUserCount = @($rows | Where-Object AccountEnabled).Count
    $script:Summary.metrics.licensedCount    = @($rows | Where-Object IsLicensed).Count
    $script:Summary.metrics.inactive90dCount = @($rows | Where-Object { $_.UserType -eq 'Member' -and $_.IsInactive }).Count
    $script:Summary.metrics.syncedUserCount  = @($rows | Where-Object OnPremisesSyncEnabled).Count
}

function Invoke-TargetUsers {
    $users = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/users?$select=id,userPrincipalName,mail,proxyAddresses,displayName,userType,accountEnabled,onPremisesSyncEnabled&$top=999'
    $rows = foreach ($u in $users) {
        [pscustomobject]@{
            Id                    = $u.id
            UserPrincipalName     = $u.userPrincipalName
            Mail                  = $u.mail
            ProxyAddresses        = ($u.proxyAddresses -join '; ')
            DisplayName           = $u.displayName
            UserType              = $u.userType
            AccountEnabled        = $u.accountEnabled
            OnPremisesSyncEnabled = [bool]$u.onPremisesSyncEnabled
        }
    }
    Export-CsvSafe -Data $rows -Name 'Users.csv'
    $script:Summary.metrics.userCount = $rows.Count
}

function Invoke-Groups {
    $groups = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/groups?$select=id,displayName,mail,mailEnabled,securityEnabled,groupTypes,membershipRule,onPremisesSyncEnabled,resourceProvisioningOptions,visibility,createdDateTime&$top=999'
    $rows = foreach ($g in $groups) {
        $memberCount = $null; $ownerCount = $null
        try {
            $c = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$($g.id)/transitiveMembers/`$count" -Headers @{ ConsistencyLevel = 'eventual' }
            $memberCount = [int]$c
        } catch {}
        try {
            $o = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$($g.id)/owners/`$count" -Headers @{ ConsistencyLevel = 'eventual' }
            $ownerCount = [int]$o
        } catch {}
        $type = 'Security'
        if (@($g.groupTypes) -contains 'Unified') { $type = 'Microsoft365' }
        elseif (@($g.groupTypes) | Where-Object { $_ -like 'DynamicMembership*' }) { $type = 'Dynamic' }
        elseif ($g.mailEnabled -and $g.securityEnabled) { $type = 'MailEnabledSecurity' }
        elseif ($g.mailEnabled -and -not $g.securityEnabled) { $type = 'Distribution' }
        [pscustomobject]@{
            Id                      = $g.id
            DisplayName             = $g.displayName
            Mail                    = $g.mail
            GroupType               = $type
            MailEnabled             = $g.mailEnabled
            SecurityEnabled         = $g.securityEnabled
            GroupTypes              = ($g.groupTypes -join '; ')
            MembershipRule          = $g.membershipRule
            OnPremisesSyncEnabled   = [bool]$g.onPremisesSyncEnabled
            IsTeam                  = (@($g.resourceProvisioningOptions) -contains 'Team')
            Visibility              = $g.visibility
            CreatedDateTime         = $g.createdDateTime
            MemberCount             = $memberCount
            OwnerCount              = $ownerCount
        }
    }
    Export-CsvSafe -Data $rows -Name 'Groups.csv'
    $script:Summary.metrics.groupCount       = $rows.Count
    $script:Summary.metrics.groupsByType     = @{}
    foreach ($t in ($rows | Group-Object GroupType)) { $script:Summary.metrics.groupsByType[$t.Name] = $t.Count }
}

function Invoke-Roles {
    $defs = @{}
    foreach ($d in (Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName')) {
        $defs[$d.id] = $d.displayName
    }
    $assignments = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?$expand=principal'
    $rows = foreach ($a in $assignments) {
        $p = $a.principal
        [pscustomobject]@{
            RoleName          = $defs[$a.roleDefinitionId]
            RoleDefinitionId  = $a.roleDefinitionId
            PrincipalId       = $a.principalId
            PrincipalType     = ($p.'@odata.type' -replace '#microsoft.graph.','')
            PrincipalName     = if ($p.displayName) { $p.displayName } else { $p.userPrincipalName }
            PrincipalUPN      = $p.userPrincipalName
            DirectoryScopeId  = $a.directoryScopeId
        }
    }
    Export-CsvSafe -Data $rows -Name 'AdminRoles.csv'
    $script:Summary.metrics.adminAssignmentCount = $rows.Count
    $script:Summary.metrics.globalAdminCount = @($rows | Where-Object { $_.RoleName -eq 'Global Administrator' }).Count
}

function Invoke-Security {
    $entraP1 = Test-LicenseGate -Capability 'entraP1' -Section 'EntraP1' -What 'Entra ID P1 (Conditional Access, sign-in aktivitet, MFA-registrering)'
    # Conditional Access
    if (-not $entraP1) {
        $script:Summary.skippedSections['ConditionalAccess'] = "Not collected: no license for Entra ID P1 in the tenant (servicePlan AAD_PREMIUM not found among active licenses)"
    } else {
    try {
        $ca = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies'
        $caRows = foreach ($p in $ca) {
            [pscustomobject]@{
                Id            = $p.id
                DisplayName   = $p.displayName
                State         = $p.state
                CreatedDateTime = $p.createdDateTime
                ModifiedDateTime = $p.modifiedDateTime
                IncludeUsers    = ($p.conditions.users.includeUsers -join '; ')
                IncludeGroups   = ($p.conditions.users.includeGroups -join '; ')
                IncludeRoles    = ($p.conditions.users.includeRoles -join '; ')
                ExcludeUsers    = ($p.conditions.users.excludeUsers -join '; ')
                ExcludeGroups   = ($p.conditions.users.excludeGroups -join '; ')
                ExcludeRoles    = ($p.conditions.users.excludeRoles -join '; ')
                IncludeApplications = ($p.conditions.applications.includeApplications -join '; ')
                ClientAppTypes  = ($p.conditions.clientAppTypes -join '; ')
                IncludePlatforms = ($p.conditions.platforms.includePlatforms -join '; ')
                IncludeLocations = ($p.conditions.locations.includeLocations -join '; ')
                ExcludeLocations = ($p.conditions.locations.excludeLocations -join '; ')
                GrantOperator   = "$($p.grantControls.operator)"
                GrantControls   = ($p.grantControls.builtInControls -join '; ')
                AuthenticationStrength = "$($p.grantControls.authenticationStrength.displayName)"
                SessionControls = ($p.grantControls.sessionControls | ConvertTo-Json -Depth 4 -Compress)
                ConditionsJson  = ($p.conditions | ConvertTo-Json -Depth 6 -Compress)
            }
        }
        Export-CsvSafe -Data $caRows -Name 'ConditionalAccess.csv'
        $script:Summary.metrics.conditionalAccessCount = $caRows.Count
        $script:Summary.metrics.caEnabledCount = @($caRows | Where-Object State -eq 'enabled').Count
    } catch {
        Write-Log "Conditional Access could not be fetched (requires P1): $($_.Exception.Message)" -Level WARN
        $script:Summary.metrics.conditionalAccessCount = 0
    }
    }

    # Named locations (trusted IPs / countries used by Conditional Access)
    # https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-list-namedlocations
    try {
        $nl = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations'
        $nlRows = foreach ($l in $nl) {
            $isIp = $l.'@odata.type' -match 'ipNamedLocation'
            [pscustomobject]@{
                Id                = $l.id
                DisplayName       = $l.displayName
                Type              = if ($isIp) { 'ip' } elseif ($l.'@odata.type' -match 'countryNamedLocation') { 'country' } else { "$($l.'@odata.type')" }
                IsTrusted         = [bool]$l.isTrusted
                IpRanges          = (($l.ipRanges | ForEach-Object cidrAddress) -join '; ')
                CountriesAndRegions = ($l.countriesAndRegions -join '; ')
                IncludeUnknownCountriesAndRegions = [bool]$l.includeUnknownCountriesAndRegions
                CreatedDateTime   = $l.createdDateTime
                ModifiedDateTime  = $l.modifiedDateTime
            }
        }
        Export-CsvSafe -Data $nlRows -Name 'NamedLocations.csv'
        $script:Summary.metrics.namedLocationCount = $nlRows.Count
        $script:Summary.metrics.trustedIpLocationCount = @($nlRows | Where-Object { $_.Type -eq 'ip' -and $_.IsTrusted }).Count
    } catch {
        Write-Log "Named locations could not be fetched: $($_.Exception.Message)" -Level WARN
        $script:Summary.metrics.namedLocationCount = 0
    }

    # Authentication methods policy (which methods the tenant allows / registration campaign)
    # https://learn.microsoft.com/en-us/graph/api/authenticationmethodspolicy-get
    try {
        $amp = Invoke-MgGraphRequest -OutputType PSObject -Method GET -Uri 'https://graph.microsoft.com/v1.0/policies/authenticationMethodsPolicy'
        $amRows = foreach ($c in @($amp.authenticationMethodConfigurations)) {
            [pscustomobject]@{
                Id            = $c.id
                MethodType    = "$($c.'@odata.type')" -replace '#microsoft\.graph\.', '' -replace 'AuthenticationMethodConfiguration$', ''
                State         = "$($c.state)"
                IncludeTargets = (@($c.includeTargets) | ForEach-Object { "$($_.id):$($_.targetType)" }) -join '; '
            }
        }
        if ($amp.registrationEnforcement) {
            $rc = $amp.registrationEnforcement.authenticationMethodsRegistrationCampaign
            $amRows += [pscustomobject]@{ Id = 'registrationCampaign'; MethodType = 'registrationCampaign'; State = "$($rc.state)"; IncludeTargets = ($rc.includeTargets | ForEach-Object { "$($_.id):$($_.targetType)" }) -join '; ' }
        }
        if ($amp.systemCredentialPreferences) {
            $amRows += [pscustomobject]@{ Id = 'systemCredentialPreferences'; MethodType = 'systemPreferredMfa'; State = "$($amp.systemCredentialPreferences.state)"; IncludeTargets = '' }
        }
        Export-CsvSafe -Data $amRows -Name 'AuthMethodsPolicy.csv'
        foreach ($k in 'microsoftAuthenticator','fido2','temporaryAccessPass','sms') {
            $hit = @($amRows | Where-Object { $_.MethodType -match $k } | Select-Object -First 1)
            $script:Summary.metrics["authMethod_$k"] = if ($hit) { $hit[0].State } else { 'unknown' }
        }
    } catch {
        Write-Log "Authentication methods policy could not be fetched: $($_.Exception.Message)" -Level WARN
    }

    # Security defaults
    try {
        $sd = Invoke-MgGraphRequest -OutputType PSObject -Method GET -Uri 'https://graph.microsoft.com/v1.0/policies/identitySecurityDefaultsEnforcementPolicy'
        $script:Summary.metrics.securityDefaultsEnabled = [bool]$sd.isEnabled
    } catch {
        $script:Summary.metrics.securityDefaultsEnabled = $null
    }

    # MFA-registrering
    if (-not $entraP1) {
        $script:Summary.skippedSections['MfaRegistration'] = "Not collected: no license for Entra ID P1 in the tenant (servicePlan AAD_PREMIUM not found among active licenses)"
        return
    }
    $mfa = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/reports/authenticationMethods/userRegistrationDetails?$top=999'
    $mfaRows = foreach ($m in $mfa) {
        [pscustomobject]@{
            Id                = $m.id
            UserPrincipalName = $m.userPrincipalName
            UserDisplayName   = $m.userDisplayName
            UserType          = $m.userType
            IsAdmin           = $m.isAdmin
            IsMfaRegistered   = $m.isMfaRegistered
            IsMfaCapable      = $m.isMfaCapable
            IsSsprRegistered  = $m.isSsprRegistered
            MethodsRegistered = ($m.methodsRegistered -join '; ')
        }
    }
    Export-CsvSafe -Data $mfaRows -Name 'MfaRegistration.csv'
    $script:Summary.metrics.mfaRegisteredCount = @($mfaRows | Where-Object IsMfaRegistered).Count
    $script:Summary.metrics.mfaTotalCount      = $mfaRows.Count
}

$script:MicrosoftTenantId = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'

function Invoke-Apps {
    $apps = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/applications?$select=id,appId,displayName,createdDateTime,signInAudience,keyCredentials,passwordCredentials&$top=999'
    $appRows = foreach ($a in $apps) {
        $credExpiry = @()
        foreach ($k in @($a.keyCredentials))    { if ($k.endDateTime) { $credExpiry += $k.endDateTime } }
        foreach ($p in @($a.passwordCredentials)){ if ($p.endDateTime) { $credExpiry += $p.endDateTime } }
        $nextExpiry = ($credExpiry | Sort-Object | Select-Object -First 1)
        [pscustomobject]@{
            Id                 = $a.id
            AppId              = $a.appId
            DisplayName        = $a.displayName
            CreatedDateTime    = $a.createdDateTime
            SignInAudience     = $a.signInAudience
            CredentialCount    = @($a.keyCredentials).Count + @($a.passwordCredentials).Count
            NextCredentialExpiry = $nextExpiry
        }
    }
    Export-CsvSafe -Data $appRows -Name 'AppRegistrations.csv'

    $sps = Get-GraphAll -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$select=id,appId,displayName,appOwnerOrganizationId,servicePrincipalType,preferredSingleSignOnMode,accountEnabled,tags,createdDateTime&`$top=999"
    $spRows = foreach ($sp in ($sps | Where-Object { $_.appOwnerOrganizationId -ne $script:MicrosoftTenantId })) {
        [pscustomobject]@{
            Id                        = $sp.id
            AppId                     = $sp.appId
            DisplayName               = $sp.displayName
            ServicePrincipalType      = $sp.servicePrincipalType
            AppOwnerOrganizationId    = $sp.appOwnerOrganizationId
            PreferredSingleSignOnMode = $sp.preferredSingleSignOnMode
            AccountEnabled            = $sp.accountEnabled
            Tags                      = ($sp.tags -join '; ')
            CreatedDateTime           = $sp.createdDateTime
        }
    }
    Export-CsvSafe -Data $spRows -Name 'EnterpriseApps.csv'
    $script:Summary.metrics.appRegistrationCount = $appRows.Count
    $script:Summary.metrics.enterpriseAppCount   = $spRows.Count
    $script:Summary.metrics.ssoSamlApps          = @($spRows | Where-Object { $_.PreferredSingleSignOnMode -eq 'saml' }).Count
    $script:Summary.metrics.ssoOidcApps          = @($spRows | Where-Object { $_.PreferredSingleSignOnMode -eq 'oidc' }).Count

    try {
        $grants = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants?$select=clientId'
        $script:Summary.metrics.oauth2GrantClients = @($grants | Group-Object clientId).Count
    } catch {}
}

function Invoke-AppSignIns {
    # Last sign-in per type for every service principal (incl. first-party and
    # managed identities), from the Entra sign-in logs (beta) plus the service
    # principal sign-in activity report (preview). Source role only.
    $windowStart    = [datetime]::UtcNow.AddDays(-$SignInLookbackDays)
    $windowStartIso = $windowStart.ToString('o')
    $script:Summary.metrics.appSignInWindowDays = $SignInLookbackDays

    # 1. All service principals
    $sps = Get-GraphAll -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$select=id,appId,displayName,servicePrincipalType,appOwnerOrganizationId,accountEnabled,preferredSingleSignOnMode,tags&`$top=999"
    $spList = @(foreach ($sp in $sps) {
        [pscustomobject]@{
            id                        = $sp.id
            appId                     = $sp.appId
            displayName               = $sp.displayName
            ServicePrincipalType      = "$($sp.servicePrincipalType)"
            IsMicrosoftFirstParty     = ("$($sp.appOwnerOrganizationId)" -eq $script:MicrosoftTenantId)
            IsManagedIdentity         = ("$($sp.servicePrincipalType)" -eq 'ManagedIdentity')
            AccountEnabled            = $sp.accountEnabled
            PreferredSingleSignOnMode = "$($sp.preferredSingleSignOnMode)"
        }
    })

    # 2. Activity report (beta, preview) - last activity ever per app
    $reportUnavailable = $false
    $actMap = @{}
    try {
        $acts = Get-GraphAll -Uri 'https://graph.microsoft.com/beta/reports/servicePrincipalSignInActivities'
        foreach ($a in $acts) {
            $d1 = "$($a.lastSignInActivity.lastSignInDateTime)"
            $d2 = "$($a.delegatedClientSignInActivity.lastSignInDateTime)"
            $d3 = "$($a.delegatedResourceSignInActivity.lastSignInDateTime)"
            $d4 = "$($a.applicationAuthenticationClientSignInActivity.lastSignInDateTime)"
            $d5 = "$($a.applicationAuthenticationResourceSignInActivity.lastSignInDateTime)"
            $latest = @(@($d1, $d2, $d3, $d4, $d5) | Where-Object { $_ } | ForEach-Object { [datetime]$_ } | Sort-Object -Descending | Select-Object -First 1)
            if ($latest.Count -gt 0) { $latest = $latest[0] } else { $latest = $null }
            $actMap[$a.appId] = [pscustomobject]@{
                LastActivityReport    = $d1
                LastDelegatedClient   = $d2
                LastDelegatedResource = $d3
                LastAppOnlyClient     = $d4
                LastAppOnlyResource   = $d5
                LastActivityDate      = $latest
            }
        }
    } catch {
        if (Test-GraphForbidden $_) {
            Write-Log "servicePrincipalSignInActivities not accessible (403/no licence) - continuing without the activity report." -Level WARN
            $reportUnavailable = $true
        } else { throw }
    }
    $script:Summary.metrics.spSignInActivityUnavailable = $reportUnavailable

    # 3. Sign-in logs per type, only for candidates
    $logsUnavailable = $false
    $lastByType = @{}
    $plan = Get-AppSignInQueryPlan -ServicePrincipals $spList -ActivityByAppId $actMap -WindowStart $windowStart -ReportUnavailable:$reportUnavailable
    $byApp = @($plan | Group-Object AppId)
    $i = 0
    :apps foreach ($g in $byApp) {
        if ($logsUnavailable) { break }
        $i++
        if (($i % 50) -eq 0) { Write-Log "  App sign-in logs $i/$($byApp.Count)" }
        foreach ($q in $g.Group) {
            $uri = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=appId eq '$($q.AppId)' and createdDateTime ge $windowStartIso and signInEventTypes/any(t: t eq '$($q.EventType)')&`$top=1&`$select=createdDateTime"
            try {
                $hit = Invoke-GraphFirst -Uri $uri
                if ($hit -and $hit.createdDateTime) {
                    if (-not $lastByType[$q.AppId]) { $lastByType[$q.AppId] = @{} }
                    $lastByType[$q.AppId][$q.EventType] = [datetime]$hit.createdDateTime
                }
            } catch {
                if (Test-GraphForbidden $_) {
                    Write-Log "Sign-in logs not accessible (403/no licence - Entra ID P1 required). Remaining queries skipped." -Level WARN
                    $logsUnavailable = $true
                    break apps
                }
                Write-Log "Sign-in query failed for appId $($q.AppId) ($($q.EventType)): $($_.Exception.Message)" -Level WARN
            }
        }
    }
    $script:Summary.metrics.signInLogsUnavailable = $logsUnavailable

    # 4. Write AppSignInActivity.csv (no user names stored)
    $rows = foreach ($sp in $spList) {
        $lt  = $lastByType[$sp.appId]
        $act = $actMap[$sp.appId]
        $mi  = $sp.IsManagedIdentity
        $fmt = { param($d) if ($d) { ([datetime]$d).ToUniversalTime().ToString('o') } else { '' } }
        $lInt = if ($mi) { 'n/a' } elseif ($lt -and $lt['interactiveUser'])     { & $fmt $lt['interactiveUser'] }     else { '' }
        $lNon = if ($mi) { 'n/a' } elseif ($lt -and $lt['nonInteractiveUser'])  { & $fmt $lt['nonInteractiveUser'] }  else { '' }
        $lSpn = if ($mi) { 'n/a' } elseif ($lt -and $lt['servicePrincipal'])    { & $fmt $lt['servicePrincipal'] }    else { '' }
        $lMi  = if (-not $mi) { 'n/a' } elseif ($lt -and $lt['managedIdentity']) { & $fmt $lt['managedIdentity'] }    else { '' }
        $logDates = @()
        if ($lt) { $logDates = @($lt.Values) }
        $repDates = @()
        $maxRep = $null
        if ($act) {
            $repDates = @($act.LastActivityReport, $act.LastDelegatedClient, $act.LastDelegatedResource, $act.LastAppOnlyClient, $act.LastAppOnlyResource | Where-Object { $_ } | ForEach-Object { [datetime]$_ })
            $maxRep = $act.LastActivityDate
        }
        $all = @($logDates) + @($repDates)
        $lastSeen = $null
        if ($all.Count -gt 0) { $lastSeen = @($all | Sort-Object -Descending | Select-Object -First 1)[0] }
        $status = Get-AppSignInStatus -LogDates $logDates -LastReportDate $maxRep -WindowStart $windowStart -LogsUnavailable:$logsUnavailable -ReportUnavailable:$reportUnavailable
        [pscustomobject]@{
            ServicePrincipalId       = $sp.id
            AppId                    = $sp.appId
            DisplayName              = $sp.displayName
            ServicePrincipalType     = $sp.ServicePrincipalType
            IsMicrosoftFirstParty    = $sp.IsMicrosoftFirstParty
            IsManagedIdentity        = $sp.IsManagedIdentity
            AccountEnabled           = $sp.AccountEnabled
            PreferredSingleSignOnMode= $sp.PreferredSingleSignOnMode
            Status                   = $status
            LastSeenAny              = if ($lastSeen) { & $fmt $lastSeen } else { '' }
            DaysSinceLastSeen        = if ($lastSeen) { [int]([datetime]::UtcNow - $lastSeen).TotalDays } else { '' }
            LastInteractiveUser      = $lInt
            LastNonInteractiveUser   = $lNon
            LastServicePrincipal     = $lSpn
            LastManagedIdentity      = $lMi
            LastActivityReport       = if ($act) { & $fmt $act.LastActivityReport } else { '' }
            LastDelegatedClient      = if ($act) { & $fmt $act.LastDelegatedClient } else { '' }
            LastDelegatedResource    = if ($act) { & $fmt $act.LastDelegatedResource } else { '' }
            LastAppOnlyClient        = if ($act) { & $fmt $act.LastAppOnlyClient } else { '' }
            LastAppOnlyResource      = if ($act) { & $fmt $act.LastAppOnlyResource } else { '' }
            EntraPortalUrl           = "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/ManagedAppMenuBlade/~/Overview/objectId/$($sp.id)/appId/$($sp.appId)"
        }
    }
    Export-CsvSafe -Data $rows -Name 'AppSignInActivity.csv'

    # 5. Metrics
    foreach ($g in (@($rows) | Group-Object Status)) { $script:Summary.metrics["appStatus_$($g.Name)"] = $g.Count }
    $script:Summary.metrics.appsActiveInWindowNonMicrosoft    = @($rows | Where-Object { $_.Status -eq 'ActiveInWindow' -and -not $_.IsMicrosoftFirstParty }).Count
    $script:Summary.metrics.managedIdentitiesActiveInWindow   = @($rows | Where-Object { $_.Status -eq 'ActiveInWindow' -and $_.IsManagedIdentity }).Count
}

function Invoke-Exchange {
    if (-not $script:ExoConnected) {
        Invoke-ExchangeFallback
        return
    }
    $mbxProps = @('RecipientTypeDetails','PrimarySmtpAddress','EmailAddresses','ArchiveStatus','ArchiveGuid',
        'LitigationHoldEnabled','InPlaceHolds','ComplianceTagHoldApplied','RetentionHoldEnabled','DelayHoldApplied',
        'ForwardingSmtpAddress','ForwardingAddress','DeliverToMailboxAndForward',
        'HiddenFromAddressListsEnabled','RetentionPolicy','WhenCreated','ProhibitSendReceiveQuota','UserPrincipalName',
        'GrantSendOnBehalfTo','DisplayName','Alias','ExchangeGuid',
        'AutoExpandingArchiveEnabled','DisabledArchiveGuid','ArchiveQuota','ArchiveWarningQuota')
    Write-Log "Fetching all mailboxes (may take a while)..."
    $mailboxes = Get-EXOMailbox -ResultSize Unlimited -Properties $mbxProps

    # If DisabledArchiveGuid is not returned by Get-EXOMailbox, fall back to a single
    # Get-Mailbox pass (read-only) so the readiness report can spot demoted archives.
    $disabledArchiveMap = @{}
    if ($mailboxes.Count -gt 0 -and -not ($mailboxes[0].PSObject.Properties.Name -contains 'DisabledArchiveGuid')) {
        Write-Log "DisabledArchiveGuid not returned by Get-EXOMailbox - falling back to Get-Mailbox." -Level WARN
        try {
            Get-Mailbox -ResultSize Unlimited -ErrorAction Stop |
                ForEach-Object { if ($_.DisabledArchiveGuid -and "$($_.DisabledArchiveGuid)" -notmatch '^0{8}-') { $disabledArchiveMap[[string]$_.ExchangeGuid] = [string]$_.DisabledArchiveGuid } }
        } catch { Write-Log "Get-Mailbox DisabledArchiveGuid fallback failed: $($_.Exception.Message)" -Level WARN }
    }
    $script:Summary.metrics.holdsUnknown = $false
    # DelayReleaseHoldApplied is not supported by Get-EXOMailbox -Properties; fetched via Get-Mailbox for all
    $delayRelease = @{}
    try {
        Get-Mailbox -ResultSize Unlimited -Filter 'DelayReleaseHoldApplied -eq $true' -ErrorAction Stop |
            ForEach-Object { $delayRelease[[string]$_.ExchangeGuid] = $true }
    } catch { Write-Log "DelayReleaseHoldApplied could not be fetched: $($_.Exception.Message)" -Level WARN }

    $stats = @{}
    $statRows = [System.Collections.Generic.List[object]]::new()
    $auxWarnLogged = $false
    $i = 0
    foreach ($m in $mailboxes) {
        $i++
        if (($i % 50) -eq 0) { Write-Log "  MailboxStatistics $i/$($mailboxes.Count)" }
        try {
            $s = Get-EXOMailboxStatistics -Identity $m.ExchangeGuid.Guid -ErrorAction Stop
            $sizeGB = ConvertTo-GB $s.TotalItemSize
            $stats[$m.ExchangeGuid.Guid] = $sizeGB
            $row = [ordered]@{
                UserPrincipalName    = $m.UserPrincipalName
                DisplayName          = $m.DisplayName
                TotalItemSizeGB      = $sizeGB
                ItemCount            = $s.ItemCount
                LastUserActionTime   = $s.LastUserActionTime
                ArchiveItemSizeGB    = $null
                ArchiveItemCount     = $null
                AuxArchiveCount      = $null
            }
            if ($m.ArchiveStatus -eq 'Active') {
                try {
                    $a = Get-EXOMailboxStatistics -Identity $m.ExchangeGuid.Guid -Archive -ErrorAction Stop
                    $row.ArchiveItemSizeGB = ConvertTo-GB $a.TotalItemSize
                    $row.ArchiveItemCount = $a.ItemCount
                } catch {}
            }
            if ($m.ArchiveStatus -eq 'Active' -or $m.AutoExpandingArchiveEnabled) {
                try {
                    $loc = @(Get-MailboxLocation -Identity $m.ExchangeGuid.Guid -MailboxLocationType AuxArchive -ErrorAction Stop)
                    $row.AuxArchiveCount = $loc.Count
                } catch {
                    $row.AuxArchiveCount = $null
                    if (-not $auxWarnLogged) {
                        Write-Log "Get-MailboxLocation AuxArchive failed (counting disabled): $($_.Exception.Message)" -Level WARN
                        $auxWarnLogged = $true
                    }
                }
            }
            $statRows.Add([pscustomobject]$row)
        } catch {
            Write-Log "Statistics failed for $($m.UserPrincipalName): $($_.Exception.Message)" -Level WARN
        }
    }
    Export-CsvSafe -Data $statRows.ToArray() -Name 'MailboxStatistics.csv'

    $statAux = @{}
    foreach ($sr in $statRows) { $statAux[$sr.UserPrincipalName] = $sr.AuxArchiveCount }

    $mbxRows = foreach ($m in $mailboxes) {
        $holdReasons = [System.Collections.Generic.List[string]]::new()
        if ($m.LitigationHoldEnabled) { $holdReasons.Add('LitigationHold') }
        if (@($m.InPlaceHolds).Count -gt 0) { $holdReasons.Add('InPlaceHold/eDiscovery') }
        if ($m.ComplianceTagHoldApplied) { $holdReasons.Add('ComplianceTagHold') }
        if ($m.RetentionHoldEnabled) { $holdReasons.Add('RetentionHold') }
        if ($m.DelayHoldApplied) { $holdReasons.Add('DelayHold') }
        if ($delayRelease.ContainsKey([string]$m.ExchangeGuid)) { $holdReasons.Add('DelayReleaseHold') }
        $sizeGB = $stats[$m.ExchangeGuid.Guid]
        [pscustomobject]@{
            UserPrincipalName         = $m.UserPrincipalName
            DisplayName               = $m.DisplayName
            Alias                     = $m.Alias
            RecipientTypeDetails      = "$($m.RecipientTypeDetails)"
            PrimarySmtpAddress        = $m.PrimarySmtpAddress
            EmailAddresses            = ($m.EmailAddresses -join '; ')
            TotalItemSizeGB           = $sizeGB
            ArchiveStatus             = "$($m.ArchiveStatus)"
            ArchiveGuid               = $m.ArchiveGuid
            AutoExpandingArchiveEnabled = [bool]$m.AutoExpandingArchiveEnabled
            DisabledArchiveGuid       = if ($m.PSObject.Properties.Name -contains 'DisabledArchiveGuid') { "$($m.DisabledArchiveGuid)" } else { "$($disabledArchiveMap[[string]$m.ExchangeGuid])" }
            ArchiveQuota              = "$($m.ArchiveQuota)"
            ArchiveWarningQuota       = "$($m.ArchiveWarningQuota)"
            AuxArchiveCount           = $statAux[$m.UserPrincipalName]
            HasAnyHold                = ($holdReasons.Count -gt 0)
            HoldReasons               = ($holdReasons -join '; ')
            LitigationHoldEnabled     = $m.LitigationHoldEnabled
            InPlaceHolds              = (@($m.InPlaceHolds) -join '; ')
            ForwardingSmtpAddress     = "$($m.ForwardingSmtpAddress)"
            ForwardingAddress         = "$($m.ForwardingAddress)"
            DeliverToMailboxAndForward= $m.DeliverToMailboxAndForward
            HiddenFromAddressListsEnabled = $m.HiddenFromAddressListsEnabled
            RetentionPolicy           = "$($m.RetentionPolicy)"
            GrantSendOnBehalfTo       = (@($m.GrantSendOnBehalfTo) -join '; ')
            WhenCreated               = $m.WhenCreated
            ProhibitSendReceiveQuota  = "$($m.ProhibitSendReceiveQuota)"
            IsLarge50GB               = ($sizeGB -gt 50)
            IsLarge100GB              = ($sizeGB -gt 100)
        }
    }
    Export-CsvSafe -Data $mbxRows -Name 'Mailboxes.csv'

    $holdRows = @($mbxRows | Where-Object HasAnyHold)
    if ($holdRows.Count -gt 0) { Export-CsvSafe -Data $holdRows -Name 'MailboxHolds.csv' }

    # Permissions on shared/resource mailboxes
    $shared = @($mailboxes | Where-Object { "$($_.RecipientTypeDetails)" -in 'SharedMailbox','RoomMailbox','EquipmentMailbox' })
    $permRows = [System.Collections.Generic.List[object]]::new()
    foreach ($m in $shared) {
        try {
            foreach ($p in (Get-EXOMailboxPermission -Identity $m.ExchangeGuid.Guid | Where-Object { -not $_.IsInherited -and $_.User -notmatch 'NT AUTHORITY\\SELF' })) {
                $permRows.Add([pscustomobject]@{
                    Mailbox       = $m.UserPrincipalName
                    MailboxType   = "$($m.RecipientTypeDetails)"
                    User          = "$($p.User)"
                    AccessRights  = ($p.AccessRights -join '; ')
                    Deny          = $p.Deny
                })
            }
        } catch {}
    }
    if ($permRows.Count -gt 0) { Export-CsvSafe -Data $permRows.ToArray() -Name 'MailboxPermissions.csv' }

    try {
        $sendAs = foreach ($m in $mailboxes) {
            Get-EXORecipientPermission -Identity $m.ExchangeGuid.Guid -ErrorAction SilentlyContinue |
                Where-Object { $_.Trustee -notmatch 'NT AUTHORITY\\SELF' } |
                ForEach-Object { [pscustomobject]@{ Mailbox = $m.UserPrincipalName; Trustee = "$($_.Trustee)"; AccessRights = ($_.AccessRights -join '; ') } }
        }
        if ($sendAs) { Export-CsvSafe -Data @($sendAs) -Name 'SendAsPermissions.csv' }
    } catch {}

    # Distributionsgrupper
    $dgRows = foreach ($dg in (Get-DistributionGroup -ResultSize Unlimited)) {
        $mc = $null
        try { $mc = @(Get-DistributionGroupMember -Identity $dg.Identity -ResultSize Unlimited).Count } catch {}
        [pscustomobject]@{
            Name              = $dg.DisplayName
            Alias             = $dg.Alias
            PrimarySmtpAddress= $dg.PrimarySmtpAddress
            GroupType         = "$($dg.GroupType)"
            RecipientTypeDetails = "$($dg.RecipientTypeDetails)"
            MemberCount       = $mc
            ManagedBy         = (@($dg.ManagedBy) -join '; ')
            HiddenFromAddressLists = $dg.HiddenFromAddressListsEnabled
        }
    }
    $ddgRows = foreach ($ddg in (Get-DynamicDistributionGroup -ResultSize Unlimited -ErrorAction SilentlyContinue)) {
        [pscustomobject]@{
            Name               = $ddg.DisplayName
            Alias              = $ddg.Alias
            PrimarySmtpAddress = $ddg.PrimarySmtpAddress
            GroupType          = 'DynamicDistribution'
            RecipientTypeDetails = "$($ddg.RecipientTypeDetails)"
            MemberCount        = $null
            ManagedBy          = (@($ddg.ManagedBy) -join '; ')
            HiddenFromAddressLists = $null
            RecipientFilter    = $ddg.RecipientFilter
        }
    }
    $allDg = @($dgRows) + @($ddgRows)
    if ($allDg.Count -gt 0) { Export-CsvSafe -Data $allDg -Name 'DistributionGroups.csv' }

    $contacts = Get-MailContact -ResultSize Unlimited -ErrorAction SilentlyContinue |
        Select-Object DisplayName, Alias, PrimarySmtpAddress, ExternalEmailAddress, HiddenFromAddressListsEnabled
    if ($contacts) { Export-CsvSafe -Data @($contacts) -Name 'MailContacts.csv' }

    $mailUsers = Get-MailUser -ResultSize Unlimited -ErrorAction SilentlyContinue |
        Select-Object DisplayName, Alias, UserPrincipalName, PrimarySmtpAddress, ExternalEmailAddress
    if ($mailUsers) { Export-CsvSafe -Data @($mailUsers) -Name 'MailUsers.csv' }

    Export-CsvSafe -Data @(Get-AcceptedDomain | Select-Object DomainName, DomainType, Default, InitiallyProvisioned) -Name 'AcceptedDomains.csv'
    $inConn = @(Get-InboundConnector -ErrorAction SilentlyContinue | Select-Object Name, Enabled, ConnectorType, SenderDomains, SenderIPAddresses, RequireTls, TlsSenderCertificateName)
    if ($inConn) { Export-CsvSafe -Data $inConn -Name 'InboundConnectors.csv' }
    $outConn = @(Get-OutboundConnector -ErrorAction SilentlyContinue | Select-Object Name, Enabled, ConnectorType, RecipientDomains, SmartHosts, UseMxRecord, TlsSettings)
    if ($outConn) { Export-CsvSafe -Data $outConn -Name 'OutboundConnectors.csv' }
    $trules = @(Get-TransportRule -ErrorAction SilentlyContinue | Select-Object Name, State, Priority, Mode, Description)
    if ($trules) { Export-CsvSafe -Data $trules -Name 'TransportRules.csv' }
    $jrules = @(Get-JournalRule -ErrorAction SilentlyContinue | Select-Object Name, Enabled, JournalEmailAddress, Scope, Recipient)
    if ($jrules) { Export-CsvSafe -Data $jrules -Name 'JournalRules.csv' }
    $dkim = @(Get-DkimSigningConfig -ErrorAction SilentlyContinue | Select-Object Domain, Enabled, Status, Selector1CNAME, Selector2CNAME)
    if ($dkim) { Export-CsvSafe -Data $dkim -Name 'DkimSigningConfig.csv' }
    $rd = @(Get-RemoteDomain -ErrorAction SilentlyContinue | Select-Object DomainName, AutoReplyEnabled, AutoForwardEnabled, AllowedOOFType, TNEFEnabled)
    if ($rd) { Export-CsvSafe -Data $rd -Name 'RemoteDomains.csv' }
    $orgRel = @(Get-OrganizationRelationship -ErrorAction SilentlyContinue | Select-Object Name, DomainNames, FreeBusyAccessEnabled, MailboxMoveEnabled, Enabled)
    if ($orgRel) { Export-CsvSafe -Data $orgRel -Name 'OrganizationRelationships.csv' }
    $migEp = @(Get-MigrationEndpoint -ErrorAction SilentlyContinue | Select-Object Identity, EndpointType, RemoteServer, ExchangeRemoteMoveAutodiscoverEmailAddress)
    if ($migEp) { Export-CsvSafe -Data $migEp -Name 'MigrationEndpoints.csv' }

    try {
        $orgConfig = Get-OrganizationConfig -ErrorAction Stop
        $script:Summary.metrics.publicFoldersEnabled = [bool]$orgConfig.PublicFoldersEnabled
        $script:Summary.metrics.orgAutoExpandingArchive = [bool]$orgConfig.AutoExpandingArchiveEnabled
        $pfMbx = @(Get-Mailbox -PublicFolder -ErrorAction SilentlyContinue)
        if ($pfMbx) { Export-CsvSafe -Data @($pfMbx | Select-Object DisplayName, PrimarySmtpAddress) -Name 'PublicFolderMailboxes.csv' }
    } catch {}

    try {
        # SchedulingMailbox = Bookings mailboxes (read-only detection for the readiness report)
        $bookings = @(Get-EXOMailbox -RecipientTypeDetails SchedulingMailbox -ResultSize Unlimited -ErrorAction SilentlyContinue |
            Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails)
        if ($bookings) { Export-CsvSafe -Data @($bookings) -Name 'BookingsMailboxes.csv' }
        $script:Summary.metrics.bookingsMailboxCount = $bookings.Count
    } catch { Write-Log "Bookings mailbox check failed: $($_.Exception.Message)" -Level WARN }

    try {
        # Customer Key indicator: an enabled Exchange DEP blocks nothing here but is reported
        # alongside the SharePoint DEP - Customer Key on the source blocks OneDrive/SPO moves.
        if (Get-Command Get-DataEncryptionPolicy -ErrorAction SilentlyContinue) {
            $dep = @(Get-DataEncryptionPolicy -ErrorAction SilentlyContinue | Select-Object Name, Identity, Enabled, State)
            if ($dep) {
                $rows = @($dep | ForEach-Object { [pscustomobject]@{ Service = 'Exchange'; Name = "$($_.Name)"; Enabled = "$($_.Enabled)"; State = "$($_.State)" } })
                $existing = Join-Path $attachDir 'CustomerKey.csv'
                if (Test-Path $existing) { $rows = @(Import-Csv $existing) + $rows }
                Export-CsvSafe -Data $rows -Name 'CustomerKey.csv'
                $script:Summary.metrics.customerKeyExchange = $true
            }
        }
    } catch { Write-Log "Get-DataEncryptionPolicy failed: $($_.Exception.Message)" -Level WARN }

    # Summary metrics
    $script:Summary.metrics.mailboxCount = $mbxRows.Count
    $mbxByType = @{}
    foreach ($t in ($mbxRows | Group-Object RecipientTypeDetails)) { $mbxByType[$t.Name] = $t.Count }
    $script:Summary.metrics.mailboxesByType = $mbxByType
    $script:Summary.metrics.totalMailboxGB = [math]::Round(($mbxRows | Measure-Object TotalItemSizeGB -Sum).Sum, 2)
    $script:Summary.metrics.totalArchiveGB = [math]::Round(($statRows | Measure-Object ArchiveItemSizeGB -Sum).Sum, 2)
    $script:Summary.metrics.archiveMailboxCount = @($mbxRows | Where-Object { $_.ArchiveStatus -eq 'Active' }).Count
    $script:Summary.metrics.autoExpandingArchiveCount = @($mbxRows | Where-Object AutoExpandingArchiveEnabled).Count
    $script:Summary.metrics.auxArchiveMailboxCount = @($mbxRows | Where-Object { $_.AuxArchiveCount -gt 0 }).Count
    $script:Summary.metrics.disabledArchiveCount = @($mbxRows | Where-Object { $_.DisabledArchiveGuid -and $_.DisabledArchiveGuid -notmatch '^0{8}-0{4}-0{4}-0{4}-0{12}$' -and $_.DisabledArchiveGuid -ne "$($_.ArchiveGuid)" }).Count
    $script:Summary.metrics.mailboxesWithHolds = $holdRows.Count
    $script:Summary.metrics.mailboxesOver50GB  = @($mbxRows | Where-Object IsLarge50GB).Count
    $script:Summary.metrics.mailboxesOver100GB = @($mbxRows | Where-Object IsLarge100GB).Count
    $script:Summary.metrics.sharedMailboxCount = @($mbxRows | Where-Object { $_.RecipientTypeDetails -in 'SharedMailbox','RoomMailbox','EquipmentMailbox' }).Count
    $script:Summary.metrics.externalForwardingCount = @($mbxRows | Where-Object { $_.ForwardingSmtpAddress -match '\S' }).Count
    $script:Summary.metrics.inboundConnectorCount  = $inConn.Count
    $script:Summary.metrics.outboundConnectorCount = $outConn.Count
    $script:Summary.metrics.transportRuleCount = $trules.Count
    $script:Summary.metrics.journalRuleCount   = $jrules.Count
    $script:Summary.metrics.distributionGroupCount = $allDg.Count
    $script:Summary.metrics.mailUserCount = @($mailUsers).Count
}

function Invoke-Purview {
    if (-not $script:IppsConnected) {
        # Graph fallback: eDiscovery cases and legal holds (v1.0, requires eDiscovery.Read.All)
        Write-Log "Purview: IPPS not connected - fetching eDiscovery data via Graph."
        try {
            $cases = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/security/cases/ediscoveryCases?$select=id,displayName,status,createdDateTime,description&$top=999'
            $caseRows = @($cases | ForEach-Object {
                [pscustomobject]@{ Id=$_.id; Name=$_.displayName; Status="$($_.status)"; CreatedDateTime=$_.createdDateTime; Description=$_.description; Source='Graph-fallback' }
            })
            if ($caseRows) { Export-CsvSafe -Data $caseRows -Name 'EDiscoveryCases.csv' }
            $holdRows = [System.Collections.Generic.List[object]]::new()
            foreach ($c in $cases) {
                try {
                    foreach ($h in (Get-GraphAll -Uri "https://graph.microsoft.com/v1.0/security/cases/ediscoveryCases/$($c.id)/legalHolds?`$select=id,displayName,status,isEnabled,createdDateTime")) {
                        $holdRows.Add([pscustomobject]@{ CaseName=$c.displayName; CaseStatus="$($c.status)"; HoldId=$h.id; HoldName=$h.displayName; Enabled=$h.isEnabled; Status="$($h.status)"; CreatedDateTime=$h.createdDateTime; Source='Graph-fallback' })
                    }
                } catch { Write-Log "legalHolds for case '$($c.displayName)' failed: $($_.Exception.Message)" -Level WARN }
            }
            if ($holdRows.Count -gt 0) { Export-CsvSafe -Data $holdRows.ToArray() -Name 'EDiscoveryHolds.csv' }
            $script:Summary.metrics.complianceCaseCount = $caseRows.Count
            $script:Summary.metrics.ediscoveryHoldCount = $holdRows.Count
            $script:Summary.metrics.fallbackUsed = $true
            $script:Summary.skippedSections['RetentionPolicies'] = 'Not available via Graph fallback (requires an IPPS connection)'
        } catch {
            Write-Log "eDiscovery via Graph failed (403?): $($_.Exception.Message)" -Level ERROR
            $script:Summary.failedSections['Purview'] = "IPPS not connected and Graph fallback failed: $($_.Exception.Message)"
        }
        return
    }
    $policies = @(Get-RetentionCompliancePolicy -DistributionDetail -ErrorAction SilentlyContinue |
        Select-Object Name, Enabled, Mode, ExchangeLocation, SharePointLocation, OneDriveLocation,
                      TeamsChannelLocation, TeamsChatLocation, ModernGroupLocation)
    if ($policies) { Export-CsvSafe -Data $policies -Name 'RetentionPolicies.csv' }

    $rules = @(Get-RetentionComplianceRule -ErrorAction SilentlyContinue |
        Select-Object Name, Policy, RetentionDuration, RetentionComplianceAction, ApplyComplianceTag)
    if ($rules) { Export-CsvSafe -Data $rules -Name 'RetentionRules.csv' }

    $cases = @(Get-ComplianceCase -ErrorAction SilentlyContinue | Select-Object Identity, Name, Status, CaseType)
    $holdRows = [System.Collections.Generic.List[object]]::new()
    foreach ($c in $cases) {
        try {
            foreach ($h in (Get-CaseHoldPolicy -Case $c.Identity -ErrorAction SilentlyContinue)) {
                $holdRows.Add([pscustomobject]@{
                    CaseName          = $c.Name
                    CaseStatus        = $c.Status
                    HoldPolicyName    = $h.Name
                    Enabled           = $h.Enabled
                    ExchangeLocation  = ($h.ExchangeLocation -join '; ')
                    SharePointLocation= ($h.SharePointLocation -join '; ')
                })
            }
        } catch {}
    }
    if ($cases)    { Export-CsvSafe -Data $cases -Name 'ComplianceCases.csv' }
    if ($holdRows.Count -gt 0) { Export-CsvSafe -Data $holdRows.ToArray() -Name 'CaseHoldPolicies.csv' }

    # EncryptionType/LabelActions flag labels with user-defined permissions - these block site moves.
    $labels = @(Get-Label -ErrorAction SilentlyContinue | Select-Object DisplayName, Name, Priority, IsValid, EncryptionType, LabelActions)
    if ($labels) { Export-CsvSafe -Data $labels -Name 'SensitivityLabels.csv' }

    $dlp = @(Get-DlpCompliancePolicy -ErrorAction SilentlyContinue | Select-Object Name, Enabled, Mode, ExchangeLocation, SharePointLocation, OneDriveLocation, TeamsLocation)
    if ($dlp) { Export-CsvSafe -Data $dlp -Name 'DlpPolicies.csv' }

    $script:Summary.metrics.retentionPolicyCount = $policies.Count
    $script:Summary.metrics.complianceCaseCount  = $cases.Count
    $script:Summary.metrics.ediscoveryHoldCount  = $holdRows.Count
    $script:Summary.metrics.dlpPolicyCount       = $dlp.Count
}

function Invoke-OneDrive {
    if (-not $script:SpoAvailable) {
        Invoke-OneDriveFallback
        return
    }
    try {
        $sites = @(Get-SPOSite -IncludePersonalSite $true -Limit All -Filter "Url -like '-my.sharepoint.com/personal/'" -ErrorAction Stop |
            Select-Object Url, Owner, Title, StorageUsageCurrent, StorageQuota, LastContentModifiedDate, LockState, SharingCapability, Status)
        $rows = foreach ($s in $sites) {
            [pscustomobject]@{
                Url                    = $s.Url
                Owner                  = $s.Owner
                Title                  = $s.Title
                StorageUsageGB         = [math]::Round($s.StorageUsageCurrent / 1KB, 2)
                StorageUsageMB         = $s.StorageUsageCurrent
                StorageQuotaGB         = [math]::Round($s.StorageQuota / 1KB, 0)
                LastContentModifiedDate= $s.LastContentModifiedDate
                LockState              = "$($s.LockState)"
                SharingCapability      = "$($s.SharingCapability)"
                Status                 = "$($s.Status)"
                Source                 = 'SPO'
            }
        }
        Export-CsvSafe -Data $rows -Name 'OneDrive.csv'
        $script:Summary.metrics.spoDataSource = 'SPO'
        $script:Summary.metrics.oneDriveCount = $rows.Count
        $script:Summary.metrics.oneDriveTotalGB = [math]::Round(($rows | Measure-Object StorageUsageGB -Sum).Sum, 2)
    } catch {
        Write-Log "Get-SPOSite failed ($($_.Exception.Message)) - falling back to Graph report." -Level WARN
        $script:SpoAvailable = $false
        Invoke-OneDriveFallback
    }

    if ($script:Summary.metrics.spoDataSource -ne 'SPO') { return }
    try {
        $usage = Get-GraphReport -Endpoint 'getOneDriveUsageAccountDetail' -CsvName 'OneDriveUsage.csv'
        if ($usage) { $script:Summary.metrics.oneDriveFileCount = ($usage | Measure-Object 'File Count' -Sum).Sum }
    } catch {
        Write-Log "OneDrive usage report failed: $($_.Exception.Message)" -Level WARN
    }
}

function Invoke-SharePoint {
    if (-not $script:SpoAvailable) {
        Invoke-SharePointFallback
        return
    }
    try {
        $sites = @(Get-SPOSite -Limit All -ErrorAction Stop |
            Where-Object { $_.Url -notmatch '-my\.sharepoint\.com/personal/' } |
            Select-Object Url, Owner, Title, Template, StorageUsageCurrent, StorageQuota,
                          LastContentModifiedDate, LockState, SharingCapability, GroupId,
                          IsTeamsConnected, IsTeamsChannelConnected, Status)
        $rows = foreach ($s in $sites) {
            [pscustomobject]@{
                Url                     = $s.Url
                Owner                   = $s.Owner
                Title                   = $s.Title
                Template                = $s.Template
                StorageUsageGB          = [math]::Round($s.StorageUsageCurrent / 1KB, 2)
                StorageQuotaGB          = [math]::Round($s.StorageQuota / 1KB, 0)
                LastContentModifiedDate = $s.LastContentModifiedDate
                LockState               = "$($s.LockState)"
                SharingCapability       = "$($s.SharingCapability)"
                GroupId                 = $s.GroupId
                IsTeamsConnected        = $s.IsTeamsConnected
                IsTeamsChannelConnected = $s.IsTeamsChannelConnected
                Status                  = "$($s.Status)"
                Source                  = 'SPO'
            }
        }
        Export-CsvSafe -Data $rows -Name 'SharePointSites.csv'
        $script:Summary.metrics.spoDataSource = 'SPO'
        $script:Summary.metrics.sharePointSiteCount = $rows.Count
        $script:Summary.metrics.sharePointTotalGB   = [math]::Round(($rows | Measure-Object StorageUsageGB -Sum).Sum, 2)
    } catch {
        Write-Log "Get-SPOSite failed ($($_.Exception.Message)) - falling back to Graph report." -Level WARN
        $script:SpoAvailable = $false
        Invoke-SharePointFallback
        return
    }

    try {
        $tenant = Get-SPOTenant -ErrorAction Stop
        $tRow = [pscustomobject]@{
            SharingCapability        = "$($tenant.SharingCapability)"
            OneDriveSharingCapability= "$($tenant.OneDriveSharingCapability)"
            DefaultSharingLinkType   = "$($tenant.DefaultSharingLinkType)"
            ConditionalAccessPolicy  = "$($tenant.ConditionalAccessPolicy)"
            SharingAllowedDomainList = ($tenant.SharingAllowedDomainList -join '; ')
            SharingBlockedDomainList = ($tenant.SharingBlockedDomainList -join '; ')
            ShowEveryoneClaim        = $tenant.ShowEveryoneClaim
            PreventExternalUsersFromResharing = $tenant.PreventExternalUsersFromResharing
        }
        Export-CsvSafe -Data @($tRow) -Name 'SharePointTenant.csv'
        $script:Summary.metrics.spoSharingCapability = "$($tenant.SharingCapability)"
    } catch {
        Write-Log "Get-SPOTenant failed: $($_.Exception.Message)" -Level WARN
    }

    try {
        $ext = @(Get-SPOExternalUser -PageSize 50 -Position 0 -ErrorAction Stop)
        $pos = 50
        while ($ext.Count -eq $pos -and $pos -lt 5000) {
            $more = @(Get-SPOExternalUser -PageSize 50 -Position $pos -ErrorAction Stop)
            if ($more.Count -eq 0) { break }
            $ext += $more
            $pos += 50
        }
        $extRows = @($ext | Select-Object DisplayName, Email, AcceptedAs, WhenCreated, InvitedBy)
        if ($extRows) { Export-CsvSafe -Data $extRows -Name 'ExternalUsers.csv' }
        $script:Summary.metrics.externalUserCount = $extRows.Count
    } catch {
        Write-Log "Get-SPOExternalUser is not supported or failed: $($_.Exception.Message)" -Level WARN
    }

    try {
        # Customer Key on the source tenant blocks cross-tenant OneDrive/SharePoint moves.
        if (Get-Command Get-SPODataEncryptionPolicy -ErrorAction SilentlyContinue) {
            $dep = @(Get-SPODataEncryptionPolicy -ErrorAction SilentlyContinue)
            if ($dep) {
                $rows = @($dep | ForEach-Object { [pscustomobject]@{ Service = 'SharePoint/OneDrive'; Name = "$($_.Name)"; Enabled = "$($_.Enabled)"; State = "$($_.State)" } })
                $existing = Join-Path $attachDir 'CustomerKey.csv'
                if (Test-Path $existing) { $rows = @(Import-Csv $existing) + $rows }
                Export-CsvSafe -Data $rows -Name 'CustomerKey.csv'
                $script:Summary.metrics.customerKeySharePoint = $true
            }
        } else {
            Write-Log "Get-SPODataEncryptionPolicy not available in the installed SPO module - Customer Key not checked." -Level WARN
        }
    } catch { Write-Log "Get-SPODataEncryptionPolicy failed: $($_.Exception.Message)" -Level WARN }
}

function Invoke-Teams {
    # Teams via Graph (groups with resourceProvisioningOptions=Team)
    $teamGroups = @(Get-GraphAll -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=resourceProvisioningOptions/Any(x:x eq 'Team')&`$select=id,displayName,visibility&`$top=999")
    $teamRows = [System.Collections.Generic.List[object]]::new()
    $chanRows = [System.Collections.Generic.List[object]]::new()
    $privateCh = 0; $sharedCh = 0; $standardCh = 0
    foreach ($t in $teamGroups) {
        $team = $null
        try { $team = Invoke-MgGraphRequest -OutputType PSObject -Method GET -Uri "https://graph.microsoft.com/v1.0/teams/$($t.id)?`$select=id,displayName,visibility,isArchived" } catch {}
        $memberCount = $null; $ownerCount = $null; $guestCount = $null
        try { $memberCount = [int](Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$($t.id)/transitiveMembers/`$count" -Headers @{ ConsistencyLevel = 'eventual' }) } catch {}
        try { $ownerCount  = [int](Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$($t.id)/owners/`$count" -Headers @{ ConsistencyLevel = 'eventual' }) } catch {}
        try { $guestCount  = [int](Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/teams/$($t.id)/members/`$count?`$filter=roles/any(r:r eq 'guest')" -Headers @{ ConsistencyLevel = 'eventual' }) } catch {}
        $std = 0; $priv = 0; $shrd = 0
        try {
            $channels = @(Get-GraphAll -Uri "https://graph.microsoft.com/v1.0/teams/$($t.id)/allChannels?`$select=id,displayName,membershipType")
            foreach ($ch in $channels) {
                switch ($ch.membershipType) {
                    'private'  { $priv++ ; $privateCh++ }
                    'shared'   { $shrd++ ; $sharedCh++ }
                    default    { $std++  ; $standardCh++ }
                }
                $chanRows.Add([pscustomobject]@{
                    TeamName       = $t.displayName
                    TeamId         = $t.id
                    ChannelName    = $ch.displayName
                    ChannelId      = $ch.id
                    MembershipType = $ch.membershipType
                })
            }
        } catch {
            Write-Log "Channels for team '$($t.displayName)' failed: $($_.Exception.Message)" -Level WARN
        }
        $teamRows.Add([pscustomobject]@{
            TeamId            = $t.id
            DisplayName       = $t.displayName
            Visibility        = if ($team) { $team.visibility } else { $t.visibility }
            IsArchived        = if ($team) { $team.isArchived } else { $null }
            MemberCount       = $memberCount
            OwnerCount        = $ownerCount
            GuestCount        = $guestCount
            StandardChannels  = $std
            PrivateChannels   = $priv
            SharedChannels    = $shrd
        })
    }
    Export-CsvSafe -Data $teamRows.ToArray() -Name 'Teams.csv'
    if ($chanRows.Count -gt 0) { Export-CsvSafe -Data $chanRows.ToArray() -Name 'TeamsChannels.csv' }
    $script:Summary.metrics.teamCount           = $teamRows.Count
    $script:Summary.metrics.standardChannelCount = $standardCh
    $script:Summary.metrics.privateChannelCount  = $privateCh
    $script:Summary.metrics.sharedChannelCount   = $sharedCh
}

function Invoke-TeamsPhone {
    # Teams Phone / voice via the MicrosoftTeams module (runs in its own process)
    if (-not $script:TeamsConnected) {
        Write-Log "MicrosoftTeams connection not established - skipping the Teams Phone section." -Level WARN
        $script:Summary.metrics.teamsPhone = $null
        $script:Summary.skippedSections['TeamsPhone'] = 'Connect-MicrosoftTeams failed or was skipped'
        return
    }
    $phoneUsers = @(Get-CsOnlineUser -ErrorAction SilentlyContinue |
        Where-Object { $_.EnterpriseVoiceEnabled -or $_.LineUri -or $_.OnPremLineUri } |
        Select-Object UserPrincipalName, EnterpriseVoiceEnabled, LineUri, OnPremLineUri, FeatureTypes)
    if ($phoneUsers) { Export-CsvSafe -Data $phoneUsers -Name 'TeamsPhoneUsers.csv' }

    $numbers = @(Get-CsPhoneNumberAssignment -ErrorAction SilentlyContinue |
        Select-Object TelephoneNumber, NumberType, AssignedPstnTargetId, PstnAssignmentStatus, City, ActivationState)
    if ($numbers) { Export-CsvSafe -Data $numbers -Name 'TeamsPhoneNumbers.csv' }

    $gw = @(Get-CsOnlinePSTNGateway -ErrorAction SilentlyContinue | Select-Object Identity, Fqdn, Enabled, SipSignalingPort)
    if ($gw) { Export-CsvSafe -Data $gw -Name 'TeamsPhoneGateways.csv' }

    $vr = @(Get-CsOnlineVoiceRoute -ErrorAction SilentlyContinue | Select-Object Identity, OnlinePstnGatewayList, OnlinePstnUsages, Priority)
    if ($vr) { Export-CsvSafe -Data $vr -Name 'TeamsPhoneVoiceRoutes.csv' }

    $aa = @(Get-CsAutoAttendant -ErrorAction SilentlyContinue | Select-Object Name, Identity, ApplicationInstances, LanguageId, TimeZoneId)
    if ($aa) { Export-CsvSafe -Data $aa -Name 'TeamsAutoAttendants.csv' }

    $cq = @(Get-CsCallQueue -ErrorAction SilentlyContinue | Select-Object Name, Identity, Agents, RoutingMethod)
    if ($cq) { Export-CsvSafe -Data $cq -Name 'TeamsCallQueues.csv' }

    $mp = @(Get-CsTeamsMeetingPolicy -ErrorAction SilentlyContinue | Select-Object Identity)
    if ($mp) { Export-CsvSafe -Data @($mp | ForEach-Object { [pscustomobject]@{ PolicyName = "$($_.Identity)" } }) -Name 'TeamsMeetingPolicies.csv' }

    $script:Summary.metrics.teamsPhoneUserCount   = $phoneUsers.Count
    $script:Summary.metrics.teamsPhoneNumberCount = $numbers.Count
    $script:Summary.metrics.teamsPhone = ($phoneUsers.Count -gt 0 -or $numbers.Count -gt 0)
}

function Invoke-Devices {
    $intuneLicensed = Test-LicenseGate -Capability 'intune' -Section 'Intune' -What 'Intune-enhedsadministration'
    $md = @()
    $mdRows = @()
    if ($intuneLicensed) {
    $md = Get-GraphAll -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDevices?$select=id,deviceName,operatingSystem,osVersion,managedDeviceOwnerType,enrolledDateTime,lastSyncDateTime,complianceState,userPrincipalName,model,manufacturer,azureADDeviceId,joinType&$top=999'
    $mdRows = foreach ($d in $md) {
        [pscustomobject]@{
            Id                    = $d.id
            DeviceName            = $d.deviceName
            OperatingSystem       = $d.operatingSystem
            OsVersion             = $d.osVersion
            OwnerType             = $d.managedDeviceOwnerType
            JoinType              = $d.joinType
            EnrolledDateTime      = $d.enrolledDateTime
            LastSyncDateTime      = $d.lastSyncDateTime
            ComplianceState       = $d.complianceState
            UserPrincipalName     = $d.userPrincipalName
            Model                 = $d.model
            Manufacturer          = $d.manufacturer
            AzureADDeviceId       = $d.azureADDeviceId
        }
    }
    Export-CsvSafe -Data $mdRows -Name 'IntuneDevices.csv'
    }

    $devices = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/devices?$select=id,displayName,trustType,operatingSystem,operatingSystemVersion,approximateLastSignInDateTime,isManaged,isCompliant,accountEnabled&$top=999'
    $devRows = foreach ($d in $devices) {
        $join = switch ($d.trustType) { 'AzureAd' { 'Entra joined' } 'ServerAd' { 'Hybrid Entra joined' } 'Workplace' { 'Entra registered' } default { "$($d.trustType)" } }
        [pscustomobject]@{
            Id                            = $d.id
            DisplayName                   = $d.displayName
            JoinType                      = $join
            TrustType                     = $d.trustType
            OperatingSystem               = $d.operatingSystem
            OperatingSystemVersion        = $d.operatingSystemVersion
            ApproximateLastSignInDateTime = $d.approximateLastSignInDateTime
            IsManaged                     = $d.isManaged
            IsCompliant                   = $d.isCompliant
            AccountEnabled                = $d.accountEnabled
        }
    }
    Export-CsvSafe -Data $devRows -Name 'EntraDevices.csv'

    if ($intuneLicensed) {
    try {
        $ap = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities?$select=id,serialNumber,productKey,groupTag,displayName,manufacturer,model,enrollmentState&$top=999'
        $apRows = @($ap | ForEach-Object {
            [pscustomobject]@{
                Id              = $_.id
                SerialNumber    = $_.serialNumber
                GroupTag        = $_.groupTag
                Manufacturer    = $_.manufacturer
                Model           = $_.model
                EnrollmentState = $_.enrollmentState
            }
        })
        if ($apRows) { Export-CsvSafe -Data $apRows -Name 'AutopilotDevices.csv' }
        $script:Summary.metrics.autopilotDeviceCount = $apRows.Count
    } catch {
        Write-Log "Autopilot devices could not be fetched: $($_.Exception.Message)" -Level WARN
        $script:Summary.metrics.autopilotDeviceCount = 0
    }

    $policyRows = [System.Collections.Generic.List[object]]::new()
    $policyEndpoints = @(
        @{ Name = 'deviceCompliancePolicies';    Uri = 'https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies?$select=id,displayName,lastModifiedDateTime'; Type = 'Compliance' },
        @{ Name = 'deviceConfigurations';        Uri = 'https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations?$select=id,displayName,lastModifiedDateTime';   Type = 'Configuration' },
        @{ Name = 'configurationPolicies';       Uri = 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?$select=id,name,lastModifiedDateTime';         Type = 'SettingsCatalog' },
        @{ Name = 'mobileApps';                  Uri = 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps?$select=id,displayName,lastModifiedDateTime';          Type = 'App' },
        @{ Name = 'managedAppPolicies';          Uri = 'https://graph.microsoft.com/v1.0/deviceAppManagement/managedAppPolicies?$select=id,displayName,lastModifiedDateTime';  Type = 'AppProtection' }
    )
    foreach ($pe in $policyEndpoints) {
        try {
            foreach ($p in (Get-GraphAll -Uri $pe.Uri)) {
                $policyRows.Add([pscustomobject]@{
                    PolicyType    = $pe.Type
                    Name          = if ($p.displayName) { $p.displayName } else { $p.name }
                    Id            = $p.id
                    LastModified  = $p.lastModifiedDateTime
                })
            }
        } catch {
            Write-Log "Intune policy $($pe.Name) failed: $($_.Exception.Message)" -Level WARN
        }
    }
    if ($policyRows.Count -gt 0) { Export-CsvSafe -Data $policyRows.ToArray() -Name 'IntunePolicies.csv' }
    } else {
        $script:Summary.skippedSections['AutopilotDevices'] = "Not collected: no license for Intune device management in the tenant"
        $script:Summary.skippedSections['IntunePolicies']  = "Not collected: no license for Intune device management in the tenant"
        $script:Summary.metrics.intuneDeviceCount = 0
        $script:Summary.metrics.autopilotDeviceCount = 0
        $script:Summary.metrics.intunePoliciesByType = @{}
    }

    $script:Summary.metrics.intuneDeviceCount = if ($mdRows) { $mdRows.Count } else { 0 }
    $byOs = @{}; foreach ($g in ($mdRows | Group-Object OperatingSystem)) { $byOs[$g.Name] = $g.Count }
    $script:Summary.metrics.intuneDevicesByOS = $byOs
    $byJoin = @{}; foreach ($g in ($devRows | Group-Object JoinType)) { $byJoin[$g.Name] = $g.Count }
    $script:Summary.metrics.entraDevicesByJoinType = $byJoin
    $script:Summary.metrics.entraDeviceCount = $devRows.Count
    $polByType = @{}; foreach ($g in ($policyRows | Group-Object PolicyType)) { $polByType[$g.Name] = $g.Count }
    $script:Summary.metrics.intunePoliciesByType = $polByType
}

function Invoke-Usage {
    $reports = @(
        @{ Endpoint = 'getEmailActivityUserDetail';       Csv = 'UsageEmailActivity.csv' },
        @{ Endpoint = 'getTeamsUserActivityUserDetail';   Csv = 'UsageTeamsActivity.csv' },
        @{ Endpoint = 'getMailboxUsageDetail';            Csv = 'UsageMailboxUsage.csv' },
        @{ Endpoint = 'getOffice365ActiveUserDetail';     Csv = 'UsageActiveUsers.csv' }
    )
    foreach ($r in $reports) {
        try { $null = Get-GraphReport -Endpoint $r.Endpoint -CsvName $r.Csv }
        catch { Write-Log "Report $($r.Endpoint) failed: $($_.Exception.Message)" -Level WARN }
    }
    $script:Summary.metrics.concealedReports = $script:ConcealedReports
}

function Resolve-DnsField {
    param([string]$Name, [string]$Type)
    try {
        $r = Resolve-DnsName -Name $Name -Type $Type -ErrorAction Stop -DnsOnly
        $txt = @($r | Where-Object { $_.Type -eq 'TXT' } | ForEach-Object { ($_.Strings -join '') })
        if ($Type -eq 'TXT' -and $txt) { return ($txt -join ' | ') }
        $vals = @($r | Where-Object { $_.Type -eq $Type } | ForEach-Object {
            switch ($Type) {
                'MX'     { "$($_.Preference) $($_.NameExchange)" }
                'CNAME'  { $_.NameHost }
                'A'      { $_.IPAddress }
                default  { "$_" }
            }
        })
        return ($vals -join '; ')
    } catch { return '' }
}

function Invoke-Dns {
    $domains = @()
    if ($script:Summary.metrics.PSObject.Properties['domains']) {
        $domains = @($script:Summary.metrics.domains | Where-Object { $_ -notmatch '\.onmicrosoft\.com$' })
    }
    if ($domains.Count -eq 0 -and (Test-Path (Join-Path $attachDir 'Domains.csv'))) {
        $domains = @((Import-Csv (Join-Path $attachDir 'Domains.csv') | Where-Object { $_.IsVerified -eq 'True' -and $_.Id -notmatch '\.onmicrosoft\.com$' }).Id)
    }
    if ($domains.Count -eq 0) {
        Write-Log "DNS: no verified domains found (requires Domains.csv from the Tenant section)." -Level WARN
        $script:Summary.skippedSections['Dns'] = 'No domain list available - run the Tenant section first'
        return
    }
    $rows = foreach ($d in $domains) {
        $txt = Resolve-DnsField -Name $d -Type 'TXT'
        $spf = if ($txt -match 'v=spf1') { ($txt -split '\|' | Where-Object { $_ -match 'v=spf1' }) -join ' | ' } else { '' }
        $msVerify = ($txt -match 'MS=ms\d+')
        [pscustomobject]@{
            Domain              = $d
            MX                  = Resolve-DnsField -Name $d -Type 'MX'
            SPF                 = $spf
            HasSPF              = [bool]$spf
            MSVerification      = $msVerify
            DMARC               = Resolve-DnsField -Name "_dmarc.$d" -Type 'TXT'
            Autodiscover        = Resolve-DnsField -Name "autodiscover.$d" -Type 'CNAME'
            DkimSelector1       = Resolve-DnsField -Name "selector1._domainkey.$d" -Type 'CNAME'
            DkimSelector2       = Resolve-DnsField -Name "selector2._domainkey.$d" -Type 'CNAME'
            EnterpriseRegistration = Resolve-DnsField -Name "enterpriseregistration.$d" -Type 'CNAME'
            EnterpriseEnrollment   = Resolve-DnsField -Name "enterpriseenrollment.$d" -Type 'CNAME'
        }
    }
    Export-CsvSafe -Data $rows -Name 'Dns.csv'
    $script:Summary.metrics.dnsCheckedDomains = $rows.Count
    $script:Summary.metrics.domainsMissingSpf   = @($rows | Where-Object { -not $_.HasSPF } | ForEach-Object Domain)
    $script:Summary.metrics.domainsMissingDmarc = @($rows | Where-Object { -not $_.DMARC } | ForEach-Object Domain)
}

function Invoke-TargetExchange {
    # Exchange parts of CrossTenant - run in the Exchange child process (requires an EXO connection)
    if (-not $script:ExoConnected) {
        $script:Summary.skippedSections['TargetExchange'] = 'Requires an active Exchange Online connection'
        Write-Log "TargetExchange: EXO not connected - skipping." -Level WARN
        return
    }
    try {
        $orgRel = @(Get-OrganizationRelationship -ErrorAction Stop | Select-Object Name, DomainNames, FreeBusyAccessEnabled, MailboxMoveEnabled, Enabled)
        if ($orgRel) { Export-CsvSafe -Data $orgRel -Name 'OrganizationRelationships.csv' }
        $script:Summary.metrics.orgRelationshipCount = $orgRel.Count
    } catch {
        Write-Log "Get-OrganizationRelationship failed: $($_.Exception.Message)" -Level WARN
        $script:Summary.failedSections['TargetExchange.Get-OrganizationRelationship'] = $_.Exception.Message
    }
    try {
        $migEp = @(Get-MigrationEndpoint -ErrorAction Stop | Select-Object Identity, EndpointType, RemoteServer)
        if ($migEp) { Export-CsvSafe -Data $migEp -Name 'MigrationEndpoints.csv' }
        $script:Summary.metrics.migrationEndpointCount = $migEp.Count
    } catch {
        Write-Log "Get-MigrationEndpoint failed: $($_.Exception.Message)" -Level WARN
        $script:Summary.failedSections['TargetExchange.Get-MigrationEndpoint'] = $_.Exception.Message
    }
    try {
        $ad = @(Get-AcceptedDomain -ErrorAction Stop | Select-Object DomainName, DomainType)
        if ($ad) { Export-CsvSafe -Data $ad -Name 'AcceptedDomains.csv' }
    } catch {
        Write-Log "Get-AcceptedDomain failed: $($_.Exception.Message)" -Level WARN
        $script:Summary.failedSections['TargetExchange.Get-AcceptedDomain'] = $_.Exception.Message
    }
    try {
        $mu = @(Get-MailUser -ResultSize Unlimited -ErrorAction Stop)
        $script:Summary.metrics.mailUserCount = $mu.Count
        if ($mu) { Export-CsvSafe -Data @($mu | Select-Object DisplayName, UserPrincipalName, PrimarySmtpAddress, ExternalEmailAddress) -Name 'MailUsers.csv' }
    } catch {
        Write-Log "Get-MailUser failed: $($_.Exception.Message)" -Level WARN
        $script:Summary.failedSections['TargetExchange.Get-MailUser'] = $_.Exception.Message
    }
}

function Invoke-CrossTenant {
    try {
        $cta = Invoke-MgGraphRequest -OutputType PSObject -Method GET -Uri 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/default'
        $script:Summary.metrics.crossTenantDefaultB2bDirectConnect = ($cta.b2bDirectConnectInbound | ConvertTo-Json -Compress -Depth 5)
    } catch {
        Write-Log "crossTenantAccessPolicy/default failed: $($_.Exception.Message)" -Level WARN
    }
    try {
        $partners = Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/partners'
        $pRows = @($partners | ForEach-Object {
            [pscustomobject]@{
                TenantId      = $_.tenantId
                B2bDirectConnectInbound = ($_.b2bDirectConnectInbound | ConvertTo-Json -Compress -Depth 5)
                B2bCollaborationInbound = ($_.b2bCollaborationInbound | ConvertTo-Json -Compress -Depth 5)
                InboundTrust  = ($_.inboundTrust | ConvertTo-Json -Compress -Depth 5)
            }
        })
        if ($pRows) { Export-CsvSafe -Data $pRows -Name 'CrossTenantPartners.csv' }
        $script:Summary.metrics.crossTenantPartnerCount = $pRows.Count
    } catch {
        Write-Log "crossTenantAccessPolicy/partners failed: $($_.Exception.Message)" -Level WARN
    }
    try {
        $mto = Invoke-MgGraphRequest -OutputType PSObject -Method GET -Uri 'https://graph.microsoft.com/beta/tenantRelationships/multiTenantOrganization'
        $script:Summary.metrics.multiTenantOrganization = $mto.displayName
    } catch {
        $script:Summary.metrics.multiTenantOrganization = $null
    }

    # Comparison with the source inventory
    if ($SourceInventoryPath -and (Test-Path (Join-Path $SourceInventoryPath 'attachments'))) {
        $srcAtt = Join-Path $SourceInventoryPath 'attachments'
        $srcDomainsCsv = Join-Path $srcAtt 'Domains.csv'
        $srcUsersCsv   = Join-Path $srcAtt 'Users.csv'
        if (Test-Path $srcDomainsCsv) {
            $srcDomains = Import-Csv $srcDomainsCsv | Where-Object { $_.IsVerified -eq 'True' -and $_.Id -notmatch '\.onmicrosoft\.com$' }
            $conflicts = foreach ($sd in $srcDomains) {
                $exists = $false
                try {
                    $null = Invoke-MgGraphRequest -OutputType PSObject -Method GET -Uri "https://graph.microsoft.com/v1.0/domains/$($sd.Id)"
                    $exists = $true
                } catch {
                    # Only 404 means "does not exist in target"; other errors (e.g. 403) give unknown status
                    $st = $null; if ($_.Exception.Response) { $st = [int]$_.Exception.Response.StatusCode }
                    if ($st -ne 404 -and $_.Exception.Message -notmatch 'NotFound|404|does not exist') {
                        $exists = 'Unknown'
                        $script:Summary.failedSections["DomainConflict.$($sd.Id)"] = "Domain lookup failed: $($_.Exception.Message)"
                    }
                }
                [pscustomobject]@{
                    SourceDomain   = $sd.Id
                    VerifiedInTarget = $exists
                    Conflict       = $exists
                }
            }
            Export-CsvSafe -Data $conflicts -Name 'DomainConflicts.csv'
            $script:Summary.metrics.domainConflicts        = @($conflicts | Where-Object { $_.Conflict -eq $true }).Count
            $script:Summary.metrics.domainConflictsUnknown = @($conflicts | Where-Object { $_.Conflict -eq 'Unknown' }).Count
        }
        if (Test-Path $srcUsersCsv) {
            $srcUsers = Import-Csv $srcUsersCsv
            $tgtUsers = @()
            $tgtCsv = Join-Path $attachDir 'Users.csv'
            if (Test-Path $tgtCsv) { $tgtUsers = Import-Csv $tgtCsv }
            if (-not $tgtUsers) {
                $tgtUsers = @(Get-GraphAll -Uri 'https://graph.microsoft.com/v1.0/users?$select=id,userPrincipalName,mail,proxyAddresses,displayName&$top=999' | ForEach-Object {
                    [pscustomobject]@{ UserPrincipalName = $_.userPrincipalName; Mail = $_.mail; ProxyAddresses = ($_.proxyAddresses -join '; '); DisplayName = $_.displayName }
                })
            }
            $matchRows = [System.Collections.Generic.List[object]]::new()
            foreach ($su in $srcUsers) {
                $srcSmtps = @($su.ProxyAddresses -split ';' | Where-Object { $_ -match '^smtp:' } | ForEach-Object { $_ -replace '^smtp:','' })
                if ($su.Mail) { $srcSmtps += $su.Mail }
                $srcPrefix = ($su.UserPrincipalName -split '@')[0]
                foreach ($tu in $tgtUsers) {
                    $tgtSmtps = @("$($tu.ProxyAddresses)" -split ';' | Where-Object { $_ -match '^smtp:' } | ForEach-Object { $_ -replace '^smtp:','' })
                    if ($tu.Mail) { $tgtSmtps += $tu.Mail }
                    $matchType = $null
                    if (($srcSmtps | Where-Object { $tgtSmtps -contains $_ })) { $matchType = 'SMTP-adresse' }
                    elseif (($tu.UserPrincipalName -split '@')[0] -eq $srcPrefix -and $srcPrefix) { $matchType = 'UPN prefix' }
                    elseif ($tu.DisplayName -and $su.DisplayName -and $tu.DisplayName -eq $su.DisplayName) { $matchType = 'DisplayName' }
                    if ($matchType) {
                        $matchRows.Add([pscustomobject]@{
                            SourceUPN     = $su.UserPrincipalName
                            SourceMail    = $su.Mail
                            TargetUPN     = $tu.UserPrincipalName
                            TargetMail    = $tu.Mail
                            MatchType     = $matchType
                        })
                        break
                    }
                }
            }
            if ($matchRows.Count -gt 0) { Export-CsvSafe -Data $matchRows.ToArray() -Name 'UserMatches.csv' }
            $script:Summary.metrics.userMatches = $matchRows.Count
        }
    }
}

# ---------- Dispatcher ----------

$sectionFunctions = @{
    Tenant      = { Invoke-Tenant }
    Licenses    = { Invoke-Licenses }
    Users       = { if ($Role -eq 'Target') { Invoke-TargetUsers } else { Invoke-Users } }
    Groups      = { Invoke-Groups }
    Roles       = { Invoke-Roles }
    Security    = { Invoke-Security }
    Apps        = { Invoke-Apps }
    AppSignIns  = { Invoke-AppSignIns }
    Exchange    = { Invoke-Exchange }
    Purview     = { Invoke-Purview }
    OneDrive    = { Invoke-OneDrive }
    SharePoint  = { Invoke-SharePoint }
    Teams       = { Invoke-Teams }
    TeamsPhone  = { Invoke-TeamsPhone }
    Devices     = { Invoke-Devices }
    Usage       = { Invoke-Usage }
    Dns         = { Invoke-Dns }
    CrossTenant = { Invoke-CrossTenant }
    TargetExchange = { Invoke-TargetExchange }
}

# Sections distributed across service groups (process isolation due to MSAL conflicts)
$groupSections = @{
    Graph      = @('Tenant','Licenses','Users','Groups','Roles','Security','Apps','AppSignIns','Teams','Devices','Usage','CrossTenant')
    Exchange   = @('Exchange','Purview','TargetExchange')
    SharePoint = @('OneDrive','SharePoint')
    Teams      = @('TeamsPhone')
}

$allSections = if ($Role -eq 'Source') { $SourceSections } else { $TargetSections }
if ($ServiceGroup) {
    # Child process: -Sections is already filtered by the orchestrator (may contain
    # internal names like TeamsPhone or explicit fallback sections)
    $requested = if ($Sections) { @($Sections) } else { @($groupSections[$ServiceGroup] | Where-Object { $allSections -contains $_ }) }
} else {
    $requested = $allSections
    if ($Sections)     { $requested = @($requested | Where-Object { $Sections -contains $_ }) }
}
if ($SkipSections) { $requested = @($requested | Where-Object { $SkipSections -notcontains $_ }) }

function Get-PartialSummary {
    param([string]$Group)
    $p = Join-Path $outDir "summary.$Group.json"
    if (Test-Path $p) { return ((Get-Content $p -Raw) -replace '(?m)^(\s*)"":', '$1"(unknown)":' | ConvertFrom-Json) }
    return $null
}

function Save-Summary {
    param([string]$FileName)
    $path = Join-Path $outDir $FileName
    # Partial files are merged with existing content so re-runs (fallback/resume) do not delete earlier data
    if ($FileName -ne 'summary.json' -and (Test-Path $path)) {
        $old = (Get-Content $path -Raw) -replace '(?m)^(\s*)"":', '$1"(unknown)":' | ConvertFrom-Json
        foreach ($bucket in 'metrics','failedSections','skippedSections') {
            if ($old.$bucket) {
                foreach ($prop in $old.$bucket.PSObject.Properties) {
                    # Old errors for sections that just ran again must not reappear
                    if ($bucket -ne 'metrics' -and $requested -contains $prop.Name) { continue }
                    if (-not $script:Summary[$bucket].Contains($prop.Name)) { $script:Summary[$bucket][$prop.Name] = $prop.Value }
                }
            }
        }
        if ($old.collectedBy -and -not $script:Summary.collectedBy) { $script:Summary.collectedBy = $old.collectedBy }
    }
    # Empty keys (e.g. devices without a join type) cannot be read by ConvertFrom-Json
    ($script:Summary | ConvertTo-Json -Depth 8) -replace '(?m)^(\s*)"":', '$1"(unknown)":' | Out-File -FilePath $path -Encoding utf8BOM
    Write-Log "Summary skrevet til $FileName"
}

# =====================================================================
# UNDERPROCES-TILSTAND (-ServiceGroup angivet internt)
# =====================================================================
if ($ServiceGroup) {
    Write-Log "=== Underproces '$ServiceGroup' startet: $TenantName ($Role), tenant $TenantId ==="

    # Resolve -TenantId (idempotent for a GUID)
    try {
        $script:TenantGuid = Resolve-TenantId -TenantIdOrDomain $TenantId
    } catch {
        Write-Log "Could not resolve -TenantId '$TenantId': $($_.Exception.Message)" -Level ERROR
        $script:Summary.failedSections['All'] = "TenantId could not be resolved: $($_.Exception.Message)"
        Save-Summary -FileName "summary.$ServiceGroup.json"
        exit 1
    }

    $script:ExoConnected   = $false
    $script:IppsConnected  = $false
    $script:TeamsConnected = $false
    $script:SpoAvailable   = $false
    $script:InitialDomain  = $null
    $script:OrgDisplayName = $null
    $script:GuestMode      = $false

    # Read the Graph partial for guestMode/initialDomain/collectedBy (produced by the Graph child process)
    $graphPartial = Get-PartialSummary -Group 'Graph'
    if ($graphPartial -and $graphPartial.metrics) {
        $gm = $graphPartial.metrics
        if ($gm.PSObject.Properties['guestMode'])      { $script:GuestMode     = [bool]$gm.guestMode }
        if ($gm.PSObject.Properties['initialDomain'])  { $script:InitialDomain = $gm.initialDomain }
        if ($gm.PSObject.Properties['signedInAccount']){ $script:Summary.collectedBy = $gm.signedInAccount }
        if ($gm.PSObject.Properties['tenantDisplayName']) { $script:OrgDisplayName = $gm.tenantDisplayName }
        if ($gm.PSObject.Properties['licenseCapabilities']) { $script:LicenseCaps = $gm.licenseCapabilities }
    }

    # Determine the sections for this group
    $toRun = @($requested | Where-Object { $groupSections[$ServiceGroup] -contains $_ })

    $exitCode = 0
    try {
        switch ($ServiceGroup) {
            'Graph' {
                if (-not (Get-Module -ListAvailable Microsoft.Graph.Authentication)) {
                    $script:Summary.failedSections['Graph'] = 'Modulet Microsoft.Graph.Authentication mangler'
                    throw 'Modulet Microsoft.Graph.Authentication mangler'
                }
                $scopes = if ($Role -eq 'Source') {
                    @('User.Read.All','Group.Read.All','Directory.Read.All','Organization.Read.All','AuditLog.Read.All',
                      'Reports.Read.All','Policy.Read.All','Application.Read.All','RoleManagement.Read.Directory',
                      'UserAuthenticationMethod.Read.All','DeviceManagementManagedDevices.Read.All',
                      'DeviceManagementConfiguration.Read.All','DeviceManagementServiceConfig.Read.All',
                      'DeviceManagementApps.Read.All','TeamSettings.Read.All','Channel.ReadBasic.All','TeamMember.Read.All',
                      'Domain.Read.All','Sites.Read.All','eDiscovery.Read.All')
                } else {
                    @('User.Read.All','Directory.Read.All','Organization.Read.All','Domain.Read.All','Policy.Read.All','AuditLog.Read.All')
                }
                try {
                    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                    if ($DisableWAM -and (Get-Command Set-MgGraphOption -ErrorAction SilentlyContinue)) {
                        # Local client setting (not a tenant change): use browser sign-in instead of WAM
                        Set-MgGraphOption -DisableLoginByWAM $true
                    }
                    $mgParams = @{ TenantId = $script:TenantGuid; Scopes = $scopes; ContextScope = 'Process'; NoWelcome = $true; ErrorAction = 'Stop' }
                    if ($UseDeviceCode) { $mgParams['UseDeviceCode'] = $true }
                    try {
                        Connect-MgGraph @mgParams
                    } catch {
                        $chain = @(); $ex = $_.Exception
                        while ($ex) { $chain += "[$($ex.GetType().Name)] $($ex.Message)"; $ex = $ex.InnerException }
                        Write-Log ("Connect-MgGraph exception chain: " + ($chain -join ' --> ')) -Level ERROR
                        throw ($chain -join ' --> ')
                    }
                    $ctx = Get-MgContext

                    # --- Tenant guard: reject data from the wrong tenant ---
                    $org = (Invoke-MgGraphRequest -OutputType PSObject -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization?$select=id,displayName,verifiedDomains').value | Select-Object -First 1
                    if ($ctx.TenantId -ne $script:TenantGuid -or $org.id -ne $script:TenantGuid) {
                        Write-Log "Connected to the wrong tenant: $($org.displayName) ($($org.id)) - expected $($script:TenantGuid)" -Level ERROR
                        $script:Summary.failedSections['TenantGuard'] = "Connected to the wrong tenant: $($org.displayName) ($($org.id))"
                        Save-Summary -FileName "summary.$ServiceGroup.json"
                        exit 1
                    }
                    $script:TenantGuid     = $org.id
                    $script:OrgDisplayName = $org.displayName
                    $script:InitialDomain  = ($org.verifiedDomains | Where-Object isInitial | Select-Object -First 1).name
                    Write-Host "`n=== Forbundet til tenant: $($org.displayName) ($($org.id)) ===" -ForegroundColor Cyan
                    Write-Log "Tenant-guard OK: $($org.displayName) ($($org.id))"
                    $script:Summary.metrics.tenantId          = $org.id
                    $script:Summary.metrics.tenantDisplayName = $org.displayName
                    $script:Summary.metrics.initialDomain     = $script:InitialDomain
                    $script:Summary.metrics.tenantIdVerified  = $true

                    # --- /me: guest or member? ---
                    try { $me = Invoke-MgGraphRequest -OutputType PSObject -Method GET -Uri 'https://graph.microsoft.com/v1.0/me?$select=userPrincipalName,userType,mail' } catch { $me = $null }
                    $account = if ($me -and $me.userPrincipalName) { $me.userPrincipalName } else { $ctx.Account }
                    $script:Summary.collectedBy = $account
                    if ($me -and $me.userType -eq 'Guest') {
                        $script:GuestMode = $true
                    } elseif (-not $me) {
                        $accDomain = ("$account" -split '@')[-1]
                        $script:GuestMode = -not (@($org.verifiedDomains | ForEach-Object name) -icontains $accDomain)
                    }
                    $script:Summary.metrics.signedInAccount     = $account
                    $script:Summary.metrics.collectedByUserType = if ($script:GuestMode) { 'Guest' } else { 'Member' }
                    $script:Summary.metrics.guestMode           = $script:GuestMode
                    if ($script:GuestMode) {
                        Write-Log "Signed in as GUEST ($account) - SharePoint admin and Exchange PowerShell limited; Graph fallbacks are used." -Level WARN
                        Write-Host "Signed in as guest ($account) - limited data for Exchange and SharePoint (Graph fallback is used)." -ForegroundColor Yellow
                    } else {
                        Write-Log "Graph connected as $account (member) to tenant $($ctx.TenantId)"
                    }

                    # Fallback states in this process (no EXO/IPPS/SPO connected here)
                    $script:ExoConnected = $false
                    $script:IppsConnected = $false

                    # Explicit fallback sections (e.g. -Sections Exchange,Purview in a re-run after an EXO failure)
                    $explicitFallback = @($requested | Where-Object { $_ -in 'Exchange','Purview','OneDrive','SharePoint' })
                    foreach ($s in $explicitFallback) {
                        if ($toRun -notcontains $s) { $toRun += $s }
                    }
                    # In guest mode the Graph process also covers OneDrive/SharePoint (SPO not possible for guests)
                    if ($script:GuestMode -and -not $explicitFallback) {
                        foreach ($s in 'OneDrive','SharePoint') {
                            if (($requested -contains $s) -and ($toRun -notcontains $s)) { $toRun += $s }
                        }
                    }
                } catch {
                    Write-Log "Connect-MgGraph failed: $($_.Exception.Message)" -Level ERROR
                    $script:Summary.failedSections['GraphLogin'] = "Connect-MgGraph failed: $($_.Exception.Message)"
                    foreach ($s in $toRun) { $script:Summary.failedSections[$s] = "Connect-MgGraph failed: $($_.Exception.Message)" }
                    $toRun = @()
                }
            }
            'Exchange' {
                if (-not (Get-Module -ListAvailable ExchangeOnlineManagement)) {
                    $script:Summary.skippedSections['Exchange'] = 'Modulet ExchangeOnlineManagement mangler'
                    foreach ($s in $toRun) { $script:Summary.skippedSections[$s] = 'Modulet ExchangeOnlineManagement mangler' }
                    $toRun = @()
                    break
                }
                try {
                    $exoParams = @{ ShowBanner = $false; ErrorAction = 'Stop' }
                    if ($DisableWAM) { $exoParams['DisableWAM'] = $true }
                    if ($script:GuestMode -and $script:InitialDomain) {
                        $exoParams['DelegatedOrganization'] = $script:InitialDomain
                        Write-Log "Exchange: connecting as guest via -DelegatedOrganization $($script:InitialDomain) ..."
                    } elseif (-not $script:GuestMode -and $script:Summary.collectedBy) {
                        $exoParams['UserPrincipalName'] = $script:Summary.collectedBy
                    }
                    if ($UseDeviceCode) { $exoParams['Device'] = $true; $exoParams.Remove('UserPrincipalName') }
                    Connect-ExchangeOnline @exoParams

                    # --- EXO tenant-guard ---
                    $exoTenant = $null
                    try { $exoTenant = (Get-ConnectionInformation | Select-Object -First 1).TenantID } catch {}
                    if (-not $exoTenant) {
                        try { $exoTenant = (Get-OrganizationConfig -ErrorAction Stop).Identity } catch {}
                    }
                    if (-not $exoTenant) {
                        Write-Log "Exchange tenant could not be verified - rejecting the connection." -Level ERROR
                        try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
                        $script:Summary.failedSections['Exchange'] = 'Exchange tenant could not be verified'
                        $toRun = @($toRun | Where-Object { $_ -ne 'Exchange' })
                    } elseif ($exoTenant -ne $script:TenantGuid -and $exoTenant -ne $script:InitialDomain) {
                        Write-Log "Exchange connected to the wrong tenant ($exoTenant, expected $($script:TenantGuid))." -Level ERROR
                        try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
                        $script:Summary.failedSections['Exchange'] = "Exchange connected to the wrong tenant ($exoTenant)"
                        $toRun = @($toRun | Where-Object { $_ -ne 'Exchange' })
                    } else {
                        $script:ExoConnected = $true
                        Write-Log "Exchange Online connected (tenant: $exoTenant)."
                    }
                } catch {
                    $wamHint = if ($_.Exception.Message -match 'WAM|broker|InteractiveBrowser') { ' Possible WAM/broker error - try -DisableWAM.' } else { '' }
                    if ($script:GuestMode) {
                        Write-Log "Connect-ExchangeOnline failed as guest: $($_.Exception.Message).$wamHint" -Level WARN
                        Write-Log "Exchange Online PowerShell does not necessarily support B2B guest administrators (DelegatedOrganization is documented for CSP/GDAP). Use a member account in Contoso for full Exchange data. Graph fallback is used." -Level WARN
                    } else {
                        Write-Log "Connect-ExchangeOnline failed: $($_.Exception.Message).$wamHint" -Level ERROR
                    }
                    foreach ($s in 'Exchange' | Where-Object { $toRun -contains $_ }) {
                        $script:Summary.failedSections[$s] = "Connect-ExchangeOnline failed: $($_.Exception.Message)"
                    }
                }

                if ($toRun -contains 'Purview' -and $script:ExoConnected) {
                    try {
                        $ippsParams = @{ ShowBanner = $false; ErrorAction = 'Stop' }
                        if ($DisableWAM) { $ippsParams['DisableWAM'] = $true }
                        if ($script:GuestMode -and $script:InitialDomain) {
                            $ippsParams['DelegatedOrganization'] = $script:InitialDomain
                        } elseif (-not $script:GuestMode -and $script:Summary.collectedBy) {
                            $ippsParams['UserPrincipalName'] = $script:Summary.collectedBy
                        }
                        Connect-IPPSSession @ippsParams
                        $ippsTenant = $null
                        try { $ippsTenant = (Get-ConnectionInformation | Select-Object -First 1).TenantID } catch {}
                        if (-not $ippsTenant) {
                            Write-Log "IPPS tenant could not be verified - rejecting the connection." -Level ERROR
                            $script:Summary.failedSections['Purview'] = 'Purview tenant could not be verified'
                            $toRun = @($toRun | Where-Object { $_ -ne 'Purview' })
                        } elseif ($ippsTenant -ne $script:TenantGuid -and $ippsTenant -ne $script:InitialDomain) {
                            Write-Log "IPPS connected to the wrong tenant ($ippsTenant)." -Level ERROR
                            $script:Summary.failedSections['Purview'] = "Purview connected to the wrong tenant ($ippsTenant)"
                            $toRun = @($toRun | Where-Object { $_ -ne 'Purview' })
                        } else {
                            $script:IppsConnected = $true
                            Write-Log "Purview (IPPS) connected."
                        }
                    } catch {
                        $wamHint = if ($_.Exception.Message -match 'WAM|broker|InteractiveBrowser') { ' Possible WAM/broker error - try -DisableWAM.' } else { '' }
                        if ($script:GuestMode) {
                            Write-Log "Connect-IPPSSession failed as guest: $($_.Exception.Message).$wamHint Exchange Online PowerShell does not necessarily support B2B guest administrators - Graph fallback (eDiscovery) is used." -Level WARN
                        } else {
                            Write-Log "Connect-IPPSSession failed: $($_.Exception.Message).$wamHint" -Level ERROR
                        }
                        $script:Summary.failedSections['Purview'] = "Connect-IPPSSession failed: $($_.Exception.Message)"
                    }
                } elseif ($toRun -contains 'Purview') {
                    $script:Summary.skippedSections['Purview'] = 'Requires an active Exchange Online connection - Graph fallback (eDiscovery) is used'
                }
            }
            'SharePoint' {
                if ($script:GuestMode) {
                    # Guests do not have access to the SharePoint admin center
                    $script:Summary.skippedSections['SharePointAdmin'] = 'Guest accounts do not have access to SharePoint admin - Graph fallback is used'
                    Write-Log "Guest mode: Connect-SPOService is skipped." -Level WARN
                    foreach ($s in $toRun) { $script:Summary.failedSections[$s] = 'SharePoint admin not available as guest - Graph fallback is used' }
                    break
                }
                if (-not (Get-Module -ListAvailable Microsoft.Online.SharePoint.PowerShell)) {
                    foreach ($s in $toRun) { $script:Summary.skippedSections[$s] = 'Modulet Microsoft.Online.SharePoint.PowerShell mangler - Graph-fallback bruges' }
                    $toRun = @()
                    break
                }
                $spoUrl = $SpoAdminUrl
                if (-not $spoUrl -and $script:InitialDomain -and $script:InitialDomain -match '^([^.]+)\.onmicrosoft\.com$') {
                    $spoUrl = "https://$($Matches[1])-admin.sharepoint.com"
                }
                if ($spoUrl) {
                    try {
                        if (-not (Get-Command Connect-SPOService -ErrorAction SilentlyContinue)) {
                            # The module is not marked Core-compatible; Microsoft recommends -UseWindowsPowerShell in PowerShell 7
                            Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell -DisableNameChecking -WarningAction SilentlyContinue -ErrorAction Stop
                        }
                        Connect-SPOService -Url $spoUrl -ErrorAction Stop
                        $script:SpoAvailable = $true
                        Write-Log "SharePoint Online connected ($spoUrl)."
                    } catch {
                        Write-Log "Connect-SPOService failed: $($_.Exception.Message) - Graph fallback is used." -Level WARN
                        foreach ($s in $toRun) { $script:Summary.failedSections[$s] = "Connect-SPOService failed: $($_.Exception.Message)" }
                    }
                } else {
                    Write-Log "SPO admin URL could not be derived - Graph fallback is used." -Level WARN
                    foreach ($s in $toRun) { $script:Summary.failedSections[$s] = 'SPO admin URL could not be derived' }
                }
            }
            'Teams' {
                if (-not (Get-Module -ListAvailable MicrosoftTeams)) {
                    $script:Summary.skippedSections['TeamsPhone'] = 'Modulet MicrosoftTeams mangler'
                    $toRun = @()
                    break
                }
                try {
                    $teamsParams = @{ TenantId = $script:TenantGuid; ErrorAction = 'Stop' }
                    if ($DisableWAM) { $teamsParams['DisableWAM'] = $true }
                    if ($UseDeviceCode) { $teamsParams['UseDeviceAuthentication'] = $true }
                    $null = Connect-MicrosoftTeams @teamsParams
                    $csTenant = $null
                    try { $csTenant = (Get-CsTenant -ErrorAction Stop).TenantId } catch {}
                    if (-not $csTenant) {
                        Write-Log "Teams tenant could not be verified - rejecting the connection." -Level ERROR
                        try { Disconnect-MicrosoftTeams -ErrorAction SilentlyContinue | Out-Null } catch {}
                        $script:Summary.failedSections['TeamsPhone'] = 'Teams tenant could not be verified'
                        $toRun = @()
                    } elseif ($csTenant -ne $script:TenantGuid) {
                        Write-Log "Microsoft Teams connected to the wrong tenant ($csTenant)." -Level ERROR
                        try { Disconnect-MicrosoftTeams -ErrorAction SilentlyContinue | Out-Null } catch {}
                        $script:Summary.failedSections['TeamsPhone'] = "Teams connected to the wrong tenant ($csTenant)"
                        $toRun = @()
                    } else {
                        $script:TeamsConnected = $true
                        Write-Log "Microsoft Teams connected (tenant: $csTenant)."
                    }
                } catch {
                    $wamHint = if ($_.Exception.Message -match 'WAM|broker|InteractiveBrowser') { ' Possible WAM/broker error - try -DisableWAM.' } else { '' }
                    Write-Log "Connect-MicrosoftTeams failed: $($_.Exception.Message).$wamHint" -Level WARN
                    $script:Summary.failedSections['TeamsPhone'] = "Connect-MicrosoftTeams failed: $($_.Exception.Message)"
                    $toRun = @()
                }
            }
        }

        # ---- Run the group's sections ----
        foreach ($section in $toRun) {
            Write-Log "--- Section: $section ---"
            try {
                & $sectionFunctions[$section]
                Write-Log "Section $section done."
            } catch {
                Write-Log "Section $section failed: $($_.Exception.Message)" -Level ERROR
                $script:Summary.failedSections[$section] = $_.Exception.Message
            }
        }
    }
    finally {
        try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}
        try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
        try { Disconnect-SPOService -ErrorAction SilentlyContinue | Out-Null } catch {}
        try { Disconnect-MicrosoftTeams -ErrorAction SilentlyContinue | Out-Null } catch {}
        Write-Log "Underproces '$ServiceGroup': forbindelser lukket."
    }

    if (-not $script:Summary.metrics.Contains('concealedReports')) {
        $script:Summary.metrics.concealedReports = $script:ConcealedReports
    }
    Save-Summary -FileName "summary.$ServiceGroup.json"
    Write-Log "=== Child process '$ServiceGroup' done ==="
    if ($ChildPauseOnError -and ($exitCode -ne 0 -or $script:Summary.failedSections.Count -gt 0)) {
        Write-Host "`nChild process '$ServiceGroup' had errors (see above / Collection.log)." -ForegroundColor Yellow
        $null = Read-Host 'Press Enter to close the window'
    }
    exit $exitCode
}

# =====================================================================
# ORCHESTRATOR MODE (normal run)
# =====================================================================
Write-Log "=== Tenant-inventar startet: $TenantName ($Role) ==="
Write-Log "Sections to run: $($requested -join ', ')"

# ---- Resolve -TenantId to the tenant GUID ----
try {
    $script:TenantGuid = Resolve-TenantId -TenantIdOrDomain $TenantId
    Write-Log "TenantId '$TenantId' resolved to tenant GUID: $($script:TenantGuid)"
} catch {
    Write-Log "Could not resolve -TenantId '$TenantId': $($_.Exception.Message)" -Level ERROR
    $script:Summary.failedSections['All'] = "TenantId could not be resolved: $($_.Exception.Message)"
    Save-Summary -FileName 'summary.json'
    throw
}

$needGraph  = @($requested | Where-Object { $groupSections.Graph -contains $_ }).Count -gt 0
$needEXO    = @($requested | Where-Object { $groupSections.Exchange -contains $_ }).Count -gt 0
$needSPO    = @($requested | Where-Object { $groupSections.SharePoint -contains $_ }).Count -gt 0
$needTeams  = $requested -contains 'Teams'
$needDns    = $requested -contains 'Dns'

$pwshExe = Join-Path $PSHOME 'pwsh.exe'

function Start-Child {
    param([string]$Group, [string[]]$ChildSections)
    $label = switch ($Group) {
        'Graph'      { 'Microsoft Graph (users, groups, security, apps, devices, reports)' }
        'Exchange'   { 'Exchange Online + Purview (mailboxes, holds, mail flow, compliance)' }
        'SharePoint' { 'SharePoint Online admin (sites, OneDrive, tenant settings)' }
        'Teams'      { 'Microsoft Teams (telephony)' }
    }
    Write-Host "`n>>> Log ind i $TenantName ($script:TenantGuid) for $Group - $label" -ForegroundColor Cyan
    Write-Log "Starting child process: $Group $(if ($ChildSections) { "[$($ChildSections -join ', ')]" })"
    $argList = @('-NoProfile','-File', $PSCommandPath,
        '-Role', $Role, '-TenantName', $TenantName, '-TenantId', $script:TenantGuid,
        '-OutputFolder', $outDir, '-ServiceGroup', $Group)
    if ($ChildSections)    { $argList += @('-Sections', ($ChildSections -join ',')) }
    elseif ($Sections)     { $argList += @('-Sections', ($Sections -join ',')) }
    if ($SkipSections)     { $argList += @('-SkipSections', ($SkipSections -join ',')) }
    if ($SpoAdminUrl)      { $argList += @('-SpoAdminUrl', $SpoAdminUrl) }
    if ($SourceInventoryPath) { $argList += @('-SourceInventoryPath', $SourceInventoryPath) }
    if ($DisableWAM)       { $argList += '-DisableWAM' }
    if ($UseDeviceCode)    { $argList += '-UseDeviceCode' }
    $quoted = $argList | ForEach-Object { if ("$_" -match '[\s"]') { '"' + ("$_" -replace '"','\"') + '"' } else { "$_" } }
    # -NewWindow: run the child process in its own console window (if the WAM sign-in cannot show in the current terminal).
    if (-not $NewWindow) {
        $proc = Start-Process -FilePath $pwshExe -ArgumentList $quoted -NoNewWindow -Wait -PassThru
    } else {
        Write-Host "    A new PowerShell window opens for sign-in and collection - follow the sign-in dialog there." -ForegroundColor Yellow
        $proc = Start-Process -FilePath $pwshExe -ArgumentList ($quoted + '-ChildPauseOnError') -Wait -PassThru
    }
    $code = $proc.ExitCode
    Write-Log "Child process $Group done (exit $code)."
    return $code
}

$childGroupsRun = [System.Collections.Generic.List[string]]::new()
$abort = $false
$abortReason = $null

# 1) Graph child process (tenant guard + guest detection + all Graph sections)
if ($needGraph -or $needSPO -or $needEXO -or $needTeams) {
    $graphSecs = @($requested | Where-Object { $groupSections.Graph -contains $_ })
    if ($graphSecs.Count -eq 0 -and (Test-Path (Join-Path $outDir 'summary.Graph.json'))) {
        Write-Log "Resuming: using existing Graph data in $outDir (tenant guard already passed)."
        $code = 0
    } else {
        if ($graphSecs.Count -eq 0) { $graphSecs = @('Tenant') }   # tenant guard + guest detection required
        $code = Start-Child -Group 'Graph' -ChildSections $graphSecs
        $childGroupsRun.Add('Graph')
    }
    $gp = Get-PartialSummary -Group 'Graph'
    if ($gp -and $gp.failedSections -and $gp.failedSections.PSObject.Properties['TenantGuard']) {
        $abortReason = "connected to the wrong tenant ($($gp.failedSections.TenantGuard))"
    } elseif ($gp -and $gp.failedSections -and $gp.failedSections.PSObject.Properties['GraphLogin']) {
        $abortReason = "Graph sign-in failed: $($gp.failedSections.GraphLogin). Try again, possibly with -DisableWAM (the sign-in window may be hidden behind other windows)."
    } elseif ($code -ne 0 -or -not $gp) {
        $abortReason = "The Graph child process stopped unexpectedly (exit $code) - see the error above in the console."
    }
    if ($abortReason) {
        Write-Log "Indsamling afbrydes: $abortReason" -Level ERROR
        $abort = $true
    }
    $script:GuestMode = $false
    if ($gp -and $gp.metrics -and $gp.metrics.PSObject.Properties['guestMode']) { $script:GuestMode = [bool]$gp.metrics.guestMode }
}

# 2) Exchange child process (EXO + IPPS)
if (-not $abort -and $needEXO) {
    $code = Start-Child -Group 'Exchange' -ChildSections @($requested | Where-Object { $groupSections.Exchange -contains $_ })
    $childGroupsRun.Add('Exchange')
    $ep = Get-PartialSummary -Group 'Exchange'
    $exFail = @('Exchange','Purview' | Where-Object {
        ($requested -contains $_) -and
        (($ep -and $ep.failedSections -and $ep.failedSections.PSObject.Properties[$_]) -or
         ($ep -and $ep.skippedSections -and $ep.skippedSections.PSObject.Properties[$_]) -or -not $ep)
    })
    # A Purview "skipped" due to a missing EXO connection must also fall back to Graph
    if ($exFail.Count -gt 0) {
        Write-Log "Exchange sections failed/skipped ($($exFail -join ', ')) - running Graph fallback." -Level WARN
        $code = Start-Child -Group 'Graph' -ChildSections $exFail
        $childGroupsRun.Add('Graph')
    }
}

# 3) SharePoint child process (member mode only)
if (-not $abort -and $needSPO -and -not $script:GuestMode) {
    $code = Start-Child -Group 'SharePoint' -ChildSections @($requested | Where-Object { $groupSections.SharePoint -contains $_ })
    $childGroupsRun.Add('SharePoint')
    $sp = Get-PartialSummary -Group 'SharePoint'
    $spFail = @('OneDrive','SharePoint' | Where-Object {
        ($requested -contains $_) -and
        (($sp -and $sp.failedSections -and $sp.failedSections.PSObject.Properties[$_]) -or
         ($sp -and $sp.skippedSections -and $sp.skippedSections.PSObject.Properties[$_]) -or -not $sp)
    })
    if ($spFail.Count -gt 0) {
        Write-Log "SharePoint sections failed ($($spFail -join ', ')) - running Graph fallback." -Level WARN
        $code = Start-Child -Group 'Graph' -ChildSections $spFail
        $childGroupsRun.Add('Graph')
    }
} elseif ($needSPO -and $script:GuestMode) {
    Write-Log "Guest mode: SharePoint child process skipped - the Graph process already handled OneDrive/SharePoint via fallback."
}

# 4) Teams child process (telephony - the Graph part of Teams ran in the Graph process)
if (-not $abort -and $needTeams) {
    # License gate: no Teams Phone license => no sign-in prompt
    $gp = Get-PartialSummary -Group 'Graph'
    $phoneLicensed = $null
    if ($gp -and $gp.metrics -and $gp.metrics.PSObject.Properties['licenseCapabilities']) {
        $lc = $gp.metrics.licenseCapabilities
        if ($lc.PSObject.Properties['teamsPhone']) { $phoneLicensed = [bool]$lc.teamsPhone }
    }
    if ($phoneLicensed -eq $false) {
        Write-Log "TeamsPhone skipped: no Teams Phone/Calling Plan license in the tenant." -Level WARN
        $script:Summary.skippedSections['TeamsPhone'] = 'Not collected: no license for Teams Phone in the tenant (servicePlan MCOEV/MCOPSTN/MCOCAP not found among active licenses)'
        $script:Summary.metrics.teamsPhone         = $false
        $script:Summary.metrics.teamsPhoneLicensed = $false
    } else {
        $code = Start-Child -Group 'Teams' -ChildSections @('TeamsPhone')
        $childGroupsRun.Add('Teams')
    }
}

# 5) DNS in the parent process (no module needed)
if (-not $abort -and $needDns) {
    Write-Log "--- Section: Dns ---"
    try {
        Invoke-Dns
        Write-Log "Section Dns done."
    } catch {
        Write-Log "Section Dns failed: $($_.Exception.Message)" -Level ERROR
        $script:Summary.failedSections['Dns'] = $_.Exception.Message
    }
}

# ---- Merge summary.<Group>.json -> summary.json ----
$mergedMetrics = [ordered]@{}
# Graph (incl. fallbacks) is merged first so real Exchange/SharePoint/Teams data overwrites fallback values.
# The partial files are left in place so a later resume (-OutputFolder) can build on them.
$partialFiles = @(Get-ChildItem (Join-Path $outDir 'summary.*.json') -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'summary.json' } |
    Sort-Object @{ Expression = { if ($_.Name -eq 'summary.Graph.json') { 0 } else { 1 } } }, Name)
foreach ($p in $partialFiles) {
    $part = (Get-Content $p.FullName -Raw) -replace '(?m)^(\s*)"":', '$1"(unknown)":' | ConvertFrom-Json
    if ($part.metrics) {
        foreach ($prop in $part.metrics.PSObject.Properties) { $mergedMetrics[$prop.Name] = $prop.Value }
    }
    if ($part.failedSections) {
        foreach ($prop in $part.failedSections.PSObject.Properties) { $script:Summary.failedSections[$prop.Name] = $prop.Value }
    }
    if ($part.skippedSections) {
        foreach ($prop in $part.skippedSections.PSObject.Properties) { $script:Summary.skippedSections[$prop.Name] = $prop.Value }
    }
    if ($part.collectedBy -and -not $script:Summary.collectedBy) { $script:Summary.collectedBy = $part.collectedBy }
}
# If Exchange PowerShell succeeded, the fallback limitations from Graph no longer apply
$exPart = $partialFiles | Where-Object Name -eq 'summary.Exchange.json'
if ($exPart -and $mergedMetrics.Contains('holdsUnknown') -and -not $mergedMetrics['holdsUnknown']) {
    foreach ($k in 'Exchange','MailboxHolds','MailboxPermissions','Mailflow') {
        $script:Summary.failedSections.Remove($k); $script:Summary.skippedSections.Remove($k)
    }
}
foreach ($k in $mergedMetrics.Keys) { $script:Summary.metrics[$k] = $mergedMetrics[$k] }
if (-not $script:Summary.metrics.Contains('concealedReports')) {
    $script:Summary.metrics.concealedReports = $script:ConcealedReports
}
Save-Summary -FileName 'summary.json'
if ($abort) {
    Write-Log "=== Afbrudt: $abortReason Output: $outDir ===" -Level ERROR
    throw "Collection aborted - $abortReason"
}
Write-Log "=== Done. Output: $outDir ==="
Write-Host "`nDone. Inventory written to: $outDir" -ForegroundColor Green
