import Foundation

struct UsagePoint: Codable, Sendable {
    let date: Date
    let sessionPct: Double
    let weeklyPct: Double
}

final class UsageHistoryService: @unchecked Sendable {
    private let key    = "com.tokn.usageHistory"
    private let maxPts = 48   // ~48 h at 1-min refresh, or ~8 h at 10-min

    func record(_ data: UsageData) {
        var pts = load()
        pts.append(UsagePoint(
            date: data.lastUpdated,
            sessionPct: data.sessionUsage.utilization,
            weeklyPct:  data.weeklyUsage.utilization
        ))
        if pts.count > maxPts { pts = Array(pts.suffix(maxPts)) }
        if let encoded = try? JSONEncoder().encode(pts) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    func load() -> [UsagePoint] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let pts  = try? JSONDecoder().decode([UsagePoint].self, from: data) else {
            return []
        }
        return pts
    }
}
