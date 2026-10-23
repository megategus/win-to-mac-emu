import XCTest
@testable import BlockbottleCore

final class AppPathsTests: XCTestCase {
    func testDirectoriesAreUnderRoot() {
        let root = URL(fileURLWithPath: "/Volumes/Untitled/Blockbottle")
        let paths = AppPaths(root: root)
        XCTAssertEqual(paths.engines.path, "/Volumes/Untitled/Blockbottle/Engines")
        XCTAssertEqual(paths.bottles.path, "/Volumes/Untitled/Blockbottle/Bottles")
        XCTAssertEqual(paths.logs.path, "/Volumes/Untitled/Blockbottle/Logs")
        XCTAssertEqual(paths.profiles.path, "/Volumes/Untitled/Blockbottle/Profiles")
    }

    func testUnsupportedFilesystemRejected() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        XCTAssertEqual(StorageValidator(fsTypeProvider: { _ in "exfat" }).validate(tmp),
                       .unsupportedFilesystem("exfat"))
        XCTAssertNil(StorageValidator(fsTypeProvider: { _ in "apfs" }).validate(tmp))
        XCTAssertNil(StorageValidator(fsTypeProvider: { _ in "hfs" }).validate(tmp))
    }

    func testMissingVolumeIsReportedNotCreated() {
        let root = URL(fileURLWithPath: "/Volumes/DefinitelyMissing/Blockbottle")
        let problem = StorageValidator(fsTypeProvider: { _ in "apfs" }).validate(root)
        XCTAssertEqual(problem, .volumeMissing("DefinitelyMissing"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testVolumeRoot() {
        XCTAssertEqual(StorageValidator.volumeRoot(of: URL(fileURLWithPath: "/Volumes/Untitled/a/b"))?.path,
                       "/Volumes/Untitled")
        XCTAssertNil(StorageValidator.volumeRoot(of: URL(fileURLWithPath: "/Users/me/x")))
    }
}
