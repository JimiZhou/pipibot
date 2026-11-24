import SwiftUI
import PipiBotKit

private enum PipiBotsHubMode: String, CaseIterable, Identifiable {
    case cards
    case space3D

    var id: String { rawValue }

    func label(_ s: PipiStrings) -> String {
        switch self {
        case .cards: return s.t("卡片", "Cards")
        case .space3D: return s.t("3D 空间", "3D Space")
        }
    }
}

private enum PipiBotLiveState {
    case idle
    case working
    case needsYou
    case collaborating
}

public struct PipiBotsHubView: View {
    @Bindable public var store: PipiAppStore
    public var collaboratingBotIds: Set<String>
    public var externalResetTrigger: Int
    public var onOpenBotChat: (PipiBotPersona) -> Void
    public var onQuickSendToBot: (PipiBotPersona, String) -> Void
    public var onStartVoiceCall: (PipiBotPersona) -> Void
    public var onCreateBot: () -> Void
    public var onEditBot: (PipiBotPersona) -> Void
    public var onDeleteBot: (PipiBotPersona) -> Void
    public var onCreateGroupChat: (String?) -> Void
    public var onOpenSession: (String) -> Void

    @Environment(\.pipiTextScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mode: PipiBotsHubMode = .cards
    @State private var selectedDetailBotId: String? = nil
    @State private var hoveredBotId: String? = nil

    public init(
        store: PipiAppStore,
        collaboratingBotIds: Set<String> = [],
        externalResetTrigger: Int = 0,
        onOpenBotChat: @escaping (PipiBotPersona) -> Void = { _ in },
        onQuickSendToBot: @escaping (PipiBotPersona, String) -> Void = { _, _ in },
        onStartVoiceCall: @escaping (PipiBotPersona) -> Void = { _ in },
        onCreateBot: @escaping () -> Void = {},
        onEditBot: @escaping (PipiBotPersona) -> Void = { _ in },
        onDeleteBot: @escaping (PipiBotPersona) -> Void = { _ in },
        onCreateGroupChat: @escaping (String?) -> Void = { _ in },
        onOpenSession: @escaping (String) -> Void = { _ in }
    ) {
        self.store = store
        self.collaboratingBotIds = collaboratingBotIds
        self.externalResetTrigger = externalResetTrigger
        self.onOpenBotChat = onOpenBotChat
        self.onQuickSendToBot = onQuickSendToBot
        self.onStartVoiceCall = onStartVoiceCall
        self.onCreateBot = onCreateBot
        self.onEditBot = onEditBot
        self.onDeleteBot = onDeleteBot
        self.onCreateGroupChat = onCreateGroupChat
        self.onOpenSession = onOpenSession
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    private var detailBotBinding: Binding<PipiBotPersona?> {
        Binding(
            get: {
                guard let id = selectedDetailBotId else { return nil }
                return store.personas.first(where: { $0.id == id })
            },
            set: { selectedDetailBotId = $0?.id }
        )
    }

    public var body: some View {
        let _ = textScale

        VStack(spacing: 0) {
            headerBar

            Rectangle()
                .fill(PipiTokens.borderSubtle)
                .frame(height: 1)

            if mode == .cards {
                cardsGridStage
            } else {
                PipiBotHomeSceneView(
                    store: store,
                    collaboratingBotIds: collaboratingBotIds,
                    showTopHUD: false,
                    externalResetTrigger: externalResetTrigger,
                    onOpenBotChat: onOpenBotChat,
                    onQuickSendToBot: onQuickSendToBot,
                    onStartVoiceCall: onStartVoiceCall,
                    onCreateBot: onCreateBot,
                    onEditBot: onEditBot,
                    onCreateGroupChat: onCreateGroupChat
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PipiTokens.bgCanvas)
        .background(alignment: .top) {
            PipiTokens.bgCanvas
                .frame(height: 72)
                .ignoresSafeArea(.container, edges: .top)
        }
        .sheet(item: detailBotBinding) { bot in
            PipiBotDetailSheet(
                store: store,
                persona: bot,
                onEditBot: {
                    selectedDetailBotId = nil
                    onEditBot(bot)
                },
                onOpenConversation: { convId in
                    selectedDetailBotId = nil
                    onOpenSession(convId)
                },
                onClose: {
                    selectedDetailBotId = nil
                }
            )
            .environment(\.pipiTextScale, store.uiZoomScale)
            .frame(minWidth: 540, minHeight: 520)
        }
    }

    // MARK: - Top Header Bar

    private var headerBar: some View {
        HStack(spacing: PipiTokens.spacing12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.botHome)
                    .font(PipiTokens.fontTitle)
                    .tracking(PipiTokens.trackingTitle)
                    .foregroundStyle(PipiTokens.textPrimary)

                Text(summaryText)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
            }

            Spacer(minLength: PipiTokens.spacing12)

            PipiSegmentedControl(
                options: PipiBotsHubMode.allCases,
                selection: $mode
            ) { item in
                item.label(s)
            }

            PipiActionButton(
                s.newGroupChat,
                systemImage: "person.2",
                tone: .secondary,
                density: .desktopCompact
            ) {
                onCreateGroupChat(nil)
            }

            PipiActionButton(
                s.newBot,
                systemImage: "plus",
                tone: .primary,
                density: .desktopCompact
            ) {
                onCreateBot()
            }
        }
        .padding(.horizontal, PipiTokens.spacing24)
        .padding(.vertical, PipiTokens.spacing16)
        .background(PipiTokens.bgCanvas)
    }

    // MARK: - Default Cards Grid

    private var cardsGridStage: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 340, maximum: 560), spacing: PipiTokens.spacing20)
                ],
                spacing: PipiTokens.spacing20
            ) {
                ForEach(store.personas) { bot in
                    botCard(bot)
                }
            }
            .padding(PipiTokens.spacing24)
            .frame(maxWidth: 1160)
            .frame(maxWidth: .infinity)
        }
        .pipiHideScrollbars()
        .clipped()
        .background(PipiTokens.bgSurface.opacity(0.55))
    }

    private func botCard(_ bot: PipiBotPersona) -> some View {
        let state = liveState(for: bot)
        let accent = PipiTokens.color(for: bot.accent)
        let isHovered = hoveredBotId == bot.id
        let routineCount = store.routines.filter { $0.personaId == bot.id }.count
        let engineLabel = preferredEngineDisplayLabel(for: bot)

        return VStack(alignment: .leading, spacing: 18) {
            Button {
                onOpenBotChat(bot)
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    PipiBotPersonaGlyph(persona: bot, size: 44, isSelected: true)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: PipiTokens.spacing8) {
                            Text(bot.name(lang))
                                .font(PipiTokens.fontHeadline)
                                .tracking(PipiTokens.trackingHeadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            statePill(state: state, accent: accent)
                        }

                        Text(bot.role(lang))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .lineSpacing(3)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(minHeight: 36, alignment: .topLeading)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: PipiTokens.spacing8) {
                Text("\(engineLabel) · \(bot.permissionTier.label(lang)) · \(s.t("\(routineCount) 条例行", "\(routineCount) \(routineCount == 1 ? "routine" : "routines")"))")
                    .font(PipiTokens.fontMicro.weight(.regular))
                    .foregroundStyle(PipiTokens.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                HStack(spacing: 4) {
                    Button {
                        selectedDetailBotId = bot.id
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(PipiTokens.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(isHovered ? PipiTokens.bgSurfaceHover : Color.clear, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(s.routinesTitle)
                    .accessibilityLabel(s.routinesTitle)
                    .opacity(isHovered ? 1.0 : 0.55)

                    Menu {
                        Button {
                            onOpenBotChat(bot)
                        } label: {
                            Label(s.t("开始任务", "Start task"), systemImage: "arrow.up.right")
                        }
                        Button {
                            selectedDetailBotId = bot.id
                        } label: {
                            Label(s.routinesTitle, systemImage: "clock.arrow.circlepath")
                        }
                        Button {
                            onEditBot(bot)
                        } label: {
                            Label(s.editBotTitle, systemImage: "pencil")
                        }
                        Button {
                            onCreateGroupChat(bot.id)
                        } label: {
                            Label(s.t("发起群聊", "Group Chat"), systemImage: "person.2")
                        }
                        if store.personas.count > 1 {
                            Divider()
                            Button(role: .destructive) {
                                onDeleteBot(bot)
                            } label: {
                                Label(s.delete, systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(PipiTokens.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(isHovered ? PipiTokens.bgSurfaceHover : Color.clear, in: Circle())
                    }
                    .pipiPlainMenu()
                    .fixedSize()
                    .help(s.t("更多操作", "More actions"))
                    .accessibilityLabel(s.t("更多操作", "More actions"))
                    .opacity(isHovered ? 1.0 : 0.55)

                    Button {
                        onOpenBotChat(bot)
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isHovered ? PipiTokens.textInverse : PipiTokens.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(isHovered ? PipiTokens.soulPrimary : PipiTokens.bgSurface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(s.t("开始任务", "Start task"))
                    .accessibilityLabel(s.t("开始任务", "Start task"))
                }
            }
        }
        .padding(PipiTokens.spacing20)
        .pipiAppleCard(cornerRadius: 16, elevated: true)
        .scaleEffect(isHovered ? 1.006 : 1.0)
        .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: isHovered)
        .onHover { hovering in
            hoveredBotId = hovering ? bot.id : (hoveredBotId == bot.id ? nil : hoveredBotId)
        }
    }

    @ViewBuilder
    private func statePill(state: PipiBotLiveState, accent: Color) -> some View {
        switch state {
        case .idle:
            HStack(spacing: 5) {
                Circle()
                    .fill(PipiTokens.textMuted.opacity(0.55))
                    .frame(width: 5.5, height: 5.5)
                Text(s.t("待命", "Ready"))
                    .font(PipiTokens.fontMicro.weight(.regular))
                    .foregroundStyle(PipiTokens.textMuted)
            }

        case .working:
            HStack(spacing: 5) {
                PipiDotIndicator(vitality: .busy, color: accent, size: 5.5)
                Text(s.t("运行中", "Running"))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textPrimary)
            }

        case .needsYou:
            HStack(spacing: 5) {
                Circle()
                    .fill(PipiTokens.stateWarning)
                    .frame(width: 5.5, height: 5.5)
                Text(s.needsYouLabel)
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.stateWarning)
            }

        case .collaborating:
            HStack(spacing: 5) {
                Circle()
                    .fill(PipiTokens.soulSecondary)
                    .frame(width: 5.5, height: 5.5)
                Text(s.t("协作中", "Collab"))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.soulSecondary)
            }
        }
    }

    private func metadataPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
            Text(text)
                .font(PipiTokens.fontMicro)
                .lineLimit(1)
        }
        .foregroundStyle(PipiTokens.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(PipiTokens.bgInset, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Helpers

    private func liveState(for persona: PipiBotPersona) -> PipiBotLiveState {
        let hasPendingApproval = store.conversations.contains { conv in
            conv.personaId == persona.id &&
            (conv.state == .needsYou || conv.approvals.contains { $0.status == .pending })
        }
        if hasPendingApproval { return .needsYou }
        if collaboratingBotIds.contains(persona.id) { return .collaborating }
        if store.isPersonaRunning(persona.id) { return .working }
        return .idle
    }

    private func preferredEngineDisplayLabel(for persona: PipiBotPersona) -> String {
        let modelOverride = persona.preferredModelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch persona.preferredTarget {
        case .auto:
            if let modelOverride, !modelOverride.isEmpty {
                return modelOverride
            }
            return s.t("默认模型", "Default")
        case .llm(let pid):
            if let cfg = store.llmProviders.first(where: { $0.id == pid }) {
                return (modelOverride?.isEmpty == false) ? modelOverride! : cfg.modelId
            }
            return (modelOverride?.isEmpty == false) ? modelOverride! : s.t("默认模型", "Default")
        case .localAgent(let kind):
            if let modelOverride, !modelOverride.isEmpty {
                return "\(kind.displayName) · \(modelOverride)"
            }
            return kind.displayName
        }
    }

    private var summaryText: String {
        let total = store.personas.count
        let activeCount = store.personas.filter {
            let st = liveState(for: $0)
            return st == .working || st == .collaborating
        }.count
        let needsCount = store.personas.filter { liveState(for: $0) == .needsYou }.count

        var parts: [String] = [
            s.t("\(total) 位智能体", "\(total) \(total == 1 ? "Agent" : "Agents")")
        ]
        if activeCount > 0 {
            parts.append(s.t("\(activeCount) 运行中", "\(activeCount) Running"))
        }
        if needsCount > 0 {
            parts.append(s.t("\(needsCount) 待确认", "\(needsCount) Needs You"))
        }
        if activeCount == 0 && needsCount == 0 {
            parts.append(s.t("全部待命", "All Ready"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Bot Detail & Routines Sheet (Migrated from Right Inspector)

public struct PipiBotDetailSheet: View {
    @Bindable public var store: PipiAppStore
    public let persona: PipiBotPersona
    public var onEditBot: () -> Void
    public var onOpenConversation: (String) -> Void
    public var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pipiTextScale) private var textScale

    @State private var showAddRoutine = false
    @State private var routineTitle = ""
    @State private var routinePrompt = ""
    @State private var routineSchedule: PipiRoutineSchedule = .daily
    @State private var routineHour: Int = 9
    @State private var routineMinute: Int = 0
    @State private var routineWeekday: Int = 2

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    private var livePersona: PipiBotPersona {
        store.personas.first(where: { $0.id == persona.id }) ?? persona
    }

    private var accent: Color {
        PipiTokens.color(for: livePersona.accent)
    }

    private var botRoutines: [PipiBotRoutine] {
        store.routines.filter { $0.personaId == livePersona.id }
    }

    private var botRunRecords: [PipiRunRecord] {
        Array(store.runRecords.filter { $0.personaId == livePersona.id }.prefix(8))
    }

    public var body: some View {
        let _ = textScale
        VStack(spacing: 0) {
            // Header
            HStack(spacing: PipiTokens.spacing12) {
                PipiBotPersonaGlyph(persona: livePersona, size: 42, isSelected: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(livePersona.name(lang))
                        .font(PipiTokens.fontTitle)
                        .tracking(PipiTokens.trackingTitle)
                        .foregroundStyle(PipiTokens.textPrimary)

                    Text(livePersona.role(lang))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: PipiTokens.spacing8)

                PipiActionButton(
                    s.editBotTitle,
                    systemImage: "pencil",
                    tone: .secondary,
                    density: .desktopCompact
                ) {
                    onEditBot()
                }

                PipiGhostIconButton(
                    systemImage: "xmark",
                    size: 28,
                    iconSize: 12,
                    cornerRadius: PipiTokens.radiusPill,
                    accessibilityLabel: s.close,
                    action: onClose
                )
            }
            .padding(.horizontal, PipiTokens.spacing24)
            .padding(.vertical, PipiTokens.spacing16)

            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
                    // 1. Permission Tier Quick Picker
                    VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                        Text(s.permissionTierTitle)
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textMuted)

                        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                            PipiSegmentedControl(
                                options: PipiPermissionTier.allCases,
                                selection: Binding(
                                    get: { livePersona.permissionTier },
                                    set: { newTier in
                                        var updated = livePersona
                                        updated.permissionTier = newTier
                                        store.upsertPersona(updated)
                                    }
                                )
                            ) { tier in
                                tier.label(lang)
                            }

                            Text(livePersona.permissionTier.description(lang))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                        }
                        .padding(PipiTokens.spacing12)
                        .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                    }

                    // 2. Routines (Prompt-to-Schedule)
                    VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                        HStack {
                            Text(s.routinesTitle)
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textMuted)
                            Spacer()
                            PipiGhostIconButton(
                                systemImage: showAddRoutine ? "minus" : "plus",
                                size: 24,
                                iconSize: 11,
                                cornerRadius: 6,
                                accessibilityLabel: s.addRoutine
                            ) {
                                withAnimation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion)) {
                                    showAddRoutine.toggle()
                                }
                            }
                            .help(s.addRoutine)
                        }

                        if showAddRoutine {
                            addRoutineInlineForm
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if botRoutines.isEmpty && !showAddRoutine {
                            Text(s.routinesEmpty)
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textMuted)
                                .padding(PipiTokens.spacing12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(PipiTokens.bgSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                        .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                        } else {
                            ForEach(botRoutines) { routine in
                                routineRow(routine)
                            }
                        }
                    }

                    // 3. Recent Runs for this Bot
                    VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                        Text(s.activityTitle)
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textMuted)

                        if botRunRecords.isEmpty {
                            Text(s.activityEmpty)
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textMuted)
                                .padding(PipiTokens.spacing12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(PipiTokens.bgSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                        .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                        } else {
                            ForEach(botRunRecords) { run in
                                runActivityRow(run)
                            }
                        }
                    }
                }
                .padding(PipiTokens.spacing24)
            }
        }
        .background(PipiTokens.bgElevated)
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
    }

    private var addRoutineInlineForm: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            TextField(s.routineTitlePlaceholder, text: $routineTitle)
                .textFieldStyle(.plain)
                .font(PipiTokens.fontCaption)
                .padding(PipiTokens.spacing8)
                .background(PipiTokens.bgInset)
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

            TextField(s.routinePromptPlaceholder, text: $routinePrompt, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .font(PipiTokens.fontCaption)
                .padding(PipiTokens.spacing8)
                .background(PipiTokens.bgInset)
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

            HStack(spacing: PipiTokens.spacing12) {
                Picker("", selection: $routineSchedule) {
                    ForEach(PipiRoutineSchedule.allCases) { kind in
                        Text(kind.label(lang)).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                if routineSchedule == .weekly {
                    Picker(s.routineWeekdayLabel, selection: $routineWeekday) {
                        ForEach(PipiBotRoutine.orderedWeekdays, id: \.self) { day in
                            Text(PipiBotRoutine.weekdayShortLabel(day, lang)).tag(day)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }

                if routineSchedule == .hourly {
                    HStack(spacing: PipiTokens.spacing8) {
                        Text(s.routineMinuteLabel)
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textMuted)
                        Picker(s.routineMinuteLabel, selection: $routineMinute) {
                            ForEach(0..<60, id: \.self) { m in
                                Text(String(format: ":%02d", m)).tag(m)
                            }
                        }
                        .labelsHidden()
                        .font(PipiTokens.fontMonoSmall)
                    }
                } else if routineSchedule == .daily || routineSchedule == .weekly {
                    HStack(spacing: PipiTokens.spacing4) {
                        Picker(s.routineHourLabel, selection: $routineHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(String(format: "%02d", h)).tag(h)
                            }
                        }
                        .labelsHidden()
                        .font(PipiTokens.fontMonoSmall)

                        Text(":")
                            .font(PipiTokens.fontMonoSmall)
                            .foregroundStyle(PipiTokens.textMuted)

                        Picker(s.routineMinuteLabel, selection: $routineMinute) {
                            ForEach(0..<60, id: \.self) { m in
                                Text(String(format: "%02d", m)).tag(m)
                            }
                        }
                        .labelsHidden()
                        .font(PipiTokens.fontMonoSmall)
                    }
                }
            }

            HStack {
                PipiActionButton(s.cancel, tone: .ghost, density: .desktopCompact) {
                    withAnimation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion)) {
                        showAddRoutine = false
                    }
                }
                Spacer()
                PipiActionButton(s.save, systemImage: "checkmark", tone: .primary, density: .desktopCompact) {
                    let cleanTitle = routineTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanPrompt = routinePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanTitle.isEmpty, !cleanPrompt.isEmpty else { return }
                    let rt = PipiBotRoutine(
                        personaId: livePersona.id,
                        title: cleanTitle,
                        prompt: cleanPrompt,
                        schedule: routineSchedule,
                        hour: routineHour,
                        minute: routineMinute,
                        weekday: routineWeekday
                    )
                    store.addRoutine(rt)
                    routineTitle = ""
                    routinePrompt = ""
                    withAnimation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion)) {
                        showAddRoutine = false
                    }
                }
                .disabled(
                    routineTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    routinePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(PipiTokens.spacing12)
        .background(PipiTokens.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderStrong, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }

    private func routineRow(_ routine: PipiBotRoutine) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack(spacing: PipiTokens.spacing8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.title)
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                        .lineLimit(1)
                    Text(routine.scheduleBadge(lang))
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { routine.isEnabled },
                    set: { store.toggleRoutine(id: routine.id, enabled: $0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            if !routine.prompt.isEmpty {
                Text(routine.prompt)
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textMuted)
                    .lineLimit(2)
            }

            HStack(spacing: PipiTokens.spacing8) {
                PipiActionButton(
                    s.runNow,
                    systemImage: "play.fill",
                    tone: .secondary,
                    density: .desktopCompact
                ) {
                    Task { await store.runRoutineNow(routine) }
                }

                Spacer()

                PipiGhostIconButton(
                    systemImage: "trash",
                    size: 26,
                    iconSize: 11,
                    accessibilityLabel: s.delete
                ) {
                    store.deleteRoutine(id: routine.id)
                }
                .help(s.delete)
            }
        }
        .padding(PipiTokens.spacing12)
        .background(PipiTokens.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }

    private func runActivityRow(_ run: PipiRunRecord) -> some View {
        let dotColor: Color = {
            switch run.status {
            case .running: return accent
            case .succeeded: return PipiTokens.stateSuccess
            case .failed: return PipiTokens.stateError
            case .cancelled: return PipiTokens.textMuted
            }
        }()

        return Button {
            onOpenConversation(run.conversationId)
        } label: {
            HStack(spacing: PipiTokens.spacing8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(run.promptPreview)
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(run.engineLabel)
                            .lineLimit(1)
                        if run.durationMs > 0 {
                            Text(String(format: "· %.1fs", Double(run.durationMs) / 1000.0))
                        }
                    }
                    .font(PipiTokens.fontMonoSmall)
                    .foregroundStyle(PipiTokens.textMuted)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(PipiTokens.textMuted)
            }
            .padding(.horizontal, PipiTokens.spacing12)
            .padding(.vertical, PipiTokens.spacing8)
            .background(PipiTokens.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.99))
    }
}
