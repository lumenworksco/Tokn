import SwiftUI

struct MenuBarContentView: View {
    let appModel: AppModel

    var body: some View {
        if appModel.isSetupComplete {
            UsageView(appModel: appModel)
        } else {
            SetupView(appModel: appModel)
        }
    }
}
