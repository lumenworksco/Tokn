import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var usageData: UsageData?
    var isLoading = false
    var errorMessage: String?
    var isSetupComplete = false

    var settings: AppSettings = .default {
        didSet {
            trySaveSettings()
            if oldValue.refreshInterval != settings.refreshInterval {
                startRefreshLoop()
            }
        }
    }

    private let keychain = KeychainRepository()
    private let settingsRepo = SettingsRepository()
    private let usageService = UsageService()
    let updateChecker = UpdateChecker()
    let autoUpdater = AutoUpdater()

    private var refreshTask: Task<Void, Never>?

    func bootstrap() {
        settings = settingsRepo.load()
        isSetupComplete = keychain.exists()

        if isSetupComplete {
            Task {
                await CloudflareSession.shared.establish()
                await refresh(force: true)
            }
            startRefreshLoop()
        }

        Task {
            await CloudflareSession.shared.establish()
            guard let update = await updateChecker.check(), !update.url.isEmpty else { return }
            autoUpdater.startUpdate(from: update.url)
        }
    }

    func refresh(force: Bool = false) async {
        guard isSetupComplete else { usageData = nil; return }
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let key = try keychain.retrieve()
            guard let orgId = settings.cachedOrganizationId else {
                errorMessage = "Missing organization ID. Please re-enter your session key."
                return
            }
            usageData = try await usageService.fetchUsage(sessionKey: key, organizationId: orgId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveSessionKey(_ raw: String) async throws {
        let key = try SessionKey(raw)
        await CloudflareSession.shared.establish()
        let orgId = try await usageService.validateKey(key)
        try keychain.save(key.value)
        settings.cachedOrganizationId = orgId
        isSetupComplete = true
        await refresh(force: true)
        startRefreshLoop()
    }

    func clearSessionKey() throws {
        try keychain.delete()
        settings.cachedOrganizationId = nil
        isSetupComplete = false
        usageData = nil
        errorMessage = nil
        refreshTask?.cancel()
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        let interval = settings.refreshInterval
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                await self?.refresh()
            }
        }
    }

    private func trySaveSettings() {
        try? settingsRepo.save(settings)
    }
}
