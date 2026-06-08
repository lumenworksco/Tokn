import WebKit

// Cloudflare protects claude.ai with a JS challenge that URLSession can't pass (TLS fingerprint).
//
// Strategy: use WKWebView for all networking — both the CF warm-up and the API calls.
// Navigating directly to an API URL sends all cookies (sessionKey, cf_clearance, etc.)
// exactly as a real browser would, bypassing every credential-injection problem.
// callAsyncJavaScript(fetch()) was unreliable because injected JS may not carry the auth
// context that Claude's SPA establishes internally; direct navigation has no such issue.
@MainActor
final class WebKitAPIClient: NSObject, WKNavigationDelegate {

    private let webView: WKWebView
    private var pageLoadContinuation: CheckedContinuation<Void, Never>?
    private var lastHTTPStatus = 200
    private var contextReady = false  // CF challenge passed + session confirmed valid

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
        await injectSessionCookie(sessionKey)

        // First call: load claude.ai to pass Cloudflare's JS challenge and verify the session.
        if !contextReady {
            await navigate(to: "https://claude.ai/")
            guard webView.url?.host?.hasSuffix("claude.ai") == true else {
                // Redirected away from claude.ai — session key is invalid/expired.
                throw NetworkError.sessionExpired
            }
            contextReady = true
            // Re-inject in case the page load cleared/replaced our cookie.
            await injectSessionCookie(sessionKey)
        }

        // Navigate directly to the API endpoint with Accept: application/json.
        // WebKit sends all cookies (sessionKey + cf_clearance) automatically — no JS injection needed.
        await navigate(to: path, acceptJSON: true)

        // If we got redirected to a login page, the session expired.
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

        // WebKit wraps a JSON response in <pre>; textContent gives the raw JSON.
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

    // Inject (or replace) the session cookie for claude.ai.
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

    // Navigate to a URL and wait for the load to finish (or fail).
    // acceptJSON: true adds Accept: application/json so the server returns JSON, not an HTML page.
    private func navigate(to urlString: String, acceptJSON: Bool = false) async {
        guard let url = URL(string: urlString) else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        if acceptJSON {
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pageLoadContinuation = continuation
            webView.load(request)
        }
    }

    // Read the page body. WebKit wraps a JSON-content-type response in <pre>,
    // so this handles both the <pre>-wrapped case and a plain body fallback.
    private func bodyText() async -> String {
        return await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            webView.evaluateJavaScript(
                "(document.querySelector('pre') || document.body).textContent.trim()"
            ) { result, _ in
                continuation.resume(returning: result as? String ?? "")
            }
        }
    }

    // MARK: WKNavigationDelegate

    // Capture the HTTP status code from the response before the page body is processed.
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
