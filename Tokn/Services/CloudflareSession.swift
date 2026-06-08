import WebKit
import AppKit

// JS fetch() inside WKWebView cannot solve Cloudflare challenges — only full
// page navigation can. Strategy: navigate the WKWebView directly to each API
// URL. WKWebView solves any Cloudflare challenge transparently, then didFinish
// fires and we read document.body.innerText to get the JSON response.
@MainActor
final class ClaudeAPIClient: NSObject {
    static let shared = ClaudeAPIClient()

    private var webView: WKWebView?
    private var apiDelegate: _APIDelegate?
    // Serialises concurrent calls — only one navigation at a time.
    private var pendingCall: CheckedContinuation<String, Error>?

    private override init() { super.init() }

    // Make an API GET to claude.ai, returning the raw JSON response body.
    func get(path: String, sessionKey: String) async throws -> String {
        let wv = ensureWebView()
        await setSessionKeyCookie(sessionKey, on: wv)

        let url = URL(string: "https://claude.ai\(path)")!
        return try await withCheckedThrowingContinuation { cont in
            pendingCall = cont
            wv.load(URLRequest(url: url))
        }
    }

    // MARK: - Internal (called by delegate)

    fileprivate func navigationSucceeded(webView: WKWebView) {
        // Extract the JSON text the WKWebView rendered.
        // For application/json URLs WebKit renders the body in a <pre> tag;
        // innerText gives us the raw JSON string.
        webView.evaluateJavaScript("document.body.innerText") { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let text = result as? String, !text.isEmpty {
                    self.pendingCall?.resume(returning: text)
                } else {
                    self.pendingCall?.resume(throwing: NetworkError.decodingFailed)
                }
                self.pendingCall = nil
            }
        }
    }

    fileprivate func navigationFailed(with error: Error) {
        pendingCall?.resume(throwing: error)
        pendingCall = nil
    }

    // MARK: - Private

    private func ensureWebView() -> WKWebView {
        if let existing = webView { return existing }

        let delegate = _APIDelegate(self)
        apiDelegate = delegate

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        wv.navigationDelegate = delegate
        webView = wv

        // WKWebView creation can flip NSApp activation policy, hiding the menu bar icon.
        NSApp.setActivationPolicy(.accessory)

        return wv
    }

    private func setSessionKeyCookie(_ value: String, on webView: WKWebView) async {
        guard let cookie = HTTPCookie(properties: [
            .name: "sessionKey", .value: value,
            .domain: ".claude.ai", .path: "/", .secure: true
        ]) else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                cont.resume()
            }
        }
    }
}

// MARK: - Delegate

final class _APIDelegate: NSObject, WKNavigationDelegate {
    weak var client: ClaudeAPIClient?
    init(_ c: ClaudeAPIClient) { client = c }

    // Allow everything — Cloudflare challenge pages (403 HTML) must be loaded
    // so that WKWebView can execute the JS challenge and get cf_clearance.
    // The only responses we cancel early are unambiguous auth/rate errors with
    // a JSON content type (i.e. from Claude's backend, not Cloudflare's HTML).
    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor response: WKNavigationResponse,
                             decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard let http = response.response as? HTTPURLResponse else {
            decisionHandler(.allow); return
        }

        let isHTML = (http.mimeType ?? "").contains("text/html")

        switch http.statusCode {
        case 200...299:
            decisionHandler(.allow)
        case 401:
            decisionHandler(.cancel)
            Task { @MainActor [weak self] in
                self?.client?.navigationFailed(with: NetworkError.authenticationFailed)
            }
        case 403 where isHTML:
            // HTML 403 = Cloudflare challenge page — let WKWebView solve it.
            decisionHandler(.allow)
        case 403:
            decisionHandler(.cancel)
            Task { @MainActor [weak self] in
                self?.client?.navigationFailed(with: NetworkError.blockedByFirewall)
            }
        case 429:
            decisionHandler(.cancel)
            Task { @MainActor [weak self] in
                self?.client?.navigationFailed(with: NetworkError.rateLimitExceeded)
            }
        default:
            decisionHandler(.allow)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.client?.navigationSucceeded(webView: webView)
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.client?.navigationFailed(with: NetworkError.networkUnavailable)
        }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFailProvisionalNavigation nav: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.client?.navigationFailed(with: NetworkError.networkUnavailable)
        }
    }
}
