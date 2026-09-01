# ==============================================================================
# Script: SnapShot Rollover
# Purpose: To create daily snapshots of VMs
# Created by: Steve Ling and claude.ai 2026-08-03
# Updated:    2026-08-09 - fixed duplicate/broken Connect-VIServer call,
#                           wrapped main logic in try/finally, added failed
#                           snapshot creation to report, added run summary,
#                           added colour output for manual runs, added -DryRun,
#                           removed invalid -SkipPublisherCheck on Import-Module,
#                           check ignore.snaps Custom Attribute existence once
#                           instead of throwing per-VM, fixed ConvertTo-Html
#                           -Fragment/-Head/-Title parameter set conflict
# ==============================================================================
#https://communities.vmware.com/t5/VMware-PowerCLI-Discussions/Remove-Snapshots-Older-than-7-Days/td-p/402681
#https://developer.vmware.com/powercli/installation-guide  (Install-Module -Name VMware.PowerCLI)

# May need to run the following on the server
#Install-Module -Name VMware.PowerCLI

# Usage:
#   .\SnapShot-Rollover.ps1              # normal run - creates/removes snapshots for real
#   .\SnapShot-Rollover.ps1 -DryRun      # simulate only - no snapshots created or removed,
#                                          no state-changing vCenter calls made, report/email
#                                          still generated and clearly marked as a dry run
param(
    [switch]$DryRun
)

# Start recording
Start-Transcript -Path "C:\Scripts\snap.txt"
#
# ------------------------------------------------------------------
# Global Variables
# ------------------------------------------------------------------
$nowdat      = (Get-Date).ToString("yyyyMMdd_HHmmss")
$logDir      = "\\bigberta.onling.com\Backups\Logs\Snapshot-Rollover"
$logFile     = Join-Path $logDir "Snapshot-Rollover_$nowdat.log"
$smtpServer  = "sfl-email-001.onling.com"
$viServer    = "vcenter80.onling.com"
$days        = 3
$mailFrom    = "no_reply@onling.com"
$mailTo      = "robinhood1995@yahoo.com"   # TODO: confirm this is the intended recipient - external address, internal report

# Datastore safety margins used before removing a snapshot
$freeSpaceMultiplier = 1.5   # require this many times the snapshot size free (consolidation can need more than the reported size)
$minFreePercent      = 0.10  # keep at least this fraction of datastore free after removal

if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

# ------------------------------------------------------------------
# Logging / console colour helpers
# ------------------------------------------------------------------
# The log FILE always stays plain text. The colour is purely a console
# convenience for when this is run manually/interactively.
function Write-Log {
    [CmdletBinding()]
    param(
        [ValidateSet("INFO","WARN","ERROR","FATAL","DEBUG")]
        [string]$Level = "INFO",
        [Parameter(Mandatory)]
        [string]$Message
    )
    $stamp = (Get-Date).ToString("yyyy/MM/dd HH:mm:ss")
    $line  = "$stamp $Level $Message"

    Add-Content -Path $logFile -Value $line

    $fg = switch ($Level) {
        "DEBUG" { "DarkGray" }
        "INFO"  { "Cyan" }
        "WARN"  { "Yellow" }
        "ERROR" { "Red" }
        "FATAL" { "White" }
        default { "White" }
    }

    Write-Host "$stamp " -ForegroundColor DarkGray -NoNewline
    if ($Level -eq "FATAL") {
        Write-Host " $Level " -ForegroundColor White -BackgroundColor DarkRed -NoNewline
        Write-Host " $Message" -ForegroundColor White
    }
    else {
        Write-Host ("{0,-5}" -f $Level) -ForegroundColor $fg -NoNewline
        Write-Host " $Message" -ForegroundColor $fg
    }
}

# Coloured banner for section breaks - purely cosmetic for manual runs.
function Write-Banner {
    param(
        [string]$Text,
        [string]$Color = "Cyan"
    )
    $bar = "=" * 70
    Write-Host ""
    Write-Host $bar -ForegroundColor $Color
    Write-Host "  $Text" -ForegroundColor $Color
    Write-Host $bar -ForegroundColor $Color
}

# One-line, colour-coded outcome per VM - green/yellow/red at a glance.
function Write-VMStatus {
    param(
        [Parameter(Mandatory)][string]$VMName,
        [Parameter(Mandatory)][string]$StatusText,
        [ValidateSet("Ok","Warn","Fail","Skip","Dry")]
        [string]$Status = "Ok"
    )
    $color = switch ($Status) {
        "Ok"   { "Green" }
        "Warn" { "Yellow" }
        "Fail" { "Red" }
        "Skip" { "DarkGray" }
        "Dry"  { "Magenta" }
    }
    $icon = switch ($Status) {
        "Ok"   { "[OK]  " }
        "Warn" { "[WARN]" }
        "Fail" { "[FAIL]" }
        "Skip" { "[SKIP]" }
        "Dry"  { "[DRY] " }
    }
    Write-Host "  $icon " -ForegroundColor $color -NoNewline
    Write-Host "$VMName" -ForegroundColor White -NoNewline
    Write-Host " - $StatusText" -ForegroundColor $color
}

# ------------------------------------------------------------------
# Email
# ------------------------------------------------------------------
function Send-SnapMail {
    param($MailTo, $Subject, $Body)
    try {
        $msg  = New-Object Net.Mail.MailMessage
        $smtp = New-Object Net.Mail.SmtpClient($smtpServer)
        $smtp.Port = 25
        $msg.From = $mailFrom
        $msg.To.Add($MailTo)
        $msg.Subject   = $Subject
        $msg.IsBodyHtml = $true
        $msg.Body      = $Body
        $smtp.Send($msg)
    }
    catch {
        Write-Log -Level ERROR -Message "Failed to send email: $($_.Exception.Message)"
    }
}

# ------------------------------------------------------------------
# Credentials
# ------------------------------------------------------------------
# Store credentials securely instead of plaintext variables.
# Option A (per-machine, tied to the account running the task):
#   Get-Credential | Export-Clixml -Path "C:\Scripts\vcenter_cred.xml" -Force
# then load it here:
$CredentialPath = "C:\Scripts\vcenter_cred.xml"

if (Test-Path -Path $CredentialPath) {
    $Credential = Import-Clixml -Path $CredentialPath
}
else {
    Write-Log -Level FATAL -Message "Credential file not found at $CredentialPath"
    Stop-Transcript
    throw "Credential file not found at $CredentialPath"
}

# ------------------------------------------------------------------
# VM exclusions
# ------------------------------------------------------------------
# Two different ways to exclude VMs from being processed:
#
# 1) Set "ignore.snaps" = 1 on the VM, via EITHER of these (Test-VMIgnoreSnaps
#    below checks both):
#      a) VM Advanced Setting / ExtraConfig - vSphere Client > VM > Edit Settings
#         > Advanced > Configuration Parameters > Add Configuration Params, or
#         New-AdvancedSetting -Entity $vm -Name ignore.snaps -Value 1
#      b) a vCenter Custom Attribute named "ignore.snaps" - vSphere Client > VM >
#         Summary > Custom Attributes, or New-CustomAttribute / Set-Annotation.
#         The Custom Attribute path only works if the "ignore.snaps" attribute
#         type has actually been created in vCenter (see the one-time check
#         after Connect-VIServer below).
#
# 2) Edit the JSON file below - exact names and/or wildcard patterns.
$exclusionConfigPath = "C:\Scripts\Snapshot-Exclusions.json"
$excludedVMs      = @()
$excludedPatterns = @()
if (Test-Path $exclusionConfigPath) {
    try {
        $exclusionConfig = Get-Content -Path $exclusionConfigPath -Raw | ConvertFrom-Json
        $excludedVMs      = @($exclusionConfig.ExcludedVMs)
        $excludedPatterns = @($exclusionConfig.ExcludedPatterns)
    }
    catch {
        Write-Log -Level WARN -Message "Could not parse $exclusionConfigPath - continuing with no config-based exclusions: $($_.Exception.Message)"
    }
}
else {
    Write-Log -Level WARN -Message "No exclusion config found at $exclusionConfigPath - all VMs will be evaluated"
}

function Test-VMExcluded {
    param([string]$Name)
    if ($excludedVMs -contains $Name) { return $true }
    foreach ($pattern in $excludedPatterns) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

function Test-VMIgnoreSnaps {
    param($VM)

    # 1) VM Advanced Setting / ExtraConfig: "ignore.snaps" = 1
    #    (vSphere Client > VM > Edit Settings > Advanced > Configuration Parameters,
    #     or: New-AdvancedSetting -Entity $vm -Name ignore.snaps -Value 1)
    try {
        $adv = Get-AdvancedSetting -Entity $VM -Name "ignore.snaps" -ErrorAction SilentlyContinue
        if ($adv -and ("$($adv.Value)".Trim() -eq "1")) { return $true }
    }
    catch { }

    # 2) vCenter Custom Attribute: "ignore.snaps" = 1
    #    (only queried if that attribute type actually exists in this vCenter)
    if ($script:IgnoreSnapsAttrExists) {
        try {
            $attr = Get-Annotation -Entity $VM -Name "ignore.snaps" -ErrorAction SilentlyContinue
            if ($attr -and ("$($attr.Value)".Trim() -eq "1")) { return $true }
        }
        catch { }
    }

    return $false
}

# ------------------------------------------------------------------
# Script start
# ------------------------------------------------------------------
$bannerText  = "Snapshot Rollover - $nowdat"
$bannerColor0 = "Cyan"
if ($DryRun) {
    $bannerText   = "Snapshot Rollover - $nowdat  [DRY RUN - no changes will be made]"
    $bannerColor0 = "Magenta"
}
Write-Banner -Text $bannerText -Color $bannerColor0
Write-Log -Message "Starting the snapshot rollover process"
Write-Log -Message "PowerShell version: $($PSVersionTable.PSVersion)"
if ($DryRun) {
    Write-Log -Level WARN -Message "DRY RUN MODE - no snapshots will be created or removed"
}

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Confirm:$false

$PSModuleAutoLoadingPreference = "All"

Write-Log -Message "Importing VMware.PowerCLI module"

# NOTE: -SkipPublisherCheck is a parameter of Install-Module / Update-Module,
# NOT Import-Module - passing it here throws "A parameter cannot be found
# that matches parameter name 'SkipPublisherCheck'." Kept commented for
# reference in case the module ever needs to be (re)installed on this box:
#   Install-Module -Name VMware.PowerCLI -SkipPublisherCheck -Scope AllUsers -Force
Import-Module -Name VMware.PowerCLI -ErrorAction Stop

Set-PowerCLIConfiguration -ParticipateInCeip $false -Confirm:$false | Out-Null
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

$results   = @()
$connected = $false

try {
    Write-Log -Message "Connecting to vCenter: $viServer"
    Connect-VIServer -Server $viServer -Credential $Credential -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null
    $connected = $true
    Write-Log -Message "Connected to $viServer"

    # Check once whether the "ignore.snaps" Custom Attribute type exists in this
    # vCenter at all, so Test-VMIgnoreSnaps can skip the per-VM Get-Annotation
    # call when it doesn't. The VM Advanced Setting (ExtraConfig) check in
    # Test-VMIgnoreSnaps works regardless of this.
    $script:IgnoreSnapsAttrExists = $false
    try {
        $null = Get-CustomAttribute -Name "ignore.snaps" -ErrorAction Stop
        $script:IgnoreSnapsAttrExists = $true
    }
    catch {
        Write-Log -Level INFO -Message "Custom Attribute 'ignore.snaps' is not defined in vCenter - per-VM exclusion relies on the VM Advanced Setting 'ignore.snaps=1' (ExtraConfig) and the JSON exclusion list. Create the attribute via New-CustomAttribute -Name 'ignore.snaps' -TargetType VirtualMachine if you also want the Custom Attribute path."
    }

    foreach ($vm in Get-VM | Sort-Object Name) {

        Write-Log -Message "Processing $($vm.Name)"

        if (Test-VMExcluded -Name $vm.Name) {
            Write-VMStatus -VMName $vm.Name -Status Skip -StatusText "excluded via config file"
            $results += [PSCustomObject]@{
                VM                   = $vm.Name
                DataCentre           = $null
                VMHost               = $vm.VMHost.Name
                SnapName             = $null
                OldSnap              = $false
                SnapsIgnored         = $true
                DataStoreFreeSpaceOK = $null
                DataStoreFreePctOK   = $null
                Action               = "Skipped (excluded via config file)"
            }
            continue
        }

        if (Test-VMIgnoreSnaps -VM $vm) {
            Write-VMStatus -VMName $vm.Name -Status Skip -StatusText "ignore.snaps=1 (advanced setting or custom attribute)"
            $results += [PSCustomObject]@{
                VM                   = $vm.Name
                DataCentre           = $null
                VMHost               = $vm.VMHost.Name
                SnapName             = $null
                OldSnap              = $false
                SnapsIgnored         = $true
                DataStoreFreeSpaceOK = $null
                DataStoreFreePctOK   = $null
                Action               = "Skipped (ignore.snaps=1)"
            }
            continue
        }

        $vmHostName   = $vm.VMHost.Name
        $vmDatacentre = (Get-VMHost -Name $vmHostName | Get-Datacenter).Name

        # Take the rollover snapshot for this VM
        $snapName = "$($vm.Name)_Snap_$nowdat"
        if ($DryRun) {
            Write-Log -Message "[DRY RUN] Would create snapshot $snapName on $($vm.Name)"
            Write-VMStatus -VMName $vm.Name -Status Dry -StatusText "would create snapshot"
        }
        else {
            try {
                New-Snapshot -VM $vm -Name $snapName -Confirm:$false -ErrorAction Stop | Out-Null
                Write-Log -Message "Created snapshot $snapName on $($vm.Name)"
                Write-VMStatus -VMName $vm.Name -Status Ok -StatusText "snapshot created"
            }
            catch {
                Write-Log -Level ERROR -Message "Failed to create snapshot on $($vm.Name): $($_.Exception.Message)"
                Write-VMStatus -VMName $vm.Name -Status Fail -StatusText "snapshot creation FAILED: $($_.Exception.Message)"
                $results += [PSCustomObject]@{
                    VM                   = $vm.Name
                    DataCentre           = $vmDatacentre
                    VMHost               = $vmHostName
                    SnapName             = $snapName
                    OldSnap              = $false
                    SnapsIgnored         = $false
                    DataStoreFreeSpaceOK = $null
                    DataStoreFreePctOK   = $null
                    Action               = "Snapshot creation FAILED: $($_.Exception.Message)"
                }
                continue
            }
        }

        # Find snapshots older than the retention window (excludes the one just taken)
        $oldSnaps = Get-Snapshot -VM $vm | Where-Object { $_.Created -lt (Get-Date).AddDays(-$days) }

        if (-not $oldSnaps) {
            Write-VMStatus -VMName $vm.Name -Status Ok -StatusText "no snapshots older than $days days"
            $createdNote = "Snapshot created."
            if ($DryRun) { $createdNote = "[DRY RUN] Snapshot would be created." }
            $results += [PSCustomObject]@{
                VM                   = $vm.Name
                DataCentre           = $vmDatacentre
                VMHost               = $vmHostName
                SnapName             = $snapName
                OldSnap              = $false
                SnapsIgnored         = $false
                DataStoreFreeSpaceOK = $null
                DataStoreFreePctOK   = $null
                Action               = "$createdNote No snapshots older than $days days"
            }
            continue
        }

        foreach ($snap in $oldSnaps) {
            Write-Log -Message "Found old snapshot $($snap.Name) ($($snap.SizeGB) GB) on $($vm.Name)"

            $datastore     = $vm | Get-Datastore | Sort-Object FreeSpaceGB | Select-Object -First 1
            $freeSpaceOK   = $datastore.FreeSpaceGB -gt ($snap.SizeGB * $freeSpaceMultiplier)
            $freePercent   = $datastore.FreeSpaceGB / $datastore.CapacityGB
            $freePercentOK = $freePercent -gt $minFreePercent

            $action = "Not removed - insufficient datastore space/headroom"
            if ($freeSpaceOK -and $freePercentOK) {
                if ($DryRun) {
                    $action = "[DRY RUN] Would remove"
                    Write-Log -Message "[DRY RUN] Would remove snapshot $($snap.Name) on $($vm.Name)"
                    Write-VMStatus -VMName $vm.Name -Status Dry -StatusText "would remove '$($snap.Name)'"
                }
                else {
                    try {
                        Remove-Snapshot -Snapshot $snap -Confirm:$false -ErrorAction Stop
                        $action = "Removed"
                        Write-Log -Message "Removed snapshot $($snap.Name) on $($vm.Name)"
                        Write-VMStatus -VMName $vm.Name -Status Ok -StatusText "removed old snapshot '$($snap.Name)'"
                    }
                    catch {
                        $action = "Removal failed: $($_.Exception.Message)"
                        Write-Log -Level ERROR -Message "Failed to remove $($snap.Name) on $($vm.Name): $($_.Exception.Message)"
                        Write-VMStatus -VMName $vm.Name -Status Fail -StatusText "removal failed for '$($snap.Name)'"
                    }
                }
            }
            else {
                Write-Log -Level WARN -Message "Skipping removal of $($snap.Name) on $($vm.Name) - insufficient datastore space/headroom"
                Write-VMStatus -VMName $vm.Name -Status Warn -StatusText "not removed - low datastore headroom for '$($snap.Name)'"
            }

            $results += [PSCustomObject]@{
                VM                   = $vm.Name
                DataCentre           = $vmDatacentre
                VMHost               = $vmHostName
                SnapName             = $snap.Name
                OldSnap              = $true
                SnapsIgnored         = $false
                DataStoreFreeSpaceOK = $freeSpaceOK
                DataStoreFreePctOK   = $freePercentOK
                Action               = $action
            }
        }
    }
}
catch {
    Write-Log -Level FATAL -Message "Snapshot rollover process failed: $($_.Exception.Message)"
    $failSubject = "Snapshot Rollover FAILED for $nowdat"
    if ($DryRun) { $failSubject = "[DRY RUN] $failSubject" }
    Send-SnapMail -MailTo $mailTo -Subject $failSubject `
        -Body "<p>The snapshot rollover script failed with the following error:</p><pre>$($_.Exception.Message)</pre><p>See log: $logFile</p>"
}
finally {
    if ($connected) {
        Disconnect-VIServer -Server $viServer -Confirm:$false
        Write-Log -Message "Disconnected from $viServer"
    }

    # --------------------------------------------------------------
    # Report
    # --------------------------------------------------------------
    if ($results.Count -gt 0) {
        $created = ($results | Where-Object { $_.SnapName -and $_.Action -notlike "Snapshot creation FAILED*" }).Count
        $removed = ($results | Where-Object { $_.Action -eq "Removed" -or $_.Action -eq "[DRY RUN] Would remove" }).Count
        $failed  = ($results | Where-Object { $_.Action -like "*FAILED*" -or $_.Action -like "Removal failed*" }).Count
        $skipped = ($results | Where-Object { $_.SnapsIgnored }).Count

        $bannerColor  = "Green"
        if ($skipped -gt 0) { $bannerColor = "Yellow" }
        if ($failed  -gt 0) { $bannerColor = "Red" }
        if ($DryRun)         { $bannerColor = "Magenta" }

        $skippedColor = "Green"; if ($skipped -gt 0) { $skippedColor = "Yellow" }
        $failedColor  = "Green"; if ($failed  -gt 0) { $failedColor  = "Red" }

        $summaryBannerText = "Run Summary"
        if ($DryRun) { $summaryBannerText = "Run Summary  [DRY RUN - nothing was actually changed]" }

        Write-Banner -Text $summaryBannerText -Color $bannerColor
        Write-Host "  Created: " -NoNewline -ForegroundColor White
        Write-Host "$created" -ForegroundColor Green
        Write-Host "  Removed: " -NoNewline -ForegroundColor White
        Write-Host "$removed" -ForegroundColor Green
        Write-Host "  Skipped: " -NoNewline -ForegroundColor White
        Write-Host "$skipped" -ForegroundColor $skippedColor
        Write-Host "  Failed:  " -NoNewline -ForegroundColor White
        Write-Host "$failed" -ForegroundColor $failedColor
        Write-Host ""

        $dryRunNote = ""
        if ($DryRun) { $dryRunNote = "<p style='color:#a020a0;'><b>DRY RUN - no snapshots were actually created or removed.</b> Figures below show what would have happened.</p>" }
        $summary = "$dryRunNote<p><b>Summary:</b> $created snapshot(s) created, $removed old snapshot(s) removed, $failed failure(s), $skipped VM(s) skipped.</p>"

        $style = @"
<style>
BODY{font-family: Arial; font-size: 10pt;}
TABLE{border: 1px solid black; border-collapse: collapse;}
TH{border: 1px solid black; background: #dddddd; padding: 5px;}
TD{border: 1px solid black; padding: 5px;}
</style>
"@

        $table = $results |
            Select-Object VM, DataCentre, VMHost, SnapName, OldSnap, SnapsIgnored, DataStoreFreeSpaceOK, DataStoreFreePctOK, Action |
            ConvertTo-Html -Fragment |
            Out-String

        $emailBody    = "<html><head>$style</head><body>$summary$table</body></html>"
        $emailSubject = "Snapshot Action table for $nowdat"
        if ($DryRun) { $emailSubject = "[DRY RUN] $emailSubject" }
        Send-SnapMail -MailTo $mailTo -Subject $emailSubject -Body $emailBody
    }
    else {
        Write-Log -Level WARN -Message "No results were recorded - script likely failed before processing any VMs"
    }

    Write-Log -Message "Snapshot rollover process complete"
    # Stop recording
    Stop-Transcript
}