import SwiftUI
import PipiBotKit

#if os(macOS)
import AppKit
#endif

// MARK: - Blueprint §7.3 Unified Session State Dot

public struct PipiSessionStateDot: View {
    public let state: PipiSessionState
    public var accent: Color
    public var isHostOffline: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: PipiSessionState, accent: Color, isHostOffline: Bool = false) {
        self.state = state
        self.accent = accent
        self.isHostOffline = isHostOffline
    }

    public var body: some View {
        if isHostOffline {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .foregroundStyle(PipiTokens.textMuted)
                .frame(width: 10, height: 10)
                .accessibilityLabel("Offline host")
        } else {
            switch state {
            case .running:
                if reduceMotion {
                    Circle()
                        .fill(accent)
                        .frame(width: 7, height: 7)
                        .frame(width: 14, height: 14)
                } else {
                    PipiDotIndicator(vitality: .busy, color: accent, size: 6)
                        .frame(width: 14, height: 14)
                }
            case .queued:
                Circle()
                    .stroke(PipiTokens.textMuted, lineWidth: 1.5)
                    .frame(width: 8, height: 8)
                    .frame(width: 14, height: 14)
            case .needsYou:
                ZStack {
                    Circle()
                        .fill(PipiTokens.stateWarning)
                        .frame(width: 13, height: 13)
                    Text("!")
                        .font(.system(size: 8.5, weight: .black, design: .rounded))
                        .foregroundStyle(PipiTokens.textInverse)
                }
                .frame(width: 14, height: 14)
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(PipiTokens.stateSuccess)
                    .frame(width: 14, height: 14)
            case .failed:
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(PipiTokens.stateError)
                    .frame(width: 14, height: 14)
            case .idle, .cancelled:
                EmptyView()
            }
        }
    }
}

// MARK: - Needs You Unified Inbox View

public struct PipiNeedsYouInboxView: View {
    @Bindable public var store: PipiAppStore
    public var onOpenSession: (String) -> Void

    @Environment(\.pipiTextScale) private var textScale

    public init(store: PipiAppStore, onOpenSession: @escaping (String) -> Void) {
        self.store = store
        self.onOpenSession = onOpenSession
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    public var body: some View {
        let _ = textScale
        let approvals = store.pendingApprovals
        let decisions = store.pendingDecisions
        let botProposals = store.pendingDynamicBotProposals

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: PipiTokens.spacing12) {
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .fill(PipiTokens.stateWarningBg)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Image(systemName: "bell.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PipiTokens.stateWarning)
                    )

                HStack(spacing: PipiTokens.spacing8) {
                    Text(s.needsYouInboxTitle)
                        .font(PipiTokens.fontTitle)
                        .tracking(PipiTokens.trackingTitle)
                        .foregroundStyle(PipiTokens.textPrimary)

                    if store.totalNeedsYouCount > 0 {
                        Text("\(store.totalNeedsYouCount)")
                            .font(PipiTokens.fontMicro)
                            .monospacedDigit()
                            .foregroundStyle(PipiTokens.textInverse)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(PipiTokens.stateWarning)
                            .clipShape(Capsule())
                    }

                    PipiInfoHelpButton(
                        title: s.needsYouInboxTitle,
                        message: s.needsYouInboxSubtitle
                    )
                }

                Spacer()
            }
            .padding(.horizontal, PipiTokens.spacing24)
            .padding(.vertical, PipiTokens.spacing16)

            Rectangle()
                .fill(PipiTokens.borderSubtle)
                .frame(height: 1)

            if approvals.isEmpty && decisions.isEmpty && botProposals.isEmpty {
                PipiEmptyState(
                    systemImage: "checkmark.seal.fill",
                    title: s.approvalsEmptyTitle,
                    message: s.approvalsEmptyMessage
                )
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                        ForEach(botProposals) { proposal in
                            PipiListCard(
                                title: "\(proposal.action.label(lang)): \(proposal.proposedName)",
                                subtitle: proposal.rationale,
                                badgeText: s.dynamicBotProposalsTitle,
                                badgeColor: PipiTokens.stateWarning,
                                footer: {
                                    HStack(spacing: PipiTokens.spacing8) {
                                        PipiActionButton(s.approveAndJoinAction, systemImage: "person.badge.plus", tone: .primary, density: .desktopCompact) {
                                            _ = store.resolveDynamicBotProposal(groupId: proposal.groupId, proposalId: proposal.id, approve: true)
                                        }
                                        PipiActionButton(s.reject, tone: .secondary, density: .desktopCompact) {
                                            _ = store.resolveDynamicBotProposal(groupId: proposal.groupId, proposalId: proposal.id, approve: false)
                                        }
                                    }
                                }
                            )
                        }

                        ForEach(approvals) { approval in
                            let session = store.conversations.first(where: { $0.id == approval.sessionId })
                            let persona = session.flatMap { conv in
                                store.personas.first(where: { $0.id == conv.personaId })
                            } ?? store.activePersona

                            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                                HStack(spacing: PipiTokens.spacing8) {
                                    PipiBotPersonaGlyph(persona: persona, size: 22, isSelected: true)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(session?.title ?? persona.name(lang))
                                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                            .lineLimit(1)
                                        Text(persona.name(lang))
                                            .font(PipiTokens.fontMicro)
                                            .foregroundStyle(PipiTokens.textMuted)
                                    }

                                    Spacer()

                                    Text(store.relativeTimeLabel(for: approval.createdAt))
                                        .font(PipiTokens.fontMonoSmall)
                                        .foregroundStyle(PipiTokens.textMuted)

                                    if let session {
                                        PipiActionButton(
                                            s.openSession,
                                            systemImage: "arrow.up.right",
                                            tone: .secondary,
                                            density: .desktopCompact
                                        ) {
                                            onOpenSession(session.id)
                                        }
                                    }
                                }

                                PipiInlineApprovalCard(approval: approval, strings: s) { optionId in
                                    Task { await store.resolveApproval(approval.id, optionId: optionId) }
                                }
                            }
                            .padding(PipiTokens.spacing16)
                            .background(PipiTokens.bgSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                        }

                        ForEach(decisions) { decision in
                            PipiListCard(
                                title: decision.title,
                                subtitle: decision.summary,
                                badgeText: s.approvalsTitle,
                                badgeColor: PipiTokens.stateWarning,
                                footer: {
                                    HStack(spacing: PipiTokens.spacing8) {
                                        if let rec = decision.options.first(where: { $0.id == decision.recommendedOptionId }) {
                                            PipiActionButton(rec.label, systemImage: "checkmark", tone: .primary, density: .desktopCompact) {
                                                Task { await store.resolveDecision(decision.id, optionId: rec.id) }
                                            }
                                        }
                                        if let deferOpt = decision.options.last, deferOpt.id != decision.recommendedOptionId {
                                            PipiActionButton(s.reject, tone: .secondary, density: .desktopCompact) {
                                                Task { await store.resolveDecision(decision.id, optionId: deferOpt.id) }
                                            }
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .frame(maxWidth: 760)
                    .padding(PipiTokens.spacing24)
                    .frame(maxWidth: .infinity)
                }
                .pipiHideScrollbars()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PipiTokens.bgCanvas)
        .background(alignment: .top) {
            PipiTokens.bgCanvas
                .frame(height: 72)
                .ignoresSafeArea(.container, edges: .top)
        }
    }
}

// MARK: - ⌘K Global Search & Command Palette

public struct PipiCommandPaletteView: View {
    @Bindable public var store: PipiAppStore
    public var onSelectConversation: (String) -> Void
    public var onSelectGroupChat: (String) -> Void
    public var onSelectBot: (String) -> Void
    public var onOpenHome: () -> Void
    public var onNewGroupChat: () -> Void
    public var onOpenNeedsYouInbox: () -> Void
    public var onToggleQuickBar: () -> Void
    public var onOpenSettings: (PipiSettingsTab) -> Void
    public var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.pipiTextScale) private var textScale

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isSearchFocused: Bool

    public init(
        store: PipiAppStore,
        onSelectConversation: @escaping (String) -> Void,
        onSelectGroupChat: @escaping (String) -> Void = { _ in },
        onSelectBot: @escaping (String) -> Void,
        onOpenHome: @escaping () -> Void = {},
        onNewGroupChat: @escaping () -> Void = {},
        onOpenNeedsYouInbox: @escaping () -> Void,
        onToggleQuickBar: @escaping () -> Void,
        onOpenSettings: @escaping (PipiSettingsTab) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.store = store
        self.onSelectConversation = onSelectConversation
        self.onSelectGroupChat = onSelectGroupChat
        self.onSelectBot = onSelectBot
        self.onOpenHome = onOpenHome
        self.onNewGroupChat = onNewGroupChat
        self.onOpenNeedsYouInbox = onOpenNeedsYouInbox
        self.onToggleQuickBar = onToggleQuickBar
        self.onOpenSettings = onOpenSettings
        self.onDismiss = onDismiss
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    private enum PaletteEntryKind {
        case command(id: String, icon: String, shortcut: String?)
        case bot(PipiBotPersona)
        case session(PipiSessionSearchMatch)
        case group(PipiGroupChat)
    }

    private struct PaletteEntry: Identifiable {
        let id: String
        let section: String
        let title: String
        let subtitle: String?
        let kind: PaletteEntryKind
    }

    private var entries: [PaletteEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var result: [PaletteEntry] = []

        // 1. Sessions (searches conversation titles + message text)
        let matchedSessions = store.searchConversations(query: query, includeArchived: true)
            .prefix(q.isEmpty ? 6 : 12)
        for match in matchedSessions {
            let botName = store.personas.first(where: { $0.id == match.conversation.personaId })?.name(lang) ?? ""
            let sub = match.matchedMessageSnippet ?? botName
            result.append(
                PaletteEntry(
                    id: "sess_\(match.conversation.id)",
                    section: s.commandPaletteSectionSessions,
                    title: match.conversation.title,
                    subtitle: sub,
                    kind: .session(match)
                )
            )
        }

        // 2. Group Chats (Swarm)
        let matchedGroups = store.sortedGroupChats.filter { group in
            q.isEmpty ||
            group.title.lowercased().contains(q) ||
            group.messages.contains { $0.content.lowercased().contains(q) }
        }.prefix(q.isEmpty ? 4 : 8)
        for group in matchedGroups {
            let names = group.participantPersonaIds.compactMap { pid in
                store.personas.first(where: { $0.id == pid })?.name(lang)
            }.joined(separator: " · ")
            result.append(
                PaletteEntry(
                    id: "grp_\(group.id)",
                    section: s.commandPaletteSectionGroups,
                    title: group.title,
                    subtitle: "\(group.swarmMode.label(lang)) · \(names)",
                    kind: .group(group)
                )
            )
        }

        // 3. Bots
        let matchedBots = store.personas.filter { persona in
            q.isEmpty ||
            persona.name(lang).lowercased().contains(q) ||
            persona.role(lang).lowercased().contains(q)
        }
        for persona in matchedBots {
            result.append(
                PaletteEntry(
                    id: "bot_\(persona.id)",
                    section: s.commandPaletteSectionBots,
                    title: persona.name(lang),
                    subtitle: persona.role(lang),
                    kind: .bot(persona)
                )
            )
        }

        // 4. Commands
        let rawCommands: [(id: String, title: String, subtitle: String, icon: String, shortcut: String?, keywords: String)] = [
            ("bot_home", s.backToBotHome, s.t("管理智能体团队、例行任务与 3D 空间", "Manage agents, routines, and 3D space"), "cpu", nil, "home 3d bots agents team routines"),
            ("new_chat", s.newChat, s.t("开启全新对话", "Start a new session"), "square.and.pencil", "⌘N", "new chat create session"),
            ("new_group", s.newGroupChat, s.t("组建多智能体协作群聊", "Create a multi-agent group chat"), "person.2", nil, "new group swarm team"),
            ("needs_you", s.needsYouInboxTitle, s.needsYouInboxSubtitle, "bell", nil, "needs you inbox approvals"),
            ("toggle_inspector", s.toggleInspector, s.t("查看详情、交付物与上下文", "View workspace details, deliverables, and context"), "sidebar.right", nil, "inspector plan diff"),
            ("quick_bar", s.quickBar, s.t("呼出全局快捷浮窗", "Summon Quick Bar"), "macwindow.on.rectangle", "⌥Space", "quick bar cue spotlight"),
            ("settings", s.settings, s.t("打开 AI 引擎与偏好设置", "Open AI engine & preferences"), "gearshape", "⌘,", "settings preferences engine"),
            ("rescan_agents", s.rescanAgents, s.t("重新探测本机 CLI Agent", "Re-scan local CLI agents"), "arrow.clockwise", "⌘R", "rescan agents claude codex")
        ]

        for cmd in rawCommands {
            let matches = q.isEmpty ||
                cmd.title.lowercased().contains(q) ||
                cmd.subtitle.lowercased().contains(q) ||
                cmd.keywords.contains(q)
            if matches {
                result.append(
                    PaletteEntry(
                        id: "cmd_\(cmd.id)",
                        section: s.commandPaletteSectionCommands,
                        title: cmd.title,
                        subtitle: cmd.subtitle,
                        kind: .command(id: cmd.id, icon: cmd.icon, shortcut: cmd.shortcut)
                    )
                )
            }
        }

        return result
    }

    public var body: some View {
        let _ = textScale
        let currentEntries = entries

        ZStack(alignment: .top) {
            PipiTokens.shadowDark
                .opacity(reduceTransparency ? 0.65 : 0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                HStack(spacing: PipiTokens.spacing12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PipiTokens.textMuted)

                    TextField(s.commandPalettePlaceholder, text: $query)
                        .textFieldStyle(.plain)
                        .font(PipiTokens.fontBody)
                        .foregroundStyle(PipiTokens.textPrimary)
                        .focused($isSearchFocused)
                        .onSubmit {
                            executeSelected(from: currentEntries)
                        }

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(s.clearFilter)
                    }

                    Text("ESC")
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PipiTokens.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .padding(.horizontal, PipiTokens.spacing16)
                .padding(.vertical, PipiTokens.spacing12)

                Rectangle()
                    .fill(PipiTokens.borderSubtle)
                    .frame(height: 1)

                if currentEntries.isEmpty {
                    Text(s.commandPaletteEmpty)
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PipiTokens.spacing32)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(currentEntries.enumerated()), id: \.element.id) { idx, entry in
                                    if idx == 0 || currentEntries[idx - 1].section != entry.section {
                                        Text(entry.section)
                                            .font(PipiTokens.fontMicro)
                                            .foregroundStyle(PipiTokens.textMuted)
                                            .textCase(.uppercase)
                                            .padding(.horizontal, PipiTokens.spacing12)
                                            .padding(.top, idx == 0 ? 6 : 10)
                                            .padding(.bottom, 2)
                                    }

                                    paletteRow(entry, isSelected: idx == selectedIndex)
                                        .id(entry.id)
                                        .onTapGesture {
                                            executeEntry(entry)
                                        }
                                }
                            }
                            .padding(.horizontal, PipiTokens.spacing8)
                            .padding(.bottom, PipiTokens.spacing8)
                        }
                        .pipiHideScrollbars()
                        .frame(maxHeight: 360)
                        .onChange(of: selectedIndex) { _, newIdx in
                            if currentEntries.indices.contains(newIdx) {
                                proxy.scrollTo(currentEntries[newIdx].id, anchor: .center)
                            }
                        }
                    }
                }
            }
            .frame(width: 560)
            .pipiLiquidGlass(cornerRadius: PipiTokens.radiusXL, shadowRadius: 28, shadowY: 14)
            .padding(.top, 72)
        }
        .onAppear {
            selectedIndex = 0
            isSearchFocused = true
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
        .onExitCommand {
            onDismiss()
        }
        .onKeyPress(.upArrow) {
            if !currentEntries.isEmpty {
                selectedIndex = (selectedIndex - 1 + currentEntries.count) % currentEntries.count
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if !currentEntries.isEmpty {
                selectedIndex = (selectedIndex + 1) % currentEntries.count
            }
            return .handled
        }
    }

    @ViewBuilder
    private func paletteRow(_ entry: PaletteEntry, isSelected: Bool) -> some View {
        HStack(spacing: PipiTokens.spacing12) {
            switch entry.kind {
            case .command(_, let icon, _):
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? PipiTokens.soulPrimary : PipiTokens.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(PipiTokens.bgSurface.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            case .bot(let persona):
                PipiBotPersonaGlyph(persona: persona, size: 24, isSelected: isSelected)
            case .session(let match):
                let persona = store.personas.first(where: { $0.id == match.conversation.personaId }) ?? store.activePersona
                PipiBotPersonaGlyph(persona: persona, size: 24, isSelected: isSelected)
            case .group:
                Image(systemName: "person.3.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isSelected ? PipiTokens.soulPrimary : PipiTokens.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(PipiTokens.bgSurface.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(PipiTokens.fontSubheadline.weight(.medium))
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)

                if let subtitle = entry.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            switch entry.kind {
            case .command(_, _, let shortcut):
                if let shortcut {
                    Text(shortcut)
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                }
            case .session(let match):
                let conv = match.conversation
                let persona = store.personas.first(where: { $0.id == conv.personaId }) ?? store.activePersona
                let accent = PipiTokens.color(for: persona.accent)
                HStack(spacing: 6) {
                    PipiSessionStateDot(
                        state: store.isRunning(conversationId: conv.id) ? .running : conv.state,
                        accent: accent,
                        isHostOffline: store.hostDescriptor(for: conv.hostId).linkState == .offline
                    )
                    Text(store.relativeTimeLabel(for: conv.updatedAt))
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                }
            case .bot:
                Text(s.filterByBotLabel)
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textMuted)
            case .group(let group):
                HStack(spacing: 6) {
                    if store.isGroupRunning(group.id) {
                        PipiSessionStateDot(state: .running, accent: PipiTokens.soulPrimary)
                    }
                    Text(store.relativeTimeLabel(for: group.updatedAt))
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                }
            }
        }
        .padding(.horizontal, PipiTokens.spacing12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                .fill(isSelected ? PipiTokens.bgSurfaceHover.opacity(0.92) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func executeSelected(from currentEntries: [PaletteEntry]) {
        guard currentEntries.indices.contains(selectedIndex) else { return }
        executeEntry(currentEntries[selectedIndex])
    }

    private func executeEntry(_ entry: PaletteEntry) {
        onDismiss()
        switch entry.kind {
        case .session(let match):
            onSelectConversation(match.conversation.id)
        case .group(let group):
            onSelectGroupChat(group.id)
        case .bot(let persona):
            onSelectBot(persona.id)
        case .command(let id, _, _):
            switch id {
            case "bot_home":
                onOpenHome()
            case "new_chat":
                _ = store.createConversation(projectId: store.activeConversation?.projectId)
            case "new_group":
                onNewGroupChat()
            case "needs_you":
                onOpenNeedsYouInbox()
            case "toggle_inspector":
                withAnimation(PipiMotion.adaptive(PipiMotion.drawer, reduceMotion: reduceMotion)) {
                    store.isInspectorPresented.toggle()
                }
            case "quick_bar":
                onToggleQuickBar()
            case "settings":
                onOpenSettings(.general)
            case "rescan_agents":
                Task { await store.refreshLocalAgents() }
            default:
                break
            }
        }
    }
}
