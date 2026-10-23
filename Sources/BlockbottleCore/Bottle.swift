import Foundation

public struct Bottle: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var windowsVersion: String
    public var createdAt: Date
    public var engine: WineEngine
    /// Set by `BottleStore` when loading; not persisted.
    public var prefix: URL = URL(fileURLWithPath: "/")

    enum CodingKeys: String, CodingKey { case id, name, windowsVersion, createdAt, engine }

    public init(id: UUID = UUID(), name: String, windowsVersion: String = "win10",
                createdAt: Date = Date(), engine: WineEngine = .staging, prefix: URL) {
        self.id = id
        self.name = name
        self.windowsVersion = windowsVersion
        self.createdAt = createdAt
        self.engine = engine
        self.prefix = prefix
    }

    /// Bottles from older builds have no engine field; they were Steam bottles,
    /// which now belong on Wine Staging.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        windowsVersion = try c.decodeIfPresent(String.self, forKey: .windowsVersion) ?? "win10"
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        engine = try c.decodeIfPresent(WineEngine.self, forKey: .engine) ?? .staging
    }
}

public enum BottleEntry: Identifiable, Sendable {
    case ok(Bottle)
    case damaged(URL)

    public var id: String {
        switch self {
        case .ok(let b): return b.id.uuidString
        case .damaged(let url): return url.path
        }
    }

    public var bottle: Bottle? {
        if case .ok(let b) = self { return b }
        return nil
    }
}

/// Bottles live at `Bottles/<uuid>/` with metadata in `bottle.json`.
public struct BottleStore: Sendable {
    public static let metadataFile = "bottle.json"
    public let paths: AppPaths

    public init(paths: AppPaths) { self.paths = paths }

    public func list(fileManager: FileManager = .default) -> [BottleEntry] {
        guard let dirs = try? fileManager.contentsOfDirectory(at: paths.bottles, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var entries: [BottleEntry] = []
        for dir in dirs where dir.hasDirectoryPath || (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let meta = dir.appendingPathComponent(Self.metadataFile)
            if let data = try? Data(contentsOf: meta), var bottle = try? decoder.decode(Bottle.self, from: data) {
                bottle.prefix = dir
                entries.append(.ok(bottle))
            } else {
                entries.append(.damaged(dir))
            }
        }
        return entries.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case let (.ok(a), .ok(b)): return a.createdAt < b.createdAt
            case (.ok, .damaged): return true
            case (.damaged, .ok): return false
            case let (.damaged(a), .damaged(b)): return a.path < b.path
            }
        }
    }

    @discardableResult
    public func create(name: String, engine: WineEngine = .staging) throws -> Bottle {
        let id = UUID()
        let dir = paths.bottles.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bottle = Bottle(id: id, name: name, engine: engine, prefix: dir)
        try save(bottle)
        return bottle
    }

    public func save(_ bottle: Bottle) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(bottle).write(to: bottle.prefix.appendingPathComponent(Self.metadataFile), options: .atomic)
    }

    /// Only deletes directories inside `Bottles/`.
    public func delete(_ url: URL) throws {
        let target = url.standardizedFileURL
        guard target.deletingLastPathComponent().path == paths.bottles.standardizedFileURL.path else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.removeItem(at: target)
    }
}
