import SwiftUI

struct SetupView: View {
    let appModel: AppModel

    @State private var rawKey = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tokn")
                    .font(.title2.bold())
                Text("Monitor your Claude session usage from the menu bar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Session Key")
                    .font(.subheadline.weight(.medium))

                SecureField("sk-ant-...", text: $rawKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Text("Found in your browser: open claude.ai, then DevTools → Application → Cookies → sessionKey")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button(action: connect) {
                if isConnecting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Connecting…")
                    }
                } else {
                    Text("Connect")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(rawKey.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 320)
    }

    private func connect() {
        let key = rawKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        isConnecting = true
        errorMessage = nil

        Task {
            defer { isConnecting = false }
            do {
                try await appModel.saveSessionKey(key)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
