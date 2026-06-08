import SwiftUI

@main
struct ToknApp: App {
    @State private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appModel: appModel)
        } label: {
            MenuBarLabel(appModel: appModel)
                .task { appModel.bootstrap() }
        }
        .menuBarExtraStyle(.window)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await appModel.refresh() }
        }
    }
}
