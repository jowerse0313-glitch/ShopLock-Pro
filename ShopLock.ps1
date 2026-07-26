# ShopLock Portable Toolkit - Pure PowerShell (no Python needed)
# Double-click Run-ShopLock.bat or run this script directly

$ErrorActionPreference = "SilentlyContinue"
$Host.UI.RawUI.WindowTitle = "ShopLock Toolkit"

# ===== CONFIG =====
$config = @{
    YourName       = "Raymond"
    BusinessName   = "ShopLock by Raymond"
    ReportEmail    = "raymondrayray777@gmail.com"
    SetupFee       = 249
    MonthlyPrice   = 79
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$reportsDir = Join-Path $scriptDir "reports"
$alertsDir  = Join-Path $scriptDir "alerts"

if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }
if (-not (Test-Path $alertsDir))  { New-Item -ItemType Directory -Path $alertsDir  | Out-Null }

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "  $($config.BusinessName)" -ForegroundColor Cyan
    Write-Host "  Operator: $($config.YourName)" -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "  Only run this on networks you have permission to secure." -ForegroundColor Yellow
    Write-Host ""
}

function Get-NetworkDevices {
    $devices = @()
    $arpOutput = arp -a 2>$null

    foreach ($line in $arpOutput) {
        if ($line -match "(\d+\.\d+\.\d+\.\d+)\s+([0-9a-fA-F-]{17})\s+(\w+)") {
            $ip  = $matches[1]
            $mac = $matches[2] -replace "-", ":"
            $type = $matches[3]
            if ($mac -ne "00:00:00:00:00:00") {
                $devices += [PSCustomObject]@{
                    IP   = $ip
                    MAC  = $mac.ToLower()
                    Type = $type
                }
            }
        }
    }

    # Deduplicate by MAC
    $devices | Sort-Object MAC -Unique
}

function Save-Report {
    param($devices)

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $txtFile   = Join-Path $reportsDir "scan_$timestamp.txt"
    $jsonFile  = Join-Path $reportsDir "scan_$timestamp.json"

    $reportText = @"
ShopLock Network Scan - $(Get-Date -Format "yyyy-MM-dd HH:mm")
==================================================

Total devices found: $($devices.Count)

"@

    $i = 1
    foreach ($d in $devices) {
        $reportText += "{0,2}. IP: {1,-16}  MAC: {2,-18}  Type: {3}`n" -f $i, $d.IP, $d.MAC, $d.Type
        $i++
    }

    $reportText += @"

==================================================
Next steps:
1. Identify every device you recognize (POS, cameras, phones, printers)
2. Anything unknown should be investigated or blocked via MAC filter
3. Change WiFi password and enable WPA3 if not already done
4. Collect setup fee (`$$($config.SetupFee)`) and start monthly (`$$($config.MonthlyPrice)`)
"@

    $reportText | Out-File -FilePath $txtFile -Encoding utf8

    # Simple JSON
    $jsonObj = @{
        timestamp    = (Get-Date).ToString("o")
        device_count = $devices.Count
        devices      = $devices
    }
    $jsonObj | ConvertTo-Json -Depth 4 | Out-File -FilePath $jsonFile -Encoding utf8

    return $txtFile, $jsonFile
}

function Show-Checklist {
    Write-Host ""
    Write-Host "--------------------------------------------------" -ForegroundColor Green
    Write-Host " QUICK LOCKDOWN CHECKLIST (do these with the owner)" -ForegroundColor Green
    Write-Host "--------------------------------------------------" -ForegroundColor Green
    Write-Host @"

1. Log into the router (usually 192.168.1.1 or 192.168.0.1)
2. Change the router ADMIN password (not just the WiFi password)
3. Set WiFi security to WPA3-Personal (or WPA2/WPA3 mixed)
4. Set a strong 20+ character WiFi password
5. Turn OFF WPS
6. Enable MAC address filtering → Allow list only
   - Add the POS, cameras, and known staff devices
7. Create or enable a Guest network for customers (isolated)
8. On the POS machine:
   - Change login / admin PIN
   - Enable auto screen lock (30-60 seconds)
   - Make sure Windows / POS software is fully updated
9. Save the scan report we just made and email a copy to yourself
10. Collect setup fee (`$$($config.SetupFee)`) and start monthly subscription (`$$($config.MonthlyPrice)`)

"@
    Write-Host "Press Enter to return to menu..." -NoNewline
    Read-Host | Out-Null
}

function Install-Monitor {
    Write-Host ""
    Write-Host "Installing ShopLock monitor (runs every 6 hours)..." -ForegroundColor Yellow

    $taskName = "ShopLockMonitor"
    $psPath   = (Get-Command powershell.exe).Source
    $script   = Join-Path $scriptDir "ShopLock.ps1"
    $action   = "$psPath -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Monitor"

    # Remove old task if exists
    schtasks /Delete /TN $taskName /F 2>$null | Out-Null

    $result = schtasks /Create /TN $taskName /TR $action /SC HOURLY /MO 6 /F /RL LIMITED 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Monitor installed successfully." -ForegroundColor Green
        Write-Host "    It will run every 6 hours in the background."
        Write-Host "    Manage it in Task Scheduler → ShopLockMonitor"
    } else {
        Write-Host "[!] Could not create scheduled task." -ForegroundColor Red
        Write-Host "    Try running this tool as Administrator."
        Write-Host $result
    }
    Write-Host ""
    Write-Host "Press Enter to continue..." -NoNewline
    Read-Host | Out-Null
}

function Run-MonitorMode {
    # Silent mode for scheduled task
    $devices = Get-NetworkDevices
    $txt, $json = Save-Report $devices

    $alertFile = Join-Path $alertsDir ("alert_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $body = @"
ShopLock Monitor Report
Time: $(Get-Date -Format "yyyy-MM-dd HH:mm")
Devices found: $($devices.Count)

Full report: $txt

Device list:
"@
    foreach ($d in $devices) {
        $body += "  $($d.IP.PadRight(16))  $($d.MAC)`n"
    }
    $body | Out-File -FilePath $alertFile -Encoding utf8
    exit
}

# ===== MAIN =====
if ($args -contains "-Monitor") {
    Run-MonitorMode
}

Show-Banner

do {
    Write-Host "What do you want to do?"
    Write-Host "  1. Scan network and create report"
    Write-Host "  2. Install ongoing monitor (every 6 hours)"
    Write-Host "  3. Show quick lockdown checklist"
    Write-Host "  4. Exit"
    Write-Host ""
    $choice = Read-Host "Choose [1-4]"

    switch ($choice) {
        "1" {
            Write-Host ""
            Write-Host "Scanning local network..." -ForegroundColor Yellow
            $devices = Get-NetworkDevices
            Write-Host ""
            Write-Host "Found $($devices.Count) device(s):" -ForegroundColor Green
            Write-Host ""
            $i = 1
            foreach ($d in $devices) {
                Write-Host ("  {0}. {1,-16}  {2}" -f $i, $d.IP, $d.MAC)
                $i++
            }
            $txtFile, $jsonFile = Save-Report $devices
            Write-Host ""
            Write-Host "[OK] Report saved:" -ForegroundColor Green
            Write-Host "     $txtFile"
            Write-Host ""
            Write-Host "Give the .txt file to the owner or keep it for your records."
            Write-Host ""
            Write-Host "Press Enter to continue..." -NoNewline
            Read-Host | Out-Null
            Show-Banner
        }
        "2" {
            Install-Monitor
            Show-Banner
        }
        "3" {
            Show-Checklist
            Show-Banner
        }
        "4" {
            Write-Host ""
            Write-Host "Done. Stay safe out there." -ForegroundColor Cyan
            Write-Host ""
            break
        }
        default {
            Write-Host "Invalid choice." -ForegroundColor Red
            Start-Sleep -Seconds 1
            Show-Banner
        }
    }
} while ($true)
