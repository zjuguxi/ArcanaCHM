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

    func testSearch_findsContentInHTML() async throws {
        let book = try makeBook(files: [
            "page.html": "<html><body>The quick brown fox jumps over the lazy dog</body></html>"
        ])
        let hits = await service.search("fox", in: book)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].path, "page.html")
        XCTAssertTrue(hits[0].snippet.lowercased().contains("fox"))
    }

    func testSearch_caseInsensitive() async throws {
        let book = try makeBook(files: [
            "doc.html": "<html><body>Hello World</body></html>"
        ])
        let count1 = await service.search("hello", in: book).count
        let count2 = await service.search("HELLO", in: book).count
        let count3 = await service.search("Hello", in: book).count
        XCTAssertEqual(count1, 1)
        XCTAssertEqual(count2, 1)
        XCTAssertEqual(count3, 1)
    }

    func testSearch_noMatchReturnsEmpty() async throws {
        let book = try makeBook(files: [
            "page.html": "<html><body>Nothing to see here</body></html>"
        ])
        let hits = await service.search("zzzzzzz", in: book)
        XCTAssertTrue(hits.isEmpty)
    }

    func testSearch_matchesTitleInMultipleFiles() async throws {
        let book = try makeBook(files: [
            "a.html": "<html><head><title>Alpha</title></head><body>apple banana</body></html>",
            "b.html": "<html><body>banana cherry</body></html>",
            "c.html": "<html><body>cherry apple</body></html>",
        ])
        let hits = await service.search("banana", in: book)
        XCTAssertEqual(hits.count, 2)
    }

    // MARK: - Title extraction

    func testSearch_extractsTitleFromTag() async throws {
        let book = try makeBook(files: [
            "page.html": "<html><head><title>My Document</title></head><body>content here</body></html>"
        ])
        let hits = await service.search("content", in: book)
        XCTAssertEqual(hits[0].title, "My Document")
    }

    func testSearch_fallbackTitleWhenNoTitleTag() async throws {
        let book = try makeBook(files: [
            "my-page.html": "<html><body>searchable text</body></html>"
        ])
        let hits = await service.search("searchable", in: book)
        XCTAssertEqual(hits[0].title, "my-page")
    }

    // MARK: - Filtering

    func testSearch_ignoresNonHTMLFiles() async throws {
        let book = try makeBook(files: [
            "content.html": "<html><body>secret text</body></html>",
            "notes.txt": "secret text here too",
            "script.js": "secret = true",
        ])
        let count = await service.search("secret", in: book).count
        XCTAssertEqual(count, 1)
    }

    func testSearch_ignoresSymlinks() async throws {
        let book = try makeBook(files: [
            "real.html": "<html><body>real content</body></html>",
        ])
        try FileManager.default.createSymbolicLink(
            at: book.rootURL.appendingPathComponent("fake.html"),
            withDestinationURL: book.rootURL.appendingPathComponent("real.html")
        )
        let hits = await service.search("real", in: book)
        XCTAssertEqual(hits.count, 1)
    }

    // MARK: - Snippet

    func testSearch_snippetContainsMatch() async throws {
        let longText = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " +
            "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. " +
            "Ut enim ad minim veniam, quis nostrud exercitation."
        let book = try makeBook(files: [
            "long.html": "<html><body>\(longText)</body></html>"
        ])
        let hits = await service.search("incididunt", in: book)
        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(hits[0].snippet.contains("incididunt"))
    }

    func testSearch_stripsHTMLTagsFromSnippet() async throws {
        let book = try makeBook(files: [
            "styled.html": "<html><body><b>bold</b> and <i>italic</i> text</body></html>"
        ])
        let hits = await service.search("italic", in: book)
        XCTAssertEqual(hits.count, 1)
        XCTAssertFalse(hits[0].snippet.contains("<"))
    }

    func testSearch_decodesEntitiesInSnippet() async throws {
        let book = try makeBook(files: [
            "ents.html": "<html><body>R&amp;D and &lt;tag&gt;</body></html>"
        ])
        let hits = await service.search("tag", in: book)
        XCTAssertEqual(hits.count, 1)
        let snippet = hits[0].snippet
        XCTAssertTrue(snippet.contains("<"), "entities should be decoded so <tag> becomes <tag>")
    }

}
