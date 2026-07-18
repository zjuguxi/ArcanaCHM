import Foundation
import XCTest
@testable import ArcanaCHM

final class SerializationFormatTests: XCTestCase {
    func testReaderEncoderProducesCompactRoundtrippableJSON() throws {
        var book = Book.empty(title: "Book", rootURL: URL(fileURLWithPath: "/tmp/book"))
        book.importedAt = Date(timeIntervalSince1970: 1_000)
        let library = LibraryFile(schemaVersion: 2, books: [book])

        let data = try JSONEncoder.reader.encode(library)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder.reader.decode(LibraryFile.self, from: data)

        XCTAssertFalse(json.contains("\n"), "persisted library JSON should remain compact")
        XCTAssertEqual(decoded.schemaVersion, library.schemaVersion)
        XCTAssertEqual(decoded.books, library.books)
    }
}
