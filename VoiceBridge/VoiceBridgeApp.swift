import SwiftUI

@main
struct VoiceBridgeApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var feishu = FeishuClient.shared

    init() {
        FeishuClient.shared.onTextReceived = { text in
            TextInjector.shared.inject(text)
        }
    }

    var body: some Scene {
        MenuBarExtra("VoiceBridge", systemImage: menuBarIcon) {
            MenuBarView()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }

    private var menuBarIcon: String {
        switch feishu.state {
        case .connected: return "mic.fill"
        case .connecting, .reconnecting: return "mic.and.signal.meter"
        case .disconnected: return "mic.slash"
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var onboardingWindow: NSWindow?
    private var workspaceObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerLifecycleObservers()

        let needsOnboarding = !PermissionManager.shared.isAccessibilityGranted
            || !BotManager.shared.isConfigured

        if needsOnboarding {
            showOnboarding()
        } else {
            FeishuClient.shared.connectWithStoredCredentials()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
        }
    }

    func showOnboarding() {
        // Prevent duplicate windows
        if onboardingWindow != nil { return }

        let onboardingView = OnboardingView { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            FeishuClient.shared.connectWithStoredCredentials()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: onboardingView)
        window.title = "VoiceBridge 设置向导"
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.onboardingWindow = window
    }

    private func registerLifecycleObservers() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ensureConnectedIfPossible()
        }

        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ensureConnectedIfPossible()
        }
    }

    private func ensureConnectedIfPossible() {
        guard onboardingWindow == nil,
              PermissionManager.shared.isAccessibilityGranted,
              BotManager.shared.isConfigured else {
            return
        }

        if case .disconnected = FeishuClient.shared.state {
            FeishuClient.shared.connectWithStoredCredentials()
        }
    }
}
