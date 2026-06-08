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
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                isVisible = true
            }
        }
    }
}
