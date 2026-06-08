import WebKit
import AppKit

// All claude.ai API calls go through WKWebView JS fetch to bypass Cloudflare.
// IMPORTANT: WKWebView creation in a menu bar (LSUIElement) app changes the
// NSApp activation policy, hiding the menu bar icon. We fix this by:
//   1. Creating the WKWebView lazily (only on first API call, not at startup)
//   2. Re-asserting .accessory policy right after creation
@MainActor
final class ClaudeAPIClient: NSObject {
    static let shared = ClaudeAPIClient()

    private var webView: WKWebView?
    private var messageRouter: _MessageRouter?
    private var navDelegate: _NavDelegate?
    private var isReady = false
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []
    private var pending: [String: CheckedContinuation<String, Error>] = [:]

    private override init() { super.init() }

    // MARK: - Public API

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
                        window.webkit.messageHandlers.bridge.postMessage(
                            {id:id,ok:true,data:d,status:200}
                        );
                    });
                } else {
                    window.webkit.messageHandlers.bridge.postMessage(
                        {id:id,ok:false,data:'',status:r.status}
                    );
                }
            })
            .catch(function(){
                window.webkit.messageHandlers.bridge.postMessage(
                    {id:id,ok:false,data:'',status:-1}
                );
            });
        })();
        """

        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            webView?.evaluateJavaScript(js) { [weak self] _, error in
                if let error {
                    self?.pending.removeValue(forKey: id)?.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Internal

    fileprivate func didLoad() {
        Task { @MainActor in
            // Give the Cloudflare JS challenge time to run and set __cf_bm cookie.
            try? await Task.sleep(for: .seconds(1.5))
            isReady = true
            let waiters = readyWaiters
            readyWaiters.removeAll()
            for w in waiters { w.resume() }
        }
    }

    fileprivate func handleMessage(_ body: [String: Any]) {
        guard let id   = body["id"]   as? String,
              let ok   = body["ok"]   as? Bool,
              let cont = pending.removeValue(forKey: id) else { return }

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

    // MARK: - Private

    private func ensureReady() async {
        if isReady { return }
        if webView == nil { buildWebView() }
        await withCheckedContinuation { readyWaiters.append($0) }
    }

    private func buildWebView() {
        // Set up the message router BEFORE WKWebView is created so the
        // userContentController is correctly copied into the web view.
        let router = _MessageRouter(self)
        messageRouter = router

        let config = WKWebViewConfiguration()
        config.userContentController.add(router, name: "bridge")

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        let nav = _NavDelegate(self)
        navDelegate = nav
        wv.navigationDelegate = nav
        webView = wv

        // Re-assert accessory policy — WKWebView creation can change it,
        // which would hide the menu bar icon.
        NSApp.setActivationPolicy(.accessory)

        wv.load(URLRequest(url: URL(string: "https://claude.ai")!))
    }

    private func setSessionKeyCookie(_ value: String) async {
        guard let wv = webView,
              let cookie = HTTPCookie(properties: [
                  .name: "sessionKey", .value: value,
                  .domain: ".claude.ai", .path: "/", .secure: true
              ]) else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            wv.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                cont.resume()
            }
        }
    }
}

// Separate object to hold the WKScriptMessageHandler (avoids retain cycle with
// WKUserContentController, which holds a strong reference to its handlers).
final class _MessageRouter: NSObject, WKScriptMessageHandler {
    weak var client: ClaudeAPIClient?
    init(_ c: ClaudeAPIClient) { client = c }

    nonisolated func userContentController(_ uc: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        Task { @MainActor [weak self] in self?.client?.handleMessage(body) }
    }
}

final class _NavDelegate: NSObject, WKNavigationDelegate {
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
