import SwiftUI
import PipiBotKit
#if os(macOS)
import AppKit
import CoreImage.CIFilterBuiltins
#endif

public struct PipiMissionBoardView: View {
    @Bindable public var store: PipiAppStore
    public var onOpenArchitect: () -> Void
    public var onOpenConversation: (String) -> Void

    private enum MissionTab: String, CaseIterable, Identifiable {
        case board
        case diffReview
        case triggersEvolution
        case marketplace
        case usage

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .board: return "rectangle.3.group"
            case .diffReview: return "checkmark.shield"
            case .triggersEvolution: return "bolt.badge.automatic"
            case .marketplace: return "square.grid.2x2"
            case .usage: return "chart.bar.xaxis"
            }
        }

        func title(_ s: PipiStrings) -> String {
            switch self {
            case .board: return s.t("看板", "Board")
            case .diffReview: return s.t("变更审查", "Review")
            case .triggersEvolution: return s.t("自动化", "Automation")
            case .marketplace: return s.t("市场", "Market")
            case .usage: return s.t("用量", "Usage")
            }
        }
    }

    @State private var selectedTab: MissionTab = .board
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
        onOpenArchitect: @escaping () -> Void = {},
        onOpenConversation: @escaping (String) -> Void = { _ in }
    ) {
        self.store = store
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
            if selectedWorktreeId == nil {
                selectedWorktreeId = store.worktreeSessions.first?.id
            }
            if newTriggerPersonaId.isEmpty {
                newTriggerPersonaId = store.personas.first?.id ?? ""
            }
        }
        .sheet(isPresented: $showNewTriggerSheet) {
            newEventTriggerSheet
        }
    }

    // MARK: - Top Header

    private var activeTaskCount: Int {
        store.activeGroupLanes.count + store.activeRuns.count
    }

    private var pendingReviewCount: Int {
        store.worktreeSessions.filter { $0.status == .readyForReview || $0.status == .changesRequested }.count
            + store.blueprintEvolutionProposals.filter { $0.status == .pending }.count
    }

    private var completedTaskCount: Int {
        store.runRecords.count + store.worktreeSessions.filter { $0.status == .merged }.count
    }

    private var headerSubtitle: String {
        if activeTaskCount == 0 && pendingReviewCount == 0 {
            return s.t("全部运行平稳 · 今日 $\(String(format: "%.2f", store.usageSummary.todayCostUSD))", "All clear · Today $\(String(format: "%.2f", store.usageSummary.todayCostUSD))")
        }
        return s.t(
            "\(activeTaskCount) 项进行中 · \(pendingReviewCount) 项待确认 · 今日 $\(String(format: "%.2f", store.usageSummary.todayCostUSD))",
            "\(activeTaskCount) active · \(pendingReviewCount) to review · $\(String(format: "%.2f", store.usageSummary.todayCostUSD))"
        )
    }

    private var topHeaderBar: some View {
        HStack(spacing: PipiTokens.spacing16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.t("任务台", "Mission Board"))
                    .font(PipiTokens.fontTitle)
                    .tracking(PipiTokens.trackingTitle)
                    .foregroundStyle(PipiTokens.textPrimary)

                Text(headerSubtitle)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
            }

            Spacer(minLength: PipiTokens.spacing12)

            PipiSegmentedControl(
                options: MissionTab.allCases,
                selection: $selectedTab
            ) { tab in
                tabLabelWithBadge(tab)
            }

            PipiActionButton(
                s.t("设计新助手", "New Bot"),
                systemImage: "sparkles",
                tone: .primary,
                density: .desktopCompact
            ) {
                onOpenArchitect()
            }
        }
        .padding(.horizontal, PipiTokens.spacing24)
        .padding(.vertical, PipiTokens.spacing16)
        .background(PipiTokens.bgCanvas)
    }

    private func tabLabelWithBadge(_ tab: MissionTab) -> String {
        let base = tab.title(s)
        switch tab {
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

    // MARK: - Tab 1: Redesigned Mission Board

    private var boardStage: some View {
        let pendingWorktrees = store.worktreeSessions.filter { $0.status == .readyForReview || $0.status == .changesRequested }
        let pendingProposals = store.blueprintEvolutionProposals.filter { $0.status == .pending }
        let mergedWorktrees = store.worktreeSessions.filter { $0.status == .merged }

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
                // Sleek unified status strip (replaces bulky hollow KPI boxes)
                boardMetricsStrip

                // Clean 3-column Apple / Linear Kanban
                HStack(alignment: .top, spacing: PipiTokens.spacing16) {
                    missionColumn(
                        title: s.t("进行中", "In Progress"),
                        count: activeTaskCount,
                        dotTint: PipiTokens.soulPrimary
                    ) {
                        ForEach(store.activeGroupLanes) { lane in
                            missionCard(
                                title: lane.statusText.isEmpty ? lane.personaName : lane.statusText,
                                subtitle: lane.hostLabel,
                                owner: lane.personaName,
                                badge: s.t("协作中", "Active"),
                                badgeTint: PipiTokens.soulPrimary,
                                icon: "bolt.fill"
                            )
                        }
                        let runningSessions = Array(store.activeRuns.values)
                        ForEach(runningSessions, id: \.runId) { run in
                            let botName = store.personas.first(where: { $0.id == run.personaId })?.name(lang) ?? s.appName
                            missionCard(
                                title: run.statusText.isEmpty ? s.t("正在执行任务…", "Running task…") : run.statusText,
                                subtitle: run.isLocalAgent ? s.t("本机代码代理", "Local Agent") : s.t("后台对话任务", "Background Run"),
                                owner: botName,
                                badge: s.t("执行中", "Running"),
                                badgeTint: PipiTokens.soulPrimary,
                                icon: "sparkles"
                            )
                        }
                        if activeTaskCount == 0 {
                            emptyColumnPlaceholder(
                                icon: "circle.dotted",
                                text: s.t("暂无进行中的任务", "Nothing running right now")
                            )
                        }
                    }

                    missionColumn(
                        title: s.t("待你确认", "Needs Review"),
                        count: pendingReviewCount,
                        dotTint: PipiTokens.stateWarning
                    ) {
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
                                    icon: "arrow.triangle.branch",
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
                                    badgeTint: PipiTokens.stateSuccess,
                                    icon: "wand.and.stars",
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        if pendingWorktrees.isEmpty && pendingProposals.isEmpty {
                            emptyColumnPlaceholder(
                                icon: "checkmark.circle",
                                text: s.t("所有待办都已确认完毕", "Everything is reviewed")
                            )
                        }
                    }

                    missionColumn(
                        title: s.t("已完成", "Completed"),
                        count: completedTaskCount,
                        dotTint: PipiTokens.stateSuccess
                    ) {
                        ForEach(store.runRecords.prefix(6)) { rec in
                            Button {
                                onOpenConversation(rec.conversationId)
                            } label: {
                                missionCard(
                                    title: rec.promptPreview.isEmpty ? rec.engineLabel : rec.promptPreview,
                                    subtitle: formatDuration(rec.durationMs),
                                    owner: rec.engineLabel,
                                    badge: rec.status == .succeeded ? s.t("已完成", "Done") : s.t("需关注", "Issue"),
                                    badgeTint: rec.status == .succeeded ? PipiTokens.stateSuccess : PipiTokens.stateError,
                                    icon: rec.status == .succeeded ? "checkmark" : "exclamationmark.triangle",
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(mergedWorktrees.prefix(4)) { wt in
                            missionCard(
                                title: wt.taskTitle,
                                subtitle: wt.diffSummary.isEmpty ? wt.branchName : wt.diffSummary,
                                owner: wt.botName,
                                badge: s.t("已合入", "Merged"),
                                badgeTint: PipiTokens.stateSuccess,
                                icon: "checkmark.seal"
                            )
                        }
                        if store.runRecords.isEmpty && mergedWorktrees.isEmpty {
                            emptyColumnPlaceholder(
                                icon: "tray",
                                text: s.t("完成的任务会汇总在这里", "Completed work appears here")
                            )
                        }
                    }
                }

                // Clean Apple-Settings-style Utility Dock (Mobile Pairing + Security & Health)
                HStack(alignment: .top, spacing: PipiTokens.spacing16) {
                    universalRemotePairingCard
                    sentinelAndSandboxCard
                }
            }
            .padding(.horizontal, PipiTokens.spacing24)
            .padding(.vertical, PipiTokens.spacing20)
        }
        .background(PipiTokens.bgCanvas)
    }

    private var boardMetricsStrip: some View {
        HStack(spacing: 0) {
            compactMetricItem(
                label: s.t("进行中", "In Progress"),
                value: "\(activeTaskCount)",
                dotTint: PipiTokens.soulPrimary
            )
            metricDivider
            compactMetricItem(
                label: s.t("待确认", "Needs Review"),
                value: "\(pendingReviewCount)",
                dotTint: PipiTokens.stateWarning
            )
            metricDivider
            compactMetricItem(
                label: s.t("已完成", "Completed"),
                value: "\(completedTaskCount)",
                dotTint: PipiTokens.stateSuccess
            )
            metricDivider
            compactMetricItem(
                label: s.t("今日估算", "Today"),
                value: "$\(String(format: "%.2f", store.usageSummary.todayCostUSD))",
                dotTint: PipiTokens.textMuted
            )
        }
        .padding(.vertical, 12)
        .background(PipiTokens.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous)
                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
        )
    }

    private func compactMetricItem(label: String, value: String, dotTint: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotTint)
                .frame(width: 7, height: 7)
            Text(label)
                .font(PipiTokens.fontCaption)
                .foregroundStyle(PipiTokens.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(PipiTokens.fontHeadline.monospacedDigit())
                .foregroundStyle(PipiTokens.textPrimary)
        }
        .padding(.horizontal, PipiTokens.spacing16)
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(PipiTokens.borderSubtle)
            .frame(width: 1, height: 22)
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms <= 0 { return s.t("刚刚", "Just now") }
        if ms < 1000 { return "\(ms) ms" }
        return String(format: "%.1fs", Double(ms) / 1000.0)
    }

    private var universalRemotePairingCard: some View {
        let relayState = store.e2eeRelayClient.state
        let isConnected = (relayState == .connected)
        let hasPairingLink = store.lastUniversalPairingURL != nil
        let devices = store.listPairedDevices().filter { !$0.revoked }

        return VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            HStack(spacing: 8) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(PipiTokens.fontSubheadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                Text(s.t("手机端连接", "Mobile Pairing"))
                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(isConnected ? PipiTokens.stateSuccess : (hasPairingLink ? PipiTokens.soulPrimary : PipiTokens.textMuted))
                        .frame(width: 6, height: 6)
                    Text(
                        isConnected
                            ? s.t("已在线", "Online")
                            : (hasPairingLink ? s.t("待扫码", "Ready") : s.t("未开启", "Off"))
                    )
                    .font(PipiTokens.fontMicro.weight(.medium))
                    .foregroundStyle(isConnected ? PipiTokens.stateSuccess : PipiTokens.textSecondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(PipiTokens.bgSurface)
                .clipShape(Capsule())
            }

            HStack(alignment: .center, spacing: PipiTokens.spacing16) {
                if let urlStr = store.lastUniversalPairingURL {
                    #if os(macOS)
                    if let qrImage = generateQRImage(from: urlStr) {
                        Image(nsImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 84, height: 84)
                            .padding(8)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                    .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                            )
                    }
                    #endif
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(s.t("手机扫码即可连接这台电脑，对话与审批全程端到端加密。", "Scan from your phone to connect with end-to-end encryption."))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if store.lastUniversalPairingURL != nil {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.stateSuccess)
                            Text("pipibot.jimizhou.com")
                                .font(PipiTokens.fontMonoSmall)
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text("·")
                                .foregroundStyle(PipiTokens.textMuted)
                            Text(s.t("\(devices.count) 台已配对", "\(devices.count) paired"))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textSecondary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(PipiTokens.bgSurface)
                        .clipShape(Capsule())
                    }

                    HStack(spacing: 8) {
                        PipiActionButton(
                            isConnected ? s.t("刷新配对码", "Refresh QR") : s.t("开启连接", "Connect"),
                            systemImage: "qrcode",
                            tone: .primary,
                            density: .desktopCompact
                        ) {
                            _ = store.startUniversalE2EERelay()
                        }

                        if let urlStr = store.lastUniversalPairingURL {
                            PipiActionButton(
                                s.t("复制链接", "Copy Link"),
                                systemImage: "doc.on.doc",
                                tone: .secondary,
                                density: .desktopCompact
                            ) {
                                #if os(macOS)
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(urlStr, forType: .string)
                                #endif
                                store.noticeBanner = s.t("已复制手机配对链接", "Copied pairing link")
                            }
                        }

                        if isConnected {
                            PipiActionButton(
                                s.t("断开", "Stop"),
                                tone: .secondary,
                                density: .desktopCompact
                            ) {
                                store.stopUniversalE2EERelay()
                            }
                        }
                    }
                }
            }

            if !devices.isEmpty {
                VStack(spacing: 0) {
                    Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
                        .padding(.bottom, 8)
                    ForEach(devices.prefix(3)) { dev in
                        HStack {
                            Image(systemName: "iphone")
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                            Text(dev.label)
                                .font(PipiTokens.fontCaption.weight(.medium))
                                .foregroundStyle(PipiTokens.textPrimary)
                            Spacer()
                            Button(s.t("移除", "Revoke")) {
                                _ = store.revokePairedDevice(id: dev.id)
                            }
                            .buttonStyle(.borderless)
                            .font(PipiTokens.fontMicro.weight(.medium))
                            .foregroundStyle(PipiTokens.stateError)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .padding(PipiTokens.spacing16)
        .frame(maxWidth: .infinity, minHeight: 198, alignment: .topLeading)
        .background(PipiTokens.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusXL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusXL, style: .continuous)
                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
        )
    }

    private var sentinelAndSandboxCard: some View {
        let box = store.lastBoxSelfCheck
        let allHealthy = (box?.allPassed ?? true) && store.sentinelIssues.isEmpty

        return VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(PipiTokens.fontSubheadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                Text(s.t("安全与运行状态", "Security & Health"))
                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(allHealthy ? PipiTokens.stateSuccess : PipiTokens.stateWarning)
                        .frame(width: 6, height: 6)
                    Text(allHealthy ? s.t("运行正常", "Healthy") : s.t("需关注", "Attention"))
                        .font(PipiTokens.fontMicro.weight(.medium))
                        .foregroundStyle(allHealthy ? PipiTokens.stateSuccess : PipiTokens.stateWarning)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(PipiTokens.bgSurface)
                .clipShape(Capsule())
            }

            VStack(spacing: 0) {
                HStack(spacing: PipiTokens.spacing12) {
                    Image(systemName: "lock.shield.fill")
                        .font(PipiTokens.fontSubheadline)
                        .foregroundStyle(PipiTokens.stateSuccess)
                        .frame(width: 28, height: 28)
                        .background(PipiTokens.stateSuccess.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.t("本地沙箱保护", "Local Sandbox"))
                            .font(PipiTokens.fontCaption.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(
                            box.map { s.t("已通过 \($0.passedCount)/\($0.checks.count) 项隔离校验 · 密钥托管已启用", "Passed \($0.passedCount)/\($0.checks.count) checks · Key isolation on") }
                                ?? s.t("默认隔离工作目录并托管 API 密钥", "Workspace isolated · Key broker active")
                        )
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer(minLength: 8)
                    PipiActionButton(
                        s.t("自检", "Verify"),
                        tone: .secondary,
                        density: .desktopCompact
                    ) {
                        let check = store.runBotBoxSelfCheck()
                        store.noticeBanner = s.t("安全沙箱自检通过 \(check.passedCount)/\(check.checks.count)", "Sandbox check passed \(check.passedCount)/\(check.checks.count)")
                    }
                }
                .padding(.vertical, 10)

                Rectangle()
                    .fill(PipiTokens.borderSubtle)
                    .frame(height: 1)

                HStack(spacing: PipiTokens.spacing12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(PipiTokens.fontSubheadline)
                        .foregroundStyle(PipiTokens.soulPrimary)
                        .frame(width: 28, height: 28)
                        .background(PipiTokens.soulPrimary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.t("后台健康巡检", "Background Health"))
                            .font(PipiTokens.fontCaption.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(
                            store.sentinelIssues.isEmpty
                                ? s.t("无卡死任务或重复报错，自动监测中", "No stalled queues or repeated errors")
                                : s.t("发现 \(store.sentinelIssues.count) 项待处理异常", "\(store.sentinelIssues.count) issues detected")
                        )
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer(minLength: 8)
                    PipiActionButton(
                        s.t("巡检", "Scan"),
                        tone: .secondary,
                        density: .desktopCompact
                    ) {
                        let rep = store.runSentinelHealthScan()
                        store.noticeBanner = s.t("健康巡检完成：\(rep.issues.count) 项异常", "Health scan finished: \(rep.issues.count) issues")
                    }
                }
                .padding(.vertical, 10)
            }
            .padding(.horizontal, PipiTokens.spacing12)
            .background(PipiTokens.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))

            if !store.sentinelIssues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.sentinelIssues.prefix(3)) { issue in
                        HStack {
                            Text("\(issue.normalizedTitle) (\(issue.count)×)")
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(issue.severity.rawValue.uppercased())
                                .font(PipiTokens.fontMicro.weight(.semibold))
                                .foregroundStyle(issue.severity == .high ? PipiTokens.stateError : PipiTokens.stateWarning)
                        }
                    }
                }
            }
        }
        .padding(PipiTokens.spacing16)
        .frame(maxWidth: .infinity, minHeight: 198, alignment: .topLeading)
        .background(PipiTokens.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusXL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusXL, style: .continuous)
                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
        )
    }

    #if os(macOS)
    private func generateQRImage(from text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
    #endif

    private func missionColumn<Content: View>(
        title: String,
        count: Int,
        dotTint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(dotTint)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                Spacer()
                Text("\(count)")
                    .font(PipiTokens.fontMicro.monospacedDigit().weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(PipiTokens.bgElevated)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                    )
            }
            .padding(.horizontal, 2)

            VStack(spacing: PipiTokens.spacing12) {
                content()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 344, alignment: .topLeading)
        .padding(PipiTokens.spacing12)
        .background(PipiTokens.bgSurface.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusXL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusXL, style: .continuous)
                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
        )
    }

    private func missionCard(
        title: String,
        subtitle: String,
        owner: String,
        badge: String,
        badgeTint: Color,
        icon: String,
        showChevron: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(badgeTint)
                    .frame(width: 24, height: 24)
                    .background(badgeTint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(subtitle)
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
            }

            HStack(spacing: 6) {
                Text(owner)
                    .font(PipiTokens.fontMicro.weight(.medium))
                    .foregroundStyle(PipiTokens.textSecondary)
                    .lineLimit(1)

                Spacer()

                Text(badge)
                    .font(PipiTokens.fontMicro.weight(.semibold))
                    .foregroundStyle(badgeTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeTint.opacity(0.11))
                    .clipShape(Capsule())

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(PipiTokens.fontMicro.weight(.semibold))
                        .foregroundStyle(PipiTokens.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PipiTokens.spacing12)
        .background(PipiTokens.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous)
                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
        )
    }

    private func emptyColumnPlaceholder(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(PipiTokens.fontHeadline)
                .foregroundStyle(PipiTokens.textMuted)
            Text(text)
                .font(PipiTokens.fontCaption)
                .foregroundStyle(PipiTokens.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, PipiTokens.spacing12)
        .background(PipiTokens.bgCanvas.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous)
                .strokeBorder(PipiTokens.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
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

    // MARK: - Tab 3: Event-Driven Triggers & Blueprint Self-Evolution

    private var triggersAndEvolutionStage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                // Section 0: Day-Shift Operational Loops & Human Draft Gate (@N01ennn)
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    HStack {
                        Text(s.t("Day-Shift 运营环与人工闸门（Trigger → Context → Draft → Gate → Report）", "Day-Shift Loops & Human Draft Gates"))
                            .font(PipiTokens.fontHeadline)
                            .foregroundStyle(PipiTokens.textPrimary)
                        Spacer()
                    }
                    HStack(spacing: PipiTokens.spacing8) {
                        ForEach(PipiOperationalLoopPreset.allCases) { preset in
                            let installed = store.operationalLoops.contains(where: { $0.preset == preset })
                            Button {
                                _ = store.installDayShiftLoop(preset)
                            } label: {
                                Label(
                                    installed ? "✓ \(preset.title(lang))" : "+ \(preset.title(lang))",
                                    systemImage: preset.iconName
                                )
                                .font(PipiTokens.fontCaption.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if !store.loopDrafts.isEmpty {
                        ForEach(store.loopDrafts.prefix(6)) { draft in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("[\(draft.loopName)] \(draft.inputSummary)")
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
                                        TextField(s.t("如草稿不够准，输入一条 Harness 新规则（改规则不改草稿）…", "Draft off? Add a Harness rule instead of one-off edits…"), text: $draftRuleNote)
                                            .textFieldStyle(.roundedBorder)
                                        Button(s.t("批准并沉淀语气范例", "Approve & Learn Tone")) {
                                            store.approveLoopDraft(id: draft.id)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        Button(s.t("加规则并发出", "Add Rule & Send")) {
                                            let note = draftRuleNote
                                            draftRuleNote = ""
                                            store.editLoopDraftAndAddRule(id: draft.id, editedDraft: draft.draftContent, newRuleNote: note)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                            }
                            .padding(PipiTokens.spacing12)
                            .background(PipiTokens.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                        }
                    }

                    // Knowledge Gaps Roadmap ("The report feeds the context")
                    let openGaps = store.knowledgeGaps.filter { $0.status == .open }
                    if !openGaps.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.t("知识缺口路线图（\(openGaps.count) 项未覆盖问题 → 反哺文档）", "Knowledge Gaps Roadmap (\(openGaps.count) open)"))
                                .font(PipiTokens.fontSubheadline.weight(.semibold))
                                .foregroundStyle(PipiTokens.stateWarning)
                            ForEach(openGaps.prefix(5)) { gap in
                                HStack {
                                    Text("×\(gap.occurrenceCount) \(gap.question)")
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Spacer()
                                    Button(s.t("已补齐文档", "Mark Documented")) {
                                        store.resolveKnowledgeGap(id: gap.id, docPath: "docs/")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                            }
                        }
                        .padding(PipiTokens.spacing12)
                        .background(PipiTokens.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                    }

                    // Skill Pruning & Poteto Pyramid Rule Graduation Card
                    let bloat = store.auditPromptBloat(for: store.activePersona)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "scissors")
                                .foregroundStyle(PipiTokens.soulPrimary)
                            Text(s.t("上下文瘦身与规则晋升（pstack / Poteto Pyramid）", "Skill Pruning & Deterministic Graduation"))
                                .font(PipiTokens.fontSubheadline.weight(.semibold))
                                .foregroundStyle(PipiTokens.textPrimary)
                            Spacer()
                            Text(lang == .zhHans ? bloat.summaryZh : bloat.summaryEn)
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                        }
                        if !bloat.graduationCandidates.isEmpty {
                            ForEach(bloat.graduationCandidates.prefix(3), id: \.self) { rule in
                                HStack {
                                    Text(rule)
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(PipiTokens.textSecondary)
                                        .lineLimit(1)
                                    Spacer()
                                    Button(s.t("晋升为确定性校验", "Graduate to Check")) {
                                        _ = store.graduateRuleToDeterministicCheck(rule: rule, removeFromBotId: store.activePersona.id)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                }
                            }
                        }
                    }
                    .padding(PipiTokens.spacing12)
                    .background(PipiTokens.bgSurface)
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                }

                // Section A: Blueprint Self-Evolution Diff Proposals
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    Text(s.t("蓝图自进化提案（EvolutionDiff 审批）", "Blueprint Self-Evolution Proposals"))
                        .font(PipiTokens.fontHeadline)
                        .foregroundStyle(PipiTokens.textPrimary)

                    if store.blueprintEvolutionProposals.isEmpty {
                        Text(s.t("当 Bot 在运行中遇到纠偏/失败或触发周期复盘时，会自动对照原始 Goal 生成流程优化 Diff 推送到这里审批。", "When a Bot gathers feedback or corrections, proposed Blueprint EvolutionDiffs appear here for one-tap approval."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textMuted)
                            .padding(PipiTokens.spacing12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PipiTokens.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                    } else {
                        ForEach(store.blueprintEvolutionProposals) { prop in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("\(prop.botName) · \(prop.goalSummary)")
                                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Spacer()
                                    Text(prop.status.rawValue.uppercased())
                                        .font(PipiTokens.fontMicro.weight(.semibold))
                                        .foregroundStyle(prop.status == .pending ? PipiTokens.stateWarning : PipiTokens.stateSuccess)
                                }
                                Text(prop.rationale)
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textSecondary)

                                ForEach(prop.diffs) { diff in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("[\(diff.operation.rawValue)] \(diff.title)")
                                            .font(PipiTokens.fontCaption.weight(.semibold))
                                            .foregroundStyle(PipiTokens.soulPrimary)
                                        if let before = diff.previousValue, !before.isEmpty {
                                            Text("- \(before)")
                                                .font(PipiTokens.fontMonoSmall)
                                                .foregroundStyle(PipiTokens.stateError)
                                        }
                                        Text("+ \(diff.proposedValue)")
                                            .font(PipiTokens.fontMonoSmall)
                                            .foregroundStyle(PipiTokens.stateSuccess)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(PipiTokens.bgCanvas)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }

                                HStack(spacing: 8) {
                                    if prop.status == .pending {
                                        Button(s.t("批准生效", "Approve")) {
                                            store.approveBlueprintEvolutionProposal(id: prop.id)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)

                                        Button(s.t("拒绝", "Reject")) {
                                            store.rejectBlueprintEvolutionProposal(id: prop.id)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    } else if prop.status == .approved {
                                        Button(s.t("回滚到上一版", "Rollback")) {
                                            store.rollbackBlueprintEvolutionProposal(id: prop.id)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                            }
                            .padding(PipiTokens.spacing12)
                            .background(PipiTokens.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous)
                                    .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                            )
                        }
                    }
                }

                // Section B: Event-Driven Routines
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    HStack {
                        Text(s.t("事件驱动 Routine（Webhook / 目录 Git / 微信规则 / 健康 / Cron）", "Event-Driven Routines"))
                            .font(PipiTokens.fontHeadline)
                            .foregroundStyle(PipiTokens.textPrimary)
                        Spacer()
                        Button {
                            showNewTriggerSheet = true
                        } label: {
                            Label(s.t("新建事件触发器", "New Event Trigger"), systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    ForEach(store.routines) { rt in
                        HStack(spacing: PipiTokens.spacing12) {
                            Image(systemName: rt.triggerKind.iconName)
                                .foregroundStyle(PipiTokens.soulPrimary)
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
                                Button(s.t("复制 Webhook URL", "Copy URL")) {
                                    #if os(macOS)
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(store.webhookURLString(for: rt), forType: .string)
                                    #endif
                                    store.noticeBanner = s.t("已复制 Webhook 地址", "Copied Webhook URL")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            Button(s.t("立即运行", "Run Now")) {
                                Task { await store.runRoutineNow(rt) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Toggle("", isOn: Binding(
                                get: { rt.isEnabled },
                                set: { store.toggleRoutine(id: rt.id, enabled: $0) }
                            ))
                            .labelsHidden()
                        }
                        .padding(PipiTokens.spacing12)
                        .background(PipiTokens.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                    }

                    if !store.routineRunLogs.isEmpty {
                        Text(s.t("最近事件触发日志", "Recent Trigger Logs"))
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textSecondary)
                            .padding(.top, 8)
                        ForEach(store.routineRunLogs.prefix(10)) { log in
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
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(PipiTokens.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
            .padding(PipiTokens.spacing16)
        }
    }

    // MARK: - Tab 4: Clean-Room MIT Bot Persona & Lean Skill Marketplace

    private var marketplaceStage: some View {
        let bots = PipiBotMarketplaceCatalog.curatedBots.filter {
            marketplaceFilter == nil || $0.category == marketplaceFilter
        }
        let skills = PipiBotMarketplaceCatalog.curatedSkills.filter {
            marketplaceFilter == nil || $0.category == marketplaceFilter
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                HStack(spacing: PipiTokens.spacing8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(PipiTokens.stateSuccess)
                    Text(s.t("100% 原创 MIT 开源人设与精炼技能市场（无任何专有提示词或商业许可隐患）：一键安装含 Goal 蓝图、Day-Shift 运营环与 <300 token 瘦身技能包。", "100% clean-room MIT Bot Personas & pruned (<300 tok) verification Skills — zero proprietary prompt or license risk."))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                }
                .padding(PipiTokens.spacing12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PipiTokens.stateSuccess.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))

                // v0.15.0 Portable Redacted Team / Bot Template Export & Import (`bot.md` / `team.md`)
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    HStack {
                        Label(s.t("便携脱敏模板导入/导出（兼容 team.md / bot.md）", "Portable Redacted Templates (team.md / bot.md)"), systemImage: "square.and.arrow.up.on.square")
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Spacer()
                        Button(s.t("脱敏导出当前团队到剪贴板", "Export Redacted Team")) {
                            let exported = store.exportTeamAsPortableMarkdown(personaIds: store.personas.prefix(6).map(\.id))
                            lastExportRedactedCount = exported.package.redactedSecretsCount
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(exported.markdown, forType: .string)
                            #endif
                            store.noticeBanner = s.t("已脱敏导出 \(exported.package.bots.count) 个 Bot（自动清洗 \(exported.package.redactedSecretsCount) 处敏感项，Routine 默认暂停）", "Exported \(exported.package.bots.count) bots (\(exported.package.redactedSecretsCount) redactions)")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    HStack(spacing: 8) {
                        TextField(
                            s.t("粘贴 bot.md / team.md 内容进行脱敏预览与安全导入…", "Paste bot.md / team.md Markdown to preview & import safely…"),
                            text: $portableImportMarkdown
                        )
                        .textFieldStyle(.roundedBorder)

                        Button(s.t("预览模板", "Preview")) {
                            guard !portableImportMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            _ = store.previewPortableTemplate(markdown: portableImportMarkdown)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if let preview = store.pendingPortableTemplatePreview {
                        HStack {
                            Text(s.t("待导入「\(preview.name)」：\(preview.bots.count) 个 Bot（默认 Bot Box 沙箱）、\(preview.routines.count) 条暂停 Routine、已清洗 \(preview.redactedSecretsCount) 处敏感信息", "Preview '\(preview.name)': \(preview.bots.count) sandboxed bots, \(preview.routines.count) paused routines, \(preview.redactedSecretsCount) redactions"))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                            Spacer()
                            Button(s.t("确认导入", "Confirm Import")) {
                                let added = store.applyPortableTemplate(preview)
                                portableImportMarkdown = ""
                                store.noticeBanner = s.t("已安全导入 \(added.count) 个智能体（均已默认开启 Bot Box 隔离）", "Safely imported \(added.count) sandboxed bots")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(PipiTokens.spacing12)
                .background(PipiTokens.bgSurface)
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous)
                        .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                )

                // Category filter pills
                HStack(spacing: 8) {
                    Button(s.t("全部", "All")) { marketplaceFilter = nil }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    ForEach(PipiMarketplaceCategory.allCases) { cat in
                        Button(cat.label(lang)) { marketplaceFilter = cat }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                Text(s.t("精选自动化 Bot 人设（含蓝图 + 默认运营环）", "Curated Automation Bot Personas (Blueprint + Loop)"))
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: PipiTokens.spacing12)], spacing: PipiTokens.spacing12) {
                    ForEach(bots) { item in
                        let installed = store.personas.contains(where: { $0.id == item.id })
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.name(lang))
                                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Spacer()
                                Text(item.license)
                                    .font(PipiTokens.fontMicro.weight(.semibold))
                                    .foregroundStyle(PipiTokens.stateSuccess)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(PipiTokens.stateSuccess.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            Text(item.tagline(lang))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                                .lineLimit(2)
                            Text("Goal: \(item.blueprint.goal)")
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textMuted)
                                .lineLimit(2)
                            HStack {
                                Text("\(item.recommendedSkills.count) \(s.t("项配套技能", "skills"))")
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(PipiTokens.soulPrimary)
                                Spacer()
                                Button(installed ? s.t("已安装", "Installed") : s.t("一键安装", "Install")) {
                                    _ = store.installMarketplaceBot(item)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(installed)
                            }
                        }
                        .padding(PipiTokens.spacing12)
                        .background(PipiTokens.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous)
                                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                    }
                }

                Text(s.t("精炼 Skill 技能市场（pstack 瘦身标准 · MIT）", "Pruned Lean Skill Packs (pstack Style · MIT)"))
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: PipiTokens.spacing12)], spacing: PipiTokens.spacing12) {
                    ForEach(skills) { sk in
                        let installed = store.ecosystemManager.installedSkills.contains(where: { $0.id == sk.id })
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(sk.name(lang))
                                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Spacer()
                                Text("~\(sk.estimatedTokens) tok · \(sk.license)")
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(PipiTokens.stateSuccess)
                            }
                            Text(sk.summary(lang))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                                .lineLimit(2)
                            HStack {
                                Spacer()
                                Button(installed ? s.t("已挂载", "Installed") : s.t("一键挂载", "Install Skill")) {
                                    _ = store.installMarketplaceSkill(sk)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(installed)
                            }
                        }
                        .padding(PipiTokens.spacing12)
                        .background(PipiTokens.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(PipiTokens.spacing16)
        }
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
