import XCTest
@testable import ArcanaCHM

final class EncodingTests: XCTestCase {

    // MARK: - UTF-8

    func testReadText_utf8() throws {
        let text = "Hello, 世界!"
        let url = try createTempFile(content: text, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(readText(url), text)
    }

    func testReadText_utf8WithBOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("Hello, 世界!".data(using: .utf8)!)
        let url = try writeTempFile(data: data)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(readText(url), "Hello, 世界!")
    }

    // MARK: - UTF-16

    func testReadText_utf16LE() throws {
        let text = "Hello, 世界!"
        var data = Data([0xFF, 0xFE])
        data.append(text.data(using: .utf16LittleEndian)!)
        let url = try writeTempFile(data: data)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(readText(url), text)
    }

    func testReadText_utf16BE() throws {
        let text = "Hello, 世界!"
        var data = Data([0xFE, 0xFF])
        data.append(text.data(using: .utf16BigEndian)!)
        let url = try writeTempFile(data: data)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(readText(url), text)
    }

    // MARK: - CJK encodings (reliable auto-detect requires BOM or meta charset)

    func testReadText_shiftJIS() throws {
        let text = "日本語テスト"
        let url = try createTempFile(content: text, encoding: .shiftJIS)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(readText(url), text)
    }

    // MARK: - Meta charset

    func testReadText_metaCharset_gbk() throws {
        let header = "<html><head><meta charset=\"gbk\"></head><body>"
        let footer = "</body></html>"
        let chinese = "中文测试"

        var data = Data(header.utf8)
        data.append(try XCTUnwrap(chinese.data(using: .gb18030)))
        data.append(Data(footer.utf8))

        let url = try writeTempFile(data: data)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(readText(url), header + chinese + footer)
    }

    func testReadText_metaContentType_big5() throws {
        let header = "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=big5\"></head><body>"
        let footer = "</body></html>"
        let chinese = "中文測試"

        var data = Data(header.utf8)
        data.append(try XCTUnwrap(chinese.data(using: .big5)))
        data.append(Data(footer.utf8))

        let url = try writeTempFile(data: data)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(readText(url), header + chinese + footer)
    }

    func testReadText_metaCharset_shiftJIS() throws {
        let header = "<html><head><meta charset=\"shiftJIS\"></head><body>"
        let footer = "</body></html>"
        let japanese = "日本語テスト"

        var data = Data(header.utf8)
        data.append(try XCTUnwrap(japanese.data(using: .shiftJIS)))
        data.append(Data(footer.utf8))

        let url = try writeTempFile(data: data)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(readText(url), header + japanese + footer)
    }

    // MARK: - Edge cases

    func testReadText_emptyFile() throws {
        let url = try createTempFile(content: "", encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(readText(url))
    }

    func testReadText_whitespaceOnly() throws {
        let url = try createTempFile(content: "   \n  ", encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(readText(url))
    }

    func testReadText_binaryData() throws {
        let data = Data([0x00, 0x01, 0x02, 0xFF, 0xFE])
        let url = try writeTempFile(data: data)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = readText(url)
        XCTAssertNotNil(result, "binary data may decode as lossy encoding, should not crash")
    }

    func testReadText_nonExistentFile() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_chm_test_file_xyz")
        XCTAssertNil(readText(url))
    }

    // MARK: - Encoding constants

    func testEncodingBig5() {
        let text = "中文測試"
        let encoded = text.data(using: .big5)
        XCTAssertNotNil(encoded)
        let decoded = String(data: encoded!, encoding: .big5)
        XCTAssertEqual(decoded, text)
    }

    func testEncodingShiftJIS() {
        let text = "日本語テスト"
        let encoded = text.data(using: .shiftJIS)
        XCTAssertNotNil(encoded)
        let decoded = String(data: encoded!, encoding: .shiftJIS)
        XCTAssertEqual(decoded, text)
    }

    // MARK: - HTML Entity Decoding

    func testDecodeEntities_named() {
        XCTAssertEqual(decodeEntities("&lt;div&gt;"), "<div>")
        XCTAssertEqual(decodeEntities("&amp;quot;"), "&quot;")
        XCTAssertEqual(decodeEntities("&copy; 2024"), "\u{00A9} 2024")
        XCTAssertEqual(decodeEntities("&mdash;"), "\u{2014}")
        XCTAssertEqual(decodeEntities("&amp;amp;"), "&amp;")
        XCTAssertEqual(decodeEntities("&amp;"), "&")
    }

    func testDecodeEntities_numeric() {
        XCTAssertEqual(decodeEntities("&#169;"), "\u{00A9}")
        XCTAssertEqual(decodeEntities("&#x00A9;"), "\u{00A9}")
        XCTAssertEqual(decodeEntities("&#x00a9;"), "\u{00A9}")
        XCTAssertEqual(decodeEntities("&#60;"), "<")
    }

    func testDecodeEntities_noChange() {
        XCTAssertEqual(decodeEntities("hello world"), "hello world")
        XCTAssertEqual(decodeEntities(""), "")
        XCTAssertEqual(decodeEntities("no entities here"), "no entities here")
    }

    func testDecodeEntities_mixed() {
        let input = "&lt;b&gt;hello &amp; &mdash; &#169; 2024&copy;&lt;/b&gt;"
        let expected = "<b>hello & \u{2014} \u{00A9} 2024\u{00A9}</b>"
        XCTAssertEqual(decodeEntities(input), expected)
    }

    func testDecodeEntities_doubleAmpersand() {
        XCTAssertEqual(decodeEntities("&amp;amp;lt;"), "&amp;lt;")
    }

    func testDecodeEntities_trade() {
        XCTAssertEqual(decodeEntities("&trade;"), "\u{2122}")
    }

    func testDecodeEntities_hellip() {
        XCTAssertEqual(decodeEntities("continue&hellip;"), "continue\u{2026}")
    }

    // MARK: - Helpers

    private func createTempFile(content: String, encoding: String.Encoding) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chmtest_\(UUID().uuidString).html")
        try content.write(to: url, atomically: true, encoding: encoding)
        return url
    }

    private func writeTempFile(data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chmtest_\(UUID().uuidString).bin")
        try data.write(to: url)
        return url
    }
}
