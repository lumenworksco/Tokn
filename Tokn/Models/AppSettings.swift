import Foundation

enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
    case dotAndPercent = "dot + %"
    case percentOnly   = "% only"
    case dotOnly       = "dot only"
}

struct AppSettings: Codable, Equatable, Sendable {
    var refreshInterval: TimeInterval
    var cachedOrganizationId: String?
    var notificationsEnabled: Bool
    var launchAtLogin: Bool
    var menuBarStyle: MenuBarStyle

    static let `default` = AppSettings(
        refreshInterval: 60,
        cachedOrganizationId: nil,
        notificationsEnabled: true,
        launchAtLogin: false,
        menuBarStyle: .dotAndPercent
    )

    mutating func setRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = max(60, min(600, interval))
    }
}
