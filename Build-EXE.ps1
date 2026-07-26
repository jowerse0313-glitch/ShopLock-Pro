# Build-EXE.ps1
# Creates ShopLock.exe and optionally code-signs it if a certificate is available
# Run on Windows with PowerShell 5.1+

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ShopLock EXE Builder + Signer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1File   = Join-Path $scriptDir "ShopLock.ps1"
$exeFile   = Join-Path $scriptDir "ShopLock.exe"

# ----- 1. Check source -----
if (-not (Test-Path $ps1File)) {
    Write-Host "ERROR: ShopLock.ps1 not found." -ForegroundColor Red
    exit 1
}

# ----- 2. Install PS2EXE if needed -----
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing PS2EXE module (one-time)..." -ForegroundColor Yellow
    try {
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    } catch {
        Write-Host "Failed to install PS2EXE. Run PowerShell as Administrator and try again." -ForegroundColor Red
        exit 1
    }
}

# ----- 3. Compile -----
Write-Host "Compiling ShopLock.ps1 → ShopLock.exe ..." -ForegroundColor Yellow

Invoke-ps2exe `
    -inputFile   $ps1File `
    -outputFile  $exeFile `
    -title       "ShopLock by Raymond" `
    -description "Network & POS lockdown toolkit for coffee shops" `
    -company     "ShopLock by Raymond" `
    -product     "ShopLock-Pro" `
    -version     "1.0.0" `
    -noConsole   $false

if (-not (Test-Path $exeFile)) {
    Write-Host "Compilation failed." -ForegroundColor Red
    exit 1
}

$sizeKB = [math]::Round((Get-Item $exeFile).Length / 1KB, 1)
Write-Host "[OK] Created: $exeFile  ($sizeKB KB)" -ForegroundColor Green
Write-Host ""

# ----- 4. Try to code-sign -----
Write-Host "Looking for code-signing certificate and signtool..." -ForegroundColor Yellow

# Find signtool.exe (Windows SDK)
$signtool = $null
$possiblePaths = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe",
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x86\signtool.exe",
    "${env:ProgramFiles}\Windows Kits\10\bin\*\x64\signtool.exe"
)

foreach ($pattern in $possiblePaths) {
    $found = Get-Item $pattern -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    if ($found) {
        $signtool = $found.FullName
        break
    }
}

if (-not $signtool) {
    # Try PATH
    $signtool = (Get-Command signtool.exe -ErrorAction SilentlyContinue).Source
}

if (-not $signtool) {
    Write-Host "[SKIP] signtool.exe not found." -ForegroundColor DarkYellow
    Write-Host "       Install the Windows SDK (or just the Signing Tools) if you want automatic signing." -ForegroundColor DarkYellow
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
    "http://timestamp.sectigo.com",
    "http://timestamp.digicert.com",
    "http://timestamp.globalsign.com/tsa/r6advanced1"
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
