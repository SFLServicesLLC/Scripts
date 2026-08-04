# ==============================================================================
# Script: Multi-Server Remote DBCC CHECKDB Monitor (Native .NET)
# Purpose: Runs DBCC CHECKDB across SQL instances using System.Data.SqlClient
# Created by: Steve Ling and Gemini 2026-08-03
# ==============================================================================

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
# Target SQL Servers (Hostnames, IPs, or Hostname\Instance)
$targetServers = @(
    "SFL-SQL-001",
    "SFL-SQL-003",
    "SFL-SQL-005"
)

# Remote network log share (UNC Path)
$remoteLogDirectory    = "\\bigberta.onling.com\Backups\Logs\SQLChecks"

# Local fallback log directory (in case the network share is offline)
$localFallbackDirectory = "C:\Scripts\Logs\SQLChecks_Fallback"

# Determine active log path (Remote vs. Fallback)
if (Test-Path -Path $remoteLogDirectory) {
    $activeLogDirectory = $remoteLogDirectory
} else {
    try {
        New-Item -ItemType Directory -Path $remoteLogDirectory -ErrorAction Stop | Out-Null
        $activeLogDirectory = $remoteLogDirectory
    } catch {
        $activeLogDirectory = $localFallbackDirectory
        if (-not (Test-Path $localFallbackDirectory)) {
            New-Item -ItemType Directory -Path $localFallbackDirectory -Force | Out-Null
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

    # Connection String with explicit TrustServerCertificate=True
    $connString = "Server=$server;Database=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True;Connect Timeout=15;"
    $connection = New-Object System.Data.SqlClient.SqlConnection($connString)

    try {
        $connection.Open()
        
        # Get list of online databases (excluding tempdb)
        $getDbQuery = "SELECT name FROM sys.databases WHERE state_desc = 'ONLINE' AND name != 'tempdb'"
        $cmd        = $connection.CreateCommand()
        $cmd.CommandText = $getDbQuery
        
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
        $dataset = New-Object System.Data.DataSet
        [void]$adapter.Fill($dataset)
        
        $databases = $dataset.Tables[0]

        foreach ($row in $databases) {
            $dbName = $row.name
            Write-Log "Running DBCC CHECKDB on [$server] -> [$dbName]..." -Path $logFile
            
            $checkCmd = $connection.CreateCommand()
            $checkCmd.CommandText = "DBCC CHECKDB ([$dbName]) WITH NO_INFOMSGS, ALL_ERRORMSGS;"
            $checkCmd.CommandTimeout = 0 # Prevent command timeouts during long DBCC scans
            
            try {
                [void]$checkCmd.ExecuteNonQuery()
                Write-Log "SUCCESS: [$dbName] passed on [$server]." -Path $logFile
            } catch {
                Write-Log "CRITICAL ERROR: Corruption or failure detected in [$dbName] on [$server]!" -Path $logFile
                Write-Log "Details: $($_.Exception.Message)" -Path $logFile
            }
        }
        
        $connection.Close()

    } catch {
        Write-Log "CONNECTION FAILED: Unable to query SQL Server [$server]." -Path $logFile
        Write-Log "Details: $($_.Exception.Message)" -Path $logFile
        if ($connection.State -eq [System.Data.ConnectionState]::Open) {
            $connection.Close()
        }
    }

    Write-Log "Completed DBCC CHECKDB routine for $server." -Path $logFile
}