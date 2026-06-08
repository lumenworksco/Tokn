import WebKit

// URLSession is blocked by Cloudflare on claude.ai via TLS fingerprinting.
// WKWebView uses WebKit's networking stack (same TLS fingerprint as Safari),
// which Cloudflare recognises as a real browser.
//
// Strategy: load a minimal HTML document at the claude.ai origin (no network
// request for the page itself), then run fetch() via JavaScript so all API
// calls go through WebKit's network stack with the correct session cookie.
@MainActor
final class WebKitAPIClient: NSObject, WKNavigationDelegate {

    private let webView: WKWebView
    private var originLoadContinuation: CheckedContinuation<Void, Error>?
    private var originLoaded = false

    override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    func get<T: Decodable>(_ path: String, sessionKey: String) async throws -> T {
        await injectSessionCookie(sessionKey)
        if !originLoaded { try await loadOrigin() }

        let js = """
            const r = await fetch('\(path)', {
                credentials: 'include',
                headers: { 'Accept': 'application/json' }
            });
            if (!r.ok) throw new Error('HTTP_' + r.status);
            return r.text();
        """

        let jsResult: Result<Any, Error> = await withCheckedContinuation { continuation in
            webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
                continuation.resume(returning: result)
            }
        }

        switch jsResult {
        case .success(let value):
            guard let str = value as? String, let data = str.data(using: .utf8) else {
                throw NetworkError.decodingFailed
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        case .failure(let err):
            let msg = (err as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? err.localizedDescription
            if msg.contains("HTTP_401") { throw NetworkError.sessionExpired }
            if msg.contains("HTTP_403") { throw NetworkError.accessBlocked }
            if msg.contains("HTTP_") { throw NetworkError.httpError(statusCode: extractStatus(msg)) }
            throw NetworkError.networkUnavailable
        }
    }

    // Inject (or replace) the session cookie in WebKit's persistent cookie store.
    private func injectSessionCookie(_ value: String) async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for old in await store.allCookies() where old.name == "sessionKey" {
            await store.deleteCookie(old)
        }
        guard let cookie = HTTPCookie(properties: [
            .domain: "claude.ai", .path: "/",
            .name: "sessionKey", .value: value,
            .secure: "TRUE"
        ]) else { return }
        await store.setCookie(cookie)
    }

    // loadHTMLString with an https:// baseURL sets the document origin to claude.ai
    // without making any network request. Subsequent fetch() calls are same-origin.
    private func loadOrigin() async throws {
        try await withCheckedThrowingContinuation { continuation in
            originLoadContinuation = continuation
            webView.loadHTMLString("<html><body></body></html>",
                                   baseURL: URL(string: "https://claude.ai")!)
        }
    }

    private func extractStatus(_ msg: String) -> Int {
        let digits = msg.components(separatedBy: "HTTP_").last ?? ""
        return Int(digits.prefix(3)) ?? 0
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        originLoaded = true
        originLoadContinuation?.resume()
        originLoadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        originLoadContinuation?.resume(throwing: error)
        originLoadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        originLoadContinuation?.resume(throwing: error)
        originLoadContinuation = nil
    }
}
