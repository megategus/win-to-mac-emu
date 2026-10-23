# Blockbottle

A Minecraft-styled macOS launcher for Windows Steam games on Apple Silicon (M1/M2/M3+).
It is **not an emulator**: it drives Wine (CrossOver-based builds) under Rosetta 2, with
selectable DirectX→Metal translation layers (D3DMetal, DXMT, DXVK+MoltenVK, WineD3D).

## Get the app

Every push builds a DMG in GitHub Actions → **Actions → build → latest run → Artifacts →
`Blockbottle-dmg`**. Unzip, open `Blockbottle.dmg`, and follow `README-FIRST.txt`
(the app is ad-hoc signed, not notarized — right-click → Open the first time).

### Installing onto an external drive

1. Drag `Blockbottle.app` into e.g. `/Volumes/Untitled/Blockbottle/`.
2. On first launch choose **Use this folder** — when a drive named `Untitled` is plugged
   in, Blockbottle suggests `/Volumes/Untitled/Blockbottle` automatically.
3. The drive must be **APFS or Mac OS Extended**. exFAT/FAT/NTFS can't hold Wine bottles
   (no symlinks/permissions) and Blockbottle refuses them. Reformat in Disk Utility if needed.
4. If the drive is unplugged, Blockbottle shows "World not found" instead of creating a
   new world on your internal disk.

Everything — Wine, graphics layers, bottles, Steam, games, logs — lives under that folder:

```
Blockbottle/
  Engines/   Wine, D3DMetal, DXMT, DXVK
  Bottles/   <uuid>/  (Wine prefixes, one has Steam)
  Profiles/  per-game settings
  Logs/      one log per launch
```

## Build locally (macOS 14+, Xcode 15+)

```sh
swift test               # core unit tests
scripts/build-app.sh     # build/Blockbottle.app
scripts/make-dmg.sh      # build/Blockbottle.dmg
```

## Layout

- `Sources/BlockbottleCore` — Foundation-only logic: storage, engines, bottles, Steam
  library scanning, Wine environments, process running. Unit tested.
- `Sources/Blockbottle` — SwiftUI app and the block-style theme.
- `docs/superpowers/` — design spec and implementation plan.

## Known limits

- Kernel anti-cheat games (EAC/BattlEye/Vanguard without Wine support) won't run.
- Engine download names are matched by pattern against upstream GitHub releases
  (Gcenx, 3Shain); if upstream renames assets, setup reports "no download found".
  Run the `probe-engines` workflow to see current names and archive layouts.
- Each bottle has its own engine:
  - **Wine Staging** (current upstream Wine, Gcenx build) for Steam bottles. DXMT and
    DXVK are swapped into it at launch.
  - **Game Porting Toolkit** (Gcenx build: Wine 7.7 + D3DMetal) for bottles of games
    added with *Add game…*. It cannot run Steam: today's 64-bit Steam client crashes on
    Wine 7.7 at start-up (reproduced in the `steam-repro` workflow).
- D3DMetal comes from Apple's Game Porting Toolkit, downloaded at runtime from
  Gcenx's third-party build; it is never shipped in this repo or DMG.

Not affiliated with Mojang, Microsoft, Valve or Apple. Font: Monocraft (SIL OFL 1.1).
