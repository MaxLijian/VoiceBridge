import SwiftUI

@main
struct VoiceBridgeApp: App {

    @State private var feishu = FeishuClient.shared

    init() {
        FeishuClient.shared.onTextReceived = { text in
            TextInjector.shared.inject(text)
        }
        FeishuClient.shared.connectWithStoredCredentials()
    }

    var body: some Scene {
        MenuBarExtra("VoiceBridge", systemImage: menuBarIcon) {
            MenuBarView()
        }

        Window("创建飞书机器人", id: "setup") {
            SetupView { appId, appSecret in
                // 备份旧凭据
                backupCredentials()
                // 保存新凭据
                UserDefaults.standard.set(appId, forKey: "feishuAppId")
                if let data = appSecret.data(using: .utf8) {
                    _ = KeychainHelper.save(data, for: "feishuAppSecret")
                }
                feishu.disconnect()
                feishu.connect(appId: appId, appSecret: appSecret)
            }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }

    private var menuBarIcon: String {
        switch feishu.state {
        case .connected:
            return "mic.fill"
        case .connecting, .reconnecting:
            return "mic.and.signal.meter"
        case .disconnected:
            return "mic.slash"
        }
    }

    private func backupCredentials() {
        let oldAppId = UserDefaults.standard.string(forKey: "feishuAppId") ?? ""
        guard !oldAppId.isEmpty else { return }

        UserDefaults.standard.set(oldAppId, forKey: "feishuAppId.backup")
        if let oldSecret = KeychainHelper.load(for: "feishuAppSecret") {
            _ = KeychainHelper.save(oldSecret, for: "feishuAppSecret.backup")
        }
    }
}
