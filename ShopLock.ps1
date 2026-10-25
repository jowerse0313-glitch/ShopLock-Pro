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

if (-not (Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null }
if (-not (Test-Path $alertsDir))  { New-Item -ItemType Directory -Path $alertsDir  -Force | Out-Null }

function Write-Status {
    param(
        [string]$Message,
        [string]$Color = 'White'
    )
    Write-Host $Message -ForegroundColor $Color
}

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
    $devicesByMac = @{}

    function Add-Device {
        param(
            [string]$Ip,
            [string]$Mac,
            [string]$Type = 'Unknown'
        )

        if ([string]::IsNullOrWhiteSpace($Ip) -or [string]::IsNullOrWhiteSpace($Mac)) {
            return
        }

        $normalizedIp = $Ip.Trim()
        $normalizedMac = $Mac.Trim().ToLower()

        if ($normalizedIp -notmatch '^\d+\.\d+\.\d+\.\d+$') {
            return
        }

        if ($normalizedMac -match '^(00:00:00:00:00:00|ff:ff:ff:ff:ff:ff|33:33:33:33:33:33|44:44:44:44:44:44|ac:de:48:00:00:00)$') {
            return
        }

        if (-not $devicesByMac.ContainsKey($normalizedMac)) {
            $devicesByMac[$normalizedMac] = [PSCustomObject]@{
                IP   = $normalizedIp
                MAC  = $normalizedMac
                Type = $Type
            }
        }
    }

    # Prefer the OS ARP table; it is more reliable on real customer networks than a single stale cache.
    try {
        $netNeighbor = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop
        foreach ($entry in $netNeighbor) {
            if (-not $entry.IPAddress) { continue }
            if (-not $entry.LinkLayerAddress) { continue }
            if ($entry.State -notmatch 'Reachable|Stale|Delay|Probe') { continue }
            Add-Device -Ip $entry.IPAddress -Mac $entry.LinkLayerAddress -Type $entry.State
        }
    } catch {
        # Ignore and fall back to the classic ARP output below.
    }

    # Fall back to the classic `arp -a` output for older or locked-down Windows installs.
    try {
        $arpOutput = arp -a 2>$null
        foreach ($line in $arpOutput) {
            if ($line -match '(\d+\.\d+\.\d+\.\d+)\s+([0-9a-fA-F-]{17})\s+(\w+)') {
                $ip  = $matches[1]
                $mac = ($matches[2] -replace '-', ':').ToLower()
                $type = $matches[3]
                Add-Device -Ip $ip -Mac $mac -Type $type
            }
        }
    } catch {
        # no-op
    }

    # Some customer networks do not populate ARP immediately. Run a very small ping sweep on common LAN subnets
    # only when ARP does not show anything useful. This keeps it fast and avoids scanning random Internet ranges.
    if ($devicesByMac.Count -eq 0) {
        $commonRanges = @(
            '192.168.0.0/24',
            '192.168.1.0/24',
            '192.168.2.0/24',
            '10.0.0.0/24',
            '10.0.1.0/24',
            '172.16.0.0/20'
        )

        foreach ($cidr in $commonRanges) {
            $networkParts = $cidr.Split('/')
            $baseIp = $networkParts[0]
            $maskBits = [int]$networkParts[1]

            if ($baseIp -notmatch '^\d+\.\d+\.\d+\.\d+$') { continue }
            if ($maskBits -ne 24 -and $maskBits -ne 20) { continue }

            $octets = $baseIp.Split('.')
            $networkBase = [int]$octets[0..2] -join '.'
            $scanMax = 254

            foreach ($host in 1..$scanMax) {
                $candidate = "$($octets[0]).$($octets[1]).$($octets[2]).$host"
                if ($candidate -like '*.0' -or $candidate -like '*.255') { continue }

                try {
                    if (Test-Connection -ComputerName $candidate -Count 1 -Quiet -TimeoutSeconds 0.35) {
                        Add-Device -Ip $candidate -Mac "00:00:00:00:00:00" -Type 'Pinged'
                    }
                } catch {
                    # ignore unreachable hosts
                }
            }
        }
    }

    $result = @($devicesByMac.Values | Sort-Object IP)
    return $result
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
    Write-Host "Installing ShopLock monitor (runs every 6 hours) ..." -ForegroundColor Yellow

    $taskName = "ShopLockMonitor"
    $psPath   = (Get-Command powershell.exe).Source
    $script   = Join-Path $scriptDir "ShopLock.ps1"

    try {
        if (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue) {
            $action = New-ScheduledTaskAction -Execute $psPath -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Monitor"
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 6) -RepetitionDuration ([TimeSpan]::MaxValue)
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Highest
            $task = New-ScheduledTask -Action $action -Principal $principal -Trigger $trigger -Description "ShopLock network monitor"
            Unregister-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null

            Write-Host "[OK] Monitor installed successfully." -ForegroundColor Green
            Write-Host "    It will run every 6 hours in the background." -ForegroundColor Green
            Write-Host "    Manage it in Task Scheduler → ShopLockMonitor" -ForegroundColor Green
        } else {
            $action = "`"$psPath`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Monitor"
            schtasks /Delete /TN $taskName /F 2>$null | Out-Null
            $result = schtasks /Create /TN $taskName /TR $action /SC HOURLY /MO 6 /F /RL HIGHEST 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Monitor installed successfully." -ForegroundColor Green
                Write-Host "    It will run every 6 hours in the background." -ForegroundColor Green
                Write-Host "    Manage it in Task Scheduler → ShopLockMonitor" -ForegroundColor Green
            } else {
                Write-Host "[!] Could not create scheduled task." -ForegroundColor Red
                Write-Host "    Try running this tool as Administrator." -ForegroundColor Red
                Write-Host $result -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "[!] Exception while creating scheduled task." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
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
    exit 0
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
            Write-Status "Scanning local network ..." "Yellow"
            $devices = Get-NetworkDevices
            Write-Host ""
            Write-Status "Found $($devices.Count) device(s):" "Green"
            Write-Host ""
            $i = 1
            foreach ($d in $devices) {
                Write-Host ("  {0}. {1,-16}  {2}" -f $i, $d.IP, $d.MAC)
                $i++
            }
            $txtFile, $jsonFile = Save-Report $devices
            Write-Host ""
            Write-Status "[OK] Report saved:" "Green"
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
            Write-Status "Done. Stay safe out there." "Cyan"
            Write-Host ""
            break
        }
        default {
            Write-Status "Invalid choice." "Red"
            Start-Sleep -Seconds 1
            Show-Banner
        }
    }
} while ($true)

