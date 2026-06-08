import WebKit

// Cloudflare's bot protection blocks plain URLSession requests from fresh machines
// that haven't visited claude.ai in Safari. Fix: load claude.ai in a hidden WKWebView
// (which executes the JS challenge), then copy the resulting __cf_bm cookie into
// HTTPCookieStorage.shared so all subsequent URLSession requests pass the check.
@MainActor
final class CloudflareSession: NSObject {
    static let shared = CloudflareSession()
    private(set) var isEstablished = false
    private var ongoingTask: Task<Void, Never>?

    func establish() async {
        guard !isEstablished else { return }
        if let existing = ongoingTask {
            await existing.value
            return
        }
        let task = Task { @MainActor in await self._establish() }
        ongoingTask = task
        await task.value
    }

    private func _establish() async {
        let loader = _WebLoader()
        await loader.load(URL(string: "https://claude.ai")!)
        let cookies = await withCheckedContinuation { (cont: CheckedContinuation<[HTTPCookie], Never>) in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cont.resume(returning: $0) }
        }
        for cookie in cookies where cookie.domain.hasSuffix("claude.ai") {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        isEstablished = true
        ongoingTask = nil
    }
}

@MainActor
private final class _WebLoader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Never>?

    func load(_ url: URL) async {
        await withCheckedContinuation { cont in
            continuation = cont
            let wv = WKWebView(frame: CGRect(x: -1, y: -1, width: 1, height: 1))
            wv.navigationDelegate = self
            webView = wv
            wv.load(URLRequest(url: url))
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            // Give the Cloudflare JS challenge time to complete and set cookies
            try? await Task.sleep(for: .seconds(2))
            self?.finish()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in self?.finish() }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in self?.finish() }
    }

    private func finish() {
        webView = nil
        continuation?.resume()
        continuation = nil
    }
}
