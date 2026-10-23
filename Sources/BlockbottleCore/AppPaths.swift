import Foundation

/// All on-disk locations Blockbottle uses, derived from one user-chosen root
/// (which may live on an external drive).
public struct AppPaths: Sendable, Equatable {
    public static let defaultsKey = "dataRoot"

    public let root: URL
    public let engines: URL
    public let bottles: URL
    public let logs: URL
    public let profiles: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
        engines = self.root.appendingPathComponent("Engines", isDirectory: true)
        bottles = self.root.appendingPathComponent("Bottles", isDirectory: true)
        logs = self.root.appendingPathComponent("Logs", isDirectory: true)
        profiles = self.root.appendingPathComponent("Profiles", isDirectory: true)
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Blockbottle", isDirectory: true)
    }

    /// `/Volumes/Untitled/Blockbottle` when that drive is plugged in.
    public static func suggestedRoot(fileManager: FileManager = .default) -> URL {
        let untitled = URL(fileURLWithPath: "/Volumes/Untitled", isDirectory: true)
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: untitled.path, isDirectory: &isDir), isDir.boolValue {
            return untitled.appendingPathComponent("Blockbottle", isDirectory: true)
        }
        return defaultRoot
    }

    public func ensureDirectories(fileManager: FileManager = .default) throws {
        for dir in [root, engines, bottles, logs, profiles] {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
