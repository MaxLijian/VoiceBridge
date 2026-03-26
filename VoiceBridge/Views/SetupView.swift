import SwiftUI
import CoreImage.CIFilterBuiltins

struct SetupView: View {

    @State private var registration = FeishuAppRegistration()
    @State private var qrURL: String = ""
    @Environment(\.dismiss) private var dismiss

    var onSuccess: ((String, String) -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text("创建飞书机器人")
                .font(.headline)

            switch registration.state {
            case .idle, .initializing:
                ProgressView("正在初始化...")
                    .frame(width: 200, height: 200)

            case .waitingForScan, .polling:
                if let qrImage = generateQRCode(from: qrURL) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                }

                if case .polling = registration.state {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在获取配置结果...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("请用飞书扫描二维码")
                        .foregroundColor(.secondary)
                }

                Button("在浏览器中打开") {
                    if let nsURL = URL(string: qrURL) {
                        NSWorkspace.shared.open(nsURL)
                    }
                }
                .buttonStyle(.link)

            case .success(let appId, let appSecret):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("机器人创建成功！")
                    .font(.title3)
                Text("App ID: \(appId)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("开始使用") {
                    onSuccess?(appId, appSecret)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

            case .failed(let message):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.red)
                Text(message)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("重试") {
                    registration.start()
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 320, height: 380)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            registration.start()
        }
        .onDisappear {
            registration.cancel()
        }
        .onChange(of: registration.state) { _, newState in
            if case .waitingForScan(let url, _) = newState {
                qrURL = url
            }
        }
    }

    // MARK: - QR Code 生成（CoreImage）

    private func generateQRCode(from string: String) -> NSImage? {
        guard !string.isEmpty else { return nil }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        let scale = 10.0
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
