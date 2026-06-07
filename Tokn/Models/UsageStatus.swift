import SwiftUI

enum UsageStatus: Sendable {
    case safe
    case warning
    case critical

    var color: Color {
        switch self {
        case .safe:     return .green
        case .warning:  return .orange
        case .critical: return .red
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
