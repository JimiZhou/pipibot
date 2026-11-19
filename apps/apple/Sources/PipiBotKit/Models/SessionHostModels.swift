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

    private enum CodingKeys: String, CodingKey {
        case id, sessionId, eventSeq, question, detail, options, recommendedOptionId
        case status, chosenOptionId, userNote, createdAt, resolvedAt
        case pendingPrompt, pendingTarget
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
        pendingTarget: PipiExecutionTarget? = nil
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

    private enum CodingKeys: String, CodingKey {
        case text, attachments, targetOverride, personaId, activateTargetConversation, permissionOverride, isApprovalResume
    }

    public init(
        text: String,
        attachments: [PipiChatAttachment] = [],
        targetOverride: PipiExecutionTarget? = nil,
        personaId: String? = nil,
        activateTargetConversation: Bool = true,
        permissionOverride: PipiPermissionTier? = nil,
        isApprovalResume: Bool = false
    ) {
        self.text = text
        self.attachments = attachments
        self.targetOverride = targetOverride
        self.personaId = personaId
        self.activateTargetConversation = activateTargetConversation
        self.permissionOverride = permissionOverride
        self.isApprovalResume = isApprovalResume
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
