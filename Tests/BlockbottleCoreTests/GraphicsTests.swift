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
        XCTAssertTrue(overrides.hasSuffix("=b"))
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

    /// Mirrors the real layout of Gcenx's GPTK 3.0 download.
    private func makeWine(_ fm: FileManager) throws -> URL {
        let lib = paths.engines.appendingPathComponent("Wine/Contents/Resources/wine/lib")
        for dir in ["wine/x86_64-windows", "wine/i386-windows", "wine/x86_64-unix", "external/D3DMetal.framework"] {
            try fm.createDirectory(at: lib.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        try Data("d3dmetal".utf8).write(to: lib.appendingPathComponent("wine/x86_64-windows/d3d11.dll"))
        try Data("d3dmetal".utf8).write(to: lib.appendingPathComponent("wine/x86_64-windows/d3d12.dll"))
        return lib.appendingPathComponent("wine")
    }

    /// Mirrors dxmt-v0.80-builtin.tar.gz.
    private func makeDXMT(_ fm: FileManager) throws {
        let root = paths.engines.appendingPathComponent("DXMT/v0.80")
        for (dir, file) in [("x86_64-windows", "d3d11.dll"), ("x86_64-windows", "winemetal.dll"),
                            ("i386-windows", "d3d11.dll"), ("x86_64-unix", "winemetal.so")] {
            try fm.createDirectory(at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
            try Data("dxmt".utf8).write(to: root.appendingPathComponent("\(dir)/\(file)"))
        }
    }

    func testD3DMetalDetectedInsideWine() throws {
        XCTAssertFalse(WineEnvironment(paths: paths).installedBackends().contains(.d3dmetal))
        _ = try makeWine(.default)
        XCTAssertTrue(WineEnvironment(paths: paths).installedBackends().contains(.d3dmetal))
    }

    func testActivateDXMTOverlaysAndD3DMetalRestores() throws {
        let fm = FileManager.default
        let wine = try makeWine(fm)
        try makeDXMT(fm)
        let switcher = BackendSwitcher(paths: paths)

        try switcher.activate(.dxmt)
        XCTAssertEqual(try String(contentsOf: wine.appendingPathComponent("x86_64-windows/d3d11.dll")), "dxmt")
        XCTAssertTrue(fm.fileExists(atPath: wine.appendingPathComponent("x86_64-unix/winemetal.so").path))
        XCTAssertTrue(fm.fileExists(atPath: wine.appendingPathComponent("i386-windows/d3d11.dll").path))
        XCTAssertEqual(try String(contentsOf: wine.appendingPathComponent("x86_64-windows/d3d12.dll")), "d3dmetal")
        XCTAssertEqual(switcher.active, .dxmt)

        try switcher.activate(.dxmt) // no-op
        try switcher.activate(.d3dmetal)
        XCTAssertEqual(try String(contentsOf: wine.appendingPathComponent("x86_64-windows/d3d11.dll")), "d3dmetal")
        XCTAssertFalse(fm.fileExists(atPath: wine.appendingPathComponent("x86_64-unix/winemetal.so").path))
        XCTAssertFalse(fm.fileExists(atPath: wine.appendingPathComponent("i386-windows/d3d11.dll").path))
        XCTAssertEqual(switcher.active, .d3dmetal)

        try switcher.activate(.dxmt) // re-activating after a restore works again
        XCTAssertEqual(try String(contentsOf: wine.appendingPathComponent("x86_64-windows/d3d11.dll")), "dxmt")
    }
}
