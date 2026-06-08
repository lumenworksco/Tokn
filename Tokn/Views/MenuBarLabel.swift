import SwiftUI
import AppKit

struct MenuBarLabel: View {
    let appModel: AppModel

    var body: some View {
        Group {
            if let data = appModel.usageData {
                ColoredUsageLabel(
                    utilization: data.sessionUsage.utilization,
                    color: data.sessionUsage.status.color
                )
            } else if appModel.isLoading {
                ProgressView().controlSize(.mini).scaleEffect(0.7)
            } else {
                Image(systemName: "clock.fill").font(.system(size: 12))
            }
        }
    }
}

// macOS strips color from MenuBarExtra labels via template rendering.
// Rendering to a non-template NSImage preserves the colors.
@MainActor
private struct ColoredUsageLabel: View {
    let utilization: Double
    let color: Color
    @State private var rendered: NSImage?

    var body: some View {
        Group {
            if let rendered {
                Image(nsImage: rendered)
            } else {
                // One-frame placeholder while ImageRenderer runs
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text("\(Int(utilization))%")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            }
        }
        .onAppear    { render() }
        .onChange(of: utilization) { _, _ in render() }
        .onChange(of: color)       { _, _ in render() }
    }

    private func render() {
        let source = HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(Int(utilization))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        }
        .fixedSize()

        let r = ImageRenderer(content: source)
        r.scale = 2
        guard let cg = r.cgImage else { return }
        let img = NSImage(
            cgImage: cg,
            size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2)
        )
        img.isTemplate = false
        rendered = img
    }
}
