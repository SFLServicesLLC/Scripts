<#
    Run this ONCE, on the same machine and under the same Windows account
    that will run Snapshot-Rollover.ps1 (e.g. log in as the scheduled task's
    service account, or run this from within that scheduled task once).

    Export-Clixml encrypts the password using Windows DPAPI, tied to:
      - the Windows user account that created it, AND
      - the machine it was created on.

    That means:
      - Only that same user, on that same machine, can decrypt it later.
      - If you change the service account or move the script to a new
        server, you MUST re-run this setup script there too.
#>

$credPath = "C:\Scripts\vcenter_cred.xml"

# Prompts for username/password interactively - nothing is typed into
# a script or stored in plain text.
$cred = Get-Credential -Message "Enter the vCenter service account (e.g. DOMAIN\svc-vcenter or svc-vcenter@vsphere.local)"

# Make sure the folder exists
$credDir = Split-Path $credPath -Parent
if (-not (Test-Path $credDir)) {
    New-Item -Path $credDir -ItemType Directory -Force | Out-Null
}

$cred | Export-Clixml -Path $credPath

Write-Host "Credential saved to $credPath"
Write-Host "This file is only usable by $($env:USERNAME) on $($env:COMPUTERNAME)."