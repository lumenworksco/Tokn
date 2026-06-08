import SwiftUI

private let bg      = Color(red: 0.085, green: 0.085, blue: 0.11)
private let cardBg  = Color(white: 1, opacity: 0.055)
private let stroke  = Color(white: 1, opacity: 0.08)
private let div     = Color(white: 1, opacity: 0.07)
private let accent  = Color(red: 0.55, green: 0.36, blue: 0.96)

struct UsageView: View {
    let appModel: AppModel
    @State private var showSettings = false
    @State private var easterEggActive = false

    var body: some View {
        Group {
            if showSettings {
                SettingsPanel(appModel: appModel, showSettings: $showSettings)
                    .transition(.push(from: .trailing))
            } else {
                mainView
                    .transition(.push(from: .leading))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: showSettings)
        .frame(width: 280)
        .background(bg)
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification))   { _ in showSettings = false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in showSettings = false }
    }

    // MARK: Main

    private var mainView: some View {
        VStack(spacing: 0) {
            header
            div.frame(height: 1)
            if appModel.updateChecker.availableVersion != nil {
                updateBanner
                div.frame(height: 1)
            }
            content
            div.frame(height: 1)
            footer
        }
    }

    private var header: some View {
        HStack {
            // Triple-tap the title for the easter egg
            Text(easterEggActive ? "made with ♥" : "Tokn")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(easterEggActive ? accent : .white)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: easterEggActive)
                .onTapGesture(count: 3) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                        easterEggActive = true
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation(.easeOut(duration: 0.4)) { easterEggActive = false }
                    }
                }

            Spacer()

            // Native ProgressView when loading — always centred, never wobbles
            Button { Task { await appModel.refresh(force: true) } } label: {
                Group {
                    if appModel.isLoading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(white: 0.45))
                    }
                }
                .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if appModel.isLoading && appModel.usageData == nil {
            loadingView
        } else if let error = appModel.errorMessage, appModel.usageData == nil {
            errorView(error)
        } else if let data = appModel.usageData {
            VStack(spacing: 8) {
                UsageCard(icon: "timer",    title: "5h Session", limit: data.sessionUsage, delay: 0)
                UsageCard(icon: "calendar", title: "Weekly",     limit: data.weeklyUsage,  delay: 0.05)
            }
            .padding(10)
        } else {
            loadingView
        }
    }

    private var loadingView: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Loading…")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(white: 0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private func errorView(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(msg)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    // MARK: Update banner

    private var updateBanner: some View {
        HStack(spacing: 8) {
            Circle().fill(accent).frame(width: 6, height: 6)
            Text("v\(appModel.updateChecker.availableVersion ?? "") available")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.65))
            Spacer()
            updateAction
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(accent.opacity(0.07))
    }

    @ViewBuilder
    private var updateAction: some View {
        switch appModel.autoUpdater.phase {
        case .idle:
            // Auto-download starts immediately; idle here means the Task is in flight
            ProgressView().controlSize(.mini).tint(accent)
        case .downloading(let p):
            HStack(spacing: 5) {
                ProgressView(value: p).progressViewStyle(.linear).frame(width: 48).tint(accent)
                Text("\(Int(p * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(white: 0.4))
            }
        case .installing:
            Text("installing…")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.4))
        case .failed:
            Button("retry") {
                if let url = appModel.updateChecker.downloadURL {
                    appModel.autoUpdater.startUpdate(from: url)
                }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.orange)
            .buttonStyle(.plain)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("settings") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { showSettings = true }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color(white: 0.38))
            .buttonStyle(.plain)
            Spacer()
            Button("quit") { NSApplication.shared.terminate(nil) }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.38))
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - UsageCard

private struct UsageCard: View {
    let icon: String
    let title: String
    let limit: UsageLimit
    let delay: Double

    // Initialised from limit so the card never starts at 0 on (re-)appear
    @State private var displayed: Double
    @State private var fillFraction: Double

    init(icon: String, title: String, limit: UsageLimit, delay: Double) {
        self.icon  = icon
        self.title = title
        self.limit = limit
        self.delay = delay
        _displayed    = State(initialValue: limit.utilization)
        _fillFraction = State(initialValue: min(limit.utilization / 100, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Title + percentage row
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.38))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.62))
                Spacer()
                Text("\(Int(displayed))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(limit.status.color)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4, dampingFraction: 0.82), value: displayed)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(white: 1, opacity: 0.07))
                        .frame(height: 4)
                    Capsule()
                        .fill(limit.status.color)
                        .frame(width: max(3, geo.size.width * fillFraction), height: 4)
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: fillFraction)
                }
            }
            .frame(height: 4)

            // Reset + status row
            HStack {
                Text(limit.resetDescription)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(white: 0.28))
                Spacer()
                HStack(spacing: 3) {
                    Circle().fill(limit.status.color).frame(width: 5, height: 5)
                    Text(limit.status.label.lowercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(limit.status.color.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cardBg)
                .strokeBorder(stroke, lineWidth: 0.5)
        )
        .onChange(of: limit.utilization) { _, newVal in
            displayed    = newVal
            fillFraction = min(newVal / 100, 1)
        }
    }
}

// MARK: - SettingsPanel

private struct SettingsPanel: View {
    let appModel: AppModel
    @Binding var showSettings: Bool
    @State private var selectedInterval: TimeInterval = 60
    @State private var showClearConfirm = false
    @State private var clearError: String?

    private let intervals: [(label: String, value: TimeInterval)] = [
        ("1 min",  60),
        ("2 min",  120),
        ("5 min",  300),
        ("10 min", 600)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.8))
                HStack {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { showSettings = false }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .semibold))
                            Text("back")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .foregroundStyle(Color(white: 0.4))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            div.frame(height: 1)

            VStack(alignment: .leading, spacing: 0) {
                rowLabel("Refresh")
                Picker("", selection: $selectedInterval) {
                    ForEach(intervals, id: \.value) { Text($0.label).tag($0.value) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .padding(.bottom, 14)

                div.frame(height: 1).padding(.bottom, 12)

                if let error = clearError {
                    Text(error)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding(.bottom, 8)
                }

                // confirmationDialog doesn't work in MenuBarExtra NSPanel —
                // use inline confirmation instead.
                if showClearConfirm {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("remove session key?")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(white: 0.55))
                        HStack(spacing: 10) {
                            Button("confirm") {
                                do {
                                    try appModel.clearSessionKey()
                                    showSettings = false
                                } catch {
                                    clearError = error.localizedDescription
                                    showClearConfirm = false
                                }
                            }
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.85))
                            .buttonStyle(.plain)

                            Button("cancel") { showClearConfirm = false }
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(white: 0.38))
                                .buttonStyle(.plain)
                        }
                    }
                } else {
                    Button { showClearConfirm = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "trash").font(.system(size: 11))
                            Text("remove session key")
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.85))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            div.frame(height: 1)

            HStack {
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color(white: 0.2))
                Spacer()
                Button("quit") { NSApplication.shared.terminate(nil) }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(white: 0.38))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .onAppear { selectedInterval = appModel.settings.refreshInterval }
        .onChange(of: selectedInterval) { appModel.settings.setRefreshInterval(selectedInterval) }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color(white: 0.32))
            .kerning(0.8)
            .textCase(.uppercase)
            .padding(.bottom, 6)
    }
}
