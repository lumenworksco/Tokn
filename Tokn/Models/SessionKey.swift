import Foundation

enum SessionKeyError: LocalizedError {
    case empty
    case tooShort

    var errorDescription: String? {
        switch self {
        case .empty:    return "Session key cannot be empty"
        case .tooShort: return "That doesn't look like a valid session key — make sure you're copying the full value"
        }
    }
}

struct SessionKey: Equatable, Sendable {
    let value: String

    init(_ raw: String) throws {
        let extracted = Self.extract(from: raw)
        guard let key = extracted, !key.isEmpty else { throw SessionKeyError.empty }
        guard key.count >= 20 else { throw SessionKeyError.tooShort }
        self.value = key
    }

    private static func extract(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Already a bare token — no prefix needed, just return as-is
        if !trimmed.contains("=") && !trimmed.contains(";") { return trimmed }

        // User pasted a full cookie string: "sessionKey=sk-ant-..." or "sessionKey=sometoken"
        let pattern = #"(?i)sessionKey\s*=\s*([^;\s'"]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: trimmed) else { return nil }
        return String(trimmed[captureRange])
    }
}
