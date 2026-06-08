import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var refreshInterval: TimeInterval
    var cachedOrganizationId: String?
    var notificationsEnabled: Bool
    var launchAtLogin: Bool

    static let `default` = AppSettings(
        refreshInterval: 60,
        cachedOrganizationId: nil,
        notificationsEnabled: true,
        launchAtLogin: false
    )

    mutating func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = max(60, min(600, interval))
    }
}
