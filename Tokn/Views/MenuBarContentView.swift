import SwiftUI

struct MenuBarContentView: View {
    let appModel: AppModel
    @State private var isVisible = false
    @Environment(\.scenePhase) private var scenePhase

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
        .onAppear {
            // First open
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                isVisible = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // Every subsequent open: reset then animate in
                isVisible = false
                withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                    isVisible = true
                }
            } else {
                // Closed — reset silently so it's ready for next open
                isVisible = false
            }
        }
    }
}
