import XCTest
import WebKit
@testable import ArcanaCHM

@MainActor
final class WebReaderNavigationBridgeTests: XCTestCase {
    func testReaderUsesOpaqueUnderPageBackground() {
        let webView = WKWebView(frame: .zero)

        WebReaderView.configureRendering(of: webView)

        XCTAssertEqual(webView.underPageBackgroundColor.alphaComponent, 1, accuracy: 0.001)
        XCTAssertEqual(
            webView.underPageBackgroundColor.usingColorSpace(.sRGB),
            WebReaderView.readerBackgroundColor.usingColorSpace(.sRGB)
        )
    }

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

    func testAppFragmentNavigationStaysWithinLoadedDocument() {
        let currentURL = URL(string: "file:///tmp/book/a.html#one")!
        let requestedURL = URL(string: "file:///tmp/book/a.html#two")!

        XCTAssertEqual(
            WebReaderView.navigationAction(
                currentURL: currentURL,
                targetURL: requestedURL,
                navigationChanged: true
            ),
            .navigateWithinDocument
        )
        XCTAssertFalse(
            WebReaderView.shouldLoad(
                currentURL: currentURL,
                targetURL: requestedURL,
                navigationChanged: true
            )
        )
    }

    func testFragmentMismatchWithoutAppNavigationAwaitsWebKitCommit() {
        let currentURL = URL(string: "file:///tmp/book/a.html#one")!
        let requestedURL = URL(string: "file:///tmp/book/a.html#two")!

        XCTAssertEqual(
            WebReaderView.navigationAction(
                currentURL: currentURL,
                targetURL: requestedURL,
                navigationChanged: false
            ),
            .awaitCommittedNavigation
        )
    }
}
