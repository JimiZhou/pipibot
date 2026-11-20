import Foundation
import Observation

#if os(macOS)
import AppKit
import Darwin
#endif

// MARK: - Resident Persisted State (~/Library/Application Support/PipiBot/resident-state.json)

public enum PipiStateLoadResult: Sendable {
    case notFound
    case loaded(PipiResidentPersistedState)
    case corrupt(backupURL: URL?, errorDescription: String)
}

public struct PipiResidentPersistedState: Codable, Sendable {
    public var outcomes: [OutcomeResponsibility]
    public var decisions: [NeedsYouDecision]
    public var museCards: [MuseCardItem]
    public var activeHarness: HarnessProvider
    public var themeModeRaw: String
    public var keepAwakeEnabled: Bool
    public var updatedAt: String

    // Commercial Personal Bot State (Optional for seamless backward-compatible decoding)
    public var hasCompletedOnboarding: Bool?
    public var languageRaw: String?
    public var llmProviders: [PipiLLMProviderConfig]?
    public var defaultLLMProviderId: String?
    public var enabledLocalAgents: [PipiLocalAgentKind]?
    public var defaultExecutionTarget: PipiExecutionTarget?
    public var workspaceDirectory: String?
    public var personas: [PipiBotPersona]?
    public var activePersonaId: String?
    public var conversations: [PipiConversation]?
    public var activeConversationId: String?
    public var memoryEnabled: Bool?
    public var personalProfileNote: String?
    public var routines: [PipiBotRoutine]?
    public var runRecords: [PipiRunRecord]?
    public var companionSyncEnabled: Bool?
    public var schemaMigrationVersion: Int?
    public var uiZoomScale: Double?
    public var projects: [PipiProject]?
    public var groupChats: [PipiGroupChat]?
    public var activeGroupChatId: String?
    // Wave 1 (#08) Guardrail & Multi-Granularity Whitelist Persistence
    public var approvalWhitelistRules: [PipiApprovalWhitelistRule]?
    public var llmGuardrailJudgeEnabled: Bool?
    // Wave 2 (#03) Proactive Guardrails, Prepare Briefings & Clue->Rule Guideline Persistence
    public var proactiveState: PipiProactivePersistedState?
    // Wave 3 (#05 AlterEgo Tasks & #11 Pocket Notes / Editable Documents)
    public var alterEgoTasks: [PipiAlterEgoTask]?
    public var pocketNotesState: PipiPocketNotesPersistedState?
    // Wave 4 (#07 Local Model Stack & Gateway, #10 Personal Daily Voice)
    public var localGatewayConfig: PipiLocalGatewayConfig?
    public var voiceConfig: PipiVoiceConfig?
    // Wave 5 (#09 Dual-Phase Computer Use)
    public var computerUseConfig: PipiComputerUseConfig?
    // Global Shared Capability Pool & Autonomous Peer Upgrades
    public var globalCapabilityPool: PipiGlobalCapabilityPool?
    // 3D Home Space Preset & Multi-Room Agent Assignments
    public var homeScenePresetRaw: String?
    public var botRoomAssignments: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case outcomes, decisions, museCards, activeHarness, themeModeRaw, keepAwakeEnabled, updatedAt
        case hasCompletedOnboarding, languageRaw, llmProviders, defaultLLMProviderId
        case enabledLocalAgents, defaultExecutionTarget, workspaceDirectory
        case personas, activePersonaId, conversations, activeConversationId
        case memoryEnabled, personalProfileNote, routines, runRecords
        case companionSyncEnabled, schemaMigrationVersion, uiZoomScale, projects
        case groupChats, activeGroupChatId
        case approvalWhitelistRules, llmGuardrailJudgeEnabled
        case proactiveState
        case alterEgoTasks, pocketNotesState
        case localGatewayConfig, voiceConfig
        case computerUseConfig
        case globalCapabilityPool
        case homeScenePresetRaw, botRoomAssignments
    }

    public init(
        outcomes: [OutcomeResponsibility],
        decisions: [NeedsYouDecision],
        museCards: [MuseCardItem],
        activeHarness: HarnessProvider,
        themeModeRaw: String,
        keepAwakeEnabled: Bool,
        updatedAt: String,
        hasCompletedOnboarding: Bool? = nil,
        languageRaw: String? = nil,
        llmProviders: [PipiLLMProviderConfig]? = nil,
        defaultLLMProviderId: String? = nil,
        enabledLocalAgents: [PipiLocalAgentKind]? = nil,
        defaultExecutionTarget: PipiExecutionTarget? = nil,
        workspaceDirectory: String? = nil,
        personas: [PipiBotPersona]? = nil,
        activePersonaId: String? = nil,
        conversations: [PipiConversation]? = nil,
        activeConversationId: String? = nil,
        memoryEnabled: Bool? = nil,
        personalProfileNote: String? = nil,
        routines: [PipiBotRoutine]? = nil,
        runRecords: [PipiRunRecord]? = nil,
        companionSyncEnabled: Bool? = nil,
        schemaMigrationVersion: Int? = nil,
        uiZoomScale: Double? = nil,
        projects: [PipiProject]? = nil,
        groupChats: [PipiGroupChat]? = nil,
        activeGroupChatId: String? = nil,
        approvalWhitelistRules: [PipiApprovalWhitelistRule]? = nil,
        llmGuardrailJudgeEnabled: Bool? = nil,
        proactiveState: PipiProactivePersistedState? = nil,
        alterEgoTasks: [PipiAlterEgoTask]? = nil,
        pocketNotesState: PipiPocketNotesPersistedState? = nil,
        localGatewayConfig: PipiLocalGatewayConfig? = nil,
        voiceConfig: PipiVoiceConfig? = nil,
        computerUseConfig: PipiComputerUseConfig? = nil,
        globalCapabilityPool: PipiGlobalCapabilityPool? = nil,
        homeScenePresetRaw: String? = nil,
        botRoomAssignments: [String: String]? = nil
    ) {
        self.outcomes = outcomes
        self.decisions = decisions
        self.museCards = museCards
        self.activeHarness = activeHarness
        self.themeModeRaw = themeModeRaw
        self.keepAwakeEnabled = keepAwakeEnabled
        self.updatedAt = updatedAt
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.languageRaw = languageRaw
        self.llmProviders = llmProviders
        self.defaultLLMProviderId = defaultLLMProviderId
        self.enabledLocalAgents = enabledLocalAgents
        self.defaultExecutionTarget = defaultExecutionTarget
        self.workspaceDirectory = workspaceDirectory
        self.personas = personas
        self.activePersonaId = activePersonaId
        self.conversations = conversations
        self.activeConversationId = activeConversationId
        self.memoryEnabled = memoryEnabled
        self.personalProfileNote = personalProfileNote
        self.routines = routines
        self.runRecords = runRecords
        self.companionSyncEnabled = companionSyncEnabled
        self.schemaMigrationVersion = schemaMigrationVersion
        self.uiZoomScale = uiZoomScale
        self.projects = projects
        self.groupChats = groupChats
        self.activeGroupChatId = activeGroupChatId
        self.approvalWhitelistRules = approvalWhitelistRules
        self.llmGuardrailJudgeEnabled = llmGuardrailJudgeEnabled
        self.proactiveState = proactiveState
        self.alterEgoTasks = alterEgoTasks
        self.pocketNotesState = pocketNotesState
        self.localGatewayConfig = localGatewayConfig
        self.voiceConfig = voiceConfig
        self.computerUseConfig = computerUseConfig
        self.globalCapabilityPool = globalCapabilityPool
        self.homeScenePresetRaw = homeScenePresetRaw
        self.botRoomAssignments = botRoomAssignments
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.outcomes = try c.decodeIfPresent([OutcomeResponsibility].self, forKey: .outcomes) ?? []
        self.decisions = try c.decodeIfPresent([NeedsYouDecision].self, forKey: .decisions) ?? []
        self.museCards = try c.decodeIfPresent([MuseCardItem].self, forKey: .museCards) ?? []
        self.activeHarness = try c.decodeIfPresent(HarnessProvider.self, forKey: .activeHarness) ?? .pi
        self.themeModeRaw = try c.decodeIfPresent(String.self, forKey: .themeModeRaw) ?? "system"
        self.keepAwakeEnabled = try c.decodeIfPresent(Bool.self, forKey: .keepAwakeEnabled) ?? false
        self.updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""

        self.hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
        self.languageRaw = try c.decodeIfPresent(String.self, forKey: .languageRaw)
        self.llmProviders = try c.decodeIfPresent([PipiLLMProviderConfig].self, forKey: .llmProviders)
        self.defaultLLMProviderId = try c.decodeIfPresent(String.self, forKey: .defaultLLMProviderId)
        self.enabledLocalAgents = try c.decodeIfPresent([PipiLocalAgentKind].self, forKey: .enabledLocalAgents)
        self.defaultExecutionTarget = try c.decodeIfPresent(PipiExecutionTarget.self, forKey: .defaultExecutionTarget)
        self.workspaceDirectory = try c.decodeIfPresent(String.self, forKey: .workspaceDirectory)
        self.personas = try c.decodeIfPresent([PipiBotPersona].self, forKey: .personas)
        self.activePersonaId = try c.decodeIfPresent(String.self, forKey: .activePersonaId)
        self.conversations = try c.decodeIfPresent([PipiConversation].self, forKey: .conversations)
        self.activeConversationId = try c.decodeIfPresent(String.self, forKey: .activeConversationId)
        self.memoryEnabled = try c.decodeIfPresent(Bool.self, forKey: .memoryEnabled)
        self.personalProfileNote = try c.decodeIfPresent(String.self, forKey: .personalProfileNote)
        self.routines = try c.decodeIfPresent([PipiBotRoutine].self, forKey: .routines)
        self.runRecords = try c.decodeIfPresent([PipiRunRecord].self, forKey: .runRecords)
        self.companionSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .companionSyncEnabled)
        self.schemaMigrationVersion = try c.decodeIfPresent(Int.self, forKey: .schemaMigrationVersion)
        self.uiZoomScale = try c.decodeIfPresent(Double.self, forKey: .uiZoomScale)
        self.projects = try c.decodeIfPresent([PipiProject].self, forKey: .projects)
        self.groupChats = try c.decodeIfPresent([PipiGroupChat].self, forKey: .groupChats)
        self.activeGroupChatId = try c.decodeIfPresent(String.self, forKey: .activeGroupChatId)
        self.approvalWhitelistRules = try c.decodeIfPresent([PipiApprovalWhitelistRule].self, forKey: .approvalWhitelistRules)
        self.llmGuardrailJudgeEnabled = try c.decodeIfPresent(Bool.self, forKey: .llmGuardrailJudgeEnabled)
        self.proactiveState = try c.decodeIfPresent(PipiProactivePersistedState.self, forKey: .proactiveState)
        self.alterEgoTasks = try c.decodeIfPresent([PipiAlterEgoTask].self, forKey: .alterEgoTasks)
        self.pocketNotesState = try c.decodeIfPresent(PipiPocketNotesPersistedState.self, forKey: .pocketNotesState)
        self.localGatewayConfig = try c.decodeIfPresent(PipiLocalGatewayConfig.self, forKey: .localGatewayConfig)
        self.voiceConfig = try c.decodeIfPresent(PipiVoiceConfig.self, forKey: .voiceConfig)
        self.computerUseConfig = try c.decodeIfPresent(PipiComputerUseConfig.self, forKey: .computerUseConfig)
        self.globalCapabilityPool = try c.decodeIfPresent(PipiGlobalCapabilityPool.self, forKey: .globalCapabilityPool)
        self.homeScenePresetRaw = try c.decodeIfPresent(String.self, forKey: .homeScenePresetRaw)
        self.botRoomAssignments = try c.decodeIfPresent([String: String].self, forKey: .botRoomAssignments)
    }
}

// MARK: - Native macOS Resident Runtime (Zero Terminal Required)

public struct PipiNativeMacRuntime: Sendable {

    public static func searchBinaryPaths() -> [String] {
        var candidates: [String] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(NSHomeDirectory())/.local/bin",
            "/Volumes/SATA-1TB/Developer/node/bin",
            "/Volumes/SATA-1TB/Developer/bun"
        ]
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            for segment in envPath.split(separator: ":") {
                let dir = String(segment)
                if !dir.isEmpty {
                    candidates.append(dir)
                }
            }
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    public static func findExecutable(_ name: String) -> String? {
        let fm = FileManager.default
        for dir in searchBinaryPaths() {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public static func probeInstalledHarnesses() -> [HarnessProbeResult] {
        let nowIso = ISO8601DateFormatter().string(from: Date())
        let fm = FileManager.default
        let home = NSHomeDirectory()

        // 1. Native Pi Harness (embedded SDK + optional CLI)
        let piBin = findExecutable("pi")
        let piResult = HarnessProbeResult(
            provider: .pi,
            installed: true,
            authenticated: true,
            binaryPath: piBin ?? "embedded-pipicore-sdk",
            version: "0.2.0-beta",
            authSource: piBin != nil ? "Pi CLI + Embedded SDK" : "Embedded 4-Tool Core",
            supportsMcp: true,
            checkedAt: nowIso
        )

        // 2. Claude Code CLI
        let claudeBin = findExecutable("claude")
        let claudeCredPath = "\(home)/.claude/.credentials.json"
        let claudeJsonPath = "\(home)/.claude.json"
        let hasAnthropicEnv = !(ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? "").isEmpty
        let claudeAuth = (claudeBin != nil) && (
            fm.fileExists(atPath: claudeCredPath) ||
            fm.fileExists(atPath: claudeJsonPath) ||
            hasAnthropicEnv
        )
        let claudeResult = HarnessProbeResult(
            provider: .claudeCode,
            installed: claudeBin != nil,
            authenticated: claudeAuth,
            binaryPath: claudeBin,
            version: claudeBin != nil ? "local-cli" : nil,
            authSource: claudeAuth ? "~/.claude credentials" : (claudeBin != nil ? "CLI installed (sign in via claude)" : "Not installed"),
            supportsMcp: true,
            checkedAt: nowIso
        )

        // 3. OpenAI Codex CLI
        let codexBin = findExecutable("codex")
        let codexAuthPath = "\(home)/.codex/auth.json"
        let hasOpenAIEnv = !(ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "").isEmpty
        let codexAuth = (codexBin != nil) && (fm.fileExists(atPath: codexAuthPath) || hasOpenAIEnv)
        let codexResult = HarnessProbeResult(
            provider: .codex,
            installed: codexBin != nil,
            authenticated: codexAuth,
            binaryPath: codexBin,
            version: codexBin != nil ? "local-cli" : nil,
            authSource: codexAuth ? "~/.codex/auth.json" : (codexBin != nil ? "CLI installed (sign in via codex)" : "Not installed"),
            supportsMcp: true,
            checkedAt: nowIso
        )

        // 4. OpenCode CLI / ACP
        let opencodeBin = findExecutable("opencode")
        let opencodeAuthPath = "\(home)/.local/share/opencode/auth.json"
        let opencodeAuth = (opencodeBin != nil) && fm.fileExists(atPath: opencodeAuthPath)
        let opencodeResult = HarnessProbeResult(
            provider: .opencode,
            installed: opencodeBin != nil,
            authenticated: opencodeAuth,
            binaryPath: opencodeBin,
            version: opencodeBin != nil ? "acp-ready" : nil,
            authSource: opencodeAuth ? "opencode auth.json" : (opencodeBin != nil ? "CLI ready (opencode acp)" : "Not installed"),
            supportsMcp: true,
            checkedAt: nowIso
        )

        // 5. BYOK Direct Router (via pi-ai + Keychain / Env / Ollama)
        let env = ProcessInfo.processInfo.environment
        let byokKeys = ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "DEEPSEEK_API_KEY", "XAI_API_KEY", "OPENROUTER_API_KEY"]
        let configuredKeys = byokKeys.filter { !(env[$0] ?? "").isEmpty }
        let ollamaBin = findExecutable("ollama")
        let byokInstalled = !configuredKeys.isEmpty || ollamaBin != nil
        let byokSource: String = {
            if !configuredKeys.isEmpty {
                return "\(configuredKeys.count) env keys + Keychain"
            }
            if let ollamaBin {
                return "Local Ollama (\(ollamaBin))"
            }
            return "Configure in Keychain / Env"
        }()

        let byokResult = HarnessProbeResult(
            provider: .byok,
            installed: byokInstalled || true,
            authenticated: !configuredKeys.isEmpty || ollamaBin != nil,
            binaryPath: ollamaBin ?? "pi-ai-direct",
            version: "pi-ai",
            authSource: byokSource,
            supportsMcp: true,
            checkedAt: nowIso
        )

        return [piResult, claudeResult, codexResult, opencodeResult, byokResult]
    }

    public static func probeLocalAgents(enabled: Set<PipiLocalAgentKind>) -> [PipiLocalAgentStatus] {
        let probes = probeInstalledHarnesses()
        return PipiLocalAgentKind.allCases.map { kind in
            let match = probes.first(where: { $0.provider == kind.mappedHarness })
            let installed = match?.installed ?? false
            let authenticated = match?.authenticated ?? false
            let binaryPath = match?.binaryPath
            let authHint = match?.authSource ?? ""
            return PipiLocalAgentStatus(
                kind: kind,
                installed: installed,
                authenticated: authenticated,
                binaryPath: binaryPath,
                authHint: authHint,
                enabled: enabled.contains(kind)
            )
        }
    }

    public static func sampleHostTelemetry(activeSessionsCount: Int = 1) -> FleetNodeTelemetry {
        let processInfo = ProcessInfo.processInfo
        let hostName = processInfo.hostName.replacingOccurrences(of: ".local", with: "")
        let cpuCount = max(1, processInfo.activeProcessorCount)
        let totalMemBytes = Double(processInfo.physicalMemory)
        let nowIso = ISO8601DateFormatter().string(from: Date())

        var cpuLoadPct = 12.0
        var memoryUsedPct = 42.0
        var diskUsedPct: Double?

        #if os(macOS)
        // Real macOS 1m load average -> normalized CPU %
        var loadAvgs = [Double](repeating: 0.0, count: 3)
        if getloadavg(&loadAvgs, 3) > 0 {
            cpuLoadPct = min(100.0, max(1.0, (loadAvgs[0] / Double(cpuCount)) * 100.0))
        }

        // Real Mach VM memory pressure calculation
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let hostPort = mach_host_self()
        let kernResult = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &count)
            }
        }
        var pageSizeBytes: vm_size_t = 0
        host_page_size(hostPort, &pageSizeBytes)
        if kernResult == KERN_SUCCESS && totalMemBytes > 0 && pageSizeBytes > 0 {
            let pageSize = Double(pageSizeBytes)
            let activeBytes = Double(stats.active_count + stats.wire_count) * pageSize
            memoryUsedPct = min(99.0, max(5.0, (activeBytes / totalMemBytes) * 100.0))
        }
        #endif

        if let fsAttrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let totalSize = (fsAttrs[.systemSize] as? NSNumber)?.doubleValue,
           let freeSize = (fsAttrs[.systemFreeSize] as? NSNumber)?.doubleValue,
           totalSize > 0 {
            diskUsedPct = min(99.9, max(1.0, ((totalSize - freeSize) / totalSize) * 100.0))
        }

        let probed = probeInstalledHarnesses()
        let availableHarnesses = probed.filter { $0.installed }.map(\.provider)

        #if arch(arm64)
        let archName = "arm64"
        #else
        let archName = "x86_64"
        #endif

        return FleetNodeTelemetry(
            nodeId: "mac-resident",
            displayName: "\(hostName) (Native Mac)",
            kind: .mac,
            osVersion: processInfo.operatingSystemVersionString,
            arch: archName,
            vitality: activeSessionsCount > 0 ? .busy : .alive,
            cpuLoadPct: (cpuLoadPct * 10).rounded() / 10,
            memoryUsedPct: (memoryUsedPct * 10).rounded() / 10,
            diskUsedPct: diskUsedPct.map { ($0 * 10).rounded() / 10 },
            batteryPct: nil,
            isCharging: true,
            tunnelRttMs: 12,
            activeSessionsCount: activeSessionsCount,
            capabilities: FleetNodeCapabilities(
                canRunPi: true,
                localHarnesses: availableHarnesses.isEmpty ? [.pi] : availableHarnesses,
                hasGpuOrNeuralEngine: true,
                canRunGuiCue: true,
                canActAsRelayHost: true,
                supportedTools: ["read", "write", "edit", "bash", "quick-bar", "local-agents"]
            ),
            tags: ["mac", "local", "\(cpuCount)cores"],
            lastSeenAt: nowIso
        )
    }

    public static func detectFrontmostAppContext(workspacePath: String? = nil) -> CueSuggestion {
        let nowIso = ISO8601DateFormatter().string(from: Date())
        var appName = "PipiBot"
        var bundleId = "ai.pipibot.mac"

        #if os(macOS)
        if let front = NSWorkspace.shared.frontmostApplication {
            appName = front.localizedName ?? appName
            bundleId = front.bundleIdentifier ?? bundleId
        }
        #endif

        let homeDir = NSHomeDirectory()
        let envWorkspace = ProcessInfo.processInfo.environment["PIPIBOT_WORKSPACE"]
        let repoCandidate = discoverRepoRoot()
        let isRuntimeBundle = repoCandidate?.contains("/Contents/Resources/runtime") == true
        let safeRepo = isRuntimeBundle ? nil : repoCandidate

        let resolvedWorkspace: String
        let allowGitProbe: Bool
        if let explicit = workspacePath, !explicit.isEmpty {
            resolvedWorkspace = explicit
            allowGitProbe = true
        } else if let envWorkspace, !envWorkspace.isEmpty {
            resolvedWorkspace = envWorkspace
            allowGitProbe = !isTccProtectedFolder(envWorkspace, homeDir: homeDir)
        } else if let safeRepo {
            resolvedWorkspace = safeRepo
            allowGitProbe = !isTccProtectedFolder(safeRepo, homeDir: homeDir)
        } else {
            resolvedWorkspace = homeDir
            allowGitProbe = false
        }

        let gitBranch = (allowGitProbe && resolvedWorkspace != homeDir)
            ? (readGitBranchFast(at: resolvedWorkspace) ?? "main")
            : "main"
        let folderName = resolvedWorkspace == homeDir
            ? "PipiBot"
            : (resolvedWorkspace as NSString).lastPathComponent

        let actions: [CueAction] = [
            CueAction(
                id: "cue_summarize",
                label: "Summarize \(folderName)",
                hotkeyHint: "⌘1",
                harness: .pi,
                promptTemplate: "Inspect workspace \(resolvedWorkspace) on branch \(gitBranch) and summarize pending tasks.",
                estimatedSeconds: 6
            ),
            CueAction(
                id: "cue_claude_review",
                label: "Review with Claude Code",
                hotkeyHint: "⌘2",
                harness: .claudeCode,
                promptTemplate: "Context from \(appName) (\(gitBranch)): review recent changes in \(folderName).",
                estimatedSeconds: 15
            ),
            CueAction(
                id: "cue_codex_tests",
                label: "Run Tests with Codex",
                hotkeyHint: "⌘3",
                harness: .codex,
                promptTemplate: "Verify test suites in \(resolvedWorkspace) on branch \(gitBranch).",
                estimatedSeconds: 10
            )
        ]

        return CueSuggestion(
            id: "cue_\(UUID().uuidString.prefix(8).lowercased())",
            nodeId: "mac-resident",
            activeAppName: appName,
            activeAppBundleId: bundleId,
            windowTitle: "\(appName) — \(folderName) (\(gitBranch))",
            workspacePath: resolvedWorkspace,
            gitBranch: gitBranch,
            detectedIntent: "Detected \(appName) active on \(folderName) [\(gitBranch)]",
            confidence: 0.94,
            actions: actions,
            capturedAt: nowIso,
            expiresAt: nowIso
        )
    }

    private static func isTccProtectedFolder(_ path: String, homeDir: String) -> Bool {
        let std = (path as NSString).standardizingPath
        for folder in ["Desktop", "Documents", "Downloads"] {
            let prefix = "\(homeDir)/\(folder)"
            if std == prefix || std.hasPrefix(prefix + "/") {
                return true
            }
        }
        return false
    }

    public static func readGitBranchFast(at directory: String) -> String? {
        let headPath = (directory as NSString).appendingPathComponent(".git/HEAD")
        guard let raw = try? String(contentsOfFile: headPath, encoding: .utf8) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: refs/heads/") {
            return String(trimmed.dropFirst("ref: refs/heads/".count))
        }
        if trimmed.count >= 7 {
            return String(trimmed.prefix(7))
        }
        return nil
    }

    public static func discoverRepoRoot(startingAt startPath: String? = nil) -> String? {
        let fm = FileManager.default
        let homeDir = NSHomeDirectory()
        var seeds: [String] = []
        if let envRoot = ProcessInfo.processInfo.environment["PIPIBOT_REPO_ROOT"], !envRoot.isEmpty {
            seeds.append(envRoot)
        }
        if let startPath, !startPath.isEmpty {
            seeds.append(startPath)
        }
        if let bundledRuntime = Bundle.main.resourceURL?.appendingPathComponent("runtime", isDirectory: true).path {
            seeds.append(bundledRuntime)
        }
        let cwd = fm.currentDirectoryPath
        if cwd != "/" && cwd != homeDir {
            seeds.append(cwd)
        }

        for seed in seeds {
            var current = (seed as NSString).standardizingPath
            for _ in 0..<6 {
                let daemonCli = (current as NSString).appendingPathComponent("packages/daemon/src/cli.ts")
                if fm.fileExists(atPath: daemonCli) {
                    return current
                }
                let parent = (current as NSString).deletingLastPathComponent
                if parent == current || parent.isEmpty || parent == "/" || parent == homeDir {
                    break
                }
                current = parent
            }
        }
        return nil
    }

    public static func stateFileUrl() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("PipiBot", isDirectory: true)
            .appendingPathComponent("resident-state.json", isDirectory: false)
    }

    public static func loadResidentStateDetailed(from url: URL = stateFileUrl()) -> PipiStateLoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return .notFound
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(PipiResidentPersistedState.self, from: data)
            return .loaded(decoded)
        } catch {
            let backupURL = backupCorruptStateFile(at: url)
            return .corrupt(backupURL: backupURL, errorDescription: error.localizedDescription)
        }
    }

    public static func loadResidentState(from url: URL = stateFileUrl()) -> PipiResidentPersistedState? {
        switch loadResidentStateDetailed(from: url) {
        case .loaded(let state):
            return state
        case .notFound, .corrupt:
            return nil
        }
    }

    private static func backupCorruptStateFile(at url: URL) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let rawStamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dir = url.deletingLastPathComponent()
        var candidate = dir.appendingPathComponent("resident-state.corrupt-\(rawStamp).json", isDirectory: false)
        if fm.fileExists(atPath: candidate.path) {
            let suffix = UUID().uuidString.prefix(6).lowercased()
            candidate = dir.appendingPathComponent("resident-state.corrupt-\(rawStamp)-\(suffix).json", isDirectory: false)
        }
        do {
            try fm.copyItem(at: url, to: candidate)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: candidate.path)
            return candidate
        } catch {
            return nil
        }
    }

    public static func saveResidentState(_ state: PipiResidentPersistedState, to url: URL = stateFileUrl()) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

// MARK: - Embedded Bridge Supervisor (Auto-manages HTTP/SSE iOS Bridge & Keep-Awake)

@MainActor
@Observable
public final class PipiEmbeddedBridgeSupervisor {
    public enum BridgeState: String, Sendable {
        case stopped = "Standalone Native"
        case starting = "Starting Bridge"
        case running = "Embedded Bridge Active"
        case external = "External Bridge Connected"
        case unavailable = "All-in-One Native"
    }

    public private(set) var bridgeState: BridgeState = .stopped
    public private(set) var bridgeDetail: String = "Zero terminal setup required"
    public private(set) var port: Int = 4242
    public private(set) var keepAwakeEnabled: Bool = false

    private var sleepAssertionToken: NSObjectProtocol?

    #if os(macOS)
    private var childProcess: Process?
    #endif

    public init(port: Int = 4242) {
        self.port = port
    }

    public func setKeepAwake(_ enabled: Bool) {
        if enabled == keepAwakeEnabled { return }
        if enabled {
            sleepAssertionToken = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
                reason: "PipiBot Always-On Resident Host"
            )
            keepAwakeEnabled = true
        } else {
            if let token = sleepAssertionToken {
                ProcessInfo.processInfo.endActivity(token)
                sleepAssertionToken = nil
            }
            keepAwakeEnabled = false
        }
    }

    public func ensureBridgeRunning(repoRootHint: String? = nil) async {
        if await probeLocalBridgeAlive() {
            bridgeState = .external
            bridgeDetail = "Connected to bridge on 127.0.0.1:\(port)"
            return
        }

        #if os(macOS)
        guard let repoRoot = PipiNativeMacRuntime.discoverRepoRoot(startingAt: repoRootHint),
              let nodePath = PipiNativeMacRuntime.findExecutable("node") else {
            bridgeState = .unavailable
            bridgeDetail = "Running self-contained native Swift runtime"
            return
        }

        let cliPath = (repoRoot as NSString).appendingPathComponent("packages/daemon/src/cli.ts")
        guard FileManager.default.fileExists(atPath: cliPath) else {
            bridgeState = .unavailable
            bridgeDetail = "Running self-contained native Swift runtime"
            return
        }

        bridgeState = .starting
        bridgeDetail = "Launching embedded HTTP/SSE bridge on :\(port)..."

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [
            "--experimental-strip-types",
            cliPath,
            "--port", String(port),
            "--workspace", repoRoot,
            "--clean"
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: repoRoot)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.bridgeState == .running {
                    self.bridgeState = .stopped
                    self.bridgeDetail = "Embedded bridge stopped"
                }
            }
        }

        do {
            try process.run()
            childProcess = process

            // Poll briefly until port responds
            for _ in 0..<12 {
                if await probeLocalBridgeAlive() {
                    bridgeState = .running
                    bridgeDetail = "Embedded iOS/Cloudflare bridge active on :\(port)"
                    return
                }
                try? await Task.sleep(for: .milliseconds(180))
            }

            bridgeState = .unavailable
            bridgeDetail = "Bridge startup timed out; continuing in native runtime"
        } catch {
            bridgeState = .unavailable
            bridgeDetail = "All-in-One native runtime active"
        }
        #else
        bridgeState = .unavailable
        bridgeDetail = "iOS companion standalone mode"
        #endif
    }

    public func stopBridge() {
        setKeepAwake(false)
        #if os(macOS)
        if let proc = childProcess, proc.isRunning {
            proc.terminate()
        }
        childProcess = nil
        #endif
        bridgeState = .stopped
        bridgeDetail = "Stopped"
    }

    private func probeLocalBridgeAlive() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/v1/status") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 0.8
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                return (200...299).contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }
}
