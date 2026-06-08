import SwiftUI

struct MenuBarContentView: View {
    let appModel: AppModel
    @State private var isVisible = false

    var body: some View {
        Group {
            if appModel.isSetupComplete {
                UsageView(appModel: appModel)
            } else {
                SetupView(appModel: appModel)
            }
        }
        .scaleEffect(isVisible ? 1 : 0.96, anchor: .top)
        .opacity(isVisible ? 1 : 0)
        // NSWindow.didChangeOcclusionStateNotification fires every time
        // the window actually becomes visible or hidden — the only reliable
        // signal for MenuBarExtra(.window) non-activating panels.
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            if window.occlusionState.contains(.visible) {
                guard !isVisible else { return }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                    isVisible = true
                }
            } else {
                // Silently reset so the animation is ready for next open.
                // (close happens after the window is already hidden so
                //  animating here would be invisible — skip it)
                isVisible = false
            }
        }
    }
}
