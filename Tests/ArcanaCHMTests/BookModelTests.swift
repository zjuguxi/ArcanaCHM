import XCTest
@testable import ArcanaCHM

final class BookModelTests: XCTestCase {

    func testBookCodableRoundtrip() throws {
        let book = Book(
            id: UUID(),
            title: "Test Book",
            rootPath: "/tmp/test",
            homePath: "index.html",
            importedAt: Date(),
            toc: [
                TOCItem(title: "Chapter 1", path: "ch1.html", children: [
                    TOCItem(title: "Section 1.1", path: "ch1s1.html")
                ])
            ],
            bookmarks: [
                Bookmark(id: UUID(), title: "My Bookmark", path: "ch1.html", scrollY: 42, createdAt: Date())
            ],
            lastReadPath: "ch1.html",
            contentFingerprint: nil,
            isPinned: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(book)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Book.self, from: data)

        XCTAssertEqual(book.id, decoded.id)
        XCTAssertEqual(book.title, decoded.title)
        XCTAssertEqual(book.rootPath, decoded.rootPath)
        XCTAssertEqual(book.homePath, decoded.homePath)
        XCTAssertEqual(book.toc.count, decoded.toc.count)
        XCTAssertEqual(book.toc.first?.title, decoded.toc.first?.title)
        XCTAssertEqual(book.toc.first?.children.count, decoded.toc.first?.children.count)
        XCTAssertEqual(book.bookmarks.count, decoded.bookmarks.count)
        XCTAssertEqual(book.lastReadPath, decoded.lastReadPath)
        XCTAssertEqual(book.isPinned, decoded.isPinned)
    }

    func testBookEmptyFactory() {
        let url = URL(fileURLWithPath: "/tmp/test")
        let book = Book.empty(title: "Empty Book", rootURL: url)

        XCTAssertEqual(book.title, "Empty Book")
        XCTAssertEqual(book.rootPath, url.path)
        XCTAssertNil(book.homePath)
        XCTAssertTrue(book.toc.isEmpty)
        XCTAssertTrue(book.bookmarks.isEmpty)
        XCTAssertNil(book.lastReadPath)
        XCTAssertNil(book.contentFingerprint)
        XCTAssertNil(book.isPinned)
    }

    func testBookRootURL() {
        let book = Book.empty(title: "Test", rootURL: URL(fileURLWithPath: "/tmp/test"))
        XCTAssertEqual(book.rootURL.path, "/tmp/test")
    }

}
