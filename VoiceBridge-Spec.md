# VoiceBridge — 飞书远程语音输入法

## 项目概述

一款 macOS 菜单栏常驻 App。用户在手机飞书 APP 中通过语音输入发送消息给飞书机器人，Mac 端通过飞书 WebSocket 长连接实时接收消息，并将文本自动插入到当前焦点所在的输入位置。

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
- **飞书通信：** URLSessionWebSocketTask + 自研 Protobuf 编解码，直连飞书 WebSocket 长连接
- **不使用：** Node.js、Electron、任何 JS 运行时、飞书 SDK

## 核心模块

### 1. 飞书 WebSocket 连接

通过飞书开放平台的 WebSocket 长连接模式接收机器人消息。

配置项：
- App ID
- App Secret

连接流程：
- POST `https://open.feishu.cn/callback/ws/endpoint`，请求体包含 AppID 和 AppSecret
- 服务端返回 WebSocket URL 和 ClientConfig（心跳间隔、重连参数等）
- 使用 URLSessionWebSocketTask 连接 WebSocket URL
- 收发二进制 Protobuf 帧（自研最小化编解码器，仅支持 Frame + Header 两个消息类型）
- 接收 im.message.receive_v1 事件，解析 JSON payload 提取纯文本
- 收到事件后立即发送 ACK 帧确认，防止服务端 3 秒超时重发

消息可靠性保障：
- **消息去重**：用事件 payload 的 message_id（业务 ID，重发不变）做去重，Dictionary O(1) 查找 + FIFO 队列淘汰，TTL 10 分钟
- **过期消息丢弃**：超过 30 分钟的消息直接丢弃，防止 WebSocket 重连后重放陈旧消息
- **断线自动重连**：首次重连在 reconnect_nonce 内随机抖动（避免集群雪崩），后续按 reconnect_interval 固定间隔重连，参数由服务端 ClientConfig 下发
- **心跳保活**：按服务端下发的 PingInterval 定时发送 Ping 帧，Pong 回复可携带更新的 ClientConfig

### 2. 文本注入

采用三层降级策略，注入前先检查当前焦点是否为文本输入元素（AXTextField / AXTextArea / AXComboBox / AXWebArea），无活跃输入框时直接丢弃文本。

**第一层 — Accessibility API（首选）：**
- AXUIElementCreateSystemWide() 获取焦点元素
- 检测 AXDOMClassList 属性判断是否为 Electron / Web 视图，是则跳过（其 AX API 返回 success 但实际不生效）
- 通过 kAXSelectedTextAttribute 直接写入文本
- 优点：不污染剪贴板

**第二层 — Apple Events（降级）：**
- 当 AX API 失败或被跳过时，使用 NSAppleScript
- tell application "System Events" to keystroke
- 对特殊字符（反斜杠、引号、换行、回车、制表符）做转义处理

**第三层 — 剪贴板 + Cmd+V（兜底）：**
- 保存原剪贴板所有 UTI 类型的完整内容
- NSPasteboard 写入文本
- CGEvent 模拟 Cmd+V
- 0.3 秒后恢复原剪贴板内容（使用 NSPasteboardItem + writeObjects 完整还原）
- 兼容性最强

调度逻辑：获取焦点元素一次，依次尝试第一层 → 第二层 → 第三层，成功即停止。

### 3. 菜单栏 UI

- 使用 SwiftUI MenuBarExtra，LSUIElement 隐藏 Dock 图标
- 菜单栏图标根据连接状态动态变化（mic.fill / mic.and.signal.meter / mic.slash）
- 下拉菜单包含：连接状态显示、连接/断开飞书、测试注入文本、设置、退出
- 设置界面：App ID / App Secret 输入，保存并连接按钮，连接状态指示
- App 启动时自动读取已保存的凭证并连接

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

## 项目结构

```
VoiceBridge/
├── VoiceBridgeApp.swift          # App 入口，MenuBarExtra，自动连接
├── Views/
│   ├── MenuBarView.swift         # 菜单栏下拉内容
│   └── SettingsView.swift        # 设置界面
├── Services/
│   ├── FeishuClient.swift        # 飞书 WebSocket 长连接、Protobuf 帧处理、消息去重
│   ├── TextInjector.swift        # 三层文本注入 + 焦点检测 + Electron 兼容
│   └── PermissionManager.swift   # 辅助功能权限检测与引导
├── Models/
│   └── FeishuMessage.swift       # 飞书事件数据模型（im.message.receive_v1）
├── Utilities/
│   ├── ProtobufCodec.swift       # 最小化 Protobuf 编解码器（Frame + Header）
│   └── KeychainHelper.swift      # App Secret 安全存储
└── Assets.xcassets               # 菜单栏图标等
```

## 已实现功能（MVP）

- 飞书 WebSocket 长连接和消息接收（含 Protobuf 帧协议）
- 三层文本注入（含 Electron 兼容和焦点检测）
- 菜单栏状态显示和动态图标
- 基础设置（App ID / App Secret）
- 消息去重和过期检查
- 断线自动重连（带随机抖动）
- 启动自动连接

## 后续考虑

- 历史记录（最近插入的文本）
- 暂停/恢复功能
- 开机自启开关
- 通知开关
- 命令系统
- AI 润色
- 快捷键模式
