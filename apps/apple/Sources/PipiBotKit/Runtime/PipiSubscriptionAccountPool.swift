// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
//
// Brigade Multi-Account Subscription & API Pool + 24/7 Cloud Teammate Runtime Models:
// - Reuses existing paid Claude (Pro/Max via `claude` CLI) & ChatGPT (Plus/Pro via `codex` CLI)
//   subscriptions with isolated `CLAUDE_CONFIG_DIR` / `CODEX_HOME` profiles.
// - Also supports stacking multiple accounts/keys for Mainland China model providers
//   (DeepSeek, Kimi, Zhipu GLM, Qwen, MiniMax, Doubao/Volcengine Ark, SiliconFlow)
//   and third-party OpenAI-compatible relays with automatic 429/402/quota failover.

import Foundation

// MARK: - 1. Stacked Subscription & API Account Record

public struct PipiSubscriptionAccountRecord: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public var label: String
    public var provider: PipiSubscriptionProviderKind
    public var planTier: String
    public var emailHint: String?
    public var profileDir: String?
    public var useSystemDefaultProfile: Bool
    /// For Mainland China & third-party OpenAI-compatible stacked accounts/keys
    public var baseURL: String?
    public var modelId: String?
    /// Keychain account key inside `PipiSecretStore` (raw `apiKey` is never serialized to JSON)
    public var keychainRef: String?
    /// Runtime-only in-memory API key hydrated from Keychain; excluded from `CodingKeys`
    public var apiKey: String
    public var priority: Int
    public var status: PipiSubscriptionAccountStatus
    public var cooldownUntil: String?
    public var rateLimitReason: String?
    public var requestsCount: Int
    public var estimatedTokensUsed: Int
    public var failoverCount: Int
    public var lastUsedAt: String?
    public let createdAt: String
    public var updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, label, provider, planTier, emailHint, profileDir, useSystemDefaultProfile
        case baseURL, modelId, keychainRef
        case priority, status, cooldownUntil, rateLimitReason
        case requestsCount, estimatedTokensUsed, failoverCount, lastUsedAt, createdAt, updatedAt
    }

    public init(
        id: String = "sub_\(UUID().uuidString.prefix(8).lowercased())",
        label: String,
        provider: PipiSubscriptionProviderKind,
        planTier: String? = nil,
        emailHint: String? = nil,
        profileDir: String? = nil,
        useSystemDefaultProfile: Bool = false,
        baseURL: String? = nil,
        modelId: String? = nil,
        keychainRef: String? = nil,
        apiKey: String = "",
        priority: Int = 1,
        status: PipiSubscriptionAccountStatus = .ready,
        cooldownUntil: String? = nil,
        rateLimitReason: String? = nil,
        requestsCount: Int = 0,
        estimatedTokensUsed: Int = 0,
        failoverCount: Int = 0,
        lastUsedAt: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.label = label
        self.provider = provider
        self.planTier = planTier ?? Self.defaultPlanTier(for: provider)
        self.emailHint = emailHint?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.profileDir = (provider.isOpenAICompatibleApiPool || useSystemDefaultProfile) ? nil : profileDir
        self.useSystemDefaultProfile = provider.isOpenAICompatibleApiPool ? false : useSystemDefaultProfile
        self.baseURL = provider.isOpenAICompatibleApiPool
            ? (baseURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? provider.defaultBaseURL)
            : nil
        self.modelId = modelId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? provider.defaultModelId
        self.keychainRef = keychainRef ?? "subpool_\(id)"
        self.apiKey = apiKey
        self.priority = priority
        self.status = status
        self.cooldownUntil = cooldownUntil
        self.rateLimitReason = rateLimitReason
        self.requestsCount = requestsCount
        self.estimatedTokensUsed = estimatedTokensUsed
        self.failoverCount = failoverCount
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedId = try c.decode(String.self, forKey: .id)
        let decodedProvider = try c.decode(PipiSubscriptionProviderKind.self, forKey: .provider)
        self.id = decodedId
        self.label = try c.decodeIfPresent(String.self, forKey: .label) ?? decodedProvider.displayName
        self.provider = decodedProvider
        self.planTier = try c.decodeIfPresent(String.self, forKey: .planTier) ?? Self.defaultPlanTier(for: decodedProvider)
        self.emailHint = try c.decodeIfPresent(String.self, forKey: .emailHint)
        self.profileDir = try c.decodeIfPresent(String.self, forKey: .profileDir)
        self.useSystemDefaultProfile = try c.decodeIfPresent(Bool.self, forKey: .useSystemDefaultProfile) ?? false
        self.baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? decodedProvider.defaultBaseURL
        self.modelId = try c.decodeIfPresent(String.self, forKey: .modelId) ?? decodedProvider.defaultModelId
        self.keychainRef = try c.decodeIfPresent(String.self, forKey: .keychainRef) ?? "subpool_\(decodedId)"
        self.apiKey = ""
        self.priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 1
        self.status = try c.decodeIfPresent(PipiSubscriptionAccountStatus.self, forKey: .status) ?? .ready
        self.cooldownUntil = try c.decodeIfPresent(String.self, forKey: .cooldownUntil)
        self.rateLimitReason = try c.decodeIfPresent(String.self, forKey: .rateLimitReason)
        self.requestsCount = try c.decodeIfPresent(Int.self, forKey: .requestsCount) ?? 0
        self.estimatedTokensUsed = try c.decodeIfPresent(Int.self, forKey: .estimatedTokensUsed) ?? 0
        self.failoverCount = try c.decodeIfPresent(Int.self, forKey: .failoverCount) ?? 0
        self.lastUsedAt = try c.decodeIfPresent(String.self, forKey: .lastUsedAt)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ISO8601DateFormatter().string(from: Date())
        self.updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? self.createdAt
    }

    public var secretAccountKey: String {
        let trimmed = (keychainRef ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "subpool_\(id)" : trimmed
    }

    public var isCurrentlyCoolingDown: Bool {
        guard status == .rateLimited, let untilStr = cooldownUntil,
              let untilDate = ISO8601DateFormatter().date(from: untilStr) else {
            return status == .rateLimited
        }
        return untilDate > Date()
    }

    private static func defaultPlanTier(for provider: PipiSubscriptionProviderKind) -> String {
        switch provider {
        case .claudeSubscription: return "Claude Pro/Max"
        case .chatgptSubscription: return "ChatGPT Plus/Pro"
        case .geminiSubscription: return "Gemini CLI"
        case .openaiCompatible: return "OpenAI Compatible"
        default: return "\(provider.displayName) API"
        }
    }
}

// MARK: - 2. Per-Teammate Isolated Browser & 24/7 Cloud Config (Mainland China + Global)

public struct PipiTeammateBrowserConfig: Codable, Equatable, Hashable, Sendable {
    public var enabled: Bool
    public var platforms: [String]
    public var proxyURL: String?
    public var remoteCDPEndpoint: String?
    public var requireApprovalBeforePost: Bool

    public init(
        enabled: Bool = false,
        platforms: [String] = ["xiaohongshu", "wechat_mp", "x", "linkedin", "reddit"],
        proxyURL: String? = nil,
        remoteCDPEndpoint: String? = nil,
        requireApprovalBeforePost: Bool = true
    ) {
        self.enabled = enabled
        self.platforms = platforms
        self.proxyURL = proxyURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.remoteCDPEndpoint = remoteCDPEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.requireApprovalBeforePost = requireApprovalBeforePost
    }

    public static let `default` = PipiTeammateBrowserConfig()

    public static let mainlandChinaPlatforms: [String] = [
        "xiaohongshu", "wechat_mp", "douyin", "weibo", "zhihu", "bilibili", "jike"
    ]

    public static let globalPlatforms: [String] = [
        "x", "linkedin", "reddit", "github", "gmail"
    ]

    public static let allSupportedPlatforms: [String] = mainlandChinaPlatforms + globalPlatforms

    public static func platformDisplayName(_ slug: String, lang: PipiResolvedLanguage = .zhHans) -> String {
        switch slug.lowercased() {
        case "xiaohongshu", "xhs": return lang == .zhHans ? "小红书" : "Xiaohongshu"
        case "wechat_mp", "weixin_mp": return lang == .zhHans ? "微信公众号" : "WeChat MP"
        case "douyin": return lang == .zhHans ? "抖音" : "Douyin"
        case "weibo": return lang == .zhHans ? "微博" : "Weibo"
        case "zhihu": return lang == .zhHans ? "知乎" : "Zhihu"
        case "bilibili", "bili": return lang == .zhHans ? "B站" : "Bilibili"
        case "jike": return lang == .zhHans ? "即刻" : "Jike"
        case "x", "twitter": return "X"
        case "linkedin": return "LinkedIn"
        case "reddit": return "Reddit"
        case "github": return "GitHub"
        case "gmail": return "Gmail"
        default: return slug
        }
    }

    public static func platformLoginURL(_ slug: String) -> String {
        switch slug.lowercased() {
        case "xiaohongshu", "xhs": return "https://creator.xiaohongshu.com/login"
        case "wechat_mp", "weixin_mp": return "https://mp.weixin.qq.com/"
        case "douyin": return "https://creator.douyin.com/"
        case "weibo": return "https://weibo.com/login.php"
        case "zhihu": return "https://www.zhihu.com/signin"
        case "bilibili", "bili": return "https://passport.bilibili.com/login"
        case "jike": return "https://web.okjike.com/"
        case "x", "twitter": return "https://x.com/i/flow/login"
        case "linkedin": return "https://www.linkedin.com/login"
        case "reddit": return "https://www.reddit.com/login"
        case "github": return "https://github.com/login"
        case "gmail": return "https://mail.google.com"
        default: return "https://www.xiaohongshu.com/"
        }
    }
}

public struct PipiCloudBrigadeConfig: Codable, Equatable, Sendable {
    public var cloudHostURL: String
    public var cloudHubToken: String
    public var autoSyncEnabled: Bool
    public var lastSyncAt: String?
    public var lastHealthSummary: String?
    public var isCloudReachable: Bool

    public init(
        cloudHostURL: String = "http://127.0.0.1:4242",
        cloudHubToken: String = "",
        autoSyncEnabled: Bool = false,
        lastSyncAt: String? = nil,
        lastHealthSummary: String? = nil,
        isCloudReachable: Bool = false
    ) {
        self.cloudHostURL = cloudHostURL
        self.cloudHubToken = cloudHubToken
        self.autoSyncEnabled = autoSyncEnabled
        self.lastSyncAt = lastSyncAt
        self.lastHealthSummary = lastHealthSummary
        self.isCloudReachable = isCloudReachable
    }

    public static let `default` = PipiCloudBrigadeConfig()
}

// MARK: - 3. Pure Subscription & API Account Pool Engine (Stacking + Auto-Failover)

public struct PipiSubscriptionErrorClassification: Equatable, Sendable {
    public let isRateLimited: Bool
    public let isAuthExpired: Bool
    public let cooldownSeconds: TimeInterval
    public let reason: String?

    public init(isRateLimited: Bool, isAuthExpired: Bool, cooldownSeconds: TimeInterval, reason: String? = nil) {
        self.isRateLimited = isRateLimited
        self.isAuthExpired = isAuthExpired
        self.cooldownSeconds = cooldownSeconds
        self.reason = reason
    }
}

public enum PipiSubscriptionAccountPoolEngine {
    public static let defaultCooldownSeconds: TimeInterval = 15 * 60
    public static let maxCooldownSeconds: TimeInterval = 6 * 60 * 60

    public static func defaultProfileDirectory(provider: PipiSubscriptionProviderKind, accountId: String) -> String {
        let slug = provider.rawValue.replacingOccurrences(of: "_subscription", with: "")
        let safeId = accountId.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
        #if os(macOS)
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pipibot/subscriptions/\(slug)/\(safeId)", isDirectory: true)
        return base.path
        #else
        return NSTemporaryDirectory() + "pipibot-sub-\(slug)-\(safeId)"
        #endif
    }

    public static func defaultBrowserProfileDirectory(botId: String) -> URL {
        let safeId = botId.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
        #if os(macOS)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".pipibot", isDirectory: true)
        return appSupport
            .appendingPathComponent("PiPiBot/browser-profiles/\(safeId)", isDirectory: true)
        #else
        return FileManager.default.temporaryDirectory.appendingPathComponent("pipibot-browser-\(safeId)", isDirectory: true)
        #endif
    }

    public static func classifyError(_ rawError: String) -> PipiSubscriptionErrorClassification {
        let trimmed = rawError.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        let authMarkers = [
            "401", "unauthorized", "invalid_api_key", "invalid api key", "authentication_error",
            "not logged in", "please log in", "authentication required",
            "session expired", "token expired", "invalid_grant", "login required",
            "鉴权失败", "密钥无效"
        ]
        if authMarkers.contains(where: { lower.contains($0) }) {
            return PipiSubscriptionErrorClassification(
                isRateLimited: false,
                isAuthExpired: true,
                cooldownSeconds: 0,
                reason: String(trimmed.prefix(200))
            )
        }

        let limitMarkers = [
            "429", "529", "402", "rate limit", "rate_limit", "rate-limit",
            "usage limit", "usage_limit", "quota exceeded", "quota_exceeded",
            "insufficient_quota", "insufficient_balance", "too many requests",
            "overloaded", "hit your limit", "cap reached", "limit reached",
            "try again in", "resets in", "tpm", "rpm", "qps",
            "余额不足", "额度已用尽", "额度不足", "请求过于频繁", "并发超限", "触发限流"
        ]
        guard limitMarkers.contains(where: { lower.contains($0) }) else {
            return PipiSubscriptionErrorClassification(isRateLimited: false, isAuthExpired: false, cooldownSeconds: 0)
        }

        var cooldown = defaultCooldownSeconds
        if let hours = extractDurationNumber(in: lower, units: ["hours", "hour", "hrs", "hr", "h"]) {
            cooldown = TimeInterval(hours * 3600)
        } else if let mins = extractDurationNumber(in: lower, units: ["minutes", "minute", "mins", "min", "m"]) {
            cooldown = TimeInterval(mins * 60)
        } else if let secs = extractDurationNumber(in: lower, units: ["seconds", "second", "secs", "sec", "s"]) {
            cooldown = max(30, TimeInterval(secs))
        }
        cooldown = max(30, min(maxCooldownSeconds, cooldown))

        return PipiSubscriptionErrorClassification(
            isRateLimited: true,
            isAuthExpired: false,
            cooldownSeconds: cooldown,
            reason: String(trimmed.prefix(200))
        )
    }

    private static func extractDurationNumber(in lower: String, units: [String]) -> Int? {
        for unit in units {
            let pattern = "(?:try again|resets?|wait|retry)\\s+(?:in\\s+)?(\\d+)\\s*\(unit)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               match.numberOfRanges >= 2,
               let range = Range(match.range(at: 1), in: lower),
               let num = Int(lower[range]) {
                return num
            }
        }
        return nil
    }

    /// Builds environment overrides so the official `claude` / `codex` / `gemini` CLI
    /// authenticates with this stacked subscription account's isolated directory instead of pay-as-you-go API keys.
    public static func cliEnvironment(for account: PipiSubscriptionAccountRecord) -> [String: String] {
        var env: [String: String] = [:]
        switch account.provider {
        case .claudeSubscription:
            env["ANTHROPIC_API_KEY"] = ""
            env["ANTHROPIC_AUTH_TOKEN"] = ""
        case .chatgptSubscription:
            env["OPENAI_API_KEY"] = ""
        case .geminiSubscription:
            env["GEMINI_API_KEY"] = ""
            env["GOOGLE_API_KEY"] = ""
        default:
            if let url = account.baseURL, !url.isEmpty {
                env["OPENAI_BASE_URL"] = url
            }
            return env
        }
        if !account.useSystemDefaultProfile, let dir = account.profileDir, !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            env[account.provider.configDirEnvKey] = dir
        }
        return env
    }

    /// Builds a live `PipiLLMProviderConfig` from a Mainland China or third-party OpenAI-compatible stacked pool account.
    public static func buildLLMProviderConfig(
        from account: PipiSubscriptionAccountRecord,
        modelOverride: String? = nil,
        apiKeyOverride: String? = nil
    ) -> PipiLLMProviderConfig {
        let resolvedBase = account.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? account.provider.defaultBaseURL
            ?? "https://api.openai.com/v1"
        let resolvedModel = modelOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? account.modelId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? account.provider.defaultModelId
        let resolvedKey = (apiKeyOverride ?? account.apiKey).trimmingCharacters(in: .whitespacesAndNewlines)

        return PipiLLMProviderConfig(
            id: "pool_\(account.id)",
            name: "\(account.provider.displayName) · \(account.label)",
            kind: account.provider.mappedLLMProviderKind,
            baseURL: resolvedBase,
            apiKey: resolvedKey,
            modelId: resolvedModel,
            isEnabled: account.status != .disabled,
            keychainRef: account.secretAccountKey
        )
    }

    public static func interactiveLoginCommand(for account: PipiSubscriptionAccountRecord) -> String {
        if account.provider.isOpenAICompatibleApiPool {
            let envName = "\(account.provider.rawValue.uppercased())_API_KEY"
            let url = account.baseURL ?? account.provider.defaultBaseURL ?? ""
            return "export \(envName)='<api-key>' # \(url)"
        }
        let bin = account.provider.cliBinaryName
        let sub = account.provider == .chatgptSubscription ? "login" : "/login"
        if account.useSystemDefaultProfile || (account.profileDir ?? "").isEmpty {
            return "\(bin) \(sub)"
        }
        let dir = (account.profileDir ?? "").replacingOccurrences(of: "'", with: "'\\''")
        return "\(account.provider.configDirEnvKey)='\(dir)' \(bin) \(sub)"
    }

    public static func recoverExpiredCooldowns(
        in accounts: inout [PipiSubscriptionAccountRecord],
        now: Date = Date()
    ) -> Int {
        let iso = ISO8601DateFormatter()
        let nowIso = iso.string(from: now)
        var recovered = 0
        for idx in accounts.indices {
            if accounts[idx].status == .rateLimited,
               let untilStr = accounts[idx].cooldownUntil,
               let untilDate = iso.date(from: untilStr),
               now >= untilDate {
                accounts[idx].status = .ready
                accounts[idx].cooldownUntil = nil
                accounts[idx].rateLimitReason = nil
                accounts[idx].updatedAt = nowIso
                recovered += 1
            }
        }
        return recovered
    }

    public static func selectAccount(
        provider: PipiSubscriptionProviderKind,
        strategy: PipiSubscriptionPoolStrategy,
        accounts: [PipiSubscriptionAccountRecord],
        preferredAccountId: String? = nil,
        excludeIds: Set<String> = [],
        roundRobinCursor: Int = 0,
        now: Date = Date()
    ) -> (account: PipiSubscriptionAccountRecord, nextCursor: Int)? {
        var mutable = accounts
        _ = recoverExpiredCooldowns(in: &mutable, now: now)

        let candidates = mutable
            .filter { $0.provider == provider && !excludeIds.contains($0.id) && ($0.status == .ready || $0.status == .active) }
            .sorted {
                if $0.priority != $1.priority { return $0.priority < $1.priority }
                return $0.createdAt < $1.createdAt
            }

        guard !candidates.isEmpty else { return nil }

        if let preferredAccountId,
           let pinned = candidates.first(where: { $0.id == preferredAccountId }) {
            return (pinned, roundRobinCursor)
        }

        switch strategy {
        case .priorityFailover:
            return (candidates[0], roundRobinCursor)
        case .roundRobin:
            let idx = abs(roundRobinCursor) % candidates.count
            return (candidates[idx], (idx + 1) % candidates.count)
        case .leastUsed:
            let picked = candidates.min { lhs, rhs in
                if lhs.requestsCount != rhs.requestsCount { return lhs.requestsCount < rhs.requestsCount }
                if lhs.estimatedTokensUsed != rhs.estimatedTokensUsed { return lhs.estimatedTokensUsed < rhs.estimatedTokensUsed }
                return lhs.priority < rhs.priority
            }!
            return (picked, roundRobinCursor)
        }
    }
}
