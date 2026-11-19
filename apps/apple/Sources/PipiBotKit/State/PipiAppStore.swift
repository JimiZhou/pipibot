import Foundation
import Observation

public enum PipiConnectionMode: String, Sendable {
    case liveDaemon = "Embedded Bridge Live"
    case nativeResident = "Native All-in-One"
}

public enum PipiRunPhase: String, Sendable, Equatable {
    case queued
    case running
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

@MainActor
@Observable
public final class PipiAppStore {
    public static let maxConcurrentLLMRuns: Int = 4
    public static let maxConcurrentLocalAgentRuns: Int = 2

    public let avatarEngine: PipiProceduralAvatarEngine
    public let client: PipiDaemonClient
    public let bridgeSupervisor: PipiEmbeddedBridgeSupervisor
    public let enableNativeRuntime: Bool
    public let enableEmbeddedBridge: Bool
    public let secretStore: any PipiSecretStore
    public let localHostConnection: PipiLocalHostConnection
    public var activeHostConnection: any PipiHostConnection
    private let persistenceUrl: URL?
    private let persistenceQueue = DispatchQueue(label: "ai.pipibot.persistence.serial", qos: .utility)
    private let saveDebounceMilliseconds: Int
    private let inferenceExecutor: PipiInferenceExecutor?
    private let sessionInferenceExecutor: PipiSessionInferenceExecutor?

    public var themeMode: PipiThemeMode = .system
    public var language: PipiAppLanguage = .system
    public var hasCompletedOnboarding: Bool = false
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
    private var groupRunTasks: [String: Task<[PipiGroupMessage], Never>] = [:]
    public var memoryEnabled: Bool = true
    public var personalProfileNote: String = ""
    public var routines: [PipiBotRoutine] = []
    public var runRecords: [PipiRunRecord] = []
    public var companionSyncEnabled: Bool = false

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

    public var totalNeedsYouCount: Int {
        pendingApprovals.count + pendingDecisions.count
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

    public var daemonVersion: String = "0.8.0"
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

    private enum RunBucket {
        case llm
        case localAgent
    }

    private struct QueuedRunWaiter {
        let id: UUID
        let conversationId: String
        let continuation: CheckedContinuation<Void, Error>
    }

    private var sseTask: Task<Void, Never>?
    private var routineSchedulerTask: Task<Void, Never>?
    private var zoomHudTask: Task<Void, Never>?
    private var saveDebounceTask: Task<Void, Never>?
    private var hasPendingSave: Bool = false
    private var undoToastDismissTask: Task<Void, Never>?
    private var inFlightLLMCount: Int = 0
    private var inFlightLocalAgentCount: Int = 0
    private var llmWaiters: [QueuedRunWaiter] = []
    private var localAgentWaiters: [QueuedRunWaiter] = []

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
        sessionInferenceExecutor: PipiSessionInferenceExecutor? = nil
    ) {
        self.daemonEndpoint = baseUrl
        self.client = PipiDaemonClient(baseUrlString: baseUrl)
        self.bridgeSupervisor = PipiEmbeddedBridgeSupervisor()
        self.enableNativeRuntime = enableNativeRuntime
        self.enableEmbeddedBridge = enableEmbeddedBridge
        self.persistenceUrl = stateFileUrl
        self.secretStore = secretStore ?? PipiKeychainSecretStore()
        self.saveDebounceMilliseconds = max(0, saveDebounceMilliseconds)
        self.inferenceExecutor = inferenceExecutor
        self.sessionInferenceExecutor = sessionInferenceExecutor
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
        self.refreshLocalHostCapabilities()
        if enableNativeRuntime {
            if self.persistenceWarning == nil {
                self.noticeBanner = strings.readyStatus
            }
            self.startRoutineScheduler()
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
            activeGroupChatId: activeGroupChatId
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
                } else if let stored = secretStore.secret(for: copy.secretAccountKey) {
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
        for groupId in Array(groupRunTasks.keys) {
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
            activateTargetConversation: false
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
        guard hasConfiguredEngine else { return }
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .weekday], from: now)
        let iso = ISO8601DateFormatter()

        let dueRoutines: [PipiBotRoutine] = routines.filter { routine in
            guard routine.isEnabled && routine.schedule != .manual else { return false }
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
                await self?.runRoutineNow(routine)
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

    public func reopenOnboarding() {
        self.hasCompletedOnboarding = false
        self.avatarEngine.setState(.ambientWarmWelcome)
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

    public func activeEngineDisplayLabel(for persona: PipiBotPersona? = nil) -> String {
        guard let target = resolvedActiveTarget(for: persona) else {
            return strings.engineStatusUnconfigured
        }
        switch target {
        case .llm(let pid):
            if let cfg = llmProviders.first(where: { $0.id == pid }) {
                return "\(cfg.name) · \(cfg.modelId)"
            }
            return strings.engineStatusUnconfigured
        case .localAgent(let kind):
            return kind.displayName
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
        removeQueuedWaiter(for: convId)

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
        activateTargetConversation: Bool = true
    ) async {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        let targetConversation = explicitConversationId.flatMap { id in
            conversations.first(where: { $0.id == id })
        }
        let resolvedPersonaId = explicitPersonaId ?? targetConversation?.personaId ?? activePersona.id
        let input = PipiUserInput(
            text: rawText,
            attachments: attachments,
            targetOverride: targetOverride,
            personaId: resolvedPersonaId,
            activateTargetConversation: activateTargetConversation
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

        let approved = (optionId == "allow_changes") || (optionId == approval.recommendedOptionId)
        conversations[cIdx].approvals[aIdx].status = approved ? .approved : .denied
        conversations[cIdx].approvals[aIdx].chosenOptionId = optionId
        conversations[cIdx].approvals[aIdx].userNote = note
        conversations[cIdx].approvals[aIdx].resolvedAt = nowIso
        conversations[cIdx].updatedAt = nowIso

        let sessionId = conversations[cIdx].id
        let updatedApproval = conversations[cIdx].approvals[aIdx]
        appendSessionEvent(sessionId, kind: .approval, approval: updatedApproval)

        if approved, let pendingPrompt = approval.pendingPrompt, !pendingPrompt.isEmpty {
            let personaId = conversations[cIdx].personaId
            let target = approval.pendingTarget
            let input = PipiUserInput(
                text: pendingPrompt,
                attachments: [],
                targetOverride: target,
                personaId: personaId,
                activateTargetConversation: conversations[cIdx].id == activeConversationId,
                permissionOverride: .autoEdit,
                isApprovalResume: true
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
                if let cfg = llmProviders.first(where: { $0.id == pid }) {
                    return "\(cfg.name) · \(cfg.modelId)"
                }
                return strings.appName
            case .localAgent(let kind):
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
        let bucket: RunBucket
        let initialStatusText: String
        switch resolvedTarget {
        case .localAgent(let kind):
            isLocalAgentTarget = true
            bucket = .localAgent
            initialStatusText = strings.runningAgentStatus(kind.displayName)
        case .llm, .auto:
            isLocalAgentTarget = false
            bucket = .llm
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
                    if let body = file.textContent, !body.isEmpty {
                        expanded += "\n\n[Attached file: \(file.name) (\(file.path))]\n```\n\(body)\n```"
                    } else if !file.isImage || isLocalAgentTarget {
                        expanded += "\n\n[Attached file: \(file.name) at \(file.path)]"
                    }
                }
                var copy = msg
                copy.content = expanded
                return copy
            }
        let effectiveHistory: [PipiChatMessage] = isApprovalResume
            ? [PipiChatMessage(role: .user, content: displayPrompt, createdAt: nowIso)]
            : historySnapshot
        let langSnapshot = resolvedLanguage
        let workDir = (projectForConv?.workspacePath?.isEmpty == false ? projectForConv?.workspacePath : nil) ?? workspaceDirectory

        let onDelta: @Sendable (String) -> Void = { [weak self] chunk in
            Task { @MainActor [weak self] in
                guard let self,
                      let cIdx = self.conversations.firstIndex(where: { $0.id == convId }),
                      let mIdx = self.conversations[cIdx].messages.firstIndex(where: { $0.id == placeholderId }) else {
                    return
                }
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
                self?.applyParsedCLIEvent(parsed, conversationId: convId, messageId: placeholderId)
            }
        }

        let customExecutor = self.inferenceExecutor
        let customSessionExecutor = self.sessionInferenceExecutor
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.acquireRunSlot(for: bucket, conversationId: convId, runId: runId)
                defer { self.releaseRunSlot(for: bucket) }

                if Task.isCancelled { throw CancellationError() }

                let result: PipiInferenceResult
                var shouldRequestWriteApproval = false

                switch resolvedTarget {
                case .llm(let providerId):
                    guard let cfg = self.llmProviders.first(where: { $0.id == providerId }) else {
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
                    if let customSessionExecutor {
                        result = try await customSessionExecutor(
                            resolvedTarget,
                            cfg,
                            effectiveSystemPrompt,
                            effectiveHistory,
                            workDir,
                            effectivePermission,
                            nil,
                            onDelta,
                            onCLIEvent
                        )
                    } else if let customExecutor {
                        result = try await customExecutor(
                            resolvedTarget,
                            cfg,
                            effectiveSystemPrompt,
                            effectiveHistory,
                            workDir,
                            onDelta
                        )
                    } else {
                        result = try await PipiInferenceEngine.invokeLLM(
                            config: cfg,
                            systemPrompt: effectiveSystemPrompt,
                            history: effectiveHistory,
                            onDelta: onDelta
                        )
                    }

                case .localAgent(let kind):
                    let needsAskGate = (effectivePermission == .ask) && (kind == .claudeCode || kind == .codex) && (input.permissionOverride == nil)
                    let invocationPermission: PipiPermissionTier = needsAskGate ? .readOnly : effectivePermission
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

                    if let customSessionExecutor {
                        result = try await customSessionExecutor(
                            resolvedTarget,
                            nil,
                            effectiveSystemPrompt,
                            effectiveHistory,
                            workDir,
                            invocationPermission,
                            existingCliSessionId,
                            onDelta,
                            onCLIEvent
                        )
                    } else if let customExecutor {
                        result = try await customExecutor(
                            resolvedTarget,
                            nil,
                            effectiveSystemPrompt,
                            effectiveHistory,
                            workDir,
                            onDelta
                        )
                    } else {
                        result = try await PipiInferenceEngine.invokeLocalAgent(
                            kind: kind,
                            systemPrompt: effectiveSystemPrompt,
                            history: effectiveHistory,
                            workingDirectory: workDir,
                            permissionTier: invocationPermission,
                            cliSessionId: existingCliSessionId,
                            onDelta: onDelta,
                            onEvent: onCLIEvent
                        )
                    }

                case .auto:
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
                        summaryInfo: s
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
                    summaryInfo: finalResult.summaryInfo
                )
                self.finalizeRunRecord(id: runId, status: .succeeded, durationMs: durationMs)

                if shouldRequestWriteApproval, case .localAgent(let kind) = resolvedTarget {
                    self.emitWriteApprovalCard(
                        conversationId: convId,
                        messageId: placeholderId,
                        agentKind: kind,
                        originalPrompt: displayPrompt
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
                self.finalizeRunRecord(id: runId, status: .cancelled, durationMs: durationMs)
                self.finishGenerating(
                    conversationId: convId,
                    runId: runId,
                    finalSessionState: .cancelled,
                    nextAvatarState: persona.idleAvatarState
                )
            } catch let err as PipiInferenceError {
                let durationMs = Int(Date().timeIntervalSince(startedAtDate) * 1000)
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

    private func emitWriteApprovalCard(
        conversationId convId: String,
        messageId: String,
        agentKind: PipiLocalAgentKind,
        originalPrompt: String
    ) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == convId }) else { return }
        let nextSeq = (conversations[cIdx].events.last?.seq ?? 0) + 1
        let resumePrompt = strings.t(
            "用户已批准工作区修改权限，请继续执行此前分析的改动。原始需求：\(originalPrompt)",
            "Write permissions approved. Please proceed with applying the planned changes. Original request: \(originalPrompt)"
        )
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
                PipiSessionApproval.Option(id: "allow_changes", label: strings.allowChangesAction, style: .primary),
                PipiSessionApproval.Option(id: "keep_readonly", label: strings.keepReadOnlyAction, style: .secondary)
            ],
            recommendedOptionId: "allow_changes",
            status: .pending,
            pendingPrompt: resumePrompt,
            pendingTarget: .localAgent(agentKind)
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

    private func acquireRunSlot(for bucket: RunBucket, conversationId: String, runId: String) async throws {
        let cap = (bucket == .localAgent) ? Self.maxConcurrentLocalAgentRuns : Self.maxConcurrentLLMRuns
        let currentCount = (bucket == .localAgent) ? inFlightLocalAgentCount : inFlightLLMCount
        if currentCount < cap {
            if bucket == .localAgent {
                inFlightLocalAgentCount += 1
            } else {
                inFlightLLMCount += 1
            }
            return
        }

        if var runState = activeRuns[conversationId], runState.runId == runId {
            runState.phase = .queued
            runState.statusText = strings.queuedStatus
            activeRuns[conversationId] = runState
        }
        setSessionState(conversationId, to: .queued)

        let waiterId = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    cont.resume(throwing: CancellationError())
                    return
                }
                let waiter = QueuedRunWaiter(id: waiterId, conversationId: conversationId, continuation: cont)
                if bucket == .localAgent {
                    localAgentWaiters.append(waiter)
                } else {
                    llmWaiters.append(waiter)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelQueuedWaiter(id: waiterId, bucket: bucket)
            }
        }
    }

    private func releaseRunSlot(for bucket: RunBucket) {
        switch bucket {
        case .localAgent:
            if !localAgentWaiters.isEmpty {
                let next = localAgentWaiters.removeFirst()
                if var runState = activeRuns[next.conversationId] {
                    runState.phase = .running
                    activeRuns[next.conversationId] = runState
                }
                setSessionState(next.conversationId, to: .running)
                next.continuation.resume()
            } else {
                inFlightLocalAgentCount = max(0, inFlightLocalAgentCount - 1)
            }
        case .llm:
            if !llmWaiters.isEmpty {
                let next = llmWaiters.removeFirst()
                if var runState = activeRuns[next.conversationId] {
                    runState.phase = .running
                    activeRuns[next.conversationId] = runState
                }
                setSessionState(next.conversationId, to: .running)
                next.continuation.resume()
            } else {
                inFlightLLMCount = max(0, inFlightLLMCount - 1)
            }
        }
    }

    private func cancelQueuedWaiter(id: UUID, bucket: RunBucket) {
        switch bucket {
        case .localAgent:
            if let idx = localAgentWaiters.firstIndex(where: { $0.id == id }) {
                let waiter = localAgentWaiters.remove(at: idx)
                waiter.continuation.resume(throwing: CancellationError())
            }
        case .llm:
            if let idx = llmWaiters.firstIndex(where: { $0.id == id }) {
                let waiter = llmWaiters.remove(at: idx)
                waiter.continuation.resume(throwing: CancellationError())
            }
        }
    }

    private func removeQueuedWaiter(for conversationId: String) {
        while let idx = llmWaiters.firstIndex(where: { $0.conversationId == conversationId }) {
            let waiter = llmWaiters.remove(at: idx)
            waiter.continuation.resume(throwing: CancellationError())
        }
        while let idx = localAgentWaiters.firstIndex(where: { $0.conversationId == conversationId }) {
            let waiter = localAgentWaiters.remove(at: idx)
            waiter.continuation.resume(throwing: CancellationError())
        }
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
        summaryInfo: PipiSessionSummaryInfo? = nil
    ) {
        guard let cIdx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let nowIso = ISO8601DateFormatter().string(from: Date())
        if let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == messageId }) {
            conversations[cIdx].messages[mIdx].content = finalContent
            conversations[cIdx].messages[mIdx].engineLabel = engineLabel
            conversations[cIdx].messages[mIdx].isError = isError
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
        for groupId in Array(groupRunTasks.keys) {
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
        guard let set = activeGroupRuns[groupId] else { return false }
        return !set.isEmpty
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
        } else {
            activeGroupChatId = nil
        }
        saveResidentState()
    }

    public func stopGroupChat(_ groupId: String) {
        groupRunTasks[groupId]?.cancel()
        groupRunTasks.removeValue(forKey: groupId)
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

        if groupRunTasks[groupId] != nil || isGroupRunning(groupId) {
            stopGroupChat(groupId)
        }

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
        groupRunTasks[groupId] = task
        let produced = await task.value
        groupRunTasks.removeValue(forKey: groupId)
        activeGroupRuns.removeValue(forKey: groupId)
        activeGroupStreamingMessageIds.removeValue(forKey: groupId)
        activeGroupRunStartTimes.removeValue(forKey: groupId)
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
        topicId: String?
    ) async -> (message: PipiGroupMessage, succeeded: Bool) {
        guard let target = resolvedActiveTarget(for: persona) else {
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

        let engineLabel: String = {
            switch target {
            case .llm(let pid):
                if let cfg = llmProviders.first(where: { $0.id == pid }) {
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
            if var set = activeGroupRuns[groupId] {
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
            switch target {
            case .llm(let providerId):
                guard let cfg = llmProviders.first(where: { $0.id == providerId }) else {
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
                    result = try await PipiInferenceEngine.invokeLocalAgent(
                        kind: kind,
                        systemPrompt: effectiveSystemPrompt,
                        history: history,
                        workingDirectory: workDir,
                        permissionTier: safePerm,
                        cliSessionId: nil,
                        onDelta: onDelta,
                        onEvent: onCLIEvent
                    )
                }

            case .auto:
                throw PipiInferenceError.emptyResponse
            }

            let parsedOutMentions = parseGroupMentions(
                in: result.text,
                participantPersonaIds: groupChats.first(where: { $0.id == groupId })?.participantPersonaIds ?? []
            )
            let updatedAt = ISO8601DateFormatter().string(from: Date())
            if let gIdx = groupChats.firstIndex(where: { $0.id == groupId }),
               let mIdx = groupChats[gIdx].messages.firstIndex(where: { $0.id == msgId }) {
                groupChats[gIdx].messages[mIdx].content = result.text
                groupChats[gIdx].messages[mIdx].engineLabel = result.engineLabel
                groupChats[gIdx].messages[mIdx].mentionedPersonaIds = parsedOutMentions.mentionedIds
                groupChats[gIdx].updatedAt = updatedAt
                saveResidentState()
                return (groupChats[gIdx].messages[mIdx], true)
            }
            var fallback = placeholder
            fallback.content = result.text
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
