# ShopLock-Pro

Single-file style portable toolkit for independent coffee shops and small restaurants.  
No Python needed. Works on almost every Windows PC / POS terminal.

## How to Use

1. Copy the whole folder to a USB stick
2. On the customer's Windows computer, open the USB
3. Double-click `Run-ShopLock.bat`
4. Follow the menu

## What it does

- Scans every device currently on the network (via ARP)
- Saves clean `.txt` + `.json` reports you can leave with the owner
- Installs a quiet background monitor (every 6 hours)
- Shows the exact lockdown checklist so the job stays fast and consistent

## Important

- Only use on networks where the business owner has given you permission
- Never store their router password inside this tool
- Run as Administrator if you want the monitor task to install cleanly

## Files

- `Run-ShopLock.bat` ← double-click this
- `ShopLock.ps1` ← the actual program (PowerShell)
- `PITCH.txt` ← ready-to-use sales pitch
- `reports/` ← scan reports land here
- `alerts/` ← monitor alerts land here

This is the closest thing to a “single exe” that works everywhere without extra installs.  
Later we can wrap it into a real `.exe` with PS2EXE if you want a true single file.

---

**ShopLock by Raymond**  
Setup: $249 | Monthly: $79  
Email: raymondrayray777@gmail.com
