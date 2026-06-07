import SwiftUI

enum UsageStatus: Sendable {
    case safe
    case warning
    case critical

    var color: Color {
        switch self {
        case .safe:     return Color(red: 0.22, green: 1.00, blue: 0.42)
        case .warning:  return Color(red: 1.00, green: 0.62, blue: 0.04)
        case .critical: return Color(red: 1.00, green: 0.27, blue: 0.23)
        }
    }

    var badgeBackground: Color {
        switch self {
        case .safe:     return Color(red: 0.08, green: 0.30, blue: 0.13)
        case .warning:  return Color(red: 0.30, green: 0.18, blue: 0.02)
        case .critical: return Color(red: 0.30, green: 0.07, blue: 0.06)
        }
    }

    var icon: String {
        switch self {
        case .safe:     return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .safe:     return "Safe"
        case .warning:  return "Warning"
        case .critical: return "Critical"
        }
    }
}
