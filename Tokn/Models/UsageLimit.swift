import Foundation

struct UsageLimit: Equatable, Sendable {
    let utilization: Double
    let resetAt: Date

    var percentage: Double { utilization }

    var status: UsageStatus {
        switch utilization {
        case 0..<50: return .safe
        case 50..<80: return .warning
        default:     return .critical
        }
    }

    var resetDescription: String {
        let remaining = resetAt.timeIntervalSinceNow
        guard remaining > 0 else { return "now" }
        let minute: TimeInterval = 60
        let hour: TimeInterval = 3600
        let day: TimeInterval = 86400
        if remaining < hour {
            let m = max(1, Int(ceil(remaining / minute)))
            return "in \(m)m"
        }
        if remaining < day {
            let h = Int(ceil(remaining / hour))
            return "in \(h)h"
        }
        let h = Int(ceil(remaining / hour))
        let d = h / 24
        let rem = h % 24
        return rem == 0 ? "in \(d)d" : "in \(d)d \(rem)h"
    }

    var isExceeded: Bool { utilization >= 100 }
}
