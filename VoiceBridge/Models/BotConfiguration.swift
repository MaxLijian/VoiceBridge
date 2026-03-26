import Foundation

enum Channel: String, Codable {
    case feishu
}

struct BotConfiguration: Codable, Identifiable {
    let id: UUID
    var name: String
    var channel: Channel
    var appId: String
    var isEnabled: Bool
    var createdAt: Date

    init(id: UUID = UUID(), name: String, channel: Channel = .feishu,
         appId: String, isEnabled: Bool = true, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.channel = channel
        self.appId = appId
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}
