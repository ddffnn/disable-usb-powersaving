#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Creates a scheduled task that runs Disable-USBPowerManagement.ps1 at every user logon.

.DESCRIPTION
    Windows Update can silently re-enable USB power-saving settings. This script creates a
    scheduled task that runs the fix at every logon with elevated privileges, ensuring the
    settings stay disabled.

    The task runs hidden (no console window) and is configured for Windows 10/11.

.PARAMETER ScriptPath
    Full path to Disable-USBPowerManagement.ps1. Defaults to the same directory as this script.

.PARAMETER TaskName
    Name for the scheduled task. Defaults to "Disable USB Power Management".
#>

param(
    [string]$ScriptPath,
    [string]$TaskName = "Disable USB Power Management"
)

if (-not $ScriptPath) {
    $ScriptPath = Join-Path $PSScriptRoot "Disable-USBPowerManagement.ps1"
}

if (-not (Test-Path $ScriptPath)) {
    Write-Error "Script not found at: $ScriptPath"
    exit 1
}

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""

$trigger = New-ScheduledTaskTrigger -AtLogOn

$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -RunLevel Highest `
    -LogonType ServiceAccount

$taskSettings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# Remove existing task if present
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Removing existing task '$TaskName'..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $taskSettings `
    -Description "Disables USB Selective Suspend and USB 3.0 Link Power Management (U1/U2) on all power plans. Guards against Windows Update re-enabling these settings." | Out-Null

Write-Host "Scheduled task '$TaskName' created successfully." -ForegroundColor Green
Write-Host "The script will run at every logon with elevated privileges." -ForegroundColor Cyan
