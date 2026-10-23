import AppKit
import BlockbottleCore
import Observation
import SwiftUI

struct SetupStep: Identifiable, Equatable {
    enum State: Equatable { case pending, running(Double), done, failed(String), skipped(String) }
    let id: String
    let title: String
    var state: State = .pending
}

struct LaunchFailure: Identifiable {
    let id = UUID()
    let title: String
    let log: String
    let logURL: URL
}

enum Route: Equatable {
    case storage
    case worldMissing(String)
    case title
    case setup
    case library
    case bottles
    case settings
}

@MainActor
@Observable
final class AppModel {
    static let splashes = [
        "Now with 100% more Wine!",
        "Runs on M1, M2 and M3!",
        "Also try CrossOver!",
        "Rosetta approved!",
        "Metal, not mining!",
        "Bottled at the source!",
        "Not affiliated with any block game!",
    ]

    var route: Route = .storage
    var paths: AppPaths?
    var storageError: String?
    var bottles: [BottleEntry] = []
    var selectedBottleID: UUID?
    var games: [SteamGame] = []
    var selectedGame: SteamGame?
    var setupSteps: [SetupStep] = []
    var isSettingUp = false
    var systemReport: SystemReport?
    var running: [String: LaunchHandle] = [:]
    var launchFailure: LaunchFailure?
    var toast: String?
    let splash = AppModel.splashes.randomElement()!

    private let runner = SystemProcessRunner()
    private let http = URLSessionHTTPClient()
    private let validator = StorageValidator()

    // MARK: Derived services

    var engineManager: EngineManager? { paths.map { EngineManager(paths: $0, http: http, runner: runner) } }
    var steamInstaller: SteamInstaller? { paths.map { SteamInstaller(paths: $0, runner: runner, http: http) } }
    var gameRunner: GameRunner? { paths.map { GameRunner(paths: $0, runner: runner) } }
    var profileStore: ProfileStore? { paths.map { ProfileStore(paths: $0) } }
    var wineEnvironment: WineEnvironment? { paths.map { WineEnvironment(paths: $0) } }

    var selectedBottle: Bottle? {
        let ok = bottles.compactMap(\.bottle)
        return ok.first { $0.id == selectedBottleID } ?? ok.first
    }

    var suggestedRoot: URL { AppPaths.suggestedRoot() }

    // MARK: Startup & storage

    func start() {
        guard let stored = UserDefaults.standard.string(forKey: AppPaths.defaultsKey) else {
            route = .storage
            return
        }
        openRoot(URL(fileURLWithPath: stored, isDirectory: true))
    }

    /// Validates and persists a new data root.
    func chooseRoot(_ url: URL) {
        if let problem = validator.validate(url) {
            storageError = problem.message
            return
        }
        UserDefaults.standard.set(url.path, forKey: AppPaths.defaultsKey)
        storageError = nil
        openRoot(url)
    }

    private func openRoot(_ url: URL) {
        if let problem = validator.validate(url) {
            if case .volumeMissing = problem {
                route = .worldMissing(problem.message)
            } else {
                storageError = problem.message
                route = .storage
            }
            return
        }
        let p = AppPaths(root: url)
        do {
            try p.ensureDirectories()
        } catch {
            storageError = "Couldn't create folders: \(error.localizedDescription)"
            route = .storage
            return
        }
        paths = p
        reloadBottles()
        route = needsSetup ? .setup : .title
        refreshLibrary()
    }

    func retryWorld() { start() }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        panel.message = "Choose where Blockbottle keeps Wine, bottles and games."
        if panel.runModal() == .OK, let url = panel.url {
            let root = url.lastPathComponent == "Blockbottle" ? url : url.appendingPathComponent("Blockbottle", isDirectory: true)
            chooseRoot(root)
        }
    }

    var needsSetup: Bool {
        guard let engines = engineManager, let steam = steamInstaller else { return true }
        let wine = EngineManifest.wine
        guard engines.isInstalled(wine), let bottle = selectedBottle else { return true }
        return !steam.isInstalled(bottle: bottle)
    }

    // MARK: Bottles & library

    func reloadBottles() {
        guard let paths else { return }
        bottles = BottleStore(paths: paths).list()
        if selectedBottle == nil { selectedBottleID = bottles.compactMap(\.bottle).first?.id }
    }

    func refreshLibrary() {
        guard let bottle = selectedBottle else { games = []; return }
        let prefix = bottle.prefix
        Task.detached {
            let found = SteamLibraryScanner().scan(prefix: prefix)
            await MainActor.run { self.games = found }
        }
    }

    func createBottle(named name: String) async {
        guard let paths, let steam = steamInstaller else { return }
        do {
            let bottle = try BottleStore(paths: paths).create(name: name.isEmpty ? "New World" : name)
            reloadBottles()
            selectedBottleID = bottle.id
            flash("Installing Steam into \(bottle.name)…")
            try await steam.install(bottle: bottle) { _ in }
            flash("\(bottle.name) is ready!")
        } catch {
            flash("Bottle setup failed: \(error.localizedDescription)")
        }
        reloadBottles()
        refreshLibrary()
    }

    func deleteBottle(_ entry: BottleEntry) {
        guard let paths else { return }
        let url: URL
        switch entry {
        case .ok(let b): url = b.prefix
        case .damaged(let u): url = u
        }
        do {
            try BottleStore(paths: paths).delete(url)
        } catch {
            flash("Couldn't delete: \(error.localizedDescription)")
        }
        reloadBottles()
        refreshLibrary()
    }

    // MARK: Setup

    func prepareSetupSteps() {
        guard setupSteps.isEmpty else { return }
        setupSteps = [SetupStep(id: "system", title: "Checking your Mac")]
            + EngineManifest.default.map { SetupStep(id: $0.id, title: "Mining \($0.displayName)") }
            + [SetupStep(id: "bottle", title: "Generating world"),
               SetupStep(id: "steam", title: "Installing Steam")]
    }

    private func update(_ id: String, _ state: SetupStep.State) {
        if let i = setupSteps.firstIndex(where: { $0.id == id }) { setupSteps[i].state = state }
    }

    var setupProgress: Double {
        guard !setupSteps.isEmpty else { return 0 }
        let total = setupSteps.reduce(0.0) { sum, step in
            switch step.state {
            case .done, .skipped: return sum + 1
            case .running(let p): return sum + p
            default: return sum
            }
        }
        return total / Double(setupSteps.count)
    }

    func runSetup() async {
        guard let paths, let engines = engineManager, let steam = steamInstaller, !isSettingUp else { return }
        isSettingUp = true
        defer { isSettingUp = false }
        prepareSetupSteps()
        for i in setupSteps.indices where setupSteps[i].state != .done { setupSteps[i].state = .pending }

        update("system", .running(0.5))
        let report = await SystemCheck(runner: runner).report()
        systemReport = report
        guard report.allGood else {
            var problems: [String] = []
            if !report.appleSilicon { problems.append("needs an Apple Silicon Mac") }
            if !report.macOSOK { problems.append("needs macOS 14 or newer") }
            if !report.rosetta { problems.append("Rosetta 2 is not installed") }
            update("system", .failed(problems.joined(separator: ", ")))
            return
        }
        update("system", .done)

        for component in EngineManifest.default {
            if engines.isInstalled(component) { update(component.id, .done); continue }
            update(component.id, .running(0))
            do {
                try await engines.install(component) { p in
                    Task { @MainActor in self.update(component.id, .running(p)) }
                }
                update(component.id, .done)
            } catch {
                if component.id == "wine" {
                    update(component.id, .failed(describe(error)))
                    return
                }
                // Graphics backends are optional; WineD3D still works.
                update(component.id, .skipped(describe(error)))
            }
        }

        update("bottle", .running(0.5))
        var bottle = selectedBottle
        if bottle == nil {
            do {
                bottle = try BottleStore(paths: paths).create(name: "Steam")
                reloadBottles()
            } catch {
                update("bottle", .failed(describe(error)))
                return
            }
        }
        update("bottle", .done)

        guard let bottle else { return }
        if steam.isInstalled(bottle: bottle) {
            update("steam", .done)
        } else {
            update("steam", .running(0.1))
            do {
                try await steam.install(bottle: bottle) { message in
                    Task { @MainActor in
                        if let i = self.setupSteps.firstIndex(where: { $0.id == "steam" }) {
                            let p: Double = message.contains("Install") ? 0.7 : (message.contains("Download") ? 0.4 : 0.2)
                            self.setupSteps[i].state = .running(p)
                        }
                    }
                }
                update("steam", .done)
            } catch {
                update("steam", .failed(describe(error)))
                return
            }
        }
        refreshLibrary()
        route = .title
    }

    func installRosetta() async {
        _ = try? await runner.run(SystemCheck.rosettaInstall, logTo: nil)
        await runSetup()
    }

    func reinstall(_ component: EngineComponent) async {
        guard let engines = engineManager else { return }
        flash("Re-mining \(component.displayName)…")
        do {
            try await engines.install(component) { _ in }
            flash("\(component.displayName) updated")
        } catch {
            flash("\(component.displayName) failed: \(describe(error))")
        }
    }

    // MARK: Launching

    func profile(for game: SteamGame) -> GameProfile {
        profileStore?.load(id: game.appID) ?? GameProfile()
    }

    func save(_ profile: GameProfile, for game: SteamGame) {
        try? profileStore?.save(profile, id: game.appID)
    }

    func isRunning(_ game: SteamGame) -> Bool { running[game.appID]?.process.isRunning ?? false }

    func launch(_ game: SteamGame) async {
        guard let runner = gameRunner, let bottle = selectedBottle else { return }
        let profile = profile(for: game)
        do {
            let handle = try await runner.launch(game: game, bottle: bottle, profile: profile)
            running[game.appID] = handle
            if handle.fellBack {
                flash("\(profile.backend.displayName) isn't installed — using \(handle.backend.displayName)")
            }
            watch(handle, key: game.appID, title: game.name)
        } catch {
            flash("Couldn't launch: \(describe(error))")
        }
    }

    func openSteam() {
        guard let runner = gameRunner, let bottle = selectedBottle else { return }
        do {
            let handle = try runner.launchSteam(bottle: bottle)
            running["steam"] = handle
            watch(handle, key: "steam", title: "Steam")
        } catch {
            flash("Couldn't start Steam: \(describe(error))")
        }
    }

    func runTool(_ args: [String]) {
        guard let runner = gameRunner, let bottle = selectedBottle else { return }
        do { _ = try runner.runTool(args, bottle: bottle) } catch { flash(describe(error)) }
    }

    func stop(_ game: SteamGame) async {
        running[game.appID]?.process.terminate()
        if let bottle = selectedBottle { await gameRunner?.killBottle(bottle) }
        running[game.appID] = nil
    }

    func killWine() async {
        if let bottle = selectedBottle { await gameRunner?.killBottle(bottle) }
        running.removeAll()
        flash("All Wine processes stopped")
    }

    private func watch(_ handle: LaunchHandle, key: String, title: String) {
        let started = Date()
        Task {
            let code = await handle.process.waitForExit()
            self.running[key] = nil
            if key == "steam" { self.refreshLibrary() }
            if code != 0, Date().timeIntervalSince(started) < 10 {
                self.launchFailure = LaunchFailure(title: "\(title) exited with code \(code)",
                                                   log: LogTail.lastLines(50, of: handle.logURL),
                                                   logURL: handle.logURL)
            }
        }
    }

    // MARK: Misc

    func flash(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.toast == message { self.toast = nil }
        }
    }

    func describe(_ error: Error) -> String {
        switch error {
        case EngineError.noMatchingAsset(let repo): return "no download found in \(repo)"
        case EngineError.checksumMismatch: return "download was corrupted — try again"
        case EngineError.extractFailed(let c): return "couldn't unpack (tar \(c))"
        case SteamInstallError.winebootFailed(let c): return "Wine failed to start (code \(c))"
        case SteamInstallError.setupFailed(let c): return "Steam installer failed (code \(c))"
        case SteamInstallError.steamMissingAfterInstall: return "Steam didn't install"
        case HTTPError.badStatus(let s): return "server answered \(s)"
        default: return error.localizedDescription
        }
    }
}
