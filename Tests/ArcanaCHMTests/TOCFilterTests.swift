import XCTest
@testable import ArcanaCHM

final class TOCFilterTests: XCTestCase {
    var root: TOCItem!
    var childA: TOCItem!
    var childB: TOCItem!
    var grandchild: TOCItem!

    override func setUp() {
        super.setUp()
        grandchild = TOCItem(id: UUID(), title: "Grandchild Topic", path: "grandchild.html", children: [])
        childA = TOCItem(id: UUID(), title: "Chapter Alpha", path: "alpha.html", children: [grandchild])
        childB = TOCItem(id: UUID(), title: "Chapter Beta", path: "beta.html", children: [])
        root = TOCItem(id: UUID(), title: "Root", path: nil, children: [childA, childB])
    }

    func testEmptyQueryReturnsAll() {
        let result = TOCView.filter(items: [root], query: "")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].children.count, 2)
    }

    func testWhitespaceQueryReturnsAll() {
        let result = TOCView.filter(items: [root], query: "   ")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].children.count, 2)
    }

    func testUnmatchedQueryReturnsEmpty() {
        let result = TOCView.filter(items: [root], query: "zzzzzz")
        XCTAssertTrue(result.isEmpty)
    }

    func testMatchesChildKeepsParentChain() {
        let result = TOCView.filter(items: [root], query: "alpha")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Root")
        XCTAssertEqual(result[0].children.count, 1)
        XCTAssertEqual(result[0].children[0].title, "Chapter Alpha")
        XCTAssertEqual(result[0].children[0].children.count, 1)
    }

    func testMatchesGrandchildKeepsFullParentChain() {
        let result = TOCView.filter(items: [root], query: "grandchild")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Root")
        XCTAssertEqual(result[0].children.count, 1)
        XCTAssertEqual(result[0].children[0].title, "Chapter Alpha")
        XCTAssertEqual(result[0].children[0].children.count, 1)
        XCTAssertEqual(result[0].children[0].children[0].title, "Grandchild Topic")
    }

    func testCaseInsensitiveMatch() {
        let result = TOCView.filter(items: [root], query: "ALPHA")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].children.count, 1)
        XCTAssertEqual(result[0].children[0].title, "Chapter Alpha")
    }

    func testPartialMatch() {
        let result = TOCView.filter(items: [root], query: "hap")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].children[0].title, "Chapter Alpha")
    }

    func testMultipleMatchesAllChildrenPreserved() {
        let result = TOCView.filter(items: [root], query: "Chapter")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].children.count, 2)
    }

    func testWhitespaceTrimmed() {
        let result = TOCView.filter(items: [root], query: "  Chapter  ")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].children.count, 2)
    }

    func testFilterOnFlatList() {
        let items = [childA!, childB!]
        let result = TOCView.filter(items: items, query: "Beta")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Chapter Beta")
    }

    func testParentItselfMatchesKeepsAllChildren() {
        let items = [TOCItem(id: UUID(), title: "Installation Guide", path: nil, children: [
            TOCItem(id: UUID(), title: "Windows", path: "win.html", children: []),
            TOCItem(id: UUID(), title: "macOS", path: "mac.html", children: []),
        ])]
        let result = TOCView.filter(items: items, query: "Installation")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].children.count, 2)
    }
}
