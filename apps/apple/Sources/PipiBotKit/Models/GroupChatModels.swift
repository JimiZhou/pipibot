import Foundation

// MARK: - Multi-Bot Group Chat & Swarm Mode Models

public enum PipiSwarmMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case swarm
    case relay
    case mentionOnly = "mention_only"

    public var id: String { rawValue }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .swarm: return lang == .zhHans ? "智能分工" : "Swarm"
        case .relay: return lang == .zhHans ? "顺序接力" : "Relay"
        case .mentionOnly: return lang == .zhHans ? "仅回应 @提及" : "@Mention Only"
        }
    }

    public func description(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .swarm:
            return lang == .zhHans
                ? "由主控智能体拆解目标并分派给成员并行协作，支持自动 @交接"
                : "Lead agent decomposes the goal and dispatches teammates in parallel with bounded handoffs"
        case .relay:
            return lang == .zhHans
                ? "成员按顺序依次接力输出，每位成员基于前一位的结论继续推进"
                : "Agents respond sequentially in order, each building on the previous reply"
        case .mentionOnly:
            return lang == .zhHans
                ? "仅被 @提及 的成员（或 @all）并行响应"
                : "Only @mentioned agents (or @all) respond in parallel"
        }
    }

    public var iconName: String {
        switch self {
        case .swarm: return "network"
        case .relay: return "arrow.triangle.branch"
        case .mentionOnly: return "at"
        }
    }
}

public struct PipiSwarmTaskAssignment: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable, Equatable {
        case queued
        case working
        case done
        case failed
    }

    public let id: String
    public var personaId: String
    public var taskTitle: String
    public var status: Status
    public var updatedAt: String
    public var waveIndex: Int?
    public var rolePreset: String?
    public var harnessLabel: String?
    public var worktreeBranch: String?
    public var dependsOn: [String]?

    private enum CodingKeys: String, CodingKey {
        case id, personaId, taskTitle, status, updatedAt
        case waveIndex, rolePreset, harnessLabel, worktreeBranch, dependsOn
    }

    public init(
        id: String = "assign_\(UUID().uuidString.prefix(8).lowercased())",
        personaId: String,
        taskTitle: String,
        status: Status = .queued,
        updatedAt: String = ISO8601DateFormatter().string(from: Date()),
        waveIndex: Int? = nil,
        rolePreset: String? = nil,
        harnessLabel: String? = nil,
        worktreeBranch: String? = nil,
        dependsOn: [String]? = nil
    ) {
        self.id = id
        self.personaId = personaId
        self.taskTitle = taskTitle
        self.status = status
        self.updatedAt = updatedAt
        self.waveIndex = waveIndex
        self.rolePreset = rolePreset
        self.harnessLabel = harnessLabel
        self.worktreeBranch = worktreeBranch
        self.dependsOn = dependsOn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? "assign_\(UUID().uuidString.prefix(8).lowercased())"
        self.personaId = try c.decode(String.self, forKey: .personaId)
        self.taskTitle = try c.decodeIfPresent(String.self, forKey: .taskTitle) ?? ""
        self.status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .queued
        self.updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        self.waveIndex = try c.decodeIfPresent(Int.self, forKey: .waveIndex)
        self.rolePreset = try c.decodeIfPresent(String.self, forKey: .rolePreset)
        self.harnessLabel = try c.decodeIfPresent(String.self, forKey: .harnessLabel)
        self.worktreeBranch = try c.decodeIfPresent(String.self, forKey: .worktreeBranch)
        self.dependsOn = try c.decodeIfPresent([String].self, forKey: .dependsOn)
    }
}

public struct PipiGroupTopic: Codable, Identifiable, Equatable, Sendable {
    public static let defaultTopicId = "topic_general"

    public let id: String
    public var title: String
    public var summary: String?
    public var isDefault: Bool
    public let createdAt: String
    public var updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, title, summary, isDefault, createdAt, updatedAt
    }

    public init(
        id: String = "topic_\(UUID().uuidString.prefix(8).lowercased())",
        title: String,
        summary: String? = nil,
        isDefault: Bool = false,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? "topic_\(UUID().uuidString.prefix(8).lowercased())"
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary)
        self.isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        self.updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    public func localizedTitle(_ lang: PipiResolvedLanguage) -> String {
        if isDefault {
            return lang == .zhHans ? "综合讨论" : "General"
        }
        return title
    }

    public static func makeDefault(_ lang: PipiResolvedLanguage = .zhHans) -> PipiGroupTopic {
        let nowIso = ISO8601DateFormatter().string(from: Date())
        return PipiGroupTopic(
            id: defaultTopicId,
            title: lang == .zhHans ? "综合讨论" : "General",
            summary: nil,
            isDefault: true,
            createdAt: nowIso,
            updatedAt: nowIso
        )
    }
}

public struct PipiGroupLongTask: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, CaseIterable, Sendable, Equatable {
        case active
        case paused
        case completed

        public func label(_ lang: PipiResolvedLanguage) -> String {
            switch self {
            case .active: return lang == .zhHans ? "进行中" : "Active"
            case .paused: return lang == .zhHans ? "已暂停" : "Paused"
            case .completed: return lang == .zhHans ? "已完成" : "Completed"
            }
        }
    }

    public let id: String
    public var title: String
    public var goal: String
    public var ownerPersonaId: String?
    public var schedule: PipiRoutineSchedule
    public var hour: Int
    public var minute: Int
    public var weekday: Int
    public var status: Status
    public var lastRunAt: String?
    public var lastSummary: String?
    public var topicId: String?
    public let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id, title, goal, ownerPersonaId, schedule, hour, minute, weekday
        case status, lastRunAt, lastSummary, topicId, createdAt
    }

    public init(
        id: String = "gtask_\(UUID().uuidString.prefix(8).lowercased())",
        title: String,
        goal: String,
        ownerPersonaId: String? = nil,
        schedule: PipiRoutineSchedule = .manual,
        hour: Int = 9,
        minute: Int = 0,
        weekday: Int = 2,
        status: Status = .active,
        lastRunAt: String? = nil,
        lastSummary: String? = nil,
        topicId: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.title = title
        self.goal = goal
        self.ownerPersonaId = ownerPersonaId
        self.schedule = schedule
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
        self.weekday = (1...7).contains(weekday) ? weekday : 2
        self.status = status
        self.lastRunAt = lastRunAt
        self.lastSummary = lastSummary
        self.topicId = topicId
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? "gtask_\(UUID().uuidString.prefix(8).lowercased())"
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? ""
        self.ownerPersonaId = try c.decodeIfPresent(String.self, forKey: .ownerPersonaId)
        self.schedule = try c.decodeIfPresent(PipiRoutineSchedule.self, forKey: .schedule) ?? .manual
        let h = try c.decodeIfPresent(Int.self, forKey: .hour) ?? 9
        let m = try c.decodeIfPresent(Int.self, forKey: .minute) ?? 0
        let w = try c.decodeIfPresent(Int.self, forKey: .weekday) ?? 2
        self.hour = min(23, max(0, h))
        self.minute = min(59, max(0, m))
        self.weekday = (1...7).contains(w) ? w : 2
        self.status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .active
        self.lastRunAt = try c.decodeIfPresent(String.self, forKey: .lastRunAt)
        self.lastSummary = try c.decodeIfPresent(String.self, forKey: .lastSummary)
        self.topicId = try c.decodeIfPresent(String.self, forKey: .topicId)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }

    public func scheduleBadge(_ lang: PipiResolvedLanguage) -> String {
        PipiBotRoutine(
            personaId: ownerPersonaId ?? "",
            title: title,
            prompt: goal,
            schedule: schedule,
            hour: hour,
            minute: minute,
            weekday: weekday
        ).scheduleBadge(lang)
    }
}

public struct PipiGroupDeliverable: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Identifiable, Sendable, Equatable {
        case summary
        case document
        case plan
        case code
        case file

        public var id: String { rawValue }

        public func label(_ lang: PipiResolvedLanguage) -> String {
            switch self {
            case .summary: return lang == .zhHans ? "总结" : "Summary"
            case .document: return lang == .zhHans ? "文档" : "Document"
            case .plan: return lang == .zhHans ? "方案" : "Plan"
            case .code: return lang == .zhHans ? "代码" : "Code"
            case .file: return lang == .zhHans ? "文件" : "File"
            }
        }

        public var iconName: String {
            switch self {
            case .summary: return "text.quote"
            case .document: return "doc.richtext"
            case .plan: return "list.bullet.clipboard"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .file: return "doc"
            }
        }
    }

    public let id: String
    public var title: String
    public var kind: Kind
    public var summary: String
    public var content: String
    public var producedByPersonaId: String?
    public var topicId: String?
    public var filePath: String?
    public let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id, title, kind, summary, content, producedByPersonaId, topicId, filePath, createdAt
    }

    public init(
        id: String = "deliv_\(UUID().uuidString.prefix(8).lowercased())",
        title: String,
        kind: Kind = .document,
        summary: String,
        content: String,
        producedByPersonaId: String? = nil,
        topicId: String? = nil,
        filePath: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.summary = summary
        self.content = content
        self.producedByPersonaId = producedByPersonaId
        self.topicId = topicId
        self.filePath = filePath
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? "deliv_\(UUID().uuidString.prefix(8).lowercased())"
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .document
        self.summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        self.content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.producedByPersonaId = try c.decodeIfPresent(String.self, forKey: .producedByPersonaId)
        self.topicId = try c.decodeIfPresent(String.self, forKey: .topicId)
        self.filePath = try c.decodeIfPresent(String.self, forKey: .filePath)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

public struct PipiGroupSkill: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var nameEn: String?
    public var instruction: String
    public var isEnabled: Bool
    public var isBuiltIn: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, nameEn, instruction, isEnabled, isBuiltIn
    }

    public init(
        id: String = "gskill_\(UUID().uuidString.prefix(8).lowercased())",
        name: String,
        nameEn: String? = nil,
        instruction: String,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.nameEn = nameEn
        self.instruction = instruction
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? "gskill_\(UUID().uuidString.prefix(8).lowercased())"
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.nameEn = try c.decodeIfPresent(String.self, forKey: .nameEn)
        self.instruction = try c.decodeIfPresent(String.self, forKey: .instruction) ?? ""
        self.isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.isBuiltIn = try c.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }

    public func localizedName(_ lang: PipiResolvedLanguage) -> String {
        if lang == .en, let nameEn, !nameEn.isEmpty {
            return nameEn
        }
        return name
    }

    public static let defaultSkills: [PipiGroupSkill] = [
        PipiGroupSkill(
            id: "gskill_multi_review",
            name: "多视角评审",
            nameEn: "Multi-Perspective Review",
            instruction: "从各自专业视角给出独立判断、潜在风险与可执行建议，避免重复其他成员已提出的观点。",
            isEnabled: true,
            isBuiltIn: true
        ),
        PipiGroupSkill(
            id: "gskill_doc_drafting",
            name: "方案与文档撰写",
            nameEn: "Spec & Doc Drafting",
            instruction: "优先使用结构化 Markdown 输出目标、方案对比、实施步骤与验收标准，便于直接沉淀为群交付物。",
            isEnabled: true,
            isBuiltIn: true
        ),
        PipiGroupSkill(
            id: "gskill_long_task",
            name: "长任务持续跟进",
            nameEn: "Long-Task Follow-Through",
            instruction: "推进长期任务时主动对照既有进展，补充阶段性结论并明确下一步负责成员与阻塞点。",
            isEnabled: true,
            isBuiltIn: true
        ),
        PipiGroupSkill(
            id: "gskill_meeting_notes",
            name: "会议纪要与行动项",
            nameEn: "Meeting Notes & Action Items",
            instruction: "在讨论收尾阶段自动提炼核心共识、待确认分歧与带负责人的行动项清单。",
            isEnabled: false,
            isBuiltIn: true
        )
    ]
}

public struct PipiGroupMemoryItem: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var content: String
    public var source: String?
    public var isPinned: Bool
    public let createdAt: String

    private enum CodingKeys: String, CodingKey {
        case id, content, source, isPinned, createdAt
    }

    public init(
        id: String = "gmem_\(UUID().uuidString.prefix(8).lowercased())",
        content: String,
        source: String? = nil,
        isPinned: Bool = false,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.content = content
        self.source = source
        self.isPinned = isPinned
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? "gmem_\(UUID().uuidString.prefix(8).lowercased())"
        self.content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.source = try c.decodeIfPresent(String.self, forKey: .source)
        self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }
}

public struct PipiGroupMessage: Codable, Identifiable, Equatable, Sendable {
    public enum SenderKind: Codable, Equatable, Sendable {
        case user
        case bot(personaId: String)
        case system
    }

    public let id: String
    public let senderKind: SenderKind
    public var content: String
    public let createdAt: String
    public var engineLabel: String?
    public var mentionedPersonaIds: [String]
    public var roleTag: String?
    public var isError: Bool
    public var topicId: String?

    private enum CodingKeys: String, CodingKey {
        case id, senderKind, content, createdAt, engineLabel, mentionedPersonaIds, roleTag, isError, topicId
    }

    public init(
        id: String = "gmsg_\(UUID().uuidString.prefix(8).lowercased())",
        senderKind: SenderKind,
        content: String,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        engineLabel: String? = nil,
        mentionedPersonaIds: [String] = [],
        roleTag: String? = nil,
        isError: Bool = false,
        topicId: String? = nil
    ) {
        self.id = id
        self.senderKind = senderKind
        self.content = content
        self.createdAt = createdAt
        self.engineLabel = engineLabel
        self.mentionedPersonaIds = mentionedPersonaIds
        self.roleTag = roleTag
        self.isError = isError
        self.topicId = topicId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? "gmsg_\(UUID().uuidString.prefix(8).lowercased())"
        self.senderKind = try c.decodeIfPresent(SenderKind.self, forKey: .senderKind) ?? .system
        self.content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        self.engineLabel = try c.decodeIfPresent(String.self, forKey: .engineLabel)
        self.mentionedPersonaIds = try c.decodeIfPresent([String].self, forKey: .mentionedPersonaIds) ?? []
        self.roleTag = try c.decodeIfPresent(String.self, forKey: .roleTag)
        self.isError = try c.decodeIfPresent(Bool.self, forKey: .isError) ?? false
        self.topicId = try c.decodeIfPresent(String.self, forKey: .topicId)
    }
}

public struct PipiGroupChat: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var participantPersonaIds: [String]
    public var leadPersonaId: String?
    public var swarmMode: PipiSwarmMode
    public var projectId: String?
    public var messages: [PipiGroupMessage]
    public var assignments: [PipiSwarmTaskAssignment]
    public var topics: [PipiGroupTopic]
    public var activeTopicId: String?
    public var longTasks: [PipiGroupLongTask]
    public var deliverables: [PipiGroupDeliverable]
    public var skills: [PipiGroupSkill]
    public var sharedMemories: [PipiGroupMemoryItem]
    /// Wave 3 (#06): Structured `team.md` collaboration protocol document & dynamic bot proposals.
    public var teamProtocolMarkdown: String?
    public var dynamicBotProposals: [PipiDynamicBotProposal]
    public var isPinned: Bool
    public var isArchived: Bool
    public let createdAt: String
    public var updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, title, participantPersonaIds, leadPersonaId, swarmMode, projectId
        case messages, assignments, topics, activeTopicId, longTasks, deliverables, skills, sharedMemories
        case teamProtocolMarkdown, dynamicBotProposals
        case isPinned, isArchived, createdAt, updatedAt
    }

    public init(
        id: String = "grp_\(UUID().uuidString.prefix(8).lowercased())",
        title: String,
        participantPersonaIds: [String],
        leadPersonaId: String? = nil,
        swarmMode: PipiSwarmMode = .swarm,
        projectId: String? = nil,
        messages: [PipiGroupMessage] = [],
        assignments: [PipiSwarmTaskAssignment] = [],
        topics: [PipiGroupTopic] = [PipiGroupTopic.makeDefault()],
        activeTopicId: String? = nil,
        longTasks: [PipiGroupLongTask] = [],
        deliverables: [PipiGroupDeliverable] = [],
        skills: [PipiGroupSkill] = PipiGroupSkill.defaultSkills,
        sharedMemories: [PipiGroupMemoryItem] = [],
        teamProtocolMarkdown: String? = nil,
        dynamicBotProposals: [PipiDynamicBotProposal] = [],
        isPinned: Bool = false,
        isArchived: Bool = false,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.title = title
        self.participantPersonaIds = participantPersonaIds
        self.leadPersonaId = leadPersonaId ?? participantPersonaIds.first
        self.swarmMode = swarmMode
        self.projectId = projectId
        self.messages = messages
        self.assignments = assignments
        var resolvedTopics = topics
        if !resolvedTopics.contains(where: { $0.isDefault }) {
            resolvedTopics.insert(PipiGroupTopic.makeDefault(), at: 0)
        }
        self.topics = resolvedTopics
        self.activeTopicId = activeTopicId
        self.longTasks = longTasks
        self.deliverables = deliverables
        self.skills = skills
        self.sharedMemories = sharedMemories
        self.teamProtocolMarkdown = teamProtocolMarkdown
        self.dynamicBotProposals = dynamicBotProposals
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.participantPersonaIds = try c.decodeIfPresent([String].self, forKey: .participantPersonaIds) ?? []
        self.leadPersonaId = try c.decodeIfPresent(String.self, forKey: .leadPersonaId) ?? self.participantPersonaIds.first
        self.swarmMode = try c.decodeIfPresent(PipiSwarmMode.self, forKey: .swarmMode) ?? .swarm
        self.projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        self.messages = try c.decodeIfPresent([PipiGroupMessage].self, forKey: .messages) ?? []
        self.assignments = try c.decodeIfPresent([PipiSwarmTaskAssignment].self, forKey: .assignments) ?? []
        var decodedTopics = try c.decodeIfPresent([PipiGroupTopic].self, forKey: .topics) ?? []
        if !decodedTopics.contains(where: { $0.isDefault }) {
            decodedTopics.insert(PipiGroupTopic.makeDefault(), at: 0)
        }
        self.topics = decodedTopics
        self.activeTopicId = try c.decodeIfPresent(String.self, forKey: .activeTopicId)
        self.longTasks = try c.decodeIfPresent([PipiGroupLongTask].self, forKey: .longTasks) ?? []
        self.deliverables = try c.decodeIfPresent([PipiGroupDeliverable].self, forKey: .deliverables) ?? []
        self.skills = try c.decodeIfPresent([PipiGroupSkill].self, forKey: .skills) ?? PipiGroupSkill.defaultSkills
        self.sharedMemories = try c.decodeIfPresent([PipiGroupMemoryItem].self, forKey: .sharedMemories) ?? []
        self.teamProtocolMarkdown = try c.decodeIfPresent(String.self, forKey: .teamProtocolMarkdown)
        self.dynamicBotProposals = try c.decodeIfPresent([PipiDynamicBotProposal].self, forKey: .dynamicBotProposals) ?? []
        self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.isArchived = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        self.updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    public var defaultTopic: PipiGroupTopic {
        topics.first(where: { $0.isDefault }) ?? PipiGroupTopic.makeDefault()
    }

    public var activeTopic: PipiGroupTopic {
        if let activeTopicId,
           let matched = topics.first(where: { $0.id == activeTopicId }) {
            return matched
        }
        return defaultTopic
    }

    /// Returns `nil` when the default General topic is active; otherwise returns the custom topic ID.
    public var effectiveActiveTopicId: String? {
        let current = activeTopic
        return current.isDefault ? nil : current.id
    }

    public func isDefaultTopicId(_ topicId: String?) -> Bool {
        guard let topicId else { return true }
        if topicId == PipiGroupTopic.defaultTopicId { return true }
        return topics.first(where: { $0.id == topicId })?.isDefault == true
    }

    public func messages(forTopic topicId: String?) -> [PipiGroupMessage] {
        if isDefaultTopicId(topicId) {
            return messages.filter { isDefaultTopicId($0.topicId) }
        }
        return messages.filter { $0.topicId == topicId }
    }

    public var activeTopicMessages: [PipiGroupMessage] {
        messages(forTopic: effectiveActiveTopicId)
    }
}
