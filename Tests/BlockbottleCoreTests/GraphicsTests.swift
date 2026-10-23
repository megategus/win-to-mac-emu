import XCTest
@testable import BlockbottleCore

final class GraphicsTests: XCTestCase {
    var root: URL!
    var paths: AppPaths!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bb-\(UUID().uuidString)")
        paths = AppPaths(root: root)
        try paths.ensureDirectories()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testRecommendedBackends() {
        XCTAssertEqual(GraphicsBackend.recommended(for: .dx12), .d3dmetal)
        XCTAssertEqual(GraphicsBackend.recommended(for: .dx11), .dxmt)
        XCTAssertEqual(GraphicsBackend.recommended(for: .dx10), .dxmt)
        XCTAssertEqual(GraphicsBackend.recommended(for: .dx9), .dxvk)
        XCTAssertEqual(GraphicsBackend.recommended(for: .unknown), .d3dmetal)
    }

    func testDXMTOverrides() throws {
        try FileManager.default.createDirectory(at: paths.engines.appendingPathComponent("DXMT"), withIntermediateDirectories: true)
        var profile = GameProfile()
        profile.backend = .dxmt
        let inv = WineEnvironment(paths: paths).invocation(prefix: root, profile: profile, program: ["game.exe"])
        let overrides = try XCTUnwrap(inv.environment["WINEDLLOVERRIDES"])
        for dll in ["d3d11", "dxgi", "d3d10core"] { XCTAssertTrue(overrides.contains(dll)) }
        XCTAssertTrue(overrides.hasSuffix("=n,b"))
    }

    func testMissingBackendFallsBackToWineD3D() {
        let env = WineEnvironment(paths: paths)
        let r = env.resolve(.dxmt)
        XCTAssertEqual(r.backend, .wined3d)
        XCTAssertTrue(r.fellBack)
        var profile = GameProfile()
        profile.backend = .dxvk
        XCTAssertNil(env.invocation(prefix: root, profile: profile, program: []).environment["WINEDLLOVERRIDES"])
        XCTAssertFalse(env.resolve(.wined3d).fellBack)
    }

    func testEnvironmentFlags() {
        var profile = GameProfile()
        profile.backend = .wined3d
        profile.metalHUD = true
        profile.msync = true
        let inv = WineEnvironment(paths: paths).invocation(prefix: root, profile: profile, program: ["a.exe"])
        XCTAssertEqual(inv.environment["WINEPREFIX"], root.standardizedFileURL.path)
        XCTAssertEqual(inv.environment["MTL_HUD_ENABLED"], "1")
        XCTAssertEqual(inv.environment["WINEMSYNC"], "1")
        XCTAssertEqual(inv.arguments, ["a.exe"])
        profile.msync = false
        profile.metalHUD = false
        let off = WineEnvironment(paths: paths).invocation(prefix: root, profile: profile, program: [])
        XCTAssertNil(off.environment["WINEMSYNC"])
        XCTAssertNil(off.environment["MTL_HUD_ENABLED"])
    }

    func testCorruptProfileReturnsDefault() throws {
        let store = ProfileStore(paths: paths)
        try "not json".write(to: paths.profiles.appendingPathComponent("42.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(store.load(id: "42"), GameProfile())
        var p = GameProfile()
        p.backend = .dxvk
        p.launchArguments = "-dx11 -windowed"
        try store.save(p, id: "42")
        XCTAssertEqual(store.load(id: "42"), p)
        XCTAssertEqual(p.argumentList, ["-dx11", "-windowed"])
    }

    func testPrepareCopiesDLLsByArch() throws {
        let fm = FileManager.default
        let dxvk = paths.engines.appendingPathComponent("DXVK/dxvk-1.0")
        for (dir, dll) in [("x64", "d3d11.dll"), ("x32", "d3d9.dll")] {
            let d = dxvk.appendingPathComponent(dir)
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: d.appendingPathComponent(dll))
        }
        let prefix = root.appendingPathComponent("prefix")
        try BackendInstaller(paths: paths).prepare(.dxvk, prefix: prefix)
        try BackendInstaller(paths: paths).prepare(.dxvk, prefix: prefix) // idempotent
        XCTAssertTrue(fm.fileExists(atPath: prefix.appendingPathComponent("drive_c/windows/system32/d3d11.dll").path))
        XCTAssertTrue(fm.fileExists(atPath: prefix.appendingPathComponent("drive_c/windows/syswow64/d3d9.dll").path))
    }
}
