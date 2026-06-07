import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var refreshInterval: TimeInterval
    var cachedOrganizationId: String?

    static let `default` = AppSettings(
        refreshInterval: 60,
        cachedOrganizationId: nil
    )

    mutating func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = max(60, min(600, interval))
    }
}
