import XCTest
@testable import ArcanaCHM

@MainActor
final class ReaderWorkspaceTests: XCTestCase {
    func testWorkspaceStartsWithOneEmptyTab() {
        let workspace = ReaderWorkspaceStore()

        XCTAssertEqual(workspace.tabs.count, 1)
        XCTAssertEqual(workspace.activeTabID, workspace.tabs[0].id)
        XCTAssertNil(workspace.activeTab.bookID)
    }

    func testOpenBookUsesActiveEmptyTab() {
        let workspace = ReaderWorkspaceStore()
        let bookID = UUID()

        workspace.openBook(bookID: bookID, path: "index.html", scrollY: 24)

        XCTAssertEqual(workspace.tabs.count, 1)
        XCTAssertEqual(workspace.activeTab.bookID, bookID)
        XCTAssertEqual(workspace.activeTab.reader.currentPath, "index.html")
        XCTAssertEqual(workspace.activeTab.reader.scrollY, 24)
    }

    func testNewTabOwnsIndependentReaderState() {
        let workspace = ReaderWorkspaceStore()
        let firstID = UUID()
        let secondID = UUID()
        workspace.openBook(bookID: firstID, path: "first.html", scrollY: 10)
        let firstTabID = workspace.activeTabID

        workspace.newTab()
        workspace.openBook(bookID: secondID, path: "second.html", scrollY: 20)
        workspace.activeTab.reader.open("changed.html", scrollY: 30)

        let firstTab = try! XCTUnwrap(workspace.tabs.first { $0.id == firstTabID })
        XCTAssertEqual(firstTab.bookID, firstID)
        XCTAssertEqual(firstTab.reader.currentPath, "first.html")
        XCTAssertEqual(firstTab.reader.scrollY, 10)
        XCTAssertEqual(workspace.activeTab.bookID, secondID)
        XCTAssertEqual(workspace.activeTab.reader.currentPath, "changed.html")
    }

    func testClosingActiveTabActivatesNearestTab() {
        let workspace = ReaderWorkspaceStore()
        let firstTabID = workspace.activeTabID
        workspace.newTab()
        let secondTabID = workspace.activeTabID
        workspace.newTab()
        let thirdTabID = workspace.activeTabID

        workspace.closeTab(thirdTabID)
        XCTAssertEqual(workspace.activeTabID, secondTabID)

        workspace.closeTab(secondTabID)
        XCTAssertEqual(workspace.activeTabID, firstTabID)
    }

    func testClosingLastTabLeavesFreshEmptyTab() {
        let workspace = ReaderWorkspaceStore()
        let oldTabID = workspace.activeTabID
        workspace.openBook(bookID: UUID(), path: "index.html", scrollY: 0)

        workspace.closeTab(oldTabID)

        XCTAssertEqual(workspace.tabs.count, 1)
        XCTAssertNotEqual(workspace.activeTabID, oldTabID)
        XCTAssertNil(workspace.activeTab.bookID)
    }

    func testClosingTabsForDeletedBookPreservesOtherBooks() {
        let workspace = ReaderWorkspaceStore()
        let deletedBookID = UUID()
        let retainedBookID = UUID()
        workspace.openBook(bookID: deletedBookID, path: "one.html", scrollY: 0)
        workspace.newTab()
        workspace.openBook(bookID: retainedBookID, path: "two.html", scrollY: 0)
        workspace.newTab()
        workspace.openBook(bookID: deletedBookID, path: "three.html", scrollY: 0)

        workspace.closeTabs(forBookID: deletedBookID)

        XCTAssertEqual(workspace.tabs.count, 1)
        XCTAssertEqual(workspace.activeTab.bookID, retainedBookID)
    }

    func testSwitchingBookClearsTabSpecificReaderState() {
        let workspace = ReaderWorkspaceStore()
        workspace.openBook(bookID: UUID(), path: "old.html", scrollY: 44)
        workspace.activeTab.reader.searchQuery = "old query"

        let newBookID = UUID()
        workspace.openBook(bookID: newBookID, path: "new.html", scrollY: 7)

        XCTAssertEqual(workspace.activeTab.bookID, newBookID)
        XCTAssertEqual(workspace.activeTab.reader.currentPath, "new.html")
        XCTAssertEqual(workspace.activeTab.reader.scrollY, 7)
        XCTAssertEqual(workspace.activeTab.reader.searchQuery, "")
        XCTAssertEqual(workspace.activeTab.searchText, "")
        XCTAssertNil(workspace.activeTab.completedSearch)
    }

    func testCycleTabsWrapsInBothDirections() {
        let workspace = ReaderWorkspaceStore()
        let first = workspace.activeTabID
        workspace.newTab()
        let second = workspace.activeTabID
        workspace.newTab()
        let third = workspace.activeTabID

        workspace.activateTab(first)
        workspace.selectNextTab()
        XCTAssertEqual(workspace.activeTabID, second)
        workspace.selectPreviousTab()
        XCTAssertEqual(workspace.activeTabID, first)
        workspace.selectPreviousTab()
        XCTAssertEqual(workspace.activeTabID, third)
    }

    func testNewTabHonorsMaximumTabCount() {
        let workspace = ReaderWorkspaceStore()
        for _ in 1..<ReaderWorkspaceStore.maximumTabCount {
            workspace.newTab()
        }

        let activeID = workspace.activeTabID
        workspace.newTab()

        XCTAssertEqual(workspace.tabs.count, ReaderWorkspaceStore.maximumTabCount)
        XCTAssertEqual(workspace.activeTabID, activeID)
    }

    func testReconcileClosesTabsWhoseBooksWereRemoved() {
        let workspace = ReaderWorkspaceStore()
        let retainedBookID = UUID()
        workspace.openBook(bookID: UUID(), path: "removed.html", scrollY: 0)
        workspace.newTab()
        workspace.openBook(bookID: retainedBookID, path: "retained.html", scrollY: 0)

        workspace.reconcile(validBookIDs: [retainedBookID])

        XCTAssertEqual(workspace.tabs.count, 1)
        XCTAssertEqual(workspace.activeTab.bookID, retainedBookID)
    }
}
