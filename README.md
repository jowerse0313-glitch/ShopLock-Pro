# ShopLock Portable Toolkit - Pure PowerShell (no Python needed)
# Double-click Run-ShopLock.bat or run this script directly

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'shoplock.config.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "ShopLock Toolkit"

$script:Version = '1.2.0'

# ===== CONFIG =====
$config = @{
    YourName       = "Raymond"
    BusinessName   = "ShopLock by Raymond"
    ReportEmail    = "raymondrayray777@gmail.com"
    SetupFee       = 249
    MonthlyPrice   = 79
    CustomerName   = "Customer Site"
    SiteName       = "Default Site"
    KnownDevices   = @(
        "00:11:22:33:44:55",
        "00:AA:BB:CC:DD:EE"
    )
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

function Write-Log {
    param([string]$Message)
    $logPath = Join-Path $logsDir ("shoplock_{0}.log" -f (Get-Date -Format "yyyyMMdd"))
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}

function Ensure-Config {
    param([string]$ConfigFile)

    if (-not (Test-Path $ConfigFile)) {
        $json = $config | ConvertTo-Json -Depth 5
        $json | Out-File -FilePath $ConfigFile -Encoding utf8
        Write-Log "Created default config at $ConfigFile"
    }
}

function Load-Config {
    param([string]$ConfigFile)

    Ensure-Config -ConfigFile $ConfigFile
    $loaded = Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json

    foreach ($key in $loaded.PSObject.Properties.Name) {
        if ($config.ContainsKey($key)) {
            $config[$key] = $loaded.$key
        } else {
            $config[$key] = $loaded.$key
        }
    }

    if ($loaded.PSObject.Properties.Name -contains 'KnownDevices') {
        $config.KnownDevices = @($loaded.KnownDevices)
    }

    return $config
}

function Normalize-Mac {
    param([string]$Mac)

    if ([string]::IsNullOrWhiteSpace($Mac)) { return $null }

    $normalized = $Mac.Trim().ToLower()
    $normalized = $normalized -replace '-', ':'
    $normalized = $normalized -replace '\s+', ''

    if ($normalized -match '^(?:[0-9a-f]{2}:){5}[0-9a-f]{2}$') {
        return $normalized
    }

    return $null
}

function Get-Classification {
    param([string]$Mac)

    $known = @($config.KnownDevices | ForEach-Object { Normalize-Mac -Mac $_ })
    if ($known -contains $Mac) {
        return 'Known Good'
    }

    if ($Mac -match '^00:00:00:00:00:00$') {
        return 'Unknown / Incomplete'
    }

    return 'Unknown'
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
    if ($parts.Count -ne 2) { return @() }

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

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "  $($config.BusinessName)" -ForegroundColor Cyan
    Write-Host "  Operator: $($config.YourName)" -ForegroundColor Cyan
    Write-Host "  Site: $($config.SiteName)" -ForegroundColor Cyan
    Write-Host "  Version: $script:Version" -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "  Only run this on networks you have permission to secure." -ForegroundColor Yellow
    Write-Host ""
}

function Get-NetworkDevices {
    $devicesByMac = @{}
    $scanSources = @{
        live = 0
        arp = 0
        ping = 0
    }

    function Add-Device {
        param(
            [string]$Ip,
            [string]$Mac,
            [string]$Type = 'Unknown',
            [string]$Source = 'unknown'
        )

        if ([string]::IsNullOrWhiteSpace($Ip) -or [string]::IsNullOrWhiteSpace($Mac)) { return }

        $normalizedIp = $Ip.Trim()
        $normalizedMac = Normalize-Mac -Mac $Mac

        if ($normalizedMac -eq $null) { return }
        if ($normalizedIp -notmatch '^\d+\.\d+\.\d+\.\d+$') { return }
        if (-not (Test-IsPrivateIPv4 -Ip $normalizedIp)) { return }
        if ($normalizedMac -match '^(00:00:00:00:00:00|ff:ff:ff:ff:ff:ff|33:33:33:33:33:33|44:44:44:44:44:44|ac:de:48:00:00:00)$') { return }

        if (-not $devicesByMac.ContainsKey($normalizedMac)) {
            $classification = Get-Classification -Mac $normalizedMac
            $devicesByMac[$normalizedMac] = [PSCustomObject]@{
                IP          = $normalizedIp
                MAC         = $normalizedMac
                Type        = $Type
                Source      = $Source
                Confidence  = if ($Source -eq 'live') { 'High' } elseif ($Source -eq 'arp') { 'Medium' } elseif ($Source -eq 'ping') { 'Low' } else { 'Unknown' }
                Classification = $classification
                FirstSeen   = (Get-Date).ToString('o')
            }
        }
    }

    try {
        $neighborTable = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction Stop
        foreach ($entry in $neighborTable) {
            if (-not $entry.IPAddress) { continue }
            $mac = Normalize-Mac -Mac $entry.LinkLayerAddress
            if (-not $mac) { continue }
            if ($entry.State -notmatch 'Reachable|Stale|Delay|Probe') { continue }
            Add-Device -Ip $entry.IPAddress -Mac $mac -Type $entry.State -Source 'live'
            $scanSources.live += 1
        }
    } catch {
        # fallback to ARP below
    }

    try {
        $arpOutput = arp -a 2>$null
        foreach ($line in $arpOutput) {
            if ($line -match '(\d+\.\d+\.\d+\.\d+)\s+([0-9a-fA-F-]{17})\s+(\w+)') {
                $ip  = $matches[1]
                $mac = Normalize-Mac -Mac $matches[2]
                $type = $matches[3]
                if ($null -ne $mac) {
                    Add-Device -Ip $ip -Mac $mac -Type $type -Source 'arp'
                    $scanSources.arp += 1
                }
            }
        }
    } catch {
        # ignore
    }

    if ($devicesByMac.Count -gt 0) {
        $result = @($devicesByMac.Values | Sort-Object IP)
        $result | Add-Member -NotePropertyName ScanSourceSummary -NotePropertyValue $scanSources -Force
        return $result
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
                        $mac = Normalize-Mac -Mac $Matches[0]
                        break
                    }
                }
                if ($null -ne $mac) {
                    Add-Device -Ip $ip -Mac $mac -Type 'Pinged' -Source 'ping'
                    $scanSources.ping += 1
                }
            }
        } catch {
            # skip unreachable hosts
        }
    }

    $result = @($devicesByMac.Values | Sort-Object IP)
    $result | Add-Member -NotePropertyName ScanSourceSummary -NotePropertyValue $scanSources -Force
    return $result
}

function Save-Report {
    param($devices)

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $txtFile   = Join-Path $reportsDir "scan_$timestamp.txt"
    $jsonFile  = Join-Path $reportsDir "scan_$timestamp.json"

    $summary = @{
        timestamp = (Get-Date).ToString('o')
        site = $config.SiteName
        customer = $config.CustomerName
        totalDevices = $devices.Count
        highConfidence = @($devices | Where-Object { $_.Confidence -eq 'High' }).Count
        mediumConfidence = @($devices | Where-Object { $_.Confidence -eq 'Medium' }).Count
        lowConfidence = @($devices | Where-Object { $_.Confidence -eq 'Low' }).Count
        unknownCount = @($devices | Where-Object { $_.Classification -eq 'Unknown' }).Count
        knownCount = @($devices | Where-Object { $_.Classification -eq 'Known Good' }).Count
    }

    $reportText = @"
ShopLock Network Security Report
Customer: $($config.CustomerName)
Site: $($config.SiteName)
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm")
==================================================

Total devices found: $($devices.Count)
Known Good: $($summary.knownCount)
Unknown: $($summary.unknownCount)
High confidence: $($summary.highConfidence)
Medium confidence: $($summary.mediumConfidence)
Low confidence: $($summary.lowConfidence)

"@

    $i = 1
    foreach ($d in $devices) {
        $reportText += "{0,2}. IP: {1,-16}  MAC: {2,-18}  Type: {3}  Confidence: {4}  Class: {5}`n" -f $i, $d.IP, $d.MAC, $d.Type, $d.Confidence, $d.Classification
        $i++
    }

    $reportText += @"

==================================================
Recommended actions:
1. Review all unknown devices
2. Remove or restrict any unapproved access points or wireless devices
3. Lock the router to allowlist-only MAC access if supported
4. Confirm POS and business devices are the only approved endpoints
5. Collect setup fee (`$$($config.SetupFee)`) and start monthly (`$$($config.MonthlyPrice)`)
"@

    $reportText | Out-File -FilePath $txtFile -Encoding utf8

    $jsonObj = @{
        timestamp = (Get-Date).ToString("o")
        customer = $config.CustomerName
        site = $config.SiteName
        summary = $summary
        devices = @($devices)
    }
    $jsonObj | ConvertTo-Json -Depth 8 | Out-File -FilePath $jsonFile -Encoding utf8

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

function Export-CustomerSummary {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $summaryPath = Join-Path $reportsDir ("customer-summary_$timestamp.txt")

    $summary = @"
ShopLock Customer Summary
Customer: $($config.CustomerName)
Site: $($config.SiteName)
Operator: $($config.YourName)
Contact: $($config.ReportEmail)
Version: $script:Version

Approved / Known devices:
$(@($config.KnownDevices) -join ", ")

Recommended next steps:
- Confirm every device on the network is approved
- Restrict guest WiFi to guest network only
- Block unknown MACs or isolate them
- Maintain the 6-hour monitoring task
"@

    $summary | Out-File -FilePath $summaryPath -Encoding utf8
    Write-Host "[OK] Customer summary exported: $summaryPath" -ForegroundColor Green
    return $summaryPath
}

function Show-DeploymentSettings {
    Write-Host ""
    Write-Host "=== ShopLock Deployment Settings ===" -ForegroundColor Cyan
    Write-Host "Config file: $ConfigPath" -ForegroundColor Gray
    Write-Host "Customer: $($config.CustomerName)" -ForegroundColor White
    Write-Host "Site: $($config.SiteName)" -ForegroundColor White
    Write-Host "Operator: $($config.YourName)" -ForegroundColor White
    Write-Host "Email: $($config.ReportEmail)" -ForegroundColor White
    Write-Host "Setup: $$($config.SetupFee) | Monthly: $$($config.MonthlyPrice)" -ForegroundColor White
    Write-Host "Known devices: $(@($config.KnownDevices).Count)" -ForegroundColor White
    Write-Host ""
    Write-Host "Press Enter to continue..." -NoNewline
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
            Write-Log "Scheduled task installed successfully via Task Scheduler module."
        } else {
            $action = "`"$psPath`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Monitor"
            schtasks /Delete /TN $taskName /F 2>$null | Out-Null
            $result = schtasks /Create /TN $taskName /TR $action /SC HOURLY /MO 6 /F /RL HIGHEST 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Monitor installed successfully." -ForegroundColor Green
                Write-Host "    It will run every 6 hours in the background." -ForegroundColor Green
                Write-Host "    Manage it in Task Scheduler → ShopLockMonitor" -ForegroundColor Green
                Write-Log "Scheduled task installed successfully via schtasks fallback."
            } else {
                Write-Host "[!] Could not create scheduled task." -ForegroundColor Red
                Write-Host "    Try running this tool as Administrator." -ForegroundColor Red
                Write-Host $result -ForegroundColor Red
                Write-Log "Scheduled task installation failed: $result"
            }
        }
    } catch {
        Write-Host "[!] Exception while creating scheduled task." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Log "Scheduled task exception: $($_.Exception.Message)"
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
Customer: $($config.CustomerName)
Site: $($config.SiteName)
Time: $(Get-Date -Format "yyyy-MM-dd HH:mm")
Duration: $((Get-Date) - $start)
Devices found: $($devices.Count)

Full report: $txt

Device list:
"@

    foreach ($d in $devices) {
        $body += "  $($d.IP.PadRight(16))  $($d.MAC)  [$($d.Confidence)]  [$($d.Classification)]`n"
    }

    $body | Out-File -FilePath $alertFile -Encoding utf8
    Write-Log "Monitor run completed with $($devices.Count) device(s)."
    exit 0
}

$config = Load-Config -ConfigFile $ConfigPath

# ===== MAIN =====
if ($args -contains "-Monitor") {
    Run-MonitorMode
}

Show-Banner
Write-Log "ShopLock version $script:Version started in interactive mode."

do {
    Write-Host "What do you want to do?"
    Write-Host "  1. Scan network and create report"
    Write-Host "  2. Install ongoing monitor (every 6 hours)"
    Write-Host "  3. Show quick lockdown checklist"
    Write-Host "  4. Show deployment settings"
    Write-Host "  5. Export customer summary"
    Write-Host "  6. Exit"
    Write-Host ""
    $choice = Read-Host "Choose [1-6]"

    switch ($choice) {
        "1" {
            Write-Host ""
            Write-Status "Scanning local network ..." "Yellow"

            $startTime = Get-Date
            $devices = Get-NetworkDevices
            $scanDuration = (Get-Date) - $startTime

            Write-Host ""
            Write-Status "Found $($devices.Count) device(s) in $([math]::Round($scanDuration.TotalSeconds,2))s:" "Green"
            Write-Host ""
            $i = 1
            foreach ($d in $devices) {
                Write-Host ("  {0}. {1,-16}  {2}  [{3}]  [{4}]" -f $i, $d.IP, $d.MAC, $d.Confidence, $d.Classification)
                $i++
            }

            $txtFile, $jsonFile = Save-Report $devices
            Write-Host ""
            Write-Status "[OK] Report saved:" "Green"
            Write-Host "     $txtFile"
            Write-Host ""
            Write-Host "Give the .txt file to the owner or keep it for your records."
            Write-Log "Manual scan completed. File: $txtFile"
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
            Show-DeploymentSettings
            Show-Banner
        }
        "5" {
            Export-CustomerSummary
            Write-Host ""
            Write-Host "Press Enter to continue..." -NoNewline
            Read-Host | Out-Null
            Show-Banner
        }
        "6" {
            Write-Host ""
            Write-Status "Done. Stay safe out there." "Cyan"
            Write-Log "ShopLock closed by user."
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

