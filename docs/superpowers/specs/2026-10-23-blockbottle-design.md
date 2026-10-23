# Blockbottle — Design Spec

Date: 2026-10-23
Status: Approved in conversation; awaiting written-spec review

## 1. Intent

**What the user said**
- A macOS launcher for Windows Steam games, built on existing foundations
  (Wine, Apple Game Porting Toolkit / D3DMetal, CrossOver-derived Wine).
- Components: game library UI, Wine bottle manager, graphics backend selector
  (DXVK, D3DMetal, DXMT), controller + display settings, game runner.
- Minecraft-style visual design.
- Must run on Apple Silicon M1, M2, M3.
- Distributed as a `.dmg` to friends.

**Decisions made during brainstorming**
- UI: SwiftUI (native; no Chromium competing with games for RAM).
- Distribution: friends only, ad-hoc signed, not notarized. Recipients bypass
  Gatekeeper once (right-click → Open, or `xattr -dr com.apple.quarantine`).
- Wine engine: downloaded on first run, not bundled.
- D3DMetal: downloaded on first run from a public third-party build alongside
  Wine — never shipped inside our DMG. (User originally picked "bundle"; the
  approved design keeps the one-click UX without us redistributing Apple
  binaries.)

**Assumptions**
- Target macOS 14 (Sonoma) or later. Rosetta 2 required.
- "Steam games" means games installed by the **Windows** Steam client running
  inside a bottle.
- Games with kernel anti-cheat (EAC/BattlEye/Vanguard without Wine support)
  are out of reach; the app warns rather than pretends.

**Success criteria (v1)**
1. A friend opens the DMG, drags the app to Applications, launches it, and the
   first-run flow installs engines + creates a bottle + installs Steam with no
   terminal use.
2. Steam games installed in the bottle appear in the library automatically.
3. A game launches with a chosen graphics backend; a failed launch shows the
   log tail.
4. CI produces a downloadable `.dmg` on every push to the dev branch.

## 2. Non-goals (v1)

Auto-update (Sparkle), community compatibility database, Intel Mac support,
notarization, non-Steam storefront integrations (Epic/GOG), anti-cheat
workarounds, bundling CrossOver.

## 3. Architecture

Swift Package with two targets plus a packaging script:

```
Package.swift
Sources/
  BlockbottleCore/   # pure Swift, no SwiftUI/AppKit. Foundation only.
  Blockbottle/       # SwiftUI app (executable target)
Tests/
  BlockbottleCoreTests/
scripts/
  build-app.sh       # swift build → .app bundle → ad-hoc codesign
  make-dmg.sh        # hdiutil → Blockbottle.dmg
.github/workflows/build.yml   # macos-14 (arm64) runner
```

No hand-maintained `.xcodeproj`. The app bundle is assembled by script with a
checked-in `Info.plist`. Architecture: `arm64` only (covers M1–M3+).

### 3.1 Core units (`BlockbottleCore`)

| Unit | Purpose | Depends on |
|---|---|---|
| `AppPaths` | Resolves `~/Library/Application Support/Blockbottle/{Engines,Bottles,Logs}`; injectable root for tests | Foundation |
| `EngineManifest` | Declares downloadable components (Wine, DXMT, DXVK+MoltenVK, D3DMetal) with URL, SHA-256, archive type, install subpath | — |
| `EngineManager` | Downloads (resumable via `URLSession`), verifies SHA-256, extracts (`/usr/bin/tar`/`ditto`), reports progress, reports installed state | `AppPaths`, `EngineManifest`, `ProcessRunner` |
| `Bottle` / `BottleStore` | Bottle model (id, name, Windows version, created date, default backend) persisted as `bottle.json` inside each prefix dir; CRUD | `AppPaths` |
| `WineEnvironment` | Builds the environment + argv for a wine invocation: `WINEPREFIX`, `WINEDEBUG`, `WINEMSYNC`/`WINEESYNC`, `WINEDLLOVERRIDES`, `MTL_HUD_ENABLED`, retina flag, backend vars | `Bottle`, `GameProfile`, `GraphicsBackend` |
| `GraphicsBackend` | Enum `d3dmetal, dxmt, dxvk, wined3d`; each maps to DLL overrides, DLL install (copy into `system32`/`syswow64`), and env vars; `recommended(for: DirectXVersion)` | — |
| `GameProfile` / `ProfileStore` | Per-game settings keyed by Steam app ID or exe path | `AppPaths` |
| `VDFParser` | Parses Valve KeyValues text (`appmanifest_*.acf`, `libraryfolders.vdf`) | — |
| `SteamLibraryScanner` | Finds Steam inside a bottle, enumerates libraries and manifests → `[Game]` (appID, name, installDir, exe guess) | `VDFParser`, `Bottle` |
| `SteamInstaller` | `wineboot --init`, download `SteamSetup.exe`, run `/S` silent install | `ProcessRunner`, `WineEnvironment` |
| `ProcessRunner` | Protocol over `Process`; launch with env, stream stdout/stderr to a log file, terminate; fake impl for tests | Foundation |
| `GameRunner` | Launches a game (via Steam `-applaunch <id>` or direct exe), tracks running state, stop, `wineserver -k` | `ProcessRunner`, `WineEnvironment`, `AppPaths` |
| `SystemCheck` | Apple Silicon? macOS ≥ 14? Rosetta installed (`arch -x86_64 /usr/bin/true`)? | `ProcessRunner` |
| `AntiCheatList` | Small bundled list of known-incompatible Steam app IDs → warning badge | — |

Rules: every unit takes its dependencies by initializer injection;
filesystem roots and process execution are injectable so Core is testable
without Wine or macOS.

### 3.2 App layer (`Blockbottle`)

SwiftUI, `@Observable` view models wrapping Core units.

Screens:
1. **Title** — logo, splash text, buttons: Play, Bottles, Settings, Quit.
2. **First-run Setup** — system check results, then "Building terrain…"
   progress for engine downloads → bottle creation → Steam install.
3. **Library** — inventory-slot grid of games (Steam header art from
   `https://cdn.cloudflare.steamstatic.com/steam/apps/<id>/header.jpg`,
   fallback block icon); "Open Steam" slot; "Add .exe" slot.
4. **Game Detail** — big green Launch / red Stop button, backend picker,
   display toggles (retina, HUD, MSync), launch args, view log, anti-cheat
   warning.
5. **Bottles** — list, create, delete, open in Finder, run winecfg, kill
   wineserver.
6. **Settings** — engines installed/versions, re-download, controllers
   connected (GameController framework), log folder.

### 3.3 Visual system (Minecraft-style, original assets)

- Font: Monocraft (SIL OFL) bundled as a resource; fallback to monospaced
  system font.
- Background: procedurally drawn dirt tile (SwiftUI `Canvas`, seeded noise
  of 4 browns, 16×16 "pixels" scaled with nearest-neighbor) darkened.
- Buttons: stone-gray fill, 2px light top-left / dark bottom-right bevel,
  black outline, white text with drop shadow; hover → blue-tinted highlight;
  disabled → darker gray.
- Panels: inventory-style `#C6C6C6` panels with bevels; slots `#8B8B8B` inset.
- Progress bar: green fill on dark track, segmented.
- Splash text: yellow, rotated −20°, pulsing scale.
- No Mojang textures, logos, or the Minecraft font.

## 4. Data flow

First run: `SystemCheck` → `EngineManager.installAll` → `BottleStore.create`
→ `SteamInstaller.install(bottle)` → Library.

Launch: user taps Launch → `ProfileStore.profile(for: game)` →
`GraphicsBackend.prepare(bottle)` (copy DLLs) → `WineEnvironment.build` →
`GameRunner.launch` → log file at `Logs/<bottle>/<timestamp>-<game>.log`.

Library refresh: on appear and on Steam process exit →
`SteamLibraryScanner.scan(bottle)`.

## 5. Error handling

- Download failure / checksum mismatch → component marked failed, Retry
  button; partial files deleted on checksum mismatch.
- Rosetta missing → setup blocked, button runs
  `softwareupdate --install-rosetta --agree-to-license`.
- Launch exits non-zero within 10s → error panel with last 50 log lines +
  "Copy log".
- Missing backend files for chosen backend → fall back to `wined3d`, show a
  warning toast.
- Corrupt `bottle.json` → bottle listed as "damaged" with delete option;
  never crashes the list.

## 6. Testing

- Unit tests for `VDFParser`, `SteamLibraryScanner` (fixture dirs),
  `WineEnvironment`, `GraphicsBackend`, `BottleStore`, `ProfileStore`,
  `EngineManager` checksum/extract logic (fake runner), `SystemCheck`
  (fake runner).
- CI (`macos-14`): `swift test`, then build app + DMG, upload as artifact.
- Manual on-device testing by the user (games, controllers, Metal backends)
  — cannot be done in CI.

## 7. Distribution

- `scripts/build-app.sh`: `swift build -c release --arch arm64`, assemble
  `Blockbottle.app/Contents/{MacOS,Resources,Info.plist}`, `codesign --force
  --deep -s -` (ad-hoc).
- `scripts/make-dmg.sh`: staging dir with app + `/Applications` symlink +
  `README-FIRST.txt` (Gatekeeper bypass steps), `hdiutil create -format UDZO`.
- CI uploads `Blockbottle.dmg` as a workflow artifact.

## 8. Known risks

- Third-party engine URLs/versions change → pinned in `EngineManifest`,
  updated by app release.
- D3DMetal license ambiguity → we never host it; user downloads from a
  third party at runtime.
- Unverifiable here: actual Wine/Metal behavior; first real validation is on
  the user's Mac.
