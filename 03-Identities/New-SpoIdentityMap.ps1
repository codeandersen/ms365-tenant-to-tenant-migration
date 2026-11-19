#requires -Version 7.2
<#
.SYNOPSIS
    Builds (and optionally uploads/verifies) the full SharePoint/OneDrive cross-tenant
    identity map that preserves access for users, guests and groups.

.DESCRIPTION
    The Orchestrator/CTIM identity mapping covers only migrating users; this map is
    what keeps OneDrive/SharePoint permissions working for everyone else - Learn calls
    it optional, the playbook treats it as required.

    Inputs:
      - migration-users.csv (01 list)   -> User rows, RegularUser. TargetUpn is used
        (the identity at migration time - FinalUpn after the domain move is NOT used).
      - guest-map.csv                   -> GuestUser rows (target member or guest).
      - group-map.csv                   -> RegularGroup rows (Security/MailEnabled/
        Distribution, GroupName = TargetGroupObjectId) and O365Group rows (col 5 =
        target alias) for M365 groups.
      - SourceTenantId (GUID).

    The script ALWAYS regenerates the complete map - Add-SPOTenantIdentityMap
    overwrites the previous map, so re-run and re-upload after every change.

    File format: no header, comma-delimited, six columns, UTF-8 *without* BOM (a BOM
    would corrupt the first field) - written via [IO.File]::WriteAllLines. Non-ASCII
    display names (æøå) survive. All validation problems are reported at once;
    the file is only written when validation is clean.

    -Upload    target side: guarded Connect-MigrationSharePoint + Add-SPOTenantIdentityMap.
    -Verify    samples -VerifySample entries with Get-SPOTenantIdentityMappingUser /
               Get-SPOTenantIdentityMappingGroup and reports missing ones.
    -CheckCompatibility  source side: Get-SPOCrossTenantCompatibilityStatus; Compatible
               or Warning pass, Incompatible throws.

    https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration-step4
    https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration-step5
    https://learn.microsoft.com/en-us/microsoft-365/migration/cross-tenant-onedrive-migration-step7

.PARAMETER TenantId
    Tenant the connection is made to: SOURCE for -CheckCompatibility, TARGET for -Upload/-Verify.

.PARAMETER SourceTenantId
    Source tenant GUID written into column 2 of every row.

.PARAMETER AdminUrl
    SPO admin URL of -TenantId, e.g. https://fabrikam-admin.sharepoint.com.

.PARAMETER PartnerCrossTenantHostUrl
    Target host URL for -CheckCompatibility, e.g. https://fabrikam.sharepoint.com.

.EXAMPLE
    .\New-SpoIdentityMap.ps1 -TenantId $target -AdminUpn admin@fabrikam.com -AdminUrl https://fabrikam-admin.sharepoint.com `
        -SourceTenantId $source -UserListPath .\migration-users.csv -GuestMapPath .\guest-map.csv -GroupMapPath .\group-map.csv `
        -Customer contoso -Upload -Verify

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    Cmdlets used: Add-SPOTenantIdentityMap, Get-SPOTenantIdentityMappingUser,
    Get-SPOTenantIdentityMappingGroup, Get-SPOCrossTenantCompatibilityStatus.
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$SourceTenantId,

    [Parameter(Mandatory)]
    [string]$UserListPath,

    [Parameter(Mandatory)]
    [string]$Customer,

    [string]$GuestMapPath,
    [string]$GroupMapPath,

    [ValidatePattern('^https://[^\.]+-admin\.sharepoint\.com/?$')]
    [string]$AdminUrl,

    [ValidatePattern('^https://[^\.]+\.sharepoint\.com/?$')]
    [string]$PartnerCrossTenantHostUrl,

    [switch]$Upload,
    [switch]$Verify,
    [switch]$CheckCompatibility,
    [int]$VerifySample = 10
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

# ---- build rows
$lines = [System.Collections.Generic.List[string]]::new()
foreach ($u in @(Import-MigrationUserList -Path $UserListPath)) {
    $lines.Add((ConvertTo-SpoIdentityMapRow -SourceTenantId $SourceTenantId -Kind User `
        -SourceKey $u.SourceUpn -TargetUpn $u.TargetUpn -TargetEmail $u.TargetPrimarySmtp -UserType RegularUser))
}
if ($GuestMapPath -and (Test-Path $GuestMapPath)) {
    foreach ($g in @(Import-Csv $GuestMapPath | Where-Object { "$($_.TargetUpn)".Trim() -or "$($_.TargetUserId)".Trim() })) {
        $lines.Add((ConvertTo-SpoIdentityMapRow -SourceTenantId $SourceTenantId -Kind User `
            -SourceKey $g.SourceGuestUpn -TargetUpn $g.TargetUpn -TargetEmail $g.TargetMail -UserType GuestUser))
    }
}
if ($GroupMapPath -and (Test-Path $GroupMapPath)) {
    foreach ($g in @(Import-Csv $GroupMapPath | Where-Object { "$($_.TargetGroupId)".Trim() })) {
        if ($g.Kind -eq 'M365' -or $g.Kind -eq 'DynamicM365') {
            $lines.Add((ConvertTo-SpoIdentityMapRow -SourceTenantId $SourceTenantId -Kind O365Group `
                -SourceKey $g.SourceGroupId -TargetGroupId $g.TargetGroupId -GroupAlias $g.TargetAlias))
        } else {
            $lines.Add((ConvertTo-SpoIdentityMapRow -SourceTenantId $SourceTenantId -Kind Group `
                -SourceKey $g.SourceGroupId -TargetGroupId $g.TargetGroupId))
        }
    }
}

$problems = @(Test-SpoIdentityMap -Rows $lines)
if ($problems) { throw "Identity map failed validation:`n  $($problems -join "`n  ")" }

$out = New-OutputFolder -Customer $Customer -Phase '03-Identities'
$path = Join-Path $out 'spo-identity-map.csv'
# UTF-8 without BOM: a BOM would corrupt the first field of the headerless file
[IO.File]::WriteAllLines($path, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "$($lines.Count) identity-map rows -> $path" -ForegroundColor Green

# ---- upload
if ($Upload) {
    if (-not $AdminUrl) { throw '-AdminUrl is required for -Upload.' }
    Write-Warning 'Add-SPOTenantIdentityMap OVERWRITES the previous map - always upload the complete map.'
    $null = Connect-MigrationSharePoint -TenantId $TenantId -AdminUrl $AdminUrl
    if ($PSCmdlet.ShouldProcess($path, 'Add-SPOTenantIdentityMap (replaces the whole map)')) {
        Add-SPOTenantIdentityMap -IdentityMapPath (Resolve-Path $path).Path
        Write-Host 'Identity map uploaded.' -ForegroundColor Green
    }
}

# ---- verify
if ($Verify) {
    if (-not $Upload) {
        if (-not $AdminUrl) { throw '-AdminUrl is required for -Verify.' }
        $null = Connect-MigrationSharePoint -TenantId $TenantId -AdminUrl $AdminUrl
    }
    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($lines | Get-Random -Count ([Math]::Min($VerifySample, $lines.Count)))) {
        $f = $line -split ','
        try {
            if ($f[0] -eq 'User') {
                $r = Get-SPOTenantIdentityMappingUser -Field SourceUserKey -Value $f[2]
                if (-not $r) { $missing.Add($line) }
            } else {
                $r = Get-SPOTenantIdentityMappingGroup -Field SourceGroupKey -Value $f[2]
                if (-not $r) { $missing.Add($line) }
            }
        } catch { $missing.Add("$line  [$($_.Exception.Message)]") }
    }
    if ($missing) { Write-Warning "Verification missing $($missing.Count) of ${VerifySample}:`n  $($missing -join "`n  ")" }
    else { Write-Host "Verification: $VerifySample sampled entries found." -ForegroundColor Green }
}

# ---- compatibility
if ($CheckCompatibility) {
    if (-not $AdminUrl) { throw '-AdminUrl is required for -CheckCompatibility (source admin URL).' }
    if (-not $PartnerCrossTenantHostUrl) { throw '-PartnerCrossTenantHostUrl is required for -CheckCompatibility.' }
    $null = Connect-MigrationSharePoint -TenantId $TenantId -AdminUrl $AdminUrl
    $status = Get-SPOCrossTenantCompatibilityStatus -PartnerCrossTenantHostURL $PartnerCrossTenantHostUrl
    # The result property name isn't documented; inspect the whole object so an Incompatible state can't slip through.
    $statusText = ($status | Format-List * | Out-String).Trim()
    Write-Host "Compatibility:`n$statusText" -ForegroundColor Cyan
    if (-not $statusText) { throw 'Get-SPOCrossTenantCompatibilityStatus returned nothing - treat as not verified.' }
    if ($statusText -match '\bIncompatible\b') {
        throw "SPO cross-tenant compatibility: Incompatible ($($status | ConvertTo-Json -Compress)) - resolve before moving data."
    }
}
