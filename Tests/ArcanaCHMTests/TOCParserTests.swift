import XCTest
@testable import ArcanaCHM

final class TOCParserTests: XCTestCase {

    private func createHHCFile(_ content: String) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("toc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }
        try content.write(to: tmp.appendingPathComponent("test.hhc"), atomically: true, encoding: .utf8)
        return tmp
    }

    private func createHTMLFiles(_ names: [String], in dir: URL) throws {
        for name in names {
            try "<html><body>\(name)</body></html>".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Parse

    func testParse_singleItem() throws {
        let dir = try createHHCFile(#"""
        <html><body>
        <ul><li><object type="text/sitemap">
        <param name="Name" value="Chapter 1">
        <param name="Local" value="ch1.html">
        </object></ul>
        </body></html>
        """#)
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertEqual(toc.count, 1)
        XCTAssertEqual(toc[0].title, "Chapter 1")
        XCTAssertEqual(toc[0].path, "ch1.html")
    }

    func testParse_nestedItems() throws {
        let dir = try createHHCFile(#"""
        <ul>
          <li><object><param name="Name" value="Ch1"><param name="Local" value="ch1.html"></object>
          <ul>
            <li><object><param name="Name" value="S1.1"><param name="Local" value="s1.html"></object></li>
            <li><object><param name="Name" value="S1.2"><param name="Local" value="s2.html"></object></li>
          </ul>
          <li><object><param name="Name" value="Ch2"><param name="Local" value="ch2.html"></object></li>
        </ul>
        """#)
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertEqual(toc.count, 2)
        XCTAssertEqual(toc[0].title, "Ch1")
        XCTAssertEqual(toc[0].children.count, 2)
        XCTAssertEqual(toc[0].children[0].title, "S1.1")
        XCTAssertEqual(toc[0].children[0].path, "s1.html")
        XCTAssertEqual(toc[1].title, "Ch2")
    }

    func testParse_reverseParamOrder() throws {
        let dir = try createHHCFile(#"""
        <ul><li><object><param name="Local" value="page.html"><param name="Name" value="My Page"></object></ul>
        """#)
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertEqual(toc.count, 1)
        XCTAssertEqual(toc[0].title, "My Page")
        XCTAssertEqual(toc[0].path, "page.html")
    }

    func testParse_titleFallback() throws {
        let dir = try createHHCFile(#"""
        <ul><li><object><param name="Title" value="Fallback"><param name="Local" value="f.html"></object></ul>
        """#)
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertEqual(toc[0].title, "Fallback")
    }

    func testParse_noLocalParam() throws {
        let dir = try createHHCFile(#"""
        <ul><li><object><param name="Name" value="No Path"></object></ul>
        """#)
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertEqual(toc.count, 1)
        XCTAssertEqual(toc[0].title, "No Path")
        XCTAssertNil(toc[0].path)
    }

    func testParse_emptyNameReturnsNil() throws {
        let dir = try createHHCFile(#"""
        <ul><li><object><param name="Name" value=""><param name="Local" value="x.html"></object></ul>
        """#)
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertTrue(toc.isEmpty)
    }

    func testParse_noNameParam() throws {
        let dir = try createHHCFile(#"""
        <ul><li><object><param name="Local" value="x.html"></object></ul>
        """#)
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertTrue(toc.isEmpty)
    }

    func testParse_htmlEntityDecoding() throws {
        let dir = try createHHCFile(#"""
        <ul><li><object><param name="Name" value="R&amp;D &lt;Test&gt;"><param name="Local" value="rd.html"></object></ul>
        """#)
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertEqual(toc[0].title, "R&D <Test>")
    }

    func testParse_malformedHtml() throws {
        let dir = try createHHCFile("<ul><li>no object here</ul>")
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertTrue(toc.isEmpty)
    }

    func testParse_emptyString() throws {
        let dir = try createHHCFile("")
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertTrue(toc.isEmpty)
    }

    // MARK: - UL with attributes

    func testParse_dotDotPaths_areResolved() throws {
        let dir = try createHHCFile(#"""
        <ul><li><object><param name="Name" value="Genesis"><param name="Local" value="../B01C001.htm"></object></ul>
        """#)
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertEqual(toc.count, 1)
        XCTAssertEqual(toc[0].title, "Genesis")
        XCTAssertEqual(toc[0].path, "B01C001.htm")
    }

    func testParse_nestedDotDotPaths_areResolved() throws {
        let dir = try createHHCFile(#"""
        <ul><li><object><param name="Name" value="Nested"><param name="Local" value="sub/../../page.html"></object></ul>
        """#)
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertEqual(toc.count, 1)
        XCTAssertEqual(toc[0].title, "Nested")
        XCTAssertEqual(toc[0].path, "page.html")
    }

    func testParse_dotDotWithHash_areResolved() throws {
        let dir = try createHHCFile(#"""
        <ul><li><object><param name="Name" value="Section"><param name="Local" value="../page.html#sec"></object></ul>
        """#)
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertEqual(toc.count, 1)
        XCTAssertEqual(toc[0].title, "Section")
        XCTAssertEqual(toc[0].path, "page.html")
    }

    func testParse_ulWithClassAttribute_itemsStillParsed() throws {
        let dir = try createHHCFile(#"""
        <html><body>
        <ul class="sitemap">
        <li><object type="text/sitemap">
        <param name="Name" value="Chapter 1">
        <param name="Local" value="ch1.html">
        </object></li>
        </ul>
        </body></html>
        """#)
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertEqual(toc.count, 1)
        XCTAssertEqual(toc[0].title, "Chapter 1")
        XCTAssertEqual(toc[0].path, "ch1.html")
    }

    func testParse_ulWithTypeAttribute_itemsStillParsed() throws {
        let dir = try createHHCFile(#"""
        <ul type="sitemap">
        <li><object><param name="Name" value="Topic"><param name="Local" value="topic.html"></object></li>
        </ul>
        """#)
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertEqual(toc.count, 1)
        XCTAssertEqual(toc[0].title, "Topic")
    }

    func testParse_nestedUlWithAttributes_preservesNesting() throws {
        let dir = try createHHCFile(#"""
        <ul class="level1">
        <li><object><param name="Name" value="Parent"><param name="Local" value="p.html"></object>
        <ul class="level2">
        <li><object><param name="Name" value="Child"><param name="Local" value="c.html"></object></li>
        </ul>
        </li>
        </ul>
        """#)
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertEqual(toc.count, 1)
        XCTAssertEqual(toc[0].title, "Parent")
        XCTAssertEqual(toc[0].children.count, 1)
        XCTAssertEqual(toc[0].children[0].title, "Child")
    }

    func testParse_ulWithIdAttribute() throws {
        let dir = try createHHCFile(#"""
        <ul id="toc">
        <li><object><param name="Name" value="Item A"><param name="Local" value="a.html"></object></li>
        </ul>
        """#)
        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertEqual(toc.count, 1)
        XCTAssertEqual(toc[0].title, "Item A")
    }

    // MARK: - Fallback TOC

    func testFallbackTOC_noHHCFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("toc-fallback-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        try createHTMLFiles(["a.html", "b.html", "c.htm"], in: dir)

        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertEqual(toc.count, 3)
        let titles = toc.map(\.title).sorted()
        XCTAssertEqual(titles, ["a", "b", "c"])
    }

    func testFallbackTOC_filtersNonHTML() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("toc-filter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        try createHTMLFiles(["a.html", "b.txt", "c.png"], in: dir)

        let toc = TOCParser(rootURL: dir).parse()
        XCTAssertEqual(toc.count, 1)
        XCTAssertEqual(toc[0].title, "a")
    }

    // MARK: - homePath

    func testHomePath_firstItem() {
        let items = [TOCItem(title: "C1", path: "c1.html"), TOCItem(title: "C2", path: "c2.html")]
        let parser = TOCParser(rootURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(parser.homePath(from: items), "c1.html")
    }

    func testHomePath_nestedChild() {
        let items = [TOCItem(title: "Parent", path: nil, children: [
            TOCItem(title: "Child", path: "child.html")
        ])]
        let parser = TOCParser(rootURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(parser.homePath(from: items), "child.html")
    }

    func testHomePath_nilWhenEmpty() {
        let parser = TOCParser(rootURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertNil(parser.homePath(from: []))
    }

    func testHomePath_skipNilPathItems() {
        let items = [TOCItem(title: "No Path", path: nil)]
        let parser = TOCParser(rootURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertNil(parser.homePath(from: items))
    }
}
