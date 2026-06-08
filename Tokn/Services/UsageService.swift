import Foundation

enum AppError: LocalizedError {
    case noSessionKey
    case authenticationFailed
    case organizationNotFound
    case networkError(NetworkError)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .noSessionKey:             return "No session key saved. Click to set up."
        case .authenticationFailed:     return "Session key invalid or expired. Please re-enter."
        case .organizationNotFound:     return "Could not find your Claude organization."
        case .networkError(let e):      return e.localizedDescription
        case .unknown(let e):           return e.localizedDescription
        }
    }
}

private struct Organization: Decodable {
    let uuid: String
}

final class UsageService {
    private let network = NetworkService()
    private let baseURL = "https://claude.ai/api"

    func validateKey(_ key: SessionKey) async throws -> String {
        let orgs: [Organization] = try await network.get(
            "\(baseURL)/organizations",
            sessionKey: key.value
        )
        guard let first = orgs.first else {
            throw AppError.organizationNotFound
        }
        return first.uuid
    }

    func fetchUsage(sessionKey: String, organizationId: String) async throws -> UsageData {
        do {
            let response: UsageAPIResponse = try await network.get(
                "\(baseURL)/organizations/\(organizationId)/usage",
                sessionKey: sessionKey
            )
            return try response.toUsageData()
        } catch let error as NetworkError {
            if case .sessionExpired = error { throw AppError.authenticationFailed }
            throw AppError.networkError(error)
        } catch {
            throw AppError.unknown(error)
        }
    }
}
