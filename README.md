# ShopLock-Pro

Professional network & POS lockdown toolkit for independent coffee shops and small restaurants.

## Simple Pitch

"Most small shops leave their WiFi and POS wide open. I come in once, lock everything down properly, put a quiet monitor on it, and then check it every month so nothing new sneaks on. One-time setup is $249, then $79 a month. Takes about 45–60 minutes the first time. You keep full control – I just make sure nobody else is on your network."

### Key points to hit:
- Protects the POS (payment machine)
- Stops random people / old devices from staying connected
- Gives you a clear list of every device on the network
- Monthly peace of mind without you having to think about it

## How to Use (Portable Toolkit)

1. Copy the whole folder to a USB stick
2. On the customer's Windows computer, open the USB
3. Double-click `Run-ShopLock.bat`
4. Follow the menu

No Python install required. Works on almost every Windows PC/POS.

### What it does
- Scans every device currently on the network
- Saves a clean report you can leave with the owner
- Installs a quiet background monitor (every 6 hours)
- Shows the exact lockdown checklist so the job stays fast and consistent

### Important
- Only use on networks where the business owner has given you permission
- Never store their router password inside this tool
- Run as Administrator if you want the monitor task to install cleanly

### Files
- `Run-ShopLock.bat` ← double-click this
- `ShopLock.ps1` ← the actual program (PowerShell)
- `PITCH.txt` ← ready-to-use pitch
- `reports/` ← scan reports land here (created on first run)
- `alerts/` ← monitor alerts land here

This is the closest thing to a “single exe” that works everywhere without extra installs.
Later we can wrap it into a real .exe with a tool like PS2EXE if you want a true single file.

---
**ShopLock by Raymond**  
Setup: $249 | Monthly: $79
