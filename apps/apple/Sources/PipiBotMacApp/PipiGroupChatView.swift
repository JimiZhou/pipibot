import SwiftUI
import PipiBotKit
#if os(macOS)
import AppKit
#endif

// MARK: - Multi-Bot Group Chat View

public struct PipiGroupChatView: View {
    @Bindable var store: PipiAppStore
    public let groupId: String
    @Binding public var pendingMentionInsert: String?
    public var onOpenSettings: (() -> Void)?
    public var onOpenMembersInspector: (() -> Void)?

    @Environment(\.pipiTextScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draftText: String = ""
    @State private var isAssignmentsExpanded: Bool = true
    @State private var isShowingEditor: Bool = false
    @State private var isShowingMentionMenu: Bool = false
    @State private var isShowingAddTopic: Bool = false
    @State private var newTopicTitle: String = ""
    @State private var hoveredMessageId: String?
    @State private var copiedMessageId: String?
    @State private var savedDeliverableMessageId: String?
    @State private var savedMemoryMessageId: String?
    @FocusState private var isComposerFocused: Bool

    public init(
        store: PipiAppStore,
        groupId: String,
        pendingMentionInsert: Binding<String?> = .constant(nil),
        onOpenSettings: (() -> Void)? = nil,
        onOpenMembersInspector: (() -> Void)? = nil
    ) {
        self.store = store
        self.groupId = groupId
        self._pendingMentionInsert = pendingMentionInsert
        self.onOpenSettings = onOpenSettings
        self.onOpenMembersInspector = onOpenMembersInspector
    }

    private var group: PipiGroupChat? {
        store.groupChats.first(where: { $0.id == groupId })
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    private func participants(for group: PipiGroupChat) -> [PipiBotPersona] {
        group.participantPersonaIds.compactMap { pid in
            store.personas.first(where: { $0.id == pid })
        }
    }

    public var body: some View {
        let _ = textScale
        Group {
            if let group {
                let members = participants(for: group)
                let isRunning = store.isGroupRunning(group.id)

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(PipiTokens.borderSubtle)
                        .frame(height: 1)

                    topicSwitcherStrip(group: group)

                    let lanes = store.activeLanes(forGroup: group.id)
                    if !lanes.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: PipiTokens.spacing8) {
                                ForEach(lanes) { lane in
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.mini)
                                        Text("\(lane.personaName) [\(lane.hostLabel)]")
                                            .font(PipiTokens.fontMicro.weight(.semibold))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                        Text(lane.statusText)
                                            .font(PipiTokens.fontMicro)
                                            .foregroundStyle(PipiTokens.textSecondary)
                                            .lineLimit(1)
                                        Button {
                                            store.stopGroupLane(lane.runId)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 11))
                                                .foregroundStyle(PipiTokens.textMuted)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(PipiTokens.bgSurface)
                                    .overlay(
                                        Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1)
                                    )
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, PipiTokens.spacing16)
                            .padding(.vertical, 6)
                        }
                        .background(PipiTokens.bgElevated)
                    }

                    Rectangle()
                        .fill(PipiTokens.borderSubtle)
                        .frame(height: 1)

                    if !group.assignments.isEmpty {
                        assignmentsBoard(group: group)
                        Rectangle()
                            .fill(PipiTokens.borderSubtle)
                            .frame(height: 1)
                    }

                    transcriptArea(group: group, members: members)

                    composerArea(group: group, members: members, isRunning: isRunning)
                }
                .background(PipiTokens.bgCanvas)
                .background(alignment: .top) {
                    PipiTokens.bgCanvas
                        .frame(height: 72)
                        .ignoresSafeArea(.container, edges: .top)
                }
                .sheet(isPresented: $isShowingEditor) {
                    PipiGroupCreatorSheet(store: store, editingGroup: group)
                }
                .onChange(of: pendingMentionInsert) { _, newValue in
                    if let token = newValue, !token.isEmpty {
                        let clean = token.hasPrefix("@") ? String(token.dropFirst()).trimmingCharacters(in: .whitespaces) : token.trimmingCharacters(in: .whitespaces)
                        if !clean.isEmpty {
                            insertMentionToken(clean)
                            isComposerFocused = true
                        }
                        pendingMentionInsert = nil
                    }
                }
            } else {
                VStack(spacing: PipiTokens.spacing12) {
                    Image(systemName: "person.3")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(PipiTokens.textMuted)
                    Text(s.t("未找到该协作群", "Group chat not found"))
                        .font(PipiTokens.fontHeadline)
                        .foregroundStyle(PipiTokens.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PipiTokens.bgCanvas)
            }
        }
    }

    // MARK: - Quiet Topic Switcher Strip

    @ViewBuilder
    private func topicSwitcherStrip(group: PipiGroupChat) -> some View {
        let activeTopic = group.activeTopic

        HStack(spacing: PipiTokens.spacing8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(group.topics) { topic in
                        let isSelected = topic.id == activeTopic.id
                        let topicCount = group.messages(forTopic: topic.isDefault ? nil : topic.id).count
                        Button {
                            withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                                store.selectGroupTopic(groupId: group.id, topicId: topic.isDefault ? nil : topic.id)
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text("#")
                                    .font(PipiTokens.fontCaption.weight(.bold))
                                    .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textMuted)
                                Text(topic.localizedTitle(lang))
                                    .font(PipiTokens.fontCaption.weight(isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                                    .lineLimit(1)
                                if topicCount > 0 {
                                    Text("\(topicCount)")
                                        .font(PipiTokens.fontMonoSmall)
                                        .monospacedDigit()
                                        .foregroundStyle(PipiTokens.textMuted)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(
                                isSelected ? PipiTokens.bgSurfaceHover : Color.clear,
                                in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                    .stroke(isSelected ? PipiTokens.borderSubtle : Color.clear, lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))
                        .contextMenu {
                            if !topic.isDefault {
                                Button(s.delete, role: .destructive) {
                                    store.deleteGroupTopic(groupId: group.id, topicId: topic.id)
                                }
                            }
                        }
                    }

                    Button {
                        newTopicTitle = ""
                        isShowingAddTopic = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text(s.t("话题", "Topic"))
                                .font(PipiTokens.fontCaption.weight(.medium))
                        }
                        .foregroundStyle(PipiTokens.textSecondary)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                    .popover(isPresented: $isShowingAddTopic, arrowEdge: .bottom) {
                        addTopicPopover(group: group)
                    }
                }
                .padding(.vertical, 6)
            }

            Spacer(minLength: 4)

            if !group.longTasks.filter({ $0.status == .active }).isEmpty {
                let activeTaskCount = group.longTasks.filter { $0.status == .active }.count
                Button {
                    onOpenMembersInspector?()
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(PipiTokens.stateSuccess)
                            .frame(width: 5.5, height: 5.5)
                        Text(s.t("\(activeTaskCount) 项长期任务", "\(activeTaskCount) Active Tasks"))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PipiTokens.bgSurface, in: Capsule())
                    .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .background(PipiTokens.bgCanvas)
    }

    private func addTopicPopover(group: PipiGroupChat) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            Text(s.t("新建协作话题", "New Topic"))
                .font(PipiTokens.fontSubheadline.weight(.semibold))
                .foregroundStyle(PipiTokens.textPrimary)

            TextField(s.t("例如：上线前检查 / 方案评审", "e.g., Launch Checklist / Spec Review"), text: $newTopicTitle)
                .textFieldStyle(.plain)
                .font(PipiTokens.fontBody)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                        .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                )
                .onSubmit {
                    submitNewTopic(groupId: group.id)
                }

            HStack {
                PipiActionButton(s.cancel, tone: .ghost, density: .desktopCompact) {
                    isShowingAddTopic = false
                }
                Spacer()
                PipiActionButton(s.t("创建", "Create"), systemImage: "plus", tone: .primary, density: .desktopCompact) {
                    submitNewTopic(groupId: group.id)
                }
                .disabled(newTopicTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(PipiTokens.spacing16)
        .frame(width: 280)
        .background(PipiTokens.bgElevated)
    }

    private func submitNewTopic(groupId: String) {
        let trimmed = newTopicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = store.createGroupTopic(groupId: groupId, title: trimmed, activate: true)
        newTopicTitle = ""
        isShowingAddTopic = false
    }

    // MARK: - Swarm Assignments Board

    @ViewBuilder
    private func assignmentsBoard(group: PipiGroupChat) -> some View {
        let doneCount = group.assignments.filter { $0.status == .done }.count
        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            Button {
                withAnimation(PipiMotion.snappy) {
                    isAssignmentsExpanded.toggle()
                }
            } label: {
                HStack(spacing: PipiTokens.spacing8) {
                    Image(systemName: isAssignmentsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PipiTokens.textMuted)
                    Image(systemName: "network")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PipiTokens.soulPrimary)
                    Text(s.t("蜂群分工看板", "Swarm Task Board"))
                        .font(PipiTokens.fontCaption)
                        .fontWeight(.semibold)
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text("\(doneCount)/\(group.assignments.count)")
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(PipiTokens.bgInset, in: Capsule())
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isAssignmentsExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PipiTokens.spacing8) {
                        ForEach(group.assignments) { item in
                            assignmentCard(item)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, PipiTokens.spacing16)
        .padding(.vertical, PipiTokens.spacing8)
        .background(PipiTokens.bgSurface.opacity(0.6))
    }

    @ViewBuilder
    private func assignmentCard(_ item: PipiSwarmTaskAssignment) -> some View {
        let bot = store.personas.first(where: { $0.id == item.personaId })
        let botColor = bot.map { PipiTokens.color(for: $0.accent) } ?? PipiTokens.soulPrimary

        HStack(alignment: .top, spacing: PipiTokens.spacing8) {
            if let bot {
                PipiBotPersonaGlyph(persona: bot, size: 22, isSelected: true)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(bot?.name(lang) ?? item.personaId)
                        .font(PipiTokens.fontMicro)
                        .fontWeight(.semibold)
                        .foregroundStyle(botColor)
                    assignmentStatusBadge(item.status, color: botColor)
                }
                Text(item.taskTitle)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .lineLimit(2)
                    .frame(maxWidth: 200, alignment: .leading)
            }
        }
        .padding(.horizontal, PipiTokens.spacing12)
        .padding(.vertical, PipiTokens.spacing8)
        .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                .strokeBorder(item.status == .working ? botColor.opacity(0.45) : PipiTokens.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func assignmentStatusBadge(_ status: PipiSwarmTaskAssignment.Status, color: Color) -> some View {
        switch status {
        case .queued:
            Text(s.t("排队中", "Queued"))
                .font(PipiTokens.fontMicro)
                .foregroundStyle(PipiTokens.textMuted)
        case .working:
            HStack(spacing: 3) {
                PipiDotIndicator(vitality: .busy, color: color, size: 5)
                Text(s.t("执行中", "Working"))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(color)
            }
        case .done:
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                Text(s.t("完成", "Done"))
                    .font(PipiTokens.fontMicro)
            }
            .foregroundStyle(PipiTokens.stateSuccess)
        case .failed:
            HStack(spacing: 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text(s.t("中断", "Stopped"))
                    .font(PipiTokens.fontMicro)
            }
            .foregroundStyle(PipiTokens.stateError)
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private func transcriptArea(group: PipiGroupChat, members: [PipiBotPersona]) -> some View {
        let topicMessages = group.activeTopicMessages
        if topicMessages.isEmpty {
            emptyState(group: group, members: members)
        } else {
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 24) {
                            ForEach(topicMessages) { msg in
                                messageRow(msg, group: group)
                                    .id(msg.id)
                            }
                        }
                        .frame(maxWidth: 780)
                        .padding(.horizontal, 38)
                        .padding(.top, 24)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity)
                    }
                    .pipiHideScrollbars()
                    .clipped()
                    .onChange(of: topicMessages.count) { _, _ in
                        if let lastId = topicMessages.last?.id {
                            withAnimation(PipiMotion.smooth) {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: topicMessages.last?.content) { _, _ in
                        if let lastId = topicMessages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }

                LinearGradient(
                    colors: [PipiTokens.bgCanvas.opacity(0), PipiTokens.bgCanvas],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 24)
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func emptyState(group: PipiGroupChat, members: [PipiBotPersona]) -> some View {
        VStack(spacing: PipiTokens.spacing16) {
            Spacer(minLength: 24)

            HStack(spacing: -10) {
                ForEach(members.prefix(5)) { bot in
                    PipiBotPersonaGlyph(persona: bot, size: 44, isSelected: true)
                        .overlay(Circle().strokeBorder(PipiTokens.bgCanvas, lineWidth: 2))
                }
            }

            VStack(spacing: PipiTokens.spacing8) {
                Text(group.title)
                    .font(PipiTokens.fontTitle)
                    .foregroundStyle(PipiTokens.textPrimary)

                Text("#\(group.activeTopic.localizedTitle(lang)) · \(group.swarmMode.label(lang))")
                    .font(PipiTokens.fontCaption.weight(.medium))
                    .foregroundStyle(PipiTokens.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(PipiTokens.bgSurface, in: Capsule())
                    .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))

                Text(group.swarmMode.description(lang))
                    .font(PipiTokens.fontBody)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            // Member summary pills clearly visible in empty state
            HStack(spacing: 8) {
                ForEach(members) { bot in
                    let isLead = group.leadPersonaId == bot.id && group.swarmMode == .swarm
                    HStack(spacing: 6) {
                        PipiBotPersonaGlyph(persona: bot, size: 18, isSelected: true)
                        Text(bot.name(lang))
                            .font(PipiTokens.fontMicro.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(1)
                        if isLead {
                            Text(s.t("主控", "Lead"))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.color(for: bot.accent))
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(PipiTokens.bgSurface, in: Capsule())
                    .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                }
            }

            VStack(spacing: PipiTokens.spacing8) {
                let firstBot = members.first?.name(lang) ?? "PiPi"
                let secondBot = members.dropFirst().first?.name(lang) ?? firstBot
                let starters: [String] = [
                    s.t("@all 请结合各自专长，针对这个目标给出一条关键建议", "@all Give one key recommendation from your specialty"),
                    s.t("协作制定一个本周交付计划，并分派给 @\(firstBot) 和 @\(secondBot)", "Create a weekly delivery plan and split work between @\(firstBot) and @\(secondBot)"),
                    s.t("对比两个方案的架构权衡并沉淀为交付文档", "Compare architectural trade-offs and produce a deliverable spec")
                ]

                ForEach(starters, id: \.self) { starter in
                    Button {
                        draftText = starter
                        isComposerFocused = true
                    } label: {
                        HStack(spacing: PipiTokens.spacing8) {
                            Text(starter)
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                        .padding(.horizontal, PipiTokens.spacing12)
                        .padding(.vertical, PipiTokens.spacing8)
                        .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PipiPressButtonStyle())
                }
            }
            .padding(.top, PipiTokens.spacing4)

            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, PipiTokens.spacing24)
    }

    @ViewBuilder
    private func messageRow(_ msg: PipiGroupMessage, group: PipiGroupChat) -> some View {
        switch msg.senderKind {
        case .user:
            HStack {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(msg.content)
                        .font(PipiTokens.fontBody)
                        .foregroundStyle(PipiTokens.textPrimary)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            PipiTokens.userBubbleBg,
                            in: RoundedRectangle(cornerRadius: PipiTokens.radiusComposer, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusComposer, style: .continuous)
                                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                        .contextMenu {
                            Button(s.t("复制", "Copy")) { copyToClipboard(msg.content, messageId: msg.id) }
                        }
                }
            }

        case .bot(let personaId):
            let bot = store.personas.first(where: { $0.id == personaId })
            let botColor = bot.map { PipiTokens.color(for: $0.accent) } ?? PipiTokens.soulPrimary
            let botName = bot?.name(lang) ?? personaId
            let isStreaming = store.groupStreamingMessageId(groupId: group.id, personaId: personaId) == msg.id
            let startedAt = isStreaming ? store.groupBotStartedAt(groupId: group.id, personaId: personaId) : nil

            HStack(alignment: .top, spacing: PipiTokens.spacing12) {
                if let bot {
                    PipiBotPersonaGlyph(persona: bot, size: 28, isSelected: true)
                        .padding(.top, 2)
                } else {
                    Circle()
                        .fill(PipiTokens.bgInset)
                        .frame(width: 28, height: 28)
                        .padding(.top, 2)
                }

                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    // Sender Header
                    HStack(spacing: PipiTokens.spacing8) {
                        Text(botName)
                            .font(PipiTokens.fontCaption)
                            .fontWeight(.semibold)
                            .foregroundStyle(botColor)

                        if let roleTag = msg.roleTag, !roleTag.isEmpty {
                            Text(roleTag)
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(botColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(botColor.opacity(0.12), in: Capsule())
                                .lineLimit(1)
                        }

                        if let engineLabel = msg.engineLabel, !engineLabel.isEmpty {
                            Text(engineLabel)
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textMuted)
                                .lineLimit(1)
                        }

                        if isStreaming {
                            PipiDotIndicator(vitality: .busy, color: botColor, size: 6)
                            if let startedAt {
                                PipiElapsedTimerLabel(startedAt: startedAt, color: botColor)
                            }
                        }

                        Spacer(minLength: 4)

                        if !isStreaming && !msg.content.isEmpty {
                            let isMsgHovered = hoveredMessageId == msg.id
                            HStack(spacing: 6) {
                                Button {
                                    saveMessageAsDeliverable(msg, group: group)
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: savedDeliverableMessageId == msg.id ? "checkmark" : "doc.badge.plus")
                                        Text(savedDeliverableMessageId == msg.id ? s.t("已存交付物", "Saved") : s.t("存为交付物", "Deliverable"))
                                    }
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(savedDeliverableMessageId == msg.id ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(PipiTokens.buttonGhostHoverBg, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .opacity(isMsgHovered || savedDeliverableMessageId == msg.id ? 1.0 : 0.0)

                                Button {
                                    saveMessageToGroupMemory(msg, group: group, sourceName: botName)
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: savedMemoryMessageId == msg.id ? "checkmark" : "bookmark")
                                        Text(savedMemoryMessageId == msg.id ? s.t("已存记忆", "Saved") : s.t("存入群记忆", "Memory"))
                                    }
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(savedMemoryMessageId == msg.id ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(PipiTokens.buttonGhostHoverBg, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .opacity(isMsgHovered || savedMemoryMessageId == msg.id ? 1.0 : 0.0)

                                Button {
                                    copyToClipboard(msg.content, messageId: msg.id)
                                } label: {
                                    Image(systemName: copiedMessageId == msg.id ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 11))
                                        .foregroundStyle(copiedMessageId == msg.id ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(s.t("复制回复", "Copy message"))
                            }
                        }
                    }

                    if msg.content.isEmpty && isStreaming {
                        HStack(spacing: 6) {
                            Text(s.t("思考与协作中…", "Thinking…"))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                        .padding(.vertical, 4)
                    } else if msg.isError {
                        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                            Text(msg.content)
                                .font(PipiTokens.fontBody)
                                .foregroundStyle(PipiTokens.stateError)
                                .textSelection(.enabled)
                            if let onOpenSettings {
                                PipiActionButton(
                                    s.t("打开 AI 引擎设置", "Open AI Engine Settings"),
                                    systemImage: "gearshape",
                                    tone: .secondary,
                                    density: .desktopCompact
                                ) {
                                    onOpenSettings()
                                }
                            }
                        }
                        .padding(PipiTokens.spacing12)
                        .background(PipiTokens.stateErrorBg, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                .strokeBorder(PipiTokens.stateError.opacity(0.35), lineWidth: 1)
                        )
                    } else {
                        PipiMarkdownView(
                            content: msg.content,
                            strings: s,
                            accent: botColor,
                            isStreaming: isStreaming
                        )
                        .padding(.horizontal, PipiTokens.spacing12)
                        .padding(.vertical, PipiTokens.spacing12)
                        .background(
                            PipiTokens.bgSurface,
                            in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                        .contextMenu {
                            Button(s.t("复制", "Copy")) { copyToClipboard(msg.content, messageId: msg.id) }
                            Button(s.t("存为交付物", "Save as Deliverable")) {
                                saveMessageAsDeliverable(msg, group: group)
                            }
                            Button(s.t("存入群记忆", "Save to Shared Memory")) {
                                saveMessageToGroupMemory(msg, group: group, sourceName: botName)
                            }
                        }
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)

                Spacer(minLength: 24)
            }
            .onHover { hovering in
                hoveredMessageId = hovering ? msg.id : (hoveredMessageId == msg.id ? nil : hoveredMessageId)
            }

        case .system:
            HStack {
                Spacer()
                Text(msg.content)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textMuted)
                    .padding(.horizontal, PipiTokens.spacing12)
                    .padding(.vertical, 4)
                    .background(PipiTokens.bgInset, in: Capsule())
                Spacer()
            }
        }
    }

    // MARK: - Composer + @Mention Autocomplete

    @ViewBuilder
    private func composerArea(group: PipiGroupChat, members: [PipiBotPersona], isRunning: Bool) -> some View {
        let shouldShowMentions = isShowingMentionMenu || draftText.hasSuffix("@")
        let canSend = !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shape = RoundedRectangle(cornerRadius: PipiTokens.radiusComposer, style: .continuous)

        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            if shouldShowMentions {
                mentionAutocompleteStrip(members: members)
            }

            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                TextField(
                    s.t("输入协作目标，或用 @成员名 指定智能体…", "Describe goal, or type @Name to mention an agent…"),
                    text: $draftText,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(PipiTokens.fontBody)
                .foregroundStyle(PipiTokens.textPrimary)
                .focused($isComposerFocused)
                .lineLimit(1...6)
                .padding(.top, 2)
                .frame(minHeight: 44, alignment: .topLeading)
                .onSubmit {
                    sendDraft(groupId: group.id)
                }

                HStack(spacing: PipiTokens.spacing8) {
                    PipiGhostIconButton(
                        systemImage: "at",
                        isActive: shouldShowMentions,
                        activeColor: PipiTokens.soulPrimary,
                        size: 30,
                        iconSize: 13.5,
                        cornerRadius: PipiTokens.radiusSM
                    ) {
                        isShowingMentionMenu = !(shouldShowMentions && !draftText.hasSuffix("@"))
                    }
                    .help(s.t("提及智能体成员", "Mention agent member"))
                    .accessibilityLabel(s.t("提及智能体成员", "Mention agent member"))

                    Spacer(minLength: 6)

                    if isRunning {
                        Button {
                            store.stopGroupChat(group.id)
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(PipiTokens.textInverse)
                                .frame(width: 32, height: 32)
                                .background(PipiTokens.stateError)
                                .clipShape(Circle())
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                        .help(s.stop)
                        .accessibilityLabel(s.stop)
                    } else {
                        Button {
                            sendDraft(groupId: group.id)
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(canSend ? PipiTokens.textInverse : PipiTokens.textMuted)
                                .frame(width: 32, height: 32)
                                .background(canSend ? PipiTokens.soulPrimary : PipiTokens.buttonGhostHoverBg)
                                .clipShape(Circle())
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                        .disabled(!canSend)
                        .help(s.send)
                        .accessibilityLabel(s.t("发送群消息", "Send group message"))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(PipiTokens.composerSurface, in: shape)
            .overlay(
                shape.stroke(
                    isComposerFocused ? PipiTokens.composerBorderFocused : PipiTokens.composerBorder,
                    lineWidth: 1
                )
            )
            .clipShape(shape)
            .shadow(
                color: PipiTokens.composerShadow,
                radius: isComposerFocused ? 10 : 6,
                y: isComposerFocused ? 3 : 2
            )
        }
        .frame(maxWidth: 780)
        .padding(.horizontal, 36)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(PipiTokens.bgCanvas)
    }

    @ViewBuilder
    private func mentionAutocompleteStrip(members: [PipiBotPersona]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PipiTokens.spacing8) {
                Button {
                    insertMentionToken("all")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 10))
                        Text("@all")
                            .font(PipiTokens.fontCaption)
                            .fontWeight(.semibold)
                        Text(s.t("全部成员", "All"))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    .foregroundStyle(PipiTokens.soulPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(PipiTokens.bgElevated, in: Capsule())
                    .overlay(Capsule().strokeBorder(PipiTokens.soulPrimary.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(PipiPressButtonStyle())

                ForEach(members) { bot in
                    let botColor = PipiTokens.color(for: bot.accent)
                    Button {
                        insertMentionToken(bot.name(lang))
                    } label: {
                        HStack(spacing: 5) {
                            PipiBotPersonaGlyph(persona: bot, size: 16, isSelected: true)
                            Text("@\(bot.name(lang))")
                                .font(PipiTokens.fontCaption)
                                .fontWeight(.medium)
                                .foregroundStyle(PipiTokens.textPrimary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(PipiTokens.bgElevated, in: Capsule())
                        .overlay(Capsule().strokeBorder(botColor.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(PipiPressButtonStyle())
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func insertMentionToken(_ name: String) {
        if draftText.hasSuffix("@") {
            draftText += "\(name) "
        } else if draftText.isEmpty || draftText.hasSuffix(" ") || draftText.hasSuffix("\n") {
            draftText += "@\(name) "
        } else {
            draftText += " @\(name) "
        }
        isShowingMentionMenu = false
    }

    private func sendDraft(groupId: String) {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draftText = ""
        isShowingMentionMenu = false
        Task {
            await store.sendGroupMessage(trimmed, toGroupId: groupId)
        }
    }

    private func copyToClipboard(_ text: String, messageId: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        copiedMessageId = messageId
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if copiedMessageId == messageId {
                copiedMessageId = nil
            }
        }
    }

    private func saveMessageAsDeliverable(_ msg: PipiGroupMessage, group: PipiGroupChat) {
        guard store.promoteMessageToDeliverable(groupId: group.id, messageId: msg.id) != nil else { return }
        savedDeliverableMessageId = msg.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if savedDeliverableMessageId == msg.id {
                savedDeliverableMessageId = nil
            }
        }
    }

    private func saveMessageToGroupMemory(_ msg: PipiGroupMessage, group: PipiGroupChat, sourceName: String) {
        let trimmed = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let concise = trimmed.count > 500 ? String(trimmed.prefix(500)) + "…" : trimmed
        guard store.addGroupMemory(groupId: group.id, content: concise, source: sourceName, pinned: false) != nil else { return }
        savedMemoryMessageId = msg.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if savedMemoryMessageId == msg.id {
                savedMemoryMessageId = nil
            }
        }
    }
}

// MARK: - Group Chat Creator / Editor Sheet

public struct PipiGroupCreatorSheet: View {
    @Bindable var store: PipiAppStore
    public var editingGroup: PipiGroupChat?
    public var preselectedBotIds: Set<String>

    @Environment(\.dismiss) private var dismiss
    @Environment(\.pipiTextScale) private var textScale

    @State private var title: String
    @State private var selectedBotIds: [String]
    @State private var leadBotId: String?
    @State private var swarmMode: PipiSwarmMode

    public init(
        store: PipiAppStore,
        editingGroup: PipiGroupChat? = nil,
        preselectedBotIds: Set<String> = []
    ) {
        self.store = store
        self.editingGroup = editingGroup
        self.preselectedBotIds = preselectedBotIds

        if let editingGroup {
            _title = State(initialValue: editingGroup.title)
            _selectedBotIds = State(initialValue: editingGroup.participantPersonaIds)
            _leadBotId = State(initialValue: editingGroup.leadPersonaId ?? editingGroup.participantPersonaIds.first)
            _swarmMode = State(initialValue: editingGroup.swarmMode)
        } else {
            let defaults = store.personas.map(\.id)
            let initialIds: [String] = {
                if !preselectedBotIds.isEmpty {
                    let ordered = defaults.filter { preselectedBotIds.contains($0) }
                    return ordered
                }
                return Array(defaults.prefix(min(3, defaults.count)))
            }()
            _title = State(initialValue: "")
            _selectedBotIds = State(initialValue: initialIds)
            _leadBotId = State(initialValue: initialIds.first)
            _swarmMode = State(initialValue: .swarm)
        }
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    private var canSave: Bool {
        selectedBotIds.count >= 2
    }

    public var body: some View {
        let _ = textScale
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        editingGroup != nil
                            ? s.t("编辑协作群", "Edit Swarm Group")
                            : s.t("新建多智能体协作群", "New Multi-Agent Group")
                    )
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                    Text(s.t("组合多个专业智能体，在同一对话中协同完成复杂任务", "Combine specialist agents to collaborate in one shared thread"))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                }
                Spacer()
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                    // Title
                    VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                        Text(s.t("群名称", "Group Name"))
                            .font(PipiTokens.fontCaption)
                            .fontWeight(.semibold)
                            .foregroundStyle(PipiTokens.textSecondary)
                        TextField(
                            s.t("例如：产品发布协作组", "e.g. Product Launch Squad"),
                            text: $title
                        )
                        .textFieldStyle(.plain)
                        .font(PipiTokens.fontBody)
                        .padding(.horizontal, PipiTokens.spacing12)
                        .padding(.vertical, PipiTokens.spacing8)
                        .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                    }

                    // Participant Bots
                    VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                        HStack {
                            Text(s.t("选择成员智能体（至少 2 个）", "Select Participant Agents (at least 2)"))
                                .font(PipiTokens.fontCaption)
                                .fontWeight(.semibold)
                                .foregroundStyle(PipiTokens.textSecondary)
                            Spacer()
                            Text(s.t("已选 \(selectedBotIds.count)", "\(selectedBotIds.count) selected"))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(canSave ? PipiTokens.soulPrimary : PipiTokens.stateWarning)
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: PipiTokens.spacing8) {
                            ForEach(store.personas) { bot in
                                let isSelected = selectedBotIds.contains(bot.id)
                                let botColor = PipiTokens.color(for: bot.accent)

                                Button {
                                    toggleBot(bot.id)
                                } label: {
                                    HStack(spacing: PipiTokens.spacing8) {
                                        PipiBotPersonaGlyph(persona: bot, size: 28, isSelected: isSelected)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(bot.name(lang))
                                                .font(PipiTokens.fontCaption)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(PipiTokens.textPrimary)
                                                .lineLimit(1)
                                            Text(bot.role(lang))
                                                .font(PipiTokens.fontMicro)
                                                .foregroundStyle(PipiTokens.textMuted)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 4)
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 15))
                                            .foregroundStyle(isSelected ? botColor : PipiTokens.textMuted)
                                    }
                                    .padding(PipiTokens.spacing12)
                                    .background(
                                        isSelected ? botColor.opacity(0.08) : PipiTokens.bgSurface,
                                        in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                            .strokeBorder(isSelected ? botColor.opacity(0.5) : PipiTokens.borderSubtle, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(PipiPressButtonStyle())
                            }
                        }
                    }

                    // Swarm Mode
                    VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                        Text(s.t("协作模式", "Collaboration Mode"))
                            .font(PipiTokens.fontCaption)
                            .fontWeight(.semibold)
                            .foregroundStyle(PipiTokens.textSecondary)

                        VStack(spacing: PipiTokens.spacing8) {
                            ForEach(PipiSwarmMode.allCases) { mode in
                                let isActive = swarmMode == mode
                                Button {
                                    swarmMode = mode
                                } label: {
                                    HStack(alignment: .top, spacing: PipiTokens.spacing12) {
                                        Image(systemName: mode.iconName)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(isActive ? PipiTokens.soulPrimary : PipiTokens.textSecondary)
                                            .frame(width: 22, height: 22)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(mode.label(lang))
                                                .font(PipiTokens.fontCaption)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(PipiTokens.textPrimary)
                                            Text(mode.description(lang))
                                                .font(PipiTokens.fontMicro)
                                                .foregroundStyle(PipiTokens.textSecondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer()
                                        Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(isActive ? PipiTokens.soulPrimary : PipiTokens.textMuted)
                                    }
                                    .padding(PipiTokens.spacing12)
                                    .background(
                                        isActive ? PipiTokens.soulPrimary.opacity(0.08) : PipiTokens.bgSurface,
                                        in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                            .strokeBorder(isActive ? PipiTokens.soulPrimary.opacity(0.45) : PipiTokens.borderSubtle, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(PipiPressButtonStyle())
                            }
                        }
                    }

                    // Lead Bot Picker (shown when Swarm mode and >= 1 selected)
                    if swarmMode == .swarm && !selectedBotIds.isEmpty {
                        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                            Text(s.t("主控协调智能体 (Lead)", "Lead Orchestrator Agent"))
                                .font(PipiTokens.fontCaption)
                                .fontWeight(.semibold)
                                .foregroundStyle(PipiTokens.textSecondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: PipiTokens.spacing8) {
                                    ForEach(selectedBotIds, id: \.self) { pid in
                                        if let bot = store.personas.first(where: { $0.id == pid }) {
                                            let isLead = leadBotId == pid
                                            let botColor = PipiTokens.color(for: bot.accent)
                                            Button {
                                                leadBotId = pid
                                            } label: {
                                                HStack(spacing: 6) {
                                                    PipiBotPersonaGlyph(persona: bot, size: 18, isSelected: isLead)
                                                    Text(bot.name(lang))
                                                        .font(PipiTokens.fontCaption)
                                                        .fontWeight(isLead ? .semibold : .regular)
                                                        .foregroundStyle(PipiTokens.textPrimary)
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(
                                                    isLead ? botColor.opacity(0.14) : PipiTokens.bgSurface,
                                                    in: Capsule()
                                                )
                                                .overlay(
                                                    Capsule()
                                                        .strokeBorder(isLead ? botColor : PipiTokens.borderSubtle, lineWidth: 1)
                                                )
                                            }
                                            .buttonStyle(PipiPressButtonStyle())
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Divider().overlay(PipiTokens.borderSubtle)

            HStack {
                if !canSave {
                    Text(s.t("请至少选择 2 位智能体成员", "Select at least 2 agents"))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.stateWarning)
                }
                Spacer()
                PipiActionButton(
                    s.t("取消", "Cancel"),
                    tone: .secondary,
                    density: .desktopCompact
                ) {
                    dismiss()
                }
                PipiActionButton(
                    editingGroup != nil ? s.t("保存", "Save") : s.t("创建群聊", "Create Group"),
                    systemImage: editingGroup != nil ? "checkmark" : "person.3.fill",
                    tone: .primary,
                    density: .desktopCompact
                ) {
                    saveGroup()
                }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
            }
        }
        .padding(PipiTokens.spacing20)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 500, idealHeight: 580)
        .background(PipiTokens.bgCanvas)
    }

    private func toggleBot(_ id: String) {
        if let idx = selectedBotIds.firstIndex(of: id) {
            selectedBotIds.remove(at: idx)
            if leadBotId == id {
                leadBotId = selectedBotIds.first
            }
        } else {
            selectedBotIds.append(id)
            if leadBotId == nil {
                leadBotId = id
            }
        }
    }

    private func saveGroup() {
        guard canSave else { return }
        let resolvedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLead = leadBotId.flatMap { selectedBotIds.contains($0) ? $0 : nil } ?? selectedBotIds.first

        if let editingGroup {
            store.updateGroupChat(
                id: editingGroup.id,
                title: resolvedTitle.isEmpty ? editingGroup.title : resolvedTitle,
                participantPersonaIds: selectedBotIds,
                leadPersonaId: .some(resolvedLead),
                swarmMode: swarmMode
            )
        } else {
            let fallbackTitle = selectedBotIds.compactMap { pid in
                store.personas.first(where: { $0.id == pid })?.name(lang)
            }.prefix(3).joined(separator: " + ")
            store.createGroupChat(
                title: resolvedTitle.isEmpty ? fallbackTitle : resolvedTitle,
                participantPersonaIds: selectedBotIds,
                leadPersonaId: resolvedLead,
                swarmMode: swarmMode,
                activate: true
            )
        }
        dismiss()
    }
}
