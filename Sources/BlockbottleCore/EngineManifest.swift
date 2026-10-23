import Foundation

/// A downloadable engine piece, resolved from a GitHub repo's latest release.
public struct EngineComponent: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let repo: String
    public let assetPattern: String
    public let installDir: String

    public init(id: String, displayName: String, repo: String, assetPattern: String, installDir: String) {
        self.id = id
        self.displayName = displayName
        self.repo = repo
        self.assetPattern = assetPattern
        self.installDir = installDir
    }

    public var latestReleaseAPI: URL {
        URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    }
}

public enum EngineManifest {
    /// Order matters: Wine first, because D3DMetal merges into it.
    public static let `default`: [EngineComponent] = [
        EngineComponent(id: "wine", displayName: "Wine (CrossOver build)", repo: "Gcenx/macOS_Wine_builds",
                        assetPattern: #"^wine-crossover-.*-osx64\.tar\.xz$"#, installDir: "Wine"),
        EngineComponent(id: "d3dmetal", displayName: "D3DMetal (Apple GPTK)", repo: "Gcenx/game-porting-toolkit",
                        assetPattern: #"^game-porting-toolkit-.*\.tar\.xz$"#, installDir: "D3DMetal"),
        EngineComponent(id: "dxmt", displayName: "DXMT", repo: "3Shain/dxmt",
                        assetPattern: #"^dxmt-.*\.tar\.gz$"#, installDir: "DXMT"),
        EngineComponent(id: "dxvk", displayName: "DXVK + MoltenVK", repo: "Gcenx/DXVK-macOS",
                        assetPattern: #"^dxvk-macOS-.*\.tar\.gz$"#, installDir: "DXVK"),
    ]
}
