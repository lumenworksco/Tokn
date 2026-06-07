import SwiftUI

private let bgColor    = Color(white: 0.10)
private let cardColor  = Color(white: 0.14)
private let divider    = Color(white: 1.0).opacity(0.08)

struct UsageView: View {
    let appModel: AppModel
    @State private var showSettings = false

    var body: some View {
        Group {
            if showSettings {
                SettingsPanel(appModel: appModel, showSettings: $showSettings)
            } else {
                mainView
            }
        }
        .background(bgColor)
        .frame(width: 320)
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            showSettings = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            showSettings = false
        }
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(divider).frame(height: 1)
            if appModel.updateChecker.availableVersion != nil {
                updateBanner
                Rectangle().fill(divider).frame(height: 1)
            }
            content
            Rectangle().fill(divider).frame(height: 1)
            footer
        }
    }

    private var updateBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color(red: 0.55, green: 0.36, blue: 0.96))
                .font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                Text("Update available")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                if let ver = appModel.updateChecker.availableVersion {
                    Text("v\(ver) is ready to install")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.5))
                }
            }
            Spacer()
            updateActionView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.55, green: 0.36, blue: 0.96).opacity(0.10))
    }

    @ViewBuilder
    private var updateActionView: some View {
        switch appModel.autoUpdater.phase {
        case .idle:
            Button("Update") {
                if let url = appModel.updateChecker.downloadURL {
                    appModel.autoUpdater.startUpdate(from: url)
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(red: 0.55, green: 0.36, blue: 0.96))
            .buttonStyle(.plain)
        case .downloading(let p):
            HStack(spacing: 6) {
                ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .frame(width: 60)
                    .tint(Color(red: 0.55, green: 0.36, blue: 0.96))
                Text("\(Int(p * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(white: 0.5))
            }
        case .installing:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Installing…")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.5))
            }
        case .failed(let msg):
            Button("Retry") { appModel.autoUpdater.reset() }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .buttonStyle(.plain)
                .help(msg)
        }
    }

    // MARK: Header
    private var header: some View {
        HStack(alignment: .center) {
            Text("Tokn")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                Task { await appModel.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(white: 0.6))
            }
            .buttonStyle(.plain)
            .disabled(appModel.isLoading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(bgColor)
    }

    // MARK: Content
    @ViewBuilder
    private var content: some View {
        if appModel.isLoading {
            loadingView
        } else if let error = appModel.errorMessage {
            errorView(error)
        } else if let data = appModel.usageData {
            VStack(spacing: 12) {
                UsageCard(icon: "timer", title: "5-Hour Session", limit: data.sessionUsage)
                UsageCard(icon: "calendar", title: "Weekly Usage",   limit: data.weeklyUsage)
            }
            .padding(16)
            .background(bgColor)
        } else {
            loadingView
        }
    }

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Loading…")
                .font(.system(size: 14))
                .foregroundStyle(Color(white: 0.5))
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(bgColor)
    }

    private func errorView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bgColor)
    }

    // MARK: Footer
    private var footer: some View {
        HStack {
            Button("Settings") { showSettings = true }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(bgColor)
    }
}

// MARK: - UsageCard
private struct UsageCard: View {
    let icon: String
    let title: String
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title row
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(limit.status.color)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                StatusBadge(status: limit.status)
            }

            // Large percentage
            Text("\(Int(limit.utilization))%")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundStyle(limit.status.color)
                .monospacedDigit()

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(white: 1.0).opacity(0.10))
                        .frame(height: 10)
                    Capsule()
                        .fill(limit.status.color)
                        .frame(width: max(8, geo.size.width * min(limit.utilization / 100, 1.0)),
                               height: 10)
                        .animation(.easeInOut(duration: 0.4), value: limit.utilization)
                }
            }
            .frame(height: 10)

            // Reset time
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.45))
                Text(limit.resetDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.45))
            }
        }
        .padding(18)
        .background(cardColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - StatusBadge
private struct StatusBadge: View {
    let status: UsageStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.icon)
                .font(.system(size: 12, weight: .semibold))
            Text(status.label)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(status.badgeBackground)
        .clipShape(Capsule())
    }
}

// MARK: - SettingsPanel (inline, no sheet)
private struct SettingsPanel: View {
    let appModel: AppModel
    @Binding var showSettings: Bool
    @State private var selectedInterval: TimeInterval = 60
    @State private var showClearConfirm = false
    @State private var clearError: String?

    private let intervals: [(label: String, value: TimeInterval)] = [
        ("1 minute",   60),
        ("2 minutes",  120),
        ("5 minutes",  300),
        ("10 minutes", 600)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    showSettings = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(white: 0.6))
                }
                .buttonStyle(.plain)
                Text("Settings")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(bgColor)

            Rectangle().fill(divider).frame(height: 1)

            // Body
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Refresh Interval")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.55))
                        .textCase(.uppercase)
                    Picker("", selection: $selectedInterval) {
                        ForEach(intervals, id: \.value) { item in
                            Text(item.label).tag(item.value)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                Rectangle().fill(divider).frame(height: 1)

                if let error = clearError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label("Remove Session Key", systemImage: "trash")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.23))
                .confirmationDialog(
                    "Remove session key?",
                    isPresented: $showClearConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive) {
                        do {
                            try appModel.clearSessionKey()
                            showSettings = false
                        } catch {
                            clearError = error.localizedDescription
                        }
                    }
                } message: {
                    Text("You will need to re-enter your session key to use Tokn.")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bgColor)

            Rectangle().fill(divider).frame(height: 1)

            // Footer
            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(bgColor)
        }
        .onAppear { selectedInterval = appModel.settings.refreshInterval }
        .onChange(of: selectedInterval) {
            appModel.settings.setRefreshInterval(selectedInterval)
        }
    }
}
