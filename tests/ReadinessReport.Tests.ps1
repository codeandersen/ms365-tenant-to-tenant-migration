BeforeAll {
    $script:Report = Join-Path $PSScriptRoot '..\00-Assessment\New-MigrationReadinessReport.ps1'
    $script:Fixture = Join-Path $PSScriptRoot 'fixtures\contoso-readiness'
}

Describe 'New-MigrationReadinessReport' {
    BeforeEach {
        $script:Inv = Join-Path $TestDrive 'contoso-readiness'
        Remove-Item $script:Inv -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item $script:Fixture $script:Inv -Recurse
        & $script:Report -InventoryPath $script:Inv
        $script:Md = [System.IO.File]::ReadAllText((Join-Path $script:Inv 'Readiness.md'), [System.Text.Encoding]::UTF8)
    }

    It 'generates Readiness.md without errors' {
        Test-Path (Join-Path $script:Inv 'Readiness.md') | Should -BeTrue
    }

    It 'recommends the orchestrator for user mailboxes' {
        $script:Md | Should -Match 'Cross-tenant migration orchestrator'
    }

    It 'recommends cross-tenant mailbox migration for shared/room mailboxes' {
        $script:Md | Should -Match 'Shared, room and equipment mailboxes \(2\)'
        $script:Md | Should -Match 'Cross-tenant mailbox migration'
    }

    It 'recommends standalone OneDrive migration for the ownerless OneDrive' {
        $script:Md | Should -Match 'OneDrive sites with no migrating user mailbox \(1\)'
        $script:Md | Should -Match 'Cross-tenant OneDrive migration'
    }

    It 'computes licence math (250.5 GB -> 3 Shared Data Migration licences, 8 user licences)' {
        $script:Md | Should -Match 'Cross-Tenant User Data Migration\s*\|\s*8\s*\|'
        $script:Md | Should -Match 'Cross-Tenant Shared Data Migration\s*\|\s*3\s*\|'
    }

    It 'lists a mailbox hold as a blocker' {
        $script:Md | Should -Match 'Mailboxes on hold - 1'
        $script:Md | Should -Match 'søren@contoso\.com'
    }

    It 'lists a public folder mailbox as a blocker' {
        $script:Md | Should -Match 'Public folders - 1'
    }

    It 'lists Customer Key and the apostrophe UPN as blockers' {
        $script:Md | Should -Match 'Customer Key enabled - 1'
        $script:Md | Should -Match 'apostrophe'
    }

    It 'reports rebuild items that are present (Bookings, Project Online, private/shared channels)' {
        $script:Md | Should -Match 'Bookings mailboxes \| 1'
        $script:Md | Should -Match 'Project Online sites.*\| 1'
        $script:Md | Should -Match 'Private / shared channels \| 2'
    }

    It 'has an archive-mailboxes section with a per-mailbox comes-along answer' {
        $script:Md | Should -Match '## 2\. Archive mailboxes'
        $script:Md | Should -Match 'Mailboxes with an archive/aux/disabled archive: \*\*6\*\*'
        $script:Md | Should -Match 'anna@contoso\.com.*Yes \(Orchestrator - inferred, confirm in pilot\)'
        $script:Md | Should -Match 'shared1@contoso\.com.*Yes - action needed'
        $script:Md | Should -Match 'expand@contoso\.com.*Yes - action needed'
        $script:Md | Should -Match 'aux@contoso\.com.*No - blocked'
        $script:Md | Should -Match 'old@contoso\.com.*No - blocked'
        # all-zero DisabledArchiveGuid (Get-Mailbox default) must not count as a disabled archive
        $script:Md | Should -Match 'anna@contoso\.com.*Yes \(Orchestrator'
        $script:Md | Should -Match 'disabled/demoted archives: \*\*1\*\*'
    }

    It 'feeds aux-over-12 and disabled archives into the blockers section' {
        $script:Md | Should -Match 'Archive mailboxes that will fail the move - 2'
    }

    It 'states the precise shared-mailbox licence rule' {
        $script:Md | Should -Match 'Plan 2 or Plan 1 \+ Exchange Online Archiving'
    }

    It 'marks archive details Unknown - not inventoried when the columns are missing' {
        $inv2 = Join-Path $TestDrive 'old-inventory'
        Copy-Item $script:Fixture $inv2 -Recurse
        # strip the archive columns as an old inventory would have
        $mbx = Import-Csv (Join-Path $inv2 'attachments\Mailboxes.csv')
        $mbx | Select-Object UserPrincipalName, RecipientTypeDetails, PrimarySmtpAddress, TotalItemSizeGB, HasAnyHold, HoldReasons, LitigationHoldEnabled, ArchiveStatus, ProhibitSendReceiveQuota |
            Export-Csv (Join-Path $inv2 'attachments\Mailboxes.csv') -NoTypeInformation -Encoding utf8
        & $script:Report -InventoryPath $inv2 -OutFile (Join-Path $inv2 'R3.md')
        $md3 = [System.IO.File]::ReadAllText((Join-Path $inv2 'R3.md'), [System.Text.Encoding]::UTF8)
        $md3 | Should -Match 'Unknown - not inventoried'
    }

    It 'renders the enterprise app usage table and excludes first-party apps' {
        $script:Md | Should -Match 'Enterprise app usage'
        $script:Md | Should -Match 'ActiveInWindow: 2'
        $script:Md | Should -Match 'Contoso CRM'
        $script:Md | Should -Match 'Inactive non-Microsoft apps \(2\)'
        $script:Md | Should -Match 'Legacy HR'
        $script:Md | Should -Match '1 managed identities active in the window'
        $script:Md | Should -Not -Match 'Microsoft Teams'
        $script:Md | Should -Match 'App sign-in history older than 30 days'
    }

    It 'marks enterprise app usage not inventoried when the CSV is missing' {
        Remove-Item (Join-Path $script:Inv 'attachments\AppSignInActivity.csv')
        & $script:Report -InventoryPath $script:Inv -OutFile (Join-Path $script:Inv 'R4.md')
        $md4 = [System.IO.File]::ReadAllText((Join-Path $script:Inv 'R4.md'), [System.Text.Encoding]::UTF8)
        $md4 | Should -Match 'Enterprise app usage.*not inventoried'
    }

    It 'writes UTF-8 with BOM and keeps æøå readable' {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:Inv 'Readiness.md'))
        $bytes[0] | Should -Be 0xEF
        $bytes[1] | Should -Be 0xBB
        $bytes[2] | Should -Be 0xBF
        $script:Md | Should -Match 'Søren|søren'
    }

    It 'tolerates missing CSVs and marks the rule not inventoried' {
        Remove-Item (Join-Path $script:Inv 'attachments\CustomerKey.csv')
        Remove-Item (Join-Path $script:Inv 'attachments\Mailboxes.csv')
        { & $script:Report -InventoryPath $script:Inv -OutFile (Join-Path $script:Inv 'R2.md') } | Should -Not -Throw
        $md2 = [System.IO.File]::ReadAllText((Join-Path $script:Inv 'R2.md'), [System.Text.Encoding]::UTF8)
        $md2 | Should -Match 'Not inventoried'
        $md2 | Should -Match 'Mailbox holds'
    }

    It 'Devices section defaults to Unknown and shows counts + both implications' {
        $script:Md | Should -Match '## 4\. Devices'
        $script:Md | Should -Match 'Device strategy: \*\*Unknown\*\*'
        $script:Md | Should -Match 'Entra joined\s*\|\s*2'
        $script:Md | Should -Match 'Hybrid Entra joined\s*\|\s*1'
        $script:Md | Should -Match 'Entra registered.*\|\s*2'
        $script:Md | Should -Match 'Autopilot-registered\s*\|\s*2'
        $script:Md | Should -Match 'Stale \(>90 days no sign-in\)\s*\|\s*1'
        $script:Md | Should -Match 'Decide the device strategy'
    }

    It 'Devices section renders NewDevices and ExistingDevices tracks' {
        & $script:Report -InventoryPath $script:Inv -DeviceStrategy NewDevices -OutFile (Join-Path $script:Inv 'R3.md')
        $m = [System.IO.File]::ReadAllText((Join-Path $script:Inv 'R3.md'), [System.Text.Encoding]::UTF8)
        $m | Should -Match 'Track 1 - new devices'
        $m | Should -Match 'Entra object is deleted last'
        $m | Should -Match 'vendor/reseller registering each new PC hash'
        & $script:Report -InventoryPath $script:Inv -DeviceStrategy ExistingDevices -OutFile (Join-Path $script:Inv 'R4.md')
        $m2 = [System.IO.File]::ReadAllText((Join-Path $script:Inv 'R4.md'), [System.Text.Encoding]::UTF8)
        $m2 | Should -Match 'Track 2 - existing devices must move'
        $m2 | Should -Match '2 Entra-joined devices'
        $m2 | Should -Match 'one tenant'
        $m2 | Should -Match 'deregistered in the source'
        $m2 | Should -Match 'open decision'
    }

    It 'Sign-in and access section covers MFA scale, source locations and target CA impact' {
        $tgt = Join-Path $PSScriptRoot 'fixtures\fabrikam-target-readiness'
        & $script:Report -InventoryPath $script:Inv -TargetInventoryPath $tgt -DeviceStrategy NewDevices -OutFile (Join-Path $script:Inv 'R5.md')
        $m = [System.IO.File]::ReadAllText((Join-Path $script:Inv 'R5.md'), [System.Text.Encoding]::UTF8)
        $m | Should -Match '## 5\. Sign-in and access'
        $m | Should -Match 'MFA registration does not move'
        $m | Should -Match '\*\*2\*\* user\(s\) registered for MFA'
        $m | Should -Match 'Temporary Access Pass'
        $m | Should -Match 'Named locations: \*\*3\*\* \(1 trusted IP'
        $m | Should -Match 'Export-TrustedLocations'
        $m | Should -Match 'Security defaults enabled: \*\*False\*\*'
        $m | Should -Match 'compliant or hybrid-joined device.*Target-RequireCompliant'
        $m | Should -Match 'Target-MFA'
    }

    It 'Sign-in section degrades without target inventory' {
        $script:Md | Should -Match 'not inventoried - run `Collect-TenantInventory'
    }

    It 'renders the apps-and-platform section with high-privilege apps' {
        $script:Md | Should -Match '## 9\. Apps and platform items to address'
        $script:Md | Should -Match 'Enterprise app API permissions'
        $script:Md | Should -Match 'high-privilege grants'
        $script:Md | Should -Match 'Contoso CRM'
        $script:Md | Should -Match 'Application: Mail\.ReadWrite'
        $script:Md | Should -Match 'Contoso Sync Tool'
        $script:Md | Should -Match 'could not be resolved'
    }

    It 'lists Power Platform, Teams apps, Planner, add-ins and the app catalog' {
        $script:Md | Should -Match '### Power Platform'
        $script:Md | Should -Match '2 environment\(s\), 2 Power App\(s\), 1 flow\(s\), 1 custom connector'
        $script:Md | Should -Match 'Contoso Dev'
        $script:Md | Should -Match 'Power BI: \*\*2 workspace\(s\)\*\*'
        $script:Md | Should -Match '1 org-uploaded Teams app\(s\).*Contoso Helper Bot'
        $script:Md | Should -Match '2 Planner plan\(s\)'
        $script:Md | Should -Match '1 organization Outlook add-in\(s\)'
        $script:Md | Should -Match '1 app\(s\) in the SharePoint tenant app catalog'
    }

    It 'marks app/platform CSVs not inventoried when they are absent' {
        foreach ($f in 'AppPermissions.csv','PowerPlatformEnvironments.csv','PowerApps.csv','PowerAutomateFlows.csv',
                      'PowerBIWorkspaces.csv','TeamsCustomApps.csv','TeamsInstalledApps.csv','PlannerPlans.csv',
                      'OutlookAddins.csv','SharePointAppCatalog.csv') {
            Remove-Item (Join-Path $script:Inv "attachments\$f") -ErrorAction SilentlyContinue
        }
        & $script:Report -InventoryPath $script:Inv -OutFile (Join-Path $script:Inv 'R6.md')
        $m = [System.IO.File]::ReadAllText((Join-Path $script:Inv 'R6.md'), [System.Text.Encoding]::UTF8)
        $m | Should -Match 'Granted permissions per enterprise app \(AppPermissions\.csv\)'
        $m | Should -Match 'Power Platform environments/apps/flows'
        $m | Should -Match 'Power BI workspaces'
        $m | Should -Match 'Org-uploaded Teams apps \(TeamsCustomApps\.csv\)'
        $m | Should -Match 'Installed Teams apps per team \(TeamsInstalledApps\.csv\)'
        $m | Should -Match 'Planner plans per group \(PlannerPlans\.csv\)'
        $m | Should -Match 'Organization Outlook add-ins \(OutlookAddins\.csv\)'
        $m | Should -Match 'SharePoint tenant app catalog apps \(SharePointAppCatalog\.csv\)'
    }
}
