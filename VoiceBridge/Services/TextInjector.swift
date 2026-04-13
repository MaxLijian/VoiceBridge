import AppKit
import os

final class TextInjector {

    static let shared = TextInjector()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceBridge",
                                category: "TextInjector")

    private init() {}

    func inject(_ text: String) {
        logger.info("开始注入文本，长度: \(text.count)")

        guard let element = focusedTextElement() else {
            logger.warning("Accessibility API 无法检测焦点输入框，尝试剪贴板")
            // 备选方案：直接用剪贴板+Cmd+V（用于 VS Code 等 Accessibility 支持不完整的应用）
            injectViaClipboard(text)
            logger.info("剪贴板兜底注入完成")
            return
        }

        if injectViaAccessibility(text, element: element) {
            logger.info("Accessibility API 注入成功")
            return
        }

        // Accessibility API 失败
        // 检测当前应用，判断是否需要用剪贴板而不是 keystroke
        let focusedApp = NSWorkspace.shared.frontmostApplication
        let bundleID = focusedApp?.bundleIdentifier ?? ""
        let appName = focusedApp?.localizedName ?? ""
        let isElectron = bundleID.contains("Electron") || appName.contains("Code") || 
                         bundleID.contains("com.microsoft.VSCode") ||
                         bundleID == "app.doodto.VoiceBridge"  // 防递归
        
        let isASCII = text.unicodeScalars.allSatisfy({ $0.value < 128 })
        
        if isElectron {
            logger.debug("检测到 Electron 应用（\(appName)）或 VS Code，直接使用剪贴板")
            injectViaClipboard(text)
            logger.info("剪贴板注入完成")
            return
        }

        if isASCII {
            logger.warning("Accessibility API 失败，降级到 Apple Events")
            if injectViaAppleScript(text) {
                logger.info("Apple Events 注入成功")
                return
            }
        } else {
            logger.debug("非 ASCII 文本，跳过 Apple Events keystroke，直接使用剪贴板")
        }

        logger.warning("降级到剪贴板")
        injectViaClipboard(text)
        logger.info("剪贴板注入完成")
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

    private func injectViaClipboard(_ text: String) {
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

        simulatePaste()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pasteboard.clearContents()
            if let items = previousItems {
                pasteboard.writeObjects(items)
            }
        }
    }

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }
}
