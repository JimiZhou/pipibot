// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// WeChat iLink Bot HTTP/JSON Protocol Client (`ilinkai.weixin.qq.com`)
// - QR Code Login Binding (`get_bot_qrcode`, `get_qrcode_status`)
// - Long-Polling Message Loop (`getupdates`) + Continuous Typing Indicator (`sendtyping` status 1/2)
// - Inbound & Outbound Rich Media (Text / Voice + ASR / Image / File / Video via AES-128-ECB CDN)
// - 1v1 Main PiPiBot Conversational Control Plane & Multi-Agent Prefix Group Mode (`【助手名称】`).

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
    public let pendingApproval: PipiWeChatPendingApprovalInfo?

    public init(
        botName: String,
        text: String,
        artifacts: [PipiDeliverableArtifact] = [],
        pendingApproval: PipiWeChatPendingApprovalInfo? = nil
    ) {
        self.botName = botName
        self.text = text
        self.artifacts = artifacts
        self.pendingApproval = pendingApproval
    }
}

public enum PipiWeChatInboundMediaKind: String, Sendable, Equatable {
    case image
    case voice
    case file
    case video
}

public struct PipiWeChatInboundMediaRef: Sendable, Equatable {
    public let kind: PipiWeChatInboundMediaKind
    public let encryptQueryParam: String
    public let aesKeyRaw: String
    public let directURL: String?
    public let fileName: String?
    public let byteSize: Int64?
    public let playtimeMs: Int?

    public init(
        kind: PipiWeChatInboundMediaKind,
        encryptQueryParam: String,
        aesKeyRaw: String,
        directURL: String? = nil,
        fileName: String? = nil,
        byteSize: Int64? = nil,
        playtimeMs: Int? = nil
    ) {
        self.kind = kind
        self.encryptQueryParam = encryptQueryParam
        self.aesKeyRaw = aesKeyRaw
        self.directURL = directURL
        self.fileName = fileName
        self.byteSize = byteSize
        self.playtimeMs = playtimeMs
    }
}

public struct PipiWeChatInboundMessage: Sendable, Equatable {
    public let messageId: String
    public let fromUserId: String
    public let contextToken: String
    public let text: String
    public let voiceText: String?
    public let voiceMedia: PipiWeChatInboundMediaRef?
    public let imageMedias: [PipiWeChatInboundMediaRef]
    public let fileMedias: [PipiWeChatInboundMediaRef]
    public let videoMedias: [PipiWeChatInboundMediaRef]

    public var hasVoice: Bool {
        voiceText != nil || voiceMedia != nil
    }

    public var hasAttachments: Bool {
        !imageMedias.isEmpty || !fileMedias.isEmpty || !videoMedias.isEmpty
    }

    public init(
        messageId: String,
        fromUserId: String,
        contextToken: String,
        text: String,
        voiceText: String? = nil,
        voiceMedia: PipiWeChatInboundMediaRef? = nil,
        imageMedias: [PipiWeChatInboundMediaRef] = [],
        fileMedias: [PipiWeChatInboundMediaRef] = [],
        videoMedias: [PipiWeChatInboundMediaRef] = []
    ) {
        self.messageId = messageId
        self.fromUserId = fromUserId
        self.contextToken = contextToken
        self.text = text
        self.voiceText = voiceText
        self.voiceMedia = voiceMedia
        self.imageMedias = imageMedias
        self.fileMedias = fileMedias
        self.videoMedias = videoMedias
    }
}

public struct PipiWeChatSessionCredentials: Codable, Sendable, Equatable {
    public let botToken: String
    public let botId: String
    public let userId: String
    public let baseURL: String
    public var lastFromUserId: String?
    public var lastContextToken: String?

    public init(
        botToken: String,
        botId: String,
        userId: String,
        baseURL: String,
        lastFromUserId: String? = nil,
        lastContextToken: String? = nil
    ) {
        self.botToken = botToken
        self.botId = botId
        self.userId = userId
        self.baseURL = baseURL
        self.lastFromUserId = lastFromUserId
        self.lastContextToken = lastContextToken
    }
}

public struct PipiWeChatMessageBridge: Sendable {
    public let availableBots: @Sendable () async -> [PipiWeChatBotInfo]
    public let availableProjects: @Sendable () async -> [PipiWeChatProjectInfo]
    public let availableConversations: @Sendable () async -> [PipiWeChatConversationInfo]
    public let availableModelChoices: @Sendable () async -> [PipiWeChatModelChoice]
    public let executeTurn: @Sendable (
        _ botId: String,
        _ conversationId: String?,
        _ projectId: String?,
        _ prompt: String,
        _ attachments: [PipiChatAttachment],
        _ fromUserId: String
    ) async -> (reply: PipiWeChatOutboundReply, resolvedConversationId: String?)
    public let createBot: @Sendable (
        _ name: String,
        _ role: String,
        _ templateId: String?,
        _ target: PipiExecutionTarget,
        _ modelId: String?,
        _ permissionTier: PipiPermissionTier
    ) async -> PipiWeChatBotInfo?
    public let createConversation: @Sendable (_ personaId: String, _ projectId: String?, _ title: String?) async -> String?
    public let bindConversationProject: @Sendable (_ conversationId: String, _ projectId: String?) async -> Void
    public let updateBotConfig: @Sendable (
        _ botId: String,
        _ target: PipiExecutionTarget?,
        _ modelId: String?,
        _ clearModelOverride: Bool,
        _ permissionTier: PipiPermissionTier?
    ) async -> String
    public let toggleSetting: @Sendable (_ settingKey: String) async -> String
    public let fetchConfigSnapshot: @Sendable (_ primaryBotId: String, _ routingMode: PipiWeChatRoutingMode, _ typingEnabled: Bool, _ convId: String?, _ projId: String?) async -> PipiWeChatConfigSnapshot
    public let resolveApproval: @Sendable (_ approvalId: String, _ optionId: String) async -> PipiWeChatOutboundReply?
    public let checkForUpdates: @Sendable () async -> (message: String, release: PipiGitHubReleaseInfo?)
    public let installUpdate: @Sendable (_ release: PipiGitHubReleaseInfo) async -> String
    public let transcribeAudioFile: @Sendable (_ filePath: String) async -> String?
    public let switchModeFromChat: @Sendable (_ mode: PipiWeChatRoutingMode, _ memberBotIds: [String]?) async -> Void

    public init(
        availableBots: @escaping @Sendable () async -> [PipiWeChatBotInfo],
        availableProjects: @escaping @Sendable () async -> [PipiWeChatProjectInfo] = { [] },
        availableConversations: @escaping @Sendable () async -> [PipiWeChatConversationInfo] = { [] },
        availableModelChoices: @escaping @Sendable () async -> [PipiWeChatModelChoice] = { [] },
        executeTurn: @escaping @Sendable (
            _ botId: String,
            _ conversationId: String?,
            _ projectId: String?,
            _ prompt: String,
            _ attachments: [PipiChatAttachment],
            _ fromUserId: String
        ) async -> (reply: PipiWeChatOutboundReply, resolvedConversationId: String?),
        createBot: @escaping @Sendable (
            _ name: String,
            _ role: String,
            _ templateId: String?,
            _ target: PipiExecutionTarget,
            _ modelId: String?,
            _ permissionTier: PipiPermissionTier
        ) async -> PipiWeChatBotInfo? = { _, _, _, _, _, _ in nil },
        createConversation: @escaping @Sendable (_ personaId: String, _ projectId: String?, _ title: String?) async -> String? = { _, _, _ in nil },
        bindConversationProject: @escaping @Sendable (_ conversationId: String, _ projectId: String?) async -> Void = { _, _ in },
        updateBotConfig: @escaping @Sendable (_ botId: String, _ target: PipiExecutionTarget?, _ modelId: String?, _ clearModelOverride: Bool, _ permissionTier: PipiPermissionTier?) async -> String = { _, _, _, _, _ in "" },
        toggleSetting: @escaping @Sendable (_ settingKey: String) async -> String = { _ in "" },
        fetchConfigSnapshot: @escaping @Sendable (_ primaryBotId: String, _ routingMode: PipiWeChatRoutingMode, _ typingEnabled: Bool, _ convId: String?, _ projId: String?) async -> PipiWeChatConfigSnapshot,
        resolveApproval: @escaping @Sendable (_ approvalId: String, _ optionId: String) async -> PipiWeChatOutboundReply? = { _, _ in nil },
        checkForUpdates: @escaping @Sendable () async -> (message: String, release: PipiGitHubReleaseInfo?) = { ("未接入更新服务。", nil) },
        installUpdate: @escaping @Sendable (_ release: PipiGitHubReleaseInfo) async -> String = { _ in "未接入更新服务。" },
        transcribeAudioFile: @escaping @Sendable (_ filePath: String) async -> String? = { _ in nil },
        switchModeFromChat: @escaping @Sendable (_ mode: PipiWeChatRoutingMode, _ memberBotIds: [String]?) async -> Void = { _, _ in }
    ) {
        self.availableBots = availableBots
        self.availableProjects = availableProjects
        self.availableConversations = availableConversations
        self.availableModelChoices = availableModelChoices
        self.executeTurn = executeTurn
        self.createBot = createBot
        self.createConversation = createConversation
        self.bindConversationProject = bindConversationProject
        self.updateBotConfig = updateBotConfig
        self.toggleSetting = toggleSetting
        self.fetchConfigSnapshot = fetchConfigSnapshot
        self.resolveApproval = resolveApproval
        self.checkForUpdates = checkForUpdates
        self.installUpdate = installUpdate
        self.transcribeAudioFile = transcribeAudioFile
        self.switchModeFromChat = switchModeFromChat
    }
}

// MARK: - 2. Pure Protocol, Rich Media & Prefix-Routing Helpers (Unit-Testable)

public enum PipiWeChatILinkProtocol {
    public static let defaultBaseURL = "https://ilinkai.weixin.qq.com"
    public static let defaultCdnBaseURL = "https://novac2c.cdn.weixin.qq.com/c2c"
    public static let channelVersion = "0.10.0"

    /// Generates the Base64-encoded random uint32 header value required by WeChat iLink (`X-WECHAT-UIN`).
    public static func makeWeChatUINHeader() -> String {
        let randomValue = UInt32.random(in: 1...UInt32.max)
        return Data(String(randomValue).utf8).base64EncodedString()
    }

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

        let sortedBots = allBots.sorted { $0.name.count > $1.name.count }
        for bot in sortedBots {
            let shortName = bot.name.split(separator: "·").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? bot.name
            var prefixes = [
                "@\(bot.name) ", "@\(bot.name)：", "@\(bot.name):", "@\(bot.name)\n",
                "#\(bot.name) ", "#\(bot.name)：", "#\(bot.name):",
                "【\(bot.name)】"
            ]
            if shortName != bot.name && !shortName.isEmpty {
                prefixes.append(contentsOf: [
                    "@\(shortName) ", "@\(shortName)：", "@\(shortName):", "@\(shortName)\n",
                    "#\(shortName) ", "【\(shortName)】"
                ])
            }
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
            return Array(chosen.prefix(4))
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

    /// Parses inbound `getupdates` JSON payload into normalized messages (Text / Voice / Image / File / Video) + updated sync cursor.
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
            var voiceText: String? = nil
            var voiceMedia: PipiWeChatInboundMediaRef? = nil
            var imageMedias: [PipiWeChatInboundMediaRef] = []
            var fileMedias: [PipiWeChatInboundMediaRef] = []
            var videoMedias: [PipiWeChatInboundMediaRef] = []

            if let items = m["item_list"] as? [[String: Any]] {
                for item in items {
                    let itemType = item["type"] as? Int

                    // 1. Text item (and optional quoted ref_msg)
                    if let textItem = item["text_item"] as? [String: Any] {
                        if let txt = textItem["text"] as? String,
                           !txt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            textParts.append(txt.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        if let ref = item["ref_msg"] as? [String: Any],
                           let refTitle = ref["title"] as? String,
                           !refTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            textParts.append("[引用消息: \(refTitle)]")
                        }
                    }

                    // 2. Voice item (type == 3 or voice_item present)
                    if let voiceItem = item["voice_item"] as? [String: Any] {
                        let asrText = (voiceItem["text"] as? String)
                            ?? (voiceItem["asr_text"] as? String)
                            ?? (voiceItem["recognize_text"] as? String)
                        if let asr = asrText?.trimmingCharacters(in: .whitespacesAndNewlines), !asr.isEmpty {
                            voiceText = asr
                            textParts.append(asr)
                        }
                        if let media = voiceItem["media"] as? [String: Any],
                           let eqp = media["encrypt_query_param"] as? String, !eqp.isEmpty {
                            voiceMedia = PipiWeChatInboundMediaRef(
                                kind: .voice,
                                encryptQueryParam: eqp,
                                aesKeyRaw: (media["aes_key"] as? String) ?? "",
                                directURL: media["url"] as? String,
                                fileName: "wechat_voice_\(msgId).silk",
                                byteSize: (media["size"] as? NSNumber)?.int64Value,
                                playtimeMs: voiceItem["playtime"] as? Int
                            )
                        }
                    }

                    // 3. Image item (type == 2 or image_item present)
                    if let imageItem = item["image_item"] as? [String: Any] {
                        let media = (imageItem["media"] as? [String: Any]) ?? [:]
                        let eqp = (media["encrypt_query_param"] as? String) ?? ""
                        let directURL = (imageItem["url"] as? String) ?? (media["url"] as? String)
                        if !eqp.isEmpty || (directURL?.isEmpty == false) {
                            imageMedias.append(PipiWeChatInboundMediaRef(
                                kind: .image,
                                encryptQueryParam: eqp,
                                aesKeyRaw: (media["aes_key"] as? String) ?? (imageItem["aeskey"] as? String) ?? "",
                                directURL: directURL,
                                fileName: "wechat_image_\(msgId)_\(imageMedias.count + 1).jpg",
                                byteSize: (imageItem["mid_size"] as? NSNumber)?.int64Value
                            ))
                        }
                    }

                    // 4. File / Attachment item (type == 4 or file_item present)
                    if let fileItem = item["file_item"] as? [String: Any] {
                        let media = (fileItem["media"] as? [String: Any]) ?? [:]
                        let eqp = (media["encrypt_query_param"] as? String) ?? ""
                        let directURL = media["url"] as? String
                        let fileName = (fileItem["file_name"] as? String) ?? "wechat_file_\(msgId)"
                        let lenVal: Int64? = (fileItem["len"] as? String).flatMap(Int64.init)
                            ?? (fileItem["len"] as? NSNumber)?.int64Value
                        if !eqp.isEmpty || (directURL?.isEmpty == false) {
                            fileMedias.append(PipiWeChatInboundMediaRef(
                                kind: .file,
                                encryptQueryParam: eqp,
                                aesKeyRaw: (media["aes_key"] as? String) ?? "",
                                directURL: directURL,
                                fileName: fileName,
                                byteSize: lenVal
                            ))
                        }
                    }

                    // 5. Video item (type == 5 or video_item present)
                    if let videoItem = item["video_item"] as? [String: Any] {
                        let media = (videoItem["media"] as? [String: Any]) ?? [:]
                        let eqp = (media["encrypt_query_param"] as? String) ?? ""
                        let directURL = media["url"] as? String
                        if !eqp.isEmpty || (directURL?.isEmpty == false) {
                            videoMedias.append(PipiWeChatInboundMediaRef(
                                kind: .video,
                                encryptQueryParam: eqp,
                                aesKeyRaw: (media["aes_key"] as? String) ?? "",
                                directURL: directURL,
                                fileName: "wechat_video_\(msgId).mp4",
                                byteSize: (videoItem["video_size"] as? NSNumber)?.int64Value
                            ))
                        }
                    }

                    _ = itemType
                }
            }

            let combined = textParts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let hasAnyContent = !combined.isEmpty || voiceMedia != nil || !imageMedias.isEmpty || !fileMedias.isEmpty || !videoMedias.isEmpty
            guard hasAnyContent else { continue }

            parsed.append(PipiWeChatInboundMessage(
                messageId: msgId,
                fromUserId: fromUser,
                contextToken: ctxToken,
                text: combined,
                voiceText: voiceText,
                voiceMedia: voiceMedia,
                imageMedias: imageMedias,
                fileMedias: fileMedias,
                videoMedias: videoMedias
            ))
        }
        return (parsed, nextCursor, errCode)
    }

    /// Decodes WeChat iLink `aes_key` across all three observed encodings:
    /// 1) Base64 of 32-char lowercase hex string -> 16 bytes
    /// 2) Base64 of 16 raw bytes -> 16 bytes
    /// 3) Direct 32-char hex string -> 16 bytes
    public static func decodeILinkAESKey(_ rawKey: String) -> Data? {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.count == 32, let hexBytes = hexStringToData(trimmed), hexBytes.count == 16 {
            return hexBytes
        }
        if let b64Data = Data(base64Encoded: trimmed) {
            if b64Data.count == 16 {
                return b64Data
            }
            if b64Data.count == 32,
               let asHex = String(data: b64Data, encoding: .utf8),
               let hexBytes = hexStringToData(asHex),
               hexBytes.count == 16 {
                return hexBytes
            }
        }
        return nil
    }

    private static func hexStringToData(_ hex: String) -> Data? {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count % 2 == 0 else { return nil }
        var out = Data(capacity: clean.count / 2)
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            guard let byte = UInt8(clean[idx..<next], radix: 16) else { return nil }
            out.append(byte)
            idx = next
        }
        return out
    }

    /// AES-128-ECB + PKCS#7 encryption used by WeChat iLink CDN media uploads.
    public static func aes128ECBEncrypt(_ plaintext: Data, key16: Data) -> Data? {
        cryptAES128ECB(plaintext, key16: key16, operation: CCOperation(kCCEncrypt))
    }

    /// AES-128-ECB + PKCS#7 decryption used by WeChat iLink CDN media downloads.
    public static func aes128ECBDecrypt(_ ciphertext: Data, key16: Data) -> Data? {
        cryptAES128ECB(ciphertext, key16: key16, operation: CCOperation(kCCDecrypt))
    }

    private static func cryptAES128ECB(_ input: Data, key16: Data, operation: CCOperation) -> Data? {
        #if canImport(CommonCrypto)
        guard key16.count == kCCKeySizeAES128 else { return nil }
        let outCapacity = input.count + kCCBlockSizeAES128
        var outBytes = Data(count: outCapacity)
        var outLength: Int = 0
        let status: CCCryptorStatus = outBytes.withUnsafeMutableBytes { outBuf in
            input.withUnsafeBytes { inBuf in
                key16.withUnsafeBytes { keyBuf in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES128),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBuf.baseAddress, kCCKeySizeAES128,
                        nil,
                        inBuf.baseAddress, input.count,
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
    public var primaryBotId: String = "bot_pipi_general"
    public var groupMemberBotIds: [String] = []
    public var typingIndicatorEnabled: Bool = true
    public private(set) var messagesHandledCount: Int = 0
    public private(set) var lastActivityNote: String? = nil

    public let coordinator = PipiWeChatConversationCoordinator()

    private var credentials: PipiWeChatSessionCredentials?
    private var qrPollTask: Task<Void, Never>?
    private var updatesLoopTask: Task<Void, Never>?
    private var syncCursor: String = ""
    private var seenMessageIds: Set<String> = []
    private let secretStore: any PipiSecretStore
    private let session: URLSession
    private let inboundDirectoryURL: URL

    private static let keychainAccountKey = "wechat_ilink_bot_credentials_v1"

    public init(
        secretStore: any PipiSecretStore = PipiKeychainSecretStore(),
        session: URLSession = .shared,
        inboundDirectoryURL: URL? = nil,
        restoreCredentialsOnInit: Bool = true
    ) {
        self.secretStore = secretStore
        self.session = session
        self.inboundDirectoryURL = inboundDirectoryURL ?? PipiPersonalWikiStore.defaultStorageDirectory()
            .appendingPathComponent("wechat-inbound", isDirectory: true)
        if restoreCredentialsOnInit {
            restoreSavedCredentialsIfAvailable()
        }
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

    /// Loads saved iLink credentials off the main thread so startup never deadlocks on Keychain ACL prompts.
    @discardableResult
    public func restoreSavedCredentialsInBackground() async -> Bool {
        if credentials != nil { return true }
        let store = self.secretStore
        let account = Self.keychainAccountKey
        let raw = await Task.detached(priority: .utility) {
            store.secret(for: account)
        }.value
        guard let raw,
              let data = raw.data(using: .utf8),
              let saved = try? JSONDecoder().decode(PipiWeChatSessionCredentials.self, from: data) else {
            return false
        }
        if self.credentials == nil {
            self.credentials = saved
        }
        return true
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

    /// Sends a proactive text notification to the most recent bound WeChat user (if `context_token` was captured).
    @discardableResult
    public func sendProactiveText(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let creds = credentials,
              let toUser = creds.lastFromUserId, !toUser.isEmpty,
              let ctxToken = creds.lastContextToken, !ctxToken.isEmpty else {
            return false
        }
        await sendTextMessage(toUserId: toUser, contextToken: ctxToken, text: trimmed, creds: creds)
        lastActivityNote = "已主动推送微信通知"
        return true
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

        // Remember latest user + context_token so proactive pushes work across turns & restarts
        if var latestCreds = self.credentials,
           (latestCreds.lastFromUserId != inbound.fromUserId || latestCreds.lastContextToken != inbound.contextToken) {
            latestCreds.lastFromUserId = inbound.fromUserId
            latestCreds.lastContextToken = inbound.contextToken
            persistCredentials(latestCreds)
        }

        // Start continuous "typing..." indicator while resolving media/voice/LLM/CLI
        let typingTask: Task<Void, Never>? = typingIndicatorEnabled ? startTypingKeepalive(
            toUserId: inbound.fromUserId,
            contextToken: inbound.contextToken,
            creds: creds
        ) : nil
        defer {
            typingTask?.cancel()
            if typingIndicatorEnabled {
                let uid = inbound.fromUserId
                let ctx = inbound.contextToken
                Task { @MainActor [weak self] in
                    await self?.sendTyping(toUserId: uid, contextToken: ctx, status: 2, creds: creds)
                }
            }
        }

        // 1. Download & decrypt inbound images, files, videos, and resolve voice transcription
        var inboundAttachments: [PipiChatAttachment] = []
        for imgRef in inbound.imageMedias {
            if let downloaded = await downloadAndDecryptCDNMedia(imgRef, fallbackExtension: "jpg") {
                inboundAttachments.append(PipiChatAttachment(
                    name: downloaded.fileName,
                    path: downloaded.filePath,
                    sizeBytes: downloaded.data.count
                ))
            }
        }
        for fileRef in inbound.fileMedias {
            if let downloaded = await downloadAndDecryptCDNMedia(fileRef, fallbackExtension: "bin") {
                let textPreview = Self.extractReadableTextIfSmall(data: downloaded.data, fileName: downloaded.fileName)
                inboundAttachments.append(PipiChatAttachment(
                    name: downloaded.fileName,
                    path: downloaded.filePath,
                    sizeBytes: downloaded.data.count,
                    textContent: textPreview
                ))
            }
        }
        for videoRef in inbound.videoMedias {
            if let downloaded = await downloadAndDecryptCDNMedia(videoRef, fallbackExtension: "mp4") {
                inboundAttachments.append(PipiChatAttachment(
                    name: downloaded.fileName,
                    path: downloaded.filePath,
                    sizeBytes: downloaded.data.count
                ))
            }
        }

        var effectiveText = inbound.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var voiceNotePrefix: String? = nil
        if let vText = inbound.voiceText, !vText.isEmpty {
            voiceNotePrefix = "🎙 语音转文字：\(vText)"
            if effectiveText.isEmpty { effectiveText = vText }
        } else if let vMedia = inbound.voiceMedia {
            lastActivityNote = "正在下载并识别微信语音..."
            if let downloadedVoice = await downloadAndDecryptCDNMedia(vMedia, fallbackExtension: "silk") {
                if let recognized = await bridge.transcribeAudioFile(downloadedVoice.filePath),
                   !recognized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let cleanRecognized = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
                    effectiveText = cleanRecognized
                    voiceNotePrefix = "🎙 语音转文字：\(cleanRecognized)"
                } else {
                    inboundAttachments.append(PipiChatAttachment(
                        name: downloadedVoice.fileName,
                        path: downloadedVoice.filePath,
                        sizeBytes: downloadedVoice.data.count
                    ))
                    if effectiveText.isEmpty {
                        await sendTextMessage(
                            toUserId: inbound.fromUserId,
                            contextToken: inbound.contextToken,
                            text: "收到您的语音消息，但微信未下发语音转文字结果且当前语音编码需要本地转码器。建议在微信语音上长按「转文字」后发送，或在 Mac「设置 → 语音」配置云端识别。",
                            creds: creds
                        )
                        return
                    }
                }
            }
        }

        if effectiveText.isEmpty && !inboundAttachments.isEmpty {
            effectiveText = "请查看并分析我通过微信发来的 \(inboundAttachments.count) 个附件/图片。"
        }

        guard !effectiveText.isEmpty else { return }

        let bots = await bridge.availableBots()
        let botCandidates = bots.map { PipiWeChatBotCandidate(id: $0.id, name: $0.name) }

        // 2. Check active 1v1 conversational wizard or approval state BEFORE normal chat routing
        let userCtx = coordinator.context(for: inbound.fromUserId)
        if inboundAttachments.isEmpty {
            if let handledReply = await handleInteractiveControlFlow(
                text: effectiveText,
                userId: inbound.fromUserId,
                currentWizard: userCtx.wizard,
                bots: bots,
                bridge: bridge,
                creds: creds,
                contextToken: inbound.contextToken
            ) {
                let finalReply = voiceNotePrefix.map { "\($0)\n\n\(handledReply)" } ?? handledReply
                await sendTextMessage(
                    toUserId: inbound.fromUserId,
                    contextToken: inbound.contextToken,
                    text: finalReply,
                    creds: creds
                )
                lastActivityNote = "已完成微信交互引导"
                return
            }
        }

        // 3. Normal or Group Chat execution with full session/project/attachment/approval support
        let route = PipiWeChatILinkProtocol.resolveRoute(
            text: effectiveText,
            mode: routingMode,
            primaryBotId: primaryBotId,
            groupMemberIds: groupMemberBotIds,
            allBots: botCandidates
        )

        lastActivityNote = "正在处理微信消息（\(route.targetBotIds.count) 位智能体）"

        if let voiceNotePrefix {
            await sendTextMessage(
                toUserId: inbound.fromUserId,
                contextToken: inbound.contextToken,
                text: voiceNotePrefix,
                creds: creds
            )
        }

        for targetBotId in route.targetBotIds {
            let ctx = coordinator.context(for: inbound.fromUserId)
            let sessionConvId = (routingMode == .directMainBot && targetBotId == primaryBotId)
                ? (ctx.activeConversationId ?? ctx.activeConversationIdByBot[targetBotId])
                : ctx.activeConversationIdByBot[targetBotId]

            let outcome = await bridge.executeTurn(
                targetBotId,
                sessionConvId,
                ctx.activeProjectId,
                route.cleanedPrompt,
                inboundAttachments,
                inbound.fromUserId
            )

            if let resolvedConv = outcome.resolvedConversationId {
                coordinator.updateContext(for: inbound.fromUserId) { c in
                    c.activeConversationIdByBot[targetBotId] = resolvedConv
                    if self.routingMode == .directMainBot && targetBotId == self.primaryBotId {
                        c.activeConversationId = resolvedConv
                    }
                }
            }

            let reply = outcome.reply
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
            if let approval = reply.pendingApproval {
                coordinator.setPendingApproval(approval, for: inbound.fromUserId)
                await sendTextMessage(
                    toUserId: inbound.fromUserId,
                    contextToken: inbound.contextToken,
                    text: coordinator.renderApprovalPrompt(approval),
                    creds: creds
                )
            }
        }
        lastActivityNote = "最近回复已完成"
    }

    // MARK: - 1v1 Conversational Menus, Wizards & Risk Approval Flow

    private func handleInteractiveControlFlow(
        text rawText: String,
        userId: String,
        currentWizard: PipiWeChatWizardState,
        bots: [PipiWeChatBotInfo],
        bridge: PipiWeChatMessageBridge,
        creds: PipiWeChatSessionCredentials,
        contextToken: String
    ) async -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Explicit cancel exits any active wizard immediately
        if let intent = PipiWeChatIntentParser.parse(trimmed, availableBots: bots), intent == .cancelFlow {
            if currentWizard == .idle { return nil }
            coordinator.updateContext(for: userId) { $0.wizard = .idle }
            return "已取消当前引导流程，恢复正常对话。"
        }

        // First handle active multi-turn wizard states if user is inside one
        switch currentWizard {
        case .idle:
            break

        case .awaitingApproval(let approval):
            let resolvedOptionId: String? = {
                if let idx = PipiWeChatIntentParser.parseIndexSelection(trimmed, maxCount: approval.options.count) {
                    return approval.options[idx].id
                }
                if ["同意", "允许", "批准", "确认", "执行", "yes", "ok", "y", "approve"].contains(lower) {
                    return approval.options.first?.id
                }
                if ["仅本次", "允许一次"].contains(where: { lower.contains($0) }) {
                    return approval.options.first?.id
                }
                if ["本会话", "本次会话"].contains(where: { lower.contains($0) }) {
                    return approval.options.first(where: { $0.id.contains("session") })?.id
                }
                if ["始终", "本项目", "总是"].contains(where: { lower.contains($0) }) {
                    return approval.options.first(where: { $0.id.contains("project") || $0.id.contains("always") })?.id
                }
                if ["拒绝", "取消", "不同意", "不", "no", "deny", "n"].contains(lower) {
                    return approval.options.last?.id
                }
                return nil
            }()
            guard let chosenId = resolvedOptionId else {
                // If user sends a completely unrelated new command, drop wizard or re-prompt
                if PipiWeChatIntentParser.parse(trimmed, availableBots: bots) == nil {
                    return "当前仍有待确认的风险操作：\n\(coordinator.renderApprovalPrompt(approval))"
                }
                coordinator.updateContext(for: userId) { $0.wizard = .idle }
                break
            }
            coordinator.updateContext(for: userId) { $0.wizard = .idle }
            await sendTextMessage(
                toUserId: userId,
                contextToken: contextToken,
                text: "已收到您的确认，正在继续执行...",
                creds: creds
            )
            if let resumedReply = await bridge.resolveApproval(approval.approvalId, chosenId) {
                for artifact in resumedReply.artifacts {
                    await sendMediaArtifact(artifact, toUserId: userId, contextToken: contextToken, creds: creds)
                }
                return resumedReply.text
            }
            return "已处理该操作确认。"

        case .mainMenu:
            if let idx = PipiWeChatIntentParser.parseIndexSelection(trimmed, maxCount: 8) {
                switch idx {
                case 0: return await enterSwitchBotFlow(targetQuery: nil, userId: userId, bots: bots)
                case 1: return enterCreateBotFlow(prefilledName: nil, userId: userId)
                case 2: return await enterSessionFlow(createNew: false, userId: userId, bridge: bridge)
                case 3: return await enterProjectFlow(targetQuery: nil, userId: userId, bridge: bridge)
                case 4: return await enterGroupModeFlow(memberQuery: nil, userId: userId, bots: bots, bridge: bridge)
                case 5: return await enterConfigMenuFlow(userId: userId, bridge: bridge)
                case 6: return await runUpdateCheckFlow(userId: userId, bridge: bridge)
                case 7:
                    coordinator.updateContext(for: userId) { $0.wizard = .idle }
                    return PipiWeChatConversationCoordinator.formatCapabilitiesGuide()
                default: break
                }
            }
            coordinator.updateContext(for: userId) { $0.wizard = .idle }

        case .selectingBot(let botIds):
            let matchedBot: PipiWeChatBotInfo? = {
                if let idx = PipiWeChatIntentParser.parseIndexSelection(trimmed, maxCount: botIds.count) {
                    return bots.first(where: { $0.id == botIds[idx] })
                }
                return bots.first(where: {
                    $0.name.lowercased() == lower || $0.name.lowercased().contains(lower)
                })
            }()
            if let target = matchedBot {
                primaryBotId = target.id
                routingMode = .directMainBot
                await bridge.switchModeFromChat(.directMainBot, nil)
                coordinator.updateContext(for: userId) { ctx in
                    ctx.wizard = .idle
                    ctx.activeConversationId = ctx.activeConversationIdByBot[target.id]
                }
                return "✅ 已将 1v1 对话助手切换为「\(target.name)」（模型：\(target.modelLabel)）。现在可以直接和 TA 对话了！"
            }
            if PipiWeChatIntentParser.parse(trimmed, availableBots: bots) == nil {
                return "未匹配到对应 Bot，请回复 1-\(botIds.count) 的编号或 Bot 名称（回复「取消」退出）。"
            }
            coordinator.updateContext(for: userId) { $0.wizard = .idle }

        case .creatingBotName(let templateIds):
            var chosenName = trimmed
            var chosenTemplateId: String? = nil
            var preRole: String? = nil
            if let idx = PipiWeChatIntentParser.parseIndexSelection(trimmed, maxCount: templateIds.count) {
                let tid = templateIds[idx]
                chosenTemplateId = tid
                if let tpl = PipiBotPersonaTemplate.catalog.first(where: { $0.id == tid }) {
                    chosenName = tpl.nameZh
                    preRole = tpl.taglineZh
                }
            }
            if let preRole, !preRole.isEmpty {
                let choices = await bridge.availableModelChoices()
                coordinator.updateContext(for: userId) {
                    $0.wizard = .creatingBotModel(name: chosenName, role: preRole, templateId: chosenTemplateId, choiceIds: choices.map(\.id))
                }
                return renderModelChoicesPrompt(title: "第 2/3 步：为「\(chosenName)」选择专属模型（默认职责：\(preRole)）", choices: choices)
            } else {
                coordinator.updateContext(for: userId) {
                    $0.wizard = .creatingBotRole(name: chosenName, templateId: chosenTemplateId)
                }
                return "第 2/4 步：请用一句话描述「\(chosenName)」的职责和擅长领域（例如：负责周报整理与英文邮件润色，或回复「默认」跳过）："
            }

        case .creatingBotRole(let name, let templateId):
            let roleText = (trimmed == "默认" || trimmed == "跳过") ? "个人专属智能助手" : trimmed
            let choices = await bridge.availableModelChoices()
            coordinator.updateContext(for: userId) {
                $0.wizard = .creatingBotModel(name: name, role: roleText, templateId: templateId, choiceIds: choices.map(\.id))
            }
            return renderModelChoicesPrompt(title: "第 3/4 步：为「\(name)」指定驱动模型", choices: choices)

        case .creatingBotModel(let name, let role, let templateId, let choiceIds):
            let choices = await bridge.availableModelChoices()
            let selectedChoice: PipiWeChatModelChoice? = {
                if trimmed == "0" || trimmed == "默认" {
                    return choices.first
                }
                if let idx = PipiWeChatIntentParser.parseIndexSelection(trimmed, maxCount: choiceIds.count) {
                    let cid = choiceIds[idx]
                    return choices.first(where: { $0.id == cid })
                }
                return nil
            }()
            let target: PipiExecutionTarget = selectedChoice?.target ?? .auto
            let modelId: String? = selectedChoice?.modelId ?? ((trimmed != "0" && trimmed != "默认" && selectedChoice == nil) ? trimmed : nil)
            coordinator.updateContext(for: userId) {
                $0.wizard = .creatingBotPermission(name: name, role: role, templateId: templateId, target: target, modelId: modelId)
            }
            return """
            第 4/4 步：请设置「\(name)」的风险执行权限（回复 1-3）：
            1. 只读分析（不修改本地文件）
            2. 风险询问（推荐 · 涉及修改或高危操作时先向您确认）
            3. 自动执行（允许直接读写工作区文件与执行命令）
            """

        case .creatingBotPermission(let name, let role, let templateId, let target, let modelId):
            let tier: PipiPermissionTier = {
                switch trimmed {
                case "1", "只读", "只读分析": return .readOnly
                case "3", "自动", "自动执行": return .autoEdit
                default: return .ask
                }
            }()
            coordinator.updateContext(for: userId) { $0.wizard = .idle }
            if let created = await bridge.createBot(name, role, templateId, target, modelId, tier) {
                primaryBotId = created.id
                routingMode = .directMainBot
                await bridge.switchModeFromChat(.directMainBot, nil)
                let newConv = await bridge.createConversation(created.id, coordinator.context(for: userId).activeProjectId, "微信 · \(created.name)")
                coordinator.updateContext(for: userId) { ctx in
                    if let newConv {
                        ctx.activeConversationId = newConv
                        ctx.activeConversationIdByBot[created.id] = newConv
                    }
                }
                return "🎉 已创建新 Bot「\(created.name)」并自动切换为当前 1v1 对话助手！\n• 职责：\(created.role)\n• 模型：\(created.modelLabel)\n• 权限：\(created.permissionTier.label(.zhHans))\n\n现在可以直接给 TA 发消息了！"
            }
            return "创建 Bot 未成功，请稍后重试。"

        case .selectingSession(let sessionIds):
            if trimmed == "0" || trimmed == "新建" || trimmed == "新会话" {
                let projId = coordinator.context(for: userId).activeProjectId
                let createdId = await bridge.createConversation(primaryBotId, projId, nil)
                coordinator.updateContext(for: userId) { ctx in
                    ctx.wizard = .idle
                    if let createdId {
                        ctx.activeConversationId = createdId
                        ctx.activeConversationIdByBot[primaryBotId] = createdId
                    }
                }
                return "🆕 已为您新建空白会话并切换过去，请直接发送消息开始对话。"
            }
            if let idx = PipiWeChatIntentParser.parseIndexSelection(trimmed, maxCount: sessionIds.count) {
                let targetConvId = sessionIds[idx]
                let allConvs = await bridge.availableConversations()
                if let matched = allConvs.first(where: { $0.id == targetConvId }) {
                    primaryBotId = matched.personaId
                    routingMode = .directMainBot
                    await bridge.switchModeFromChat(.directMainBot, nil)
                    coordinator.updateContext(for: userId) { ctx in
                        ctx.wizard = .idle
                        ctx.activeConversationId = matched.id
                        ctx.activeConversationIdByBot[matched.personaId] = matched.id
                        if let pid = matched.projectId {
                            ctx.activeProjectId = pid
                        }
                    }
                    return "✅ 已切换至会话「\(matched.title)」（助手：\(matched.personaName)）。"
                }
            }
            if PipiWeChatIntentParser.parse(trimmed, availableBots: bots) == nil {
                return "请回复「0」新建会话，或回复 1-\(sessionIds.count) 切换历史会话（回复「取消」退出）。"
            }
            coordinator.updateContext(for: userId) { $0.wizard = .idle }

        case .selectingProject(let projectIds):
            if trimmed == "0" || trimmed == "解绑" {
                let activeConv = coordinator.context(for: userId).activeConversationId
                if let activeConv {
                    await bridge.bindConversationProject(activeConv, nil)
                }
                coordinator.updateContext(for: userId) { ctx in
                    ctx.wizard = .idle
                    ctx.activeProjectId = nil
                }
                return "✅ 已取消项目绑定，当前将使用默认工作区。"
            }
            let projects = await bridge.availableProjects()
            let matchedProject: PipiWeChatProjectInfo? = {
                if let idx = PipiWeChatIntentParser.parseIndexSelection(trimmed, maxCount: projectIds.count) {
                    let pid = projectIds[idx]
                    return projects.first(where: { $0.id == pid })
                }
                return projects.first(where: { $0.name.lowercased().contains(lower) })
            }()
            if let proj = matchedProject {
                let activeConv = coordinator.context(for: userId).activeConversationId
                if let activeConv {
                    await bridge.bindConversationProject(activeConv, proj.id)
                }
                coordinator.updateContext(for: userId) { ctx in
                    ctx.wizard = .idle
                    ctx.activeProjectId = proj.id
                }
                let dirHint = proj.workspacePath.map { "\n工作目录：\($0)" } ?? ""
                return "✅ 已切换并绑定到项目「\(proj.name)」！\(dirHint)"
            }
            if PipiWeChatIntentParser.parse(trimmed, availableBots: bots) == nil {
                return "未匹配到项目，请回复编号 0-\(projectIds.count) 或项目名称（回复「取消」退出）。"
            }
            coordinator.updateContext(for: userId) { $0.wizard = .idle }

        case .configuringGroupMembers(let botIds):
            if lower == "完成" || lower == "确认" || lower == "就这样" || lower == "ok" {
                routingMode = .groupPrefixMode
                await bridge.switchModeFromChat(.groupPrefixMode, groupMemberBotIds)
                coordinator.updateContext(for: userId) { $0.wizard = .idle }
                let names = groupMemberBotIds.compactMap { id in bots.first(where: { $0.id == id })?.name }
                return "✅ 已进入群聊模式！当前群成员：\(names.joined(separator: "、"))。\n发送消息时多位助手会依次回复（带【助手名】前缀），也可使用「@助手名 指令」单独点名，随时说「切回1v1」退出群聊。"
            }
            let indices = PipiWeChatIntentParser.parseMultiIndexSelection(trimmed, maxCount: botIds.count)
            if !indices.isEmpty {
                let pickedIds = indices.map { botIds[$0] }
                groupMemberBotIds = pickedIds
                routingMode = .groupPrefixMode
                await bridge.switchModeFromChat(.groupPrefixMode, pickedIds)
                coordinator.updateContext(for: userId) { $0.wizard = .idle }
                let names = pickedIds.compactMap { id in bots.first(where: { $0.id == id })?.name }
                return "✅ 已开启群聊模式！参与成员已更新为：\(names.joined(separator: "、"))。\n现在直接发消息即可多助手协同（支持 @助手名 或 @全体），随时说「切回1v1」退出。"
            }
            if PipiWeChatIntentParser.parse(trimmed, availableBots: bots) == nil {
                return "请回复要拉入群聊的 Bot 编号（如「1,2」或「全部」），或回复「确认」使用默认成员。"
            }
            coordinator.updateContext(for: userId) { $0.wizard = .idle }

        case .configMenu:
            if let idx = PipiWeChatIntentParser.parseIndexSelection(trimmed, maxCount: 7) {
                switch idx {
                case 0:
                    let choices = await bridge.availableModelChoices()
                    coordinator.updateContext(for: userId) {
                        $0.wizard = .configSelectingBotModel(botId: primaryBotId, choiceIds: choices.map(\.id))
                    }
                    let botName = bots.first(where: { $0.id == primaryBotId })?.name ?? "当前助手"
                    return renderModelChoicesPrompt(title: "请为「\(botName)」选择模型（或输入自定义模型 ID）", choices: choices)
                case 1:
                    coordinator.updateContext(for: userId) {
                        $0.wizard = .configSelectingBotPermission(botId: primaryBotId)
                    }
                    return """
                    请为当前 Bot 选择风险执行权限（回复 1-3）：
                    1. 只读分析
                    2. 风险询问（推荐）
                    3. 自动执行
                    """
                case 2:
                    coordinator.updateContext(for: userId) { $0.wizard = .idle }
                    return await bridge.toggleSetting("llm_judge")
                case 3:
                    coordinator.updateContext(for: userId) { $0.wizard = .idle }
                    return await bridge.toggleSetting("proactive_cli")
                case 4:
                    typingIndicatorEnabled.toggle()
                    coordinator.updateContext(for: userId) { $0.wizard = .idle }
                    return "✅ 微信「正在输入」状态已\(typingIndicatorEnabled ? "开启" : "关闭")。"
                case 5:
                    coordinator.updateContext(for: userId) { $0.wizard = .idle }
                    return await bridge.toggleSetting("memory")
                case 6:
                    return await enterProjectFlow(targetQuery: nil, userId: userId, bridge: bridge)
                default: break
                }
            }
            coordinator.updateContext(for: userId) { $0.wizard = .idle }

        case .configSelectingBotModel(let botId, let choiceIds):
            let choices = await bridge.availableModelChoices()
            coordinator.updateContext(for: userId) { $0.wizard = .idle }
            if trimmed == "0" || trimmed == "恢复默认" || trimmed == "默认" {
                return await bridge.updateBotConfig(botId, .auto, nil, true, nil)
            }
            if let idx = PipiWeChatIntentParser.parseIndexSelection(trimmed, maxCount: choiceIds.count) {
                let cid = choiceIds[idx]
                if let picked = choices.first(where: { $0.id == cid }) {
                    return await bridge.updateBotConfig(botId, picked.target, picked.modelId, picked.modelId == nil && picked.target == .auto, nil)
                }
            }
            // Treat arbitrary non-menu text as custom modelId on current provider
            if PipiWeChatIntentParser.parse(trimmed, availableBots: bots) == nil {
                return await bridge.updateBotConfig(botId, nil, trimmed, false, nil)
            }

        case .configSelectingBotPermission(let botId):
            coordinator.updateContext(for: userId) { $0.wizard = .idle }
            let tier: PipiPermissionTier = {
                switch trimmed {
                case "1", "只读", "只读分析": return .readOnly
                case "3", "自动", "自动执行": return .autoEdit
                default: return .ask
                }
            }()
            return await bridge.updateBotConfig(botId, nil, nil, false, tier)

        case .awaitingUpdateConfirm(let release):
            coordinator.updateContext(for: userId) { $0.wizard = .idle }
            if ["1", "更新", "立即更新", "确认", "安装", "升级", "yes", "ok", "y"].contains(lower) {
                return await bridge.installUpdate(release)
            }
            if PipiWeChatIntentParser.parse(trimmed, availableBots: bots) == nil {
                return "已暂缓安装更新，您可以随时发送「检查更新」再次触发。"
            }
        }

        // 2. Check fresh natural-language intents
        guard let intent = PipiWeChatIntentParser.parse(trimmed, availableBots: bots) else {
            return nil
        }

        switch intent {
        case .showMenu:
            let ctx = coordinator.context(for: userId)
            let snap = await bridge.fetchConfigSnapshot(primaryBotId, routingMode, typingIndicatorEnabled, ctx.activeConversationId, ctx.activeProjectId)
            coordinator.updateContext(for: userId) { $0.wizard = .mainMenu }
            return coordinator.renderMainMenu(config: snap)

        case .switchBot(let targetQuery):
            return await enterSwitchBotFlow(targetQuery: targetQuery, userId: userId, bots: bots, bridge: bridge)

        case .createBot(let prefilledName, _):
            return enterCreateBotFlow(prefilledName: prefilledName, userId: userId)

        case .manageSessions(let createNew):
            return await enterSessionFlow(createNew: createNew, userId: userId, bridge: bridge)

        case .switchProject(let targetQuery):
            return await enterProjectFlow(targetQuery: targetQuery, userId: userId, bridge: bridge)

        case .enterGroupMode(let memberQuery):
            return await enterGroupModeFlow(memberQuery: memberQuery, userId: userId, bots: bots, bridge: bridge)

        case .exitGroupMode:
            routingMode = .directMainBot
            await bridge.switchModeFromChat(.directMainBot, nil)
            coordinator.updateContext(for: userId) { $0.wizard = .idle }
            let primaryName = bots.first(where: { $0.id == primaryBotId })?.name ?? "主助手"
            return "✅ 已切回「1v1 主智能体模式」，当前对话助手：\(primaryName)。"

        case .showConfig:
            return await enterConfigMenuFlow(userId: userId, bridge: bridge)

        case .checkUpdate:
            return await runUpdateCheckFlow(userId: userId, bridge: bridge)

        case .confirmInstallUpdate:
            return nil

        case .cancelFlow:
            coordinator.updateContext(for: userId) { $0.wizard = .idle }
            return "当前没有进行中的引导流程。"
        }
    }

    private func enterSwitchBotFlow(
        targetQuery: String?,
        userId: String,
        bots: [PipiWeChatBotInfo],
        bridge: PipiWeChatMessageBridge? = nil
    ) async -> String {
        if let query = targetQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            if let matched = bots.first(where: {
                $0.name.lowercased() == query.lowercased() || $0.name.lowercased().contains(query.lowercased())
            }) {
                primaryBotId = matched.id
                routingMode = .directMainBot
                if let bridge {
                    await bridge.switchModeFromChat(.directMainBot, nil)
                }
                coordinator.updateContext(for: userId) { ctx in
                    ctx.wizard = .idle
                    ctx.activeConversationId = ctx.activeConversationIdByBot[matched.id]
                }
                return "✅ 已切换至「\(matched.name)」（模型：\(matched.modelLabel)）。现在可以直接对话了！"
            }
        }
        coordinator.updateContext(for: userId) { $0.wizard = .selectingBot(botIds: bots.map(\.id)) }
        return coordinator.renderBotPicker(bots: bots, primaryBotId: primaryBotId)
    }

    private func enterCreateBotFlow(prefilledName: String?, userId: String) -> String {
        let templates = Array(PipiBotPersonaTemplate.catalog.prefix(7))
        if let name = prefilledName, !name.isEmpty {
            coordinator.updateContext(for: userId) {
                $0.wizard = .creatingBotRole(name: name, templateId: "tpl_custom")
            }
            return "好的，我们来创建新 Bot「\(name)」！\n第 2/4 步：请用一句话描述它的职责或系统指令（或回复「默认」）："
        }
        coordinator.updateContext(for: userId) {
            $0.wizard = .creatingBotName(templateIds: templates.map(\.id))
        }
        var lines = ["✨ 创建新 Bot（引导式 4 步）：", "请直接输入新 Bot 的名称（如「架构师」），或回复编号快速选用角色模板："]
        for (idx, tpl) in templates.enumerated() {
            lines.append("\(idx + 1). \(tpl.nameZh) — \(tpl.taglineZh)")
        }
        lines.append("\n回复「取消」退出创建。")
        return lines.joined(separator: "\n")
    }

    private func enterSessionFlow(createNew: Bool, userId: String, bridge: PipiWeChatMessageBridge) async -> String {
        if createNew {
            let projId = coordinator.context(for: userId).activeProjectId
            let createdId = await bridge.createConversation(primaryBotId, projId, nil)
            coordinator.updateContext(for: userId) { ctx in
                ctx.wizard = .idle
                if let createdId {
                    ctx.activeConversationId = createdId
                    ctx.activeConversationIdByBot[primaryBotId] = createdId
                }
            }
            return "🆕 已开启全新会话！请直接发送内容开始新的上下文。"
        }
        let convs = await bridge.availableConversations()
        let listed = Array(convs.prefix(12))
        coordinator.updateContext(for: userId) {
            $0.wizard = .selectingSession(sessionIds: listed.map(\.id))
        }
        return coordinator.renderSessionPicker(conversations: listed, currentId: coordinator.context(for: userId).activeConversationId)
    }

    private func enterProjectFlow(targetQuery: String?, userId: String, bridge: PipiWeChatMessageBridge) async -> String {
        let projects = await bridge.availableProjects()
        if let query = targetQuery?.lowercased() {
            if let matched = projects.first(where: { query.contains($0.name.lowercased()) }) {
                if let activeConv = coordinator.context(for: userId).activeConversationId {
                    await bridge.bindConversationProject(activeConv, matched.id)
                }
                coordinator.updateContext(for: userId) { ctx in
                    ctx.wizard = .idle
                    ctx.activeProjectId = matched.id
                }
                return "✅ 已绑定到项目「\(matched.name)」！"
            }
        }
        coordinator.updateContext(for: userId) {
            $0.wizard = .selectingProject(projectIds: projects.map(\.id))
        }
        return coordinator.renderProjectPicker(projects: projects, currentId: coordinator.context(for: userId).activeProjectId)
    }

    private func enterGroupModeFlow(
        memberQuery: String?,
        userId: String,
        bots: [PipiWeChatBotInfo],
        bridge: PipiWeChatMessageBridge
    ) async -> String {
        // Check if user named specific bots in the prompt (e.g. "拉 PiPi 和 Coder 进群聊")
        if let q = memberQuery?.lowercased() {
            let named = bots.filter { bot in
                let short = (bot.name.split(separator: "·").first.map(String.init) ?? bot.name).trimmingCharacters(in: .whitespaces).lowercased()
                return q.contains(bot.name.lowercased()) || (!short.isEmpty && q.contains(short))
            }
            if named.count >= 2 {
                let ids = named.map(\.id)
                groupMemberBotIds = ids
                routingMode = .groupPrefixMode
                await bridge.switchModeFromChat(.groupPrefixMode, ids)
                coordinator.updateContext(for: userId) { $0.wizard = .idle }
                return "✅ 已进入群聊模式！成员：\(named.map(\.name).joined(separator: "、"))。\n每条回复将带【助手名称】前缀，也支持「@助手名」或「@全体」。随时说「切回1v1」退出。"
            }
        }

        coordinator.updateContext(for: userId) {
            $0.wizard = .configuringGroupMembers(botIds: bots.map(\.id))
        }
        var lines = ["👥 进入群聊模式 — 请选择参与讨论的 Bot（回复编号如 `1,2`，或回复 `全部` / `确认`）："]
        let effectiveCurrent = Set(PipiWeChatILinkProtocol.effectiveGroupRoster(
            primaryBotId: primaryBotId,
            groupMemberIds: groupMemberBotIds,
            allBots: bots.map { PipiWeChatBotCandidate(id: $0.id, name: $0.name) }
        ))
        for (idx, bot) in bots.enumerated() {
            let mark = effectiveCurrent.contains(bot.id) ? " [默认已选]" : ""
            lines.append("\(idx + 1). \(bot.name)\(mark)")
        }
        lines.append("\n回复「取消」保持当前模式。")
        return lines.joined(separator: "\n")
    }

    private func enterConfigMenuFlow(userId: String, bridge: PipiWeChatMessageBridge) async -> String {
        let ctx = coordinator.context(for: userId)
        let snap = await bridge.fetchConfigSnapshot(primaryBotId, routingMode, typingIndicatorEnabled, ctx.activeConversationId, ctx.activeProjectId)
        coordinator.updateContext(for: userId) { $0.wizard = .configMenu }
        return coordinator.renderConfigMenu(config: snap)
    }

    private func runUpdateCheckFlow(userId: String, bridge: PipiWeChatMessageBridge) async -> String {
        let res = await bridge.checkForUpdates()
        if let release = res.release {
            coordinator.updateContext(for: userId) { $0.wizard = .awaitingUpdateConfirm(release: release) }
            return "\(res.message)\n\n回复「1」或「立即更新」即可在 Mac 端自动下载校验并安装重启。"
        }
        coordinator.updateContext(for: userId) { $0.wizard = .idle }
        return res.message
    }

    private func renderModelChoicesPrompt(title: String, choices: [PipiWeChatModelChoice]) -> String {
        var lines = ["🧠 \(title)："]
        for (idx, ch) in choices.enumerated() {
            lines.append("\(idx + 1). \(ch.label)")
        }
        lines.append("\n回复编号（1-\(choices.count)），或直接输入自定义模型 ID（回复「0」恢复默认）。")
        return lines.joined(separator: "\n")
    }

    // MARK: - Typing Keepalive & CDN Media Download / Decrypt

    private func startTypingKeepalive(
        toUserId: String,
        contextToken: String,
        creds: PipiWeChatSessionCredentials
    ) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.sendTyping(toUserId: toUserId, contextToken: contextToken, status: 1, creds: creds)
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }

    private func downloadAndDecryptCDNMedia(
        _ ref: PipiWeChatInboundMediaRef,
        fallbackExtension: String
    ) async -> (filePath: String, fileName: String, data: Data)? {
        let targetURL: URL? = {
            if !ref.encryptQueryParam.isEmpty {
                let enc = ref.encryptQueryParam.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ref.encryptQueryParam
                return URL(string: "\(PipiWeChatILinkProtocol.defaultCdnBaseURL)/download?encrypted_query_param=\(enc)")
            }
            if let direct = ref.directURL, !direct.isEmpty {
                return URL(string: direct)
            }
            return nil
        }()
        guard let url = targetURL else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 45

        guard let (rawData, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              !rawData.isEmpty else {
            return nil
        }

        let finalData: Data
        if let aesKey = PipiWeChatILinkProtocol.decodeILinkAESKey(ref.aesKeyRaw) {
            finalData = PipiWeChatILinkProtocol.aes128ECBDecrypt(rawData, key16: aesKey) ?? rawData
        } else {
            finalData = rawData
        }

        try? FileManager.default.createDirectory(at: inboundDirectoryURL, withIntermediateDirectories: true)
        let rawName = (ref.fileName ?? "wechat_\(UUID().uuidString.prefix(8)).\(fallbackExtension)")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "_")
        let safeName = "\(Int(Date().timeIntervalSince1970))_\(rawName)"
        let destURL = inboundDirectoryURL.appendingPathComponent(safeName)
        do {
            try finalData.write(to: destURL, options: .atomic)
            return (destURL.path, rawName, finalData)
        } catch {
            return nil
        }
    }

    private static func extractReadableTextIfSmall(data: Data, fileName: String) -> String? {
        guard data.count <= 65_536 else { return nil }
        let ext = (fileName as NSString).pathExtension.lowercased()
        let textExts: Set<String> = ["txt", "md", "markdown", "json", "yaml", "yml", "csv", "ts", "js", "swift", "py", "sh", "log", "xml", "html", "css", "sql", "toml"]
        guard textExts.contains(ext) || ext.isEmpty else { return nil }
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Outbound Transport (sendtyping / sendmessage / getuploadurl / CDN)

    private func sendTyping(
        toUserId: String,
        contextToken: String,
        status: Int = 1,
        creds: PipiWeChatSessionCredentials
    ) async {
        let cleanBase = creds.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanBase)/ilink/bot/sendtyping") else { return }
        let payload: [String: Any] = [
            "ilink_user_id": toUserId,
            "context_token": contextToken,
            "status": status,
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
