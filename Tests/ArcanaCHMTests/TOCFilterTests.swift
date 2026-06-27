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

    // MARK: - leafMatchIDs tests

    func testLeafMatchIDs_emptyQuery() {
        let result = TOCView.leafMatchIDs(in: [root], query: "")
        XCTAssertTrue(result.isEmpty)
    }

    func testLeafMatchIDs_noMatch() {
        let result = TOCView.leafMatchIDs(in: [root], query: "zzzzzz")
        XCTAssertTrue(result.isEmpty)
    }

    func testLeafMatchIDs_leafMatch() {
        let result = TOCView.leafMatchIDs(in: [root], query: "grandchild")
        XCTAssertEqual(result, [grandchild.id])
    }

    func testLeafMatchIDs_midLevelMatch() {
        let result = TOCView.leafMatchIDs(in: [root], query: "Alpha")
        XCTAssertEqual(result, [childA.id])
    }

    func testLeafMatchIDs_bothLevelsMatch() {
        let result = TOCView.leafMatchIDs(in: [root], query: "Topic")
        XCTAssertEqual(result, [grandchild.id])
    }

    func testLeafMatchIDs_multipleLeafMatches() {
        let result = TOCView.leafMatchIDs(in: [root], query: "Chapter")
        XCTAssertEqual(result, [childA.id, childB.id])
    }

    func testLeafMatchIDs_topLevelMatch() {
        let result = TOCView.leafMatchIDs(in: [root], query: "Root")
        XCTAssertEqual(result, [root.id])
    }

    // MARK: - expandedIDsForSearch tests

    func testExpandedIDs_emptyQuery() {
        let result = TOCView.expandedIDsForSearch(in: [root], query: "")
        XCTAssertTrue(result.isEmpty)
    }

    func testExpandedIDs_noMatch() {
        let result = TOCView.expandedIDsForSearch(in: [root], query: "zzzzzz")
        XCTAssertTrue(result.isEmpty)
    }

    func testExpandedIDs_leafMatch() {
        let result = TOCView.expandedIDsForSearch(in: [root], query: "grandchild")
        XCTAssertEqual(result, [childA.id, root.id])
    }

    func testExpandedIDs_midLevelMatch() {
        let result = TOCView.expandedIDsForSearch(in: [root], query: "Alpha")
        XCTAssertEqual(result, [root.id])
    }

    func testExpandedIDs_bothLevelsMatch() {
        let result = TOCView.expandedIDsForSearch(in: [root], query: "Topic")
        XCTAssertEqual(result, [childA.id, root.id])
    }

    func testExpandedIDs_topLevelMatch() {
        let result = TOCView.expandedIDsForSearch(in: [root], query: "Root")
        XCTAssertTrue(result.isEmpty)
    }

    func testExpandedIDs_multipleLeafMatches() {
        let result = TOCView.expandedIDsForSearch(in: [root], query: "Chapter")
        XCTAssertEqual(result, [root.id])
    }
}
