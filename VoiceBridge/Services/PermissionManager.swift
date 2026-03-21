import AppKit
import os

final class PermissionManager {

    static let shared = PermissionManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceBridge",
                                category: "PermissionManager")

    private init() {}

    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityIfNeeded() {
        guard !isAccessibilityGranted else { return }

        logger.warning("辅助功能权限未授权，弹出引导")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
