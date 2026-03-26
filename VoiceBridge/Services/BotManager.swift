import Foundation
import os

@Observable
final class BotManager {

    static let shared = BotManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceBridge",
                                category: "BotManager")

    private(set) var bots: [BotConfiguration] = []

    /// 是否已完成配置（至少有一个机器人）
    var isConfigured: Bool { !bots.isEmpty }

    private let storageURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("VoiceBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bots.json")
    }()

    private init() {
        loadBots()
        migrateFromLegacyIfNeeded()
    }

    // MARK: - CRUD

    func addBot(_ bot: BotConfiguration, secret: String) {
        bots.append(bot)
        saveSecret(secret, for: bot.id)
        saveBots()
        logger.info("添加机器人: \(bot.name) (\(bot.appId))")
    }

    func removeBot(_ bot: BotConfiguration) {
        bots.removeAll { $0.id == bot.id }
        KeychainHelper.delete("bot-secret-\(bot.id.uuidString)")
        saveBots()
        logger.info("删除机器人: \(bot.name)")
    }

    func toggleBot(_ bot: BotConfiguration, enabled: Bool) {
        guard let index = bots.firstIndex(where: { $0.id == bot.id }) else { return }
        bots[index].isEnabled = enabled
        saveBots()
    }

    func secret(for bot: BotConfiguration) -> String? {
        guard let data = KeychainHelper.load(for: "bot-secret-\(bot.id.uuidString)"),
              let secret = String(data: data, encoding: .utf8) else { return nil }
        return secret
    }

    // MARK: - 持久化

    private func saveBots() {
        do {
            let data = try JSONEncoder().encode(bots)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            logger.error("保存机器人配置失败: \(error.localizedDescription)")
        }
    }

    private func loadBots() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            bots = try JSONDecoder().decode([BotConfiguration].self, from: data)
        } catch {
            logger.error("加载机器人配置失败: \(error.localizedDescription)")
        }
    }

    private func saveSecret(_ secret: String, for botId: UUID) {
        if let data = secret.data(using: .utf8) {
            _ = KeychainHelper.save(data, for: "bot-secret-\(botId.uuidString)")
        }
    }

    // MARK: - 旧数据迁移

    /// 将旧版单机器人配置（UserDefaults + Keychain）迁移到新格式
    private func migrateFromLegacyIfNeeded() {
        guard bots.isEmpty else { return }

        let legacyAppId = UserDefaults.standard.string(forKey: "feishuAppId") ?? ""
        guard !legacyAppId.isEmpty,
              let secretData = KeychainHelper.load(for: "feishuAppSecret"),
              let secret = String(data: secretData, encoding: .utf8),
              !secret.isEmpty else { return }

        let bot = BotConfiguration(name: "我的语音助手", appId: legacyAppId)
        addBot(bot, secret: secret)

        // 清理旧数据
        UserDefaults.standard.removeObject(forKey: "feishuAppId")
        KeychainHelper.delete("feishuAppSecret")
        UserDefaults.standard.removeObject(forKey: "feishuAppId.backup")
        KeychainHelper.delete("feishuAppSecret.backup")

        logger.info("已迁移旧版机器人配置: \(legacyAppId)")
    }
}
