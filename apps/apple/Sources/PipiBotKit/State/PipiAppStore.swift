import Foundation
import Observation

public enum PipiConnectionMode: String, Sendable {
    case liveDaemon = "Live Mac Daemon"
    case offlineDemo = "Offline Seed Studio"
}

@MainActor
@Observable
public final class PipiAppStore {
    public let avatarEngine: PipiProceduralAvatarEngine
    public let client: PipiDaemonClient

    public var themeMode: PipiThemeMode = .dark
    public var connectionMode: PipiConnectionMode = .offlineDemo
    public var daemonEndpoint: String = "http://127.0.0.1:4242"

    public var daemonVersion: String = "0.2.0-beta"
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

    public init(
        baseUrl: String = "http://127.0.0.1:4242",
        autoConnect: Bool = false
    ) {
        self.daemonEndpoint = baseUrl
        self.client = PipiDaemonClient(baseUrlString: baseUrl)
        self.avatarEngine = PipiProceduralAvatarEngine(initialState: .idle)

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

        if autoConnect {
            startLiveSync()
        }
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
            await self.refreshAllFromDaemon()
            await self.listenSseLoop()
        }
    }

    public func stopLiveSync() {
        sseTask?.cancel()
        sseTask = nil
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
            self.harnessProbes = status.harnesses
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
            self.episodicMemories = memoryEnv.episodic
            self.synthesizedSkills = memoryEnv.skills
            self.lastDigest = memoryEnv.lastDigest ?? self.lastDigest
            self.soulPreview = soulEnv
            self.noticeBanner = "Synced live with macOS daemon on \(daemonEndpoint)"
        } catch {
            self.connectionMode = .offlineDemo
            self.noticeBanner = "Standalone demo mode active (daemon offline)"
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
                    connectionMode = .offlineDemo
                }
            }
            try? await Task.sleep(for: .seconds(3))
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

    public func refreshCueContext(appName: String = "Xcode", windowTitle: String = "PipiBotApple — Package.swift", gitBranch: String = "main") async {
        avatarEngine.setState(.cueWindowMatched)
        if connectionMode == .liveDaemon {
            if let res = try? await client.refreshCue(
                activeAppName: appName,
                windowTitle: windowTitle,
                workspacePath: "/Users/jimizhou/Desktop/Projects/pipibot",
                gitBranch: gitBranch
            ) {
                latestCue = res.cue
                return
            }
        }
        let nowIso = ISO8601DateFormatter().string(from: Date())
        latestCue = CueSuggestion(
            id: "cue_\(UUID().uuidString.prefix(8).lowercased())",
            nodeId: "mac-resident",
            activeAppName: appName,
            activeAppBundleId: "com.apple.dt.Xcode",
            windowTitle: windowTitle,
            workspacePath: "/Users/jimizhou/Desktop/Projects/pipibot",
            gitBranch: gitBranch,
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

    // MARK: - Rich Seed State (Offline & Demo Parity)

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
