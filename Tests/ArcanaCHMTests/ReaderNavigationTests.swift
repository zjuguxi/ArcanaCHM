import XCTest
@testable import ArcanaCHM

@MainActor
final class ReaderNavigationTests: XCTestCase {
    func testBeginSessionReplacesBookAndReadingState() {
        let store = ReaderStore()
        let bookID = UUID()

        store.beginSession(bookID: bookID, path: "chapter.html", scrollY: 42)

        XCTAssertEqual(store.currentBookID, bookID)
        XCTAssertEqual(store.currentPath, "chapter.html")
        XCTAssertEqual(store.scrollY, 42)
        XCTAssertEqual(store.searchQuery, "")
    }

    func testCommittedNavigationUpdatesMatchingSession() {
        let store = ReaderStore()
        let bookID = UUID()
        store.beginSession(bookID: bookID, path: "a.html")

        store.synchronizeCommittedNavigation(bookID: bookID, path: "b.html#details")

        XCTAssertEqual(store.currentPath, "b.html#details")
    }

    func testCommittedNavigationRejectsStaleBookCallback() {
        let store = ReaderStore()
        let currentBookID = UUID()
        store.beginSession(bookID: currentBookID, path: "current.html")

        store.synchronizeCommittedNavigation(bookID: UUID(), path: "stale.html")

        XCTAssertEqual(store.currentPath, "current.html")
    }

    func testSessionCanRepresentBookWithoutReadableHomePath() {
        let store = ReaderStore()
        let bookID = UUID()

        store.beginSession(bookID: bookID, path: nil)

        XCTAssertEqual(store.currentBookID, bookID)
        XCTAssertNil(store.currentPath)
    }

    func testEndSessionClearsReadingState() {
        let store = ReaderStore()
        store.beginSession(bookID: UUID(), path: "chapter.html", scrollY: 42)

        store.endSession()

        XCTAssertNil(store.currentBookID)
        XCTAssertNil(store.currentPath)
        XCTAssertEqual(store.scrollY, 0)
        XCTAssertEqual(store.searchQuery, "")
    }

    func testScrollAcceptsSameDocumentWithDifferentFragment() {
        let store = ReaderStore()
        let bookID = UUID()
        store.beginSession(bookID: bookID, path: "chapter.html#one")

        store.synchronizeScroll(bookID: bookID, path: "chapter.html#two", scrollY: 88)

        XCTAssertEqual(store.scrollY, 88)
    }

    func testScrollRejectsDifferentDocumentAndStaleBook() {
        let store = ReaderStore()
        let bookID = UUID()
        store.beginSession(bookID: bookID, path: "chapter.html", scrollY: 12)

        store.synchronizeScroll(bookID: bookID, path: "other.html", scrollY: 50)
        store.synchronizeScroll(bookID: UUID(), path: "chapter.html", scrollY: 60)

        XCTAssertEqual(store.scrollY, 12)
    }
}
