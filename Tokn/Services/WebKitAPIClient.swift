import WebKit

// Cloudflare protects claude.ai with a JS challenge that URLSession can't pass (TLS fingerprint).
//
// Strategy: use WKWebView navigation for all requests — both the CF warm-up and API calls.
// The session cookie is set directly in the URLRequest Cookie header (not via WKHTTPCookieStore,
// which has a known async propagation race where setCookie() completes but the networking layer
// hasn't picked it up before the next navigation starts). URLRequest Cookie headers are merged
// with any store-held cookies (e.g. cf_clearance set during warm-up), so CF bypass is preserved.
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
        let sessionCookie = "sessionKey=\(sessionKey)"

        // First call: load claude.ai to pass Cloudflare's JS challenge and verify the session.
        // The session cookie is in the URLRequest header — no WKHTTPCookieStore race condition.
        if !contextReady {
            await navigate(to: "https://claude.ai/", extraCookies: sessionCookie)
            guard webView.url?.host?.hasSuffix("claude.ai") == true,
                  webView.url?.path.hasPrefix("/login") == false else {
                // Session invalid — redirected to login or accounts.anthropic.com.
                throw NetworkError.sessionExpired
            }
            contextReady = true
        }

        // Navigate directly to the API endpoint.
        // sessionCookie is in the URLRequest header; cf_clearance (set by Cloudflare during
        // warm-up) is merged in automatically from the WKHTTPCookieStore.
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

    // Navigate and wait for completion. extraCookies is merged with any store-held cookies.
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

    // Read the page body. WebKit wraps a JSON-content-type response in <pre>,
    // so this handles both the <pre>-wrapped case and a plain body fallback.
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
