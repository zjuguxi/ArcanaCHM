import Foundation
import Testing
@testable import ArcanaCHM

struct TOCFilterTests {
    let root: TOCItem
    let childA: TOCItem
    let childB: TOCItem
    let grandchild: TOCItem

    init() {
        grandchild = TOCItem(id: UUID(), title: "Grandchild Topic", path: "grandchild.html", children: [])
        childA = TOCItem(id: UUID(), title: "Chapter Alpha", path: "alpha.html", children: [grandchild])
        childB = TOCItem(id: UUID(), title: "Chapter Beta", path: "beta.html", children: [])
        root = TOCItem(id: UUID(), title: "Root", path: nil, children: [childA, childB])
    }

    @Test func emptyQueryReturnsAll() {
        let result = TOCView.filter(items: [root], query: "")
        #expect(result.count == 1)
        #expect(result[0].children.count == 2)
    }

    @Test func whitespaceQueryReturnsAll() {
        let result = TOCView.filter(items: [root], query: "   ")
        #expect(result.count == 1)
        #expect(result[0].children.count == 2)
    }

    @Test func unmatchedQueryReturnsEmpty() {
        let result = TOCView.filter(items: [root], query: "zzzzzz")
        #expect(result.isEmpty)
    }

    @Test func matchesChildKeepsParentChain() {
        let result = TOCView.filter(items: [root], query: "alpha")
        #expect(result.count == 1)
        #expect(result[0].title == "Root")
        #expect(result[0].children.count == 1)
        #expect(result[0].children[0].title == "Chapter Alpha")
        #expect(result[0].children[0].children.count == 1)
    }

    @Test func matchesGrandchildKeepsFullParentChain() {
        let result = TOCView.filter(items: [root], query: "grandchild")
        #expect(result.count == 1)
        #expect(result[0].title == "Root")
        #expect(result[0].children.count == 1)
        #expect(result[0].children[0].title == "Chapter Alpha")
        #expect(result[0].children[0].children.count == 1)
        #expect(result[0].children[0].children[0].title == "Grandchild Topic")
    }

    @Test func caseInsensitiveMatch() {
        let result = TOCView.filter(items: [root], query: "ALPHA")
        #expect(result.count == 1)
        #expect(result[0].children.count == 1)
        #expect(result[0].children[0].title == "Chapter Alpha")
    }

    @Test func partialMatch() {
        let result = TOCView.filter(items: [root], query: "hap")
        #expect(result.count == 1)
        #expect(result[0].children[0].title == "Chapter Alpha")
    }

    @Test func multipleMatchesAllChildrenPreserved() {
        let result = TOCView.filter(items: [root], query: "Chapter")
        #expect(result.count == 1)
        #expect(result[0].children.count == 2)
    }

    @Test func whitespaceTrimmed() {
        let result = TOCView.filter(items: [root], query: "  Chapter  ")
        #expect(result.count == 1)
        #expect(result[0].children.count == 2)
    }

    @Test func filterOnFlatList() {
        let items = [childA, childB]
        let result = TOCView.filter(items: items, query: "Beta")
        #expect(result.count == 1)
        #expect(result[0].title == "Chapter Beta")
    }

    @Test func parentItselfMatchesKeepsAllChildren() {
        let items = [TOCItem(id: UUID(), title: "Installation Guide", path: nil, children: [
            TOCItem(id: UUID(), title: "Windows", path: "win.html", children: []),
            TOCItem(id: UUID(), title: "macOS", path: "mac.html", children: []),
        ])]
        let result = TOCView.filter(items: items, query: "Installation")
        #expect(result.count == 1)
        #expect(result[0].children.count == 2)
    }
}
