import Foundation

public struct WineInvocation: Equatable, Sendable {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: URL?

    public init(executable: URL, arguments: [String], environment: [String: String] = [:],
                workingDirectory: URL? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

/// Builds wine command lines and environments from a profile.
public struct WineEnvironment: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths) { self.paths = paths }

    public var wineRoot: URL { paths.engines.appendingPathComponent("Wine", isDirectory: true) }

    /// Gcenx builds ship either as an app bundle or a plain tree.
    public var wineBinary: URL {
        let candidates = [
            "Contents/Resources/wine/bin/wine64",
            "Contents/Resources/wine/bin/wine",
            "bin/wine64",
            "bin/wine",
        ].map { wineRoot.appendingPathComponent($0) }
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) { return hit }
        return EngineLayout.find("bin/wine64", under: wineRoot) ?? EngineLayout.find("bin/wine", under: wineRoot) ?? candidates[1]
    }

    public var wineserverBinary: URL {
        wineBinary.deletingLastPathComponent().appendingPathComponent("wineserver")
    }

    public func installedBackends(fileManager: FileManager = .default) -> Set<GraphicsBackend> {
        var result: Set<GraphicsBackend> = [.wined3d]
        if EngineLayout.find("lib/external/D3DMetal.framework", under: wineRoot) != nil {
            result.insert(.d3dmetal)
        }
        for backend in [GraphicsBackend.dxmt, .dxvk] {
            if let dir = backend.engineDirectory,
               fileManager.fileExists(atPath: paths.engines.appendingPathComponent(dir).path) {
                result.insert(backend)
            }
        }
        return result
    }

    /// Falls back to WineD3D when the wanted backend's files are missing.
    public func resolve(_ wanted: GraphicsBackend) -> (backend: GraphicsBackend, fellBack: Bool) {
        installedBackends().contains(wanted) ? (wanted, false) : (.wined3d, wanted != .wined3d)
    }

    /// `verbose` keeps Wine's error channel so logs are useful for diagnosis;
    /// otherwise everything is silenced for speed.
    public func baseEnvironment(prefix: URL, verbose: Bool = false) -> [String: String] {
        [
            "WINEPREFIX": prefix.path,
            "WINEDEBUG": verbose ? "fixme-all" : "-all",
        ]
    }

    public func invocation(prefix: URL, profile: GameProfile, program: [String], verbose: Bool = false) -> WineInvocation {
        let backend = resolve(profile.backend).backend
        var env = baseEnvironment(prefix: prefix, verbose: verbose)
        if profile.msync {
            env["WINEMSYNC"] = "1"
            env["WINEESYNC"] = "1"
        }
        if profile.metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        if !backend.dllOverrides.isEmpty {
            env["WINEDLLOVERRIDES"] = backend.dllOverrides.joined(separator: ",") + "=b"
        }
        switch backend {
        case .dxvk:
            env["DXVK_ASYNC"] = "1"
        case .d3dmetal, .dxmt, .wined3d:
            break
        }
        return WineInvocation(executable: wineBinary, arguments: program, environment: env)
    }

    /// Plain wine call with no game profile (wineboot, winecfg, reg, installers).
    public func tool(prefix: URL, _ arguments: [String], verbose: Bool = false, workingDirectory: URL? = nil) -> WineInvocation {
        WineInvocation(executable: wineBinary, arguments: arguments,
                       environment: baseEnvironment(prefix: prefix, verbose: verbose), workingDirectory: workingDirectory)
    }

    public func retinaInvocation(prefix: URL, enabled: Bool) -> WineInvocation {
        tool(prefix: prefix, ["reg", "add", "HKCU\\Software\\Wine\\Mac Driver", "/v", "RetinaMode",
                              "/t", "REG_SZ", "/d", enabled ? "y" : "n", "/f"])
    }
}

/// DXMT and DXVK ship as Wine *builtin* DLLs, which Wine only loads from its
/// own `lib/wine/<arch>` folders. Activating a backend overlays its files there;
/// activating D3DMetal/WineD3D restores the originals. One backend is active at
/// a time for the shared Wine install.
public struct BackendSwitcher: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths) { self.paths = paths }

    static let archAliases: [String: String] = [
        "x86_64-windows": "x86_64-windows", "x64": "x86_64-windows",
        "i386-windows": "i386-windows", "x32": "i386-windows",
        "x86_64-unix": "x86_64-unix",
    ]

    var wineLib: URL? {
        EngineLayout.find("lib/wine", under: paths.engines.appendingPathComponent("Wine", isDirectory: true))
    }

    var stateDir: URL { paths.engines.appendingPathComponent("Wine-originals", isDirectory: true) }
    private var activeFile: URL { stateDir.appendingPathComponent(".active") }
    private var overlayFile: URL { stateDir.appendingPathComponent(".overlay") }

    public var active: GraphicsBackend? {
        (try? String(contentsOf: activeFile, encoding: .utf8)).flatMap(GraphicsBackend.init(rawValue:))
    }

    public func activate(_ backend: GraphicsBackend, fileManager fm: FileManager = .default) throws {
        guard let lib = wineLib else { return }
        let normalized: GraphicsBackend = (backend == .dxmt || backend == .dxvk) ? backend : .d3dmetal
        if active == normalized { return }
        try fm.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try restore(lib: lib, fileManager: fm)

        if let dir = normalized.engineDirectory, normalized != .d3dmetal {
            let source = paths.engines.appendingPathComponent(dir, isDirectory: true)
            var overlaid: [String] = []
            if let walker = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) {
                for case let file as URL in walker {
                    guard (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true,
                          let arch = Self.archAliases[file.deletingLastPathComponent().lastPathComponent.lowercased()]
                    else { continue }
                    let rel = "\(arch)/\(file.lastPathComponent)"
                    let dest = lib.appendingPathComponent(rel)
                    let backup = stateDir.appendingPathComponent(rel)
                    if fm.fileExists(atPath: dest.path), !fm.fileExists(atPath: backup.path) {
                        try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try fm.copyItem(at: dest, to: backup)
                    }
                    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                    try fm.copyItem(at: file, to: dest)
                    overlaid.append(rel)
                }
            }
            try overlaid.joined(separator: "\n").write(to: overlayFile, atomically: true, encoding: .utf8)
        }
        try normalized.rawValue.write(to: activeFile, atomically: true, encoding: .utf8)
    }

    /// Removes overlaid files and puts Wine's originals back.
    private func restore(lib: URL, fileManager fm: FileManager) throws {
        let overlaid = ((try? String(contentsOf: overlayFile, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)
        for rel in overlaid {
            let dest = lib.appendingPathComponent(rel)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            let backup = stateDir.appendingPathComponent(rel)
            if fm.fileExists(atPath: backup.path) { try fm.copyItem(at: backup, to: dest) }
        }
        try? fm.removeItem(at: overlayFile)
    }
}
