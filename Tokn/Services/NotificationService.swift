import UserNotifications
import Foundation

@Observable
@MainActor
final class NotificationService {

    // Per-type threshold tracking: key = "Session" or "Weekly", value = highest notified threshold
    private var notifiedAt: [String: Int] = [:]

    func requestPermission() async {
        try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    func check(_ data: UsageData, enabled: Bool) {
        guard enabled else { return }
        checkLimit(data.sessionUsage, name: "Session")
        checkLimit(data.weeklyUsage,  name: "Weekly")
    }

    func resetAll() {
        notifiedAt = [:]
    }

    private func checkLimit(_ limit: UsageLimit, name: String) {
        let pct = Int(limit.utilization)
        let thresholds = [80, 100]

        for threshold in thresholds where pct >= threshold {
            if (notifiedAt[name] ?? 0) < threshold {
                notifiedAt[name] = threshold
                send(name: name, threshold: threshold, pct: pct)
            }
        }

        // Reset when usage drops back below 75% so future spikes re-notify
        if pct < 75 { notifiedAt[name] = 0 }
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
