import Foundation

// MARK: - 1. Goal-First Automation Blueprint (Dr Eggbot Methodology)

public struct PipiBlueprintEdgeCase: Codable, Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public var scenario: String
    public var expectedBehavior: String
    public var verificationCheck: String

    public init(
        id: String = "edge_\(UUID().uuidString.prefix(8).lowercased())",
        scenario: String,
        expectedBehavior: String,
        verificationCheck: String = ""
    ) {
        self.id = id
        self.scenario = scenario
        self.expectedBehavior = expectedBehavior
        self.verificationCheck = verificationCheck
    }
}

public struct PipiBotAutomationBlueprint: Codable, Equatable, Hashable, Sendable {
    public var goal: String
    public var processSteps: [String]
    public var sourceOfTruthRules: [String]
    public var verificationCriteria: [String]
    public var escalationRules: [String]
    public var feedbackSources: [String]
    public var entityIdSchema: [String]
    public var dryRunExamples: [PipiBlueprintEdgeCase]
    public var blueprintVersion: Int
    public var updatedAt: String
    public var lastReviewedAt: String?

    public init(
        goal: String = "",
        processSteps: [String] = [],
        sourceOfTruthRules: [String] = [],
        verificationCriteria: [String] = [],
        escalationRules: [String] = [],
        feedbackSources: [String] = [],
        entityIdSchema: [String] = [],
        dryRunExamples: [PipiBlueprintEdgeCase] = [],
        blueprintVersion: Int = 1,
        updatedAt: String = ISO8601DateFormatter().string(from: Date()),
        lastReviewedAt: String? = nil
    ) {
        self.goal = goal
        self.processSteps = processSteps
        self.sourceOfTruthRules = sourceOfTruthRules
        self.verificationCriteria = verificationCriteria
        self.escalationRules = escalationRules
        self.feedbackSources = feedbackSources
        self.entityIdSchema = entityIdSchema
        self.dryRunExamples = dryRunExamples
        self.blueprintVersion = max(1, blueprintVersion)
        self.updatedAt = updatedAt
        self.lastReviewedAt = lastReviewedAt
    }

    public var isConfigured: Bool {
        !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !processSteps.isEmpty
    }

    /// Formats the structured automation blueprint as a high-signal system prompt section.
    public func renderedPromptBlock() -> String {
        guard isConfigured else { return "" }
        var lines: [String] = ["## Automation Blueprint (v\(blueprintVersion))"]
        if !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("- **Primary Goal**: \(goal)")
        }
        if !processSteps.isEmpty {
            lines.append("- **Process Steps**:")
            for (idx, step) in processSteps.enumerated() {
                lines.append("  \(idx + 1). \(step)")
            }
        }
        if !sourceOfTruthRules.isEmpty {
            lines.append("- **Source-of-Truth & Decision Rules**:")
            for rule in sourceOfTruthRules {
                lines.append("  - \(rule)")
            }
        }
        if !verificationCriteria.isEmpty {
            lines.append("- **Verification / Done Criteria**:")
            for check in verificationCriteria {
                lines.append("  - \(check)")
            }
        }
        if !escalationRules.isEmpty {
            lines.append("- **When to Escalate to Owner**:")
            for rule in escalationRules {
                lines.append("  - \(rule)")
            }
        }
        if !feedbackSources.isEmpty {
            lines.append("- **Feedback Sources for Self-Improvement**: \(feedbackSources.joined(separator: ", "))")
        }
        if !entityIdSchema.isEmpty {
            lines.append("- **Cross-Source Entity IDs**: \(entityIdSchema.joined(separator: ", ")) (use `record_entity_ledger` / `query_entity_ledger` to stay consistent across sources)")
        }
        if !dryRunExamples.isEmpty {
            lines.append("- **Verified Edge-Case Walkthroughs**:")
            for ex in dryRunExamples.prefix(5) {
                lines.append("  - If \(ex.scenario) -> \(ex.expectedBehavior)\(ex.verificationCheck.isEmpty ? "" : " [Verify: \(ex.verificationCheck)]")")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 2. Entity Correlation Ledger & Run Outcome Records

public struct PipiEntityLedgerEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var botId: String
    public var entityKey: String
    public var entityType: String
    public var source: String
    public var status: String
    public var summary: String
    public var attributes: [String: String]
    public var updatedAt: String

    public init(
        id: String = "ent_\(UUID().uuidString.prefix(8).lowercased())",
        botId: String,
        entityKey: String,
        entityType: String = "generic",
        source: String = "pipibot",
        status: String = "active",
        summary: String,
        attributes: [String: String] = [:],
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.botId = botId
        self.entityKey = entityKey
        self.entityType = entityType
        self.source = source
        self.status = status
        self.summary = summary
        self.attributes = attributes
        self.updatedAt = updatedAt
    }
}

public struct PipiRunOutcomeRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let botId: String
    public let routineId: String?
    public let taskTitle: String
    public let succeeded: Bool
    public let verificationNotes: String
    public var userCorrection: String?
    public let entityKeys: [String]
    public let durationMs: Int
    public let createdAt: String

    public init(
        id: String = "out_\(UUID().uuidString.prefix(8).lowercased())",
        botId: String,
        routineId: String? = nil,
        taskTitle: String,
        succeeded: Bool,
        verificationNotes: String,
        userCorrection: String? = nil,
        entityKeys: [String] = [],
        durationMs: Int = 0,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.botId = botId
        self.routineId = routineId
        self.taskTitle = taskTitle
        self.succeeded = succeeded
        self.verificationNotes = verificationNotes
        self.userCorrection = userCorrection
        self.entityKeys = entityKeys
        self.durationMs = durationMs
        self.createdAt = createdAt
    }
}

public enum PipiEvolutionProposalStatus: String, Codable, Sendable, Equatable {
    case pending
    case approved
    case rejected
    case rolledBack
}

public struct PipiBlueprintEvolutionProposal: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let botId: String
    public let botName: String
    public let goalSummary: String
    public let rationale: String
    public var diffs: [EvolutionDiffItem]
    public var proposedBlueprint: PipiBotAutomationBlueprint
    public var previousBlueprint: PipiBotAutomationBlueprint?
    public var status: PipiEvolutionProposalStatus
    public let createdAt: String
    public var resolvedAt: String?
    public var resolutionNote: String?

    public init(
        id: String = "evo_\(UUID().uuidString.prefix(8).lowercased())",
        botId: String,
        botName: String,
        goalSummary: String,
        rationale: String,
        diffs: [EvolutionDiffItem],
        proposedBlueprint: PipiBotAutomationBlueprint,
        previousBlueprint: PipiBotAutomationBlueprint? = nil,
        status: PipiEvolutionProposalStatus = .pending,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        resolvedAt: String? = nil,
        resolutionNote: String? = nil
    ) {
        self.id = id
        self.botId = botId
        self.botName = botName
        self.goalSummary = goalSummary
        self.rationale = rationale
        self.diffs = diffs
        self.proposedBlueprint = proposedBlueprint
        self.previousBlueprint = previousBlueprint
        self.status = status
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.resolutionNote = resolutionNote
    }
}

// MARK: - 3. Event-Driven Routine Triggers

public enum PipiRoutineTriggerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case schedule
    case webhook
    case fileOrGitWatch = "file_or_git_watch"
    case channelMessage = "channel_message"
    case hostHealth = "host_health"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .schedule: return "clock.arrow.circlepath"
        case .webhook: return "bolt.horizontal.circle"
        case .fileOrGitWatch: return "folder.badge.gearshape"
        case .channelMessage: return "message.badge.waveform"
        case .hostHealth: return "waveform.path.ecg"
        }
    }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .schedule: return lang == .zhHans ? "定时 / Cron" : "Schedule / Cron"
        case .webhook: return lang == .zhHans ? "HTTP Webhook" : "HTTP Webhook"
        case .fileOrGitWatch: return lang == .zhHans ? "目录 / Git 变动" : "File / Git Watch"
        case .channelMessage: return lang == .zhHans ? "微信 / 群聊规则" : "Channel Message"
        case .hostHealth: return lang == .zhHans ? "主机健康阈值" : "Host Health"
        }
    }
}

public enum PipiHealthTriggerMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case cpuPercent = "cpu_percent"
    case memoryPercent = "memory_percent"
    case diskFreeGB = "disk_free_gb"
    case nodeOffline = "node_offline"

    public var id: String { rawValue }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .cpuPercent: return lang == .zhHans ? "CPU 占用高于 (%)" : "CPU Usage Above (%)"
        case .memoryPercent: return lang == .zhHans ? "内存占用高于 (%)" : "Memory Usage Above (%)"
        case .diskFreeGB: return lang == .zhHans ? "可用磁盘低于 (GB)" : "Free Disk Below (GB)"
        case .nodeOffline: return lang == .zhHans ? "远程主机离线" : "Remote Node Offline"
        }
    }
}

public struct PipiRoutineEventConfig: Codable, Equatable, Hashable, Sendable {
    /// Standard 5-field cron expression (e.g. "30 9 * * 1-5") when overriding simple schedule.
    public var cronExpression: String?
    /// Shared secret for HMAC-SHA256 (`X-PiPiBot-Signature`) or `Authorization: Bearer <secret>`.
    public var webhookSecret: String?
    /// Local directory or Git repository path for `.fileOrGitWatch`.
    public var watchPath: String?
    public var watchGitEvents: Bool
    /// Keyword or regex match for `.channelMessage`.
    public var messageKeyword: String?
    /// Optional channel scope ("wechat", "group", "any").
    public var channelFilter: String?
    /// Metric & numeric threshold for `.hostHealth`.
    public var healthMetric: PipiHealthTriggerMetric?
    public var healthThreshold: Double?
    /// Minimum seconds between consecutive event firings (anti-storm debounce).
    public var cooldownSeconds: Int

    public init(
        cronExpression: String? = nil,
        webhookSecret: String? = nil,
        watchPath: String? = nil,
        watchGitEvents: Bool = true,
        messageKeyword: String? = nil,
        channelFilter: String? = "any",
        healthMetric: PipiHealthTriggerMetric? = nil,
        healthThreshold: Double? = nil,
        cooldownSeconds: Int = 60
    ) {
        self.cronExpression = cronExpression?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.webhookSecret = webhookSecret?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.watchPath = watchPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.watchGitEvents = watchGitEvents
        self.messageKeyword = messageKeyword?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.channelFilter = channelFilter?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.healthMetric = healthMetric
        self.healthThreshold = healthThreshold
        self.cooldownSeconds = max(5, cooldownSeconds)
    }
}

public struct PipiRoutineRunLog: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let routineId: String
    public let routineTitle: String
    public let botId: String
    public let triggerKind: PipiRoutineTriggerKind
    public let triggerSummary: String
    public let payloadPreview: String?
    public var status: PipiRunRecord.Status
    public var outputPreview: String
    public var durationMs: Int
    public let triggeredAt: String

    public init(
        id: String = "rtlog_\(UUID().uuidString.prefix(8).lowercased())",
        routineId: String,
        routineTitle: String,
        botId: String,
        triggerKind: PipiRoutineTriggerKind,
        triggerSummary: String,
        payloadPreview: String? = nil,
        status: PipiRunRecord.Status = .running,
        outputPreview: String = "",
        durationMs: Int = 0,
        triggeredAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.routineId = routineId
        self.routineTitle = routineTitle
        self.botId = botId
        self.triggerKind = triggerKind
        self.triggerSummary = triggerSummary
        self.payloadPreview = payloadPreview
        self.status = status
        self.outputPreview = outputPreview
        self.durationMs = durationMs
        self.triggeredAt = triggeredAt
    }
}

// MARK: - 4. Git Worktree Isolation & Diff Review Closure

public enum PipiWorktreeReviewStatus: String, Codable, CaseIterable, Sendable, Equatable {
    case active
    case readyForReview = "ready_for_review"
    case changesRequested = "changes_requested"
    case merged
    case discarded

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .active: return lang == .zhHans ? "隔离执行中" : "Running in Worktree"
        case .readyForReview: return lang == .zhHans ? "待审查 Diff" : "Ready for Review"
        case .changesRequested: return lang == .zhHans ? "已打回续改" : "Changes Requested"
        case .merged: return lang == .zhHans ? "已合并并清理" : "Merged & Cleaned"
        case .discarded: return lang == .zhHans ? "已丢弃" : "Discarded"
        }
    }
}

public enum PipiWorktreeMergeStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case squash
    case mergeCommit = "merge_commit"
    case keepBranchForPR = "keep_branch_for_pr"

    public var id: String { rawValue }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .squash: return lang == .zhHans ? "Squash 合并并清理" : "Squash Merge & Clean"
        case .mergeCommit: return lang == .zhHans ? "Merge Commit 并清理" : "Merge Commit & Clean"
        case .keepBranchForPR: return lang == .zhHans ? "保留分支用于提 PR" : "Keep Branch for PR"
        }
    }
}

public struct PipiWorktreeFileChange: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let status: String
    public let additions: Int
    public let deletions: Int

    public init(path: String, status: String = "M", additions: Int = 0, deletions: Int = 0) {
        self.path = path
        self.status = status
        self.additions = additions
        self.deletions = deletions
    }
}

public struct PipiWorktreeReviewComment: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let filePath: String?
    public let lineNumber: Int?
    public let comment: String
    public let author: String
    public let createdAt: String
    public var resolved: Bool

    public init(
        id: String = "wcmt_\(UUID().uuidString.prefix(8).lowercased())",
        filePath: String? = nil,
        lineNumber: Int? = nil,
        comment: String,
        author: String = "owner",
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        resolved: Bool = false
    ) {
        self.id = id
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.comment = comment
        self.author = author
        self.createdAt = createdAt
        self.resolved = resolved
    }
}

public struct PipiWorktreeReviewSession: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let repoPath: String
    public let worktreePath: String
    public let branchName: String
    public let baseBranch: String
    public var taskTitle: String
    public let botId: String
    public let botName: String
    public let hostId: String
    public let conversationId: String?
    public let groupId: String?
    public var status: PipiWorktreeReviewStatus
    public var files: [PipiWorktreeFileChange]
    public var unifiedDiff: String
    public var diffSummary: String
    public var comments: [PipiWorktreeReviewComment]
    public var testSummary: String?
    public let createdAt: String
    public var updatedAt: String

    public init(
        id: String = "wt_\(UUID().uuidString.prefix(8).lowercased())",
        repoPath: String,
        worktreePath: String,
        branchName: String,
        baseBranch: String,
        taskTitle: String,
        botId: String,
        botName: String,
        hostId: String = PipiHostDescriptor.localHostId,
        conversationId: String? = nil,
        groupId: String? = nil,
        status: PipiWorktreeReviewStatus = .active,
        files: [PipiWorktreeFileChange] = [],
        unifiedDiff: String = "",
        diffSummary: String = "",
        comments: [PipiWorktreeReviewComment] = [],
        testSummary: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.repoPath = repoPath
        self.worktreePath = worktreePath
        self.branchName = branchName
        self.baseBranch = baseBranch
        self.taskTitle = taskTitle
        self.botId = botId
        self.botName = botName
        self.hostId = hostId
        self.conversationId = conversationId
        self.groupId = groupId
        self.status = status
        self.files = files
        self.unifiedDiff = unifiedDiff
        self.diffSummary = diffSummary
        self.comments = comments
        self.testSummary = testSummary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var totalAdditions: Int { files.reduce(0) { $0 + $1.additions } }
    public var totalDeletions: Int { files.reduce(0) { $0 + $1.deletions } }
}

// MARK: - 5. Token & Cost Metering (Alert-Only, Non-Blocking)

public struct PipiUsageRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let botId: String
    public let botName: String
    public let hostId: String
    public let conversationId: String?
    public let taskTitle: String
    public let modelId: String
    public let providerKind: String
    public let promptTokens: Int
    public let completionTokens: Int
    public let cachedTokens: Int
    public let totalTokens: Int
    public let estimatedCostUSD: Double
    public let isEstimated: Bool
    public let isLocalFree: Bool
    public let createdAt: String

    public init(
        id: String = "usg_\(UUID().uuidString.prefix(8).lowercased())",
        botId: String,
        botName: String,
        hostId: String = PipiHostDescriptor.localHostId,
        conversationId: String? = nil,
        taskTitle: String,
        modelId: String,
        providerKind: String,
        promptTokens: Int,
        completionTokens: Int,
        cachedTokens: Int = 0,
        estimatedCostUSD: Double,
        isEstimated: Bool = false,
        isLocalFree: Bool = false,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.botId = botId
        self.botName = botName
        self.hostId = hostId
        self.conversationId = conversationId
        self.taskTitle = taskTitle
        self.modelId = modelId
        self.providerKind = providerKind
        self.promptTokens = max(0, promptTokens)
        self.completionTokens = max(0, completionTokens)
        self.cachedTokens = max(0, cachedTokens)
        self.totalTokens = max(0, promptTokens) + max(0, completionTokens)
        self.estimatedCostUSD = isLocalFree ? 0 : max(0, estimatedCostUSD)
        self.isEstimated = isEstimated
        self.isLocalFree = isLocalFree
        self.createdAt = createdAt
    }
}

public struct PipiUsageAlertConfig: Codable, Equatable, Sendable {
    /// Alert-only thresholds: PiPiBot notifies the user gently and NEVER blocks or kills running tasks.
    public var enableAlerts: Bool
    public var dailyCostAlertUSD: Double
    public var perTaskCostAlertUSD: Double
    public var dailyTokenAlert: Int
    public var perTaskTokenAlert: Int

    public init(
        enableAlerts: Bool = true,
        dailyCostAlertUSD: Double = 5.0,
        perTaskCostAlertUSD: Double = 1.0,
        dailyTokenAlert: Int = 500_000,
        perTaskTokenAlert: Int = 120_000
    ) {
        self.enableAlerts = enableAlerts
        self.dailyCostAlertUSD = max(0.1, dailyCostAlertUSD)
        self.perTaskCostAlertUSD = max(0.05, perTaskCostAlertUSD)
        self.dailyTokenAlert = max(10_000, dailyTokenAlert)
        self.perTaskTokenAlert = max(5_000, perTaskTokenAlert)
    }

    public static let `default` = PipiUsageAlertConfig()
}

public struct PipiUsageAlertNotice: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let scope: String
    public let messageZh: String
    public let messageEn: String
    public let createdAt: String
    public var acknowledged: Bool

    public init(
        id: String = "ualert_\(UUID().uuidString.prefix(8).lowercased())",
        scope: String,
        messageZh: String,
        messageEn: String,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        acknowledged: Bool = false
    ) {
        self.id = id
        self.scope = scope
        self.messageZh = messageZh
        self.messageEn = messageEn
        self.createdAt = createdAt
        self.acknowledged = acknowledged
    }

    public func message(_ lang: PipiResolvedLanguage) -> String {
        lang == .zhHans ? messageZh : messageEn
    }
}

// MARK: - 6. Mission Board Unified Projection

public enum PipiMissionTaskColumn: String, CaseIterable, Identifiable, Sendable {
    case queued
    case running
    case needsReview = "needs_review"
    case done

    public var id: String { rawValue }

    public func title(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .queued: return lang == .zhHans ? "待执行" : "Queued"
        case .running: return lang == .zhHans ? "运行中" : "Running"
        case .needsReview: return lang == .zhHans ? "待审查" : "Needs Review"
        case .done: return lang == .zhHans ? "已完成" : "Done"
        }
    }
}
