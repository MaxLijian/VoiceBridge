import SwiftUI

struct MenuBarView: View {

    @State private var feishu = FeishuClient.shared
    @AppStorage("feishuAppId") private var appId = ""
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(statusText, systemImage: statusIcon)
                .foregroundColor(statusColor)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            Divider()

            if appId.isEmpty {
                Button("配置飞书机器人...") {
                    openWindow(id: "setup")
                }
            } else if feishu.state == .disconnected {
                Button("连接飞书") {
                    connectFeishu()
                }
            }

            if feishu.state != .disconnected {
                Button("断开连接") {
                    feishu.disconnect()
                }
            }

            Button("测试注入文本") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    TextInjector.shared.inject("Hello from VoiceBridge")
                }
            }
            .keyboardShortcut("t", modifiers: [.command])

            Divider()

            Button("创建新机器人") {
                openWindow(id: "setup")
            }

            if hasBackup {
                Button("恢复旧机器人配置") {
                    restoreCredentials()
                }
            }

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
    }

    // MARK: - 状态显示

    private var statusText: String {
        switch feishu.state {
        case .disconnected: return "未连接"
        case .connecting: return "连接中..."
        case .connected: return "已连接"
        case .reconnecting(let attempt): return "重连中 (\(attempt))..."
        }
    }

    private var statusIcon: String {
        switch feishu.state {
        case .disconnected: return "bolt.slash.fill"
        case .connecting, .reconnecting: return "bolt.horizontal.fill"
        case .connected: return "bolt.fill"
        }
    }

    private var statusColor: Color {
        switch feishu.state {
        case .disconnected: return .secondary
        case .connecting, .reconnecting: return .orange
        case .connected: return .green
        }
    }

    private var hasBackup: Bool {
        let backupId = UserDefaults.standard.string(forKey: "feishuAppId.backup") ?? ""
        return !backupId.isEmpty
    }

    private func restoreCredentials() {
        guard let backupId = UserDefaults.standard.string(forKey: "feishuAppId.backup"),
              !backupId.isEmpty else { return }

        appId = backupId
        UserDefaults.standard.set(backupId, forKey: "feishuAppId")
        if let backupSecret = KeychainHelper.load(for: "feishuAppSecret.backup") {
            _ = KeychainHelper.save(backupSecret, for: "feishuAppSecret")
        }

        // 清理备份
        UserDefaults.standard.removeObject(forKey: "feishuAppId.backup")
        KeychainHelper.delete("feishuAppSecret.backup")

        feishu.disconnect()
        feishu.connectWithStoredCredentials()
    }

    private func connectFeishu() {
        feishu.connectWithStoredCredentials()
    }
}
