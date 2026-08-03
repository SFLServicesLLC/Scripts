# ==============================================================================
# Script: Bulk Move SQL Server User Database Files (.mdf / .ldf)
# Purpose: Moves all non-system database files to new target storage paths
# Created by: Steve Ling and Gemini 2026-08-03
# ==============================================================================

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
$targetServer = "Server-001"    # Hostname or IP of target SQL Server

# New destination root paths (Ensure SQL Service account has NTFS Full Control here)
$newMdfPath   = "D:\SQLData"      # Target directory for Data (.mdf / .ndf) files
$newLdfPath   = "E:\SQLLogs"      # Target directory for Log (.ldf) files

# ------------------------------------------------------------------------------
# Script Execution
# ------------------------------------------------------------------------------
Import-Module SqlServer -ErrorAction SilentlyContinue

# Query to grab all physical file details for USER databases only
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

Write-Host "Connecting to [$targetServer] to inspect database files..." -ForegroundColor Cyan

try {
    # Fetch file mappings
    $fileList = Invoke-Sqlcmd -ServerInstance $targetServer `
                              -Query $getFilesQuery `
                              -TrustServerCertificate `
                              -ErrorAction Stop

    if (-not $fileList) {
        Write-Host "No user databases found to move." -ForegroundColor Yellow
        exit
    }

    # Group files by Database
    $databases = $fileList | Group-Object -Property DatabaseName

    # Create destination folders locally or via UNC path if running remotely
    $serverHost = $targetServer.Split('\')[0]
    $uncMdfPath = "\\$serverHost\" + ($newMdfPath -replace ':', '$')
    $uncLdfPath = "\\$serverHost\" + ($newLdfPath -replace ':', '$')

    if (-not (Test-Path $uncMdfPath)) { New-Item -ItemType Directory -Path $uncMdfPath -Force | Out-Null }
    if (-not (Test-Path uncLdfPath)) { New-Item -ItemType Directory -Path $uncLdfPath -Force | Out-Null }

    foreach ($dbGroup in $databases) {
        $dbName = $dbGroup.Name
        Write-Host "`n==================================================" -ForegroundColor Cyan
        Write-Host "Processing Database: [$dbName]" -ForegroundColor Yellow
        Write-Host "==================================================" -ForegroundColor Cyan

        # 1. Take Database Offline
        Write-Host "-> Setting [$dbName] OFFLINE..." -ForegroundColor Gray
        $offlineQuery = "ALTER DATABASE [$dbName] SET OFFLINE WITH ROLLBACK IMMEDIATE;"
        Invoke-Sqlcmd -ServerInstance $targetServer -Query $offlineQuery -TrustServerCertificate -ErrorAction Stop

        try {
            foreach ($file in $dbGroup.Group) {
                $logicalName  = $file.LogicalName
                $oldPath      = $file.CurrentPhysicalPath
                $fileName     = Split-Path $oldPath -Leaf
                $fileType     = $file.FileType # 'ROWS' or 'LOG'

                # Determine target location based on file type
                if ($fileType -eq 'ROWS') {
                    $targetLocalPath = "$newMdfPath\$fileName"
                    $targetUncPath   = "$uncMdfPath\$fileName"
                } else {
                    $targetLocalPath = "$newLdfPath\$fileName"
                    $targetUncPath   = "$uncLdfPath\$fileName"
                }

                # Unc Path for source file
                $oldUncPath = "\\$serverHost\" + ($oldPath -replace ':', '$')

                # 2. Update Metadata in master DB
                Write-Host "-> Updating system catalog for logical file [$logicalName]..." -ForegroundColor Gray
                $alterCatalogQuery = "ALTER DATABASE [$dbName] MODIFY FILE (NAME = '$logicalName', FILENAME = '$targetLocalPath');"
                Invoke-Sqlcmd -ServerInstance $targetServer -Query $alterCatalogQuery -TrustServerCertificate -ErrorAction Stop

                # 3. Physically move file on disk
                Write-Host "-> Moving file [$fileName] to [$targetLocalPath]..." -ForegroundColor Gray
                Move-Item -Path $oldUncPath -Destination $targetUncPath -Force -ErrorAction Stop
            }

            # 4. Bring Database Back Online
            Write-Host "-> Setting [$dbName] ONLINE..." -ForegroundColor Green
            $onlineQuery = "ALTER DATABASE [$dbName] SET ONLINE;"
            Invoke-Sqlcmd -ServerInstance $targetServer -Query $onlineQuery -TrustServerCertificate -ErrorAction Stop
            
            Write-Host "SUCCESS: [$dbName] moved and brought online." -ForegroundColor Green

        } catch {
            Write-Host "CRITICAL ERROR moving files for [$dbName]: $_" -ForegroundColor Red
            Write-Host "Attempting to restore original state..." -ForegroundColor Red
            
            # Revert catalog paths back to old location if move fails
            foreach ($file in $dbGroup.Group) {
                $revertQuery = "ALTER DATABASE [$dbName] MODIFY FILE (NAME = '$($file.LogicalName)', FILENAME = '$($file.CurrentPhysicalPath)');"
                Invoke-Sqlcmd -ServerInstance $targetServer -Query $revertQuery -TrustServerCertificate -ErrorAction SilentlyContinue
            }
            # Attempt bring online
            Invoke-Sqlcmd -ServerInstance $targetServer -Query "ALTER DATABASE [$dbName] SET ONLINE;" -TrustServerCertificate -ErrorAction SilentlyContinue
        }
    }

} catch {
    Write-Host "ERROR: Script failed to execute query against [$targetServer]." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}