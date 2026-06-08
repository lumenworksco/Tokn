import SwiftUI

struct MenuBarLabel: View {
    let appModel: AppModel

    var body: some View {
        HStack(spacing: 4) {
            if let data = appModel.usageData {
                Circle()
                    .fill(data.sessionUsage.status.color)
                    .frame(width: 7, height: 7)
                Text("\(Int(data.sessionUsage.utilization))%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(data.sessionUsage.status.color)
            } else if appModel.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            } else {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12))
            }
        }
    }
}
