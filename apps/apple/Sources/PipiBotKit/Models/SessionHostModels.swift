import Foundation

// MARK: - 1. Bot & Project Permission Tier

public enum PipiPermissionTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case readOnly
    case ask
    case autoEdit

    public var id: String { rawValue }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .readOnly: return lang == .zhHans ? "只读" : "Read-only"
        case .ask: return lang == .zhHans ? "询问后执行" : "Ask first"
        case .autoEdit: return lang == .zhHans ? "自动编辑" : "Auto-edit"
        }
    }

    public func description(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .readOnly:
            return lang == .zhHans
                ? "仅允许分析、搜索与制定计划，禁止修改文件或执行写入命令"
                : "Analysis and planning only; prevents file writes and mutating commands"
        case .ask:
            return lang == .zhHans
                ? "先以只读方式准备方案，待你点击批准后再执行写入"
                : "Runs read-only first and requests your approval before applying edits"
        case .autoEdit:
            return lang == .zhHans
                ? "允许直接在工作区创建、编辑文件并执行命令"
                : "Allows editing files and running workspace commands automatically"
        }
    }

    public var iconName: String {
        switch self {
        case .readOnly: return "eye"
        case .ask: return "hand.raised"
        case .autoEdit: return "pencil.and.outline"
        }
    }
}

// MARK: - 2. Runtime Host Descriptor (Blueprint §4 & §5)

public enum PipiHostKind: String, Codable, Sendable, Equatable {
    case local
    case remote
}

public enum PipiHostLinkState: String, Codable, Sendable, Equatable {
    case online
    case degraded
    case offline

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .online: return lang == .zhHans ? "在线" : "Online"
        case .degraded: return lang == .zhHans ? "信号弱" : "Degraded"
        case .offline: return lang == .zhHans ? "离线" : "Offline"
        }
    }
}

public struct PipiHostCapabilities: Codable, Equatable, Sendable {
    public var llmProviderIds: [String]
    public var cliAgents: [PipiLocalAgentKind]
    public var hasFilesystem: Bool
    public var osName: String

    public init(
        llmProviderIds: [String] = [],
        cliAgents: [PipiLocalAgentKind] = [],
        hasFilesystem: Bool = true,
        osName: String = "macOS"
    ) {
        self.llmProviderIds = llmProviderIds
        self.cliAgents = cliAgents
        self.hasFilesystem = hasFilesystem
        self.osName = osName
    }
}

public struct PipiHostDescriptor: Codable, Identifiable, Equatable, Sendable {
    public static let localHostId = "host_local_mac"

    public let id: String
    public var name: String
    public var kind: PipiHostKind
    public var endpoint: String?
    public var linkState: PipiHostLinkState
    public var capabilities: PipiHostCapabilities

    public init(
        id: String = PipiHostDescriptor.localHostId,
        name: String,
        kind: PipiHostKind = .local,
        endpoint: String? = nil,
        linkState: PipiHostLinkState = .online,
        capabilities: PipiHostCapabilities = PipiHostCapabilities()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.endpoint = endpoint
        self.linkState = linkState
        self.capabilities = capabilities
    }

    public static func currentLocalMachineName() -> String {
        #if os(macOS)
        if let localized = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localized.isEmpty {
            return localized
        }
        #endif
        let fallback = ProcessInfo.processInfo.hostName
            .replacingOccurrences(of: ".local", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "This Mac" : fallback
    }

    public func displayName(_ lang: PipiResolvedLanguage) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if kind == .local {
            return lang == .zhHans ? "本机" : "This Mac"
        }
        return id
    }

    public func statusBadgeText(_ lang: PipiResolvedLanguage) -> String {
        "\(displayName(lang)) · \(linkState.label(lang))"
    }

    public static func local(
        name: String = currentLocalMachineName(),
        llmProviderIds: [String] = [],
        cliAgents: [PipiLocalAgentKind] = []
    ) -> PipiHostDescriptor {
        #if os(macOS)
        let osName = "macOS"
        let hasFS = true
        #else
        let osName = "iOS"
        let hasFS = false
        #endif
        return PipiHostDescriptor(
            id: localHostId,
            name: name.isEmpty ? "This Mac" : name,
            kind: .local,
            endpoint: nil,
            linkState: .online,
            capabilities: PipiHostCapabilities(
                llmProviderIds: llmProviderIds,
                cliAgents: cliAgents,
                hasFilesystem: hasFS,
                osName: osName
            )
        )
    }
}

// MARK: - 3. Session State & Structured Activity Models (Blueprint §4 & §7.2)

public enum PipiSessionState: String, Codable, CaseIterable, Sendable {
    case idle
    case queued
    case running
    case needsYou
    case done
    case failed
    case cancelled

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .idle: return lang == .zhHans ? "空闲" : "Idle"
        case .queued: return lang == .zhHans ? "排队中" : "Queued"
        case .running: return lang == .zhHans ? "运行中" : "Running"
        case .needsYou: return lang == .zhHans ? "需要你" : "Needs You"
        case .done: return lang == .zhHans ? "已完成" : "Done"
        case .failed: return lang == .zhHans ? "失败" : "Failed"
        case .cancelled: return lang == .zhHans ? "已取消" : "Cancelled"
        }
    }
}

public struct PipiPlanItem: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var isCompleted: Bool
    public var detail: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, isCompleted, detail
    }

    public init(
        id: String = "plan_\(UUID().uuidString.prefix(8).lowercased())",
        title: String,
        isCompleted: Bool = false,
        detail: String? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.detail = detail
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? "plan_\(UUID().uuidString.prefix(8).lowercased())"
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        self.detail = try c.decodeIfPresent(String.self, forKey: .detail)
    }
}

public struct PipiStepEvent: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case running
        case succeeded
        case failed
    }

    public let id: String
    public var verbPhrase: String
    public var detail: String?
    public var toolName: String?
    public var status: Status
    public var durationMs: Int?
    public var exitCode: Int?
    public let timestamp: String

    private enum CodingKeys: String, CodingKey {
        case id, verbPhrase, detail, toolName, status, durationMs, exitCode, timestamp
    }

    public init(
        id: String = "step_\(UUID().uuidString.prefix(8).lowercased())",
        verbPhrase: String,
        detail: String? = nil,
        toolName: String? = nil,
        status: Status = .running,
        durationMs: Int? = nil,
        exitCode: Int? = nil,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.verbPhrase = verbPhrase
        self.detail = detail
        self.toolName = toolName
        self.status = status
        self.durationMs = durationMs
        self.exitCode = exitCode
        self.timestamp = timestamp
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? "step_\(UUID().uuidString.prefix(8).lowercased())"
        self.verbPhrase = try c.decodeIfPresent(String.self, forKey: .verbPhrase) ?? ""
        self.detail = try c.decodeIfPresent(String.self, forKey: .detail)
        self.toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        self.status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .succeeded
        self.durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
        self.exitCode = try c.decodeIfPresent(Int.self, forKey: .exitCode)
        self.timestamp = try c.decodeIfPresent(String.self, forKey: .timestamp) ?? ""
    }

    public var formattedDuration: String? {
        guard let durationMs, durationMs > 0 else { return nil }
        if durationMs < 1000 { return "\(durationMs)ms" }
        return String(format: "%.1fs", Double(durationMs) / 1000.0)
    }
}

public struct PipiFileChange: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var path: String
    public var additions: Int
    public var deletions: Int
    public var diffPreview: String?
    public var operation: String?

    private enum CodingKeys: String, CodingKey {
        case id, path, additions, deletions, diffPreview, operation
    }

    public init(
        id: String = "fc_\(UUID().uuidString.prefix(8).lowercased())",
        path: String,
        additions: Int = 0,
        deletions: Int = 0,
        diffPreview: String? = nil,
        operation: String? = nil
    ) {
        self.id = id
        self.path = path
        self.additions = additions
        self.deletions = deletions
        self.diffPreview = diffPreview
        self.operation = operation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? "fc_\(UUID().uuidString.prefix(8).lowercased())"
        self.path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        self.additions = try c.decodeIfPresent(Int.self, forKey: .additions) ?? 0
        self.deletions = try c.decodeIfPresent(Int.self, forKey: .deletions) ?? 0
        self.diffPreview = try c.decodeIfPresent(String.self, forKey: .diffPreview)
        self.operation = try c.decodeIfPresent(String.self, forKey: .operation)
    }

    public var fileName: String {
        (path as NSString).lastPathComponent
    }
}

public struct PipiSessionApproval: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending
        case approved
        case denied
        case expired
    }

    public struct Option: Codable, Identifiable, Equatable, Sendable {
        public enum Style: String, Codable, Sendable {
            case primary
            case secondary
            case destructive
        }

        public let id: String
        public let label: String
        public let style: Style

        public init(id: String, label: String, style: Style) {
            self.id = id
            self.label = label
            self.style = style
        }
    }

    public let id: String
    public let sessionId: String
    public var eventSeq: Int
    public var question: String
    public var detail: String?
    public var options: [Option]
    public var recommendedOptionId: String
    public var status: Status
    public var chosenOptionId: String?
    public var userNote: String?
    public let createdAt: String
    public var resolvedAt: String?
    public var pendingPrompt: String?
    public var pendingTarget: PipiExecutionTarget?
    // Wave 1 (#08) Guardrail & Multi-Granularity Approval metadata (backward-compatible optional fields)
    public var riskLevel: PipiRiskLevel?
    public var userAuthorization: PipiUserAuthorizationLevel?
    public var rationale: String?
    public var operationId: String?
    public var actionToolName: String?
    public var actionKind: PipiActionKind?
    public var actionTarget: String?
    public var projectId: String?
    public var chosenGranularity: PipiApprovalGranularity?

    private enum CodingKeys: String, CodingKey {
        case id, sessionId, eventSeq, question, detail, options, recommendedOptionId
        case status, chosenOptionId, userNote, createdAt, resolvedAt
        case pendingPrompt, pendingTarget
        case riskLevel, userAuthorization, rationale, operationId
        case actionToolName, actionKind, actionTarget, projectId, chosenGranularity
    }

    public init(
        id: String = "appr_\(UUID().uuidString.prefix(8).lowercased())",
        sessionId: String,
        eventSeq: Int = 0,
        question: String,
        detail: String? = nil,
        options: [Option],
        recommendedOptionId: String,
        status: Status = .pending,
        chosenOptionId: String? = nil,
        userNote: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        resolvedAt: String? = nil,
        pendingPrompt: String? = nil,
        pendingTarget: PipiExecutionTarget? = nil,
        riskLevel: PipiRiskLevel? = nil,
        userAuthorization: PipiUserAuthorizationLevel? = nil,
        rationale: String? = nil,
        operationId: String? = nil,
        actionToolName: String? = nil,
        actionKind: PipiActionKind? = nil,
        actionTarget: String? = nil,
        projectId: String? = nil,
        chosenGranularity: PipiApprovalGranularity? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.eventSeq = eventSeq
        self.question = question
        self.detail = detail
        self.options = options
        self.recommendedOptionId = recommendedOptionId
        self.status = status
        self.chosenOptionId = chosenOptionId
        self.userNote = userNote
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.pendingPrompt = pendingPrompt
        self.pendingTarget = pendingTarget
        self.riskLevel = riskLevel
        self.userAuthorization = userAuthorization
        self.rationale = rationale
        self.operationId = operationId
        self.actionToolName = actionToolName
        self.actionKind = actionKind
        self.actionTarget = actionTarget
        self.projectId = projectId
        self.chosenGranularity = chosenGranularity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.sessionId = try c.decode(String.self, forKey: .sessionId)
        self.eventSeq = try c.decodeIfPresent(Int.self, forKey: .eventSeq) ?? 0
        self.question = try c.decodeIfPresent(String.self, forKey: .question) ?? ""
        self.detail = try c.decodeIfPresent(String.self, forKey: .detail)
        self.options = try c.decodeIfPresent([Option].self, forKey: .options) ?? []
        self.recommendedOptionId = try c.decodeIfPresent(String.self, forKey: .recommendedOptionId) ?? ""
        self.status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .pending
        self.chosenOptionId = try c.decodeIfPresent(String.self, forKey: .chosenOptionId)
        self.userNote = try c.decodeIfPresent(String.self, forKey: .userNote)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        self.resolvedAt = try c.decodeIfPresent(String.self, forKey: .resolvedAt)
        self.pendingPrompt = try c.decodeIfPresent(String.self, forKey: .pendingPrompt)
        self.pendingTarget = try c.decodeIfPresent(PipiExecutionTarget.self, forKey: .pendingTarget)
        self.riskLevel = try c.decodeIfPresent(PipiRiskLevel.self, forKey: .riskLevel)
        self.userAuthorization = try c.decodeIfPresent(PipiUserAuthorizationLevel.self, forKey: .userAuthorization)
        self.rationale = try c.decodeIfPresent(String.self, forKey: .rationale)
        self.operationId = try c.decodeIfPresent(String.self, forKey: .operationId)
        self.actionToolName = try c.decodeIfPresent(String.self, forKey: .actionToolName)
        self.actionKind = try c.decodeIfPresent(PipiActionKind.self, forKey: .actionKind)
        self.actionTarget = try c.decodeIfPresent(String.self, forKey: .actionTarget)
        self.projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        self.chosenGranularity = try c.decodeIfPresent(PipiApprovalGranularity.self, forKey: .chosenGranularity)
    }
}

public struct PipiSessionSummaryInfo: Codable, Equatable, Sendable {
    public var conclusion: String
    public var exitCode: Int?
    public var testSummary: String?
    public var changedFilesCount: Int
    public var durationMs: Int?

    private enum CodingKeys: String, CodingKey {
        case conclusion, exitCode, testSummary, changedFilesCount, durationMs
    }

    public init(
        conclusion: String,
        exitCode: Int? = nil,
        testSummary: String? = nil,
        changedFilesCount: Int = 0,
        durationMs: Int? = nil
    ) {
        self.conclusion = conclusion
        self.exitCode = exitCode
        self.testSummary = testSummary
        self.changedFilesCount = changedFilesCount
        self.durationMs = durationMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.conclusion = try c.decodeIfPresent(String.self, forKey: .conclusion) ?? ""
        self.exitCode = try c.decodeIfPresent(Int.self, forKey: .exitCode)
        self.testSummary = try c.decodeIfPresent(String.self, forKey: .testSummary)
        self.changedFilesCount = try c.decodeIfPresent(Int.self, forKey: .changedFilesCount) ?? 0
        self.durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
    }
}

public enum PipiSessionEventKind: String, Codable, Sendable {
    case message
    case plan
    case step
    case toolCall
    case fileChange
    case approval
    case artifact
    case summary
    case error
    case stateChange
}

public struct PipiSessionEvent: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let sessionId: String
    public let seq: Int
    public let kind: PipiSessionEventKind
    public var messageId: String?
    public var textDelta: String?
    public var planItems: [PipiPlanItem]?
    public var step: PipiStepEvent?
    public var fileChange: PipiFileChange?
    public var approval: PipiSessionApproval?
    public var summary: PipiSessionSummaryInfo?
    public var state: PipiSessionState?
    public var errorMessage: String?
    public let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id, sessionId, seq, kind, messageId, textDelta
        case planItems, step, fileChange, approval, summary, state, errorMessage, createdAt
    }

    public init(
        id: String = "evt_\(UUID().uuidString.prefix(8).lowercased())",
        sessionId: String,
        seq: Int,
        kind: PipiSessionEventKind,
        messageId: String? = nil,
        textDelta: String? = nil,
        planItems: [PipiPlanItem]? = nil,
        step: PipiStepEvent? = nil,
        fileChange: PipiFileChange? = nil,
        approval: PipiSessionApproval? = nil,
        summary: PipiSessionSummaryInfo? = nil,
        state: PipiSessionState? = nil,
        errorMessage: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.sessionId = sessionId
        self.seq = seq
        self.kind = kind
        self.messageId = messageId
        self.textDelta = textDelta
        self.planItems = planItems
        self.step = step
        self.fileChange = fileChange
        self.approval = approval
        self.summary = summary
        self.state = state
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? "evt_\(UUID().uuidString.prefix(8).lowercased())"
        self.sessionId = try c.decode(String.self, forKey: .sessionId)
        self.seq = try c.decodeIfPresent(Int.self, forKey: .seq) ?? 0
        self.kind = try c.decodeIfPresent(PipiSessionEventKind.self, forKey: .kind) ?? .message
        self.messageId = try c.decodeIfPresent(String.self, forKey: .messageId)
        self.textDelta = try c.decodeIfPresent(String.self, forKey: .textDelta)
        self.planItems = try c.decodeIfPresent([PipiPlanItem].self, forKey: .planItems)
        self.step = try c.decodeIfPresent(PipiStepEvent.self, forKey: .step)
        self.fileChange = try c.decodeIfPresent(PipiFileChange.self, forKey: .fileChange)
        self.approval = try c.decodeIfPresent(PipiSessionApproval.self, forKey: .approval)
        self.summary = try c.decodeIfPresent(PipiSessionSummaryInfo.self, forKey: .summary)
        self.state = try c.decodeIfPresent(PipiSessionState.self, forKey: .state)
        self.errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

// MARK: - 4. Host Protocol v2 Transfer Objects (Blueprint §5)

public struct PipiUserInput: Codable, Equatable, Sendable {
    public var text: String
    public var attachments: [PipiChatAttachment]
    public var targetOverride: PipiExecutionTarget?
    public var personaId: String?
    public var activateTargetConversation: Bool
    public var permissionOverride: PipiPermissionTier?
    public var isApprovalResume: Bool
    public var priority: PipiSchedulerPriority?

    private enum CodingKeys: String, CodingKey {
        case text, attachments, targetOverride, personaId, activateTargetConversation, permissionOverride, isApprovalResume, priority
    }

    public init(
        text: String,
        attachments: [PipiChatAttachment] = [],
        targetOverride: PipiExecutionTarget? = nil,
        personaId: String? = nil,
        activateTargetConversation: Bool = true,
        permissionOverride: PipiPermissionTier? = nil,
        isApprovalResume: Bool = false,
        priority: PipiSchedulerPriority? = nil
    ) {
        self.text = text
        self.attachments = attachments
        self.targetOverride = targetOverride
        self.personaId = personaId
        self.activateTargetConversation = activateTargetConversation
        self.permissionOverride = permissionOverride
        self.isApprovalResume = isApprovalResume
        self.priority = priority
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.attachments = try c.decodeIfPresent([PipiChatAttachment].self, forKey: .attachments) ?? []
        self.targetOverride = try c.decodeIfPresent(PipiExecutionTarget.self, forKey: .targetOverride)
        self.personaId = try c.decodeIfPresent(String.self, forKey: .personaId)
        self.activateTargetConversation = try c.decodeIfPresent(Bool.self, forKey: .activateTargetConversation) ?? true
        self.permissionOverride = try c.decodeIfPresent(PipiPermissionTier.self, forKey: .permissionOverride)
        self.isApprovalResume = try c.decodeIfPresent(Bool.self, forKey: .isApprovalResume) ?? false
        self.priority = try c.decodeIfPresent(PipiSchedulerPriority.self, forKey: .priority)
    }
}

public struct PipiSessionSummary: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let hostId: String
    public let botId: String
    public let projectId: String?
    public let title: String
    public let state: PipiSessionState
    public let engineLabel: String?
    public let updatedAt: String
    public let lastEventSeq: Int

    public init(
        id: String,
        hostId: String,
        botId: String,
        projectId: String? = nil,
        title: String,
        state: PipiSessionState,
        engineLabel: String? = nil,
        updatedAt: String,
        lastEventSeq: Int = 0
    ) {
        self.id = id
        self.hostId = hostId
        self.botId = botId
        self.projectId = projectId
        self.title = title
        self.state = state
        self.engineLabel = engineLabel
        self.updatedAt = updatedAt
        self.lastEventSeq = lastEventSeq
    }
}

// MARK: - 5. Context Usage Estimation (Assistant Inspector)

public struct PipiContextUsageEstimate: Equatable, Sendable {
    public let estimatedTokens: Int
    public let contextWindowTokens: Int
    public let messageCount: Int
    public let turnCount: Int
    public let attachmentCount: Int
    public let isMemoryEnabled: Bool
    public let hasPersonalProfile: Bool

    public init(
        estimatedTokens: Int,
        contextWindowTokens: Int,
        messageCount: Int,
        turnCount: Int,
        attachmentCount: Int,
        isMemoryEnabled: Bool,
        hasPersonalProfile: Bool
    ) {
        self.estimatedTokens = max(0, estimatedTokens)
        self.contextWindowTokens = max(1, contextWindowTokens)
        self.messageCount = max(0, messageCount)
        self.turnCount = max(0, turnCount)
        self.attachmentCount = max(0, attachmentCount)
        self.isMemoryEnabled = isMemoryEnabled
        self.hasPersonalProfile = hasPersonalProfile
    }

    public var utilizationRatio: Double {
        min(1.0, max(0.0, Double(estimatedTokens) / Double(contextWindowTokens)))
    }

    public var utilizationPercent: Int {
        Int((utilizationRatio * 100.0).rounded())
    }

    public var formattedEstimatedTokens: String {
        Self.formatTokenCount(estimatedTokens)
    }

    public var formattedWindowTokens: String {
        Self.formatTokenCount(contextWindowTokens)
    }

    public static func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            let m = Double(count) / 1_000_000.0
            return m.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(m))M" : String(format: "%.1fM", m)
        }
        if count >= 1000 {
            let k = Double(count) / 1000.0
            if k >= 10 || k.truncatingRemainder(dividingBy: 1) == 0 {
                return "\(Int(k.rounded()))k"
            }
            return String(format: "%.1fk", k)
        }
        return "\(count)"
    }
}

// MARK: - 6. Wave 1 Canonical Host v2 Contracts (Aligned with host-v2.schema.json)
//
// PiPiBot — Clean-room MIT implementation.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

public enum PipiSchedulerPriority: String, Codable, CaseIterable, Sendable, Equatable {
    case approvalReview = "approval_review"
    case voiceInteractive = "voice_interactive"
    case chatInteractive = "chat_interactive"
    case delegatedTask = "delegated_task"
    case proactiveRoutine = "proactive_routine"
    case compaction = "compaction"
    case backgroundMemory = "background_memory"

    /// Lower rank means higher urgency.
    public var rank: Int {
        switch self {
        case .approvalReview: return 0
        case .voiceInteractive: return 1
        case .chatInteractive: return 2
        case .delegatedTask: return 3
        case .proactiveRoutine: return 4
        case .compaction: return 5
        case .backgroundMemory: return 6
        }
    }

    public var isInteractiveOrHigher: Bool {
        rank <= PipiSchedulerPriority.chatInteractive.rank
    }

    public var isPreemptible: Bool {
        switch self {
        case .delegatedTask, .proactiveRoutine, .backgroundMemory:
            return true
        case .approvalReview, .voiceInteractive, .chatInteractive, .compaction:
            return false
        }
    }
}

public enum PipiRiskLevel: String, Codable, CaseIterable, Sendable, Equatable {
    case low
    case medium
    case high
    case critical

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .low: return lang == .zhHans ? "低风险" : "Low Risk"
        case .medium: return lang == .zhHans ? "中风险" : "Medium Risk"
        case .high: return lang == .zhHans ? "高风险" : "High Risk"
        case .critical: return lang == .zhHans ? "严重阻断" : "Critical"
        }
    }
}

public enum PipiUserAuthorizationLevel: String, Codable, CaseIterable, Sendable, Equatable {
    case high
    case medium
    case low
    case unknown
}

public enum PipiGuardrailDecision: String, Codable, CaseIterable, Sendable, Equatable {
    case allow
    case needsApproval = "needs_approval"
    case deny
}

public enum PipiApprovalGranularity: String, Codable, CaseIterable, Sendable, Equatable {
    case allowOnce = "allow_once"
    case allowSession = "allow_session"
    case allowProject = "allow_project"
    case allowAlways = "allow_always"
    case deny = "deny"

    public var isApproved: Bool {
        self != .deny
    }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .allowOnce: return lang == .zhHans ? "允许本次" : "Allow once"
        case .allowSession: return lang == .zhHans ? "本会话同类允许" : "Allow in session"
        case .allowProject: return lang == .zhHans ? "本项目允许" : "Allow in project"
        case .allowAlways: return lang == .zhHans ? "始终允许" : "Always allow"
        case .deny: return lang == .zhHans ? "拒绝" : "Deny"
        }
    }

    /// Maps both Wave 1 option IDs and legacy S1 option IDs (`allow_changes`, `keep_readonly`).
    public static func fromOptionId(_ optionId: String, recommendedOptionId: String = "allow_changes") -> PipiApprovalGranularity {
        switch optionId {
        case "allow_once", "allow_changes":
            return .allowOnce
        case "allow_session":
            return .allowSession
        case "allow_project":
            return .allowProject
        case "allow_always":
            return .allowAlways
        case "deny", "keep_readonly", "reject":
            return .deny
        default:
            return optionId == recommendedOptionId ? .allowOnce : .deny
        }
    }
}

public enum PipiActionKind: String, Codable, CaseIterable, Sendable, Equatable {
    case readOnly = "read_only"
    case prepareDraft = "prepare_draft"
    case localWrite = "local_write"
    case shellCommand = "shell_command"
    case externalEffect = "external_effect"
    case credentialAccess = "credential_access"
    case securityChange = "security_change"
    case destructive = "destructive"
}

public enum PipiActionSourceTrust: String, Codable, CaseIterable, Sendable, Equatable {
    case trustedUser = "trusted_user"
    case trustedUserRoutine = "trusted_user_routine"
    case agentGeneratedRoutine = "agent_generated_routine"
    case untrustedExternal = "untrusted_external"
}

public enum PipiOperationLedgerStatus: String, Codable, CaseIterable, Sendable, Equatable {
    case inFlight = "in_flight"
    case completed = "completed"
    case denied = "denied"
    case unknownOutcome = "unknown_outcome"
}

public enum PipiTeamCollaborationPattern: String, Codable, CaseIterable, Sendable, Equatable {
    case classifyAndAct = "classify-and-act"
    case fanOutAndSynthesize = "fan-out-and-synthesize"
    case adversarialVerification = "adversarial-verification"
    case tournament = "tournament"
    case loopUntilDone = "loop-until-done"
}

public struct PipiGuardrailActionInput: Codable, Equatable, Sendable {
    public var operationId: String
    public var toolName: String
    public var actionKind: PipiActionKind
    public var target: String
    public var payloadSummary: String
    public var isPreparatoryOnly: Bool
    public var sessionId: String?
    public var projectId: String?
    public var sourceTrust: PipiActionSourceTrust
    public var trustedUserMessages: [String]
    public var untrustedContextSnippets: [String]
    public var hasRecentRevocation: Bool

    public init(
        operationId: String = "op_\(UUID().uuidString.prefix(8).lowercased())",
        toolName: String,
        actionKind: PipiActionKind,
        target: String,
        payloadSummary: String,
        isPreparatoryOnly: Bool = false,
        sessionId: String? = nil,
        projectId: String? = nil,
        sourceTrust: PipiActionSourceTrust = .trustedUser,
        trustedUserMessages: [String] = [],
        untrustedContextSnippets: [String] = [],
        hasRecentRevocation: Bool = false
    ) {
        self.operationId = operationId
        self.toolName = toolName
        self.actionKind = actionKind
        self.target = target
        self.payloadSummary = payloadSummary
        self.isPreparatoryOnly = isPreparatoryOnly
        self.sessionId = sessionId
        self.projectId = projectId
        self.sourceTrust = sourceTrust
        self.trustedUserMessages = trustedUserMessages
        self.untrustedContextSnippets = untrustedContextSnippets
        self.hasRecentRevocation = hasRecentRevocation
    }
}

public struct PipiGuardrailVerdict: Codable, Equatable, Sendable {
    public var riskLevel: PipiRiskLevel
    public var userAuthorization: PipiUserAuthorizationLevel
    public var decision: PipiGuardrailDecision
    public var rationale: String
    public var operationId: String
    public var ruleId: String?
    public var usedLLMJudge: Bool
    public var matchedWhitelistRuleId: String?

    public init(
        riskLevel: PipiRiskLevel,
        userAuthorization: PipiUserAuthorizationLevel,
        decision: PipiGuardrailDecision,
        rationale: String,
        operationId: String,
        ruleId: String? = nil,
        usedLLMJudge: Bool = false,
        matchedWhitelistRuleId: String? = nil
    ) {
        self.riskLevel = riskLevel
        self.userAuthorization = userAuthorization
        self.decision = decision
        self.rationale = rationale
        self.operationId = operationId
        self.ruleId = ruleId
        self.usedLLMJudge = usedLLMJudge
        self.matchedWhitelistRuleId = matchedWhitelistRuleId
    }
}

public struct PipiApprovalWhitelistRule: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var granularity: PipiApprovalGranularity
    public var toolName: String
    public var actionKind: PipiActionKind
    public var targetPattern: String?
    public var sessionId: String?
    public var projectId: String?
    public var note: String?
    public let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id, granularity, toolName, actionKind, targetPattern, sessionId, projectId, note, createdAt
    }

    public init(
        id: String = "wl_\(UUID().uuidString.prefix(8).lowercased())",
        granularity: PipiApprovalGranularity,
        toolName: String,
        actionKind: PipiActionKind,
        targetPattern: String? = nil,
        sessionId: String? = nil,
        projectId: String? = nil,
        note: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.granularity = granularity
        self.toolName = toolName
        self.actionKind = actionKind
        self.targetPattern = targetPattern
        self.sessionId = sessionId
        self.projectId = projectId
        self.note = note
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? "wl_\(UUID().uuidString.prefix(8).lowercased())"
        self.granularity = try c.decodeIfPresent(PipiApprovalGranularity.self, forKey: .granularity) ?? .allowSession
        self.toolName = try c.decodeIfPresent(String.self, forKey: .toolName) ?? "*"
        self.actionKind = try c.decodeIfPresent(PipiActionKind.self, forKey: .actionKind) ?? .localWrite
        self.targetPattern = try c.decodeIfPresent(String.self, forKey: .targetPattern)
        self.sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        self.projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        self.note = try c.decodeIfPresent(String.self, forKey: .note)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

// MARK: - 7. Wave 2 Canonical Host v2 Contracts (#01 Personal Wiki, #02 Bot Memory, #03 Proactive)
//
// PiPiBot — Clean-room MIT implementation.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

public enum PipiWikiEntityCategory: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
    case people
    case projects
    case topics
    case life
    case repos

    public var id: String { rawValue }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .people: return lang == .zhHans ? "人物" : "People"
        case .projects: return lang == .zhHans ? "项目" : "Projects"
        case .topics: return lang == .zhHans ? "主题" : "Topics"
        case .life: return lang == .zhHans ? "生活" : "Life"
        case .repos: return lang == .zhHans ? "代码库" : "Repos"
        }
    }

    public var iconName: String {
        switch self {
        case .people: return "person.crop.circle"
        case .projects: return "folder.badge.gearshape"
        case .topics: return "book.pages"
        case .life: return "sun.horizon"
        case .repos: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

public enum PipiWikiSearchScope: String, Codable, CaseIterable, Sendable, Equatable {
    case all
    case originals
    case summaries
}

public enum PipiBotMemoryLifecycleStage: String, Codable, CaseIterable, Sendable, Equatable {
    case candidate
    case consolidated
    case archived
}

public enum PipiProactiveSourceKind: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
    case calendarEventKit = "calendar_eventkit"
    case remindersEventKit = "reminders_eventkit"
    case gitWorkspace = "git_workspace"
    case deviceTelemetry = "device_telemetry"
    case chatPocketNote = "chat_pocket_note"

    public var id: String { rawValue }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .calendarEventKit: return lang == .zhHans ? "Apple 日历" : "Apple Calendar"
        case .remindersEventKit: return lang == .zhHans ? "Apple 提醒事项" : "Apple Reminders"
        case .gitWorkspace: return lang == .zhHans ? "本地 Git 与工作区" : "Local Git & Workspace"
        case .deviceTelemetry: return lang == .zhHans ? "Mac 设备状态" : "Mac Telemetry"
        case .chatPocketNote: return lang == .zhHans ? "对话与随手记" : "Chats & Notes"
        }
    }

    public var iconName: String {
        switch self {
        case .calendarEventKit: return "calendar"
        case .remindersEventKit: return "checklist"
        case .gitWorkspace: return "arrow.triangle.branch"
        case .deviceTelemetry: return "gauge.with.dots.needle.33percent"
        case .chatPocketNote: return "note.text"
        }
    }
}

public enum PipiProactiveActionDecision: String, Codable, CaseIterable, Sendable, Equatable {
    case remindDirectly = "remind_directly"
    case prepareBriefing = "prepare_briefing"
    case trackForFollowUp = "track_for_follow_up"
    case staySilent = "stay_silent"

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .remindDirectly: return lang == .zhHans ? "直接提醒" : "Remind Directly"
        case .prepareBriefing: return lang == .zhHans ? "提前备料 (Prepare)" : "Prepare Briefing"
        case .trackForFollowUp: return lang == .zhHans ? "静默跟进" : "Track Quietly"
        case .staySilent: return lang == .zhHans ? "保持静默" : "Stay Silent"
        }
    }
}

public enum PipiProactiveFeedbackSignal: String, Codable, CaseIterable, Sendable, Equatable {
    case acted
    case thanked
    case dismissed
    case snoozed
    case mutedTopic = "muted_topic"
    case ignored

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .acted: return lang == .zhHans ? "已采纳" : "Acted"
        case .thanked: return lang == .zhHans ? "有帮助" : "Helpful"
        case .dismissed: return lang == .zhHans ? "忽略" : "Dismiss"
        case .snoozed: return lang == .zhHans ? "稍后" : "Snooze"
        case .mutedTopic: return lang == .zhHans ? "不再提醒此类" : "Mute Topic"
        case .ignored: return lang == .zhHans ? "未读跳过" : "Ignored"
        }
    }
}

// MARK: - 8. Wave 3 Canonical Host v2 Contracts (#05 AlterEgo, #06 team.md, #11 CLI/Skills/Notes)
//
// PiPiBot — Clean-room MIT implementation.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

public enum PipiDelegationTaskStatus: String, Codable, CaseIterable, Sendable, Equatable {
    case queued
    case running
    case paused
    case completed
    case failed
    case cancelled

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .queued: return lang == .zhHans ? "排队中" : "Queued"
        case .running: return lang == .zhHans ? "分身运行中" : "Running"
        case .paused: return lang == .zhHans ? "已暂停" : "Paused"
        case .completed: return lang == .zhHans ? "已完成" : "Done"
        case .failed: return lang == .zhHans ? "失败" : "Failed"
        case .cancelled: return lang == .zhHans ? "已取消" : "Cancelled"
        }
    }

    public var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }
}

public enum PipiDynamicBotProposalAction: String, Codable, CaseIterable, Sendable, Equatable {
    case inviteExisting = "invite_existing"
    case createAndInvite = "create_and_invite"

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .inviteExisting: return lang == .zhHans ? "拉入现有 Bot" : "Invite Existing Bot"
        case .createAndInvite: return lang == .zhHans ? "新建角色 Bot 并加入" : "Create & Invite Bot"
        }
    }
}

public enum PipiDynamicBotProposalStatus: String, Codable, CaseIterable, Sendable, Equatable {
    case pending
    case approved
    case rejected
}

public enum PipiTrackingItemStatus: String, Codable, CaseIterable, Sendable, Equatable {
    case open
    case done
    case archived

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .open: return lang == .zhHans ? "待办" : "Open"
        case .done: return lang == .zhHans ? "已完成" : "Done"
        case .archived: return lang == .zhHans ? "已归档" : "Archived"
        }
    }
}

public enum PipiArtifactDocumentKind: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
    case note
    case report
    case spec
    case plan
    case draft

    public var id: String { rawValue }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .note: return lang == .zhHans ? "笔记" : "Note"
        case .report: return lang == .zhHans ? "报告" : "Report"
        case .spec: return lang == .zhHans ? "方案规格" : "Spec"
        case .plan: return lang == .zhHans ? "计划" : "Plan"
        case .draft: return lang == .zhHans ? "草稿" : "Draft"
        }
    }

    public var iconName: String {
        switch self {
        case .note: return "note.text"
        case .report: return "doc.text.magnifyingglass"
        case .spec: return "doc.badge.gearshape"
        case .plan: return "list.bullet.clipboard"
        case .draft: return "square.and.pencil"
        }
    }
}

// MARK: - 9. Wave 4 Canonical Host v2 Contracts (#07 Local Model Stack & #10 Personal Daily Voice)
//
// PiPiBot — Clean-room MIT implementation.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied) and optional MIT
// backend adapter for simplexai-labs/PolyStrata (MIT License). See root NOTICE.

public enum PipiModelSourceMode: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
    case localModel = "local_model"
    case subscription
    case byok

    public var id: String { rawValue }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .localModel: return lang == .zhHans ? "本地模型 (Local)" : "Local Model"
        case .subscription: return lang == .zhHans ? "订阅 CLI (Subscription)" : "Subscription CLI"
        case .byok: return lang == .zhHans ? "自有接口 (BYOK)" : "BYOK API"
        }
    }
}

public enum PipiLocalInferenceEngineKind: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
    case polystrata
    case llamaCpp = "llama_cpp"
    case ollama
    case mlx

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .polystrata: return "PolyStrata (MIT)"
        case .llamaCpp: return "llama.cpp Metal"
        case .ollama: return "Ollama"
        case .mlx: return "Apple MLX"
        }
    }

    public func localizedBadge(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .polystrata:
            return lang == .zhHans ? "PolyStrata MoE (MIT)" : "PolyStrata MoE (MIT)"
        case .llamaCpp:
            return "llama.cpp Metal"
        case .ollama:
            return "Ollama"
        case .mlx:
            return "Apple MLX"
        }
    }
}

public enum PipiModelSelfTestStatus: String, Codable, CaseIterable, Sendable, Equatable {
    case untested
    case running
    case verified
    case failed

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .untested: return lang == .zhHans ? "未验证" : "Untested"
        case .running: return lang == .zhHans ? "自测中..." : "Testing..."
        case .verified: return lang == .zhHans ? "真实问答已通过" : "QA Verified"
        case .failed: return lang == .zhHans ? "自测失败" : "Test Failed"
        }
    }
}

public enum PipiVoiceInteractionMode: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
    case dictation
    case museHandsFree = "muse_hands_free"
    case voiceToTask = "voice_to_task"

    public var id: String { rawValue }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .dictation: return lang == .zhHans ? "语音输入" : "Dictation"
        case .museHandsFree: return lang == .zhHans ? "语音通话" : "Voice Call"
        case .voiceToTask: return lang == .zhHans ? "语音任务" : "Voice Task"
        }
    }

    public var iconName: String {
        switch self {
        case .dictation: return "mic"
        case .museHandsFree: return "phone.fill"
        case .voiceToTask: return "checklist"
        }
    }
}

public enum PipiVoiceSessionState: String, Codable, CaseIterable, Sendable, Equatable {
    case idle
    case listening
    case transcribing
    case thinking
    case speaking
    case interrupted
    case error

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .idle: return lang == .zhHans ? "空闲" : "Idle"
        case .listening: return lang == .zhHans ? "聆听中" : "Listening"
        case .transcribing: return lang == .zhHans ? "识别中" : "Transcribing"
        case .thinking: return lang == .zhHans ? "思考中" : "Thinking"
        case .speaking: return lang == .zhHans ? "播报中" : "Speaking"
        case .interrupted: return lang == .zhHans ? "已打断，正在听你说" : "Interrupted — Listening"
        case .error: return lang == .zhHans ? "语音异常" : "Voice Error"
        }
    }
}

public enum PipiVoiceEngineProvider: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
    case appleOnDevice = "apple_on_device"
    case whisperKit = "whisper_kit"
    case mlxAudio = "mlx_audio"
    case openaiByok = "openai_byok"
    case deepgramByok = "deepgram_byok"
    case elevenlabsByok = "elevenlabs_byok"
    case customByok = "custom_byok"

    public var id: String { rawValue }

    public var isOnDevice: Bool {
        switch self {
        case .appleOnDevice, .whisperKit, .mlxAudio:
            return true
        case .openaiByok, .deepgramByok, .elevenlabsByok, .customByok:
            return false
        }
    }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .appleOnDevice: return lang == .zhHans ? "Apple 原生端侧 (Speech / AVSpeech)" : "Apple On-Device (Speech / AVSpeech)"
        case .whisperKit: return lang == .zhHans ? "WhisperKit (端侧)" : "WhisperKit (On-Device)"
        case .mlxAudio: return lang == .zhHans ? "Apple MLX Audio (端侧)" : "Apple MLX Audio (On-Device)"
        case .openaiByok: return lang == .zhHans ? "OpenAI Voice API (云端 BYOK)" : "OpenAI Voice API (Cloud BYOK)"
        case .deepgramByok: return lang == .zhHans ? "Deepgram Nova (云端 BYOK)" : "Deepgram Nova (Cloud BYOK)"
        case .elevenlabsByok: return lang == .zhHans ? "ElevenLabs TTS (云端 BYOK)" : "ElevenLabs TTS (Cloud BYOK)"
        case .customByok: return lang == .zhHans ? "自定义兼容语音 API (云端 BYOK)" : "Custom Voice API (Cloud BYOK)"
        }
    }
}

public enum PipiVoicePrivacyPolicy: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
    case onDeviceOnly = "on_device_only"
    case onDeviceFirst = "on_device_first"
    case cloudPreferred = "cloud_preferred"

    public var id: String { rawValue }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .onDeviceOnly: return lang == .zhHans ? "严格仅端侧（零外发）" : "On-Device Only (Zero Egress)"
        case .onDeviceFirst: return lang == .zhHans ? "端侧优先（可回退云端 BYOK）" : "On-Device First (BYOK Fallback)"
        case .cloudPreferred: return lang == .zhHans ? "云端 BYOK 优先（端侧兜底）" : "Cloud BYOK First (Local Fallback)"
        }
    }
}

// MARK: - 10. Wave 5 Canonical Host v2 Contracts (#09 Computer Use: Phase A Chrome & Phase B macOS Cua)
//
// PiPiBot — Clean-room MIT implementation.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

public enum PipiComputerUsePhase: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
    case chromeBrowser = "chrome_browser"
    case macosDesktop = "macos_desktop"

    public var id: String { rawValue }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .chromeBrowser: return lang == .zhHans ? "Phase A · 已登录 Chrome 协同" : "Phase A · Signed-In Chrome"
        case .macosDesktop: return lang == .zhHans ? "Phase B · macOS 桌面元素树" : "Phase B · macOS Desktop Cua"
        }
    }
}

public enum PipiBrowserSeatMode: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
    case signedInChromeSeat = "signed_in_chrome_seat"
    case isolatedProfile = "isolated_profile"

    public var id: String { rawValue }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .signedInChromeSeat:
            return lang == .zhHans ? "复用本机已登录 Chrome（每 Agent 独立 Seat/Tab）" : "Signed-In Chrome (Per-Agent Seat/Tab)"
        case .isolatedProfile:
            return lang == .zhHans ? "独立隔离 Chrome Profile" : "Isolated Chrome Profile"
        }
    }
}

public enum PipiComputerUseActionType: String, Codable, CaseIterable, Sendable, Equatable {
    case snapshot
    case navigate
    case click
    case doubleClick = "double_click"
    case typeText = "type_text"
    case pressKey = "press_key"
    case scroll
    case drag
    case submitForm = "submit_form"
    case focusWindow = "focus_window"

    public var isReadOnly: Bool {
        self == .snapshot || self == .scroll
    }

    public var isExternalSubmitRisk: Bool {
        self == .submitForm
    }
}

public enum PipiComputerUseLaneKind: String, Codable, CaseIterable, Sendable, Equatable {
    case desktopScreen = "desktop_screen"
    case agentBrowser = "agent_browser"

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .desktopScreen: return lang == .zhHans ? "桌面全局单车道" : "Global Desktop Screen Lane"
        case .agentBrowser: return lang == .zhHans ? "Agent 独立浏览器车道" : "Per-Agent Browser Lane"
        }
    }
}

public enum PipiComputerUseLaneState: String, Codable, CaseIterable, Sendable, Equatable {
    case idle
    case active
    case yieldedToHuman = "yielded_to_human"
    case blockedUnknownOutcome = "blocked_unknown_outcome"

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .idle: return lang == .zhHans ? "空闲" : "Idle"
        case .active: return lang == .zhHans ? "操控中" : "Active"
        case .yieldedToHuman: return lang == .zhHans ? "已礼让人类焦点" : "Yielded to Human"
        case .blockedUnknownOutcome: return lang == .zhHans ? "结果未知 · 已安全锁定" : "Locked (Unknown Outcome)"
        }
    }
}

public enum PipiWriteAheadJournalStatus: String, Codable, CaseIterable, Sendable, Equatable {
    case prepared
    case dispatched
    case committed
    case yieldedToHuman = "yielded_to_human"
    case blockedGuardrail = "blocked_guardrail"
    case unknownOutcome = "unknown_outcome"

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .prepared: return lang == .zhHans ? "已预写日志" : "Prepared"
        case .dispatched: return lang == .zhHans ? "已派发" : "Dispatched"
        case .committed: return lang == .zhHans ? "已完成" : "Committed"
        case .yieldedToHuman: return lang == .zhHans ? "礼让人类中止" : "Yielded to Human"
        case .blockedGuardrail: return lang == .zhHans ? "风控拦截" : "Blocked by Guardrail"
        case .unknownOutcome: return lang == .zhHans ? "结果未知（防重放）" : "Unknown Outcome (No Replay)"
        }
    }
}




