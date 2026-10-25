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

- Scans the customer LAN using live network neighbor data first, ARP fallback second, and narrow subnet validation when needed
- Filters out junk and invalid MACs to keep results trustworthy
- Classifies devices as Known Good or Unknown and includes confidence metadata
- Saves clean `.txt` + `.json` reports with summary details and action guidance
- Installs a quiet background monitor (every 6 hours)
- Writes logs in a `logs/` folder so each run can be reviewed and debugged
- Uses a config file to support customer-specific branding and approved device lists

## Important

- Only use on networks where the business owner has given permission
- Never store router passwords inside the tool
- Run as Administrator if you want the monitor task to install cleanly
- This project is designed for Windows systems and requires PowerShell 5.1 or newer

## Files

- `Run-ShopLock.bat` – launcher for the .ps1 version
- `ShopLock.ps1` – the main script
- `shoplock.config.json` – customer/site settings and known-good device list
- `Build-EXE.ps1` – creates + optionally signs the single .exe
- `Verify-Signature.ps1` – checks digital signature of the EXE
- `PITCH.txt` – sales pitch
- `reports/`, `alerts/`, `logs/` – created automatically at runtime

---

**ShopLock by Raymond**
Setup: $249 | Monthly: $79
Email: raymondrayray777@gmail.com

