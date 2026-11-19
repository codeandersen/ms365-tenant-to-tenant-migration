#requires -Version 7.2
Set-StrictMode -Version Latest

function Assert-TenantContext {
    <#
    .SYNOPSIS
        Verifies that a live connection points at the expected tenant (and optionally the expected account).

    .DESCRIPTION
        Pure function: compares -ExpectedTenantId to -ActualTenantId and, when both are given,
        -ExpectedUpn to -ActualUpn. Comparison is case-insensitive. Throws a clear error on any
        mismatch so a script can never run against the wrong tenant by accident. On success it
        writes "Signed in as <upn> to tenant <id>" to the host.

    .PARAMETER ExpectedTenantId
        The tenant ID (GUID) the connection must belong to.

    .PARAMETER ActualTenantId
        The tenant ID reported by the active session (Get-MgContext / Get-ConnectionInformation).

    .PARAMETER ExpectedUpn
        Optional. The sign-in name the session must belong to.

    .PARAMETER ActualUpn
        Optional. The account reported by the active session.

    .EXAMPLE
        Assert-TenantContext -ExpectedTenantId $tenantId -ActualTenantId (Get-MgContext).TenantId -ExpectedUpn 'admin@fabrikam.com' -ActualUpn (Get-MgContext).Account
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ExpectedTenantId,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$ActualTenantId,

        [string]$ExpectedUpn,

        [string]$ActualUpn
    )

    if ($ExpectedTenantId -ine $ActualTenantId) {
        throw "Tenant mismatch: expected tenant '$ExpectedTenantId' but the session is connected to '$ActualTenantId'. Aborting - refusing to run against the wrong tenant."
    }
    if ($ExpectedUpn -and $ActualUpn -and ($ExpectedUpn -ine $ActualUpn)) {
        throw "Account mismatch: expected '$ExpectedUpn' but the session is signed in as '$ActualUpn'. Aborting."
    }
    $upnShown = if ($ActualUpn) { $ActualUpn } elseif ($ExpectedUpn) { $ExpectedUpn } else { '(unknown account)' }
    Write-Host "Signed in as $upnShown to tenant $ActualTenantId"
}

function Connect-MigrationGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph for a migration session and asserts the tenant context.

    .DESCRIPTION
        Runs Connect-MgGraph -TenantId -Scopes -NoWelcome, then reads Get-MgContext and calls
        Assert-TenantContext so the session is guaranteed to be in -TenantId (and, when given,
        signed in as -AdminUpn) before returning.

    .PARAMETER TenantId
        Tenant ID of the tenant to work against. Must be a GUID: Get-MgContext returns the
        GUID, so a domain here could never match the post-connect assertion.

    .PARAMETER AdminUpn
        Optional. Expected sign-in name; asserted after connect.

    .PARAMETER Scopes
        Graph scopes to request, passed straight through to Connect-MgGraph -Scopes.

    .EXAMPLE
        Connect-MigrationGraph -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@fabrikam.com' -Scopes 'User.Read.All','Organization.Read.All'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
        [string]$TenantId,

        [string]$AdminUpn,

        [Parameter(Mandatory)]
        [string[]]$Scopes
    )

    Connect-MgGraph -TenantId $TenantId -Scopes $Scopes -NoWelcome
    $ctx = Get-MgContext
    if (-not $ctx) { throw 'Connect-MgGraph returned but Get-MgContext is empty - cannot verify tenant context. Aborting.' }
    Assert-TenantContext -ExpectedTenantId $TenantId -ActualTenantId $ctx.TenantId -ExpectedUpn $AdminUpn -ActualUpn $ctx.Account
    return $ctx
}

function Connect-MigrationExchange {
    <#
    .SYNOPSIS
        Connects to Exchange Online for a migration session and asserts the tenant context.

    .DESCRIPTION
        Runs Connect-ExchangeOnline -UserPrincipalName -ShowBanner:$false, then reads
        Get-ConnectionInformation and calls Assert-TenantContext on TenantID and
        UserPrincipalName.

    .PARAMETER TenantId
        Tenant ID the Exchange session must belong to. Must be a GUID: Get-ConnectionInformation
        returns the GUID, so a domain here could never match the post-connect assertion.

    .PARAMETER AdminUpn
        The admin account to sign in with (and assert afterwards).

    .EXAMPLE
        Connect-MigrationExchange -TenantId $tenantId -AdminUpn 'admin@fabrikam.com'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$AdminUpn
    )

    Connect-ExchangeOnline -UserPrincipalName $AdminUpn -ShowBanner:$false
    $conn = Get-ConnectionInformation | Select-Object -First 1
    if (-not $conn) { throw 'Connect-ExchangeOnline returned but Get-ConnectionInformation is empty - cannot verify tenant context. Aborting.' }
    Assert-TenantContext -ExpectedTenantId $TenantId -ActualTenantId $conn.TenantID -ExpectedUpn $AdminUpn -ActualUpn $conn.UserPrincipalName
    return $conn
}

function Export-CsvSafe {
    <#
    .SYNOPSIS
        Exports pipeline input to CSV as UTF-8 with BOM, creating the parent folder if needed.

    .DESCRIPTION
        Thin wrapper over Export-Csv that always uses -NoTypeInformation -Encoding utf8BOM
        (so Excel renders æøå and other non-ASCII characters correctly) and creates the
        destination folder when it does not exist.

    .PARAMETER InputObject
        Objects to export; normally supplied via the pipeline.

    .PARAMETER Path
        Destination CSV path.

    .PARAMETER Delimiter
        CSV delimiter. Default ',' - the same delimiter Collect-TenantInventory.ps1 uses.

    .EXAMPLE
        $rows | Export-CsvSafe -Path .\out\Users.csv
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [object]$InputObject,

        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [string]$Delimiter = ','
    )

    begin { $buffer = [System.Collections.Generic.List[object]]::new() }
    process { if ($null -ne $InputObject) { $buffer.Add($InputObject) } }
    end {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        $buffer | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8BOM -Delimiter $Delimiter
    }
}

function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped log line to the host and optionally appends it to a log file.

    .PARAMETER Message
        The text to log.

    .PARAMETER Level
        Info, Warn or Error. Controls the host colour and the level tag in the line.

    .PARAMETER LogPath
        Optional file to append the line to (UTF-8 with BOM; created if missing).

    .EXAMPLE
        Write-Log -Message 'Starting CTIM copy request' -Level Info -LogPath $log
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [ValidateSet('Info', 'Warn', 'Error')]
        [string]$Level = 'Info',

        [string]$LogPath
    )

    $stamp = [datetime]::Now.ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
    $line = "$stamp [$Level] $Message"
    switch ($Level) {
        'Warn' { Write-Warning $Message }
        'Error' { Write-Host $line -ForegroundColor Red }
        default { Write-Host $line }
    }
    if ($LogPath) {
        $dir = Split-Path -Parent $LogPath
        if ($dir -and -not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        $line | Out-File -FilePath $LogPath -Append -Encoding utf8BOM
    }
}

function New-OutputFolder {
    <#
    .SYNOPSIS
        Creates and returns a timestamped output folder under customers/<Customer>/output/<Phase>/.

    .DESCRIPTION
        Builds <repoRoot>/customers/<Customer>/output/<Phase>/<yyyyMMdd-HHmmss> (invariant
        culture), creates it, and returns the full path. The customers/ tree is gitignored;
        per-run output belongs there, not in the repo.

    .PARAMETER Customer
        The customer folder name (the <name> in customers/<name>).

    .PARAMETER Phase
        Phase folder, e.g. '00-Assessment' or '03-Identities'.

    .PARAMETER Root
        Override for the repo root. Default: the parent of the tools folder containing this module.

    .EXAMPLE
        $out = New-OutputFolder -Customer contoso -Phase 00-Assessment
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Customer,

        [Parameter(Mandatory)]
        [string]$Phase,

        [string]$Root = (Split-Path -Parent $PSScriptRoot)
    )

    $stamp = [datetime]::Now.ToString('yyyyMMdd-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture)
    $path = Join-Path $Root (Join-Path 'customers' (Join-Path $Customer (Join-Path 'output' (Join-Path $Phase $stamp))))
    $null = New-Item -ItemType Directory -Path $path -Force
    return $path
}

Export-ModuleMember -Function Assert-TenantContext, Connect-MigrationGraph, Connect-MigrationExchange, Export-CsvSafe, Write-Log, New-OutputFolder
