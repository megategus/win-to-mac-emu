import XCTest
@testable import BlockbottleCore

final class SteamDiagnosticsTests: XCTestCase {
    var root: URL!
    var paths: AppPaths!
    var bottle: Bottle!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bb-\(UUID().uuidString)")
        paths = AppPaths(root: root)
        try paths.ensureDirectories()
        bottle = try BottleStore(paths: paths).create(name: "Steam")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testSteamLaunchKeepsWineErrorsInLog() throws {
        let fake = FakeProcessRunner()
        _ = try GameRunner(paths: paths, runner: fake).launchSteam(bottle: bottle)
        // "-all" would silence every Wine error and leave the log empty.
        XCTAssertEqual(fake.invocations.last?.environment["WINEDEBUG"], "fixme-all")
    }

    func testSteamRunningProbeUsesPgrep() async {
        let fake = FakeProcessRunner()
        fake.exitCode = { _ in 0 }
        let running = await SteamProcessProbe(runner: fake).isRunning()
        XCTAssertTrue(running)
        XCTAssertEqual(fake.invocations.last?.executable.path, "/usr/bin/pgrep")
        XCTAssertEqual(fake.invocations.last?.arguments, ["-if", "steam\\.exe"])

        fake.exitCode = { _ in 1 }
        let stopped = await SteamProcessProbe(runner: fake).isRunning()
        XCTAssertFalse(stopped)
    }

    func testReportIncludesSteamAndLaunchLogTails() throws {
        let steamLogs = SteamLibraryScanner().steamRoot(in: bottle.prefix).appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: steamLogs, withIntermediateDirectories: true)
        try (1...200).map { "bootstrap line \($0)" }.joined(separator: "\n")
            .write(to: steamLogs.appendingPathComponent("bootstrap_log.txt"), atomically: true, encoding: .utf8)
        let launchLogs = paths.logs.appendingPathComponent(bottle.id.uuidString)
        try FileManager.default.createDirectory(at: launchLogs, withIntermediateDirectories: true)
        try "err:module:import_dll Library X not found".write(
            to: launchLogs.appendingPathComponent("20261023-150000-steam.log"), atomically: true, encoding: .utf8)

        let report = SteamDiagnostics(paths: paths).report(bottle: bottle)
        XCTAssertTrue(report.contains("steam.exe: MISSING"))
        XCTAssertTrue(report.contains("bootstrap line 200"))
        XCTAssertFalse(report.contains("bootstrap line 1\n"))   // tail only
        XCTAssertTrue(report.contains("err:module:import_dll Library X not found"))
        XCTAssertTrue(report.contains(paths.root.path))
    }
}
