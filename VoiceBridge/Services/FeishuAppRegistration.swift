import Foundation
import os

/// 飞书应用一键创建协议（移植自 openclaw-lark-tools 的 app/registration API）
/// 三步流程：init → begin（获取二维码 URL）→ poll（轮询获取凭据）
@Observable
final class FeishuAppRegistration {

    enum State: Equatable {
        case idle
        case initializing
        case waitingForScan(url: String, expiresIn: Int)
        case polling
        case success(appId: String, appSecret: String)
        case failed(message: String)
    }

    private(set) var state: State = .idle

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "VoiceBridge",
                                category: "FeishuAppRegistration")
    private let session = URLSession(configuration: .default)
    private let baseURL = "https://accounts.feishu.cn"
    private var pollTask: Task<Void, Never>?

    func start() {
        cancel()
        state = .initializing

        pollTask = Task {
            do {
                // Step 1: init
                let initRes = try await callRegistration(params: ["action": "init"])
                guard let methods = initRes["supported_auth_methods"] as? [String],
                      methods.contains("client_secret") else {
                    state = .failed(message: "当前环境不支持自动创建机器人")
                    return
                }

                // Step 2: begin
                let beginRes = try await callRegistration(params: [
                    "action": "begin",
                    "archetype": "PersonalAgent",
                    "auth_method": "client_secret",
                    "request_user_info": "open_id",
                ])

                guard let deviceCode = beginRes["device_code"] as? String,
                      let verificationURL = beginRes["verification_uri_complete"] as? String else {
                    state = .failed(message: "获取二维码失败")
                    return
                }

                let expiresIn = beginRes["expire_in"] as? Int ?? 600
                let interval = beginRes["interval"] as? Int ?? 5

                logger.info("获取注册二维码成功，有效期 \(expiresIn)s")
                state = .waitingForScan(url: verificationURL, expiresIn: expiresIn)

                // Step 3: poll
                let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
                var currentInterval = interval

                while Date() < deadline {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .seconds(currentInterval))
                    try Task.checkCancellation()

                    state = .polling

                    let pollRes = try await callRegistration(params: [
                        "action": "poll",
                        "device_code": deviceCode,
                    ])

                    // 检查是否需要切换到 Lark 域名
                    if let userInfo = pollRes["user_info"] as? [String: Any],
                       let brand = userInfo["tenant_brand"] as? String,
                       brand == "lark" {
                        logger.info("检测到 Lark 租户，但 VoiceBridge 目前仅支持飞书")
                    }

                    // 成功获取凭据
                    if let clientId = pollRes["client_id"] as? String,
                       let clientSecret = pollRes["client_secret"] as? String {
                        logger.info("机器人创建成功，App ID: \(clientId)")
                        state = .success(appId: clientId, appSecret: clientSecret)
                        return
                    }

                    // 处理错误
                    if let error = pollRes["error"] as? String {
                        switch error {
                        case "authorization_pending":
                            state = .waitingForScan(url: verificationURL, expiresIn: expiresIn)
                            continue
                        case "slow_down":
                            currentInterval = min(currentInterval + 5, 60)
                            continue
                        case "access_denied":
                            state = .failed(message: "用户拒绝授权")
                            return
                        case "expired_token":
                            state = .failed(message: "二维码已过期，请重试")
                            return
                        default:
                            let desc = pollRes["error_description"] as? String ?? error
                            state = .failed(message: desc)
                            return
                        }
                    }
                }

                state = .failed(message: "二维码已过期，请重试")
            } catch is CancellationError {
                state = .idle
            } catch {
                logger.error("注册流程失败: \(error.localizedDescription)")
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    func cancel() {
        pollTask?.cancel()
        pollTask = nil
        state = .idle
    }

    // MARK: - API 调用

    private func callRegistration(params: [String: String]) async throws -> [String: Any] {
        let url = URL(string: "\(baseURL)/oauth/v1/app/registration")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await session.data(for: request)

        let action = params["action"] ?? "unknown"
        logger.info("[\(action)] 响应: \(String(data: data, encoding: .utf8) ?? "<binary>")")

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RegistrationError.invalidResponse
        }

        return json
    }
}

enum RegistrationError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "飞书注册 API 返回无效响应"
    }
}
