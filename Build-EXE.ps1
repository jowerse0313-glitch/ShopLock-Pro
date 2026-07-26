# Build-EXE.ps1 - Run on Windows
Write-Host "ShopLock EXE Builder" -ForegroundColor Cyan
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ps1File = Join-Path $scriptDir "ShopLock.ps1"
$exeFile = Join-Path $scriptDir "ShopLock.exe"
if (-not (Test-Path $ps1File)) { Write-Host "ShopLock.ps1 missing" -ForegroundColor Red; exit 1 }
if (-not (Get-Module -ListAvailable -Name ps2exe)) { Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber }
Write-Host "Compiling..." -ForegroundColor Yellow
Invoke-ps2exe -inputFile $ps1File -outputFile $exeFile -title "ShopLock by Raymond" -description "Network & POS lockdown toolkit" -company "ShopLock by Raymond" -product "ShopLock-Pro" -version "1.0.0"
if (Test-Path $exeFile) { Write-Host "[OK] Created $exeFile" -ForegroundColor Green } else { Write-Host "Failed" -ForegroundColor Red }
