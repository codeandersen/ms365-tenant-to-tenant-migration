#requires -Version 7.2
<#
.SYNOPSIS
    Drives Cross-Tenant Identity Mapping (CTIM) one documented step at a time.

.DESCRIPTION
    Wraps the CTIM cmdlets so each run does exactly one phase, in the right tenant, with the
    documented safety rails:

      - The loopback redirect-URI trap: every step except AddServicePrincipal /
        RemoveServicePrincipal REFUSES to run while this window has an active
        Exchange Online (Get-ConnectionInformation) or Graph (Get-MgContext) session -
        run CTIM steps from a fresh PowerShell window per the doc.
      - Accept -Overwrite always downloads the current mapping file to the customer output
        folder first and aborts if the download fails - overwritten mappings are
        unrecoverable.
      - ShouldProcess messages state WHICH tenant the step belongs to, so a -WhatIf run
        doubles as a checklist.

    Tenant placement per the doc:
      source tenant : Copy (New-CtimCopyRequest), RemoveData (-CtimTenantRole Source)
      target tenant : Status, Accept, Map, Download, Upload, Write, Report,
                      RemoveData (-CtimTenantRole Target, default)
      both tenants  : AddServicePrincipal / RemoveServicePrincipal (pick -CtimTenantRole)

.PARAMETER Step
    AddServicePrincipal | Copy | Status | Accept | Reject | Map | Download | Upload | Write |
    Report | RemoveData | RemoveServicePrincipal

.PARAMETER CtimTenantRole
    Source or Target - which tenant this step runs in. Defaults: source for Copy,
    target for everything else; required for AddServicePrincipal/RemoveServicePrincipal/RemoveData.

.PARAMETER SourceTenantId
    Source tenant ID (GUID). Required for Copy, Accept, Map, Download, Upload, Write, Report,
    RemoveData(target).

.PARAMETER TargetTenantId
    Target tenant ID (GUID). Required for Copy and RemoveData(source).

.PARAMETER AdminUpn
    Sign-in name used for the Graph connection in AddServicePrincipal / RemoveServicePrincipal
    (those two steps connect; all other steps require a session-free window).

.PARAMETER SecurityGroupId
    ExternalDirectoryObjectId of the source scope group (Copy).

.PARAMETER RequestId
    CTIM request ID (Status, Accept, Reject, Report).

.PARAMETER MappingCsvFilePath
    Edited mapping CSV for Upload; output path for Download (default: customers folder).

.PARAMETER UseCsv
    Map via the uploaded CSV (New-CtimMapRequest -UseCsv) instead of PrimarySmtpAddress matching.

.PARAMETER AutoProgress
    Upload-CtimMappingData -AutoProgress (skips the separate -UseCsv map request).

.PARAMETER Overwrite
    Accept a copy request with -Overwrite. Forces a mapping-file download first; aborts if that
    download fails.

.PARAMETER Customer
    For Download (and the forced pre-Overwrite download): writes the file under
    customers/<Customer>/output/03-Identities/.

.EXAMPLE
    .\Invoke-CtimMapping.ps1 -Step Copy -SourceTenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' `
        -TargetTenantId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -SecurityGroupId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'

.EXAMPLE
    .\Invoke-CtimMapping.ps1 -Step Accept -SourceTenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' `
        -RequestId 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' -Overwrite -Customer fabrikam

.NOTES
    Untested against live tenants - validate in technical test/pilot.
    The hybrid (DirSynced MailUser) write path (Write-CtimIdentitiesInOnPremises) is out of scope -
    this playbook is cloud-only.
    Source: https://learn.microsoft.com/en-us/microsoft-365/enterprise/cross-tenant-identity-mapping
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('AddServicePrincipal', 'Copy', 'Status', 'Accept', 'Reject', 'Map', 'Download', 'Upload', 'Write', 'Report', 'RemoveData', 'RemoveServicePrincipal')]
    [string]$Step,

    [ValidateSet('Source', 'Target')]
    [string]$CtimTenantRole,

    [ValidateScript({ -not $_ -or [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$SourceTenantId,

    [ValidateScript({ -not $_ -or [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TargetTenantId,

    [string]$AdminUpn,
    [ValidateScript({ -not $_ -or [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$SecurityGroupId,
    [string]$RequestId,
    [string]$MappingCsvFilePath,
    [switch]$UseCsv,
    [switch]$AutoProgress,
    [switch]$Overwrite,
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module CrossTenantIdentityMapping -ErrorAction Stop

# ------------------------------------------------------------ tenant placement
$sourceSteps = 'Copy'
$servicePrincipalSteps = 'AddServicePrincipal', 'RemoveServicePrincipal'
if (-not $CtimTenantRole) {
    $CtimTenantRole = if ($sourceSteps -contains $Step) { 'Source' } elseif ($servicePrincipalSteps -contains $Step -or $Step -eq 'RemoveData') { $null } else { 'Target' }
    if (-not $CtimTenantRole) { throw "Step '$Step' runs in a specific tenant - pass -CtimTenantRole Source|Target." }
    Write-Host "Step '$Step' runs in the $CtimTenantRole tenant." -ForegroundColor Cyan
}

$tenantId = if ($CtimTenantRole -eq 'Source') { $SourceTenantId } else { $TargetTenantId }

# ------------------------------------------------------------ session guard
if ($servicePrincipalSteps -contains $Step) {
    # These two steps DO need Graph - connect tenant-guarded, run, disconnect.
    if (-not $tenantId) { throw "-Step $Step needs the tenant ID for the $CtimTenantRole tenant (-${CtimTenantRole}TenantId)." }
    if (-not $AdminUpn) { throw "-Step $Step needs -AdminUpn." }
    # Learn only says "Connect-MgGraph as Global Administrator" - the scope set below is an
    # assumption (SP/role provisioning); confirm in the technical test.
    $null = Connect-MigrationGraph -TenantId $tenantId -AdminUpn $AdminUpn -Scopes 'Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'RoleManagement.ReadWrite.Directory'
}
else {
    # The documented loopback trap: CTIM auth breaks when this session also holds EXO/Graph tokens.
    if ((Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue) -and (Get-ConnectionInformation)) {
        throw 'An Exchange Online session is active in this window. CTIM fails with a loopback redirect-URI error - open a fresh PowerShell window and retry.'
    }
    if ((Get-Command Get-MgContext -ErrorAction SilentlyContinue) -and (Get-MgContext)) {
        throw 'A Microsoft Graph session is active in this window. Disconnect-MgGraph (or use a fresh window) and retry - see the CTIM loopback redirect-URI note.'
    }
}

function Invoke-Step([string]$what, [scriptblock]$do) {
    if ($PSCmdlet.ShouldProcess("$CtimTenantRole tenant $tenantId", $what)) { & $do }
}

switch ($Step) {
    'AddServicePrincipal' {
        try {
            Invoke-Step 'Add-CtimServicePrincipal' {
                try { Add-CtimServicePrincipal }
                catch {
                    Write-Warning "Add-CtimServicePrincipal failed ($($_.Exception.Message)) - documented transient failure; retrying once."
                    Add-CtimServicePrincipal
                }
            }
        }
        finally { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
    }
    'RemoveServicePrincipal' {
        try { Invoke-Step 'Remove-CtimServicePrincipal' { Remove-CtimServicePrincipal } }
        finally { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
    }
    'Copy' {
        if (-not $SecurityGroupId -or -not $TargetTenantId) { throw 'Copy needs -SecurityGroupId (ExternalDirectoryObjectId of the source scope group) and -TargetTenantId.' }
        Invoke-Step "New-CtimCopyRequest -SecurityGroupGuid $SecurityGroupId -TargetTenantGuid $TargetTenantId (run in the SOURCE tenant)" {
            New-CtimCopyRequest -SecurityGroupGuid $SecurityGroupId -TargetTenantGuid $TargetTenantId
        }
        Write-Host 'Share the returned RequestID with the target tenant admin.' -ForegroundColor Yellow
    }
    'Status' {
        if (-not $RequestId) { throw 'Status needs -RequestId.' }
        Get-CtimRequest $RequestId
    }
    'Accept' {
        if (-not $RequestId -or -not $SourceTenantId) { throw 'Accept needs -RequestId and -SourceTenantId.' }
        if ($Overwrite) {
            # Documented: -Overwrite without a saved mapping file is unrecoverable. Download first; abort on failure.
            if (-not $Customer) { throw 'Accept -Overwrite needs -Customer so the backup mapping file lands under customers/.' }
            $out = New-OutputFolder -Customer $Customer -Phase '03-Identities'
            $backup = Join-Path $out "ctim-mapping-backup-before-overwrite.csv"
            Write-Host "Downloading current mapping first (safety net for -Overwrite) -> $backup" -ForegroundColor Yellow
            Download-CtimCopiedIdentities -SourceTenantGuid $SourceTenantId -FilePath $backup
            if (-not (Test-Path $backup)) { throw 'Mapping download failed - aborting instead of overwriting without a safety net.' }
        }
        Invoke-Step "Accept-CtimCopyRequest -RequestID $RequestId -SourceTenantGUID $SourceTenantId$(if ($Overwrite) { ' -Overwrite' }) (run in the TARGET tenant)" {
            if ($Overwrite) { Accept-CtimCopyRequest -RequestID $RequestId -SourceTenantGUID $SourceTenantId -Overwrite }
            else { Accept-CtimCopyRequest -RequestID $RequestId -SourceTenantGUID $SourceTenantId }
        }
        Write-Host 'Wait for the request to reach Completed (Get-CtimRequest) before mapping.' -ForegroundColor Yellow
    }
    'Reject' {
        if (-not $RequestId) { throw 'Reject needs -RequestId.' }
        Invoke-Step "Reject-CtimCopyRequest -RequestID $RequestId (run in the TARGET tenant)" {
            Reject-CtimCopyRequest -RequestID $RequestId
        }
    }
    'Map' {
        if (-not $SourceTenantId) { throw 'Map needs -SourceTenantId.' }
        $csvNote = if ($UseCsv) { ' -UseCsv' } else { ' (PrimarySmtpAddress matching)' }
        Invoke-Step "New-CtimMapRequest -SourceTenantGuid $SourceTenantId$csvNote (run in the TARGET tenant)" {
            if ($UseCsv) { New-CtimMapRequest -SourceTenantGuid $SourceTenantId -UseCsv }
            else { New-CtimMapRequest -SourceTenantGuid $SourceTenantId }
        }
    }
    'Download' {
        if (-not $SourceTenantId) { throw 'Download needs -SourceTenantId.' }
        if (-not $MappingCsvFilePath) {
            if (-not $Customer) { throw 'Download needs -MappingCsvFilePath or -Customer (file goes under customers/).' }
            $out = New-OutputFolder -Customer $Customer -Phase '03-Identities'
            $MappingCsvFilePath = Join-Path $out 'ctim-mapping.csv'
        }
        Invoke-Step "Download-CtimCopiedIdentities -SourceTenantGuid $SourceTenantId -FilePath $MappingCsvFilePath" {
            Download-CtimCopiedIdentities -SourceTenantGuid $SourceTenantId -FilePath $MappingCsvFilePath
        }
        Write-Host "Edit ONLY the TargetExternalDirectoryObjectId column (comma delimiter), then upload." -ForegroundColor Yellow
    }
    'Upload' {
        if (-not $SourceTenantId -or -not $MappingCsvFilePath) { throw 'Upload needs -SourceTenantId and -MappingCsvFilePath.' }
        Invoke-Step "Upload-CtimMappingData -SourceTenantGuid $SourceTenantId -MappingCsvFilePath $MappingCsvFilePath$(if ($AutoProgress) { ' -AutoProgress' })" {
            if ($AutoProgress) { Upload-CtimMappingData -SourceTenantGuid $SourceTenantId -MappingCsvFilePath $MappingCsvFilePath -AutoProgress }
            else { Upload-CtimMappingData -SourceTenantGuid $SourceTenantId -MappingCsvFilePath $MappingCsvFilePath }
        }
        if (-not $AutoProgress) { Write-Host 'When the upload is Completed, run -Step Map -UseCsv.' -ForegroundColor Yellow }
    }
    'Write' {
        if (-not $SourceTenantId) { throw 'Write needs -SourceTenantId.' }
        Invoke-Step "New-CtimWriteRequest -SourceTenantGuid $SourceTenantId - writes ExchangeGuid/ArchiveGuid/X500/PrimarySmtp onto target MailUsers (cloud-only path; run in the TARGET tenant)" {
            New-CtimWriteRequest -SourceTenantGuid $SourceTenantId
        }
        Write-Host 'Validate with Get-CtimReport / Download-CtimCopiedIdentities until MigrationStatus = Completed, then run Test-IdentityMapping -Mode Verify.' -ForegroundColor Yellow
    }
    'Report' {
        if (-not $SourceTenantId) { throw 'Report needs -SourceTenantId.' }
        if ($RequestId) { Get-CtimReport -SourceTenantGuid $SourceTenantId -RequestId $RequestId }
        else { Get-CtimReport -SourceTenantGuid $SourceTenantId }
    }
    'RemoveData' {
        Write-Host 'WARNING: do not run Remove-CtimData while any migration batches are running -' -ForegroundColor Yellow
        Write-Host 'it removes users with completed mailbox migrations from identity mapping and' -ForegroundColor Yellow
        Write-Host 'breaks their Teams chats/meetings and future reruns. To add users, rerun the map' -ForegroundColor Yellow
        Write-Host 'without RemoveData instead. (migration-orchestrator-7-end-user-exp)' -ForegroundColor Yellow
        if ($CtimTenantRole -eq 'Target') {
            if (-not $SourceTenantId) { throw 'RemoveData (target) needs -SourceTenantId.' }
            Invoke-Step "Remove-CtimData -SourceTenantGuid $SourceTenantId (run in the TARGET tenant)" {
                Remove-CtimData -SourceTenantGuid $SourceTenantId
            }
        }
        else {
            if (-not $TargetTenantId) { throw 'RemoveData (source) needs -TargetTenantId.' }
            Invoke-Step "Remove-CtimData -TargetTenantGuid $TargetTenantId (run in the SOURCE tenant)" {
                Remove-CtimData -TargetTenantGuid $TargetTenantId
            }
        }
        Write-Host 'Removing mapped users does not un-write their attributes. Recreate the copy request to remap.' -ForegroundColor Yellow
    }
}
