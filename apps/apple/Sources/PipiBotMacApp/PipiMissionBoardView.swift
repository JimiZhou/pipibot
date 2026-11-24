import SwiftUI
import PipiBotKit
#if os(macOS)
import AppKit
#endif

public struct PipiMissionBoardView: View {
    @Bindable public var store: PipiAppStore
    public var initialFocusNeedsYou: Bool
    public var onNewTask: (() -> Void)?
    public var onOpenArchitect: () -> Void
    public var onOpenConversation: (String) -> Void

    private enum MissionTab: String, CaseIterable, Identifiable {
        case board
        case needsYou
        case inspect
        case diffReview
        case triggersEvolution
        case marketplace
        case usage

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .board: return "rectangle.3.group"
            case .needsYou: return "bell"
            case .inspect: return "waveform.path.ecg"
            case .diffReview: return "checkmark.shield"
            case .triggersEvolution: return "bolt.badge.automatic"
            case .marketplace: return "square.grid.2x2"
            case .usage: return "chart.bar.xaxis"
            }
        }

        func title(_ s: PipiStrings) -> String {
            switch self {
            case .board: return s.t("看板", "Board")
            case .needsYou: return s.t("待确认", "Needs you")
            case .inspect: return s.t("活动流", "Activity")
            case .diffReview: return s.t("审查", "Review")
            case .triggersEvolution: return s.t("自动化", "Automation")
            case .marketplace: return s.t("市场", "Market")
            case .usage: return s.t("用量", "Usage")
            }
        }
    }

    @State private var selectedTab: MissionTab = .board
    @State private var selectedChannelFilter: String? = nil
    @State private var selectedBoardThreadId: String? = nil
    @State private var showNewBoardTaskSheet: Bool = false
    @State private var newTaskChannel: String = "inbox"
    @State private var newTaskTitle: String = ""
    @State private var newTaskBody: String = ""
    @State private var newTaskPriority: PipiBoardTaskPriority = .normal
    @State private var newTaskBlockedById: String = ""
    @State private var threadReplyDraft: String = ""
    @State private var threadDeliverableDraft: String = ""
    @State private var threadFollowUpDraft: String = ""
    @State private var selectedWorktreeId: String? = nil
    @State private var reviewFeedbackText: String = ""
    @State private var mergeStrategy: PipiWorktreeMergeStrategy = .squash
    @State private var isVerifyingProof: Bool = false
    @State private var showRawDiffInReview: Bool = true
    @State private var draftRuleNote: String = ""
    @State private var marketplaceFilter: PipiMarketplaceCategory? = nil
    @State private var showNewTriggerSheet: Bool = false
    @State private var newTriggerTitle: String = ""
    @State private var newTriggerPrompt: String = ""
    @State private var newTriggerKind: PipiRoutineTriggerKind = .webhook
    @State private var newTriggerValue: String = ""
    @State private var newTriggerPersonaId: String = ""
    @State private var portableImportMarkdown: String = ""
    @State private var lastExportRedactedCount: Int? = nil

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    public init(
        store: PipiAppStore,
        initialFocusNeedsYou: Bool = false,
        onNewTask: (() -> Void)? = nil,
        onOpenArchitect: @escaping () -> Void = {},
        onOpenConversation: @escaping (String) -> Void = { _ in }
    ) {
        self.store = store
        self.initialFocusNeedsYou = initialFocusNeedsYou
        self.onNewTask = onNewTask
        self.onOpenArchitect = onOpenArchitect
        self.onOpenConversation = onOpenConversation
    }

    public var body: some View {
        VStack(spacing: 0) {
            topHeaderBar
            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
            Group {
                switch selectedTab {
                case .board:
                    boardStage
                case .needsYou:
                    PipiNeedsYouInboxView(store: store, onOpenSession: onOpenConversation)
                case .inspect:
                    liveInspectStage
                case .diffReview:
                    diffReviewStage
                case .triggersEvolution:
                    triggersAndEvolutionStage
                case .marketplace:
                    marketplaceStage
                case .usage:
                    usageLedgerStage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(PipiTokens.bgCanvas)
        .onAppear {
            if initialFocusNeedsYou {
                selectedTab = .needsYou
            }
            if selectedWorktreeId == nil {
                selectedWorktreeId = store.worktreeSessions.first?.id
            }
            if newTriggerPersonaId.isEmpty {
                newTriggerPersonaId = store.personas.first?.id ?? ""
            }
            _ = store.sweepExpiredBoardLeases()
            _ = store.collectDueBoardFollowUps()
        }
        .onChange(of: initialFocusNeedsYou) { _, focus in
            if focus {
                selectedTab = .needsYou
            }
        }
        .sheet(isPresented: $showNewTriggerSheet) {
            newEventTriggerSheet
        }
        .sheet(isPresented: $showNewBoardTaskSheet) {
            newBoardTaskSheet
        }
        .sheet(isPresented: Binding(
            get: { selectedBoardThreadId != nil },
            set: { if !$0 { selectedBoardThreadId = nil } }
        )) {
            if let tid = selectedBoardThreadId,
               let thread = store.boardThreads.first(where: { $0.id == tid }) {
                boardThreadDetailSheet(thread: thread)
            }
        }
    }

    // MARK: - Top Header

    private var filteredBoardThreads: [PipiBoardThread] {
        guard let slug = selectedChannelFilter else { return store.boardThreads }
        return store.boardThreads.filter { $0.channelSlug == slug }
    }

    private var openBoardThreads: [PipiBoardThread] {
        filteredBoardThreads
            .filter { $0.status == .open || $0.status == .blocked }
            .sorted { lhs, rhs in
                if lhs.status != rhs.status { return lhs.status == .open }
                if lhs.priority.sortRank != rhs.priority.sortRank { return lhs.priority.sortRank < rhs.priority.sortRank }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private var claimedBoardThreads: [PipiBoardThread] {
        filteredBoardThreads
            .filter { $0.status == .claimed }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var needsYouBoardThreads: [PipiBoardThread] {
        filteredBoardThreads
            .filter { $0.status == .needsYou }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var doneBoardThreads: [PipiBoardThread] {
        filteredBoardThreads
            .filter { $0.status == .done }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var activeTaskCount: Int {
        store.activeGroupLanes.count + store.activeRuns.count + claimedBoardThreads.count
    }

    private var pendingReviewCount: Int {
        needsYouBoardThreads.count
            + store.worktreeSessions.filter { $0.status == .readyForReview || $0.status == .changesRequested }.count
            + store.blueprintEvolutionProposals.filter { $0.status == .pending }.count
    }

    private var completedTaskCount: Int {
        doneBoardThreads.count + store.runRecords.count + store.worktreeSessions.filter { $0.status == .merged }.count
    }

    private var headerSubtitle: String {
        let openCount = openBoardThreads.count
        if activeTaskCount == 0 && pendingReviewCount == 0 && openCount == 0 {
            return s.t("全部运行平稳 · 今日 $\(String(format: "%.2f", store.usageSummary.todayCostUSD))", "All clear · Today $\(String(format: "%.2f", store.usageSummary.todayCostUSD))")
        }
        return s.t(
            "\(openCount) 待认领 · \(activeTaskCount) 进行中 · \(pendingReviewCount) 待确认 · $\(String(format: "%.2f", store.usageSummary.todayCostUSD))",
            "\(openCount) open · \(activeTaskCount) active · \(pendingReviewCount) review · $\(String(format: "%.2f", store.usageSummary.todayCostUSD))"
        )
    }

    private var topHeaderBar: some View {
        HStack(spacing: PipiTokens.spacing12) {
            PipiSegmentedControl(
                options: MissionTab.allCases,
                selection: $selectedTab
            ) { tab in
                tabLabelWithBadge(tab)
            }

            Spacer(minLength: PipiTokens.spacing12)

            Text(headerSubtitle)
                .font(PipiTokens.fontCaption)
                .foregroundStyle(PipiTokens.textMuted)
                .monospacedDigit()
                .lineLimit(1)

            PipiActionButton(
                s.t("新任务", "New task"),
                systemImage: "plus",
                tone: .primary,
                density: .desktopCompact
            ) {
                newTaskChannel = selectedChannelFilter ?? "inbox"
                newTaskTitle = ""
                newTaskBody = ""
                newTaskPriority = .normal
                newTaskBlockedById = ""
                showNewBoardTaskSheet = true
            }
        }
        .padding(.horizontal, PipiTokens.spacing24)
        .padding(.vertical, 12)
        .background(PipiTokens.bgCanvas)
    }

    private func tabLabelWithBadge(_ tab: MissionTab) -> String {
        let base = tab.title(s)
        switch tab {
        case .needsYou:
            let pending = store.totalNeedsYouCount + store.boardNeedsYouThreads.count
            return pending > 0 ? "\(base) \(pending)" : base
        case .inspect:
            let leases = store.boardThreads.filter { $0.status == .claimed }.count
            return leases > 0 ? "\(base) \(leases)" : base
        case .diffReview:
            let pending = store.worktreeSessions.filter { $0.status == .readyForReview }.count
            return pending > 0 ? "\(base) \(pending)" : base
        case .triggersEvolution:
            let pending = store.blueprintEvolutionProposals.filter { $0.status == .pending }.count
                + store.pendingGateDraftCount()
            return pending > 0 ? "\(base) \(pending)" : base
        case .marketplace:
            return base
        case .usage:
            let alerts = store.unacknowledgedUsageAlerts.count
            return alerts > 0 ? "\(base) \(alerts)" : base
        case .board:
            return base
        }
    }

    private var ownerBoardActor: PipiBoardActorRef {
        PipiBoardActorRef(id: "human:owner", name: s.t("我", "Owner"), kind: .human)
    }

    private var activePersonaBoardActor: PipiBoardActorRef {
        let p = store.activePersona
        return PipiBoardActorRef(id: "bot:\(p.id)", name: p.name(lang), kind: .bot, harness: p.preferredModelId)
    }

    private func priorityLabel(_ priority: PipiBoardTaskPriority) -> String {
        switch priority {
        case .urgent: return s.t("紧急", "Urgent")
        case .high: return s.t("高优", "High")
        case .normal: return s.t("普通", "Normal")
        case .low: return s.t("低优", "Low")
        }
    }

    private func statusLabel(_ status: PipiBoardTaskStatus) -> String {
        switch status {
        case .open: return s.t("待认领", "Open")
        case .claimed: return s.t("已认领", "Claimed")
        case .blocked: return s.t("已阻塞", "Blocked")
        case .needsYou: return s.t("待确认", "Needs you")
        case .done: return s.t("已完成", "Done")
        case .cancelled: return s.t("已取消", "Cancelled")
        }
    }

    private func statusTint(_ status: PipiBoardTaskStatus) -> Color {
        switch status {
        case .open: return PipiTokens.textSecondary
        case .claimed: return PipiTokens.soulPrimary
        case .blocked: return PipiTokens.stateWarning
        case .needsYou: return PipiTokens.stateWarning
        case .done: return PipiTokens.stateSuccess
        case .cancelled: return PipiTokens.textMuted
        }
    }

    private func leaseRemainingText(_ claim: PipiBoardTaskClaim?) -> String {
        guard let claim, let exp = PipiBoardEngine.parseISO(claim.expiresAt) else {
            return s.t("有效租约", "Active lease")
        }
        let secs = Int(exp.timeIntervalSinceNow)
        if secs <= 0 {
            return s.t("租约已过期", "Lease expired")
        }
        let mins = max(1, (secs + 59) / 60)
        return s.t("租约剩余 \(mins)m", "\(mins)m left")
    }

    private func shortTime(_ iso: String) -> String {
        guard let date = PipiBoardEngine.parseISO(iso) else { return iso }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: date)
    }

    // MARK: - Tab 1: Live Board (Channel Filter + 4 Open Columns, Zero Nested Cards)

    private var channelFilterBar: some View {
        HStack(spacing: PipiTokens.spacing8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    channelChip(slug: nil, label: s.t("全部频道", "All channels"), count: store.boardThreads.count)
                    ForEach(store.boardChannels) { ch in
                        let cnt = store.boardThreads.filter { $0.channelSlug == ch.slug }.count
                        channelChip(slug: ch.slug, label: "#\(ch.slug)", count: cnt)
                    }
                }
            }

            Spacer(minLength: PipiTokens.spacing12)

            if openBoardThreads.contains(where: { $0.status == .open }) {
                Button {
                    let res = store.claimNextBoardTask(
                        actor: activePersonaBoardActor,
                        channelSlug: selectedChannelFilter
                    )
                    if res.ok, let th = res.thread {
                        store.noticeBanner = s.t("已由 \(activePersonaBoardActor.name) 认领「\(th.title)」", "\(activePersonaBoardActor.name) claimed \"\(th.title)\"")
                    }
                } label: {
                    Text(s.t("认领下一项", "Claim next"))
                        .font(PipiTokens.fontCaption.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(PipiTokens.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            if !claimedBoardThreads.isEmpty {
                Button {
                    let expired = store.sweepExpiredBoardLeases()
                    let due = store.collectDueBoardFollowUps()
                    store.noticeBanner = s.t(
                        "已巡检租约：释放 \(expired.count) 项过期，触发 \(due.count) 条跟进",
                        "Swept leases: \(expired.count) expired, \(due.count) follow-ups due"
                    )
                } label: {
                    Text(s.t("巡检租约", "Sweep leases"))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(PipiTokens.bgCanvas)
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func channelChip(slug: String?, label: String, count: Int) -> some View {
        let isSelected = (selectedChannelFilter == slug)
        return Button {
            withAnimation(PipiMotion.press) {
                selectedChannelFilter = slug
            }
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(PipiTokens.fontCaption.weight(isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                if count > 0 {
                    Text("\(count)")
                        .font(PipiTokens.fontMonoSmall)
                        .monospacedDigit()
                        .foregroundStyle(PipiTokens.textMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? PipiTokens.bgElevated : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .strokeBorder(isSelected ? PipiTokens.borderSubtle : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var boardStage: some View {
        let pendingWorktrees = store.worktreeSessions.filter { $0.status == .readyForReview || $0.status == .changesRequested }
        let pendingProposals = store.blueprintEvolutionProposals.filter { $0.status == .pending }
        let mergedWorktrees = store.worktreeSessions.filter { $0.status == .merged }

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                channelFilterBar

                HStack(alignment: .top, spacing: PipiTokens.spacing16) {
                    // Column 1: Open & Blocked
                    missionColumn(
                        title: s.t("待认领", "Open"),
                        count: openBoardThreads.count,
                        dotTint: PipiTokens.textSecondary
                    ) {
                        ForEach(openBoardThreads) { thread in
                            let unresolvedCount = PipiBoardEngine.unresolvedBlockers(for: thread.blockedBy, in: store.boardThreads).count
                            let sub = unresolvedCount > 0
                                ? s.t("#\(thread.channelSlug) · 等待 \(unresolvedCount) 项前置任务", "#\(thread.channelSlug) · Waiting on \(unresolvedCount) blocker(s)")
                                : "#\(thread.channelSlug) · \(priorityLabel(thread.priority))"
                            Button {
                                selectedBoardThreadId = thread.id
                            } label: {
                                missionCard(
                                    title: thread.title,
                                    subtitle: sub,
                                    owner: thread.createdBy.name,
                                    badge: statusLabel(thread.status),
                                    badgeTint: statusTint(thread.status),
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        if openBoardThreads.isEmpty {
                            emptyColumnPlaceholder(
                                text: s.t("当前频道暂无待认领任务", "No open tasks in this channel")
                            )
                        }
                    }

                    // Column 2: Claimed + Live Runs
                    missionColumn(
                        title: s.t("进行中", "In progress"),
                        count: activeTaskCount,
                        dotTint: PipiTokens.soulPrimary
                    ) {
                        ForEach(claimedBoardThreads) { thread in
                            let holder = thread.claim?.actor.name ?? activePersonaBoardActor.name
                            let leaseNote = leaseRemainingText(thread.claim)
                            Button {
                                selectedBoardThreadId = thread.id
                            } label: {
                                missionCard(
                                    title: thread.title,
                                    subtitle: "#\(thread.channelSlug) · \(leaseNote)",
                                    owner: holder,
                                    badge: s.t("已认领", "Claimed"),
                                    badgeTint: PipiTokens.soulPrimary,
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(store.activeGroupLanes) { lane in
                            missionCard(
                                title: lane.statusText.isEmpty ? lane.personaName : lane.statusText,
                                subtitle: lane.hostLabel,
                                owner: lane.personaName,
                                badge: s.t("协作中", "Active"),
                                badgeTint: PipiTokens.soulPrimary
                            )
                        }
                        let runningSessions = Array(store.activeRuns.values)
                        ForEach(runningSessions, id: \.runId) { run in
                            let botName = store.personas.first(where: { $0.id == run.personaId })?.name(lang) ?? s.appName
                            missionCard(
                                title: run.statusText.isEmpty ? s.t("正在执行任务…", "Running task…") : run.statusText,
                                subtitle: run.isLocalAgent ? s.t("本机代码代理", "Local agent") : s.t("后台对话任务", "Background run"),
                                owner: botName,
                                badge: s.t("执行中", "Running"),
                                badgeTint: PipiTokens.soulPrimary
                            )
                        }
                        if activeTaskCount == 0 {
                            emptyColumnPlaceholder(
                                text: s.t("暂无进行中的任务", "Nothing running right now")
                            )
                        }
                    }

                    // Column 3: Needs You
                    missionColumn(
                        title: s.t("待你确认", "Needs you"),
                        count: pendingReviewCount,
                        dotTint: PipiTokens.stateWarning
                    ) {
                        ForEach(needsYouBoardThreads) { thread in
                            let lastNote = thread.messages.last?.body ?? "#\(thread.channelSlug)"
                            Button {
                                selectedBoardThreadId = thread.id
                            } label: {
                                missionCard(
                                    title: thread.title,
                                    subtitle: "#\(thread.channelSlug) · \(lastNote)",
                                    owner: thread.messages.last?.author.name ?? thread.createdBy.name,
                                    badge: s.t("待拍板", "Decision"),
                                    badgeTint: PipiTokens.stateWarning,
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(pendingWorktrees) { wt in
                            Button {
                                selectedWorktreeId = wt.id
                                selectedTab = .diffReview
                            } label: {
                                missionCard(
                                    title: wt.taskTitle,
                                    subtitle: wt.diffSummary.isEmpty ? wt.branchName : "\(wt.branchName) · \(wt.diffSummary)",
                                    owner: wt.botName,
                                    badge: wt.status.label(lang),
                                    badgeTint: PipiTokens.stateWarning,
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(pendingProposals) { prop in
                            Button {
                                selectedTab = .triggersEvolution
                            } label: {
                                missionCard(
                                    title: prop.rationale.isEmpty ? s.t("助手配置更新建议", "Suggested assistant update") : prop.rationale,
                                    subtitle: s.t("\(prop.diffs.count) 处待确认改动", "\(prop.diffs.count) changes proposed"),
                                    owner: prop.botName,
                                    badge: s.t("优化建议", "Proposal"),
                                    badgeTint: PipiTokens.stateWarning,
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        if pendingReviewCount == 0 {
                            emptyColumnPlaceholder(
                                text: s.t("所有待办都已确认完毕", "Everything is reviewed")
                            )
                        }
                    }

                    // Column 4: Completed
                    missionColumn(
                        title: s.t("已完成", "Done"),
                        count: completedTaskCount,
                        dotTint: PipiTokens.stateSuccess
                    ) {
                        ForEach(doneBoardThreads.prefix(6)) { thread in
                            let sub = thread.deliverableRef?.isEmpty == false
                                ? "#\(thread.channelSlug) · \(thread.deliverableRef!)"
                                : "#\(thread.channelSlug) · \(shortTime(thread.updatedAt))"
                            Button {
                                selectedBoardThreadId = thread.id
                            } label: {
                                missionCard(
                                    title: thread.title,
                                    subtitle: sub,
                                    owner: thread.messages.last?.author.name ?? thread.createdBy.name,
                                    badge: s.t("已完成", "Done"),
                                    badgeTint: PipiTokens.stateSuccess,
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(store.runRecords.prefix(5)) { rec in
                            Button {
                                onOpenConversation(rec.conversationId)
                            } label: {
                                missionCard(
                                    title: rec.promptPreview.isEmpty ? rec.engineLabel : rec.promptPreview,
                                    subtitle: formatDuration(rec.durationMs),
                                    owner: rec.engineLabel,
                                    badge: rec.status == .succeeded ? s.t("已完成", "Done") : s.t("需关注", "Issue"),
                                    badgeTint: rec.status == .succeeded ? PipiTokens.stateSuccess : PipiTokens.stateError,
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(mergedWorktrees.prefix(3)) { wt in
                            missionCard(
                                title: wt.taskTitle,
                                subtitle: wt.diffSummary.isEmpty ? wt.branchName : "\(wt.branchName) · \(wt.diffSummary)",
                                owner: wt.botName,
                                badge: s.t("已合入", "Merged"),
                                badgeTint: PipiTokens.stateSuccess
                            )
                        }
                        if completedTaskCount == 0 {
                            emptyColumnPlaceholder(
                                text: s.t("完成的任务会汇总在这里", "Completed work appears here")
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: 1180, alignment: .leading)
            .padding(.horizontal, PipiTokens.spacing24)
            .padding(.vertical, PipiTokens.spacing20)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(PipiTokens.bgCanvas)
    }

    // MARK: - Tab 3: Live Inspect (Active Leases, Pending Follow-Ups & Event Stream)

    private var liveInspectStage: some View {
        let activeLeases = store.boardThreads.filter { $0.status == .claimed && $0.claim != nil }
        let pendingFollowUps = store.boardThreads.flatMap { th in
            th.followUps.filter { $0.status == .pending }.map { (th, $0) }
        }
        let recentEvents = Array(store.boardEvents.reversed().prefix(40))

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
                HStack(spacing: PipiTokens.spacing12) {
                    Text(s.t("实时协作状态", "Live coordination"))
                        .font(PipiTokens.fontHeadline)
                        .foregroundStyle(PipiTokens.textPrimary)

                    Text(s.t(
                        "\(activeLeases.count) 个活跃租约 · \(pendingFollowUps.count) 条定时跟进 · \(store.boardEvents.count) 条事件",
                        "\(activeLeases.count) active leases · \(pendingFollowUps.count) follow-ups · \(store.boardEvents.count) events"
                    ))
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textMuted)
                    .monospacedDigit()

                    Spacer()

                    PipiActionButton(
                        s.t("巡检租约与跟进", "Sweep now"),
                        systemImage: "arrow.clockwise",
                        tone: .secondary,
                        density: .desktopCompact
                    ) {
                        let expired = store.sweepExpiredBoardLeases()
                        let due = store.collectDueBoardFollowUps()
                        store.noticeBanner = s.t(
                            "巡检完成：释放 \(expired.count) 项过期租约，触发 \(due.count) 条跟进",
                            "Swept \(expired.count) expired lease(s) and \(due.count) due follow-up(s)"
                        )
                    }
                }

                if !activeLeases.isEmpty {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                        Text(s.t("活跃认领租约", "Active leases"))
                            .font(PipiTokens.fontSubheadline)
                            .foregroundStyle(PipiTokens.textPrimary)

                        VStack(spacing: 0) {
                            ForEach(Array(activeLeases.enumerated()), id: \.element.id) { idx, thread in
                                if idx > 0 {
                                    Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
                                }
                                HStack(spacing: PipiTokens.spacing12) {
                                    Circle()
                                        .fill(PipiTokens.soulPrimary)
                                        .frame(width: 6, height: 6)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(thread.title)
                                            .font(PipiTokens.fontSubheadline)
                                            .foregroundStyle(PipiTokens.textPrimary)
                                            .lineLimit(1)
                                        Text("#\(thread.channelSlug) · \(thread.claim?.actor.name ?? "") · \(leaseRemainingText(thread.claim))")
                                            .font(PipiTokens.fontCaption)
                                            .foregroundStyle(PipiTokens.textSecondary)
                                            .monospacedDigit()
                                    }
                                    Spacer()
                                    if let claim = thread.claim {
                                        Button(s.t("续租 +15m", "Renew")) {
                                            _ = store.renewBoardLease(
                                                threadId: thread.id,
                                                actorId: claim.actor.id,
                                                leaseToken: claim.leaseToken,
                                                leaseSeconds: 900
                                            )
                                        }
                                        .buttonStyle(.borderless)
                                        .font(PipiTokens.fontCaption.weight(.medium))
                                        .foregroundStyle(PipiTokens.soulPrimary)

                                        Button(s.t("完成", "Complete")) {
                                            _ = store.completeBoardTask(
                                                threadId: thread.id,
                                                actor: claim.actor,
                                                summary: s.t("已在实时活动流中确认完成。", "Completed from Live Inspect."),
                                                leaseToken: claim.leaseToken
                                            )
                                        }
                                        .buttonStyle(.borderless)
                                        .font(PipiTokens.fontCaption.weight(.medium))
                                        .foregroundStyle(PipiTokens.stateSuccess)
                                    }
                                }
                                .padding(.horizontal, PipiTokens.spacing12)
                                .padding(.vertical, 10)
                            }
                        }
                        .background(PipiTokens.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusCardDesktop, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusCardDesktop, style: .continuous)
                                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                    }
                }

                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    Text(s.t("实时事件流", "Activity stream"))
                        .font(PipiTokens.fontSubheadline)
                        .foregroundStyle(PipiTokens.textPrimary)

                    if recentEvents.isEmpty {
                        emptyColumnPlaceholder(
                            text: s.t("创建任务、认领、续租或完成任务后，实时事件流会按时间顺序记录在这里。", "Board events (claims, leases, unblocks, follow-ups) appear here live.")
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(recentEvents.enumerated()), id: \.element.id) { idx, ev in
                                if idx > 0 {
                                    Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
                                }
                                Button {
                                    if let tid = ev.threadId,
                                       store.boardThreads.contains(where: { $0.id == tid }) {
                                        selectedBoardThreadId = tid
                                    }
                                } label: {
                                    HStack(spacing: PipiTokens.spacing12) {
                                        Text(shortTime(ev.createdAt))
                                            .font(PipiTokens.fontMonoSmall)
                                            .monospacedDigit()
                                            .foregroundStyle(PipiTokens.textMuted)
                                            .frame(width: 44, alignment: .leading)
                                        Circle()
                                            .fill(eventDotTint(ev.kind))
                                            .frame(width: 6, height: 6)
                                        Text("#\(ev.channelSlug)")
                                            .font(PipiTokens.fontMonoSmall)
                                            .foregroundStyle(PipiTokens.textSecondary)
                                            .frame(width: 72, alignment: .leading)
                                            .lineLimit(1)
                                        Text(ev.summary)
                                            .font(PipiTokens.fontCaption)
                                            .foregroundStyle(PipiTokens.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        if ev.threadId != nil {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(PipiTokens.textMuted)
                                        }
                                    }
                                    .padding(.horizontal, PipiTokens.spacing12)
                                    .padding(.vertical, 9)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(PipiTokens.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusCardDesktop, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusCardDesktop, style: .continuous)
                                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                    }
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, PipiTokens.spacing24)
            .padding(.vertical, PipiTokens.spacing20)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(PipiTokens.bgCanvas)
    }

    private func eventDotTint(_ kind: PipiBoardEventKind) -> Color {
        switch kind {
        case .taskCompleted, .taskUnblocked:
            return PipiTokens.stateSuccess
        case .taskClaimed, .leaseRenewed:
            return PipiTokens.soulPrimary
        case .claimLost, .taskNeedsYou:
            return PipiTokens.stateWarning
        default:
            return PipiTokens.textMuted
        }
    }

    // MARK: - Board Sheets (New Task & Thread Detail)

    private var newBoardTaskSheet: some View {
        let openCandidates = store.boardThreads.filter { $0.status != .done && $0.status != .cancelled }
        return VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            HStack {
                Text(s.t("新建看板任务", "New board task"))
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                Spacer()
                Button {
                    showNewBoardTaskSheet = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PipiTokens.textSecondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: PipiTokens.spacing12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.t("频道", "Channel"))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                    Picker("", selection: $newTaskChannel) {
                        ForEach(store.boardChannels) { ch in
                            Text("#\(ch.slug)").tag(ch.slug)
                        }
                    }
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.t("优先级", "Priority"))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                    Picker("", selection: $newTaskPriority) {
                        Text(s.t("紧急", "Urgent")).tag(PipiBoardTaskPriority.urgent)
                        Text(s.t("高优", "High")).tag(PipiBoardTaskPriority.high)
                        Text(s.t("普通", "Normal")).tag(PipiBoardTaskPriority.normal)
                        Text(s.t("低优", "Low")).tag(PipiBoardTaskPriority.low)
                    }
                    .labelsHidden()
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(s.t("任务标题", "Title"))
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                TextField(s.t("例如：修复云节点 omp 路径并验证 exit=0", "e.g. Fix remote omp entrypoint and verify exit=0"), text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(s.t("背景与验收标准", "Context & acceptance criteria"))
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                TextEditor(text: $newTaskBody)
                    .font(PipiTokens.fontBody)
                    .frame(height: 96)
                    .padding(6)
                    .background(PipiTokens.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                            .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                    )
            }

            if !openCandidates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.t("前置依赖（可选）", "Blocked by (optional)"))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                    Picker("", selection: $newTaskBlockedById) {
                        Text(s.t("无依赖，立即可认领", "No blocker — open immediately")).tag("")
                        ForEach(openCandidates) { th in
                            Text("#\(th.channelSlug) · \(th.title)").tag(th.id)
                        }
                    }
                    .labelsHidden()
                }
            }

            HStack {
                if let onNewTask {
                    Button(s.t("改为发起新对话", "Start chat instead")) {
                        showNewBoardTaskSheet = false
                        onNewTask()
                    }
                    .buttonStyle(.borderless)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                }
                Spacer()
                PipiActionButton(s.t("取消", "Cancel"), tone: .secondary, density: .desktopCompact) {
                    showNewBoardTaskSheet = false
                }
                PipiActionButton(
                    s.t("发布到看板", "Post to board"),
                    tone: .primary,
                    density: .desktopCompact
                ) {
                    let blockers = newTaskBlockedById.isEmpty ? [] : [newTaskBlockedById]
                    let created = store.createBoardThread(
                        channelSlug: newTaskChannel,
                        title: newTaskTitle,
                        body: newTaskBody,
                        kind: .task,
                        priority: newTaskPriority,
                        blockedBy: blockers,
                        author: ownerBoardActor
                    )
                    showNewBoardTaskSheet = false
                    selectedBoardThreadId = created.id
                }
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(PipiTokens.spacing20)
        .frame(width: 500)
        .background(PipiTokens.bgCanvas)
    }

    private func boardThreadDetailSheet(thread: PipiBoardThread) -> some View {
        let unresolvedIds = PipiBoardEngine.unresolvedBlockers(for: thread.blockedBy, in: store.boardThreads)
        return VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            HStack(alignment: .top, spacing: PipiTokens.spacing12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("#\(thread.channelSlug)")
                            .font(PipiTokens.fontMonoSmall)
                            .foregroundStyle(PipiTokens.textSecondary)
                        Circle()
                            .fill(statusTint(thread.status))
                            .frame(width: 6, height: 6)
                        Text(statusLabel(thread.status))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                        Text("·")
                            .foregroundStyle(PipiTokens.textMuted)
                        Text(priorityLabel(thread.priority))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    Text(thread.title)
                        .font(PipiTokens.fontTitle)
                        .foregroundStyle(PipiTokens.textPrimary)
                }
                Spacer()
                Button {
                    selectedBoardThreadId = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PipiTokens.textSecondary)
                }
                .buttonStyle(.plain)
            }

            // Contextual Coordination Action Bar
            HStack(spacing: PipiTokens.spacing8) {
                if thread.status == .open {
                    PipiActionButton(s.t("认领任务", "Claim task"), tone: .primary, density: .desktopCompact) {
                        _ = store.claimBoardTask(threadId: thread.id, actor: activePersonaBoardActor)
                    }
                    PipiActionButton(s.t("直接完成", "Complete"), tone: .secondary, density: .desktopCompact) {
                        _ = store.completeBoardTask(
                            threadId: thread.id,
                            actor: ownerBoardActor,
                            summary: s.t("已由主人确认完成。", "Marked complete by owner."),
                            deliverableRef: threadDeliverableDraft.isEmpty ? nil : threadDeliverableDraft
                        )
                    }
                } else if thread.status == .claimed, let claim = thread.claim {
                    Text("\(claim.actor.name) · \(leaseRemainingText(claim))")
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.soulPrimary)
                        .monospacedDigit()
                    Spacer()
                    PipiActionButton(s.t("续租 +15m", "Renew"), tone: .secondary, density: .desktopCompact) {
                        _ = store.renewBoardLease(threadId: thread.id, actorId: claim.actor.id, leaseToken: claim.leaseToken, leaseSeconds: 900)
                    }
                    PipiActionButton(s.t("释放", "Release"), tone: .secondary, density: .desktopCompact) {
                        _ = store.releaseBoardClaim(threadId: thread.id, actor: ownerBoardActor)
                    }
                    PipiActionButton(s.t("转待确认", "Needs you"), tone: .secondary, density: .desktopCompact) {
                        _ = store.requestBoardNeedsYou(threadId: thread.id, actor: claim.actor, reason: s.t("需要主人进一步拍板确认。", "Waiting for owner review."))
                    }
                    PipiActionButton(s.t("标记完成", "Complete"), tone: .primary, density: .desktopCompact) {
                        _ = store.completeBoardTask(
                            threadId: thread.id,
                            actor: claim.actor,
                            summary: s.t("任务已验收完成。", "Task completed."),
                            deliverableRef: threadDeliverableDraft.isEmpty ? nil : threadDeliverableDraft,
                            leaseToken: claim.leaseToken
                        )
                    }
                } else if thread.status == .needsYou {
                    PipiActionButton(s.t("重新开放", "Reopen"), tone: .secondary, density: .desktopCompact) {
                        _ = store.releaseBoardClaim(threadId: thread.id, actor: ownerBoardActor, reason: s.t("主人已确认，重新放回待认领队列。", "Approved by owner and reopened."))
                    }
                    PipiActionButton(s.t("确认完成", "Complete"), tone: .primary, density: .desktopCompact) {
                        _ = store.completeBoardTask(
                            threadId: thread.id,
                            actor: ownerBoardActor,
                            summary: s.t("主人已确认验收通过。", "Approved and completed by owner.")
                        )
                    }
                }
                Spacer(minLength: 0)
            }

            if !unresolvedIds.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.t("前置阻塞依赖", "Blocked by"))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.stateWarning)
                    ForEach(unresolvedIds, id: \.self) { bid in
                        let blocker = store.boardThreads.first(where: { $0.id == bid })
                        Button {
                            selectedBoardThreadId = bid
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(PipiTokens.stateWarning).frame(width: 5, height: 5)
                                Text(blocker?.title ?? bid)
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Spacer()
                                Text(s.t("查看", "Open"))
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(PipiTokens.textMuted)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(PipiTokens.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                    .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Follow-ups strip
            HStack(spacing: 8) {
                TextField(s.t("定时跟进提醒（如：15 分钟后检查构建）", "Follow-up prompt (e.g. check CI in 15m)"), text: $threadFollowUpDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(PipiTokens.fontCaption)
                PipiActionButton(
                    s.t("+15m 跟进", "+15m Follow-up"),
                    tone: .secondary,
                    density: .desktopCompact
                ) {
                    _ = store.scheduleBoardFollowUp(
                        threadId: thread.id,
                        actor: activePersonaBoardActor,
                        prompt: threadFollowUpDraft,
                        inSeconds: 900
                    )
                    threadFollowUpDraft = ""
                }
                .disabled(threadFollowUpDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !thread.followUps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(thread.followUps.suffix(3)) { fup in
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                                .foregroundStyle(PipiTokens.textMuted)
                            Text("\(shortTime(fup.dueAt)) · \(fup.prompt)")
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text(fup.status == .pending ? s.t("待触发", "Pending") : s.t("已触发", "Triggered"))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                    }
                }
            }

            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

            // Message Timeline
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if thread.messages.isEmpty {
                        Text(s.t("暂无讨论记录。可以在下方直接留言或补充上下文。", "No messages yet. Post context or updates below."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textMuted)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(thread.messages) { msg in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(msg.author.name)
                                        .font(PipiTokens.fontCaption.weight(.medium))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Text(shortTime(msg.createdAt))
                                        .font(PipiTokens.fontMonoSmall)
                                        .monospacedDigit()
                                        .foregroundStyle(PipiTokens.textMuted)
                                    if let ref = msg.artifactRef, !ref.isEmpty {
                                        Text("· \(ref)")
                                            .font(PipiTokens.fontMonoSmall)
                                            .foregroundStyle(PipiTokens.soulPrimary)
                                    }
                                }
                                Text(msg.body)
                                    .font(PipiTokens.fontBody)
                                    .foregroundStyle(PipiTokens.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(PipiTokens.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                    .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                            )
                        }
                    }
                }
            }
            .frame(minHeight: 170, maxHeight: 260)

            // Flat Reply Composer
            HStack(spacing: 8) {
                TextField(s.t("在此任务线程留言…", "Reply to this thread…"), text: $threadReplyDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submitThreadReply(threadId: thread.id)
                    }
                PipiActionButton(
                    s.t("发送", "Post"),
                    tone: .primary,
                    density: .desktopCompact
                ) {
                    submitThreadReply(threadId: thread.id)
                }
                .disabled(threadReplyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(PipiTokens.spacing20)
        .frame(width: 580)
        .background(PipiTokens.bgCanvas)
    }

    private func submitThreadReply(threadId: String) {
        let trimmed = threadReplyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = store.postBoardMessage(threadId: threadId, author: ownerBoardActor, body: trimmed)
        threadReplyDraft = ""
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms <= 0 { return s.t("刚刚", "Just now") }
        if ms < 1000 { return "\(ms) ms" }
        return String(format: "%.1fs", Double(ms) / 1000.0)
    }

    private func missionColumn<Content: View>(
        title: String,
        count: Int,
        dotTint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(dotTint)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(PipiTokens.fontSubheadline.weight(.medium))
                    .foregroundStyle(PipiTokens.textPrimary)
                Text("\(count)")
                    .font(PipiTokens.fontMonoSmall)
                    .monospacedDigit()
                    .foregroundStyle(PipiTokens.textMuted)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)

            VStack(spacing: 10) {
                content()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(PipiTokens.bgSurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func missionCard(
        title: String,
        subtitle: String,
        owner: String,
        badge: String,
        badgeTint: Color,
        showChevron: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(PipiTokens.fontSubheadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                Text(owner)
                    .font(PipiTokens.fontMicro.weight(.regular))
                    .foregroundStyle(PipiTokens.textMuted)
                    .lineLimit(1)

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    Circle()
                        .fill(badgeTint)
                        .frame(width: 5.5, height: 5.5)
                    Text(badge)
                        .font(PipiTokens.fontMicro.weight(.regular))
                        .foregroundStyle(PipiTokens.textSecondary)
                }

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PipiTokens.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .pipiAppleCard(cornerRadius: 12, elevated: true)
    }

    private func emptyColumnPlaceholder(text: String) -> some View {
        Text(text)
            .font(PipiTokens.fontCaption)
            .foregroundStyle(PipiTokens.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
    }

    // MARK: - Tab 2: Git Worktree Diff Review & Send-Back Closure

    private var diffReviewStage: some View {
        HStack(spacing: 0) {
            // Left Worktree Session List
            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                HStack {
                    Text(s.t("隔离 Worktree 会话", "Worktree Sessions"))
                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Spacer()
                    Button {
                        if let bot = store.personas.first(where: { $0.id == "bot_pipi_coder" }) ?? store.personas.first {
                            if let wt = store.prepareWorktreeIfNeeded(
                                repoPath: store.workspaceDirectory,
                                taskTitle: "manual-sandbox",
                                persona: bot,
                                forceCreate: true
                            ) {
                                selectedWorktreeId = wt.id
                            }
                        }
                    } label: {
                        Label(s.t("新建隔离", "New"), systemImage: "plus")
                            .font(PipiTokens.fontCaption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, PipiTokens.spacing12)
                .padding(.top, PipiTokens.spacing12)

                ScrollView {
                    LazyVStack(spacing: PipiTokens.spacing8) {
                        ForEach(store.worktreeSessions) { wt in
                            Button {
                                selectedWorktreeId = wt.id
                                _ = store.refreshWorktreeDiff(sessionId: wt.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(wt.taskTitle)
                                            .font(PipiTokens.fontSubheadline.weight(.medium))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(wt.status.label(lang))
                                            .font(PipiTokens.fontMicro)
                                            .foregroundStyle(worktreeStatusColor(wt.status))
                                    }
                                    Text(wt.branchName)
                                        .font(PipiTokens.fontMonoSmall)
                                        .foregroundStyle(PipiTokens.textSecondary)
                                        .lineLimit(1)
                                    Text(wt.diffSummary)
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(PipiTokens.textMuted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(selectedWorktreeId == wt.id ? PipiTokens.soulPrimary.opacity(0.12) : PipiTokens.bgSurface)
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        if store.worktreeSessions.isEmpty {
                            Text(s.t("当群聊并行写代码或项目开启「始终 Worktree 隔离」时，隔离分支与 Diff 会自动出现在这里。", "Isolated Git Worktrees and Diffs appear here automatically during parallel coding runs."))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textMuted)
                                .padding(PipiTokens.spacing12)
                        }
                    }
                    .padding(.horizontal, PipiTokens.spacing12)
                    .padding(.bottom, PipiTokens.spacing12)
                }
            }
            .frame(width: 280)
            .background(PipiTokens.bgElevated)

            Rectangle().fill(PipiTokens.borderSubtle).frame(width: 1)

            // Right Diff Viewer + Send Back + Merge Controls
            if let wt = store.worktreeSessions.first(where: { $0.id == selectedWorktreeId }) ?? store.worktreeSessions.first {
                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    HStack(spacing: PipiTokens.spacing12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(wt.branchName) → \(wt.baseBranch)")
                                .font(PipiTokens.fontHeadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text("\(wt.botName) · \(wt.worktreePath)")
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            isVerifyingProof = true
                            Task {
                                _ = await store.verifyWorktreeProof(sessionId: wt.id)
                                isVerifyingProof = false
                            }
                        } label: {
                            Label(
                                isVerifyingProof ? s.t("验证中…", "Verifying…") : s.t("生成验证证据包", "Verify Proof"),
                                systemImage: "checkmark.shield.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isVerifyingProof)

                        Button {
                            _ = store.refreshWorktreeDiff(sessionId: wt.id)
                        } label: {
                            Label(s.t("刷新 Diff", "Refresh"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Picker("", selection: $mergeStrategy) {
                            ForEach(PipiWorktreeMergeStrategy.allCases) { st in
                                Text(st.label(lang)).tag(st)
                            }
                        }
                        .frame(width: 170)

                        Button {
                            _ = store.mergeWorktreeSession(sessionId: wt.id, strategy: mergeStrategy)
                        } label: {
                            Label(s.t("合并并清理", "Merge & Clean"), systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(wt.status == .merged || wt.status == .discarded)

                        Button(role: .destructive) {
                            store.discardWorktreeSession(sessionId: wt.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(wt.status == .merged || wt.status == .discarded)
                    }

                    // "Review Proof, Not Code" Verification Bundle Card (Poteto Pyramid + Multi-Model Panel)
                    if let proof = store.proofBundle(for: wt.id) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: proof.overallStatus == .verified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(proof.overallStatus == .verified ? PipiTokens.stateSuccess : (proof.overallStatus == .blocked ? PipiTokens.stateError : PipiTokens.stateWarning))
                                Text(proof.overallStatus.label(lang))
                                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Spacer()
                                Text(proof.evidenceSummary)
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textSecondary)
                            }
                            HStack(spacing: 8) {
                                ForEach(proof.checkResults) { chk in
                                    HStack(spacing: 4) {
                                        Image(systemName: chk.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(chk.passed ? PipiTokens.stateSuccess : PipiTokens.stateError)
                                        Text(chk.name)
                                            .font(PipiTokens.fontMicro)
                                            .foregroundStyle(PipiTokens.textPrimary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(PipiTokens.bgCanvas)
                                    .clipShape(Capsule())
                                }
                            }
                            ForEach(proof.panelVotes) { vote in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("[\(vote.verdict.label(lang))] \(vote.reviewerLabel) (\(vote.modelId)):")
                                        .font(PipiTokens.fontCaption.weight(.semibold))
                                        .foregroundStyle(vote.verdict == .approve ? PipiTokens.stateSuccess : (vote.verdict == .block ? PipiTokens.stateError : PipiTokens.stateWarning))
                                    Text(vote.summary)
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(PipiTokens.textSecondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(PipiTokens.spacing12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PipiTokens.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                    }

                    // Changed files pills
                    if !wt.files.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(wt.files) { f in
                                    HStack(spacing: 4) {
                                        Text(f.status)
                                            .font(PipiTokens.fontMonoSmall.weight(.bold))
                                            .foregroundStyle(PipiTokens.soulPrimary)
                                        Text(f.path)
                                            .font(PipiTokens.fontMonoSmall)
                                            .foregroundStyle(PipiTokens.textPrimary)
                                        Text("+\(f.additions)")
                                            .font(PipiTokens.fontMonoSmall)
                                            .foregroundStyle(PipiTokens.stateSuccess)
                                        Text("-\(f.deletions)")
                                            .font(PipiTokens.fontMonoSmall)
                                            .foregroundStyle(PipiTokens.stateError)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(PipiTokens.bgSurface)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    // Unified Diff Code Pane
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            let lines = (wt.unifiedDiff.isEmpty ? wt.diffSummary : wt.unifiedDiff)
                                .components(separatedBy: .newlines)
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                Text(line.isEmpty ? " " : line)
                                    .font(PipiTokens.fontMonoSmall)
                                    .foregroundStyle(diffLineForeground(line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 1)
                                    .background(diffLineBackground(line))
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .background(PipiTokens.bgSurface)
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                            .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                    )

                    // Send-Back Review Comment Bar
                    HStack(spacing: PipiTokens.spacing8) {
                        TextField(
                            s.t("输入代码审查意见，一键打回给原 Agent 在同一 Worktree 续改…", "Enter review feedback to send back to the Agent in this worktree…"),
                            text: $reviewFeedbackText
                        )
                        .textFieldStyle(.roundedBorder)

                        Button {
                            let fb = reviewFeedbackText
                            reviewFeedbackText = ""
                            Task {
                                await store.sendBackWorktreeFeedback(sessionId: wt.id, feedback: fb)
                            }
                        } label: {
                            Label(s.t("打回续改", "Send Back"), systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(reviewFeedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(PipiTokens.spacing16)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 28))
                        .foregroundStyle(PipiTokens.textMuted)
                    Text(s.t("暂无活跃的 Worktree Diff", "No active Worktree Diffs"))
                        .font(PipiTokens.fontHeadline)
                        .foregroundStyle(PipiTokens.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func worktreeStatusColor(_ status: PipiWorktreeReviewStatus) -> Color {
        switch status {
        case .active: return PipiTokens.soulPrimary
        case .readyForReview: return PipiTokens.stateWarning
        case .changesRequested: return PipiTokens.stateError
        case .merged: return PipiTokens.stateSuccess
        case .discarded: return PipiTokens.textMuted
        }
    }

    private func diffLineForeground(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return PipiTokens.stateSuccess }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return PipiTokens.stateError }
        if line.hasPrefix("@@") { return PipiTokens.soulPrimary }
        return PipiTokens.textPrimary
    }

    private func diffLineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") && !line.hasPrefix("+++") { return PipiTokens.stateSuccess.opacity(0.08) }
        if line.hasPrefix("-") && !line.hasPrefix("---") { return PipiTokens.stateError.opacity(0.08) }
        return Color.clear
    }

    // MARK: - Tab 3: Automation & Assistant Improvements (Unified Tactile C-End Style)

    private var triggersAndEvolutionStage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing24) {
                // Section 1: Daily Automation Templates (2x2 Tactile Card Grid)
                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.t("常用自动化模板", "Automation Templates"))
                            .font(PipiTokens.fontHeadline)
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.t("一键启用常见办公与日常流程，所有外发动作均会先由你确认。", "Enable everyday workflows with one click. External actions always wait for your approval."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: PipiTokens.spacing12), GridItem(.flexible(), spacing: PipiTokens.spacing12)], spacing: PipiTokens.spacing12) {
                        ForEach(PipiOperationalLoopPreset.allCases) { preset in
                            let installed = store.operationalLoops.contains(where: { $0.preset == preset })
                            HStack(spacing: PipiTokens.spacing12) {
                                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                    .fill(PipiTokens.bgSurface)
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Image(systemName: preset.iconName)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(installed ? PipiTokens.stateSuccess : PipiTokens.textPrimary)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.title(lang))
                                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                        .lineLimit(1)
                                    Text(installed ? s.t("已启用 · 运行中", "Active") : s.t("一键启用自动流转", "One-click setup"))
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(installed ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                }
                                Spacer(minLength: 4)
                                PipiActionButton(
                                    installed ? s.t("已启用", "Active") : s.t("启用", "Enable"),
                                    systemImage: installed ? "checkmark" : "plus",
                                    tone: installed ? .ghost : .secondary,
                                    density: .desktopCompact
                                ) {
                                    _ = store.installDayShiftLoop(preset)
                                }
                            }
                            .padding(PipiTokens.spacing12)
                            .pipiTactileCard(cornerRadius: PipiTokens.radiusMD)
                        }
                    }

                    if !store.loopDrafts.isEmpty {
                        VStack(spacing: PipiTokens.spacing8) {
                            ForEach(store.loopDrafts.prefix(6)) { draft in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("\(draft.loopName) · \(draft.inputSummary)")
                                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                        Spacer()
                                        Text(draft.status.label(lang))
                                            .font(PipiTokens.fontMicro.weight(.semibold))
                                            .foregroundStyle(draft.status == .flaggedUndrafted ? PipiTokens.stateError : (draft.status == .pendingGate ? PipiTokens.stateWarning : PipiTokens.stateSuccess))
                                    }
                                    if let esc = draft.escalationReason {
                                        Text(esc)
                                            .font(PipiTokens.fontCaption)
                                            .foregroundStyle(PipiTokens.stateError)
                                    } else {
                                        Text(draft.draftContent)
                                            .font(PipiTokens.fontCaption)
                                            .foregroundStyle(PipiTokens.textSecondary)
                                            .lineLimit(4)
                                    }
                                    if draft.status == .pendingGate {
                                        HStack(spacing: 8) {
                                            TextField(s.t("如需调整风格，输入一条偏好说明…", "Add a preference note if needed…"), text: $draftRuleNote)
                                                .textFieldStyle(.roundedBorder)
                                            PipiActionButton(s.t("批准发送", "Approve"), tone: .primary, density: .desktopCompact) {
                                                store.approveLoopDraft(id: draft.id)
                                            }
                                            PipiActionButton(s.t("记住偏好并发出", "Save Rule & Send"), tone: .secondary, density: .desktopCompact) {
                                                let note = draftRuleNote
                                                draftRuleNote = ""
                                                store.editLoopDraftAndAddRule(id: draft.id, editedDraft: draft.draftContent, newRuleNote: note)
                                            }
                                        }
                                    }
                                }
                                .padding(PipiTokens.spacing16)
                                .pipiTactileCard(cornerRadius: PipiTokens.radiusMD)
                            }
                        }
                    }

                    let openGaps = store.knowledgeGaps.filter { $0.status == .open }
                    if !openGaps.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(s.t("待补充的知识条目（\(openGaps.count)）", "Knowledge to Fill In (\(openGaps.count))"))
                                .font(PipiTokens.fontSubheadline.weight(.semibold))
                                .foregroundStyle(PipiTokens.textPrimary)
                            ForEach(openGaps.prefix(5)) { gap in
                                HStack {
                                    Text("×\(gap.occurrenceCount) \(gap.question)")
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Spacer()
                                    PipiActionButton(s.t("标记已补齐", "Mark Done"), tone: .secondary, density: .desktopCompact) {
                                        store.resolveKnowledgeGap(id: gap.id, docPath: "docs/")
                                    }
                                }
                            }
                        }
                        .padding(PipiTokens.spacing16)
                        .pipiTactileCard(cornerRadius: PipiTokens.radiusMD)
                    }
                }

                // Section 2: Scheduled & Event Rules
                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.t("定时与触发规则", "Scheduled & Trigger Rules"))
                                .font(PipiTokens.fontHeadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text(s.t("按时间、文件变动或消息关键词自动唤醒助手执行任务。", "Automatically wake an assistant on schedule, folder changes, or message rules."))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                        }
                        Spacer()
                        PipiActionButton(
                            s.t("新建规则", "New Rule"),
                            systemImage: "plus",
                            tone: .primary,
                            density: .desktopCompact
                        ) {
                            showNewTriggerSheet = true
                        }
                    }

                    if store.routines.isEmpty {
                        HStack(spacing: PipiTokens.spacing12) {
                            Image(systemName: "clock.badge.checkmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(PipiTokens.textMuted)
                            Text(s.t("暂无定时或自动触发规则，点击右上角「新建规则」即可创建每日汇总、定时提醒等任务。", "No rules yet. Click New Rule to create daily briefs or scheduled checks."))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                            Spacer()
                        }
                        .padding(PipiTokens.spacing16)
                        .pipiTactileCard(cornerRadius: PipiTokens.radiusMD)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(store.routines.enumerated()), id: \.element.id) { idx, rt in
                                if idx > 0 {
                                    Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
                                }
                                HStack(spacing: PipiTokens.spacing12) {
                                    Image(systemName: rt.triggerKind.iconName)
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rt.title.isEmpty ? rt.prompt : rt.title)
                                            .font(PipiTokens.fontSubheadline.weight(.medium))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                        Text("\(rt.triggerKind.label(lang)) · \(rt.scheduleBadge(lang))")
                                            .font(PipiTokens.fontCaption)
                                            .foregroundStyle(PipiTokens.textSecondary)
                                    }
                                    Spacer()
                                    if rt.triggerKind == .webhook {
                                        PipiActionButton(s.t("复制地址", "Copy URL"), tone: .ghost, density: .desktopCompact) {
                                            #if os(macOS)
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(store.webhookURLString(for: rt), forType: .string)
                                            #endif
                                            store.noticeBanner = s.t("已复制触发地址", "Copied trigger URL")
                                        }
                                    }
                                    PipiActionButton(s.t("立即运行", "Run"), tone: .secondary, density: .desktopCompact) {
                                        Task { await store.runRoutineNow(rt) }
                                    }
                                    Toggle("", isOn: Binding(
                                        get: { rt.isEnabled },
                                        set: { store.toggleRoutine(id: rt.id, enabled: $0) }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                        }
                        .pipiTactileCard(cornerRadius: PipiTokens.radiusMD)
                    }

                    if !store.routineRunLogs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.t("最近运行记录", "Recent Runs"))
                                .font(PipiTokens.fontCaption.weight(.semibold))
                                .foregroundStyle(PipiTokens.textSecondary)
                            VStack(spacing: 0) {
                                ForEach(Array(store.routineRunLogs.prefix(8).enumerated()), id: \.element.id) { idx, log in
                                    if idx > 0 {
                                        Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
                                    }
                                    HStack {
                                        Text(log.routineTitle)
                                            .font(PipiTokens.fontCaption.weight(.medium))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                        Text("· \(log.triggerSummary)")
                                            .font(PipiTokens.fontCaption)
                                            .foregroundStyle(PipiTokens.textSecondary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(log.durationMs)ms")
                                            .font(PipiTokens.fontMonoSmall)
                                            .foregroundStyle(PipiTokens.textMuted)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                }
                            }
                            .pipiTactileCard(cornerRadius: PipiTokens.radiusMD)
                        }
                    }
                }

                // Section 3: Assistant Improvement Suggestions
                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.t("助手优化建议", "Assistant Improvement Suggestions"))
                            .font(PipiTokens.fontHeadline)
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.t("当你多次纠正助手后，系统会整理改进建议推送到这里，经你确认后生效。", "When you correct an assistant, suggested workflow improvements appear here for your approval."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }

                    if store.blueprintEvolutionProposals.isEmpty {
                        HStack(spacing: PipiTokens.spacing12) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(PipiTokens.textMuted)
                            Text(s.t("当前没有待确认的优化建议，助手运行状态良好。", "No pending suggestions right now."))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                            Spacer()
                        }
                        .padding(PipiTokens.spacing16)
                        .pipiTactileCard(cornerRadius: PipiTokens.radiusMD)
                    } else {
                        ForEach(store.blueprintEvolutionProposals) { prop in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("\(prop.botName) · \(prop.goalSummary)")
                                        .font(PipiTokens.fontSubheadline)
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Spacer()
                                    Text(prop.status.rawValue.capitalized)
                                        .font(PipiTokens.fontMicro)
                                        .foregroundStyle(prop.status == .pending ? PipiTokens.stateWarning : PipiTokens.stateSuccess)
                                }
                                Text(prop.rationale)
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textSecondary)

                                ForEach(prop.diffs) { diff in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(diff.title)
                                            .font(PipiTokens.fontCaption.weight(.semibold))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                        if let before = diff.previousValue, !before.isEmpty {
                                            Text("- \(before)")
                                                .font(PipiTokens.fontMonoSmall)
                                                .foregroundStyle(PipiTokens.stateError)
                                        }
                                        Text("+ \(diff.proposedValue)")
                                            .font(PipiTokens.fontMonoSmall)
                                            .foregroundStyle(PipiTokens.stateSuccess)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(PipiTokens.bgSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                                }

                                HStack(spacing: 8) {
                                    if prop.status == .pending {
                                        PipiActionButton(s.t("批准生效", "Approve"), tone: .primary, density: .desktopCompact) {
                                            store.approveBlueprintEvolutionProposal(id: prop.id)
                                        }
                                        PipiActionButton(s.t("忽略", "Dismiss"), tone: .secondary, density: .desktopCompact) {
                                            store.rejectBlueprintEvolutionProposal(id: prop.id)
                                        }
                                    } else if prop.status == .approved {
                                        PipiActionButton(s.t("恢复上一版", "Rollback"), tone: .secondary, density: .desktopCompact) {
                                            store.rollbackBlueprintEvolutionProposal(id: prop.id)
                                        }
                                    }
                                }
                            }
                            .padding(PipiTokens.spacing16)
                            .pipiTactileCard(cornerRadius: PipiTokens.radiusMD)
                        }
                    }
                }
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.horizontal, PipiTokens.spacing24)
            .padding(.vertical, PipiTokens.spacing20)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(PipiTokens.bgCanvas)
    }

    // MARK: - Tab 4: Clean-Room MIT Bot Persona & Lean Skill Marketplace

    private var marketplaceStage: some View {
        let bots = PipiBotMarketplaceCatalog.curatedBots.filter {
            marketplaceFilter == nil || $0.category == marketplaceFilter
        }
        let skills = PipiBotMarketplaceCatalog.curatedSkills.filter {
            marketplaceFilter == nil || $0.category == marketplaceFilter
        }
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
                // Category filter pills (consistent with Knowledge Hub monochrome capsule pills)
                HStack(spacing: 8) {
                    let isAll = marketplaceFilter == nil
                    Button {
                        marketplaceFilter = nil
                    } label: {
                        Text(s.t("全部", "All"))
                            .font(PipiTokens.fontCaption.weight(isAll ? .semibold : .medium))
                            .foregroundStyle(isAll ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isAll ? PipiTokens.bgElevated : PipiTokens.bgSurface, in: Capsule())
                            .overlay(Capsule().strokeBorder(isAll ? PipiTokens.borderStrong : PipiTokens.borderSubtle, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    ForEach(PipiMarketplaceCategory.allCases) { cat in
                        let selected = marketplaceFilter == cat
                        Button {
                            marketplaceFilter = cat
                        } label: {
                            Text(cat.label(lang))
                                .font(PipiTokens.fontCaption.weight(selected ? .semibold : .medium))
                                .foregroundStyle(selected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selected ? PipiTokens.bgElevated : PipiTokens.bgSurface, in: Capsule())
                                .overlay(Capsule().strokeBorder(selected ? PipiTokens.borderStrong : PipiTokens.borderSubtle, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }

                Text(s.t("精选助手模板", "Featured Assistants"))
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: PipiTokens.spacing12)], spacing: PipiTokens.spacing12) {
                    ForEach(bots) { item in
                        let installed = store.personas.contains(where: { $0.id == item.id })
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(item.name(lang))
                                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Spacer()
                                Text("\(item.recommendedSkills.count) \(s.t("项技能", "skills"))")
                                    .font(PipiTokens.fontMicro.weight(.medium))
                                    .foregroundStyle(PipiTokens.textSecondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(PipiTokens.bgSurface, in: Capsule())
                            }
                            Text(item.tagline(lang))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                                .lineLimit(2)
                            HStack {
                                Spacer()
                                PipiActionButton(
                                    installed ? s.t("已安装", "Installed") : s.t("一键安装", "Install"),
                                    systemImage: installed ? "checkmark" : "plus",
                                    tone: installed ? .ghost : .primary,
                                    density: .desktopCompact
                                ) {
                                    guard !installed else { return }
                                    _ = store.installMarketplaceBot(item)
                                }
                            }
                        }
                        .padding(PipiTokens.spacing16)
                        .pipiTactileCard(cornerRadius: PipiTokens.radiusMD)
                    }
                }

                Text(s.t("精选实用技能", "Featured Skills"))
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: PipiTokens.spacing12)], spacing: PipiTokens.spacing12) {
                    ForEach(skills) { sk in
                        let installed = store.ecosystemManager.installedSkills.contains(where: { $0.id == sk.id })
                        VStack(alignment: .leading, spacing: 8) {
                            Text(sk.name(lang))
                                .font(PipiTokens.fontSubheadline.weight(.semibold))
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text(sk.summary(lang))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                                .lineLimit(2)
                            HStack {
                                Spacer()
                                PipiActionButton(
                                    installed ? s.t("已安装", "Installed") : s.t("安装技能", "Install"),
                                    systemImage: installed ? "checkmark" : "plus",
                                    tone: installed ? .ghost : .secondary,
                                    density: .desktopCompact
                                ) {
                                    guard !installed else { return }
                                    _ = store.installMarketplaceSkill(sk)
                                }
                            }
                        }
                        .padding(PipiTokens.spacing16)
                        .pipiTactileCard(cornerRadius: PipiTokens.radiusMD)
                    }
                }
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .padding(.horizontal, PipiTokens.spacing24)
            .padding(.vertical, PipiTokens.spacing20)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(PipiTokens.bgCanvas)
    }

    // MARK: - Tab 5: Usage Metering (Alert-Only, Non-Blocking)

    private var usageLedgerStage: some View {
        let summary = store.usageSummary
        return ScrollView {
            VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(PipiTokens.soulPrimary)
                    Text(s.t("用量策略：仅统计 Token/估算费用并在超阈值时推送温和提醒，绝不中断或阻断你的自主任务。", "Metering policy: Tracks tokens & estimated spend with gentle alerts only — never blocks or pauses autonomous runs."))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                }
                .padding(PipiTokens.spacing12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PipiTokens.soulPrimary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))

                // Active gentle alerts
                ForEach(store.unacknowledgedUsageAlerts) { alert in
                    HStack {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(PipiTokens.stateWarning)
                        Text(alert.message(lang))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textPrimary)
                        Spacer()
                        Button(s.t("知道了", "Dismiss")) {
                            store.acknowledgeUsageAlert(id: alert.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(PipiTokens.stateWarning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                }

                HStack(spacing: PipiTokens.spacing12) {
                    kpiCard(title: s.t("今日 Token", "Today Tokens"), value: "\(summary.todayTokens)", tint: PipiTokens.soulPrimary, icon: "number")
                    kpiCard(title: s.t("今日估算费用", "Today Est. USD"), value: "$\(String(format: "%.3f", summary.todayCostUSD))", tint: PipiTokens.stateWarning, icon: "dollarsign.circle")
                    kpiCard(title: s.t("7 日 Token", "7-Day Tokens"), value: "\(summary.sevenDayTokens)", tint: PipiTokens.textPrimary, icon: "calendar")
                    kpiCard(title: s.t("7 日估算费用", "7-Day Est. USD"), value: "$\(String(format: "%.3f", summary.sevenDayCostUSD))", tint: PipiTokens.stateSuccess, icon: "chart.line.uptrend.xyaxis")
                }

                // Alert thresholds
                VStack(alignment: .leading, spacing: 8) {
                    Text(s.t("温和提醒阈值（仅通知不拦截）", "Gentle Alert Thresholds (Alert-Only)"))
                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                    HStack(spacing: PipiTokens.spacing16) {
                        Toggle(s.t("启用超额提醒", "Enable Alerts"), isOn: $store.usageAlertConfig.enableAlerts)
                        HStack(spacing: 6) {
                            Text(s.t("每日提醒 ($)", "Daily ($)"))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                            TextField("5.0", value: $store.usageAlertConfig.dailyCostAlertUSD, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 72)
                        }
                        HStack(spacing: 6) {
                            Text(s.t("单任务提醒 ($)", "Per-Task ($)"))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                            TextField("1.0", value: $store.usageAlertConfig.perTaskCostAlertUSD, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 72)
                        }
                    }
                }
                .padding(PipiTokens.spacing12)
                .background(PipiTokens.bgSurface)
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))

                // Per-Bot Breakdown
                VStack(alignment: .leading, spacing: 8) {
                    Text(s.t("按智能体统计（近 7 日）", "Breakdown by Bot (7 Days)"))
                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                    if summary.byBot.isEmpty {
                        Text(s.t("开始对话或运行 Routine 后会自动记录真实与估算 Token 用量。", "Token usage and estimated spend will appear automatically after runs."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textMuted)
                    } else {
                        ForEach(summary.byBot) { item in
                            HStack {
                                Text(item.botName)
                                    .font(PipiTokens.fontSubheadline.weight(.medium))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Spacer()
                                Text("\(item.runCount) runs")
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textMuted)
                                Text("\(item.totalTokens) tok")
                                    .font(PipiTokens.fontMonoSmall)
                                    .foregroundStyle(PipiTokens.textSecondary)
                                Text("$\(String(format: "%.3f", item.estimatedCostUSD))")
                                    .font(PipiTokens.fontMonoSmall.weight(.semibold))
                                    .foregroundStyle(PipiTokens.soulPrimary)
                                    .frame(width: 72, alignment: .trailing)
                            }
                            .padding(10)
                            .background(PipiTokens.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
            .padding(PipiTokens.spacing16)
        }
    }

    private func kpiCard(title: String, value: String, tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(title)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
            }
            Text(value)
                .font(PipiTokens.fontTitle)
                .foregroundStyle(PipiTokens.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PipiTokens.spacing12)
        .background(PipiTokens.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous)
                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - New Event Trigger Sheet

    private var newEventTriggerSheet: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            Text(s.t("新建事件驱动 Routine", "New Event-Driven Routine"))
                .font(PipiTokens.fontHeadline)
                .foregroundStyle(PipiTokens.textPrimary)

            Picker(s.t("执行助手", "Bot"), selection: $newTriggerPersonaId) {
                ForEach(store.personas) { bot in
                    Text(bot.name(lang)).tag(bot.id)
                }
            }

            Picker(s.t("触发类型", "Trigger Kind"), selection: $newTriggerKind) {
                ForEach(PipiRoutineTriggerKind.allCases) { kind in
                    Text(kind.label(lang)).tag(kind)
                }
            }

            TextField(s.t("任务标题（例如：GitHub PR Webhook 自动巡检）", "Routine title"), text: $newTriggerTitle)
                .textFieldStyle(.roundedBorder)

            TextField(triggerValuePlaceholder, text: $newTriggerValue)
                .textFieldStyle(.roundedBorder)

            TextField(s.t("触发后让 Bot 执行什么指令？", "Prompt to run when triggered"), text: $newTriggerPrompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            HStack {
                Spacer()
                Button(s.t("取消", "Cancel")) {
                    showNewTriggerSheet = false
                }
                Button(s.t("创建触发器", "Create Trigger")) {
                    var cfg = PipiRoutineEventConfig()
                    switch newTriggerKind {
                    case .schedule:
                        cfg.cronExpression = newTriggerValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    case .webhook:
                        cfg.webhookSecret = newTriggerValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                            ?? "whsec_\(UUID().uuidString.prefix(12).lowercased())"
                    case .fileOrGitWatch:
                        cfg.watchPath = newTriggerValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? store.workspaceDirectory
                        cfg.watchGitEvents = true
                    case .channelMessage:
                        cfg.messageKeyword = newTriggerValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "巡检"
                        cfg.channelFilter = "any"
                    case .hostHealth:
                        cfg.healthMetric = .cpuPercent
                        cfg.healthThreshold = Double(newTriggerValue) ?? 85
                    }
                    let rt = PipiBotRoutine(
                        personaId: newTriggerPersonaId.isEmpty ? (store.personas.first?.id ?? "") : newTriggerPersonaId,
                        title: newTriggerTitle.isEmpty ? newTriggerKind.label(lang) : newTriggerTitle,
                        prompt: newTriggerPrompt.isEmpty ? "Check the triggered event and summarize findings." : newTriggerPrompt,
                        schedule: .daily,
                        triggerKind: newTriggerKind,
                        eventConfig: cfg,
                        isEnabled: true
                    )
                    store.addRoutine(rt)
                    newTriggerTitle = ""
                    newTriggerPrompt = ""
                    newTriggerValue = ""
                    showNewTriggerSheet = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(PipiTokens.spacing16)
        .frame(width: 460)
    }

    private var triggerValuePlaceholder: String {
        switch newTriggerKind {
        case .schedule: return s.t("5 段 Cron 表达式（例：30 9 * * 1-5，留空则每日 09:00）", "5-field Cron (e.g. 30 9 * * 1-5)")
        case .webhook: return s.t("Webhook Secret（留空自动生成 HMAC 密钥）", "Webhook Secret (leave blank to auto-generate)")
        case .fileOrGitWatch: return s.t("监听目录或 Git 仓库路径（留空默认当前工作区）", "Directory or Git repo path")
        case .channelMessage: return s.t("微信/群聊关键词或 /正则/（例：上线、/报警|故障/）", "Keyword or /regex/")
        case .hostHealth: return s.t("CPU 阈值百分比（默认 85）", "CPU threshold % (default 85)")
        }
    }
}
