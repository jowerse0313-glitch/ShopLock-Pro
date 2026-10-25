# Build-EXE.ps1
# Creates ShopLock.exe and optionally code-signs it if a certificate is available
# Run on Windows with PowerShell 5.1+ (PowerShell 7 is supported if PS2EXE loads cleanly)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ShopLock EXE Builder + Signer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1File   = Join-Path $scriptDir "ShopLock.ps1"
$exeFile   = Join-Path $scriptDir "ShopLock.exe"

# ----- 1. Platform check -----
if (-not ($IsWindows -or ($env:OS -match 'Windows'))) {
    Write-Host "ERROR: This build script must run on Windows." -ForegroundColor Red
    exit 1
}

# ----- 2. Check source -----
if (-not (Test-Path $ps1File)) {
    Write-Host "ERROR: ShopLock.ps1 not found." -ForegroundColor Red
    exit 1
}

# ----- 3. Ensure PowerShell version is usable -----
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "ERROR: PowerShell 5.1 or newer is required." -ForegroundColor Red
    exit 1
}

# ----- 4. Install PS2EXE if needed -----
$ps2exeModule = Get-Module -ListAvailable -Name ps2exe | Sort-Object Version -Descending | Select-Object -First 1
if (-not $ps2exeModule) {
    Write-Host "Installing PS2EXE module (one-time) ..." -ForegroundColor Yellow
    try {
        if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
            Register-PSRepository -Default -ErrorAction SilentlyContinue
        }
        Install-Module -Name ps2exe -Scope CurrentUser -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
    } catch {
        Write-Host "Failed to install PS2EXE. Run PowerShell as Administrator and try again." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
}

Import-Module ps2exe -Force -ErrorAction Stop
if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: The ps2exe command was not loaded correctly." -ForegroundColor Red
    exit 1
}

# ----- 5. Compile -----
Write-Host "Compiling ShopLock.ps1 → ShopLock.exe ..." -ForegroundColor Yellow

try {
    Invoke-ps2exe `
        -inputFile   $ps1File `
        -outputFile  $exeFile `
        -title       "ShopLock by Raymond" `
        -description "Network & POS lockdown toolkit for coffee shops" `
        -company     "ShopLock by Raymond" `
        -product     "ShopLock-Pro" `
        -version     "1.0.0" `
        -noConsole   $false
} catch {
    Write-Host "Compilation failed. Please verify that the ps2exe module loads correctly." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $exeFile)) {
    Write-Host "Compilation failed." -ForegroundColor Red
    exit 1
}

$sizeKB = [math]::Round((Get-Item $exeFile).Length / 1KB, 1)
Write-Host "[OK] Created: $exeFile  ($sizeKB KB)" -ForegroundColor Green
Write-Host ""

# ----- 6. Try to code-sign -----
Write-Host "Looking for code-signing certificate and signtool..." -ForegroundColor Yellow

# Find signtool.exe (Windows SDK)
$signtool = $null
$possiblePaths = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe",
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x86\signtool.exe",
    "${env:ProgramFiles}\Windows Kits\10\bin\*\x64\signtool.exe",
    "${env:ProgramFiles}\Windows Kits\10\bin\*\x86\signtool.exe"
)

foreach ($pattern in $possiblePaths) {
    $found = Get-Item $pattern -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    if ($found) {
        $signtool = $found.FullName
        break
    }
}

if (-not $signtool) {
    $signtool = (Get-Command signtool.exe -ErrorAction SilentlyContinue).Source
}

if (-not $signtool) {
    Write-Host "[SKIP] signtool.exe not found." -ForegroundColor DarkYellow
    Write-Host "       Install the Windows SDK (or the Signing Tools) if you want automatic signing." -ForegroundColor DarkYellow
    Write-Host "       EXE is ready but unsigned." -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "Done." -ForegroundColor Cyan
    exit 0
}

Write-Host "Found signtool: $signtool" -ForegroundColor Gray

# Check for a usable code-signing certificate
$certs = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue
if (-not $certs) {
    $certs = Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue
}

if (-not $certs -or $certs.Count -eq 0) {
    Write-Host "[SKIP] No code-signing certificate found in the certificate store." -ForegroundColor DarkYellow
    Write-Host "       Once you buy a certificate and install it (or plug in the USB token)," -ForegroundColor DarkYellow
    Write-Host "       re-run this script and it will sign automatically." -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "Done. EXE is ready but unsigned." -ForegroundColor Cyan
    exit 0
}

Write-Host "Found $($certs.Count) code-signing certificate(s). Signing..." -ForegroundColor Yellow

# Preferred timestamp servers (Sectigo / DigiCert / others)
$timestampServers = @(
    "https://timestamp.sectigo.com",
    "https://timestamp.digicert.com",
    "https://timestamp.globalsign.com/tsa/r6advanced1"
)

$signed = $false
foreach ($ts in $timestampServers) {
    try {
        & $signtool sign /fd SHA256 /tr $ts /td SHA256 /a /v $exeFile 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $signed = $true
            Write-Host "[OK] Successfully signed with timestamp: $ts" -ForegroundColor Green
            break
        }
    } catch {
        # try next server
    }
}

if (-not $signed) {
    # Fallback without timestamp
    Write-Host "Timestamp servers failed — trying signature without timestamp..." -ForegroundColor DarkYellow
    & $signtool sign /fd SHA256 /a /v $exeFile 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Signed (no timestamp)." -ForegroundColor Green
        Write-Host "     Note: Signature will become invalid when the certificate expires." -ForegroundColor DarkYellow
        $signed = $true
    }
}

if ($signed) {
    Write-Host ""
    Write-Host "Verifying signature..." -ForegroundColor Gray
    & $signtool verify /pa /v $exeFile
    Write-Host ""
    Write-Host "ShopLock.exe is now signed and ready for distribution." -ForegroundColor Green
} else {
    Write-Host "[FAIL] Could not sign the EXE." -ForegroundColor Red
    Write-Host "       Check that your certificate is valid and the private key is accessible." -ForegroundColor Red
}

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

# README.md
# ShopLock-Pro

Portable network & POS lockdown toolkit for independent coffee shops.
No Python needed. Works on almost every Windows PC / POS terminal.

## Quick Start (Script version)

1. Copy the whole folder to a USB stick
2. On the customer's Windows computer open the USB
3. Double-click `Run-ShopLock.bat`
4. Follow the menu

## Build a single EXE (recommended)

On any Windows machine with PowerShell 5.1+:

```powershell
.\Build-EXE.ps1
```

This will:
1. Install PS2EXE if needed
2. Compile `ShopLock.ps1` into `ShopLock.exe`
3. Auto-sign the EXE if a valid code-signing certificate and `signtool.exe` are available

### About code signing
- If you have a code-signing certificate installed (or a USB token plugged in), the builder will sign the EXE with SHA256 + timestamp.
- If no certificate is found, it simply skips signing and gives you a working unsigned EXE.
- Once you buy a certificate later, just re-run `./Build-EXE.ps1` and it will sign automatically.

## Verify a signature

After building (or on any machine), run:

```powershell
.\Verify-Signature.ps1
```

Or check a specific file:

```powershell
.\Verify-Signature.ps1 -Path "C:\path\to\ShopLock.exe"
```

It shows:
- Authenticode status (Valid / NotSigned / etc.)
- Signer name and certificate details
- Whether a timestamp is present
- Optional SignTool verification

## What it does

- Scans every device currently on the network (via ARP)
- Saves clean `.txt` + `.json` reports
- Installs a quiet background monitor (every 6 hours)
- Shows the exact lockdown checklist

## Important

- Only use on networks where the business owner has given permission
- Never store router passwords inside the tool
- Run as Administrator if you want the monitor task to install cleanly
- This project is designed for Windows systems and requires PowerShell 5.1 or newer

## Files

- `Run-ShopLock.bat` – launcher for the .ps1 version
- `ShopLock.ps1` – the main script
- `Build-EXE.ps1` – creates + optionally signs the single .exe
- `Verify-Signature.ps1` – checks digital signature of the EXE
- `PITCH.txt` – sales pitch
- `reports/` and `alerts/` – created automatically at runtime

---

**ShopLock by Raymond**
Setup: $249 | Monthly: $79
Email: raymondrayray777@gmail.com

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""