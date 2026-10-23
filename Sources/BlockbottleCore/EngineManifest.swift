import Foundation

/// One place a component can be downloaded from: a GitHub repo's latest release.
public struct EngineSource: Codable, Hashable, Sendable {
    public let repo: String
    public let assetPattern: String

    public init(repo: String, assetPattern: String) {
        self.repo = repo
        self.assetPattern = assetPattern
    }

    public var latestReleaseAPI: URL {
        URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    }
}

/// A downloadable engine piece. Sources are tried in order.
public struct EngineComponent: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let sources: [EngineSource]
    public let installDir: String

    public init(id: String, displayName: String, sources: [EngineSource], installDir: String) {
        self.id = id
        self.displayName = displayName
        self.sources = sources
        self.installDir = installDir
    }
}

/// Which Wine a bottle runs on.
public enum WineEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Current upstream Wine (Gcenx wine-staging). Runs today's 64-bit Steam client.
    case staging
    /// Gcenx Game Porting Toolkit build: Wine 7.7 with D3DMetal. Too old for the
    /// current Steam client (crashes on start-up), so it is for hand-added games.
    case gptk

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .staging: return "Wine Staging (Steam)"
        case .gptk: return "Game Porting Toolkit (D3DMetal)"
        }
    }

    public var component: EngineComponent {
        switch self {
        case .staging: return EngineManifest.wine
        case .gptk: return EngineManifest.gptk
        }
    }

    public var runsSteam: Bool { self == .staging }
}

public enum EngineManifest {
    /// Upstream Wine for Steam bottles. `wine-devel` is deliberately not matched.
    public static let wine = EngineComponent(
        id: "wine", displayName: "Wine Staging",
        sources: [EngineSource(repo: "Gcenx/macOS_Wine_builds", assetPattern: #"^wine-staging-.*-osx64\.tar\.xz$"#)],
        installDir: "Wine")

    /// Full Wine 7.7 with D3DMetal built in (`Game Porting Toolkit.app/Contents/Resources/wine`).
    public static let gptk = EngineComponent(
        id: "gptk", displayName: "Game Porting Toolkit (D3DMetal)",
        sources: [EngineSource(repo: "Gcenx/game-porting-toolkit", assetPattern: #"^game-porting-toolkit-.*\.tar\.xz$"#)],
        installDir: "GPTK")

    /// Builtin layout: `<ver>/{x86_64-windows,i386-windows,x86_64-unix}/`.
    public static let dxmt = EngineComponent(
        id: "dxmt", displayName: "DXMT",
        sources: [EngineSource(repo: "3Shain/dxmt", assetPattern: #"^dxmt-.*-builtin\.tar\.gz$"#)],
        installDir: "DXMT")

    public static let dxvk = EngineComponent(
        id: "dxvk", displayName: "DXVK + MoltenVK",
        sources: [EngineSource(repo: "Gcenx/DXVK-macOS", assetPattern: #"^dxvk-macOS-.*-builtin\.tar\.gz$"#)],
        installDir: "DXVK")

    /// Order matters: Wine first, the backends overlay onto it.
    public static let `default`: [EngineComponent] = [wine, gptk, dxmt, dxvk]

    /// Components setup cannot continue without.
    public static let required: Set<String> = ["wine"]

    /// Earlier builds installed the GPTK Wine into `Engines/Wine`. Move it to
    /// `Engines/GPTK` so Wine Staging can take its place without a re-download.
    public static func migrate(paths: AppPaths, fileManager fm: FileManager = .default) {
        let wineDir = paths.engines.appendingPathComponent(wine.installDir, isDirectory: true)
        let gptkDir = paths.engines.appendingPathComponent(gptk.installDir, isDirectory: true)
        guard let version = try? String(contentsOf: wineDir.appendingPathComponent(".version"), encoding: .utf8),
              version.hasPrefix("game-porting-toolkit"),
              !fm.fileExists(atPath: gptkDir.path) else { return }
        try? fm.moveItem(at: wineDir, to: gptkDir)
        let oldState = paths.engines.appendingPathComponent("Wine-originals", isDirectory: true)
        let newState = paths.engines.appendingPathComponent("GPTK-originals", isDirectory: true)
        if fm.fileExists(atPath: oldState.path), !fm.fileExists(atPath: newState.path) {
            try? fm.moveItem(at: oldState, to: newState)
        }
    }
}
