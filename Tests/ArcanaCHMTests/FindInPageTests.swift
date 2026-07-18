import WebKit
import XCTest
@testable import ArcanaCHM

@MainActor
final class FindInPageTests: XCTestCase {
    func testFindUpdateActionsAreDerivedFromProductionState() {
        let oldTrigger = UUID()
        let newTrigger = UUID()

        XCTAssertEqual(
            WebReaderView.findUpdateActions(
                findQuery: "new",
                lastFindQuery: "old",
                findNavigationTrigger: oldTrigger,
                lastFindNavigationTrigger: oldTrigger
            ),
            .init(queryChanged: true, navigationChanged: false)
        )
        XCTAssertEqual(
            WebReaderView.findUpdateActions(
                findQuery: "same",
                lastFindQuery: "same",
                findNavigationTrigger: newTrigger,
                lastFindNavigationTrigger: oldTrigger
            ),
            .init(queryChanged: false, navigationChanged: true)
        )
        XCTAssertEqual(
            WebReaderView.findUpdateActions(
                findQuery: "new",
                lastFindQuery: "old",
                findNavigationTrigger: newTrigger,
                lastFindNavigationTrigger: oldTrigger
            ),
            .init(queryChanged: true, navigationChanged: true)
        )
    }

    func testInjectedFindScriptFindsAndNavigatesActualDOM() throws {
        let configuration = WKWebViewConfiguration()
        let messageSink = ScriptMessageSink()
        configuration.userContentController.add(messageSink, name: "reader")
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: WebReaderView.appJSContent,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let loaded = expectation(description: "HTML loaded")
        let navigationDelegate = NavigationDelegate(loaded: loaded)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = navigationDelegate
        webView.loadHTMLString("<html><body>Alpha beta alpha <span>ALPHA</span></body></html>", baseURL: nil)
        wait(for: [loaded], timeout: 10)

        let found = try evaluate(
            """
            window.__arcanaFindInPage('alpha');
            ({
              count: document.querySelectorAll('mark.arcana-find-hit').length,
              current: window.__arcanaFindCurrent,
              selected: document.querySelectorAll('mark.arcana-find-current').length
            });
            """,
            in: webView
        )
        XCTAssertEqual(found["count"] as? Int, 3)
        XCTAssertEqual(found["current"] as? Int, 0)
        XCTAssertEqual(found["selected"] as? Int, 1)

        let next = try evaluate(
            "window.__arcanaNavigateFind('next'); ({ current: window.__arcanaFindCurrent, text: document.querySelector('mark.arcana-find-current').textContent });",
            in: webView
        )
        XCTAssertEqual(next["current"] as? Int, 1)
        XCTAssertEqual((next["text"] as? String)?.lowercased(), "alpha")

        let previous = try evaluate(
            "window.__arcanaNavigateFind('previous'); ({ current: window.__arcanaFindCurrent });",
            in: webView
        )
        XCTAssertEqual(previous["current"] as? Int, 0)
    }

    private func evaluate(_ script: String, in webView: WKWebView) throws -> [String: Any] {
        let evaluated = expectation(description: "JavaScript evaluated")
        var result: Result<[String: Any], Error>?
        webView.evaluateJavaScript(script) { value, error in
            if let error {
                result = .failure(error)
            } else if let dictionary = value as? [String: Any] {
                result = .success(dictionary)
            } else {
                result = .failure(UnexpectedJavaScriptResult())
            }
            evaluated.fulfill()
        }
        wait(for: [evaluated], timeout: 10)
        return try XCTUnwrap(result).get()
    }
}

private struct UnexpectedJavaScriptResult: Error {}

private final class ScriptMessageSink: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {}
}

private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation

    init(loaded: XCTestExpectation) {
        self.loaded = loaded
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded.fulfill()
    }
}
