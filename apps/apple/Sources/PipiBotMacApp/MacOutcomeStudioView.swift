import SwiftUI
import PipiBotKit
import PipiBotIOSUI

public enum MacStudioSection: String, CaseIterable, Identifiable, Sendable {
    case outcomes = "Outcomes"
    case needsYou = "Needs You"
    case harnessMuse = "Harnesses & Muse"
    case manusCue = "Manus Cue"
    case fleetCloudflare = "Fleet & Cloudflare"
    case memorySoul = "Memory & Soul"
    case iosCompanion = "iOS Companion"
    case avatarLab = "PipiAvatar 53"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .outcomes: return "target"
        case .needsYou: return "tray.and.arrow.down.fill"
        case .harnessMuse: return "point.3.connected.trianglepath.dotted"
        case .manusCue: return "sparkles.rectangle.stack"
        case .fleetCloudflare: return "circle.grid.3x3.fill"
        case .memorySoul: return "brain.head.profile"
        case .iosCompanion: return "iphone"
        case .avatarLab: return "face.smiling"
        }
    }
}

public struct MacOutcomeStudioView: View {
    @Bindable public var store: PipiAppStore
    public var onToggleFloatingCue: () -> Void

    @State private var selection: MacStudioSection? = .outcomes
    @State private var showCreateOutcome = false
    @State private var newTitle = ""
    @State private var newGoal = ""
    @State private var newDomain: OutcomeDomain = .dev
    @State private var newHarness: HarnessProvider = .pi
    @State private var chatDraft = ""
    @State private var selectedAvatarGroup: AvatarLifecycleGroup = .idleAmbient
    @State private var showSoulModal = false

    public init(
        store: PipiAppStore,
        onToggleFloatingCue: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onToggleFloatingCue = onToggleFloatingCue
    }

    public var body: some View {
        ZStack {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 270)
            } detail: {
                detailStage
            }
            .background(PipiTokens.bgCanvas)

            if showCreateOutcome {
                PipiFormSheet(
                    title: "Create Outcome Responsibility",
                    subtitle: "Devin-style goal ownership with daily USD budget cap",
                    detent: .compact,
                    submitLabel: "Deploy Outcome Bot",
                    submitIcon: "sparkles",
                    onCancel: { showCreateOutcome = false },
                    onSubmit: {
                        Task {
                            await store.createOutcome(
                                title: newTitle,
                                domain: newDomain,
                                goal: newGoal,
                                preferredHarness: newHarness,
                                dailyBudgetUsd: 2.0
                            )
                            newTitle = ""
                            newGoal = ""
                            showCreateOutcome = false
                        }
                    }
                ) {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                        TextField("Outcome title", text: $newTitle)
                            .textFieldStyle(.plain)
                            .padding(PipiTokens.spacing12)
                            .background(PipiTokens.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM))

                        TextField("Goal, success metrics, and constraints", text: $newGoal, axis: .vertical)
                            .lineLimit(3...5)
                            .textFieldStyle(.plain)
                            .padding(PipiTokens.spacing12)
                            .background(PipiTokens.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM))

                        HStack(spacing: PipiTokens.spacing12) {
                            Picker("Domain", selection: $newDomain) {
                                ForEach(OutcomeDomain.allCases) { d in
                                    Text(d.displayName).tag(d)
                                }
                            }
                            Picker("Harness", selection: $newHarness) {
                                ForEach(HarnessProvider.allCases) { h in
                                    Text(h.displayName).tag(h)
                                }
                            }
                        }
                    }
                }
            }

            if showSoulModal {
                PipiSheet(
                    title: "SOUL.md & USER.md",
                    subtitle: "Live L2 cognitive persona graph synced with PipiMemoryEngine",
                    detent: .expanded,
                    onClose: { showSoulModal = false }
                ) {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                        Text(store.soulPreview.soulMd)
                            .font(PipiTokens.fontMono)
                            .foregroundStyle(PipiTokens.textPrimary)
                            .padding(PipiTokens.spacing16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PipiTokens.bgInset)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD))

                        Text(store.soulPreview.userMd)
                            .font(PipiTokens.fontMono)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .padding(PipiTokens.spacing16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PipiTokens.bgInset)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD))
                    }
                }
            }
        }
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: PipiTokens.spacing12) {
                PipiAvatarView(engine: store.avatarEngine, size: 40, compactMode: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PipiBot Studio")
                        .font(PipiTokens.fontHeadline)
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text("v\(store.daemonVersion) · \(store.connectionMode.rawValue)")
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(store.connectionMode == .liveDaemon ? PipiTokens.stateSuccess : PipiTokens.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(PipiTokens.spacing16)
            .frame(maxWidth: .infinity, alignment: .leading)

            List(MacStudioSection.allCases, selection: $selection) { section in
                HStack(spacing: PipiTokens.spacing12) {
                    Image(systemName: section.iconName)
                        .font(.system(size: PipiTokens.buttonIconDesktop, weight: .medium))
                        .foregroundStyle(selection == section ? PipiTokens.soulPrimary : PipiTokens.textSecondary)
                        .frame(width: 20)

                    Text(section.rawValue)
                        .font(PipiTokens.fontBody.weight(selection == section ? .semibold : .regular))
                        .foregroundStyle(PipiTokens.textPrimary)

                    Spacer()

                    if section == .needsYou && !store.pendingDecisions.isEmpty {
                        Text("\(store.pendingDecisions.count)")
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.stateWarning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PipiTokens.stateWarningBg)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 4)
                .tag(section)
            }
            .scrollContentBackground(.hidden)

            // Grounded Bottom Bar for Theme & Sync
            PipiBottomBar {
                VStack(spacing: PipiTokens.spacing8) {
                    Picker("Theme", selection: $store.themeMode) {
                        ForEach(PipiThemeMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    PipiActionButton("Sync Daemon", systemImage: "arrow.triangle.2.circlepath", tone: .secondary, density: .desktopCompact, fullWidth: true) {
                        Task { await store.refreshAllFromDaemon() }
                    }
                }
            }
        }
        .background(PipiTokens.bgElevated)
    }

    // MARK: - Detail Stage

    private var detailStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
                switch selection ?? .outcomes {
                case .outcomes:
                    outcomesDetail
                case .needsYou:
                    needsYouDetail
                case .harnessMuse:
                    harnessAndMuseDetail
                case .manusCue:
                    manusCueDetail
                case .fleetCloudflare:
                    DotsFleetAndTunnelView(store: store)
                case .memorySoul:
                    memoryAndSoulDetail
                case .iosCompanion:
                    iosPreviewDetail
                case .avatarLab:
                    avatarLabDetail
                }
            }
            .padding(PipiTokens.spacing24)
        }
        .background(PipiTokens.bgCanvas)
    }

    // MARK: - Sections

    private var outcomesDetail: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            PipiDock(
                avatarEngine: store.avatarEngine,
                title: "PipiOutcomeEngine · Result Ownership",
                subtitle: "\(store.outcomes.count) responsibilities · \(store.subSessions.count) child sub-sessions",
                actionTitle: "New Outcome",
                actionIcon: "plus",
                density: .desktopCompact
            ) {
                showCreateOutcome = true
            }

            ForEach(store.outcomes) { outcome in
                PipiListCard(
                    title: outcome.title,
                    subtitle: outcome.goal,
                    badgeText: outcome.status.displayLabel,
                    badgeColor: outcome.status == .needsYou ? PipiTokens.stateWarning : PipiTokens.stateSuccess,
                    trailing: {
                        HStack(spacing: PipiTokens.spacing8) {
                            Text(outcome.preferredHarness.displayName)
                                .font(PipiTokens.fontMonoSmall)
                                .foregroundStyle(PipiTokens.color(for: outcome.preferredHarness))
                            PipiActionButton("Evaluate", systemImage: "play.fill", tone: .secondary, density: .desktopCompact) {
                                Task { await store.evaluateOutcome(outcome.id) }
                            }
                        }
                    },
                    footer: {
                        HStack(spacing: PipiTokens.spacing12) {
                            Text("Constraints: \(outcome.constraints.joined(separator: " · "))")
                            Spacer()
                            Text(String(format: "$%.2f / $%.2f", outcome.spentTodayUsd, outcome.dailyBudgetUsd))
                        }
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                    }
                )
            }

            Text("Parallel Sub-Session DAG")
                .font(PipiTokens.fontTitle)
                .foregroundStyle(PipiTokens.textPrimary)

            ForEach(store.subSessions) { sub in
                PipiListCard(
                    title: "\(sub.role) · \(sub.provider.shortLabel)",
                    subtitle: sub.summary ?? sub.objective,
                    badgeText: sub.status.rawValue,
                    badgeColor: PipiTokens.color(for: sub.provider)
                )
            }
        }
    }

    private var needsYouDetail: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            Text("Needs You Decision Inbox (\(store.pendingDecisions.count) Pending)")
                .font(PipiTokens.fontTitle)
                .foregroundStyle(PipiTokens.textPrimary)

            if store.pendingDecisions.isEmpty {
                PipiEmptyState(
                    systemImage: "checkmark.seal.fill",
                    title: "Zero Pending Escalations",
                    message: "All bot outcomes are operating autonomously inside their constraints.",
                    buttonTitle: "Run Preflight Check",
                    buttonAction: {
                        if let id = store.outcomes.first?.id {
                            Task { await store.evaluateOutcome(id) }
                        }
                    }
                )
            } else {
                ForEach(store.pendingDecisions) { dec in
                    PipiListCard(
                        title: dec.title,
                        subtitle: dec.summary,
                        badgeText: dec.severity.rawValue.uppercased(),
                        badgeColor: PipiTokens.color(for: dec.severity),
                        footer: {
                            HStack(spacing: PipiTokens.spacing8) {
                                ForEach(dec.options) { opt in
                                    let tone: PipiButtonTone = opt.style == .primary ? .primary : (opt.style == .destructive ? .destructive : .secondary)
                                    PipiActionButton(opt.label, systemImage: opt.style == .primary ? "checkmark" : nil, tone: tone, density: .desktopCompact) {
                                        Task { await store.resolveDecision(dec.id, optionId: opt.id) }
                                    }
                                }
                                Spacer()
                                if let firstEv = dec.evidence.first {
                                    Text("R2: \(firstEv.kind.label)")
                                        .font(PipiTokens.fontMonoSmall)
                                        .foregroundStyle(PipiTokens.soulSecondary)
                                }
                            }
                        }
                    )
                }
            }
        }
    }

    private var harnessAndMuseDetail: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            Text("PipiHarnessRouter & Routed MCP Bridge")
                .font(PipiTokens.fontTitle)
                .foregroundStyle(PipiTokens.textPrimary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: PipiTokens.spacing12)], spacing: PipiTokens.spacing12) {
                ForEach(store.harnessProbes) { probe in
                    let active = store.activeHarness == probe.provider
                    PipiListCard(
                        title: probe.provider.displayName,
                        subtitle: "\(probe.binaryPath ?? "") · \(probe.authSource ?? "")",
                        badgeText: active ? "Active" : (probe.authenticated ? "Authenticated" : "Unavailable"),
                        badgeColor: active ? PipiTokens.color(for: probe.provider) : PipiTokens.stateSuccess,
                        footer: {
                            PipiActionButton(
                                active ? "Active Harness" : "Switch Router",
                                systemImage: active ? "checkmark.circle.fill" : "arrow.triangle.branch",
                                tone: active ? .primary : .secondary,
                                density: .desktopCompact,
                                fullWidth: true
                            ) {
                                store.activeHarness = probe.provider
                                store.avatarEngine.setState(store.avatarState(for: probe.provider))
                            }
                        }
                    )
                }
            }

            HStack(spacing: PipiTokens.spacing8) {
                TextField("Send instruction to \(store.activeHarness.displayName)...", text: $chatDraft)
                    .textFieldStyle(.plain)
                    .padding(PipiTokens.spacing12)
                    .background(PipiTokens.bgSurface)
                    .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusMD).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD))

                PipiActionButton("Run Turn", systemImage: "paperplane.fill", tone: .primary, density: .desktopCompact) {
                    let msg = chatDraft
                    chatDraft = ""
                    Task { await store.sendChatMessage(msg) }
                }
            }

            ForEach(store.chatMessages) { msg in
                PipiListCard(
                    title: msg.role == .user ? "Owner" : msg.harness.displayName,
                    subtitle: msg.content,
                    badgeText: msg.harness.shortLabel,
                    badgeColor: PipiTokens.color(for: msg.harness)
                )
            }
        }
    }

    private var manusCueDetail: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manus Cue Ambient Pill (⌥Space)")
                        .font(PipiTokens.fontTitle)
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text("Context-aware desktop whisper reading frontmost app, git branch & workspace.")
                        .font(PipiTokens.fontBody)
                        .foregroundStyle(PipiTokens.textSecondary)
                }
                Spacer()
                PipiActionButton(
                    store.isCuePanelVisible ? "Hide Floating Pill" : "Show Floating Pill",
                    systemImage: "sparkles",
                    tone: .primary,
                    density: .desktopCompact,
                    action: onToggleFloatingCue
                )
            }

            ManusCuePillContentView(store: store, onDismiss: onToggleFloatingCue)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, PipiTokens.spacing8)

            HStack(spacing: PipiTokens.spacing8) {
                PipiActionButton("Simulate Xcode", systemImage: "hammer", tone: .secondary, density: .desktopCompact) {
                    Task { await store.refreshCueContext(appName: "Xcode", windowTitle: "PipiBotApple — Package.swift", gitBranch: "main") }
                }
                PipiActionButton("Simulate Terminal", systemImage: "terminal", tone: .secondary, density: .desktopCompact) {
                    Task { await store.refreshCueContext(appName: "Ghostty", windowTitle: "zsh — npm run verify", gitBranch: "feat/v0.2-beta") }
                }
                PipiActionButton("Simulate Safari PR", systemImage: "safari", tone: .secondary, density: .desktopCompact) {
                    Task { await store.refreshCueContext(appName: "Safari", windowTitle: "PR #142 · CLS Layout Diff", gitBranch: "pipibot/fix-cls") }
                }
            }
        }
    }

    private var memoryAndSoulDetail: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            PipiListCard(
                title: String(format: "Understanding Score · %.1f%% (+%.1f%%)", store.understandingScore.overall, store.understandingScore.deltaFromPrevious),
                subtitle: "L0 Working · L1 Episodic SQLite FTS5 · L2 SOUL/USER.md · L3 Auto-Synthesized Pi Skills",
                badgeText: "PipiEvolve",
                badgeColor: PipiTokens.evolveAccent,
                trailing: {
                    HStack(spacing: PipiTokens.spacing8) {
                        PipiActionButton("View SOUL.md", systemImage: "doc.plaintext", tone: .secondary, density: .desktopCompact) {
                            showSoulModal = true
                        }
                        PipiActionButton("Run Nightly Dream", systemImage: "moon.stars.fill", tone: .primary, density: .desktopCompact) {
                            Task { await store.runNightlyDreaming() }
                        }
                    }
                }
            )

            if let digest = store.lastDigest {
                ForEach(digest.diffs) { diff in
                    PipiListCard(
                        title: diff.title,
                        subtitle: diff.proposedValue,
                        badgeText: diff.reviewStatus.rawValue.uppercased(),
                        badgeColor: diff.reviewStatus == .approved ? PipiTokens.stateSuccess : PipiTokens.stateWarning,
                        trailing: {
                            if diff.reviewStatus == .pending {
                                HStack(spacing: PipiTokens.spacing8) {
                                    PipiActionButton("Approve", systemImage: "checkmark", tone: .primary, density: .desktopCompact) {
                                        Task { await store.reviewEvolutionDiff(diffId: diff.diffId, approve: true) }
                                    }
                                    PipiActionButton("Revert", systemImage: "arrow.uturn.backward", tone: .destructive, density: .desktopCompact) {
                                        Task { await store.reviewEvolutionDiff(diffId: diff.diffId, approve: false) }
                                    }
                                }
                            }
                        }
                    )
                }
            }
        }
    }

    private var iosPreviewDetail: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            Text("Stageshow Device-Pair · Live iOS Companion Preview")
                .font(PipiTokens.fontTitle)
                .foregroundStyle(PipiTokens.textPrimary)
            Text("Identical PipiBotIOSUI SwiftUI module sharing live state with macOS MenuBar & Daemon.")
                .font(PipiTokens.fontBody)
                .foregroundStyle(PipiTokens.textSecondary)

            HStack {
                Spacer()
                PipiIOSCompanionRootView(store: store)
                    .frame(width: 393, height: 760)
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radius2XL, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radius2XL, style: .continuous)
                            .stroke(PipiTokens.borderStrong, lineWidth: 6)
                    )
                Spacer()
            }
        }
    }

    private var avatarLabDetail: some View {
        let telemetry = store.avatarEngine.telemetrySnapshot()
        let statesInGroup = AvatarState53.allCases.filter {
            PipiProceduralAvatarEngine.metadata(for: $0).group == selectedAvatarGroup
        }

        return VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            HStack(spacing: PipiTokens.spacing24) {
                ZStack {
                    RoundedRectangle(cornerRadius: PipiTokens.radiusXL, style: .continuous)
                        .fill(PipiTokens.bgInset)
                        .frame(width: 240, height: 240)
                    PipiAvatarView(engine: store.avatarEngine, size: 176)
                }

                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    Text(PipiProceduralAvatarEngine.metadata(for: store.avatarEngine.state).label)
                        .font(PipiTokens.fontHero)
                        .foregroundStyle(PipiTokens.textPrimary)

                    Text("192-ray radial contour · 120 Hz Euler springs · Rodrigues 3D sphere gaze · 0.26s blink @ 45%")
                        .font(PipiTokens.fontBody)
                        .foregroundStyle(PipiTokens.textSecondary)

                    Text(String(
                        format: "Springs: amount=%.2f swap=%.2f spin=%.1f° | Gaze θ=%.2frad",
                        telemetry.springAmount,
                        telemetry.springSwap,
                        telemetry.springSpin,
                        telemetry.gazeThetaRad
                    ))
                    .font(PipiTokens.fontMono)
                    .foregroundStyle(PipiTokens.soulSecondary)

                    HStack(spacing: PipiTokens.spacing8) {
                        PipiActionButton("Blink (0.26s)", systemImage: "eye", tone: .secondary, density: .desktopCompact) {
                            store.avatarEngine.blink()
                        }
                        PipiActionButton("Poke Physics", systemImage: "hand.tap", tone: .primary, density: .desktopCompact) {
                            store.avatarEngine.poke()
                        }
                    }
                }
            }

            Picker("Lifecycle Group", selection: $selectedAvatarGroup) {
                ForEach(AvatarLifecycleGroup.allCases) { group in
                    Text(group.displayTitle).tag(group)
                }
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: PipiTokens.spacing8)], spacing: PipiTokens.spacing8) {
                ForEach(statesInGroup) { state in
                    let isSelected = store.avatarEngine.state == state
                    PipiActionButton(
                        state.rawValue,
                        tone: isSelected ? .primary : .secondary,
                        density: .desktopCompact,
                        fullWidth: true
                    ) {
                        store.avatarEngine.setState(state)
                    }
                }
            }
        }
    }
}
