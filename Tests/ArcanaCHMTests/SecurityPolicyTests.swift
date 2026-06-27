import XCTest
@testable import ArcanaCHM

final class SecurityPolicyTests: XCTestCase {

    // MARK: - safeRelativePath

    func testSafeRelativePath_basicPath() {
        XCTAssertEqual(SecurityPolicy.safeRelativePath("foo/bar.html"), "foo/bar.html")
    }

    func testSafeRelativePath_stripsLeadingSlash() {
        // Leading slash is stripped, not rejected — path is normalized to relative
        XCTAssertEqual(SecurityPolicy.safeRelativePath("/foo/bar.html"), "foo/bar.html")
    }

    func testSafeRelativePath_stripsHashFragment() {
        XCTAssertEqual(SecurityPolicy.safeRelativePath("foo/bar.html#section1"), "foo/bar.html")
    }

    func testSafeRelativePath_stripsQueryString() {
        XCTAssertEqual(SecurityPolicy.safeRelativePath("foo/bar.html?param=1"), "foo/bar.html")
    }

    func testSafeRelativePath_rejectsDotDot() {
        XCTAssertNil(SecurityPolicy.safeRelativePath("foo/../../etc/passwd"))
    }

    func testSafeRelativePath_rejectsDotComponent() {
        XCTAssertNil(SecurityPolicy.safeRelativePath("./foo/bar.html"))
    }

    func testSafeRelativePath_rejectsTilde() {
        XCTAssertNil(SecurityPolicy.safeRelativePath("~/foo/bar.html"))
    }

    func testSafeRelativePath_rejectsURLScheme() {
        XCTAssertNil(SecurityPolicy.safeRelativePath("http://evil.com/foo.html"))
    }

    func testSafeRelativePath_convertsBackslashes() {
        XCTAssertEqual(SecurityPolicy.safeRelativePath("foo\\bar.html"), "foo/bar.html")
    }

    func testSafeRelativePath_decodedPercentEncoding() {
        XCTAssertEqual(SecurityPolicy.safeRelativePath("foo%20bar.html"), "foo bar.html")
    }

    func testSafeRelativePath_emptyReturnsNil() {
        XCTAssertNil(SecurityPolicy.safeRelativePath(""))
        XCTAssertNil(SecurityPolicy.safeRelativePath("   "))
    }

    func testSafeRelativePath_rejectsHTTPScheme() {
        XCTAssertNil(SecurityPolicy.safeRelativePath("https://evil.com/foo"))
    }

    func testSafeRelativePath_rejectsJavaScriptScheme() {
        XCTAssertNil(SecurityPolicy.safeRelativePath("javascript:alert(1)"))
    }

    // MARK: - isDescendant

    func testIsDescendant_sameURL() {
        let root = URL(fileURLWithPath: "/tmp/books")
        XCTAssertTrue(SecurityPolicy.isDescendant(root, of: root))
    }

    func testIsDescendant_subdirectory() {
        let root = URL(fileURLWithPath: "/tmp/books")
        let child = URL(fileURLWithPath: "/tmp/books/chm1/index.html")
        XCTAssertTrue(SecurityPolicy.isDescendant(child, of: root))
    }

    func testIsDescendant_sibling() {
        let root = URL(fileURLWithPath: "/tmp/books/book1")
        let sibling = URL(fileURLWithPath: "/tmp/books/book2")
        XCTAssertFalse(SecurityPolicy.isDescendant(sibling, of: root))
    }

    func testIsDescendant_parent() {
        let root = URL(fileURLWithPath: "/tmp/books/book1")
        let parent = URL(fileURLWithPath: "/tmp/books")
        XCTAssertFalse(SecurityPolicy.isDescendant(parent, of: root))
    }

    func testIsDescendant_unrelated() {
        let root = URL(fileURLWithPath: "/tmp/books")
        let unrelated = URL(fileURLWithPath: "/etc/passwd")
        XCTAssertFalse(SecurityPolicy.isDescendant(unrelated, of: root))
    }

    // MARK: - safeFileURL

    func testSafeFileURL_validPath() {
        let root = URL(fileURLWithPath: "/tmp/books/testbook")
        let result = SecurityPolicy.safeFileURL(rootURL: root, relativePath: "index.html")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.path, "/tmp/books/testbook/index.html")
    }

    func testSafeFileURL_rejectsDotDot() {
        let root = URL(fileURLWithPath: "/tmp/books/testbook")
        XCTAssertNil(SecurityPolicy.safeFileURL(rootURL: root, relativePath: "../index.html"))
    }

    func testSafeFileURL_rejectsNilPath() {
        let root = URL(fileURLWithPath: "/tmp/books/testbook")
        XCTAssertNil(SecurityPolicy.safeFileURL(rootURL: root, relativePath: nil))
    }

    func testSafeFileURL_nestedSubdirectory() {
        let root = URL(fileURLWithPath: "/tmp/books/testbook")
        let result = SecurityPolicy.safeFileURL(rootURL: root, relativePath: "subdir/page.html")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.path, "/tmp/books/testbook/subdir/page.html")
    }

    // MARK: - relativePath

    func testRelativePath_insideRoot() {
        let root = URL(fileURLWithPath: "/tmp/books/testbook")
        let file = URL(fileURLWithPath: "/tmp/books/testbook/index.html")
        XCTAssertEqual(SecurityPolicy.relativePath(for: file, rootURL: root), "index.html")
    }

    func testRelativePath_outsideRoot() {
        let root = URL(fileURLWithPath: "/tmp/books/testbook")
        let file = URL(fileURLWithPath: "/tmp/other/file.html")
        XCTAssertNil(SecurityPolicy.relativePath(for: file, rootURL: root))
    }

    func testRelativePath_nestedFile() {
        let root = URL(fileURLWithPath: "/tmp/books/testbook")
        let file = URL(fileURLWithPath: "/tmp/books/testbook/subdir/page.html")
        XCTAssertEqual(SecurityPolicy.relativePath(for: file, rootURL: root), "subdir/page.html")
    }

    func testRelativePath_rootItself() {
        let root = URL(fileURLWithPath: "/tmp/books/testbook")
        XCTAssertEqual(SecurityPolicy.relativePath(for: root, rootURL: root), "")
    }

    // MARK: - readableExtensions

    func testReadableExtensions() {
        XCTAssertTrue(SecurityPolicy.readableExtensions.contains("html"))
        XCTAssertTrue(SecurityPolicy.readableExtensions.contains("htm"))
        XCTAssertTrue(SecurityPolicy.readableExtensions.contains("xhtml"))
    }
}

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

    func testTOCItemNestedChildren() {
        let child = TOCItem(title: "Child", path: "child.html")
        let parent = TOCItem(title: "Parent", path: "parent.html", children: [child])
        XCTAssertEqual(parent.children.count, 1)
        XCTAssertEqual(parent.children[0].title, "Child")
        XCTAssertEqual(parent.children[0].path, "child.html")
    }

}

final class SearchHitTests: XCTestCase {
    func testSearchHitCreation() {
        let hit = SearchHit(title: "Result", path: "page.html", snippet: "some text here")
        XCTAssertEqual(hit.title, "Result")
        XCTAssertEqual(hit.path, "page.html")
        XCTAssertEqual(hit.snippet, "some text here")
    }
}

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
