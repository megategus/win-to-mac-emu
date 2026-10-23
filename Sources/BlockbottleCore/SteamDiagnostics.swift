import Foundation

/// Detects Steam inside Wine regardless of which process started it. Steam's
/// bootstrapper exits and relaunches itself while updating, so the process we
/// spawned is not a reliable signal.
public struct SteamProcessProbe: Sendable {
    let runner: ProcessRunner

    public init(runner: ProcessRunner) { self.runner = runner }

    public func isRunning() async -> Bool {
        let inv = WineInvocation(executable: URL(fileURLWithPath: "/usr/bin/pgrep"), arguments: ["-if", "steam\\.exe"])
        return ((try? await runner.run(inv, logTo: nil)) ?? 1) == 0
    }
}

/// Collects everything needed to diagnose Steam into one plain-text report.
public struct SteamDiagnostics: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths) { self.paths = paths }

    static let steamLogFiles = ["bootstrap_log.txt", "webhelper.txt", "cef_log.txt",
                                "connection_log.txt", "stderr.txt", "content_log.txt"]

    public func report(bottle: Bottle, fileManager fm: FileManager = .default) -> String {
        let env = WineEnvironment(paths: paths)
        let steamRoot = SteamLibraryScanner().steamRoot(in: bottle.prefix)
        let steamExe = steamRoot.appendingPathComponent("steam.exe")
        var out: [String] = []

        out.append("=== Blockbottle Steam report ===")
        out.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        out.append("data root: \(paths.root.path)")
        if let attrs = try? fm.attributesOfFileSystem(forPath: paths.root.path),
           let free = attrs[.systemFreeSize] as? NSNumber {
            out.append("free space: \(free.int64Value / 1_000_000_000) GB")
        }
        out.append("filesystem: \(StorageValidator.filesystemType(of: paths.root) ?? "unknown")")
        out.append("wine: \(env.wineBinary.path) (\(fm.isExecutableFile(atPath: env.wineBinary.path) ? "ok" : "MISSING"))")
        for c in EngineManifest.default {
            let v = (try? String(contentsOf: paths.engines.appendingPathComponent(c.installDir).appendingPathComponent(".version"),
                                 encoding: .utf8)) ?? "not installed"
            out.append("engine \(c.id): \(v)")
        }
        out.append("installed backends: \(env.installedBackends().map(\.rawValue).sorted().joined(separator: ", "))")
        out.append("active backend: \(BackendSwitcher(paths: paths).active?.rawValue ?? "none")")
        out.append("bottle: \(bottle.name) \(bottle.prefix.path)")
        out.append("steam.exe: \(fm.fileExists(atPath: steamExe.path) ? "present" : "MISSING")")
        let topLevel = (try? fm.contentsOfDirectory(atPath: steamRoot.path))?.sorted() ?? []
        out.append("Steam folder: \(topLevel.joined(separator: ", "))")

        for name in Self.steamLogFiles {
            let url = steamRoot.appendingPathComponent("logs").appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else { continue }
            out.append("\n--- Steam/logs/\(name) (last 80 lines) ---")
            out.append(LogTail.lastLines(80, of: url))
        }

        let launchDir = paths.logs.appendingPathComponent(bottle.id.uuidString)
        let launches = ((try? fm.contentsOfDirectory(atPath: launchDir.path)) ?? [])
            .filter { $0.hasSuffix("-steam.log") || $0.hasSuffix("-steam-install.log") || $0 == "steam-install.log" }
            .sorted()
        for name in launches.suffix(2) {
            out.append("\n--- Blockbottle launch log \(name) (last 80 lines) ---")
            out.append(LogTail.lastLines(80, of: launchDir.appendingPathComponent(name)))
        }
        return out.joined(separator: "\n")
    }
}
