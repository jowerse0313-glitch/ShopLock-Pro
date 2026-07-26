# ShopLock-Pro v1.0
# Network & POS lockdown toolkit for independent coffee shops
# Author: Raymond / ShopLock
# Run via Run-ShopLock.bat (ExecutionPolicy Bypass)

#Requires -Version 5.1

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ReportsDir = Join-Path $ScriptDir "reports"
$AlertsDir  = Join-Path $ScriptDir "alerts"

# Ensure folders exist
if (-not (Test-Path $ReportsDir)) { New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null }
if (-not (Test-Path $AlertsDir))  { New-Item -ItemType Directory -Path $AlertsDir  -Force | Out-Null }

function Show-Header {
    Clear-Host
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   ShopLock-Pro  |  Network Lockdown" -ForegroundColor Cyan
    Write-Host "   For coffee shops & small restaurants" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-LocalNetworkInfo {
    $adapters = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
        $_.IPAddress -notlike "127.*" -and $_.PrefixOrigin -ne "WellKnown"
    } | Select-Object -First 1

    if (-not $adapters) {
        return $null
    }

    $ip = $adapters.IPAddress
    $prefix = $adapters.PrefixLength
    $iface = $adapters.InterfaceAlias

    # Simple subnet calculation (works for common /24)
    $ipParts = $ip.Split('.')
    $subnet = "$($ipParts[0]).$($ipParts[1]).$($ipParts[2]).0"
    $broadcastHint = "$($ipParts[0]).$($ipParts[1]).$($ipParts[2]).255"

    return [PSCustomObject]@{
        IP          = $ip
        Prefix      = $prefix
        Interface   = $iface
        Subnet      = $subnet
        Broadcast   = $broadcastHint
    }
}

function Scan-NetworkDevices {
    param($NetInfo)

    Write-Host "[*] Scanning local network devices..." -ForegroundColor Yellow
    Write-Host "    Local IP : $($NetInfo.IP)" -ForegroundColor Gray
    Write-Host "    Interface: $($NetInfo.Interface)" -ForegroundColor Gray
    Write-Host ""

    $devices = @()

    # Method 1: ARP table (fast, shows recently active devices)
    try {
        $arp = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
               Where-Object { $_.State -eq "Reachable" -or $_.State -eq "Stale" -or $_.State -eq "Permanent" } |
               Where-Object { $_.IPAddress -notlike "224.*" -and $_.IPAddress -notlike "239.*" }

        foreach ($entry in $arp) {
            $hostname = $null
            try {
                $hostname = [System.Net.Dns]::GetHostEntry($entry.IPAddress).HostName
            } catch {}

            $devices += [PSCustomObject]@{
                IP       = $entry.IPAddress
                MAC      = $entry.LinkLayerAddress
                Hostname = if ($hostname) { $hostname } else { "-" }
                State    = $entry.State
                Source   = "ARP"
            }
        }
    } catch {
        Write-Host "    [!] ARP scan limited (may need Admin)" -ForegroundColor DarkYellow
    }

    # Method 2: Quick ping sweep of common range if /24 (optional, slower)
    if ($NetInfo.Prefix -eq 24 -and $devices.Count -lt 5) {
        Write-Host "    Running light ping sweep for more devices..." -ForegroundColor Gray
        $base = ($NetInfo.IP -split '\.')[0..2] -join '.'
        1..254 | ForEach-Object -Parallel {
            $ip = "$using:base.$_"
            if (Test-Connection -ComputerName $ip -Count 1 -Quiet -TimeoutSeconds 1) {
                [PSCustomObject]@{ IP = $ip }
            }
        } -ThrottleLimit 40 -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.IP -and ($devices.IP -notcontains $_.IP)) {
                $devices += [PSCustomObject]@{
                    IP       = $_.IP
                    MAC      = "-"
                    Hostname = "-"
                    State    = "Responded"
                    Source   = "Ping"
                }
            }
        }
    }

    # Deduplicate by IP
    $devices = $devices | Sort-Object IP -Unique

    return $devices
}

function Save-Report {
    param($Devices, $NetInfo)

    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $reportFile = Join-Path $ReportsDir "ShopLock_Scan_$timestamp.txt"

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("ShopLock-Pro Network Scan Report")
    [void]$sb.AppendLine("Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    [void]$sb.AppendLine("Local IP  : $($NetInfo.IP)")
    [void]$sb.AppendLine("Interface : $($NetInfo.Interface)")
    [void]$sb.AppendLine("Subnet    : $($NetInfo.Subnet)/$($NetInfo.Prefix)")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Devices found: $($Devices.Count)")
    [void]$sb.AppendLine("----------------------------------------")
    [void]$sb.AppendLine(("{0,-16} {1,-18} {2,-25} {3}" -f "IP Address", "MAC Address", "Hostname", "State"))
    [void]$sb.AppendLine("----------------------------------------")

    foreach ($d in $Devices) {
        [void]$sb.AppendLine(("{0,-16} {1,-18} {2,-25} {3}" -f $d.IP, $d.MAC, $d.Hostname, $d.State))
    }

    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Notes:")
    [void]$sb.AppendLine("- This is a snapshot of devices seen on the network.")
    [void]$sb.AppendLine("- Unknown or unexpected devices should be investigated.")
    [void]$sb.AppendLine("- POS terminal, routers, printers, and staff phones are normal.")
    [void]$sb.AppendLine("- ShopLock does not change any router settings automatically.")

    $sb.ToString() | Out-File -FilePath $reportFile -Encoding UTF8

    Write-Host ""
    Write-Host "[+] Report saved:" -ForegroundColor Green
    Write-Host "    $reportFile" -ForegroundColor White
    return $reportFile
}

function Show-LockdownChecklist {
    Write-Host ""
    Write-Host "=== Recommended Lockdown Checklist ===" -ForegroundColor Cyan
    Write-Host "1. Log into the router (usually 192.168.0.1 or 192.168.1.1)"
    Write-Host "2. Change the default admin password to a strong unique one"
    Write-Host "3. Set a strong WiFi password (WPA2/WPA3) and hide SSID if desired"
    Write-Host "4. Enable MAC filtering only if the shop has a fixed set of devices"
    Write-Host "5. Disable WPS (WiFi Protected Setup) – it is a known weak point"
    Write-Host "6. Create a separate Guest network for customers (isolate it)"
    Write-Host "7. Make sure the POS terminal is on the main (trusted) network only"
    Write-Host "8. Update router firmware if an update is available"
    Write-Host "9. Note the list of trusted devices from this scan and keep it"
    Write-Host "10. Schedule the monthly ShopLock check (or use the monitor)"
    Write-Host ""
    Write-Host "ShopLock does NOT change router settings for you." -ForegroundColor Yellow
    Write-Host "You (or the owner) must log into the router and apply the above." -ForegroundColor Yellow
}

function Install-Monitor {
    Write-Host ""
    Write-Host "[*] Installing quiet background monitor (every 6 hours)..." -ForegroundColor Yellow

    $monitorScript = Join-Path $ScriptDir "ShopLock-Monitor.ps1"

    # Create a simple monitor script that diffs against last known good list
    $monitorContent = @"
# ShopLock quiet monitor - runs every 6 hours
`$ScriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$AlertsDir = Join-Path `$ScriptDir "alerts"
`$ReportsDir = Join-Path `$ScriptDir "reports"
if (-not (Test-Path `$AlertsDir)) { New-Item -ItemType Directory -Path `$AlertsDir -Force | Out-Null }

`$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
`$logFile = Join-Path `$AlertsDir "monitor_`$timestamp.txt"

try {
    `$neighbors = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                 Where-Object { `$_.State -match "Reachable|Stale|Permanent" } |
                 Select-Object IPAddress, LinkLayerAddress
    `$count = (`$neighbors | Measure-Object).Count
    "ShopLock Monitor - `$(Get-Date)" | Out-File `$logFile
    "Devices currently visible: `$count" | Out-File `$logFile -Append
    `$neighbors | Format-Table -AutoSize | Out-String | Out-File `$logFile -Append
} catch {
    "Monitor error: `$_" | Out-File `$logFile
}
"@

    $monitorContent | Out-File -FilePath $monitorScript -Encoding UTF8

    # Try to create a scheduled task (requires Admin)
    $taskName = "ShopLock-NetworkMonitor"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$monitorScript`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 6) -RepetitionDuration (New-TimeSpan -Days 365)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force -ErrorAction Stop | Out-Null
        Write-Host "[+] Monitor scheduled task installed: $taskName" -ForegroundColor Green
        Write-Host "    It will run every 6 hours and write to the alerts folder." -ForegroundColor Gray
    } catch {
        Write-Host "[!] Could not create scheduled task (need to run as Administrator)." -ForegroundColor Red
        Write-Host "    Monitor script was still created at:" -ForegroundColor Yellow
        Write-Host "    $monitorScript" -ForegroundColor White
        Write-Host "    You can run it manually or create the task yourself later." -ForegroundColor Gray
    }
}

function Show-Menu {
    Show-Header
    Write-Host "1. Scan network & generate report"
    Write-Host "2. Show lockdown checklist"
    Write-Host "3. Install quiet monitor (every 6 hours)"
    Write-Host "4. Full job (scan + checklist + optional monitor)"
    Write-Host "5. Exit"
    Write-Host ""
    $choice = Read-Host "Select option (1-5)"
    return $choice
}

# ========== MAIN ==========
Show-Header

$netInfo = Get-LocalNetworkInfo
if (-not $netInfo) {
    Write-Host "[!] Could not detect a usable local network adapter." -ForegroundColor Red
    Write-Host "    Make sure you are connected to the shop WiFi or Ethernet." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

$choice = Show-Menu

switch ($choice) {
    "1" {
        $devices = Scan-NetworkDevices -NetInfo $netInfo
        if ($devices.Count -eq 0) {
            Write-Host "[!] No devices found. Try running as Administrator or check connection." -ForegroundColor Red
        } else {
            Write-Host ""
            Write-Host "Found $($devices.Count) device(s):" -ForegroundColor Green
            $devices | Format-Table -AutoSize
            Save-Report -Devices $devices -NetInfo $netInfo | Out-Null
        }
        Write-Host ""
        Read-Host "Press Enter to return to menu / exit"
    }
    "2" {
        Show-LockdownChecklist
        Read-Host "Press Enter to exit"
    }
    "3" {
        Install-Monitor
        Read-Host "Press Enter to exit"
    }
    "4" {
        $devices = Scan-NetworkDevices -NetInfo $netInfo
        if ($devices.Count -gt 0) {
            $devices | Format-Table -AutoSize
            Save-Report -Devices $devices -NetInfo $netInfo | Out-Null
        }
        Show-LockdownChecklist
        Write-Host ""
        $install = Read-Host "Install the quiet monitor now? (y/n)"
        if ($install -match '^[Yy]') {
            Install-Monitor
        }
        Write-Host ""
        Write-Host "Full job complete. Leave the report with the owner." -ForegroundColor Green
        Read-Host "Press Enter to exit"
    }
    default {
        Write-Host "Exiting..."
    }
}

Write-Host ""
Write-Host "ShopLock-Pro finished." -ForegroundColor Cyan
