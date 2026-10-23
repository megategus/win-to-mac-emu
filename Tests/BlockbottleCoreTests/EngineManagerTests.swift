import XCTest
@testable import BlockbottleCore

final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    var json = Data()
    var jsonByURL: [String: Data] = [:]
    var payload = Data()
    func data(from url: URL) async throws -> Data { jsonByURL[url.absoluteString] ?? json }
    func download(from url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString)")
        try payload.write(to: f)
        progress(1)
        return f
    }
}

final class EngineManagerTests: XCTestCase {
    var root: URL!
    var paths: AppPaths!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bb-\(UUID().uuidString)")
        paths = AppPaths(root: root)
        try paths.ensureDirectories()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    let releaseJSON = """
    {"assets":[
      {"name":"README.md","browser_download_url":"https://example.com/readme","digest":null},
      {"name":"game-porting-toolkit-3.0-3.tar.xz","browser_download_url":"https://example.com/gptk.tar.xz","digest":"sha256:ABCDEF"}
    ]}
    """

    func testResolvePicksMatchingAsset() async throws {
        let http = FakeHTTPClient()
        http.json = Data(releaseJSON.utf8)
        let m = EngineManager(paths: paths, http: http, runner: FakeProcessRunner())
        let asset = try await m.resolve(EngineManifest.gptk)
        XCTAssertEqual(asset.name, "game-porting-toolkit-3.0-3.tar.xz")
        XCTAssertEqual(asset.url.absoluteString, "https://example.com/gptk.tar.xz")
        XCTAssertEqual(asset.sha256, "abcdef")
    }

    /// Real asset names from Gcenx/macOS_Wine_builds 11.18.
    func testWinePicksStagingNotDevel() async throws {
        let http = FakeHTTPClient()
        http.json = Data("""
        {"assets":[
          {"name":"wine-devel-11.18-osx64.tar.xz","browser_download_url":"https://e.com/devel","digest":null},
          {"name":"wine-staging-11.18-osx64.tar.xz","browser_download_url":"https://e.com/staging","digest":null}
        ]}
        """.utf8)
        let asset = try await EngineManager(paths: paths, http: http, runner: FakeProcessRunner()).resolve(EngineManifest.wine)
        XCTAssertEqual(asset.name, "wine-staging-11.18-osx64.tar.xz")
    }

    func testMigrationMovesOldGPTKOutOfWineFolder() throws {
        let fm = FileManager.default
        let oldWine = paths.engines.appendingPathComponent("Wine")
        try fm.createDirectory(at: oldWine.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try "game-porting-toolkit-3.0-3.tar.xz".write(to: oldWine.appendingPathComponent(".version"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: paths.engines.appendingPathComponent("Wine-originals"), withIntermediateDirectories: true)

        EngineManifest.migrate(paths: paths)
        let m = EngineManager(paths: paths, http: FakeHTTPClient(), runner: FakeProcessRunner())
        XCTAssertFalse(m.isInstalled(EngineManifest.wine))   // staging must now be downloaded
        XCTAssertTrue(m.isInstalled(EngineManifest.gptk))
        XCTAssertTrue(fm.fileExists(atPath: paths.engines.appendingPathComponent("GPTK-originals").path))

        EngineManifest.migrate(paths: paths) // idempotent
        XCTAssertTrue(m.isInstalled(EngineManifest.gptk))
    }

    func testRealAssetNamesMatch() throws {
        let cases: [(EngineComponent, String)] = [
            (EngineManifest.wine, "wine-staging-11.18-osx64.tar.xz"),
            (EngineManifest.gptk, "game-porting-toolkit-3.0-3.tar.xz"),
            (EngineManifest.dxmt, "dxmt-v0.80-builtin.tar.gz"),
            (EngineManifest.dxvk, "dxvk-macOS-async-v1.10.3-20230507-repack-builtin.tar.gz"),
        ]
        for (component, name) in cases {
            let regex = try NSRegularExpression(pattern: component.sources[0].assetPattern)
            XCTAssertNotNil(regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)), name)
        }
    }

    func testNoMatchingAssetThrows() async {
        let http = FakeHTTPClient()
        http.json = Data(#"{"assets":[{"name":"readme.txt","browser_download_url":"https://e.com/r","digest":null}]}"#.utf8)
        let m = EngineManager(paths: paths, http: http, runner: FakeProcessRunner())
        do {
            _ = try await m.resolve(EngineManifest.dxmt)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? EngineError, .noMatchingAsset("3Shain/dxmt"))
        }
    }

    func testChecksumMismatchDeletesFile() throws {
        let f = root.appendingPathComponent("partial.tar.xz")
        try Data("half a download".utf8).write(to: f)
        let m = EngineManager(paths: paths, http: FakeHTTPClient(), runner: FakeProcessRunner())
        XCTAssertThrowsError(try m.verify(f, expected: String(repeating: "0", count: 64))) {
            XCTAssertEqual($0 as? EngineError, .checksumMismatch)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.path))
    }

    func testSHA256KnownValue() throws {
        let f = root.appendingPathComponent("abc")
        try Data("abc".utf8).write(to: f)
        XCTAssertEqual(try EngineManager.sha256(of: f),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let m = EngineManager(paths: paths, http: FakeHTTPClient(), runner: FakeProcessRunner())
        XCTAssertNoThrow(try m.verify(f, expected: nil))
    }

    func testInstallExtractsWithRealTar() async throws {
        // Build a tiny tar.gz with one top-level folder and install it with the real runner.
        let src = root.appendingPathComponent("src/dxmt-v1")
        try FileManager.default.createDirectory(at: src.appendingPathComponent("x86_64-windows"), withIntermediateDirectories: true)
        try Data("dll".utf8).write(to: src.appendingPathComponent("x86_64-windows/d3d11.dll"))
        let archive = root.appendingPathComponent("dxmt-v1-builtin.tar.gz")
        let code = try await SystemProcessRunner().run(
            WineInvocation(executable: URL(fileURLWithPath: "/usr/bin/tar"),
                           arguments: ["-czf", archive.path, "-C", src.deletingLastPathComponent().path, "dxmt-v1"]), logTo: nil)
        XCTAssertEqual(code, 0)

        let http = FakeHTTPClient()
        http.json = Data(#"{"assets":[{"name":"dxmt-v1-builtin.tar.gz","browser_download_url":"https://e.com/d","digest":null}]}"#.utf8)
        http.payload = try Data(contentsOf: archive)
        let m = EngineManager(paths: paths, http: http, runner: SystemProcessRunner())
        let dxmt = EngineManifest.dxmt
        try await m.install(dxmt) { _ in }
        XCTAssertTrue(m.isInstalled(dxmt))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.engines.appendingPathComponent("DXMT/x86_64-windows/d3d11.dll").path))
        XCTAssertEqual(m.installedVersion(dxmt), "dxmt-v1-builtin.tar.gz")
    }
}
