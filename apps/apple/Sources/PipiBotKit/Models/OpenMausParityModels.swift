// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// v0.15.0 OpenMausBot Parity + Self-Hosted E2EE Relay & Security Foundations Models.

import Foundation

// MARK: - 1. Device Pairing, Bounded Auth & Universal Relay Link

public enum PipiPairingScope: String, Codable, CaseIterable, Sendable, Equatable {
    /// Full human owner access (chat, approvals, draft gates, diff merge, triggers).
    case owner
    /// Chat-only remote device access (cannot approve destructive actions or modify settings).
    case chat
    /// External IDE / Agent stdio MCP bounded control plane (hard-blocks approvals, merge, delete, secret reads).
    case mcpBounded = "mcp_bounded"

    public var allowsApprovalsAndMerge: Bool {
        self == .owner
    }

    public var allowsMutations: Bool {
        self == .owner || self == .mcpBounded
    }
}

public struct PipiPairedDevice: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var label: String
    public let scope: PipiPairingScope
    public let tokenHash: String
    public let clientPublicKeyB64: String?
    public let createdAt: Date
    public var lastSeenAt: Date
    public var revoked: Bool

    public init(
        id: String = "dev_\(UUID().uuidString.prefix(10).lowercased())",
        label: String,
        scope: PipiPairingScope = .owner,
        tokenHash: String,
        clientPublicKeyB64: String? = nil,
        createdAt: Date = Date(),
        lastSeenAt: Date = Date(),
        revoked: Bool = false
    ) {
        self.id = id
        self.label = label
        self.scope = scope
        self.tokenHash = tokenHash
        self.clientPublicKeyB64 = clientPublicKeyB64
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.revoked = revoked
    }
}

public struct PipiPairingChallenge: Codable, Sendable, Equatable {
    public let code: String
    public let scope: PipiPairingScope
    public let createdAt: Date
    public let expiresAt: Date
    public var consumed: Bool

    public init(
        code: String,
        scope: PipiPairingScope = .owner,
        createdAt: Date = Date(),
        ttlSeconds: TimeInterval = 300,
        consumed: Bool = false
    ) {
        self.code = code
        self.scope = scope
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(ttlSeconds)
        self.consumed = consumed
    }

    public func isValid(at now: Date = Date()) -> Bool {
        !consumed && now < expiresAt
    }
}

/// Universal remote link shared across iPhone Safari PWA, future App Store iOS App, browsers, and CLI.
/// Format: `https://pipibot.jimizhou.com/c/<hostId>#t=<oneTimeToken>&k=<hostPubKeyB64Url>&lan=<optionalLanUrl>`
/// Sensitive pairing token & host public key live exclusively in the URL `#fragment`, which browsers never transmit in HTTP requests.
public struct PipiUniversalPairingLink: Codable, Sendable, Equatable {
    public let relayOrigin: String
    public let hostId: String
    public let hostPublicKeyB64Url: String
    public let oneTimeToken: String
    public let lanHintURL: String?
    public let expiresAt: Date

    public init(
        relayOrigin: String = "https://pipibot.jimizhou.com",
        hostId: String,
        hostPublicKeyB64Url: String,
        oneTimeToken: String,
        lanHintURL: String? = nil,
        expiresAt: Date = Date().addingTimeInterval(300)
    ) {
        self.relayOrigin = relayOrigin.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.hostId = hostId
        self.hostPublicKeyB64Url = hostPublicKeyB64Url
        self.oneTimeToken = oneTimeToken
        self.lanHintURL = lanHintURL
        self.expiresAt = expiresAt
    }

    public var urlString: String {
        var fragParts = [
            "t=\(Self.urlEncode(oneTimeToken))",
            "k=\(Self.urlEncode(hostPublicKeyB64Url))"
        ]
        if let lan = lanHintURL?.trimmingCharacters(in: .whitespacesAndNewlines), !lan.isEmpty {
            fragParts.append("lan=\(Self.urlEncode(lan))")
        }
        return "\(relayOrigin)/c/\(hostId)#\(fragParts.joined(separator: "&"))"
    }

    public static func parse(_ rawURL: String) -> PipiUniversalPairingLink? {
        guard let components = URLComponents(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme, let host = components.host else {
            return nil
        }
        let pathParts = components.path.split(separator: "/").map(String.init)
        guard pathParts.count >= 2, pathParts[0] == "c", !pathParts[1].isEmpty else {
            return nil
        }
        let hostId = pathParts[1]
        var portSuffix = ""
        if let port = components.port {
            portSuffix = ":\(port)"
        }
        let origin = "\(scheme)://\(host)\(portSuffix)"

        let fragment = components.fragment ?? ""
        var fragMap: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                fragMap[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
            }
        }
        guard let token = fragMap["t"], !token.isEmpty,
              let pubKey = fragMap["k"], !pubKey.isEmpty else {
            return nil
        }
        return PipiUniversalPairingLink(
            relayOrigin: origin,
            hostId: hostId,
            hostPublicKeyB64Url: pubKey,
            oneTimeToken: token,
            lanHintURL: fragMap["lan"]
        )
    }

    private static func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=#+?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

public enum PipiRelayConnectionState: String, Codable, Sendable, Equatable {
    case disabled
    case connecting
    case connected
    case reconnecting
    case error
}

// MARK: - 2. Three-Tier Fast Group Auto-Routing (Decision Model)

public enum PipiDecisionModelProviderKind: String, Codable, CaseIterable, Sendable, Equatable {
    case localFast = "local_fast"
    case cloudflareWorkersAI = "cloudflare_workers_ai"
    case customOpenAICompat = "custom_openai_compat"
    case disabled = "disabled"

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .localFast: return lang == .zhHans ? "本地极速小模型（Ollama / MLX 优先）" : "Local Fast Model (Ollama / MLX)"
        case .cloudflareWorkersAI: return lang == .zhHans ? "Cloudflare Workers AI（每日免费额度）" : "Cloudflare Workers AI (Free Tier)"
        case .customOpenAICompat: return lang == .zhHans ? "自定义轻量 OpenAI 兼容端点" : "Custom Fast OpenAI-Compatible Endpoint"
        case .disabled: return lang == .zhHans ? "关闭（仅确定性规则与群主兜底）" : "Disabled (Rules + Lead Fallback Only)"
        }
    }
}

public struct PipiDecisionModelConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var providerKind: PipiDecisionModelProviderKind
    public var endpointURL: String
    public var modelId: String
    public var accountId: String
    public var secretAccountKey: String
    public var timeoutMs: Int
    public var minConfidence: Double
    public var maxAutoParallel: Int

    public init(
        enabled: Bool = true,
        providerKind: PipiDecisionModelProviderKind = .localFast,
        endpointURL: String = "http://127.0.0.1:11434/v1/chat/completions",
        modelId: String = "qwen2.5:1.5b",
        accountId: String = "",
        secretAccountKey: String = "pipibot_decision_model_api_key",
        timeoutMs: Int = 1500,
        minConfidence: Double = 0.6,
        maxAutoParallel: Int = 2
    ) {
        self.enabled = enabled
        self.providerKind = providerKind
        self.endpointURL = endpointURL
        self.modelId = modelId
        self.accountId = accountId
        self.secretAccountKey = secretAccountKey
        self.timeoutMs = max(300, min(5000, timeoutMs))
        self.minConfidence = max(0.3, min(0.95, minConfidence))
        self.maxAutoParallel = max(1, min(2, maxAutoParallel))
    }
}

public enum PipiGroupRouteTier: String, Codable, Sendable, Equatable {
    case explicitMention = "explicit_mention"
    case deterministicRule = "deterministic_rule"
    case decisionModel = "decision_model"
    case leadFallback = "lead_fallback"
}

public struct PipiGroupRoutePick: Codable, Sendable, Equatable {
    public let botId: String
    public let confidence: Double
    public let reason: String

    public init(botId: String, confidence: Double, reason: String) {
        self.botId = botId
        self.confidence = confidence
        self.reason = reason
    }
}

public struct PipiGroupRouteDecision: Codable, Sendable, Equatable {
    public let tier: PipiGroupRouteTier
    public let picks: [PipiGroupRoutePick]
    public let latencyMs: Int
    public let note: String

    public init(tier: PipiGroupRouteTier, picks: [PipiGroupRoutePick], latencyMs: Int, note: String) {
        self.tier = tier
        self.picks = picks
        self.latencyMs = latencyMs
        self.note = note
    }
}

// MARK: - 3. Sentinel Zero-LLM Out-of-Process Health Scanner

public enum PipiSentinelIssueKind: String, Codable, Sendable, Equatable {
    case toolError = "tool_error"
    case shellError = "shell_error"
    case queueStall = "queue_stall"
    case highCostTurn = "high_cost_turn"
    case routineFailure = "routine_failure"
}

public enum PipiSentinelSeverity: String, Codable, Sendable, Equatable {
    case low
    case medium
    case high
}

public struct PipiSentinelIssue: Identifiable, Codable, Sendable, Equatable {
    public var id: String { signature }
    public let signature: String
    public let kind: PipiSentinelIssueKind
    public let severity: PipiSentinelSeverity
    public let normalizedTitle: String
    public let toolName: String?
    public let botId: String?
    public var count: Int
    public var wastedTurns: Int
    public let firstSeenAt: Date
    public var lastSeenAt: Date
    public var evidenceRefIds: [String]
    public var promotedToEvolutionId: String?

    public init(
        signature: String,
        kind: PipiSentinelIssueKind,
        severity: PipiSentinelSeverity,
        normalizedTitle: String,
        toolName: String? = nil,
        botId: String? = nil,
        count: Int = 1,
        wastedTurns: Int = 1,
        firstSeenAt: Date = Date(),
        lastSeenAt: Date = Date(),
        evidenceRefIds: [String] = [],
        promotedToEvolutionId: String? = nil
    ) {
        self.signature = signature
        self.kind = kind
        self.severity = severity
        self.normalizedTitle = String(normalizedTitle.prefix(160))
        self.toolName = toolName
        self.botId = botId
        self.count = count
        self.wastedTurns = wastedTurns
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.evidenceRefIds = evidenceRefIds
        self.promotedToEvolutionId = promotedToEvolutionId
    }
}

public struct PipiSentinelReport: Codable, Sendable, Equatable {
    public let scannedAt: Date
    public let issues: [PipiSentinelIssue]
    public let promotedProposalsCount: Int
    public let skippedUnchanged: Bool

    public init(
        scannedAt: Date = Date(),
        issues: [PipiSentinelIssue] = [],
        promotedProposalsCount: Int = 0,
        skippedUnchanged: Bool = false
    ) {
        self.scannedAt = scannedAt
        self.issues = issues
        self.promotedProposalsCount = promotedProposalsCount
        self.skippedUnchanged = skippedUnchanged
    }
}

// MARK: - 4. Layered Bot Box Sandbox, Credential Broker & Custom ACP Engines

public enum PipiBotExecutionIsolationMode: String, Codable, CaseIterable, Sendable, Equatable {
    case hostDirect = "host_direct"
    case sandboxBox = "sandbox_box"

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .hostDirect: return lang == .zhHans ? "宿主机直通（含凭据代理）" : "Host Direct (+ Credential Broker)"
        case .sandboxBox: return lang == .zhHans ? "Bot Box 强隔离沙箱（推荐外部导入 Bot）" : "Bot Box Isolated Sandbox"
        }
    }
}

public struct PipiBoxSelfCheckItem: Codable, Sendable, Equatable {
    public let name: String
    public let passed: Bool
    public let detail: String

    public init(name: String, passed: Bool, detail: String) {
        self.name = name
        self.passed = passed
        self.detail = detail
    }
}

public struct PipiBoxSelfCheckResult: Codable, Sendable, Equatable {
    public let backend: String // "seatbelt" | "bwrap" | "off"
    public let checkedAt: Date
    public let checks: [PipiBoxSelfCheckItem]

    public var passedCount: Int { checks.filter(\.passed).count }
    public var allPassed: Bool { !checks.isEmpty && checks.allSatisfy(\.passed) }

    public init(backend: String, checkedAt: Date = Date(), checks: [PipiBoxSelfCheckItem]) {
        self.backend = backend
        self.checkedAt = checkedAt
        self.checks = checks
    }
}

public struct PipiCustomACPEngineConfig: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var displayName: String
    public var commandLine: String
    public var iconPreset: String
    public var extraEnvKeys: [String]
    public var discoveredModels: [String]
    public var enabled: Bool

    public init(
        id: String = "acp_\(UUID().uuidString.prefix(8).lowercased())",
        displayName: String,
        commandLine: String,
        iconPreset: String = "terminal",
        extraEnvKeys: [String] = [],
        discoveredModels: [String] = [],
        enabled: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.commandLine = commandLine
        self.iconPreset = iconPreset
        self.extraEnvKeys = extraEnvKeys
        self.discoveredModels = discoveredModels
        self.enabled = enabled
    }
}

// MARK: - 5. Portable Redacted Team / Bot Templates (bot.md / team.md)

public struct PipiPortableBotSpec: Codable, Sendable, Equatable {
    public let slug: String
    public let name: String
    public let roleTitle: String
    public let tagline: String
    public let instructionsMarkdown: String
    public let skillNames: [String]
    public let recommendedIsolation: PipiBotExecutionIsolationMode
    public let automationBlueprint: PipiBotAutomationBlueprint?

    public init(
        slug: String,
        name: String,
        roleTitle: String,
        tagline: String,
        instructionsMarkdown: String,
        skillNames: [String] = [],
        recommendedIsolation: PipiBotExecutionIsolationMode = .sandboxBox,
        automationBlueprint: PipiBotAutomationBlueprint? = nil
    ) {
        self.slug = slug
        self.name = name
        self.roleTitle = roleTitle
        self.tagline = tagline
        self.instructionsMarkdown = instructionsMarkdown
        self.skillNames = skillNames
        self.recommendedIsolation = recommendedIsolation
        self.automationBlueprint = automationBlueprint
    }
}

public struct PipiPortableRoutineSpec: Codable, Sendable, Equatable {
    public let title: String
    public let botSlug: String
    public let prompt: String
    public let triggerKind: PipiRoutineTriggerKind
    public let cronExpression: String?
    public let enabled: Bool // Always false on export/import for safety

    public init(
        title: String,
        botSlug: String,
        prompt: String,
        triggerKind: PipiRoutineTriggerKind = .schedule,
        cronExpression: String? = nil,
        enabled: Bool = false
    ) {
        self.title = title
        self.botSlug = botSlug
        self.prompt = prompt
        self.triggerKind = triggerKind
        self.cronExpression = cronExpression
        self.enabled = false
    }
}

public struct PipiPortableSkillSpec: Codable, Sendable, Equatable {
    public let slug: String
    public let name: String
    public let description: String
    public let markdownBody: String

    public init(slug: String, name: String, description: String, markdownBody: String) {
        self.slug = slug
        self.name = name
        self.description = description
        self.markdownBody = markdownBody
    }
}

public struct PipiPortableTemplatePackage: Codable, Sendable, Equatable {
    public let formatVersion: String
    public let scope: String // "bot" | "team"
    public let name: String
    public let tagline: String
    public let bots: [PipiPortableBotSpec]
    public let skills: [PipiPortableSkillSpec]
    public let routines: [PipiPortableRoutineSpec]
    public let channelName: String?
    public let redactedSecretsCount: Int
    public let skippedFiles: [String]
    public let sourceDescription: String

    public init(
        formatVersion: String = "pipibot-portable-v1",
        scope: String,
        name: String,
        tagline: String,
        bots: [PipiPortableBotSpec],
        skills: [PipiPortableSkillSpec] = [],
        routines: [PipiPortableRoutineSpec] = [],
        channelName: String? = nil,
        redactedSecretsCount: Int = 0,
        skippedFiles: [String] = [],
        sourceDescription: String = ""
    ) {
        self.formatVersion = formatVersion
        self.scope = scope
        self.name = name
        self.tagline = tagline
        self.bots = bots
        self.skills = skills
        self.routines = routines
        self.channelName = channelName
        self.redactedSecretsCount = redactedSecretsCount
        self.skippedFiles = skippedFiles
        self.sourceDescription = sourceDescription
    }
}
