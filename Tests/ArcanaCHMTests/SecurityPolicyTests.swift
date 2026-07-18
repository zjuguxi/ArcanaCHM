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

    func testSafeRelativePath_resolvesDotDot() {
        XCTAssertEqual(SecurityPolicy.safeRelativePath("foo/../../etc/passwd"), "etc/passwd")
    }

    func testSafeRelativePath_resolvesDotComponent() {
        XCTAssertEqual(SecurityPolicy.safeRelativePath("./foo/bar.html"), "foo/bar.html")
    }

    func testSafeRelativePath_resolvesLeadingDotDot() {
        XCTAssertEqual(SecurityPolicy.safeRelativePath("../B01C001.htm"), "B01C001.htm")
    }

    func testSafeRelativePath_resolvesMultipleLeadingDotDot() {
        XCTAssertEqual(SecurityPolicy.safeRelativePath("../../file.html"), "file.html")
    }

    func testSafeRelativePath_resolvesNestedDotDot() {
        XCTAssertEqual(SecurityPolicy.safeRelativePath("a/b/../c/d.html"), "a/c/d.html")
    }

    func testSafeRelativePath_resolvesDotDotWithHash() {
        XCTAssertEqual(SecurityPolicy.safeRelativePath("../page.html#section"), "page.html")
    }

    func testSafeRelativePath_allDotDotOnlyReturnsNil() {
        XCTAssertNil(SecurityPolicy.safeRelativePath(".."))
        XCTAssertNil(SecurityPolicy.safeRelativePath("../.."))
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

    func testSafeFileURL_resolvesDotDot() {
        let root = URL(fileURLWithPath: "/tmp/books/testbook")
        let result = SecurityPolicy.safeFileURL(rootURL: root, relativePath: "../index.html")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.path, "/tmp/books/testbook/index.html")
    }

    func testSafeFileURL_resolvesNestedDotDot() {
        let root = URL(fileURLWithPath: "/tmp/books/testbook")
        let result = SecurityPolicy.safeFileURL(rootURL: root, relativePath: "a/../../index.html")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.path, "/tmp/books/testbook/index.html")
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

    func testReaderRelativePathPreservesFragment() {
        let root = URL(fileURLWithPath: "/tmp/books/testbook")
        let file = URL(string: "file:///tmp/books/testbook/chapter.html#details")!

        XCTAssertEqual(
            SecurityPolicy.readerRelativePath(for: file, rootURL: root),
            "chapter.html#details"
        )
    }

    func testReaderRelativePathRejectsOutsideRoot() {
        let root = URL(fileURLWithPath: "/tmp/books/testbook")
        let file = URL(string: "file:///tmp/books/other/chapter.html#details")!

        XCTAssertNil(SecurityPolicy.readerRelativePath(for: file, rootURL: root))
    }

    func testDocumentPathStripsFragment() {
        XCTAssertEqual(SecurityPolicy.documentPath("chapter.html#details"), "chapter.html")
        XCTAssertEqual(SecurityPolicy.documentPath("chapter.html"), "chapter.html")
    }

    // MARK: - readableExtensions

    func testReadableExtensions() {
        XCTAssertTrue(SecurityPolicy.readableExtensions.contains("html"))
        XCTAssertTrue(SecurityPolicy.readableExtensions.contains("htm"))
        XCTAssertTrue(SecurityPolicy.readableExtensions.contains("xhtml"))
    }
}
