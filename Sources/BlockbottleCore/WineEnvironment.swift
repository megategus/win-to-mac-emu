import Foundation

public struct WineInvocation: Equatable, Sendable {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]

    public init(executable: URL, arguments: [String], environment: [String: String] = [:]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
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
        for backend in GraphicsBackend.allCases {
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

    public func baseEnvironment(prefix: URL) -> [String: String] {
        [
            "WINEPREFIX": prefix.path,
            "WINEDEBUG": "-all",
        ]
    }

    public func invocation(prefix: URL, profile: GameProfile, program: [String]) -> WineInvocation {
        let backend = resolve(profile.backend).backend
        var env = baseEnvironment(prefix: prefix)
        if profile.msync {
            env["WINEMSYNC"] = "1"
            env["WINEESYNC"] = "1"
        }
        if profile.metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        if !backend.dllOverrides.isEmpty {
            env["WINEDLLOVERRIDES"] = backend.dllOverrides.joined(separator: ",") + "=n,b"
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
    public func tool(prefix: URL, _ arguments: [String]) -> WineInvocation {
        WineInvocation(executable: wineBinary, arguments: arguments, environment: baseEnvironment(prefix: prefix))
    }

    public func retinaInvocation(prefix: URL, enabled: Bool) -> WineInvocation {
        tool(prefix: prefix, ["reg", "add", "HKCU\\Software\\Wine\\Mac Driver", "/v", "RetinaMode",
                              "/t", "REG_SZ", "/d", enabled ? "y" : "n", "/f"])
    }
}

/// Copies DXMT / DXVK DLLs into a prefix so overrides find them.
public struct BackendInstaller: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths) { self.paths = paths }

    static let x64Dirs: Set<String> = ["x64", "x86_64-windows"]
    static let x32Dirs: Set<String> = ["x32", "i386-windows"]

    public func prepare(_ backend: GraphicsBackend, prefix: URL, fileManager: FileManager = .default) throws {
        guard backend == .dxmt || backend == .dxvk, let dir = backend.engineDirectory else { return }
        let source = paths.engines.appendingPathComponent(dir, isDirectory: true)
        let system32 = prefix.appendingPathComponent("drive_c/windows/system32", isDirectory: true)
        let syswow64 = prefix.appendingPathComponent("drive_c/windows/syswow64", isDirectory: true)
        guard let walker = fileManager.enumerator(at: source, includingPropertiesForKeys: nil) else { return }
        for case let file as URL in walker where file.pathExtension.lowercased() == "dll" {
            let parent = file.deletingLastPathComponent().lastPathComponent.lowercased()
            let target: URL
            if Self.x64Dirs.contains(parent) { target = system32 }
            else if Self.x32Dirs.contains(parent) { target = syswow64 }
            else { continue }
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            let dest = target.appendingPathComponent(file.lastPathComponent)
            if fileManager.fileExists(atPath: dest.path) { try fileManager.removeItem(at: dest) }
            try fileManager.copyItem(at: file, to: dest)
        }
    }
}
