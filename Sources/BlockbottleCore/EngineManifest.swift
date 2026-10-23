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

public enum EngineManifest {
    /// Gcenx's Game Porting Toolkit build is a full CrossOver-based Wine with
    /// D3DMetal built in (`Game Porting Toolkit.app/Contents/Resources/wine`).
    /// Plain wine-staging is the fallback (no D3DMetal).
    public static let wine = EngineComponent(
        id: "wine", displayName: "Wine + D3DMetal (Game Porting Toolkit)",
        sources: [
            EngineSource(repo: "Gcenx/game-porting-toolkit", assetPattern: #"^game-porting-toolkit-.*\.tar\.xz$"#),
            EngineSource(repo: "Gcenx/macOS_Wine_builds", assetPattern: #"^wine-staging-.*-osx64\.tar\.xz$"#),
        ],
        installDir: "Wine")

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
    public static let `default`: [EngineComponent] = [wine, dxmt, dxvk]
}
