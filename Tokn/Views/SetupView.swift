import SwiftUI

struct SetupView: View {
    let appModel: AppModel

    @State private var rawKey = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var appeared = false

    private let bg     = Color(red: 0.085, green: 0.085, blue: 0.11)
    private let cardBg = Color(white: 1, opacity: 0.055)
    private let stroke = Color(white: 1, opacity: 0.08)
    private let div    = Color(white: 1, opacity: 0.07)
    private let accent = Color(red: 0.55, green: 0.36, blue: 0.96)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                Text("Tokn")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Claude session usage in your menu bar.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(white: 0.35))
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 12)

            div.frame(height: 1)

            VStack(alignment: .leading, spacing: 0) {
                Text("SESSION KEY")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(white: 0.32))
                    .kerning(0.8)
                    .padding(.bottom, 6)

                SecureField("sk-ant-…", text: $rawKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(cardBg)
                            .strokeBorder(stroke, lineWidth: 0.5)
                    )
                    .padding(.bottom, 8)

                Text("claude.ai → DevTools (⌘⌥I) → Application → Cookies → sessionKey")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(white: 0.28))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)

                if let error = errorMessage {
                    Text("✗ \(error)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding(.bottom, 8)
                }

                Button(action: connect) {
                    HStack(spacing: 5) {
                        if isConnecting {
                            ProgressView().controlSize(.mini)
                            Text("connecting…")
                        } else {
                            Text("connect →")
                        }
                    }
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(accent.opacity(isConnecting ? 0.5 : 1))
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(rawKey.trimmingCharacters(in: .whitespaces).isEmpty || isConnecting)
                .opacity(rawKey.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .frame(width: 280)
        .background(bg)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 5)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) { appeared = true }
        }
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
