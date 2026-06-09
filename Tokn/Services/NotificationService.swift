import UserNotifications
import Foundation

@Observable
@MainActor
final class NotificationService {

    // Per-type threshold tracking: key = "Session" or "Weekly", value = highest notified threshold
    private var notifiedAt: [String: Int] = [:]

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    func check(_ data: UsageData, enabled: Bool, threshold: Int) {
        guard enabled else { return }
        checkLimit(data.sessionUsage, name: "Session", threshold: threshold)
        checkLimit(data.weeklyUsage,  name: "Weekly",  threshold: threshold)
    }

    private func checkLimit(_ limit: UsageLimit, name: String, threshold: Int) {
        let pct = Int(limit.utilization)
        let thresholds = [threshold, 100]

        for t in thresholds where pct >= t {
            if (notifiedAt[name] ?? 0) < t {
                notifiedAt[name] = t
                send(name: name, threshold: t, pct: pct)
            }
        }

        // Reset tracking when usage falls 5pp below the first threshold
        if pct < max(threshold - 5, 0) { notifiedAt[name] = 0 }
    }

    private func send(name: String, threshold: Int, pct: Int) {
        let content = UNMutableNotificationContent()
        if threshold >= 100 {
            content.title = "Claude limit reached"
            content.body  = "\(name) usage is at \(pct)% — you've hit the limit"
        } else {
            content.title = "Claude usage at \(threshold)%"
            content.body  = "\(name) is \(pct)% used"
        }
        content.sound = .default

        let req = UNNotificationRequest(
            identifier: "tokn.\(name.lowercased()).\(threshold)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
