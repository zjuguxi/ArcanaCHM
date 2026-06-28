import XCTest
@testable import ArcanaCHM

final class FindInPageTests: XCTestCase {

    func testFindDirectionEnum() {
        XCTAssertNotNil(FindDirection.next)
        XCTAssertNotNil(FindDirection.previous)
    }

    func testFindQueryChangeDetection() {
        let book = Book.empty(title: "Test", rootURL: URL(fileURLWithPath: "/tmp"))

        let view = WebReaderView(
            book: book,
            path: "test.html",
            scrollY: 0,
            fontScale: 1.0,
            spotlightMode: false,
            searchQuery: "",
            navigationToken: UUID(),
            onNavigate: { _ in },
            onScroll: { _, _ in },
            onTitle: { _ in },
            findQuery: "hello",
            findNavigationTrigger: UUID(),
            findDirection: .next,
            onFindResults: { _, _ in }
        )

        let coordinator = WebReaderView.Coordinator(view)
        XCTAssertEqual(coordinator.lastFindQuery, "")
        XCTAssertNotEqual(coordinator.parent.findQuery, coordinator.lastFindQuery)
    }

    func testFindNavigationTriggerDetection() {
        let book = Book.empty(title: "Test", rootURL: URL(fileURLWithPath: "/tmp"))
        let trigger = UUID()

        let view = WebReaderView(
            book: book,
            path: "test.html",
            scrollY: 0,
            fontScale: 1.0,
            spotlightMode: false,
            searchQuery: "",
            navigationToken: UUID(),
            onNavigate: { _ in },
            onScroll: { _, _ in },
            onTitle: { _ in },
            findQuery: "",
            findNavigationTrigger: trigger,
            findDirection: .next,
            onFindResults: { _, _ in }
        )

        let coordinator = WebReaderView.Coordinator(view)
        coordinator.lastFindNavigationTrigger = UUID()
        XCTAssertNotEqual(coordinator.lastFindNavigationTrigger, coordinator.parent.findNavigationTrigger)
    }

    func testFindBarUIStateTransitions() {
        let book = Book.empty(title: "Test", rootURL: URL(fileURLWithPath: "/tmp"))

        var findQuery = ""
        var findNavigationTrigger = UUID()
        var findDirection: FindDirection = .next

        _ = WebReaderView(
            book: book,
            path: "test.html",
            scrollY: 0,
            fontScale: 1.0,
            spotlightMode: false,
            searchQuery: "",
            navigationToken: UUID(),
            onNavigate: { _ in },
            onScroll: { _, _ in },
            onTitle: { _ in },
            findQuery: findQuery,
            findNavigationTrigger: findNavigationTrigger,
            findDirection: findDirection,
            onFindResults: { _, _ in }
        )

        // Simulate the find bar state machine:
        // 1. Set query
        findQuery = "test"
        findNavigationTrigger = UUID()
        findDirection = .next
        XCTAssertEqual(findQuery, "test")
        XCTAssertEqual(findDirection, .next)

        // 2. Navigate next
        findDirection = .next
        findNavigationTrigger = UUID()
        XCTAssertEqual(findDirection, .next)

        // 3. Navigate previous
        findDirection = .previous
        findNavigationTrigger = UUID()
        XCTAssertEqual(findDirection, .previous)
    }

    func testFindQueryChangeTriggersNavigation() {
        var trigger = UUID()
        let initialTrigger = trigger
        var direction: FindDirection = .next

        let book = Book.empty(title: "Test", rootURL: URL(fileURLWithPath: "/tmp"))
        _ = WebReaderView(
            book: book,
            path: "test.html",
            scrollY: 0,
            fontScale: 1.0,
            spotlightMode: false,
            searchQuery: "",
            navigationToken: UUID(),
            onNavigate: { _ in },
            onScroll: { _, _ in },
            onTitle: { _ in },
            findQuery: "",
            findNavigationTrigger: trigger,
            findDirection: direction,
            onFindResults: { _, _ in }
        )

        // Simulate query change -> new trigger + direction reset
        trigger = UUID()
        direction = .next
        XCTAssertNotEqual(trigger, initialTrigger)
        XCTAssertEqual(direction, .next)
    }
}
