@echo off
title ShopLock Toolkit
cd /d "%~dp0"

:: This launches the PowerShell version with ExecutionPolicy Bypass
:: so it runs on any Windows machine without changing system settings permanently.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ShopLock.ps1"

if errorlevel 1 (
    echo.
    echo Something went wrong. Make sure you are on a Windows computer.
    pause
)
