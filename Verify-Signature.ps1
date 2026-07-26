# Verify-Signature.ps1
# Checks the digital signature of ShopLock.exe (or any file you pass)
# Usage:
#   .\Verify-Signature.ps1
#   .\Verify-Signature.ps1 -Path "C:\path\to\other.exe"

param(
    [string]$Path = ".\ShopLock.exe"
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  ShopLock Signature Verifier" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $Path)) {
    Write-Host "ERROR: File not found → $Path" -ForegroundColor Red
    Write-Host ""
    Write-Host "Usage: .\Verify-Signature.ps1 [-Path path\to\file.exe]" -ForegroundColor Yellow
    exit 1
}

$fullPath = (Resolve-Path $Path).Path
Write-Host "File: $fullPath" -ForegroundColor Gray
Write-Host ""

# ----- 1. PowerShell Authenticode check (primary) -----
Write-Host "1. PowerShell Authenticode Check" -ForegroundColor Yellow
Write-Host "---------------------------------" -ForegroundColor Yellow

$sig = Get-AuthenticodeSignature -FilePath $fullPath

$statusColor = switch ($sig.Status) {
    "Valid"            { "Green" }
    "NotSigned"        { "DarkYellow" }
    "HashMismatch"     { "Red" }
    "NotTrusted"       { "Red" }
    "UnknownError"     { "Red" }
    default            { "Red" }
}

Write-Host ("Status          : {0}" -f $sig.Status) -ForegroundColor $statusColor

if ($sig.SignerCertificate) {
    Write-Host ("Signer          : {0}" -f $sig.SignerCertificate.Subject)
    Write-Host ("Issuer          : {0}" -f $sig.SignerCertificate.Issuer)
    Write-Host ("Valid From      : {0}" -f $sig.SignerCertificate.NotBefore)
    Write-Host ("Valid To        : {0}" -f $sig.SignerCertificate.NotAfter)
    Write-Host ("Thumbprint      : {0}" -f $sig.SignerCertificate.Thumbprint)
} else {
    Write-Host "Signer          : (none)"
}

if ($sig.TimeStamperCertificate) {
    Write-Host ("Timestamped by  : {0}" -f $sig.TimeStamperCertificate.Subject) -ForegroundColor Green
} else {
    Write-Host "Timestamped by  : (no timestamp)" -ForegroundColor DarkYellow
}

Write-Host ""

# ----- 2. SignTool check (if available) -----
Write-Host "2. SignTool Verification" -ForegroundColor Yellow
Write-Host "------------------------" -ForegroundColor Yellow

$signtool = $null
$possible = @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe",
    "${env:ProgramFiles}\Windows Kits\10\bin\*\x64\signtool.exe"
)
foreach ($p in $possible) {
    $found = Get-Item $p -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    if ($found) { $signtool = $found.FullName; break }
}
if (-not $signtool) {
    $signtool = (Get-Command signtool.exe -ErrorAction SilentlyContinue).Source
}

if ($signtool) {
    Write-Host "Using: $signtool" -ForegroundColor Gray
    Write-Host ""
    & $signtool verify /pa /v $fullPath
} else {
    Write-Host "signtool.exe not found (optional). Skipping." -ForegroundColor DarkYellow
}

Write-Host ""

# ----- 3. Final summary -----
Write-Host "========================================" -ForegroundColor Cyan
if ($sig.Status -eq "Valid") {
    Write-Host "RESULT: Signature is VALID" -ForegroundColor Green
} elseif ($sig.Status -eq "NotSigned") {
    Write-Host "RESULT: File is NOT SIGNED" -ForegroundColor DarkYellow
} else {
    Write-Host "RESULT: Signature problem → $($sig.Status)" -ForegroundColor Red
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
