# CLAUDE.md

## 项目

VoiceBridge — macOS 菜单栏 App，通过飞书机器人 WebSocket 长链接接收手机端语音输入的文字，自动插入到 Mac 当前焦点位置。

## 技术栈

- Swift, SwiftUI, macOS 13+
- 纯原生实现，不依赖 Node.js 或任何 JS 运行时
- MenuBarExtra 做菜单栏常驻
- URLSessionWebSocketTask 做飞书 WebSocket 连接
- Accessibility API + Apple Events + CGEvent 做文本注入

## 关键技术点

### 飞书连接
- 用 App ID + App Secret 换 tenant_access_token
- 通过 token 建立 WebSocket 长链接
- 监听 im.message.receive_v1 事件
- 断线指数退避重连

### 文本注入（三层降级）
1. AXUIElement kAXSelectedTextAttribute 直接写入（不污染剪贴板）
2. NSAppleScript System Events keystroke（降级）
3. NSPasteboard + CGEvent Cmd+V（兜底，需保存恢复剪贴板）

### 权限
- 需要辅助功能权限（Accessibility）
- 需要 Apple Events 权限
- 禁用 App Sandbox

## 代码规范
- 文件组织：Views/, Services/, Models/, Utilities/
- 用 async/await，不用 completion handler
- 敏感信息（App Secret）存 Keychain
- 日志用 os.Logger

## 项目规格文档
详见 VoiceBridge-Spec.md
