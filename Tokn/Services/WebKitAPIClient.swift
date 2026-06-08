import WebKit

// Cloudflare on claude.ai blocks URLSession via TLS fingerprinting and also blocks
// WKWebView with a private cookie store (missing cf_clearance) and wrong User-Agent.
//
// Fix: use the system-default WebKit data store (shared with Safari — contains the
// real cf_clearance and other Cloudflare cookies), set a Safari User-Agent, and
// load an actual claude.ai page before making API calls so all requests come from
// a real, Cloudflare-trusted document context.
@MainActor
final class WebKitAPIClient: NSObject, WKNavigationDelegate {

    private let webView: WKWebView
    private var pageLoadContinuation: CheckedContinuation<Void, Never>?
    private var contextReady = false

    override init() {
        let config = WKWebViewConfiguration()
        // Default store shares cookies with Safari, including cf_clearance issued
        // to the user's real browser sessions on claude.ai.
        config.websiteDataStore = .default()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        super.init()
        webView.navigationDelegate = self
        // Present as Safari so Cloudflare's bot detection accepts the requests.
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/18.3 Safari/605.1.15"
    }

    func get<T: Decodable>(_ path: String, sessionKey: String) async throws -> T {
        await injectSessionCookie(sessionKey)
        if !contextReady { await loadContext() }

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

    // Inject (or replace) the session cookie. Goes into the shared Safari store,
    // alongside cf_clearance and other cookies Cloudflare expects.
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

    // Load a real, lightweight page from claude.ai so subsequent fetch() calls
    // originate from a genuine claude.ai document context (not a local string).
    private func loadContext() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pageLoadContinuation = continuation
            let req = URLRequest(
                url: URL(string: "https://claude.ai/robots.txt")!,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 15
            )
            webView.load(req)
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
        // Even if the page itself fails (e.g. 403 on robots.txt), mark context ready
        // and let the fetch() call surface the real error.
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
