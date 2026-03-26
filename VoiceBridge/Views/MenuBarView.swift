import SwiftUI

struct MenuBarView: View {

    @State private var feishu = FeishuClient.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(statusText, systemImage: "circle.fill")
                .foregroundColor(statusColor)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            Divider()

            SettingsLink {
                Text("设置...")
            }
            .keyboardShortcut(",", modifiers: [.command])

            Button("退出 VoiceBridge") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding(.vertical, 4)
        .onAppear {
            let needsOnboarding = !PermissionManager.shared.isAccessibilityGranted
                || !BotManager.shared.isConfigured
            if needsOnboarding {
                // TODO: Task 8 will add AppDelegate
                // (NSApp.delegate as? AppDelegate)?.showOnboarding()
            }
        }
    }

    private var statusText: String {
        switch feishu.state {
        case .disconnected: return "未连接"
        case .connecting: return "连接中..."
        case .connected: return "已连接"
        case .reconnecting(let attempt): return "重连中 (\(attempt))..."
        }
    }

    private var statusColor: Color {
        switch feishu.state {
        case .disconnected: return .secondary
        case .connecting, .reconnecting: return .orange
        case .connected: return .green
        }
    }
}
