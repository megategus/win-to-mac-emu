import XCTest
@testable import BlockbottleCore

final class CustomGameTests: XCTestCase {
    var root: URL!
    var paths: AppPaths!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bb-\(UUID().uuidString)")
        paths = AppPaths(root: root)
        try paths.ensureDirectories()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testCustomGameStoreRoundTrip() throws {
        let store = CustomGameStore(paths: paths)
        let exe = URL(fileURLWithPath: "/Volumes/Untitled/Games/My Game/game.exe")
        let game = try store.add(executable: exe, name: "My Game")
        XCTAssertTrue(game.appID.hasPrefix("custom-"))
        XCTAssertEqual(store.list(), [game])
        XCTAssertEqual(store.list().first?.executable, exe)
        XCTAssertNil(game.headerImageURL)
        try store.remove(appID: game.appID)
        XCTAssertTrue(store.list().isEmpty)
    }

    func testLaunchCustomExeRunsFromItsOwnFolder() async throws {
        let fake = FakeProcessRunner()
        let bottle = try BottleStore(paths: paths).create(name: "B")
        let exe = URL(fileURLWithPath: "/Volumes/Untitled/Games/My Game/bin/game.exe")
        let game = try CustomGameStore(paths: paths).add(executable: exe, name: "My Game")
        var profile = GameProfile()
        profile.launchArguments = "-windowed"
        _ = try await GameRunner(paths: paths, runner: fake).launch(game: game, bottle: bottle, profile: profile)
        let inv = try XCTUnwrap(fake.invocations.last)
        XCTAssertEqual(inv.arguments, [exe.path, "-windowed"])
        XCTAssertEqual(inv.workingDirectory?.path, "/Volumes/Untitled/Games/My Game/bin")
        XCTAssertEqual(inv.environment["WINEPREFIX"], bottle.prefix.path)
    }

    func testCustomGamesFilteredByBottle() throws {
        let store = CustomGameStore(paths: paths)
        let a = UUID(), b = UUID()
        try store.add(executable: URL(fileURLWithPath: "/g/a.exe"), name: "A", bottleID: a)
        try store.add(executable: URL(fileURLWithPath: "/g/b.exe"), name: "B", bottleID: b)
        try store.add(executable: URL(fileURLWithPath: "/g/any.exe"), name: "Any")
        XCTAssertEqual(store.list(bottleID: a).map(\.name), ["A", "Any"])
        XCTAssertEqual(store.list().count, 3)
    }
}
