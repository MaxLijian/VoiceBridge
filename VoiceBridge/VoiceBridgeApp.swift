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
}
