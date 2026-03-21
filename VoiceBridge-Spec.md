# VoiceBridge — 飞书远程语音输入法

## 项目概述

一款 macOS 菜单栏常驻 App。用户在手机飞书 APP 中通过语音输入发送消息给飞书机器人，Mac 端通过飞书 WebSocket 长链接实时接收消息，并将文本自动插入到当前焦点所在的输入位置。

本质上是把手机变成 Mac 的无线语音键盘。

## 用户流程

1. Mac App 后台运行，菜单栏显示连接状态
2. 用户在 Mac 上任意应用中将光标放到要输入的位置
3. 拿起手机，在飞书机器人私聊中使用语音输入
4. 飞书 ASR 转为文字并发送
5. Mac 端收到后自动将文本插入到光标位置

## 技术栈

- **语言：** Swift
- **UI 框架：** SwiftUI（MenuBarExtra）
- **最低支持：** macOS 13+
- **飞书通信：** URLSessionWebSocketTask 对接飞书 Open API
- **不使用：** Node.js、Electron、任何 JS 运行时

## 核心模块

### 1. 飞书 WebSocket 连接

通过飞书开放平台的 WebSocket 长链接模式接收机器人消息。

配置项：
- App ID
- App Secret

连接流程：
- 使用 App ID + App Secret 获取 tenant_access_token
- 通过 token 获取 WebSocket 连接地址
- 建立 WebSocket 连接，接收 im.message.receive_v1 事件
- 解析消息内容，提取纯文本
- 断线自动重连（指数退避）

飞书相关 API：
- POST https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal — 获取 token
- 飞书 SDK WSClient 协议（或直接 WebSocket 实现）

### 2. 文本注入（参考 AutoGLM 智谱 AI 输入法的实现方案）

采用三层降级策略：

**第一层 — Accessibility API（首选）：**
- AXUIElementCreateSystemWide() 获取焦点元素
- 通过 kAXSelectedTextAttribute 直接写入文本
- 优点：不污染剪贴板
- 注意：超过约 2000 字符需分段写入

**第二层 — Apple Events（降级）：**
- 当 AX API 失败时，使用 NSAppleScript
- tell application "System Events" to keystroke
- 可针对特定应用做脚本适配

**第三层 — 剪贴板 + Cmd+V（兜底）：**
- NSPasteboard 写入文本
- CGEvent 模拟 Cmd+V
- 延迟后恢复原剪贴板内容
- 兼容性最强

调度逻辑：依次尝试第一层 → 第二层 → 第三层，成功即停止。

### 3. 菜单栏 UI

- 使用 SwiftUI MenuBarExtra
- 显示连接状态（已连接 / 断开 / 重连中）
- 下拉菜单包含：最近插入的文本记录、暂停/恢复、设置、退出
- 设置界面：App ID / App Secret 输入、开机自启开关、通知开关

### 4. 权限管理

需要声明的权限（Info.plist）：

```xml
<key>NSAccessibilityUsageDescription</key>
<string>需要辅助功能权限以检测焦点位置并插入语音转写的文本</string>

<key>NSAppleEventsUsageDescription</key>
<string>需要自动化权限以在应用中插入文本</string>
```

App 需要禁用沙箱（Accessibility API 要求）。

启动时检测辅助功能权限，未授权则引导用户到系统设置中开启。

## 项目结构建议

```
VoiceBridge/
├── VoiceBridgeApp.swift          # App 入口，MenuBarExtra
├── Views/
│   ├── MenuBarView.swift         # 菜单栏下拉内容
│   └── SettingsView.swift        # 设置界面
├── Services/
│   ├── FeishuClient.swift        # 飞书 WebSocket 连接、token 管理、消息解析
│   ├── TextInjector.swift        # 三层文本注入逻辑
│   └── PermissionManager.swift   # 辅助功能权限检测与引导
├── Models/
│   ├── FeishuMessage.swift       # 飞书消息模型
│   └── InsertionHistory.swift    # 插入历史记录
├── Utilities/
│   ├── KeychainHelper.swift      # App Secret 安全存储
│   └── Logger.swift              # 日志
└── Resources/
    └── Assets.xcassets           # 菜单栏图标等
```

## MVP 范围

第一个可用版本只需要：
- 飞书 WebSocket 连接和消息接收
- 三层文本注入
- 菜单栏状态显示
- 基础设置（App ID / App Secret）

后续再考虑：历史记录、命令系统、AI 润色、快捷键模式等。
