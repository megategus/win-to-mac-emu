import Foundation

/// Games added by hand: any Windows .exe, anywhere on disk (e.g. an external drive).
/// Stored in `<root>/custom-games.json`.
public struct CustomGameStore: Sendable {
    struct Entry: Codable, Equatable {
        let id: UUID
        let name: String
        let exePath: String
        /// Bottle the game runs in; nil (older entries) shows in every bottle.
        let bottleID: UUID?
    }

    public let paths: AppPaths

    public init(paths: AppPaths) { self.paths = paths }

    private var file: URL { paths.root.appendingPathComponent("custom-games.json") }

    private func load() -> [Entry] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func save(_ entries: [Entry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(to: file, options: .atomic)
    }

    private func game(_ e: Entry) -> SteamGame {
        let exe = URL(fileURLWithPath: e.exePath)
        return SteamGame(appID: "custom-\(e.id.uuidString)", name: e.name,
                         installDir: exe.deletingLastPathComponent(), executable: exe)
    }

    /// All games, or only those belonging to `bottleID` (plus unassigned ones).
    public func list(bottleID: UUID? = nil) -> [SteamGame] {
        load().filter { bottleID == nil || $0.bottleID == nil || $0.bottleID == bottleID }.map(game)
    }

    @discardableResult
    public func add(executable: URL, name: String, bottleID: UUID? = nil) throws -> SteamGame {
        let entry = Entry(id: UUID(), name: name, exePath: executable.standardizedFileURL.path, bottleID: bottleID)
        try save(load() + [entry])
        return game(entry)
    }

    public func remove(appID: String) throws {
        try save(load().filter { "custom-\($0.id.uuidString)" != appID })
    }
}
