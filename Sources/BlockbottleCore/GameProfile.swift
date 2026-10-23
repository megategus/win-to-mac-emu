import Foundation

public struct GameProfile: Codable, Equatable, Sendable {
    public var backend: GraphicsBackend = .d3dmetal
    public var retinaMode = false
    public var metalHUD = false
    public var msync = true
    public var launchArguments = ""
    public var directX: DirectXVersion = .unknown

    public init() {}

    public var argumentList: [String] {
        launchArguments.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

/// Stores one JSON file per game at `Profiles/<id>.json`.
public struct ProfileStore: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths) { self.paths = paths }

    private func url(for id: String) -> URL {
        let safe = id.replacingOccurrences(of: "/", with: "_")
        return paths.profiles.appendingPathComponent("\(safe).json")
    }

    /// Missing or corrupt profiles yield defaults.
    public func load(id: String) -> GameProfile {
        guard let data = try? Data(contentsOf: url(for: id)),
              let profile = try? JSONDecoder().decode(GameProfile.self, from: data) else {
            return GameProfile()
        }
        return profile
    }

    public func save(_ profile: GameProfile, id: String) throws {
        try FileManager.default.createDirectory(at: paths.profiles, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: url(for: id), options: .atomic)
    }
}
