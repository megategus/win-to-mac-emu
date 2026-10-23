import XCTest
@testable import BlockbottleCore

final class SteamLibraryScannerTests: XCTestCase {
    var prefix: URL!

    override func setUpWithError() throws {
        prefix = FileManager.default.temporaryDirectory.appendingPathComponent("prefix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: prefix)
    }

    private func write(_ text: String, to relative: String) throws {
        let url = prefix.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func manifest(_ id: String, _ name: String, _ dir: String) -> String {
        "\"AppState\"\n{\n\t\"appid\"\t\"\(id)\"\n\t\"name\"\t\"\(name)\"\n\t\"installdir\"\t\"\(dir)\"\n}\n"
    }

    func testScansAllLibraryFolders() throws {
        let steam = "drive_c/Program Files (x86)/Steam/steamapps"
        try write("""
        "libraryfolders"
        {
            "0" { "path" "C:\\\\Program Files (x86)\\\\Steam" }
            "1" { "path" "C:\\\\Games\\\\SteamLibrary" }
        }
        """, to: "\(steam)/libraryfolders.vdf")
        try write(manifest("620", "Portal 2", "Portal 2"), to: "\(steam)/appmanifest_620.acf")
        try write(manifest("70", "Half-Life", "Half-Life"), to: "drive_c/Games/SteamLibrary/steamapps/appmanifest_70.acf")

        let games = SteamLibraryScanner().scan(prefix: prefix)
        XCTAssertEqual(games.map(\.appID), ["70", "620"])
        XCTAssertEqual(games[0].installDir.path,
                       prefix.appendingPathComponent("drive_c/Games/SteamLibrary/steamapps/common/Half-Life").path)
    }

    func testSkipsRedistributables() throws {
        let steam = "drive_c/Program Files (x86)/Steam/steamapps"
        try write(manifest("228980", "Steamworks Common Redistributables", "Steamworks Shared"), to: "\(steam)/appmanifest_228980.acf")
        try write(manifest("400", "Portal", "Portal"), to: "\(steam)/appmanifest_400.acf")
        XCTAssertEqual(SteamLibraryScanner().scan(prefix: prefix).map(\.appID), ["400"])
    }

    func testOtherDriveLettersUseDosdevices() {
        let url = SteamLibraryScanner.hostPath(forWindowsPath: "D:\\Lib", prefix: prefix)
        XCTAssertEqual(url.path, prefix.appendingPathComponent("dosdevices/d:/Lib").path)
    }
}
