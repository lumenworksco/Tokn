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
        guard remaining > 0 else { return "Resets now" }
        let minute: TimeInterval = 60
        let hour: TimeInterval = 3600
        let day: TimeInterval = 86400
        if remaining < hour {
            let m = max(1, Int(ceil(remaining / minute)))
            return "Resets in \(m) \(m == 1 ? "minute" : "minutes")"
        }
        if remaining < day {
            let h = Int(ceil(remaining / hour))
            return "Resets in \(h) \(h == 1 ? "hour" : "hours")"
        }
        let totalH = Int(ceil(remaining / hour))
        let d = totalH / 24
        let h = totalH % 24
        if h == 0 { return "Resets in \(d) \(d == 1 ? "day" : "days")" }
        return "Resets in \(d) \(d == 1 ? "day" : "days") \(h) \(h == 1 ? "hour" : "hours")"
    }

    var shortResetDescription: String {
        let remaining = resetAt.timeIntervalSinceNow
        guard remaining > 0 else { return "now" }
        let hour: TimeInterval = 3600
        let day: TimeInterval = 86400
        if remaining < hour { return "\(max(1, Int(ceil(remaining / 60))))m" }
        if remaining < day  { return "\(Int(ceil(remaining / hour)))h" }
        let d = Int(ceil(remaining / hour)) / 24
        return "\(d)d"
    }

    var isExceeded: Bool { utilization >= 100 }
}
