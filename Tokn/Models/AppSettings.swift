import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var refreshInterval: TimeInterval
    var cachedOrganizationId: String?
    var notificationsEnabled: Bool

    static let `default` = AppSettings(
        refreshInterval: 60,
        cachedOrganizationId: nil,
        notificationsEnabled: true
    )

    mutating func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = max(60, min(600, interval))
    }
}
