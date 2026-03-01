#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Disables USB Selective Suspend and USB 3.0 Link Power Management (U1/U2) on all Windows power plans.

.DESCRIPTION
    Fixes random USB device disconnections caused by two Windows power-saving features:

    1. USB Selective Suspend - Allows Windows to suspend individual USB hub ports.
       When a hub controller fails to re-enumerate devices on wake, they appear as disconnected.

    2. USB 3.0 Link Power Management (U1/U2) - A hidden setting that puts USB 3.0 links into
       low-power U1/U2 states independently of Selective Suspend. Hardware with buggy U1/U2
       implementations fails to wake properly, causing device disconnections.

    This script disables both settings on ALL power plans (AC and DC) and is safe to run repeatedly.
    It is designed to be used as a logon script via Task Scheduler to guard against Windows Update
    re-enabling these settings silently.

.NOTES
    Requires: Windows 10/11, Administrator privileges

.LINK
    https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/usb-selective-suspend
    https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/usb-3-0-lpm-mechanism-
    https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/common-hardware-problems-with-u1-or-u2-implementation
#>

$subgroup = "2a737441-1930-4402-8d77-b2bebba308a3"
$settings = @(
    @{ Guid = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"; Name = "USB Selective Suspend" },
    @{ Guid = "d4e98f31-5ffe-4ce1-be31-1b38b384c009"; Name = "USB 3 Link Power Management (U1/U2)" }
)
$changed = $false

# Unhide the U1/U2 setting so it can be queried and set
powercfg /attributes $subgroup "d4e98f31-5ffe-4ce1-be31-1b38b384c009" -ATTRIB_HIDE 2>$null

$plans = powercfg /list | Select-String 'Power Scheme GUID:\s+(\S+)\s+\((.+?)\)' | ForEach-Object {
    [PSCustomObject]@{ Guid = $_.Matches[0].Groups[1].Value; Name = $_.Matches[0].Groups[2].Value }
}

foreach ($plan in $plans) {
    foreach ($s in $settings) {
        $query = powercfg /query $plan.Guid $subgroup $s.Guid 2>$null
        $acMatch = $query | Select-String 'Current AC Power Setting Index:\s+0x(\d+)'
        $dcMatch = $query | Select-String 'Current DC Power Setting Index:\s+0x(\d+)'
        if (-not $acMatch) { continue }
        $ac = [int]$acMatch.Matches[0].Groups[1].Value
        $dc = [int]$dcMatch.Matches[0].Groups[1].Value

        if ($ac -ne 0 -or $dc -ne 0) {
            Write-Host "[$($plan.Name)] $($s.Name) is ENABLED - disabling..." -ForegroundColor Yellow
            powercfg /SETACVALUEINDEX $plan.Guid $subgroup $s.Guid 0
            powercfg /SETDCVALUEINDEX $plan.Guid $subgroup $s.Guid 0
            $changed = $true
        } else {
            Write-Host "[$($plan.Name)] $($s.Name) already disabled." -ForegroundColor Green
        }
    }
}

if ($changed) {
    powercfg /SETACTIVE SCHEME_CURRENT
    Write-Host ""
    Write-Host "Done. USB power management settings disabled." -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "No changes needed." -ForegroundColor Cyan
}
