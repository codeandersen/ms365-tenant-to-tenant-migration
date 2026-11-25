# Pure analysis functions shared by New-InventoryReport.ps1 and
# New-MigrationReadinessReport.ps1. No I/O, no state - StrictMode safe.
# Column names follow the CSVs produced by Collect-TenantInventory.ps1.

function Get-Prop {
    param([object]$Row, [string]$Name)
    if ($null -eq $Row) { return '' }
    $p = $Row.PSObject.Properties[$Name]
    if ($null -eq $p) { return '' }
    return "$($p.Value)"
}

function ConvertTo-LocationList {
    # Location columns serialize joined lists ('; ' separated) - 'All' appears
    # literally. Returns trimmed entries (may be empty).
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    return @($Value -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Test-UrlMatch {
    # Case-insensitive, trailing-slash tolerant URL comparison.
    param([string]$A, [string]$B)
    return ($A.TrimEnd('/') -ieq $B.TrimEnd('/'))
}

function Get-OneDriveHoldStatus {
    <#
    .SYNOPSIS
        Maps enabled retention policies and eDiscovery case holds onto OneDrive
        sites. Returns held OneDrives plus status flags describing what could
        not be evaluated.
    .OUTPUTS
        pscustomobject @{ Rows; Evaluated; AdaptiveScopesMissing;
                          AdaptiveTargetsOneDrive; AdaptiveUnknown }
    #>
    param(
        [object[]]$OneDrives           = @(),
        [object[]]$RetentionPolicies   = @(),
        [object[]]$CaseHoldPolicies    = @(),
        [object[]]$AdaptiveScopes      = @(),
        [bool]$RetentionCsvPresent     = $false,
        [bool]$AdaptiveScopesCsvPresent = $false
    )
    $reasons = @{}   # normalized url -> List[string]
    $byNormUrl = @{} # normalized url -> row
    foreach ($od in $OneDrives) {
        $byNormUrl[(Get-Prop $od 'Url').TrimEnd('/').ToLower()] = $od
    }
    function Add-Hold {
        param([object]$Row, [string]$Reason)
        $key = (Get-Prop $Row 'Url').TrimEnd('/').ToLower()
        if (-not $reasons.ContainsKey($key)) { $reasons[$key] = [System.Collections.Generic.List[string]]::new() }
        if (-not $reasons[$key].Contains($Reason)) { $reasons[$key].Add($Reason) }
    }

    $adaptiveNames = @{}   # lower scope name -> row
    foreach ($s in $AdaptiveScopes) { $adaptiveNames[(Get-Prop $s 'Name').ToLower()] = $s }
    $adaptiveTargetsOneDrive = $false
    $adaptiveUnknown = $false

    foreach ($p in $RetentionPolicies) {
        if ((Get-Prop $p 'Enabled') -ne 'True') { continue }
        $pName = Get-Prop $p 'Name'
        # Adaptive scope policies: location fields are empty; the scope decides
        # membership and cannot be resolved here.
        $scopeRefs = ConvertTo-LocationList (Get-Prop $p 'AdaptiveScopeLocation')
        if ($scopeRefs.Count -gt 0) {
            foreach ($ref in $scopeRefs) {
                $scope = $adaptiveNames[$ref.ToLower()]
                if ($null -eq $scope) { $adaptiveUnknown = $true; continue }
                if ((Get-Prop $scope 'LocationType') -match '(?i)onedrive|^\s*(user|site)\s*$') { $adaptiveTargetsOneDrive = $true }
                # LocationType is User/Group/Site; User and Site scopes can include OneDrive -> validate manually
            }
        }
        $odLocs = ConvertTo-LocationList (Get-Prop $p 'OneDriveLocation')
        if ($odLocs.Count -eq 0) { continue }
        if ($odLocs -contains 'All') {
            foreach ($od in $OneDrives) { Add-Hold $od "Retention policy '$pName' (all OneDrive)" }
        } else {
            foreach ($loc in $odLocs) {
                $match = $byNormUrl[$loc.TrimEnd('/').ToLower()]
                if ($match) { Add-Hold $match "Retention policy '$pName' (targeted)" }
            }
        }
    }

    foreach ($h in $CaseHoldPolicies) {
        if ((Get-Prop $h 'Enabled') -ne 'True') { continue }
        $label = "eDiscovery hold '$(Get-Prop $h 'CaseName')/$(Get-Prop $h 'HoldPolicyName')'"
        $spLocs = ConvertTo-LocationList (Get-Prop $h 'SharePointLocation')
        if ($spLocs -contains 'All') {
            foreach ($od in $OneDrives) { Add-Hold $od $label }
        } else {
            foreach ($loc in ($spLocs | Where-Object { $_ -match '(?i)-my\.sharepoint\.com' })) {
                $match = $byNormUrl[$loc.TrimEnd('/').ToLower()]
                if ($match) { Add-Hold $match $label }
            }
        }
    }

    $rows = foreach ($key in $reasons.Keys) {
        $od = $byNormUrl[$key]
        [pscustomobject]@{
            Url     = Get-Prop $od 'Url'
            Owner   = Get-Prop $od 'Owner'
            OnHold  = 'True'
            Reasons = ($reasons[$key] | Sort-Object) -join '; '
        }
    }

    $adaptivePolicies = @($RetentionPolicies | Where-Object {
        (Get-Prop $_ 'Enabled') -eq 'True' -and (Get-Prop $_ 'AdaptiveScopeLocation').Trim() })
    return [pscustomobject]@{
        Rows                    = @($rows)
        Evaluated               = $RetentionCsvPresent
        AdaptiveScopesMissing   = ($adaptivePolicies.Count -gt 0 -and -not $AdaptiveScopesCsvPresent)
        AdaptiveTargetsOneDrive = $adaptiveTargetsOneDrive
        AdaptiveUnknown         = ($adaptivePolicies.Count -gt 0 -and ($adaptiveUnknown -or (-not $adaptiveTargetsOneDrive -and -not $AdaptiveScopesCsvPresent)))
    }
}

function Get-PowerPlatformOwnerStatus {
    <#
    .SYNOPSIS
        Adds OwnerStatus to Power App / flow rows by matching Owner against
        Users.csv rows (UPN, mail or display name - case-insensitive).
        OwnerStatus: Active | Disabled | Guest | NotFound | Unknown.
    #>
    param(
        [object[]]$Items = @(),
        [object[]]$Users = @()
    )
    $byKey = @{}
    foreach ($u in $Users) {
        foreach ($k in @((Get-Prop $u 'UserPrincipalName'), (Get-Prop $u 'Mail'), (Get-Prop $u 'DisplayName'))) {
            if ($k -and -not $byKey.ContainsKey($k.ToLower())) { $byKey[$k.ToLower()] = $u }
        }
    }
    foreach ($it in $Items) {
        $owner = (Get-Prop $it 'Owner').Trim()
        $status = 'Unknown'
        if ($owner) {
            $u = $byKey[$owner.ToLower()]
            if ($null -eq $u) {
                $status = 'NotFound'
            } elseif ((Get-Prop $u 'IsGuest') -eq 'True' -or (Get-Prop $u 'UserType') -eq 'Guest') {
                $status = 'Guest'
            } elseif ((Get-Prop $u 'AccountEnabled') -eq 'False') {
                $status = 'Disabled'
            } else {
                $status = 'Active'
            }
        }
        $it | Add-Member -NotePropertyName OwnerStatus -NotePropertyValue $status -Force
    }
    return @($Items)
}

# Connectors that are on-prem (gateway), external or custom: connections must
# be rebuilt in the target tenant. Names are the normalized api names used in
# the ConnectorsUsed column (shared_ prefix stripped). 'custom' matches any
# connector whose name also appears in PowerPlatformConnectors.csv.
$script:OnPremConnectorPatterns = @(
    '^sql$',              # SQL Server (often via data gateway)
    '^http$',             # raw HTTP - calls arbitrary endpoints
    '^httpwithazure(ad)?$',  # HTTP with Microsoft Entra ID
    '^webcontents?$',
    '^filesystem$',       # File System - on-prem gateway
    '^oracle$',
    '^sharepoint$',       # on-prem SharePoint (online is 'sharepointonline')
    '^ftp$', '^sftp$',
    'gateway'
)

function Get-ConnectorUsage {
    <#
    .SYNOPSIS
        Aggregates the ConnectorsUsed column ('; ' separated api names) across
        apps and flows. Connector names are normalized: the 'shared_' prefix and
        a trailing GUID/instance suffix are stripped. Rows: Connector, Apps,
        Flows, OnPremOrExternal.
    #>
    param(
        [object[]]$Apps  = @(),
        [object[]]$Flows = @(),
        [object[]]$CustomConnectors = @()   # PowerPlatformConnectors.csv rows
    )
    $customNames = @{}
    foreach ($c in $CustomConnectors) {
        foreach ($k in @((Get-Prop $c 'Name'), (Get-Prop $c 'DisplayName'), (Get-Prop $c 'ConnectorName'))) {
            if ($k) { $customNames[$k.ToLower()] = $true }
        }
    }
    $use = @{}   # normalized name -> @{ Display; Apps; Flows }
    function Add-Use {
        param([string]$Raw, [string]$Kind)
        $n = $Raw.Trim()
        if (-not $n) { return }
        $n = $n -replace '^shared_', ''
        # strip a trailing GUID or hex instance suffix (custom connector ids)
        $n = $n -replace '-[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$', ''
        $n = $n -replace '_[0-9a-fA-F]{32}$', ''
        $key = $n.ToLower()
        if (-not $use.ContainsKey($key)) { $use[$key] = @{ Display = $n; Apps = 0; Flows = 0 } }
        $use[$key][$Kind]++
    }
    foreach ($a in $Apps)  { foreach ($c in ((Get-Prop $a 'ConnectorsUsed') -split ';')) { Add-Use $c 'Apps' } }
    foreach ($f in $Flows) { foreach ($c in ((Get-Prop $f 'ConnectorsUsed') -split ';')) { Add-Use $c 'Flows' } }

    $rows = foreach ($key in $use.Keys) {
        $onPrem = $false
        foreach ($pat in $script:OnPremConnectorPatterns) { if ($key -match $pat) { $onPrem = $true; break } }
        if (-not $onPrem -and ($customNames.ContainsKey($key) -or $key -match 'custom')) { $onPrem = $true }
        [pscustomobject]@{
            Connector       = $use[$key].Display
            Apps            = $use[$key].Apps
            Flows           = $use[$key].Flows
            OnPremOrExternal= $onPrem
        }
    }
    return @($rows | Sort-Object { -($_.Apps + $_.Flows) }, Connector)
}

Export-ModuleMember -Function Get-OneDriveHoldStatus, Get-PowerPlatformOwnerStatus, Get-ConnectorUsage
