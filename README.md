# ShopLock-Pro

Portable network & POS lockdown toolkit for independent coffee shops.  
No Python needed. Works on almost every Windows PC / POS terminal.

## Quick Start (Script version)

1. Copy the whole folder to a USB stick
2. On the customer's Windows computer open the USB
3. Double-click `Run-ShopLock.bat`
4. Follow the menu

## Create a single EXE (recommended for distribution)

On any Windows machine with PowerShell:

1. Open PowerShell in the ShopLock-Pro folder
2. Run:
   ```
   .\Build-EXE.ps1
   ```
3. It will install the PS2EXE module (one time) and create `ShopLock.exe`

You can then put just `ShopLock.exe` on a USB stick.  
When it runs it will automatically create the `reports` and `alerts` folders next to itself.

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
- `Build-EXE.ps1` – creates the single .exe
- `PITCH.txt` – sales pitch
- `reports/` and `alerts/` – created automatically

---

**ShopLock by Raymond**  
Setup: $249 | Monthly: $79  
Email: raymondrayray777@gmail.com
