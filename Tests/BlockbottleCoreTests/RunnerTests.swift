import XCTest
@testable import BlockbottleCore

final class RunnerTests: XCTestCase {
    func testRosettaMissingReported() async {
        let fake = FakeProcessRunner()
        fake.exitCode = { inv in inv.executable.path == "/usr/bin/arch" ? 1 : 0 }
        let report = await SystemCheck(runner: fake, machine: { "arm64" },
                                       osVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)).report()
        XCTAssertFalse(report.rosetta)
        XCTAssertTrue(report.appleSilicon)
        XCTAssertTrue(report.macOSOK)
        XCTAssertFalse(report.allGood)

        let old = await SystemCheck(runner: FakeProcessRunner(), machine: { "x86_64" },
                                    osVersion: OperatingSystemVersion(majorVersion: 13, minorVersion: 6, patchVersion: 0)).report()
        XCTAssertFalse(old.appleSilicon)
        XCTAssertFalse(old.macOSOK)
    }

    func testLaunchBuildsApplaunchArgsAndLogPath() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bb-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        try paths.ensureDirectories()
        let fake = FakeProcessRunner()
        let fixed = Date(timeIntervalSince1970: 0)
        let runner = GameRunner(paths: paths, runner: fake, now: { fixed })
        let bottle = Bottle(name: "B", prefix: root.appendingPathComponent("Bottles/x"))
        var profile = GameProfile()
        profile.backend = .dxmt // not installed → falls back
        profile.launchArguments = "-windowed"
        let handle = try await runner.launch(game: SteamGame(appID: "620", name: "Portal 2", installDir: root),
                                             bottle: bottle, profile: profile)
        XCTAssertTrue(handle.fellBack)
        XCTAssertEqual(handle.backend, .wined3d)
        XCTAssertEqual(fake.invocations.last?.arguments, [GameRunner.steamExe, "-applaunch", "620", "-windowed"])
        XCTAssertTrue(handle.logURL.path.hasPrefix(paths.logs.appendingPathComponent(bottle.id.uuidString).path))
        XCTAssertTrue(handle.logURL.lastPathComponent.hasSuffix("-620.log"))
    }

    func testLogTailReturnsLastLines() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("log-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        try (1...100).map(String.init).joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        let tail = LogTail.lastLines(3, of: url)
        XCTAssertEqual(tail, "98\n99\n100")
    }
}
