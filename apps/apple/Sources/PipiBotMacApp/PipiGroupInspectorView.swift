import SwiftUI
import PipiBotKit

#if os(macOS)
import AppKit
#endif

public enum PipiGroupInspectorTab: String, CaseIterable, Identifiable, Sendable {
    case membersTasks
    case deliverables
    case skillsMemory

    public var id: String { rawValue }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .membersTasks: return lang == .zhHans ? "成员与任务" : "Members & Tasks"
        case .deliverables: return lang == .zhHans ? "交付物" : "Deliverables"
        case .skillsMemory: return lang == .zhHans ? "技能与记忆" : "Skills & Memory"
        }
    }
}

public struct PipiGroupInspectorView: View {
    @Bindable public var store: PipiAppStore
    public let groupId: String
    @Binding public var selectedTab: PipiGroupInspectorTab
    public var onMentionBot: (String) -> Void
    public var onManageMembers: (PipiGroupChat) -> Void

    @Environment(\.pipiTextScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Inline Forms State
    @State private var showAddLongTask = false
    @State private var taskTitleDraft = ""
    @State private var taskGoalDraft = ""
    @State private var taskOwnerId: String? = nil
    @State private var taskSchedule: PipiRoutineSchedule = .daily
    @State private var taskHour: Int = 9
    @State private var taskMinute: Int = 0
    @State private var taskWeekday: Int = 2

    @State private var showAddDeliverable = false
    @State private var delivTitleDraft = ""
    @State private var delivKind: PipiGroupDeliverable.Kind = .document
    @State private var delivContentDraft = ""
    @State private var delivProducerId: String? = nil
    @State private var previewDeliverable: PipiGroupDeliverable? = nil
    @State private var copiedDeliverableId: String? = nil

    @State private var showAddSkill = false
    @State private var skillNameDraft = ""
    @State private var skillInstructionDraft = ""

    @State private var showAddMemory = false
    @State private var memoryContentDraft = ""
    @State private var memoryPinnedDraft = true

    // Wave 3 (#06) team.md Protocol Editor & Runner State
    @State private var selectedTeamPattern: PipiTeamCollaborationPattern = .fanOutAndSynthesize
    @State private var showTeamProtocolEditor = false
    @State private var teamProtocolDraft = ""
    @State private var teamProtocolPromptDraft = ""
    @State private var isRunningTeamProtocol = false

    public init(
        store: PipiAppStore,
        groupId: String,
        selectedTab: Binding<PipiGroupInspectorTab>,
        onMentionBot: @escaping (String) -> Void = { _ in },
        onManageMembers: @escaping (PipiGroupChat) -> Void = { _ in }
    ) {
        self.store = store
        self.groupId = groupId
        self._selectedTab = selectedTab
        self.onMentionBot = onMentionBot
        self.onManageMembers = onManageMembers
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    private var group: PipiGroupChat? {
        store.groupChats.first(where: { $0.id == groupId })
    }

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
                VStack(spacing: 0) {
                    inspectorHeader(group: group, members: members)

                    Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                            switch selectedTab {
                            case .membersTasks:
                                membersSection(group: group, members: members)
                                dynamicBotProposalsSection(group: group)
                                teamProtocolSection(group: group)
                                longTasksSection(group: group, members: members)
                                topicAndContextSection(group: group, members: members)
                            case .deliverables:
                                deliverablesSection(group: group, members: members)
                            case .skillsMemory:
                                skillsSection(group: group)
                                sharedMemorySection(group: group)
                            }
                        }
                        .padding(PipiTokens.spacing16)
                    }
                    .pipiHideScrollbars()
                }
                .sheet(item: $previewDeliverable) { deliverable in
                    deliverablePreviewSheet(deliverable, group: group)
                        .environment(\.pipiTextScale, store.uiZoomScale)
                }
                .sheet(isPresented: $showTeamProtocolEditor) {
                    teamProtocolEditorSheet(group: group)
                        .frame(minWidth: 540, minHeight: 500)
                        .environment(\.pipiTextScale, store.uiZoomScale)
                }
            } else {
                PipiEmptyState(
                    systemImage: "person.2",
                    title: s.t("未找到该协作群", "Group Not Found"),
                    message: s.t("请选择一个多智能体协作群查看详情。", "Select a multi-agent group to inspect its workspace.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PipiTokens.bgSidebar.ignoresSafeArea(.container, edges: .top))
        .background(alignment: .top) {
            PipiTokens.bgSidebar
                .frame(height: 80)
                .ignoresSafeArea(.container, edges: .top)
        }
    }

    // MARK: - Header & Crisp 3-Tab Switcher (Zero [✕] Close Button)

    private func inspectorHeader(group: PipiGroupChat, members: [PipiBotPersona]) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack(spacing: PipiTokens.spacing8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.t("群协作工作区", "Group Workspace"))
                        .font(PipiTokens.fontHeadline)
                        .tracking(PipiTokens.trackingHeadline)
                        .foregroundStyle(PipiTokens.textPrimary)
                        .lineLimit(1)

                    Text(s.t("\(members.count) 位智能体 · #\(group.activeTopic.localizedTitle(lang))",
                             "\(members.count) agents · #\(group.activeTopic.localizedTitle(lang))"))
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if store.isGroupRunning(group.id) {
                    HStack(spacing: 5) {
                        PipiDotIndicator(vitality: .busy, color: PipiTokens.soulPrimary, size: 5.5)
                        Text(s.t("协作中", "Running"))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textPrimary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PipiTokens.bgSurfaceHover, in: Capsule())
                }
            }

            HStack(spacing: 4) {
                ForEach(PipiGroupInspectorTab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(tab.label(lang))
                                .font(PipiTokens.fontMicro.weight(isSelected ? .semibold : .medium))
                                .lineLimit(1)
                            if tab == .deliverables && !group.deliverables.isEmpty {
                                Text("\(group.deliverables.count)")
                                    .font(PipiTokens.fontMonoSmall)
                                    .monospacedDigit()
                                    .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textMuted)
                            }
                        }
                        .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? PipiTokens.bgElevated : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(isSelected ? PipiTokens.borderSubtle : Color.clear, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.98))
                }
            }
            .padding(3)
            .background(PipiTokens.bgInset, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
        }
        .padding(.horizontal, PipiTokens.spacing16)
        .padding(.top, 12)
        .padding(.bottom, PipiTokens.spacing12)
    }

    // MARK: - Tab 1: Members, Long Tasks & Context

    private func membersSection(group: PipiGroupChat, members: [PipiBotPersona]) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack {
                sectionTitle(s.t("群成员 (\(members.count))", "Members (\(members.count))"))
                Spacer()
                Button {
                    onManageMembers(group)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(s.t("管理成员", "Manage"))
                            .font(PipiTokens.fontMicro.weight(.medium))
                    }
                    .foregroundStyle(PipiTokens.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
            }

            VStack(spacing: 0) {
                ForEach(Array(members.enumerated()), id: \.element.id) { idx, bot in
                    let isLead = group.leadPersonaId == bot.id
                    let isBusy = store.isBotWorkingInGroup(bot.id, groupId: group.id)
                    let botAccent = PipiTokens.color(for: bot.accent)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: PipiTokens.spacing12) {
                            PipiBotPersonaGlyph(persona: bot, size: 32, isSelected: true)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(bot.name(lang))
                                        .font(PipiTokens.fontCaption.weight(.semibold))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                        .lineLimit(1)

                                    if isLead && group.swarmMode == .swarm {
                                        Text(s.t("主控", "Lead"))
                                            .font(PipiTokens.fontMicro.weight(.semibold))
                                            .foregroundStyle(botAccent)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(botAccent.opacity(0.14), in: Capsule())
                                    }

                                    Spacer(minLength: 4)

                                    if isBusy {
                                        PipiDotIndicator(vitality: .busy, color: botAccent, size: 5.5)
                                    } else {
                                        Circle()
                                            .fill(PipiTokens.stateSuccess)
                                            .frame(width: 6, height: 6)
                                    }
                                }

                                Text(bot.role(lang))
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(PipiTokens.textSecondary)
                                    .lineLimit(1)

                                HStack(spacing: 6) {
                                    Text(store.activeEngineDisplayLabel(for: bot))
                                        .font(PipiTokens.fontMonoSmall)
                                        .foregroundStyle(PipiTokens.textMuted)
                                        .lineLimit(1)

                                    Spacer(minLength: 4)

                                    if group.swarmMode == .swarm && !isLead {
                                        Button {
                                            store.updateGroupChat(id: group.id, leadPersonaId: .some(bot.id))
                                        } label: {
                                            Text(s.t("设为主控", "Set Lead"))
                                                .font(PipiTokens.fontMicro)
                                                .foregroundStyle(PipiTokens.textSecondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(PipiTokens.bgSurface, in: Capsule())
                                                .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                                        }
                                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.95))
                                    }

                                    Button {
                                        onMentionBot("@\(bot.name(lang)) ")
                                    } label: {
                                        Text("@")
                                            .font(PipiTokens.fontMonoSmall.weight(.semibold))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                            .frame(width: 22, height: 22)
                                            .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                                    .help(s.t("在输入框中 @\(bot.name(lang))", "Mention @\(bot.name(lang))"))
                                }
                            }
                        }
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onMentionBot("@\(bot.name(lang)) ")
                    }

                    if idx < members.count - 1 {
                        cardDivider
                    }
                }
            }
            .background(PipiTokens.bgElevated)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        }
    }

    private func longTasksSection(group: PipiGroupChat, members: [PipiBotPersona]) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack {
                sectionTitle(s.t("长期任务 (\(group.longTasks.count))", "Long-Running Tasks (\(group.longTasks.count))"))
                Spacer()
                Button {
                    withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                        if !showAddLongTask && taskOwnerId == nil {
                            taskOwnerId = group.leadPersonaId ?? members.first?.id
                        }
                        showAddLongTask.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showAddLongTask ? "minus" : "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(s.t("新建长期任务", "New Task"))
                            .font(PipiTokens.fontMicro.weight(.medium))
                    }
                    .foregroundStyle(PipiTokens.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
            }

            if showAddLongTask {
                addLongTaskForm(group: group, members: members)
            }

            if group.longTasks.isEmpty && !showAddLongTask {
                Text(s.t("暂无长期任务。添加后将自动注入群内全部智能体共识，并可随时推进。",
                         "No long-running tasks yet. Active tasks are shared across all agents in this group."))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textMuted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                            .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                    )
            } else {
                ForEach(group.longTasks) { task in
                    longTaskCard(task, group: group, members: members)
                }
            }
        }
    }

    private func addLongTaskForm(group: PipiGroupChat, members: [PipiBotPersona]) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            TextField(s.t("任务标题（例如：每日指标巡检与周报）", "Task title (e.g., Weekly Release Readiness)"), text: $taskTitleDraft)
                .textFieldStyle(.plain)
                .font(PipiTokens.fontCaption)
                .padding(PipiTokens.spacing8)
                .background(PipiTokens.bgInset, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

            TextField(s.t("长期目标与验收标准…", "Ongoing goal & acceptance criteria…"), text: $taskGoalDraft, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .font(PipiTokens.fontCaption)
                .padding(PipiTokens.spacing8)
                .background(PipiTokens.bgInset, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

            HStack(spacing: PipiTokens.spacing8) {
                Picker(s.t("负责人", "Owner"), selection: $taskOwnerId) {
                    Text(s.t("群智协同", "Whole Group")).tag(String?.none)
                    ForEach(members) { bot in
                        Text(bot.name(lang)).tag(Optional(bot.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Picker(s.t("周期", "Schedule"), selection: $taskSchedule) {
                    ForEach(PipiRoutineSchedule.allCases) { kind in
                        Text(kind.label(lang)).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }

            HStack {
                PipiActionButton(s.cancel, tone: .ghost, density: .desktopCompact) {
                    showAddLongTask = false
                }
                Spacer()
                PipiActionButton(s.save, systemImage: "checkmark", tone: .primary, density: .desktopCompact) {
                    let task = PipiGroupLongTask(
                        title: taskTitleDraft,
                        goal: taskGoalDraft,
                        ownerPersonaId: taskOwnerId,
                        schedule: taskSchedule,
                        hour: taskHour,
                        minute: taskMinute,
                        weekday: taskWeekday,
                        status: .active,
                        topicId: group.effectiveActiveTopicId
                    )
                    if store.addGroupLongTask(groupId: group.id, task: task) != nil {
                        taskTitleDraft = ""
                        taskGoalDraft = ""
                        showAddLongTask = false
                    }
                }
                .disabled(
                    taskTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    taskGoalDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(12)
        .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderStrong, lineWidth: 1)
        )
    }

    private func longTaskCard(_ task: PipiGroupLongTask, group: PipiGroupChat, members: [PipiBotPersona]) -> some View {
        let owner = task.ownerPersonaId.flatMap { oid in
            members.first(where: { $0.id == oid }) ?? store.personas.first(where: { $0.id == oid })
        }
        let statusColor: Color = {
            switch task.status {
            case .active: return PipiTokens.stateSuccess
            case .paused: return PipiTokens.textMuted
            case .completed: return PipiTokens.soulPrimary
            }
        }()

        return VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack(spacing: PipiTokens.spacing8) {
                Text(task.title)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5.5, height: 5.5)
                    Text(task.status.label(lang))
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(task.status == .active ? PipiTokens.stateSuccess : PipiTokens.textSecondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(PipiTokens.bgSurface, in: Capsule())
            }

            Text(task.goal)
                .font(PipiTokens.fontMicro)
                .foregroundStyle(PipiTokens.textSecondary)
                .lineLimit(3)

            HStack(spacing: 6) {
                if let owner {
                    HStack(spacing: 4) {
                        PipiBotPersonaGlyph(persona: owner, size: 14, isSelected: true)
                        Text(owner.name(lang))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PipiTokens.bgSurface, in: Capsule())
                }

                Text(task.scheduleBadge(lang))
                    .font(PipiTokens.fontMonoSmall)
                    .foregroundStyle(PipiTokens.textMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PipiTokens.bgInset, in: Capsule())

                Spacer(minLength: 4)

                if let lastRun = task.lastRunAt, !lastRun.isEmpty {
                    Text(store.relativeTimeLabel(for: lastRun))
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                }
            }

            if let summary = task.lastSummary, !summary.isEmpty {
                Text(summary)
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textMuted)
                    .lineLimit(2)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            HStack(spacing: 6) {
                PipiActionButton(
                    s.t("立即推进", "Advance Now"),
                    systemImage: "play.fill",
                    tone: .secondary,
                    density: .desktopCompact
                ) {
                    Task { await store.runGroupLongTaskNow(groupId: group.id, taskId: task.id) }
                }
                .disabled(store.isGroupRunning(group.id))

                Button {
                    let next: PipiGroupLongTask.Status = (task.status == .active) ? .paused : .active
                    store.toggleGroupLongTask(groupId: group.id, taskId: task.id, status: next)
                } label: {
                    Image(systemName: task.status == .active ? "pause.circle" : "play.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.94))
                .help(task.status == .active ? s.t("暂停任务", "Pause Task") : s.t("恢复任务", "Resume Task"))

                Spacer()

                PipiGhostIconButton(
                    systemImage: "trash",
                    size: 26,
                    iconSize: 11,
                    cornerRadius: 6,
                    accessibilityLabel: s.delete
                ) {
                    store.deleteGroupLongTask(groupId: group.id, taskId: task.id)
                }
            }
        }
        .padding(12)
        .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
    }

    private func topicAndContextSection(group: PipiGroupChat, members: [PipiBotPersona]) -> some View {
        let usage = store.estimateGroupContextUsage(for: group)
        let barColor: Color = {
            if usage.utilizationRatio >= 0.90 { return PipiTokens.stateError }
            if usage.utilizationRatio >= 0.72 { return PipiTokens.stateWarning }
            return PipiTokens.soulPrimary
        }()

        return VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack {
                sectionTitle(s.t("话题与上下文", "Topic & Context"))
                Spacer()
                Text(s.t("估算", "Estimated"))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(PipiTokens.bgElevated, in: Capsule())
                    .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("~\(usage.formattedEstimatedTokens)")
                        .font(PipiTokens.fontHeadline)
                        .monospacedDigit()
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text("/ \(usage.formattedWindowTokens) tokens")
                        .font(PipiTokens.fontCaption)
                        .monospacedDigit()
                        .foregroundStyle(PipiTokens.textMuted)
                    Spacer()
                    Text("\(usage.utilizationPercent)%")
                        .font(PipiTokens.fontMonoSmall.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(usage.utilizationRatio >= 0.72 ? barColor : PipiTokens.textSecondary)
                }

                GeometryReader { geo in
                    let fillRatio = usage.estimatedTokens > 0
                        ? min(1.0, max(0.025, usage.utilizationRatio))
                        : 0.0
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(PipiTokens.bgInset)
                        Capsule()
                            .fill(barColor)
                            .frame(width: geo.size.width * fillRatio)
                    }
                }
                .frame(height: 5)

                cardDivider

                VStack(alignment: .leading, spacing: 6) {
                    contextMetricRow(
                        label: s.t("当前话题", "Active Topic"),
                        value: "#\(group.activeTopic.localizedTitle(lang))"
                    )
                    contextMetricRow(
                        label: s.t("消息轮次", "Transcript"),
                        value: s.t("\(usage.turnCount) 轮 · \(usage.messageCount) 条消息",
                                   "\(usage.turnCount) turns · \(usage.messageCount) msgs")
                    )
                    contextMetricRow(
                        label: s.t("群成员与模式", "Team & Mode"),
                        value: "\(members.count) · \(group.swarmMode.label(lang))"
                    )
                    contextMetricRow(
                        label: s.t("运行主机", "Host"),
                        value: store.localHost.displayName(lang)
                    )
                }
            }
            .padding(14)
            .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )
        }
    }

    private func contextMetricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(PipiTokens.fontCaption)
                .foregroundStyle(PipiTokens.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(PipiTokens.fontCaption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(PipiTokens.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Tab 2: Deliverables

    private func deliverablesSection(group: PipiGroupChat, members: [PipiBotPersona]) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack {
                sectionTitle(s.t("协作交付物 (\(group.deliverables.count))", "Deliverables (\(group.deliverables.count))"))
                Spacer()
                Button {
                    withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                        if !showAddDeliverable && delivProducerId == nil {
                            delivProducerId = group.leadPersonaId ?? members.first?.id
                        }
                        showAddDeliverable.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showAddDeliverable ? "minus" : "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(s.t("记录交付物", "Record"))
                            .font(PipiTokens.fontMicro.weight(.medium))
                    }
                    .foregroundStyle(PipiTokens.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
            }

            if showAddDeliverable {
                addDeliverableForm(group: group, members: members)
            }

            if group.deliverables.isEmpty && !showAddDeliverable {
                Text(s.t("还没有交付物。在群聊回复中点击「存为交付物」或在此手动记录产出结论。",
                         "No deliverables yet. Save any agent message as a deliverable or record one here."))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textMuted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                            .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                    )
            } else {
                ForEach(group.deliverables) { item in
                    deliverableCard(item, group: group)
                }
            }
        }
    }

    private func addDeliverableForm(group: PipiGroupChat, members: [PipiBotPersona]) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            TextField(s.t("交付物标题（例如：架构设计方案 v1）", "Title (e.g., Architecture Spec v1)"), text: $delivTitleDraft)
                .textFieldStyle(.plain)
                .font(PipiTokens.fontCaption)
                .padding(PipiTokens.spacing8)
                .background(PipiTokens.bgInset, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

            HStack(spacing: PipiTokens.spacing8) {
                Picker(s.t("类型", "Kind"), selection: $delivKind) {
                    ForEach(PipiGroupDeliverable.Kind.allCases) { kind in
                        Text(kind.label(lang)).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 96)

                Picker(s.t("产出成员", "Producer"), selection: $delivProducerId) {
                    Text(s.t("团队共同", "Team")).tag(String?.none)
                    ForEach(members) { bot in
                        Text(bot.name(lang)).tag(Optional(bot.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            TextField(s.t("交付物正文或关键结论…", "Content or key findings…"), text: $delivContentDraft, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.plain)
                .font(PipiTokens.fontCaption)
                .padding(PipiTokens.spacing8)
                .background(PipiTokens.bgInset, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

            HStack {
                PipiActionButton(s.cancel, tone: .ghost, density: .desktopCompact) {
                    showAddDeliverable = false
                }
                Spacer()
                PipiActionButton(s.save, systemImage: "checkmark", tone: .primary, density: .desktopCompact) {
                    let deliv = PipiGroupDeliverable(
                        title: delivTitleDraft,
                        kind: delivKind,
                        summary: "",
                        content: delivContentDraft,
                        producedByPersonaId: delivProducerId,
                        topicId: group.effectiveActiveTopicId
                    )
                    if store.addGroupDeliverable(groupId: group.id, deliverable: deliv) != nil {
                        delivTitleDraft = ""
                        delivContentDraft = ""
                        showAddDeliverable = false
                    }
                }
                .disabled(delivTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderStrong, lineWidth: 1)
        )
    }

    private func deliverableCard(_ item: PipiGroupDeliverable, group: PipiGroupChat) -> some View {
        let producer = item.producedByPersonaId.flatMap { pid in
            store.personas.first(where: { $0.id == pid })
        }
        let topicTitle: String = {
            if let tid = item.topicId, let t = group.topics.first(where: { $0.id == tid }) {
                return t.localizedTitle(lang)
            }
            return group.defaultTopic.localizedTitle(lang)
        }()

        return Button {
            previewDeliverable = item
        } label: {
            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                HStack(spacing: PipiTokens.spacing8) {
                    Image(systemName: item.kind.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                        .frame(width: 24, height: 24)
                        .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(PipiTokens.fontCaption.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            Text(item.kind.label(lang))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textSecondary)
                            Text("·")
                                .foregroundStyle(PipiTokens.textMuted)
                            Text("#\(topicTitle)")
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textMuted)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    PipiGhostIconButton(
                        systemImage: "trash",
                        size: 24,
                        iconSize: 10.5,
                        cornerRadius: 6,
                        accessibilityLabel: s.delete
                    ) {
                        store.deleteGroupDeliverable(groupId: group.id, deliverableId: item.id)
                    }
                }

                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack(spacing: 6) {
                    if let producer {
                        PipiBotPersonaGlyph(persona: producer, size: 15, isSelected: true)
                        Text(producer.name(lang))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if !item.createdAt.isEmpty {
                        Text(store.relativeTimeLabel(for: item.createdAt))
                            .font(PipiTokens.fontMonoSmall)
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.99))
    }

    private func deliverablePreviewSheet(_ item: PipiGroupDeliverable, group: PipiGroupChat) -> some View {
        let producer = item.producedByPersonaId.flatMap { pid in
            store.personas.first(where: { $0.id == pid })
        }
        return VStack(spacing: 0) {
            HStack(spacing: PipiTokens.spacing12) {
                Image(systemName: item.kind.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(PipiTokens.fontHeadline)
                        .foregroundStyle(PipiTokens.textPrimary)
                    HStack(spacing: 6) {
                        Text(item.kind.label(lang))
                        if let producer {
                            Text("·")
                            Text(producer.name(lang))
                        }
                    }
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                }

                Spacer()

                PipiActionButton(
                    copiedDeliverableId == item.id ? s.copied : s.t("复制全文", "Copy All"),
                    systemImage: copiedDeliverableId == item.id ? "checkmark" : "doc.on.doc",
                    tone: .secondary,
                    density: .desktopCompact
                ) {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.content, forType: .string)
                    #endif
                    copiedDeliverableId = item.id
                }

                PipiActionButton(s.close, tone: .primary, density: .desktopCompact) {
                    previewDeliverable = nil
                }
            }
            .padding(PipiTokens.spacing20)

            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

            ScrollView(showsIndicators: false) {
                PipiMarkdownView(
                    content: item.content.isEmpty ? item.summary : item.content,
                    strings: s,
                    accent: PipiTokens.soulPrimary,
                    isStreaming: false
                )
                .padding(PipiTokens.spacing24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .pipiHideScrollbars()
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 440, idealHeight: 540)
        .background(PipiTokens.bgCanvas)
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
    }

    // MARK: - Tab 3: Skills & Shared Memory

    private func skillsSection(group: PipiGroupChat) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack {
                sectionTitle(s.t("群 Skill", "Group Skills"))
                Spacer()
                Button {
                    withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                        showAddSkill.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showAddSkill ? "minus" : "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(s.t("新增 Skill", "Add Skill"))
                            .font(PipiTokens.fontMicro.weight(.medium))
                    }
                    .foregroundStyle(PipiTokens.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
            }

            if showAddSkill {
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    TextField(s.t("Skill 名称（例如：代码安全审计）", "Skill name (e.g., Security Audit)"), text: $skillNameDraft)
                        .textFieldStyle(.plain)
                        .font(PipiTokens.fontCaption)
                        .padding(PipiTokens.spacing8)
                        .background(PipiTokens.bgInset, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

                    TextField(s.t("执行规范与协作指令…", "Collaboration rule or instruction…"), text: $skillInstructionDraft, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .font(PipiTokens.fontCaption)
                        .padding(PipiTokens.spacing8)
                        .background(PipiTokens.bgInset, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

                    HStack {
                        PipiActionButton(s.cancel, tone: .ghost, density: .desktopCompact) {
                            showAddSkill = false
                        }
                        Spacer()
                        PipiActionButton(s.save, systemImage: "checkmark", tone: .primary, density: .desktopCompact) {
                            if store.addGroupSkill(groupId: group.id, name: skillNameDraft, instruction: skillInstructionDraft) != nil {
                                skillNameDraft = ""
                                skillInstructionDraft = ""
                                showAddSkill = false
                            }
                        }
                        .disabled(
                            skillNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            skillInstructionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }
                .padding(12)
                .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                        .stroke(PipiTokens.borderStrong, lineWidth: 1)
                )
            }

            VStack(spacing: 0) {
                ForEach(Array(group.skills.enumerated()), id: \.element.id) { idx, skill in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: PipiTokens.spacing8) {
                            Text(skill.localizedName(lang))
                                .font(PipiTokens.fontCaption.weight(.semibold))
                                .foregroundStyle(PipiTokens.textPrimary)

                            if skill.isBuiltIn {
                                Text(s.builtInBadge)
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(PipiTokens.textMuted)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(PipiTokens.bgSurface, in: Capsule())
                            }

                            Spacer()

                            if !skill.isBuiltIn {
                                PipiGhostIconButton(
                                    systemImage: "trash",
                                    size: 22,
                                    iconSize: 10,
                                    cornerRadius: 5,
                                    accessibilityLabel: s.delete
                                ) {
                                    store.deleteGroupSkill(groupId: group.id, skillId: skill.id)
                                }
                            }

                            Toggle("", isOn: Binding(
                                get: { skill.isEnabled },
                                set: { store.toggleGroupSkill(groupId: group.id, skillId: skill.id, enabled: $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        }

                        Text(skill.instruction)
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .lineLimit(3)
                    }
                    .padding(12)

                    if idx < group.skills.count - 1 {
                        cardDivider
                    }
                }
            }
            .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )
        }
    }

    private func sharedMemorySection(group: PipiGroupChat) -> some View {
        let sortedMemories = group.sharedMemories.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            return lhs.createdAt > rhs.createdAt
        }

        return VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack {
                sectionTitle(s.t("群共享记忆 (\(sortedMemories.count))", "Shared Memory (\(sortedMemories.count))"))
                Spacer()
                Button {
                    withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                        showAddMemory.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showAddMemory ? "minus" : "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(s.t("添加群记忆", "Add Memory"))
                            .font(PipiTokens.fontMicro.weight(.medium))
                    }
                    .foregroundStyle(PipiTokens.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(PipiTokens.stateSuccess)
                    .frame(width: 6, height: 6)
                Text(s.t("已自动注入本群全部智能体", "Automatically injected into all agents in this group"))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )

            if showAddMemory {
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    TextField(s.t("输入团队共识、项目约束或重要事实…", "Shared fact, decision, or constraint…"), text: $memoryContentDraft, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .font(PipiTokens.fontCaption)
                        .padding(PipiTokens.spacing8)
                        .background(PipiTokens.bgInset, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

                    HStack {
                        Toggle(s.t("置顶记忆", "Pin memory"), isOn: $memoryPinnedDraft)
                            .toggleStyle(.checkbox)
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textSecondary)

                        Spacer()

                        PipiActionButton(s.cancel, tone: .ghost, density: .desktopCompact) {
                            showAddMemory = false
                        }

                        PipiActionButton(s.save, systemImage: "checkmark", tone: .primary, density: .desktopCompact) {
                            if store.addGroupMemory(groupId: group.id, content: memoryContentDraft, source: s.t("手动添加", "Manual"), pinned: memoryPinnedDraft) != nil {
                                memoryContentDraft = ""
                                showAddMemory = false
                            }
                        }
                        .disabled(memoryContentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(12)
                .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                        .stroke(PipiTokens.borderStrong, lineWidth: 1)
                )
            }

            if sortedMemories.isEmpty && !showAddMemory {
                Text(s.t("暂无群共享记忆。可在回复上点击「存入群记忆」或直接在此添加。",
                         "No shared memories yet. Bookmark any reply or add shared context above."))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textMuted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                            .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                    )
            } else {
                ForEach(sortedMemories) { mem in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(mem.content)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 6) {
                            if let src = mem.source, !src.isEmpty {
                                Text(src)
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(PipiTokens.textMuted)
                                    .lineLimit(1)
                            }
                            if !mem.createdAt.isEmpty {
                                Text(store.relativeTimeLabel(for: mem.createdAt))
                                    .font(PipiTokens.fontMonoSmall)
                                    .foregroundStyle(PipiTokens.textMuted)
                            }
                            Spacer()

                            PipiGhostIconButton(
                                systemImage: mem.isPinned ? "pin.fill" : "pin",
                                isActive: mem.isPinned,
                                activeColor: PipiTokens.soulPrimary,
                                size: 22,
                                iconSize: 10.5,
                                cornerRadius: 5,
                                accessibilityLabel: mem.isPinned ? s.unpinChat : s.pinChat
                            ) {
                                store.togglePinGroupMemory(groupId: group.id, memoryId: mem.id)
                            }

                            PipiGhostIconButton(
                                systemImage: "trash",
                                size: 22,
                                iconSize: 10,
                                cornerRadius: 5,
                                accessibilityLabel: s.delete
                            ) {
                                store.deleteGroupMemory(groupId: group.id, memoryId: mem.id)
                            }
                        }
                    }
                    .padding(12)
                    .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                            .stroke(mem.isPinned ? PipiTokens.borderStrong : PipiTokens.borderSubtle, lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - Wave 3 (#06): Dynamic Bot Proposals & team.md Protocol

    @ViewBuilder
    private func dynamicBotProposalsSection(group: PipiGroupChat) -> some View {
        let pending = group.dynamicBotProposals.filter { $0.status == .pending }
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                sectionTitle("\(s.dynamicBotProposalsTitle) (\(pending.count))")

                ForEach(pending) { prop in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(PipiTokens.stateWarning)
                            Text(prop.proposedName)
                                .font(PipiTokens.fontSubheadline.weight(.semibold))
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text(prop.action.label(lang))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.stateWarning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(PipiTokens.stateWarningBg, in: Capsule())
                        }

                        Text(prop.rationale)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)

                        HStack(spacing: PipiTokens.spacing8) {
                            PipiActionButton(s.approveAndJoinAction, systemImage: "checkmark", tone: .primary, density: .desktopCompact) {
                                _ = store.resolveDynamicBotProposal(groupId: group.id, proposalId: prop.id, approve: true)
                            }
                            PipiActionButton(s.reject, tone: .ghost, density: .desktopCompact) {
                                _ = store.resolveDynamicBotProposal(groupId: group.id, proposalId: prop.id, approve: false)
                            }
                        }
                    }
                    .padding(12)
                    .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                            .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                    )
                }
            }
        }
    }

    private func teamProtocolSection(group: PipiGroupChat) -> some View {
        let validation = store.validateGroupTeamProtocol(groupId: group.id)

        return VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack {
                sectionTitle(s.teamProtocolTitle)
                Spacer()
                if let validation {
                    Text(validation.valid ? s.t("协议有效", "Valid") : s.t("\(validation.issues.count) 处待修正", "\(validation.issues.count) issue(s)"))
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(validation.valid ? PipiTokens.stateSuccess : PipiTokens.stateWarning)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Menu {
                    ForEach(PipiTeamCollaborationPattern.allCases, id: \.self) { pat in
                        Button {
                            selectedTeamPattern = pat
                        } label: {
                            if selectedTeamPattern == pat {
                                Label(pat.label(lang), systemImage: "checkmark")
                            } else {
                                Text(pat.label(lang))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: PipiTokens.spacing8) {
                        Text(selectedTeamPattern.label(lang))
                            .font(PipiTokens.fontCaption.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(PipiTokens.buttonSecondaryBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                            .strokeBorder(PipiTokens.composerBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                }
                .pipiPlainMenu()

                HStack(spacing: PipiTokens.spacing8) {
                    PipiActionButton(s.teamProtocolGenerate, systemImage: "doc.badge.plus", tone: .secondary, density: .desktopCompact, fullWidth: true) {
                        if let md = store.generateGroupTeamTemplate(groupId: group.id, pattern: selectedTeamPattern) {
                            teamProtocolDraft = md
                        }
                    }
                    PipiActionButton(s.t("编辑协议", "Edit"), systemImage: "pencil", tone: .secondary, density: .desktopCompact, fullWidth: true) {
                        teamProtocolDraft = group.teamProtocolMarkdown ?? (store.generateGroupTeamTemplate(groupId: group.id, pattern: selectedTeamPattern) ?? "")
                        showTeamProtocolEditor = true
                    }
                }

                if let doc = validation?.document {
                    Text("\(doc.pattern.label(lang)) · \(doc.members.count) members · \(validation?.executionWaves.count ?? 0) wave(s)")
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                }

                if validation?.valid == true {
                    HStack(spacing: PipiTokens.spacing8) {
                        TextField(s.t("输入本次协作指令...", "Protocol run prompt..."), text: $teamProtocolPromptDraft)
                            .textFieldStyle(.plain)
                            .font(PipiTokens.fontCaption)
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(PipiTokens.bgInset)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

                        PipiActionButton(
                            isRunningTeamProtocol ? s.t("执行中...", "Running...") : s.teamProtocolRun,
                            systemImage: "play.fill",
                            tone: .primary,
                            density: .desktopCompact
                        ) {
                            guard !isRunningTeamProtocol else { return }
                            let prompt = teamProtocolPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? (validation?.document?.taskGoal ?? group.title)
                                : teamProtocolPromptDraft
                            isRunningTeamProtocol = true
                            Task {
                                _ = try? await store.runGroupTeamProtocol(groupId: group.id, userPrompt: prompt)
                                teamProtocolPromptDraft = ""
                                isRunningTeamProtocol = false
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(PipiTokens.bgElevated, in: RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )
        }
    }

    private func teamProtocolEditorSheet(group: PipiGroupChat) -> some View {
        let previewValidation = PipiTeamProtocol.parseAndValidate(
            teamProtocolDraft,
            roomMemberActorIds: group.participantPersonaIds
        )
        return VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack {
                Text("team.md · \(group.title)")
                    .font(PipiTokens.fontTitle)
                    .foregroundStyle(PipiTokens.textPrimary)
                Spacer()
                PipiGhostIconButton(systemImage: "xmark", size: 28, iconSize: 12, accessibilityLabel: s.close) {
                    showTeamProtocolEditor = false
                }
            }

            TextEditor(text: $teamProtocolDraft)
                .font(PipiTokens.fontMono)
                .scrollContentBackground(.hidden)
                .padding(PipiTokens.spacing8)
                .frame(minHeight: 260)
                .background(PipiTokens.bgInset)
                .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

            if !previewValidation.issues.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(previewValidation.issues.prefix(4)) { issue in
                        Text("• [\(issue.code)] \(issue.message)")
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.stateWarning)
                    }
                }
            } else {
                Text(s.t("校验通过 · DAG 执行波次：\(previewValidation.executionWaves.count) 波",
                         "Valid team.md · DAG execution waves: \(previewValidation.executionWaves.count)"))
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.stateSuccess)
            }

            HStack {
                PipiActionButton(s.cancel, tone: .secondary, density: .desktopCompact) {
                    showTeamProtocolEditor = false
                }
                Spacer()
                PipiActionButton(s.save, systemImage: "checkmark", tone: .primary, density: .desktopCompact) {
                    _ = store.updateGroupTeamProtocol(groupId: group.id, markdown: teamProtocolDraft)
                    showTeamProtocolEditor = false
                }
            }
        }
        .padding(PipiTokens.spacing24)
        .background(PipiTokens.bgCanvas)
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(PipiTokens.fontMicro)
            .foregroundStyle(PipiTokens.textMuted)
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(PipiTokens.borderSubtle)
            .frame(height: 1)
    }
}
