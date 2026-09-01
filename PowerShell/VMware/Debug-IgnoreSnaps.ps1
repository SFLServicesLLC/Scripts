# ==============================================================================
# Script: Debug-IgnoreSnaps
# Purpose: Smoke-test the "ignore.snaps = 1" exclusion path used by
#          Snapshot-Rollover.ps1, against the live vCenter, for one VM.
#          Checks BOTH sources the real script now uses:
#            1) VM Advanced Setting / ExtraConfig  "ignore.snaps" = 1
#            2) vCenter Custom Attribute           "ignore.snaps" = 1
#          Prints every intermediate value. Makes NO changes.
#
# Usage:
#   .\Debug-IgnoreSnaps.ps1 -VMName 'SFL-CA-001_W25'
#   .\Debug-IgnoreSnaps.ps1 -VMName 'SFL-CA-001'          # wildcard fallback
# ==============================================================================
param(
    [Parameter(Mandatory)][string]$VMName,
    [string]$AttributeName  = 'ignore.snaps',
    [string]$ViServer       = 'vcenter80.onling.com',
    [string]$CredentialPath = 'C:\Scripts\vcenter_cred.xml'
)

$ErrorActionPreference = 'Stop'

function Line($k, $v) { '{0,-38}: {1}' -f $k, $v }

Import-Module VMware.PowerCLI -ErrorAction Stop | Out-Null
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

if (-not (Test-Path $CredentialPath)) { throw "Credential file not found: $CredentialPath" }
$cred = Import-Clixml $CredentialPath

Write-Host "Connecting to $ViServer ..." -ForegroundColor Cyan
Connect-VIServer -Server $ViServer -Credential $cred -WarningAction SilentlyContinue | Out-Null

try {
    Write-Host "`n--- 1. Resolve the VM ---" -ForegroundColor Yellow
    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-Host (Line "exact match for '$VMName'" "none - trying wildcard *$VMName*") -ForegroundColor DarkYellow
        $vm = Get-VM -Name "*$VMName*" -ErrorAction SilentlyContinue
    }
    if (-not $vm)            { throw "No VM matched '$VMName' (exact or wildcard)." }
    if (@($vm).Count -gt 1)  {
        Write-Host (Line "matched" (($vm.Name) -join ', ')) -ForegroundColor Red
        throw "VM name is ambiguous - pass the exact name."
    }
    Write-Host (Line "VM" $vm.Name) -ForegroundColor Green

    Write-Host "`n--- 2. Source A: VM Advanced Setting / ExtraConfig ---" -ForegroundColor Yellow
    $adv = Get-AdvancedSetting -Entity $vm -Name $AttributeName -ErrorAction SilentlyContinue
    if ($adv) {
        Write-Host (Line "Get-AdvancedSetting .Value" ("[{0}]" -f $adv.Value))
        Write-Host (Line '("$($adv.Value)".Trim() -eq "1")' ("$($adv.Value)".Trim() -eq '1'))
    } else {
        Write-Host (Line "Get-AdvancedSetting" "not set on this VM") -ForegroundColor DarkYellow
    }
    Write-Host "  (raw ExtraConfig entry, for reference:)"
    $vm.ExtensionData.Config.ExtraConfig |
        Where-Object { $_.Key -like "*$AttributeName*" } |
        Select-Object Key, Value | Format-Table -AutoSize | Out-String | Write-Host

    Write-Host "`n--- 3. Source B: vCenter Custom Attribute ---" -ForegroundColor Yellow
    $script:IgnoreSnapsAttrExists = $false
    try {
        $null = Get-CustomAttribute -Name $AttributeName -ErrorAction Stop
        $script:IgnoreSnapsAttrExists = $true
        Write-Host (Line "attribute type exists in vCenter" "YES") -ForegroundColor Green
    }
    catch {
        Write-Host (Line "attribute type exists in vCenter" "NO (Custom Attribute path is skipped)") -ForegroundColor DarkYellow
    }
    if ($script:IgnoreSnapsAttrExists) {
        $attr = Get-Annotation -Entity $vm -Name $AttributeName -ErrorAction SilentlyContinue
        if ($attr) {
            Write-Host (Line "Get-Annotation .Value" ("[{0}]" -f $attr.Value))
            Write-Host (Line '("$($attr.Value)".Trim() -eq "1")' ("$($attr.Value)".Trim() -eq '1'))
        } else {
            Write-Host (Line "Get-Annotation" "not set on this VM") -ForegroundColor DarkYellow
        }
    }

    Write-Host "`n--- 4. Everything set on this VM (for context) ---" -ForegroundColor Yellow
    Write-Host "  Custom Attributes:"
    Get-Annotation -Entity $vm | Where-Object { $_.Value } | Select-Object Name, Value | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "  Tags:"
    try { Get-TagAssignment -Entity $vm | Select-Object -ExpandProperty Tag | Format-Table -AutoSize | Out-String | Write-Host }
    catch { Write-Host (Line "  tag lookup" $_.Exception.Message) }

    Write-Host "`n--- VERDICT (same logic as Test-VMIgnoreSnaps) ---" -ForegroundColor Cyan
    $viaAdv  = [bool]($adv  -and ("$($adv.Value)".Trim()  -eq '1'))
    $viaAttr = [bool]($script:IgnoreSnapsAttrExists -and $attr -and ("$($attr.Value)".Trim() -eq '1'))
    Write-Host (Line "excluded via Advanced Setting" $viaAdv)
    Write-Host (Line "excluded via Custom Attribute" $viaAttr)
    $wouldExclude = $viaAdv -or $viaAttr
    Write-Host (Line "Snapshot-Rollover would SKIP this VM?" $wouldExclude) -ForegroundColor $(if ($wouldExclude) { 'Green' } else { 'Red' })
}
finally {
    Disconnect-VIServer -Server $ViServer -Confirm:$false -ErrorAction SilentlyContinue
}
