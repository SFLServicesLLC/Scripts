# ==============================================================================
# Script: SQL Backup - Cleanup Orphaned Directories
# Purpose: Adds a Schedule Task at 3AM in the \Powershell path
# Created by: Steve Ling and Gemini 2026-08-03
# ==============================================================================
$TaskName   = "SQL Backup - Cleanup Orphaned Directories"
$TaskPath   = "\Powershell\"
$ScriptPath = "\\bigberta.onling.com\Backups\Scripts\Cleanup-OrphanedSqlBackups.ps1"
$RunAsUser  = "ONLING\svcSQL"

# 1. Define Daily Trigger (Runs daily at 3:00 AM)
$Trigger = New-ScheduledTaskTrigger -Daily -At "3:00 AM"

# 2. Define Action using the explicit system path to powershell.exe
$Action = New-ScheduledTaskAction `
    -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

# 3. Define Settings
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)

# 4. Register Scheduled Task under \Powershell\
Register-ScheduledTask -TaskName $TaskName `
    -TaskPath $TaskPath `
    -Trigger $Trigger `
    -Action $Action `
    -Settings $Settings `
    -User $RunAsUser `
    -RunLevel Highest