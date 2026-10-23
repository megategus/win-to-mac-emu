import XCTest
@testable import BlockbottleCore

final class VDFParserTests: XCTestCase {
    func testParsesNestedObjects() throws {
        let text = """
        "AppState"
        {
            "appid"     "220"
            // comment
            "UserConfig" { "language" "english" }
        }
        """
        let v = try VDFParser.parse(text)
        XCTAssertEqual(v["appstate"]?["appid"]?.stringValue, "220")
        XCTAssertEqual(v["appstate"]?["userconfig"]?["language"]?.stringValue, "english")
    }

    func testQuotedValuesWithEscapesAndUnicode() throws {
        let text = #""AppState" { "name" "Half-Life 2: \"Ep\" Ω" "path" "C:\\Games\\HL 2" }"#
        let v = try VDFParser.parse(text)
        XCTAssertEqual(v["appstate"]?["name"]?.stringValue, "Half-Life 2: \"Ep\" Ω")
        XCTAssertEqual(v["appstate"]?["path"]?.stringValue, "C:\\Games\\HL 2")
    }

    func testUnterminatedObjectThrows() {
        XCTAssertThrowsError(try VDFParser.parse(#""a" { "b" "c""#))
    }
}
