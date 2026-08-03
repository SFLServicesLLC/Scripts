# ==============================================================================
# Script: Bulk Move SQL Server User Database Files (.mdf / .ldf)
# Purpose: Moves all non-system database files using pure .NET (No Invoke-Sqlcmd)
# Safety Check: Ensures the target SQL host is running on PHYSICAL HARDWARE
# Created by: Steve Ling and Gemini 2026-08-03
# ==============================================================================

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
$targetServer = "SFL-SQL-003"    # Hostname or IP of target SQL Server

# New destination root paths on the target SQL Server
$newMdfPath   = "D:\SQLData"      # Target directory for Data (.mdf / .ndf) files
$newLdfPath   = "E:\SQLLogs"      # Target directory for Log (.ldf) files

# ------------------------------------------------------------------------------
# Helper Functions for SQL Execution
# ------------------------------------------------------------------------------
Function Execute-SqlNonQuery {
    Param (
        [string]$Server,
        [string]$Query
    )
    $connString = "Server=$Server;Database=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True;Connect Timeout=15;"
    $conn = New-Object System.Data.SqlClient.SqlConnection($connString)
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = 0 # Prevent timeout during state changes
        [void]$cmd.ExecuteNonQuery()
    } finally {
        if ($conn.State -eq [System.Data.ConnectionState]::Open) {
            $conn.Close()
        }
    }
}

Function Get-SqlData {
    Param (
        [string]$Server,
        [string]$Query
    )
    $connString = "Server=$Server;Database=master;Integrated Security=True;TrustServerCertificate=True;Encrypt=True;Connect Timeout=15;"
    $conn = New-Object System.Data.SqlClient.SqlConnection($connString)
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Query
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
        $dataset = New-Object System.Data.DataSet
        [void]$adapter.Fill($dataset)
        return $dataset.Tables[0]
    } finally {
        if ($conn.State -eq [System.Data.ConnectionState]::Open) {
            $conn.Close()
        }
    }
}

# ------------------------------------------------------------------------------
# Script Execution
# ------------------------------------------------------------------------------

# 1. PHYSICAL SERVER HARDWARE CHECK
Write-Host "Connecting to [$targetServer] and checking host platform..." -ForegroundColor Cyan

$hardwareCheckQuery = "
    SELECT 
        virtual_machine_type_desc
    FROM sys.dm_os_sys_info;
"

try {
    $hwResult = Get-SqlData -Server $targetServer -Query $hardwareCheckQuery
    $vmType   = $hwResult.Rows[0].virtual_machine_type_desc

    if ($vmType -ne 'NONE') {
        Write-Host "==================================================" -ForegroundColor Red
        Write-Host "ABORTED: Target server [$targetServer] is a VIRTUAL MACHINE ($vmType)!" -ForegroundColor Red
        Write-Host "This script is configured to run ONLY on Physical Hardware." -ForegroundColor Red
        Write-Host "==================================================" -ForegroundColor Red
        exit
    } else {
        Write-Host "PHYSICAL SERVER CONFIRMED ($vmType). Proceeding with database inventory..." -ForegroundColor Green
    }
} catch {
    Write-Host "ERROR: Failed to query hardware info on [$targetServer]. Aborting for safety." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit
}

# 2. FILE INVENTORY & MOVE PROCESS
$getFilesQuery = "
    SELECT 
        d.name AS DatabaseName,
        f.name AS LogicalName,
        f.physical_name AS CurrentPhysicalPath,
        f.type_desc AS FileType
    FROM sys.master_files f
    INNER JOIN sys.databases d ON f.database_id = d.database_id
    WHERE d.name NOT IN ('master', 'model', 'msdb', 'tempdb')
      AND d.state_desc = 'ONLINE';
"

try {
    # Fetch file mappings using .NET SqlClient
    $fileList = Get-SqlData -Server $targetServer -Query $getFilesQuery

    if ($fileList.Rows.Count -eq 0) {
        Write-Host "No user databases found to move." -ForegroundColor Yellow
        exit
    }

    # Group files by Database
    $databases = $fileList | Group-Object -Property DatabaseName

    # Resolve UNC paths for file transfer from remote tools machine
    $serverHost = $targetServer.Split('\')[0]
    $uncMdfPath = "\\$serverHost\" + ($newMdfPath -replace ':', '$')
    $uncLdfPath = "\\$serverHost\" + ($newLdfPath -replace ':', '$')

    if (-not (Test-Path $uncMdfPath)) { New-Item -ItemType Directory -Path $uncMdfPath -Force | Out-Null }
    if (-not (Test-Path $uncLdfPath)) { New-Item -ItemType Directory -Path $uncLdfPath -Force | Out-Null }

    foreach ($dbGroup in $databases) {
        $dbName = $dbGroup.Name
        Write-Host "`n==================================================" -ForegroundColor Cyan
        Write-Host "Processing Database: [$dbName]" -ForegroundColor Yellow
        Write-Host "==================================================" -ForegroundColor Cyan

        # Take Database Offline
        Write-Host "-> Setting [$dbName] OFFLINE..." -ForegroundColor Gray
        $offlineQuery = "ALTER DATABASE [$dbName] SET OFFLINE WITH ROLLBACK IMMEDIATE;"
        Execute-SqlNonQuery -Server $targetServer -Query $offlineQuery

        try {
            foreach ($row in $dbGroup.Group) {
                $logicalName  = $row.LogicalName
                $oldPath      = $row.CurrentPhysicalPath
                $fileName     = Split-Path $oldPath -Leaf
                $fileType     = $row.FileType # 'ROWS' or 'LOG'

                # Determine target location based on file type
                if ($fileType -eq 'ROWS') {
                    $targetLocalPath = "$newMdfPath\$fileName"
                    $targetUncPath   = "$uncMdfPath\$fileName"
                } else {
                    $targetLocalPath = "$newLdfPath\$fileName"
                    $targetUncPath   = "$uncLdfPath\$fileName"
                }

                # UNC Path for source file
                $oldUncPath = "\\$serverHost\" + ($oldPath -replace ':', '$')

                # Update Metadata in master DB
                Write-Host "-> Updating system catalog for logical file [$logicalName]..." -ForegroundColor Gray
                $alterCatalogQuery = "ALTER DATABASE [$dbName] MODIFY FILE (NAME = '$logicalName', FILENAME = '$targetLocalPath');"
                Execute-SqlNonQuery -Server $targetServer -Query $alterCatalogQuery

                # Physically move file on disk via administrative share
                Write-Host "-> Moving file [$fileName] to [$targetLocalPath]..." -ForegroundColor Gray
                Move-Item -Path $oldUncPath -Destination $targetUncPath -Force -ErrorAction Stop
            }

            # Bring Database Back Online
            Write-Host "-> Setting [$dbName] ONLINE..." -ForegroundColor Green
            $onlineQuery = "ALTER DATABASE [$dbName] SET ONLINE;"
            Execute-SqlNonQuery -Server $targetServer -Query $onlineQuery
            
            Write-Host "SUCCESS: [$dbName] moved and brought online." -ForegroundColor Green

        } catch {
            Write-Host "CRITICAL ERROR moving files for [$dbName]: $_" -ForegroundColor Red
            Write-Host "Attempting to restore original state..." -ForegroundColor Red
            
            # Revert catalog paths back to old location if move fails
            foreach ($row in $dbGroup.Group) {
                $revertQuery = "ALTER DATABASE [$dbName] MODIFY FILE (NAME = '$($row.LogicalName)', FILENAME = '$($row.CurrentPhysicalPath)');"
                try { Execute-SqlNonQuery -Server $targetServer -Query $revertQuery } catch {}
            }
            # Attempt bring online
            try { Execute-SqlNonQuery -Server $targetServer -Query "ALTER DATABASE [$dbName] SET ONLINE;" } catch {}
        }
    }

} catch {
    Write-Host "ERROR: Script failed to execute query against [$targetServer]." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}