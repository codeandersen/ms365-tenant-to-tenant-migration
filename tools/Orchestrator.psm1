#requires -Version 7.2
Set-StrictMode -Version Latest

$script:ValidWorkloads = 'Exchange', 'ODSP', 'Teams', 'Meeting'
$script:RequiredUserColumns = @(
    'SourceUpn', 'SourcePrimarySmtp', 'DisplayName', 'FirstName', 'LastName',
    'TargetUpn', 'TargetPrimarySmtp', 'UsageLocation', 'TargetLicenseSku',
    'Batch', 'CompleteAfterDateTimeUtc', 'Workloads'
)

function ConvertTo-WorkloadList {
    <#
    .SYNOPSIS
        Read-only helper: parses and validates a workload list (e.g. 'Exchange;ODSP;Teams;Meeting').

    .DESCRIPTION
        Accepts a string or string[] of workload names, keeps only the four names the Migration
        Orchestrator knows (Exchange, ODSP, Teams, Meeting) in canonical casing, and throws when an
        unknown name shows up or Meeting is requested without Teams and Exchange - Meetings move
        through the Teams stack and need Exchange for the calendar.

    .PARAMETER Workloads
        A ';'- or ','-delimited string, or a string array, of workload names.

    .EXAMPLE
        ConvertTo-WorkloadList -Workloads 'exchange;teams;meeting'
        Returns 'Exchange','Teams','Meeting'.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [object]$Workloads
    )

    $raw = if ($Workloads -is [string]) { $Workloads -split '[;,]' } else { @($Workloads) }
    $list = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($w in $raw) {
        $t = "$w".Trim()
        if (-not $t) { continue }
        $match = @($script:ValidWorkloads | Where-Object { $_ -ieq $t })
        if ($match) { if ($list -notcontains $match[0]) { $list.Add($match[0]) } }
        else { $errors.Add("unknown workload '$t' (valid: $($script:ValidWorkloads -join ', '))") }
    }
    if ($errors.Count) { throw "Invalid workloads: $($errors -join '; ')" }
    if ($list -contains 'Meeting' -and (($list -notcontains 'Teams') -or ($list -notcontains 'Exchange'))) {
        throw "Workload 'Meeting' requires 'Teams' and 'Exchange' in the same batch (Microsoft recommends all workloads together)."
    }
    if (-not $list.Count) { throw 'No workloads given. Use one or more of: ' + ($script:ValidWorkloads -join ', ') }
    return [string[]]$list
}

function Import-MigrationUserList {
    <#
    .SYNOPSIS
        Read-only helper: imports and validates the canonical migration user CSV.

    .DESCRIPTION
        Reads the migration-users.csv (see 01-Design/templates/migration-users.csv) and validates it
        in one pass, throwing a single error that lists every problem found:
        required columns present; SourceUpn/TargetUpn/TargetPrimarySmtp/SourcePrimarySmtp/Batch
        non-empty; SourceUpn and TargetUpn unique (case-insensitive); CompleteAfterDateTimeUtc a
        parseable ISO 8601 UTC timestamp; Workloads valid per ConvertTo-WorkloadList.

    .PARAMETER Path
        Path to the migration user CSV (comma-delimited, UTF-8).

    .EXAMPLE
        $users = Import-MigrationUserList -Path .\migration-users.csv
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $rows = @(Import-Csv -Path $Path -Encoding utf8)
    if (-not $rows.Count) { throw "$Path has no data rows." }

    $problems = [System.Collections.Generic.List[string]]::new()

    $cols = @($rows[0].PSObject.Properties.Name)
    foreach ($c in $script:RequiredUserColumns) {
        if ($cols -notcontains $c) { $problems.Add("missing column '$c'") }
    }
    if ($problems.Count) { throw "$Path failed validation: $($problems -join '; ')" }

    $seenSource = @{}; $seenTarget = @{}
    $n = 0
    foreach ($r in $rows) {
        $n++
        $where = "row $n ($($r.SourceUpn))"
        foreach ($c in 'SourceUpn', 'TargetUpn', 'SourcePrimarySmtp', 'TargetPrimarySmtp', 'Batch', 'DisplayName', 'UsageLocation', 'TargetLicenseSku') {
            if ([string]::IsNullOrWhiteSpace("$($r.$c)")) { $problems.Add("$where : empty $c") }
        }
        foreach ($pair in @(@('SourceUpn', $seenSource), @('TargetUpn', $seenTarget))) {
            $key = "$($r.($pair[0]))".Trim().ToLower()
            if ($key -and $pair[1].ContainsKey($key)) { $problems.Add("$where : duplicate $($pair[0]) '$key' (first seen row $($pair[1][$key]))") }
            elseif ($key) { $pair[1][$key] = $n }
        }
        if ("$($r.CompleteAfterDateTimeUtc)".Trim()) {
            $dt = [datetime]::MinValue
            if (-not [datetime]::TryParse("$($r.CompleteAfterDateTimeUtc)", [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$dt)) {
                $problems.Add("$where : CompleteAfterDateTimeUtc '$($r.CompleteAfterDateTimeUtc)' is not a parseable UTC timestamp (use ISO 8601, e.g. 2026-09-05T22:00:00Z)")
            }
        }
        else { $problems.Add("$where : empty CompleteAfterDateTimeUtc") }
        if ("$($r.Workloads)".Trim()) {
            try { $null = ConvertTo-WorkloadList -Workloads $r.Workloads } catch { $problems.Add("$where : $($_.Exception.Message)") }
        }
        else { $problems.Add("$where : empty Workloads") }
    }
    if ($problems.Count) { throw "$Path failed validation:`n - " + ($problems -join "`n - ") }
    return $rows
}

function Split-MigrationBatch {
    <#
    .SYNOPSIS
        Read-only helper: groups validated user rows into migration batches of at most -MaxBatchSize users.

    .DESCRIPTION
        Groups rows by their Batch column. A group larger than -MaxBatchSize (default 100, the
        Orchestrator maximum) is split into batches named '<Batch>-01', '-02' and so on; a group
        within the limit keeps its Batch name (suffixed only if needed for uniqueness). All rows in
        a group must share CompleteAfterDateTimeUtc and Workloads - a batch is submitted with a
        single cutover time and workload set, so mixed groups throw.

    .PARAMETER Users
        User rows from Import-MigrationUserList.

    .PARAMETER MaxBatchSize
        Maximum users per batch. Default 100.

    .EXAMPLE
        $batches = Split-MigrationBatch -Users $users
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Users,

        [int]$MaxBatchSize = 100
    )

    $groups = $Users | Group-Object -Property { "$($_.Batch)".Trim() }
    $out = [System.Collections.Generic.List[object]]::new()
    $usedNames = @{}
    foreach ($g in $groups) {
        $dates = @($g.Group | ForEach-Object { "$($_.CompleteAfterDateTimeUtc)".Trim() } | Sort-Object -Unique)
        $wl = @($g.Group | ForEach-Object { (@(ConvertTo-WorkloadList $_.Workloads) -join ';') } | Sort-Object -Unique)
        if ($dates.Count -gt 1) { throw "Batch '$($g.Name)' mixes CompleteAfterDateTimeUtc values ($($dates -join ', ')). A batch has a single cutover time - split it." }
        if ($wl.Count -gt 1) { throw "Batch '$($g.Name)' mixes Workloads values ($($wl -join ' / ')). A batch has a single workload set - split it." }

        $chunks = @(for ($i = 0; $i -lt $g.Group.Count; $i += $MaxBatchSize) {
            , @($g.Group[$i..([Math]::Min($i + $MaxBatchSize - 1, $g.Group.Count - 1))])
        })
        $part = 0
        foreach ($chunk in $chunks) {
            $part++
            $name = if ($chunks.Count -gt 1) { '{0}-{1:d2}' -f $g.Name, $part } else { $g.Name }
            if ($usedNames.ContainsKey($name)) {
                $n = 2
                while ($usedNames.ContainsKey("$name-$n")) { $n++ }
                $name = "$name-$n"
            }
            $usedNames[$name] = $true
            $out.Add([pscustomobject]@{
                Name                    = $name
                CompleteAfterDateTimeUtc = $dates[0]
                Workloads               = [string[]]($wl[0] -split ';')
                Users                   = [object[]]$chunk
            })
        }
    }
    return $out
}

function ConvertTo-CrossTenantMigrationJobBody {
    <#
    .SYNOPSIS
        Read-only helper: builds the request body for New-MgBetaCrossTenantMigrationJob -BodyParameter.

    .DESCRIPTION
        Returns the hashtable documented in "Running the migration" (Microsoft Learn): displayName,
        completeAfterDateTime, sourceTenantId, exchangeSettings { targetDeliveryDomain,
        sourceEndpoint }, resources, resourceType "Users", workloads.

    .PARAMETER Name
        Unique batch display name.

    .PARAMETER CompleteAfterDateTimeUtc
        ISO 8601 UTC timestamp: earliest acceptable cutover time.

    .PARAMETER ResourceIds
        ExternalDirectoryObjectIds (GUIDs) of the target users in the batch.

    .PARAMETER SourceTenantId
        Source tenant ID (GUID).

    .PARAMETER SourceEndpoint
        Name of the migration endpoint created on the target tenant.

    .PARAMETER TargetDeliveryDomain
        Target tenant domain, e.g. fabrikam.onmicrosoft.com.

    .PARAMETER Workloads
        Workload names (validated via ConvertTo-WorkloadList).

    .EXAMPLE
        $body = ConvertTo-CrossTenantMigrationJobBody -Name 'wave1' -CompleteAfterDateTimeUtc '2026-09-05T22:00:00Z' `
            -ResourceIds $ids -SourceTenantId $srcTenant -SourceEndpoint 'CTM-Endpoint' `
            -TargetDeliveryDomain 'fabrikam.onmicrosoft.com' -Workloads 'Exchange;ODSP;Teams;Meeting'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$CompleteAfterDateTimeUtc,
        [Parameter(Mandatory)][string[]]$ResourceIds,
        [Parameter(Mandatory)][string]$SourceTenantId,
        [Parameter(Mandatory)][string]$SourceEndpoint,
        [Parameter(Mandatory)][string]$TargetDeliveryDomain,
        [Parameter(Mandatory)]$Workloads
    )

    return [ordered]@{
        displayName            = $Name
        completeAfterDateTime  = $CompleteAfterDateTimeUtc
        sourceTenantId         = $SourceTenantId
        exchangeSettings       = @{
            targetDeliveryDomain = $TargetDeliveryDomain
            sourceEndpoint       = $SourceEndpoint
        }
        resources              = [string[]]$ResourceIds
        resourceType           = 'Users'
        workloads              = [string[]](ConvertTo-WorkloadList -Workloads $Workloads)
    }
}

function Test-ValidationFresh {
    <#
    .SYNOPSIS
        Read-only helper: is a batch validation still fresh enough to call migrate?

    .DESCRIPTION
        Migration may only start when validation passed within the last 7 days. Returns $true when
        -ValidatedAtUtc is within -MaxAgeDays of -NowUtc (and not in the future).

    .EXAMPLE
        Test-ValidationFresh -ValidatedAtUtc (Get-Date).AddDays(-5) -NowUtc (Get-Date)
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][datetime]$ValidatedAtUtc,
        [Parameter(Mandatory)][datetime]$NowUtc,
        [int]$MaxAgeDays = 7
    )
    $age = $NowUtc.ToUniversalTime() - $ValidatedAtUtc.ToUniversalTime()
    return ($age.TotalMinutes -ge 0 -and $age.TotalDays -lt $MaxAgeDays)
}

function Compare-MigrationIdentity {
    <#
    .SYNOPSIS
        Read-only helper: checks a target MailUser carries everything CTIM should have written.

    .DESCRIPTION
        Compares a source mailbox identity row against the target MailUser object and the tenant's
        accepted domains. Returns { Pass, Problems[] }. A pass requires: the target is a MailUser
        (not a mailbox), ExchangeGuid equal and non-empty, ArchiveGuid equal when the source has an
        archive, 'x500:<source LegacyExchangeDN>' and every source x500 present in the target
        EmailAddresses, and a PrimarySmtpAddress in an accepted domain.

    .PARAMETER Source
        Row with ExchangeGuid, ArchiveGuid, ArchiveStatus, LegacyExchangeDN, X500Addresses (';'-list).

    .PARAMETER Target
        Row with RecipientTypeDetails, ExchangeGuid, ArchiveGuid, EmailAddresses, PrimarySmtpAddress.

    .PARAMETER AcceptedDomains
        Accepted-domain names in the target tenant (lowercase ok).

    .EXAMPLE
        Compare-MigrationIdentity -Source $srcRow -Target $mailUser -AcceptedDomains $domains
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)]$Target,
        [Parameter(Mandatory)][string[]]$AcceptedDomains
    )

    $problems = [System.Collections.Generic.List[string]]::new()
    $accepted = @($AcceptedDomains | ForEach-Object { "$_".ToLower() })

    if ("$($Target.RecipientTypeDetails)" -ne 'MailUser') {
        $problems.Add("target is '$($Target.RecipientTypeDetails)', expected MailUser (a licensed mailbox breaks the migration)")
    }

    $srcXg = "$($Source.ExchangeGuid)".Trim(); $dstXg = "$($Target.ExchangeGuid)".Trim()
    if (-not $srcXg) { $problems.Add('source ExchangeGuid empty') }
    elseif (-not $dstXg -or $dstXg -eq '00000000-0000-0000-0000-000000000000') { $problems.Add('target ExchangeGuid empty - CTIM write has not run') }
    elseif ($srcXg -ine $dstXg) { $problems.Add("ExchangeGuid mismatch: source $srcXg, target $dstXg") }

    $srcHasArchive = "$($Source.ArchiveStatus)" -eq 'Active' -and "$($Source.ArchiveGuid)".Trim()
    if ($srcHasArchive -and "$($Source.ArchiveGuid)" -ine "$($Target.ArchiveGuid)") {
        $problems.Add("ArchiveGuid mismatch: source $($Source.ArchiveGuid), target '$($Target.ArchiveGuid)'")
    }

    $dstAddrs = @($Target.EmailAddresses | ForEach-Object { "$_".ToLower() })
    $expectedX500 = [System.Collections.Generic.List[string]]::new()
    if ("$($Source.LegacyExchangeDN)".Trim()) { $expectedX500.Add("x500:$($Source.LegacyExchangeDN)") }
    foreach ($x in ("$($Source.X500Addresses)" -split ';' | Where-Object { $_ })) {
        if ($expectedX500 -notcontains $x.ToLower() -and $expectedX500 -notcontains $x) { $expectedX500.Add($x) }
    }
    foreach ($x in $expectedX500) {
        if ($dstAddrs -notcontains $x.ToLower()) { $problems.Add("missing proxy '$x' on target") }
    }

    $primDom = ("$($Target.PrimarySmtpAddress)" -split '@')[-1].ToLower()
    if ($accepted -notcontains $primDom) {
        $problems.Add("target PrimarySmtpAddress '$($Target.PrimarySmtpAddress)' uses non-accepted domain '$primDom'")
    }

    return [pscustomobject]@{ Pass = ($problems.Count -eq 0); Problems = [string[]]$problems }
}

function Get-GraphValue {
    <#
    .SYNOPSIS
        Read-only helper: reads a property from a Graph SDK object, whether it is a typed property
        or sitting in AdditionalProperties.

    .DESCRIPTION
        Graph beta objects sometimes surface fields as typed properties, sometimes only inside
        AdditionalProperties. Looks up -Name as a typed property first; if missing or null, does a
        case-insensitive key lookup in AdditionalProperties. Returns $null when not found.
        NOTE: never write "$($obj.Prop -or $obj.Other)" for this - the -or returns "True"/"False",
        not the value; that bug class is what this helper exists to prevent.

    .PARAMETER Object
        The SDK object (PSCustomObject / generated model).

    .PARAMETER Name
        Property name, e.g. 'status', 'displayName', 'id'.

    .EXAMPLE
        $status = Get-GraphValue -Object $job -Name 'status'
    #>
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name
    )
    if ($null -eq $Object) { return $null }
    $typed = $Object.PSObject.Properties[$Name]
    if ($typed -and $null -ne $typed.Value -and "$($typed.Value)" -ne '') { return $typed.Value }
    $apProp = $Object.PSObject.Properties['AdditionalProperties']
    $ap = if ($apProp) { $apProp.Value } else { $null }
    if ($ap) {
        foreach ($k in $ap.Keys) {
            if ($k -ieq $Name -and $null -ne $ap[$k] -and "$($ap[$k])" -ne '') { return $ap[$k] }
        }
    }
    return $null
}

function Select-LicensableUser {
    <#
    .SYNOPSIS
        Read-only helper: decides which users may be licensed (CTIM write verified, recently).

    .DESCRIPTION
        Joins the user list to the verification rows produced by Test-IdentityMapping -Mode Verify.
        A user is licensable only when a verification row exists, it Passes, and its VerifiedAtUtc
        is at most -MaxAgeHours (default 24) before -NowUtc. Returns { Licensable, Refused } where
        Refused rows carry a Reason.

    .PARAMETER Users
        User rows from Import-MigrationUserList.

    .PARAMETER Verification
        Rows with TargetUpn, Pass (bool/string) and VerifiedAtUtc.

    .PARAMETER NowUtc
        Reference time (tests inject it).

    .PARAMETER MaxAgeHours
        Maximum verification age. Default 24.

    .EXAMPLE
        Select-LicensableUser -Users $users -Verification $v -NowUtc (Get-Date).ToUniversalTime()
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Users,
        [Parameter(Mandatory)][object[]]$Verification,
        [Parameter(Mandatory)][datetime]$NowUtc,
        [int]$MaxAgeHours = 24
    )

    $byUpn = @{}
    foreach ($v in $Verification) { $byUpn["$($v.TargetUpn)".ToLower()] = $v }

    $licensable = [System.Collections.Generic.List[object]]::new()
    $refused = [System.Collections.Generic.List[object]]::new()
    foreach ($u in $Users) {
        $key = "$($u.TargetUpn)".ToLower()
        $reason = $null
        if (-not $byUpn.ContainsKey($key)) { $reason = 'no verification row - run Test-IdentityMapping -Mode Verify first' }
        else {
            $v = $byUpn[$key]
            $passed = "$($v.Pass)" -imatch '^(true|pass|yes|1)$'
            if (-not $passed) { $reason = "verification failed: $($v.Problems)" }
            else {
                $at = [datetime]::MinValue
                if (-not [datetime]::TryParse("$($v.VerifiedAtUtc)", [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$at)) {
                    $reason = "verification row has unparseable VerifiedAtUtc '$($v.VerifiedAtUtc)'"
                }
                elseif (($NowUtc.ToUniversalTime() - $at.ToUniversalTime()).TotalHours -gt $MaxAgeHours) {
                    $reason = "verification is $([math]::Round(($NowUtc.ToUniversalTime() - $at.ToUniversalTime()).TotalHours, 1))h old (max ${MaxAgeHours}h) - re-verify before licensing"
                }
            }
        }
        if ($reason) { $refused.Add([pscustomobject]@{ User = $u; Reason = $reason }) }
        else { $licensable.Add($u) }
    }
    return [pscustomobject]@{ Licensable = [object[]]$licensable; Refused = [object[]]$refused }
}

Export-ModuleMember -Function Import-MigrationUserList, ConvertTo-WorkloadList, Split-MigrationBatch,
    ConvertTo-CrossTenantMigrationJobBody, Test-ValidationFresh, Compare-MigrationIdentity, Select-LicensableUser, Get-GraphValue
