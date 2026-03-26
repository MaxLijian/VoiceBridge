import SwiftUI
import ServiceManagement

struct SettingsView: View {

    @State private var botManager = BotManager.shared
    @State private var permissions = PermissionManager.shared
    @State private var feishu = FeishuClient.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var expandedBotId: UUID?
    @State private var showingAddBot = false

    var body: some View {
        Form {
            // 机器人管理
            Section {
                ForEach(botManager.bots) { bot in
                    botRow(bot)
                }

                Button {
                    showingAddBot = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("添加机器人")
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            } header: {
                Text("机器人")
            }

            // 权限
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("辅助功能权限")
                        Text("用于检测焦点位置并插入文本")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if permissions.isAccessibilityGranted {
                        Text("已授权")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    } else {
                        HStack(spacing: 8) {
                            Text("未授权")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(Color.red.opacity(0.15))
                                .foregroundColor(.red)
                                .clipShape(Capsule())
                            Button("去授权") {
                                permissions.requestAccessibility()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("权限")
            }

            // 通用
            Section {
                Toggle("开机自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !newValue
                        }
                    }
            } header: {
                Text("通用")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 300)
        .sheet(isPresented: $showingAddBot) {
            AddBotSheet()
        }
        .onAppear {
            permissions.refreshStatus()
        }
    }

    // MARK: - 机器人行

    @ViewBuilder
    private func botRow(_ bot: BotConfiguration) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bot.name)
                        .font(.body)
                    Text("\(channelName(bot.channel)) · \(botStatusText(bot))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { bot.isEnabled },
                    set: { newValue in
                        botManager.toggleBot(bot, enabled: newValue)
                        if newValue {
                            connectBot(bot)
                        } else {
                            feishu.disconnect()
                        }
                    }
                ))
                .labelsHidden()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    expandedBotId = expandedBotId == bot.id ? nil : bot.id
                }
            }

            // 展开详情
            if expandedBotId == bot.id {
                VStack(spacing: 8) {
                    Divider()
                    detailRow(label: "App ID", value: String(bot.appId.prefix(16)) + "...")
                    detailRow(label: "渠道", value: channelName(bot.channel))
                    detailRow(label: "状态", value: botStatusText(bot))

                    HStack {
                        Spacer()
                        Button("删除", role: .destructive) {
                            if bot.isEnabled { feishu.disconnect() }
                            botManager.removeBot(bot)
                            expandedBotId = nil
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func channelName(_ channel: Channel) -> String {
        switch channel {
        case .feishu: return "飞书"
        }
    }

    private func botStatusText(_ bot: BotConfiguration) -> String {
        guard bot.isEnabled else { return "已禁用" }
        switch feishu.state {
        case .connected: return "已连接"
        case .connecting, .reconnecting: return "连接中"
        case .disconnected: return "未连接"
        }
    }

    private func connectBot(_ bot: BotConfiguration) {
        guard let secret = botManager.secret(for: bot) else { return }
        feishu.connect(appId: bot.appId, appSecret: secret)
    }
}

// MARK: - 添加机器人 Sheet

struct AddBotSheet: View {

    @State private var registration = FeishuAppRegistration()
    @State private var qrURL = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("创建飞书机器人")
                .font(.headline)

            Text("用飞书扫描下方二维码，填写机器人名称即可")
                .foregroundColor(.secondary)
                .font(.callout)

            switch registration.state {
            case .idle, .initializing:
                ProgressView("正在初始化...")
                    .frame(width: 200, height: 200)

            case .waitingForScan, .polling:
                if let qrImage = QRCodeGenerator.generate(from: qrURL) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                }

                if case .polling = registration.state {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("正在获取配置结果...").foregroundColor(.secondary)
                    }
                } else {
                    Text("等待扫码...").foregroundColor(.secondary)
                }

                Button("在浏览器中打开") {
                    if let url = URL(string: qrURL) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.link)

            case .success(let appId, let appSecret):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("机器人创建成功！")
                    .font(.title3)

                Button("完成") {
                    let bot = BotConfiguration(name: "我的语音助手", appId: appId)
                    BotManager.shared.addBot(bot, secret: appSecret)
                    FeishuClient.shared.connect(appId: appId, appSecret: appSecret)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

            case .failed(let message):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.red)
                Text(message).foregroundColor(.secondary)
                Button("重试") { registration.start() }
            }
        }
        .padding(24)
        .frame(width: 360, height: 420)
        .onAppear { registration.start() }
        .onDisappear { registration.cancel() }
        .onChange(of: registration.state) { _, newState in
            if case .waitingForScan(let url, _) = newState { qrURL = url }
        }
    }

}
