# ==============================================================================
# Script: Cleanup-OrphanedSqlBackups.ps1
# Description: Identifies and removes backup directories for deleted databases 
#              while honoring retention policy and writing to a rolling log file.
# Created by: Steve Ling and Gemini 2026-08-03
# ==============================================================================

# --- Configuration Parameters ---
$SqlInstances  = @("SFL-SQL-001", "SFL-SQL-002", "SFL-SQL-003", "SFL-SQL-005")
$BackupRoot    = "\\bigberta.onling.com\Backups"
$LogDirectory  = "\\bigberta.onling.com\Backups\Logs\OrphanedBackupCleanup"
$RetentionDays = 14
$CutoffDate    = (Get-Date).AddDays(-$RetentionDays)

# --- Ensure Log Directory Exists ---
if (-not (Test-Path -Path $LogDirectory)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

# --- Setup Daily Log File ---
$LogFileName = "OrphanedBackupCleanup_$(Get-Date -Format 'yyyyMMdd').log"
$LogPath     = Join-Path -Path $LogDirectory -ChildPath $LogFileName

# Logging Helper Function
function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "SUCCESS", "ERROR")][string]$Level = "INFO"
    )
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $FormattedMessage = "[$TimeStamp] [$Level] $Message"
    
    # Write to Log File
    Add-Content -Path $LogPath -Value $FormattedMessage
    
    # Write to Console with Color
    switch ($Level) {
        "INFO"    { Write-Host $FormattedMessage -ForegroundColor White }
        "WARN"    { Write-Host $FormattedMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $FormattedMessage -ForegroundColor Green }
        "ERROR"   { Write-Host $FormattedMessage -ForegroundColor Red }
    }
}

# --- Execution Entry ---
Write-Log "=========================================================================="
Write-Log "Starting Orphaned SQL Backup Directory Cleanup Process"
Write-Log "Retention Cutoff: $RetentionDays Days ($($CutoffDate.ToString('yyyy-MM-dd HH:mm:ss')))"
Write-Log "Log Location: $LogPath"
Write-Log "=========================================================================="

foreach ($Server in $SqlInstances) {
    Write-Log "Processing SQL Server Instance: $Server"
    
    # 1. Fetch Active Database List (TrustServerCertificate handles untrusted SSL certs)
    try {
        $ActiveDatabases = (Invoke-Sqlcmd -ServerInstance $Server -Database "master" `
            -Query "SELECT name FROM sys.databases" `
            -TrustServerCertificate `
            -ConnectionTimeout 5 `
            -ErrorAction Stop).name
        
        Write-Log "Successfully connected to $Server. Found $($ActiveDatabases.Count) active databases."
    } catch {
        Write-Log "Failed to query sys.databases on instance [$Server]. Error: $_" -Level ERROR
        continue
    }

    # Path to server backups: e.g., \\bigberta.onling.com\Backups\SFL-SQL-005
    $ServerBackupPath = Join-Path -Path $BackupRoot -ChildPath $Server

    if (-not (Test-Path -Path $ServerBackupPath)) {
        Write-Log "Backup directory for server [$ServerBackupPath] does not exist. Skipping." -Level WARN
        continue
    }

    # 2. Get all top-level database folders under the server directory
    $DbFolders = Get-ChildItem -Path $ServerBackupPath -Directory

    foreach ($Folder in $DbFolders) {
        # Check if directory name matches an existing active database
        if ($ActiveDatabases -notcontains $Folder.Name) {
            Write-Log "Orphaned directory detected: '$($Folder.FullName)' (Database no longer exists in SQL)" -Level WARN

            # Inspect newest file in directory tree to enforce safety retention
            $NewestFile = Get-ChildItem -Path $Folder.FullName -Recurse -File -ErrorAction SilentlyContinue | 
                          Sort-Object LastWriteTime -Descending | 
                          Select-Object -First 1

            if ($null -eq $NewestFile) {
                Write-Log "Directory is completely empty. Deleting: '$($Folder.FullName)'" -Level INFO
                try {
                    Remove-Item -Path $Folder.FullName -Recurse -Force -ErrorAction Stop
                    Write-Log "Successfully removed empty directory: '$($Folder.FullName)'" -Level SUCCESS
                } catch {
                    Write-Log "Failed to delete empty directory '$($Folder.FullName)'. Error: $_" -Level ERROR
                }
            }
            elseif ($NewestFile.LastWriteTime -lt $CutoffDate) {
                Write-Log "Newest file in '$($Folder.Name)' is from $($NewestFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')). Exceeds $RetentionDays days." -Level INFO
                try {
                    Remove-Item -Path $Folder.FullName -Recurse -Force -ErrorAction Stop
                    Write-Log "Successfully purged orphaned backup directory: '$($Folder.FullName)'" -Level SUCCESS
                } catch {
                    Write-Log "Failed to delete directory '$($Folder.FullName)'. Error: $_" -Level ERROR
                }
            } 
            else {
                Write-Log "Skipping deletion of '$($Folder.Name)': Contains backups newer than cutoff date ($($NewestFile.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')))." -Level INFO
            }
        }
    }
}

Write-Log "=========================================================================="
Write-Log "Cleanup Process Completed Successfully"
Write-Log "=========================================================================="