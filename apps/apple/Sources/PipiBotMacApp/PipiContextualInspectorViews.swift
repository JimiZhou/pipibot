import SwiftUI
import PipiBotKit

// MARK: - 1. Home / Agents Space Contextual Inspector

public struct PipiHomeInspectorView: View {
    @Bindable public var store: PipiAppStore
    public var onSelectBotChat: (PipiBotPersona) -> Void
    public var onEditBot: (PipiBotPersona) -> Void
    public var onCreateBot: () -> Void
    public var onCreateGroup: () -> Void
    public var onReset3DCamera: () -> Void
    public var onOpenHelp: (PipiHelpTopic) -> Void

    @Environment(\.pipiTextScale) private var textScale

    public init(
        store: PipiAppStore,
        onSelectBotChat: @escaping (PipiBotPersona) -> Void,
        onEditBot: @escaping (PipiBotPersona) -> Void,
        onCreateBot: @escaping () -> Void,
        onCreateGroup: @escaping () -> Void,
        onReset3DCamera: @escaping () -> Void,
        onOpenHelp: @escaping (PipiHelpTopic) -> Void
    ) {
        self.store = store
        self.onSelectBotChat = onSelectBotChat
        self.onEditBot = onEditBot
        self.onCreateBot = onCreateBot
        self.onCreateGroup = onCreateGroup
        self.onReset3DCamera = onReset3DCamera
        self.onOpenHelp = onOpenHelp
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    private var workingCount: Int {
        store.personas.filter { store.isPersonaRunning($0.id) }.count
    }

    private var collaboratingCount: Int {
        store.collaboratingBotIds.count
    }

    private var needsApprovalCount: Int {
        store.totalNeedsYouCount
    }

    private var idleCount: Int {
        max(0, store.personas.count - workingCount)
    }

    public var body: some View {
        let _ = textScale
        VStack(spacing: 0) {
            inspectorHeader(title: s.t("空间概览", "Space Overview"), topic: .gettingStarted)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                    inspectorCard(title: s.t("运行状态", "Status Summary")) {
                        PipiKeyValueRow(key: s.t("助手总数", "Total Assistants"), value: "\(store.personas.count)", monospaced: true)
                        PipiKeyValueRow(
                            key: s.t("工作中", "Working"),
                            value: "\(workingCount)",
                            valueColor: workingCount > 0 ? PipiTokens.stateSuccess : PipiTokens.textSecondary,
                            monospaced: true
                        )
                        PipiKeyValueRow(
                            key: s.t("协作中", "Collaborating"),
                            value: "\(collaboratingCount)",
                            valueColor: collaboratingCount > 0 ? PipiTokens.soulSecondary : PipiTokens.textSecondary,
                            monospaced: true
                        )
                        PipiKeyValueRow(
                            key: s.t("待确认", "Pending"),
                            value: "\(needsApprovalCount)",
                            valueColor: needsApprovalCount > 0 ? PipiTokens.stateWarning : PipiTokens.textSecondary,
                            monospaced: true
                        )
                        PipiKeyValueRow(key: s.t("空闲", "Idle"), value: "\(idleCount)", monospaced: true)
                    }

                    inspectorCard(title: s.t("助手列表", "Assistants")) {
                        ForEach(Array(store.personas.enumerated()), id: \.element.id) { idx, bot in
                            if idx > 0 {
                                Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
                            }
                            let isBusy = store.isPersonaRunning(bot.id)
                            HStack(spacing: PipiTokens.spacing8) {
                                Button {
                                    onSelectBotChat(bot)
                                } label: {
                                    HStack(spacing: PipiTokens.spacing8) {
                                        PipiBotPersonaGlyph(persona: bot, size: 22, isSelected: isBusy)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(bot.name(lang))
                                                .font(PipiTokens.fontCaption.weight(.semibold))
                                                .foregroundStyle(PipiTokens.textPrimary)
                                                .lineLimit(1)
                                            Text(isBusy ? s.t("工作中", "Working") : s.t("空闲", "Idle"))
                                                .font(PipiTokens.fontMicro)
                                                .foregroundStyle(isBusy ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                PipiGhostIconButton(
                                    systemImage: "pencil",
                                    size: 24,
                                    iconSize: 11,
                                    accessibilityLabel: s.edit
                                ) {
                                    onEditBot(bot)
                                }
                            }
                        }
                    }

                    inspectorCard(title: s.t("快捷操作", "Actions")) {
                        HStack(spacing: PipiTokens.spacing8) {
                            PipiActionButton(s.newBot, systemImage: "plus", tone: .secondary, density: .desktopCompact, fullWidth: true) {
                                onCreateBot()
                            }
                            PipiActionButton(s.newGroupChat, systemImage: "person.2", tone: .secondary, density: .desktopCompact, fullWidth: true) {
                                onCreateGroup()
                            }
                        }
                        PipiActionButton(s.t("重置 3D 视角", "Reset 3D Camera"), systemImage: "arrow.counterclockwise", tone: .ghost, density: .desktopCompact, fullWidth: true) {
                            onReset3DCamera()
                        }
                    }
                }
                .padding(PipiTokens.spacing16)
            }
            .pipiHideScrollbars()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PipiTokens.bgSidebar.ignoresSafeArea(.container, edges: .top))
    }

    private func inspectorHeader(title: String, topic: PipiHelpTopic) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: PipiTokens.spacing8) {
                Text(title)
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)
                Spacer()
                PipiGhostIconButton(
                    systemImage: "questionmark.circle",
                    size: 24,
                    iconSize: 12.5,
                    accessibilityLabel: s.t("帮助", "Help")
                ) {
                    onOpenHelp(topic)
                }
                .help(s.t("查看说明", "View Help"))
            }
            .padding(.horizontal, PipiTokens.spacing16)
            .padding(.top, 12)
            .padding(.bottom, PipiTokens.spacing12)
            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
        }
    }
}

// MARK: - 2. Session Contextual Inspector (Session Details default + optional Assistant tab)

private enum PipiSessionInspectorMode: String, CaseIterable, Identifiable {
    case session
    case assistant

    var id: String { rawValue }

    func label(_ s: PipiStrings) -> String {
        switch self {
        case .session: return s.t("会话", "Session")
        case .assistant: return s.t("助手", "Assistant")
        }
    }
}

public struct PipiSessionInspectorView: View {
    @Bindable public var store: PipiAppStore
    public var sessionId: String
    public var onEditBot: (PipiBotPersona) -> Void
    public var onOpenBotRoutines: (PipiBotPersona) -> Void
    public var onClose: () -> Void
    public var onOpenHelp: (PipiHelpTopic) -> Void

    @State private var mode: PipiSessionInspectorMode = .session
    @Environment(\.pipiTextScale) private var textScale

    public init(
        store: PipiAppStore,
        sessionId: String,
        onEditBot: @escaping (PipiBotPersona) -> Void,
        onOpenBotRoutines: @escaping (PipiBotPersona) -> Void,
        onClose: @escaping () -> Void,
        onOpenHelp: @escaping (PipiHelpTopic) -> Void
    ) {
        self.store = store
        self.sessionId = sessionId
        self.onEditBot = onEditBot
        self.onOpenBotRoutines = onOpenBotRoutines
        self.onClose = onClose
        self.onOpenHelp = onOpenHelp
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    private var session: PipiConversation? {
        store.conversations.first(where: { $0.id == sessionId }) ?? store.activeConversation
    }

    private var sessionPersona: PipiBotPersona {
        if let pid = session?.personaId,
           let matched = store.personas.first(where: { $0.id == pid }) {
            return matched
        }
        return store.activePersona
    }

    public var body: some View {
        let _ = textScale
        VStack(spacing: 0) {
            HStack(spacing: PipiTokens.spacing8) {
                Text(mode == .session ? s.t("会话详情", "Session Details") : s.t("助手配置", "Assistant"))
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)
                Spacer()
                PipiSegmentedControl(options: PipiSessionInspectorMode.allCases, selection: $mode) { item in
                    item.label(s)
                }
            }
            .padding(.horizontal, PipiTokens.spacing16)
            .padding(.top, 10)
            .padding(.bottom, 10)

            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

            if mode == .session {
                sessionDetailsBody
            } else {
                PipiBotInspectorView(
                    store: store,
                    showHeader: false,
                    onEditBot: onEditBot,
                    onOpenBotRoutines: onOpenBotRoutines,
                    onClose: onClose
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PipiTokens.bgSidebar.ignoresSafeArea(.container, edges: .top))
    }

    private var sessionDetailsBody: some View {
        let conv = session
        let planItems = conv?.planItems ?? []
        let fileChanges = conv?.fileChanges ?? []
        let bgTasks = store.alterEgoTasks(forSession: conv?.id ?? sessionId)
        let project = conv?.projectId.flatMap { pid in store.projects.first(where: { $0.id == pid }) }
        let workspacePath = project?.workspacePath?.isEmpty == false ? (project?.workspacePath ?? store.workspaceDirectory) : store.workspaceDirectory

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                inspectorCard(title: s.t("会话属性", "Session Metadata")) {
                    PipiKeyValueRow(key: s.t("标题", "Title"), value: conv?.title ?? "-")
                    PipiKeyValueRow(key: s.t("助手", "Assistant"), value: sessionPersona.name(lang))
                    PipiKeyValueRow(key: s.t("执行引擎", "Engine"), value: store.activeEngineDisplayLabel(for: sessionPersona))
                    PipiKeyValueRow(key: s.permissionTierTitle, value: sessionPersona.permissionTier.label(lang))
                    PipiKeyValueRow(key: s.t("消息数", "Messages"), value: "\(conv?.messages.count ?? 0)", monospaced: true)
                    if let project {
                        PipiKeyValueRow(key: s.t("所属项目", "Project"), value: project.name)
                    }
                    PipiKeyValueRow(key: s.t("工作目录", "Workspace"), value: (workspacePath as NSString).abbreviatingWithTildeInPath, monospaced: true)
                }

                // v0.13.0 Automation Blueprint + Worktree + Usage Quick Card
                if let bp = sessionPersona.automationBlueprint, bp.isConfigured {
                    inspectorCard(title: s.t("自动化蓝图 (v\(bp.blueprintVersion))", "Automation Blueprint (v\(bp.blueprintVersion))")) {
                        PipiKeyValueRow(key: s.t("终极目标", "Goal"), value: bp.goal)
                        PipiKeyValueRow(key: s.t("流程步骤", "Steps"), value: "\(bp.processSteps.count)", monospaced: true)
                        PipiKeyValueRow(key: s.t("验收标准", "Checks"), value: "\(bp.verificationCriteria.count)", monospaced: true)
                        Button {
                            _ = store.proposeBlueprintEvolution(
                                botId: sessionPersona.id,
                                rationale: lang == .zhHans
                                    ? "主人主动发起对照原始目标的蓝图自检优化"
                                    : "Owner-initiated blueprint review against original Goal",
                                addedVerification: [lang == .zhHans ? "交付前显式核对每条验收标准" : "Explicitly verify every criterion before closing"]
                            )
                        } label: {
                            Label(s.t("对照目标生成自进化提案", "Propose goal review diff"), systemImage: "arrow.triangle.2.circlepath")
                                .font(PipiTokens.fontCaption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                let convWorktrees = store.worktreeSessions.filter { $0.conversationId == sessionId }
                if !convWorktrees.isEmpty {
                    inspectorCard(title: s.t("隔离 Worktree (\(convWorktrees.count))", "Worktree Sandbox (\(convWorktrees.count))")) {
                        ForEach(convWorktrees.prefix(3)) { wt in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(wt.branchName)
                                    .font(PipiTokens.fontMonoSmall.weight(.semibold))
                                    .foregroundStyle(PipiTokens.soulPrimary)
                                Text(wt.diffSummary)
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textSecondary)
                            }
                        }
                    }
                }

                let sessionUsage = store.usageRecords.filter { $0.conversationId == sessionId }
                if !sessionUsage.isEmpty {
                    let tokens = sessionUsage.reduce(0) { $0 + $1.totalTokens }
                    let usd = sessionUsage.reduce(0.0) { $0 + $1.estimatedCostUSD }
                    inspectorCard(title: s.t("本会话用量（仅统计不拦截）", "Session Usage (Alert-Only)")) {
                        PipiKeyValueRow(key: "Tokens", value: "\(tokens)", monospaced: true)
                        PipiKeyValueRow(key: s.t("估算费用", "Est. USD"), value: "$\(String(format: "%.4f", usd))", monospaced: true)
                    }
                }

                if !bgTasks.isEmpty {
                    inspectorCard(title: s.t("后台任务 (\(bgTasks.count))", "Background Tasks (\(bgTasks.count))")) {
                        ForEach(bgTasks.prefix(5)) { task in
                            HStack(spacing: PipiTokens.spacing8) {
                                Text(task.title)
                                    .font(PipiTokens.fontCaption.weight(.medium))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(task.status.label(lang))
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(task.status == .completed ? PipiTokens.stateSuccess : PipiTokens.textSecondary)
                            }
                        }
                    }
                }

                inspectorCard(title: "\(s.planTitle) (\(planItems.count))") {
                    if planItems.isEmpty {
                        Text(s.planEmpty)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textMuted)
                    } else {
                        ForEach(planItems) { item in
                            HStack(spacing: 6) {
                                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(item.isCompleted ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                Text(item.title)
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                inspectorCard(title: "\(s.inspectorTabChanges) (\(fileChanges.count))") {
                    if fileChanges.isEmpty {
                        Text(s.changesEmpty)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textMuted)
                    } else {
                        ForEach(fileChanges.prefix(10)) { change in
                            HStack(spacing: PipiTokens.spacing8) {
                                Text((change.path as NSString).lastPathComponent)
                                    .font(PipiTokens.fontMonoSmall)
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text("+\(change.additions) -\(change.deletions)")
                                    .font(PipiTokens.fontMonoSmall)
                                    .foregroundStyle(PipiTokens.textMuted)
                            }
                        }
                    }
                }
            }
            .padding(PipiTokens.spacing16)
        }
        .pipiHideScrollbars()
    }
}

// MARK: - 3. Knowledge Hub Contextual Inspector

public struct PipiKnowledgeInspectorView: View {
    @Bindable public var store: PipiAppStore
    public var onOpenSettings: (PipiSettingsTab) -> Void
    public var onOpenHelp: (PipiHelpTopic) -> Void

    @State private var isScanning: Bool = false
    @State private var feedbackText: String? = nil
    @Environment(\.pipiTextScale) private var textScale

    public init(
        store: PipiAppStore,
        onOpenSettings: @escaping (PipiSettingsTab) -> Void,
        onOpenHelp: @escaping (PipiHelpTopic) -> Void
    ) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        self.onOpenHelp = onOpenHelp
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    public var body: some View {
        let _ = textScale
        let openTodos = store.pocketTrackingItems.filter { $0.status == .open }.count

        VStack(spacing: 0) {
            HStack(spacing: PipiTokens.spacing8) {
                Text(s.t("知识库概览", "Knowledge Overview"))
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)
                Spacer()
                PipiGhostIconButton(
                    systemImage: "questionmark.circle",
                    size: 24,
                    iconSize: 12.5,
                    accessibilityLabel: s.t("帮助", "Help")
                ) {
                    onOpenHelp(.knowledgeMemory)
                }
                .help(s.t("查看知识库说明", "Knowledge Help"))
            }
            .padding(.horizontal, PipiTokens.spacing16)
            .padding(.top, 12)
            .padding(.bottom, PipiTokens.spacing12)

            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                    inspectorCard(title: s.t("数据统计", "Statistics")) {
                        PipiKeyValueRow(key: s.t("词条总数", "Entries"), value: "\(store.wikiPages.count)", monospaced: true)
                        PipiKeyValueRow(key: s.t("日程简报", "Schedule Briefs"), value: "\(store.proactiveBriefings.count)", monospaced: true)
                        PipiKeyValueRow(
                            key: s.t("待办事项", "To-Dos"),
                            value: "\(openTodos) / \(store.pocketTrackingItems.count)",
                            monospaced: true
                        )
                        PipiKeyValueRow(key: s.t("文档数量", "Documents"), value: "\(store.artifactDocuments.count)", monospaced: true)
                        PipiKeyValueRow(key: s.t("内置技能", "Builtin Skills"), value: "\(PipiBuiltinSkillsRegistry.allPacks.count)", monospaced: true)
                        PipiKeyValueRow(
                            key: s.t("检索索引", "Search Index"),
                            value: store.personalWiki?.supportsFts5 == true ? s.t("本地全文索引", "Local Full-Text") : s.t("本地数据库", "Local DB"),
                            helpMessage: s.t("数据存储在本地 SQLite 数据库中，使用全文索引实现离线检索，不依赖外部向量服务。", "Stored in local SQLite with full-text indexing for offline search without external embedding models.")
                        )
                    }

                    inspectorCard(title: s.t("系统数据源", "System Sources")) {
                        PipiKeyValueRow(
                            key: s.t("Apple 日历", "Apple Calendar"),
                            value: store.eventKitCalendarAuth.label(lang),
                            valueColor: store.eventKitCalendarAuth == .authorized ? PipiTokens.stateSuccess : PipiTokens.textSecondary
                        )
                        PipiKeyValueRow(
                            key: s.t("提醒事项", "Reminders"),
                            value: store.eventKitRemindersAuth.label(lang),
                            valueColor: store.eventKitRemindersAuth == .authorized ? PipiTokens.stateSuccess : PipiTokens.textSecondary
                        )
                        if store.eventKitCalendarAuth != .authorized || store.eventKitRemindersAuth != .authorized {
                            HStack(spacing: PipiTokens.spacing8) {
                                if store.eventKitCalendarAuth != .authorized {
                                    PipiActionButton(s.t("授权日历", "Calendar"), tone: .secondary, density: .desktopCompact, fullWidth: true) {
                                        Task { await store.requestEventKitCalendarAccess() }
                                    }
                                }
                                if store.eventKitRemindersAuth != .authorized {
                                    PipiActionButton(s.t("授权提醒", "Reminders"), tone: .secondary, density: .desktopCompact, fullWidth: true) {
                                        Task { await store.requestEventKitRemindersAccess() }
                                    }
                                }
                            }
                        }
                    }

                    inspectorCard(title: s.t("常用操作", "Actions")) {
                        PipiActionButton(
                            isScanning ? s.t("扫描中...", "Scanning...") : s.proactiveScanNow,
                            systemImage: "arrow.clockwise",
                            tone: .secondary,
                            density: .desktopCompact,
                            fullWidth: true
                        ) {
                            guard !isScanning else { return }
                            isScanning = true
                            Task {
                                let res = await store.scanNativeProactiveSignals()
                                feedbackText = s.t("已扫描 \(res.count) 条数据源记录。", "Scanned \(res.count) source item(s).")
                                isScanning = false
                            }
                        }
                        PipiActionButton(
                            s.t("防打扰与记忆设置", "Memory & Guardrails"),
                            systemImage: "gearshape",
                            tone: .ghost,
                            density: .desktopCompact,
                            fullWidth: true
                        ) {
                            onOpenSettings(.memoryPrivacy)
                        }
                        if let feedbackText {
                            Text(feedbackText)
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.stateSuccess)
                        }
                    }
                }
                .padding(PipiTokens.spacing16)
            }
            .pipiHideScrollbars()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PipiTokens.bgSidebar.ignoresSafeArea(.container, edges: .top))
    }
}

// MARK: - 4. Needs You / Approvals Contextual Inspector

public struct PipiNeedsYouInspectorView: View {
    @Bindable public var store: PipiAppStore
    public var onOpenSettings: (PipiSettingsTab) -> Void
    public var onOpenHelp: (PipiHelpTopic) -> Void

    @Environment(\.pipiTextScale) private var textScale

    public init(
        store: PipiAppStore,
        onOpenSettings: @escaping (PipiSettingsTab) -> Void,
        onOpenHelp: @escaping (PipiHelpTopic) -> Void
    ) {
        self.store = store
        self.onOpenSettings = onOpenSettings
        self.onOpenHelp = onOpenHelp
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    public var body: some View {
        let _ = textScale
        VStack(spacing: 0) {
            HStack(spacing: PipiTokens.spacing8) {
                Text(s.t("确认与安全策略", "Approvals & Policy"))
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)
                Spacer()
                PipiGhostIconButton(
                    systemImage: "questionmark.circle",
                    size: 24,
                    iconSize: 12.5,
                    accessibilityLabel: s.t("帮助", "Help")
                ) {
                    onOpenHelp(.desktopSafety)
                }
                .help(s.t("查看审批与安全说明", "Safety Help"))
            }
            .padding(.horizontal, PipiTokens.spacing16)
            .padding(.top, 12)
            .padding(.bottom, PipiTokens.spacing12)

            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                    inspectorCard(title: s.t("待处理统计", "Queue Summary")) {
                        PipiKeyValueRow(key: s.t("权限审批", "Permission Requests"), value: "\(store.pendingApprovals.count)", monospaced: true)
                        PipiKeyValueRow(key: s.t("个人决策", "Decisions"), value: "\(store.pendingDecisions.count)", monospaced: true)
                        PipiKeyValueRow(key: s.t("成员建议", "Team Proposals"), value: "\(store.pendingDynamicBotProposals.count)", monospaced: true)
                        PipiKeyValueRow(
                            key: s.t("风险评估护栏", "Risk Guardrail"),
                            value: store.llmGuardrailJudgeEnabled ? s.enabled : s.disabled,
                            valueColor: store.llmGuardrailJudgeEnabled ? PipiTokens.stateSuccess : PipiTokens.textMuted
                        )
                    }

                    inspectorCard(title: s.t("已保存授权规则 (\(store.approvalWhitelistRules.count))", "Saved Rules (\(store.approvalWhitelistRules.count))")) {
                        if store.approvalWhitelistRules.isEmpty {
                            Text(s.t("暂无已保存的授权规则。", "No saved approval rules."))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textMuted)
                        } else {
                            ForEach(Array(store.approvalWhitelistRules.enumerated()), id: \.element.id) { idx, rule in
                                if idx > 0 {
                                    Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
                                }
                                HStack(spacing: PipiTokens.spacing8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rule.toolName)
                                            .font(PipiTokens.fontCaption.weight(.semibold))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                            .lineLimit(1)
                                        Text(rule.granularity.label(lang))
                                            .font(PipiTokens.fontMicro)
                                            .foregroundStyle(PipiTokens.textMuted)
                                    }
                                    Spacer()
                                    PipiGhostIconButton(
                                        systemImage: "trash",
                                        size: 24,
                                        iconSize: 11,
                                        accessibilityLabel: s.delete
                                    ) {
                                        store.revokeApprovalWhitelistRule(id: rule.id)
                                    }
                                }
                            }
                        }
                    }

                    inspectorCard(title: s.t("策略管理", "Policy Controls")) {
                        if !store.approvalWhitelistRules.isEmpty {
                            PipiActionButton(s.clearWhitelistRules, systemImage: "trash", tone: .destructive, density: .desktopCompact, fullWidth: true) {
                                store.clearApprovalWhitelistRules()
                            }
                        }
                        PipiActionButton(
                            s.t("安全与权限设置", "Security Settings"),
                            systemImage: "lock.shield",
                            tone: .secondary,
                            density: .desktopCompact,
                            fullWidth: true
                        ) {
                            onOpenSettings(.memoryPrivacy)
                        }
                    }
                }
                .padding(PipiTokens.spacing16)
            }
            .pipiHideScrollbars()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PipiTokens.bgSidebar.ignoresSafeArea(.container, edges: .top))
    }
}

// MARK: - Shared Inspector Card Container

private func inspectorCard<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
        Text(title)
            .font(PipiTokens.fontCaption.weight(.semibold))
            .foregroundStyle(PipiTokens.textSecondary)

        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PipiTokens.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }
}
