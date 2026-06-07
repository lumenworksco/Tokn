import Foundation

final class SettingsRepository: @unchecked Sendable {
    private let defaults = UserDefaults.standard
    private let key = "com.tokn.app.settings"

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: key)
    }
}
