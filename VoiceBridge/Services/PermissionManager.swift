import AppKit
import os

@Observable
final class PermissionManager {

    static let shared = PermissionManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceBridge",
                                category: "PermissionManager")

    private(set) var isAccessibilityGranted: Bool = AXIsProcessTrusted()
    private var pollTimer: Timer?

    private init() {}

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        startPolling()
    }

    /// 开始轮询权限状态（每 1 秒检查一次）
    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let granted = AXIsProcessTrusted()
            if granted != self.isAccessibilityGranted {
                self.isAccessibilityGranted = granted
                if granted {
                    self.logger.info("辅助功能权限已授权")
                    self.stopPolling()
                }
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// 刷新一次权限状态（不轮询）
    func refreshStatus() {
        isAccessibilityGranted = AXIsProcessTrusted()
    }
}
