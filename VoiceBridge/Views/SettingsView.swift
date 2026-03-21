import SwiftUI

struct SettingsView: View {

    @AppStorage("feishuAppId") private var appId = ""
    @State private var appSecret = ""
    @State private var feishu = FeishuClient.shared
    @State private var saved = false

    var body: some View {
        Form {
            Section("飞书配置") {
                TextField("App ID", text: $appId)
                SecureField("App Secret", text: $appSecret)

                HStack {
                    Button("保存并连接") {
                        saveAndConnect()
                    }
                    .disabled(appId.isEmpty || appSecret.isEmpty)

                    if saved {
                        Text("已保存")
                            .foregroundColor(.green)
                            .font(.caption)
                    }

                    Spacer()

                    statusBadge
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 220)
        .onAppear {
            if let data = KeychainHelper.load(for: "feishuAppSecret"),
               let secret = String(data: data, encoding: .utf8) {
                appSecret = secret
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch feishu.state {
        case .disconnected:
            Label("未连接", systemImage: "circle.fill")
                .foregroundColor(.secondary)
                .font(.caption)
        case .connecting, .reconnecting:
            Label("连接中", systemImage: "circle.fill")
                .foregroundColor(.orange)
                .font(.caption)
        case .connected:
            Label("已连接", systemImage: "circle.fill")
                .foregroundColor(.green)
                .font(.caption)
        }
    }

    private func saveAndConnect() {
        if let data = appSecret.data(using: .utf8) {
            _ = KeychainHelper.save(data, for: "feishuAppSecret")
        }

        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }

        feishu.disconnect()
        feishu.connect(appId: appId, appSecret: appSecret)
    }
}
