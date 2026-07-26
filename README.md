# ShopLock-Pro

Portable network & POS lockdown toolkit for independent coffee shops.  
No Python needed. Works on almost every Windows PC / POS terminal.

## Quick Start (Script version)

1. Copy the whole folder to a USB stick
2. On the customer's Windows computer open the USB
3. Double-click `Run-ShopLock.bat`
4. Follow the menu

## Create a single EXE (recommended)

On any Windows machine with PowerShell:

```powershell
.\Build-EXE.ps1
```

This will:
1. Install PS2EXE if needed
2. Compile `ShopLock.ps1` into `ShopLock.exe`
3. **Automatically code-sign** the EXE if a certificate is present and `signtool.exe` is available

### About code signing
- If you have a code-signing certificate installed (or a USB token plugged in), the builder will sign the EXE with SHA256 + timestamp.
- If no certificate is found, it simply skips signing and gives you a working unsigned EXE.
- Once you buy a certificate later, just re-run `.\Build-EXE.ps1` and it will sign automatically.

## What it does

- Scans every device currently on the network (via ARP)
- Saves clean `.txt` + `.json` reports
- Installs a quiet background monitor (every 6 hours)
- Shows the exact lockdown checklist

## Important

- Only use on networks where the business owner has given permission
- Never store router passwords inside the tool
- Run as Administrator if you want the monitor task to install cleanly

## Files

- `Run-ShopLock.bat` – launcher for the .ps1 version
- `ShopLock.ps1` – the main script
- `Build-EXE.ps1` – creates + optionally signs the single .exe
- `PITCH.txt` – sales pitch
- `reports/` and `alerts/` – created automatically at runtime

---

**ShopLock by Raymond**  
Setup: $249 | Monthly: $79  
Email: raymondrayray777@gmail.com
