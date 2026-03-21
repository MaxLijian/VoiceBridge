# VoiceBridge

把手机变成 Mac 的无线语音键盘。

macOS 菜单栏常驻 App，通过飞书机器人 WebSocket 长连接接收手机端语音输入的文字，自动插入到 Mac 当前光标所在的输入位置。

## 工作流程

1. Mac 端 VoiceBridge 后台运行，菜单栏显示连接状态
2. 在 Mac 上任意应用中将光标放到要输入的位置
3. 拿起手机，在飞书机器人私聊中使用语音输入
4. 飞书语音识别转为文字并发送
5. Mac 端实时收到文字，自动插入到光标位置

## 技术特性

- **纯 Swift 原生实现**，不依赖 Node.js 或任何 JS 运行时
- **飞书 WebSocket 长连接**，自研 Protobuf 编解码，无需飞书 SDK
- **三层文本注入降级策略**：
  - Accessibility API（不污染剪贴板）
  - Apple Events keystroke（降级）
  - 剪贴板 + Cmd+V（兜底，自动恢复原剪贴板内容）
- **Electron 应用兼容**（飞书、Claude 桌面版等），自动检测 Web 视图跳过不可靠的 AX API
- **消息去重 + 过期检查**，防止 WebSocket 重发和重连重放
- **断线自动重连**，带随机抖动避免雪崩
- **无焦点输入框时自动丢弃**，不会缓存按键导致意外输入

## 系统要求

- macOS 13+
- 需要授予辅助功能权限（Accessibility）
- 需要授予 Apple Events 权限

## 配置飞书机器人

1. 打开 [飞书开放平台](https://open.feishu.cn/app) → 创建企业自建应用
2. 添加应用能力 → 选择「机器人」
3. 事件与回调 → 添加事件 `im.message.receive_v1` → **接收方式选择「长连接」**
4. 权限管理 → 开通 `im:message`、`im:message.receive_v1`
5. 版本管理与发布 → 创建版本 → 申请发布

## 使用

1. 运行 VoiceBridge，菜单栏出现麦克风图标
2. 点击图标 → 设置 → 填入 App ID 和 App Secret → 保存并连接
3. 图标变为实心麦克风 = 连接成功
4. 在飞书中搜索你的机器人名称，发起私聊，用语音输入发消息
5. Mac 端当前光标位置自动插入文字

## 项目结构

```
VoiceBridge/
├── VoiceBridgeApp.swift          # App 入口，MenuBarExtra
├── Views/
│   ├── MenuBarView.swift         # 菜单栏下拉内容
│   └── SettingsView.swift        # 设置界面
├── Services/
│   ├── FeishuClient.swift        # 飞书 WebSocket 长连接、消息解析、去重
│   ├── TextInjector.swift        # 三层文本注入
│   └── PermissionManager.swift   # 辅助功能权限检测
├── Models/
│   └── FeishuMessage.swift       # 飞书事件数据模型
├── Utilities/
│   ├── ProtobufCodec.swift       # 最小化 Protobuf 编解码器
│   └── KeychainHelper.swift      # Keychain 安全存储
└── Assets.xcassets
```

## 许可证

MIT
