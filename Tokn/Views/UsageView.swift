import SwiftUI

struct UsageView: View {
    let appModel: AppModel

    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if appModel.isLoading {
                loadingRow
            } else if let error = appModel.errorMessage {
                errorRow(error)
            } else if let data = appModel.usageData {
                usageContent(data)
            } else {
                loadingRow
            }
            Divider()
            footer
        }
        .frame(width: 300)
        .sheet(isPresented: $showSettings) {
            SettingsSheet(appModel: appModel)
        }
    }

    private var header: some View {
        HStack {
            Text("Tokn")
                .font(.headline)
            Spacer()
            Button {
                Task { await appModel.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(appModel.isLoading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var loadingRow: some View {
        HStack {
            ProgressView()
                .controlSize(.small)
            Text("Loading…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 13))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private func usageContent(_ data: UsageData) -> some View {
        VStack(spacing: 2) {
            UsageRow(
                label: "Session",
                sublabel: "5h window",
                limit: data.sessionUsage
            )
            Divider().padding(.horizontal, 14)
            UsageRow(
                label: "Weekly",
                sublabel: "7d window",
                limit: data.weeklyUsage
            )
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack {
            if let data = appModel.usageData {
                Text("Updated \(data.freshnessDescription)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Settings") { showSettings = true }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Text("·")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct UsageRow: View {
    let label: String
    let sublabel: String
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.subheadline.weight(.medium))
                    Text(sublabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(Int(limit.utilization))%")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(limit.status.color)
                    Text(limit.resetDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(limit.status.color)
                        .frame(width: geo.size.width * min(limit.utilization / 100, 1.0), height: 6)
                        .animation(.easeInOut(duration: 0.3), value: limit.utilization)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct SettingsSheet: View {
    let appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedInterval: TimeInterval = 60
    @State private var showClearConfirm = false
    @State private var clearError: String?

    private let intervals: [(label: String, value: TimeInterval)] = [
        ("1 minute",  60),
        ("2 minutes", 120),
        ("5 minutes", 300),
        ("10 minutes", 600)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Refresh interval")
                    .font(.subheadline.weight(.medium))
                Picker("", selection: $selectedInterval) {
                    ForEach(intervals, id: \.value) { item in
                        Text(item.label).tag(item.value)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Divider()

            if let error = clearError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("Remove session key", systemImage: "trash")
            }
            .confirmationDialog(
                "Remove session key?",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    do {
                        try appModel.clearSessionKey()
                        dismiss()
                    } catch {
                        clearError = error.localizedDescription
                    }
                }
            } message: {
                Text("You will need to re-enter your session key to use Tokn.")
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 280, height: 260)
        .onAppear { selectedInterval = appModel.settings.refreshInterval }
        .onChange(of: selectedInterval) {
            appModel.settings.setRefreshInterval(selectedInterval)
        }
    }
}
