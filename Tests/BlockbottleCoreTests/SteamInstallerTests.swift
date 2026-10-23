import XCTest
@testable import BlockbottleCore

final class SteamInstallerTests: XCTestCase {
    func testInstallRunsWinebootThenSetup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bb-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        try paths.ensureDirectories()
        let bottle = try BottleStore(paths: paths).create(name: "Steam")
        let installer = SteamInstaller(paths: paths, runner: FakeProcessRunner(), http: FakeHTTPClient())

        // Simulate the silent installer creating steam.exe.
        let fake = FakeProcessRunner()
        let exe = installer.steamExe(in: bottle)
        fake.onRun = { inv in
            if inv.arguments.last == "/S" {
                try? FileManager.default.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: exe.path, contents: Data())
            }
        }
        let real = SteamInstaller(paths: paths, runner: fake, http: FakeHTTPClient())
        try await real.install(bottle: bottle) { _ in }

        let args = fake.invocations.map(\.arguments)
        XCTAssertEqual(args.first, ["wineboot", "--init"])
        XCTAssertEqual(args.last?.last, "/S")
        XCTAssertTrue(args.last?.first?.hasSuffix("SteamSetup.exe") ?? false)
        XCTAssertEqual(fake.invocations.first?.environment["WINEPREFIX"], bottle.prefix.path)
        XCTAssertTrue(real.isInstalled(bottle: bottle))
    }

    func testSetupWithoutSteamExeFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bb-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        try paths.ensureDirectories()
        let bottle = try BottleStore(paths: paths).create(name: "Steam")
        do {
            try await SteamInstaller(paths: paths, runner: FakeProcessRunner(), http: FakeHTTPClient()).install(bottle: bottle) { _ in }
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? SteamInstallError, .steamMissingAfterInstall)
        }
    }

    func testBlockedIDs() {
        XCTAssertTrue(AntiCheatList.isBlocked("1172470"))
        XCTAssertFalse(AntiCheatList.isBlocked("620"))
    }
}
