# ==============================================================================
# Script: SQL Maintenance - DBCC CHECKDB Monito
# Purpose: Adds a Schedule Taks at 4AM in the \Powershell path
# Created by: Steve Ling and Gemini 2026-08-03
# ==============================================================================
$TaskName   = "SQL Maintenance - DBCC CHECKDB Monitor"
$TaskPath   = "\Powershell\"
$ScriptPath = "\\bigberta.onling.com\Backups\Scripts\Check-SqlCheckDb.ps1" # Update path if stored elsewhere
$RunAsUser  = "ONLING\svcSQL"

# 1. Define Daily Trigger (Runs daily at 4:00 AM)
$Trigger = New-ScheduledTaskTrigger -Daily -At "4:00 AM"

# 2. Define Action using explicit powershell.exe path
$Action = New-ScheduledTaskAction `
    -Execute "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

# 3. Define Settings (Allow running on battery, 2 hour execution cap)
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)

# 4. Register Scheduled Task under \Powershell\
Register-ScheduledTask -TaskName $TaskName `
    -TaskPath $TaskPath `
    -Trigger $Trigger `
    -Action $Action `
    -Settings $Settings `
    -User $RunAsUser `
    -RunLevel Highest