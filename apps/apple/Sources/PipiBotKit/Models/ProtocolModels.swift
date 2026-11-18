import Foundation

// MARK: - 1. Harness & Inference Routing

public enum HarnessProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case pi
    case claudeCode = "claude-code"
    case codex
    case opencode
    case byok

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pi: return "Pi Native"
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex CLI"
        case .opencode: return "OpenCode ACP"
        case .byok: return "BYOK pi-ai"
        }
    }

    public var shortLabel: String {
        switch self {
        case .pi: return "Pi"
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        case .byok: return "BYOK"
        }
    }
}

public enum HarnessExecutionPhase: String, Codable, Sendable, CaseIterable {
    case initializing
    case recallingMemory = "recalling_memory"
    case streamingModel = "streaming_model"
    case executingTool = "executing_tool"
    case awaitingMcpRelay = "awaiting_mcp_relay"
    case awaitingHuman = "awaiting_human"
    case reflecting
    case completed
    case failed
    case aborted
}

public struct HarnessActivityPulse: Codable, Sendable, Equatable {
    public let sessionId: String
    public let subSessionId: String?
    public let provider: HarnessProvider
    public let modelId: String?
    public let phase: HarnessExecutionPhase
    public let pulseIntervalMs: Int
    public let seq: Int
    public let elapsedMs: Int
    public let activeToolName: String?
    public let tokensEstimated: Int
    public let suggestedAvatarState: AvatarState53
    public let timestamp: String

    public init(
        sessionId: String,
        subSessionId: String? = nil,
        provider: HarnessProvider,
        modelId: String? = nil,
        phase: HarnessExecutionPhase,
        pulseIntervalMs: Int = 250,
        seq: Int,
        elapsedMs: Int,
        activeToolName: String? = nil,
        tokensEstimated: Int,
        suggestedAvatarState: AvatarState53,
        timestamp: String
    ) {
        self.sessionId = sessionId
        self.subSessionId = subSessionId
        self.provider = provider
        self.modelId = modelId
        self.phase = phase
        self.pulseIntervalMs = pulseIntervalMs
        self.seq = seq
        self.elapsedMs = elapsedMs
        self.activeToolName = activeToolName
        self.tokensEstimated = tokensEstimated
        self.suggestedAvatarState = suggestedAvatarState
        self.timestamp = timestamp
    }
}

public struct HarnessProbeResult: Codable, Sendable, Identifiable, Equatable {
    public var id: String { provider.rawValue }
    public let provider: HarnessProvider
    public let installed: Bool
    public let authenticated: Bool
    public let binaryPath: String?
    public let version: String?
    public let authSource: String?
    public let supportsMcp: Bool
    public let checkedAt: String

    public init(
        provider: HarnessProvider,
        installed: Bool,
        authenticated: Bool,
        binaryPath: String? = nil,
        version: String? = nil,
        authSource: String? = nil,
        supportsMcp: Bool,
        checkedAt: String
    ) {
        self.provider = provider
        self.installed = installed
        self.authenticated = authenticated
        self.binaryPath = binaryPath
        self.version = version
        self.authSource = authSource
        self.supportsMcp = supportsMcp
        self.checkedAt = checkedAt
    }
}

// MARK: - 2. Devin-Style Outcome Ownership, Sub-Sessions & Needs You

public enum OutcomeDomain: String, Codable, Sendable, CaseIterable, Identifiable {
    case dev
    case work
    case dailyLife = "daily_life"
    case infra

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dev: return "Engineering"
        case .work: return "Work"
        case .dailyLife: return "Daily Life"
        case .infra: return "Infra Fleet"
        }
    }
}

public enum OutcomeTriggerKind: String, Codable, Sendable, CaseIterable {
    case cron
    case webhook
    case filesystemWatch = "filesystem_watch"
    case telemetryThreshold = "telemetry_threshold"
    case cueAction = "cue_action"
    case manual
}

public struct OutcomeTriggerSpec: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let kind: OutcomeTriggerKind
    public let expression: String
    public let nodeTarget: String?
    public var enabled: Bool

    public init(
        id: String,
        kind: OutcomeTriggerKind,
        expression: String,
        nodeTarget: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.expression = expression
        self.nodeTarget = nodeTarget
        self.enabled = enabled
    }
}

public enum OutcomeStatus: String, Codable, Sendable, CaseIterable {
    case active
    case evaluating
    case delegating
    case needsYou = "needs_you"
    case paused
    case achieved
    case failed

    public var displayLabel: String {
        switch self {
        case .active: return "Active"
        case .evaluating: return "Evaluating"
        case .delegating: return "Delegating"
        case .needsYou: return "Needs You"
        case .paused: return "Paused"
        case .achieved: return "Achieved"
        case .failed: return "Failed"
        }
    }
}

public struct OutcomeResponsibility: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public var title: String
    public var domain: OutcomeDomain
    public var goal: String
    public var constraints: [String]
    public var successMetrics: [String]
    public var triggers: [OutcomeTriggerSpec]
    public var preferredHarness: HarnessProvider
    public var fallbackHarnesses: [HarnessProvider]
    public var targetNodeId: String?
    public var status: OutcomeStatus
    public var maxSubSessions: Int
    public var dailyBudgetUsd: Double
    public var spentTodayUsd: Double
    public var lastEvaluatedAt: String?
    public var lastEvidenceArtifactIds: [String]
    public let createdAt: String
    public var updatedAt: String

    public init(
        id: String,
        title: String,
        domain: OutcomeDomain,
        goal: String,
        constraints: [String],
        successMetrics: [String],
        triggers: [OutcomeTriggerSpec],
        preferredHarness: HarnessProvider,
        fallbackHarnesses: [HarnessProvider] = [.pi],
        targetNodeId: String? = nil,
        status: OutcomeStatus = .active,
        maxSubSessions: Int = 3,
        dailyBudgetUsd: Double = 2.0,
        spentTodayUsd: Double = 0.0,
        lastEvaluatedAt: String? = nil,
        lastEvidenceArtifactIds: [String] = [],
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.title = title
        self.domain = domain
        self.goal = goal
        self.constraints = constraints
        self.successMetrics = successMetrics
        self.triggers = triggers
        self.preferredHarness = preferredHarness
        self.fallbackHarnesses = fallbackHarnesses
        self.targetNodeId = targetNodeId
        self.status = status
        self.maxSubSessions = maxSubSessions
        self.dailyBudgetUsd = dailyBudgetUsd
        self.spentTodayUsd = spentTodayUsd
        self.lastEvaluatedAt = lastEvaluatedAt
        self.lastEvidenceArtifactIds = lastEvidenceArtifactIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum SubSessionStatus: String, Codable, Sendable, CaseIterable {
    case queued
    case running
    case waitingTool = "waiting_tool"
    case needsYou = "needs_you"
    case succeeded
    case failed
    case cancelled
}

public struct SubSession: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let parentOutcomeId: String?
    public let parentSessionId: String?
    public let role: String
    public let objective: String
    public let provider: HarnessProvider
    public let modelId: String
    public let nodeId: String
    public let worktreePath: String?
    public let branchName: String?
    public var status: SubSessionStatus
    public var lastPulseAt: String?
    public var artifactIds: [String]
    public var summary: String?
    public let startedAt: String
    public var completedAt: String?

    public init(
        id: String,
        parentOutcomeId: String? = nil,
        parentSessionId: String? = nil,
        role: String,
        objective: String,
        provider: HarnessProvider,
        modelId: String,
        nodeId: String,
        worktreePath: String? = nil,
        branchName: String? = nil,
        status: SubSessionStatus,
        lastPulseAt: String? = nil,
        artifactIds: [String] = [],
        summary: String? = nil,
        startedAt: String,
        completedAt: String? = nil
    ) {
        self.id = id
        self.parentOutcomeId = parentOutcomeId
        self.parentSessionId = parentSessionId
        self.role = role
        self.objective = objective
        self.provider = provider
        self.modelId = modelId
        self.nodeId = nodeId
        self.worktreePath = worktreePath
        self.branchName = branchName
        self.status = status
        self.lastPulseAt = lastPulseAt
        self.artifactIds = artifactIds
        self.summary = summary
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

public enum DecisionSeverity: String, Codable, Sendable, CaseIterable {
    case info
    case warning
    case critical
}

public enum DecisionCategory: String, Codable, Sendable, CaseIterable {
    case codeMergeOrPush = "code_merge_or_push"
    case infraMutation = "infra_mutation"
    case financialOrPurchase = "financial_or_purchase"
    case externalCommunication = "external_communication"
    case memoryEvolutionReview = "memory_evolution_review"
    case ambiguousRequirement = "ambiguous_requirement"

    public var displayName: String {
        switch self {
        case .codeMergeOrPush: return "PR & Merge"
        case .infraMutation: return "Infra Change"
        case .financialOrPurchase: return "Purchase"
        case .externalCommunication: return "External Send"
        case .memoryEvolutionReview: return "Soul Diff"
        case .ambiguousRequirement: return "Clarification"
        }
    }
}

public struct DecisionOption: Codable, Sendable, Identifiable, Equatable {
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

public struct ArtifactEvidenceRef: Codable, Sendable, Identifiable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case screenshot
        case video
        case diffPatch = "diff_patch"
        case htmlPreview = "html_preview"
        case logExcerpt = "log_excerpt"

        public var label: String {
            switch self {
            case .screenshot: return "Screenshot"
            case .video: return "Before/After Video"
            case .diffPatch: return "Git Diff"
            case .htmlPreview: return "HTML Preview"
            case .logExcerpt: return "Log Excerpt"
            }
        }
    }

    public var id: String { artifactId }
    public let artifactId: String
    public let r2Key: String
    public let kind: Kind
    public let caption: String
    public let signedUrl: String?
    public let expiresAt: String?

    public init(
        artifactId: String,
        r2Key: String,
        kind: Kind,
        caption: String,
        signedUrl: String? = nil,
        expiresAt: String? = nil
    ) {
        self.artifactId = artifactId
        self.r2Key = r2Key
        self.kind = kind
        self.caption = caption
        self.signedUrl = signedUrl
        self.expiresAt = expiresAt
    }
}

public struct NeedsYouDecision: Codable, Sendable, Identifiable, Equatable {
    public enum Status: String, Codable, Sendable {
        case pending
        case resolved
        case expired
    }

    public enum FallbackAction: String, Codable, Sendable {
        case pause
        case abort
        case autoRecommended = "auto_recommended"
    }

    public let id: String
    public let outcomeId: String?
    public let sessionId: String
    public let sourceNodeId: String
    public let severity: DecisionSeverity
    public let category: DecisionCategory
    public let title: String
    public let summary: String
    public let recommendedOptionId: String
    public let options: [DecisionOption]
    public let evidence: [ArtifactEvidenceRef]
    public let timeoutSeconds: Int?
    public let fallbackAction: FallbackAction?
    public var status: Status
    public var chosenOptionId: String?
    public var userNote: String?
    public var resolvedBy: String?
    public let createdAt: String
    public var resolvedAt: String?

    public init(
        id: String,
        outcomeId: String? = nil,
        sessionId: String,
        sourceNodeId: String,
        severity: DecisionSeverity,
        category: DecisionCategory,
        title: String,
        summary: String,
        recommendedOptionId: String,
        options: [DecisionOption],
        evidence: [ArtifactEvidenceRef] = [],
        timeoutSeconds: Int? = nil,
        fallbackAction: FallbackAction? = nil,
        status: Status = .pending,
        chosenOptionId: String? = nil,
        userNote: String? = nil,
        resolvedBy: String? = nil,
        createdAt: String,
        resolvedAt: String? = nil
    ) {
        self.id = id
        self.outcomeId = outcomeId
        self.sessionId = sessionId
        self.sourceNodeId = sourceNodeId
        self.severity = severity
        self.category = category
        self.title = title
        self.summary = summary
        self.recommendedOptionId = recommendedOptionId
        self.options = options
        self.evidence = evidence
        self.timeoutSeconds = timeoutSeconds
        self.fallbackAction = fallbackAction
        self.status = status
        self.chosenOptionId = chosenOptionId
        self.userNote = userNote
        self.resolvedBy = resolvedBy
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
    }
}

// MARK: - 3. Manus Cue & PipiFleet Multi-Node Telemetry

public struct CueAction: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let label: String
    public let hotkeyHint: String?
    public let harness: HarnessProvider
    public let promptTemplate: String
    public let estimatedSeconds: Int?
    public let requiresConfirmation: Bool?

    public init(
        id: String,
        label: String,
        hotkeyHint: String? = nil,
        harness: HarnessProvider,
        promptTemplate: String,
        estimatedSeconds: Int? = nil,
        requiresConfirmation: Bool? = nil
    ) {
        self.id = id
        self.label = label
        self.hotkeyHint = hotkeyHint
        self.harness = harness
        self.promptTemplate = promptTemplate
        self.estimatedSeconds = estimatedSeconds
        self.requiresConfirmation = requiresConfirmation
    }
}

public struct CueSuggestion: Codable, Sendable, Identifiable, Equatable {
    public enum Feedback: String, Codable, Sendable {
        case accepted
        case dismissed
        case ignored
    }

    public let id: String
    public let nodeId: String
    public let activeAppName: String
    public let activeAppBundleId: String
    public let windowTitle: String
    public let workspacePath: String?
    public let gitBranch: String?
    public let detectedIntent: String
    public let confidence: Double
    public let actions: [CueAction]
    public var feedback: Feedback?
    public let capturedAt: String
    public let expiresAt: String

    public init(
        id: String,
        nodeId: String,
        activeAppName: String,
        activeAppBundleId: String,
        windowTitle: String,
        workspacePath: String? = nil,
        gitBranch: String? = nil,
        detectedIntent: String,
        confidence: Double,
        actions: [CueAction],
        feedback: Feedback? = nil,
        capturedAt: String,
        expiresAt: String
    ) {
        self.id = id
        self.nodeId = nodeId
        self.activeAppName = activeAppName
        self.activeAppBundleId = activeAppBundleId
        self.windowTitle = windowTitle
        self.workspacePath = workspacePath
        self.gitBranch = gitBranch
        self.detectedIntent = detectedIntent
        self.confidence = confidence
        self.actions = actions
        self.feedback = feedback
        self.capturedAt = capturedAt
        self.expiresAt = expiresAt
    }
}

public enum FleetNodeKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case mac
    case ios
    case vps
    case windows
    case embedded

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mac: return "macOS"
        case .ios: return "iOS"
        case .vps: return "Linux VPS"
        case .windows: return "Windows"
        case .embedded: return "Embedded IoT"
        }
    }

    public var sfSymbolName: String {
        switch self {
        case .mac: return "laptopcomputer"
        case .ios: return "iphone"
        case .vps: return "server.rack"
        case .windows: return "pc"
        case .embedded: return "cpu"
        }
    }
}

public enum DotsVitalityState: String, Codable, Sendable, CaseIterable {
    case alive
    case busy
    case degraded
    case sleeping
    case offline

    public var displayLabel: String {
        switch self {
        case .alive: return "Alive"
        case .busy: return "Busy"
        case .degraded: return "Degraded"
        case .sleeping: return "Sleeping"
        case .offline: return "Offline"
        }
    }
}

public struct FleetNodeCapabilities: Codable, Sendable, Equatable {
    public let canRunPi: Bool
    public let localHarnesses: [HarnessProvider]
    public let hasGpuOrNeuralEngine: Bool
    public let canRunGuiCue: Bool
    public let canActAsRelayHost: Bool
    public let supportedTools: [String]

    public init(
        canRunPi: Bool,
        localHarnesses: [HarnessProvider],
        hasGpuOrNeuralEngine: Bool,
        canRunGuiCue: Bool,
        canActAsRelayHost: Bool,
        supportedTools: [String]
    ) {
        self.canRunPi = canRunPi
        self.localHarnesses = localHarnesses
        self.hasGpuOrNeuralEngine = hasGpuOrNeuralEngine
        self.canRunGuiCue = canRunGuiCue
        self.canActAsRelayHost = canActAsRelayHost
        self.supportedTools = supportedTools
    }
}

public struct FleetNodeTelemetry: Codable, Sendable, Identifiable, Equatable {
    public var id: String { nodeId }
    public let nodeId: String
    public let displayName: String
    public let kind: FleetNodeKind
    public let osVersion: String
    public let arch: String
    public var vitality: DotsVitalityState
    public var cpuLoadPct: Double
    public var memoryUsedPct: Double
    public var diskUsedPct: Double?
    public var batteryPct: Double?
    public var isCharging: Bool?
    public var tunnelRttMs: Double?
    public var activeSessionsCount: Int
    public let capabilities: FleetNodeCapabilities
    public let tags: [String]
    public var lastSeenAt: String

    public init(
        nodeId: String,
        displayName: String,
        kind: FleetNodeKind,
        osVersion: String,
        arch: String,
        vitality: DotsVitalityState,
        cpuLoadPct: Double,
        memoryUsedPct: Double,
        diskUsedPct: Double? = nil,
        batteryPct: Double? = nil,
        isCharging: Bool? = nil,
        tunnelRttMs: Double? = nil,
        activeSessionsCount: Int,
        capabilities: FleetNodeCapabilities,
        tags: [String],
        lastSeenAt: String
    ) {
        self.nodeId = nodeId
        self.displayName = displayName
        self.kind = kind
        self.osVersion = osVersion
        self.arch = arch
        self.vitality = vitality
        self.cpuLoadPct = cpuLoadPct
        self.memoryUsedPct = memoryUsedPct
        self.diskUsedPct = diskUsedPct
        self.batteryPct = batteryPct
        self.isCharging = isCharging
        self.tunnelRttMs = tunnelRttMs
        self.activeSessionsCount = activeSessionsCount
        self.capabilities = capabilities
        self.tags = tags
        self.lastSeenAt = lastSeenAt
    }
}

public struct CloudflareFreeTierQuotaSnapshot: Codable, Sendable, Equatable {
    public let workersReqToday: Int
    public let workersDailyLimit: Int
    public let d1ReadsToday: Int
    public let d1DailyLimit: Int
    public let d1WritesToday: Int
    public let d1DailyWriteLimit: Int
    public let r2UsedBytes: Int
    public let r2CapBytes: Int
    public let monthlyCostUsd: Double

    public var r2StorageGbUsed: Double {
        Double(r2UsedBytes) / 1_073_741_824.0
    }

    public var r2StorageGbLimit: Double {
        Double(r2CapBytes) / 1_073_741_824.0
    }

    public init(
        workersReqToday: Int,
        workersDailyLimit: Int = 100_000,
        d1ReadsToday: Int,
        d1DailyLimit: Int = 5_000_000,
        d1WritesToday: Int,
        d1DailyWriteLimit: Int = 100_000,
        r2UsedBytes: Int,
        r2CapBytes: Int = 10_737_418_240,
        monthlyCostUsd: Double = 0.0
    ) {
        self.workersReqToday = workersReqToday
        self.workersDailyLimit = workersDailyLimit
        self.d1ReadsToday = d1ReadsToday
        self.d1DailyLimit = d1DailyLimit
        self.d1WritesToday = d1WritesToday
        self.d1DailyWriteLimit = d1DailyWriteLimit
        self.r2UsedBytes = r2UsedBytes
        self.r2CapBytes = r2CapBytes
        self.monthlyCostUsd = monthlyCostUsd
    }
}

public struct CloudflareTunnelStatus: Codable, Sendable, Equatable {
    public let tunnelConnected: Bool
    public let tunnelUrl: String
    public let tunnelRttMs: Int
    public let cloudflaredInstalled: Bool
    public let accessZeroTrustEnabled: Bool
    public let offlineQueuePendingCount: Int
    public let lastHeartbeatAt: String
    public let freeTierQuota: CloudflareFreeTierQuotaSnapshot

    public init(
        tunnelConnected: Bool,
        tunnelUrl: String,
        tunnelRttMs: Int,
        cloudflaredInstalled: Bool,
        accessZeroTrustEnabled: Bool,
        offlineQueuePendingCount: Int,
        lastHeartbeatAt: String,
        freeTierQuota: CloudflareFreeTierQuotaSnapshot
    ) {
        self.tunnelConnected = tunnelConnected
        self.tunnelUrl = tunnelUrl
        self.tunnelRttMs = tunnelRttMs
        self.cloudflaredInstalled = cloudflaredInstalled
        self.accessZeroTrustEnabled = accessZeroTrustEnabled
        self.offlineQueuePendingCount = offlineQueuePendingCount
        self.lastHeartbeatAt = lastHeartbeatAt
        self.freeTierQuota = freeTierQuota
    }
}

// MARK: - 4. Procedural Avatar Engine: 53-State Machine & 9 Core Expressions

public enum AvatarLifecycleGroup: String, Codable, Sendable, CaseIterable, Identifiable {
    case idleAmbient = "idle_ambient"
    case thinkingReasoning = "thinking_reasoning"
    case toolHarnessExecution = "tool_harness_execution"
    case cueNeedsYouAlert = "cue_needs_you_alert"
    case selfEvolutionDreaming = "self_evolution_dreaming"

    public var id: String { rawValue }

    public var displayTitle: String {
        switch self {
        case .idleAmbient: return "Idle & Ambient"
        case .thinkingReasoning: return "Thinking & Reasoning"
        case .toolHarnessExecution: return "Tool & Harness Execution"
        case .cueNeedsYouAlert: return "Cue & Needs-You Alert"
        case .selfEvolutionDreaming: return "Self-Evolution & Dreaming"
        }
    }
}

public enum AvatarExpression9: String, Codable, Sendable, CaseIterable, Identifiable {
    case neutral
    case happy
    case focused
    case curious
    case alert
    case proud
    case sleepy
    case evolving
    case listening

    public var id: String { rawValue }
}

public enum AvatarShape: String, Codable, Sendable, CaseIterable, Identifiable {
    case orb
    case squircle
    case cloud
    case spark
    case bolt
    case shield
    case dream
    case terminal

    public var id: String { rawValue }
}

public enum AvatarPresetKind: String, Codable, Sendable {
    case idle
    case thinking
    case piCoding = "pi-coding"
    case claudeRouting = "claude-routing"
    case codexRouting = "codex-routing"
    case opencodeRouting = "opencode-routing"
    case byokStreaming = "byok-streaming"
    case manusCue = "manus-cue"
    case needsYou = "needs-you"
    case evolving
    case sleeping
}

/// Complete canonical 53-state taxonomy (10 + 11 + 14 + 10 + 8 = 53)
/// matching `packages/protocol/src/index.ts` and `design-system/pipibot-avatar.js`.
public enum AvatarState53: String, Codable, Sendable, CaseIterable, Identifiable {
    // Group 1: Idle & Ambient (10)
    case idle
    case ambientBreathe = "ambient-breathe"
    case ambientWander = "ambient-wander"
    case ambientCuriousGlance = "ambient-curious-glance"
    case ambientCoffeeBreak = "ambient-coffee-break"
    case ambientNightWatch = "ambient-night-watch"
    case ambientBatterySaver = "ambient-battery-saver"
    case ambientStandby = "ambient-standby"
    case ambientWarmWelcome = "ambient-warm-welcome"
    case ambientZen = "ambient-zen"

    // Group 2: Thinking & Reasoning (11)
    case thinking
    case deepReasoning = "deep-reasoning"
    case memoryRecall = "memory-recall"
    case contextScanning = "context-scanning"
    case planStructuring = "plan-structuring"
    case hypothesisBranching = "hypothesis-branching"
    case crossChecking = "cross-checking"
    case costRouting = "cost-routing"
    case diffAnalyzing = "diff-analyzing"
    case voiceTranscribing = "voice-transcribing"
    case synthesizing

    // Group 3: Tool & Harness Execution (14)
    case piCoding = "pi-coding"
    case piBashRunning = "pi-bash-running"
    case piFileEditing = "pi-file-editing"
    case claudeRouting = "claude-routing"
    case codexRouting = "codex-routing"
    case opencodeRouting = "opencode-routing"
    case byokStreaming = "byok-streaming"
    case mcpBridging = "mcp-bridging"
    case subsessionSpawning = "subsession-spawning"
    case browserEvaluating = "browser-evaluating"
    case vpsDeploying = "vps-deploying"
    case macAutomating = "mac-automating"
    case iotSignaling = "iot-signaling"
    case gitCommitting = "git-committing"

    // Group 4: Cue & Needs-You Alert (10)
    case manusCue = "manus-cue"
    case cueWhispering = "cue-whispering"
    case cueWindowMatched = "cue-window-matched"
    case needsYou = "needs-you"
    case needsYouUrgent = "needs-you-urgent"
    case needsYouApproval = "needs-you-approval"
    case needsYouDiffReady = "needs-you-diff-ready"
    case fleetDegraded = "fleet-degraded"
    case tunnelReconnecting = "tunnel-reconnecting"
    case voiceInterrupted = "voice-interrupted"

    // Group 5: Self-Evolution & Dreaming (8)
    case evolving
    case sleeping
    case dreamingConsolidating = "dreaming-consolidating"
    case skillSynthesizing = "skill-synthesizing"
    case personaUpdating = "persona-updating"
    case memoryPruning = "memory-pruning"
    case r2BackingUp = "r2-backing-up"
    case evolutionProud = "evolution-proud"

    public var id: String { rawValue }
}

// MARK: - 5. 4-Tier Cognitive Memory & Self-Evolution

public enum MemoryTier: String, Codable, Sendable, CaseIterable {
    case l0Working = "L0_WORKING"
    case l1Episodic = "L1_EPISODIC"
    case l2Semantic = "L2_SEMANTIC"
    case l3Procedural = "L3_PROCEDURAL"
}

public enum MemoryDomain: String, Codable, Sendable, CaseIterable, Identifiable {
    case codingConvention = "coding_convention"
    case communicationPref = "communication_pref"
    case dailyLife = "daily_life"
    case workContext = "work_context"
    case infraTopology = "infra_topology"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codingConvention: return "Coding"
        case .communicationPref: return "Tone"
        case .dailyLife: return "Daily Life"
        case .workContext: return "Work"
        case .infraTopology: return "Infra"
        }
    }
}

public struct MemoryEntry: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let seq: Int
    public let tier: MemoryTier
    public let domain: MemoryDomain
    public let title: String
    public let content: String
    public let confidence: Double
    public let importanceBase: Double
    public let createdAt: Double

    public init(
        id: String,
        seq: Int,
        tier: MemoryTier,
        domain: MemoryDomain,
        title: String,
        content: String,
        confidence: Double,
        importanceBase: Double,
        createdAt: Double
    ) {
        self.id = id
        self.seq = seq
        self.tier = tier
        self.domain = domain
        self.title = title
        self.content = content
        self.confidence = confidence
        self.importanceBase = importanceBase
        self.createdAt = createdAt
    }
}

public struct UnderstandingScoreBreakdown: Codable, Sendable, Equatable {
    public struct Metrics: Codable, Sendable, Equatable {
        public let coverage: Double
        public let cueAcceptanceRate: Double
        public let memoryRetention: Double
        public let correctionRate: Double

        public init(
            coverage: Double,
            cueAcceptanceRate: Double,
            memoryRetention: Double,
            correctionRate: Double
        ) {
            self.coverage = coverage
            self.cueAcceptanceRate = cueAcceptanceRate
            self.memoryRetention = memoryRetention
            self.correctionRate = correctionRate
        }
    }

    public let overall: Double
    public let deltaFromPrevious: Double
    public let breakdown: [String: Double]
    public let metrics: Metrics

    public init(
        overall: Double,
        deltaFromPrevious: Double,
        breakdown: [String: Double],
        metrics: Metrics
    ) {
        self.overall = overall
        self.deltaFromPrevious = deltaFromPrevious
        self.breakdown = breakdown
        self.metrics = metrics
    }
}

public enum EvolutionDiffOperation: String, Codable, Sendable {
    case add
    case supersede
    case addSkill = "add_skill"
    case updateSoul = "update_soul"
    case archive
}

public enum EvolutionReviewStatus: String, Codable, Sendable {
    case pending
    case approved
    case edited
    case reverted
}

public struct EvolutionDiffItem: Codable, Sendable, Identifiable, Equatable {
    public var id: String { diffId }
    public let diffId: String
    public let operation: EvolutionDiffOperation
    public let targetFile: String
    public let domain: MemoryDomain
    public let title: String
    public let previousValue: String?
    public let proposedValue: String
    public let confidence: Double
    public let evidenceSummary: String
    public var reviewStatus: EvolutionReviewStatus

    public init(
        diffId: String,
        operation: EvolutionDiffOperation,
        targetFile: String,
        domain: MemoryDomain,
        title: String,
        previousValue: String? = nil,
        proposedValue: String,
        confidence: Double,
        evidenceSummary: String,
        reviewStatus: EvolutionReviewStatus = .pending
    ) {
        self.diffId = diffId
        self.operation = operation
        self.targetFile = targetFile
        self.domain = domain
        self.title = title
        self.previousValue = previousValue
        self.proposedValue = proposedValue
        self.confidence = confidence
        self.evidenceSummary = evidenceSummary
        self.reviewStatus = reviewStatus
    }
}

public struct SynthesizedSkillCandidate: Codable, Sendable, Identifiable, Equatable {
    public var id: String { slug }
    public let slug: String
    public let name: String
    public let description: String
    public let domain: MemoryDomain
    public let toolSequence: [String]
    public let occurrences: Int
    public let successRate: Double
    public var status: String

    public init(
        slug: String,
        name: String,
        description: String,
        domain: MemoryDomain,
        toolSequence: [String],
        occurrences: Int,
        successRate: Double,
        status: String = "candidate"
    ) {
        self.slug = slug
        self.name = name
        self.description = description
        self.domain = domain
        self.toolSequence = toolSequence
        self.occurrences = occurrences
        self.successRate = successRate
        self.status = status
    }
}

public struct EvolutionSummary: Codable, Sendable, Identifiable, Equatable {
    public var id: String { digestId }
    public let digestId: String
    public let cycle: String
    public let generatedAt: String
    public let episodicEventsProcessed: Int
    public var understandingScore: UnderstandingScoreBreakdown
    public var diffs: [EvolutionDiffItem]
    public var candidateSkills: [SynthesizedSkillCandidate]
    public var requiresUserReviewCount: Int

    public init(
        digestId: String,
        cycle: String,
        generatedAt: String,
        episodicEventsProcessed: Int,
        understandingScore: UnderstandingScoreBreakdown,
        diffs: [EvolutionDiffItem],
        candidateSkills: [SynthesizedSkillCandidate],
        requiresUserReviewCount: Int
    ) {
        self.digestId = digestId
        self.cycle = cycle
        self.generatedAt = generatedAt
        self.episodicEventsProcessed = episodicEventsProcessed
        self.understandingScore = understandingScore
        self.diffs = diffs
        self.candidateSkills = candidateSkills
        self.requiresUserReviewCount = requiresUserReviewCount
    }
}

// MARK: - 6. Muse Spatial Canvas, Chat & Daemon API Snapshots

public enum MuseCardKind: String, Codable, Sendable, CaseIterable {
    case outcome
    case voiceNote = "voice_note"
    case memory
    case infra
    case life

    public var displayName: String {
        switch self {
        case .outcome: return "Outcome"
        case .voiceNote: return "Voice Note"
        case .memory: return "Memory"
        case .infra: return "Infra"
        case .life: return "Life"
        }
    }
}

public struct MuseCardItem: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let kind: MuseCardKind
    public let domain: OutcomeDomain
    public let title: String
    public let body: String
    public var offsetX: Double
    public var offsetY: Double
    public let harness: HarnessProvider?
    public let timestamp: String

    public init(
        id: String,
        kind: MuseCardKind,
        domain: OutcomeDomain,
        title: String,
        body: String,
        offsetX: Double,
        offsetY: Double,
        harness: HarnessProvider? = nil,
        timestamp: String
    ) {
        self.id = id
        self.kind = kind
        self.domain = domain
        self.title = title
        self.body = body
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.harness = harness
        self.timestamp = timestamp
    }
}

public struct ChatTranscriptMessage: Codable, Sendable, Identifiable, Equatable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    public let id: String
    public let role: Role
    public let harness: HarnessProvider
    public let content: String
    public let avatarState: AvatarState53?
    public let timestamp: String

    public init(
        id: String,
        role: Role,
        harness: HarnessProvider,
        content: String,
        avatarState: AvatarState53? = nil,
        timestamp: String
    ) {
        self.id = id
        self.role = role
        self.harness = harness
        self.content = content
        self.avatarState = avatarState
        self.timestamp = timestamp
    }
}

public struct DaemonCountsSnapshot: Codable, Sendable, Equatable {
    public let outcomes: Int
    public let pendingDecisions: Int
    public let activeSubSessions: Int
    public let fleetOnline: Int

    public init(outcomes: Int, pendingDecisions: Int, activeSubSessions: Int, fleetOnline: Int) {
        self.outcomes = outcomes
        self.pendingDecisions = pendingDecisions
        self.activeSubSessions = activeSubSessions
        self.fleetOnline = fleetOnline
    }
}

public struct DaemonStatusSnapshot: Codable, Sendable, Equatable {
    public let version: String
    public let uptimeSeconds: Double
    public let avatarState: AvatarState53
    public let avatarExpression: AvatarExpression9
    public let harnesses: [HarnessProbeResult]
    public let cloudflare: CloudflareTunnelStatus
    public let understandingScore: UnderstandingScoreBreakdown
    public let counts: DaemonCountsSnapshot

    public init(
        version: String,
        uptimeSeconds: Double,
        avatarState: AvatarState53,
        avatarExpression: AvatarExpression9,
        harnesses: [HarnessProbeResult],
        cloudflare: CloudflareTunnelStatus,
        understandingScore: UnderstandingScoreBreakdown,
        counts: DaemonCountsSnapshot
    ) {
        self.version = version
        self.uptimeSeconds = uptimeSeconds
        self.avatarState = avatarState
        self.avatarExpression = avatarExpression
        self.harnesses = harnesses
        self.cloudflare = cloudflare
        self.understandingScore = understandingScore
        self.counts = counts
    }
}

public struct SoulDocumentPreview: Codable, Sendable, Equatable {
    public let soulMd: String
    public let userMd: String
    public let memoryMd: String

    public init(soulMd: String, userMd: String, memoryMd: String = "") {
        self.soulMd = soulMd
        self.userMd = userMd
        self.memoryMd = memoryMd
    }
}
