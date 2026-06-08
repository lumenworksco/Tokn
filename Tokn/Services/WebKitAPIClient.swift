import WebKit

// Cloudflare protects claude.ai with a JS challenge that URLSession can't pass (TLS fingerprint).
//
// Strategy: use WKWebView navigation for all requests — both the CF warm-up and API calls.
// The session cookie is set in the URLRequest Cookie header (no WKHTTPCookieStore race).
// URLRequest Cookie headers are MERGED with store-held cookies by WebKit, so if the store has
// a stale sessionKey from a previous account, the server sees duplicate cookies and may use the
// wrong one. Fix: clear all non-CF claude.ai cookies from the store on account switch.
@MainActor
final class WebKitAPIClient: NSObject, WKNavigationDelegate {

    private let webView: WKWebView
    private var pageLoadContinuation: CheckedContinuation<Void, Never>?
    private var lastHTTPStatus = 200
    private var contextReady = false
    private var currentSessionKey: String?   // tracks account; reset on switch

    // CF bot-detection cookies are domain/IP-scoped, not account-scoped — keep them on switch.
    private static let cfCookieNames: Set<String> = ["cf_clearance", "__cf_bm", "_cfuvid"]

    override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/18.3 Safari/605.1.15"
    }

    func get<T: Decodable>(_ path: String, sessionKey: String) async throws -> T {
        // Account switch: clear stale session cookies and force a fresh warm-up.
        // Without this, the store holds the previous account's sessionKey, which WebKit
        // merges with our header → the server sees duplicate cookies → returns [] (wrong account).
        if currentSessionKey != sessionKey {
            currentSessionKey = sessionKey
            contextReady = false
            await clearClaudeSessionCookies()
        }

        let sessionCookie = "sessionKey=\(sessionKey)"

        // First call: load claude.ai to pass Cloudflare's JS challenge and verify the session.
        if !contextReady {
            await navigate(to: "https://claude.ai/", extraCookies: sessionCookie)
            guard webView.url?.host?.hasSuffix("claude.ai") == true,
                  webView.url?.path.hasPrefix("/login") == false else {
                throw NetworkError.sessionExpired
            }
            contextReady = true
        }

        // Navigate directly to the API endpoint.
        // sessionCookie is in the URLRequest header; cf_clearance from the store is merged in.
        await navigate(to: path, extraCookies: sessionCookie, acceptJSON: true)

        guard webView.url?.host?.hasSuffix("claude.ai") == true else {
            contextReady = false
            throw NetworkError.sessionExpired
        }

        switch lastHTTPStatus {
        case 200...299: break
        case 401: throw NetworkError.sessionExpired
        case 403:
            contextReady = false
            let body = await bodyText()
            if body.contains("permission_error") || body.contains("authorization") {
                throw NetworkError.permissionDenied
            }
            throw NetworkError.accessBlocked(detail: body.prefix(200).description)
        case 429: throw NetworkError.rateLimitExceeded
        default: throw NetworkError.httpError(statusCode: lastHTTPStatus)
        }

        guard let jsonText = await bodyText().nilIfEmpty,
              let data = jsonText.data(using: .utf8) else {
            throw NetworkError.decodingFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingFailed
        }
    }

    // Remove all claude.ai session cookies except CF bot-detection ones.
    // Called on account switch to prevent cookie conflicts with the new account.
    private func clearClaudeSessionCookies() async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in await store.allCookies() {
            guard cookie.domain.hasSuffix("claude.ai") else { continue }
            guard !Self.cfCookieNames.contains(cookie.name) else { continue }
            await store.deleteCookie(cookie)
        }
    }

    private func navigate(to urlString: String, extraCookies: String? = nil, acceptJSON: Bool = false) async {
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        if let cookies = extraCookies {
            request.setValue(cookies, forHTTPHeaderField: "Cookie")
        }
        if acceptJSON {
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pageLoadContinuation = continuation
            webView.load(request)
        }
    }

    private func bodyText() async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            webView.evaluateJavaScript(
                "(document.querySelector('pre') || document.body).textContent.trim()"
            ) { result, _ in
                continuation.resume(returning: result as? String ?? "")
            }
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let http = navigationResponse.response as? HTTPURLResponse {
            lastHTTPStatus = http.statusCode
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoadContinuation?.resume()
        pageLoadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pageLoadContinuation?.resume()
        pageLoadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        pageLoadContinuation?.resume()
        pageLoadContinuation = nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
