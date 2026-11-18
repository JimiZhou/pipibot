import SwiftUI
import PipiBotKit

#if os(iOS)
import UIKit
#endif

public enum PipiIOSTab: String, CaseIterable, Sendable, Identifiable {
    case outcomes
    case needsYou
    case muse
    case fleetSoul

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .outcomes: return "Outcomes"
        case .needsYou: return "Needs You"
        case .muse: return "Muse"
        case .fleetSoul: return "Fleet"
        }
    }

    public var iconName: String {
        switch self {
        case .outcomes: return "target"
        case .needsYou: return "tray.and.arrow.down.fill"
        case .muse: return "square.grid.2x2.fill"
        case .fleetSoul: return "circle.grid.3x3.fill"
        }
    }
}

public struct PipiIOSCompanionRootView: View {
    @Bindable public var store: PipiAppStore

    @State private var selectedTab: PipiIOSTab = .outcomes
    @State private var domainFilter: OutcomeDomain?
    @State private var showCreateOutcomeSheet = false
    @State private var showHarnessSheet = false
    @State private var newTitle = ""
    @State private var newGoal = ""
    @State private var newDomain: OutcomeDomain = .dev
    @State private var newHarness: HarnessProvider = .pi
    @State private var newBudget = "2.00"

    public init(store: PipiAppStore) {
        self.store = store
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            PipiTokens.bgCanvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                dynamicIslandHeader
                    .padding(.top, PipiTokens.spacing8)
                    .padding(.horizontal, PipiTokens.spacing16)
                    .padding(.bottom, PipiTokens.spacing12)

                Group {
                    switch selectedTab {
                    case .outcomes:
                        outcomesPage
                    case .needsYou:
                        NeedsYouSwipeDeckView(store: store, onHaptic: triggerHaptic)
                    case .muse:
                        MuseSpatialCanvasView(store: store, onOpenHarnessSheet: { showHarnessSheet = true })
                    case .fleetSoul:
                        DotsFleetAndTunnelView(store: store)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Grounded bottom bar (never box-in-box floating card)
                PipiBottomBar {
                    HStack(spacing: PipiTokens.spacing8) {
                        ForEach(PipiIOSTab.allCases) { tab in
                            bottomTabButton(tab)
                        }
                    }
                }
            }

            if showCreateOutcomeSheet {
                PipiFormSheet(
                    title: "New Outcome Contract",
                    subtitle: "Define an autonomous goal & daily budget ceiling",
                    detent: .compact,
                    submitLabel: "Launch Outcome Bot",
                    submitIcon: "sparkles",
                    onCancel: { showCreateOutcomeSheet = false },
                    onSubmit: {
                        let budget = Double(newBudget) ?? 2.0
                        Task {
                            await store.createOutcome(
                                title: newTitle,
                                domain: newDomain,
                                goal: newGoal,
                                preferredHarness: newHarness,
                                dailyBudgetUsd: budget
                            )
                            triggerHaptic(.success)
                            newTitle = ""
                            newGoal = ""
                            showCreateOutcomeSheet = false
                        }
                    }
                ) {
                    outcomeFormFields
                }
            }

            if showHarnessSheet {
                PipiSheet(
                    title: "Universal Harness Router",
                    subtitle: "Zero-duplicate-key local CLIs + BYOK pi-ai",
                    detent: .expanded,
                    onClose: { showHarnessSheet = false }
                ) {
                    harnessRouterSheetContent
                }
            }
        }
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
    }

    // MARK: - Dynamic Island Live Activity Header

    private var dynamicIslandHeader: some View {
        VStack(spacing: PipiTokens.spacing8) {
            // Single obsidian Dynamic Island pill with content on top layer
            ZStack {
                Capsule(style: .continuous)
                    .fill(PipiTokens.dynamicIslandShell)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(PipiTokens.dynamicIslandStroke, lineWidth: 1)
                    )

                HStack(spacing: PipiTokens.spacing12) {
                    PipiAvatarView(engine: store.avatarEngine, size: 28, compactMode: true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(PipiProceduralAvatarEngine.metadata(for: store.avatarEngine.state).label)
                            .font(PipiTokens.fontCaption.weight(.semibold))
                            .foregroundStyle(PipiTokens.textInverse)
                            .lineLimit(1)

                        Text("\(store.activeHarness.shortLabel) · \(store.onlineFleetCount)/\(store.fleetNodes.count) nodes")
                            .font(PipiTokens.fontMonoSmall)
                            .foregroundStyle(PipiTokens.color(for: store.activeHarness))
                            .lineLimit(1)
                    }

                    Spacer(minLength: PipiTokens.spacing4)

                    if !store.pendingDecisions.isEmpty {
                        Button {
                            selectedTab = .needsYou
                            triggerHaptic(.light)
                        } label: {
                            Text("\(store.pendingDecisions.count) Needs You")
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.stateWarning)
                                .padding(.horizontal, PipiTokens.spacing8)
                                .padding(.vertical, 4)
                                .background(PipiTokens.stateWarningBg)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        PipiDotIndicator(vitality: .alive, color: PipiTokens.stateSuccess, size: 7)
                    }
                }
                .padding(.horizontal, PipiTokens.spacing12)
            }
            .frame(height: 44)

            if let notice = store.noticeBanner {
                HStack(spacing: PipiTokens.spacing8) {
                    Circle()
                        .fill(store.connectionMode == .liveDaemon ? PipiTokens.stateSuccess : PipiTokens.soulPrimary)
                        .frame(width: 6, height: 6)
                    Text(notice)
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        Task { await store.refreshAllFromDaemon() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, PipiTokens.spacing4)
            }
        }
    }

    // MARK: - Outcomes Page

    private var filteredOutcomes: [OutcomeResponsibility] {
        guard let domainFilter else { return store.outcomes }
        return store.outcomes.filter { $0.domain == domainFilter }
    }

    private var outcomesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                PipiDock(
                    avatarEngine: store.avatarEngine,
                    title: "Outcome Manager",
                    subtitle: "\(store.outcomes.count) active responsibilities · $0 Edge",
                    actionTitle: "New Bot",
                    actionIcon: "plus",
                    density: .mobile
                ) {
                    showCreateOutcomeSheet = true
                    triggerHaptic(.medium)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PipiTokens.spacing8) {
                        domainChip(title: "All", domain: nil)
                        ForEach(OutcomeDomain.allCases) { domain in
                            domainChip(title: domain.displayName, domain: domain)
                        }
                    }
                }

                if filteredOutcomes.isEmpty {
                    PipiEmptyState(
                        systemImage: "target",
                        title: "No Outcomes in This Domain",
                        message: "Create an autonomous Outcome Bot to monitor goals, delegate child sessions, and surface clean decisions.",
                        buttonTitle: "Create Outcome",
                        buttonAction: { showCreateOutcomeSheet = true }
                    )
                    .padding(.vertical, PipiTokens.spacing24)
                } else {
                    ForEach(filteredOutcomes) { outcome in
                        let statusColor = statusBadgeColor(outcome.status)
                        PipiListCard(
                            title: outcome.title,
                            subtitle: outcome.goal,
                            badgeText: outcome.status.displayLabel,
                            badgeColor: statusColor,
                            leading: {
                                Image(systemName: iconForDomain(outcome.domain))
                                    .font(.system(size: PipiTokens.buttonIconMobile, weight: .semibold))
                                    .foregroundStyle(PipiTokens.color(for: outcome.domain))
                                    .frame(width: 38, height: 38)
                                    .background(PipiTokens.color(for: outcome.domain).opacity(0.14))
                                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                            },
                            trailing: {
                                Text(outcome.preferredHarness.shortLabel)
                                    .font(PipiTokens.fontMonoSmall)
                                    .foregroundStyle(PipiTokens.color(for: outcome.preferredHarness))
                                    .padding(.horizontal, PipiTokens.spacing8)
                                    .padding(.vertical, 4)
                                    .background(PipiTokens.bgInset)
                                    .clipShape(Capsule())
                            },
                            footer: {
                                HStack(spacing: PipiTokens.spacing8) {
                                    Text(String(format: "$%.2f / $%.2f today", outcome.spentTodayUsd, outcome.dailyBudgetUsd))
                                        .font(PipiTokens.fontMonoSmall)
                                        .foregroundStyle(PipiTokens.textMuted)

                                    Spacer()

                                    PipiActionButton(
                                        "Evaluate",
                                        systemImage: "play.fill",
                                        tone: .secondary,
                                        density: .mobile
                                    ) {
                                        Task {
                                            await store.evaluateOutcome(outcome.id)
                                            triggerHaptic(.light)
                                        }
                                    }
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, PipiTokens.spacing16)
            .padding(.bottom, PipiTokens.spacing24)
        }
    }

    private func domainChip(title: String, domain: OutcomeDomain?) -> some View {
        let isSelected = domainFilter == domain
        return Button {
            domainFilter = domain
            triggerHaptic(.light)
        } label: {
            Text(title)
                .font(PipiTokens.fontCaption.weight(.semibold))
                .foregroundStyle(isSelected ? PipiTokens.textInverse : PipiTokens.textSecondary)
                .padding(.horizontal, PipiTokens.spacing12)
                .frame(height: 32)
                .background(isSelected ? PipiTokens.soulPrimary : PipiTokens.bgSurface)
                .overlay(
                    Capsule().stroke(isSelected ? PipiTokens.soulPrimary : PipiTokens.borderSubtle, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Form Sheet Fields

    private var outcomeFormFields: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                Text("Bot Title")
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)
                TextField("e.g., Weekly API Parity Bot", text: $newTitle)
                    .textFieldStyle(.plain)
                    .padding(PipiTokens.spacing12)
                    .background(PipiTokens.bgSurface)
                    .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusSM).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM))
            }

            VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                Text("Outcome Goal")
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)
                TextField("Describe target end-state & success metrics", text: $newGoal, axis: .vertical)
                    .lineLimit(3...5)
                    .textFieldStyle(.plain)
                    .padding(PipiTokens.spacing12)
                    .background(PipiTokens.bgSurface)
                    .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusSM).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM))
            }

            HStack(spacing: PipiTokens.spacing12) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                    Text("Domain")
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                    Picker("Domain", selection: $newDomain) {
                        ForEach(OutcomeDomain.allCases) { d in
                            Text(d.displayName).tag(d)
                        }
                    }
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                    Text("Harness")
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                    Picker("Harness", selection: $newHarness) {
                        ForEach(HarnessProvider.allCases) { h in
                            Text(h.shortLabel).tag(h)
                        }
                    }
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                    Text("USD/day")
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                    TextField("2.00", text: $newBudget)
                        .textFieldStyle(.plain)
                        .padding(PipiTokens.spacing8)
                        .frame(width: 72)
                        .background(PipiTokens.bgSurface)
                        .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusXS).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusXS))
                }
            }
        }
    }

    // MARK: - Harness Router Sheet Content

    private var harnessRouterSheetContent: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            ForEach(store.harnessProbes) { probe in
                let isSelected = store.activeHarness == probe.provider
                let accent = PipiTokens.color(for: probe.provider)
                PipiListCard(
                    title: probe.provider.displayName,
                    subtitle: "\(probe.binaryPath ?? "runtime") · \(probe.authSource ?? "local auth")",
                    badgeText: isSelected ? "Active" : (probe.authenticated ? "Ready" : "Offline"),
                    badgeColor: isSelected ? accent : (probe.authenticated ? PipiTokens.stateSuccess : PipiTokens.textMuted),
                    trailing: {
                        PipiActionButton(
                            isSelected ? "Selected" : "Route Here",
                            systemImage: isSelected ? "checkmark" : "arrow.triangle.branch",
                            tone: isSelected ? .primary : .secondary,
                            density: .mobile
                        ) {
                            store.activeHarness = probe.provider
                            store.avatarEngine.setState(store.avatarState(for: probe.provider))
                            triggerHaptic(.medium)
                            showHarnessSheet = false
                        }
                    }
                )
            }
        }
    }

    // MARK: - Bottom Bar Button

    private func bottomTabButton(_ tab: PipiIOSTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
            triggerHaptic(.light)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: tab.iconName)
                        .font(.system(size: PipiTokens.buttonIconMobile, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? PipiTokens.soulPrimary : PipiTokens.textMuted)
                        .frame(height: 22)

                    if tab == .needsYou && !store.pendingDecisions.isEmpty {
                        Circle()
                            .fill(PipiTokens.stateError)
                            .frame(width: 7, height: 7)
                            .offset(x: 5, y: -1)
                    }
                }

                Text(tab.title)
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: PipiTokens.buttonHeightMobile)
            .background(isSelected ? PipiTokens.soulPrimary.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func iconForDomain(_ domain: OutcomeDomain) -> String {
        switch domain {
        case .dev: return "chevron.left.forwardslash.chevron.right"
        case .work: return "briefcase.fill"
        case .dailyLife: return "heart.text.square.fill"
        case .infra: return "server.rack"
        }
    }

    private func statusBadgeColor(_ status: OutcomeStatus) -> Color {
        switch status {
        case .active, .achieved: return PipiTokens.stateSuccess
        case .evaluating, .delegating: return PipiTokens.stateInfo
        case .needsYou: return PipiTokens.stateWarning
        case .paused: return PipiTokens.textMuted
        case .failed: return PipiTokens.stateError
        }
    }

    public enum HapticKind: Sendable {
        case light
        case medium
        case success
    }

    private func triggerHaptic(_ kind: HapticKind) {
        #if os(iOS)
        switch kind {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        #else
        _ = kind
        #endif
    }
}
