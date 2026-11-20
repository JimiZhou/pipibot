// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// WeChat iLink Bot HTTP/JSON Protocol Client (`ilinkai.weixin.qq.com`)
// - QR Code Login Binding (`get_bot_qrcode`, `get_qrcode_status`)
// - Long-Polling Message Loop (`getupdates`) + Typing Indicator (`sendtyping`)
// - 1v1 Main PiPiBot Mode (default) & Multi-Agent Prefix Group Mode (`【助手名称】`)
// - Outbound Text + AES-128-ECB CDN Rich Media Delivery (Image / Video / File / Voice).

import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - 1. WeChat iLink Mode, State & Protocol Contracts

public enum PipiWeChatRoutingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case directMainBot = "direct_main_bot"
    case groupPrefixMode = "group_prefix_mode"

    public var id: String { rawValue }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .directMainBot:
            return lang == .zhHans ? "1v1 主智能体模式（默认）" : "1v1 Main Agent (Default)"
        case .groupPrefixMode:
            return lang == .zhHans ? "群聊模式（消息前缀区分智能体）" : "Group Mode (Agent Prefixes)"
        }
    }

    public func shortLabel(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .directMainBot:
            return lang == .zhHans ? "1v1 主智能体" : "1v1 Main Bot"
        case .groupPrefixMode:
            return lang == .zhHans ? "群聊前缀模式" : "Group Prefix"
        }
    }
}

public enum PipiWeChatILinkState: Sendable, Equatable {
    case disconnected
    case requestingQR
    case awaitingScan(qrcodeToken: String, qrContent: String, scanned: Bool)
    case connected(botId: String, userId: String, connectedAt: Date)
    case sessionExpired(String)
    case error(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var qrPayload: String? {
        if case .awaitingScan(_, let content, _) = self { return content }
        return nil
    }

    public var isScannedWaitingConfirm: Bool {
        if case .awaitingScan(_, _, let scanned) = self { return scanned }
        return false
    }
}

public struct PipiWeChatBotCandidate: Identifiable, Hashable, Sendable, Equatable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct PipiWeChatRouteDecision: Sendable, Equatable {
    public let targetBotIds: [String]
    public let cleanedPrompt: String
    public let isExplicitMention: Bool

    public init(targetBotIds: [String], cleanedPrompt: String, isExplicitMention: Bool) {
        self.targetBotIds = targetBotIds
        self.cleanedPrompt = cleanedPrompt
        self.isExplicitMention = isExplicitMention
    }
}

public struct PipiWeChatOutboundReply: Sendable, Equatable {
    public let botName: String
    public let text: String
    public let artifacts: [PipiDeliverableArtifact]

    public init(botName: String, text: String, artifacts: [PipiDeliverableArtifact] = []) {
        self.botName = botName
        self.text = text
        self.artifacts = artifacts
    }
}

public struct PipiWeChatInboundMessage: Sendable, Equatable {
    public let messageId: String
    public let fromUserId: String
    public let contextToken: String
    public let text: String

    public init(messageId: String, fromUserId: String, contextToken: String, text: String) {
        self.messageId = messageId
        self.fromUserId = fromUserId
        self.contextToken = contextToken
        self.text = text
    }
}

public struct PipiWeChatSessionCredentials: Codable, Sendable, Equatable {
    public let botToken: String
    public let botId: String
    public let userId: String
    public let baseURL: String

    public init(botToken: String, botId: String, userId: String, baseURL: String) {
        self.botToken = botToken
        self.botId = botId
        self.userId = userId
        self.baseURL = baseURL
    }
}

public struct PipiWeChatMessageBridge: Sendable {
    public let availableBots: @Sendable () async -> [PipiWeChatBotCandidate]
    public let executeTurn: @Sendable (_ botId: String, _ prompt: String, _ fromUserId: String) async -> PipiWeChatOutboundReply
    public let switchModeFromChat: @Sendable (_ mode: PipiWeChatRoutingMode) async -> Void

    public init(
        availableBots: @escaping @Sendable () async -> [PipiWeChatBotCandidate],
        executeTurn: @escaping @Sendable (_ botId: String, _ prompt: String, _ fromUserId: String) async -> PipiWeChatOutboundReply,
        switchModeFromChat: @escaping @Sendable (_ mode: PipiWeChatRoutingMode) async -> Void
    ) {
        self.availableBots = availableBots
        self.executeTurn = executeTurn
        self.switchModeFromChat = switchModeFromChat
    }
}

// MARK: - 2. Pure Protocol & Prefix-Routing Helpers (Unit-Testable)

public enum PipiWeChatILinkProtocol {
    public static let defaultBaseURL = "https://ilinkai.weixin.qq.com"
    public static let defaultCdnBaseURL = "https://novac2c.cdn.weixin.qq.com/c2c"
    public static let channelVersion = "0.9.0"

    /// Generates the Base64-encoded random uint32 header value required by WeChat iLink (`X-WECHAT-UIN`).
    public static func makeWeChatUINHeader() -> String {
        let randomValue = UInt32.random(in: 1...UInt32.max)
        return Data(String(randomValue).utf8).base64EncodedString()
    }

    /// Formats an outbound assistant reply:
    /// - In `directMainBot` (1v1): returns clean text directly.
    /// - In `groupPrefixMode`: always prefixes `【<BotName>】` so each assistant is unmistakably distinguished inside WeChat's single iLink chat stream.
    public static func formatOutboundText(
        _ text: String,
        botName: String,
        mode: PipiWeChatRoutingMode
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        switch mode {
        case .directMainBot:
            return trimmed
        case .groupPrefixMode:
            if trimmed.hasPrefix("【\(botName)】") {
                return trimmed
            }
            return "【\(botName)】\n\(trimmed)"
        }
    }

    /// Resolves which agent(s) should handle an inbound WeChat message:
    /// - In `directMainBot`: routes to `primaryBotId` (unless the user explicitly writes `@OtherBot ...`).
    /// - In `groupPrefixMode`:
    ///   - `@助手名 ...` / `#助手名 ...` / `【助手名】...` routes to that exact assistant.
    ///   - `@all ...` / `@全体 ...` or general group messages route to the active group roster (up to 3 bots).
    public static func resolveRoute(
        text rawText: String,
        mode: PipiWeChatRoutingMode,
        primaryBotId: String,
        groupMemberIds: [String],
        allBots: [PipiWeChatBotCandidate]
    ) -> PipiWeChatRouteDecision {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !allBots.isEmpty else {
            return PipiWeChatRouteDecision(targetBotIds: [primaryBotId], cleanedPrompt: trimmed, isExplicitMention: false)
        }

        // Check explicit prefix mention: "@Name msg", "#Name msg", or "【Name】msg"
        let sortedBots = allBots.sorted { $0.name.count > $1.name.count }
        for bot in sortedBots {
            let prefixes = [
                "@\(bot.name) ", "@\(bot.name)：", "@\(bot.name):", "@\(bot.name)\n",
                "#\(bot.name) ", "#\(bot.name)：", "#\(bot.name):",
                "【\(bot.name)】"
            ]
            for prefix in prefixes {
                if trimmed.lowercased().hasPrefix(prefix.lowercased()) {
                    let body = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    return PipiWeChatRouteDecision(
                        targetBotIds: [bot.id],
                        cleanedPrompt: body.isEmpty ? trimmed : body,
                        isExplicitMention: true
                    )
                }
            }
        }

        // Check @all / @全体
        for allPrefix in ["@all ", "@all：", "@all:", "@全体 ", "@全体：", "@全体:", "@所有人 "] {
            if trimmed.lowercased().hasPrefix(allPrefix.lowercased()) {
                let body = String(trimmed.dropFirst(allPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                let roster = effectiveGroupRoster(primaryBotId: primaryBotId, groupMemberIds: groupMemberIds, allBots: allBots)
                return PipiWeChatRouteDecision(
                    targetBotIds: roster,
                    cleanedPrompt: body.isEmpty ? trimmed : body,
                    isExplicitMention: true
                )
            }
        }

        switch mode {
        case .directMainBot:
            let resolvedPrimary = allBots.contains(where: { $0.id == primaryBotId }) ? primaryBotId : allBots[0].id
            return PipiWeChatRouteDecision(
                targetBotIds: [resolvedPrimary],
                cleanedPrompt: trimmed,
                isExplicitMention: false
            )
        case .groupPrefixMode:
            let roster = effectiveGroupRoster(primaryBotId: primaryBotId, groupMemberIds: groupMemberIds, allBots: allBots)
            return PipiWeChatRouteDecision(
                targetBotIds: roster,
                cleanedPrompt: trimmed,
                isExplicitMention: false
            )
        }
    }

    public static func effectiveGroupRoster(
        primaryBotId: String,
        groupMemberIds: [String],
        allBots: [PipiWeChatBotCandidate]
    ) -> [String] {
        let validIds = Set(allBots.map(\.id))
        let chosen = groupMemberIds.filter { validIds.contains($0) }
        if !chosen.isEmpty {
            return Array(chosen.prefix(3))
        }
        var defaults: [String] = []
        if validIds.contains(primaryBotId) {
            defaults.append(primaryBotId)
        }
        for bot in allBots where !defaults.contains(bot.id) {
            defaults.append(bot.id)
            if defaults.count >= 3 { break }
        }
        return defaults
    }

    /// Parses inbound `getupdates` JSON payload into normalized messages + updated sync cursor.
    public static func parseGetUpdatesResponse(_ data: Data) -> (
        messages: [PipiWeChatInboundMessage],
        nextCursor: String?,
        errCode: Int
    ) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return ([], nil, 0)
        }
        let errCode = (root["errcode"] as? Int) ?? (root["ret"] as? Int) ?? 0
        let nextCursor = root["get_updates_buf"] as? String
        let rawMsgs = (root["msgs"] as? [[String: Any]]) ?? []
        var parsed: [PipiWeChatInboundMessage] = []

        for m in rawMsgs {
            // message_type == 1 is inbound user message (2 is outbound bot echo)
            if let mType = m["message_type"] as? Int, mType != 1 {
                continue
            }
            guard let fromUser = (m["from_user_id"] as? String), !fromUser.isEmpty,
                  let ctxToken = (m["context_token"] as? String), !ctxToken.isEmpty else {
                continue
            }
            let msgId = (m["message_id"] as? String)
                ?? (m["msg_id"] as? String)
                ?? (m["seq"] as? Int).map(String.init)
                ?? UUID().uuidString
            var textParts: [String] = []
            if let items = m["item_list"] as? [[String: Any]] {
                for item in items {
                    if let textItem = item["text_item"] as? [String: Any],
                       let txt = textItem["text"] as? String,
                       !txt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        textParts.append(txt)
                    } else if let voiceItem = item["voice_item"] as? [String: Any],
                              let txt = voiceItem["text"] as? String,
                              !txt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        textParts.append(txt)
                    }
                }
            }
            let combined = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !combined.isEmpty else { continue }
            parsed.append(PipiWeChatInboundMessage(
                messageId: msgId,
                fromUserId: fromUser,
                contextToken: ctxToken,
                text: combined
            ))
        }
        return (parsed, nextCursor, errCode)
    }

    /// AES-128-ECB + PKCS#7 encryption used by WeChat iLink CDN media uploads.
    public static func aes128ECBEncrypt(_ plaintext: Data, key16: Data) -> Data? {
        #if canImport(CommonCrypto)
        guard key16.count == kCCKeySizeAES128 else { return nil }
        let outCapacity = plaintext.count + kCCBlockSizeAES128
        var outBytes = Data(count: outCapacity)
        var outLength: Int = 0
        let status: CCCryptorStatus = outBytes.withUnsafeMutableBytes { outBuf in
            plaintext.withUnsafeBytes { inBuf in
                key16.withUnsafeBytes { keyBuf in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBuf.baseAddress, kCCKeySizeAES128,
                        nil,
                        inBuf.baseAddress, plaintext.count,
                        outBuf.baseAddress, outCapacity,
                        &outLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        outBytes.removeSubrange(outLength..<outBytes.count)
        return outBytes
        #else
        return nil
        #endif
    }

    public static func md5Hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        #endif
    }

    public static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        for idx in 0..<count {
            bytes[idx] = UInt8.random(in: 0...255)
        }
        return Data(bytes)
    }
}

// MARK: - 3. Live WeChat iLink Bot Manager

@MainActor
@Observable
public final class PipiWeChatILinkManager {
    public private(set) var state: PipiWeChatILinkState = .disconnected
    public var routingMode: PipiWeChatRoutingMode = .directMainBot
    public var primaryBotId: String = "pipibot-main"
    public var groupMemberBotIds: [String] = []
    public private(set) var messagesHandledCount: Int = 0
    public private(set) var lastActivityNote: String? = nil

    private var credentials: PipiWeChatSessionCredentials?
    private var qrPollTask: Task<Void, Never>?
    private var updatesLoopTask: Task<Void, Never>?
    private var syncCursor: String = ""
    private var seenMessageIds: Set<String> = []
    private let secretStore: any PipiSecretStore
    private let session: URLSession

    private static let keychainAccountKey = "wechat_ilink_bot_credentials_v1"

    public init(secretStore: any PipiSecretStore = PipiKeychainSecretStore(), session: URLSession = .shared) {
        self.secretStore = secretStore
        self.session = session
        restoreSavedCredentialsIfAvailable()
    }

    public var hasSavedCredentials: Bool { credentials != nil }

    private func restoreSavedCredentialsIfAvailable() {
        guard let raw = secretStore.secret(for: Self.keychainAccountKey),
              let data = raw.data(using: .utf8),
              let saved = try? JSONDecoder().decode(PipiWeChatSessionCredentials.self, from: data) else {
            return
        }
        self.credentials = saved
    }

    private func persistCredentials(_ creds: PipiWeChatSessionCredentials) {
        self.credentials = creds
        if let data = try? JSONEncoder().encode(creds),
           let json = String(data: data, encoding: .utf8) {
            secretStore.setSecret(json, for: Self.keychainAccountKey)
        }
    }

    private func clearSavedCredentials() {
        self.credentials = nil
        secretStore.deleteSecret(for: Self.keychainAccountKey)
    }

    /// Reconnects using previously authorized iLink credentials stored in Keychain.
    public func reconnectSavedSession(bridge: PipiWeChatMessageBridge) {
        guard let creds = credentials else {
            state = .disconnected
            return
        }
        stopTasksOnly()
        state = .connected(botId: creds.botId, userId: creds.userId, connectedAt: Date())
        lastActivityNote = "已恢复微信 iLink 长轮询连接"
        startUpdatesLoop(creds: creds, bridge: bridge)
    }

    /// Requests a fresh WeChat iLink QR code (`get_bot_qrcode`) and polls `get_qrcode_status` until confirmed.
    public func startQRLogin(bridge: PipiWeChatMessageBridge) async {
        stopTasksOnly()
        state = .requestingQR
        lastActivityNote = "正在向微信 iLink 网关申请绑定二维码..."

        guard let url = URL(string: "\(PipiWeChatILinkProtocol.defaultBaseURL)/ilink/bot/get_bot_qrcode?bot_type=3") else {
            state = .error("无效的 iLink 网关地址")
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("1", forHTTPHeaderField: "iLink-App-ClientVersion")
        req.setValue(PipiWeChatILinkProtocol.makeWeChatUINHeader(), forHTTPHeaderField: "X-WECHAT-UIN")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                state = .error("微信 iLink 网关返回异常，请检查网络连接后重试。")
                return
            }

            let qrToken = (obj["qrcode"] as? String) ?? ""
            let qrContent = (obj["qrcode_img_content"] as? String) ?? (obj["qrcode_url"] as? String) ?? ""
            guard !qrToken.isEmpty, !qrContent.isEmpty else {
                let errMsg = (obj["errmsg"] as? String) ?? "未获取到有效二维码内容"
                state = .error(errMsg)
                return
            }

            state = .awaitingScan(qrcodeToken: qrToken, qrContent: qrContent, scanned: false)
            lastActivityNote = "请使用手机微信扫描二维码并确认绑定"
            startQRStatusPolling(qrToken: qrToken, qrContent: qrContent, bridge: bridge)
        } catch {
            state = .error("获取微信绑定二维码失败：\(error.localizedDescription)")
        }
    }

    public func disconnect(forgetBinding: Bool = false) {
        stopTasksOnly()
        if forgetBinding {
            clearSavedCredentials()
            lastActivityNote = "已解除微信 iLink 绑定"
        } else {
            lastActivityNote = "已停止微信 iLink 监听"
        }
        state = .disconnected
    }

    private func stopTasksOnly() {
        qrPollTask?.cancel()
        qrPollTask = nil
        updatesLoopTask?.cancel()
        updatesLoopTask = nil
    }

    private func startQRStatusPolling(qrToken: String, qrContent: String, bridge: PipiWeChatMessageBridge) {
        qrPollTask?.cancel()
        qrPollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let encoded = qrToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? qrToken
            guard let pollURL = URL(string: "\(PipiWeChatILinkProtocol.defaultBaseURL)/ilink/bot/get_qrcode_status?qrcode=\(encoded)") else {
                return
            }

            for _ in 0..<180 {
                if Task.isCancelled { return }
                var req = URLRequest(url: pollURL)
                req.httpMethod = "GET"
                req.timeoutInterval = 35
                req.setValue("1", forHTTPHeaderField: "iLink-App-ClientVersion")
                req.setValue(PipiWeChatILinkProtocol.makeWeChatUINHeader(), forHTTPHeaderField: "X-WECHAT-UIN")

                do {
                    let (data, _) = try await self.session.data(for: req)
                    if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                       let status = obj["status"] as? String {
                        switch status {
                        case "wait":
                            break
                        case "scaned", "scanned":
                            self.state = .awaitingScan(qrcodeToken: qrToken, qrContent: qrContent, scanned: true)
                            self.lastActivityNote = "已扫码，请在手机微信点击「确认」"
                        case "confirmed":
                            let botToken = (obj["bot_token"] as? String) ?? ""
                            let botId = (obj["ilink_bot_id"] as? String) ?? "ilink-bot"
                            let userId = (obj["ilink_user_id"] as? String) ?? "wechat-user"
                            let baseURL = (obj["baseurl"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                                ?? PipiWeChatILinkProtocol.defaultBaseURL
                            guard !botToken.isEmpty else {
                                self.state = .error("确认成功但未返回 bot_token")
                                return
                            }
                            let creds = PipiWeChatSessionCredentials(
                                botToken: botToken,
                                botId: botId,
                                userId: userId,
                                baseURL: baseURL
                            )
                            self.persistCredentials(creds)
                            self.syncCursor = ""
                            self.state = .connected(botId: botId, userId: userId, connectedAt: Date())
                            self.lastActivityNote = "微信 iLink 绑定成功，已开始接收消息"
                            self.startUpdatesLoop(creds: creds, bridge: bridge)
                            return
                        case "expired":
                            self.state = .error("二维码已过期，请重新点击获取。")
                            return
                        default:
                            break
                        }
                    }
                } catch {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .seconds(2))
                }
                try? await Task.sleep(for: .milliseconds(1200))
            }
            if case .awaitingScan = self.state {
                self.state = .error("扫码超时，请重新获取二维码。")
            }
        }
    }

    private func startUpdatesLoop(creds: PipiWeChatSessionCredentials, bridge: PipiWeChatMessageBridge) {
        updatesLoopTask?.cancel()
        updatesLoopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let cleanBase = creds.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let updatesURL = URL(string: "\(cleanBase)/ilink/bot/getupdates") else { return }

            while !Task.isCancelled {
                let bodyObj: [String: Any] = [
                    "get_updates_buf": self.syncCursor,
                    "base_info": ["channel_version": PipiWeChatILinkProtocol.channelVersion]
                ]
                var req = URLRequest(url: updatesURL)
                req.httpMethod = "POST"
                req.timeoutInterval = 42
                req.httpBody = try? JSONSerialization.data(withJSONObject: bodyObj)
                self.applyAuthHeaders(&req, token: creds.botToken)

                do {
                    let (data, response) = try await self.session.data(for: req)
                    if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                        self.state = .sessionExpired("微信 iLink 会话已过期，请重新扫码绑定。")
                        return
                    }
                    let parsed = PipiWeChatILinkProtocol.parseGetUpdatesResponse(data)
                    if parsed.errCode == -14 {
                        self.state = .sessionExpired("微信 iLink 授权已失效（errcode -14），请重新扫码绑定。")
                        return
                    }
                    if let cursor = parsed.nextCursor, !cursor.isEmpty {
                        self.syncCursor = cursor
                    }
                    for inbound in parsed.messages {
                        if self.seenMessageIds.contains(inbound.messageId) { continue }
                        self.seenMessageIds.insert(inbound.messageId)
                        if self.seenMessageIds.count > 400 {
                            self.seenMessageIds.removeAll(keepingCapacity: true)
                        }
                        await self.handleInboundMessage(inbound, creds: creds, bridge: bridge)
                    }
                } catch {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }
    }

    private func handleInboundMessage(
        _ inbound: PipiWeChatInboundMessage,
        creds: PipiWeChatSessionCredentials,
        bridge: PipiWeChatMessageBridge
    ) async {
        messagesHandledCount += 1
        let trimmed = inbound.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let bots = await bridge.availableBots()

        // Built-in WeChat mode & help commands
        if lower == "/mode 1v1" || trimmed == "/单聊" || trimmed == "切换单聊" {
            routingMode = .directMainBot
            await bridge.switchModeFromChat(.directMainBot)
            await sendTextMessage(
                toUserId: inbound.fromUserId,
                contextToken: inbound.contextToken,
                text: "已切换至「1v1 主智能体模式」，后续消息将默认由主 PiPiBot 直接回复。",
                creds: creds
            )
            return
        }
        if lower == "/mode group" || trimmed == "/群聊" || trimmed == "切换群聊" {
            routingMode = .groupPrefixMode
            await bridge.switchModeFromChat(.groupPrefixMode)
            let rosterNames = PipiWeChatILinkProtocol.effectiveGroupRoster(
                primaryBotId: primaryBotId,
                groupMemberIds: groupMemberBotIds,
                allBots: bots
            ).compactMap { id in bots.first(where: { $0.id == id })?.name }
            await sendTextMessage(
                toUserId: inbound.fromUserId,
                contextToken: inbound.contextToken,
                text: "已切换至「群聊模式（前缀区分智能体）」。当前参与成员：\(rosterNames.joined(separator: "、"))。\n每条回复将携带【助手名称】前缀，您也可以直接发送「@助手名 指令」指定单人回复。",
                creds: creds
            )
            return
        }
        if lower == "/bots" || trimmed == "/助手" {
            let list = bots.map { "• \($0.name)" }.joined(separator: "\n")
            let modeText = routingMode == .directMainBot ? "1v1 主智能体" : "群聊前缀模式"
            await sendTextMessage(
                toUserId: inbound.fromUserId,
                contextToken: inbound.contextToken,
                text: "当前模式：\(modeText)\n可用智能体：\n\(list)\n\n快捷指令：/mode 1v1 · /mode group · /screenshot · /sms · /mail · /build <命令>",
                creds: creds
            )
            return
        }

        // Send typing status while Mac executes
        await sendTyping(toUserId: inbound.fromUserId, contextToken: inbound.contextToken, creds: creds)

        let route = PipiWeChatILinkProtocol.resolveRoute(
            text: trimmed,
            mode: routingMode,
            primaryBotId: primaryBotId,
            groupMemberIds: groupMemberBotIds,
            allBots: bots
        )

        lastActivityNote = "正在处理微信消息（\(route.targetBotIds.count) 位智能体）"

        for targetBotId in route.targetBotIds {
            let reply = await bridge.executeTurn(targetBotId, route.cleanedPrompt, inbound.fromUserId)
            let effectiveMode: PipiWeChatRoutingMode = (routingMode == .groupPrefixMode || route.targetBotIds.count > 1)
                ? .groupPrefixMode
                : .directMainBot
            let formattedText = PipiWeChatILinkProtocol.formatOutboundText(
                reply.text,
                botName: reply.botName,
                mode: effectiveMode
            )
            if !formattedText.isEmpty {
                await sendTextMessage(
                    toUserId: inbound.fromUserId,
                    contextToken: inbound.contextToken,
                    text: formattedText,
                    creds: creds
                )
            }
            for artifact in reply.artifacts {
                await sendMediaArtifact(
                    artifact,
                    toUserId: inbound.fromUserId,
                    contextToken: inbound.contextToken,
                    creds: creds
                )
            }
        }
        lastActivityNote = "最近回复已完成"
    }

    private func sendTyping(toUserId: String, contextToken: String, creds: PipiWeChatSessionCredentials) async {
        let cleanBase = creds.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanBase)/ilink/bot/sendtyping") else { return }
        let payload: [String: Any] = [
            "ilink_user_id": toUserId,
            "context_token": contextToken,
            "status": 1,
            "base_info": ["channel_version": PipiWeChatILinkProtocol.channelVersion]
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        applyAuthHeaders(&req, token: creds.botToken)
        _ = try? await session.data(for: req)
    }

    private func sendTextMessage(
        toUserId: String,
        contextToken: String,
        text: String,
        creds: PipiWeChatSessionCredentials
    ) async {
        let cleanBase = creds.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanBase)/ilink/bot/sendmessage") else { return }
        let payload: [String: Any] = [
            "msg": [
                "to_user_id": toUserId,
                "client_id": "pipibot_\(UUID().uuidString.prefix(12).lowercased())",
                "message_type": 2,
                "message_state": 2,
                "context_token": contextToken,
                "item_list": [
                    [
                        "type": 1,
                        "text_item": ["text": text]
                    ]
                ]
            ],
            "base_info": ["channel_version": PipiWeChatILinkProtocol.channelVersion]
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        applyAuthHeaders(&req, token: creds.botToken)
        _ = try? await session.data(for: req)
    }

    /// Uploads encrypted media via WeChat iLink `getuploadurl` -> CDN -> `sendmessage` (Image / Video / File / Voice).
    private func sendMediaArtifact(
        _ artifact: PipiDeliverableArtifact,
        toUserId: String,
        contextToken: String,
        creds: PipiWeChatSessionCredentials
    ) async {
        guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: artifact.filePath)),
              !rawData.isEmpty else { return }

        let aesKey = PipiWeChatILinkProtocol.randomBytes(16)
        guard let encrypted = PipiWeChatILinkProtocol.aes128ECBEncrypt(rawData, key16: aesKey) else { return }

        let aesHex = aesKey.map { String(format: "%02x", $0) }.joined()
        let fileKey = PipiWeChatILinkProtocol.randomBytes(16).map { String(format: "%02x", $0) }.joined()
        let rawMD5 = PipiWeChatILinkProtocol.md5Hex(rawData)
        let cleanBase = creds.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let uploadMetaURL = URL(string: "\(cleanBase)/ilink/bot/getuploadurl") else { return }
        let metaPayload: [String: Any] = [
            "filekey": fileKey,
            "media_type": artifact.kind.iLinkMediaType,
            "to_user_id": toUserId,
            "rawsize": rawData.count,
            "rawfilemd5": rawMD5,
            "filesize": encrypted.count,
            "no_need_thumb": true,
            "aeskey": aesHex,
            "base_info": ["channel_version": PipiWeChatILinkProtocol.channelVersion]
        ]

        var metaReq = URLRequest(url: uploadMetaURL)
        metaReq.httpMethod = "POST"
        metaReq.timeoutInterval = 15
        metaReq.httpBody = try? JSONSerialization.data(withJSONObject: metaPayload)
        applyAuthHeaders(&metaReq, token: creds.botToken)

        guard let (metaRespData, _) = try? await session.data(for: metaReq),
              let metaObj = (try? JSONSerialization.jsonObject(with: metaRespData)) as? [String: Any],
              let uploadParam = metaObj["upload_param"] as? String,
              !uploadParam.isEmpty else {
            return
        }

        let encParam = uploadParam.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uploadParam
        let encKey = fileKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fileKey
        guard let cdnURL = URL(string: "\(PipiWeChatILinkProtocol.defaultCdnBaseURL)/upload?encrypted_query_param=\(encParam)&filekey=\(encKey)") else {
            return
        }

        var cdnReq = URLRequest(url: cdnURL)
        cdnReq.httpMethod = "POST"
        cdnReq.timeoutInterval = 45
        cdnReq.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        cdnReq.httpBody = encrypted

        guard let (_, cdnResp) = try? await session.data(for: cdnReq),
              let httpResp = cdnResp as? HTTPURLResponse,
              let downloadParam = httpResp.value(forHTTPHeaderField: "x-encrypted-param"),
              !downloadParam.isEmpty else {
            return
        }

        let aesKeyB64 = Data(aesHex.utf8).base64EncodedString()
        let mediaBlock: [String: Any] = [
            "encrypt_query_param": downloadParam,
            "aes_key": aesKeyB64,
            "encrypt_type": 1
        ]

        let item: [String: Any]
        switch artifact.kind {
        case .image:
            item = [
                "type": 2,
                "image_item": [
                    "media": mediaBlock,
                    "mid_size": encrypted.count
                ]
            ]
        case .audio:
            item = [
                "type": 3,
                "voice_item": [
                    "media": mediaBlock,
                    "playtime": 5000
                ]
            ]
        case .file:
            item = [
                "type": 4,
                "file_item": [
                    "media": mediaBlock,
                    "file_name": artifact.fileName,
                    "len": String(rawData.count)
                ]
            ]
        case .video:
            item = [
                "type": 5,
                "video_item": [
                    "media": mediaBlock,
                    "video_size": encrypted.count
                ]
            ]
        }

        guard let sendURL = URL(string: "\(cleanBase)/ilink/bot/sendmessage") else { return }
        let sendPayload: [String: Any] = [
            "msg": [
                "to_user_id": toUserId,
                "client_id": "pipibot_media_\(UUID().uuidString.prefix(10).lowercased())",
                "message_type": 2,
                "message_state": 2,
                "context_token": contextToken,
                "item_list": [item]
            ],
            "base_info": ["channel_version": PipiWeChatILinkProtocol.channelVersion]
        ]
        var sendReq = URLRequest(url: sendURL)
        sendReq.httpMethod = "POST"
        sendReq.timeoutInterval = 20
        sendReq.httpBody = try? JSONSerialization.data(withJSONObject: sendPayload)
        applyAuthHeaders(&sendReq, token: creds.botToken)
        _ = try? await session.data(for: sendReq)
    }

    private func applyAuthHeaders(_ request: inout URLRequest, token: String) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ilink_bot_token", forHTTPHeaderField: "AuthorizationType")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(PipiWeChatILinkProtocol.makeWeChatUINHeader(), forHTTPHeaderField: "X-WECHAT-UIN")
    }
}
