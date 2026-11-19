import SwiftUI
import PipiBotKit

#if os(macOS)
import AppKit
#endif

public struct PipiBotInspectorView: View {
    @Bindable public var store: PipiAppStore
    public var onEditBot: (PipiBotPersona) -> Void
    public var onOpenBotRoutines: (PipiBotPersona) -> Void
    public var onClose: () -> Void

    @Environment(\.pipiTextScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isPlanExpanded: Bool = true
    @State private var isChangesExpanded: Bool = false

    public init(
        store: PipiAppStore,
        onEditBot: @escaping (PipiBotPersona) -> Void = { _ in },
        onOpenBotRoutines: @escaping (PipiBotPersona) -> Void = { _ in },
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self.onEditBot = onEditBot
        self.onOpenBotRoutines = onOpenBotRoutines
        self.onClose = onClose
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }
    private var accent: Color { PipiTokens.color(for: store.activePersona.accent) }

    public var body: some View {
        let _ = textScale
        VStack(spacing: 0) {
            // Inspector Header (No duplicate [✕] close button; top-right [◫] toolbar button controls visibility)
            HStack(spacing: PipiTokens.spacing8) {
                Text(s.inspectorTitle)
                    .font(PipiTokens.fontHeadline)
                    .tracking(PipiTokens.trackingHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, PipiTokens.spacing16)
            .padding(.top, 12)
            .padding(.bottom, PipiTokens.spacing12)

            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                    botDetailSection
                    executionRoutingSection
                    contextUsageSection
                    runtimeEnvironmentSection
                    optionalPlanAndChangesSection
                }
                .padding(PipiTokens.spacing16)
            }
            .pipiHideScrollbars()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PipiTokens.bgSidebar.ignoresSafeArea(.container, edges: .top))
        .background(alignment: .top) {
            PipiTokens.bgSidebar
                .frame(height: 80)
                .ignoresSafeArea(.container, edges: .top)
        }
        .onAppear {
            if store.selectedFileChangeId != nil {
                isChangesExpanded = true
            }
        }
        .onChange(of: store.selectedFileChangeId) { _, newId in
            if newId != nil {
                withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                    isChangesExpanded = true
                }
            }
        }
    }

    // MARK: - 1. Bot 详情卡

    private var botDetailSection: some View {
        let bot = store.activePersona
        let routineCount = store.routines.filter { $0.personaId == bot.id }.count

        return VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack(alignment: .top, spacing: PipiTokens.spacing12) {
                PipiBotPersonaGlyph(persona: bot, size: 44, isSelected: true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: PipiTokens.spacing8) {
                        Text(bot.name(lang))
                            .font(PipiTokens.fontHeadline)
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 4)

                        botLiveStatusPill(for: bot)
                            .fixedSize()
                    }

                    Text(bot.role(lang))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

            HStack(spacing: PipiTokens.spacing8) {
                PipiActionButton(
                    s.t("编辑智能体", "Edit Agent"),
                    systemImage: "pencil",
                    tone: .secondary,
                    density: .desktopCompact,
                    fullWidth: true
                ) {
                    onEditBot(bot)
                }

                PipiActionButton(
                    s.t("例行任务 (\(routineCount))", "Routines (\(routineCount))"),
                    systemImage: "clock.arrow.circlepath",
                    tone: .secondary,
                    density: .desktopCompact,
                    fullWidth: true
                ) {
                    onOpenBotRoutines(bot)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PipiTokens.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }

    @ViewBuilder
    private func botLiveStatusPill(for bot: PipiBotPersona) -> some View {
        if store.isGeneratingReply {
            let isThinking = store.generatingStatusText == s.thinkingStatus
            HStack(spacing: 5) {
                PipiDotIndicator(vitality: .busy, color: accent, size: 5.5)
                Text(isThinking ? s.t("思考中", "Thinking") : s.t("运行中", "Running"))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textPrimary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(PipiTokens.bgSurfaceHover, in: Capsule())
        } else if store.activeConversation?.state == .needsYou {
            HStack(spacing: 5) {
                Circle()
                    .fill(PipiTokens.stateWarning)
                    .frame(width: 6, height: 6)
                Text(s.needsYouLabel)
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.stateWarning)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(PipiTokens.stateWarningBg, in: Capsule())
        } else if store.isPersonaRunning(bot.id) {
            HStack(spacing: 5) {
                PipiDotIndicator(vitality: .busy, color: accent, size: 5.5)
                Text(s.t("运行中", "Running"))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textPrimary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(PipiTokens.bgSurfaceHover, in: Capsule())
        } else {
            HStack(spacing: 4) {
                Circle()
                    .fill(PipiTokens.stateSuccess)
                    .frame(width: 6, height: 6)
                Text(s.t("待命", "Ready"))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textSecondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(PipiTokens.bgSurface, in: Capsule())
            .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
        }
    }

    // MARK: - 2. 底层执行与调度（Who Executed）

    private var executionRoutingSection: some View {
        let tier = store.effectivePermissionTier()
        let convId = store.activeConversationId
        let recentRuns: [PipiRunRecord] = convId.map { id in
            Array(store.runRecords.filter { $0.conversationId == id }.prefix(3))
        } ?? []
        let lastExecutedLabel: String = {
            if let lastRun = recentRuns.first?.engineLabel, !lastRun.isEmpty {
                return lastRun
            }
            if let convEngine = store.activeConversation?.lastEngineLabel, !convEngine.isEmpty {
                return convEngine
            }
            return s.t("尚无调用记录", "No runs yet")
        }()
        let hasExecuted = recentRuns.first != nil || !(store.activeConversation?.lastEngineLabel ?? "").isEmpty

        return VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            sectionTitle(s.t("底层执行与调度", "Execution & Routing"))

            VStack(alignment: .leading, spacing: 0) {
                // Current Routed Engine
                HStack(spacing: PipiTokens.spacing8) {
                    Text(s.t("当前路由引擎", "Routed Engine"))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                    Spacer(minLength: 6)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(store.hasConfiguredEngine ? PipiTokens.stateSuccess : PipiTokens.stateWarning)
                            .frame(width: 6.5, height: 6.5)
                        Text(store.hasConfiguredEngine ? store.activeEngineDisplayLabel() : s.engineStatusUnconfigured)
                            .font(PipiTokens.fontCaption.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                cardDivider

                // Last Actual Executed Engine
                HStack(spacing: PipiTokens.spacing8) {
                    Text(s.t("最近底层调用", "Last Executed By"))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                    Spacer(minLength: 6)
                    Text(lastExecutedLabel)
                        .font(PipiTokens.fontCaption.weight(hasExecuted ? .semibold : .regular))
                        .foregroundStyle(hasExecuted ? PipiTokens.textPrimary : PipiTokens.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                cardDivider

                // Permission Tier with friendly explanation
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: PipiTokens.spacing8) {
                        Text(s.permissionTierTitle)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                        Spacer(minLength: 6)
                        HStack(spacing: 5) {
                            Image(systemName: tier.iconName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(PipiTokens.textSecondary)
                            Text(tier.label(lang))
                                .font(PipiTokens.fontCaption.weight(.semibold))
                                .foregroundStyle(PipiTokens.textPrimary)
                        }
                    }

                    Text(friendlyPermissionHint(tier))
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textMuted)
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if !recentRuns.isEmpty {
                    cardDivider

                    VStack(alignment: .leading, spacing: 8) {
                        Text(s.t("最近 3 次本会话调用", "Recent Calls (This Session)"))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textMuted)

                        ForEach(recentRuns) { run in
                            compactRunRow(run)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
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

    private func friendlyPermissionHint(_ tier: PipiPermissionTier) -> String {
        switch tier {
        case .readOnly:
            return s.t("仅分析与回答，不会修改本地文件或执行写入命令", "Reads and answers only; never modifies local files")
        case .ask:
            return s.t("先生成方案或草稿，涉及修改本地文件时会先征求你同意", "Drafts safely first and asks before applying local file changes")
        case .autoEdit:
            return s.t("允许直接协助读写工作区文件与执行命令", "Allows direct file edits and workspace commands")
        }
    }

    private func compactRunRow(_ run: PipiRunRecord) -> some View {
        let dotColor: Color = {
            switch run.status {
            case .running: return accent
            case .succeeded: return PipiTokens.stateSuccess
            case .failed: return PipiTokens.stateError
            case .cancelled: return PipiTokens.textMuted
            }
        }()
        let durationLabel: String = {
            if run.status == .running { return s.t("进行中", "Running") }
            if run.durationMs <= 0 { return "—" }
            if run.durationMs < 1000 { return "\(run.durationMs)ms" }
            return String(format: "%.1fs", Double(run.durationMs) / 1000.0)
        }()

        return HStack(spacing: PipiTokens.spacing8) {
            Circle()
                .fill(dotColor)
                .frame(width: 6.5, height: 6.5)

            Text(run.engineLabel)
                .font(PipiTokens.fontCaption.weight(.medium))
                .foregroundStyle(PipiTokens.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(durationLabel)
                .font(PipiTokens.fontMonoSmall)
                .monospacedDigit()
                .foregroundStyle(PipiTokens.textMuted)
        }
    }

    // MARK: - 3. 上下文消耗情况（Context Usage）

    private var contextUsageSection: some View {
        let usage = store.estimateContextUsage()
        let barColor: Color = {
            if usage.utilizationRatio >= 0.90 { return PipiTokens.stateError }
            if usage.utilizationRatio >= 0.72 { return PipiTokens.stateWarning }
            return PipiTokens.soulPrimary
        }()

        return VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack {
                sectionTitle(s.t("上下文消耗", "Context Usage"))
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

                // Thin Progress Bar
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
                    HStack {
                        Text(s.t("消息轮次", "Conversation"))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                        Spacer()
                        Text(
                            s.t(
                                "\(usage.turnCount) 轮 · \(usage.messageCount) 条消息",
                                "\(usage.turnCount) turns · \(usage.messageCount) msgs"
                            )
                        )
                        .font(PipiTokens.fontCaption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(PipiTokens.textPrimary)
                    }

                    HStack {
                        Text(s.t("附加文件", "Attachments"))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                        Spacer()
                        Text(s.t("\(usage.attachmentCount) 个", "\(usage.attachmentCount)"))
                            .font(PipiTokens.fontCaption.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(PipiTokens.textPrimary)
                    }

                    HStack {
                        Text(s.t("个人记忆", "Personal Memory"))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                        Spacer()
                        HStack(spacing: 5) {
                            Circle()
                                .fill(usage.isMemoryEnabled ? PipiTokens.stateSuccess : PipiTokens.textMuted.opacity(0.45))
                                .frame(width: 6, height: 6)
                            Text(
                                usage.isMemoryEnabled
                                    ? (usage.hasPersonalProfile
                                       ? s.t("已开启 · 已加载偏好", "On · Profile loaded")
                                       : s.t("已开启", "On"))
                                    : s.t("未开启", "Off")
                            )
                            .font(PipiTokens.fontCaption.weight(.medium))
                            .foregroundStyle(usage.isMemoryEnabled ? PipiTokens.textPrimary : PipiTokens.textMuted)
                        }
                    }
                }

                Text(s.t("根据当前会话消息、附件正文与人设记忆估算（仅供参考）", "Estimated from active messages, attachments, and memory"))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(PipiTokens.bgElevated)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        }
    }

    // MARK: - 4. 执行环境（Runtime Environment）

    private var runtimeEnvironmentSection: some View {
        let host = store.localHost
        let hostDotColor: Color = {
            switch host.linkState {
            case .online: return PipiTokens.stateSuccess
            case .degraded: return PipiTokens.stateWarning
            case .offline: return PipiTokens.textMuted
            }
        }()
        let rawPath = store.effectiveWorkspaceDirectory
        let folderName = URL(fileURLWithPath: rawPath).lastPathComponent
        let displayFolder = folderName.isEmpty ? rawPath : folderName

        return VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            sectionTitle(s.t("执行环境", "Environment"))

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: PipiTokens.spacing8) {
                    Circle()
                        .fill(hostDotColor)
                        .frame(width: 6.5, height: 6.5)
                    Text(host.displayName(lang))
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(host.capabilities.osName)
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                cardDivider

                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    HStack(spacing: PipiTokens.spacing8) {
                        Image(systemName: "folder")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(PipiTokens.textSecondary)
                        Text(displayFolder)
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }

                    Text(rawPath)
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    #if os(macOS)
                    HStack(spacing: PipiTokens.spacing8) {
                        PipiActionButton(
                            s.t("访达打开", "Reveal"),
                            systemImage: "arrow.up.forward.app",
                            tone: .secondary,
                            density: .desktopCompact
                        ) {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: rawPath)
                        }

                        PipiActionButton(
                            s.t("切换", "Switch"),
                            systemImage: "folder",
                            tone: .ghost,
                            density: .desktopCompact
                        ) {
                            chooseWorkspaceFolder()
                        }
                    }
                    #endif
                }
                .padding(14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PipiTokens.bgElevated)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        }
    }

    // MARK: - 5. 任务计划与改动（仅按需出现）

    @ViewBuilder
    private var optionalPlanAndChangesSection: some View {
        let planItems = store.activeConversation?.planItems ?? []
        let fileChanges = store.activeConversation?.fileChanges ?? []

        if !planItems.isEmpty || !fileChanges.isEmpty {
            VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                sectionTitle(s.t("任务计划与改动", "Plan & Changes"))

                if !planItems.isEmpty {
                    let completedCount = planItems.filter(\.isCompleted).count
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                                isPlanExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: PipiTokens.spacing8) {
                                Image(systemName: isPlanExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(PipiTokens.textMuted)
                                Text(s.planTitle)
                                    .font(PipiTokens.fontCaption.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Spacer()
                                Text("\(completedCount)/\(planItems.count)")
                                    .font(PipiTokens.fontMonoSmall)
                                    .monospacedDigit()
                                    .foregroundStyle(PipiTokens.textMuted)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isPlanExpanded {
                            cardDivider
                            PipiPlanChecklistCard(items: planItems, strings: s, accent: accent)
                                .padding(10)
                        }
                    }
                    .background(PipiTokens.bgElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                            .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                }

                if !fileChanges.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                                isChangesExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: PipiTokens.spacing8) {
                                Image(systemName: isChangesExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(PipiTokens.textMuted)
                                Text(s.filesChangedCountLabel(fileChanges.count))
                                    .font(PipiTokens.fontCaption.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isChangesExpanded {
                            cardDivider
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(fileChanges) { change in
                                    fileChangeRow(change, allChanges: fileChanges)
                                }
                            }
                            .padding(10)
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
        }
    }

    private func fileChangeRow(_ change: PipiFileChange, allChanges: [PipiFileChange]) -> some View {
        let isSelected = store.selectedFileChangeId == change.id || (store.selectedFileChangeId == nil && change.id == allChanges.first?.id)
        return Button {
            store.selectedFileChangeId = change.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: PipiTokens.spacing8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textMuted)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(change.fileName)
                            .font(PipiTokens.fontCaption.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(1)
                        Text(change.path)
                            .font(PipiTokens.fontMonoSmall)
                            .foregroundStyle(PipiTokens.textMuted)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        if change.additions > 0 {
                            Text("+\(change.additions)")
                                .foregroundStyle(PipiTokens.stateSuccess)
                        }
                        if change.deletions > 0 {
                            Text("-\(change.deletions)")
                                .foregroundStyle(PipiTokens.stateError)
                        }
                    }
                    .font(PipiTokens.fontMonoSmall.weight(.semibold))
                    .monospacedDigit()
                }

                if isSelected, let diff = change.diffPreview, !diff.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(diff.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                                let isAdd = line.hasPrefix("+")
                                let isDel = line.hasPrefix("-")
                                Text(line.isEmpty ? " " : line)
                                    .font(PipiTokens.fontMonoSmall)
                                    .foregroundStyle(isAdd ? PipiTokens.stateSuccess : (isDel ? PipiTokens.stateError : PipiTokens.textSecondary))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(isAdd ? PipiTokens.stateSuccessBg : (isDel ? PipiTokens.stateErrorBg : Color.clear))
                            }
                        }
                        .padding(PipiTokens.spacing8)
                    }
                    .background(PipiTokens.bgInset)
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                }
            }
            .padding(PipiTokens.spacing12)
            .background(PipiTokens.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .stroke(isSelected ? PipiTokens.borderStrong : PipiTokens.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.99))
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(PipiTokens.fontMicro)
            .foregroundStyle(PipiTokens.textMuted)
            .textCase(.uppercase)
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(PipiTokens.borderSubtle)
            .frame(height: 1)
    }

    #if os(macOS)
    private func chooseWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: store.effectiveWorkspaceDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            if var proj = store.activeProject {
                proj.workspacePath = url.path
                store.upsertProject(proj)
            } else {
                store.workspaceDirectory = url.path
                store.saveResidentState()
            }
        }
    }
    #endif
}
