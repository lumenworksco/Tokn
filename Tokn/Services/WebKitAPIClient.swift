import WebKit

// Cloudflare protects claude.ai with a JS challenge that sets a cf_clearance cookie.
// URLSession has a non-browser TLS fingerprint that Cloudflare blocks → 403 HTML.
//
// Fix: navigate WKWebView to https://claude.ai/ so Cloudflare runs its JS challenge in
// WebKit's full engine and sets cf_clearance. After confirming we landed on claude.ai
// (not redirected to accounts.anthropic.com, which means the session key is invalid),
// all fetch() calls from the loaded page carry cf_clearance and the session cookie.
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
            let landedOnClaude = await loadContext()
            guard landedOnClaude else {
                // claude.ai redirected us away — session key is invalid or expired.
                throw NetworkError.sessionExpired
            }
            contextReady = true
        }
        // Re-inject after page load in case the server refreshed or cleared the cookie.
        await injectSessionCookie(sessionKey)

        // Include anthropic-client headers that Claude's SPA normally sends.
        // Also check we're still on claude.ai (guards against unexpected redirects).
        let js = """
            if (!window.location.hostname.endsWith('claude.ai')) {
                throw new Error('WRONG_DOMAIN: ' + window.location.hostname);
            }
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
            if msg.hasPrefix("WRONG_DOMAIN") {
                // JS reports we're on the wrong domain — reset so next call re-loads claude.ai.
                contextReady = false
                throw NetworkError.sessionExpired
            }
            if msg.contains("HTTP_401") {
                throw NetworkError.sessionExpired
            }
            if msg.contains("HTTP_403") {
                // Distinguish Cloudflare HTML (need new CF challenge) from Claude API JSON (don't reset).
                if msg.contains("\"type\":\"error\"") || msg.contains("{\"type\":") {
                    if msg.contains("permission_error") || msg.contains("authorization") {
                        throw NetworkError.permissionDenied
                    }
                    throw NetworkError.httpError(statusCode: 403)
                }
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

    // Navigate to claude.ai. Returns true if we land on claude.ai (session valid + CF passed),
    // false if redirected elsewhere (e.g. accounts.anthropic.com = session expired).
    private func loadContext() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pageLoadContinuation = continuation
            webView.load(URLRequest(
                url: URL(string: "https://claude.ai/")!,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 30
            ))
        }
        let host = webView.url?.host ?? ""
        return host.hasSuffix("claude.ai")
    }

    private func extractStatus(_ msg: String) -> Int {
        let digits = msg.components(separatedBy: "HTTP_").last ?? ""
        return Int(digits.prefix(3)) ?? 0
    }

    // MARK: WKNavigationDelegate — just signal completion; domain check happens in loadContext().

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
