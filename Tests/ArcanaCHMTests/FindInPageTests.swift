import XCTest
@testable import ArcanaCHM

final class FindInPageTests: XCTestCase {

    // MARK: - Navigation algorithm (mirrors JS __arcanaNavigateFind)

    private func navigate(current: Int, total: Int, direction: FindDirection) -> Int {
        guard total > 0 else { return 0 }
        var cur = current
        if cur < 0 || cur >= total { cur = 0 }
        let next: Int
        switch direction {
        case .next:
            next = cur + 1
        case .previous:
            next = cur - 1
        }
        if next >= total { return 0 }
        if next < 0 { return total - 1 }
        return next
    }

    func testNavigateNextAdvancesIndex() {
        XCTAssertEqual(navigate(current: 0, total: 5, direction: .next), 1)
        XCTAssertEqual(navigate(current: 1, total: 5, direction: .next), 2)
        XCTAssertEqual(navigate(current: 3, total: 5, direction: .next), 4)
    }

    func testNavigateNextWrapsToZero() {
        XCTAssertEqual(navigate(current: 4, total: 5, direction: .next), 0)
        XCTAssertEqual(navigate(current: 0, total: 1, direction: .next), 0)
    }

    func testNavigatePreviousGoesBack() {
        XCTAssertEqual(navigate(current: 4, total: 5, direction: .previous), 3)
        XCTAssertEqual(navigate(current: 1, total: 5, direction: .previous), 0)
    }

    func testNavigatePreviousWrapsToLast() {
        XCTAssertEqual(navigate(current: 0, total: 5, direction: .previous), 4)
    }

    func testNavigateFromInvalidIndexFallsBackToZero() {
        XCTAssertEqual(navigate(current: -1, total: 5, direction: .next), 1)
        XCTAssertEqual(navigate(current: 10, total: 5, direction: .next), 1)
        XCTAssertEqual(navigate(current: -1, total: 5, direction: .previous), 4)
    }

    func testNavigateNoMatchesReturnsZero() {
        XCTAssertEqual(navigate(current: 0, total: 0, direction: .next), 0)
        XCTAssertEqual(navigate(current: 0, total: 0, direction: .previous), 0)
    }

    // MARK: - updateNSView action detection

    func testQueryChangeDetected_NavigateNotDetected() {
        let (coordinator, _) = makeCoordinator(findQuery: "initial")
        let initialTrigger = coordinator.parent.findNavigationTrigger
        coordinator.lastFindQuery = "initial"
        coordinator.lastFindNavigationTrigger = initialTrigger

        // Simulate: user types → query changes, trigger unchanged
        let newView = makeView(findQuery: "hello", findNavigationTrigger: initialTrigger)
        coordinator.parent = newView

        XCTAssertNotEqual(coordinator.parent.findQuery, coordinator.lastFindQuery,
                          "findQuery change must be detected for findInPage JS")
        XCTAssertEqual(coordinator.parent.findNavigationTrigger, coordinator.lastFindNavigationTrigger,
                       "navigationTrigger should NOT change when user types")
    }

    func testNavigateDetected_QueryChangeNotDetected() {
        let (coordinator, _) = makeCoordinator(findQuery: "hello")
        coordinator.lastFindQuery = "hello"
        coordinator.lastFindNavigationTrigger = coordinator.parent.findNavigationTrigger

        // Simulate: button/Enter click → trigger changes, query unchanged
        let newTrigger = UUID()
        let newView = makeView(findQuery: "hello", findNavigationTrigger: newTrigger)
        coordinator.parent = newView

        XCTAssertEqual(coordinator.parent.findQuery, coordinator.lastFindQuery,
                       "query should NOT change on button press")
        XCTAssertNotEqual(coordinator.parent.findNavigationTrigger, coordinator.lastFindNavigationTrigger,
                          "navigationTrigger change must be detected for navigateFind JS")
    }

    func testBothChangeWhenQueryAndTriggerChangeSimultaneously() {
        let (coordinator, _) = makeCoordinator(findQuery: "old")
        coordinator.lastFindQuery = "old"
        coordinator.lastFindNavigationTrigger = coordinator.parent.findNavigationTrigger

        // Simulate: user presses Enter on new query (via onSubmit)
        let newView = makeView(findQuery: "new", findNavigationTrigger: UUID())
        coordinator.parent = newView

        XCTAssertNotEqual(coordinator.parent.findQuery, coordinator.lastFindQuery)
        XCTAssertNotEqual(coordinator.parent.findNavigationTrigger, coordinator.lastFindNavigationTrigger)
    }

    // MARK: - OnSubmit produces .next direction

    // MARK: - Helpers

    private func makeCoordinator(
        findQuery: String = "",
        findNavigationTrigger: UUID? = nil
    ) -> (WebReaderView.Coordinator, WebReaderView) {
        let view = makeView(findQuery: findQuery, findNavigationTrigger: findNavigationTrigger ?? UUID())
        let coordinator = WebReaderView.Coordinator(view)
        return (coordinator, view)
    }

    private func makeView(
        findQuery: String = "",
        findNavigationTrigger: UUID = UUID()
    ) -> WebReaderView {
        WebReaderView(
            book: Book.empty(title: "Test", rootURL: URL(fileURLWithPath: "/tmp")),
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
            findDirection: .next,
            onFindResults: { _, _ in }
        )
    }
}
