import Combine
import WebKit

@MainActor
final class ReaderNavigationController: ObservableObject {
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    private weak var webView: WKWebView?

    func attach(_ webView: WKWebView) {
        self.webView = webView
        refreshState()
    }

    func detach(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        self.webView = nil
        reset()
    }

    func goBack() {
        guard webView?.canGoBack == true else { return }
        webView?.goBack()
    }

    func goForward() {
        guard webView?.canGoForward == true else { return }
        webView?.goForward()
    }

    func refreshState() {
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
    }

    func reset() {
        canGoBack = false
        canGoForward = false
    }
}
