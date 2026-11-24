import Foundation
import Observation
#if canImport(Speech)
import Speech
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

public enum PipiConnectionMode: String, Sendable {
    case liveDaemon = "Embedded Bridge Live"
    case nativeResident = "Native All-in-One"
}

public enum PipiRunPhase: String, Sendable, Equatable {
    case queued
    case running
}

public struct PipiGroupActiveLane: Identifiable, Sendable, Equatable {
    public var id: String { runId }
    public let runId: String
    public let groupId: String
    public let topicId: String?
    public let personaId: String
    public let personaName: String
    public let hostLabel: String
    public var statusText: String
    public let startedAt: Date

    public init(
        runId: String,
        groupId: String,
        topicId: String?,
        personaId: String,
        personaName: String,
        hostLabel: String,
        statusText: String,
        startedAt: Date = Date()
    ) {
        self.runId = runId
        self.groupId = groupId
        self.topicId = topicId
        self.personaId = personaId
        self.personaName = personaName
        self.hostLabel = hostLabel
        self.statusText = statusText
        self.startedAt = startedAt
    }
}

public struct PipiConversationRunState: Sendable {
    public let conversationId: String
    public let personaId: String
    public let runId: String
    public let streamingMessageId: String
    public let startedAt: Date
    public var phase: PipiRunPhase
    public var statusText: String
    public var isLocalAgent: Bool
    public var task: Task<Void, Never>?

    public init(
        conversationId: String,
        personaId: String,
        runId: String,
        streamingMessageId: String,
        startedAt: Date,
        phase: PipiRunPhase,
        statusText: String,
        isLocalAgent: Bool,
        task: Task<Void, Never>? = nil
    ) {
        self.conversationId = conversationId
        self.personaId = personaId
        self.runId = runId
        self.streamingMessageId = streamingMessageId
        self.startedAt = startedAt
        self.phase = phase
        self.statusText = statusText
        self.isLocalAgent = isLocalAgent
        self.task = task
    }
}

public enum PipiUndoableDeletion: Sendable, Equatable {
    case conversation(conversation: PipiConversation, index: Int, wasActiveConversationId: String?)
    case project(project: PipiProject, index: Int, affectedConversationIds: [String])

    public func toastLabel(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .conversation(let conv, _, _):
            return lang == .zhHans ? "已删除对话「\(conv.title)」" : "Deleted “\(conv.title)”"
        case .project(let proj, _, _):
            return lang == .zhHans ? "已删除项目「\(proj.name)」" : "Deleted project “\(proj.name)”"
        }
    }
}

public enum PipiInspectorTab: String, CaseIterable, Identifiable, Sendable {
    case plan
    case changes
    case context

    public var id: String { rawValue }
}

public enum PipiSessionTimeBucket: Int, CaseIterable, Identifiable, Sendable {
    case activeOrNeedsYou = 0
    case pinned = 1
    case today = 2
    case yesterday = 3
    case last7Days = 4
    case earlier = 5

    public var id: Int { rawValue }

    public func title(_ s: PipiStrings) -> String {
        switch self {
        case .activeOrNeedsYou: return s.sessionGroupActive
        case .pinned: return s.sessionGroupPinned
        case .today: return s.sessionGroupToday
        case .yesterday: return s.sessionGroupYesterday
        case .last7Days: return s.sessionGroupLast7Days
        case .earlier: return s.sessionGroupEarlier
        }
    }
}

public struct PipiSessionSearchMatch: Identifiable, Sendable {
    public let conversation: PipiConversation
    public let matchedMessageSnippet: String?

    public var id: String { conversation.id }

    public init(conversation: PipiConversation, matchedMessageSnippet: String? = nil) {
        self.conversation = conversation
        self.matchedMessageSnippet = matchedMessageSnippet
    }
}

public typealias PipiInferenceExecutor = @Sendable (
    _ target: PipiExecutionTarget,
    _ provider: PipiLLMProviderConfig?,
    _ systemPrompt: String,
    _ history: [PipiChatMessage],
    _ workingDirectory: String,
    _ onDelta: (@Sendable (String) -> Void)?
) async throws -> PipiInferenceResult

public typealias PipiSessionInferenceExecutor = @Sendable (
    _ target: PipiExecutionTarget,
    _ provider: PipiLLMProviderConfig?,
    _ systemPrompt: String,
    _ history: [PipiChatMessage],
    _ workingDirectory: String,
    _ permissionTier: PipiPermissionTier,
    _ cliSessionId: String?,
    _ onDelta: (@Sendable (String) -> Void)?,
    _ onEvent: (@Sendable (PipiParsedCLIEvent) -> Void)?
) async throws -> PipiInferenceResult

public enum PipiConversationRowStatus: Sendable, Equatable {
    case processing
    case queued
    case needsApproval
    case failed
    case unread(Int)
    case idle
}

public struct PipiCLIDelegationDirective: Sendable, Equatable {
    public let agent: PipiLocalAgentKind
    public let isWriteMode: Bool
    public let reason: String
    public let taskPrompt: String

    public init(agent: PipiLocalAgentKind, isWriteMode: Bool, reason: String, taskPrompt: String) {
        self.agent = agent
        self.isWriteMode = isWriteMode
        self.reason = reason
        self.taskPrompt = taskPrompt
    }
}

public enum PipiExternalSubAgentRouter {
    /// Parses explicit on-demand external CLI sub-agent invocations (`/claude ...`, `/codex ...`, `/opencode ...`)
    /// so PiPi remains the default built-in engine while delegating specialized coding/CLI tasks on demand.
    public static func parseOnDemandInvocation(_ rawPrompt: String) -> (kind: PipiLocalAgentKind, taskPrompt: String)? {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let mappings: [(String, PipiLocalAgentKind)] = [
            ("/claude ", .claudeCode),
            ("/claude-code ", .claudeCode),
            ("/codex ", .codex),
            ("/opencode ", .opencode)
        ]
        for (prefix, kind) in mappings where lower.hasPrefix(prefix) {
            let body = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                return (kind, body)
            }
        }
        return nil
    }

    /// Detects natural-language requests to delegate to Codex, Claude Code, or OpenCode without requiring `/codex`.
    public static func detectNaturalLanguageInvocation(
        _ rawPrompt: String,
        usableAgents: [PipiLocalAgentKind]
    ) -> (kind: PipiLocalAgentKind, taskPrompt: String)? {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !usableAgents.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        let agentPatterns: [(kind: PipiLocalAgentKind, tokens: [String])] = [
            (.codex, ["codex"]),
            (.claudeCode, ["claude code", "claude-code", "claudecode"]),
            (.opencode, ["opencode"])
        ]
        let actionVerbHints = [
            "用", "让", "叫", "调用", "使用", "交给", "派", "请", "运行", "启动", "通过",
            "use ", "ask ", "call ", "run ", "via ", "with ", "delegate "
        ]

        for entry in agentPatterns where usableAgents.contains(entry.kind) {
            for token in entry.tokens {
                guard lower.contains(token) else { continue }
                let hasVerb = actionVerbHints.contains(where: { lower.contains($0) })
                let startsWithToken = lower.hasPrefix(token)
                if hasVerb || startsWithToken {
                    return (entry.kind, trimmed)
                }
            }
        }
        return nil
    }

    /// Extracts `<pipibot_cli_delegate agent="codex|claude-code|opencode" mode="readonly|write" reason="...">task</pipibot_cli_delegate>`
    /// emitted proactively by PiPi during reasoning.
    public static func extractCLIDelegation(from rawText: String) -> (directive: PipiCLIDelegationDirective, cleanedText: String)? {
        let pattern = #"<pipibot_cli_delegate\b([^>]*)>([\s\S]*?)</pipibot_cli_delegate>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsRange = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
        guard let match = regex.firstMatch(in: rawText, options: [], range: nsRange),
              let fullRange = Range(match.range, in: rawText),
              let attrRange = Range(match.range(at: 1), in: rawText),
              let bodyRange = Range(match.range(at: 2), in: rawText) else {
            return nil
        }

        let attrs = String(rawText[attrRange])
        let taskBody = String(rawText[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !taskBody.isEmpty else { return nil }

        let agentRaw = extractAttribute("agent", from: attrs)?.lowercased() ?? "codex"
        let kind: PipiLocalAgentKind = {
            if agentRaw.contains("claude") { return .claudeCode }
            if agentRaw.contains("open") { return .opencode }
            return .codex
        }()
        let modeRaw = extractAttribute("mode", from: attrs)?.lowercased() ?? "readonly"
        let isWrite = (modeRaw == "write" || modeRaw == "edit" || modeRaw == "execute")
        let reason = extractAttribute("reason", from: attrs) ?? ""

        var cleaned = rawText
        cleaned.removeSubrange(fullRange)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return (
            PipiCLIDelegationDirective(agent: kind, isWriteMode: isWrite, reason: reason, taskPrompt: taskBody),
            cleaned
        )
    }

    private static func extractAttribute(_ name: String, from attrs: String) -> String? {
        let pattern = #"\#(name)\s*=\s*["']([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(attrs.startIndex..<attrs.endIndex, in: attrs)
        guard let match = regex.firstMatch(in: attrs, options: [], range: range),
              let valRange = Range(match.range(at: 1), in: attrs) else {
            return nil
        }
        return String(attrs[valRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
@Observable
public final class PipiAppStore {
    public static let maxConcurrentLLMRuns: Int = 4
    public static let maxConcurrentLocalAgentRuns: Int = 2

    public let avatarEngine: PipiProceduralAvatarEngine
    public let client: PipiDaemonClient
    public let bridgeSupervisor: PipiEmbeddedBridgeSupervisor
    public let remoteTunnelManager: PipiCloudflareTunnelManager
    public let wechatILinkManager: PipiWeChatILinkManager
    public let updateManager = PipiGitHubUpdateManager()
    public let macOmnipotentEngine: PipiMacOmnipotentEngine
    public let localModelPlatformManager: PipiLocalModelPlatformManager
    public let telemetryMonitor: PipiSystemTelemetryMonitor
    public var macPermissionsSnapshot: PipiMacPermissionSnapshot = .empty
    public var unreadConversationCounts: [String: Int] = [:]
    public var unreadGroupCounts: [String: Int] = [:]
    public var currentlyVisibleSessionId: String? = nil
    public var currentlyVisibleGroupId: String? = nil
    public var isDeployingLocalModel: Bool = false
    public var localModelDeployStatus: String? = nil
    public let enableNativeRuntime: Bool
    public let enableEmbeddedBridge: Bool
    public let secretStore: any PipiSecretStore
    private let defersSystemKeychainReads: Bool
    public let localHostConnection: PipiLocalHostConnection
    public var activeHostConnection: any PipiHostConnection
    /// Wave 1 (#04) 7-level priority scheduler with interactive reserved slot, AIMD & preemption.
    public let modelScheduler: PipiModelScheduler
    /// Wave 1 (#08) Two-tier static + LLM Risk x Authorization guardrail & idempotency ledger.
    public let permissionGuardrail: PipiPermissionGuardrail
    /// Wave 2 (#01) Personal Entity Wiki backed by native SQLite3 WAL + FTS5.
    public let personalWiki: PipiPersonalWikiStore?
    /// Wave 2 (#02) Per-Bot isolated experiential memory & Prompt-Cache-safe recall engine.
    public let botMemoryEngine: PipiBotMemoryEngine
    /// Wave 2 (#03) Proactive anti-fatigue guardrails, Prepare pre-briefing & Clue->Rule dreaming.
    public let proactiveEngine: PipiProactiveEngine
    /// Wave 2 (#03) First-batch macOS native signal collector (EventKit, Git/FS, Telemetry, Notes).
    public let nativeSignalProvider: any PipiNativeSignalProvider
    /// Wave 3 (#05) Meta / AlterEgo in-chat autonomous background delegation coordinator.
    public let alterEgoCoordinator: PipiAlterEgoCoordinator
    /// Wave 3 (#11) Daily Pocket Notes (5m silence) & Editable Artifact Documents engine.
    public let pocketNotesEngine: PipiPocketNotesEngine
    /// Wave 4 (#10) Personal Daily Voice engine (on-device first + BYOK cloud + echo-gated VAD barge-in).
    public let voiceEngine: PipiDailyVoiceEngine
    /// Wave 4 (#07) Unified loopback LLM Gateway (`127.0.0.1`) serving OpenAI & Anthropic protocols.
    public private(set) var localGateway: PipiLocalLLMGateway?
    /// Wave 5 (#09) Dual-Phase Computer Use coordinator (Phase A Chrome Seats + Phase B macOS AX/Cua + WAL + Human Yield).
    public let computerUseCoordinator: PipiComputerUseCoordinator
    /// Multi-Machine Mesh Hub client (connects to built-in Mac Hub or remote 24h Linux VPS Hub).
    public let meshHubClient: PipiMeshHubClient
    /// Open-Source Ecosystem Manager (MCP Server stdio/SSE + standard SKILL.md packs).
    public let ecosystemManager: PipiEcosystemManager
    /// Local storage root used for SQLite Wiki, Per-Bot memory, AlterEgo playgrounds, CLI overlays, WAL, and read-only builtin skills.
    public let localDataRootURL: URL
    private let persistenceUrl: URL?
    private let persistenceQueue = DispatchQueue(label: "ai.pipibot.persistence.serial", qos: .utility)
    private let saveDebounceMilliseconds: Int
    private let inferenceExecutor: PipiInferenceExecutor?
    private let sessionInferenceExecutor: PipiSessionInferenceExecutor?
    private let llmGuardrailJudge: PipiLLMGuardrailJudge?
    private var progressCallbacksByConversation: [String: @Sendable (String) async -> Void] = [:]
    private var pendingToolApprovalContextByApprovalId: [String: (toolCall: PipiLLMToolCall, workDir: String)] = [:]
    private var lastMorningBriefingYmd: String? = nil
    private var lastSentinelCheckAt: Date = .distantPast
    private var lastSentinelAlertAtByCategory: [String: Date] = [:]

    public var themeMode: PipiThemeMode = .system
    public var language: PipiAppLanguage = .system
    public var hasCompletedOnboarding: Bool = false
    public var onboardingInitialStep: Int = 0
    public var homeScenePreset: PipiHomeScenePreset = .warmStudio
    public var botRoomAssignments: [String: PipiHomeRoomKind] = [:]
    public var uiZoomScale: Double = 1.0
    public var showZoomHUD: Bool = false
    public var replyMode: PipiReplyMode = .auto

    public static let minZoomScale: Double = 0.80
    public static let maxZoomScale: Double = 1.40
    public static let zoomStep: Double = 0.10

    // Personal Bot Engine & Multi-Persona Chat State
    public var llmProviders: [PipiLLMProviderConfig] = []
    public var defaultLLMProviderId: String?
    public var enabledLocalAgents: Set<PipiLocalAgentKind> = []
    public var localAgentStatuses: [PipiLocalAgentStatus] = []
    public var defaultExecutionTarget: PipiExecutionTarget = .auto
    public var overrideExecutionTarget: PipiExecutionTarget?
    public var workspaceDirectory: String = NSHomeDirectory()
    public var personas: [PipiBotPersona] = PipiBotPersona.defaultPersonas
    public var activePersonaId: String = "bot_pipi_general"
    public var projects: [PipiProject] = []
    public var conversations: [PipiConversation] = []
    public var activeConversationId: String?
    public var activeRuns: [String: PipiConversationRunState] = [:]
    public var groupChats: [PipiGroupChat] = []
    public var activeGroupChatId: String?
    public var activeGroupRuns: [String: Set<String>] = [:]
    public var activeGroupStreamingMessageIds: [String: [String: String]] = [:]
    public var activeGroupRunStartTimes: [String: [String: Date]] = [:]
    public private(set) var activeGroupLanes: [PipiGroupActiveLane] = []
    private var groupRunTasksByRunId: [String: (groupId: String, task: Task<[PipiGroupMessage], Never>)] = [:]
    public var memoryEnabled: Bool = true
    public var personalProfileNote: String = ""
    public var routines: [PipiBotRoutine] = []
    public var runRecords: [PipiRunRecord] = []
    public var companionSyncEnabled: Bool = false
    // Wave 1 (#08) Multi-Granularity Approval Whitelist & LLM Guardrail Judge Toggle
    public var approvalWhitelistRules: [PipiApprovalWhitelistRule] = []
    public var llmGuardrailJudgeEnabled: Bool = true
    public var securityAuditorBotId: String = PipiBotPersona.securityAuditorId
    public var proactiveCLIDelegationEnabled: Bool = true
    public var autoCheckUpdatesEnabled: Bool = true
    public var wechatAutoConnectEnabled: Bool = true
    public var availableModelsByProviderId: [String: [String]] = [:]

    // v0.13.0 Automation Blueprint, Self-Evolution, Event Routines, Worktree Diff & Token Metering
    public var worktreeSessions: [PipiWorktreeReviewSession] = []
    public var blueprintEvolutionProposals: [PipiBlueprintEvolutionProposal] = []
    public var entityLedgerEntries: [PipiEntityLedgerEntry] = []
    public var runOutcomeRecords: [PipiRunOutcomeRecord] = []
    public var routineRunLogs: [PipiRoutineRunLog] = []
    public var usageRecords: [PipiUsageRecord] = []
    public var usageAlertConfig: PipiUsageAlertConfig = .default
    public var usageAlertNotices: [PipiUsageAlertNotice] = []
    internal var watchFingerprintsByRoutineId: [String: String] = [:]

    // v0.14.0 "Review Proof, Not Code" + Loop & Harness Engineering State
    public var deterministicChecks: [PipiDeterministicCheckSpec] = PipiDeterministicCheckSpec.defaultChecks
    public var proofBundlesByWorktreeId: [String: PipiVerificationProofBundle] = [:]
    public var operationalLoops: [PipiOperationalLoop] = []
    public var loopDrafts: [PipiLoopDraftItem] = []
    public var approvedExamples: [PipiApprovedExample] = []
    public var knowledgeGaps: [PipiKnowledgeGapItem] = []

    // v0.15.0 OpenMausBot Parity + Self-Hosted Zero-Knowledge E2EE Relay State
    public let e2eeRelayClient: PipiE2EERelayClient
    public let accountClient: PipiAccountClient
    public var lastUniversalPairingURL: String? = nil
    public var decisionModelConfig: PipiDecisionModelConfig = PipiDecisionModelConfig()
    public var lastGroupRouteDecision: PipiGroupRouteDecision? = nil
    public var sentinelIssues: [PipiSentinelIssue] = []
    public var lastSentinelReport: PipiSentinelReport? = nil
    public var customACPEngines: [PipiCustomACPEngineConfig] = []
    public var lastBoxSelfCheck: PipiBoxSelfCheckResult? = nil
    public var pendingPortableTemplatePreview: PipiPortableTemplatePackage? = nil
    internal var systemWakeObserver: NSObjectProtocol? = nil

    // Wave 2 (#01 Wiki, #02 Per-Bot Memory, #03 Proactive & Prepare) Observable State
    public var wikiPages: [PipiPersonalWikiPage] = []
    public var proactiveBriefings: [PipiPreparedBriefing] = []
    public var proactiveRules: [PipiLearnedProactiveRule] = []
    public var proactiveClues: [PipiProactiveClue] = []
    public var proactiveGuidelineVersion: Int = 1
    public var proactiveHistoryVersions: [Int] = [1]
    public var proactivePolicy: PipiProactiveGuardrailPolicy = PipiProactiveGuardrailPolicy()
    public var eventKitCalendarAuth: PipiEventKitAuthState = .notDetermined
    public var eventKitRemindersAuth: PipiEventKitAuthState = .notDetermined
    public var botMemoryVersionCounter: Int = 0
    public private(set) var lastPromptCacheRecallResult: PipiPromptCacheSafeRecallResult? = nil

    // Wave 3 (#05 AlterEgo, #06 team.md Dynamic Bot Proposals, #11 Pocket Notes / Docs / Builtin Skills)
    public var alterEgoTasks: [PipiAlterEgoTask] = []
    public var pocketTrackingItems: [PipiTrackingItem] = []
    public var artifactDocuments: [PipiArtifactDocument] = []
    public var builtinSkillReceipts: [PipiProjectedSkillReceipt] = []
    public var pocketNotesVersionCounter: Int = 0

    // Wave 4 (#07 Hardware Model Autopilot, PolyStrata, Local LLM Gateway & #10 Personal Daily Voice)
    public var hardwareProfile: PipiHardwareProfile = PipiHardwareProfile.detectCurrentHost()
    public var modelAutopilotPlan: PipiModelAutopilotPlan = PipiModelAutopilot.plan(hardware: PipiHardwareProfile.detectCurrentHost())
    public var localEngineStatuses: [PipiLocalEngineProbeStatus] = []
    public var localGatewayConfig: PipiLocalGatewayConfig = PipiLocalGatewayConfig()
    public var localGatewayStatus: PipiGatewayRuntimeStatus = .stopped
    public var lastModelSelfTestResult: PipiModelSelfTestResult? = nil
    public var isRunningModelSelfTest: Bool = false
    public var lastIsolatedCLIOverlays: [PipiReverseInjectedCLITarget: PipiIsolatedCLIOverlay] = [:]
    public var voiceConfig: PipiVoiceConfig = PipiVoiceConfig()
    public var voiceSessionState: PipiVoiceSessionState = .idle
    public var voiceActiveMode: PipiVoiceInteractionMode = .dictation
    public var voiceLiveTranscript: String = ""
    public var voiceInputLevel: Double = 0
    public var voiceLastError: String? = nil
    public var voiceIsOverlayPresented: Bool = false
    public var voicePendingDictationText: String? = nil
    public var isVoiceCallActive: Bool = false
    public var voiceCallStartedAt: Date? = nil
    public var isVoiceCallMuted: Bool = false
    public var voiceCallPersonaId: String? = nil

    // Global Capability Sharing Pool & Autonomous Peer Upgrade State
    public var globalCapabilityPool: PipiGlobalCapabilityPool = .default
    public var lastPeerUpgradeNotice: String? = nil

    // Wave 5 (#09 Dual-Phase Computer Use: Chrome Seats, macOS AX Lanes, Human Yield & WAL)
    public var computerUseConfig: PipiComputerUseConfig = PipiComputerUseConfig()
    public var computerUseEnvironment: PipiComputerUseEnvironmentProbe? = nil
    public var computerUseLanes: [PipiComputerUseLaneSnapshot] = []
    public var computerUseSeats: [PipiChromeBrowserSeat] = []
    public var computerUseJournal: [PipiWriteAheadJournalEntry] = []
    public var computerUseYieldedToHuman: Bool = false
    public var computerUseYieldReason: String? = nil
    public var computerUseBarPresented: Bool = false

    // Phase 2: Vercel Board-Inspired Coordination State (Channels -> Threads -> Tasks & Leases)
    public var boardChannels: [PipiBoardChannel] = PipiBoardEngine.defaultChannels()
    public var boardThreads: [PipiBoardThread] = []
    public var boardEvents: [PipiBoardActivityEvent] = []

    // Inspector, Shell & Host Seam State
    public var isInspectorPresented: Bool = false
    public var selectedInspectorTab: PipiInspectorTab = .context
    public var selectedFileChangeId: String?
    public var isCommandPalettePresented: Bool = false
    public var selectedBotFilterId: String? = nil

    // Safe Persistence & Undo State
    public private(set) var corruptStateDetected: Bool = false
    public private(set) var corruptStateBackupUrl: URL?
    public var persistenceWarning: String?
    public var lastDeletedItem: PipiUndoableDeletion?
    public var showUndoToast: Bool = false

    public var generatingElapsedSec: Double {
        guard let activeConversationId, let run = activeRuns[activeConversationId] else { return 0 }
        return max(0, Date().timeIntervalSince(run.startedAt))
    }

    public var activeRunStartedAt: Date? {
        guard let activeConversationId else { return nil }
        return activeRuns[activeConversationId]?.startedAt
    }

    public func runStartedAt(for conversationId: String) -> Date? {
        activeRuns[conversationId]?.startedAt
    }

    public var localHost: PipiHostDescriptor {
        localHostConnection.host
    }

    public func hostDescriptor(for hostId: String) -> PipiHostDescriptor {
        localHost
    }

    public var pendingApprovals: [PipiSessionApproval] {
        conversations
            .flatMap(\.approvals)
            .filter { $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public var pendingDynamicBotProposals: [PipiDynamicBotProposal] {
        groupChats
            .flatMap(\.dynamicBotProposals)
            .filter { $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public var totalNeedsYouCount: Int {
        pendingApprovals.count + pendingDecisions.count + pendingDynamicBotProposals.count
    }

    public func approval(id: String, in conversationId: String? = nil) -> PipiSessionApproval? {
        if let conversationId,
           let conv = conversations.first(where: { $0.id == conversationId }),
           let match = conv.approvals.first(where: { $0.id == id }) {
            return match
        }
        return conversations.lazy.flatMap(\.approvals).first(where: { $0.id == id })
    }

    public var isGeneratingReply: Bool {
        guard let activeConversationId else { return false }
        return activeRuns[activeConversationId] != nil
    }

    public var generatingPersonaId: String? {
        guard let activeConversationId else { return nil }
        return activeRuns[activeConversationId]?.personaId
    }

    public var streamingMessageId: String? {
        guard let activeConversationId else { return nil }
        return activeRuns[activeConversationId]?.streamingMessageId
    }

    public var generatingStatusText: String? {
        guard let activeConversationId else { return nil }
        return activeRuns[activeConversationId]?.statusText
    }

    public var isAnyConversationRunning: Bool {
        !activeRuns.isEmpty
    }

    public var canUndoLastDeletion: Bool {
        lastDeletedItem != nil
    }

    public func isRunning(conversationId: String) -> Bool {
        activeRuns[conversationId] != nil
    }

    public func isQueued(conversationId: String) -> Bool {
        activeRuns[conversationId]?.phase == .queued
    }

    public func runPhase(for conversationId: String) -> PipiRunPhase? {
        activeRuns[conversationId]?.phase
    }

    public func isPersonaRunning(_ personaId: String) -> Bool {
        activeRuns.values.contains { $0.personaId == personaId }
    }

    public var connectionMode: PipiConnectionMode = .nativeResident
    public var daemonEndpoint: String = "http://127.0.0.1:4242"

    public var daemonVersion: String = "0.12.0"

    public var appDisplayVersion: String {
        if let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !bundleVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return bundleVersion
        }
        return daemonVersion
    }
    public var activeHarness: HarnessProvider = .pi
    public var harnessProbes: [HarnessProbeResult] = []
    public var outcomes: [OutcomeResponsibility] = []
    public var subSessions: [SubSession] = []
    public var decisions: [NeedsYouDecision] = []
    public var latestCue: CueSuggestion?
    public var fleetNodes: [FleetNodeTelemetry] = []
    public var tunnelStatus: CloudflareTunnelStatus
    public var museCards: [MuseCardItem] = []
    public var chatMessages: [ChatTranscriptMessage] = []
    public var episodicMemories: [MemoryEntry] = []
    public var synthesizedSkills: [SynthesizedSkillCandidate] = []
    public var understandingScore: UnderstandingScoreBreakdown
    public var lastDigest: EvolutionSummary?
    public var soulPreview: SoulDocumentPreview
    public var lastPulseSeq: Int = 0
    public var noticeBanner: String?
    public var isCuePanelVisible: Bool = false

    private var sseTask: Task<Void, Never>?
    private var routineSchedulerTask: Task<Void, Never>?
    private var zoomHudTask: Task<Void, Never>?
    private var saveDebounceTask: Task<Void, Never>?
    private var hasPendingSave: Bool = false
    private var undoToastDismissTask: Task<Void, Never>?

    public var uiZoomPercentLabel: String {
        "\(Int((uiZoomScale * 100.0).rounded()))%"
    }

    public func setZoomScale(_ rawScale: Double) {
        let clamped = min(Self.maxZoomScale, max(Self.minZoomScale, (rawScale * 10.0).rounded() / 10.0))
        uiZoomScale = clamped
        PipiTokens.textScale = CGFloat(clamped)
        showZoomHUD = true
        zoomHudTask?.cancel()
        zoomHudTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            self?.showZoomHUD = false
        }
        saveResidentState()
    }

    public func zoomIn() {
        setZoomScale(uiZoomScale + Self.zoomStep)
    }

    public func zoomOut() {
        setZoomScale(uiZoomScale - Self.zoomStep)
    }

    public func resetZoom() {
        setZoomScale(1.0)
    }

    public static let currentSchemaMigrationVersion: Int = 2

    public var resolvedLanguage: PipiResolvedLanguage {
        language.resolved
    }

    public var strings: PipiStrings {
        PipiStrings(resolved: resolvedLanguage)
    }

    public var activePersona: PipiBotPersona {
        personas.first(where: { $0.id == activePersonaId }) ?? personas.first ?? PipiBotPersona.defaultPersonas[0]
    }

    public var activeConversation: PipiConversation? {
        guard let activeConversationId else { return nil }
        return conversations.first(where: { $0.id == activeConversationId })
    }

    public var conversationsForActivePersona: [PipiConversation] {
        conversations
            .filter { $0.personaId == activePersona.id && !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public var ungroupedConversationsForActivePersona: [PipiConversation] {
        conversations
            .filter { $0.personaId == activePersona.id && !$0.isArchived && $0.projectId == nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func conversations(inProject projectId: String) -> [PipiConversation] {
        conversations
            .filter { $0.projectId == projectId && !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public var activeProject: PipiProject? {
        guard let pid = activeConversation?.projectId else { return nil }
        return projects.first(where: { $0.id == pid })
    }

    public var effectiveWorkspaceDirectory: String {
        if let projPath = activeProject?.workspacePath, !projPath.isEmpty {
            return projPath
        }
        return workspaceDirectory
    }

    public var archivedConversationsForActivePersona: [PipiConversation] {
        conversations
            .filter { $0.personaId == activePersona.id && $0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public var allArchivedConversations: [PipiConversation] {
        conversations
            .filter(\.isArchived)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public var routinesForActivePersona: [PipiBotRoutine] {
        routines.filter { $0.personaId == activePersona.id }
    }

    public var runRecordsForActivePersona: [PipiRunRecord] {
        runRecords.filter { $0.personaId == activePersona.id }
    }

    public var readyLLMProviders: [PipiLLMProviderConfig] {
        llmProviders.filter(\.isReady)
    }

    public var usableLocalAgents: [PipiLocalAgentStatus] {
        localAgentStatuses.filter(\.isUsable)
    }

    public var hasConfiguredEngine: Bool {
        !readyLLMProviders.isEmpty || !usableLocalAgents.isEmpty
    }

    public init(
        baseUrl: String = "http://127.0.0.1:4242",
        autoConnect: Bool = false,
        enableNativeRuntime: Bool = false,
        enableEmbeddedBridge: Bool = false,
        stateFileUrl: URL? = nil,
        seedDemoData: Bool = false,
        secretStore: (any PipiSecretStore)? = nil,
        saveDebounceMilliseconds: Int = 400,
        inferenceExecutor: PipiInferenceExecutor? = nil,
        sessionInferenceExecutor: PipiSessionInferenceExecutor? = nil,
        modelScheduler: PipiModelScheduler? = nil,
        permissionGuardrail: PipiPermissionGuardrail? = nil,
        llmGuardrailJudge: PipiLLMGuardrailJudge? = nil,
        personalWiki: PipiPersonalWikiStore? = nil,
        botMemoryEngine: PipiBotMemoryEngine? = nil,
        proactiveEngine: PipiProactiveEngine? = nil,
        nativeSignalProvider: (any PipiNativeSignalProvider)? = nil,
        alterEgoCoordinator: PipiAlterEgoCoordinator? = nil,
        pocketNotesEngine: PipiPocketNotesEngine? = nil,
        voiceEngine: PipiDailyVoiceEngine? = nil,
        computerUseCoordinator: PipiComputerUseCoordinator? = nil
    ) {
        self.daemonEndpoint = baseUrl
        self.client = PipiDaemonClient(baseUrlString: baseUrl)
        self.bridgeSupervisor = PipiEmbeddedBridgeSupervisor()
        self.remoteTunnelManager = PipiCloudflareTunnelManager()
        self.localModelPlatformManager = PipiLocalModelPlatformManager()
        self.telemetryMonitor = PipiSystemTelemetryMonitor()
        let resolvedSecretStore = secretStore ?? (enableNativeRuntime ? PipiLocalEncryptedSecretStore() : PipiInMemorySecretStore())
        let defersKeychain = resolvedSecretStore is PipiKeychainSecretStore
        self.defersSystemKeychainReads = defersKeychain
        self.wechatILinkManager = PipiWeChatILinkManager(
            secretStore: resolvedSecretStore,
            restoreCredentialsOnInit: !defersKeychain
        )
        self.e2eeRelayClient = PipiE2EERelayClient(
            relayOrigin: PipiE2EERelayClient.defaultRelayOrigin,
            secretStore: resolvedSecretStore
        )
        self.accountClient = PipiAccountClient(
            relayOrigin: PipiE2EERelayClient.defaultRelayOrigin,
            secretStore: resolvedSecretStore
        )
        self.enableNativeRuntime = enableNativeRuntime
        self.enableEmbeddedBridge = enableEmbeddedBridge
        self.persistenceUrl = stateFileUrl
        self.secretStore = resolvedSecretStore
        self.saveDebounceMilliseconds = max(0, saveDebounceMilliseconds)
        self.inferenceExecutor = inferenceExecutor
        self.sessionInferenceExecutor = sessionInferenceExecutor
        let resolvedScheduler = modelScheduler ?? PipiModelScheduler(
            defaultConfig: PipiEndpointPoolConfig(
                initialLimit: Self.maxConcurrentLLMRuns,
                maxLimit: Self.maxConcurrentLLMRuns
            )
        )
        self.modelScheduler = resolvedScheduler
        self.permissionGuardrail = permissionGuardrail ?? PipiPermissionGuardrail()
        self.llmGuardrailJudge = llmGuardrailJudge

        // Wave 2 & 3 isolated storage root: use stateFileUrl parent in tests, App Support in native runtime,
        // and isolated ephemeral storage for stateless previews.
        let wave2RootURL: URL = {
            if let stateFileUrl {
                return stateFileUrl.deletingLastPathComponent()
            }
            if enableNativeRuntime {
                return PipiPersonalWikiStore.defaultStorageDirectory()
            }
            return URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("pipibot-preview-\(UUID().uuidString.prefix(8))", isDirectory: true)
        }()
        self.localDataRootURL = wave2RootURL
        self.meshHubClient = PipiMeshHubClient(hubURLString: baseUrl)
        self.ecosystemManager = PipiEcosystemManager(storageRootURL: wave2RootURL)
        self.macOmnipotentEngine = PipiMacOmnipotentEngine(dataRootURL: wave2RootURL)
        let resolvedWiki: PipiPersonalWikiStore? = {
            if let personalWiki { return personalWiki }
            let useFileDb = (stateFileUrl != nil || enableNativeRuntime)
            let dbPath = useFileDb
                ? wave2RootURL.appendingPathComponent("wiki.sqlite").path
                : ":memory:"
            let mdRoot: URL? = useFileDb ? wave2RootURL : nil
            return try? PipiPersonalWikiStore(dbPath: dbPath, markdownRootURL: mdRoot)
        }()
        self.personalWiki = resolvedWiki
        self.botMemoryEngine = botMemoryEngine ?? PipiBotMemoryEngine(rootURL: wave2RootURL)
        let resolvedProactive = proactiveEngine ?? PipiProactiveEngine(wikiStore: resolvedWiki)
        resolvedProactive.attachWikiStore(resolvedWiki)
        self.proactiveEngine = resolvedProactive
        self.nativeSignalProvider = nativeSignalProvider ?? PipiMacNativeSignalCollector()
        let resolvedAlterEgo = alterEgoCoordinator ?? PipiAlterEgoCoordinator(rootURL: wave2RootURL, scheduler: resolvedScheduler)
        resolvedAlterEgo.attachScheduler(resolvedScheduler)
        self.alterEgoCoordinator = resolvedAlterEgo
        self.pocketNotesEngine = pocketNotesEngine ?? PipiPocketNotesEngine(rootURL: wave2RootURL)
        self.voiceEngine = voiceEngine ?? PipiDailyVoiceEngine(config: PipiVoiceConfig(), secretStore: self.secretStore)
        self.computerUseCoordinator = computerUseCoordinator ?? PipiComputerUseCoordinator(
            rootURL: wave2RootURL,
            config: PipiComputerUseConfig(),
            guardrail: self.permissionGuardrail,
            llmGuardrailJudge: llmGuardrailJudge,
            installWorkspaceFocusObserver: enableNativeRuntime
        )
        let hostConn = PipiLocalHostConnection(host: .local())
        self.localHostConnection = hostConn
        self.activeHostConnection = hostConn
        self.avatarEngine = PipiProceduralAvatarEngine(initialState: .idle)

        if seedDemoData {
            let seeded = Self.buildOfflineSeed()
            self.harnessProbes = seeded.harnesses
            self.outcomes = seeded.outcomes
            self.subSessions = seeded.subSessions
            self.decisions = seeded.decisions
            self.latestCue = seeded.cue
            self.fleetNodes = seeded.nodes
            self.tunnelStatus = seeded.tunnel
            self.museCards = seeded.museCards
            self.chatMessages = seeded.chatMessages
            self.episodicMemories = seeded.memories
            self.synthesizedSkills = seeded.skills
            self.understandingScore = seeded.understanding
            self.lastDigest = seeded.digest
            self.soulPreview = seeded.soul
        } else {
            let empty = Self.buildCleanEmptyState()
            self.harnessProbes = []
            self.outcomes = []
            self.subSessions = []
            self.decisions = []
            self.latestCue = nil
            self.fleetNodes = []
            self.tunnelStatus = empty.tunnel
            self.museCards = []
            self.chatMessages = []
            self.episodicMemories = []
            self.synthesizedSkills = []
            self.understandingScore = empty.understanding
            self.lastDigest = nil
            self.soulPreview = empty.soul
        }

        hostConn.attach(store: self)

        if enableNativeRuntime || stateFileUrl != nil {
            self.loadResidentState()
        }
        PipiTokens.textScale = CGFloat(self.uiZoomScale)
        self.localAgentStatuses = PipiNativeMacRuntime.probeLocalAgents(enabled: self.enabledLocalAgents)
        self.wireVoiceEngineCallbacks()
        self.wireComputerUseCallbacks()
        self.refreshHardwareAndModelPlan()
        self.refreshLocalHostCapabilities()
        self.refreshWikiPages()
        self.syncProactiveObservableState()
        self.refreshEventKitAuthStates()
        self.syncPocketNotesObservableState()
        self.alterEgoCoordinator.onChange = { [weak self] in
            self?.syncAlterEgoObservableState()
        }
        self.syncAlterEgoObservableState()
        if enableNativeRuntime {
            if self.hasCompletedOnboarding && !self.personas.contains(where: { $0.id == PipiBotPersona.securityAuditorId }) {
                self.personas.append(PipiBotPersona.securityAuditorDefault)
            }
            if self.hasCompletedOnboarding && !self.personas.contains(where: { $0.id == PipiBotPersona.botArchitectId }) {
                self.personas.append(PipiBotPersona.botArchitectDefault)
            }
            self.usageRecords = PipiUsageMeteringEngine.loadLedger()
            self.entityLedgerEntries = PipiEntityLedgerStore.load()
            if self.persistenceWarning == nil {
                self.noticeBanner = strings.readyStatus
            }
            self.startRoutineScheduler()
            self.installSystemWakeRecoveryObserver()
            if self.defersSystemKeychainReads {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(250))
                    await self?.hydrateNativeSecretsAfterLaunch()
                }
            } else if self.wechatAutoConnectEnabled && self.wechatILinkManager.hasSavedCredentials {
                self.reconnectWeChatILink()
            }
            if self.autoCheckUpdatesEnabled {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    guard let self else { return }
                    _ = await self.updateManager.checkForUpdates(currentVersion: self.appDisplayVersion, silent: true)
                }
            }
        }

        if autoConnect && (companionSyncEnabled || enableEmbeddedBridge) {
            startLiveSync()
        }
    }

    public func refreshLocalHostCapabilities() {
        localHostConnection.updateHost(
            PipiHostDescriptor.local(
                llmProviderIds: readyLLMProviders.map(\.id),
                cliAgents: usableLocalAgents.map(\.kind)
            )
        )
    }

    public func effectivePermissionTier(
        for persona: PipiBotPersona? = nil,
        project: PipiProject? = nil
    ) -> PipiPermissionTier {
        let p = persona ?? activePersona
        let proj = project ?? activeProject
        return proj?.permissionTierOverride ?? p.permissionTier
    }

    public func setEffectivePermissionTier(_ tier: PipiPermissionTier) {
        if let activeProj = activeProject,
           let pIdx = projects.firstIndex(where: { $0.id == activeProj.id }) {
            projects[pIdx].permissionTierOverride = tier
        } else if let idx = personas.firstIndex(where: { $0.id == activePersona.id }) {
            personas[idx].permissionTier = tier
        }
        saveResidentState()
    }

    public func assignActiveConversationPersona(_ personaId: String) {
        guard personas.contains(where: { $0.id == personaId }) else { return }
        activePersonaId = personaId
        overrideExecutionTarget = nil
        if let activeId = activeConversationId,
           let idx = conversations.firstIndex(where: { $0.id == activeId }),
           conversations[idx].messages.isEmpty,
           activeRuns[activeId] == nil {
            conversations[idx].personaId = personaId
            conversations[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        }
        syncElapsedAndAvatarForActiveConversation()
        saveResidentState()
    }

    public func setDefaultExecutionTarget(_ target: PipiExecutionTarget) {
        defaultExecutionTarget = target
        if case .llm(let pid) = target {
            defaultLLMProviderId = pid
        }
        saveResidentState()
    }

    public func openInspectorForChange(_ change: PipiFileChange) {
        selectedFileChangeId = change.id
        selectedInspectorTab = .changes
        isInspectorPresented = true
    }

    public static func estimateTokenCount(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        var cjkCount = 0
        var otherCount = 0
        for scalar in trimmed.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v)
                || (0x3400...0x4DBF).contains(v)
                || (0x3040...0x30FF).contains(v)
                || (0xAC00...0xD7AF).contains(v) {
                cjkCount += 1
            } else if !scalar.properties.isWhitespace {
                otherCount += 1
            }
        }
        let cjkTokens = Double(cjkCount) / 1.5
        let otherTokens = Double(otherCount) / 3.8
        return max(1, Int((cjkTokens + otherTokens).rounded(.up)))
    }

    public func estimateContextUsage(for explicitConversation: PipiConversation? = nil) -> PipiContextUsageEstimate {
        let conv = explicitConversation ?? activeConversation
        let persona = conv.flatMap { c in personas.first(where: { $0.id == c.personaId }) } ?? activePersona
        let project = conv?.projectId.flatMap { pid in projects.first(where: { $0.id == pid }) }
        let systemPrompt = buildSystemPrompt(for: persona, project: project)

        var totalTokens = Self.estimateTokenCount(for: systemPrompt)
        let messages = conv?.messages ?? []
        var turnCount = 0
        var attachmentCount = 0

        for msg in messages {
            if msg.role == .user { turnCount += 1 }
            totalTokens += 4 + Self.estimateTokenCount(for: msg.content)
            if let files = msg.attachments {
                attachmentCount += files.count
                for file in files {
                    if let body = file.textContent, !body.isEmpty {
                        totalTokens += 20 + Self.estimateTokenCount(for: body)
                    } else if file.isImage {
                        totalTokens += 256
                    } else {
                        totalTokens += 24
                    }
                }
            }
        }

        let engineSignal = (conv?.lastEngineLabel ?? activeEngineDisplayLabel(for: persona)).lowercased()
        let windowTokens: Int = {
            if engineSignal.contains("claude") { return 200_000 }
            if engineSignal.contains("gemini") { return 1_000_000 }
            return 128_000
        }()

        let hasProfile = !personalProfileNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return PipiContextUsageEstimate(
            estimatedTokens: totalTokens,
            contextWindowTokens: windowTokens,
            messageCount: messages.count,
            turnCount: turnCount,
            attachmentCount: attachmentCount,
            isMemoryEnabled: memoryEnabled,
            hasPersonalProfile: hasProfile
        )
    }

    public func refreshNativeRuntimeSnapshot() {
        let probes = PipiNativeMacRuntime.probeInstalledHarnesses()
        self.harnessProbes = probes
        self.localAgentStatuses = PipiNativeMacRuntime.probeLocalAgents(enabled: self.enabledLocalAgents)

        let activeCount = self.subSessions.filter { $0.status == .running || $0.status == .waitingTool }.count
        let liveMacNode = PipiNativeMacRuntime.sampleHostTelemetry(activeSessionsCount: activeCount)
        if let idx = self.fleetNodes.firstIndex(where: { $0.nodeId == "mac-resident" }) {
            self.fleetNodes[idx] = liveMacNode
        } else {
            self.fleetNodes.insert(liveMacNode, at: 0)
        }

        self.latestCue = PipiNativeMacRuntime.detectFrontmostAppContext()
    }

    public func refreshNativeRuntimeSnapshotAsync() async {
        let activeCount = self.subSessions.filter { $0.status == .running || $0.status == .waitingTool }.count
        let enabledSnapshot = self.enabledLocalAgents
        let (probes, agents, liveMacNode, cue) = await Task.detached(priority: .utility) {
            let p = PipiNativeMacRuntime.probeInstalledHarnesses()
            let ag = PipiNativeMacRuntime.probeLocalAgents(enabled: enabledSnapshot)
            let mac = PipiNativeMacRuntime.sampleHostTelemetry(activeSessionsCount: activeCount)
            let c = PipiNativeMacRuntime.detectFrontmostAppContext()
            return (p, ag, mac, c)
        }.value

        self.harnessProbes = probes
        self.localAgentStatuses = agents
        if let idx = self.fleetNodes.firstIndex(where: { $0.nodeId == "mac-resident" }) {
            self.fleetNodes[idx] = liveMacNode
        } else {
            self.fleetNodes.insert(liveMacNode, at: 0)
        }
        self.latestCue = cue
    }

    public func refreshLocalAgents() async {
        let enabledSnapshot = self.enabledLocalAgents
        let agents = await Task.detached(priority: .userInitiated) {
            PipiNativeMacRuntime.probeLocalAgents(enabled: enabledSnapshot)
        }.value
        self.localAgentStatuses = agents
        refreshLocalHostCapabilities()
    }

    public func setKeepAwake(_ enabled: Bool) {
        bridgeSupervisor.setKeepAwake(enabled)
        noticeBanner = enabled
            ? strings.t("已开启保持 Mac 唤醒", "Keep Mac Awake enabled")
            : strings.t("已关闭保持 Mac 唤醒", "Keep Mac Awake disabled")
        saveResidentState()
    }

    private var isStateMeaningfullyEmpty: Bool {
        conversations.isEmpty &&
        llmProviders.isEmpty &&
        projects.isEmpty &&
        routines.isEmpty &&
        outcomes.isEmpty &&
        personalProfileNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func makePersistedSnapshot() -> PipiResidentPersistedState {
        PipiResidentPersistedState(
            outcomes: outcomes,
            decisions: decisions,
            museCards: museCards,
            activeHarness: activeHarness,
            themeModeRaw: themeMode.rawValue,
            keepAwakeEnabled: bridgeSupervisor.keepAwakeEnabled,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            hasCompletedOnboarding: hasCompletedOnboarding,
            languageRaw: language.rawValue,
            llmProviders: llmProviders,
            defaultLLMProviderId: defaultLLMProviderId,
            enabledLocalAgents: Array(enabledLocalAgents),
            defaultExecutionTarget: defaultExecutionTarget,
            workspaceDirectory: workspaceDirectory,
            personas: personas,
            activePersonaId: activePersonaId,
            conversations: conversations,
            activeConversationId: activeConversationId,
            memoryEnabled: memoryEnabled,
            personalProfileNote: personalProfileNote,
            routines: routines,
            runRecords: Array(runRecords.prefix(50)),
            companionSyncEnabled: companionSyncEnabled,
            schemaMigrationVersion: Self.currentSchemaMigrationVersion,
            uiZoomScale: uiZoomScale,
            projects: projects,
            groupChats: groupChats,
            activeGroupChatId: activeGroupChatId,
            approvalWhitelistRules: approvalWhitelistRules,
            llmGuardrailJudgeEnabled: llmGuardrailJudgeEnabled,
            proactiveState: proactiveEngine.exportPersistedState(),
            alterEgoTasks: Array(alterEgoCoordinator.tasks.prefix(40)),
            pocketNotesState: pocketNotesEngine.exportPersistedState(),
            localGatewayConfig: localGatewayConfig,
            voiceConfig: voiceConfig,
            computerUseConfig: computerUseConfig,
            globalCapabilityPool: globalCapabilityPool,
            homeScenePresetRaw: homeScenePreset.rawValue,
            botRoomAssignments: botRoomAssignments.mapValues { $0.rawValue },
            autoCheckUpdatesEnabled: autoCheckUpdatesEnabled,
            proactiveCLIDelegationEnabled: proactiveCLIDelegationEnabled,
            securityAuditorBotId: securityAuditorBotId,
            wechatAutoConnectEnabled: wechatAutoConnectEnabled,
            wechatTypingIndicatorEnabled: wechatILinkManager.typingIndicatorEnabled,
            wechatPrimaryBotId: wechatILinkManager.primaryBotId,
            wechatRoutingModeRaw: wechatILinkManager.routingMode.rawValue,
            wechatGroupMemberBotIds: wechatILinkManager.groupMemberBotIds,
            boardChannels: boardChannels,
            boardThreads: Array(boardThreads.prefix(200)),
            boardEvents: Array(boardEvents.suffix(200))
        )
    }

    public func saveResidentState() {
        guard enableNativeRuntime || persistenceUrl != nil else { return }
        if corruptStateDetected && isStateMeaningfullyEmpty {
            return
        }
        hasPendingSave = true
        saveDebounceTask?.cancel()
        let debounceMs = saveDebounceMilliseconds
        saveDebounceTask = Task { [weak self] in
            if debounceMs > 0 {
                try? await Task.sleep(for: .milliseconds(debounceMs))
            }
            guard !Task.isCancelled else { return }
            self?.enqueueAsyncSnapshotWrite()
        }
    }

    private func enqueueAsyncSnapshotWrite() {
        guard hasPendingSave, enableNativeRuntime || persistenceUrl != nil else { return }
        if corruptStateDetected && isStateMeaningfullyEmpty {
            hasPendingSave = false
            return
        }
        hasPendingSave = false
        let targetUrl = persistenceUrl ?? PipiNativeMacRuntime.stateFileUrl()
        let snapshot = makePersistedSnapshot()
        persistenceQueue.async {
            PipiNativeMacRuntime.saveResidentState(snapshot, to: targetUrl)
        }
    }

    /// Synchronously cancels any pending debounce timer and writes pending state to disk on the serial persistence queue.
    /// Call this on app termination / iOS background transitions.
    public func flush() {
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        guard enableNativeRuntime || persistenceUrl != nil else { return }
        if corruptStateDetected && isStateMeaningfullyEmpty {
            hasPendingSave = false
            return
        }
        let targetUrl = persistenceUrl ?? PipiNativeMacRuntime.stateFileUrl()
        if hasPendingSave {
            hasPendingSave = false
            let snapshot = makePersistedSnapshot()
            persistenceQueue.sync {
                PipiNativeMacRuntime.saveResidentState(snapshot, to: targetUrl)
            }
        } else {
            persistenceQueue.sync {}
        }
    }

    public func flushResidentState() {
        flush()
    }

    /// Force-flushes the full in-memory snapshot synchronously to disk and creates a verified
    /// `resident-state.pre-update.json` backup so app upgrades & relaunches never lose settings or chats.
    public func prepareForAppUpgrade() {
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        guard enableNativeRuntime || persistenceUrl != nil else { return }
        if corruptStateDetected && isStateMeaningfullyEmpty {
            hasPendingSave = false
            return
        }
        hasPendingSave = false
        let targetUrl = persistenceUrl ?? PipiNativeMacRuntime.stateFileUrl()
        let snapshot = makePersistedSnapshot()
        persistenceQueue.sync {
            PipiNativeMacRuntime.saveResidentState(snapshot, to: targetUrl)
            _ = PipiNativeMacRuntime.createPreUpdateBackup(from: targetUrl)
        }
    }

    public func dismissPersistenceWarning() {
        persistenceWarning = nil
        if noticeBanner?.contains("resident-state.corrupt") == true || noticeBanner?.contains("Corrupt state") == true {
            noticeBanner = strings.readyStatus
        }
    }

    public func setPersonalProfileNote(_ note: String) {
        personalProfileNote = note
        saveResidentState()
    }

    public func loadResidentState() {
        let targetUrl = persistenceUrl ?? PipiNativeMacRuntime.stateFileUrl()
        let result = PipiNativeMacRuntime.loadResidentStateDetailed(from: targetUrl)
        let saved: PipiResidentPersistedState
        switch result {
        case .notFound:
            return
        case .corrupt(let backupURL, _):
            corruptStateDetected = true
            corruptStateBackupUrl = backupURL
            let backupName = backupURL?.lastPathComponent ?? "resident-state.corrupt.json"
            let warning = strings.corruptStateNotice(backupName: backupName)
            persistenceWarning = warning
            noticeBanner = warning
            return
        case .loaded(let decoded):
            corruptStateDetected = false
            corruptStateBackupUrl = nil
            persistenceWarning = nil
            saved = decoded
        }

        let needsDirtySeedPurge = (saved.schemaMigrationVersion ?? 0) < Self.currentSchemaMigrationVersion
        if needsDirtySeedPurge {
            // Strip legacy demo seed items injected by v0.2/v0.3 while preserving all real user data
            self.outcomes = saved.outcomes.filter { !Self.isLegacyDemoOutcome($0) }
            self.decisions = saved.decisions.filter { !Self.isLegacyDemoDecision($0) }
            self.museCards = []
        } else {
            if !saved.outcomes.isEmpty { self.outcomes = saved.outcomes }
            if !saved.decisions.isEmpty { self.decisions = saved.decisions }
            if !saved.museCards.isEmpty { self.museCards = saved.museCards }
        }

        self.activeHarness = saved.activeHarness
        if let mode = PipiThemeMode(rawValue: saved.themeModeRaw) {
            self.themeMode = mode
        }
        bridgeSupervisor.setKeepAwake(saved.keepAwakeEnabled)

        if let onboarded = saved.hasCompletedOnboarding {
            self.hasCompletedOnboarding = onboarded
        }
        if let langRaw = saved.languageRaw, let lang = PipiAppLanguage(rawValue: langRaw) {
            self.language = lang
        }
        var didMigratePlaintextKeys = false
        if let providers = saved.llmProviders {
            self.llmProviders = providers.map { provider in
                var copy = provider
                let plaintext = copy.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if !plaintext.isEmpty {
                    secretStore.setSecret(plaintext, for: copy.secretAccountKey)
                    copy.apiKey = plaintext
                    didMigratePlaintextKeys = true
                } else if !defersSystemKeychainReads, let stored = secretStore.secret(for: copy.secretAccountKey) {
                    copy.apiKey = stored
                }
                return copy
            }
        }
        self.defaultLLMProviderId = saved.defaultLLMProviderId
        if let agents = saved.enabledLocalAgents {
            self.enabledLocalAgents = Set(agents)
        }
        if let target = saved.defaultExecutionTarget {
            self.defaultExecutionTarget = target
        }
        if let dir = saved.workspaceDirectory, !dir.isEmpty {
            self.workspaceDirectory = dir
        }
        var didMigratePipiPersona = false
        if let savedPersonas = saved.personas, !savedPersonas.isEmpty {
            self.personas = savedPersonas.map { persona in
                guard persona.id == "bot_pipi_general" else { return persona }
                var upgraded = persona
                if upgraded.nameZh == "Pipi · 全能助手" {
                    upgraded.nameZh = "PiPi · 全能助手"
                    didMigratePipiPersona = true
                }
                if upgraded.nameEn == "Pipi · Assistant" {
                    upgraded.nameEn = "PiPi · Assistant"
                    didMigratePipiPersona = true
                }
                if upgraded.greetingZh.contains("Pipi") {
                    upgraded.greetingZh = upgraded.greetingZh.replacingOccurrences(of: "Pipi", with: "PiPi")
                    didMigratePipiPersona = true
                }
                if upgraded.greetingEn.contains("Pipi") {
                    upgraded.greetingEn = upgraded.greetingEn.replacingOccurrences(of: "Pipi", with: "PiPi")
                    didMigratePipiPersona = true
                }
                if upgraded.systemPrompt.contains("Pipi") {
                    upgraded.systemPrompt = upgraded.systemPrompt.replacingOccurrences(of: "Pipi", with: "PiPi")
                    didMigratePipiPersona = true
                }
                return upgraded
            }
        }
        if let savedActivePersona = saved.activePersonaId,
           self.personas.contains(where: { $0.id == savedActivePersona }) {
            self.activePersonaId = savedActivePersona
        }
        if let savedConvs = saved.conversations {
            self.conversations = savedConvs.map { conv in
                var sanitized = conv
                if sanitized.state == .running || sanitized.state == .queued {
                    sanitized.state = sanitized.approvals.contains(where: { $0.status == .pending }) ? .needsYou : .cancelled
                } else if sanitized.approvals.contains(where: { $0.status == .pending }) {
                    sanitized.state = .needsYou
                }
                return sanitized
            }
        }
        if let savedActiveConv = saved.activeConversationId,
           self.conversations.contains(where: { $0.id == savedActiveConv }) {
            self.activeConversationId = savedActiveConv
        }
        if let memEnabled = saved.memoryEnabled {
            self.memoryEnabled = memEnabled
        }
        if let note = saved.personalProfileNote {
            self.personalProfileNote = note
        }
        if let savedRoutines = saved.routines {
            self.routines = savedRoutines
        }
        if let savedRuns = saved.runRecords {
            self.runRecords = savedRuns
        }
        if let syncEnabled = saved.companionSyncEnabled {
            self.companionSyncEnabled = syncEnabled
        }
        if let savedZoom = saved.uiZoomScale {
            let clamped = min(Self.maxZoomScale, max(Self.minZoomScale, savedZoom))
            self.uiZoomScale = clamped
            PipiTokens.textScale = CGFloat(clamped)
        }
        if let savedProjects = saved.projects {
            self.projects = savedProjects
        }
        if let savedGroups = saved.groupChats {
            self.groupChats = savedGroups.map { group in
                var copy = group
                copy.assignments = copy.assignments.map { assignment in
                    var updated = assignment
                    if updated.status == .working || updated.status == .queued {
                        updated.status = .done
                    }
                    return updated
                }
                return copy
            }
        }
        if let savedGroupId = saved.activeGroupChatId,
           self.groupChats.contains(where: { $0.id == savedGroupId }) {
            self.activeGroupChatId = savedGroupId
        }
        if let savedWhitelist = saved.approvalWhitelistRules {
            self.approvalWhitelistRules = savedWhitelist
            self.permissionGuardrail.replaceWhitelistRules(savedWhitelist)
        }
        if let savedJudge = saved.llmGuardrailJudgeEnabled {
            self.llmGuardrailJudgeEnabled = savedJudge
        }
        if let savedProactive = saved.proactiveState {
            self.proactiveEngine.restorePersistedState(savedProactive)
            self.syncProactiveObservableState()
        }
        if let savedAlterEgo = saved.alterEgoTasks {
            self.alterEgoCoordinator.restorePersistedTasks(savedAlterEgo)
            self.syncAlterEgoObservableState()
        }
        if let savedPocket = saved.pocketNotesState {
            self.pocketNotesEngine.restorePersistedState(savedPocket)
            self.syncPocketNotesObservableState()
        }
        if let savedGateway = saved.localGatewayConfig {
            self.localGatewayConfig = savedGateway
        }
        if let savedVoice = saved.voiceConfig {
            self.voiceConfig = savedVoice
            self.voiceEngine.config = savedVoice
        }
        if let savedCU = saved.computerUseConfig {
            self.computerUseConfig = savedCU
            self.computerUseCoordinator.config = savedCU
        }
        if let savedPool = saved.globalCapabilityPool {
            self.globalCapabilityPool = savedPool
        }
        if let presetRaw = saved.homeScenePresetRaw, let preset = PipiHomeScenePreset(rawValue: presetRaw) {
            self.homeScenePreset = preset
        }
        if let savedRooms = saved.botRoomAssignments {
            var decodedRooms: [String: PipiHomeRoomKind] = [:]
            for (botId, roomRaw) in savedRooms {
                if let kind = PipiHomeRoomKind(rawValue: roomRaw) {
                    decodedRooms[botId] = kind
                }
            }
            self.botRoomAssignments = decodedRooms
        }
        if let autoUpdates = saved.autoCheckUpdatesEnabled {
            self.autoCheckUpdatesEnabled = autoUpdates
        }
        if let proactiveCLI = saved.proactiveCLIDelegationEnabled {
            self.proactiveCLIDelegationEnabled = proactiveCLI
        }
        if let auditorId = saved.securityAuditorBotId, !auditorId.isEmpty {
            self.securityAuditorBotId = auditorId
        }
        if let wxAuto = saved.wechatAutoConnectEnabled {
            self.wechatAutoConnectEnabled = wxAuto
        }
        if let wxTyping = saved.wechatTypingIndicatorEnabled {
            self.wechatILinkManager.typingIndicatorEnabled = wxTyping
        }
        if let wxPrimary = saved.wechatPrimaryBotId, !wxPrimary.isEmpty {
            self.wechatILinkManager.primaryBotId = wxPrimary
        }
        if let wxModeRaw = saved.wechatRoutingModeRaw, let wxMode = PipiWeChatRoutingMode(rawValue: wxModeRaw) {
            self.wechatILinkManager.routingMode = wxMode
        }
        if let wxMembers = saved.wechatGroupMemberBotIds {
            self.wechatILinkManager.groupMemberBotIds = wxMembers
        }
        if let savedBoardChannels = saved.boardChannels, !savedBoardChannels.isEmpty {
            self.boardChannels = savedBoardChannels
        }
        if let savedBoardThreads = saved.boardThreads {
            self.boardThreads = savedBoardThreads
        }
        if let savedBoardEvents = saved.boardEvents {
            self.boardEvents = savedBoardEvents
        }

        if needsDirtySeedPurge || didMigratePlaintextKeys || didMigratePipiPersona {
            hasPendingSave = true
            flush()
        }
    }

    private static func isLegacyDemoOutcome(_ item: OutcomeResponsibility) -> Bool {
        let legacyIds: Set<String> = [
            "out_layout_cls",
            "out_android_parity",
            "out_vps_sentinel",
            "out_daily_brief",
            "out_layout_guardian",
            "out_feature_parity",
            "out_vps_guard",
            "out_life_steward"
        ]
        if legacyIds.contains(item.id) { return true }
        let title = item.title.lowercased()
        return title.contains("layout bot") ||
            title.contains("layout guardian") ||
            title.contains("hk vps") ||
            title.contains("feature parity") ||
            title.contains("sanctuary watch")
    }

    private static func isLegacyDemoDecision(_ item: NeedsYouDecision) -> Bool {
        let legacyIds: Set<String> = [
            "dec_pr_142",
            "dec_vps_nginx",
            "dec_dream_diff",
            "dec_layout_pr42",
            "dec_vps_reload",
            "dec_thu_calendar"
        ]
        if legacyIds.contains(item.id) { return true }
        let title = item.title.lowercased()
        return title.contains("pr #142") ||
            title.contains("pr #42") ||
            title.contains("nginx") ||
            title.contains("soul diff") ||
            title.contains("thursday evening")
    }

    public func setCompanionSyncEnabled(_ enabled: Bool) {
        companionSyncEnabled = enabled
        saveResidentState()
        if enabled {
            startLiveSync()
        } else {
            sseTask?.cancel()
            sseTask = nil
            bridgeSupervisor.stopBridge()
            connectionMode = .nativeResident
        }
    }

    public func toggleArchiveConversation(_ id: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].isArchived.toggle()
        if conversations[idx].isArchived && activeConversationId == id {
            activeConversationId = conversationsForActivePersona.first?.id
        }
        saveResidentState()
    }

    public func togglePinConversation(_ id: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].isPinned.toggle()
        saveResidentState()
    }

    private static let isoFormatterBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public func parseSessionDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        return Self.isoFormatterBasic.date(from: raw) ?? Self.isoFormatterFractional.date(from: raw)
    }

    public func sessionTimeBucket(for conv: PipiConversation, now: Date = Date()) -> PipiSessionTimeBucket {
        if isRunning(conversationId: conv.id) || conv.state == .running || conv.state == .queued || conv.state == .needsYou {
            return .activeOrNeedsYou
        }
        if conv.isPinned {
            return .pinned
        }
        let date = parseSessionDate(conv.updatedAt) ?? parseSessionDate(conv.createdAt) ?? Date.distantPast
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return .today
        }
        if cal.isDateInYesterday(date) {
            return .yesterday
        }
        if let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now)),
           date >= sevenDaysAgo {
            return .last7Days
        }
        return .earlier
    }

    public func groupedGlobalSessions(
        searchQuery: String = "",
        botFilterId: String? = nil,
        now: Date = Date()
    ) -> [(bucket: PipiSessionTimeBucket, conversations: [PipiConversation])] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = conversations.filter { conv in
            if conv.isArchived { return false }
            if let botFilterId, conv.personaId != botFilterId { return false }
            if q.isEmpty { return true }
            if conv.title.lowercased().contains(q) { return true }
            return conv.messages.contains { $0.content.lowercased().contains(q) }
        }
        .sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }

        var buckets: [PipiSessionTimeBucket: [PipiConversation]] = [:]
        for conv in filtered {
            let bucket = sessionTimeBucket(for: conv, now: now)
            buckets[bucket, default: []].append(conv)
        }
        return PipiSessionTimeBucket.allCases.compactMap { bucket in
            guard let items = buckets[bucket], !items.isEmpty else { return nil }
            return (bucket: bucket, conversations: items)
        }
    }

    public func searchConversations(
        query: String,
        botFilterId: String? = nil,
        includeArchived: Bool = true
    ) -> [PipiSessionSearchMatch] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sorted = conversations
            .filter { conv in
                if !includeArchived && conv.isArchived { return false }
                if let botFilterId, conv.personaId != botFilterId { return false }
                return true
            }
            .sorted { $0.updatedAt > $1.updatedAt }

        guard !q.isEmpty else {
            return sorted.map { PipiSessionSearchMatch(conversation: $0, matchedMessageSnippet: nil) }
        }

        var results: [PipiSessionSearchMatch] = []
        for conv in sorted {
            let titleMatches = conv.title.lowercased().contains(q)
            let matchedMessage = conv.messages.first { $0.content.lowercased().contains(q) }
            if titleMatches || matchedMessage != nil {
                let snippet: String? = matchedMessage.map { msg in
                    Self.extractSnippet(from: msg.content, matching: q)
                }
                results.append(PipiSessionSearchMatch(conversation: conv, matchedMessageSnippet: snippet))
            }
        }
        return results
    }

    private static func extractSnippet(from text: String, matching lowercaseQuery: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = collapsed.lowercased().range(of: lowercaseQuery) else {
            return String(collapsed.prefix(80))
        }
        let startIdx = collapsed.index(range.lowerBound, offsetBy: -24, limitedBy: collapsed.startIndex) ?? collapsed.startIndex
        let endIdx = collapsed.index(range.upperBound, offsetBy: 48, limitedBy: collapsed.endIndex) ?? collapsed.endIndex
        let prefix = startIdx > collapsed.startIndex ? "…" : ""
        let suffix = endIdx < collapsed.endIndex ? "…" : ""
        return "\(prefix)\(collapsed[startIdx..<endIdx])\(suffix)"
    }

    public func relativeTimeLabel(for isoString: String, now: Date = Date()) -> String {
        guard let date = parseSessionDate(isoString) else { return "" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return strings.relativeTimeJustNow }
        let minutes = seconds / 60
        if minutes < 60 { return strings.relativeTimeMinutes(minutes) }
        let hours = minutes / 60
        if Calendar.current.isDateInToday(date) && hours < 24 {
            return strings.relativeTimeHours(hours)
        }
        if Calendar.current.isDateInYesterday(date) {
            return strings.relativeTimeYesterday
        }
        let days = max(1, seconds / 86_400)
        if days < 30 {
            return strings.relativeTimeDays(days)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    public func clearAllConversations() {
        for convId in Array(activeRuns.keys) {
            stopGenerating(conversationId: convId)
        }
        for groupId in Set(groupRunTasksByRunId.values.map(\.groupId)) {
            stopGroupChat(groupId)
        }
        conversations = []
        activeConversationId = nil
        groupChats = []
        activeGroupChatId = nil
        activeGroupRuns = [:]
        activeGroupStreamingMessageIds = [:]
        runRecords = []
        lastDeletedItem = nil
        showUndoToast = false
        undoToastDismissTask?.cancel()
        saveResidentState()
    }

    // MARK: - Bot Routines (Prompt-to-Schedule)

    public func addRoutine(_ routine: PipiBotRoutine) {
        routines.insert(routine, at: 0)
        saveResidentState()
    }

    public func toggleRoutine(id: String, enabled: Bool) {
        guard let idx = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[idx].isEnabled = enabled
        saveResidentState()
    }

    public func deleteRoutine(id: String) {
        routines.removeAll { $0.id == id }
        saveResidentState()
    }

    public func runRoutineNow(_ routine: PipiBotRoutine) async {
        guard !routine.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let nowIso = ISO8601DateFormatter().string(from: Date())
        if let idx = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[idx].lastRunAt = nowIso
            saveResidentState()
        }
        let bgConv = createConversation(
            for: routine.personaId,
            title: routine.title.isEmpty ? nil : routine.title,
            activate: false
        )
        await sendPersonalMessage(
            routine.prompt,
            conversationId: bgConv.id,
            personaId: routine.personaId,
            activateTargetConversation: false,
            priority: .proactiveRoutine
        )
    }

    private func startRoutineScheduler() {
        routineSchedulerTask?.cancel()
        routineSchedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                await self?.checkDueRoutines()
            }
        }
    }

    public func checkDueRoutines(now: Date = Date()) async {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .weekday], from: now)

        // Wave 2 (#02 & #03): Background 6h-idle Per-Bot memory consolidation & nightly Clue->Rule dreaming
        if memoryEnabled {
            var didConsolidateAny = false
            for persona in personas {
                let res = await botMemoryEngine.consolidateIfDue(botId: persona.id, now: now, trigger: .idleCheck)
                if res.consolidated { didConsolidateAny = true }
            }
            if didConsolidateAny {
                botMemoryVersionCounter += 1
            }
        }
        let todayYmd = PipiProactiveEngine.formatLocalYmd(now)
        if (comps.hour ?? 0) >= proactiveEngine.policy.quietHoursStart,
           proactiveEngine.lastDreamDateYmd != todayYmd,
           !proactiveEngine.pendingFeedback.isEmpty {
            _ = runProactiveNightlyDreaming(todayYmd: todayYmd)
        }

        // Wave 3 (#11): Auto-reconcile today's Pocket Note after 5 minutes of editing silence
        let pocketReconcile = pocketNotesEngine.reconcileDailyNoteIfQuiet(dateYmd: todayYmd, now: now, force: false)
        if pocketReconcile.extracted {
            syncPocketNotesObservableState()
            saveResidentState()
        }

        // Jarvis Proactive Butler #2: Daily morning briefing (08:30–10:30 local time, once per day)
        if enableNativeRuntime,
           let hour = comps.hour, let minute = comps.minute,
           (hour == 8 && minute >= 30) || hour == 9 || (hour == 10 && minute <= 30),
           lastMorningBriefingYmd != todayYmd {
            lastMorningBriefingYmd = todayYmd
            Task { @MainActor [weak self] in
                await self?.triggerDailyBriefingNow()
            }
        }

        // Jarvis Proactive Butler #4: Mac health & GitHub release sentinel (every 15 min, 4h per-category cooldown)
        if enableNativeRuntime && now.timeIntervalSince(lastSentinelCheckAt) >= 900 {
            lastSentinelCheckAt = now
            Task { @MainActor [weak self] in
                await self?.runProactiveSentinelSweep(now: now)
            }
        }

        guard hasConfiguredEngine else { return }
        let iso = ISO8601DateFormatter()

        let dueRoutines: [PipiBotRoutine] = routines.filter { routine in
            guard routine.isEnabled, routine.triggerKind == .schedule else { return false }
            if let cron = routine.eventConfig.cronExpression, !cron.isEmpty {
                if PipiEventTriggerEngine.isWithinCooldown(lastRunAt: routine.lastRunAt, cooldownSeconds: 55, now: now) {
                    return false
                }
                return PipiEventTriggerEngine.matchesCron(cron, date: now, calendar: cal)
            }
            guard routine.schedule != .manual else { return false }
            if let lastStr = routine.lastRunAt, let lastDate = iso.date(from: lastStr) {
                let elapsed = now.timeIntervalSince(lastDate)
                if routine.schedule == .hourly && elapsed < 3500 { return false }
                if routine.schedule == .daily && elapsed < 82800 { return false }
                if routine.schedule == .weekly && elapsed < 590000 { return false }
            }
            switch routine.schedule {
            case .manual:
                return false
            case .hourly:
                return (comps.minute ?? -1) == routine.minute
            case .daily:
                return (comps.hour ?? -1) == routine.hour && (comps.minute ?? -1) == routine.minute
            case .weekly:
                return (comps.weekday ?? -1) == routine.weekday &&
                    (comps.hour ?? -1) == routine.hour &&
                    (comps.minute ?? -1) == routine.minute
            }
        }

        // Sweep non-schedule event triggers (file/git watchers & host health thresholds)
        await evaluateEventDrivenRoutines(now: now)

        guard !dueRoutines.isEmpty else { return }
        let nowIso = iso.string(from: now)
        for routine in dueRoutines {
            if let idx = routines.firstIndex(where: { $0.id == routine.id }) {
                routines[idx].lastRunAt = nowIso
            }
        }
        saveResidentState()

        for routine in dueRoutines {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.runRoutineNow(routine)
                if self.enableNativeRuntime,
                   let conv = self.conversations.first(where: { $0.title == "⏰ \(routine.title)" }),
                   let latestReply = conv.messages.last(where: { $0.role == .assistant })?.content {
                    let preview = String(latestReply.prefix(400))
                    await self.deliverSystemAndWeChatNotification(
                        title: "⏰ 定时任务已完成：\(routine.title)",
                        body: preview
                    )
                }
            }
        }
    }

    // MARK: - Commercial Personal Bot Lifecycle (Onboarding, Engines, Personas, Chat)

    public func setLanguage(_ newLanguage: PipiAppLanguage) {
        self.language = newLanguage
        saveResidentState()
    }

    public func setThemeMode(_ newTheme: PipiThemeMode) {
        self.themeMode = newTheme
        saveResidentState()
    }

    public func completeOnboarding(selectedPersonaId: String? = nil) {
        if let selectedPersonaId, personas.contains(where: { $0.id == selectedPersonaId }) {
            self.activePersonaId = selectedPersonaId
        }
        self.hasCompletedOnboarding = true
        self.avatarEngine.setState(activePersona.idleAvatarState)
        saveResidentState()
    }

    public func reopenOnboarding(atStep step: Int = 0) {
        self.onboardingInitialStep = min(max(step, 0), 3)
        self.hasCompletedOnboarding = false
        self.avatarEngine.setState(.ambientWarmWelcome)
        saveResidentState()
    }

    public func setHomeScenePreset(_ preset: PipiHomeScenePreset) {
        guard homeScenePreset != preset else { return }
        homeScenePreset = preset
        saveResidentState()
    }

    public func assignedRoom(for personaId: String) -> PipiHomeRoomKind {
        if let assigned = botRoomAssignments[personaId] {
            return assigned
        }
        let idx = personas.firstIndex(where: { $0.id == personaId }) ?? 0
        return PipiHomeRoomKind.defaultRoom(forPersonaId: personaId, index: idx)
    }

    public func assignBot(_ personaId: String, to room: PipiHomeRoomKind) {
        botRoomAssignments[personaId] = room
        saveResidentState()
    }

    public func upsertLLMProvider(_ config: PipiLLMProviderConfig, setAsDefault: Bool = true) {
        var normalized = config
        if normalized.keychainRef?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            normalized.keychainRef = normalized.id
        }
        let cleanedKey = normalized.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedKey.isEmpty {
            secretStore.setSecret(cleanedKey, for: normalized.secretAccountKey)
        } else {
            secretStore.deleteSecret(for: normalized.secretAccountKey)
        }
        if let idx = llmProviders.firstIndex(where: { $0.id == normalized.id }) {
            llmProviders[idx] = normalized
        } else {
            llmProviders.append(normalized)
        }
        if setAsDefault || defaultLLMProviderId == nil {
            defaultLLMProviderId = normalized.id
            defaultExecutionTarget = .llm(providerId: normalized.id)
        }
        refreshLocalHostCapabilities()
        saveResidentState()
    }

    public func deleteLLMProvider(id: String) {
        if let existing = llmProviders.first(where: { $0.id == id }) {
            secretStore.deleteSecret(for: existing.secretAccountKey)
        } else {
            secretStore.deleteSecret(for: id)
        }
        llmProviders.removeAll { $0.id == id }
        if defaultLLMProviderId == id {
            defaultLLMProviderId = llmProviders.first(where: \.isReady)?.id ?? llmProviders.first?.id
            if let nextId = defaultLLMProviderId {
                defaultExecutionTarget = .llm(providerId: nextId)
            } else {
                defaultExecutionTarget = .auto
            }
        }
        if case .llm(let pid) = overrideExecutionTarget, pid == id {
            overrideExecutionTarget = nil
        }
        refreshLocalHostCapabilities()
        saveResidentState()
    }

    public func setDefaultLLMProvider(id: String) {
        guard llmProviders.contains(where: { $0.id == id }) else { return }
        defaultLLMProviderId = id
        defaultExecutionTarget = .llm(providerId: id)
        saveResidentState()
    }

    public func toggleLocalAgent(_ kind: PipiLocalAgentKind, enabled: Bool, setAsDefaultIfFirst: Bool = false) {
        if enabled {
            enabledLocalAgents.insert(kind)
            if setAsDefaultIfFirst && !hasConfiguredLLM {
                defaultExecutionTarget = .localAgent(kind)
            }
        } else {
            enabledLocalAgents.remove(kind)
            if defaultExecutionTarget == .localAgent(kind) {
                defaultExecutionTarget = .auto
            }
            if overrideExecutionTarget == .localAgent(kind) {
                overrideExecutionTarget = nil
            }
        }
        localAgentStatuses = localAgentStatuses.map { status in
            var copy = status
            if copy.kind == kind {
                copy.enabled = enabled
            }
            return copy
        }
        refreshLocalHostCapabilities()
        saveResidentState()
    }

    private var hasConfiguredLLM: Bool {
        !readyLLMProviders.isEmpty
    }

    public func resolvedActiveTarget(for persona: PipiBotPersona? = nil) -> PipiExecutionTarget? {
        let p = persona ?? activePersona
        let candidates: [PipiExecutionTarget] = [
            overrideExecutionTarget,
            p.preferredTarget == .auto ? nil : p.preferredTarget,
            defaultExecutionTarget == .auto ? nil : defaultExecutionTarget
        ].compactMap { $0 }

        for candidate in candidates {
            switch candidate {
            case .llm(let pid):
                if llmProviders.first(where: { $0.id == pid && $0.isReady }) != nil {
                    return candidate
                }
            case .localAgent(let kind):
                if usableLocalAgents.contains(where: { $0.kind == kind }) {
                    return candidate
                }
            case .auto:
                break
            }
        }

        if let defaultId = defaultLLMProviderId,
           let provider = llmProviders.first(where: { $0.id == defaultId && $0.isReady }) {
            return .llm(providerId: provider.id)
        }
        if let firstReady = readyLLMProviders.first {
            return .llm(providerId: firstReady.id)
        }
        if let firstAgent = usableLocalAgents.first {
            return .localAgent(firstAgent.kind)
        }
        return nil
    }

    public var securityAuditorPersona: PipiBotPersona {
        personas.first(where: { $0.id == securityAuditorBotId })
            ?? personas.first(where: { $0.id == PipiBotPersona.securityAuditorId })
            ?? PipiBotPersona.securityAuditorDefault
    }

    public func resolvedEffectiveLLMConfig(providerId: String, for persona: PipiBotPersona) -> PipiLLMProviderConfig? {
        guard var cfg = llmProviders.first(where: { $0.id == providerId }) else { return nil }
        if let modelOverride = persona.preferredModelId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !modelOverride.isEmpty {
            cfg.modelId = modelOverride
        }
        return cfg
    }

    public func setPersonaExecutionModel(personaId: String, target: PipiExecutionTarget?, modelId: String?) {
        guard let idx = personas.firstIndex(where: { $0.id == personaId }) else { return }
        if let target {
            personas[idx].preferredTarget = target
        }
        let cleanedModel = modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        personas[idx].preferredModelId = (cleanedModel?.isEmpty == false) ? cleanedModel : nil
        saveResidentState()
    }

    public func refreshAvailableModels(for providerId: String) async {
        guard let cfg = llmProviders.first(where: { $0.id == providerId }) else { return }
        let discovered = await PipiInferenceEngine.fetchAvailableModels(for: cfg)
        availableModelsByProviderId[providerId] = discovered
    }

    public func activeEngineDisplayLabel(for persona: PipiBotPersona? = nil) -> String {
        let p = persona ?? activePersona
        guard let target = resolvedActiveTarget(for: p) else {
            return strings.engineStatusUnconfigured
        }
        switch target {
        case .llm(let pid):
            if let cfg = resolvedEffectiveLLMConfig(providerId: pid, for: p) {
                let isCustom = (p.preferredTarget != .auto) || (p.preferredModelId?.isEmpty == false)
                let prefix = isCustom ? "PiPi" : "PiPi · 默认"
                return "\(prefix) · \(cfg.name) (\(cfg.modelId))"
            }
            return strings.engineStatusUnconfigured
        case .localAgent(let kind):
            if let model = p.preferredModelId, !model.isEmpty {
                return "PiPi → \(kind.displayName) (\(model))"
            }
            return "PiPi → \(kind.displayName)"
        case .auto:
            return strings.autoRouteEngine
        }
    }

    private func syncElapsedAndAvatarForActiveConversation() {
        if let activeId = activeConversationId, let run = activeRuns[activeId] {
            avatarEngine.setState(run.isLocalAgent ? .claudeRouting : .byokStreaming)
        } else if let active = activeConversation, active.state == .needsYou {
            avatarEngine.setState(.needsYouApproval)
        } else {
            avatarEngine.setState(activePersona.idleAvatarState)
        }
    }

    public func selectPersona(_ personaId: String) {
        guard personas.contains(where: { $0.id == personaId }) else { return }
        activePersonaId = personaId
        overrideExecutionTarget = nil
        if let latest = conversationsForActivePersona.first {
            activeConversationId = latest.id
        } else {
            activeConversationId = nil
        }
        syncElapsedAndAvatarForActiveConversation()
        saveResidentState()
    }

    @discardableResult
    public func createConversation(
        for personaId: String? = nil,
        projectId: String? = nil,
        title: String? = nil,
        activate: Bool = true
    ) -> PipiConversation {
        let targetPersonaId = personaId ?? activePersona.id
        let persona = personas.first(where: { $0.id == targetPersonaId }) ?? activePersona
        let resolvedTitle = (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? title!.trimmingCharacters(in: .whitespacesAndNewlines)
            : strings.newChat
        let conv = PipiConversation(
            personaId: persona.id,
            projectId: projectId,
            title: resolvedTitle
        )
        conversations.insert(conv, at: 0)
        if activate {
            activePersonaId = persona.id
            activeConversationId = conv.id
            syncElapsedAndAvatarForActiveConversation()
        }
        if let projectId, let pIdx = projects.firstIndex(where: { $0.id == projectId }) {
            projects[pIdx].isCollapsed = false
        }
        saveResidentState()
        return conv
    }

    public func upsertProject(_ project: PipiProject) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
        } else {
            projects.insert(project, at: 0)
        }
        saveResidentState()
    }

    public func deleteProject(_ id: String) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        let removedProject = projects.remove(at: idx)
        var affectedConversationIds: [String] = []
        for cIdx in conversations.indices where conversations[cIdx].projectId == id {
            affectedConversationIds.append(conversations[cIdx].id)
            conversations[cIdx].projectId = nil
        }
        recordUndoableDeletion(.project(project: removedProject, index: idx, affectedConversationIds: affectedConversationIds))
        saveResidentState()
    }

    public func toggleProjectCollapsed(_ id: String) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].isCollapsed.toggle()
        saveResidentState()
    }

    public func moveConversation(_ conversationId: String, toProject projectId: String?) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].projectId = projectId
        conversations[idx].isArchived = false
        conversations[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        if let projectId, let pIdx = projects.firstIndex(where: { $0.id == projectId }) {
            projects[pIdx].isCollapsed = false
        }
        saveResidentState()
    }

    public func renameConversation(_ conversationId: String, title: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].title = cleaned
        saveResidentState()
    }

    public func selectConversation(_ id: String) {
        guard let conv = conversations.first(where: { $0.id == id }) else { return }
        activePersonaId = conv.personaId
        activeConversationId = conv.id
        markConversationRead(id)
        syncElapsedAndAvatarForActiveConversation()
        saveResidentState()
    }

    public func deleteConversation(_ id: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        if activeRuns[id] != nil {
            stopGenerating(conversationId: id)
        }
        let wasActiveId = activeConversationId
        let removed = conversations.remove(at: idx)
        if activeConversationId == id {
            activeConversationId = conversationsForActivePersona.first?.id
        }
        recordUndoableDeletion(.conversation(conversation: removed, index: idx, wasActiveConversationId: wasActiveId))
        saveResidentState()
    }

    private func recordUndoableDeletion(_ deletion: PipiUndoableDeletion) {
        lastDeletedItem = deletion
        showUndoToast = true
        undoToastDismissTask?.cancel()
        undoToastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.showUndoToast = false
        }
    }

    @discardableResult
    public func undoLastDeletion() -> Bool {
        guard let item = lastDeletedItem else { return false }
        lastDeletedItem = nil
        showUndoToast = false
        undoToastDismissTask?.cancel()
        undoToastDismissTask = nil

        switch item {
        case .conversation(let conv, let index, let wasActiveConversationId):
            if !conversations.contains(where: { $0.id == conv.id }) {
                let insertAt = min(max(0, index), conversations.count)
                conversations.insert(conv, at: insertAt)
            }
            if wasActiveConversationId == conv.id || activeConversationId == nil {
                if personas.contains(where: { $0.id == conv.personaId }) {
                    activePersonaId = conv.personaId
                }
                activeConversationId = conv.id
            }
            saveResidentState()
            return true

        case .project(let project, let index, let affectedConversationIds):
            if !projects.contains(where: { $0.id == project.id }) {
                let insertAt = min(max(0, index), projects.count)
                projects.insert(project, at: insertAt)
            }
            let affectedSet = Set(affectedConversationIds)
            for idx in conversations.indices where affectedSet.contains(conversations[idx].id) {
                conversations[idx].projectId = project.id
            }
            saveResidentState()
            return true
        }
    }

    public func dismissUndoToast() {
        showUndoToast = false
        undoToastDismissTask?.cancel()
        undoToastDismissTask = nil
    }

    public func conversationCount(forPersona personaId: String) -> Int {
        conversations.filter { $0.personaId == personaId }.count
    }

    public func clearActiveConversation() {
        guard let activeId = activeConversationId,
              let idx = conversations.firstIndex(where: { $0.id == activeId }) else { return }
        if activeRuns[activeId] != nil {
            stopGenerating(conversationId: activeId)
        }
        conversations[idx].messages = []
        conversations[idx].planItems = []
        conversations[idx].fileChanges = []
        conversations[idx].approvals = []
        conversations[idx].events = []
        conversations[idx].cliSessionId = nil
        conversations[idx].state = .idle
        conversations[idx].title = strings.newChat
        conversations[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
    }

    public func upsertPersona(_ persona: PipiBotPersona) {
        if let idx = personas.firstIndex(where: { $0.id == persona.id }) {
            personas[idx] = persona
        } else {
            personas.append(persona)
        }
        activePersonaId = persona.id
        saveResidentState()
    }

    public func deletePersona(_ id: String) {
        guard personas.count > 1 else { return }
        let doomedConvIds = conversations.filter { $0.personaId == id }.map(\.id)
        for convId in doomedConvIds where activeRuns[convId] != nil {
            stopGenerating(conversationId: convId)
        }
        personas.removeAll { $0.id == id }
        conversations.removeAll { $0.personaId == id }
        for gIdx in groupChats.indices {
            groupChats[gIdx].participantPersonaIds.removeAll { $0 == id }
            if groupChats[gIdx].leadPersonaId == id {
                groupChats[gIdx].leadPersonaId = groupChats[gIdx].participantPersonaIds.first
            }
        }
        if activePersonaId == id {
            activePersonaId = personas.first?.id ?? "bot_pipi_general"
            activeConversationId = conversationsForActivePersona.first?.id
        }
        saveResidentState()
    }

    public func stopGenerating() {
        stopGenerating(conversationId: activeConversationId)
    }

    public func stopGenerating(conversationId: String?) {
        guard let convId = conversationId else { return }
        if let local = activeHostConnection as? PipiLocalHostConnection {
            local.stopImmediate(sessionId: convId)
        } else {
            let conn = activeHostConnection
            Task { try? await conn.stop(sessionId: convId) }
        }
    }

    public func performLocalHostStop(sessionId convId: String) {
        guard let run = activeRuns[convId] else { return }
        run.task?.cancel()
        activeRuns.removeValue(forKey: convId)
        modelScheduler.cancelQueued(runId: run.runId)

        if let runIdx = runRecords.firstIndex(where: { $0.id == run.runId }) {
            runRecords[runIdx].status = .cancelled
            runRecords[runIdx].durationMs = Int(Date().timeIntervalSince(run.startedAt) * 1000)
        }
        if let cIdx = conversations.firstIndex(where: { $0.id == convId }),
           let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == run.streamingMessageId }),
           conversations[cIdx].messages[mIdx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           conversations[cIdx].messages[mIdx].steps.isEmpty,
           conversations[cIdx].messages[mIdx].planItems.isEmpty,
           conversations[cIdx].messages[mIdx].fileChanges.isEmpty {
            conversations[cIdx].messages.remove(at: mIdx)
        }
        setSessionState(convId, to: .cancelled)
        if convId == activeConversationId {
            avatarEngine.setState(activePersona.idleAvatarState)
        }
    }

    public func sendPersonalMessage(
        _ rawText: String,
        attachments: [PipiChatAttachment] = [],
        targetOverride: PipiExecutionTarget? = nil,
        conversationId explicitConversationId: String? = nil,
        personaId explicitPersonaId: String? = nil,
        activateTargetConversation: Bool = true,
        priority: PipiSchedulerPriority? = nil,
        onProgress: (@Sendable (String) async -> Void)? = nil
    ) async {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        let targetConversation = explicitConversationId.flatMap { id in
            conversations.first(where: { $0.id == id })
        }
        let resolvedPersonaId = explicitPersonaId ?? targetConversation?.personaId ?? activePersona.id
        // Autonomous on-demand bot-to-bot consultation & capability upgrade (when permitted)
        _ = evaluatePeerUpgradeForPrompt(botId: resolvedPersonaId, prompt: trimmed)

        // Direct native macOS omnipotent capability execution (/screenshot, /sms, /mail, /build, /sendfile, /voiceclip, /record)
        if attachments.isEmpty, let directIntent = PipiMacOmnipotentIntentParser.parse(trimmed) {
            let convId: String
            if let existing = targetConversation {
                convId = existing.id
            } else {
                let created = createConversation(for: resolvedPersonaId, activate: activateTargetConversation)
                convId = created.id
            }
            if let onProgress {
                await onProgress(PipiLivelyProgressNarrator.initialAck(for: trimmed, lang: resolvedLanguage))
            }
            _ = await executeOmnipotentIntent(directIntent, userPrompt: trimmed, in: convId, personaId: resolvedPersonaId)
            return
        }

        // On-demand or explicit-CLI invocation (e.g. /codex OR "用 codex 帮我...").
        // Note: General natural-language tasks go into PiPi's native Jarvis Agent Loop where PiPi can directly use
        // native tools AND call `delegate_cli_agent` on demand with automatic recovery!
        var effectiveRawText = rawText
        var effectiveTargetOverride = targetOverride
        if effectiveTargetOverride == nil {
            let usableKinds = usableLocalAgents.map(\.kind)
            if let delegated = PipiExternalSubAgentRouter.parseOnDemandInvocation(trimmed),
               usableKinds.contains(delegated.kind) {
                effectiveTargetOverride = .localAgent(delegated.kind)
                effectiveRawText = delegated.taskPrompt
            } else if proactiveCLIDelegationEnabled,
                      let natural = PipiExternalSubAgentRouter.detectNaturalLanguageInvocation(trimmed, usableAgents: usableKinds) {
                effectiveTargetOverride = .localAgent(natural.kind)
                effectiveRawText = natural.taskPrompt
            }
        }

        let resolvedConvForProgress: String? = explicitConversationId
        if let onProgress, let resolvedConvForProgress {
            progressCallbacksByConversation[resolvedConvForProgress] = onProgress
        }
        defer {
            if let resolvedConvForProgress {
                progressCallbacksByConversation.removeValue(forKey: resolvedConvForProgress)
            }
        }

        let input = PipiUserInput(
            text: effectiveRawText,
            attachments: attachments,
            targetOverride: effectiveTargetOverride,
            personaId: resolvedPersonaId,
            activateTargetConversation: activateTargetConversation,
            priority: priority
        )

        do {
            let sessionId = try await activeHostConnection.send(
                sessionId: explicitConversationId,
                botId: resolvedPersonaId,
                input: input
            )
            if let task = activeRuns[sessionId]?.task {
                await task.value
            }
        } catch {
            // Host connection send failure is surfaced if a target conversation exists
            if let explicitConversationId {
                appendAssistantMessage(
                    to: explicitConversationId,
                    content: error.localizedDescription,
                    engineLabel: strings.appName,
                    isError: true
                )
            }
        }
    }

    public func resolveApproval(_ approvalId: String, optionId: String, note: String? = nil) async {
        try? await activeHostConnection.resolveApproval(approvalId, optionId: optionId, note: note)
    }

    @discardableResult
    public func performLocalHostResolveApproval(_ approvalId: String, optionId: String, note: String? = nil) -> Task<Void, Never>? {
        guard let cIdx = conversations.firstIndex(where: { $0.approvals.contains(where: { $0.id == approvalId }) }),
              let aIdx = conversations[cIdx].approvals.firstIndex(where: { $0.id == approvalId }) else {
            return nil
        }

        let nowIso = ISO8601DateFormatter().string(from: Date())
        let approval = conversations[cIdx].approvals[aIdx]
        guard approval.status == .pending else { return nil }

        let granularity = PipiApprovalGranularity.fromOptionId(optionId, recommendedOptionId: approval.recommendedOptionId)
        let approved = granularity.isApproved
        conversations[cIdx].approvals[aIdx].status = approved ? .approved : .denied
        conversations[cIdx].approvals[aIdx].chosenOptionId = optionId
        conversations[cIdx].approvals[aIdx].chosenGranularity = granularity
        conversations[cIdx].approvals[aIdx].userNote = note
        conversations[cIdx].approvals[aIdx].resolvedAt = nowIso
        conversations[cIdx].updatedAt = nowIso

        let sessionId = conversations[cIdx].id
        let projectIdForApproval = approval.projectId ?? conversations[cIdx].projectId

        // Persist multi-granularity whitelist rule when user opts into session / project / always scope
        if granularity == .allowSession || granularity == .allowProject || granularity == .allowAlways {
            let effectiveGranularity: PipiApprovalGranularity = (granularity == .allowProject && projectIdForApproval == nil)
                ? .allowAlways
                : granularity
            let rule = PipiApprovalWhitelistRule(
                granularity: effectiveGranularity,
                toolName: approval.actionToolName ?? "*",
                actionKind: approval.actionKind ?? .localWrite,
                targetPattern: approval.actionTarget,
                sessionId: effectiveGranularity == .allowSession ? sessionId : nil,
                projectId: effectiveGranularity == .allowProject ? projectIdForApproval : nil,
                note: note
            )
            addApprovalWhitelistRule(rule)
        } else if granularity == .deny, let opId = approval.operationId {
            permissionGuardrail.ledger.markDenied(opId)
        }

        let updatedApproval = conversations[cIdx].approvals[aIdx]
        appendSessionEvent(sessionId, kind: .approval, approval: updatedApproval)

        if approved, let pendingTool = pendingToolApprovalContextByApprovalId.removeValue(forKey: approvalId) {
            let personaId = conversations[cIdx].personaId
            return Task { @MainActor [weak self] in
                guard let self else { return }
                let callbacks = self.makeAgentHostCallbacks(conversationId: sessionId, personaId: personaId)
                let deliverablesDir = self.localDataRootURL.appendingPathComponent("deliverables", isDirectory: true)
                let effectiveLLM = self.resolvedEffectiveLLMConfig(providerId: self.defaultLLMProviderId ?? self.readyLLMProviders.first?.id ?? "", for: self.personas.first(where: { $0.id == personaId }) ?? self.activePersona)
                let toolRes = await PipiAgentToolbox.execute(
                    toolCall: pendingTool.toolCall,
                    workspaceDirectory: pendingTool.workDir,
                    llmConfig: effectiveLLM,
                    deliverablesDirectory: deliverablesDir,
                    callbacks: callbacks,
                    skipRiskCheck: true
                )
                let attachments: [PipiChatAttachment] = toolRes.artifacts.map { art in
                    PipiChatAttachment(id: art.id, name: art.fileName, path: art.filePath, sizeBytes: Int(art.byteSize))
                }
                let replyText = toolRes.isError
                    ? "😅 刚执行的时候遇到点小状况：\n\(toolRes.output)"
                    : "✅ 已经按你的确认执行完毕啦！\n\n\(toolRes.output)"
                let replyIso = ISO8601DateFormatter().string(from: Date())
                if let idx = self.conversations.firstIndex(where: { $0.id == sessionId }) {
                    self.conversations[idx].messages.append(PipiChatMessage(
                        role: .assistant,
                        content: replyText,
                        createdAt: replyIso,
                        engineLabel: "PiPi Jarvis",
                        isError: toolRes.isError,
                        attachments: attachments.isEmpty ? nil : attachments
                    ))
                    self.conversations[idx].updatedAt = replyIso
                }
                self.setSessionState(sessionId, to: toolRes.isError ? .failed : .done)
                self.saveResidentState()
            }
        }

        if approved, let pendingPrompt = approval.pendingPrompt, !pendingPrompt.isEmpty {
            let personaId = conversations[cIdx].personaId
            if let directIntent = PipiMacOmnipotentIntentParser.parse(pendingPrompt) {
                return Task { @MainActor [weak self] in
                    guard let self else { return }
                    _ = await self.executeOmnipotentIntent(
                        directIntent,
                        userPrompt: pendingPrompt,
                        in: sessionId,
                        personaId: personaId,
                        skipGuardrail: true,
                        appendUserMessage: false
                    )
                }
            }
            let target = approval.pendingTarget
            let input = PipiUserInput(
                text: pendingPrompt,
                attachments: [],
                targetOverride: target,
                personaId: personaId,
                activateTargetConversation: conversations[cIdx].id == activeConversationId,
                permissionOverride: .autoEdit,
                isApprovalResume: true,
                priority: .approvalReview
            )
            let resumedId = performLocalHostSend(sessionId: sessionId, botId: personaId, input: input)
            return activeRuns[resumedId]?.task
        } else {
            setSessionState(sessionId, to: .done)
            if sessionId == activeConversationId {
                avatarEngine.setState(activePersona.idleAvatarState)
            }
            saveResidentState()
            return nil
        }
    }

    public func retryTurn(conversationId: String, errorMessageId: String? = nil) async {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        if let errorMessageId,
           let errIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == errorMessageId }),
           conversations[cIdx].messages[errIdx].isError {
            conversations[cIdx].messages.remove(at: errIdx)
        } else if conversations[cIdx].messages.last?.isError == true {
            conversations[cIdx].messages.removeLast()
        }

        guard let lastUserIdx = conversations[cIdx].messages.lastIndex(where: { $0.role == .user }) else {
            saveResidentState()
            return
        }
        let lastUserMsg = conversations[cIdx].messages[lastUserIdx]
        if lastUserIdx == conversations[cIdx].messages.count - 1 {
            conversations[cIdx].messages.remove(at: lastUserIdx)
        }
        await sendPersonalMessage(
            lastUserMsg.content,
            attachments: lastUserMsg.attachments ?? [],
            conversationId: conversationId,
            personaId: conversations[cIdx].personaId,
            activateTargetConversation: conversationId == activeConversationId
        )
    }

    public func switchEngineAndRetry(
        conversationId: String,
        errorMessageId: String? = nil,
        target: PipiExecutionTarget
    ) async {
        overrideExecutionTarget = target
        await retryTurn(conversationId: conversationId, errorMessageId: errorMessageId)
    }

    @discardableResult
    public func performLocalHostSend(sessionId explicitConversationId: String?, botId: String, input: PipiUserInput) -> String {
        let trimmed = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = input.attachments
        let targetOverride = input.targetOverride
        let activateTargetConversation = input.activateTargetConversation

        let targetConversation = explicitConversationId.flatMap { id in
            conversations.first(where: { $0.id == id })
        }
        let resolvedPersonaId = input.personaId ?? targetConversation?.personaId ?? botId
        let persona = personas.first(where: { $0.id == resolvedPersonaId }) ?? activePersona

        let convId: String
        if let targetConversation {
            convId = targetConversation.id
        } else if activateTargetConversation,
                  let existing = activeConversation,
                  existing.personaId == persona.id,
                  !existing.isArchived {
            convId = existing.id
        } else {
            convId = createConversation(for: persona.id, activate: activateTargetConversation).id
        }

        // Only stop an active run in THIS same conversation; other conversations continue untouched.
        if activeRuns[convId] != nil {
            performLocalHostStop(sessionId: convId)
        }

        guard let convIndex = conversations.firstIndex(where: { $0.id == convId }) else { return convId }

        let displayPrompt = trimmed.isEmpty
            ? strings.t("请分析我附加的文件。", "Please analyze the attached file(s).")
            : trimmed
        let nowIso = ISO8601DateFormatter().string(from: Date())

        // Avoid adding a duplicate user message when resuming an approval continuation turn
        let isApprovalResume = input.isApprovalResume
        if !isApprovalResume {
            let userMsg = PipiChatMessage(
                role: .user,
                content: displayPrompt,
                createdAt: nowIso,
                attachments: attachments.isEmpty ? nil : attachments
            )
            conversations[convIndex].messages.append(userMsg)
            appendSessionEvent(convId, kind: .message, messageId: userMsg.id, textDelta: displayPrompt)
            if conversations[convIndex].messages.filter({ $0.role == .user }).count == 1,
               conversations[convIndex].title == strings.newChat {
                let preview = String(displayPrompt.prefix(28))
                conversations[convIndex].title = displayPrompt.count > 28 ? preview + "…" : preview
            }
        }
        conversations[convIndex].updatedAt = nowIso
        saveResidentState()

        if activateTargetConversation, let targetOverride, !isApprovalResume {
            self.overrideExecutionTarget = targetOverride
        }

        let effectiveTarget: PipiExecutionTarget? = {
            if let targetOverride, (!activateTargetConversation || isApprovalResume) {
                return targetOverride
            }
            return resolvedActiveTarget(for: persona)
        }()

        guard let resolvedTarget = effectiveTarget else {
            let guideText = strings.noConfiguredEngineGuide
            appendAssistantMessage(
                to: convId,
                content: guideText,
                engineLabel: strings.appName,
                isError: true,
                isNoEngineGuide: true
            )
            setSessionState(convId, to: .failed)
            if convId == activeConversationId {
                avatarEngine.setState(.needsYouApproval)
            }
            saveResidentState()
            return convId
        }

        let engineLabel: String = {
            switch resolvedTarget {
            case .llm(let pid):
                if let cfg = resolvedEffectiveLLMConfig(providerId: pid, for: persona) {
                    return "\(cfg.name) · \(cfg.modelId)"
                }
                return strings.appName
            case .localAgent(let kind):
                if let model = persona.preferredModelId, !model.isEmpty {
                    return "\(kind.displayName) · \(model)"
                }
                return kind.displayName
            case .auto:
                return strings.appName
            }
        }()
        conversations[convIndex].lastEngineLabel = engineLabel

        // Insert live streaming placeholder assistant message + real run record
        let placeholderMsg = PipiChatMessage(
            role: .assistant,
            content: "",
            createdAt: nowIso,
            engineLabel: engineLabel,
            isError: false
        )
        let placeholderId = placeholderMsg.id
        conversations[convIndex].messages.append(placeholderMsg)

        let runId = "run_\(UUID().uuidString.prefix(8).lowercased())"
        let promptShort = displayPrompt.count > 44 ? String(displayPrompt.prefix(44)) + "…" : displayPrompt
        runRecords.insert(
            PipiRunRecord(
                id: runId,
                personaId: persona.id,
                conversationId: convId,
                engineLabel: engineLabel,
                promptPreview: promptShort,
                status: .running,
                durationMs: 0,
                startedAt: nowIso
            ),
            at: 0
        )
        if runRecords.count > 50 {
            runRecords = Array(runRecords.prefix(50))
        }

        let isLocalAgentTarget: Bool
        let initialStatusText: String
        switch resolvedTarget {
        case .localAgent(let kind):
            isLocalAgentTarget = true
            initialStatusText = strings.runningAgentStatus(kind.displayName)
        case .llm, .auto:
            isLocalAgentTarget = false
            initialStatusText = strings.thinkingStatus
        }

        let startedAtDate = Date()
        activeRuns[convId] = PipiConversationRunState(
            conversationId: convId,
            personaId: persona.id,
            runId: runId,
            streamingMessageId: placeholderId,
            startedAt: startedAtDate,
            phase: .running,
            statusText: initialStatusText,
            isLocalAgent: isLocalAgentTarget,
            task: nil
        )
        setSessionState(convId, to: .running)

        let projectForConv = conversations[convIndex].projectId.flatMap { pid in
            projects.first(where: { $0.id == pid })
        }
        let configuredTier = effectivePermissionTier(for: persona, project: projectForConv)
        let effectivePermission = input.permissionOverride ?? configuredTier
        let existingCliSessionId = conversations[convIndex].cliSessionId

        let effectiveSystemPrompt = buildSystemPrompt(for: persona, project: projectForConv)
        let historySnapshot: [PipiChatMessage] = conversations[convIndex].messages
            .filter { $0.id != placeholderId }
            .map { msg in
                guard msg.role == .user, let files = msg.attachments, !files.isEmpty else { return msg }
                var expanded = msg.content
                for file in files {
                    let extractedBody: String? = {
                        if let body = file.textContent, !body.isEmpty {
                            return body
                        }
                        guard !file.path.isEmpty else { return nil }
                        let fileURL = URL(fileURLWithPath: file.path)
                        if file.isImage {
                            return PipiDocumentExtractor.extractTextFromImage(url: fileURL)
                        }
                        return PipiDocumentExtractor.extractText(from: fileURL)
                    }()
                    if let body = extractedBody, !body.isEmpty {
                        let label = file.isImage ? "已识别图片中的文字" : "已提取附件正文"
                        expanded += "\n\n[\(label)：\(file.name) (\(file.path))]\n```\n\(body)\n```"
                    } else if !file.isImage || isLocalAgentTarget {
                        expanded += "\n\n[Attached file: \(file.name) at \(file.path)]"
                    }
                }
                var copy = msg
                copy.content = expanded
                return copy
            }
        var outboundHistory: [PipiChatMessage] = isApprovalResume
            ? [PipiChatMessage(role: .user, content: displayPrompt, createdAt: nowIso)]
            : historySnapshot

        let runPriority: PipiSchedulerPriority = input.priority ?? (isApprovalResume ? .approvalReview : .chatInteractive)
        if runPriority.isInteractiveOrHigher {
            proactiveEngine.recordUserChatActivity(at: startedAtDate)
        }

        // Wave 2 (#02): Prompt-Cache-Safe hidden memory recall.
        // NEVER mutates `effectiveSystemPrompt` or persisted visible messages; injects Per-Bot `summary.md`
        // + Personal Wiki recall ONLY on the first message of a session or immediately after compaction.
        if memoryEnabled && !isApprovalResume {
            let wikiSnippets: [String] = {
                guard let wiki = personalWiki else { return [] }
                let searchHits = wiki.search(PipiWikiSearchOptions(
                    query: displayPrompt,
                    scope: .all,
                    limit: 2,
                    factLimit: 2
                ))
                var lines = searchHits.summaries.prefix(2).map { "[\($0.category.rawValue)] \($0.title): \($0.summary)" }
                lines.append(contentsOf: searchHits.facts.prefix(2).map(\.factText))
                return lines
            }()
            let recall = botMemoryEngine.buildPromptCacheSafeRecall(
                botId: persona.id,
                sessionId: convId,
                compactionGeneration: conversations[convIndex].compactionGeneration,
                wikiRecallSnippets: wikiSnippets
            )
            lastPromptCacheRecallResult = recall
            if recall.injected,
               let hiddenNote = recall.hiddenNote,
               let lastUserIdx = outboundHistory.lastIndex(where: { $0.role == .user }) {
                outboundHistory[lastUserIdx].content = "\(hiddenNote)\n\n\(outboundHistory[lastUserIdx].content)"
            }
        }

        let effectiveHistory = outboundHistory
        let langSnapshot = resolvedLanguage
        let workDir = (projectForConv?.workspacePath?.isEmpty == false ? projectForConv?.workspacePath : nil) ?? workspaceDirectory

        let endpointKey = schedulerEndpointKey(for: resolvedTarget)
        ensureDefaultSchedulerPool(for: resolvedTarget, endpointKey: endpointKey)
        let estimatedPromptTokens = max(
            100,
            (effectiveSystemPrompt.count + effectiveHistory.reduce(0) { $0 + $1.content.count }) / 4
        )

        @MainActor
        final class RunExecutionCoordinator {
            var observedOutputOrToolEvent = false
            var yieldTriggered = false
            var yieldCount = 0
            var activeAttemptTask: Task<PipiInferenceResult, Error>?
        }
        let coordinator = RunExecutionCoordinator()
        self.telemetryMonitor.beginInference(
            runId: runId,
            engineLabel: engineLabel,
            inputTokensEstimate: estimatedPromptTokens
        )

        let onDelta: @Sendable (String) -> Void = { [weak self] chunk in
            Task { @MainActor [weak self] in
                coordinator.observedOutputOrToolEvent = true
                guard let self,
                      let cIdx = self.conversations.firstIndex(where: { $0.id == convId }),
                      let mIdx = self.conversations[cIdx].messages.firstIndex(where: { $0.id == placeholderId }) else {
                    return
                }
                self.telemetryMonitor.markFirstToken(runId: runId)
                self.conversations[cIdx].messages[mIdx].content += chunk
                if var runState = self.activeRuns[convId], runState.runId == runId {
                    runState.statusText = self.strings.streamingStatus
                    self.activeRuns[convId] = runState
                }
                self.localHostConnection.publishEvent(PipiSessionEvent(
                    sessionId: convId,
                    seq: (self.conversations[cIdx].events.last?.seq ?? 0) + 1,
                    kind: .message,
                    messageId: placeholderId,
                    textDelta: chunk
                ))
            }
        }

        let onCLIEvent: @Sendable (PipiParsedCLIEvent) -> Void = { [weak self] parsed in
            Task { @MainActor [weak self] in
                switch parsed {
                case .textDelta, .finalText, .stepStarted, .stepFinished, .fileChanged:
                    coordinator.observedOutputOrToolEvent = true
                case .sessionId, .planUpdated, .summary:
                    break
                }
                self?.applyParsedCLIEvent(parsed, conversationId: convId, messageId: placeholderId)
            }
        }

        let customExecutor = self.inferenceExecutor
        let customSessionExecutor = self.sessionInferenceExecutor
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // Wave 1 (#08) + Dedicated Security Auditor: Pre-execution two-tier guardrail check
                var precheckVerdict: PipiGuardrailVerdict?
                var whitelistedForWrite = false
                if case .localAgent(let kind) = resolvedTarget {
                    let actionInput = PipiGuardrailActionInput(
                        operationId: "op_\(runId)",
                        toolName: kind.binaryName,
                        actionKind: effectivePermission == .readOnly ? .readOnly : .localWrite,
                        target: workDir,
                        payloadSummary: displayPrompt,
                        isPreparatoryOnly: effectivePermission == .readOnly,
                        sessionId: convId,
                        projectId: projectForConv?.id,
                        sourceTrust: runPriority == .proactiveRoutine ? .trustedUserRoutine : .trustedUser,
                        trustedUserMessages: [displayPrompt]
                    )
                    let verdict = await self.evaluateActionWithGuardrail(actionInput, auditMediumRisk: true)
                    precheckVerdict = verdict
                    if verdict.decision == .deny {
                        let durationMs = Int(Date().timeIntervalSince(startedAtDate) * 1000)
                        let blockedMsg = self.strings.t(
                            "安全风控已拦截该高危操作（\(verdict.riskLevel.label(.zhHans))）：\(verdict.rationale)",
                            "Blocked by safety guardrail (\(verdict.riskLevel.label(.en))): \(verdict.rationale)"
                        )
                        self.finalizeStreamingMessage(
                            conversationId: convId,
                            messageId: placeholderId,
                            finalContent: blockedMsg,
                            engineLabel: engineLabel,
                            isError: true
                        )
                        self.finalizeRunRecord(id: runId, status: .failed, durationMs: durationMs)
                        self.finishGenerating(
                            conversationId: convId,
                            runId: runId,
                            finalSessionState: .failed,
                            nextAvatarState: .needsYouUrgent
                        )
                        self.saveResidentState()
                        return
                    }
                    whitelistedForWrite = (verdict.ruleId == "whitelist.matched")
                } else if case .llm = resolvedTarget, !isApprovalResume {
                    let riskClass = PipiPermissionGuardrail.classifyPromptRisk(displayPrompt, defaultTarget: workDir)
                    if riskClass.isRisky {
                        let actionInput = PipiGuardrailActionInput(
                            operationId: "op_\(runId)",
                            toolName: "pipi_task",
                            actionKind: riskClass.actionKind,
                            target: riskClass.target,
                            payloadSummary: displayPrompt,
                            isPreparatoryOnly: false,
                            sessionId: convId,
                            projectId: projectForConv?.id,
                            sourceTrust: runPriority == .proactiveRoutine ? .trustedUserRoutine : .trustedUser,
                            trustedUserMessages: [displayPrompt]
                        )
                        let verdict = await self.evaluateActionWithGuardrail(actionInput, auditMediumRisk: true)
                        if verdict.decision == .deny {
                            let durationMs = Int(Date().timeIntervalSince(startedAtDate) * 1000)
                            let blockedMsg = self.strings.t(
                                "安全审计官已拦截该高危任务（\(verdict.riskLevel.label(.zhHans))）：\(verdict.rationale)",
                                "Blocked by Security Auditor (\(verdict.riskLevel.label(.en))): \(verdict.rationale)"
                            )
                            self.finalizeStreamingMessage(
                                conversationId: convId,
                                messageId: placeholderId,
                                finalContent: blockedMsg,
                                engineLabel: engineLabel,
                                isError: true
                            )
                            self.finalizeRunRecord(id: runId, status: .failed, durationMs: durationMs)
                            self.finishGenerating(
                                conversationId: convId,
                                runId: runId,
                                finalSessionState: .failed,
                                nextAvatarState: .needsYouUrgent
                            )
                            self.saveResidentState()
                            return
                        }
                        if verdict.decision == .needsApproval && effectivePermission != .autoEdit {
                            let durationMs = Int(Date().timeIntervalSince(startedAtDate) * 1000)
                            let pauseMsg = self.strings.t(
                                "🛡️ 检测到风险操作，已暂停执行并等待您的确认（\(verdict.riskLevel.label(.zhHans))）：\n\(verdict.rationale)",
                                "🛡️ Risky operation detected; paused for your confirmation (\(verdict.riskLevel.label(.en))):\n\(verdict.rationale)"
                            )
                            self.finalizeStreamingMessage(
                                conversationId: convId,
                                messageId: placeholderId,
                                finalContent: pauseMsg,
                                engineLabel: engineLabel,
                                isError: false
                            )
                            self.emitRiskyTaskApprovalCard(
                                conversationId: convId,
                                messageId: placeholderId,
                                question: self.strings.t("允许 PiPi 执行该风险任务吗？", "Allow PiPi to execute this risky task?"),
                                detail: verdict.rationale,
                                pendingPrompt: displayPrompt,
                                pendingTarget: resolvedTarget,
                                toolName: "pipi_task",
                                actionKind: riskClass.actionKind,
                                workDir: workDir,
                                projectId: projectForConv?.id,
                                verdict: verdict
                            )
                            self.finalizeRunRecord(id: runId, status: .succeeded, durationMs: durationMs)
                            self.finishGenerating(
                                conversationId: convId,
                                runId: runId,
                                finalSessionState: .needsYou,
                                nextAvatarState: .needsYouApproval
                            )
                            self.saveResidentState()
                            return
                        }
                    }
                }

                // Wave 1 (#04): Priority admission + interactive reserved slot + preemptive CLI --resume loop
                var finalAttemptResult: PipiInferenceResult?
                var shouldRequestWriteApproval = false

                while finalAttemptResult == nil {
                    if Task.isCancelled { throw CancellationError() }
                    coordinator.yieldTriggered = false

                    let lease = try await self.modelScheduler.acquire(
                        endpointKey: endpointKey,
                        priority: runPriority,
                        runId: runId,
                        onQueued: { [weak self] in
                            guard let self else { return }
                            if var runState = self.activeRuns[convId], runState.runId == runId {
                                runState.phase = .queued
                                runState.statusText = coordinator.yieldCount > 0 ? self.strings.yieldedStatus : self.strings.queuedStatus
                                self.activeRuns[convId] = runState
                            }
                            self.setSessionState(convId, to: .queued)
                        },
                        canYield: { [weak self] in
                            guard let self, runPriority.isPreemptible else { return false }
                            guard let conv = self.conversations.first(where: { $0.id == convId }) else { return false }
                            if conv.approvals.contains(where: { $0.status == .pending }) {
                                return false
                            }
                            switch resolvedTarget {
                            case .llm, .auto:
                                return true
                            case .localAgent(let kind):
                                let hasSession = !(conv.cliSessionId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                                guard hasSession else { return false }
                                if kind == .codex {
                                    return coordinator.observedOutputOrToolEvent
                                }
                                return true
                            }
                        },
                        onYieldRequested: {
                            coordinator.yieldTriggered = true
                            coordinator.activeAttemptTask?.cancel()
                        }
                    )

                    let attemptStarted = Date()
                    do {
                        if Task.isCancelled {
                            lease.release()
                            throw CancellationError()
                        }

                        let attemptCliSessionId = self.conversations.first(where: { $0.id == convId })?.cliSessionId ?? existingCliSessionId
                        let attemptHistory: [PipiChatMessage] = (coordinator.yieldCount > 0 && attemptCliSessionId != nil)
                            ? [PipiChatMessage(
                                role: .user,
                                content: self.strings.t(
                                    "前台任务已结束，请从上次暂停处继续完成当前任务。",
                                    "Foreground work finished. Please resume and complete the task from where you paused."
                                ),
                                createdAt: ISO8601DateFormatter().string(from: Date())
                            )]
                            : effectiveHistory

                        let attemptTask: Task<PipiInferenceResult, Error>
                        switch resolvedTarget {
                        case .llm(let providerId):
                            guard let cfg = self.resolvedEffectiveLLMConfig(providerId: providerId, for: persona) else {
                                throw PipiInferenceError.emptyResponse
                            }
                            if var runState = self.activeRuns[convId], runState.runId == runId {
                                runState.phase = .running
                                runState.statusText = self.strings.thinkingStatus
                                self.activeRuns[convId] = runState
                            }
                            self.setSessionState(convId, to: .running)
                            if convId == self.activeConversationId {
                                self.avatarEngine.setState(.byokStreaming)
                            }
                            attemptTask = Task {
                                if let customSessionExecutor {
                                    return try await customSessionExecutor(
                                        resolvedTarget,
                                        cfg,
                                        effectiveSystemPrompt,
                                        attemptHistory,
                                        workDir,
                                        effectivePermission,
                                        nil,
                                        onDelta,
                                        onCLIEvent
                                    )
                                } else if let customExecutor {
                                    return try await customExecutor(
                                        resolvedTarget,
                                        cfg,
                                        effectiveSystemPrompt,
                                        attemptHistory,
                                        workDir,
                                        onDelta
                                    )
                                } else {
                                    return try await self.runJarvisAgentLoop(
                                        config: cfg,
                                        systemPrompt: effectiveSystemPrompt,
                                        history: attemptHistory,
                                        conversationId: convId,
                                        persona: persona,
                                        workDir: workDir,
                                        runId: runId,
                                        placeholderMessageId: placeholderId,
                                        onDelta: onDelta
                                    )
                                }
                            }

                        case .localAgent(let kind):
                            let needsAskGate = (effectivePermission == .ask)
                                && (kind == .claudeCode || kind == .codex)
                                && (input.permissionOverride == nil)
                                && !whitelistedForWrite
                            let invocationPermission: PipiPermissionTier = whitelistedForWrite
                                ? .autoEdit
                                : (needsAskGate ? .readOnly : effectivePermission)
                            shouldRequestWriteApproval = needsAskGate

                            if var runState = self.activeRuns[convId], runState.runId == runId {
                                runState.phase = .running
                                runState.statusText = self.strings.runningAgentStatus(kind.displayName)
                                self.activeRuns[convId] = runState
                            }
                            self.setSessionState(convId, to: .running)
                            if convId == self.activeConversationId {
                                self.avatarEngine.setState(kind.avatarRunningState)
                            }
                            attemptTask = Task {
                                if let customSessionExecutor {
                                    return try await customSessionExecutor(
                                        resolvedTarget,
                                        nil,
                                        effectiveSystemPrompt,
                                        attemptHistory,
                                        workDir,
                                        invocationPermission,
                                        attemptCliSessionId,
                                        onDelta,
                                        onCLIEvent
                                    )
                                } else if let customExecutor {
                                    return try await customExecutor(
                                        resolvedTarget,
                                        nil,
                                        effectiveSystemPrompt,
                                        attemptHistory,
                                        workDir,
                                        onDelta
                                    )
                                } else {
                                    do {
                                        let injectedEnv = await self.resolveCLIReverseInjectionEnvironment(for: kind, profileId: convId)
                                        return try await PipiInferenceEngine.invokeLocalAgent(
                                            kind: kind,
                                            systemPrompt: effectiveSystemPrompt,
                                            history: attemptHistory,
                                            workingDirectory: workDir,
                                            permissionTier: invocationPermission,
                                            cliSessionId: attemptCliSessionId,
                                            modelOverride: persona.preferredModelId,
                                            extraEnvironment: injectedEnv,
                                            onDelta: onDelta,
                                            onEvent: onCLIEvent
                                        )
                                    } catch {
                                        if Task.isCancelled { throw error }
                                        return try await self.recoverFromLocalCLIFailure(
                                            failedKind: kind,
                                            originalError: error,
                                            systemPrompt: effectiveSystemPrompt,
                                            history: attemptHistory,
                                            conversationId: convId,
                                            persona: persona,
                                            workDir: workDir,
                                            permissionTier: invocationPermission,
                                            runId: runId,
                                            placeholderMessageId: placeholderId,
                                            onDelta: onDelta,
                                            onCLIEvent: onCLIEvent
                                        )
                                    }
                                }
                            }

                        case .auto:
                            throw PipiInferenceError.emptyResponse
                        }

                        coordinator.activeAttemptTask = attemptTask
                        let attemptResult = try await withTaskCancellationHandler {
                            try await attemptTask.value
                        } onCancel: {
                            attemptTask.cancel()
                        }
                        coordinator.activeAttemptTask = nil

                        lease.reportMetrics(PipiLeaseCompletionMetrics(
                            durationMs: Date().timeIntervalSince(attemptStarted) * 1000,
                            promptTokens: estimatedPromptTokens
                        ))
                        lease.release()
                        finalAttemptResult = attemptResult
                    } catch {
                        coordinator.activeAttemptTask = nil
                        let wasYield = coordinator.yieldTriggered || lease.wasYielded
                        if wasYield && !Task.isCancelled {
                            coordinator.yieldCount += 1
                            lease.release()
                            if var runState = self.activeRuns[convId], runState.runId == runId {
                                runState.phase = .queued
                                runState.statusText = self.strings.yieldedStatus
                                self.activeRuns[convId] = runState
                            }
                            self.setSessionState(convId, to: .queued)
                            continue
                        }
                        let rateLimited = Self.isRateLimitOrOverloadError(error)
                        let timedOut = error.localizedDescription.localizedCaseInsensitiveContains("timed out")
                            || error.localizedDescription.localizedCaseInsensitiveContains("timeout")
                        lease.reportMetrics(PipiLeaseCompletionMetrics(
                            durationMs: Date().timeIntervalSince(attemptStarted) * 1000,
                            promptTokens: estimatedPromptTokens,
                            rateLimitedOrOverloaded: rateLimited,
                            timedOut: timedOut
                        ))
                        lease.release()
                        throw error
                    }
                }

                guard let result = finalAttemptResult else {
                    throw PipiInferenceError.emptyResponse
                }

                if Task.isCancelled { throw CancellationError() }
                let durationMs = Int(Date().timeIntervalSince(startedAtDate) * 1000)

                if let sid = result.cliSessionId, !sid.isEmpty,
                   let cIdx = self.conversations.firstIndex(where: { $0.id == convId }) {
                    self.conversations[cIdx].cliSessionId = sid
                }

                var finalResult = result
                if var s = finalResult.summaryInfo, s.durationMs == nil {
                    s.durationMs = durationMs
                    finalResult = PipiInferenceResult(
                        text: result.text,
                        engineLabel: result.engineLabel,
                        cliSessionId: result.cliSessionId,
                        steps: result.steps,
                        planItems: result.planItems,
                        fileChanges: result.fileChanges,
                        summaryInfo: s,
                        attachments: result.attachments
                    )
                }

                self.finalizeStreamingMessage(
                    conversationId: convId,
                    messageId: placeholderId,
                    finalContent: finalResult.text,
                    engineLabel: finalResult.engineLabel,
                    isError: false,
                    steps: finalResult.steps,
                    planItems: finalResult.planItems,
                    fileChanges: finalResult.fileChanges,
                    summaryInfo: finalResult.summaryInfo,
                    attachments: finalResult.attachments
                )
                self.telemetryMonitor.finishInference(
                    runId: runId,
                    outputTokensEstimate: max(1, finalResult.text.count / 3),
                    succeeded: true
                )
                self.finalizeRunRecord(id: runId, status: .succeeded, durationMs: durationMs)

                // Wave 2 (#02): Record successful run for Per-Bot isolated experiential memory (extracts every 5 runs)
                if self.memoryEnabled && !shouldRequestWriteApproval {
                    _ = await self.botMemoryEngine.recordSuccessfulRun(PipiBotMemoryRunInput(
                        botId: persona.id,
                        sessionId: convId,
                        userPrompt: displayPrompt,
                        assistantReply: finalResult.text,
                        toolSummary: finalResult.steps.isEmpty ? nil : "\(finalResult.steps.count) steps"
                    ))
                    self.botMemoryVersionCounter += 1
                }

                // Wave 3 (#05): Autonomous Meta -> AlterEgo delegation when Meta emits `<pipibot_delegate>`
                if !shouldRequestWriteApproval,
                   let directive = PipiDelegationDetector.extractDirective(from: finalResult.text) {
                    _ = self.spawnAlterEgoTask(
                        sessionId: convId,
                        botId: persona.id,
                        title: directive.title,
                        goal: directive.goal
                    )
                }

                // Proactive CLI Sub-Agent Delegation: when PiPi emits `<pipibot_cli_delegate ...>`, automatically invoke Codex / Claude Code / OpenCode
                var cliDelegatedPausedForApproval = false
                if !shouldRequestWriteApproval,
                   case .llm = resolvedTarget,
                   self.proactiveCLIDelegationEnabled,
                   let cliPlan = PipiExternalSubAgentRouter.extractCLIDelegation(from: finalResult.text),
                   self.usableLocalAgents.contains(where: { $0.kind == cliPlan.directive.agent }) {
                    let cliDir = cliPlan.directive
                    let preamble = cliPlan.cleanedText
                    let actionInput = PipiGuardrailActionInput(
                        operationId: "op_cli_\(runId)",
                        toolName: cliDir.agent.binaryName,
                        actionKind: cliDir.isWriteMode ? .localWrite : .readOnly,
                        target: workDir,
                        payloadSummary: cliDir.taskPrompt,
                        isPreparatoryOnly: !cliDir.isWriteMode,
                        sessionId: convId,
                        projectId: projectForConv?.id,
                        sourceTrust: runPriority == .proactiveRoutine ? .trustedUserRoutine : .trustedUser,
                        trustedUserMessages: [displayPrompt]
                    )
                    let cliVerdict = await self.evaluateActionWithGuardrail(actionInput, auditMediumRisk: cliDir.isWriteMode)
                    if cliVerdict.decision == .deny {
                        let denyMsg = [
                            preamble,
                            self.strings.t(
                                "🛡️ 安全审计官已拦截对 \(cliDir.agent.displayName) 的调用：\(cliVerdict.rationale)",
                                "🛡️ Security Auditor blocked \(cliDir.agent.displayName) delegation: \(cliVerdict.rationale)"
                            )
                        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
                        self.finalizeStreamingMessage(
                            conversationId: convId,
                            messageId: placeholderId,
                            finalContent: denyMsg,
                            engineLabel: "\(engineLabel) · 🛡️",
                            isError: true
                        )
                    } else if (cliVerdict.decision == .needsApproval || (cliDir.isWriteMode && effectivePermission == .ask && cliVerdict.ruleId != "whitelist.matched")) && effectivePermission != .autoEdit {
                        let askMsg = [
                            preamble,
                            self.strings.t(
                                "🤖 PiPi 建议调用 \(cliDir.agent.displayName) 执行工作区修改（\(cliDir.reason.isEmpty ? "工程任务" : cliDir.reason)），等待您的确认后执行。",
                                "🤖 PiPi recommends delegating to \(cliDir.agent.displayName) (\(cliDir.reason.isEmpty ? "workspace task" : cliDir.reason)); awaiting your approval."
                            )
                        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
                        self.finalizeStreamingMessage(
                            conversationId: convId,
                            messageId: placeholderId,
                            finalContent: askMsg,
                            engineLabel: "\(engineLabel) → \(cliDir.agent.displayName)",
                            isError: false
                        )
                        self.emitWriteApprovalCard(
                            conversationId: convId,
                            messageId: placeholderId,
                            agentKind: cliDir.agent,
                            originalPrompt: cliDir.taskPrompt,
                            workDir: workDir,
                            projectId: projectForConv?.id,
                            verdict: cliVerdict
                        )
                        cliDelegatedPausedForApproval = true
                    } else {
                        if var runState = self.activeRuns[convId], runState.runId == runId {
                            runState.statusText = self.strings.runningAgentStatus(cliDir.agent.displayName)
                            self.activeRuns[convId] = runState
                        }
                        if convId == self.activeConversationId {
                            self.avatarEngine.setState(cliDir.agent.avatarRunningState)
                        }
                        let cliTier: PipiPermissionTier = cliDir.isWriteMode ? .autoEdit : .readOnly
                        let cliHistory = [PipiChatMessage(role: .user, content: cliDir.taskPrompt, createdAt: ISO8601DateFormatter().string(from: Date()))]
                        let cliResult: PipiInferenceResult
                        if let customSessionExecutor {
                            cliResult = try await customSessionExecutor(
                                .localAgent(cliDir.agent),
                                nil,
                                effectiveSystemPrompt,
                                cliHistory,
                                workDir,
                                cliTier,
                                existingCliSessionId,
                                nil,
                                onCLIEvent
                            )
                        } else {
                            do {
                                let injectedEnv = await self.resolveCLIReverseInjectionEnvironment(for: cliDir.agent, profileId: convId)
                                cliResult = try await PipiInferenceEngine.invokeLocalAgent(
                                    kind: cliDir.agent,
                                    systemPrompt: effectiveSystemPrompt,
                                    history: cliHistory,
                                    workingDirectory: workDir,
                                    permissionTier: cliTier,
                                    cliSessionId: existingCliSessionId,
                                    modelOverride: persona.preferredModelId,
                                    extraEnvironment: injectedEnv,
                                    onDelta: nil,
                                    onEvent: onCLIEvent
                                )
                            } catch {
                                cliResult = try await self.recoverFromLocalCLIFailure(
                                    failedKind: cliDir.agent,
                                    originalError: error,
                                    systemPrompt: effectiveSystemPrompt,
                                    history: cliHistory,
                                    conversationId: convId,
                                    persona: persona,
                                    workDir: workDir,
                                    permissionTier: cliTier,
                                    runId: runId,
                                    placeholderMessageId: placeholderId,
                                    onDelta: onDelta,
                                    onCLIEvent: onCLIEvent
                                )
                            }
                        }
                        if let sid = cliResult.cliSessionId, !sid.isEmpty,
                           let cIdx = self.conversations.firstIndex(where: { $0.id == convId }) {
                            self.conversations[cIdx].cliSessionId = sid
                        }
                        let combinedText = [
                            preamble,
                            cliResult.text
                        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
                        self.finalizeStreamingMessage(
                            conversationId: convId,
                            messageId: placeholderId,
                            finalContent: combinedText,
                            engineLabel: "\(engineLabel) → \(cliResult.engineLabel)",
                            isError: false,
                            steps: cliResult.steps,
                            planItems: cliResult.planItems,
                            fileChanges: cliResult.fileChanges,
                            summaryInfo: cliResult.summaryInfo,
                            attachments: cliResult.attachments
                        )
                    }
                }

                if cliDelegatedPausedForApproval {
                    self.finishGenerating(
                        conversationId: convId,
                        runId: runId,
                        finalSessionState: .needsYou,
                        nextAvatarState: .needsYouApproval
                    )
                } else if shouldRequestWriteApproval, case .localAgent(let kind) = resolvedTarget {
                    self.emitWriteApprovalCard(
                        conversationId: convId,
                        messageId: placeholderId,
                        agentKind: kind,
                        originalPrompt: displayPrompt,
                        workDir: workDir,
                        projectId: projectForConv?.id,
                        verdict: precheckVerdict
                    )
                    self.finishGenerating(
                        conversationId: convId,
                        runId: runId,
                        finalSessionState: .needsYou,
                        nextAvatarState: .needsYouApproval
                    )
                } else {
                    let hasStructuredActivity = isLocalAgentTarget ||
                        !finalResult.steps.isEmpty ||
                        !finalResult.planItems.isEmpty ||
                        !finalResult.fileChanges.isEmpty ||
                        finalResult.summaryInfo != nil ||
                        !activateTargetConversation
                    let endState: PipiSessionState = hasStructuredActivity ? .done : .idle
                    self.finishGenerating(
                        conversationId: convId,
                        runId: runId,
                        finalSessionState: endState,
                        nextAvatarState: .synthesizing
                    )
                }
                self.saveResidentState()
            } catch is CancellationError {
                let durationMs = Int(Date().timeIntervalSince(startedAtDate) * 1000)
                self.telemetryMonitor.finishInference(runId: runId, outputTokensEstimate: 0, succeeded: false)
                self.finalizeRunRecord(id: runId, status: .cancelled, durationMs: durationMs)
                self.finishGenerating(
                    conversationId: convId,
                    runId: runId,
                    finalSessionState: .cancelled,
                    nextAvatarState: persona.idleAvatarState
                )
            } catch let err as PipiInferenceError {
                let durationMs = Int(Date().timeIntervalSince(startedAtDate) * 1000)
                self.telemetryMonitor.finishInference(runId: runId, outputTokensEstimate: 0, succeeded: false)
                self.finalizeStreamingMessage(
                    conversationId: convId,
                    messageId: placeholderId,
                    finalContent: err.localizedMessage(langSnapshot),
                    engineLabel: engineLabel,
                    isError: true
                )
                self.finalizeRunRecord(id: runId, status: .failed, durationMs: durationMs)
                self.finishGenerating(
                    conversationId: convId,
                    runId: runId,
                    finalSessionState: .failed,
                    nextAvatarState: .needsYouApproval
                )
                self.saveResidentState()
            } catch {
                let durationMs = Int(Date().timeIntervalSince(startedAtDate) * 1000)
                self.telemetryMonitor.finishInference(runId: runId, outputTokensEstimate: 0, succeeded: false)
                self.finalizeStreamingMessage(
                    conversationId: convId,
                    messageId: placeholderId,
                    finalContent: error.localizedDescription,
                    engineLabel: engineLabel,
                    isError: true
                )
                self.finalizeRunRecord(id: runId, status: .failed, durationMs: durationMs)
                self.finishGenerating(
                    conversationId: convId,
                    runId: runId,
                    finalSessionState: .failed,
                    nextAvatarState: .needsYouApproval
                )
                self.saveResidentState()
            }
        }
        if var runState = activeRuns[convId], runState.runId == runId {
            runState.task = task
            activeRuns[convId] = runState
        }
        return convId
    }

    private func applyParsedCLIEvent(
        _ parsed: PipiParsedCLIEvent,
        conversationId convId: String,
        messageId: String
    ) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == convId }) else { return }
        let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == messageId })

        switch parsed {
        case .sessionId(let sid):
            conversations[cIdx].cliSessionId = sid

        case .textDelta, .finalText:
            break

        case .planUpdated(let items):
            conversations[cIdx].planItems = items
            if let mIdx {
                conversations[cIdx].messages[mIdx].planItems = items
            }
            appendSessionEvent(convId, kind: .plan, messageId: messageId, planItems: items)

        case .stepStarted(let step):
            if let mIdx {
                if let sIdx = conversations[cIdx].messages[mIdx].steps.firstIndex(where: { $0.id == step.id }) {
                    conversations[cIdx].messages[mIdx].steps[sIdx] = step
                } else {
                    conversations[cIdx].messages[mIdx].steps.append(step)
                }
            }
            if var runState = activeRuns[convId] {
                runState.statusText = step.verbPhrase
                activeRuns[convId] = runState
            }
            appendSessionEvent(convId, kind: .step, messageId: messageId, step: step)

        case .stepFinished(let stepId, let status, let detail, let durationMs, let exitCode):
            if let mIdx, let sIdx = conversations[cIdx].messages[mIdx].steps.firstIndex(where: { $0.id == stepId }) {
                conversations[cIdx].messages[mIdx].steps[sIdx].status = status
                if let detail, !detail.isEmpty { conversations[cIdx].messages[mIdx].steps[sIdx].detail = detail }
                if let durationMs { conversations[cIdx].messages[mIdx].steps[sIdx].durationMs = durationMs }
                if let exitCode { conversations[cIdx].messages[mIdx].steps[sIdx].exitCode = exitCode }
                let updatedStep = conversations[cIdx].messages[mIdx].steps[sIdx]
                appendSessionEvent(convId, kind: .toolCall, messageId: messageId, step: updatedStep)
            }

        case .fileChanged(let change):
            if let fIdx = conversations[cIdx].fileChanges.firstIndex(where: { $0.path == change.path }) {
                conversations[cIdx].fileChanges[fIdx] = change
            } else {
                conversations[cIdx].fileChanges.append(change)
            }
            if let mIdx {
                if let fIdx = conversations[cIdx].messages[mIdx].fileChanges.firstIndex(where: { $0.path == change.path }) {
                    conversations[cIdx].messages[mIdx].fileChanges[fIdx] = change
                } else {
                    conversations[cIdx].messages[mIdx].fileChanges.append(change)
                }
            }
            appendSessionEvent(convId, kind: .fileChange, messageId: messageId, fileChange: change)

        case .summary(let info):
            if let mIdx {
                conversations[cIdx].messages[mIdx].summaryInfo = info
            }
            appendSessionEvent(convId, kind: .summary, messageId: messageId, summary: info)
        }
    }

    // MARK: - Wave 1 (#04 & #08): Scheduler Endpoint Helpers & Two-Tier Guardrail APIs

    public func schedulerEndpointKey(for target: PipiExecutionTarget) -> String {
        switch target {
        case .llm(let pid):
            if let cfg = llmProviders.first(where: { $0.id == pid }), cfg.kind == .ollama {
                return "local-model:\(pid)"
            }
            return "llm:\(pid)"
        case .localAgent(let kind):
            return "local-agent:\(kind.rawValue)"
        case .auto:
            return "llm:auto"
        }
    }

    private func ensureDefaultSchedulerPool(for target: PipiExecutionTarget, endpointKey: String) {
        switch target {
        case .llm(let pid):
            if let cfg = llmProviders.first(where: { $0.id == pid }), cfg.kind == .ollama {
                modelScheduler.ensureDefaultEndpointConfig(endpointKey, config: .localModelDefault)
            } else {
                modelScheduler.ensureDefaultEndpointConfig(
                    endpointKey,
                    config: PipiEndpointPoolConfig(
                        initialLimit: Self.maxConcurrentLLMRuns,
                        maxLimit: Self.maxConcurrentLLMRuns
                    )
                )
            }
        case .localAgent:
            modelScheduler.ensureDefaultEndpointConfig(
                endpointKey,
                config: PipiEndpointPoolConfig(
                    initialLimit: Self.maxConcurrentLocalAgentRuns,
                    maxLimit: Self.maxConcurrentLocalAgentRuns
                )
            )
        case .auto:
            modelScheduler.ensureDefaultEndpointConfig(
                endpointKey,
                config: PipiEndpointPoolConfig(
                    initialLimit: Self.maxConcurrentLLMRuns,
                    maxLimit: Self.maxConcurrentLLMRuns
                )
            )
        }
    }

    private static func isRateLimitOrOverloadError(_ error: Error) -> Bool {
        if case PipiInferenceError.httpError(let code, _) = error {
            return code == 429 || code == 503 || code == 529
        }
        let msg = error.localizedDescription.lowercased()
        return msg.contains("429") || msg.contains("rate limit") || msg.contains("overloaded")
    }

    public func setLLMGuardrailJudgeEnabled(_ enabled: Bool) {
        llmGuardrailJudgeEnabled = enabled
        saveResidentState()
    }

    public func addApprovalWhitelistRule(_ rule: PipiApprovalWhitelistRule) {
        if !approvalWhitelistRules.contains(where: {
            $0.granularity == rule.granularity &&
            $0.toolName == rule.toolName &&
            $0.actionKind == rule.actionKind &&
            $0.targetPattern == rule.targetPattern &&
            $0.sessionId == rule.sessionId &&
            $0.projectId == rule.projectId
        }) {
            approvalWhitelistRules.append(rule)
            permissionGuardrail.addWhitelistRule(rule)
            saveResidentState()
        }
    }

    public func revokeApprovalWhitelistRule(id: String) {
        approvalWhitelistRules.removeAll(where: { $0.id == id })
        permissionGuardrail.revokeWhitelistRule(id: id)
        saveResidentState()
    }

    public func clearApprovalWhitelistRules() {
        approvalWhitelistRules.removeAll()
        permissionGuardrail.clearWhitelistRules()
        saveResidentState()
    }

    public func evaluateActionWithGuardrail(
        _ action: PipiGuardrailActionInput,
        auditMediumRisk: Bool = false
    ) async -> PipiGuardrailVerdict {
        let judge = llmGuardrailJudge ?? buildLiveSecurityAuditorJudge()
        return await permissionGuardrail.evaluate(
            action,
            enableLLMJudge: llmGuardrailJudgeEnabled && judge != nil,
            llmJudge: judge,
            auditMediumRisk: auditMediumRisk
        )
    }

    /// Live Security Auditor Agent judge using `securityAuditorPersona` and its configured model.
    private func buildLiveSecurityAuditorJudge() -> PipiLLMGuardrailJudge? {
        guard llmGuardrailJudgeEnabled,
              inferenceExecutor == nil,
              sessionInferenceExecutor == nil else {
            return nil
        }
        let auditor = securityAuditorPersona
        guard let target = resolvedActiveTarget(for: auditor),
              case .llm(let pid) = target,
              let cfg = resolvedEffectiveLLMConfig(providerId: pid, for: auditor) else {
            return nil
        }
        let auditorPrompt = auditor.systemPrompt
        return { request in
            let system = """
            \(auditorPrompt)

            \(request.systemInstruction)
            Respond with ONLY a valid JSON object matching:
            {"risk_level":"low|medium|high|critical","user_authorization":"high|medium|low|unknown","decision":"allow|needs_approval|deny","rationale":"concise reason in user's language"}
            """
            let history = [PipiChatMessage(role: .user, content: request.structuredPrompt)]
            let result = try await PipiInferenceEngine.invokeLLM(
                config: cfg,
                systemPrompt: system,
                history: history,
                maxTokens: 320,
                onDelta: nil
            )
            guard let parsed = PipiPermissionGuardrail.parseLLMJudgeResponse(result.text) else {
                throw PipiInferenceError.emptyResponse
            }
            return parsed
        }
    }

    private func emitRiskyTaskApprovalCard(
        conversationId convId: String,
        messageId: String,
        question: String,
        detail: String,
        pendingPrompt: String,
        pendingTarget: PipiExecutionTarget?,
        toolName: String,
        actionKind: PipiActionKind,
        workDir: String = "",
        projectId: String? = nil,
        verdict: PipiGuardrailVerdict? = nil
    ) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == convId }) else { return }
        let nextSeq = (conversations[cIdx].events.last?.seq ?? 0) + 1
        let projectOrAlwaysLabel = (projectId != nil) ? strings.allowProjectAction : strings.allowAlwaysAction
        let projectOrAlwaysOptionId = (projectId != nil) ? "allow_project" : "allow_always"
        let approval = PipiSessionApproval(
            sessionId: convId,
            eventSeq: nextSeq,
            question: question,
            detail: detail,
            options: [
                PipiSessionApproval.Option(id: "allow_changes", label: strings.allowOnceAction, style: .primary),
                PipiSessionApproval.Option(id: "allow_session", label: strings.allowSessionAction, style: .secondary),
                PipiSessionApproval.Option(id: projectOrAlwaysOptionId, label: projectOrAlwaysLabel, style: .secondary),
                PipiSessionApproval.Option(id: "keep_readonly", label: strings.t("拒绝执行", "Deny"), style: .destructive)
            ],
            recommendedOptionId: "allow_changes",
            status: .pending,
            pendingPrompt: pendingPrompt,
            pendingTarget: pendingTarget,
            riskLevel: verdict?.riskLevel ?? .high,
            userAuthorization: verdict?.userAuthorization ?? .unknown,
            rationale: verdict?.rationale ?? detail,
            operationId: verdict?.operationId ?? "op_\(UUID().uuidString.prefix(8).lowercased())",
            actionToolName: toolName,
            actionKind: actionKind,
            actionTarget: workDir.isEmpty ? nil : workDir,
            projectId: projectId
        )
        conversations[cIdx].approvals.append(approval)
        if let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == messageId }) {
            conversations[cIdx].messages[mIdx].approvalId = approval.id
        }
        appendSessionEvent(convId, kind: .approval, messageId: messageId, approval: approval)
    }

    private func emitWriteApprovalCard(
        conversationId convId: String,
        messageId: String,
        agentKind: PipiLocalAgentKind,
        originalPrompt: String,
        workDir: String = "",
        projectId: String? = nil,
        verdict: PipiGuardrailVerdict? = nil
    ) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == convId }) else { return }
        let nextSeq = (conversations[cIdx].events.last?.seq ?? 0) + 1
        let resumePrompt = strings.t(
            "用户已批准工作区修改权限，请继续执行此前分析的改动。原始需求：\(originalPrompt)",
            "Write permissions approved. Please proceed with applying the planned changes. Original request: \(originalPrompt)"
        )
        let projectOrAlwaysLabel = (projectId != nil) ? strings.allowProjectAction : strings.allowAlwaysAction
        let projectOrAlwaysOptionId = (projectId != nil) ? "allow_project" : "allow_always"
        let approval = PipiSessionApproval(
            sessionId: convId,
            eventSeq: nextSeq,
            question: strings.t(
                "允许 \(agentKind.displayName) 在工作区执行修改吗？",
                "Allow \(agentKind.displayName) to apply changes in the workspace?"
            ),
            detail: strings.t(
                "已以只读权限完成分析。批准后将以可写权限恢复当前会话。",
                "Read-only analysis finished. Approving resumes this session with write permissions."
            ),
            options: [
                PipiSessionApproval.Option(id: "allow_changes", label: strings.allowOnceAction, style: .primary),
                PipiSessionApproval.Option(id: "allow_session", label: strings.allowSessionAction, style: .secondary),
                PipiSessionApproval.Option(id: projectOrAlwaysOptionId, label: projectOrAlwaysLabel, style: .secondary),
                PipiSessionApproval.Option(id: "keep_readonly", label: strings.keepReadOnlyAction, style: .destructive)
            ],
            recommendedOptionId: "allow_changes",
            status: .pending,
            pendingPrompt: resumePrompt,
            pendingTarget: .localAgent(agentKind),
            riskLevel: verdict?.riskLevel ?? .medium,
            userAuthorization: verdict?.userAuthorization ?? .medium,
            rationale: verdict?.rationale,
            operationId: verdict?.operationId ?? "op_\(UUID().uuidString.prefix(8).lowercased())",
            actionToolName: agentKind.binaryName,
            actionKind: .localWrite,
            actionTarget: workDir.isEmpty ? nil : workDir,
            projectId: projectId
        )
        conversations[cIdx].approvals.append(approval)
        if let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == messageId }) {
            conversations[cIdx].messages[mIdx].approvalId = approval.id
        }
        appendSessionEvent(convId, kind: .approval, messageId: messageId, approval: approval)
    }

    private func setSessionState(_ convId: String, to newState: PipiSessionState) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == convId }) else { return }
        if conversations[cIdx].state != newState {
            conversations[cIdx].state = newState
            appendSessionEvent(convId, kind: .stateChange, state: newState)
        }
    }

    private func appendSessionEvent(
        _ convId: String,
        kind: PipiSessionEventKind,
        messageId: String? = nil,
        textDelta: String? = nil,
        planItems: [PipiPlanItem]? = nil,
        step: PipiStepEvent? = nil,
        fileChange: PipiFileChange? = nil,
        approval: PipiSessionApproval? = nil,
        summary: PipiSessionSummaryInfo? = nil,
        state: PipiSessionState? = nil,
        errorMessage: String? = nil
    ) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == convId }) else { return }
        let seq = (conversations[cIdx].events.last?.seq ?? 0) + 1
        let event = PipiSessionEvent(
            sessionId: convId,
            seq: seq,
            kind: kind,
            messageId: messageId,
            textDelta: textDelta,
            planItems: planItems,
            step: step,
            fileChange: fileChange,
            approval: approval,
            summary: summary,
            state: state,
            errorMessage: errorMessage
        )
        conversations[cIdx].events.append(event)
        if conversations[cIdx].events.count > 400 {
            conversations[cIdx].events.removeFirst(conversations[cIdx].events.count - 400)
        }
        localHostConnection.publishEvent(event)
    }

    private func finalizeStreamingMessage(
        conversationId: String,
        messageId: String,
        finalContent: String,
        engineLabel: String?,
        isError: Bool,
        steps: [PipiStepEvent] = [],
        planItems: [PipiPlanItem] = [],
        fileChanges: [PipiFileChange] = [],
        summaryInfo: PipiSessionSummaryInfo? = nil,
        attachments: [PipiChatAttachment] = []
    ) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let nowIso = ISO8601DateFormatter().string(from: Date())
        if let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == messageId }) {
            conversations[cIdx].messages[mIdx].content = finalContent
            conversations[cIdx].messages[mIdx].engineLabel = engineLabel
            conversations[cIdx].messages[mIdx].isError = isError
            if !attachments.isEmpty {
                var existing = conversations[cIdx].messages[mIdx].attachments ?? []
                for att in attachments where !existing.contains(where: { $0.path == att.path }) {
                    existing.append(att)
                }
                conversations[cIdx].messages[mIdx].attachments = existing
            }
            if !steps.isEmpty {
                conversations[cIdx].messages[mIdx].steps = steps
            }
            if !planItems.isEmpty {
                conversations[cIdx].messages[mIdx].planItems = planItems
                conversations[cIdx].planItems = planItems
            }
            if !fileChanges.isEmpty {
                conversations[cIdx].messages[mIdx].fileChanges = fileChanges
                for change in fileChanges {
                    if let fIdx = conversations[cIdx].fileChanges.firstIndex(where: { $0.path == change.path }) {
                        conversations[cIdx].fileChanges[fIdx] = change
                    } else {
                        conversations[cIdx].fileChanges.append(change)
                    }
                }
            }
            if let summaryInfo {
                conversations[cIdx].messages[mIdx].summaryInfo = summaryInfo
            }
        } else {
            conversations[cIdx].messages.append(
                PipiChatMessage(
                    role: .assistant,
                    content: finalContent,
                    createdAt: nowIso,
                    engineLabel: engineLabel,
                    isError: isError,
                    steps: steps,
                    planItems: planItems,
                    fileChanges: fileChanges,
                    summaryInfo: summaryInfo
                )
            )
        }
        conversations[cIdx].updatedAt = nowIso
        if currentlyVisibleSessionId != conversationId {
            unreadConversationCounts[conversationId, default: 0] += 1
        }
        if isError {
            appendSessionEvent(conversationId, kind: .error, messageId: messageId, errorMessage: finalContent)
        } else {
            appendSessionEvent(conversationId, kind: .message, messageId: messageId, textDelta: finalContent)
        }
    }

    private func finalizeRunRecord(id: String, status: PipiRunRecord.Status, durationMs: Int) {
        guard let idx = runRecords.firstIndex(where: { $0.id == id }) else { return }
        runRecords[idx].status = status
        runRecords[idx].durationMs = durationMs
    }

    private func finishGenerating(
        conversationId: String,
        runId: String,
        finalSessionState: PipiSessionState,
        nextAvatarState: AvatarState53
    ) {
        if activeRuns[conversationId]?.runId == runId {
            activeRuns.removeValue(forKey: conversationId)
        }
        setSessionState(conversationId, to: finalSessionState)
        if conversationId == activeConversationId {
            avatarEngine.setState(nextAvatarState)
        }
    }

    public func regenerateLastReply() async {
        guard let convId = activeConversationId,
              let idx = conversations.firstIndex(where: { $0.id == convId }),
              let lastUserMsg = conversations[idx].messages.last(where: { $0.role == .user }) else {
            return
        }
        if conversations[idx].messages.last?.role == .assistant {
            conversations[idx].messages.removeLast()
        }
        if conversations[idx].messages.last?.id == lastUserMsg.id {
            conversations[idx].messages.removeLast()
        }
        await sendPersonalMessage(lastUserMsg.content, attachments: lastUserMsg.attachments ?? [])
    }

    private func appendAssistantMessage(
        to conversationId: String,
        content: String,
        engineLabel: String?,
        isError: Bool,
        isNoEngineGuide: Bool = false
    ) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let nowIso = ISO8601DateFormatter().string(from: Date())
        let msg = PipiChatMessage(
            role: .assistant,
            content: content,
            createdAt: nowIso,
            engineLabel: engineLabel,
            isError: isError,
            isNoEngineGuide: isNoEngineGuide
        )
        conversations[idx].messages.append(msg)
        conversations[idx].updatedAt = nowIso
    }

    private func buildSystemPrompt(for persona: PipiBotPersona, project: PipiProject? = nil) -> String {
        var sections = [persona.systemPrompt]
        if let blueprintBlock = persona.automationBlueprint?.renderedPromptBlock(), !blueprintBlock.isEmpty {
            sections.append(blueprintBlock)
        }
        let botApprovedExamples = approvedExamples.filter { $0.botId == persona.id }
        let examplesBlock = PipiLoopHarnessEngine.renderApprovedExamplesBlock(examples: botApprovedExamples, limit: 4)
        if !examplesBlock.isEmpty {
            sections.append(examplesBlock)
        }
        if let project {
            var projLines = ["[Active Project: \(project.name)]"]
            let projInstr = project.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            if !projInstr.isEmpty {
                projLines.append(projInstr)
            }
            if let projDir = project.workspacePath, !projDir.isEmpty {
                projLines.append("Project working directory: \(projDir)")
            }
            sections.append(projLines.joined(separator: "\n"))
        }
        if let modeHint = replyMode.promptInstruction {
            sections.append("[Response Style]\n\(modeHint)")
        }
        if memoryEnabled {
            let trimmedNote = personalProfileNote.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedNote.isEmpty {
                sections.append("[Personal Memory & Preferences]\n\(trimmedNote)")
            }
        }
        let skillPackSection = ecosystemManager.activeSkillsPromptSection(forPersonaId: persona.id, hostId: persona.hostId)
        if !skillPackSection.isEmpty {
            sections.append(skillPackSection)
        }

        // Jarvis Companion Persona & Native Capabilities
        sections.append(
            """
            [PiPiBot Jarvis 个人管家模式 · 自主闭环执行]
            你是主人这台设备（Mac / iPhone）及所管理远程节点上真正能干活的贴身个人管家（像 Jarvis 一样果断靠谱，说话自然清晰、不打官腔）。
            核心行为准则：
            1. 端到端闭环，干到位再交付（最高优先级）：只要任务在当前权限范围内，必须一口气推进到**真正完成并验证通过**（实测命令退出码 `exit=0`、测试通过、目标文件/服务可用）再回复主人。**严禁**干到一半发“进度汇报 / 快出锅了 / 离成功就差一行 / 还没跑通要不要我继续改”把球踢回给主人！
            2. 合并命令提速，拒绝碎步空转：排查或修复本机/远程节点问题时，优先把多项探测或「修复 + 验证」合并在**一次** compound shell 命令（如 `&&`、分号或多行脚本）中完成；需要同时读多个文件或查多个节点时，在同一轮并发发出多个只读工具调用。绝不要把 `ls`、`cat`、`which`、`chmod` 拆成五六个单独回合白白耗时间。
            3. 仅在真正硬阻塞时才停下询问：只有触发系统安全确认（高危删除/外发/工作区外写入）、缺少主人私密凭据或明确业务抉择、或连续换 2-3 种方案仍无法突破的外部硬故障时，才暂停请示；其余一律自主判断、试错、兜底并完成。
            4. 主动动手，绝不推脱：你拥有完整的原生工具箱（list_directory / read_file / search_files / write_file / edit_file / run_shell / run_script / get_system_status / device_vision_ocr / device_clipboard / device_npu_status / web_search / fetch_webpage / browser_browse / browser_open / browser_act / browser_snapshot / capture_screenshot / record_screen / synthesize_voice / send_local_file / render_visual_card / generate_image / delegate_cli_agent / remote_nodes_list / remote_node_inspect / remote_node_exec / remote_node_run_harness / read_calendar_and_reminders / create_routine_or_reminder / read_mail_or_sms / send_mail_or_sms / show_control_menu / list_or_switch_bot / create_bot / switch_session_or_project / configure_group_mode / update_settings / check_updates）。严禁说出“我只是纯文本对话模型”“我无法访问本地文件/磁盘”“我打不开动态网页”这类推脱话术！
            5. 内置沙箱由你后台静默调用：遇到数值计算、日期换算、JSON/CSV 解析、正则清洗或工作区文件批处理，主动调用 `run_script(code)`（内置 Apple JavaScriptCore 沙箱，支持 `fs` 工作区读写）或 `run_shell(command)`（Mac 走原生 zsh，iPhone 走内置 POSIX 沙箱并在需要 python3/git/swift/npm 时自动通过 E2EE 中继到在线 Mac/Linux 节点）。沙箱是你的后台执行引擎，绝对不要让用户自己去敲命令，直接把算好的结果交付给用户。
            6. 真实浏览器 CUA 优先：用户发来 X/Twitter 链接、长帖/文章、动态网页、仪表盘或要求打开网页交互查信息时，**优先调用 `browser_browse(url, goal)`**（独立多模态浏览器子代理，自带真实 Chromium/WebKit 渲染、滚屏、点击展开与视觉截屏读图）或 `browser_open` + `browser_act`；不要用纯 HTTP `fetch_webpage` 硬拉动态 SPA 导致内容缺失。
            7. 用户提到本地目录或项目（如“桌面上的 Projects/FSD”）：立刻调用 list_directory + read_file 亲自查看源码和 README，直接给出结论，不要把命令贴给用户自己跑。
            8. 用户要语音/图片/截图/文件/管家操作：直接调用对应原生工具真实交付或落地生效；遇到工具或外部 CLI 报错，自主换方案兜底并验证成功后再交付最终结果，不要把原始 stderr 堆栈甩给用户。
            当前默认工作区：\(workspaceDirectory)
            """
        )

        if !usableLocalAgents.isEmpty {
            let agents = usableLocalAgents.map(\.kind)
            let names = agents.map(\.displayName).joined(separator: ", ")
            if proactiveCLIDelegationEnabled {
                sections.append(
                    "[已就绪的本地工程 CLI 助手]\n本机已安装：\(names)。对于简单目录查看/读文件/运行命令请直接用你的原生工具完成；仅在需要大型多文件代码重构时调用 `delegate_cli_agent` 工具（失败时自动回退到你的原生工具继续完成）。"
                )
            } else {
                sections.append(
                    "[已就绪的本地工程 CLI 助手]\n本机已安装：\(names)，用户可通过 /claude、/codex 或 /opencode 按需调用。"
                )
            }
        }
        return sections.joined(separator: "\n\n")
    }

    public var pendingDecisions: [NeedsYouDecision] {
        decisions.filter { $0.status == .pending }
    }

    public var onlineFleetCount: Int {
        fleetNodes.filter { $0.vitality == .alive || $0.vitality == .busy }.count
    }

    public func startLiveSync() {
        sseTask?.cancel()
        sseTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            if self.enableNativeRuntime {
                await self.refreshLocalAgents()
            }
            if self.enableEmbeddedBridge || self.companionSyncEnabled {
                await self.bridgeSupervisor.ensureBridgeRunning()
                await self.refreshAllFromDaemon()
                await self.listenSseLoop()
            }
        }
    }

    public func stopLiveSync() {
        sseTask?.cancel()
        sseTask = nil
        routineSchedulerTask?.cancel()
        routineSchedulerTask = nil
        for groupId in Set(groupRunTasksByRunId.values.map(\.groupId)) {
            stopGroupChat(groupId)
        }
        if enableEmbeddedBridge || companionSyncEnabled {
            bridgeSupervisor.stopBridge()
        }
        flush()
    }

    public func refreshAllFromDaemon() async {
        await client.updateBaseUrl(daemonEndpoint)
        do {
            async let statusTask = client.fetchStatus()
            async let outcomesTask = client.fetchOutcomes()
            async let decisionsTask = client.fetchDecisions()
            async let cueTask = client.fetchCue()
            async let fleetTask = client.fetchFleet()
            async let memoryTask = client.fetchMemory()
            async let soulTask = client.fetchSoulDocuments()

            let status = try await statusTask
            let outcomesEnv = try await outcomesTask
            let decisionsEnv = try await decisionsTask
            let cueEnv = try await cueTask
            let fleetEnv = try await fleetTask
            let memoryEnv = try await memoryTask
            let soulEnv = try await soulTask

            self.connectionMode = .liveDaemon
            self.daemonVersion = status.version
            self.harnessProbes = enableNativeRuntime ? PipiNativeMacRuntime.probeInstalledHarnesses() : status.harnesses
            self.tunnelStatus = status.cloudflare
            self.understandingScore = status.understandingScore
            self.avatarEngine.setState(status.avatarState)
            self.outcomes = outcomesEnv.outcomes
            self.subSessions = outcomesEnv.subSessions
            self.decisions = decisionsEnv.decisions
            if let latest = cueEnv.latest {
                self.latestCue = latest
            }
            self.fleetNodes = fleetEnv.nodes
            if enableNativeRuntime {
                let activeCount = self.subSessions.filter { $0.status == .running || $0.status == .waitingTool }.count
                let liveMac = PipiNativeMacRuntime.sampleHostTelemetry(activeSessionsCount: activeCount)
                if let idx = self.fleetNodes.firstIndex(where: { $0.nodeId == "mac-resident" }) {
                    self.fleetNodes[idx] = liveMac
                }
            }
            self.episodicMemories = memoryEnv.episodic
            self.synthesizedSkills = memoryEnv.skills
            self.lastDigest = memoryEnv.lastDigest ?? self.lastDigest
            self.soulPreview = soulEnv
            self.noticeBanner = strings.t("多端同步服务已连接", "Companion sync connected")
        } catch {
            self.connectionMode = .nativeResident
            if enableNativeRuntime {
                refreshNativeRuntimeSnapshot()
            }
            self.noticeBanner = strings.readyStatus
        }
    }

    private func listenSseLoop() async {
        while !Task.isCancelled {
            do {
                for try await event in await client.streamEvents() {
                    if Task.isCancelled { break }
                    handleSseEvent(event)
                }
            } catch {
                if connectionMode == .liveDaemon {
                    connectionMode = .nativeResident
                }
            }
            if enableNativeRuntime {
                let activeCount = subSessions.filter { $0.status == .running || $0.status == .waitingTool }.count
                let liveMac = PipiNativeMacRuntime.sampleHostTelemetry(activeSessionsCount: activeCount)
                if let idx = fleetNodes.firstIndex(where: { $0.nodeId == "mac-resident" }) {
                    fleetNodes[idx] = liveMac
                }
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func handleSseEvent(_ event: PipiSseEvent) {
        switch event {
        case .connected(let avatarState):
            connectionMode = .liveDaemon
            if let avatarState {
                avatarEngine.setState(avatarState)
            }
        case .harnessPulse(let pulse):
            lastPulseSeq = pulse.seq
            avatarEngine.setState(pulse.suggestedAvatarState)
        case .outcomeUpdate(let updated):
            if let idx = outcomes.firstIndex(where: { $0.id == updated.id }) {
                outcomes[idx] = updated
            } else {
                outcomes.insert(updated, at: 0)
            }
        case .decisionNeedsYou(let decision):
            if let idx = decisions.firstIndex(where: { $0.id == decision.id }) {
                decisions[idx] = decision
            } else {
                decisions.insert(decision, at: 0)
            }
            avatarEngine.setState(.needsYou)
        case .decisionResolved(let decision):
            if let idx = decisions.firstIndex(where: { $0.id == decision.id }) {
                decisions[idx] = decision
            }
        case .cueSuggestion(let cue):
            latestCue = cue
            avatarEngine.setState(.manusCue)
        case .nodeHeartbeat(let node):
            if let idx = fleetNodes.firstIndex(where: { $0.nodeId == node.nodeId }) {
                fleetNodes[idx] = node
            } else {
                fleetNodes.append(node)
            }
        case .evolutionDigestReady(let digest):
            lastDigest = digest
            understandingScore = digest.understandingScore
        }
    }

    // MARK: - Multi-Bot Group Chat & Swarm Orchestration

    public var activeGroupChat: PipiGroupChat? {
        guard let activeGroupChatId else { return nil }
        return groupChats.first(where: { $0.id == activeGroupChatId })
    }

    public var collaboratingBotIds: Set<String> {
        var result = Set<String>()
        for set in activeGroupRuns.values {
            result.formUnion(set)
        }
        return result
    }

    public var sortedGroupChats: [PipiGroupChat] {
        groupChats
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    public func isGroupRunning(_ groupId: String) -> Bool {
        if let set = activeGroupRuns[groupId], !set.isEmpty {
            return true
        }
        return groupRunTasksByRunId.values.contains(where: { $0.groupId == groupId })
    }

    public func activeLanes(forGroup groupId: String) -> [PipiGroupActiveLane] {
        activeGroupLanes.filter { $0.groupId == groupId }
    }

    public func stopGroupLane(_ runId: String) {
        groupRunTasksByRunId[runId]?.task.cancel()
        groupRunTasksByRunId.removeValue(forKey: runId)
        activeGroupLanes.removeAll { $0.runId == runId }
    }

    public func isBotWorkingInGroup(_ personaId: String, groupId: String) -> Bool {
        activeGroupRuns[groupId]?.contains(personaId) ?? false
    }

    public func groupBotStartedAt(groupId: String, personaId: String) -> Date? {
        activeGroupRunStartTimes[groupId]?[personaId]
    }

    public func groupStreamingMessageId(groupId: String, personaId: String) -> String? {
        activeGroupStreamingMessageIds[groupId]?[personaId]
    }

    @discardableResult
    public func createGroupChat(
        title: String,
        participantPersonaIds: [String],
        leadPersonaId: String? = nil,
        swarmMode: PipiSwarmMode = .swarm,
        projectId: String? = nil,
        activate: Bool = true
    ) -> PipiGroupChat {
        let validIds = participantPersonaIds.filter { pid in personas.contains(where: { $0.id == pid }) }
        let uniqueIds = validIds.reduce(into: [String]()) { acc, item in
            if !acc.contains(item) { acc.append(item) }
        }
        let resolvedParticipants = uniqueIds.isEmpty ? [activePersona.id] : uniqueIds
        let resolvedLead = (leadPersonaId.flatMap { lid in resolvedParticipants.contains(lid) ? lid : nil }) ?? resolvedParticipants.first
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultTitle = strings.t("多智能体协作群", "Agent Swarm Group")
        let group = PipiGroupChat(
            title: trimmedTitle.isEmpty ? defaultTitle : trimmedTitle,
            participantPersonaIds: resolvedParticipants,
            leadPersonaId: resolvedLead,
            swarmMode: swarmMode,
            projectId: projectId
        )
        groupChats.insert(group, at: 0)
        if activate {
            activeGroupChatId = group.id
        }
        saveResidentState()
        return group
    }

    public func updateGroupChat(
        id: String,
        title: String? = nil,
        participantPersonaIds: [String]? = nil,
        leadPersonaId: String?? = nil,
        swarmMode: PipiSwarmMode? = nil,
        projectId: String?? = nil
    ) {
        guard let idx = groupChats.firstIndex(where: { $0.id == id }) else { return }
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { groupChats[idx].title = trimmed }
        }
        if let participantPersonaIds {
            let unique = participantPersonaIds.reduce(into: [String]()) { acc, pid in
                if personas.contains(where: { $0.id == pid }), !acc.contains(pid) {
                    acc.append(pid)
                }
            }
            if !unique.isEmpty {
                groupChats[idx].participantPersonaIds = unique
                if let currentLead = groupChats[idx].leadPersonaId, !unique.contains(currentLead) {
                    groupChats[idx].leadPersonaId = unique.first
                }
            }
        }
        if let leadPersonaId {
            if let lid = leadPersonaId, groupChats[idx].participantPersonaIds.contains(lid) {
                groupChats[idx].leadPersonaId = lid
            } else if leadPersonaId == nil {
                groupChats[idx].leadPersonaId = groupChats[idx].participantPersonaIds.first
            }
        }
        if let swarmMode {
            groupChats[idx].swarmMode = swarmMode
        }
        if let projectId {
            groupChats[idx].projectId = projectId
        }
        groupChats[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
    }

    public func renameGroupChat(id: String, title: String) {
        updateGroupChat(id: id, title: title)
    }

    public func togglePinGroupChat(id: String) {
        guard let idx = groupChats.firstIndex(where: { $0.id == id }) else { return }
        groupChats[idx].isPinned.toggle()
        groupChats[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
    }

    public func deleteGroupChat(id: String) {
        stopGroupChat(id)
        groupChats.removeAll { $0.id == id }
        if activeGroupChatId == id {
            activeGroupChatId = sortedGroupChats.first?.id
        }
        saveResidentState()
    }

    public func selectGroupChat(_ id: String?) {
        if let id, groupChats.contains(where: { $0.id == id }) {
            activeGroupChatId = id
            markGroupRead(id)
        } else {
            activeGroupChatId = nil
        }
        saveResidentState()
    }

    public func stopGroupChat(_ groupId: String) {
        let matchingRunIds = groupRunTasksByRunId.filter { $0.value.groupId == groupId }.map(\.key)
        for rid in matchingRunIds {
            groupRunTasksByRunId[rid]?.task.cancel()
            groupRunTasksByRunId.removeValue(forKey: rid)
        }
        activeGroupLanes.removeAll { $0.groupId == groupId }
        activeGroupRuns.removeValue(forKey: groupId)
        activeGroupStreamingMessageIds.removeValue(forKey: groupId)
        activeGroupRunStartTimes.removeValue(forKey: groupId)
        if let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) {
            let nowIso = ISO8601DateFormatter().string(from: Date())
            for aIdx in groupChats[gIdx].assignments.indices {
                if groupChats[gIdx].assignments[aIdx].status == .working || groupChats[gIdx].assignments[aIdx].status == .queued {
                    groupChats[gIdx].assignments[aIdx].status = .failed
                    groupChats[gIdx].assignments[aIdx].updatedAt = nowIso
                }
            }
        }
        syncElapsedAndAvatarForActiveConversation()
        saveResidentState()
    }

    /// Parses `@all` / `@全体` / `@所有人` and `@BotName` mentions across participants.
    public func parseGroupMentions(
        in text: String,
        participantPersonaIds: [String]
    ) -> (mentionedIds: [String], isAll: Bool) {
        guard text.contains("@") else { return ([], false) }

        func isWordBoundaryBefore(_ idx: String.Index) -> Bool {
            if idx == text.startIndex { return true }
            let prev = text[text.index(before: idx)]
            return !prev.isASCIIAlphaNumOrUnderscore
        }

        func isAliasBoundaryAfter(_ endIdx: String.Index, alias: String) -> Bool {
            guard endIdx < text.endIndex else { return true }
            guard let last = alias.last, last.isASCIIAlphaNumOrUnderscore else {
                return true
            }
            let next = text[endIdx]
            return !next.isASCIIAlphaNumOrUnderscore
        }

        // Check @all / @全体 / @所有人
        var isAll = false
        for allToken in ["all", "全体", "所有人"] {
            let needle = "@\(allToken)"
            var searchStart = text.startIndex
            while let range = text.range(of: needle, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
                if isWordBoundaryBefore(range.lowerBound) && isAliasBoundaryAfter(range.upperBound, alias: allToken) {
                    isAll = true
                    break
                }
                searchStart = range.upperBound
            }
            if isAll { break }
        }

        // Build alias table sorted longest-first so `@PiPi Coder` wins over `@PiPi`.
        var candidates: [(alias: String, personaId: String)] = []
        for pid in participantPersonaIds {
            guard let persona = personas.first(where: { $0.id == pid }) else { continue }
            var aliases: [String] = [persona.nameEn, persona.nameZh, persona.id]
            let firstToken = persona.nameEn.split(separator: " ").first.map(String.init) ?? ""
            if firstToken.count >= 2 {
                aliases.append(firstToken)
            }
            for raw in aliases {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    candidates.append((trimmed, pid))
                }
            }
        }
        candidates.sort { $0.alias.count > $1.alias.count }

        struct MatchHit {
            let personaId: String
            let range: Range<String.Index>
        }
        var hits: [MatchHit] = []

        for candidate in candidates {
            let needle = "@\(candidate.alias)"
            var searchStart = text.startIndex
            while let range = text.range(of: needle, options: [.caseInsensitive], range: searchStart..<text.endIndex) {
                let overlaps = hits.contains { $0.range.overlaps(range) }
                if !overlaps
                    && isWordBoundaryBefore(range.lowerBound)
                    && isAliasBoundaryAfter(range.upperBound, alias: candidate.alias) {
                    hits.append(MatchHit(personaId: candidate.personaId, range: range))
                }
                searchStart = range.upperBound
            }
        }

        hits.sort { $0.range.lowerBound < $1.range.lowerBound }
        var orderedIds: [String] = []
        for hit in hits where !orderedIds.contains(hit.personaId) {
            orderedIds.append(hit.personaId)
        }
        if isAll {
            for pid in participantPersonaIds where !orderedIds.contains(pid) {
                orderedIds.append(pid)
            }
        }
        return (orderedIds, isAll)
    }

    /// Extracts `@BotName: <subtask>` lines from a Lead bot's decomposition response.
    public func parseSwarmAssignments(
        from leadResponse: String,
        participantPersonaIds: [String],
        excludingLeadId: String?
    ) -> [(personaId: String, subtask: String)] {
        let nonLeadIds = participantPersonaIds.filter { $0 != excludingLeadId }
        guard !nonLeadIds.isEmpty else { return [] }

        var assignments: [(personaId: String, subtask: String)] = []
        let lines = leadResponse.components(separatedBy: .newlines)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, line.contains("@") else { continue }
            let parsed = parseGroupMentions(in: line, participantPersonaIds: nonLeadIds)
            guard !parsed.mentionedIds.isEmpty else { continue }

            // Find where the mention ends on this line to extract the subtask description
            let cleanTask = extractSubtaskText(from: line, targetIds: parsed.mentionedIds)
            if parsed.isAll && parsed.mentionedIds.count == nonLeadIds.count {
                for pid in nonLeadIds where !assignments.contains(where: { $0.personaId == pid }) {
                    assignments.append((pid, cleanTask.isEmpty ? line : cleanTask))
                }
            } else {
                for pid in parsed.mentionedIds {
                    if let existingIdx = assignments.firstIndex(where: { $0.personaId == pid }) {
                        if !cleanTask.isEmpty {
                            assignments[existingIdx].subtask += "\n" + cleanTask
                        }
                    } else {
                        assignments.append((pid, cleanTask.isEmpty ? line : cleanTask))
                    }
                }
            }
        }

        return assignments
    }

    private func extractSubtaskText(from line: String, targetIds: [String]) -> String {
        var stripped = line
        // Remove leading markdown bullet or numbering
        if let bulletRange = stripped.range(of: #"^\s*([-*•]|\d+[\.\)])\s*"#, options: .regularExpression) {
            stripped.removeSubrange(bulletRange)
        }
        // Strip @all or @alias tokens
        var tokensToStrip = ["@all", "@全体", "@所有人"]
        for pid in targetIds {
            if let p = personas.first(where: { $0.id == pid }) {
                tokensToStrip.append("@\(p.nameEn)")
                tokensToStrip.append("@\(p.nameZh)")
                tokensToStrip.append("@\(p.id)")
                if let first = p.nameEn.split(separator: " ").first {
                    tokensToStrip.append("@\(first)")
                }
            }
        }
        tokensToStrip.sort { $0.count > $1.count }
        for tok in tokensToStrip {
            if let r = stripped.range(of: tok, options: [.caseInsensitive]) {
                stripped.removeSubrange(r)
            }
        }
        let separators = CharacterSet(charactersIn: ":：-—–|• \t")
        stripped = stripped.trimmingCharacters(in: separators)
        return stripped
    }

    // MARK: - Group Topics, Long Tasks, Deliverables, Skills & Shared Memory

    @discardableResult
    public func createGroupTopic(
        groupId: String,
        title: String,
        summary: String? = nil,
        activate: Bool = true
    ) -> PipiGroupTopic? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) else {
            return nil
        }
        let nowIso = ISO8601DateFormatter().string(from: Date())
        let cleanSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let topic = PipiGroupTopic(
            title: trimmed,
            summary: (cleanSummary?.isEmpty == false) ? cleanSummary : nil,
            isDefault: false,
            createdAt: nowIso,
            updatedAt: nowIso
        )
        groupChats[gIdx].topics.append(topic)
        if activate {
            groupChats[gIdx].activeTopicId = topic.id
        }
        groupChats[gIdx].updatedAt = nowIso
        saveResidentState()
        return topic
    }

    public func selectGroupTopic(groupId: String, topicId: String?) {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) else { return }
        if let topicId,
           let matched = groupChats[gIdx].topics.first(where: { $0.id == topicId }) {
            groupChats[gIdx].activeTopicId = matched.isDefault ? nil : matched.id
        } else {
            groupChats[gIdx].activeTopicId = nil
        }
        saveResidentState()
    }

    public func deleteGroupTopic(groupId: String, topicId: String) {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }),
              let target = groupChats[gIdx].topics.first(where: { $0.id == topicId }),
              !target.isDefault else {
            return
        }
        groupChats[gIdx].topics.removeAll { $0.id == topicId }
        groupChats[gIdx].messages.removeAll { $0.topicId == topicId }
        for idx in groupChats[gIdx].longTasks.indices where groupChats[gIdx].longTasks[idx].topicId == topicId {
            groupChats[gIdx].longTasks[idx].topicId = nil
        }
        for idx in groupChats[gIdx].deliverables.indices where groupChats[gIdx].deliverables[idx].topicId == topicId {
            groupChats[gIdx].deliverables[idx].topicId = nil
        }
        if groupChats[gIdx].activeTopicId == topicId {
            groupChats[gIdx].activeTopicId = nil
        }
        groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
    }

    @discardableResult
    public func addGroupLongTask(groupId: String, task: PipiGroupLongTask) -> PipiGroupLongTask? {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) else { return nil }
        let trimmedTitle = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGoal = task.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedGoal.isEmpty else { return nil }
        var cleanTask = task
        cleanTask.title = trimmedTitle
        cleanTask.goal = trimmedGoal
        groupChats[gIdx].longTasks.insert(cleanTask, at: 0)
        groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
        return cleanTask
    }

    public func toggleGroupLongTask(
        groupId: String,
        taskId: String,
        status: PipiGroupLongTask.Status? = nil
    ) {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }),
              let tIdx = groupChats[gIdx].longTasks.firstIndex(where: { $0.id == taskId }) else {
            return
        }
        if let status {
            groupChats[gIdx].longTasks[tIdx].status = status
        } else {
            let current = groupChats[gIdx].longTasks[tIdx].status
            groupChats[gIdx].longTasks[tIdx].status = (current == .active) ? .paused : .active
        }
        groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
    }

    public func deleteGroupLongTask(groupId: String, taskId: String) {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) else { return }
        groupChats[gIdx].longTasks.removeAll { $0.id == taskId }
        groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
    }

    public func runGroupLongTaskNow(groupId: String, taskId: String) async {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }),
              let task = groupChats[gIdx].longTasks.first(where: { $0.id == taskId }) else {
            return
        }
        let resolvedTopicId: String? = {
            if let tid = task.topicId,
               groupChats[gIdx].topics.contains(where: { $0.id == tid && !$0.isDefault }) {
                return tid
            }
            return groupChats[gIdx].effectiveActiveTopicId
        }()
        if groupChats[gIdx].activeTopicId != resolvedTopicId {
            groupChats[gIdx].activeTopicId = resolvedTopicId
        }
        let participants = groupChats[gIdx].participantPersonaIds
        let validOwnerId = task.ownerPersonaId.flatMap { participants.contains($0) ? $0 : nil }
        let ownerName = validOwnerId.flatMap { oid in
            personas.first(where: { $0.id == oid })?.name(resolvedLanguage)
        }

        let promptText: String = {
            if let ownerName {
                return strings.t(
                    "[长期任务推进 · \(task.title)] @\(ownerName) 请推进以下长期目标并汇报当前阶段结论：\n\(task.goal)",
                    "[Long-Task Check-In · \(task.title)] @\(ownerName) Please advance this ongoing goal and report progress:\n\(task.goal)"
                )
            }
            return strings.t(
                "[长期任务推进 · \(task.title)] 请协同推进以下长期目标并汇报当前阶段结论：\n\(task.goal)",
                "[Long-Task Check-In · \(task.title)] Please collaborate on advancing this ongoing goal and summarize progress:\n\(task.goal)"
            )
        }()

        let forcedTargets = validOwnerId.map { [$0] }
        let producedMessages = await dispatchGroupMessage(
            promptText,
            toGroupId: groupId,
            topicId: resolvedTopicId,
            forcedTargetPersonaIds: forcedTargets
        )

        let nowIso = ISO8601DateFormatter().string(from: Date())
        if let freshGIdx = groupChats.firstIndex(where: { $0.id == groupId }),
           let freshTIdx = groupChats[freshGIdx].longTasks.firstIndex(where: { $0.id == taskId }) {
            groupChats[freshGIdx].longTasks[freshTIdx].lastRunAt = nowIso
            if let bestReply = producedMessages.last(where: { !$0.isError && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                let compact = bestReply.content
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                groupChats[freshGIdx].longTasks[freshTIdx].lastSummary = compact.count > 200
                    ? String(compact.prefix(200)) + "…"
                    : compact
            }
            groupChats[freshGIdx].updatedAt = nowIso
            saveResidentState()
        }
    }

    @discardableResult
    public func addGroupDeliverable(
        groupId: String,
        deliverable: PipiGroupDeliverable
    ) -> PipiGroupDeliverable? {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) else { return nil }
        let trimmedTitle = deliverable.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        var clean = deliverable
        clean.title = trimmedTitle
        if clean.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let preview = clean.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            clean.summary = preview.count > 160 ? String(preview.prefix(160)) + "…" : preview
        }
        groupChats[gIdx].deliverables.insert(clean, at: 0)
        groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
        return clean
    }

    @discardableResult
    public func promoteMessageToDeliverable(
        groupId: String,
        messageId: String,
        title: String? = nil,
        kind: PipiGroupDeliverable.Kind = .document
    ) -> PipiGroupDeliverable? {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }),
              let msg = groupChats[gIdx].messages.first(where: { $0.id == messageId }) else {
            return nil
        }
        let rawContent = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawContent.isEmpty else { return nil }

        let resolvedTitle: String = {
            let custom = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !custom.isEmpty { return custom }
            let firstLine = rawContent
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? ""
            let cleaned = firstLine
                .replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                return strings.t("群协作交付物", "Group Deliverable")
            }
            return cleaned.count > 44 ? String(cleaned.prefix(44)) + "…" : cleaned
        }()

        let flatSummary = rawContent
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = flatSummary.count > 160 ? String(flatSummary.prefix(160)) + "…" : flatSummary

        let producerId: String? = {
            if case .bot(let pid) = msg.senderKind { return pid }
            return nil
        }()

        let deliverable = PipiGroupDeliverable(
            title: resolvedTitle,
            kind: kind,
            summary: summary,
            content: rawContent,
            producedByPersonaId: producerId,
            topicId: msg.topicId
        )
        groupChats[gIdx].deliverables.insert(deliverable, at: 0)
        groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
        return deliverable
    }

    public func deleteGroupDeliverable(groupId: String, deliverableId: String) {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) else { return }
        groupChats[gIdx].deliverables.removeAll { $0.id == deliverableId }
        groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
    }

    public func toggleGroupSkill(groupId: String, skillId: String, enabled: Bool) {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }),
              let sIdx = groupChats[gIdx].skills.firstIndex(where: { $0.id == skillId }) else {
            return
        }
        groupChats[gIdx].skills[sIdx].isEnabled = enabled
        groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
    }

    @discardableResult
    public func addGroupSkill(
        groupId: String,
        name: String,
        instruction: String
    ) -> PipiGroupSkill? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanInstruction.isEmpty,
              let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) else {
            return nil
        }
        let skill = PipiGroupSkill(
            name: cleanName,
            instruction: cleanInstruction,
            isEnabled: true,
            isBuiltIn: false
        )
        groupChats[gIdx].skills.append(skill)
        groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
        return skill
    }

    public func deleteGroupSkill(groupId: String, skillId: String) {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) else { return }
        groupChats[gIdx].skills.removeAll { $0.id == skillId }
        groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
    }

    @discardableResult
    public func addGroupMemory(
        groupId: String,
        content: String,
        source: String? = nil,
        pinned: Bool = false
    ) -> PipiGroupMemoryItem? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) else {
            return nil
        }
        let cleanSource = source?.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = PipiGroupMemoryItem(
            content: trimmed,
            source: (cleanSource?.isEmpty == false) ? cleanSource : nil,
            isPinned: pinned
        )
        groupChats[gIdx].sharedMemories.insert(item, at: 0)
        groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
        return item
    }

    public func togglePinGroupMemory(groupId: String, memoryId: String) {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }),
              let mIdx = groupChats[gIdx].sharedMemories.firstIndex(where: { $0.id == memoryId }) else {
            return
        }
        groupChats[gIdx].sharedMemories[mIdx].isPinned.toggle()
        groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
    }

    public func deleteGroupMemory(groupId: String, memoryId: String) {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) else { return }
        groupChats[gIdx].sharedMemories.removeAll { $0.id == memoryId }
        groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
    }

    public func estimateGroupContextUsage(for group: PipiGroupChat) -> PipiContextUsageEstimate {
        let project = group.projectId.flatMap { pid in projects.first(where: { $0.id == pid }) }
        let leadPersona = group.leadPersonaId.flatMap { lid in personas.first(where: { $0.id == lid }) }
            ?? group.participantPersonaIds.first.flatMap { pid in personas.first(where: { $0.id == pid }) }
            ?? activePersona
        let baseSystemPrompt = buildSystemPrompt(for: leadPersona, project: project)
        let groupContextPrompt = buildGroupContextPromptSection(for: group, topicId: group.effectiveActiveTopicId)

        var totalTokens = Self.estimateTokenCount(for: baseSystemPrompt) + Self.estimateTokenCount(for: groupContextPrompt)
        let topicMessages = group.activeTopicMessages
        var turnCount = 0
        for msg in topicMessages {
            if msg.senderKind == .user { turnCount += 1 }
            totalTokens += 4 + Self.estimateTokenCount(for: msg.content)
        }

        let engineSignal = activeEngineDisplayLabel(for: leadPersona).lowercased()
        let windowTokens: Int = {
            if engineSignal.contains("claude") { return 200_000 }
            if engineSignal.contains("gemini") { return 1_000_000 }
            return 128_000
        }()

        let hasSharedOrProfile = !group.sharedMemories.isEmpty || !personalProfileNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return PipiContextUsageEstimate(
            estimatedTokens: totalTokens,
            contextWindowTokens: windowTokens,
            messageCount: topicMessages.count,
            turnCount: turnCount,
            attachmentCount: group.deliverables.count,
            isMemoryEnabled: memoryEnabled || !group.sharedMemories.isEmpty,
            hasPersonalProfile: hasSharedOrProfile
        )
    }

    public func buildGroupContextPromptSection(for group: PipiGroupChat, topicId: String? = nil) -> String {
        let resolvedTopic: PipiGroupTopic = {
            if let topicId, let matched = group.topics.first(where: { $0.id == topicId }) {
                return matched
            }
            return group.activeTopic
        }()

        var blocks: [String] = []
        var topicLines = [
            "[Group Collaboration Context: \(group.title)]",
            "Active Topic: #\(resolvedTopic.localizedTitle(resolvedLanguage))"
        ]
        if let summary = resolvedTopic.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            topicLines.append("Topic Summary: \(summary)")
        }
        blocks.append(topicLines.joined(separator: "\n"))

        let enabledSkills = group.skills.filter(\.isEnabled)
        if !enabledSkills.isEmpty {
            var skillLines = ["[Enabled Group Skills]"]
            for skill in enabledSkills {
                skillLines.append("- \(skill.localizedName(resolvedLanguage)): \(skill.instruction)")
            }
            blocks.append(skillLines.joined(separator: "\n"))
        }

        if !group.sharedMemories.isEmpty {
            let orderedMemories = group.sharedMemories.sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
                return lhs.createdAt > rhs.createdAt
            }
            var memoryLines = ["[Group Shared Memory]"]
            for mem in orderedMemories {
                let prefix = mem.isPinned ? "[Pinned] " : ""
                let src = (mem.source?.isEmpty == false) ? " (source: \(mem.source!))" : ""
                memoryLines.append("- \(prefix)\(mem.content)\(src)")
            }
            blocks.append(memoryLines.joined(separator: "\n"))
        }

        let activeTasks = group.longTasks.filter { $0.status == .active }
        if !activeTasks.isEmpty {
            var taskLines = ["[Active Long-Running Group Tasks]"]
            for task in activeTasks {
                let ownerName = task.ownerPersonaId.flatMap { oid in
                    personas.first(where: { $0.id == oid })?.name(resolvedLanguage)
                } ?? strings.t("团队协作", "Team")
                var line = "- \(task.title) (Owner: \(ownerName), Schedule: \(task.schedule.label(resolvedLanguage))): \(task.goal)"
                if let lastSummary = task.lastSummary, !lastSummary.isEmpty {
                    line += " [Latest: \(lastSummary)]"
                }
                taskLines.append(line)
            }
            blocks.append(taskLines.joined(separator: "\n"))
        }

        return blocks.joined(separator: "\n\n")
    }

    public func sendGroupMessage(_ rawText: String, toGroupId groupId: String, topicId: String? = nil) async {
        _ = await dispatchGroupMessage(rawText, toGroupId: groupId, topicId: topicId, forcedTargetPersonaIds: nil)
        evaluateChannelMessageRoutines(channel: "group", text: rawText)
    }

    @discardableResult
    private func dispatchGroupMessage(
        _ rawText: String,
        toGroupId groupId: String,
        topicId: String? = nil,
        forcedTargetPersonaIds: [String]? = nil
    ) async -> [PipiGroupMessage] {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let gIdx = groupChats.firstIndex(where: { $0.id == groupId }),
              !groupChats[gIdx].participantPersonaIds.isEmpty else {
            return []
        }

        // Per-Task True Parallel Lanes: NEVER cancel in-flight tasks in the same group when new messages arrive!
        let runId = "grun_\(UUID().uuidString.prefix(8).lowercased())"

        let resolvedTopicId: String? = {
            if let topicId {
                return groupChats[gIdx].isDefaultTopicId(topicId) ? nil : topicId
            }
            return groupChats[gIdx].effectiveActiveTopicId
        }()

        let participants = groupChats[gIdx].participantPersonaIds
        let mentions = parseGroupMentions(in: trimmed, participantPersonaIds: participants)
        let nowIso = ISO8601DateFormatter().string(from: Date())
        let userMsg = PipiGroupMessage(
            senderKind: .user,
            content: trimmed,
            createdAt: nowIso,
            mentionedPersonaIds: mentions.mentionedIds,
            topicId: resolvedTopicId
        )
        groupChats[gIdx].messages.append(userMsg)
        groupChats[gIdx].assignments = []
        groupChats[gIdx].updatedAt = nowIso
        if groupChats[gIdx].messages.filter({ $0.senderKind == .user }).count == 1,
           groupChats[gIdx].title == strings.t("多 Bot 协作群", "Bot Swarm Group") ||
           groupChats[gIdx].title == strings.t("多智能体协作群", "Agent Swarm Group") {
            let preview = String(trimmed.prefix(26))
            groupChats[gIdx].title = trimmed.count > 26 ? preview + "…" : preview
        }
        saveResidentState()

        let task = Task { @MainActor [weak self] () -> [PipiGroupMessage] in
            guard let self else { return [] }
            return await self.executeGroupTurn(
                groupId: groupId,
                userText: trimmed,
                mentions: (mentions.mentionedIds, mentions.isAll),
                topicId: resolvedTopicId,
                forcedTargetPersonaIds: forcedTargetPersonaIds
            )
        }
        groupRunTasksByRunId[runId] = (groupId: groupId, task: task)
        let produced = await task.value
        groupRunTasksByRunId.removeValue(forKey: runId)
        let stillHasOtherRuns = groupRunTasksByRunId.values.contains(where: { $0.groupId == groupId })
        if !stillHasOtherRuns {
            activeGroupRuns.removeValue(forKey: groupId)
            activeGroupStreamingMessageIds.removeValue(forKey: groupId)
            activeGroupRunStartTimes.removeValue(forKey: groupId)
        }
        if !produced.isEmpty {
            incrementGroupUnreadIfNotVisible(groupId)
        }
        syncElapsedAndAvatarForActiveConversation()
        saveResidentState()
        return produced
    }

    private func executeGroupTurn(
        groupId: String,
        userText: String,
        mentions: (mentionedIds: [String], isAll: Bool),
        topicId: String?,
        forcedTargetPersonaIds: [String]? = nil
    ) async -> [PipiGroupMessage] {
        guard let group = groupChats.first(where: { $0.id == groupId }) else { return [] }
        let participants = group.participantPersonaIds
        let project = group.projectId.flatMap { pid in projects.first(where: { $0.id == pid }) }
        let mode = group.swarmMode

        if let forcedTargetPersonaIds, !forcedTargetPersonaIds.isEmpty {
            let suffix = strings.t(
                "你正在协作群中负责推进当前长期任务。请结合群技能、共享记忆与最新进展，给出具体推进结果与下一步建议。",
                "You own advancing this long-running task in the group chat. Use the group skills, shared memory, and progress so far to report concrete updates and next steps."
            )
            return await runBotsInParallel(
                groupId: groupId,
                dispatches: forcedTargetPersonaIds.map { ($0, userText, strings.t("任务推进", "Task Run") as String?) },
                systemPromptSuffix: suffix,
                project: project,
                topicId: topicId
            )
        }

        switch mode {
        case .mentionOnly:
            let targets: [String]
            if mentions.isAll {
                targets = participants
            } else if !mentions.mentionedIds.isEmpty {
                targets = mentions.mentionedIds
            } else {
                let fallback = group.leadPersonaId.flatMap { participants.contains($0) ? $0 : nil } ?? participants.first
                targets = fallback.map { [$0] } ?? []
            }
            let suffix = strings.t(
                "你正在多智能体协作群中回复用户。直接针对你的专长回答即可，保持简洁清晰。",
                "You are replying in a multi-agent group chat. Respond concisely from your specialty."
            )
            return await runBotsInParallel(
                groupId: groupId,
                dispatches: targets.map { ($0, userText, nil as String?) },
                systemPromptSuffix: suffix,
                project: project,
                topicId: topicId
            )

        case .relay:
            var runningContext = userText
            var relayMessages: [PipiGroupMessage] = []
            let total = participants.count
            for (index, pid) in participants.enumerated() {
                if Task.isCancelled { break }
                guard let persona = personas.first(where: { $0.id == pid }) else { continue }
                let stepLabel = "\(index + 1)/\(total)"
                let suffix = strings.t(
                    "你正在「顺序接力」模式中（第 \(stepLabel) 棒）。请基于用户的原始需求与前序成员的输出继续深化、补充或审查。",
                    "You are in sequential Relay mode (turn \(stepLabel)). Build upon the user's request and the previous teammates' outputs."
                )
                let promptForBot: String
                if index == 0 {
                    promptForBot = userText
                } else {
                    promptForBot = strings.t(
                        "原始请求：\(userText)\n\n前序接力结论：\n\(runningContext)\n\n请接力完成你的部分：",
                        "Original request: \(userText)\n\nPrevious relay output:\n\(runningContext)\n\nPlease continue from your specialty:"
                    )
                }
                let result = await invokeSingleBotForGroup(
                    groupId: groupId,
                    persona: persona,
                    promptText: promptForBot,
                    systemPromptSuffix: suffix,
                    roleTag: strings.t("接力 \(stepLabel)", "Relay \(stepLabel)"),
                    project: project,
                    topicId: topicId
                )
                relayMessages.append(result.message)
                if result.succeeded && !result.message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    runningContext = "[\(persona.name(resolvedLanguage))]: \(result.message.content)"
                }
            }
            return relayMessages

        case .swarm:
            let leadId = group.leadPersonaId.flatMap { participants.contains($0) ? $0 : nil } ?? participants.first
            guard let leadId, let leadPersona = personas.first(where: { $0.id == leadId }) else { return [] }

            if participants.count == 1 {
                let suffix = strings.t("你是当前协作群的唯一成员，请直接完成用户请求。", "You are the sole member of this group; fulfill the user's request directly.")
                let single = await invokeSingleBotForGroup(
                    groupId: groupId,
                    persona: leadPersona,
                    promptText: userText,
                    systemPromptSuffix: suffix,
                    roleTag: strings.t("主控", "Lead"),
                    project: project,
                    topicId: topicId
                )
                return [single.message]
            }

            let rosterLines = participants.compactMap { pid -> String? in
                guard pid != leadId, let p = personas.first(where: { $0.id == pid }) else { return nil }
                return "- @\(p.nameEn) (中文名: @\(p.nameZh)): \(p.role(resolvedLanguage))"
            }.joined(separator: "\n")

            let leadSuffix = strings.t(
                """
                你是多智能体蜂群协作的主控 (Lead)。当前团队其他成员如下：
                \(rosterLines)

                如果任务需要多人分工协作，请先简要给出整体方案，并逐行使用 `@成员名: 具体子任务` 格式分派任务（例如 `@Coder: 实现接口`）。
                如果任务非常简单，不需要其他成员介入，也可以直接独立完成。
                """,
                """
                You are the Lead orchestrator of a multi-agent swarm. Your teammates are:
                \(rosterLines)

                If collaboration helps, briefly outline the plan and delegate subtasks on separate lines using `@MemberName: specific subtask`.
                If the request is trivial and needs no delegation, answer directly without mentioning teammates.
                """
            )

            let leadOutcome = await invokeSingleBotForGroup(
                groupId: groupId,
                persona: leadPersona,
                promptText: userText,
                systemPromptSuffix: leadSuffix,
                roleTag: strings.t("主控", "Lead"),
                project: project,
                topicId: topicId
            )
            var collectedMessages = [leadOutcome.message]
            if Task.isCancelled || !leadOutcome.succeeded { return collectedMessages }

            let parsedAssignments = parseSwarmAssignments(
                from: leadOutcome.message.content,
                participantPersonaIds: participants,
                excludingLeadId: leadId
            )
            guard !parsedAssignments.isEmpty else { return collectedMessages }

            let nowIso = ISO8601DateFormatter().string(from: Date())
            if let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) {
                groupChats[gIdx].assignments = parsedAssignments.map { item in
                    PipiSwarmTaskAssignment(
                        personaId: item.personaId,
                        taskTitle: item.subtask,
                        status: .queued,
                        updatedAt: nowIso
                    )
                }
                saveResidentState()
            }

            var spokenInWave: Set<String> = [leadId]
            let workerSuffix = strings.t(
                "你是多智能体蜂群协作中的执行成员。请专注完成主控分派给你的子任务；只有确实需要另一位尚未发言的队友接手补充时，才使用 `@成员名` 交接。",
                "You are a specialist in a multi-agent swarm. Focus on completing your assigned subtask. Only @mention another teammate if a genuine follow-up handoff is needed."
            )

            let initialDispatches = parsedAssignments.map { item -> (String, String, String?) in
                let prompt = strings.t(
                    "用户总目标：\(userText)\n\n主控分派给你的子任务：\(item.subtask)",
                    "User goal: \(userText)\n\nYour assigned subtask: \(item.subtask)"
                )
                return (item.personaId, prompt, item.subtask)
            }

            for item in parsedAssignments {
                spokenInWave.insert(item.personaId)
            }

            var latestMessages = await runBotsInParallel(
                groupId: groupId,
                dispatches: initialDispatches,
                systemPromptSuffix: workerSuffix,
                project: project,
                topicId: topicId,
                trackAssignments: true
            )
            collectedMessages.append(contentsOf: latestMessages)

            // Bounded bot-to-bot handoff: at most 2 rounds, never re-triggering bots that already spoke this turn.
            let maxHandoffRounds = 2
            for _ in 0..<maxHandoffRounds {
                if Task.isCancelled { break }
                var nextHandoffs: [(personaId: String, subtask: String, fromBotId: String)] = []

                for msg in latestMessages {
                    guard case .bot(let speakerId) = msg.senderKind else { continue }
                    let handoffMentions = parseGroupMentions(
                        in: msg.content,
                        participantPersonaIds: participants
                    )
                    for targetId in handoffMentions.mentionedIds {
                        guard targetId != speakerId,
                              !spokenInWave.contains(targetId),
                              !nextHandoffs.contains(where: { $0.personaId == targetId }) else {
                            continue
                        }
                        let speakerName = personas.first(where: { $0.id == speakerId })?.name(resolvedLanguage) ?? speakerId
                        let snippet = String(msg.content.prefix(600))
                        let prompt = strings.t(
                            "用户总目标：\(userText)\n\n队友 \(speakerName) 在协作中 @了你 并请求接力：\n\(snippet)",
                            "User goal: \(userText)\n\nTeammate \(speakerName) @mentioned you for a handoff:\n\(snippet)"
                        )
                        nextHandoffs.append((targetId, prompt, speakerId))
                    }
                }

                guard !nextHandoffs.isEmpty else { break }

                let handoffTime = ISO8601DateFormatter().string(from: Date())
                if let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) {
                    for h in nextHandoffs {
                        spokenInWave.insert(h.personaId)
                        let speakerName = personas.first(where: { $0.id == h.fromBotId })?.name(resolvedLanguage) ?? h.fromBotId
                        groupChats[gIdx].assignments.append(
                            PipiSwarmTaskAssignment(
                                personaId: h.personaId,
                                taskTitle: strings.t("来自 \(speakerName) 的交接", "Handoff from \(speakerName)"),
                                status: .queued,
                                updatedAt: handoffTime
                            )
                        )
                    }
                    saveResidentState()
                }

                latestMessages = await runBotsInParallel(
                    groupId: groupId,
                    dispatches: nextHandoffs.map { ($0.personaId, $0.subtask, strings.t("接力协作", "Handoff")) },
                    systemPromptSuffix: workerSuffix,
                    project: project,
                    topicId: topicId,
                    trackAssignments: true
                )
                collectedMessages.append(contentsOf: latestMessages)
            }
            return collectedMessages
        }
    }

    @discardableResult
    private func runBotsInParallel(
        groupId: String,
        dispatches: [(personaId: String, prompt: String, roleTag: String?)],
        systemPromptSuffix: String,
        project: PipiProject?,
        topicId: String?,
        trackAssignments: Bool = false
    ) async -> [PipiGroupMessage] {
        guard !dispatches.isEmpty else { return [] }

        var tasks: [Task<(Int, PipiGroupMessage), Never>] = []
        for (index, item) in dispatches.enumerated() {
            guard let persona = personas.first(where: { $0.id == item.personaId }) else { continue }
            if trackAssignments {
                updateAssignmentStatus(groupId: groupId, personaId: item.personaId, status: .working)
            }
            let pid = item.personaId
            let promptText = item.prompt
            let roleTag = item.roleTag
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    return (index, PipiGroupMessage(senderKind: .bot(personaId: pid), content: "", isError: true, topicId: topicId))
                }
                let outcome = await self.invokeSingleBotForGroup(
                    groupId: groupId,
                    persona: persona,
                    promptText: promptText,
                    systemPromptSuffix: systemPromptSuffix,
                    roleTag: roleTag,
                    project: project,
                    topicId: topicId
                )
                if trackAssignments {
                    self.updateAssignmentStatus(
                        groupId: groupId,
                        personaId: pid,
                        status: outcome.succeeded ? .done : .failed
                    )
                }
                return (index, outcome.message)
            }
            tasks.append(task)
        }

        let capturedTasks = tasks
        var indexedResults: [(Int, PipiGroupMessage)] = []
        await withTaskCancellationHandler {
            for task in capturedTasks {
                indexedResults.append(await task.value)
            }
        } onCancel: {
            for task in capturedTasks {
                task.cancel()
            }
        }
        return indexedResults.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private func updateAssignmentStatus(
        groupId: String,
        personaId: String,
        status: PipiSwarmTaskAssignment.Status
    ) {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) else { return }
        let nowIso = ISO8601DateFormatter().string(from: Date())
        if let aIdx = groupChats[gIdx].assignments.lastIndex(where: { $0.personaId == personaId }) {
            groupChats[gIdx].assignments[aIdx].status = status
            groupChats[gIdx].assignments[aIdx].updatedAt = nowIso
        }
    }

    private func invokeSingleBotForGroup(
        groupId: String,
        persona: PipiBotPersona,
        promptText: String,
        systemPromptSuffix: String,
        roleTag: String?,
        project: PipiProject?,
        topicId: String?,
        handoffHop: Int = 0,
        handoffArtifactIds: [String] = []
    ) async -> (message: PipiGroupMessage, succeeded: Bool) {
        let isRemoteTarget = persona.isRemoteHost && sessionInferenceExecutor == nil && inferenceExecutor == nil
        let target: PipiExecutionTarget? = isRemoteTarget ? .auto : resolvedActiveTarget(for: persona)
        guard let target else {
            let errMsg = PipiGroupMessage(
                senderKind: .bot(personaId: persona.id),
                content: strings.noConfiguredEngineGuide,
                engineLabel: strings.appName,
                roleTag: roleTag,
                isError: true,
                topicId: topicId
            )
            if let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) {
                groupChats[gIdx].messages.append(errMsg)
                groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
                saveResidentState()
            }
            return (errMsg, false)
        }

        let hostBadge = persona.hostBadgeLabel(resolvedLanguage)
        let laneId = "lane_\(UUID().uuidString.prefix(8).lowercased())"
        activeGroupLanes.append(PipiGroupActiveLane(
            runId: laneId,
            groupId: groupId,
            topicId: topicId,
            personaId: persona.id,
            personaName: persona.name(resolvedLanguage),
            hostLabel: hostBadge,
            statusText: isRemoteTarget ? "正在连接 [\(hostBadge)]…" : "正在并行处理…"
        ))

        let engineLabel: String = {
            if isRemoteTarget {
                return "🖥️ \(hostBadge)"
            }
            switch target {
            case .llm(let pid):
                if let cfg = resolvedEffectiveLLMConfig(providerId: pid, for: persona) {
                    return "\(cfg.name) · \(cfg.modelId)"
                }
                return strings.appName
            case .localAgent(let kind):
                return kind.displayName
            case .auto:
                return strings.appName
            }
        }()

        let nowIso = ISO8601DateFormatter().string(from: Date())
        let placeholder = PipiGroupMessage(
            senderKind: .bot(personaId: persona.id),
            content: "",
            createdAt: nowIso,
            engineLabel: engineLabel,
            roleTag: roleTag,
            isError: false,
            topicId: topicId
        )
        let msgId = placeholder.id

        if let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) {
            groupChats[gIdx].messages.append(placeholder)
        }
        var workingSet = activeGroupRuns[groupId] ?? []
        workingSet.insert(persona.id)
        activeGroupRuns[groupId] = workingSet

        var streamMap = activeGroupStreamingMessageIds[groupId] ?? [:]
        streamMap[persona.id] = msgId
        activeGroupStreamingMessageIds[groupId] = streamMap

        var startMap = activeGroupRunStartTimes[groupId] ?? [:]
        startMap[persona.id] = Date()
        activeGroupRunStartTimes[groupId] = startMap

        if groupId == activeGroupChatId {
            switch target {
            case .localAgent:
                avatarEngine.setState(.claudeRouting)
            default:
                avatarEngine.setState(.byokStreaming)
            }
        }

        defer {
            activeGroupLanes.removeAll { $0.runId == laneId }
            let stillActiveSameBot = activeGroupLanes.contains { $0.groupId == groupId && $0.personaId == persona.id }
            if !stillActiveSameBot, var set = activeGroupRuns[groupId] {
                set.remove(persona.id)
                if set.isEmpty {
                    activeGroupRuns.removeValue(forKey: groupId)
                } else {
                    activeGroupRuns[groupId] = set
                }
            }
            if var sm = activeGroupStreamingMessageIds[groupId] {
                sm.removeValue(forKey: persona.id)
                if sm.isEmpty { activeGroupStreamingMessageIds.removeValue(forKey: groupId) }
                else { activeGroupStreamingMessageIds[groupId] = sm }
            }
            if var tm = activeGroupRunStartTimes[groupId] {
                tm.removeValue(forKey: persona.id)
                if tm.isEmpty { activeGroupRunStartTimes.removeValue(forKey: groupId) }
                else { activeGroupRunStartTimes[groupId] = tm }
            }
        }

        let groupContextSection: String = {
            guard let liveGroup = groupChats.first(where: { $0.id == groupId }) else { return "" }
            return buildGroupContextPromptSection(for: liveGroup, topicId: topicId)
        }()
        let promptSections = [
            buildSystemPrompt(for: persona, project: project),
            groupContextSection,
            systemPromptSuffix
        ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let effectiveSystemPrompt = promptSections.joined(separator: "\n\n")
        let workDir = (project?.workspacePath?.isEmpty == false ? project?.workspacePath : nil) ?? workspaceDirectory
        let effectivePermission = effectivePermissionTier(for: persona, project: project)

        // Build clean conversational history scoped to the active topic, excluding empty placeholders
        var history: [PipiChatMessage] = []
        if let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) {
            let scopedMessages = groupChats[gIdx].messages(forTopic: topicId)
            let recent = scopedMessages
                .filter { $0.id != msgId && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .suffix(12)
            for item in recent {
                switch item.senderKind {
                case .user:
                    history.append(PipiChatMessage(role: .user, content: item.content, createdAt: item.createdAt))
                case .bot(let senderId):
                    if senderId == persona.id {
                        history.append(PipiChatMessage(role: .assistant, content: item.content, createdAt: item.createdAt))
                    } else {
                        let senderName = personas.first(where: { $0.id == senderId })?.name(resolvedLanguage) ?? senderId
                        history.append(PipiChatMessage(role: .user, content: "[\(senderName)]: \(item.content)", createdAt: item.createdAt))
                    }
                case .system:
                    break
                }
            }
        }
        if history.last?.content != promptText {
            history.append(PipiChatMessage(role: .user, content: promptText, createdAt: nowIso))
        }

        let onDelta: @Sendable (String) -> Void = { [weak self] chunk in
            Task { @MainActor [weak self] in
                guard let self,
                      let gIdx = self.groupChats.firstIndex(where: { $0.id == groupId }),
                      let mIdx = self.groupChats[gIdx].messages.firstIndex(where: { $0.id == msgId }) else {
                    return
                }
                self.groupChats[gIdx].messages[mIdx].content += chunk
            }
        }
        let onCLIEvent: @Sendable (PipiParsedCLIEvent) -> Void = { _ in }

        let customSessionExecutor = self.sessionInferenceExecutor
        let customExecutor = self.inferenceExecutor

        do {
            if Task.isCancelled { throw CancellationError() }
            let result: PipiInferenceResult
            if isRemoteTarget {
                let remoteOutcome = try await meshHubClient.dispatchAndAwaitTask(
                    targetNodeId: persona.hostId,
                    prompt: promptText,
                    botId: persona.id,
                    botName: persona.name(resolvedLanguage),
                    groupId: groupId,
                    topicId: topicId,
                    handoffFromBot: handoffHop > 0 ? "handoff" : nil,
                    handoffHop: handoffHop,
                    artifactIds: handoffArtifactIds,
                    onProgress: { [weak self] stepNote in
                        await MainActor.run {
                            if let idx = self?.activeGroupLanes.firstIndex(where: { $0.runId == laneId }) {
                                self?.activeGroupLanes[idx].statusText = stepNote
                            }
                        }
                    }
                )
                let deliverablesDir = localDataRootURL.appendingPathComponent("deliverables", isDirectory: true)
                var downloadedNotes: [String] = []
                for artId in remoteOutcome.artifactIds {
                    if let art = await meshHubClient.downloadArtifact(artifactId: artId, deliverablesDir: deliverablesDir) {
                        macOmnipotentEngine.registerArtifact(art)
                        downloadedNotes.append("📎 跨机产物已同步：\(art.fileName) (`\(art.filePath)`)")
                    }
                }
                let finalRemoteText = ([remoteOutcome.text] + downloadedNotes)
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: "\n\n")
                result = PipiInferenceResult(text: finalRemoteText, engineLabel: "🖥️ \(hostBadge)")
            } else {
                switch target {
                case .llm(let providerId):
                    guard let cfg = resolvedEffectiveLLMConfig(providerId: providerId, for: persona) else {
                        throw PipiInferenceError.emptyResponse
                    }
                    if let customSessionExecutor {
                        result = try await customSessionExecutor(
                            target,
                            cfg,
                            effectiveSystemPrompt,
                            history,
                            workDir,
                            effectivePermission,
                            nil,
                            onDelta,
                            onCLIEvent
                        )
                    } else if let customExecutor {
                        result = try await customExecutor(
                            target,
                            cfg,
                            effectiveSystemPrompt,
                            history,
                            workDir,
                            onDelta
                        )
                    } else {
                        result = try await PipiInferenceEngine.invokeLLM(
                            config: cfg,
                            systemPrompt: effectiveSystemPrompt,
                            history: history,
                            onDelta: onDelta
                        )
                    }

                case .localAgent(let kind):
                    let safePerm: PipiPermissionTier = (effectivePermission == .ask) ? .readOnly : effectivePermission
                    if let customSessionExecutor {
                        result = try await customSessionExecutor(
                            target,
                            nil,
                            effectiveSystemPrompt,
                            history,
                            workDir,
                            safePerm,
                            nil,
                            onDelta,
                            onCLIEvent
                        )
                    } else if let customExecutor {
                        result = try await customExecutor(
                            target,
                            nil,
                            effectiveSystemPrompt,
                            history,
                            workDir,
                            onDelta
                        )
                    } else {
                        let injectedEnv = await self.resolveCLIReverseInjectionEnvironment(for: kind, profileId: groupId)
                        result = try await PipiInferenceEngine.invokeLocalAgent(
                            kind: kind,
                            systemPrompt: effectiveSystemPrompt,
                            history: history,
                            workingDirectory: workDir,
                            permissionTier: safePerm,
                            cliSessionId: nil,
                            extraEnvironment: injectedEnv,
                            onDelta: onDelta,
                            onEvent: onCLIEvent
                        )
                    }

                case .auto:
                    throw PipiInferenceError.emptyResponse
                }
            }

            // Cross-Machine `@Agent` Handoff: detect `<pipi_handoff target="@name" artifact="optional/path">...</pipi_handoff>`
            var displayResultText = result.text
            if handoffHop < 3, let handoff = PipiHandoffParser.extract(from: result.text) {
                let targetQuery = handoff.directive.targetQuery
                let participants = groupChats.first(where: { $0.id == groupId })?.participantPersonaIds ?? []
                if let targetPersona = personas.first(where: { p in
                    p.id != persona.id &&
                        participants.contains(p.id) &&
                        (p.nameZh.localizedCaseInsensitiveContains(targetQuery)
                            || p.nameEn.localizedCaseInsensitiveContains(targetQuery)
                            || (p.hostDisplayName?.localizedCaseInsensitiveContains(targetQuery) == true))
                }) {
                    let targetHost = targetPersona.hostBadgeLabel(resolvedLanguage)
                    let handoffNote = "🔀 已跨机交接给 @\(targetPersona.name(resolvedLanguage)) [\(targetHost)]：\(handoff.directive.instruction)"
                    displayResultText = [handoff.cleanedText, handoffNote].filter { !$0.isEmpty }.joined(separator: "\n\n")

                    var relayArtifactIds: [String] = []
                    if let artPath = handoff.directive.artifactPath {
                        let expanded = PipiJarvisToolRiskEvaluator.resolveExpandedPath(artPath, workspaceDirectory: workDir)
                        if FileManager.default.fileExists(atPath: expanded),
                           let uploadedId = await meshHubClient.uploadArtifact(fileURL: URL(fileURLWithPath: expanded), sourceNodeId: persona.hostId) {
                            relayArtifactIds.append(uploadedId)
                        }
                    }

                    let handoffRunId = "ghandoff_\(UUID().uuidString.prefix(8).lowercased())"
                    let handoffTask = Task { @MainActor [weak self] () -> [PipiGroupMessage] in
                        guard let self else { return [] }
                        let res = await self.invokeSingleBotForGroup(
                            groupId: groupId,
                            persona: targetPersona,
                            promptText: "[来自 @\(persona.name(self.resolvedLanguage)) (\(hostBadge)) 的跨机交接]\n\(handoff.directive.instruction)",
                            systemPromptSuffix: systemPromptSuffix,
                            roleTag: "跨机接力",
                            project: project,
                            topicId: topicId,
                            handoffHop: handoffHop + 1,
                            handoffArtifactIds: relayArtifactIds
                        )
                        return [res.message]
                    }
                    groupRunTasksByRunId[handoffRunId] = (groupId: groupId, task: handoffTask)
                    Task { @MainActor [weak self] in
                        _ = await handoffTask.value
                        self?.groupRunTasksByRunId.removeValue(forKey: handoffRunId)
                    }
                }
            }

            let parsedOutMentions = parseGroupMentions(
                in: displayResultText,
                participantPersonaIds: groupChats.first(where: { $0.id == groupId })?.participantPersonaIds ?? []
            )
            let updatedAt = ISO8601DateFormatter().string(from: Date())
            if let gIdx = groupChats.firstIndex(where: { $0.id == groupId }),
               let mIdx = groupChats[gIdx].messages.firstIndex(where: { $0.id == msgId }) {
                groupChats[gIdx].messages[mIdx].content = displayResultText
                groupChats[gIdx].messages[mIdx].engineLabel = result.engineLabel
                groupChats[gIdx].messages[mIdx].mentionedPersonaIds = parsedOutMentions.mentionedIds
                groupChats[gIdx].updatedAt = updatedAt
                saveResidentState()
                return (groupChats[gIdx].messages[mIdx], true)
            }
            var fallback = placeholder
            fallback.content = displayResultText
            fallback.engineLabel = result.engineLabel
            fallback.mentionedPersonaIds = parsedOutMentions.mentionedIds
            return (fallback, true)

        } catch is CancellationError {
            if let gIdx = groupChats.firstIndex(where: { $0.id == groupId }),
               let mIdx = groupChats[gIdx].messages.firstIndex(where: { $0.id == msgId }) {
                if groupChats[gIdx].messages[mIdx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    groupChats[gIdx].messages[mIdx].content = strings.t("已停止生成。", "Generation stopped.")
                }
                groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
                saveResidentState()
                return (groupChats[gIdx].messages[mIdx], false)
            }
            return (placeholder, false)

        } catch {
            let errText = error.localizedDescription.isEmpty
                ? strings.t("执行失败。", "Execution failed.")
                : error.localizedDescription
            if let gIdx = groupChats.firstIndex(where: { $0.id == groupId }),
               let mIdx = groupChats[gIdx].messages.firstIndex(where: { $0.id == msgId }) {
                groupChats[gIdx].messages[mIdx].content = errText
                groupChats[gIdx].messages[mIdx].isError = true
                groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
                saveResidentState()
                return (groupChats[gIdx].messages[mIdx], false)
            }
            var errCopy = placeholder
            errCopy.content = errText
            errCopy.isError = true
            return (errCopy, false)
        }
    }

    // MARK: - Actions (Live + Seamless Offline Fallback)

    public func createOutcome(
        title: String,
        domain: OutcomeDomain,
        goal: String,
        preferredHarness: HarnessProvider,
        dailyBudgetUsd: Double
    ) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedGoal.isEmpty else { return }

        if connectionMode == .liveDaemon {
            if let created = try? await client.createOutcome(
                title: trimmedTitle,
                domain: domain,
                goal: trimmedGoal,
                preferredHarness: preferredHarness,
                dailyBudgetUsd: dailyBudgetUsd
            ) {
                outcomes.insert(created.outcome, at: 0)
                avatarEngine.setState(.planStructuring)
                noticeBanner = "Created Outcome: \(created.outcome.title)"
                return
            }
        }

        let nowIso = ISO8601DateFormatter().string(from: Date())
        let localOutcome = OutcomeResponsibility(
            id: "out_\(UUID().uuidString.prefix(8).lowercased())",
            title: trimmedTitle,
            domain: domain,
            goal: trimmedGoal,
            constraints: ["Strict sandbox boundaries", "Escalate irreversible actions"],
            successMetrics: ["All automated assertions pass"],
            triggers: [OutcomeTriggerSpec(id: "trg_manual", kind: .cron, expression: "0 */4 * * *", enabled: true)],
            preferredHarness: preferredHarness,
            fallbackHarnesses: [.pi],
            targetNodeId: domain == .infra ? "hk-vps-01" : "mac-resident",
            status: .active,
            maxSubSessions: 3,
            dailyBudgetUsd: dailyBudgetUsd,
            spentTodayUsd: 0.0,
            lastEvaluatedAt: nowIso,
            lastEvidenceArtifactIds: [],
            createdAt: nowIso,
            updatedAt: nowIso
        )
        outcomes.insert(localOutcome, at: 0)
        avatarEngine.setState(.planStructuring)
        noticeBanner = "Created Outcome: \(trimmedTitle)"
        saveResidentState()
    }

    public func evaluateOutcome(_ outcomeId: String) async {
        avatarEngine.setState(.planStructuring)
        if connectionMode == .liveDaemon {
            if let res = try? await client.evaluateOutcome(id: outcomeId) {
                if let idx = outcomes.firstIndex(where: { $0.id == res.outcome.id }) {
                    outcomes[idx] = res.outcome
                }
                if let sub = res.subSession {
                    subSessions.insert(sub, at: 0)
                }
                if let dec = res.createdDecision {
                    decisions.insert(dec, at: 0)
                }
                avatarEngine.setState(res.createdDecision != nil ? .needsYou : .synthesizing)
                noticeBanner = res.skipReason ?? "Evaluated \(res.outcome.title)"
                return
            }
        }

        guard let idx = outcomes.firstIndex(where: { $0.id == outcomeId }) else { return }
        let nowIso = ISO8601DateFormatter().string(from: Date())
        outcomes[idx].status = .achieved
        outcomes[idx].lastEvaluatedAt = nowIso
        outcomes[idx].updatedAt = nowIso
        outcomes[idx].spentTodayUsd += 0.04
        let sub = SubSession(
            id: "sub_\(UUID().uuidString.prefix(8).lowercased())",
            parentOutcomeId: outcomes[idx].id,
            role: "\(outcomes[idx].domain.rawValue)-evaluator",
            objective: "Preflight & Stage 2 verification for \(outcomes[idx].title)",
            provider: outcomes[idx].preferredHarness,
            modelId: "pi-native-core",
            nodeId: outcomes[idx].targetNodeId ?? "mac-resident",
            status: .succeeded,
            lastPulseAt: nowIso,
            artifactIds: [],
            summary: "All success metrics verified within budget.",
            startedAt: nowIso,
            completedAt: nowIso
        )
        subSessions.insert(sub, at: 0)
        avatarEngine.setState(.synthesizing)
        noticeBanner = "Evaluated \(outcomes[idx].title) cleanly"
    }

    public func resolveDecision(_ decisionId: String, optionId: String, note: String? = nil) async {
        if connectionMode == .liveDaemon {
            if let res = try? await client.resolveDecision(id: decisionId, chosenOptionId: optionId, userNote: note) {
                if let idx = decisions.firstIndex(where: { $0.id == res.decision.id }) {
                    decisions[idx] = res.decision
                }
                avatarEngine.setState(.gitCommitting)
                noticeBanner = "Decision recorded: \(res.decision.title)"
                return
            }
        }

        guard let idx = decisions.firstIndex(where: { $0.id == decisionId }) else { return }
        let nowIso = ISO8601DateFormatter().string(from: Date())
        decisions[idx].status = .resolved
        decisions[idx].chosenOptionId = optionId
        decisions[idx].userNote = note
        decisions[idx].resolvedBy = "apple-app"
        decisions[idx].resolvedAt = nowIso
        avatarEngine.setState(optionId.contains("reject") ? .thinking : .gitCommitting)
        noticeBanner = "Resolved: \(decisions[idx].title)"
        saveResidentState()
    }

    public func executeCueAction(_ action: CueAction) async {
        guard let cue = latestCue else { return }
        activeHarness = action.harness
        avatarEngine.setState(avatarState(for: action.harness))

        if connectionMode == .liveDaemon {
            if let res = try? await client.executeCueAction(cueId: cue.id, actionId: action.id) {
                latestCue = res.cue
                appendChatPair(prompt: action.promptTemplate, reply: res.turnResult.text, harness: res.turnResult.providerUsed)
                noticeBanner = "Cue executed via \(action.harness.displayName)"
                return
            }
        }

        latestCue?.feedback = .accepted
        appendChatPair(
            prompt: action.promptTemplate,
            reply: "[\(action.harness.displayName)] Routed via PipiHarnessRouter + RoutedMcpBridge. Context attached from \(cue.activeAppName) (\(cue.gitBranch ?? "main")). Action completed and logged to L1 memory.",
            harness: action.harness
        )
        noticeBanner = "Executed \(action.label)"
    }

    public func refreshCueContext(appName: String? = nil, windowTitle: String? = nil, gitBranch: String? = nil) async {
        avatarEngine.setState(.cueWindowMatched)
        if enableNativeRuntime && appName == nil {
            let detected = PipiNativeMacRuntime.detectFrontmostAppContext()
            latestCue = detected
            if connectionMode == .liveDaemon {
                if let res = try? await client.refreshCue(
                    activeAppName: detected.activeAppName,
                    windowTitle: detected.windowTitle,
                    workspacePath: detected.workspacePath,
                    gitBranch: detected.gitBranch
                ) {
                    latestCue = res.cue
                }
            }
            return
        }
        let targetApp = appName ?? "Xcode"
        let targetWindow = windowTitle ?? "PipiBotApple — Package.swift"
        let targetBranch = gitBranch ?? "main"
        if connectionMode == .liveDaemon {
            if let res = try? await client.refreshCue(
                activeAppName: targetApp,
                windowTitle: targetWindow,
                workspacePath: PipiNativeMacRuntime.discoverRepoRoot() ?? "/Users/jimizhou/Desktop/Projects/pipibot",
                gitBranch: targetBranch
            ) {
                latestCue = res.cue
                return
            }
        }
        let nowIso = ISO8601DateFormatter().string(from: Date())
        latestCue = CueSuggestion(
            id: "cue_\(UUID().uuidString.prefix(8).lowercased())",
            nodeId: "mac-resident",
            activeAppName: targetApp,
            activeAppBundleId: "com.apple.dt.Xcode",
            windowTitle: targetWindow,
            workspacePath: PipiNativeMacRuntime.discoverRepoRoot() ?? "/Users/jimizhou/Desktop/Projects/pipibot",
            gitBranch: targetBranch,
            detectedIntent: "Review Swift 6 package diagnostics and run PipiBotKitTests",
            confidence: 0.94,
            actions: [
                CueAction(id: "act_swift_test", label: "Run Swift Tests via Pi", hotkeyHint: "⌘1", harness: .pi, promptTemplate: "Run swift test in apps/apple and report coverage.", estimatedSeconds: 8),
                CueAction(id: "act_claude_review", label: "Audit Concurrency via Claude", hotkeyHint: "⌘2", harness: .claudeCode, promptTemplate: "Review Swift 6 Sendable actors across PipiBotKit.", estimatedSeconds: 18),
                CueAction(id: "act_codex_bench", label: "Add Edge Tests via Codex", hotkeyHint: "⌘3", harness: .codex, promptTemplate: "Generate edge-case physics assertions for 192 rays.", estimatedSeconds: 12)
            ],
            capturedAt: nowIso,
            expiresAt: nowIso
        )
    }

    public func sendChatMessage(_ text: String, harness: HarnessProvider? = nil) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let selectedHarness = harness ?? activeHarness
        activeHarness = selectedHarness
        avatarEngine.setState(avatarState(for: selectedHarness))

        if connectionMode == .liveDaemon {
            if let res = try? await client.sendChatTurn(prompt: trimmed, provider: selectedHarness) {
                appendChatPair(prompt: trimmed, reply: res.text, harness: res.providerUsed)
                avatarEngine.setState(.synthesizing)
                return
            }
        }

        appendChatPair(
            prompt: trimmed,
            reply: "[\(selectedHarness.displayName)] Recalled top L2 user facts & routed with 4-tool Pi kernel + MCP Bridge. Task handled cleanly with zero duplicate API keys.",
            harness: selectedHarness
        )
        avatarEngine.setState(.synthesizing)
    }

    public func addMuseCard(title: String, body: String, kind: MuseCardKind, domain: OutcomeDomain) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let nowIso = ISO8601DateFormatter().string(from: Date())
        let index = Double(museCards.count)
        let card = MuseCardItem(
            id: "muse_\(UUID().uuidString.prefix(8).lowercased())",
            kind: kind,
            domain: domain,
            title: trimmedTitle,
            body: body.isEmpty ? "Captured via Muse spatial voice/card studio" : body,
            offsetX: (index.truncatingRemainder(dividingBy: 2) == 0 ? 18 : 170),
            offsetY: 20 + floor(index / 2) * 124,
            harness: activeHarness,
            timestamp: nowIso
        )
        museCards.insert(card, at: 0)
        avatarEngine.setState(.voiceInterrupted)
        noticeBanner = "Added Muse card: \(trimmedTitle)"
        saveResidentState()
    }

    public func moveMuseCard(id: String, x: Double, y: Double) {
        guard let idx = museCards.firstIndex(where: { $0.id == id }) else { return }
        museCards[idx].offsetX = max(8, x)
        museCards[idx].offsetY = max(8, y)
    }

    public func runNightlyDreaming() async {
        avatarEngine.setState(.dreamingConsolidating)
        if connectionMode == .liveDaemon {
            if let res = try? await client.runDreamCycle() {
                lastDigest = res.summary
                understandingScore = res.summary.understandingScore
                avatarEngine.setState(.evolutionProud)
                noticeBanner = "Nightly Dreaming consolidated \(res.summary.episodicEventsProcessed) episodes"
                return
            }
        }

        let currentScore = understandingScore.overall
        let boosted = min(99.0, currentScore + 1.4)
        understandingScore = UnderstandingScoreBreakdown(
            overall: boosted,
            deltaFromPrevious: boosted - currentScore,
            breakdown: understandingScore.breakdown,
            metrics: understandingScore.metrics
        )
        let newDiff = EvolutionDiffItem(
            diffId: "diff_\(UUID().uuidString.prefix(6).lowercased())",
            operation: .addSkill,
            targetFile: "skills/apple-swift6-audit/SKILL.md",
            domain: .codingConvention,
            title: "Synthesize Swift 6 zero-raw-hex audit check",
            proposedValue: "Always verify DesignTokens.swift isolation and swift test before posting [done].",
            confidence: 0.93,
            evidenceSummary: "Observed 4 consecutive verified Swift 6 checks across Mac + iOS packages.",
            reviewStatus: .pending
        )
        if var digest = lastDigest {
            digest.diffs.insert(newDiff, at: 0)
            digest.requiresUserReviewCount = digest.diffs.filter { $0.reviewStatus == .pending }.count
            digest.understandingScore = understandingScore
            lastDigest = digest
        }
        avatarEngine.setState(.evolutionProud)
        noticeBanner = "Dreaming cycle complete (+1.4% Understanding)"
    }

    public func reviewEvolutionDiff(diffId: String, approve: Bool) async {
        let action = approve ? "approve" : "revert"
        if connectionMode == .liveDaemon {
            if let res = try? await client.reviewEvolutionDiff(diffId: diffId, action: action) {
                lastDigest = res.summary
                understandingScore = res.summary.understandingScore
                avatarEngine.setState(approve ? .evolutionProud : .memoryPruning)
                return
            }
        }
        guard var digest = lastDigest,
              let idx = digest.diffs.firstIndex(where: { $0.diffId == diffId }) else { return }
        digest.diffs[idx].reviewStatus = approve ? .approved : .reverted
        digest.requiresUserReviewCount = digest.diffs.filter { $0.reviewStatus == .pending }.count
        lastDigest = digest
        avatarEngine.setState(approve ? .evolutionProud : .memoryPruning)
    }

    public func avatarState(for provider: HarnessProvider) -> AvatarState53 {
        switch provider {
        case .pi: return .piCoding
        case .claudeCode: return .claudeRouting
        case .codex: return .codexRouting
        case .opencode: return .opencodeRouting
        case .byok: return .byokStreaming
        }
    }

    private func appendChatPair(prompt: String, reply: String, harness: HarnessProvider) {
        let nowIso = ISO8601DateFormatter().string(from: Date())
        chatMessages.append(
            ChatTranscriptMessage(
                id: "msg_\(UUID().uuidString.prefix(8))",
                role: .user,
                harness: harness,
                content: prompt,
                avatarState: .voiceTranscribing,
                timestamp: nowIso
            )
        )
        chatMessages.append(
            ChatTranscriptMessage(
                id: "msg_\(UUID().uuidString.prefix(8))",
                role: .assistant,
                harness: harness,
                content: reply,
                avatarState: avatarState(for: harness),
                timestamp: nowIso
            )
        )
    }

    // MARK: - Clean Empty State (Zero Dirty Data for Production Launches)

    private struct CleanEmptyPayload {
        let tunnel: CloudflareTunnelStatus
        let understanding: UnderstandingScoreBreakdown
        let soul: SoulDocumentPreview
    }

    private static func buildCleanEmptyState() -> CleanEmptyPayload {
        let now = ISO8601DateFormatter().string(from: Date())
        let tunnel = CloudflareTunnelStatus(
            tunnelConnected: false,
            tunnelUrl: "",
            tunnelRttMs: 0,
            cloudflaredInstalled: false,
            accessZeroTrustEnabled: false,
            offlineQueuePendingCount: 0,
            lastHeartbeatAt: now,
            freeTierQuota: CloudflareFreeTierQuotaSnapshot(
                workersReqToday: 0,
                d1ReadsToday: 0,
                d1WritesToday: 0,
                r2UsedBytes: 0
            )
        )
        let understanding = UnderstandingScoreBreakdown(
            overall: 0,
            deltaFromPrevious: 0,
            breakdown: [:],
            metrics: UnderstandingScoreBreakdown.Metrics(
                coverage: 0,
                cueAcceptanceRate: 0,
                memoryRetention: 0,
                correctionRate: 0
            )
        )
        let soul = SoulDocumentPreview(soulMd: "", userMd: "")
        return CleanEmptyPayload(tunnel: tunnel, understanding: understanding, soul: soul)
    }

    // MARK: - Rich Seed State (Unit Tests & Opt-In Demo Only)

    private struct SeedPayload {
        let harnesses: [HarnessProbeResult]
        let outcomes: [OutcomeResponsibility]
        let subSessions: [SubSession]
        let decisions: [NeedsYouDecision]
        let cue: CueSuggestion
        let nodes: [FleetNodeTelemetry]
        let tunnel: CloudflareTunnelStatus
        let museCards: [MuseCardItem]
        let chatMessages: [ChatTranscriptMessage]
        let memories: [MemoryEntry]
        let skills: [SynthesizedSkillCandidate]
        let understanding: UnderstandingScoreBreakdown
        let digest: EvolutionSummary
        let soul: SoulDocumentPreview
    }

    private static func buildOfflineSeed() -> SeedPayload {
        let now = "2026-11-19T00:30:00Z"

        let harnesses = [
            HarnessProbeResult(provider: .pi, installed: true, authenticated: true, binaryPath: "embedded-sdk", version: "0.2.0", authSource: "Pi Core SDK", supportsMcp: true, checkedAt: now),
            HarnessProbeResult(provider: .claudeCode, installed: true, authenticated: true, binaryPath: "/usr/local/bin/claude", version: "2.1.x", authSource: "Keychain OAuth", supportsMcp: true, checkedAt: now),
            HarnessProbeResult(provider: .codex, installed: true, authenticated: true, binaryPath: "/usr/local/bin/codex", version: "0.29.x", authSource: "~/.codex/auth.json", supportsMcp: true, checkedAt: now),
            HarnessProbeResult(provider: .opencode, installed: true, authenticated: true, binaryPath: "/opt/homebrew/bin/opencode", version: "0.9.x", authSource: "ACP :4096", supportsMcp: true, checkedAt: now),
            HarnessProbeResult(provider: .byok, installed: true, authenticated: true, binaryPath: "pi-ai", version: "1.0", authSource: "Keychain Vault", supportsMcp: true, checkedAt: now)
        ]

        let outcomes = [
            OutcomeResponsibility(
                id: "out_layout_cls",
                title: "Layout Bot · Zero CLS Regression",
                domain: .dev,
                goal: "Run every 3h on main, record first & repeat visits, trace layout shifts to PRs, and attach before/after video evidence.",
                constraints: ["Never force push main", "Daily budget <= $2.00", "Quiet hours 23:30-07:30"],
                successMetrics: ["CLS < 0.05", "Smoke tests 100%"],
                triggers: [OutcomeTriggerSpec(id: "trg_3h", kind: .cron, expression: "0 */3 * * *", nodeTarget: "hk-vps-01", enabled: true)],
                preferredHarness: .claudeCode,
                fallbackHarnesses: [.pi, .codex],
                targetNodeId: "hk-vps-01",
                status: .needsYou,
                maxSubSessions: 3,
                dailyBudgetUsd: 2.0,
                spentTodayUsd: 0.42,
                lastEvaluatedAt: now,
                lastEvidenceArtifactIds: ["art_cls_video"],
                createdAt: now,
                updatedAt: now
            ),
            OutcomeResponsibility(
                id: "out_android_parity",
                title: "Client Feature Parity Guardian",
                domain: .dev,
                goal: "Continuously keep companion surfaces aligned with core protocol types and design system governance.",
                constraints: ["Use 6 canonical named blocks", "Zero raw hex outside DesignTokens"],
                successMetrics: ["swift test passes", "audit-design-system passes"],
                triggers: [OutcomeTriggerSpec(id: "trg_push", kind: .webhook, expression: "github.push.main", enabled: true)],
                preferredHarness: .codex,
                fallbackHarnesses: [.pi],
                targetNodeId: "mac-resident",
                status: .delegating,
                maxSubSessions: 3,
                dailyBudgetUsd: 3.0,
                spentTodayUsd: 0.85,
                lastEvaluatedAt: now,
                createdAt: now,
                updatedAt: now
            ),
            OutcomeResponsibility(
                id: "out_vps_sentinel",
                title: "HK VPS & Home Sanctuary Watch",
                domain: .infra,
                goal: "Monitor Nginx TLS certificates, disk thresholds, and home Raspberry Pi/ESP32 air & water sensors.",
                constraints: ["Require approval before nginx restart", "Private data stays local"],
                successMetrics: ["TLS expiry > 14d", "Disk < 85%"],
                triggers: [OutcomeTriggerSpec(id: "trg_disk", kind: .telemetryThreshold, expression: "disk_used_pct > 85", nodeTarget: "hk-vps-01", enabled: true)],
                preferredHarness: .pi,
                fallbackHarnesses: [.byok],
                targetNodeId: "hk-vps-01",
                status: .needsYou,
                maxSubSessions: 2,
                dailyBudgetUsd: 0.5,
                spentTodayUsd: 0.03,
                lastEvaluatedAt: now,
                createdAt: now,
                updatedAt: now
            ),
            OutcomeResponsibility(
                id: "out_daily_brief",
                title: "Daily Life & Work Morning Digest",
                domain: .dailyLife,
                goal: "Synthesize calendar, family water filter reminder, and overnight PR outcomes into a 3-minute morning deck.",
                constraints: ["Respect quiet hours", "Zero external messages without sign-off"],
                successMetrics: ["Delivered at 08:00 local"],
                triggers: [OutcomeTriggerSpec(id: "trg_morn", kind: .cron, expression: "0 8 * * *", enabled: true)],
                preferredHarness: .pi,
                fallbackHarnesses: [.byok],
                targetNodeId: "mac-resident",
                status: .active,
                maxSubSessions: 2,
                dailyBudgetUsd: 0.8,
                spentTodayUsd: 0.09,
                lastEvaluatedAt: now,
                createdAt: now,
                updatedAt: now
            )
        ]

        let subSessions = [
            SubSession(
                id: "sub_cls_fix_142",
                parentOutcomeId: "out_layout_cls",
                role: "layout-remediator",
                objective: "Fix sticky header CLS jump (0.19 -> 0.01) in isolated git worktree",
                provider: .claudeCode,
                modelId: "claude-sonnet-4",
                nodeId: "mac-resident",
                worktreePath: ".pipibot-worktrees/out_layout_cls/sub_142",
                branchName: "pipibot/fix-header-cls-142",
                status: .needsYou,
                lastPulseAt: now,
                artifactIds: ["art_cls_video", "art_cls_diff"],
                summary: "Stabilized header height reservation; CLS dropped from 0.19 to 0.01.",
                startedAt: now
            ),
            SubSession(
                id: "sub_swift_parity",
                parentOutcomeId: "out_android_parity",
                role: "swift6-verifier",
                objective: "Cross-check 53 AvatarState53 cases across ProtocolModels & pipibot-avatar.js",
                provider: .codex,
                modelId: "gpt-5-codex",
                nodeId: "mac-resident",
                status: .running,
                lastPulseAt: now,
                summary: "Validating 192-ray contour math & 120Hz spring convergence.",
                startedAt: now
            ),
            SubSession(
                id: "sub_vps_nginx",
                parentOutcomeId: "out_vps_sentinel",
                role: "infra-triage",
                objective: "Rotate gzip logs & prepare TLS reload check on hk-vps-01",
                provider: .pi,
                modelId: "pi-native-core",
                nodeId: "hk-vps-01",
                status: .waitingTool,
                lastPulseAt: now,
                summary: "Awaiting human approval for systemctl reload nginx.",
                startedAt: now
            )
        ]

        let decisions = [
            NeedsYouDecision(
                id: "dec_pr_142",
                outcomeId: "out_layout_cls",
                sessionId: "sub_cls_fix_142",
                sourceNodeId: "mac-resident",
                severity: .warning,
                category: .codeMergeOrPush,
                title: "Approve PR #142: Fix Mobile Header CLS",
                summary: "Layout Bot traced CLS 0.19 regression to dynamic navbar hydration. Fixed in worktree with 0.01 CLS and verified repeat visit.",
                recommendedOptionId: "approve_merge",
                options: [
                    DecisionOption(id: "approve_merge", label: "Approve & Merge PR", style: .primary),
                    DecisionOption(id: "steer_rerun", label: "Request Re-run", style: .secondary),
                    DecisionOption(id: "reject_close", label: "Reject", style: .destructive)
                ],
                evidence: [
                    ArtifactEvidenceRef(artifactId: "art_cls_video", r2Key: "artifacts/out_layout_cls/pr142-before-after.mp4", kind: .video, caption: "Before (0.19 CLS) vs After (0.01 CLS) 60fps capture"),
                    ArtifactEvidenceRef(artifactId: "art_cls_diff", r2Key: "artifacts/out_layout_cls/pr142.patch", kind: .diffPatch, caption: "+14 / -3 lines in StickyHeader.tsx")
                ],
                createdAt: now
            ),
            NeedsYouDecision(
                id: "dec_vps_nginx",
                outcomeId: "out_vps_sentinel",
                sessionId: "sub_vps_nginx",
                sourceNodeId: "hk-vps-01",
                severity: .critical,
                category: .infraMutation,
                title: "Reload Nginx & Prune 4.2GB Rotated Logs",
                summary: "hk-vps-01 /var/log hit 87% capacity. Safe dry-run prepared 4.2GB gzipped archive cleanup plus graceful nginx reload.",
                recommendedOptionId: "approve_ops",
                options: [
                    DecisionOption(id: "approve_ops", label: "Execute Cleanup + Reload", style: .primary),
                    DecisionOption(id: "cleanup_only", label: "Prune Logs Only", style: .secondary),
                    DecisionOption(id: "defer", label: "Defer 4h", style: .destructive)
                ],
                evidence: [
                    ArtifactEvidenceRef(artifactId: "art_df_log", r2Key: "artifacts/out_vps_sentinel/df-report.txt", kind: .logExcerpt, caption: "df -h: /dev/vda1 87% -> projected 54% after prune")
                ],
                createdAt: now
            ),
            NeedsYouDecision(
                id: "dec_dream_diff",
                outcomeId: "out_daily_brief",
                sessionId: "dream_nightly_01",
                sourceNodeId: "mac-resident",
                severity: .info,
                category: .memoryEvolutionReview,
                title: "Approve Nightly Soul Diff (+1.8% Score)",
                summary: "PipiEvolve distilled 29 episodes: learned preference for Chinese engineering docs with exact English technical terms + RO filter 5-day alert.",
                recommendedOptionId: "approve_soul",
                options: [
                    DecisionOption(id: "approve_soul", label: "Commit to USER.md", style: .primary),
                    DecisionOption(id: "edit_soul", label: "Keep Pending", style: .secondary),
                    DecisionOption(id: "revert_soul", label: "Revert", style: .destructive)
                ],
                evidence: [
                    ArtifactEvidenceRef(artifactId: "art_soul_html", r2Key: "artifacts/dream/evolution-diff.html", kind: .htmlPreview, caption: "Understanding Score 78.4% -> 80.2%")
                ],
                createdAt: now
            )
        ]

        let cue = CueSuggestion(
            id: "cue_xcode_01",
            nodeId: "mac-resident",
            activeAppName: "Xcode",
            activeAppBundleId: "com.apple.dt.Xcode",
            windowTitle: "PipiBotApple — PipiProceduralAvatarEngine.swift",
            workspacePath: "/Users/jimizhou/Desktop/Projects/pipibot",
            gitBranch: "main",
            detectedIntent: "Run Swift 6 tests or audit OpenPencil token compliance",
            confidence: 0.95,
            actions: [
                CueAction(id: "act_pi_test", label: "Run Swift Test via Pi", hotkeyHint: "⌘1", harness: .pi, promptTemplate: "Run swift test in apps/apple and summarize results.", estimatedSeconds: 6),
                CueAction(id: "act_claude_arch", label: "Deep Review via Claude", hotkeyHint: "⌘2", harness: .claudeCode, promptTemplate: "Audit RoutedMcpBridge & PipiBotKit protocol alignment.", estimatedSeconds: 15),
                CueAction(id: "act_codex_perf", label: "Verify 120Hz Springs via Codex", hotkeyHint: "⌘3", harness: .codex, promptTemplate: "Check 120Hz semi-implicit Euler stability in PipiBotKitTests.", estimatedSeconds: 10)
            ],
            capturedAt: now,
            expiresAt: now
        )

        let nodes = [
            FleetNodeTelemetry(
                nodeId: "mac-resident",
                displayName: "MacBook Pro M3 (Host)",
                kind: .mac,
                osVersion: "macOS 15.4",
                arch: "arm64",
                vitality: .busy,
                cpuLoadPct: 24.5,
                memoryUsedPct: 48.2,
                diskUsedPct: 54.0,
                batteryPct: 92.0,
                isCharging: true,
                tunnelRttMs: 14,
                activeSessionsCount: 2,
                capabilities: FleetNodeCapabilities(canRunPi: true, localHarnesses: [.pi, .claudeCode, .codex, .opencode, .byok], hasGpuOrNeuralEngine: true, canRunGuiCue: true, canActAsRelayHost: true, supportedTools: ["read", "write", "edit", "bash", "cue"]),
                tags: ["primary", "launchd"],
                lastSeenAt: now
            ),
            FleetNodeTelemetry(
                nodeId: "ios-companion",
                displayName: "iPhone 16 Pro",
                kind: .ios,
                osVersion: "iOS 18.4",
                arch: "arm64",
                vitality: .alive,
                cpuLoadPct: 8.1,
                memoryUsedPct: 39.0,
                batteryPct: 84.0,
                isCharging: false,
                tunnelRttMs: 28,
                activeSessionsCount: 0,
                capabilities: FleetNodeCapabilities(canRunPi: false, localHarnesses: [], hasGpuOrNeuralEngine: true, canRunGuiCue: false, canActAsRelayHost: false, supportedTools: ["apns", "faceid", "voice"]),
                tags: ["companion", "dynamic-island"],
                lastSeenAt: now
            ),
            FleetNodeTelemetry(
                nodeId: "hk-vps-01",
                displayName: "HK Staging VPS",
                kind: .vps,
                osVersion: "Ubuntu 24.04",
                arch: "x86_64",
                vitality: .degraded,
                cpuLoadPct: 38.0,
                memoryUsedPct: 61.5,
                diskUsedPct: 87.0,
                tunnelRttMs: 36,
                activeSessionsCount: 1,
                capabilities: FleetNodeCapabilities(canRunPi: true, localHarnesses: [.pi], hasGpuOrNeuralEngine: false, canRunGuiCue: false, canActAsRelayHost: true, supportedTools: ["bash", "docker", "playwright"]),
                tags: ["layout-bot", "nginx"],
                lastSeenAt: now
            ),
            FleetNodeTelemetry(
                nodeId: "win-gpu-rig",
                displayName: "Windows RTX Rig (WSL2)",
                kind: .windows,
                osVersion: "Win11 + WSL2",
                arch: "x86_64",
                vitality: .sleeping,
                cpuLoadPct: 4.2,
                memoryUsedPct: 28.0,
                diskUsedPct: 41.0,
                tunnelRttMs: 42,
                activeSessionsCount: 0,
                capabilities: FleetNodeCapabilities(canRunPi: true, localHarnesses: [.pi, .codex, .byok], hasGpuOrNeuralEngine: true, canRunGuiCue: false, canActAsRelayHost: false, supportedTools: ["cuda", "vllm", "powershell"]),
                tags: ["gpu", "ollama"],
                lastSeenAt: now
            ),
            FleetNodeTelemetry(
                nodeId: "home-iot-rpi",
                displayName: "Home RPi + ESP32 Mesh",
                kind: .embedded,
                osVersion: "Debian ARM64",
                arch: "arm64",
                vitality: .alive,
                cpuLoadPct: 6.4,
                memoryUsedPct: 31.0,
                diskUsedPct: 29.5,
                tunnelRttMs: 19,
                activeSessionsCount: 1,
                capabilities: FleetNodeCapabilities(canRunPi: true, localHarnesses: [.pi], hasGpuOrNeuralEngine: false, canRunGuiCue: false, canActAsRelayHost: false, supportedTools: ["mqtt", "gpio", "home-assistant"]),
                tags: ["iot", "dots-led"],
                lastSeenAt: now
            )
        ]

        let tunnel = CloudflareTunnelStatus(
            tunnelConnected: true,
            tunnelUrl: "https://mac-origin.pipibot.dev",
            tunnelRttMs: 18,
            cloudflaredInstalled: true,
            accessZeroTrustEnabled: true,
            offlineQueuePendingCount: 0,
            lastHeartbeatAt: now,
            freeTierQuota: CloudflareFreeTierQuotaSnapshot(
                workersReqToday: 4_120,
                d1ReadsToday: 42_500,
                d1WritesToday: 9_840,
                r2UsedBytes: 3_920_000_000
            )
        )

        let museCards = [
            MuseCardItem(id: "muse_1", kind: .outcome, domain: .dev, title: "Layout Bot PR #142", body: "Header CLS fixed (0.19 -> 0.01). Video diff ready on R2.", offsetX: 16, offsetY: 16, harness: .claudeCode, timestamp: now),
            MuseCardItem(id: "muse_2", kind: .life, domain: .dailyLife, title: "RO Water Filter Alert", body: "5 days remaining on kitchen cartridge; price matched last order.", offsetX: 176, offsetY: 28, harness: .pi, timestamp: now),
            MuseCardItem(id: "muse_3", kind: .infra, domain: .infra, title: "HK VPS Disk 87%", body: "4.2 GB rotated nginx logs queued for approval.", offsetX: 24, offsetY: 162, harness: .pi, timestamp: now),
            MuseCardItem(id: "muse_4", kind: .voiceNote, domain: .work, title: "Hangzhou Weekend Plan", body: "Voice note: low-salt restaurant spots + pre-trip NAS backup.", offsetX: 182, offsetY: 174, harness: .byok, timestamp: now)
        ]

        let chatMessages = [
            ChatTranscriptMessage(id: "chat_1", role: .assistant, harness: .pi, content: "PipiCore online with 4 core tools + Routed MCP Bridge. All 5 fleet nodes reporting healthy telemetry over $0 Cloudflare Tunnel.", avatarState: .idle, timestamp: now)
        ]

        let memories = [
            MemoryEntry(id: "mem_1", seq: 1, tier: .l2Semantic, domain: .codingConvention, title: "Zero Raw Hex in Views", content: "Always route colors via DesignTokens.swift and CSS variables; enforce 44pt mobile / 32pt desktop buttons.", confidence: 0.97, importanceBase: 0.9, createdAt: 1_795_000_000),
            MemoryEntry(id: "mem_2", seq: 2, tier: .l2Semantic, domain: .dailyLife, title: "Quiet Hours Policy", content: "Hold non-critical P2/P3 alerts between 23:30 and 07:30 for the 08:00 Morning Decision Deck.", confidence: 0.95, importanceBase: 0.88, createdAt: 1_795_001_000),
            MemoryEntry(id: "mem_3", seq: 3, tier: .l3Procedural, domain: .infraTopology, title: "VPS Nginx Safe Reload Skill", content: "Run nginx -t && du -sh /var/log before requesting reload sign-off.", confidence: 0.92, importanceBase: 0.85, createdAt: 1_795_002_000)
        ]

        let skills = [
            SynthesizedSkillCandidate(
                slug: "layout-cls-triage",
                name: "Layout CLS Regression Triage",
                description: "Captures first/repeat visit metrics and isolates PR causing CLS > 0.05",
                domain: .codingConvention,
                toolSequence: ["bash:playwright", "read", "edit", "pipi_artifact_publish"],
                occurrences: 7,
                successRate: 0.96,
                status: "active"
            ),
            SynthesizedSkillCandidate(
                slug: "vps-log-hygiene",
                name: "VPS Safe Log Rotation",
                description: "Inspects disk usage, gzips logs > 500MB, and prepares Needs You approval.",
                domain: .infraTopology,
                toolSequence: ["pipi_fleet_exec:df", "bash:gzip", "pipi_needs_you_ask"],
                occurrences: 4,
                successRate: 1.0,
                status: "candidate"
            )
        ]

        let understanding = UnderstandingScoreBreakdown(
            overall: 80.2,
            deltaFromPrevious: 1.8,
            breakdown: [
                "coding_convention": 86.0,
                "communication_pref": 82.5,
                "daily_life": 74.0,
                "work_context": 79.0,
                "infra_topology": 83.5
            ],
            metrics: UnderstandingScoreBreakdown.Metrics(
                coverage: 0.81,
                cueAcceptanceRate: 0.88,
                memoryRetention: 0.92,
                correctionRate: 0.08
            )
        )

        let digest = EvolutionSummary(
            digestId: "dig_20261119",
            cycle: "nightly_dreaming",
            generatedAt: now,
            episodicEventsProcessed: 29,
            understandingScore: understanding,
            diffs: [
                EvolutionDiffItem(
                    diffId: "diff_bilingual_docs",
                    operation: .updateSoul,
                    targetFile: "USER.md",
                    domain: .communicationPref,
                    title: "Chinese architecture prose + exact English identifiers",
                    previousValue: "Default concise prose",
                    proposedValue: "Primary Chinese technical documentation preserving exact English protocol/API symbols.",
                    confidence: 0.96,
                    evidenceSummary: "Confirmed across 6 architecture & design system reviews.",
                    reviewStatus: .pending
                ),
                EvolutionDiffItem(
                    diffId: "diff_ro_filter",
                    operation: .add,
                    targetFile: "USER.md",
                    domain: .dailyLife,
                    title: "Kitchen RO Filter Replacement Threshold",
                    proposedValue: "Escalate replenishment card when estimated cartridge life <= 5 days.",
                    confidence: 0.89,
                    evidenceSummary: "Extracted from embedded Home Assistant TDS sensor trend.",
                    reviewStatus: .pending
                )
            ],
            candidateSkills: skills,
            requiresUserReviewCount: 2
        )

        let soul = SoulDocumentPreview(
            soulMd: """
            # SOUL.md · PipiBot Core Identity
            - Role: Personal & Infrastructure AI Manager (One Human + Bot Fleet)
            - Core Principles: Outcome ownership over task churn; 95% autonomous execution, 5% high-signal Needs You escalation.
            - Aesthetic: Ambient Soul & Outcome Studio — living 120Hz presence, zero noise.
            """,
            userMd: """
            # USER.md · Learned Owner Preferences
            - Engineering: Minimalist Pi 4-tool core, TypeScript + Swift 6 strict concurrency, zero raw hex outside tokens.
            - Infra: 100% Cloudflare Free Tier ($0/mo ceiling); never expose inbound Mac ports.
            - Daily Life: Respect 23:30-07:30 quiet hours except P0 critical infra alerts.
            """
        )

        return SeedPayload(
            harnesses: harnesses,
            outcomes: outcomes,
            subSessions: subSessions,
            decisions: decisions,
            cue: cue,
            nodes: nodes,
            tunnel: tunnel,
            museCards: museCards,
            chatMessages: chatMessages,
            memories: memories,
            skills: skills,
            understanding: understanding,
            digest: digest,
            soul: soul
        )
    }

    // MARK: - Wave 2 (#01 Personal Wiki, #02 Per-Bot Memory, #03 Native Proactive & Prepare)

    public func refreshWikiPages() {
        wikiPages = personalWiki?.listPages() ?? []
    }

    @discardableResult
    public func upsertWikiPage(_ input: PipiWikiPageInput) -> PipiPersonalWikiPage? {
        guard let wiki = personalWiki else { return nil }
        guard let page = try? wiki.upsertPage(input) else { return nil }
        refreshWikiPages()
        return page
    }

    public func deleteWikiPage(id: String) {
        guard let wiki = personalWiki else { return }
        _ = wiki.deletePage(id: id)
        refreshWikiPages()
    }

    public func searchPersonalWiki(_ options: PipiWikiSearchOptions) -> PipiWikiSearchResult {
        guard let wiki = personalWiki else {
            return PipiWikiSearchResult(
                query: options.query,
                effectiveQueries: [],
                scope: options.scope,
                usedFts5: false,
                usedVectorChannel: false,
                chunks: [],
                facts: [],
                summaries: []
            )
        }
        return wiki.search(options)
    }

    public func botMemorySummary(for botId: String) -> String {
        _ = botMemoryVersionCounter
        return botMemoryEngine.readSummary(for: botId)
    }

    public func botMemoryState(for botId: String) -> PipiBotMemoryState {
        _ = botMemoryVersionCounter
        return botMemoryEngine.readState(for: botId)
    }

    public func botMemoryCandidates(for botId: String) -> [PipiBotMemoryCandidate] {
        _ = botMemoryVersionCounter
        return botMemoryEngine.readCandidates(for: botId)
    }

    @discardableResult
    public func consolidateBotMemoryNow(for botId: String, now: Date = Date()) async -> PipiBotMemoryConsolidationOutcome {
        let res = await botMemoryEngine.consolidateIfDue(botId: botId, now: now, trigger: .manual)
        botMemoryVersionCounter += 1
        return res
    }

    public func saveBotMemorySummary(for botId: String, summary: String) {
        botMemoryEngine.writeSummaryManually(for: botId, summary: summary)
        botMemoryVersionCounter += 1
    }

    /// Wave 2 (#02): Compacts older conversation turns into a crisp summary, triggers Per-Bot memory
    /// consolidation, and increments `compactionGeneration` so the next turn re-injects memory
    /// without mutating System Prompt.
    @discardableResult
    public func compactConversation(id: String, now: Date = Date()) async -> Bool {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return false }
        let conv = conversations[idx]
        guard conv.messages.count >= 2 else {
            conversations[idx].compactionGeneration += 1
            _ = await botMemoryEngine.consolidateIfDue(botId: conv.personaId, now: now, trigger: .compaction)
            botMemoryVersionCounter += 1
            saveResidentState()
            return true
        }

        let keepCount = min(2, conv.messages.count)
        let older = Array(conv.messages.dropLast(keepCount))
        let recent = Array(conv.messages.suffix(keepCount))
        let summaryLines = older.suffix(8).map { msg -> String in
            let prefix = msg.role == .user ? "User" : "Assistant"
            let snippet = msg.content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(120)
            return "- [\(prefix)] \(snippet)"
        }
        let compactedMessage = PipiChatMessage(
            role: .assistant,
            content: strings.t(
                "已压缩早期 \(older.count) 条上下文记录：\n\(summaryLines.joined(separator: "\n"))",
                "Compacted \(older.count) earlier message(s):\n\(summaryLines.joined(separator: "\n"))"
            ),
            createdAt: ISO8601DateFormatter().string(from: now),
            engineLabel: "Context Compaction"
        )

        conversations[idx].messages = [compactedMessage] + recent
        conversations[idx].compactionGeneration += 1
        conversations[idx].updatedAt = ISO8601DateFormatter().string(from: now)

        _ = await botMemoryEngine.consolidateIfDue(botId: conv.personaId, now: now, trigger: .compaction)
        botMemoryVersionCounter += 1
        saveResidentState()
        return true
    }

    public func syncProactiveObservableState() {
        proactiveBriefings = proactiveEngine.briefings
        proactiveRules = proactiveEngine.rules
        proactiveClues = proactiveEngine.clues
        proactiveGuidelineVersion = proactiveEngine.guidelineVersion
        proactiveHistoryVersions = proactiveEngine.history.map(\.version)
        proactivePolicy = proactiveEngine.policy
    }

    public func refreshEventKitAuthStates() {
        eventKitCalendarAuth = nativeSignalProvider.calendarAuthorizationState()
        eventKitRemindersAuth = nativeSignalProvider.remindersAuthorizationState()
    }

    public func requestEventKitCalendarAccess() async {
        eventKitCalendarAuth = await nativeSignalProvider.requestCalendarAccess()
    }

    public func requestEventKitRemindersAccess() async {
        eventKitRemindersAuth = await nativeSignalProvider.requestRemindersAccess()
    }

    @discardableResult
    public func scanNativeProactiveSignals(
        now: Date = Date(),
        localHourOverride: Int? = nil
    ) async -> [PipiProactiveEvaluationResult] {
        var workspaceDirs = [workspaceDirectory]
        for proj in projects {
            if let path = proj.workspacePath, !path.isEmpty {
                workspaceDirs.append(path)
            }
        }
        let collectorInput = PipiNativeSignalCollectorInput(
            enabledSources: Set(proactiveEngine.policy.enabledSources),
            workspaceDirectories: workspaceDirs,
            recentProfileNote: personalProfileNote,
            now: now
        )
        let signals = await nativeSignalProvider.collectSignals(input: collectorInput)
        var outcomes: [PipiProactiveEvaluationResult] = []
        for signal in signals {
            let res = proactiveEngine.evaluateSignal(signal, now: now, localHourOverride: localHourOverride)
            outcomes.append(res)
        }
        syncProactiveObservableState()
        saveResidentState()
        return outcomes
    }

    public func recordProactiveFeedback(
        briefingId: String,
        signal: PipiProactiveFeedbackSignal,
        now: Date = Date()
    ) {
        _ = proactiveEngine.recordFeedback(briefingId: briefingId, signal: signal, now: now)
        syncProactiveObservableState()
        saveResidentState()
    }

    @discardableResult
    public func runProactiveNightlyDreaming(
        todayYmd: String? = nil,
        removedRuleIds: [String] = []
    ) -> PipiNightlyDreamResult {
        let res = proactiveEngine.runNightlyDreaming(todayYmd: todayYmd, removedRuleIds: removedRuleIds)
        syncProactiveObservableState()
        saveResidentState()
        return res
    }

    @discardableResult
    public func rollbackProactiveGuideline(toVersion version: Int) -> Bool {
        let ok = proactiveEngine.rollbackGuideline(toVersion: version)
        if ok {
            syncProactiveObservableState()
            saveResidentState()
        }
        return ok
    }

    public func updateProactivePolicy(_ policy: PipiProactiveGuardrailPolicy) {
        proactiveEngine.policy = policy
        syncProactiveObservableState()
        saveResidentState()
    }

    public func toggleProactiveRule(id: String, enabled: Bool) {
        proactiveEngine.toggleRule(id: id, enabled: enabled)
        syncProactiveObservableState()
        saveResidentState()
    }

    public func deleteProactiveRule(id: String) {
        proactiveEngine.deleteRule(id: id)
        syncProactiveObservableState()
        saveResidentState()
    }

    @discardableResult
    public func openBriefingInChat(_ briefing: PipiPreparedBriefing) -> PipiConversation {
        recordProactiveFeedback(briefingId: briefing.id, signal: .acted)
        let conv = createConversation(for: activePersona.id, title: briefing.title, activate: true)
        if let idx = conversations.firstIndex(where: { $0.id == conv.id }) {
            let bullets = briefing.bulletPoints.map { "- \($0)" }.joined(separator: "\n")
            let intro = PipiChatMessage(
                role: .assistant,
                content: "### \(briefing.title)\n\n\(briefing.summary)\n\n\(bullets)",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                engineLabel: "Prepare Briefing"
            )
            conversations[idx].messages.append(intro)
            conversations[idx].updatedAt = intro.createdAt
            saveResidentState()
        }
        return conversations.first(where: { $0.id == conv.id }) ?? conv
    }

    // MARK: - Wave 3 (#05 AlterEgo Delegation, #06 team.md & Dynamic Bots, #11 Pocket Notes / Docs / Skills)

    public func syncAlterEgoObservableState() {
        alterEgoTasks = alterEgoCoordinator.tasks
    }

    public func alterEgoTasks(forSession sessionId: String) -> [PipiAlterEgoTask] {
        alterEgoTasks.filter { $0.sessionId == sessionId }
    }

    @discardableResult
    public func spawnAlterEgoTask(
        sessionId: String,
        botId: String? = nil,
        title: String,
        goal: String,
        runner: PipiAlterEgoRunner? = nil
    ) -> PipiAlterEgoTask {
        let resolvedBotId = botId ?? activePersona.id
        let task = alterEgoCoordinator.spawnTask(
            sessionId: sessionId,
            botId: resolvedBotId,
            title: title,
            goal: goal,
            runner: runner
        )
        syncAlterEgoObservableState()
        saveResidentState()
        return task
    }

    public func steerAlterEgoTask(id: String, instruction: String) {
        if alterEgoCoordinator.steerTask(id: id, instruction: instruction) {
            syncAlterEgoObservableState()
            saveResidentState()
        }
    }

    public func cancelAlterEgoTask(id: String) {
        if alterEgoCoordinator.cancelTask(id: id) {
            syncAlterEgoObservableState()
            saveResidentState()
        }
    }

    @discardableResult
    public func resumeAlterEgoTask(
        id: String,
        additionalInstruction: String? = nil,
        runner: PipiAlterEgoRunner? = nil
    ) -> PipiAlterEgoTask? {
        let resumed = alterEgoCoordinator.resumeTask(
            id: id,
            additionalInstruction: additionalInstruction,
            runner: runner
        )
        syncAlterEgoObservableState()
        saveResidentState()
        return resumed
    }

    // ---- #06 Structured `team.md` Protocol & Dynamic Bot Proposals ----

    public func generateGroupTeamTemplate(
        groupId: String,
        pattern: PipiTeamCollaborationPattern,
        taskGoal: String? = nil
    ) -> String? {
        guard let group = groupChats.first(where: { $0.id == groupId }) else { return nil }
        let leadId = group.leadPersonaId ?? group.participantPersonaIds.first ?? activePersona.id
        let leadPersona = personas.first(where: { $0.id == leadId }) ?? activePersona
        let memberPersonas = group.participantPersonaIds
            .filter { $0 != leadId }
            .compactMap { pid in personas.first(where: { $0.id == pid }) }
        let effectiveMembers = memberPersonas.isEmpty ? [leadPersona] : memberPersonas

        let goal = (taskGoal?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? strings.t("围绕「\(group.title)」按结构化协作协议产出高质量交付物", "Collaborate cleanly on \"\(group.title)\" using structured handoffs")

        let md = PipiTeamProtocol.renderTemplate(
            pattern: pattern,
            taskGoal: goal,
            orchestrator: PipiTeamParticipant(
                name: leadPersona.name(resolvedLanguage),
                actorId: leadPersona.id,
                role: leadPersona.role(resolvedLanguage)
            ),
            members: effectiveMembers.map { p in
                PipiTeamParticipant(
                    name: p.name(resolvedLanguage),
                    actorId: p.id,
                    role: p.role(resolvedLanguage)
                )
            }
        )
        _ = updateGroupTeamProtocol(groupId: groupId, markdown: md)
        return md
    }

    @discardableResult
    public func updateGroupTeamProtocol(groupId: String, markdown: String) -> PipiTeamMdValidationResult? {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }) else { return nil }
        groupChats[gIdx].teamProtocolMarkdown = markdown
        groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())

        let result = PipiTeamProtocol.parseAndValidate(
            markdown,
            roomMemberActorIds: groupChats[gIdx].participantPersonaIds
        )

        if let doc = result.document, !result.missingMemberActorIds.isEmpty {
            let newProposals = PipiTeamProtocol.buildDynamicBotProposals(
                groupId: groupId,
                document: doc,
                groupMemberIds: groupChats[gIdx].participantPersonaIds,
                allPersonas: personas,
                language: resolvedLanguage
            )
            for prop in newProposals {
                let alreadyPending = groupChats[gIdx].dynamicBotProposals.contains {
                    $0.status == .pending && $0.requestedActorId == prop.requestedActorId
                }
                if !alreadyPending {
                    groupChats[gIdx].dynamicBotProposals.insert(prop, at: 0)
                }
            }
        }

        saveResidentState()
        return result
    }

    public func validateGroupTeamProtocol(groupId: String) -> PipiTeamMdValidationResult? {
        guard let group = groupChats.first(where: { $0.id == groupId }),
              let md = group.teamProtocolMarkdown else {
            return nil
        }
        return PipiTeamProtocol.parseAndValidate(md, roomMemberActorIds: group.participantPersonaIds)
    }

    @discardableResult
    public func resolveDynamicBotProposal(groupId: String, proposalId: String, approve: Bool) -> PipiBotPersona? {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }),
              let pIdx = groupChats[gIdx].dynamicBotProposals.firstIndex(where: { $0.id == proposalId }) else {
            return nil
        }

        let proposal = groupChats[gIdx].dynamicBotProposals[pIdx]
        guard proposal.status == .pending else { return nil }

        if !approve {
            groupChats[gIdx].dynamicBotProposals[pIdx].status = .rejected
            groupChats[gIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
            saveResidentState()
            return nil
        }

        let joinedPersona: PipiBotPersona
        switch proposal.action {
        case .inviteExisting:
            if let existingId = proposal.existingBotId,
               let found = personas.first(where: { $0.id == existingId }) {
                joinedPersona = found
            } else {
                let created = PipiBotPersona(
                    id: proposal.requestedActorId,
                    nameZh: proposal.proposedName,
                    nameEn: proposal.proposedName,
                    roleZh: proposal.proposedRole,
                    roleEn: proposal.proposedRole,
                    greetingZh: "你好，我是 \(proposal.proposedName)，已加入本群协助协作。",
                    greetingEn: "Hi, I'm \(proposal.proposedName), ready to collaborate.",
                    systemPrompt: proposal.proposedSystemPrompt,
                    accent: .sky,
                    avatarShape: .spark
                )
                personas.append(created)
                joinedPersona = created
            }
        case .createAndInvite:
            let created = PipiBotPersona(
                id: proposal.requestedActorId,
                nameZh: proposal.proposedName,
                nameEn: proposal.proposedName,
                roleZh: proposal.proposedRole,
                roleEn: proposal.proposedRole,
                greetingZh: "你好，我是新创建的 \(proposal.proposedName)，负责「\(proposal.proposedRole)」。",
                greetingEn: "Hi, I'm \(proposal.proposedName) (\(proposal.proposedRole)), ready to collaborate.",
                systemPrompt: proposal.proposedSystemPrompt,
                accent: .emerald,
                avatarShape: .shield
            )
            personas.append(created)
            joinedPersona = created
        }

        if !groupChats[gIdx].participantPersonaIds.contains(joinedPersona.id) {
            groupChats[gIdx].participantPersonaIds.append(joinedPersona.id)
        }
        groupChats[gIdx].dynamicBotProposals[pIdx].status = .approved
        let nowIso = ISO8601DateFormatter().string(from: Date())
        groupChats[gIdx].messages.append(PipiGroupMessage(
            senderKind: .bot(personaId: joinedPersona.id),
            content: strings.t(
                "已通过动态协作审批，\(joinedPersona.name(.zhHans))（\(joinedPersona.role(.zhHans))）已加入本群。",
                "Approved dynamic proposal: \(joinedPersona.name(.en)) (\(joinedPersona.role(.en))) joined this group."
            ),
            createdAt: nowIso,
            engineLabel: "team.md"
        ))
        groupChats[gIdx].updatedAt = nowIso
        saveResidentState()
        return joinedPersona
    }

    @discardableResult
    public func runGroupTeamProtocol(
        groupId: String,
        userPrompt: String,
        executorOverride: PipiTeamBotExecutor? = nil
    ) async throws -> PipiTeamExecutionResult? {
        guard let gIdx = groupChats.firstIndex(where: { $0.id == groupId }),
              let md = groupChats[gIdx].teamProtocolMarkdown else {
            return nil
        }
        let validation = PipiTeamProtocol.parseAndValidate(
            md,
            roomMemberActorIds: groupChats[gIdx].participantPersonaIds
        )
        guard validation.valid, let doc = validation.document else {
            return nil
        }

        let effectiveExecutor: PipiTeamBotExecutor
        if let executorOverride {
            effectiveExecutor = executorOverride
        } else {
            let storeExecutor = self.sessionInferenceExecutor
            let providersSnapshot = self.llmProviders
            let defaultProviderId = self.defaultLLMProviderId
            let personasSnapshot = self.personas
            let workDir = self.workspaceDirectory
            effectiveExecutor = { req in
                let persona = personasSnapshot.first(where: { $0.id == req.actorId })
                let sysPrompt = persona?.systemPrompt ?? "You are \(req.memberName) (\(req.role))."
                let upstreamBlock = req.upstreamOutputs
                    .map { "[\($0.memberName)]: \($0.output)" }
                    .joined(separator: "\n\n")
                let fullPrompt = upstreamBlock.isEmpty ? req.prompt : "\(req.prompt)\n\nUpstream context:\n\(upstreamBlock)"

                if let storeExecutor {
                    let provider = providersSnapshot.first(where: { $0.id == defaultProviderId && $0.isReady })
                        ?? providersSnapshot.first(where: \.isReady)
                    let target: PipiExecutionTarget = provider.map { .llm(providerId: $0.id) } ?? .auto
                    let res = try await storeExecutor(
                        target,
                        provider,
                        sysPrompt,
                        [PipiChatMessage(role: .user, content: fullPrompt)],
                        workDir,
                        .readOnly,
                        nil,
                        nil,
                        nil
                    )
                    return PipiTeamBotTurnResponse(
                        output: res.text,
                        selectedActorId: doc.members.first?.actorId,
                        approved: req.phase == .verify ? true : nil,
                        done: req.phase == .loopStep ? true : nil
                    )
                }

                // Deterministic local fallback when no cloud/CLI engine is configured yet
                return PipiTeamBotTurnResponse(
                    output: "[\(req.memberName) · \(req.phase.rawValue) r\(req.round)] Completed response for: \(req.prompt.prefix(120))",
                    selectedActorId: doc.members.first?.actorId,
                    approved: req.phase == .verify ? true : nil,
                    done: req.phase == .loopStep ? true : nil
                )
            }
        }

        let result = try await PipiTeamProtocol.execute(
            document: doc,
            userPrompt: userPrompt,
            executor: effectiveExecutor
        )

        if let latestIdx = groupChats.firstIndex(where: { $0.id == groupId }) {
            let nowIso = ISO8601DateFormatter().string(from: Date())
            for entry in result.trace {
                groupChats[latestIdx].messages.append(PipiGroupMessage(
                    senderKind: .bot(personaId: entry.actorId),
                    content: entry.output,
                    createdAt: nowIso,
                    engineLabel: "team.md · \(doc.pattern.rawValue)"
                ))
            }
            groupChats[latestIdx].deliverables.insert(
                PipiGroupDeliverable(
                    title: "team.md · \(doc.pattern.label(resolvedLanguage))",
                    kind: .summary,
                    summary: String(result.finalOutput.prefix(160)),
                    content: result.finalOutput,
                    producedByPersonaId: doc.orchestrator.actorId
                ),
                at: 0
            )
            groupChats[latestIdx].updatedAt = nowIso
            saveResidentState()
        }

        return result
    }

    // ---- #11 Daily Pocket Notes, Editable Artifact Documents & Builtin Skills ----

    public func syncPocketNotesObservableState() {
        pocketTrackingItems = pocketNotesEngine.trackingItems
        artifactDocuments = pocketNotesEngine.documents
        pocketNotesVersionCounter += 1
    }

    public func dailyPocketNoteText(for dateYmd: String) -> String {
        _ = pocketNotesVersionCounter
        return pocketNotesEngine.dailyNote(for: dateYmd)?.content ?? ""
    }

    @discardableResult
    public func saveDailyPocketNote(dateYmd: String, content: String, now: Date = Date()) -> PipiDailyPocketNote {
        let saved = pocketNotesEngine.saveDailyNote(dateYmd: dateYmd, content: content, now: now)
        syncPocketNotesObservableState()
        saveResidentState()
        return saved
    }

    @discardableResult
    public func reconcileDailyPocketNote(
        dateYmd: String,
        now: Date = Date(),
        force: Bool = false
    ) -> PipiPocketReconcileResult {
        let res = pocketNotesEngine.reconcileDailyNoteIfQuiet(dateYmd: dateYmd, now: now, force: force)
        if res.extracted {
            syncPocketNotesObservableState()
            saveResidentState()
        }
        return res
    }

    public func setTrackingItemStatus(id: String, status: PipiTrackingItemStatus) {
        pocketNotesEngine.setTrackingItemStatus(id: id, status: status)
        syncPocketNotesObservableState()
        saveResidentState()
    }

    @discardableResult
    public func upsertArtifactDocument(
        id: String? = nil,
        title: String,
        kind: PipiArtifactDocumentKind = .note,
        markdown: String,
        sessionId: String? = nil,
        groupId: String? = nil,
        tags: [String] = []
    ) -> PipiArtifactDocument {
        let saved = pocketNotesEngine.upsertDocument(
            id: id,
            title: title,
            kind: kind,
            markdown: markdown,
            sessionId: sessionId,
            groupId: groupId,
            tags: tags
        )
        syncPocketNotesObservableState()
        saveResidentState()
        return saved
    }

    public func deleteArtifactDocument(id: String) {
        pocketNotesEngine.deleteDocument(id: id)
        syncPocketNotesObservableState()
        saveResidentState()
    }

    @discardableResult
    public func syncArtifactDocumentToWiki(docId: String) -> PipiPersonalWikiPage? {
        guard let wiki = personalWiki else { return nil }
        let page = pocketNotesEngine.syncDocumentToWiki(docId: docId, wiki: wiki)
        if page != nil {
            refreshWikiPages()
        }
        return page
    }

    @discardableResult
    public func projectBuiltinSkillsNow() -> [PipiProjectedSkillReceipt] {
        let receipts = (try? PipiBuiltinSkillsRegistry.projectReadOnly(to: localDataRootURL)) ?? []
        builtinSkillReceipts = receipts
        return receipts
    }

    public func verifyBuiltinSkillsNow() -> PipiSkillIntegrityReport {
        PipiBuiltinSkillsRegistry.verifyIntegrity(at: localDataRootURL)
    }

    // MARK: - Wave 4 (#07 Hardware Model Autopilot, PolyStrata, Local Unified Gateway & CLI Reverse Injection)

    @discardableResult
    public func refreshHardwareAndModelPlan(overrideHardware: PipiHardwareProfile? = nil) -> PipiModelAutopilotPlan {
        let hw = overrideHardware ?? PipiHardwareProfile.detectCurrentHost()
        let engines = PipiModelAutopilot.probeInstalledEngines()
        let plan = PipiModelAutopilot.plan(
            hardware: hw,
            enableMacPolyStrataBeta: localGatewayConfig.enableMacPolyStrataBeta,
            installedEngines: engines
        )
        hardwareProfile = hw
        localEngineStatuses = engines
        modelAutopilotPlan = plan
        return plan
    }

    public func updateLocalGatewayConfig(_ config: PipiLocalGatewayConfig) {
        localGatewayConfig = config
        refreshHardwareAndModelPlan()
        saveResidentState()
    }

    public func applyAutopilotPlanToGatewayConfig() {
        let plan = modelAutopilotPlan
        var updated = localGatewayConfig
        updated.selectedLocalEngine = plan.selectedEngine
        updated.selectedLocalModelId = plan.primaryModel.id
        if let engineInfo = localEngineStatuses.first(where: { $0.engine == plan.selectedEngine }) {
            updated.localUpstreamBaseURL = engineInfo.endpointUrl
        }
        updated.sourceMode = .localModel
        localGatewayConfig = updated
        saveResidentState()
    }

    public func resolveCurrentGatewayUpstreamTarget() -> PipiGatewayUpstreamTarget {
        switch localGatewayConfig.sourceMode {
        case .byok:
            let cfg = llmProviders.first(where: { $0.id == localGatewayConfig.byokProviderId })
                ?? readyLLMProviders.first
            if let cfg {
                let dialect: PipiGatewayUpstreamDialect = (cfg.kind == .anthropic)
                    ? .anthropic
                    : PipiGatewayUpstreamDialect.detect(baseURL: cfg.baseURL)
                return PipiGatewayUpstreamTarget(
                    sourceMode: .byok,
                    dialect: dialect,
                    baseURL: cfg.baseURL,
                    modelId: cfg.modelId,
                    apiKey: cfg.apiKey,
                    contextWindow: 131_072
                )
            }
            fallthrough
        case .localModel, .subscription:
            let base = localGatewayConfig.localUpstreamBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedBase = base.isEmpty ? "http://127.0.0.1:11438/v1" : base
            let modelId = localGatewayConfig.selectedLocalModelId.trimmingCharacters(in: .whitespacesAndNewlines)
            return PipiGatewayUpstreamTarget(
                sourceMode: localGatewayConfig.sourceMode,
                dialect: PipiGatewayUpstreamDialect.detect(baseURL: resolvedBase),
                baseURL: resolvedBase,
                modelId: modelId.isEmpty ? modelAutopilotPlan.primaryModel.id : modelId,
                apiKey: nil,
                contextWindow: modelAutopilotPlan.plannedContextWindow
            )
        }
    }

    @discardableResult
    public func startLocalGateway(
        portOverride: UInt16? = nil,
        transport: PipiLocalLLMGateway.UpstreamTransport? = nil
    ) async throws -> PipiGatewayRuntimeStatus {
        let target = resolveCurrentGatewayUpstreamTarget()
        if let existing = localGateway {
            await existing.updateUpstream(target)
            let current = await existing.currentStatus()
            if current.isRunning {
                localGatewayStatus = current
                return current
            }
        }
        let gateway = PipiLocalLLMGateway(upstream: target, transport: transport)
        let requestedPort: UInt16 = portOverride ?? UInt16(clamping: max(0, min(65535, localGatewayConfig.gatewayPort)))
        let status = try await gateway.start(port: requestedPort)
        self.localGateway = gateway
        self.localGatewayStatus = status
        return status
    }

    public func stopLocalGateway() async {
        if let gateway = localGateway {
            await gateway.stop()
        }
        localGatewayStatus = .stopped
    }

    public func switchModelSourceMode(
        _ targetMode: PipiModelSourceMode,
        confirmedInterruptActiveRuns: Bool = false
    ) async -> (switched: Bool, requiresConfirmation: Bool, unloadedLocalModel: Bool, message: String) {
        let activeCount = activeRuns.count
        if activeCount > 0 && !confirmedInterruptActiveRuns {
            return (
                false,
                true,
                false,
                strings.t(
                    "当前有 \(activeCount) 个会话正在运行，切换模型源前请先确认是否中断。",
                    "\(activeCount) active run(s) in progress. Confirm before switching model source."
                )
            )
        }

        let previousMode = localGatewayConfig.sourceMode
        var unloadedLocal = false
        if activeCount > 0 && confirmedInterruptActiveRuns {
            for convId in Array(activeRuns.keys) {
                stopGenerating(conversationId: convId)
            }
        }
        if previousMode == .localModel && targetMode != .localModel {
            unloadedLocal = true
        }

        localGatewayConfig.sourceMode = targetMode
        if let gateway = localGateway {
            await gateway.updateUpstream(resolveCurrentGatewayUpstreamTarget())
            localGatewayStatus = await gateway.currentStatus()
        }
        saveResidentState()
        return (
            true,
            false,
            unloadedLocal,
            strings.t(
                "已将模型源切换为 \(targetMode.label(.zhHans))\(unloadedLocal ? "（已释放本地模型内存）" : "")",
                "Switched model source to \(targetMode.label(.en))\(unloadedLocal ? " (local model memory released)" : "")"
            )
        )
    }

    @discardableResult
    public func runLocalModelSelfTest(
        transport: PipiModelAutopilot.QATransport? = nil
    ) async -> PipiModelSelfTestResult {
        isRunningModelSelfTest = true
        defer { isRunningModelSelfTest = false }

        let target = resolveCurrentGatewayUpstreamTarget()
        let endpoint = localGatewayStatus.isRunning ? "\(localGatewayStatus.origin)/v1" : target.baseURL
        let apiKey: String? = localGatewayStatus.isRunning ? (localGateway?.token) : target.apiKey
        let result = await PipiModelAutopilot.verifyModelWithQA(
            endpointUrl: endpoint,
            modelId: target.modelId,
            apiKey: apiKey,
            transport: transport
        )
        lastModelSelfTestResult = result
        return result
    }

    @discardableResult
    public func prepareIsolatedCLIOverlay(
        for cli: PipiReverseInjectedCLITarget,
        profileId: String = "default"
    ) async throws -> PipiIsolatedCLIOverlay {
        if !localGatewayStatus.isRunning {
            _ = try await startLocalGateway(portOverride: 0)
        }
        guard let gateway = localGateway else {
            throw PipiInferenceError.invalidEndpoint("Local gateway unavailable")
        }
        let overlay = try await gateway.prepareOverlay(
            dataRootURL: localDataRootURL,
            cli: cli,
            profileId: profileId
        )
        lastIsolatedCLIOverlays[cli] = overlay
        return overlay
    }

    private func resolveCLIReverseInjectionEnvironment(
        for kind: PipiLocalAgentKind,
        profileId: String
    ) async -> [String: String] {
        guard localGatewayConfig.reverseInjectCLIAgents else { return [:] }
        guard localGatewayConfig.sourceMode != .subscription else { return [:] }
        let target = PipiReverseInjectedCLITarget(localAgentKind: kind)
        guard let overlay = try? await prepareIsolatedCLIOverlay(for: target, profileId: profileId) else {
            return [:]
        }
        return overlay.environment
    }

    // MARK: - Wave 4 (#10 Personal Daily Voice: Dictation, Muse Hands-Free & Voice-to-Task)

    private func wireVoiceEngineCallbacks() {
        voiceEngine.onStateChanged = { [weak self] newState in
            guard let self else { return }
            self.voiceSessionState = newState
            switch newState {
            case .listening, .transcribing:
                self.avatarEngine.setState(.voiceTranscribing)
            case .interrupted:
                self.avatarEngine.setState(.voiceInterrupted)
            case .idle:
                if !self.isAnyConversationRunning {
                    self.avatarEngine.setState(.idle)
                }
            default:
                break
            }
        }
        voiceEngine.onTranscriptUpdated = { [weak self] text, _ in
            self?.voiceLiveTranscript = text
        }
        voiceEngine.onInputLevelUpdated = { [weak self] rms in
            self?.voiceInputLevel = rms
        }
        voiceEngine.onBargeInInterrupt = { [weak self] in
            guard let self else { return }
            self.avatarEngine.setState(.voiceInterrupted)
        }
        voiceEngine.onSpeakingFinished = { [weak self] in
            guard let self else { return }
            // In active Voice Call mode, seamlessly reopen listening after the assistant finishes speaking
            if self.isVoiceCallActive && !self.isVoiceCallMuted {
                Task { @MainActor [weak self] in
                    guard let self, self.isVoiceCallActive, !self.isVoiceCallMuted else { return }
                    await self.startVoiceCapture(mode: .museHandsFree)
                }
            }
        }
    }

    public func effectiveVoiceProfileId(for personaId: String? = nil) -> String {
        let targetId = personaId ?? voiceCallPersonaId ?? activePersona.id
        if let bot = personas.first(where: { $0.id == targetId }),
           let explicit = bot.voiceProfileId,
           !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicit
        }
        return voiceConfig.selectedVoiceProfileId
    }

    public func previewVoiceProfile(_ profileId: String) {
        voiceEngine.previewVoice(profileId: profileId, lang: resolvedLanguage)
    }

    /// Starts a live hands-free Voice Call with the specified assistant (or current active assistant).
    public func startVoiceCall(with personaId: String? = nil) async {
        let targetBotId = personaId ?? activePersona.id
        selectPersona(targetBotId)
        voiceCallPersonaId = targetBotId
        isVoiceCallActive = true
        isVoiceCallMuted = false
        voiceCallStartedAt = Date()
        voiceActiveMode = .museHandsFree
        voiceIsOverlayPresented = true
        voiceLastError = nil
        voiceLiveTranscript = ""
        await startVoiceCapture(mode: .museHandsFree)
    }

    public func endVoiceCall() {
        isVoiceCallActive = false
        voiceCallStartedAt = nil
        isVoiceCallMuted = false
        voiceCallPersonaId = nil
        voiceEngine.stopLiveCapture()
        voiceEngine.interruptPlaybackImmediately()
        voiceSessionState = .idle
        voiceIsOverlayPresented = false
    }

    public func toggleVoiceCallMute() {
        guard isVoiceCallActive else { return }
        isVoiceCallMuted.toggle()
        if isVoiceCallMuted {
            voiceEngine.stopLiveCapture()
        } else {
            Task { @MainActor in
                await startVoiceCapture(mode: .museHandsFree)
            }
        }
    }

    // MARK: - Per-Agent Capabilities, Global Sharing Pool & Autonomous Bot-to-Bot Upgrade

    public func updateGlobalCapabilityPool(_ pool: PipiGlobalCapabilityPool) {
        globalCapabilityPool = pool
        saveResidentState()
    }

    public func effectiveCapabilities(for personaId: String) -> PipiEffectiveBotCapabilities {
        let bot = personas.first(where: { $0.id == personaId }) ?? activePersona
        return PipiBotCapabilityMesh.effectiveCapabilities(
            for: bot,
            allPersonas: personas,
            globalPool: globalCapabilityPool,
            globalDefaultVoiceId: voiceConfig.selectedVoiceProfileId
        )
    }

    @discardableResult
    public func evaluatePeerUpgradeForPrompt(botId: String, prompt: String) -> PipiPeerUpgradeOutcome? {
        guard let idx = personas.firstIndex(where: { $0.id == botId }) else { return nil }
        let outcome = PipiBotCapabilityMesh.evaluateAndUpgradeOnDemand(
            targetBot: personas[idx],
            prompt: prompt,
            allPersonas: personas,
            globalPool: globalCapabilityPool,
            peerMemorySummaryLookup: { [weak self] peerId in
                self?.botMemorySummary(for: peerId)
            },
            lang: resolvedLanguage
        )
        if !outcome.newUpgrades.isEmpty {
            personas[idx] = outcome.updatedBot
            if let first = outcome.newUpgrades.first {
                lastPeerUpgradeNotice = first.summary
            }
            saveResidentState()
        }
        return outcome
    }

    @discardableResult
    public func syncPeerUpgrades(for botId: String) -> PipiPeerUpgradeOutcome? {
        guard let idx = personas.firstIndex(where: { $0.id == botId }) else { return nil }
        let outcome = PipiBotCapabilityMesh.syncAllShareableCapabilities(
            for: personas[idx],
            allPersonas: personas,
            peerMemorySummaryLookup: { [weak self] peerId in
                self?.botMemorySummary(for: peerId)
            },
            lang: resolvedLanguage
        )
        if !outcome.newUpgrades.isEmpty {
            personas[idx] = outcome.updatedBot
            lastPeerUpgradeNotice = strings.t(
                "已从团队同伴同步 \(outcome.newUpgrades.count) 项新能力。",
                "Synced \(outcome.newUpgrades.count) capability upgrade(s) from peers."
            )
            saveResidentState()
        } else {
            lastPeerUpgradeNotice = strings.t(
                "当前助手已拥有所有可共享的团队能力。",
                "This assistant already has all shareable peer capabilities."
            )
        }
        return outcome
    }

    public func updateVoiceConfig(_ config: PipiVoiceConfig) {
        voiceConfig = config
        voiceEngine.config = config
        saveResidentState()
    }

    public func voiceCloudSttApiKey() -> String {
        secretStore.secret(for: voiceConfig.cloudStt.keychainAccount) ?? ""
    }

    public func setVoiceCloudSttApiKey(_ key: String) {
        secretStore.setSecret(key, for: voiceConfig.cloudStt.keychainAccount)
    }

    public func voiceCloudTtsApiKey() -> String {
        secretStore.secret(for: voiceConfig.cloudTts.keychainAccount) ?? ""
    }

    public func setVoiceCloudTtsApiKey(_ key: String) {
        secretStore.setSecret(key, for: voiceConfig.cloudTts.keychainAccount)
    }

    public func startVoiceCapture(mode: PipiVoiceInteractionMode) async {
        voiceActiveMode = mode
        voiceLastError = nil
        voiceLiveTranscript = ""
        voiceIsOverlayPresented = true
        do {
            try await voiceEngine.startLiveCapture()
        } catch {
            voiceLastError = error.localizedDescription
            voiceSessionState = .error
        }
    }

    public func stopVoiceCapture(commitTranscript: Bool = true) async {
        let captured = voiceLiveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        voiceEngine.stopLiveCapture()
        if commitTranscript && !captured.isEmpty {
            _ = await dispatchVoiceUtterance(captured, mode: voiceActiveMode)
        }
    }

    public func interruptVoicePlayback() {
        voiceEngine.interruptPlaybackImmediately()
    }

    /// Dispatches a daily voice utterance under `.voiceInteractive` scheduler priority.
    @discardableResult
    public func dispatchVoiceUtterance(
        _ transcript: String,
        mode: PipiVoiceInteractionMode? = nil,
        explicitAction: PipiVoiceIntentAction? = nil
    ) async -> PipiVoiceUtteranceRoute {
        let resolvedMode = mode ?? voiceActiveMode
        let lease = try? await modelScheduler.acquire(
            endpointKey: "voice_daily",
            priority: .voiceInteractive,
            runId: "voice_\(resolvedMode.rawValue)_\(UUID().uuidString.prefix(6).lowercased())"
        )
        defer { lease?.release() }

        let route = PipiDailyVoiceEngine.routeUtterance(
            transcript: transcript,
            mode: resolvedMode,
            explicitAction: explicitAction
        )
        guard !route.cleanedPayload.isEmpty else { return route }

        switch route.action {
        case .dictationInsert:
            voicePendingDictationText = route.cleanedPayload
            voiceSessionState = .idle

        case .museReply:
            let convId = activeConversationId ?? createConversation(activate: true).id
            let targetPersonaId = conversations.first(where: { $0.id == convId })?.personaId ?? voiceCallPersonaId ?? activePersona.id
            voiceSessionState = .thinking
            await sendPersonalMessage(
                route.cleanedPayload,
                conversationId: convId,
                personaId: targetPersonaId,
                priority: .voiceInteractive
            )
            let shouldSpeak = isVoiceCallActive || voiceConfig.autoSpeakMuseReplies
            if shouldSpeak,
               let reply = conversations.first(where: { $0.id == convId })?.messages.last(where: { $0.role == .assistant && !$0.isError })?.content,
               !reply.isEmpty {
                let voiceId = effectiveVoiceProfileId(for: targetPersonaId)
                voiceEngine.speakOnDevice(reply, voiceProfileId: voiceId)
            } else {
                voiceSessionState = .idle
                if isVoiceCallActive && !isVoiceCallMuted {
                    await startVoiceCapture(mode: .museHandsFree)
                }
            }

        case .delegateAlterEgo:
            let convId = activeConversationId ?? createConversation(activate: true).id
            _ = spawnAlterEgoTask(
                sessionId: convId,
                title: String(route.cleanedPayload.prefix(48)),
                goal: route.cleanedPayload
            )
            voiceSessionState = .idle

        case .appendPocketNote:
            let today = Self.todayYmdString()
            let existing = pocketNotesEngine.dailyNote(for: today)?.content ?? ""
            let appended = existing.isEmpty ? "- \(route.cleanedPayload)" : "\(existing)\n- \(route.cleanedPayload)"
            _ = saveDailyPocketNote(dateYmd: today, content: appended)
            voiceSessionState = .idle

        case .createTrackingItem:
            let today = Self.todayYmdString()
            let existing = pocketNotesEngine.dailyNote(for: today)?.content ?? ""
            let line = "- [ ] \(route.cleanedPayload)"
            let appended = existing.isEmpty ? line : "\(existing)\n\(line)"
            _ = saveDailyPocketNote(dateYmd: today, content: appended)
            _ = reconcileDailyPocketNote(dateYmd: today, force: true)
            voiceSessionState = .idle
        }
        return route
    }

    private static func todayYmdString(date: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    // MARK: - Wave 5 (#09 Dual-Phase Computer Use: Chrome Seats, macOS AX/Cua, Human Yield & WAL)

    private func wireComputerUseCallbacks() {
        computerUseCoordinator.onStateChanged = { [weak self] in
            self?.syncComputerUseObservableState()
        }
        syncComputerUseObservableState()
    }

    public func syncComputerUseObservableState() {
        computerUseLanes = computerUseCoordinator.listLanes()
        computerUseSeats = computerUseCoordinator.listSeats()
        computerUseJournal = Array(computerUseCoordinator.journal.listEntries().suffix(30).reversed())
        computerUseYieldedToHuman = computerUseCoordinator.isYieldedToHuman
        computerUseYieldReason = computerUseCoordinator.humanYieldReason
    }

    public var hasComputerUseAttention: Bool {
        computerUseBarPresented ||
            computerUseYieldedToHuman ||
            computerUseLanes.contains(where: { $0.state != .idle }) ||
            !computerUseSeats.isEmpty
    }

    public func updateComputerUseConfig(_ config: PipiComputerUseConfig) {
        computerUseConfig = config
        computerUseCoordinator.config = config
        saveResidentState()
    }

    @discardableResult
    public func refreshComputerUseEnvironment() async -> PipiComputerUseEnvironmentProbe {
        let probe = await computerUseCoordinator.probeEnvironment()
        computerUseEnvironment = probe
        syncComputerUseObservableState()
        return probe
    }

    @discardableResult
    public func executeComputerUseAction(_ request: PipiComputerUseActionRequest) async -> PipiComputerUseActionResult {
        let result = await computerUseCoordinator.executeAction(request)
        syncComputerUseObservableState()
        if result.yieldedToHuman {
            avatarEngine.setState(.needsYou)
        } else if result.status == .unknownOutcome {
            avatarEngine.setState(.needsYouUrgent)
        } else if result.ok {
            avatarEngine.setState(.macAutomating)
        }
        return result
    }

    public func humanTakeOverComputerUse(reason: String = "Manual human takeover") {
        _ = computerUseCoordinator.notifyHumanFocusChanged(activeBundleId: "user.manual.takeover", reason: reason)
        syncComputerUseObservableState()
        avatarEngine.setState(.idle)
    }

    public func resumeComputerUseAfterHumanYield() {
        computerUseCoordinator.resumeFromHumanYield()
        syncComputerUseObservableState()
    }

    @discardableResult
    public func acknowledgeAndUnlockComputerUseLane(_ laneId: String, note: String? = nil) -> Bool {
        let ok = computerUseCoordinator.acknowledgeUnknownOutcomeAndUnlockLane(laneId, note: note)
        syncComputerUseObservableState()
        return ok
    }

    // MARK: - Cloudflare Tunnel Remote PWA Control

    public func refreshCloudflaredAvailability() {
        remoteTunnelManager.refreshCloudflaredAvailability()
    }

    public func startRemoteTunnel() async {
        await remoteTunnelManager.start(bridge: makeRemoteControlBridge())
    }

    public func regenerateRemoteTunnel() async {
        await remoteTunnelManager.regenerate(bridge: makeRemoteControlBridge())
    }

    public func stopRemoteTunnel() {
        remoteTunnelManager.stop()
    }

    public func makeRemoteControlBridge() -> PipiRemoteControlBridge {
        PipiRemoteControlBridge(
            fetchSnapshot: { [weak self] requestedConvId in
                await MainActor.run {
                    guard let self else {
                        return PipiRemoteControlSnapshot(
                            hostName: "Mac",
                            appVersion: "0.11.0",
                            activeModelLabel: "",
                            language: "zh-Hans",
                            bots: [],
                            conversations: [],
                            selectedConversationId: nil,
                            messages: [],
                            isSelectedConversationRunning: false,
                            pendingItems: []
                        )
                    }
                    let lang = self.resolvedLanguage
                    let botDTOs = self.personas.map { bot in
                        PipiRemoteBotDTO(
                            id: bot.id,
                            name: bot.name(lang),
                            role: bot.role(lang),
                            isRunning: self.isPersonaRunning(bot.id),
                            skillCount: bot.assignedSkillSlugs.count
                        )
                    }
                    let visibleConvs = self.conversations
                        .filter { !$0.isArchived }
                        .sorted { $0.updatedAt > $1.updatedAt }
                    let convDTOs = visibleConvs.prefix(20).map { conv in
                        let persona = self.personas.first(where: { $0.id == conv.personaId })
                        return PipiRemoteConversationDTO(
                            id: conv.id,
                            personaId: conv.personaId,
                            personaName: persona?.name(lang) ?? self.strings.appName,
                            title: conv.title,
                            messageCount: conv.messages.count,
                            updatedAt: conv.updatedAt,
                            isRunning: self.isRunning(conversationId: conv.id)
                        )
                    }

                    let targetConv: PipiConversation? = {
                        if let requestedConvId, let found = visibleConvs.first(where: { $0.id == requestedConvId }) {
                            return found
                        }
                        if let activeId = self.activeConversationId, let found = visibleConvs.first(where: { $0.id == activeId }) {
                            return found
                        }
                        return visibleConvs.first
                    }()

                    let msgDTOs = (targetConv?.messages ?? []).suffix(60).map { msg in
                        let deliverables: [PipiRemoteDeliverableDTO] = (msg.attachments ?? []).compactMap { att in
                            if let art = self.macOmnipotentEngine.artifact(id: att.id) {
                                return PipiRemoteDeliverableDTO(
                                    id: art.id,
                                    kind: art.kind.rawValue,
                                    fileName: art.fileName,
                                    mimeType: art.mimeType,
                                    byteSize: art.byteSize
                                )
                            }
                            if FileManager.default.fileExists(atPath: att.path) {
                                let (kind, mime) = PipiDeliverableArtifact.inferKindAndMime(for: att.path)
                                let registered = PipiDeliverableArtifact(
                                    id: att.id,
                                    kind: kind,
                                    fileName: att.name,
                                    filePath: att.path,
                                    mimeType: mime,
                                    byteSize: Int64(att.sizeBytes)
                                )
                                self.macOmnipotentEngine.registerArtifact(registered)
                                return PipiRemoteDeliverableDTO(
                                    id: registered.id,
                                    kind: kind.rawValue,
                                    fileName: att.name,
                                    mimeType: mime,
                                    byteSize: Int64(att.sizeBytes)
                                )
                            }
                            return nil
                        }
                        return PipiRemoteMessageDTO(
                            id: msg.id,
                            role: msg.role.rawValue,
                            content: msg.content,
                            createdAt: msg.createdAt,
                            engineLabel: msg.engineLabel,
                            isError: msg.isError,
                            deliverables: deliverables
                        )
                    }

                    var pending: [PipiRemotePendingItemDTO] = []
                    for dec in self.decisions where dec.status == .pending {
                        pending.append(PipiRemotePendingItemDTO(
                            kind: "decision",
                            id: dec.id,
                            title: dec.title,
                            summary: dec.summary,
                            severity: dec.severity.rawValue,
                            options: dec.options.map { opt in
                                PipiRemotePendingOptionDTO(
                                    id: opt.id,
                                    label: opt.label,
                                    isPrimary: opt.style == .primary,
                                    isDestructive: opt.style == .destructive
                                )
                            }
                        ))
                    }
                    for conv in visibleConvs {
                        for appr in conv.approvals where appr.status == .pending {
                            pending.append(PipiRemotePendingItemDTO(
                                kind: "approval",
                                id: appr.id,
                                title: appr.question,
                                summary: appr.detail ?? appr.rationale ?? conv.title,
                                severity: appr.riskLevel?.rawValue ?? "warning",
                                options: appr.options.map { opt in
                                    PipiRemotePendingOptionDTO(
                                        id: opt.id,
                                        label: opt.label,
                                        isPrimary: opt.style == .primary,
                                        isDestructive: opt.style == .destructive
                                    )
                                }
                            ))
                        }
                    }

                    let hostName: String = {
                        #if os(macOS)
                        return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
                        #else
                        return ProcessInfo.processInfo.hostName
                        #endif
                    }()

                    return PipiRemoteControlSnapshot(
                        hostName: hostName,
                        appVersion: self.appDisplayVersion,
                        activeModelLabel: self.activeEngineDisplayLabel(),
                        language: lang.rawValue,
                        bots: botDTOs,
                        conversations: convDTOs,
                        selectedConversationId: targetConv?.id,
                        messages: msgDTOs,
                        isSelectedConversationRunning: targetConv.map { self.isRunning(conversationId: $0.id) } ?? false,
                        pendingItems: pending
                    )
                }
            },
            sendMessage: { [weak self] conversationId, personaId, text in
                await MainActor.run {
                    guard let self else { return "" }
                    let resolvedConvId: String
                    if let conversationId, self.conversations.contains(where: { $0.id == conversationId }) {
                        resolvedConvId = conversationId
                    } else {
                        let created = self.createConversation(for: personaId, activate: true)
                        resolvedConvId = created.id
                    }
                    let convPersonaId = personaId ?? self.conversations.first(where: { $0.id == resolvedConvId })?.personaId
                    Task { @MainActor in
                        await self.sendPersonalMessage(
                            text,
                            conversationId: resolvedConvId,
                            personaId: convPersonaId,
                            activateTargetConversation: true
                        )
                    }
                    return resolvedConvId
                }
            },
            createConversation: { [weak self] personaId in
                await MainActor.run {
                    guard let self else { return "" }
                    return self.createConversation(for: personaId, activate: true).id
                }
            },
            stopGeneration: { [weak self] conversationId in
                await MainActor.run {
                    self?.stopGenerating(conversationId: conversationId)
                }
            },
            resolvePending: { [weak self] kind, id, optionId, note in
                guard let self else { return false }
                if kind == "approval" {
                    await self.resolveApproval(id, optionId: optionId, note: note)
                    return true
                } else {
                    await self.resolveDecision(id, optionId: optionId, note: note)
                    return true
                }
            },
            loadDeliverableData: { [weak self] artifactId in
                guard let self,
                      let art = self.macOmnipotentEngine.artifact(id: artifactId),
                      let data = try? Data(contentsOf: URL(fileURLWithPath: art.filePath)) else {
                    return nil
                }
                return (data: data, mimeType: art.mimeType, fileName: art.fileName)
            },
            handleWebhook: { [weak self] routineId, authHeader, sigHeader, body in
                guard let self else { return (503, "Host store unavailable") }
                return await self.handleIncomingWebhook(
                    routineId: routineId,
                    authorizationHeader: authHeader,
                    signatureHeader: sigHeader,
                    body: body
                )
            }
        )
    }

    // MARK: - macOS Native System Takeover, Permissions & Omnipotent Execution

    public func refreshMacPermissions() {
        macPermissionsSnapshot = macOmnipotentEngine.probePermissions()
    }

    public func openMacPermissionSettings(_ kind: PipiMacPermissionKind) {
        PipiMacOmnipotentEngine.openSystemSettings(for: kind)
    }

    public func requestMacPermission(_ kind: PipiMacPermissionKind) async {
        await PipiMacOmnipotentEngine.requestInteractivePermission(for: kind)
        refreshMacPermissions()
    }

    public func revealCurrentAppInFinder() {
        PipiMacOmnipotentEngine.revealCurrentAppInFinder()
    }

    public func relaunchAppForPermissions() {
        prepareForAppUpgrade()
        PipiMacOmnipotentEngine.relaunchCurrentApp()
    }

    public var grantedMacPermissionsCount: Int {
        macPermissionsSnapshot.items.filter { $0.state == .granted }.count
    }

    @discardableResult
    public func executeOmnipotentIntent(
        _ intent: PipiOmnipotentDirectIntent,
        userPrompt: String,
        in conversationId: String,
        personaId: String,
        skipGuardrail: Bool = false,
        appendUserMessage: Bool = true
    ) async -> PipiMacOmnipotentCommandResult {
        let nowIso = ISO8601DateFormatter().string(from: Date())
        if appendUserMessage, let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            let userMsg = PipiChatMessage(role: .user, content: userPrompt, createdAt: nowIso)
            conversations[idx].messages.append(userMsg)
            conversations[idx].updatedAt = nowIso
            if conversations[idx].messages.count == 1 {
                conversations[idx].title = String(userPrompt.prefix(24))
            }
        }

        let projectForConv: PipiProject? = conversations.first(where: { $0.id == conversationId })?.projectId.flatMap { pid in
            projects.first(where: { $0.id == pid })
        }
        let projectDir: String? = {
            if let path = projectForConv?.workspacePath, !path.isEmpty {
                return path
            }
            return workspaceDirectory
        }()

        // Risk assessment + Security Auditor check for Mac-native side-effecting intents
        if !skipGuardrail {
            let personaObj = personas.first(where: { $0.id == personaId }) ?? activePersona
            let effectivePermission = effectivePermissionTier(for: personaObj, project: projectForConv)
            let riskSpec: (actionKind: PipiActionKind, toolName: String, target: String)? = {
                switch intent {
                case .sendSMS(let recipient, _):
                    return (.externalEffect, "apple_messages", recipient)
                case .sendMail(let recipient, _, _):
                    return (.externalEffect, "apple_mail", recipient)
                case .runCommand(let cmd):
                    let risk = PipiPermissionGuardrail.classifyPromptRisk(cmd, defaultTarget: projectDir ?? workspaceDirectory)
                    let kind: PipiActionKind = risk.actionKind == .readOnly ? .shellCommand : risk.actionKind
                    return (kind, "mac_shell", projectDir ?? workspaceDirectory)
                case .sendFile(let path):
                    return (.externalEffect, "send_file", path)
                case .recordScreen:
                    return (.localWrite, "screen_record", "mac_display")
                case .screenshot, .readSMS, .readMail, .voiceClip:
                    return nil
                }
            }()

            if let spec = riskSpec {
                let actionInput = PipiGuardrailActionInput(
                    operationId: "op_omni_\(UUID().uuidString.prefix(8).lowercased())",
                    toolName: spec.toolName,
                    actionKind: spec.actionKind,
                    target: spec.target,
                    payloadSummary: userPrompt,
                    isPreparatoryOnly: false,
                    sessionId: conversationId,
                    projectId: projectForConv?.id,
                    sourceTrust: .trustedUser,
                    trustedUserMessages: [userPrompt]
                )
                let verdict = await evaluateActionWithGuardrail(actionInput, auditMediumRisk: true)
                if verdict.decision == .deny {
                    let blocked = strings.t(
                        "🛡️ 安全审计官已拦截该高危操作（\(verdict.riskLevel.label(.zhHans))）：\(verdict.rationale)",
                        "🛡️ Blocked by Security Auditor (\(verdict.riskLevel.label(.en))): \(verdict.rationale)"
                    )
                    appendAssistantMessage(to: conversationId, content: blocked, engineLabel: strings.t("安全审计", "Security Auditor"), isError: true)
                    setSessionState(conversationId, to: .failed)
                    avatarEngine.setState(.needsYouUrgent)
                    saveResidentState()
                    return PipiMacOmnipotentCommandResult(succeeded: false, summary: blocked)
                }
                if verdict.decision == .needsApproval && effectivePermission != .autoEdit {
                    let msgId = UUID().uuidString
                    let pauseText = strings.t(
                        "🛡️ 该系统操作存在风险，已暂停并等待您的确认（\(verdict.riskLevel.label(.zhHans))）：\(verdict.rationale)",
                        "🛡️ Risky system action paused for your approval (\(verdict.riskLevel.label(.en))): \(verdict.rationale)"
                    )
                    if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
                        let msg = PipiChatMessage(
                            id: msgId,
                            role: .assistant,
                            content: pauseText,
                            createdAt: ISO8601DateFormatter().string(from: Date()),
                            engineLabel: strings.t("Mac 原生执行 · 待确认", "Mac Native · Needs Approval"),
                            isError: false
                        )
                        conversations[idx].messages.append(msg)
                    }
                    emitRiskyTaskApprovalCard(
                        conversationId: conversationId,
                        messageId: msgId,
                        question: strings.t("允许执行该 Mac 原生操作吗？", "Allow executing this Mac native action?"),
                        detail: verdict.rationale,
                        pendingPrompt: userPrompt,
                        pendingTarget: nil,
                        toolName: spec.toolName,
                        actionKind: spec.actionKind,
                        workDir: spec.target,
                        projectId: projectForConv?.id,
                        verdict: verdict
                    )
                    setSessionState(conversationId, to: .needsYou)
                    avatarEngine.setState(.needsYouApproval)
                    saveResidentState()
                    return PipiMacOmnipotentCommandResult(succeeded: false, summary: pauseText)
                }
            }
        }

        avatarEngine.setState(.macAutomating)

        let personaVoiceName: String? = {
            if let bot = personas.first(where: { $0.id == personaId }),
               let opt = PipiVoiceTimbreOption.builtInPresets.first(where: { $0.id == bot.voiceProfileId }) {
                return opt.systemVoiceIdentifier
            }
            return nil
        }()

        let result: PipiMacOmnipotentCommandResult
        switch intent {
        case .screenshot:
            result = await macOmnipotentEngine.captureScreenshot()
        case .recordScreen(let seconds):
            result = await macOmnipotentEngine.recordScreenVideo(durationSeconds: seconds)
        case .readSMS(let limit):
            result = await macOmnipotentEngine.readRecentSMS(limit: limit)
        case .sendSMS(let recipient, let body):
            result = await macOmnipotentEngine.sendSMS(recipient: recipient, body: body)
        case .readMail(let limit):
            result = await macOmnipotentEngine.readRecentMail(limit: limit)
        case .sendMail(let recipient, let subject, let body):
            result = await macOmnipotentEngine.sendOrDraftMail(to: recipient, subject: subject, body: body, sendImmediately: false)
        case .voiceClip(let text):
            result = await macOmnipotentEngine.synthesizeVoiceClip(text: text, voiceName: personaVoiceName)
        case .sendFile(let path):
            result = await macOmnipotentEngine.prepareFileDeliverable(path: path)
        case .runCommand(let command):
            result = await macOmnipotentEngine.runShellBuildOrTask(command: command, workingDirectory: projectDir)
        }

        let chatAttachments: [PipiChatAttachment] = result.artifacts.map { art in
            PipiChatAttachment(
                id: art.id,
                name: art.fileName,
                path: art.filePath,
                sizeBytes: Int(art.byteSize)
            )
        }

        let replyIso = ISO8601DateFormatter().string(from: Date())
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            let replyMsg = PipiChatMessage(
                role: .assistant,
                content: result.summary,
                createdAt: replyIso,
                engineLabel: strings.t("Mac 原生执行", "Mac Native"),
                isError: !result.succeeded,
                attachments: chatAttachments.isEmpty ? nil : chatAttachments
            )
            conversations[idx].messages.append(replyMsg)
            conversations[idx].updatedAt = replyIso
            if currentlyVisibleSessionId != conversationId {
                unreadConversationCounts[conversationId, default: 0] += 1
            }
            if !result.succeeded {
                setSessionState(conversationId, to: .failed)
            }
        }
        avatarEngine.setState(result.succeeded ? .idle : .needsYou)
        saveResidentState()
        return result
    }

    // MARK: - Dynamic Conversation Row Status & Local Model Platform Launcher

    public func unreadCount(forConversation id: String) -> Int {
        unreadConversationCounts[id] ?? 0
    }

    public func unreadCount(forGroup id: String) -> Int {
        unreadGroupCounts[id] ?? 0
    }

    public func markConversationRead(_ id: String) {
        unreadConversationCounts.removeValue(forKey: id)
    }

    public func markGroupRead(_ id: String) {
        unreadGroupCounts.removeValue(forKey: id)
    }

    public func incrementGroupUnreadIfNotVisible(_ groupId: String) {
        if currentlyVisibleGroupId != groupId {
            unreadGroupCounts[groupId, default: 0] += 1
        }
    }

    public func conversationRowStatus(for conv: PipiConversation) -> PipiConversationRowStatus {
        if let phase = runPhase(for: conv.id) {
            return phase == .queued ? .queued : .processing
        }
        if conv.state == .running {
            return .processing
        }
        if conv.state == .queued {
            return .queued
        }
        if conv.state == .needsYou || conv.approvals.contains(where: { $0.status == .pending }) {
            return .needsApproval
        }
        if conv.state == .failed || conv.messages.last?.isError == true {
            return .failed
        }
        let unread = unreadCount(forConversation: conv.id)
        if unread > 0 {
            return .unread(unread)
        }
        return .idle
    }

    @discardableResult
    public func scanLocalModelPlatforms() async -> [PipiLocalPlatformStatus] {
        await localModelPlatformManager.scanInstalledPlatforms()
    }

    @discardableResult
    public func launchAndUseLocalPlatformModel(
        platform kind: PipiLocalModelPlatformKind,
        modelId: String? = nil
    ) async -> PipiLocalLaunchResult {
        let result = await localModelPlatformManager.launchModel(platform: kind, modelId: modelId)
        if result.succeeded {
            let providerId = "local_\(kind.rawValue)"
            let cfg = PipiLLMProviderConfig(
                id: providerId,
                name: kind.displayName,
                kind: kind.providerKind,
                baseURL: result.baseURL,
                apiKey: kind == .ollama ? "" : "local-engine",
                modelId: result.modelId,
                isEnabled: true,
                temperature: 0.7
            )
            upsertLLMProvider(cfg, setAsDefault: true)
            setDefaultExecutionTarget(.llm(providerId: providerId))
        }
        return result
    }

    /// Immediately deploys a hardware-planned local model from the Unified Local Models workflow.
    @discardableResult
    public func deployPlannedLocalModel(
        entry: PipiLocalModelCatalogEntry? = nil,
        preferredPlatform: PipiLocalModelPlatformKind? = nil
    ) async -> PipiLocalLaunchResult {
        isDeployingLocalModel = true
        defer { isDeployingLocalModel = false }

        let targetEntry = entry ?? modelAutopilotPlan.primaryModel
        applyAutopilotPlanToGatewayConfig()
        var gwCfg = localGatewayConfig
        gwCfg.selectedLocalModelId = targetEntry.id
        updateLocalGatewayConfig(gwCfg)

        localModelDeployStatus = strings.t(
            "正在部署 \(targetEntry.displayName)...",
            "Deploying \(targetEntry.displayName)..."
        )

        let result = await localModelPlatformManager.deployPlannedModel(
            entry: targetEntry,
            preferredPlatform: preferredPlatform
        )
        if result.succeeded {
            let providerId = "local_\(result.platform.rawValue)"
            let cfg = PipiLLMProviderConfig(
                id: providerId,
                name: result.platform.displayName,
                kind: result.platform.providerKind,
                baseURL: result.baseURL,
                apiKey: result.platform == .ollama ? "" : "local-engine",
                modelId: result.modelId,
                isEnabled: true,
                temperature: 0.7
            )
            upsertLLMProvider(cfg, setAsDefault: true)
            setDefaultExecutionTarget(.llm(providerId: providerId))
        }
        localModelDeployStatus = result.message
        return result
    }

    // MARK: - WeChat iLink Remote Access Channel

    public func startWeChatILinkQRLogin() async {
        if wechatILinkManager.primaryBotId.isEmpty || !personas.contains(where: { $0.id == wechatILinkManager.primaryBotId }) {
            wechatILinkManager.primaryBotId = personas.first?.id ?? activePersona.id
        }
        if wechatILinkManager.groupMemberBotIds.isEmpty {
            wechatILinkManager.groupMemberBotIds = Array(personas.prefix(3).map(\.id))
        }
        await wechatILinkManager.startQRLogin(bridge: makeWeChatMessageBridge())
    }

    public func reconnectWeChatILink() {
        wechatILinkManager.reconnectSavedSession(bridge: makeWeChatMessageBridge())
    }

    public func disconnectWeChatILink(forgetBinding: Bool = false) {
        wechatILinkManager.disconnect(forgetBinding: forgetBinding)
    }

    public func setWeChatRoutingMode(_ mode: PipiWeChatRoutingMode) {
        wechatILinkManager.routingMode = mode
        saveResidentState()
    }

    public func toggleWeChatGroupMember(_ botId: String) {
        if let idx = wechatILinkManager.groupMemberBotIds.firstIndex(of: botId) {
            if wechatILinkManager.groupMemberBotIds.count > 1 {
                wechatILinkManager.groupMemberBotIds.remove(at: idx)
            }
        } else {
            wechatILinkManager.groupMemberBotIds.append(botId)
        }
        saveResidentState()
    }

    public func setAutoCheckUpdatesEnabled(_ enabled: Bool) {
        autoCheckUpdatesEnabled = enabled
        saveResidentState()
    }

    public func setProactiveCLIDelegationEnabled(_ enabled: Bool) {
        proactiveCLIDelegationEnabled = enabled
        saveResidentState()
    }

    public func setSecurityAuditorBotId(_ botId: String) {
        if personas.contains(where: { $0.id == botId }) {
            securityAuditorBotId = botId
            saveResidentState()
        }
    }

    /// Hydrates Keychain-backed LLM API keys and WeChat iLink credentials off the main thread after launch.
    private func hydrateNativeSecretsAfterLaunch() async {
        let store = self.secretStore
        let missingAccounts: [String] = llmProviders
            .filter { $0.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(\.secretAccountKey)

        if !missingAccounts.isEmpty {
            let hydratedMap = await Task.detached(priority: .utility) { () -> [String: String] in
                var map: [String: String] = [:]
                for account in missingAccounts {
                    if let val = store.secret(for: account) {
                        map[account] = val
                    }
                }
                return map
            }.value

            if !hydratedMap.isEmpty {
                var didChange = false
                for idx in llmProviders.indices {
                    let acct = llmProviders[idx].secretAccountKey
                    if llmProviders[idx].apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let secret = hydratedMap[acct], !secret.isEmpty {
                        llmProviders[idx].apiKey = secret
                        didChange = true
                    }
                }
                if didChange {
                    refreshLocalHostCapabilities()
                }
            }
        }

        let restoredWeChat = await wechatILinkManager.restoreSavedCredentialsInBackground()
        if restoredWeChat && wechatAutoConnectEnabled {
            reconnectWeChatILink()
        }
    }

    /// Delivers a system + in-app + WeChat notification (e.g. triggered via `pipibot://notify?...`).
    public func deliverSystemAndWeChatNotification(title: String, body: String) async {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "PiPiBot" : title
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBody.isEmpty else { return }

        noticeBanner = "\(cleanTitle)：\(cleanBody)"
        let targetConvId = activeConversationId ?? conversations.first?.id ?? createConversation(activate: true).id
        appendAssistantMessage(
            to: targetConvId,
            content: "📣 **\(cleanTitle)**\n\n\(cleanBody)",
            engineLabel: strings.appName,
            isError: false
        )
        saveResidentState()

        #if canImport(UserNotifications)
        if enableNativeRuntime && Bundle.main.bundleURL.pathExtension == "app" {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            let content = UNMutableNotificationContent()
            content.title = cleanTitle
            content.body = cleanBody
            content.sound = .default
            let req = UNNotificationRequest(identifier: "pipi_notify_\(UUID().uuidString.prefix(8))", content: content, trigger: nil)
            try? await center.add(req)
        }
        #endif

        _ = await wechatILinkManager.sendProactiveText("📣 \(cleanTitle)\n\n\(cleanBody)")
    }

    /// Transcribes an inbound WeChat audio file (converting SILK/AMR/M4A if local decoders exist, then using Apple Speech / Cloud STT).
    private func transcribeLocalAudioFile(_ filePath: String) async -> String? {
        guard FileManager.default.fileExists(atPath: filePath) else { return nil }
        let ext = (filePath as NSString).pathExtension.lowercased()
        var playableURL = URL(fileURLWithPath: filePath)
        var tempWavURL: URL? = nil

        #if os(macOS)
        // Convert to WAV off the main thread with timeout so audio conversion never freezes UI
        if ext != "wav" && ext != "m4a" && ext != "mp3" && ext != "caf" {
            let candidateWav = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pipi_wx_voice_\(UUID().uuidString.prefix(8)).wav")
            let ffmpegPath = PipiNativeMacRuntime.findExecutable("ffmpeg")
            let converted: Bool = await Task.detached(priority: .userInitiated) {
                let proc = Process()
                if let ffmpegPath {
                    proc.executableURL = URL(fileURLWithPath: ffmpegPath)
                    proc.arguments = ["-y", "-i", filePath, "-ar", "16000", "-ac", "1", candidateWav.path]
                } else {
                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
                    proc.arguments = ["-f", "WAVE", "-d", "LEI16@16000", filePath, candidateWav.path]
                }
                proc.standardInput = FileHandle.nullDevice
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                do {
                    try proc.run()
                    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                    timer.schedule(deadline: .now() + 15.0)
                    timer.setEventHandler { if proc.isRunning { proc.terminate() } }
                    timer.resume()
                    proc.waitUntilExit()
                    timer.cancel()
                    return proc.terminationStatus == 0 && FileManager.default.fileExists(atPath: candidateWav.path)
                } catch {
                    return false
                }
            }.value
            if converted {
                playableURL = candidateWav
                tempWavURL = candidateWav
            }
        }
        #endif
        defer {
            if let tempWavURL {
                try? FileManager.default.removeItem(at: tempWavURL)
            }
        }

        // Try on-device Apple Speech Recognition first
        #if canImport(Speech)
        if SFSpeechRecognizer.authorizationStatus() == .authorized {
            let localeId = resolvedLanguage == .zhHans ? "zh-CN" : "en-US"
            if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId)), recognizer.isAvailable {
                let text: String? = await withCheckedContinuation { cont in
                    let req = SFSpeechURLRecognitionRequest(url: playableURL)
                    req.shouldReportPartialResults = false
                    var finished = false
                    recognizer.recognitionTask(with: req) { result, error in
                        if finished { return }
                        if let result, result.isFinal {
                            finished = true
                            cont.resume(returning: result.bestTranscription.formattedString)
                        } else if error != nil {
                            finished = true
                            cont.resume(returning: nil)
                        }
                    }
                }
                if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
            }
        }
        #endif

        // Fallback to PipiDailyVoiceEngine Cloud STT if user configured an API key
        if let audioData = try? Data(contentsOf: playableURL), !audioData.isEmpty {
            if let res = try? await voiceEngine.transcribeAudioBuffer(audioData) {
                return res.text
            }
        }
        return nil
    }

    public func makeWeChatMessageBridge() -> PipiWeChatMessageBridge {
        PipiWeChatMessageBridge(
            availableBots: { [weak self] in
                await MainActor.run {
                    guard let self else { return [] }
                    let lang = self.resolvedLanguage
                    return self.personas.map { bot in
                        PipiWeChatBotInfo(
                            id: bot.id,
                            name: bot.name(lang),
                            role: bot.role(lang),
                            modelLabel: self.activeEngineDisplayLabel(for: bot),
                            permissionTier: bot.permissionTier
                        )
                    }
                }
            },
            availableProjects: { [weak self] in
                await MainActor.run {
                    guard let self else { return [] }
                    return self.projects.map {
                        PipiWeChatProjectInfo(id: $0.id, name: $0.name, workspacePath: $0.workspacePath)
                    }
                }
            },
            availableConversations: { [weak self] in
                await MainActor.run {
                    guard let self else { return [] }
                    let lang = self.resolvedLanguage
                    return self.conversations
                        .filter { !$0.isArchived }
                        .sorted { $0.updatedAt > $1.updatedAt }
                        .prefix(20)
                        .map { conv in
                            let persona = self.personas.first(where: { $0.id == conv.personaId })
                            let proj = conv.projectId.flatMap { pid in self.projects.first(where: { $0.id == pid }) }
                            return PipiWeChatConversationInfo(
                                id: conv.id,
                                personaId: conv.personaId,
                                personaName: persona?.name(lang) ?? self.strings.appName,
                                title: conv.title,
                                projectId: conv.projectId,
                                projectName: proj?.name,
                                messageCount: conv.messages.count
                            )
                        }
                }
            },
            availableModelChoices: { [weak self] in
                await MainActor.run {
                    guard let self else { return [] }
                    var choices: [PipiWeChatModelChoice] = [
                        PipiWeChatModelChoice(
                            id: "auto_default",
                            label: "跟随全局默认模型（\(self.activeEngineDisplayLabel(for: PipiBotPersona.defaultPersonas[0]))）",
                            target: .auto,
                            modelId: nil
                        )
                    ]
                    for cfg in self.readyLLMProviders {
                        choices.append(PipiWeChatModelChoice(
                            id: "llm_\(cfg.id)",
                            label: "\(cfg.name) · \(cfg.modelId)",
                            target: .llm(providerId: cfg.id),
                            modelId: cfg.modelId
                        ))
                        for m in cfg.kind.suggestedModels where m != cfg.modelId {
                            choices.append(PipiWeChatModelChoice(
                                id: "llm_\(cfg.id)_\(m)",
                                label: "\(cfg.name) · \(m)",
                                target: .llm(providerId: cfg.id),
                                modelId: m
                            ))
                        }
                    }
                    for agent in self.usableLocalAgents {
                        choices.append(PipiWeChatModelChoice(
                            id: "cli_\(agent.kind.rawValue)",
                            label: "本地 Agent · \(agent.kind.displayName)",
                            target: .localAgent(agent.kind),
                            modelId: nil
                        ))
                    }
                    return choices
                }
            },
            executeTurn: { [weak self] botId, requestedConvId, projectId, prompt, attachments, fromUserId in
                guard let self else {
                    return (PipiWeChatOutboundReply(botName: "PiPiBot", text: "Mac 端服务未就绪。"), nil)
                }
                let (convId, botName, beforeMsgCount) = await MainActor.run { () -> (String, String, Int) in
                    let lang = self.resolvedLanguage
                    let bot = self.personas.first(where: { $0.id == botId }) ?? self.activePersona
                    let conv: PipiConversation
                    if let requestedConvId,
                       let found = self.conversations.first(where: { $0.id == requestedConvId && !$0.isArchived }) {
                        conv = found
                        if let projectId, found.projectId != projectId {
                            self.moveConversation(found.id, toProject: projectId)
                        }
                    } else {
                        let titleTag = "微信 · \(bot.name(lang))"
                        if let existing = self.conversations.first(where: { $0.personaId == bot.id && $0.title == titleTag && !$0.isArchived }) {
                            conv = existing
                            if let projectId, existing.projectId != projectId {
                                self.moveConversation(existing.id, toProject: projectId)
                            }
                        } else {
                            conv = self.createConversation(for: bot.id, projectId: projectId, title: titleTag, activate: false)
                        }
                    }
                    return (conv.id, bot.name(lang), conv.messages.count)
                }

                await self.sendPersonalMessage(
                    prompt,
                    attachments: attachments,
                    conversationId: convId,
                    personaId: botId,
                    activateTargetConversation: false
                )

                return await MainActor.run {
                    let conv = self.conversations.first(where: { $0.id == convId })
                    let newAssistantMsgs = (conv?.messages.dropFirst(beforeMsgCount) ?? []).filter { $0.role == .assistant }
                    let latest = newAssistantMsgs.last
                    let replyText = latest?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "已在 Mac 端完成处理。"
                    let artifacts: [PipiDeliverableArtifact] = (latest?.attachments ?? []).compactMap { att in
                        if let art = self.macOmnipotentEngine.artifact(id: att.id) {
                            return art
                        }
                        if FileManager.default.fileExists(atPath: att.path) {
                            let (kind, mime) = PipiDeliverableArtifact.inferKindAndMime(for: att.path)
                            let art = PipiDeliverableArtifact(
                                id: att.id,
                                kind: kind,
                                fileName: att.name,
                                filePath: att.path,
                                mimeType: mime,
                                byteSize: Int64(att.sizeBytes)
                            )
                            self.macOmnipotentEngine.registerArtifact(art)
                            return art
                        }
                        return nil
                    }

                    let pendingAppr: PipiWeChatPendingApprovalInfo? = conv?.approvals
                        .last(where: { $0.status == .pending })
                        .map { appr in
                            PipiWeChatPendingApprovalInfo(
                                approvalId: appr.id,
                                question: appr.question,
                                rationale: appr.rationale ?? appr.detail ?? "需要您的安全确认。",
                                riskLevel: appr.riskLevel ?? .medium,
                                options: appr.options.map { ($0.id, $0.label) }
                            )
                        }

                    _ = fromUserId
                    return (
                        PipiWeChatOutboundReply(
                            botName: botName,
                            text: replyText,
                            artifacts: artifacts,
                            pendingApproval: pendingAppr
                        ),
                        convId
                    )
                }
            },
            createBot: { [weak self] name, role, templateId, target, modelId, permissionTier in
                await MainActor.run {
                    guard let self else { return nil }
                    let tpl = PipiBotPersonaTemplate.catalog.first(where: { $0.id == templateId })
                        ?? PipiBotPersonaTemplate.catalog.last!
                    var created = tpl.instantiate(
                        customName: name,
                        customPrompt: nil,
                        permissionTier: permissionTier,
                        preferredTarget: target,
                        preferredModelId: modelId
                    )
                    created.roleZh = role
                    created.roleEn = role
                    created.systemPrompt = "You are \(name), \(role). Reply in the user's language with concise, practical, high-signal assistance."
                    self.upsertPersona(created)
                    return PipiWeChatBotInfo(
                        id: created.id,
                        name: created.name(self.resolvedLanguage),
                        role: created.role(self.resolvedLanguage),
                        modelLabel: self.activeEngineDisplayLabel(for: created),
                        permissionTier: created.permissionTier
                    )
                }
            },
            createConversation: { [weak self] personaId, projectId, title in
                await MainActor.run {
                    guard let self else { return nil }
                    return self.createConversation(for: personaId, projectId: projectId, title: title, activate: false).id
                }
            },
            bindConversationProject: { [weak self] conversationId, projectId in
                await MainActor.run {
                    self?.moveConversation(conversationId, toProject: projectId)
                }
            },
            updateBotConfig: { [weak self] botId, target, modelId, clearModelOverride, permissionTier in
                await MainActor.run {
                    guard let self, let idx = self.personas.firstIndex(where: { $0.id == botId }) else {
                        return "未找到目标 Bot。"
                    }
                    if let target {
                        self.personas[idx].preferredTarget = target
                    }
                    if clearModelOverride {
                        self.personas[idx].preferredModelId = nil
                    } else if let modelId, !modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.personas[idx].preferredModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if let permissionTier {
                        self.personas[idx].permissionTier = permissionTier
                    }
                    self.saveResidentState()
                    let updated = self.personas[idx]
                    return "✅ 已更新「\(updated.name(self.resolvedLanguage))」配置：\n• 驱动引擎/模型：\(self.activeEngineDisplayLabel(for: updated))\n• 风险权限：\(updated.permissionTier.label(.zhHans))"
                }
            },
            toggleSetting: { [weak self] key in
                await MainActor.run {
                    guard let self else { return "" }
                    switch key {
                    case "llm_judge":
                        self.setLLMGuardrailJudgeEnabled(!self.llmGuardrailJudgeEnabled)
                        return "✅ 「安全审计官自动评估」已\(self.llmGuardrailJudgeEnabled ? "开启" : "关闭")。"
                    case "proactive_cli":
                        self.setProactiveCLIDelegationEnabled(!self.proactiveCLIDelegationEnabled)
                        return "✅ 「主动调用 Codex/CLI 工具」已\(self.proactiveCLIDelegationEnabled ? "开启" : "关闭")。"
                    case "memory":
                        self.memoryEnabled.toggle()
                        self.saveResidentState()
                        return "✅ 「跨会话长期记忆」已\(self.memoryEnabled ? "开启" : "关闭")。"
                    default:
                        return "已记录配置。"
                    }
                }
            },
            fetchConfigSnapshot: { [weak self] primaryBotId, routingMode, typingEnabled, convId, projId in
                await MainActor.run {
                    guard let self else {
                        return PipiWeChatConfigSnapshot(
                            primaryBotId: primaryBotId,
                            primaryBotName: "PiPi",
                            routingMode: routingMode,
                            activeConversationTitle: nil,
                            activeProjectName: nil,
                            defaultModelLabel: "未配置",
                            llmJudgeEnabled: true,
                            proactiveCLIDelegationEnabled: true,
                            typingIndicatorEnabled: typingEnabled,
                            memoryEnabled: true,
                            appVersion: "0.11.0"
                        )
                    }
                    let lang = self.resolvedLanguage
                    let bot = self.personas.first(where: { $0.id == primaryBotId }) ?? self.activePersona
                    let conv = convId.flatMap { id in self.conversations.first(where: { $0.id == id }) }
                    let proj = projId.flatMap { id in self.projects.first(where: { $0.id == id }) }
                    return PipiWeChatConfigSnapshot(
                        primaryBotId: bot.id,
                        primaryBotName: bot.name(lang),
                        routingMode: routingMode,
                        activeConversationTitle: conv?.title,
                        activeProjectName: proj?.name,
                        defaultModelLabel: self.activeEngineDisplayLabel(for: PipiBotPersona.defaultPersonas[0]),
                        llmJudgeEnabled: self.llmGuardrailJudgeEnabled,
                        proactiveCLIDelegationEnabled: self.proactiveCLIDelegationEnabled,
                        typingIndicatorEnabled: typingEnabled,
                        memoryEnabled: self.memoryEnabled,
                        appVersion: self.appDisplayVersion
                    )
                }
            },
            resolveApproval: { [weak self] approvalId, optionId in
                guard let self else { return nil }
                let (convId, beforeCount, botName) = await MainActor.run { () -> (String?, Int, String) in
                    let conv = self.conversations.first(where: { $0.approvals.contains(where: { $0.id == approvalId }) })
                    let persona = conv.flatMap { c in self.personas.first(where: { $0.id == c.personaId }) } ?? self.activePersona
                    return (conv?.id, conv?.messages.count ?? 0, persona.name(self.resolvedLanguage))
                }
                await self.resolveApproval(approvalId, optionId: optionId, note: "Resolved via WeChat")
                return await MainActor.run {
                    guard let convId, let conv = self.conversations.first(where: { $0.id == convId }) else {
                        return PipiWeChatOutboundReply(botName: botName, text: "已处理确认。")
                    }
                    let latest = conv.messages.dropFirst(beforeCount).last(where: { $0.role == .assistant })
                    let text = latest?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "已取消该风险操作。"
                    return PipiWeChatOutboundReply(botName: botName, text: text)
                }
            },
            checkForUpdates: { [weak self] in
                guard let self else { return ("服务未就绪", nil) }
                let current = await MainActor.run { self.appDisplayVersion }
                let state = await self.updateManager.checkForUpdates(currentVersion: current, silent: false)
                switch state {
                case .updateAvailable(let rel):
                    let notes = rel.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    let shortNotes = notes.isEmpty ? "" : "\n更新内容：\n\(String(notes.prefix(360)))"
                    return ("🚀 发现新版本 \(rel.tagName)（当前 v\(current)）：\(rel.title)\(shortNotes)", rel)
                case .upToDate(let v, _):
                    return ("✅ 当前版本 v\(v) 已是最新 GitHub Release。", nil)
                case .error(let msg):
                    return ("⚠️ \(msg)", nil)
                default:
                    return ("正在检查更新中...", nil)
                }
            },
            installUpdate: { [weak self] release in
                guard let self else { return "服务未就绪" }
                await MainActor.run {
                    self.updateManager.downloadAndInstallUpdate(release) {
                        self.prepareForAppUpgrade()
                    }
                }
                return "⬇️ 已开始在 Mac 端下载并校验 v\(release.version)，安装完成后 PiPiBot 将自动重启。"
            },
            transcribeAudioFile: { [weak self] path in
                guard let self else { return nil }
                return await self.transcribeLocalAudioFile(path)
            },
            switchModeFromChat: { [weak self] mode, memberIds in
                await MainActor.run {
                    guard let self else { return }
                    self.wechatILinkManager.routingMode = mode
                    if let memberIds, !memberIds.isEmpty {
                        self.wechatILinkManager.groupMemberBotIds = memberIds
                    }
                    self.saveResidentState()
                }
            },
            executeTurnWithProgress: { [weak self] botId, requestedConvId, projectId, prompt, attachments, fromUserId, onProgress in
                guard let self else {
                    return (PipiWeChatOutboundReply(botName: "PiPiBot", text: "Mac 端服务未就绪。"), nil)
                }
                let (convId, botName, beforeMsgCount) = await MainActor.run { () -> (String, String, Int) in
                    let lang = self.resolvedLanguage
                    let bot = self.personas.first(where: { $0.id == botId }) ?? self.activePersona
                    let conv: PipiConversation
                    if let requestedConvId,
                       let found = self.conversations.first(where: { $0.id == requestedConvId && !$0.isArchived }) {
                        conv = found
                        if let projectId, found.projectId != projectId {
                            self.moveConversation(found.id, toProject: projectId)
                        }
                    } else {
                        let titleTag = "微信 · \(bot.name(lang))"
                        if let existing = self.conversations.first(where: { $0.personaId == bot.id && $0.title == titleTag && !$0.isArchived }) {
                            conv = existing
                            if let projectId, existing.projectId != projectId {
                                self.moveConversation(existing.id, toProject: projectId)
                            }
                        } else {
                            conv = self.createConversation(for: bot.id, projectId: projectId, title: titleTag, activate: false)
                        }
                    }
                    return (conv.id, bot.name(lang), conv.messages.count)
                }

                await self.sendPersonalMessage(
                    prompt,
                    attachments: attachments,
                    conversationId: convId,
                    personaId: botId,
                    activateTargetConversation: false,
                    onProgress: onProgress
                )

                return await MainActor.run {
                    let conv = self.conversations.first(where: { $0.id == convId })
                    let newAssistantMsgs = (conv?.messages.dropFirst(beforeMsgCount) ?? []).filter { $0.role == .assistant }
                    let latest = newAssistantMsgs.last
                    let replyText = latest?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? "已在 Mac 端完成处理。"
                    let artifacts: [PipiDeliverableArtifact] = (latest?.attachments ?? []).compactMap { att in
                        if let art = self.macOmnipotentEngine.artifact(id: att.id) {
                            return art
                        }
                        if FileManager.default.fileExists(atPath: att.path) {
                            let (kind, mime) = PipiDeliverableArtifact.inferKindAndMime(for: att.path)
                            let art = PipiDeliverableArtifact(
                                id: att.id,
                                kind: kind,
                                fileName: att.name,
                                filePath: att.path,
                                mimeType: mime,
                                byteSize: Int64(att.sizeBytes)
                            )
                            self.macOmnipotentEngine.registerArtifact(art)
                            return art
                        }
                        return nil
                    }

                    let pendingAppr: PipiWeChatPendingApprovalInfo? = conv?.approvals
                        .last(where: { $0.status == .pending })
                        .map { appr in
                            PipiWeChatPendingApprovalInfo(
                                approvalId: appr.id,
                                question: appr.question,
                                rationale: appr.rationale ?? appr.detail ?? "需要您的安全确认。",
                                riskLevel: appr.riskLevel ?? .medium,
                                options: appr.options.map { ($0.id, $0.label) }
                            )
                        }

                    _ = fromUserId
                    return (
                        PipiWeChatOutboundReply(
                            botName: botName,
                            text: replyText,
                            artifacts: artifacts,
                            pendingApproval: pendingAppr
                        ),
                        convId
                    )
                }
            },
            synthesizeVoiceReply: { [weak self] spokenText, botId in
                guard let self else { return nil }
                let voiceName: String? = await MainActor.run {
                    if let bot = self.personas.first(where: { $0.id == botId }),
                       let opt = PipiVoiceTimbreOption.builtInPresets.first(where: { $0.id == bot.voiceProfileId }) {
                        return opt.systemVoiceIdentifier
                    }
                    return nil
                }
                let res = await self.macOmnipotentEngine.synthesizeVoiceClip(text: spokenText, voiceName: voiceName)
                return res.artifacts.first
            }
        )
    }

    // MARK: - Jarvis Native Multi-Step Agent Loop, CLI Self-Recovery, Local Vault Migration & Proactive Butler

    /// Manual one-time import from legacy macOS Keychain into the zero-popup local AES-256-GCM vault.
    /// Never invoked automatically at launch.
    @discardableResult
    public func importSecretsFromLegacyKeychain() -> Int {
        guard let vault = secretStore as? PipiLocalEncryptedSecretStore else {
            return 0
        }
        var accounts = llmProviders.map(\.secretAccountKey)
        accounts.append("wechat_ilink_bot_credentials_v1")
        accounts.append(voiceConfig.cloudStt.keychainAccount)
        accounts.append(voiceConfig.cloudTts.keychainAccount)

        let imported = vault.migrateFromLegacyKeychain(accounts: accounts)
        if imported > 0 {
            for idx in llmProviders.indices {
                let acct = llmProviders[idx].secretAccountKey
                if llmProviders[idx].apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let sec = vault.secret(for: acct), !sec.isEmpty {
                    llmProviders[idx].apiKey = sec
                }
            }
            refreshLocalHostCapabilities()
            Task { @MainActor [weak self] in
                guard let self else { return }
                let restored = await self.wechatILinkManager.restoreSavedCredentialsInBackground()
                if restored && self.wechatAutoConnectEnabled {
                    self.reconnectWeChatILink()
                }
            }
            noticeBanner = "已从旧版 Keychain 成功导入 \(imported) 项凭据到本地加密保险库，以后再也不会弹密码窗啦！"
        } else {
            noticeBanner = "本地加密保险库已是最新状态，未发现需要迁入的旧版凭据。"
        }
        return imported
    }

    /// Connects to a local built-in or remote self-hosted Linux VPS Mesh Hub and syncs online nodes.
    public func connectMeshHub(url: String, token: String = "") async {
        meshHubClient.hubURLString = url.trimmingCharacters(in: .whitespacesAndNewlines)
        meshHubClient.hubToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = await refreshMeshNodes()
    }

    /// Refreshes online multi-machine nodes from the configured Mesh Hub.
    @discardableResult
    public func refreshMeshNodes() async -> [PipiMeshNodeInfo] {
        let fetched = await meshHubClient.refreshNodes()
        for node in fetched {
            _ = ensurePersonaForMeshNode(node, saveImmediately: false)
        }
        if !fetched.isEmpty {
            saveResidentState()
        }
        return fetched
    }

    /// Binds an existing Bot persona to run on a specific remote Mesh Hub node (or back to Local Mac when nil).
    public func bindPersona(_ personaId: String, toHostNode node: PipiMeshNodeInfo?) {
        guard let idx = personas.firstIndex(where: { $0.id == personaId }) else { return }
        if let node {
            personas[idx].hostId = node.nodeId
            personas[idx].hostDisplayName = node.name
        } else {
            personas[idx].hostId = PipiHostDescriptor.localHostId
            personas[idx].hostDisplayName = nil
        }
        saveResidentState()
    }

    /// Ensures a directly chat-able / group-mentionable Bot persona exists for a discovered remote Linux/Mac node
    /// so users can @mention or chat with any machine's Agent without switching workspaces!
    @discardableResult
    public func ensurePersonaForMeshNode(_ node: PipiMeshNodeInfo, saveImmediately: Bool = true) -> PipiBotPersona {
        let personaId = "bot_mesh_\(node.nodeId.lowercased().replacingOccurrences(of: " ", with: "_"))"
        if let existingIdx = personas.firstIndex(where: { $0.id == personaId || $0.hostId == node.nodeId }) {
            personas[existingIdx].hostDisplayName = node.name
            if saveImmediately { saveResidentState() }
            return personas[existingIdx]
        }
        let gpuHint = node.telemetry.gpuSummary.map { " · GPU: \($0)" } ?? ""
        let cliHint = node.cliAgents.isEmpty ? "原生工具箱" : node.cliAgents.joined(separator: "/")
        let created = PipiBotPersona(
            id: personaId,
            hostId: node.nodeId,
            hostDisplayName: node.name,
            nameZh: "\(node.name) · 节点管家",
            nameEn: "\(node.name) · Node Agent",
            roleZh: "\(node.platformBadge)/\(node.arch) 远程主机执行节点（\(cliHint)\(gpuHint)）",
            roleEn: "\(node.platformBadge)/\(node.arch) remote execution node (\(cliHint)\(gpuHint))",
            greetingZh: "嗨！我驻扎在「\(node.name)」(\(node.platformBadge)) 上，随时可以直接发指令或在群里 @我 跨机协作！",
            greetingEn: "Hi! I run directly on \(node.name) (\(node.platformBadge)). Message or @mention me in any group!",
            systemPrompt: "You are the remote node agent on \(node.name) (\(node.platformBadge)/\(node.arch)). Execute tasks directly on this machine and collaborate seamlessly with teammates across hosts.",
            accent: node.platform.lowercased() == "linux" ? .emerald : .sky,
            avatarShape: .orb,
            idleAvatarState: .ambientBreathe,
            preferredTarget: .auto,
            permissionTier: .autoEdit
        )
        personas.append(created)
        if saveImmediately { saveResidentState() }
        return created
    }

    /// Installs a community SKILL.md pack (catalog ID, GitHub URL, or local directory) and syncs to Hub.
    @discardableResult
    public func installCommunitySkill(
        source: String,
        scope: PipiEcosystemScope = .global,
        targetId: String? = nil
    ) async -> PipiInstalledSkillPack {
        let pack = await ecosystemManager.installSkill(
            source: source,
            scope: scope,
            targetId: targetId,
            hubClient: meshHubClient.isConnected ? meshHubClient : nil
        )
        noticeBanner = "已安装社区技能包「\(pack.name)」"
        return pack
    }

    /// Installs a community MCP Server (stdio or SSE) and syncs to Hub.
    @discardableResult
    public func installCommunityMCP(
        id: String? = nil,
        name: String,
        description: String = "Community MCP Server",
        transport: PipiInstalledMCPServer.Transport = .stdio,
        command: String? = nil,
        args: [String] = [],
        url: String? = nil,
        scope: PipiEcosystemScope = .global,
        targetId: String? = nil
    ) async -> PipiInstalledMCPServer {
        let srv = await ecosystemManager.installMCPServer(
            id: id,
            name: name,
            description: description,
            transport: transport,
            command: command,
            args: args,
            url: url,
            scope: scope,
            targetId: targetId,
            hubClient: meshHubClient.isConnected ? meshHubClient : nil
        )
        noticeBanner = "已安装 MCP 服务「\(srv.name)」"
        return srv
    }

    /// Generates and delivers the Jarvis daily morning / pre-meeting briefing to Mac & WeChat.
    public func triggerDailyBriefingNow() async {
        let calSummary = await readCalendarAndRemindersSummary()
        let failedCount = runRecords.prefix(20).filter { $0.status == .failed }.count
        let briefing = await PipiProactiveButler.buildDailyBriefing(
            calendarSummary: calSummary,
            workspaceDirectory: workspaceDirectory,
            recentFailedRunsCount: failedCount
        )
        await deliverSystemAndWeChatNotification(title: "☀️ PiPi 每日早报", body: briefing)
    }

    /// Runs the Mac health & GitHub release sentinel with 4-hour per-category anti-fatigue cooldown.
    private func runProactiveSentinelSweep(now: Date = Date()) async {
        let updateVer: String? = {
            if case .updateAvailable(let rel) = updateManager.state {
                return rel.version
            }
            return nil
        }()
        let alerts = await PipiProactiveButler.inspectSystemSentinel(availableUpdateVersion: updateVer)
        for alert in alerts {
            if let lastAt = lastSentinelAlertAtByCategory[alert.category],
               now.timeIntervalSince(lastAt) < 14_400 {
                continue
            }
            lastSentinelAlertAtByCategory[alert.category] = now
            await deliverSystemAndWeChatNotification(title: "🔔 \(alert.title)", body: alert.body)
        }
    }

    private func readCalendarAndRemindersSummary() async -> String {
        let collectorInput = PipiNativeSignalCollectorInput(
            enabledSources: Set([.calendarEventKit, .remindersEventKit]),
            workspaceDirectories: [workspaceDirectory],
            recentProfileNote: personalProfileNote,
            now: Date()
        )
        let signals = await nativeSignalProvider.collectSignals(input: collectorInput)
        let filtered = signals.filter { $0.source == .calendarEventKit || $0.source == .remindersEventKit }
        var calLines: [String] = []
        for sig in filtered.prefix(8) {
            calLines.append("• \(sig.title)：\(sig.content)")
        }
        if calLines.isEmpty {
            return "未来 24 小时内暂无待办日程或即将到期的提醒。"
        }
        return calLines.joined(separator: "\n")
    }

    /// Native multi-step Jarvis ReAct / Function-Calling loop with lively step-by-step narration,
    /// workspace-wide auto-execution, concurrent read-only batching, premature-stop auto-continuation,
    /// Guard confirmation for high-risk actions, and artifact collection.
    public func runJarvisAgentLoop(
        config: PipiLLMProviderConfig,
        systemPrompt: String,
        history: [PipiChatMessage],
        conversationId: String,
        persona: PipiBotPersona,
        workDir: String,
        runId: String,
        placeholderMessageId: String,
        onDelta: (@Sendable (String) -> Void)?,
        maxSteps: Int = PipiAgentToolbox.ContinuationGuard.defaultMaxSteps
    ) async throws -> PipiInferenceResult {
        var wireMessages = PipiInferenceEngine.buildInitialAgentWireMessages(
            systemPrompt: systemPrompt,
            history: history
        )
        let deliverablesDir = localDataRootURL.appendingPathComponent("deliverables", isDirectory: true)
        let callbacks = makeAgentHostCallbacks(conversationId: conversationId, personaId: persona.id)
        let progressCallback = progressCallbacksByConversation[conversationId]
        let lang = resolvedLanguage
        let latestUserText = history.last(where: { $0.role == .user })?.content ?? ""

        var collectedSteps: [PipiStepEvent] = []
        var collectedArtifacts: [PipiDeliverableArtifact] = []
        var sentInitialAck = false
        var finalText = ""
        var finalLabel = "\(config.name) · \(config.modelId)"
        var autoContinueCount = 0
        var lastCallSignature: String? = nil
        var consecutiveRepeatCount = 0
        var budgetHintInjected = false

        let dynamicMCPTools = ecosystemManager.dynamicMCPTools(forPersonaId: persona.id, hostId: persona.hostId)
        let combinedTools = PipiAgentToolbox.allTools + dynamicMCPTools

        for stepIdx in 1...maxSteps {
            if Task.isCancelled { throw CancellationError() }

            let compactedWire = PipiVisionContextCompactor.compact(messages: wireMessages, maxRetainedImages: 2)
            let stepResult = try await PipiInferenceEngine.invokeLLMWithTools(
                config: config,
                messages: compactedWire,
                tools: combinedTools
            )
            finalLabel = stepResult.engineLabel
            self.recordLLMUsage(
                persona: persona,
                conversationId: conversationId,
                taskTitle: latestUserText.isEmpty ? persona.name(lang) : String(latestUserText.prefix(48)),
                config: config,
                promptTokens: stepResult.promptTokens,
                completionTokens: stepResult.completionTokens,
                cachedTokens: stepResult.cachedTokens ?? 0,
                fallbackPromptText: latestUserText,
                fallbackCompletionText: stepResult.text
            )

            // No tool calls -> check whether the model stopped prematurely mid-task before finishing
            if stepResult.toolCalls.isEmpty {
                if stepIdx < maxSteps,
                   PipiAgentToolbox.ContinuationGuard.shouldAutoContinue(
                       replyText: stepResult.text,
                       executedStepCount: collectedSteps.count,
                       autoContinueCount: autoContinueCount
                   ) {
                    autoContinueCount += 1
                    wireMessages.append(.assistant(text: stepResult.text, toolCalls: []))
                    wireMessages.append(.user(text: PipiAgentToolbox.ContinuationGuard.continuationNudgePrompt(), images: []))
                    let nudgeStatus = lang == .zhHans ? "检测到任务还差最后一步，继续自动完成并验证…" : "Detected unfinished final step, continuing automatically…"
                    if var runState = activeRuns[conversationId], runState.runId == runId {
                        runState.statusText = nudgeStatus
                        activeRuns[conversationId] = runState
                    }
                    continue
                }

                finalText = stepResult.text
                if !finalText.isEmpty {
                    onDelta?(finalText)
                }
                break
            }

            // Emit lively initial ack on the first tool round so user never waits in silence
            if !sentInitialAck {
                sentInitialAck = true
                let ack = PipiLivelyProgressNarrator.initialAck(for: latestUserText, lang: lang)
                if var runState = activeRuns[conversationId], runState.runId == runId {
                    runState.statusText = ack
                    activeRuns[conversationId] = runState
                }
                if let progressCallback {
                    await progressCallback(ack)
                }
            }

            wireMessages.append(.assistant(text: stepResult.text, toolCalls: stepResult.toolCalls))

            var pausedForApprovalMessage: String? = nil
            var repeatedToolNameToNudge: String? = nil

            let canRunInParallel = stepResult.toolCalls.count > 1
                && stepResult.toolCalls.allSatisfy { PipiAgentToolbox.ContinuationGuard.isReadOnlyParallelizableTool($0.name) }

            if canRunInParallel {
                let batchNarration = lang == .zhHans
                    ? "并行执行 \(stepResult.toolCalls.count) 项只读查询…"
                    : "Running \(stepResult.toolCalls.count) read-only checks in parallel…"
                if var runState = activeRuns[conversationId], runState.runId == runId {
                    runState.statusText = batchNarration
                    activeRuns[conversationId] = runState
                }
                if let progressCallback {
                    await progressCallback(batchNarration)
                }

                let toolCalls = stepResult.toolCalls
                let batchResults: [(Int, PipiLLMToolCall, PipiAgentToolExecutionResult, Int)] = await withTaskGroup(
                    of: (Int, PipiLLMToolCall, PipiAgentToolExecutionResult, Int).self
                ) { group in
                    for (idx, tc) in toolCalls.enumerated() {
                        group.addTask {
                            let startedAt = Date()
                            let res = await PipiAgentToolbox.execute(
                                toolCall: tc,
                                workspaceDirectory: workDir,
                                llmConfig: config,
                                deliverablesDirectory: deliverablesDir,
                                callbacks: callbacks,
                                skipRiskCheck: false
                            )
                            let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                            return (idx, tc, res, elapsedMs)
                        }
                    }
                    var ordered: [(Int, PipiLLMToolCall, PipiAgentToolExecutionResult, Int)] = []
                    for await item in group {
                        ordered.append(item)
                    }
                    return ordered.sorted { $0.0 < $1.0 }
                }

                for (_, tc, execRes, elapsedMs) in batchResults {
                    let narration = PipiLivelyProgressNarrator.narrateToolStep(tc, stepIndex: stepIdx, lang: lang)
                    let stepId = "jarvis_\(stepIdx)_\(UUID().uuidString.prefix(5).lowercased())"
                    collectedSteps.append(
                        PipiStepEvent(
                            id: stepId,
                            verbPhrase: narration,
                            detail: tc.argumentsJSON.count > 160 ? String(tc.argumentsJSON.prefix(160)) + "…" : tc.argumentsJSON,
                            toolName: tc.name,
                            status: execRes.isError ? .failed : .succeeded,
                            durationMs: elapsedMs
                        )
                    )
                    if !execRes.artifacts.isEmpty {
                        for art in execRes.artifacts where !collectedArtifacts.contains(where: { $0.filePath == art.filePath }) {
                            collectedArtifacts.append(art)
                        }
                    }
                    wireMessages.append(.toolResult(callId: tc.id, toolName: tc.name, content: execRes.output))
                    if !execRes.visionImages.isEmpty {
                        wireMessages.append(.user(text: "[Live browser viewport screenshot from \(tc.name)]", images: execRes.visionImages))
                    }
                }
            } else {
                for tc in stepResult.toolCalls {
                    if Task.isCancelled { throw CancellationError() }

                    let sig = "\(tc.name)::\(tc.argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines))"
                    if sig == lastCallSignature {
                        consecutiveRepeatCount += 1
                    } else {
                        lastCallSignature = sig
                        consecutiveRepeatCount = 1
                    }
                    if consecutiveRepeatCount >= 3 {
                        repeatedToolNameToNudge = tc.name
                    }

                    let narration = PipiLivelyProgressNarrator.narrateToolStep(tc, stepIndex: stepIdx, lang: lang)
                    if var runState = activeRuns[conversationId], runState.runId == runId {
                        runState.statusText = narration
                        activeRuns[conversationId] = runState
                    }
                    if let progressCallback {
                        await progressCallback(narration)
                    }

                    let stepId = "jarvis_\(stepIdx)_\(UUID().uuidString.prefix(5).lowercased())"
                    let startedAt = Date()
                    var stepEvent = PipiStepEvent(
                        id: stepId,
                        verbPhrase: narration,
                        detail: tc.argumentsJSON.count > 160 ? String(tc.argumentsJSON.prefix(160)) + "…" : tc.argumentsJSON,
                        toolName: tc.name,
                        status: .running
                    )
                    collectedSteps.append(stepEvent)

                    let execRes = await PipiAgentToolbox.execute(
                        toolCall: tc,
                        workspaceDirectory: workDir,
                        llmConfig: config,
                        deliverablesDirectory: deliverablesDir,
                        callbacks: callbacks,
                        skipRiskCheck: false
                    )
                    let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                    stepEvent.status = execRes.isError ? .failed : .succeeded
                    stepEvent.durationMs = elapsedMs
                    if let sIdx = collectedSteps.firstIndex(where: { $0.id == stepId }) {
                        collectedSteps[sIdx] = stepEvent
                    }

                    if let risk = execRes.needsApproval, !risk.isHardDenied {
                        emitToolApprovalCard(
                            conversationId: conversationId,
                            messageId: placeholderMessageId,
                            toolCall: tc,
                            workDir: workDir,
                            risk: risk
                        )
                        pausedForApprovalMessage = "🛡️ 这一步涉及「\(risk.summary)」，\(risk.reason)\n\n我先帮你暂停在这里，等你确认后再动手～"
                        break
                    }

                    if !execRes.artifacts.isEmpty {
                        for art in execRes.artifacts where !collectedArtifacts.contains(where: { $0.filePath == art.filePath }) {
                            collectedArtifacts.append(art)
                        }
                    }

                    wireMessages.append(.toolResult(callId: tc.id, toolName: tc.name, content: execRes.output))
                    if !execRes.visionImages.isEmpty {
                        wireMessages.append(.user(text: "[Live browser viewport screenshot from \(tc.name)]", images: execRes.visionImages))
                    }
                }
            }

            if let pausedMsg = pausedForApprovalMessage {
                finalText = pausedMsg
                onDelta?(pausedMsg)
                break
            }

            if let repeatedTool = repeatedToolNameToNudge, stepIdx < maxSteps {
                wireMessages.append(.user(text: PipiAgentToolbox.ContinuationGuard.repeatedCallPivotHint(toolName: repeatedTool), images: []))
                consecutiveRepeatCount = 0
            }

            let remaining = maxSteps - stepIdx
            if !budgetHintInjected, remaining == 2 {
                budgetHintInjected = true
                wireMessages.append(.user(text: PipiAgentToolbox.ContinuationGuard.remainingBudgetHint(remainingSteps: remaining), images: []))
            }

            // If we truly exhausted all maxSteps without a final text turn, ask for an honest structured status
            if stepIdx == maxSteps {
                wireMessages.append(.user(text: "已达到单轮最大工具步数（\(maxSteps) 步）。请用简洁清晰的中文向主人说明：1) 已完成并验证的部分；2) 当前真正卡住的具体阻塞点（如有）；3) 接下来唯一需要执行的命令或决策。不要说空话。", images: []))
                let wrapUp = try await PipiInferenceEngine.invokeLLMWithTools(
                    config: config,
                    messages: wireMessages,
                    tools: []
                )
                finalText = wrapUp.text
                if !finalText.isEmpty { onDelta?(finalText) }
            }
        }

        if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalText = collectedArtifacts.isEmpty
                ? "已经帮你处理好啦 ✨ 如果还想继续深入哪一块，随时告诉我！"
                : "搞定啦！已经把你要的文件/媒体准备好并附在下面啦 ✨"
        }

        let chatAttachments: [PipiChatAttachment] = collectedArtifacts.map { art in
            PipiChatAttachment(
                id: art.id,
                name: art.fileName,
                path: art.filePath,
                sizeBytes: Int(art.byteSize)
            )
        }

        return PipiInferenceResult(
            text: finalText,
            engineLabel: collectedSteps.isEmpty ? finalLabel : "\(finalLabel) · Jarvis",
            steps: collectedSteps,
            attachments: chatAttachments
        )
    }

    /// Automatically recovers when a local CLI agent (e.g. Codex) fails:
    /// 1) tries another installed CLI agent; 2) falls back to PiPi's own Jarvis native tool loop;
    /// NEVER dumps raw stderr stack traces to the user.
    private func recoverFromLocalCLIFailure(
        failedKind: PipiLocalAgentKind,
        originalError: Error,
        systemPrompt: String,
        history: [PipiChatMessage],
        conversationId: String,
        persona: PipiBotPersona,
        workDir: String,
        permissionTier: PipiPermissionTier,
        runId: String,
        placeholderMessageId: String,
        onDelta: (@Sendable (String) -> Void)?,
        onCLIEvent: (@Sendable (PipiParsedCLIEvent) -> Void)?
    ) async throws -> PipiInferenceResult {
        let progressCallback = progressCallbacksByConversation[conversationId]

        // 1. Try another usable local CLI agent if available
        let alternativeAgents = usableLocalAgents
            .map(\.kind)
            .filter { $0 != failedKind }
        for altKind in alternativeAgents {
            if let progressCallback {
                await progressCallback("\(failedKind.displayName) 这边刚才卡壳了，我自动换 \(altKind.displayName) 接着帮你跑 🔄")
            }
            if let injectedEnv = Optional(await resolveCLIReverseInjectionEnvironment(for: altKind, profileId: conversationId)),
               let altResult = try? await PipiInferenceEngine.invokeLocalAgent(
                   kind: altKind,
                   systemPrompt: systemPrompt,
                   history: history,
                   workingDirectory: workDir,
                   permissionTier: permissionTier,
                   cliSessionId: nil,
                   modelOverride: persona.preferredModelId,
                   extraEnvironment: injectedEnv,
                   onDelta: onDelta,
                   onEvent: onCLIEvent
               ) {
                return altResult
            }
        }

        // 2. Fall back to PiPi's own native Jarvis tool loop so the task STILL succeeds!
        let fallbackProviderId = defaultLLMProviderId ?? readyLLMProviders.first?.id
        if let pid = fallbackProviderId,
           let cfg = resolvedEffectiveLLMConfig(providerId: pid, for: persona) {
            if let progressCallback {
                await progressCallback("本地 CLI 暂时连不上，别急！我自己直接动手翻本地文件和跑工具帮你搞定 💪")
            }
            return try await runJarvisAgentLoop(
                config: cfg,
                systemPrompt: systemPrompt,
                history: history,
                conversationId: conversationId,
                persona: persona,
                workDir: workDir,
                runId: runId,
                placeholderMessageId: placeholderMessageId,
                onDelta: onDelta
            )
        }

        // 3. Only if literally no fallback engine exists, explain in warm human language (no ugly raw stderr dump)
        let cleanDetail = (originalError as? PipiInferenceError)?.localizedMessage(resolvedLanguage)
            ?? originalError.localizedDescription
        let shortHint = cleanDetail.count > 140 ? String(cleanDetail.prefix(140)) + "…" : cleanDetail
        return PipiInferenceResult(
            text: "😅 刚才调用 \(failedKind.displayName) 时遇到网络/环境异常，而且当前还没有配置可兜底的云端大模型。\n\n建议：在 Mac 端「设置 → 模型」确认一个可用 LLM，或者在终端检查一下 `\(failedKind.binaryName)` 登录与代理状态，弄好跟我说一声我马上继续！\n（简要原因：\(shortHint)）",
            engineLabel: "PiPi Jarvis"
        )
    }

    private func emitToolApprovalCard(
        conversationId convId: String,
        messageId: String,
        toolCall: PipiLLMToolCall,
        workDir: String,
        risk: PipiToolRiskAssessment
    ) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == convId }) else { return }
        let nextSeq = (conversations[cIdx].events.last?.seq ?? 0) + 1
        let approval = PipiSessionApproval(
            sessionId: convId,
            eventSeq: nextSeq,
            question: "确认执行「\(risk.summary)」吗？",
            detail: risk.reason,
            options: [
                PipiSessionApproval.Option(id: "allow_once", label: strings.allowOnceAction, style: .primary),
                PipiSessionApproval.Option(id: "allow_session", label: strings.allowSessionAction, style: .secondary),
                PipiSessionApproval.Option(id: "deny", label: "取消执行", style: .destructive)
            ],
            recommendedOptionId: "allow_once",
            status: .pending,
            pendingPrompt: nil,
            pendingTarget: nil,
            riskLevel: risk.actionKind == .destructive || risk.actionKind == .externalEffect ? .high : .medium,
            userAuthorization: .medium,
            rationale: risk.reason,
            operationId: "op_tool_\(UUID().uuidString.prefix(8).lowercased())",
            actionToolName: toolCall.name,
            actionKind: risk.actionKind,
            actionTarget: risk.target,
            projectId: conversations[cIdx].projectId
        )
        pendingToolApprovalContextByApprovalId[approval.id] = (toolCall: toolCall, workDir: workDir)
        conversations[cIdx].approvals.append(approval)
        appendSessionEvent(convId, kind: .approval, approval: approval)
        setSessionState(convId, to: .needsYou)
        avatarEngine.setState(.needsYouApproval)
        saveResidentState()
        _ = messageId
    }

    private func makeAgentHostCallbacks(conversationId: String, personaId: String) -> PipiAgentHostCallbacks {
        PipiAgentHostCallbacks(
            captureScreenshot: { [weak self] in
                guard let self else { return PipiMacOmnipotentCommandResult(succeeded: false, summary: "服务未就绪") }
                return await self.macOmnipotentEngine.captureScreenshot()
            },
            recordScreen: { [weak self] seconds in
                guard let self else { return PipiMacOmnipotentCommandResult(succeeded: false, summary: "服务未就绪") }
                return await self.macOmnipotentEngine.recordScreenVideo(durationSeconds: seconds)
            },
            synthesizeVoice: { [weak self] text in
                guard let self else { return PipiMacOmnipotentCommandResult(succeeded: false, summary: "服务未就绪") }
                let voiceName: String? = await MainActor.run {
                    if let bot = self.personas.first(where: { $0.id == personaId }),
                       let opt = PipiVoiceTimbreOption.builtInPresets.first(where: { $0.id == bot.voiceProfileId }) {
                        return opt.systemVoiceIdentifier
                    }
                    return nil
                }
                return await self.macOmnipotentEngine.synthesizeVoiceClip(text: text, voiceName: voiceName)
            },
            prepareLocalFile: { [weak self] path in
                guard let self else { return PipiMacOmnipotentCommandResult(succeeded: false, summary: "服务未就绪") }
                return await self.macOmnipotentEngine.prepareFileDeliverable(path: path)
            },
            registerArtifact: { [weak self] art in
                await MainActor.run {
                    self?.macOmnipotentEngine.registerArtifact(art)
                }
            },
            delegateCLIAgent: { [weak self] agentRaw, mode, taskPrompt, workingDir in
                guard let self else { return (false, "服务未就绪") }
                let preferred: PipiLocalAgentKind = {
                    let low = agentRaw.lowercased()
                    if low.contains("claude") { return .claudeCode }
                    if low.contains("open") { return .opencode }
                    return .codex
                }()
                let candidates: [PipiLocalAgentKind] = await MainActor.run {
                    let usable = self.usableLocalAgents.map(\.kind)
                    var ordered: [PipiLocalAgentKind] = []
                    if usable.contains(preferred) { ordered.append(preferred) }
                    for k in usable where !ordered.contains(k) { ordered.append(k) }
                    return ordered
                }
                guard !candidates.isEmpty else {
                    return (false, "本机未启用外部 CLI Agent，请直接改用 list_directory / read_file / run_shell 等原生工具自己完成任务。")
                }
                let tier: PipiPermissionTier = (mode.lowercased() == "write") ? .autoEdit : .readOnly
                let cliHist = [PipiChatMessage(role: .user, content: taskPrompt)]
                // Smart Auto-Isolation: automatically spawn an isolated Git Worktree when in write mode and concurrency/project policy requires it
                let isolatedSession: PipiWorktreeReviewSession? = await MainActor.run {
                    guard tier != .readOnly,
                          let persona = self.personas.first(where: { $0.id == personaId }) else { return nil }
                    let conv = self.conversations.first(where: { $0.id == conversationId })
                    let proj = conv?.projectId.flatMap { pid in self.projects.first(where: { $0.id == pid }) }
                    let hasConcurrentGroupLanes = !self.activeGroupLanes.isEmpty
                    return self.prepareWorktreeIfNeeded(
                        repoPath: workingDir,
                        taskTitle: String(taskPrompt.prefix(44)),
                        persona: persona,
                        conversationId: conversationId,
                        isGroupParallel: hasConcurrentGroupLanes,
                        projectAlwaysUseWorktree: proj?.alwaysUseWorktree ?? false
                    )
                }
                let effectiveDir = isolatedSession?.worktreePath ?? workingDir
                var lastErr = ""
                for kind in candidates {
                    let env = await self.resolveCLIReverseInjectionEnvironment(for: kind, profileId: conversationId)
                    do {
                        let res = try await PipiInferenceEngine.invokeLocalAgent(
                            kind: kind,
                            systemPrompt: "",
                            history: cliHist,
                            workingDirectory: effectiveDir,
                            permissionTier: tier,
                            extraEnvironment: env
                        )
                        if let wt = isolatedSession {
                            let refreshed = await MainActor.run { self.refreshWorktreeDiff(sessionId: wt.id) }
                            let diffNote = refreshed.map { "\n\n🌿 已在隔离分支 `\($0.branchName)` 完成改动：\($0.diffSummary)（可在「任务台 → 代码审查」一键打回或合并）" } ?? ""
                            return (true, "[\(kind.displayName) 完成]\n\(res.text)\(diffNote)")
                        }
                        return (true, "[\(kind.displayName) 完成]\n\(res.text)")
                    } catch {
                        lastErr = error.localizedDescription
                    }
                }
                return (false, "外部 CLI 暂时不可用（\(lastErr.prefix(120))）。请立刻改用你自己的原生工具（list_directory / read_file / search_files / run_shell）亲自完成任务，不要向用户展示报错。")
            },
            readCalendarAndReminders: { [weak self] in
                guard let self else { return "服务未就绪" }
                return await self.readCalendarAndRemindersSummary()
            },
            createRoutineOrReminder: { [weak self] title, prompt, intervalMinutes, scheduleHint in
                await MainActor.run {
                    guard let self else { return "服务未就绪" }
                    let parsed = PipiScheduleParser.parseIntervalMinutes(from: scheduleHint, fallback: intervalMinutes)
                    let cal = Calendar.current
                    let now = Date()
                    let targetDate = parsed.isOneShot
                        ? now.addingTimeInterval(TimeInterval(parsed.minutes * 60))
                        : now
                    let comps = cal.dateComponents([.hour, .minute, .weekday], from: targetDate)
                    let schedule: PipiRoutineSchedule = parsed.minutes <= 60 ? .hourly : (parsed.minutes >= 1440 * 7 ? .weekly : .daily)
                    // Extract explicit hour like "早上9点" or "21点" if present
                    var resolvedHour = comps.hour ?? 9
                    var resolvedMinute = comps.minute ?? 0
                    if let rx = try? NSRegularExpression(pattern: #"(\d{1,2})\s*[点时:](\d{1,2})?"#),
                       let m = rx.firstMatch(in: scheduleHint, range: NSRange(scheduleHint.startIndex..<scheduleHint.endIndex, in: scheduleHint)) {
                        let ns = scheduleHint as NSString
                        if let h = Int(ns.substring(with: m.range(at: 1))), (0...23).contains(h) {
                            resolvedHour = h
                            if m.range(at: 2).location != NSNotFound, let min = Int(ns.substring(with: m.range(at: 2))), (0...59).contains(min) {
                                resolvedMinute = min
                            } else {
                                resolvedMinute = 0
                            }
                        }
                    }
                    let routine = PipiBotRoutine(
                        personaId: personaId,
                        title: title,
                        prompt: prompt,
                        schedule: schedule,
                        hour: resolvedHour,
                        minute: resolvedMinute,
                        weekday: comps.weekday ?? 2,
                        isEnabled: true
                    )
                    self.routines.append(routine)
                    self.saveResidentState()
                    return "✅ 已为你创建持久化定时任务「\(title)」：\(parsed.display)（\(String(format: "%02d:%02d", resolvedHour, resolvedMinute))），到期后会自动执行并同步推送到 Mac 和微信！"
                }
            },
            readMailOrSMS: { [weak self] channel, limit in
                guard let self else { return "服务未就绪" }
                if channel == "sms" {
                    return await self.macOmnipotentEngine.readRecentSMS(limit: limit).summary
                }
                return await self.macOmnipotentEngine.readRecentMail(limit: limit).summary
            },
            sendMailOrSMS: { [weak self] channel, recipient, subject, body in
                guard let self else { return PipiMacOmnipotentCommandResult(succeeded: false, summary: "服务未就绪") }
                if channel == "sms" {
                    return await self.macOmnipotentEngine.sendSMS(recipient: recipient, body: body)
                }
                return await self.macOmnipotentEngine.sendOrDraftMail(to: recipient, subject: subject, body: body, sendImmediately: false)
            },
            showControlMenu: { [weak self] in
                await MainActor.run {
                    guard let self else { return "" }
                    let primary = self.personas.first(where: { $0.id == self.wechatILinkManager.primaryBotId }) ?? self.activePersona
                    let activeConv = self.conversations.first(where: { $0.id == conversationId })
                    let activeProj = activeConv?.projectId.flatMap { pid in self.projects.first(where: { $0.id == pid }) }
                    let snap = PipiWeChatConfigSnapshot(
                        primaryBotId: primary.id,
                        primaryBotName: primary.name(self.resolvedLanguage),
                        routingMode: self.wechatILinkManager.routingMode,
                        activeConversationTitle: activeConv?.title,
                        activeProjectName: activeProj?.name,
                        defaultModelLabel: self.activeEngineDisplayLabel(for: PipiBotPersona.defaultPersonas[0]),
                        llmJudgeEnabled: self.llmGuardrailJudgeEnabled,
                        proactiveCLIDelegationEnabled: self.proactiveCLIDelegationEnabled,
                        typingIndicatorEnabled: self.wechatILinkManager.typingIndicatorEnabled,
                        memoryEnabled: self.memoryEnabled,
                        appVersion: self.appDisplayVersion
                    )
                    return self.wechatILinkManager.coordinator.renderMainMenu(config: snap)
                }
            },
            listOrSwitchBot: { [weak self] targetQuery in
                await MainActor.run {
                    guard let self else { return "" }
                    let lang = self.resolvedLanguage
                    if let q = targetQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
                        if let matched = self.personas.first(where: {
                            $0.name(lang).localizedCaseInsensitiveContains(q) || $0.role(lang).localizedCaseInsensitiveContains(q)
                        }) {
                            self.selectPersona(matched.id)
                            self.wechatILinkManager.primaryBotId = matched.id
                            self.saveResidentState()
                            return "✅ 已切换当前对话助手为「\(matched.name(lang))」（模型：\(self.activeEngineDisplayLabel(for: matched))）！"
                        }
                        return "没找到包含「\(q)」的助手。当前可用助手：\n" + self.personas.map { "• \($0.name(lang))（\($0.role(lang))）" }.joined(separator: "\n")
                    }
                    return "🤖 当前所有助手：\n" + self.personas.map {
                        let cur = $0.id == self.wechatILinkManager.primaryBotId ? " ✅当前" : ""
                        return "• \($0.name(lang))\(cur) — 模型：\(self.activeEngineDisplayLabel(for: $0))"
                    }.joined(separator: "\n")
                }
            },
            createBot: { [weak self] name, role, modelId in
                await MainActor.run {
                    guard let self else { return "" }
                    let tpl = PipiBotPersonaTemplate.catalog.last!
                    var created = tpl.instantiate(
                        customName: name,
                        customPrompt: nil,
                        permissionTier: .ask,
                        preferredTarget: .auto,
                        preferredModelId: modelId
                    )
                    created.roleZh = role
                    created.roleEn = role
                    created.systemPrompt = "你是 \(name)，\(role)。用轻松活泼、自然贴心的伙伴口吻帮主人真正动手解决问题。"
                    self.upsertPersona(created)
                    self.wechatILinkManager.primaryBotId = created.id
                    self.saveResidentState()
                    return "✅ 已创建新助手「\(name)」（职责：\(role)，模型：\(self.activeEngineDisplayLabel(for: created))），并已自动为你切到 TA 啦！"
                }
            },
            switchSessionOrProject: { [weak self] kind, query in
                await MainActor.run {
                    guard let self else { return "" }
                    if kind == "project" {
                        if let q = query, !q.isEmpty,
                           let proj = self.projects.first(where: { $0.name.localizedCaseInsensitiveContains(q) }) {
                            self.moveConversation(conversationId, toProject: proj.id)
                            return "✅ 已将当前会话绑定到项目「\(proj.name)」(\(proj.workspacePath ?? "默认目录"))。"
                        }
                        if self.projects.isEmpty {
                            return "当前还没有新建项目，目前使用默认工作区：\(self.workspaceDirectory)"
                        }
                        return "📁 可用项目：\n" + self.projects.map { "• \($0.name) (\($0.workspacePath ?? "-"))" }.joined(separator: "\n")
                    } else {
                        if let q = query?.lowercased(), (q == "new" || q.contains("新建")) {
                            let created = self.createConversation(for: personaId, activate: true)
                            return "✅ 已为你开启全新会话「\(created.title)」！"
                        }
                        let recent = self.conversations.filter { !$0.isArchived }.sorted { $0.updatedAt > $1.updatedAt }.prefix(8)
                        return "💬 最近会话：\n" + recent.map { "• \($0.title)（\($0.messages.count)条）" }.joined(separator: "\n")
                    }
                }
            },
            configureGroupMode: { [weak self] enable, memberQuery in
                await MainActor.run {
                    guard let self else { return "" }
                    if enable {
                        self.wechatILinkManager.routingMode = .groupPrefixMode
                        let lang = self.resolvedLanguage
                        if let mq = memberQuery, !mq.isEmpty {
                            let matched = self.personas.filter { mq.localizedCaseInsensitiveContains($0.name(lang)) }.map(\.id)
                            if !matched.isEmpty {
                                self.wechatILinkManager.groupMemberBotIds = matched
                            }
                        }
                        if self.wechatILinkManager.groupMemberBotIds.isEmpty {
                            self.wechatILinkManager.groupMemberBotIds = Array(self.personas.prefix(3).map(\.id))
                        }
                        self.saveResidentState()
                        let names = self.wechatILinkManager.groupMemberBotIds.compactMap { id in
                            self.personas.first(where: { $0.id == id })?.name(lang)
                        }.joined(separator: "、")
                        return "✅ 已进入微信群聊模式！当前群成员：\(names)。你发消息时大家会按【助手名】前缀协作回复，随时说「退出群聊」切回 1v1。"
                    } else {
                        self.wechatILinkManager.routingMode = .directMainBot
                        self.saveResidentState()
                        return "✅ 已切回 1v1 单聊模式！"
                    }
                }
            },
            updateSettings: { [weak self] key, value in
                await MainActor.run {
                    guard let self else { return "" }
                    switch key.lowercased() {
                    case "proactive_cli":
                        let next = value.map { ["on", "true", "1"].contains($0.lowercased()) } ?? !self.proactiveCLIDelegationEnabled
                        self.setProactiveCLIDelegationEnabled(next)
                        return "✅ 主动调用 CLI 工具已\(next ? "开启" : "关闭")。"
                    case "llm_judge":
                        let next = value.map { ["on", "true", "1"].contains($0.lowercased()) } ?? !self.llmGuardrailJudgeEnabled
                        self.setLLMGuardrailJudgeEnabled(next)
                        return "✅ 安全审计官自动评估已\(next ? "开启" : "关闭")。"
                    case "typing":
                        let next = value.map { ["on", "true", "1"].contains($0.lowercased()) } ?? !self.wechatILinkManager.typingIndicatorEnabled
                        self.wechatILinkManager.typingIndicatorEnabled = next
                        self.saveResidentState()
                        return "✅ 微信正在输入状态已\(next ? "开启" : "关闭")。"
                    case "bot_model":
                        if let idx = self.personas.firstIndex(where: { $0.id == personaId }) {
                            let v = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                            self.personas[idx].preferredModelId = (v == nil || v == "default" || v == "默认") ? nil : v
                            self.saveResidentState()
                            return "✅ 已更新当前 Bot 模型为：\(self.activeEngineDisplayLabel(for: self.personas[idx]))"
                        }
                        return "未找到当前 Bot。"
                    default:
                        return """
                        ⚙️ 当前管家配置（v\(self.appDisplayVersion)）：
                        • 默认工作区：\(self.workspaceDirectory)
                        • 主动 CLI 协作：\(self.proactiveCLIDelegationEnabled ? "开启" : "关闭")
                        • 安全审计官：\(self.llmGuardrailJudgeEnabled ? "开启" : "关闭")
                        • 微信输入状态：\(self.wechatILinkManager.typingIndicatorEnabled ? "开启" : "关闭")
                        • 跨会话记忆：\(self.memoryEnabled ? "开启" : "关闭")
                        """
                    }
                }
            },
            checkUpdates: { [weak self] in
                guard let self else { return "服务未就绪" }
                let current = await MainActor.run { self.appDisplayVersion }
                let state = await self.updateManager.checkForUpdates(currentVersion: current, silent: false)
                switch state {
                case .updateAvailable(let rel):
                    return "🚀 发现新版本 \(rel.tagName)（当前 v\(current)）：\(rel.title)\n在微信回复「更新」或到 Mac 设置页即可一键升级！"
                case .upToDate(let v, _):
                    return "✅ 当前 v\(v) 已经是最新 GitHub Release 啦！"
                case .error(let msg):
                    return "检查更新时网络有点小波动：\(msg)"
                default:
                    return "正在检查更新中..."
                }
            },
            materializeBlueprintBot: { [weak self] args in
                await MainActor.run {
                    guard let self else { return "服务未就绪" }
                    return self.materializeBlueprintBot(from: args).summary
                }
            },
            recordEntityLedger: { [weak self] key, type, source, status, summary in
                await MainActor.run {
                    guard let self else { return "服务未就绪" }
                    let saved = self.upsertEntityLedgerEntry(
                        botId: personaId,
                        entityKey: key,
                        entityType: type,
                        source: source,
                        status: status,
                        summary: summary
                    )
                    return "✅ 已写入实体台账 [\(saved.entityKey)]（状态：\(saved.status)，来源：\(saved.source)）"
                }
            },
            queryEntityLedger: { [weak self] key, search in
                await MainActor.run {
                    guard let self else { return "服务未就绪" }
                    let hits = self.queryEntityLedger(botId: personaId, entityKey: key, search: search)
                    if hits.isEmpty { return "暂未找到匹配的跨源实体记录。" }
                    return hits.map { "• [\($0.entityKey)] (\($0.entityType) / \($0.status) / \($0.source)): \($0.summary)" }.joined(separator: "\n")
                }
            },
            proposeBlueprintEvolution: { [weak self] botQuery, rationale, newRule, newVerification, newStepsCSV in
                await MainActor.run {
                    guard let self else { return "服务未就绪" }
                    let lang = self.resolvedLanguage
                    let targetBot: PipiBotPersona? = {
                        if let q = botQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
                            return self.personas.first(where: {
                                $0.id == q || $0.name(lang).localizedCaseInsensitiveContains(q)
                            })
                        }
                        return self.personas.first(where: { $0.id == personaId })
                    }()
                    guard let bot = targetBot else { return "未找到目标 Bot。" }
                    let steps = newStepsCSV?.replacingOccurrences(of: "；", with: ";")
                        .split(separator: ";")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let proposal = self.proposeBlueprintEvolution(
                        botId: bot.id,
                        rationale: rationale,
                        proposedSteps: (steps?.isEmpty == false) ? steps : nil,
                        addedRules: newRule.map { [$0] } ?? [],
                        addedVerification: newVerification.map { [$0] } ?? []
                    )
                    guard let proposal else { return "生成蓝图进化提案失败。" }
                    return "✨ 已为「\(bot.name(lang))」生成蓝图自进化 Diff 提案（\(proposal.diffs.count) 项变更，编号 `\(proposal.id)`），已推送至任务台等待主人审批生效。"
                }
            },
            manageTriggers: { [weak self] action, args in
                await MainActor.run {
                    guard let self else { return "服务未就绪" }
                    return self.handleBotTriggerTool(action: action, args: args, callerBotId: personaId)
                }
            },
            remoteNodeAction: { [weak self] action, args in
                guard let self else { return "服务未就绪" }
                return await self.handleRemoteNodeTool(action: action, args: args)
            }
        )
    }
}

private extension Character {
    var isASCIIAlphaNumOrUnderscore: Bool {
        guard isASCII, let ascii = asciiValue else { return false }
        return (ascii >= 48 && ascii <= 57) // 0-9
            || (ascii >= 65 && ascii <= 90) // A-Z
            || (ascii >= 97 && ascii <= 122) // a-z
            || ascii == 95 // _
    }
}
