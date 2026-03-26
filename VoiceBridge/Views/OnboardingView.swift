import SwiftUI

struct OnboardingView: View {

    @State private var currentStep: OnboardingStep = .welcome
    @State private var permissions = PermissionManager.shared
    @State private var registration = FeishuAppRegistration()
    @State private var qrURL = ""
    var onComplete: () -> Void

    enum OnboardingStep {
        case welcome
        case createBot
        case complete
    }

    var body: some View {
        VStack(spacing: 0) {
            // 步骤指示器
            stepIndicator
                .padding(.top, 24)
                .padding(.bottom, 20)

            Divider()

            // 内容区域
            Group {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .createBot:
                    createBotStep
                case .complete:
                    completeStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 520)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            permissions.refreshStatus()
            // 自动跳到未完成的步骤
            if permissions.isAccessibilityGranted {
                if BotManager.shared.isConfigured {
                    currentStep = .complete
                } else {
                    currentStep = .createBot
                }
            }
        }
        .onDisappear { permissions.stopPolling() }
    }

    // MARK: - 步骤指示器

    private var stepIndicator: some View {
        HStack(spacing: 24) {
            stepBadge(number: 1, title: "授权权限",
                      isActive: currentStep == .welcome,
                      isCompleted: currentStep != .welcome)
            stepConnector(isCompleted: currentStep != .welcome)
            stepBadge(number: 2, title: "创建机器人",
                      isActive: currentStep == .createBot,
                      isCompleted: currentStep == .complete)
            stepConnector(isCompleted: currentStep == .complete)
            stepBadge(number: 3, title: "完成",
                      isActive: currentStep == .complete,
                      isCompleted: false)
        }
    }

    private func stepBadge(number: Int, title: String, isActive: Bool, isCompleted: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green : (isActive ? Color.blue : Color.secondary.opacity(0.3)))
                    .frame(width: 28, height: 28)
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isActive ? .white : .secondary)
                }
            }
            Text(title)
                .font(.caption)
                .foregroundColor(isActive ? .primary : .secondary)
        }
    }

    private func stepConnector(isCompleted: Bool) -> some View {
        Rectangle()
            .fill(isCompleted ? Color.green : Color.secondary.opacity(0.3))
            .frame(width: 40, height: 2)
    }

    // MARK: - Step 1: 欢迎 & 权限

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("欢迎使用 VoiceBridge")
                .font(.title2.bold())

            Text("让手机变成你的 Mac 语音键盘")
                .foregroundColor(.secondary)

            // 权限卡片
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "keyboard")
                        .font(.title3)
                        .foregroundColor(.blue)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("辅助功能权限")
                            .font(.headline)
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
                        Text("未授权")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .clipShape(Capsule())
                    }
                }

                if !permissions.isAccessibilityGranted {
                    Button("授权辅助功能权限") {
                        permissions.requestAccessibility()
                    }
                    .buttonStyle(.borderedProminent)

                    Text("点击后会打开系统设置，请在列表中找到 VoiceBridge 并开启")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 40)

            Spacer()

            Button("下一步") {
                currentStep = .createBot
                registration.start()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!permissions.isAccessibilityGranted)

            if !permissions.isAccessibilityGranted {
                Text("请先完成授权")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer().frame(height: 20)
        }
    }

    // MARK: - Step 2: 创建机器人

    private var createBotStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("创建你的飞书机器人")
                .font(.title3.bold())

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
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if case .polling = registration.state {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("正在获取配置结果...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("等待扫码...")
                        .foregroundColor(.secondary)
                }

                Button("在浏览器中打开") {
                    if let url = URL(string: qrURL) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.link)

            case .success:
                ProgressView()

            case .failed(let message):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.red)
                Text(message)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试") { registration.start() }
            }

            Spacer()
        }
        .onAppear {
            if case .idle = registration.state { registration.start() }
        }
        .onDisappear { registration.cancel() }
        .onChange(of: registration.state) { _, newState in
            if case .waitingForScan(let url, _) = newState { qrURL = url }
            if case .success(let appId, let appSecret) = newState {
                let bot = BotConfiguration(name: "我的语音助手", appId: appId)
                BotManager.shared.addBot(bot, secret: appSecret)
                FeishuClient.shared.connect(appId: appId, appSecret: appSecret)
                currentStep = .complete
            }
        }
    }

    // MARK: - 完成页

    private var completeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)

            Text("一切就绪！")
                .font(.title2.bold())

            Text("VoiceBridge 已连接并在菜单栏运行")
                .foregroundColor(.secondary)

            // 使用说明
            VStack(alignment: .leading, spacing: 12) {
                Text("使用方法")
                    .font(.headline)

                instructionRow(number: "1", text: "在 Mac 上点击任意输入框")
                instructionRow(number: "2", text: "打开飞书，给机器人发送语音或文字")
                instructionRow(number: "3", text: "文字会自动出现在 Mac 的光标位置")
            }
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 40)

            Spacer()

            Button("开始使用") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer().frame(height: 20)
        }
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.callout.bold())
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .font(.callout)
        }
    }

}
