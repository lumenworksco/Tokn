import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case authenticationFailed
    case blockedByFirewall
    case rateLimitExceeded
    case httpError(statusCode: Int)
    case decodingFailed
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:            return "Invalid URL"
        case .authenticationFailed:  return "Authentication failed — session key invalid or expired"
        case .blockedByFirewall:     return "Request blocked — open claude.ai in Safari once, then try again"
        case .rateLimitExceeded:     return "Rate limit exceeded, try again shortly"
        case .httpError(let code):   return "HTTP error \(code)"
        case .decodingFailed:        return "Unexpected response from Claude API"
        case .networkUnavailable:    return "Network unavailable"
        }
    }
}

actor NetworkService {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func get<T: Decodable>(_ urlString: String, sessionKey: String) async throws -> T {
        guard urlString.hasPrefix("https://") else { throw NetworkError.invalidURL }

        // Claude.ai is behind Cloudflare bot protection that blocks URLSession.
        // Route through WKWebView-based client which passes as a real browser.
        if urlString.hasPrefix("https://claude.ai") {
            let path = String(urlString.dropFirst("https://claude.ai".count))
            let json = try await ClaudeAPIClient.shared.fetch(path: path, sessionKey: sessionKey)
            guard let data = json.data(using: .utf8) else { throw NetworkError.decodingFailed }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(T.self, from: data)
            } catch {
                throw NetworkError.decodingFailed
            }
        }

        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.networkUnavailable }

        switch http.statusCode {
        case 200...299: break
        case 401:       throw NetworkError.authenticationFailed
        case 403:       throw NetworkError.blockedByFirewall
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
