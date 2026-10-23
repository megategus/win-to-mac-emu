import Foundation

public struct SteamGame: Identifiable, Hashable, Codable, Sendable {
    public let appID: String
    public let name: String
    public let installDir: URL
    /// Set for games added by hand (any .exe anywhere); nil for Steam games.
    public let executable: URL?
    public var id: String { appID }

    public init(appID: String, name: String, installDir: URL, executable: URL? = nil) {
        self.appID = appID
        self.name = name
        self.installDir = installDir
        self.executable = executable
    }

    public var isCustom: Bool { executable != nil }

    public var headerImageURL: URL? {
        isCustom ? nil : URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/header.jpg")
    }
}

/// Finds games installed by the Windows Steam client inside a Wine prefix.
public struct SteamLibraryScanner: Sendable {
    /// Steamworks Common Redistributables and similar non-games.
    public static let ignoredAppIDs: Set<String> = ["228980"]

    public init() {}

    public func steamRoot(in prefix: URL) -> URL {
        prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
    }

    /// Maps `C:\Games\SteamLibrary` to `<prefix>/drive_c/Games/SteamLibrary`.
    /// Other drive letters go through `dosdevices/<x>:`.
    public static func hostPath(forWindowsPath path: String, prefix: URL) -> URL {
        let normalized = path.replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "\\", with: "/")
        let scalars = Array(normalized)
        guard scalars.count >= 2, scalars[1] == ":", scalars[0].isLetter else {
            return URL(fileURLWithPath: normalized, isDirectory: true)
        }
        let letter = String(scalars[0]).lowercased()
        let rest = String(scalars.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = letter == "c"
            ? prefix.appendingPathComponent("drive_c", isDirectory: true)
            : prefix.appendingPathComponent("dosdevices/\(letter):", isDirectory: true)
        return rest.isEmpty ? base : base.appendingPathComponent(rest, isDirectory: true)
    }

    public func libraryFolders(prefix: URL, fileManager: FileManager = .default) -> [URL] {
        let root = steamRoot(in: prefix)
        var folders = [root]
        let vdf = root.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let text = try? String(contentsOf: vdf, encoding: .utf8),
           let parsed = try? VDFParser.parse(text),
           let entries = parsed["libraryfolders"]?.objectValue {
            for key in entries.keys.sorted() {
                let entry = entries[key]!
                // Modern format: "0" { "path" "C:\\..." }; legacy: "1" "D:\\..."
                let raw = entry["path"]?.stringValue ?? (Int(key) != nil ? entry.stringValue : nil)
                guard let raw else { continue }
                let url = Self.hostPath(forWindowsPath: raw, prefix: prefix)
                if !folders.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                    folders.append(url)
                }
            }
        }
        return folders
    }

    public func scan(prefix: URL, fileManager: FileManager = .default) -> [SteamGame] {
        var games: [String: SteamGame] = [:]
        for library in libraryFolders(prefix: prefix, fileManager: fileManager) {
            let steamapps = library.appendingPathComponent("steamapps", isDirectory: true)
            guard let files = try? fileManager.contentsOfDirectory(atPath: steamapps.path) else { continue }
            for file in files where file.hasPrefix("appmanifest_") && file.hasSuffix(".acf") {
                let url = steamapps.appendingPathComponent(file)
                guard let text = try? String(contentsOf: url, encoding: .utf8),
                      let parsed = try? VDFParser.parse(text),
                      let state = parsed["appstate"],
                      let appID = state["appid"]?.stringValue,
                      !Self.ignoredAppIDs.contains(appID) else { continue }
                let name = state["name"]?.stringValue ?? "App \(appID)"
                let dir = steamapps.appendingPathComponent("common", isDirectory: true)
                    .appendingPathComponent(state["installdir"]?.stringValue ?? name, isDirectory: true)
                games[appID] = SteamGame(appID: appID, name: name, installDir: dir)
            }
        }
        return games.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
