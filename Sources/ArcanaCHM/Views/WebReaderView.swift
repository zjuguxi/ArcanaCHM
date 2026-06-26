import SwiftUI
import WebKit

struct WebReaderView: NSViewRepresentable {
    var book: Book
    var path: String
    var scrollY: Double
    var fontScale: Double
    var spotlightMode: Bool
    var searchQuery: String
    var navigationToken: UUID
    var onNavigate: (String) -> Void
    var onScroll: (String, Double) -> Void
    var onTitle: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.userContentController.add(context.coordinator, name: "reader")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.installContentBlocker {
            context.coordinator.isContentBlockerReady = true
            load(webView)
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.isContentBlockerReady else { return }
        let targetURL = fileURL()
        if webView.url?.standardizedFileURL != targetURL.standardizedFileURL {
            load(webView)
        } else {
            let shouldScrollToMatch = context.coordinator.lastHighlightedQuery != normalizedSearchQuery
            injectStyle(into: webView, scrollToMatch: shouldScrollToMatch)
            context.coordinator.lastHighlightedQuery = normalizedSearchQuery
            if context.coordinator.lastNavigationToken != navigationToken {
                context.coordinator.lastNavigationToken = navigationToken
                scrollToRequestedPosition(in: webView)
            }
        }
    }

    private func load(_ webView: WKWebView) {
        webView.appearance = NSAppearance(named: .aqua)
        webView.loadFileURL(fileURL(), allowingReadAccessTo: book.rootURL)
    }

    private func fileURL() -> URL {
        SecurityPolicy.safeFileURL(rootURL: book.rootURL, relativePath: path)
            ?? book.rootURL
    }

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate func injectStyle(into webView: WKWebView, scrollToMatch: Bool) {
        let css = """
        :root {
          color-scheme: light;
          --reader-bg: #fbfcfa;
          --reader-surface: #ffffff;
          --reader-fg: #20302e;
          --reader-heading: #163d39;
          --reader-muted: #60716d;
          --reader-accent: #0f8f83;
          --reader-rule: #d7e3de;
          --reader-code: #edf5f2;
          --reader-scrollbar: #9bb5af;
          --reader-scrollbar-hover: #6f9189;
        }
        html {
          background: var(--reader-bg) !important;
          font-size: \(Int(fontScale * 100))% !important;
        }
        body {
          max-width: 980px !important;
          margin: 0 auto !important;
          padding: \(spotlightMode ? "46px 96px 120px" : "34px 64px 100px") !important;
          color: var(--reader-fg) !important;
          background: var(--reader-bg) !important;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif !important;
          font-size: 1rem !important;
          line-height: 1.68 !important;
        }
        body font, body span, body div, body p, body li, body dd, body dt, body td, body th {
          font-size: 1rem !important;
          font-family: inherit !important;
        }
        h1, h2, h3, h4 {
          color: var(--reader-heading) !important;
          line-height: 1.2 !important;
          letter-spacing: 0 !important;
        }
        h1 { font-size: 2rem !important; margin-top: 1.2em !important; border-bottom: 1px solid var(--reader-rule) !important; padding-bottom: .35em !important; }
        h2 { font-size: 1.45rem !important; margin-top: 1.55em !important; }
        h3 { font-size: 1.15rem !important; margin-top: 1.35em !important; }
        h1 *, h2 *, h3 *, h4 * { font-size: inherit !important; }
        a { color: var(--reader-accent) !important; text-decoration-thickness: .08em !important; }
        table {
          border-collapse: collapse !important;
          width: 100% !important;
          margin: 1.1em 0 !important;
          background: white !important;
          box-shadow: 0 0 0 1px var(--reader-rule) !important;
        }
        th, td {
          border: 1px solid var(--reader-rule) !important;
          padding: .55em .7em !important;
          vertical-align: top !important;
        }
        th { background: var(--reader-code) !important; color: var(--reader-heading) !important; }
        img { max-width: 100% !important; height: auto !important; }
        pre, code {
          background: #edf5f2 !important;
          border-radius: 6px !important;
        }
        table, td, th { background-color: var(--reader-surface) !important; }
        pre, code { background: var(--reader-code) !important; color: var(--reader-fg) !important; }
        ::-webkit-scrollbar { width: 12px; height: 12px; background: var(--reader-bg); }
        ::-webkit-scrollbar-thumb {
          background: var(--reader-scrollbar);
          border-radius: 8px;
          border: 3px solid var(--reader-bg);
        }
        ::-webkit-scrollbar-thumb:hover { background: var(--reader-scrollbar-hover); }
        ::-webkit-scrollbar-corner { background: var(--reader-bg); }
        blockquote {
          border-left: 4px solid #7ec9bd !important;
          color: var(--reader-muted) !important;
          padding-left: 1em !important;
          margin-left: 0 !important;
        }
        mark.arcana-search-hit {
          background: #ffe66d !important;
          color: #13211f !important;
          border-radius: 3px !important;
          box-shadow: 0 0 0 1px rgba(226, 169, 29, .35) !important;
          padding: 0 .08em !important;
        }
        \(spotlightMode ? "body > * { max-width: 760px !important; margin-left: auto !important; margin-right: auto !important; }" : "")
        """

        let script = """
        (function() {
          let style = document.getElementById('arcana-reader-style');
          if (!style) {
            style = document.createElement('style');
            style.id = 'arcana-reader-style';
            document.head.appendChild(style);
          }
          style.textContent = \(css.javascriptStringLiteral);
          const query = \(normalizedSearchQuery.javascriptStringLiteral);
          const scrollToMatch = \(scrollToMatch ? "true" : "false");
          function clearHighlights() {
            document.querySelectorAll('mark.arcana-search-hit').forEach(function(mark) {
              const text = document.createTextNode(mark.textContent || '');
              mark.replaceWith(text);
              if (text.parentNode) text.parentNode.normalize();
            });
          }
          function highlightQuery(value) {
            clearHighlights();
            if (!value || value.length < 2) return;
            const needle = value.toLocaleLowerCase();
            const walker = document.createTreeWalker(
              document.body,
              NodeFilter.SHOW_TEXT,
              {
                acceptNode: function(node) {
                  const parent = node.parentElement;
                  if (!parent) return NodeFilter.FILTER_REJECT;
                  if (['SCRIPT', 'STYLE', 'TEXTAREA', 'INPUT', 'MARK'].includes(parent.tagName)) {
                    return NodeFilter.FILTER_REJECT;
                  }
                  return (node.nodeValue || '').toLocaleLowerCase().includes(needle) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
                }
              }
            );
            const nodes = [];
            while (walker.nextNode()) nodes.push(walker.currentNode);
            nodes.forEach(function(node) {
              const text = node.nodeValue || '';
              const lower = text.toLocaleLowerCase();
              const fragment = document.createDocumentFragment();
              let lastIndex = 0;
              let matchIndex = lower.indexOf(needle);
              while (matchIndex !== -1) {
                if (matchIndex > lastIndex) {
                  fragment.appendChild(document.createTextNode(text.slice(lastIndex, matchIndex)));
                }
                const mark = document.createElement('mark');
                mark.className = 'arcana-search-hit';
                mark.textContent = text.slice(matchIndex, matchIndex + value.length);
                fragment.appendChild(mark);
                lastIndex = matchIndex + value.length;
                matchIndex = lower.indexOf(needle, lastIndex);
              }
              if (lastIndex < text.length) {
                fragment.appendChild(document.createTextNode(text.slice(lastIndex)));
              }
              node.replaceWith(fragment);
            });
            if (scrollToMatch) {
              const first = document.querySelector('mark.arcana-search-hit');
              if (first) first.scrollIntoView({ block: 'center' });
            }
          }
          highlightQuery(query);
          if (!window.__arcanaScrollHooked) {
            window.__arcanaScrollHooked = true;
            let last = 0;
            window.addEventListener('scroll', function() {
              const now = Date.now();
              if (now - last > 120) {
                window.webkit.messageHandlers.reader.postMessage({ type: 'scroll', y: window.scrollY });
                last = now;
              }
            }, { passive: true });
          }
          window.webkit.messageHandlers.reader.postMessage({ type: 'title', title: document.title || '' });
        })();
        """
        webView.evaluateJavaScript(script)
    }

    fileprivate func scrollToRequestedPosition(in webView: WKWebView) {
        let y = max(0, Int(scrollY))
        webView.evaluateJavaScript("requestAnimationFrame(function(){ window.scrollTo(0, \(y)); });")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebReaderView
        var lastHighlightedQuery = ""
        var lastNavigationToken: UUID?
        var isContentBlockerReady = false
        weak var webView: WKWebView?

        init(_ parent: WebReaderView) {
            self.parent = parent
        }

        func installContentBlocker(completion: @escaping () -> Void) {
            let rules = """
            [
              {
                "trigger": { "url-filter": "^https?://.*" },
                "action": { "type": "block" }
              }
            ]
            """
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "ArcanaCHM.BlockRemoteContent",
                encodedContentRuleList: rules
            ) { [weak self] ruleList, _ in
                DispatchQueue.main.async {
                    if let ruleList {
                        self?.webView?.configuration.userContentController.add(ruleList)
                    }
                    completion()
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.injectStyle(into: webView, scrollToMatch: !parent.normalizedSearchQuery.isEmpty)
            lastHighlightedQuery = parent.normalizedSearchQuery
            lastNavigationToken = parent.navigationToken
            let y = parent.scrollY
            if y > 0 && parent.normalizedSearchQuery.isEmpty {
                parent.scrollToRequestedPosition(in: webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            preferences.allowsContentJavaScript = false

            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel, preferences)
                return
            }

            guard url.isFileURL else {
                decisionHandler(.cancel, preferences)
                return
            }

            let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
            guard SecurityPolicy.isDescendant(resolved, of: parent.book.rootURL) else {
                decisionHandler(.cancel, preferences)
                return
            }

            if navigationAction.navigationType == .linkActivated,
               let relative = SecurityPolicy.relativePath(for: resolved, rootURL: parent.book.rootURL),
               SecurityPolicy.safeFileURL(rootURL: parent.book.rootURL, relativePath: relative) != nil {
                parent.onNavigate(relative)
            }

            decisionHandler(.allow, preferences)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else {
                return
            }

            if type == "scroll", let y = body["y"] as? Double {
                parent.onScroll(parent.path, y)
            } else if type == "title", let title = body["title"] as? String {
                parent.onTitle(title)
            }
        }
    }
}

private extension String {
    var javascriptStringLiteral: String {
        guard let data = try? JSONEncoder().encode(self),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        return encoded
    }
}
