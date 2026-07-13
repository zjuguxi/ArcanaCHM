import SwiftUI
import WebKit

enum FindDirection {
    case next, previous
}

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
    var findQuery: String
    var findNavigationTrigger: UUID
    var findDirection: FindDirection
    var onFindResults: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let userContentController = configuration.userContentController

        let csp = """
        var meta = document.createElement('meta');
        meta.httpEquiv = 'Content-Security-Policy';
        meta.content = "default-src 'none'; img-src 'self' data: file:; style-src 'self' file: 'unsafe-inline'; font-src 'self' data: file:; media-src 'self' file:; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'";
        document.head.insertBefore(meta, document.head.firstChild);
        """
        userContentController.addUserScript(WKUserScript(source: csp, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        userContentController.addUserScript(WKUserScript(source: Self.appJSContent, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        userContentController.add(context.coordinator, name: "reader")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.installContentBlocker { succeeded in
            context.coordinator.isContentBlockerReady = succeeded
            if succeeded {
                load(webView)
            } else {
                webView.loadHTMLString(Self.securityConfigurationFailedHTML, baseURL: nil)
            }
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
            let navigationChanged = context.coordinator.lastNavigationToken != navigationToken
            injectStyle(into: webView, scrollToMatch: shouldScrollToMatch, scrollY: navigationChanged ? scrollY : nil)
            context.coordinator.lastHighlightedQuery = normalizedSearchQuery
            context.coordinator.lastNavigationToken = navigationToken
            if findQuery != context.coordinator.lastFindQuery {
                context.coordinator.lastFindQuery = findQuery
                let escaped = findQuery.javascriptStringLiteral
                webView.evaluateJavaScript("window.__arcanaFindInPage(\(escaped))")
            }
            if findNavigationTrigger != context.coordinator.lastFindNavigationTrigger {
                context.coordinator.lastFindNavigationTrigger = findNavigationTrigger
                let dir = findDirection == .next ? "'next'" : "'previous'"
                webView.evaluateJavaScript("window.__arcanaNavigateFind(\(dir))")
            }
        }
    }

    private func load(_ webView: WKWebView) {
        webView.appearance = NSAppearance(named: .aqua)
        let url = fileURL()
        if url == book.rootURL {
            webView.loadHTMLString(Self.pageNotFoundHTML(title: book.title), baseURL: nil)
        } else {
            webView.loadFileURL(url, allowingReadAccessTo: book.rootURL)
        }
    }

    private func fileURL() -> URL {
        if let safe = SecurityPolicy.safeFileURL(rootURL: book.rootURL, relativePath: path) {
            return safe
        }
        if let homePath = book.homePath,
           let homeURL = SecurityPolicy.safeFileURL(rootURL: book.rootURL, relativePath: homePath) {
            return homeURL
        }
        return book.rootURL
    }

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate func injectStyle(into webView: WKWebView, scrollToMatch: Bool, scrollY: Double? = nil) {
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
        body font, body span, body div, body p, body li, body dd, body dt, body td, body th, body b, body strong, body em, body i, body u {
          font-size: 1rem !important;
          font-family: inherit !important;
          color: inherit !important;
        }
        h1, h2, h3, h4 {
          color: var(--reader-heading) !important;
          line-height: 1.2 !important;
          letter-spacing: 0 !important;
        }
        h1 { font-size: 2rem !important; margin-top: 1.2em !important; border-bottom: 1px solid var(--reader-rule) !important; padding-bottom: .35em !important; }
        h2 { font-size: 1.45rem !important; margin-top: 1.55em !important; }
        h3 { font-size: 1.15rem !important; margin-top: 1.35em !important; }
        h1 *, h2 *, h3 *, h4 * { font-size: inherit !important; color: inherit !important; }
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
        table, td { background-color: var(--reader-surface) !important; }
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
        mark.arcana-find-hit {
          background: #d4edda !important;
          color: #13211f !important;
          border-radius: 3px !important;
          padding: 0 .08em !important;
        }
        mark.arcana-find-current {
          background: #f5a623 !important;
          color: #13211f !important;
          border-radius: 3px !important;
          box-shadow: 0 0 0 2px rgba(226, 169, 29, .5) !important;
          padding: 0 .08em !important;
        }
        \(spotlightMode ? "body > * { max-width: 760px !important; margin-left: auto !important; margin-right: auto !important; }" : "")
        """

        let query = normalizedSearchQuery
        let script = """
        (function() {
          var style = document.getElementById('arcana-reader-style');
          if (!style) {
            style = document.createElement('style');
            style.id = 'arcana-reader-style';
            document.head.appendChild(style);
          }
          style.textContent = \(css.javascriptStringLiteral);
          window.__arcanaHighlightQuery(\(query.javascriptStringLiteral), \(scrollToMatch ? "true" : "false"));
          \(scrollY.map { y in "requestAnimationFrame(function(){ window.scrollTo(0, \(Int(max(0, y)))); });" } ?? "")
        })();
        """
        webView.evaluateJavaScript(script)
    }

    private static let appJSContent = """
    window.__arcanaHighlightQuery = function(value, scrollToMatch) {
      document.querySelectorAll('mark.arcana-search-hit').forEach(function(mark) {
        var text = document.createTextNode(mark.textContent || '');
        mark.replaceWith(text);
        if (text.parentNode) text.parentNode.normalize();
      });
      if (!value || value.length < 2) return;
      var needle = value.toLocaleLowerCase();
      var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
        acceptNode: function(node) {
          var parent = node.parentElement;
          if (!parent) return NodeFilter.FILTER_REJECT;
          if (['SCRIPT', 'STYLE', 'TEXTAREA', 'INPUT', 'MARK'].includes(parent.tagName)) return NodeFilter.FILTER_REJECT;
          return (node.nodeValue || '').toLocaleLowerCase().includes(needle) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
        }
      });
      var nodes = [];
      while (walker.nextNode() && nodes.length < 10000) nodes.push(walker.currentNode);
      var highlightCount = 0;
      nodes.forEach(function(node) {
        var text = node.nodeValue || '';
        var lower = text.toLocaleLowerCase();
        var fragment = document.createDocumentFragment();
        var lastIndex = 0;
        var matchIndex = lower.indexOf(needle);
        while (matchIndex !== -1 && highlightCount < 10000) {
          if (matchIndex > lastIndex) fragment.appendChild(document.createTextNode(text.slice(lastIndex, matchIndex)));
          var mark = document.createElement('mark');
          mark.className = 'arcana-search-hit';
          mark.textContent = text.slice(matchIndex, matchIndex + value.length);
          fragment.appendChild(mark);
          highlightCount++;
          lastIndex = matchIndex + value.length;
          matchIndex = lower.indexOf(needle, lastIndex);
        }
        if (lastIndex < text.length) fragment.appendChild(document.createTextNode(text.slice(lastIndex)));
        node.replaceWith(fragment);
      });
      if (scrollToMatch) {
        var first = document.querySelector('mark.arcana-search-hit');
        if (first) first.scrollIntoView({ block: 'center' });
      }
    };
    window.__arcanaFindInPage = function(value) {
      document.querySelectorAll('mark.arcana-find-hit, mark.arcana-find-current').forEach(function(m) {
        var t = document.createTextNode(m.textContent || '');
        m.replaceWith(t);
        if (t.parentNode) t.parentNode.normalize();
      });
      if (!value || value.length < 1) {
        window.webkit.messageHandlers.reader.postMessage({ type: 'find', count: 0, current: 0 });
        return;
      }
      var needle = value.toLocaleLowerCase();
      var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
        acceptNode: function(node) {
          var p = node.parentElement;
          if (!p || ['SCRIPT','STYLE','TEXTAREA','INPUT','MARK'].includes(p.tagName)) return NodeFilter.FILTER_REJECT;
          return (node.nodeValue || '').toLocaleLowerCase().includes(needle) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
        }
      });
      var nodes = [];
      while (walker.nextNode() && nodes.length < 10000) nodes.push(walker.currentNode);
      var idx = 0;
      nodes.forEach(function(node) {
        var text = node.nodeValue || '';
        var lower = text.toLocaleLowerCase();
        var frag = document.createDocumentFragment();
        var last = 0;
        var pos = lower.indexOf(needle);
        while (pos !== -1 && idx < 10000) {
          if (pos > last) frag.appendChild(document.createTextNode(text.slice(last, pos)));
          var mark = document.createElement('mark');
          mark.className = 'arcana-find-hit';
          mark.dataset.fi = idx;
          mark.textContent = text.slice(pos, pos + value.length);
          frag.appendChild(mark);
          last = pos + value.length;
          pos = lower.indexOf(needle, last);
          idx++;
        }
        if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
        node.replaceWith(frag);
      });
      window.__arcanaFindCount = idx;
      window.__arcanaFindCurrent = 0;
      var first = document.querySelector('mark.arcana-find-hit');
      if (first) { first.classList.add('arcana-find-current'); first.scrollIntoView({ block: 'center' }); }
      window.webkit.messageHandlers.reader.postMessage({ type: 'find', count: idx, current: idx > 0 ? 1 : 0 });
    };
    window.__arcanaNavigateFind = function(dir) {
      var marks = document.querySelectorAll('mark.arcana-find-hit');
      if (!marks.length) return;
      var cur = window.__arcanaFindCurrent || 0;
      if (cur < 0 || cur >= marks.length) cur = 0;
      var next = dir === 'next' ? cur + 1 : cur - 1;
      if (next >= marks.length) next = 0;
      if (next < 0) next = marks.length - 1;
      document.querySelectorAll('mark.arcana-find-current').forEach(function(m) { m.classList.remove('arcana-find-current'); });
      marks[next].classList.add('arcana-find-current');
      marks[next].scrollIntoView({ block: 'center' });
      window.__arcanaFindCurrent = next;
      window.webkit.messageHandlers.reader.postMessage({ type: 'find', count: marks.length, current: next + 1 });
    };
    if (!window.__arcanaScrollHooked) {
      window.__arcanaScrollHooked = true;
      var last = 0;
      window.addEventListener('scroll', function() {
        var now = Date.now();
        if (now - last > 120) {
          window.webkit.messageHandlers.reader.postMessage({ type: 'scroll', y: window.scrollY });
          last = now;
        }
      }, { passive: true });
    }
    window.webkit.messageHandlers.reader.postMessage({ type: 'title', title: document.title || '' });
    """

    private static func pageNotFoundHTML(title: String) -> String {
        """
        <html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center;
               color: #60716d; margin-top: 120px; font-size: 15px; }
        </style></head><body>
        <p>&#128218; \("reader_page_not_found".loc)</p>
        </body></html>
        """
    }

    private static let securityConfigurationFailedHTML = """
    <html><head><meta charset="utf-8"></head><body>
    <p>Reader security configuration failed. Content was not loaded.</p>
    </body></html>
    """

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebReaderView
        var lastHighlightedQuery = ""
        var lastNavigationToken: UUID?
        var lastFindQuery = ""
        var lastFindNavigationTrigger = UUID()
        var isContentBlockerReady = false
        weak var webView: WKWebView?

        init(_ parent: WebReaderView) {
            self.parent = parent
        }

        func installContentBlocker(completion: @escaping @MainActor (Bool) -> Void) {
            let rules = """
            [
              {
                "trigger": { "url-filter": "^(https?|ftps?|wss?)://.*" },
                "action": { "type": "block" }
              },
              {
                "trigger": { "url-filter": "^data:.*" },
                "action": { "type": "block" }
              },
              {
                "trigger": { "url-filter": "^blob:.*" },
                "action": { "type": "block" }
              },
              {
                "trigger": { "url-filter": ".*", "resource-type": ["script"] },
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
                        completion(true)
                    } else {
                        completion(false)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let hasSearch = !parent.normalizedSearchQuery.isEmpty
            parent.injectStyle(into: webView, scrollToMatch: hasSearch, scrollY: hasSearch ? nil : parent.scrollY)
            lastHighlightedQuery = parent.normalizedSearchQuery
            lastNavigationToken = parent.navigationToken
            lastFindQuery = parent.findQuery
            if !parent.findQuery.isEmpty {
                let escaped = parent.findQuery.javascriptStringLiteral
                webView.evaluateJavaScript("window.__arcanaFindInPage(\(escaped))")
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            preferences.allowsContentJavaScript = false

            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel, preferences)
                return
            }

            let scheme = url.scheme?.lowercased() ?? ""
            if ["data", "blob", "javascript"].contains(scheme) {
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
            guard message.frameInfo.isMainFrame else { return }
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String
            else {
                return
            }

            if type == "scroll", let y = body["y"] as? Double, y >= 0, y.isFinite {
                parent.onScroll(parent.path, y)
            } else if type == "title", let title = body["title"] as? String {
                parent.onTitle(String(title.prefix(1_024)))
            } else if type == "find",
                      let count = body["count"] as? Int,
                      let current = body["current"] as? Int,
                      count >= 0, current >= 0, count <= 100000, current <= count {
                parent.onFindResults(current, count)
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
