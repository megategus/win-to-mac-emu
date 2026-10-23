import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct ResolvedAsset: Equatable, Sendable {
    public let url: URL
    public let name: String
    public let sha256: String?
}

public enum EngineError: Error, Equatable {
    case noMatchingAsset(String)
    case checksumMismatch
    case extractFailed(Int32)
}

/// Downloads, verifies and unpacks engine components into `Engines/`.
public struct EngineManager: Sendable {
    public let paths: AppPaths
    let http: HTTPClient
    let runner: ProcessRunner

    public init(paths: AppPaths, http: HTTPClient, runner: ProcessRunner) {
        self.paths = paths
        self.http = http
        self.runner = runner
    }

    public func installURL(_ c: EngineComponent) -> URL {
        paths.engines.appendingPathComponent(c.installDir, isDirectory: true)
    }

    public func isInstalled(_ c: EngineComponent) -> Bool {
        FileManager.default.fileExists(atPath: installURL(c).appendingPathComponent(".version").path)
    }

    public func installedVersion(_ c: EngineComponent) -> String? {
        try? String(contentsOf: installURL(c).appendingPathComponent(".version"), encoding: .utf8)
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let digest: String?
        }
        let assets: [Asset]
    }

    public func resolve(_ c: EngineComponent) async throws -> ResolvedAsset {
        let data = try await http.data(from: c.latestReleaseAPI)
        let release = try JSONDecoder().decode(Release.self, from: data)
        let regex = try NSRegularExpression(pattern: c.assetPattern)
        guard let asset = release.assets.first(where: {
            regex.firstMatch(in: $0.name, range: NSRange($0.name.startIndex..., in: $0.name)) != nil
        }) else {
            throw EngineError.noMatchingAsset(c.repo)
        }
        let sha = asset.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
        return ResolvedAsset(url: asset.browser_download_url, name: asset.name, sha256: sha)
    }

    public func install(_ c: EngineComponent, progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = try await resolve(c)
        let file = try await http.download(from: asset.url, progress: progress)
        defer { try? FileManager.default.removeItem(at: file) }
        try verify(file, expected: asset.sha256)
        try await extract(file, to: installURL(c))
        try asset.name.write(to: installURL(c).appendingPathComponent(".version"), atomically: true, encoding: .utf8)
        if c.id == "d3dmetal" { try mergeD3DMetalIntoWine() }
    }

    /// Deletes the file on mismatch. A nil checksum means GitHub didn't publish one.
    public func verify(_ file: URL, expected: String?) throws {
        guard let expected else { return }
        if try Self.sha256(of: file) != expected {
            try? FileManager.default.removeItem(at: file)
            throw EngineError.checksumMismatch
        }
    }

    func extract(_ archive: URL, to destination: URL) async throws {
        let fm = FileManager.default
        let staging = paths.engines.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let tar = WineInvocation(executable: URL(fileURLWithPath: "/usr/bin/tar"),
                                 arguments: ["-xf", archive.path, "-C", staging.path])
        let code = try await runner.run(tar, logTo: nil)
        guard code == 0 else { throw EngineError.extractFailed(code) }
        let items = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
        let source = items.count == 1 && items[0].hasDirectoryPath ? items[0] : staging
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: source, to: destination)
    }

    /// Whisky-style integration: GPTK's `lib` tree overlays Wine's `lib`.
    func mergeD3DMetalIntoWine() throws {
        let fm = FileManager.default
        let gptkRoot = paths.engines.appendingPathComponent("D3DMetal", isDirectory: true)
        let wineRoot = paths.engines.appendingPathComponent("Wine", isDirectory: true)
        guard let gptkLib = EngineLayout.find("lib/external", under: gptkRoot)?.deletingLastPathComponent(),
              let wineLib = EngineLayout.find("lib/wine", under: wineRoot)?.deletingLastPathComponent() else { return }
        try EngineLayout.overlay(gptkLib, onto: wineLib, fileManager: fm)
    }

    public static func sha256(of url: URL) throws -> String {
        #if canImport(CryptoKit)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        fatalError("SHA-256 requires CryptoKit")
        #endif
    }
}

enum EngineLayout {
    /// Finds `<dir>/<relative>` for some `dir` at most `depth` levels under `root`.
    static func find(_ relative: String, under root: URL, depth: Int = 4) -> URL? {
        let fm = FileManager.default
        var frontier = [root]
        for _ in 0...depth {
            var next: [URL] = []
            for dir in frontier {
                let candidate = dir.appendingPathComponent(relative)
                if fm.fileExists(atPath: candidate.path) { return candidate }
                let children = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
                next += children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            }
            frontier = next
        }
        return nil
    }

    static func overlay(_ source: URL, onto dest: URL, fileManager fm: FileManager) throws {
        guard let walker = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        let base = source.standardizedFileURL.path
        for case let item as URL in walker {
            let rel = String(item.standardizedFileURL.path.dropFirst(base.count + 1))
            let target = dest.appendingPathComponent(rel)
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
               item.pathExtension != "framework" {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: item, to: target)
            if item.pathExtension == "framework" { walker.skipDescendants() }
        }
    }
}
