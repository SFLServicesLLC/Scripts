#/*****************************************************************************
#/*     Script : copyNumberOfFiles.ps1
#/*   Function : This script is to split a folder that has [x] amount of files
#/*              into subfolders
#/*
#/*    Written : 2 Apr 2026
#/*     Author : Steven F Ling
#/*
#/*****************************************************************************
# Revision History :
VERSION=1.1
# *(#) Date               BY            Revision Description
# *(#) ---------    ---------------     --------------------
# *(#) 2026-04-01   Steve Ling          Created
# *(#)
#
#*****************************************************************************
# --- Configuration ---
$sourcePath = "C:\SourceFolder"        # Path to your source files
$destRoot = "C:\DestinationRoot"      # Where the new folders will be created
$filesPerFolder = 250                 # Number of files per folder
$folderPrefix = "Batch_"              # Name prefix for new folders

# --- Execution ---
# Get all files from the source (excluding folders)
$files = Get-ChildItem -Path $sourcePath -File

$fileCount = $files.Count
$folderCount = [Math]::Ceiling($fileCount / $filesPerFolder)

Write-Host "Found $($fileCount) files. Splitting into $($folderCount) folders..." -ForegroundColor Cyan

for ($i = 0; $i -lt $fileCount; $i += $filesPerFolder) {
    # Calculate folder number (e.g., 1, 2, 3...)
    $batchNum = ($i / $filesPerFolder) + 1
    $currentFolderName = "$folderPrefix$batchNum"
    $targetPath = Join-Path -ChildPath $currentFolderName -Path $destRoot

    # Create the directory if it doesn't exist
    if (!(Test-Path $targetPath)) {
        New-Item -ItemType Directory -Path $targetPath | Out-Null
    }

    # Select the range of files and copy them
    $filesToCopy = $files | Select-Object -Skip $i -First $filesPerFolder
    $filesToCopy | Copy-Item -Destination $targetPath

    Write-Host "Created $currentFolderName and copied $($filesToCopy.Count) files." -ForegroundColor Green
}

Write-Host "Task complete!" -ForegroundColor Yellow