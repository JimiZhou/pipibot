import Foundation

// MARK: - 1. "Review Proof, Not Code" — Verification Proof Bundles & Deterministic Checks (Poteto Pyramid)

public enum PipiDeterministicCheckKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case shellCommand = "shell_command"
    case regexBan = "regex_ban"
    case requiredPattern = "required_pattern"

    public var id: String { rawValue }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .shellCommand: return lang == .zhHans ? "命令行校验（测试/Lint）" : "Shell Check (Test/Lint)"
        case .regexBan: return lang == .zhHans ? "正则禁令（如禁多余注释/密钥）" : "Regex Ban (Lint Ratchet)"
        case .requiredPattern: return lang == .zhHans ? "必含规范校验" : "Required Pattern"
        }
    }
}

public struct PipiDeterministicCheckSpec: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var kind: PipiDeterministicCheckKind
    /// Shell command (for `.shellCommand`) or regex pattern (for `.regexBan` / `.requiredPattern`).
    public var commandOrPattern: String
    /// Optional file extension filter for regex checks (e.g. "swift,ts,js"). Empty = all changed text files.
    public var fileExtensionsCSV: String
    public var isEnabled: Bool
    /// Original prose Blueprint rule this deterministic check graduated from (Poteto Pyramid graduation).
    public var graduatedFromRule: String?

    public init(
        id: String = "chk_\(UUID().uuidString.prefix(8).lowercased())",
        name: String,
        kind: PipiDeterministicCheckKind,
        commandOrPattern: String,
        fileExtensionsCSV: String = "",
        isEnabled: Bool = true,
        graduatedFromRule: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.commandOrPattern = commandOrPattern
        self.fileExtensionsCSV = fileExtensionsCSV
        self.isEnabled = isEnabled
        self.graduatedFromRule = graduatedFromRule
    }

    public static let defaultChecks: [PipiDeterministicCheckSpec] = [
        PipiDeterministicCheckSpec(
            id: "chk_no_secret_leak",
            name: "No Hardcoded Secrets",
            kind: .regexBan,
            commandOrPattern: #"(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16})"#,
            fileExtensionsCSV: "swift,ts,tsx,js,mjs,py,json,env",
            isEnabled: true,
            graduatedFromRule: "Never commit hardcoded API keys or credentials."
        ),
        PipiDeterministicCheckSpec(
            id: "chk_no_excuse_comments",
            name: "No Excuse/TODO-Hack Comments (pstack ratchet)",
            kind: .regexBan,
            commandOrPattern: #"//\s*(HACK|FIXME|XXX|TEMP|TODO:\s*fix\s*later)\b"#,
            fileExtensionsCSV: "swift,ts,tsx,js,py",
            isEnabled: true,
            graduatedFromRule: "Avoid excuse comments that let hacky code propagate; file an issue instead."
        )
    ]
}

public struct PipiDeterministicCheckResult: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let checkId: String
    public let name: String
    public let kind: PipiDeterministicCheckKind
    public let passed: Bool
    public let exitCode: Int
    public let durationMs: Int
    public let outputSnippet: String

    public init(
        id: String = "chkres_\(UUID().uuidString.prefix(8).lowercased())",
        checkId: String,
        name: String,
        kind: PipiDeterministicCheckKind,
        passed: Bool,
        exitCode: Int = 0,
        durationMs: Int = 0,
        outputSnippet: String
    ) {
        self.id = id
        self.checkId = checkId
        self.name = name
        self.kind = kind
        self.passed = passed
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.outputSnippet = outputSnippet
    }
}

public enum PipiPanelVerdict: String, Codable, CaseIterable, Sendable, Equatable {
    case approve
    case caution
    case block

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .approve: return lang == .zhHans ? "通过" : "Approve"
        case .caution: return lang == .zhHans ? "需留意" : "Caution"
        case .block: return lang == .zhHans ? "建议打回" : "Block"
        }
    }
}

public struct PipiPanelReviewerVote: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let reviewerLabel: String
    public let modelId: String
    public let focusArea: String
    public let verdict: PipiPanelVerdict
    public let summary: String
    public let blockingIssues: [String]

    public init(
        id: String = "vote_\(UUID().uuidString.prefix(8).lowercased())",
        reviewerLabel: String,
        modelId: String,
        focusArea: String,
        verdict: PipiPanelVerdict,
        summary: String,
        blockingIssues: [String] = []
    ) {
        self.id = id
        self.reviewerLabel = reviewerLabel
        self.modelId = modelId
        self.focusArea = focusArea
        self.verdict = verdict
        self.summary = summary
        self.blockingIssues = blockingIssues
    }
}

public enum PipiProofOverallStatus: String, Codable, Sendable, Equatable {
    case verified
    case needsAttention = "needs_attention"
    case blocked

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .verified: return lang == .zhHans ? "证据完备 · 可安全合并" : "Verified Proof · Ready to Merge"
        case .needsAttention: return lang == .zhHans ? "存在提示项 · 请抽查证据" : "Caution · Inspect Evidence"
        case .blocked: return lang == .zhHans ? "校验未通过 · 建议打回" : "Blocked · Send Back Recommended"
        }
    }
}

public struct PipiVerificationProofBundle: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let worktreeSessionId: String
    public let generatedAt: String
    public let checkResults: [PipiDeterministicCheckResult]
    public let panelVotes: [PipiPanelReviewerVote]
    public let evidenceSummary: String
    public let overallStatus: PipiProofOverallStatus
    public let proofScore: Int

    public init(
        id: String = "proof_\(UUID().uuidString.prefix(8).lowercased())",
        worktreeSessionId: String,
        generatedAt: String = ISO8601DateFormatter().string(from: Date()),
        checkResults: [PipiDeterministicCheckResult],
        panelVotes: [PipiPanelReviewerVote],
        evidenceSummary: String,
        overallStatus: PipiProofOverallStatus,
        proofScore: Int
    ) {
        self.id = id
        self.worktreeSessionId = worktreeSessionId
        self.generatedAt = generatedAt
        self.checkResults = checkResults
        self.panelVotes = panelVotes
        self.evidenceSummary = evidenceSummary
        self.overallStatus = overallStatus
        self.proofScore = min(100, max(0, proofScore))
    }

    public var passedCheckCount: Int { checkResults.filter(\.passed).count }
    public var totalCheckCount: Int { checkResults.count }
}

// MARK: - 2. Harness Engineering & 5-Part Operational Loops (@N01ennn)

public struct PipiHarnessFence: Codable, Equatable, Hashable, Sendable {
    /// Minimal-privilege tool allowlist for this loop (empty = inherit Bot defaults).
    public var allowedToolNames: [String]
    /// Hard rules the Bot must never violate (e.g., "Never promise a release date").
    public var hardRules: [String]
    /// Keywords/intents that stay strictly with the owner UNDRAFTED (e.g. refunds, account security, angry messages).
    public var hardNoDraftTriggers: [String]
    /// Answer strictly from cited docs/context; log missing info into Knowledge Gaps instead of guessing.
    public var docsOnlyMode: Bool

    public init(
        allowedToolNames: [String] = [],
        hardRules: [String] = [
            "Never send external replies, open issues, or publish releases without owner Gate approval.",
            "Never promise unconfirmed release dates or execute money-moving operations."
        ],
        hardNoDraftTriggers: [String] = ["refund", "退款", "billing dispute", "账号安全", "account compromise", "angry", "投诉", "律师"],
        docsOnlyMode: Bool = false
    ) {
        self.allowedToolNames = allowedToolNames
        self.hardRules = hardRules
        self.hardNoDraftTriggers = hardNoDraftTriggers
        self.docsOnlyMode = docsOnlyMode
    }
}

public enum PipiOperationalLoopPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case supportFromDocs = "support_from_docs"
    case bugToIssue = "bug_to_issue"
    case weeklyChangelog = "weekly_changelog"
    case weeklyPulse = "weekly_pulse"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .supportFromDocs: return "book.closed.fill"
        case .bugToIssue: return "ladybug.fill"
        case .weeklyChangelog: return "newspaper.fill"
        case .weeklyPulse: return "chart.line.uptrend.xyaxis"
        }
    }

    public func title(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .supportFromDocs: return lang == .zhHans ? "文档客服环（Support Loop）" : "Support-from-Docs Loop"
        case .bugToIssue: return lang == .zhHans ? "报错转工单环（Bug Loop）" : "Bug-to-Issue Loop"
        case .weeklyChangelog: return lang == .zhHans ? "周度更新日志环（Changelog Loop）" : "Weekly Changelog Loop"
        case .weeklyPulse: return lang == .zhHans ? "周一经营一图流（Weekly Pulse）" : "Weekly Pulse in One Message"
        }
    }
}

public struct PipiOperationalLoop: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var botId: String
    public var name: String
    public var preset: PipiOperationalLoopPreset?
    public var triggerKind: PipiRoutineTriggerKind
    public var contextSources: [String]
    public var draftInstruction: String
    public var requiresHumanGate: Bool
    public var reportFeedsContext: Bool
    public var harness: PipiHarnessFence
    public var isEnabled: Bool
    public var approvedCount: Int

    public init(
        id: String = "loop_\(UUID().uuidString.prefix(8).lowercased())",
        botId: String,
        name: String,
        preset: PipiOperationalLoopPreset? = nil,
        triggerKind: PipiRoutineTriggerKind = .channelMessage,
        contextSources: [String] = [],
        draftInstruction: String,
        requiresHumanGate: Bool = true,
        reportFeedsContext: Bool = true,
        harness: PipiHarnessFence = PipiHarnessFence(),
        isEnabled: Bool = true,
        approvedCount: Int = 0
    ) {
        self.id = id
        self.botId = botId
        self.name = name
        self.preset = preset
        self.triggerKind = triggerKind
        self.contextSources = contextSources
        self.draftInstruction = draftInstruction
        self.requiresHumanGate = requiresHumanGate
        self.reportFeedsContext = reportFeedsContext
        self.harness = harness
        self.isEnabled = isEnabled
        self.approvedCount = approvedCount
    }
}

public enum PipiLoopDraftGateStatus: String, Codable, Sendable, Equatable {
    case pendingGate = "pending_gate"
    case approvedAndSent = "approved_and_sent"
    case editedAndSent = "edited_and_sent"
    case flaggedUndrafted = "flagged_undrafted"
    case discarded

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .pendingGate: return lang == .zhHans ? "等待你拍板（Gate）" : "Waiting for Gate Approval"
        case .approvedAndSent: return lang == .zhHans ? "已批准发出" : "Approved & Sent"
        case .editedAndSent: return lang == .zhHans ? "已改规则并发出" : "Rule Added & Sent"
        case .flaggedUndrafted: return lang == .zhHans ? "高敏直转人工（未起草）" : "Flagged Undrafted"
        case .discarded: return lang == .zhHans ? "已丢弃" : "Discarded"
        }
    }
}

public struct PipiLoopDraftItem: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let loopId: String
    public let loopName: String
    public let botId: String
    public let botName: String
    public let inputSummary: String
    public var draftContent: String
    public var citedSources: [String]
    public var status: PipiLoopDraftGateStatus
    public var escalationReason: String?
    public var addedHarnessRule: String?
    public let createdAt: String
    public var resolvedAt: String?

    public init(
        id: String = "drf_\(UUID().uuidString.prefix(8).lowercased())",
        loopId: String,
        loopName: String,
        botId: String,
        botName: String,
        inputSummary: String,
        draftContent: String,
        citedSources: [String] = [],
        status: PipiLoopDraftGateStatus = .pendingGate,
        escalationReason: String? = nil,
        addedHarnessRule: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        resolvedAt: String? = nil
    ) {
        self.id = id
        self.loopId = loopId
        self.loopName = loopName
        self.botId = botId
        self.botName = botName
        self.inputSummary = inputSummary
        self.draftContent = draftContent
        self.citedSources = citedSources
        self.status = status
        self.escalationReason = escalationReason
        self.addedHarnessRule = addedHarnessRule
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }
}

/// Real owner-approved outputs stored as tone examples (learn tone from approved replies, not style guides).
public struct PipiApprovedExample: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let botId: String
    public let loopId: String?
    public let inputSummary: String
    public let approvedOutput: String
    public let createdAt: String

    public init(
        id: String = "ex_\(UUID().uuidString.prefix(8).lowercased())",
        botId: String,
        loopId: String? = nil,
        inputSummary: String,
        approvedOutput: String,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.botId = botId
        self.loopId = loopId
        self.inputSummary = inputSummary
        self.approvedOutput = approvedOutput
        self.createdAt = createdAt
    }
}

/// Unanswered questions logged by loops into a living docs/knowledge roadmap ("report feeds the context").
public struct PipiKnowledgeGapItem: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable, Equatable {
        case open
        case resolved
    }

    public let id: String
    public let botId: String
    public let loopId: String?
    public var question: String
    public var sourceChannel: String
    public var occurrenceCount: Int
    public var status: Status
    public var resolvedDocPath: String?
    public let createdAt: String
    public var updatedAt: String

    public init(
        id: String = "gap_\(UUID().uuidString.prefix(8).lowercased())",
        botId: String,
        loopId: String? = nil,
        question: String,
        sourceChannel: String = "support",
        occurrenceCount: Int = 1,
        status: Status = .open,
        resolvedDocPath: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.botId = botId
        self.loopId = loopId
        self.question = question
        self.sourceChannel = sourceChannel
        self.occurrenceCount = max(1, occurrenceCount)
        self.status = status
        self.resolvedDocPath = resolvedDocPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 3. Skill Pruning & Prompt Bloat Audit (pstack v0.15.46)

public struct PipiSkillWeightItem: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let estimatedTokens: Int
    public let isBloated: Bool
    public let suggestion: String
}

public struct PipiContextBloatReport: Equatable, Sendable {
    public let totalPromptTokens: Int
    public let systemPromptTokens: Int
    public let blueprintTokens: Int
    public let skillWeights: [PipiSkillWeightItem]
    public let graduationCandidates: [String]
    public let summaryZh: String
    public let summaryEn: String
}
