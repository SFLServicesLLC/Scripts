#/*****************************************************************************
#/*     Script : pingMonitor.ps1
#/*   Function : This script is ping a server ti see if any
#/*              drop in network happens
#/*    Written : 6 May 2026
#/*     Author : Steven F Ling
#/*
#/*****************************************************************************
# Revision History :
VERSION=1.1
# *(#) Date               BY            Revision Description
# *(#) ---------    ---------------     --------------------
# *(#) 2026-05-06   Steve Ling          Created
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
       powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Scripts\PingMonitor.ps1" -TargetIP "8.8.8.8"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$TargetIP,

    [string]$LogPath = "C:\Logs\PingMonitor.log",

    [int]$PingIntervalSeconds = 2,
    [int]$TimeoutMs = 1000,
    [int]$ConsecutiveFailuresAlert = 3,

    # ==================== EMAIL SETTINGS ====================
    [string]$SmtpServer = "",           # e.g. "smtp.gmail.com" or "mail.contoso.com"
    [int]$SmtpPort = 587,
    [string]$FromEmail = "",
    [string[]]$ToEmail = @(),           # e.g. @("admin@contoso.com", "netops@contoso.com")
    [string]$Username = "",             # SMTP username (often same as FromEmail)
    [string]$Password = "",             # Use a secure method in production!
    [bool]$UseSSL = $true,
    [int]$AlertCooldownMinutes = 15     # Minimum time between repeated alerts
    # ======================================================
)

# Ensure log directory exists
$LogDir = Split-Path $LogPath -Parent
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
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

# Log function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp [$Level] $Message" | Out-File -FilePath $LogPath -Append -Encoding UTF8
    Write-Host "$Timestamp [$Level] $Message"
}

# Initialize
$failureCount = 0
$lastAlertTime = [DateTime]::MinValue
$inFailureState = $false
$scriptStart = Get-Date

Write-Log "=== Ping Monitor Started for $TargetIP ===" "START"
Write-Log "Log: $LogPath | Interval: ${PingIntervalSeconds}s | Email enabled: $(if($SmtpServer){'Yes'}else{'No'})" "INFO"

try {
    while ($true) {
        $pingResult = Test-Connection -ComputerName $TargetIP -Count 1 -TimeoutMilliseconds $TimeoutMs -Quiet -ErrorAction SilentlyContinue
        $currentTime = Get-Date

        if ($pingResult) {
            # ===================== SUCCESS =====================
            if ($inFailureState) {
                $duration = [math]::Round(($currentTime - $failureStartTime).TotalMinutes, 1)
                $subject = "✅ NETWORK RESTORED - $TargetIP is back online"
                $body = "Ping to $TargetIP has recovered.`n`nDowntime duration: $duration minutes`nTime: $currentTime"
                
                Send-PingAlert -Subject $subject -Body $body
                Write-Log "NETWORK RESTORED after $duration minutes" "RECOVERED"
                
                $inFailureState = $false
            }
            $failureCount = 0
        }
        else {
            # ===================== FAILURE =====================
            $failureCount++
            
            if (-not $inFailureState -and $failureCount -ge $ConsecutiveFailuresAlert) {
                # First time we declare it a drop
                $failureStartTime = $currentTime
                $inFailureState = $true
                
                $subject = "❌ NETWORK DROP DETECTED - $TargetIP unreachable"
                $body = "Failed to ping $TargetIP for $ConsecutiveFailuresAlert consecutive attempts.`n`nStart time: $currentTime`nTarget: $TargetIP"
                
                Send-PingAlert -Subject $subject -Body $body
                Write-Log "NETWORK DROP DETECTED" "ERROR"
            }
            elseif ($inFailureState) {
                # Ongoing outage - send periodic reminder
                $minutesSinceLastAlert = ($currentTime - $lastAlertTime).TotalMinutes
                if ($minutesSinceLastAlert -ge $AlertCooldownMinutes) {
                    $duration = [math]::Round(($currentTime - $failureStartTime).TotalMinutes, 1)
                    $subject = "⚠️ ONGOING NETWORK OUTAGE - $TargetIP still down"
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