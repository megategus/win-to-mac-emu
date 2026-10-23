import Foundation

public enum StorageProblem: Error, Equatable, Sendable {
    /// The external volume holding the root is not mounted.
    case volumeMissing(String)
    case notWritable
    /// Wine prefixes need symlinks and POSIX permissions (APFS / HFS+ only).
    case unsupportedFilesystem(String)

    public var message: String {
        switch self {
        case .volumeMissing(let name):
            return "World not found — plug in \(name)"
        case .notWritable:
            return "Blockbottle can't write to this folder."
        case .unsupportedFilesystem(let fs):
            return "This drive is formatted as \(fs.uppercased()). Wine needs APFS or Mac OS Extended — reformat it in Disk Utility."
        }
    }
}

public struct StorageValidator: Sendable {
    public static let supportedFilesystems: Set<String> = ["apfs", "hfs"]

    public var fsTypeProvider: @Sendable (URL) -> String?

    public init(fsTypeProvider: @escaping @Sendable (URL) -> String? = StorageValidator.filesystemType(of:)) {
        self.fsTypeProvider = fsTypeProvider
    }

    /// Returns nil when `root` is usable. Never creates anything on a missing volume.
    public func validate(_ root: URL, fileManager: FileManager = .default) -> StorageProblem? {
        if let volume = Self.volumeRoot(of: root), !fileManager.fileExists(atPath: volume.path) {
            return .volumeMissing(volume.lastPathComponent)
        }
        let existing = Self.nearestExistingAncestor(of: root, fileManager: fileManager)
        if let fs = fsTypeProvider(existing)?.lowercased(), !Self.supportedFilesystems.contains(fs) {
            return .unsupportedFilesystem(fs)
        }
        if !fileManager.isWritableFile(atPath: existing.path) {
            return .notWritable
        }
        return nil
    }

    /// `/Volumes/<Name>` for paths on an external volume, nil otherwise.
    public static func volumeRoot(of url: URL) -> URL? {
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count >= 3, parts[0] == "/", parts[1] == "Volumes" else { return nil }
        return URL(fileURLWithPath: "/Volumes/\(parts[2])", isDirectory: true)
    }

    static func nearestExistingAncestor(of url: URL, fileManager: FileManager) -> URL {
        var current = url.standardizedFileURL
        while !fileManager.fileExists(atPath: current.path), current.path != "/" {
            current = current.deletingLastPathComponent()
        }
        return current
    }

    public static func filesystemType(of url: URL) -> String? {
        #if canImport(Darwin)
        var info = statfs()
        guard statfs(url.path, &info) == 0 else { return nil }
        return withUnsafePointer(to: &info.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { String(cString: $0) }
        }
        #else
        return nil
        #endif
    }
}
