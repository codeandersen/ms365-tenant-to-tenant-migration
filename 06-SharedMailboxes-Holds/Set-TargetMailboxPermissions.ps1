#requires -Version 7.2
<#
.SYNOPSIS
    Rebuilds Full Access, Send As and Send on Behalf permissions on the target tenant, mapping
    source trustees to target identities through the migration user list and the shared-mailbox
    mapping - unmapped trustees are reported, never guessed.

.DESCRIPTION
    Reads MailboxPermissions.csv (from Export-MailboxPermissions.ps1) plus two mappings:
      - the 01-Design user list (SourcePrimarySmtp -> TargetUpn)
      - the shared-mailbox mapping CSV (SourcePrimarySmtp -> TargetPrimarySmtp)
    Every mailbox and trustee must resolve through those files via Resolve-PermissionTrustee;
    anything unmapped (or 'unresolved:'/'external:' from the export) is logged Skipped.

    NOTE: Send As on shared mailboxes is a pilot-test item - the cross-tenant mailbox migration
    doc says store permissions survive as described in "Manage permissions for recipients in
    Exchange Online", but verify delegation behaviour in the technical pilot.

.PARAMETER TenantId
    Target tenant ID (GUID).

.PARAMETER AdminUpn
    Target admin sign-in name.

.PARAMETER PermissionsCsv
    MailboxPermissions.csv from Export-MailboxPermissions.ps1.

.PARAMETER UserListPath
    migration-users.csv (source->target mapping for user mailboxes).

.PARAMETER SharedMappingCsv
    Optional: shared-mailbox mapping CSV (SourcePrimarySmtp, TargetPrimarySmtp).

.PARAMETER Customer
    Writes the run report under customers/<Customer>/output/06-SharedMailboxes-Holds/.

.EXAMPLE
    .\Set-TargetMailboxPermissions.ps1 -TenantId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' -AdminUpn 'admin@fabrikam.com' `
        -PermissionsCsv .\MailboxPermissions.csv -UserListPath .\migration-users.csv `
        -SharedMappingCsv .\shared-mailbox-mapping.csv -Customer contoso -WhatIf

.NOTES
    Untested against live tenants - validate in technical test/pilot.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ [guid]::TryParse($_, [ref][guid]::Empty) })]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$AdminUpn,

    [Parameter(Mandatory)]
    [string]$PermissionsCsv,

    [Parameter(Mandatory)]
    [string]$UserListPath,

    [string]$SharedMappingCsv,

    [Parameter(Mandatory)]
    [string]$Customer
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\tools\Common.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\tools\Orchestrator.psm1') -Force

$map = @{}
foreach ($u in Import-MigrationUserList -Path $UserListPath) {
    $map["$($u.SourcePrimarySmtp)".ToLower()] = "$($u.TargetUpn)"
    $map["$($u.SourceUpn)".ToLower()] = "$($u.TargetUpn)"
}
if ($SharedMappingCsv) {
    foreach ($m in Import-Csv $SharedMappingCsv) {
        $map["$($m.SourcePrimarySmtp)".ToLower()] = "$($m.TargetPrimarySmtp)".Trim()
    }
}

$null = Connect-MigrationExchange -TenantId $TenantId -AdminUpn $AdminUpn

$log = [System.Collections.Generic.List[object]]::new()
function Add-Result($Obj, $Status, $Detail) {
    $log.Add([pscustomobject]@{ Object = $Obj; Status = $Status; Detail = $Detail })
    $c = @{ Added = 'Green'; Exists = 'Gray'; Skipped = 'Yellow'; WhatIf = 'Cyan'; Problem = 'Red' }[$Status]
    Write-Host ("  [{0}] {1}: {2}" -f $Status, $Obj, $Detail) -ForegroundColor $c
}

foreach ($p in Import-Csv $PermissionsCsv) {
    $label = "$($p.Right): $($p.Trustee) on $($p.Mailbox)"
    if ($p.Trustee -like 'unresolved:*' -or $p.Trustee -like 'external:*') { Add-Result $label 'Skipped' 'Trustee not resolvable/external in the source export'; continue }
    $box = Resolve-PermissionTrustee -Trustee $p.Mailbox -Mapping $map
    $who = Resolve-PermissionTrustee -Trustee $p.Trustee -Mapping $map
    if (-not $box -or -not $who) { Add-Result $label 'Skipped' 'Mailbox or trustee not in the user list/shared mapping'; continue }
    if (-not $PSCmdlet.ShouldProcess($box, "$($p.Right) for $who")) { Add-Result $label 'WhatIf' "Would grant to $who on $box"; continue }
    try {
        switch ($p.Right) {
            'FullAccess'   { Add-MailboxPermission -Identity $box -User $who -AccessRights FullAccess -InheritanceType All -AutoMapping $true -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null }
            'SendAs'       { Add-RecipientPermission -Identity $box -Trustee $who -AccessRights SendAs -Confirm:$false -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null }
            'SendOnBehalf' { Set-Mailbox -Identity $box -GrantSendOnBehalfTo @{ Add = $who } -ErrorAction Stop }
            default        { Add-Result $label 'Skipped' "Unknown right '$($p.Right)'"; continue }
        }
        Add-Result $label 'Added' "$who on $box"
    }
    catch {
        if ($_.Exception.Message -match 'already|exists') { Add-Result $label 'Exists' '' }
        else { Add-Result $label 'Problem' $_.Exception.Message }
    }
}

$out = New-OutputFolder -Customer $Customer -Phase '06-SharedMailboxes-Holds'
$file = Join-Path $out 'MailboxPermissions-Applied.csv'
$log | Export-CsvSafe -Path $file
Write-Host "Report: $file" -ForegroundColor Cyan
