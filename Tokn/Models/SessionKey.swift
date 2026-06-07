import Foundation

enum SessionKeyError: LocalizedError {
    case invalidFormat
    case tooShort

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "Session key must start with 'sk-ant-'"
        case .tooShort:      return "Session key is too short"
        }
    }
}

struct SessionKey: Equatable, Sendable {
    let value: String

    init(_ raw: String) throws {
        let extracted = Self.extract(from: raw)
        guard let key = extracted else { throw SessionKeyError.invalidFormat }
        guard key.hasPrefix("sk-ant-") else { throw SessionKeyError.invalidFormat }
        guard key.count > 10 else { throw SessionKeyError.tooShort }
        self.value = key
    }

    private static func extract(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("sk-ant-") { return trimmed }

        let pattern = #"(?i)sessionKey\s*=\s*([^;\s'"]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: trimmed) else { return nil }
        return String(trimmed[captureRange])
    }
}
