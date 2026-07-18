import XCTest
@testable import ArcanaCHM

@MainActor
final class WebReaderNavigationBridgeTests: XCTestCase {
    func testNativeBackForwardMismatchDoesNotTriggerStaleReload() {
        let webViewURL = URL(string: "file:///tmp/book/a.html")!
        let staleSwiftUIURL = URL(string: "file:///tmp/book/b.html")!

        XCTAssertFalse(
            WebReaderView.shouldLoad(
                currentURL: webViewURL,
                targetURL: staleSwiftUIURL,
                navigationChanged: false
            )
        )
    }

    func testAppNavigationMismatchTriggersLoad() {
        let currentURL = URL(string: "file:///tmp/book/a.html")!
        let requestedURL = URL(string: "file:///tmp/book/b.html")!

        XCTAssertTrue(
            WebReaderView.shouldLoad(
                currentURL: currentURL,
                targetURL: requestedURL,
                navigationChanged: true
            )
        )
    }

    func testSameLocationNeverReloadsForNavigationTokenAlone() {
        let url = URL(string: "file:///tmp/book/a.html#details")!

        XCTAssertFalse(
            WebReaderView.shouldLoad(
                currentURL: url,
                targetURL: url,
                navigationChanged: true
            )
        )
    }

    func testAppFragmentNavigationTriggersLoad() {
        let currentURL = URL(string: "file:///tmp/book/a.html#one")!
        let requestedURL = URL(string: "file:///tmp/book/a.html#two")!

        XCTAssertTrue(
            WebReaderView.shouldLoad(
                currentURL: currentURL,
                targetURL: requestedURL,
                navigationChanged: true
            )
        )
    }
}
