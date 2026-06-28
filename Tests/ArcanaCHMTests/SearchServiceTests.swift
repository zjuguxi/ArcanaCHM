import XCTest
@testable import ArcanaCHM

final class SearchServiceTests: XCTestCase {

    private let service = SearchService()

    private func makeBook(files: [String: String]) throws -> Book {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("search-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        for (path, content) in files {
            let url = dir.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }

        return Book.empty(title: "Test", rootURL: dir)
    }

    // MARK: - Basic matching

    func testSearch_findsContentInHTML() throws {
        let book = try makeBook(files: [
            "page.html": "<html><body>The quick brown fox jumps over the lazy dog</body></html>"
        ])
        let hits = service.search("fox", in: book)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].path, "page.html")
        XCTAssertTrue(hits[0].snippet.lowercased().contains("fox"))
    }

    func testSearch_caseInsensitive() throws {
        let book = try makeBook(files: [
            "doc.html": "<html><body>Hello World</body></html>"
        ])
        XCTAssertEqual(service.search("hello", in: book).count, 1)
        XCTAssertEqual(service.search("HELLO", in: book).count, 1)
        XCTAssertEqual(service.search("Hello", in: book).count, 1)
    }

    func testSearch_noMatchReturnsEmpty() throws {
        let book = try makeBook(files: [
            "page.html": "<html><body>Nothing to see here</body></html>"
        ])
        XCTAssertTrue(service.search("zzzzzzz", in: book).isEmpty)
    }

    func testSearch_matchesTitleInMultipleFiles() throws {
        let book = try makeBook(files: [
            "a.html": "<html><head><title>Alpha</title></head><body>apple banana</body></html>",
            "b.html": "<html><body>banana cherry</body></html>",
            "c.html": "<html><body>cherry apple</body></html>",
        ])
        let hits = service.search("banana", in: book)
        XCTAssertEqual(hits.count, 2)
    }

    // MARK: - Title extraction

    func testSearch_extractsTitleFromTag() throws {
        let book = try makeBook(files: [
            "page.html": "<html><head><title>My Document</title></head><body>content here</body></html>"
        ])
        let hits = service.search("content", in: book)
        XCTAssertEqual(hits[0].title, "My Document")
    }

    func testSearch_fallbackTitleWhenNoTitleTag() throws {
        let book = try makeBook(files: [
            "my-page.html": "<html><body>searchable text</body></html>"
        ])
        let hits = service.search("searchable", in: book)
        XCTAssertEqual(hits[0].title, "my-page")
    }

    // MARK: - Filtering

    func testSearch_ignoresNonHTMLFiles() throws {
        let book = try makeBook(files: [
            "content.html": "<html><body>secret text</body></html>",
            "notes.txt": "secret text here too",
            "script.js": "secret = true",
        ])
        XCTAssertEqual(service.search("secret", in: book).count, 1)
    }

    func testSearch_ignoresSymlinks() throws {
        let book = try makeBook(files: [
            "real.html": "<html><body>real content</body></html>",
        ])
        try FileManager.default.createSymbolicLink(
            at: book.rootURL.appendingPathComponent("fake.html"),
            withDestinationURL: book.rootURL.appendingPathComponent("real.html")
        )
        // Only real.html should be found
        let hits = service.search("real", in: book)
        XCTAssertEqual(hits.count, 1)
    }

    // MARK: - Snippet

    func testSearch_snippetContainsMatch() throws {
        let longText = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " +
            "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " +
            "Ut enim ad minim veniam, quis nostrud exercitation."
        let book = try makeBook(files: [
            "long.html": "<html><body>\(longText)</body></html>"
        ])
        let hits = service.search("incididunt", in: book)
        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(hits[0].snippet.contains("incididunt"))
    }

    func testSearch_stripsHTMLTagsFromSnippet() throws {
        let book = try makeBook(files: [
            "styled.html": "<html><body><b>bold</b> and <i>italic</i> text</body></html>"
        ])
        let hits = service.search("italic", in: book)
        XCTAssertEqual(hits.count, 1)
        XCTAssertFalse(hits[0].snippet.contains("<"))
    }

    func testSearch_decodesEntitiesInSnippet() throws {
        let book = try makeBook(files: [
            "ents.html": "<html><body>R&amp;D and &lt;tag&gt;</body></html>"
        ])
        let hits = service.search("tag", in: book)
        XCTAssertEqual(hits.count, 1)
        let snippet = hits[0].snippet
        XCTAssertTrue(snippet.contains("<"), "entities should be decoded so <tag> becomes <tag>")
    }

}
