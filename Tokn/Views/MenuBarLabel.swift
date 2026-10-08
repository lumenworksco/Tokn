import SwiftUI
import AppKit

struct MenuBarLabel: View {
    let appModel: AppModel

    var body: some View {
        Group {
            if let data = appModel.usageData, data.weeklyUsage.isExceeded {
                GameOverLabel()
            } else if let data = appModel.usageData {
                ColoredUsageLabel(
                    utilization: data.sessionUsage.utilization,
                    color: data.sessionUsage.status.color,
                    style: appModel.settings.menuBarStyle
                )
            } else if appModel.isLoading {
                ProgressView().controlSize(.mini).scaleEffect(0.7)
            } else {
                Image("MenuBarIcon")
            }
        }
    }
}

// Shown in place of the usage label once the weekly limit is used up,
// regardless of the chosen menu bar style.
@MainActor
private struct GameOverLabel: View {
    @State private var rendered: NSImage?

    var body: some View {
        Group {
            if let rendered {
                Image(nsImage: rendered)
            } else {
                Text("GAME OVER").font(.system(size: 11, weight: .heavy, design: .monospaced))
            }
        }
        .onAppear { render() }
    }

    private func render() {
        let red = Color(red: 1.0, green: 0.27, blue: 0.23)
        let r = ImageRenderer(content:
            Text("☠ GAME OVER")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(red)
                .fixedSize()
        )
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

// macOS strips color from MenuBarExtra labels via template rendering.
// Rendering to a non-template NSImage preserves the colors.
@MainActor
private struct ColoredUsageLabel: View {
    let utilization: Double
    let color: Color
    let style: MenuBarStyle
    @State private var rendered: NSImage?

    var body: some View {
        Group {
            if let rendered {
                Image(nsImage: rendered)
            } else {
                placeholderContent
            }
        }
        .onAppear    { render() }
        .onChange(of: utilization) { _, _ in render() }
        .onChange(of: color)       { _, _ in render() }
        .onChange(of: style)       { _, _ in render() }
    }

    @ViewBuilder
    private var placeholderContent: some View {
        switch style {
        case .dotAndPercent:
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text("\(Int(utilization))%").font(.system(size: 12, weight: .medium, design: .monospaced))
            }
        case .percentOnly:
            Text("\(Int(utilization))%").font(.system(size: 12, weight: .medium, design: .monospaced))
        case .dotOnly:
            Circle().fill(color).frame(width: 8, height: 8)
        }
    }

    private func render() {
        let source: AnyView
        switch style {
        case .dotAndPercent:
            source = AnyView(
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text("\(Int(utilization))%")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(color)
                }
                .fixedSize()
            )
        case .percentOnly:
            source = AnyView(
                Text("\(Int(utilization))%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(color)
                    .fixedSize()
            )
        case .dotOnly:
            source = AnyView(
                Circle().fill(color).frame(width: 8, height: 8).fixedSize()
            )
        }

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
