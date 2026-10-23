import XCTest
@testable import BlockbottleCore

final class BottleStoreTests: XCTestCase {
    var root: URL!
    var store: BottleStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("bb-\(UUID().uuidString)")
        let paths = AppPaths(root: root)
        try paths.ensureDirectories()
        store = BottleStore(paths: paths)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testCreateListRoundTrip() throws {
        let b = try store.create(name: "Steam")
        let listed = store.list().compactMap(\.bottle)
        XCTAssertEqual(listed.map(\.id), [b.id])
        XCTAssertEqual(listed.first?.name, "Steam")
        XCTAssertEqual(listed.first?.prefix.standardizedFileURL.path, b.prefix.standardizedFileURL.path)
    }

    func testCorruptMetadataListedAsDamaged() throws {
        let b = try store.create(name: "Bad")
        try "{".write(to: b.prefix.appendingPathComponent("bottle.json"), atomically: true, encoding: .utf8)
        guard case .damaged = try XCTUnwrap(store.list().first) else { return XCTFail("expected damaged") }
    }

    func testDeleteRemovesDirectory() throws {
        let b = try store.create(name: "Gone")
        try store.delete(b.prefix)
        XCTAssertTrue(store.list().isEmpty)
        XCTAssertThrowsError(try store.delete(root))
    }

    func testOldBottleWithoutEngineDecodesAsStaging() throws {
        let b = try store.create(name: "Old")
        let legacy = #"{"createdAt":"2026-10-23T14:00:00Z","id":"\#(b.id.uuidString)","name":"Old","windowsVersion":"win10"}"#
        try legacy.write(to: b.prefix.appendingPathComponent("bottle.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(store.list().first?.bottle?.engine, .staging)
        let gptk = try store.create(name: "D3DMetal", engine: .gptk)
        XCTAssertEqual(store.list().compactMap(\.bottle).first { $0.id == gptk.id }?.engine, .gptk)
    }
}
