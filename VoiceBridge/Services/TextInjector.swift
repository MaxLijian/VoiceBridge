import AppKit
import os

final class TextInjector {

    static let shared = TextInjector()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceBridge",
                                category: "TextInjector")

    private init() {}

    func inject(_ text: String) {
        logger.info("开始注入文本，长度: \(text.count)")

        let focusedApp = NSWorkspace.shared.frontmostApplication
        let bundleID = focusedApp?.bundleIdentifier ?? ""
        let appName = focusedApp?.localizedName ?? ""
        let targetPID = focusedApp?.processIdentifier

        // 已知 AX 不可靠的应用（VS Code / Electron 类），直接走剪贴板，跳过 AX 尝试，
        // 避免 AX 返回假成功（write 被接受但文字未出现）
        if shouldForceClipboard(bundleID: bundleID, appName: appName) {
            logger.debug("[\(appName)] 直接走剪贴板通道")
            injectViaClipboard(text, targetPID: targetPID)
            return
        }

        guard let element = focusedTextElement() else {
            logger.warning("Accessibility API 无法检测焦点输入框，降级剪贴板")
            injectViaClipboard(text, targetPID: targetPID)
            return
        }

        if injectViaAccessibility(text, element: element) {
            logger.info("Accessibility API 注入成功")
            return
        }

        // AX 失败，判断降级路径
        let isASCII = text.unicodeScalars.allSatisfy({ $0.value < 128 })

        if isASCII {
            logger.warning("Accessibility API 失败，降级到 Apple Events")
            if injectViaAppleScript(text) {
                logger.info("Apple Events 注入成功")
                return
            }
        } else {
            logger.debug("非 ASCII 文本，跳过 Apple Events keystroke")
        }

        logger.warning("降级到剪贴板")
        injectViaClipboard(text, targetPID: targetPID)
    }

    // MARK: - 应用路由策略

    /// 对 AX 注入无效或会假成功的应用，强制走剪贴板通道。
    /// 规则：AX 能写入文字但不触发框架事件（React/Vue contenteditable）的场景，
    ///       必须走剪贴板 + paste 事件，才能让 Web 框架感知到输入。
    private func shouldForceClipboard(bundleID: String, appName: String) -> Bool {
        // 防止对自身触发递归
        if bundleID == (Bundle.main.bundleIdentifier ?? "app.doodto.VoiceBridge") { return false }

        // VS Code 系列（含 Insiders / VSCodium）
        if bundleID.hasPrefix("com.microsoft.VSCode") { return true }
        if bundleID == "com.visualstudio.code.oss" { return true }

        // 其他已知 Electron 应用
        if bundleID.contains(".electron.") { return true }
        if appName == "Visual Studio Code" || appName == "Code" { return true }

        // 浏览器：web 内容区（contenteditable / React 输入框）需要 paste 事件，
        // 地址栏同样支持剪贴板粘贴，不会退化。
        if bundleID.hasPrefix("com.google.Chrome") { return true }  // Chrome / Chrome Canary
        if bundleID.hasPrefix("com.apple.Safari") { return true }   // Safari / Safari Technology Preview
        if bundleID == "company.thebrowser.Browser" { return true } // Arc
        if bundleID.hasPrefix("com.microsoft.edgemac") { return true } // Edge
        if bundleID.hasPrefix("org.mozilla.firefox") { return true } // Firefox
        if bundleID.hasPrefix("com.brave.Browser") { return true }  // Brave
        if bundleID.hasPrefix("com.operasoftware") { return true }  // Opera
        if bundleID.hasPrefix("io.github.zen-browser") { return true } // Zen

        return false
    }

    // MARK: - 获取焦点文本元素（单次查询，避免重复 IPC）

    private func focusedTextElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: AnyObject?

        guard AXUIElementCopyAttributeValue(systemWide,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focusedRef) == .success else {
            return nil
        }

        // AXUIElement is a CFTypeRef, always succeeds from AX API
        let element = focusedRef as! AXUIElement
        return element
    }

    // MARK: - 第一层：Accessibility API

    private func injectViaAccessibility(_ text: String, element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element,
                                             kAXSelectedTextAttribute as CFString,
                                             &settable) == .success,
              settable.boolValue else {
            logger.debug("焦点元素不支持 selectedText 写入")
            return false
        }

        let result = AXUIElementSetAttributeValue(element,
                                                   kAXSelectedTextAttribute as CFString,
                                                   text as CFTypeRef)
        if result != .success {
            logger.debug("AX 设置 selectedText 失败: \(result.rawValue)")
            return false
        }

        return true
    }

    // MARK: - 第二层：Apple Events

    private func injectViaAppleScript(_ text: String) -> Bool {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        let source = """
        tell application "System Events"
            keystroke "\(escaped)"
        end tell
        """

        guard let script = NSAppleScript(source: source) else { return false }

        var error: NSDictionary?
        script.executeAndReturnError(&error)

        if let error = error {
            logger.error("AppleScript 执行失败: \(error)")
            return false
        }
        return true
    }

    // MARK: - 第三层：剪贴板 + Cmd+V

    private func injectViaClipboard(_ text: String, targetPID: pid_t?) {
        let pasteboard = NSPasteboard.general

        // 保存原剪贴板（所有类型）
        let previousItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // AppleScript `keystroke "v"` 是同步执行：其 IPC 往返（约 30-100ms）本身就保证
        // 剪贴板已写入完成后才触发粘贴，同时也能正确路由到 Electron 渲染子进程的焦点元素。
        // 不能用 postToPid：Electron/WKWebView 的实际输入由渲染子进程处理，
        // postToPid 发到主进程 PID 无法抵达渲染层。
        simulatePaste()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if let items = previousItems {
                pasteboard.writeObjects(items)
            }
        }
    }

    /// 向焦点窗口发送 Cmd+V 粘贴事件（优先 AppleScript，失败降级到 CGEvent HID）
    private func simulatePaste() {
        let source = """
        tell application "System Events"
            keystroke "v" using {command down}
        end tell
        """
        guard let script = NSAppleScript(source: source) else {
            simulatePasteViaCGEvent()
            return
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            logger.warning("AppleScript paste 失败，降级 CGEvent: \(error)")
            simulatePasteViaCGEvent()
        }
    }

    private func simulatePasteViaCGEvent() {
        let src = CGEventSource(stateID: .hidSystemState)
        let kd = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        kd?.flags = .maskCommand
        let ku = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        ku?.flags = .maskCommand
        kd?.post(tap: .cghidEventTap)
        ku?.post(tap: .cghidEventTap)
    }
}
