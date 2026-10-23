import Foundation

public struct LaunchHandle: Sendable {
    public let process: RunningProcess
    public let logURL: URL
    public let backend: GraphicsBackend
    public let fellBack: Bool
}

/// Starts games and Steam inside a bottle and records a log per launch.
public struct GameRunner: Sendable {
    public static let steamExe = "C:\\Program Files (x86)\\Steam\\steam.exe"

    public let paths: AppPaths
    let runner: ProcessRunner
    let env: WineEnvironment
    let now: @Sendable () -> Date

    public init(paths: AppPaths, runner: ProcessRunner, now: @escaping @Sendable () -> Date = Date.init) {
        self.paths = paths
        self.runner = runner
        self.env = WineEnvironment(paths: paths)
        self.now = now
    }

    public func logURL(bottle: Bottle, label: String) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return paths.logs.appendingPathComponent(bottle.id.uuidString, isDirectory: true)
            .appendingPathComponent("\(f.string(from: now()))-\(label).log")
    }

    public func launch(game: SteamGame, bottle: Bottle, profile: GameProfile) async throws -> LaunchHandle {
        let resolved = env.resolve(profile.backend)
        try BackendInstaller(paths: paths).prepare(resolved.backend, prefix: bottle.prefix)
        let log = logURL(bottle: bottle, label: game.appID)
        _ = try? await runner.run(env.retinaInvocation(prefix: bottle.prefix, enabled: profile.retinaMode), logTo: log)
        var effective = profile
        effective.backend = resolved.backend
        let program = [Self.steamExe, "-applaunch", game.appID] + profile.argumentList
        let process = try runner.start(env.invocation(prefix: bottle.prefix, profile: effective, program: program), logTo: log)
        return LaunchHandle(process: process, logURL: log, backend: resolved.backend, fellBack: resolved.fellBack)
    }

    public func launchSteam(bottle: Bottle) throws -> LaunchHandle {
        let log = logURL(bottle: bottle, label: "steam")
        var profile = GameProfile()
        profile.backend = env.resolve(.d3dmetal).backend
        let process = try runner.start(env.invocation(prefix: bottle.prefix, profile: profile, program: [Self.steamExe]), logTo: log)
        return LaunchHandle(process: process, logURL: log, backend: profile.backend, fellBack: false)
    }

    public func runTool(_ args: [String], bottle: Bottle) throws -> LaunchHandle {
        let log = logURL(bottle: bottle, label: args.first ?? "tool")
        let process = try runner.start(env.tool(prefix: bottle.prefix, args), logTo: log)
        return LaunchHandle(process: process, logURL: log, backend: .wined3d, fellBack: false)
    }

    /// Kills every wine process in the bottle.
    public func killBottle(_ bottle: Bottle) async {
        let inv = WineInvocation(executable: env.wineserverBinary, arguments: ["-k"],
                                 environment: env.baseEnvironment(prefix: bottle.prefix))
        _ = try? await runner.run(inv, logTo: nil)
    }
}
