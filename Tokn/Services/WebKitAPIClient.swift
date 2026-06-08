import WebKit

// Cloudflare protects claude.ai with a JS challenge that sets a cf_clearance cookie.
// URLSession and WKWebView with a bare data store both lack this cookie → 403.
//
// Fix: navigate the WKWebView to https://claude.ai/ so Cloudflare runs its JS
// challenge in WebKit's full engine and sets cf_clearance in our cookie store.
// After that, all fetch() calls from within the loaded page carry cf_clearance
// and are accepted. On a 403, contextReady is reset so the next call re-runs the
// challenge rather than retrying without the cookie.
@MainActor
final class WebKitAPIClient: NSObject, WKNavigationDelegate {

    private let webView: WKWebView
    private var pageLoadContinuation: CheckedContinuation<Void, Never>?
    private var contextReady = false

    override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        super.init()
        webView.navigationDelegate = self
        // Match Safari's User-Agent — Cloudflare checks for the Version/X Safari/X suffix.
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/18.3 Safari/605.1.15"
    }

    func get<T: Decodable>(_ path: String, sessionKey: String) async throws -> T {
        if !contextReady {
            await injectSessionCookie(sessionKey)
            await loadContext()
        }
        // Re-inject after page load — the server may have refreshed or cleared the cookie.
        await injectSessionCookie(sessionKey)

        // Include anthropic-client headers that Claude's SPA normally sends.
        // Omit Cookie header (forbidden in browser fetch — WebKit sends it automatically).
        let js = """
            const r = await fetch('\(path)', {
                credentials: 'include',
                headers: {
                    'Accept': 'application/json, text/plain, */*',
                    'anthropic-client-version': '1.0.0',
                    'anthropic-client-platform': 'web_claude_ai'
                }
            });
            if (!r.ok) {
                let body = '';
                try { body = (await r.text()).substring(0, 300); } catch {}
                throw new Error('HTTP_' + r.status + ': ' + body);
            }
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
            if msg.contains("HTTP_401") {
                throw NetworkError.sessionExpired
            }
            if msg.contains("HTTP_403") {
                // Distinguish Cloudflare HTML (reset context) from Claude API JSON (don't reset).
                if msg.contains("\"type\":\"error\"") || msg.contains("{\"type\":") {
                    // Claude API permission error — CF is satisfied, don't reset context.
                    if msg.contains("permission_error") || msg.contains("authorization") {
                        throw NetworkError.permissionDenied
                    }
                    throw NetworkError.httpError(statusCode: 403)
                }
                // Cloudflare HTML 403 — need a new CF challenge.
                contextReady = false
                throw NetworkError.accessBlocked(detail: msg)
            }
            if msg.contains("HTTP_") { throw NetworkError.httpError(statusCode: extractStatus(msg)) }
            throw NetworkError.networkUnavailable
        }
    }

    // Inject (or replace) the session cookie so claude.ai sees us as logged in.
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

    // Navigate to claude.ai's main page. Cloudflare runs its JS challenge in WebKit,
    // sets cf_clearance, and only then does didFinish fire. All subsequent fetch()
    // calls within this WKWebView carry the valid cf_clearance.
    private func loadContext() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pageLoadContinuation = continuation
            webView.load(URLRequest(
                url: URL(string: "https://claude.ai/")!,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 30
            ))
        }
    }

    private func extractStatus(_ msg: String) -> Int {
        let digits = msg.components(separatedBy: "HTTP_").last ?? ""
        return Int(digits.prefix(3)) ?? 0
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        contextReady = true
        pageLoadContinuation?.resume()
        pageLoadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        contextReady = true
        pageLoadContinuation?.resume()
        pageLoadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        contextReady = true
        pageLoadContinuation?.resume()
        pageLoadContinuation = nil
    }
}
