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

    var label: String {
        switch self {
        case .safe:     return "Safe"
        case .warning:  return "Warning"
        case .critical: return "Critical"
        }
    }
}
