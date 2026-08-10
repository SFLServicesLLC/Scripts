#/*****************************************************************************
#/*     Script : pingMonitor.ps1
#/*   Function : This script pings an IP address to see if any
#/*              drop on the network happens
#/*    Written : 6 May 2026
#/*     Author : Steven F Ling
#/*
#/*****************************************************************************
# Revision History :
# VERSION: 1.3
# *(#) Date               BY            Revision Description
# *(#) ---------    ---------------     --------------------
# *(#) 2026-05-06   Steve Ling          Created
# *(#) 2026-08-09   (revised)           Fixed ToEmail default-value syntax bug
# *(#)                                  (was unquoted, script would not parse).
# *(#)                                  Switched to .NET Ping for latency data,
# *(#)                                  added Ctrl+C handling, log rotation,
# *(#)                                  and packet-loss stats in alerts.
# *(#) 2026-08-09   (revised)           Added colorized console log output and
# *(#)                                  a per-ping live status line (screen
# *(#)                                  only, via -ShowLivePings).
# *(#)
#
#*****************************************************************************
<#
.SYNOPSIS
    Continuous network ping monitor for Windows Server.
    Logs ping results to a file and detects network drops.

.DESCRIPTION
    This script pings a target IP continuously and logs successes/failures.
    It is designed to run in the background with low CPU usage.

    Recommended way to run in background:
    1. Save as C:\Scripts\PingMonitor.ps1
    2. Run via Task Scheduler (see instructions below) or:
       powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Scripts\PingMonitor.ps1" -TargetIP "8.8.8.8" -ToEmail "netops@contoso.com"

.NOTES
    -Password is accepted as a plain string for simplicity. For anything
    beyond ad-hoc use, prefer storing credentials with Export-Clixml
    (tied to the running user/machine) or reading from an environment
    variable instead of passing it as a script argument, since arguments
    can show up in process listings and Task Scheduler history.
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$TargetIP,

    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ToEmail,                 # e.g. -ToEmail "admin@contoso.com","netops@contoso.com"

    [string]$nowdat = (Get-Date).ToString("yyyyMMdd_HHmmss"),
    [string]$logDir = "C:\Scripts\PingMonitor",
    [string]$LogPath = (Join-Path $logDir "PingMonitor_$nowdat.log"),
    [long]$MaxLogSizeBytes = 1MB,

    [int]$PingIntervalSeconds = 2,
    [int]$TimeoutMs = 1000,
    [int]$ConsecutiveFailuresAlert = 3,

    # ==================== EMAIL SETTINGS ====================
    [string]$SmtpServer = "mail.onling.com",           # e.g. "smtp.gmail.com" or "mail.contoso.com"
    [int]$SmtpPort = 25,
    [string]$FromEmail = "server@onling.com",
    [string]$Username = "",             # SMTP username (often same as FromEmail)
    [string]$Password = "",             # Prefer Export-Clixml or an env var over passing this directly
    [bool]$UseSSL = $false,
    [int]$AlertCooldownMinutes = 15,    # Minimum time between repeated alerts
    # ======================================================

    [bool]$ShowLivePings = $true        # Print a colored line per ping when run on screen (has no effect on the log file)
)

# Only colorize if attached to a real console - avoids errors/garbage when
# running headless under Task Scheduler with output redirected to a file.
$script:UseColor = [Environment]::UserInteractive -and -not ([Console]::IsOutputRedirected)

# Ensure log directory exists
$LogDir = Split-Path $LogPath -Parent
if ($LogDir -and -not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

# Rotate the log if it's grown past the size threshold
function Invoke-LogRotation {
    if ((Test-Path $LogPath) -and (Get-Item $LogPath).Length -ge $MaxLogSizeBytes) {
        $archivePath = "$LogPath.{0:yyyyMMdd_HHmmss}.bak" -f (Get-Date)
        Rename-Item -Path $LogPath -NewName (Split-Path $archivePath -Leaf) -Force
    }
}

# Log function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    Invoke-LogRotation
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$Timestamp [$Level] $Message"
    $line | Out-File -FilePath $LogPath -Append -Encoding UTF8

    if ($script:UseColor) {
        $color = switch ($Level) {
            "ERROR"     { "Red" }
            "WARNING"   { "Yellow" }
            "RECOVERED" { "Green" }
            "START"     { "Cyan" }
            "STOP"      { "Cyan" }
            default     { "Gray" }
        }
        Write-Host $line -ForegroundColor $color
    }
    else {
        Write-Host $line
    }
}

# Per-ping console line (screen only - not written to the log file, to keep it small)
function Write-PingStatus {
    param([bool]$Success, [Nullable[int]]$RoundtripMs)
    if (-not $ShowLivePings) { return }

    $Timestamp = Get-Date -Format "HH:mm:ss"
    if ($Success) {
        $text = "$Timestamp  OK    $TargetIP  ${RoundtripMs}ms"
        if ($script:UseColor) { Write-Host $text -ForegroundColor DarkGreen } else { Write-Host $text }
    }
    else {
        $text = "$Timestamp  FAIL  $TargetIP  (timeout/unreachable)"
        if ($script:UseColor) { Write-Host $text -ForegroundColor DarkRed } else { Write-Host $text }
    }
}

# Email function
function Send-PingAlert {
    param(
        [string]$Subject,
        [string]$Body
    )

    if ([string]::IsNullOrEmpty($SmtpServer) -or $ToEmail.Count -eq 0) {
        Write-Log "Email alert skipped - SMTP settings not configured" "WARNING"
        return
    }

    try {
        $mailParams = @{
            From       = $FromEmail
            To         = $ToEmail
            Subject    = $Subject
            Body       = $Body
            SmtpServer = $SmtpServer
            Port       = $SmtpPort
            UseSsl     = $UseSSL
            BodyAsHtml = $false
        }

        if (-not [string]::IsNullOrEmpty($Username) -and -not [string]::IsNullOrEmpty($Password)) {
            $mailParams.Credential = New-Object System.Management.Automation.PSCredential ($Username, (ConvertTo-SecureString $Password -AsPlainText -Force))
        }

        Send-MailMessage @mailParams -ErrorAction Stop
        Write-Log "Email alert sent successfully: $Subject" "INFO"
    }
    catch {
        Write-Log "Failed to send email alert: $($_.Exception.Message)" "ERROR"
    }
}

# Single ping using .NET (faster and gives round-trip time, unlike Test-Connection -Quiet)
$pingSender = New-Object System.Net.NetworkInformation.Ping
function Invoke-SinglePing {
    param([string]$Target, [int]$TimeoutMs)
    try {
        $reply = $pingSender.Send($Target, $TimeoutMs)
        return @{
            Success = ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success)
            RoundtripMs = $reply.RoundtripTime
        }
    }
    catch {
        return @{ Success = $false; RoundtripMs = $null }
    }
}

# Initialize
$failureCount = 0
$totalAttempts = 0
$failuresDuringOutage = 0
$lastAlertTime = [DateTime]::MinValue
$inFailureState = $false
$scriptStart = Get-Date

# Make sure a stop event is logged even on Ctrl+C / console close
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Write-Log "=== Ping Monitor Stopped (process exiting) ===" "STOP"
}

Write-Log "=== Ping Monitor Started for $TargetIP ===" "START"
Write-Log "Log: $LogPath | Interval: ${PingIntervalSeconds}s | Email enabled: $(if($SmtpServer){'Yes'}else{'No'})" "INFO"

try {
    while ($true) {
        $result = Invoke-SinglePing -Target $TargetIP -TimeoutMs $TimeoutMs
        $currentTime = Get-Date
        $totalAttempts++

        Write-PingStatus -Success $result.Success -RoundtripMs $result.RoundtripMs

        if ($result.Success) {
            # ===================== SUCCESS =====================
            if ($inFailureState) {
                $duration = [math]::Round(($currentTime - $failureStartTime).TotalMinutes, 1)
                $subject = "NETWORK RESTORED - $TargetIP is back online"
                $body = "Ping to $TargetIP has recovered.`n`nDowntime duration: $duration minutes`nFailed attempts during outage: $failuresDuringOutage`nTime: $currentTime"

                Send-PingAlert -Subject $subject -Body $body
                Write-Log "NETWORK RESTORED after $duration minutes ($failuresDuringOutage failed attempts)" "RECOVERED"

                $inFailureState = $false
                $failuresDuringOutage = 0
            }
            $failureCount = 0
        }
        else {
            # ===================== FAILURE =====================
            $failureCount++
            if ($inFailureState) { $failuresDuringOutage++ }

            if (-not $inFailureState -and $failureCount -ge $ConsecutiveFailuresAlert) {
                # First time we declare it a drop
                $failureStartTime = $currentTime
                $inFailureState = $true
                $failuresDuringOutage = $failureCount

                $subject = "NETWORK DROP DETECTED - $TargetIP unreachable"
                $body = "Failed to ping $TargetIP for $ConsecutiveFailuresAlert consecutive attempts.`n`nStart time: $currentTime`nTarget: $TargetIP"

                Send-PingAlert -Subject $subject -Body $body
                Write-Log "NETWORK DROP DETECTED" "ERROR"
            }
            elseif ($inFailureState) {
                # Ongoing outage - send periodic reminder
                $minutesSinceLastAlert = ($currentTime - $lastAlertTime).TotalMinutes
                if ($minutesSinceLastAlert -ge $AlertCooldownMinutes) {
                    $duration = [math]::Round(($currentTime - $failureStartTime).TotalMinutes, 1)
                    $subject = "ONGOING NETWORK OUTAGE - $TargetIP still down"
                    $body = "Ping to $TargetIP is still failing.`n`nOutage duration: $duration minutes`nConsecutive failures: $failureCount`nTime: $currentTime"

                    Send-PingAlert -Subject $subject -Body $body
                    $lastAlertTime = $currentTime
                }
            }
        }

        Start-Sleep -Seconds $PingIntervalSeconds
    }
}
catch {
    Write-Log "Script error: $($_.Exception.Message)" "ERROR"
}
finally {
    Write-Log "=== Ping Monitor Stopped ===" "STOP"
}