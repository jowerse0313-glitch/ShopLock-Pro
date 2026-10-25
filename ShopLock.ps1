# ShopLock Portable Toolkit - Pure PowerShell (no Python needed)
# Double-click Run-ShopLock.bat or run this script directly

$ErrorActionPreference = "Stop"
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
$logsDir    = Join-Path $scriptDir "logs"

foreach ($dir in @($reportsDir, $alertsDir, $logsDir)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

function Write-Status {
    param(
        [string]$Message,
        [string]$Color = 'White'
    )
    Write-Host $Message -ForegroundColor $Color
}

function Get-ScanLogPath {
    return Join-Path $logsDir ("scan_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
}

function Write-ScanLog {
    param([string]$Message)
    $path = Get-ScanLogPath
    Add-Content -Path $path -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message) -Encoding UTF8
    return $path
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

function Test-IsPrivateIPv4 {
    param([string]$Ip)

    if ($Ip -notmatch '^\d+\.\d+\.\d+\.\d+$') { return $false }

    $octets = $Ip.Split('.') | ForEach-Object { [int]$_ }
    $first = $octets[0]
    $second = $octets[1]

    if ($first -eq 10) { return $true }
    if ($first -eq 172 -and $second -ge 16 -and $second -le 31) { return $true }
    if ($first -eq 192 -and $second -eq 168) { return $true }
    return $false
}

function Get-LocalSubnetCandidates {
    $candidates = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    try {
        $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop
        foreach ($ip in $ips) {
            if (-not $ip.IPv4Address) { continue }
            if ($ip.IPv4Address -match '127\.0\.0\.1') { continue }
            if ($ip.IPv4Address -match '^169\.254\.') { continue }

            $prefixLength = $ip.PrefixLength
            if ($prefixLength -notin 8,16,20,24,28,30) { continue }

            $octets = $ip.IPv4Address.Split('.')
            $first = [int]$octets[0]
            $second = [int]$octets[1]
            $third = [int]$octets[2]

            if ($prefixLength -ge 24) {
                $network = "$first.$second.$third.0/24"
            } elseif ($prefixLength -ge 20) {
                $network = "$first.$second.0.0/16"
            } else {
                $network = "$first.0.0.0/8"
            }

            if ($network -notmatch '^169\.254\.') {
                [void]$candidates.Add($network)
            }
        }
    } catch {
        # fallback below
    }

    if ($candidates.Count -eq 0) {
        foreach ($range in @('192.168.0.0/24', '192.168.1.0/24', '192.168.2.0/24', '10.0.0.0/24', '10.0.1.0/24', '172.16.0.0/20')) {
            [void]$candidates.Add($range)
        }
    }

    return @($candidates)
}

function Get-SubnetHosts {
    param([string]$Cidr)

    $parts = $Cidr.Split('/')
    $network = $parts[0]
    $maskBits = [int]$parts[1]

    if ($network -notmatch '^\d+\.\d+\.\d+\.\d+$') { return @() }
    if ($maskBits -notin 8,16,20,24) { return @() }

    $octets = $network.Split('.') | ForEach-Object { [int]$_ }
    $addresses = New-Object 'System.Collections.Generic.List[string]'

    foreach ($host in 1..254) {
        $ip = "$($octets[0]).$($octets[1]).$($octets[2]).$host"
        $addresses.Add($ip)
    }

    return @($addresses)
}

function Get-NetworkDevices {
    $devicesByMac = @{}

    function Add-Device {
        param(
            [string]$Ip,
            [string]$Mac,
            [string]$Type = 'Unknown'
        )

        if ([string]::IsNullOrWhiteSpace($Ip) -or [string]::IsNullOrWhiteSpace($Mac)) { return }

        $normalizedIp = $Ip.Trim()
        $normalizedMac = $Mac.Trim().ToLower()

        if ($normalizedIp -notmatch '^\d+\.\d+\.\d+\.\d+$') { return }
        if (-not (Test-IsPrivateIPv4 -Ip $normalizedIp)) { return }
        if ($normalizedMac -match '^(00:00:00:00:00:00|ff:ff:ff:ff:ff:ff|33:33:33:33:33:33|44:44:44:44:44:44|ac:de:48:00:00:00)$') { return }

        if (-not $devicesByMac.ContainsKey($normalizedMac)) {
            $devicesByMac[$normalizedMac] = [PSCustomObject]@{
                IP   = $normalizedIp
                MAC  = $normalizedMac
                Type = $Type
            }
        }
    }

    try {
        $neighborTable = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop
        foreach ($entry in $neighborTable) {
            if (-not $entry.IPAddress) { continue }
            if (-not $entry.LinkLayerAddress) { continue }
            if ($entry.State -notmatch 'Reachable|Stale|Delay|Probe') { continue }
            Add-Device -Ip $entry.IPAddress -Mac $entry.LinkLayerAddress -Type $entry.State
        }
    } catch {
        # fallback to ARP below
    }

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
        # ignore
    }

    if ($devicesByMac.Count -gt 0) {
        return @($devicesByMac.Values | Sort-Object IP)
    }

    $scanList = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($range in Get-LocalSubnetCandidates) {
        foreach ($ip in Get-SubnetHosts -Cidr $range) {
            [void]$scanList.Add($ip)
        }
    }

    foreach ($ip in $scanList) {
        try {
            if (Test-Connection -ComputerName $ip -Count 1 -Quiet -TimeoutSeconds 0.4) {
                $arpEntry = arp -a $ip 2>$null
                $mac = $null
                foreach ($line in $arpEntry) {
                    if ($line -match '\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b') {
                        $mac = ($Matches[0] -replace '-', ':').ToLower()
                        break
                    }
                }
                if (-not $mac) { $mac = '00:00:00:00:00:00' }
                Add-Device -Ip $ip -Mac $mac -Type 'Pinged'
            }
        } catch {
            # skip unreachable hosts
        }
    }

    return @($devicesByMac.Values | Sort-Object IP)
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
        devices      = @($devices)
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
    $start = Get-Date
    $devices = Get-NetworkDevices
    $txt, $json = Save-Report $devices

    $alertFile = Join-Path $alertsDir ("alert_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $body = @"
ShopLock Monitor Report
Time: $(Get-Date -Format "yyyy-MM-dd HH:mm")
Duration: $((Get-Date) - $start)
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

