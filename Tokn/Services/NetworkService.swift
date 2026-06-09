import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case sessionExpired          // HTTP 401
    case accessBlocked(detail: String)  // HTTP 403 — Cloudflare or permission
    case permissionDenied        // API-level 403 with permission_error
    case rateLimitExceeded
    case httpError(statusCode: Int)
    case decodingFailed
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Invalid URL"
        case .sessionExpired:       return "Session key invalid or expired. Please re-enter."
        case .accessBlocked(let d): return "Request blocked (403)\(d.isEmpty ? "" : " — \(d)")"
        case .permissionDenied:     return "Permission denied — organization access unavailable"
        case .rateLimitExceeded:    return "Rate limit exceeded, try again shortly"
        case .httpError(let c):     return "HTTP \(c) from Claude API"
        case .decodingFailed:       return "Unexpected response format from Claude API"
        case .networkUnavailable:   return "Network unavailable"
        }
    }
}

actor NetworkService {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        // Don't let URLSession merge cookies from the system store into our requests.
        // We set the Cookie header manually, so any automatic cookie injection could
        // send a stale session key alongside ours and confuse the server.
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        self.session = URLSession(configuration: config)
    }

    func get<T: Decodable>(_ urlString: String, sessionKey: String) async throws -> T {
        guard urlString.hasPrefix("https://"),
              let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)",       forHTTPHeaderField: "Cookie")
        request.setValue("application/json",               forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://claude.ai",  forHTTPHeaderField: "Referer")
        request.setValue("claude.ai",          forHTTPHeaderField: "Origin")
        request.setValue("same-origin",        forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("cors",               forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("empty",              forHTTPHeaderField: "Sec-Fetch-Dest")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.networkUnavailable
        }

        switch http.statusCode {
        case 200...299: break
        case 401:       throw NetworkError.sessionExpired
        case 403:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NetworkError.accessBlocked(detail: body.prefix(300).description)
        case 429:       throw NetworkError.rateLimitExceeded
        default:        throw NetworkError.httpError(statusCode: http.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingFailed
        }
    }
}
