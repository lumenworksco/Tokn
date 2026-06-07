import SwiftUI

@main
struct ToknApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appModel: appModel)
        } label: {
            MenuBarLabel(appModel: appModel)
                .task { appModel.bootstrap() }
        }
        .menuBarExtraStyle(.window)
    }
}
