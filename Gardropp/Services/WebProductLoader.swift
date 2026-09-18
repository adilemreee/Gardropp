import UIKit
import WebKit

/// Some shops (Zara among them) answer a plain HTTP request with a JavaScript
/// bot challenge instead of the product page. Running the page in a real
/// WebKit view clears the challenge exactly as Safari would, and the rendered
/// DOM then carries the same metadata every other shop publishes up front.
@MainActor
final class WebProductLoader: NSObject {

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?
    private var settleTask: Task<Void, Never>?
    private var attempts = 0

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

            let script = "document.documentElement.outerHTML"
            let html = try? await webView.evaluateJavaScript(script) as? String

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
