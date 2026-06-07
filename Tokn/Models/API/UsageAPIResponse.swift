import Foundation

struct UsageAPIResponse: Decodable {
    let fiveHour: LimitResponse
    let sevenDay: LimitResponse

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct LimitResponse: Decodable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

extension UsageAPIResponse {
    func toUsageData() throws -> UsageData {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parseDate(_ raw: String?, fallback: TimeInterval) -> Date {
            guard let raw, let date = formatter.date(from: raw) else {
                return Date().addingTimeInterval(fallback)
            }
            return date
        }

        return UsageData(
            sessionUsage: UsageLimit(
                utilization: fiveHour.utilization,
                resetAt: parseDate(fiveHour.resetsAt, fallback: 5 * 3600)
            ),
            weeklyUsage: UsageLimit(
                utilization: sevenDay.utilization,
                resetAt: parseDate(sevenDay.resetsAt, fallback: 7 * 86400)
            ),
            lastUpdated: Date()
        )
    }
}
