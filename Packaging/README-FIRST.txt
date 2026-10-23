BLOCKBOTTLE — read me first
===========================

1. Drag Blockbottle into Applications — or into a folder on your external
   drive (e.g. /Volumes/Untitled/Blockbottle). Either works.

2. The first time, macOS will say Blockbottle "can't be opened" because it
   isn't notarized by Apple. To allow it:
     • Right-click (or Control-click) Blockbottle → Open → Open
   or, if that doesn't offer "Open":
     • System Settings → Privacy & Security → scroll down → "Open Anyway"
   or in Terminal:
     xattr -dr com.apple.quarantine /path/to/Blockbottle.app

3. On first launch, choose where Blockbottle keeps its world. External
   drives must be formatted APFS or Mac OS Extended (not exFAT).

4. Setup downloads Wine, graphics layers (D3DMetal, DXMT, DXVK) and Steam
   (~1 GB). Then sign in to Steam, install games, and play.

Requirements: Apple Silicon Mac (M1/M2/M3 or newer), macOS 14+, Rosetta 2
(the app offers to install it).

Games with kernel anti-cheat (Apex, PUBG, Rainbow Six Siege, CoD…) will not run.

Blockbottle is not affiliated with Mojang, Microsoft, Valve or Apple.
Font: Monocraft by Idrees Hassan, SIL Open Font License 1.1.
