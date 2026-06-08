import WebKit

// Cloudflare blocks URLSession on claude.ai — it can't pass the JS bot challenge.
// Solution: make all claude.ai API calls from within a persistent WKWebView using
// JS fetch. The WKWebView is a real browser context, passes Cloudflare automatically,
// and its cookie store holds both the sessionKey and __cf_bm cookies.
@MainActor
final class ClaudeAPIClient: NSObject {
    static let shared = ClaudeAPIClient()

    private let webView: WKWebView
    private var isReady = false
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []
    private var pending: [String: CheckedContinuation<String, Error>] = [:]

    private override init() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10), configuration: config)
        super.init()
        config.userContentController.add(_Bridge(self), name: "bridge")
        webView.navigationDelegate = _NavDelegate(self)
        webView.load(URLRequest(url: URL(string: "https://claude.ai")!))
    }

    // Wait until claude.ai has loaded and Cloudflare cookies are established.
    func ensureReady() async {
        guard !isReady else { return }
        await withCheckedContinuation { readyWaiters.append($0) }
    }

    // Make a JSON API call via WKWebView's JS fetch (bypasses Cloudflare).
    func fetch(path: String, sessionKey: String) async throws -> String {
        await ensureReady()
        await setSessionKeyCookie(sessionKey)

        let id = UUID().uuidString
        let js = """
        (function(){
            var id='\(id)';
            fetch('https://claude.ai\(path)',{
                credentials:'include',
                headers:{'Accept':'application/json'}
            })
            .then(function(r){
                if(r.ok){
                    r.text().then(function(d){
                        window.webkit.messageHandlers.bridge.postMessage({id:id,ok:true,data:d,status:200});
                    });
                } else {
                    window.webkit.messageHandlers.bridge.postMessage({id:id,ok:false,data:'',status:r.status});
                }
            })
            .catch(function(){
                window.webkit.messageHandlers.bridge.postMessage({id:id,ok:false,data:'',status:-1});
            });
        })();
        """

        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            webView.evaluateJavaScript(js) { [weak self] _, error in
                if let error {
                    self?.pending.removeValue(forKey: id)?.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Internal

    fileprivate func didLoad() {
        Task { @MainActor in
            // Give the Cloudflare JS challenge time to complete and set __cf_bm cookie.
            try? await Task.sleep(for: .seconds(1.5))
            isReady = true
            let waiters = readyWaiters
            readyWaiters.removeAll()
            for w in waiters { w.resume() }
        }
    }

    fileprivate func handleMessage(_ body: [String: Any]) {
        guard let id     = body["id"]     as? String,
              let ok     = body["ok"]     as? Bool,
              let cont   = pending.removeValue(forKey: id) else { return }

        if ok, let data = body["data"] as? String {
            cont.resume(returning: data)
        } else {
            let status = body["status"] as? Int ?? 0
            switch status {
            case 401: cont.resume(throwing: NetworkError.authenticationFailed)
            case 403: cont.resume(throwing: NetworkError.blockedByFirewall)
            case 429: cont.resume(throwing: NetworkError.rateLimitExceeded)
            default:  cont.resume(throwing: NetworkError.httpError(statusCode: status))
            }
        }
    }

    private func setSessionKeyCookie(_ value: String) async {
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

// Weak-proxy bridge to avoid WKUserContentController retain cycle.
private final class _Bridge: NSObject, WKScriptMessageHandler {
    weak var client: ClaudeAPIClient?
    init(_ c: ClaudeAPIClient) { client = c }

    nonisolated func userContentController(_ uc: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        Task { @MainActor [weak self] in self?.client?.handleMessage(body) }
    }
}

private final class _NavDelegate: NSObject, WKNavigationDelegate {
    weak var client: ClaudeAPIClient?
    init(_ c: ClaudeAPIClient) { client = c }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in self?.client?.didLoad() }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in self?.client?.didLoad() }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in self?.client?.didLoad() }
    }
}
