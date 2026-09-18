import OSLog
import UIKit
import WebKit

/// Some shops (Zara among them) answer a plain HTTP request with a JavaScript
/// bot challenge instead of the product page. Running the page in a real
/// WebKit view clears the challenge exactly as Safari would, and the rendered
/// DOM then carries the same metadata every other shop publishes up front.
@MainActor
final class WebProductLoader: NSObject {

    private static let log = Logger(subsystem: "com.gardropp", category: "linkimport")

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?
    private var settleTask: Task<Void, Never>?
    private var attempts = 0

    struct Rendered {
        var html: String?
        /// Sizeable images in the order the page lays them out — the product
        /// gallery, which the link-preview tag only shows one frame of.
        var imageURLs: [URL] = []
    }

    /// Loads the page, lets its scripts run, and reads back what it rendered.
    func load(_ url: URL, timeout: TimeInterval = 30) async -> Rendered {
        let html = await self.html(for: url, timeout: timeout)
        return Rendered(html: html, imageURLs: collectedImages)
    }

    private var collectedImages: [URL] = []

    /// Returns the page's HTML once its scripts have run, or nil on timeout.
    func html(for url: URL, timeout: TimeInterval = 30) async -> String? {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 420, height: 900), configuration: configuration)
        webView.navigationDelegate = self
        webView.isUserInteractionEnabled = false
        webView.alpha = 0.01
        self.webView = webView

        // A challenge script can check that it is actually being rendered, so
        // the view goes into the window — behind everything, and invisible.
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) {
            window.insertSubview(webView, at: 0)
        }

        webView.load(URLRequest(url: url))

        let result = await withTaskGroup(of: String?.self) { group in
            group.addTask { @MainActor in
                await withCheckedContinuation { continuation in
                    self.continuation = continuation
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        cleanUp()
        return result
    }

    /// Reads the gallery straight out of the rendered page. Shops lazy-load the
    /// rest of the gallery, so the page is nudged down first and the markup's
    /// own lazy attributes are read as well as what has actually loaded.
    private func collectImages(from webView: WKWebView) async {
        _ = try? await webView.evaluateJavaScript(
            "window.scrollTo(0, document.body.scrollHeight * 0.5); true"
        )
        try? await Task.sleep(for: .seconds(1.2))
        _ = try? await webView.evaluateJavaScript(
            "window.scrollTo(0, document.body.scrollHeight * 0.85); true"
        )
        try? await Task.sleep(for: .seconds(1.2))

        let script = """
        (function () {
          function widest(set) {
            if (!set) return null;
            var best = null, bestW = 0;
            set.split(',').forEach(function (part) {
              var bits = part.trim().split(/\\s+/);
              if (!bits[0]) return;
              var w = bits[1] ? parseInt(bits[1], 10) : 0;
              if (!best || w >= bestW) { best = bits[0]; bestW = w; }
            });
            return best;
          }
          var seen = {}, out = [];
          var nodes = document.querySelectorAll('img, source');
          for (var i = 0; i < nodes.length; i++) {
            var el = nodes[i];
            var src = el.currentSrc || widest(el.getAttribute('srcset')) ||
                      el.getAttribute('src') || el.getAttribute('data-src');
            if (!src || src.indexOf('http') !== 0 || seen[src]) continue;
            var natural = el.naturalWidth || 0;
            var box = el.getBoundingClientRect();
            var wide = natural >= 300 || box.width >= 200 || /w=\\d{3,}/.test(src);
            if (!wide) continue;
            seen[src] = 1;
            out.push({ src: src, y: box.top + window.scrollY });
          }
          out.sort(function (a, b) { return a.y - b.y; });
          return JSON.stringify(out.slice(0, 14).map(function (o) { return o.src; }));
        })()
        """
        guard let json = try? await webView.evaluateJavaScript(script) as? String,
              let data = json.data(using: .utf8),
              let urls = try? JSONDecoder().decode([String].self, from: data) else {
            Self.log.notice("Gallery scan returned nothing")
            return
        }
        collectedImages = urls.compactMap(URL.init(string:))
        Self.log.notice("Gallery scan found \(self.collectedImages.count, privacy: .public) images")
    }

    private func cleanUp() {
        settleTask?.cancel()
        settleTask = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
    }

    private func finish(_ html: String?) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: html)
    }

    /// Reads the page, and gives the bot challenge a second chance to redirect.
    private func capture() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            // Let late-loading product scripts write their markup first.
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, let webView, !Task.isCancelled else { return }

            let html = try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String
            await collectImages(from: webView)

            guard let html else {
                finish(nil)
                return
            }
            // The interstitial reloads itself; wait for the page behind it.
            if html.contains("bm-verify") || html.contains("/interstitial/"), attempts < 2 {
                attempts += 1
                try? await Task.sleep(for: .seconds(3))
                capture()
                return
            }
            finish(html)
        }
    }
}

extension WebProductLoader: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in capture() }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in finish(nil) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in finish(nil) }
    }
}
