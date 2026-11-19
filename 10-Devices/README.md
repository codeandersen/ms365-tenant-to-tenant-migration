# 10 - Devices (new PCs)

**Decision:** every user gets a **brand-new PC** enrolled directly in the target tenant via
Autopilot/Intune. There is no in-place device move, no profile copy, and no domain rejoin
(the toolkit's `Move-TenantDevices`/`Copy-ProfileData` path was considered and rejected).

## New-PC checklist (target tenant)

1. Target Autopilot deployment profile + hardware hashes registered (or OEM direct upload).
2. Enrollment Status Page (ESP) configured so the PC is ready before first sign-in.
3. Intune baseline/compliance policies, Windows update rings.
4. Required apps assigned (Office, Teams, company apps, VPN client).
5. Windows Hello for Business policy enabled.
6. OneDrive Known Folder Move in the **target** - only after the OneDrive migration completed.
7. Printers (Universal Print or new queues) and VPN profiles pointed at the target.
8. BitLocker enabled so the new keys escrow in the **target** tenant from day one.

## Pre-cutover sign-in rules for users

- Signing in with the **target** account and registering MFA before cutover is allowed and
  encouraged (validated in the pilot).
- **No Outlook against the target before cutover** - the mailbox doesn't exist there yet.
- **No OneDrive or Teams in the target before cutover** - data syncs later.
- After cutover: sign in on the new PC, Outlook builds a **new profile** (don't reuse the old one).

## Timing

Hand out PCs shortly before cutover weekend so users sign in to target on day T+0. Earlier is
wasted effort (they can't use mail/OneDrive yet); later leaves people without a working PC on
Monday. Decide with the business; the pilot checks that target sign-in works from the new PC.

## UPN change on the new PC

If UPNs change to the custom domain during cutover (phase 09, hypothesis), validate in the pilot
that a UPN change after first sign-in doesn't strand the Autopilot/Intune enrolment - see
`docs/Questions-For-Microsoft.md` and the pilot checklist.

## Old-PC retirement - order matters

1. **Check local data** - files outside OneDrive/KFM, browser data, local PSTs.
2. **Wipe/retire** the device.
3. Remove the **Intune** managed-device record.
4. Remove the **Autopilot** registration.
5. Delete the **Entra ID** device object **last** - deleting it also deletes the escrowed
   BitLocker recovery key. A device wiped while its only key lives in the source is
   unrecoverable if recovery is later needed.

## Scripts

| Script | Side | What it does |
|---|---|---|
| `Get-DeviceInventory.ps1` | source | Read-only: Entra devices + Intune match, join type, last sign-in, staleness |
| `Get-BitLockerKeyReport.ps1` | source | Read-only: which devices have a recovery key escrowed - **metadata only, never key values** (uses `BitlockerKey.ReadBasic.All`). Get an individual key in the Entra/Intune portal when needed |
| `Get-OldDeviceRetirementPlan.ps1` | offline | Read-only: joins the inventory + user list + key report into a per-device retirement plan with the fixed step order |

No deletion script ships in this phase - the plan is executed deliberately, by hand or with your
own tooling, after the checks.
