import Foundation

struct UsageData: Equatable, Sendable {
    let sessionUsage: UsageLimit
    let weeklyUsage: UsageLimit
    let lastUpdated: Date

    var freshnessDescription: String {
        let elapsed = Date().timeIntervalSince(lastUpdated)
        if elapsed < 60 { return "just now" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        return "\(Int(elapsed / 3600))h ago"
    }
}
