import Foundation

public enum SteamInstallError: Error, Equatable {
    case winebootFailed(Int32)
    case setupFailed(Int32)
    case steamMissingAfterInstall
}

/// Initializes a prefix and installs the Windows Steam client into it.
public struct SteamInstaller: Sendable {
    public static let setupURL = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!

    let paths: AppPaths
    let runner: ProcessRunner
    let http: HTTPClient

    public init(paths: AppPaths, runner: ProcessRunner, http: HTTPClient) {
        self.paths = paths
        self.runner = runner
        self.http = http
    }

    private func log(_ bottle: Bottle) -> URL {
        paths.logs.appendingPathComponent(bottle.id.uuidString, isDirectory: true).appendingPathComponent("steam-install.log")
    }

    /// Creates the Wine prefix (any engine) and sets the Windows version.
    public func initialize(bottle: Bottle) async throws {
        let env = WineEnvironment(paths: paths, engine: bottle.engine)
        let boot = try await runner.run(env.tool(prefix: bottle.prefix, ["wineboot", "--init"], verbose: true), logTo: log(bottle))
        guard boot == 0 else { throw SteamInstallError.winebootFailed(boot) }
        _ = try? await runner.run(env.tool(prefix: bottle.prefix,
            ["reg", "add", "HKCU\\Software\\Wine", "/v", "Version", "/t", "REG_SZ", "/d", bottle.windowsVersion, "/f"]),
            logTo: log(bottle))
    }

    public func steamExe(in bottle: Bottle) -> URL {
        SteamLibraryScanner().steamRoot(in: bottle.prefix).appendingPathComponent("steam.exe")
    }

    public func isInstalled(bottle: Bottle) -> Bool {
        FileManager.default.fileExists(atPath: steamExe(in: bottle).path)
    }

    public func install(bottle: Bottle, progress: @escaping @Sendable (String) -> Void) async throws {
        let env = WineEnvironment(paths: paths, engine: bottle.engine)
        let logURL = log(bottle)

        progress("Generating world…")
        try await initialize(bottle: bottle)

        progress("Downloading Steam…")
        let downloaded = try await http.download(from: Self.setupURL) { _ in }
        let setup = bottle.prefix.appendingPathComponent("SteamSetup.exe")
        try? FileManager.default.removeItem(at: setup)
        try FileManager.default.moveItem(at: downloaded, to: setup)
        defer { try? FileManager.default.removeItem(at: setup) }

        progress("Installing Steam…")
        let code = try await runner.run(env.tool(prefix: bottle.prefix, [setup.path, "/S"], verbose: true), logTo: logURL)
        guard code == 0 else { throw SteamInstallError.setupFailed(code) }
        guard isInstalled(bottle: bottle) else { throw SteamInstallError.steamMissingAfterInstall }
    }
}
