# ==============================================================================
# Script: Multi-Server Remote DBCC CHECKDB Monitor
# Purpose: Runs DBCC CHECKDB across SQL instances and logs to a remote UNC share
# Created by: Steve Ling and Gemini 2026-08-03
# ==============================================================================

#Install module first if needed
#Install-Module -Name SqlServer -AllowClobber -Force

Import-Module SqlServer -ErrorAction SilentlyContinue

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
# Target SQL Servers (Hostnames, IPs, or Hostname\Instance)
$targetServers = @(
    "Server-001",
    "Server-003",
    "Server-005"
)

# Remote network log share (UNC Path)
$remoteLogDirectory = "\\bigberta.onling.com\Backups\Logs\SQLChecks"

# Local fallback log directory (in case the network share is offline)
$localFallbackDirectory = "C:\Scripts\Logs\SQLChecks_Fallback"

# Determine active log path (Remote vs. Fallback)
if (Test-Path -Path $remoteLogDirectory) {
    $activeLogDirectory = $remoteLogDirectory
} else {
    # If remote folder doesn't exist, attempt to create it; otherwise use fallback
    try {
        New-Item -ItemType Directory -Path $remoteLogDirectory -ErrorAction Stop | Out-Null
        $activeLogDirectory = $remoteLogDirectory
    } catch {
        $activeLogDirectory = $localFallbackDirectory
        if (-not (Test-Path $localFallbackDirectory)) {
            New-Item -ItemType Directory -Path $localFallbackDirectory | Out-Null
        }
    }
}

# Helper function for timestamped logging
Function Write-Log {
    Param (
        [string]$Message,
        [string]$Path
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry  = "[$timestamp] $Message"
    
    try {
        Add-Content -Path $Path -Value $logEntry -ErrorAction Stop
    } catch {
        # Secondary fallback writing if a file lock or network interruption occurs mid-stream
        $fallbackPath = Join-Path -Path $localFallbackDirectory -ChildPath (Split-Path -Leaf $Path)
        Add-Content -Path $fallbackPath -Value "[$timestamp] [FALLBACK LOG] $Message"
    }
    
    Write-Output $logEntry 
}

# ------------------------------------------------------------------------------
# Execution Loop
# ------------------------------------------------------------------------------
$dateStamp = Get-Date -Format 'yyyyMMdd'

foreach ($server in $targetServers) {
    # Sanitize server name for log filename compatibility
    $safeServerName = $server -replace '[\:\\]', '_'
    $logFile        = "$activeLogDirectory\DBCC_Check_${safeServerName}_${dateStamp}.log"

    Write-Log "----------------------------------------------------------------------" -Path $logFile
    Write-Log "Starting DBCC CHECKDB routine for target server: $server" -Path $logFile
    
    if ($activeLogDirectory -eq $localFallbackDirectory) {
        Write-Log "WARNING: Remote log share [$remoteLogDirectory] was unreachable. Using local fallback path." -Path $logFile
    }

    try {
        # Fetch all online databases except tempdb
        $getDbQuery = "SELECT name FROM sys.databases WHERE state_desc = 'ONLINE' AND name != 'tempdb'"
        
        # Test connection & fetch DB list (Added -TrustServerCertificate)
        $databases = Invoke-Sqlcmd -ServerInstance $server -Query $getDbQuery -ConnectionTimeout 10 -TrustServerCertificate -ErrorAction Stop

        foreach ($db in $databases) {
            $dbName = $db.name
            Write-Log "Running DBCC CHECKDB on [$server] -> [$dbName]..." -Path $logFile
            
            # NO_INFOMSGS ensures output is clean unless corruption/errors are found
            $checkQuery = "DBCC CHECKDB ([$dbName]) WITH NO_INFOMSGS, ALL_ERRORMSGS;"
            
            try {
                # QueryTimeout 0 prevents command timeouts on large DBs (Added -TrustServerCertificate)
                Invoke-Sqlcmd -ServerInstance $server -Query $checkQuery -QueryTimeout 0 -TrustServerCertificate -ErrorAction Stop
                Write-Log "SUCCESS: [$dbName] passed on [$server]." -Path $logFile
            } catch {
                Write-Log "CRITICAL ERROR: Corruption or failure detected in [$dbName] on [$server]!" -Path $logFile
                Write-Log "Details: $($_.Exception.Message)" -Path $logFile
            }
        }
    } catch {
        # Server unreachable, offline, or permissions denied
        Write-Log "CONNECTION FAILED: Unable to query SQL Server [$server]." -Path $logFile
        Write-Log "Details: $($_.Exception.Message)" -Path $logFile
    }

    Write-Log "Completed DBCC CHECKDB routine for $server." -Path $logFile
}