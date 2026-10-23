# Blockbottle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Minecraft-styled SwiftUI launcher that installs Wine + graphics backends + Windows Steam into bottles on a user-chosen drive and launches Steam games, shipped as an ad-hoc-signed arm64 DMG.

**Architecture:** Swift Package with `BlockbottleCore` (Foundation-only, injectable filesystem + process runner, unit tested) and `Blockbottle` (SwiftUI executable). Shell scripts assemble the `.app` and `.dmg`; GitHub Actions on `macos-14` is the compiler, test runner and packager.

**Tech Stack:** Swift 5.10+/6 toolchain on Xcode 15+/16, SwiftUI, Observation, GameController, XCTest, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-23-blockbottle-design.md`

## Global Constraints

- Platform: `.macOS(.v14)`; architecture `arm64` only.
- Bundle ID `com.blockbottle.app`; app name `Blockbottle`.
- Data root from `UserDefaults` key `dataRoot`; default `~/Library/Application Support/Blockbottle`; suggested `/Volumes/Untitled/Blockbottle` when `/Volumes/Untitled` exists.
- Data root filesystem must be `apfs` or `hfs`.
- Subdirectories: `Engines`, `Bottles`, `Logs`, `Profiles`.
- No Mojang assets; font Monocraft (OFL) if available, else `.system(design: .monospaced)`.
- D3DMetal is never committed or packaged; downloaded at runtime only.
- No third-party Swift packages.
- `BlockbottleCore` imports only Foundation (and `FoundationNetworking` under `#if canImport`).

## Review Focus

1. Data root on an unplugged external drive → app must not silently create a fresh root on the internal disk; shows "World not found". (Task 1 test `testMissingVolumeIsReportedNotCreated`.)
2. Game names/paths with spaces, quotes, unicode in `.acf` → parsed intact. (Task 2 test `testQuotedValuesWithEscapesAndUnicode`.)
3. Steam library on a second drive inside the bottle (`libraryfolders.vdf` with multiple entries) → all libraries scanned. (Task 2 `testScansAllLibraryFolders`.)
4. Chosen backend not installed → falls back to `wined3d` with a warning, never launches with half-copied DLLs. (Task 3 `testMissingBackendFallsBackToWineD3D`.)
5. Interrupted/corrupt engine download → checksum mismatch deletes partial file and marks failed. (Task 6 `testChecksumMismatchDeletesFile`.)

---

### Task 1: Package scaffold, CI, AppPaths, StorageValidator

**Files:**
- Create: `Package.swift`, `Sources/BlockbottleCore/AppPaths.swift`, `Sources/BlockbottleCore/StorageValidator.swift`, `Sources/Blockbottle/BlockbottleApp.swift` (placeholder window), `Tests/BlockbottleCoreTests/AppPathsTests.swift`, `.github/workflows/build.yml`, `.gitignore`

**Interfaces:**
- Produces:
  - `struct AppPaths { init(root: URL); let root, engines, bottles, logs, profiles: URL; func ensureDirectories() throws }`
  - `enum StorageProblem: Error, Equatable { case volumeMissing(String), notWritable, unsupportedFilesystem(String) }`
  - `struct StorageValidator { var fsTypeProvider: (URL) -> String?; func validate(_ root: URL) -> StorageProblem?; static func volumeRoot(of: URL) -> URL? }` — `fsTypeProvider` default uses `statfs` `f_fstypename`.

- [ ] Test `testDirectoriesAreUnderRoot` — each subdir equals `root/<Name>`.
- [ ] Test `testUnsupportedFilesystemRejected` — provider returns `"exfat"` → `.unsupportedFilesystem("exfat")`; `"apfs"`, `"hfs"` → nil.
- [ ] Test `testMissingVolumeIsReportedNotCreated` — root `/Volumes/DefinitelyMissing/Blockbottle` → `.volumeMissing("DefinitelyMissing")` and directory not created.
- [ ] Implement; CI workflow job `test` runs `swift test` on `macos-14`.
- [ ] Commit.

### Task 2: VDFParser + SteamLibraryScanner

**Files:** `Sources/BlockbottleCore/VDFParser.swift`, `Sources/BlockbottleCore/SteamLibraryScanner.swift`, `Tests/BlockbottleCoreTests/VDFParserTests.swift`, `Tests/BlockbottleCoreTests/SteamLibraryScannerTests.swift`

**Interfaces:**
- Produces:
  - `indirect enum VDFValue: Equatable { case string(String), object([String: VDFValue]) ; subscript(key: String) -> VDFValue?; var stringValue: String? }`
  - `enum VDFParser { static func parse(_ text: String) throws -> [String: VDFValue] }` — keys case-insensitive lookup via lowercased storage; handles `\"`, `\\`, `//` comments.
  - `struct SteamGame: Identifiable, Hashable, Codable { let appID: String; let name: String; let installDir: URL }` (`id == appID`)
  - `struct SteamLibraryScanner { func steamRoot(in prefix: URL) -> URL  // drive_c/Program Files (x86)/Steam ; func scan(prefix: URL) -> [SteamGame] }` sorted by name; skips appID `228980` (Steamworks Common Redistributables).

- [ ] Tests: `testParsesNestedObjects`, `testQuotedValuesWithEscapesAndUnicode` (`"name" "Half-Life 2: \"Ep\" Ω"`), `testScansAllLibraryFolders` (fixture written in temp dir: two library paths, one Windows-style `C:\\Games\\SteamLibrary` mapped to `drive_c/Games/SteamLibrary`), `testSkipsRedistributables`.
- [ ] Implement; Windows paths `X:\\a\\b` map to `prefix/drive_x/a/b` for `c`, other letters via `prefix/dosdevices/x:`.
- [ ] Commit.

### Task 3: GraphicsBackend, GameProfile/ProfileStore, WineEnvironment

**Files:** `Sources/BlockbottleCore/GraphicsBackend.swift`, `GameProfile.swift`, `WineEnvironment.swift`, tests for each.

**Interfaces:**
- Produces:
  - `enum DirectXVersion: String, Codable, CaseIterable { case dx9, dx10, dx11, dx12, unknown }`
  - `enum GraphicsBackend: String, Codable, CaseIterable, Identifiable { case d3dmetal, dxmt, dxvk, wined3d; var displayName: String; var dllOverrides: [String]; static func recommended(for: DirectXVersion) -> GraphicsBackend }` — dx12→d3dmetal, dx11/dx10→dxmt, dx9→dxvk, unknown→d3dmetal.
  - `struct GameProfile: Codable, Equatable { var backend: GraphicsBackend = .d3dmetal; var retinaMode = false; var metalHUD = false; var msync = true; var launchArguments = "" ; var directX: DirectXVersion = .unknown }`
  - `struct ProfileStore { init(paths: AppPaths); func load(id: String) -> GameProfile; func save(_: GameProfile, id: String) throws }` — file `Profiles/<id>.json`; missing/corrupt → default.
  - `struct WineInvocation: Equatable { var executable: URL; var arguments: [String]; var environment: [String: String] }`
  - `struct WineEnvironment { init(paths: AppPaths); func installedBackends() -> Set<GraphicsBackend>; func resolve(_ wanted: GraphicsBackend) -> (backend: GraphicsBackend, fellBack: Bool); func invocation(prefix: URL, profile: GameProfile, program: [String]) -> WineInvocation }`
- Env values: `WINEPREFIX`, `WINEDEBUG=-all`, `WINEMSYNC=1` + `WINEESYNC=1` when msync, `MTL_HUD_ENABLED=1` when HUD, `WINEDLLOVERRIDES="<dlls>=n,b"` for dxmt/dxvk, `DXVK_ASYNC=1` for dxvk. D3DMetal: `WINEDLLPATH=<Engines/D3DMetal>/lib/wine` and `DYLD_FALLBACK_LIBRARY_PATH=<Engines/D3DMetal>/lib/external:<Engines/D3DMetal>/lib` (on-device validation required). Retina: registry key `HKCU\Software\Wine\Mac Driver` `RetinaMode` set via `reg add` before launch (`retinaInvocation(prefix:enabled:)`).
- Wine binary: first existing of `Engines/Wine/Contents/Resources/wine/bin/wine64`, `.../wine`, `Engines/Wine/bin/wine64`, `Engines/Wine/bin/wine`.
- `struct BackendInstaller { func prepare(_: GraphicsBackend, prefix: URL) throws }` — for dxmt/dxvk copy every `.dll` under a dir named `x64` or `x86_64-windows` into `drive_c/windows/system32`, and `x32` or `i386-windows` into `drive_c/windows/syswow64`; idempotent overwrite. Test `testPrepareCopiesDLLsByArch`.
- Backend installed when its marker dir exists: `Engines/D3DMetal`, `Engines/DXMT`, `Engines/DXVK`; `wined3d` always.

- [ ] Tests: `testRecommendedBackends`, `testDXMTOverrides` (contains `d3d11`, `dxgi`, `d3d10core`), `testMissingBackendFallsBackToWineD3D`, `testEnvironmentFlags`, `testCorruptProfileReturnsDefault`.
- [ ] Implement; commit.

### Task 4: Bottle + BottleStore

**Files:** `Sources/BlockbottleCore/Bottle.swift`, `Tests/BlockbottleCoreTests/BottleStoreTests.swift`

**Interfaces:**
- Produces:
  - `struct Bottle: Codable, Identifiable, Hashable { let id: UUID; var name: String; var windowsVersion: String = "win10"; var createdAt: Date; var prefix: URL { get } }` — prefix set by store, not encoded.
  - `enum BottleEntry: Identifiable { case ok(Bottle), damaged(URL) }`
  - `struct BottleStore { init(paths: AppPaths); func list() -> [BottleEntry]; func create(name: String) throws -> Bottle; func delete(_ url: URL) throws; func save(_: Bottle) throws }` — dir `Bottles/<uuid>/`, metadata `Bottles/<uuid>/bottle.json`.

- [ ] Tests: `testCreateListRoundTrip`, `testCorruptMetadataListedAsDamaged`, `testDeleteRemovesDirectory`.
- [ ] Implement; commit.

### Task 5: ProcessRunner, SystemCheck, GameRunner

**Files:** `ProcessRunner.swift`, `SystemCheck.swift`, `GameRunner.swift`, tests with `FakeProcessRunner`.

**Interfaces:**
- Produces:
  - `protocol ProcessRunner: Sendable { func run(_ inv: WineInvocation, logTo: URL?) async throws -> Int32; func start(_ inv: WineInvocation, logTo: URL?) throws -> RunningProcess }`
  - `protocol RunningProcess: AnyObject { var isRunning: Bool { get }; func terminate(); func waitForExit() async -> Int32 }`
  - `final class SystemProcessRunner: ProcessRunner` (Foundation `Process`).
  - `struct SystemReport: Equatable { var appleSilicon: Bool; var macOSOK: Bool; var rosetta: Bool; var allGood: Bool }`
  - `struct SystemCheck { init(runner: ProcessRunner, machine: () -> String = uname-based, osVersion: OperatingSystemVersion = ProcessInfo…); func report() async -> SystemReport }` — rosetta probe `/usr/bin/arch -x86_64 /usr/bin/true` exit 0.
  - `static let rosettaInstall: WineInvocation` → `/usr/sbin/softwareupdate --install-rosetta --agree-to-license`.
  - `final class GameRunner { init(paths:, runner:, env:); func launch(game: SteamGame, bottle: Bottle, profile: GameProfile) throws -> LaunchHandle; func launchSteam(bottle:) throws -> LaunchHandle; func killBottle(_:) async }`
  - `struct LaunchHandle { let process: RunningProcess; let logURL: URL; let fellBack: Bool }`; log path `Logs/<bottleID>/<yyyyMMdd-HHmmss>-<appID>.log`.
  - `enum LogTail { static func lastLines(_ n: Int, of: URL) -> String }`
- Steam launch program: `["C:\\Program Files (x86)\\Steam\\steam.exe", "-applaunch", appID] + launchArguments split on spaces`.

- [ ] Tests: `testRosettaMissingReported`, `testLaunchBuildsApplaunchArgsAndLogPath`, `testLogTailReturnsLastLines`.
- [ ] Implement; commit.

### Task 6: EngineManifest + EngineManager

**Files:** `EngineManifest.swift`, `EngineManager.swift`, `Tests/.../EngineManagerTests.swift`

**Interfaces:**
- Produces:
  - `struct EngineComponent: Codable, Identifiable { let id: String; let displayName: String; let repo: String; let assetPattern: String; let installDir: String }`
  - `static let EngineManifest.default: [EngineComponent]` — `wine` (`Gcenx/macOS_Wine_builds`, `^wine-crossover-.*-osx64\.tar\.xz$`, `Wine`), `d3dmetal` (`Gcenx/game-porting-toolkit`, `^game-porting-toolkit-.*\.tar\.xz$`, `D3DMetal`), `dxmt` (`3Shain/dxmt`, `^dxmt-.*\.tar\.gz$`, `DXMT`), `dxvk` (`Gcenx/DXVK-macOS`, `^dxvk-macOS-.*\.tar\.gz$`, `DXVK`).
  - `struct ResolvedAsset { let url: URL; let name: String; let sha256: String? }`
  - `protocol HTTPClient { func data(from: URL) async throws -> Data; func download(from: URL, progress: @Sendable (Double) -> Void) async throws -> URL }`
  - `final class EngineManager { init(paths:, http:, runner:); func isInstalled(_:) -> Bool; func resolve(_:) async throws -> ResolvedAsset; func install(_:, progress:) async throws; static func sha256(of: URL) throws -> String }` — parses GitHub `/repos/<repo>/releases/latest` JSON `assets[].name/browser_download_url/digest` (`"sha256:<hex>"`); extracts with `/usr/bin/tar -xf <file> -C <tmp>`, then moves single top-level dir (or the tmp dir) into `Engines/<installDir>`; writes `Engines/<installDir>/.version` with asset name.
  - `enum EngineError: Error { case noMatchingAsset(String), checksumMismatch, extractFailed(Int32) }`
- SHA-256: implement manually over `FileHandle` chunks (no CryptoKit in Core for Linux portability is not required — use CryptoKit under `#if canImport(CryptoKit)`).

- [ ] Tests: `testResolvePicksMatchingAsset` (fixture JSON), `testNoMatchingAssetThrows`, `testChecksumMismatchDeletesFile`.
- [ ] Implement; commit.

### Task 7: SteamInstaller + AntiCheatList

**Files:** `SteamInstaller.swift`, `AntiCheatList.swift`, tests.

**Interfaces:**
- Produces:
  - `struct SteamInstaller { static let setupURL = URL(string: "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe")!; func isInstalled(bottle:) -> Bool; func install(bottle:, progress: (String) -> Void) async throws }` — steps: `wineboot --init` (program `["wineboot", "--init"]`), download setup to `Bottles/<id>/SteamSetup.exe`, run `[setupPath, "/S"]`, verify `steam.exe` exists.
  - `enum AntiCheatList { static let blocked: Set<String>; static func isBlocked(_ appID: String) -> Bool }` — seed IDs: `1172470` (Apex Legends), `578080` (PUBG), `359550` (Rainbow Six Siege), `2357570` (Overwatch 2 — Battle.net-gated), `1938090` (Call of Duty).
- [ ] Tests: `testInstallRunsWinebootThenSetup` (fake runner records invocations, fake http), `testBlockedIDs`.
- [ ] Commit.

### Task 8: Minecraft-style theme

**Files:** `Sources/Blockbottle/Theme/{Palette.swift, PixelFont.swift, DirtBackground.swift, BlockButtonStyle.swift, InventoryPanel.swift, BlockProgressBar.swift, SplashText.swift}`, `Sources/Blockbottle/Resources/` (font if obtainable).

**Interfaces:**
- Produces: `Palette.{stone, stoneLight, stoneDark, panel, slot, grassGreen, text, textShadow, splashYellow}`; `Font.pixel(_ size: CGFloat) -> Font`; `DirtBackground()` view (Canvas, deterministic seed, 16-px blocks of 4 browns, 0.55 black overlay); `BlockButtonStyle(kind: .stone | .green | .red)`; `InventoryPanel { content }`; `BlockProgressBar(value: Double)`; `SplashText(text:)` rotating −20°, pulse 1.0↔1.08 over 0.6s.
- Colors: stone `#7F7F7F`, light bevel `#BEBEBE`, dark bevel `#3F3F3F`, panel `#C6C6C6`, slot `#8B8B8B`, green `#5B8731`, splash `#FFFF55`.
- [ ] Builds in CI; commit.

### Task 9: Screens + view models

**Files:** `Sources/Blockbottle/{AppModel.swift, Views/TitleView.swift, Views/StoragePickerView.swift, Views/SetupView.swift, Views/LibraryView.swift, Views/GameDetailView.swift, Views/BottlesView.swift, Views/SettingsView.swift, ControllerMonitor.swift}`

**Interfaces:**
- Consumes all Core interfaces above.
- Produces `@MainActor @Observable final class AppModel` with `route: Route` (`.storage, .title, .setup, .library, .bottles, .settings, .worldMissing`), `dataRoot: URL?`, `bottles`, `games`, `selectedBottle`, `setupSteps: [SetupStep]`, `running: [String: LaunchHandle]`, `lastError: String?`; methods `chooseRoot(_:)`, `runSetup()`, `refreshLibrary()`, `launch(_:)`, `stop(_:)`.
- Startup routing: no `dataRoot` → `.storage`; validator `.volumeMissing` → `.worldMissing`; engines or Steam missing → `.setup`; else `.title`.
- Copy: storage title "Where should Blockbottle keep its world?"; missing "World not found — plug in <volume>"; setup progress label "Building terrain…"; splash texts include "Now with 100% more Wine!".
- Launch error: process exits within 10s non-zero → panel with `LogTail.lastLines(50)` + Copy button.
- [ ] Builds in CI; commit.

### Task 10: Packaging

**Files:** `Packaging/Info.plist`, `Packaging/README-FIRST.txt`, `scripts/build-app.sh`, `scripts/make-dmg.sh`, workflow job `package`, `README.md`.

- Info.plist: `CFBundleIdentifier com.blockbottle.app`, `CFBundleExecutable Blockbottle`, `LSMinimumSystemVersion 14.0`, `LSArchitecturePriority [arm64]`, `NSHighResolutionCapable true`, `CFBundleShortVersionString 0.1.0`.
- `build-app.sh`: `swift build -c release --arch arm64`, copy binary + resource bundle into `build/Blockbottle.app`, `codesign --force --deep -s - build/Blockbottle.app`.
- `make-dmg.sh`: stage app + `Applications` symlink + README-FIRST, `hdiutil create -volname Blockbottle -srcfolder stage -ov -format UDZO build/Blockbottle.dmg`.
- CI uploads `build/Blockbottle.dmg` via `actions/upload-artifact@v4`.
- [ ] CI green with artifact; commit.
