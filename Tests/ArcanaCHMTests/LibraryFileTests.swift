import XCTest
@testable import ArcanaCHM

final class LibraryFileTests: XCTestCase {
    func testLibraryFileCodableRoundtrip() throws {
        let books = [
            Book.empty(title: "Book 1", rootURL: URL(fileURLWithPath: "/tmp/b1")),
            Book.empty(title: "Book 2", rootURL: URL(fileURLWithPath: "/tmp/b2"))
        ]
        let libraryFile = LibraryFile(schemaVersion: 1, books: books)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(libraryFile)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LibraryFile.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.books.count, 2)
        XCTAssertEqual(decoded.books[0].title, "Book 1")
        XCTAssertEqual(decoded.books[1].title, "Book 2")
    }

    func testLibraryFileBackwardCompatibleWithBareArray() throws {
        let books = [
            Book.empty(title: "Old Book", rootURL: URL(fileURLWithPath: "/tmp/old"))
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let oldData = try encoder.encode(books)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([Book].self, from: oldData)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].title, "Old Book")
    }
}
