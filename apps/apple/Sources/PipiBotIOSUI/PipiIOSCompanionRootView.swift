import SwiftUI
import PipiBotKit

#if os(iOS)
import UIKit
#endif

public enum PipiIOSTab: String, CaseIterable, Sendable, Identifiable {
    case chat
    case bots
    case tasks
    case settings

    public var id: String { rawValue }

    public func title(_ s: PipiStrings) -> String {
        switch self {
        case .chat: return s.tabChat
        case .bots: return s.tabBots
        case .tasks: return s.tabTasks
        case .settings: return s.tabSettings
        }
    }

    public var iconName: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .bots: return "person.2.fill"
        case .tasks: return "checklist"
        case .settings: return "gearshape.fill"
        }
    }
}

public struct PipiIOSCompanionRootView: View {
    @Bindable public var store: PipiAppStore

    @State private var selectedTab: PipiIOSTab = .chat
    @State private var chatSurfaceMode: Int = 0 // 0 = Direct 1v1, 1 = Multi-Host Parallel Group
    @State private var draftInput: String = ""
    @State private var groupDraftInput: String = ""
    @State private var meshHubURLDraft: String = "http://127.0.0.1:4242"
    @State private var meshHubTokenDraft: String = ""
    @State private var ecoSkillURLDraft: String = ""
    @State private var showAddModelSheet = false
    @State private var modelPreset: PipiLLMProviderKind = .openai
    @State private var modelApiKey: String = ""
    @State private var modelBaseURL: String = PipiLLMProviderKind.openai.defaultBaseURL
    @State private var modelId: String = PipiLLMProviderKind.openai.defaultModelId
    @State private var testResultText: String?
    @State private var tasksSubTab: Int = 0
    @State private var iosWorktreeFeedbackDraft: String = ""

    public init(store: PipiAppStore) {
        self.store = store
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }
    private var activeAccent: Color { PipiTokens.color(for: store.activePersona.accent) }

    public var body: some View {
        ZStack(alignment: .bottom) {
            PipiTokens.bgCanvas
                .ignoresSafeArea()

            if !store.hasCompletedOnboarding {
                iosOnboardingView
            } else {
                mainTabShell
            }

            if showAddModelSheet {
                PipiFormSheet(
                    title: s.addModelProvider,
                    subtitle: s.t("配置任意云端大模型 API 或本地兼容接口", "Connect a cloud LLM API or compatible endpoint"),
                    detent: .compact,
                    submitLabel: s.saveAndUse,
                    submitIcon: "checkmark.circle.fill",
                    onCancel: { showAddModelSheet = false },
                    onSubmit: {
                        let cfg = PipiLLMProviderConfig(
                            name: modelPreset.displayName,
                            kind: modelPreset,
                            baseURL: modelBaseURL,
                            apiKey: modelApiKey,
                            modelId: modelId.isEmpty ? modelPreset.defaultModelId : modelId
                        )
                        if cfg.isReady {
                            store.upsertLLMProvider(cfg, setAsDefault: true)
                            triggerHaptic(.success)
                            showAddModelSheet = false
                        }
                    }
                ) {
                    iosModelFormFields
                }
            }
        }
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
        .onOpenURL { url in
            if let action = PipiIOSDeepLinkRouter.parse(url) {
                PipiIOSDeepLinkRouter.apply(action, to: store, selectedTab: &selectedTab)
                triggerHaptic(.medium)
            }
        }
    }

    // MARK: - Compact iOS First-Launch Setup

    private var iosOnboardingView: some View {
        ScrollView {
            VStack(spacing: PipiTokens.spacing20) {
                Spacer(minLength: 24)
                PipiAvatarView(engine: store.avatarEngine, size: 96, accentOverride: activeAccent)

                VStack(spacing: PipiTokens.spacing8) {
                    Text(s.onboardingWelcomeTitle)
                        .font(PipiTokens.fontHero)
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text(s.appTagline)
                        .font(PipiTokens.fontBody)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    iosModelFormFields
                }
                .padding(PipiTokens.spacing16)
                .background(PipiTokens.bgSurface)
                .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous))

                PipiActionButton(s.onboardingStartChatting, systemImage: "arrow.right", tone: .primary, density: .mobile, fullWidth: true) {
                    let cfg = PipiLLMProviderConfig(
                        name: modelPreset.displayName,
                        kind: modelPreset,
                        baseURL: modelBaseURL,
                        apiKey: modelApiKey,
                        modelId: modelId.isEmpty ? modelPreset.defaultModelId : modelId
                    )
                    if cfg.isReady {
                        store.upsertLLMProvider(cfg, setAsDefault: true)
                    }
                    store.completeOnboarding()
                    triggerHaptic(.success)
                }

                Button(s.skipForNow) {
                    store.completeOnboarding()
                }
                .buttonStyle(.plain)
                .font(PipiTokens.fontCaption)
                .foregroundStyle(PipiTokens.textMuted)
            }
            .padding(PipiTokens.spacing20)
        }
    }

    // MARK: - Main Shell

    private var mainTabShell: some View {
        VStack(spacing: 0) {
            dynamicIslandHeader
                .padding(.top, PipiTokens.spacing8)
                .padding(.horizontal, PipiTokens.spacing16)
                .padding(.bottom, PipiTokens.spacing12)

            Group {
                switch selectedTab {
                case .chat:
                    chatPage
                case .bots:
                    botsPage
                case .tasks:
                    iosMissionHubPage
                case .settings:
                    settingsPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PipiBottomBar {
                HStack(spacing: PipiTokens.spacing8) {
                    ForEach(PipiIOSTab.allCases) { tab in
                        bottomTabButton(tab)
                    }
                }
            }
        }
    }

    // MARK: - Top Status Pill

    private var dynamicIslandHeader: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(PipiTokens.dynamicIslandShell)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(PipiTokens.dynamicIslandStroke, lineWidth: 1)
                )

            HStack(spacing: PipiTokens.spacing12) {
                PipiBotPersonaGlyph(persona: store.activePersona, size: 26, isSelected: true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(store.activePersona.name(lang))
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textInverse)
                        .lineLimit(1)

                    Text(store.generatingStatusText ?? store.activeEngineDisplayLabel())
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(store.hasConfiguredEngine ? activeAccent : PipiTokens.stateWarning)
                        .lineLimit(1)
                }

                Spacer(minLength: PipiTokens.spacing4)

                if !store.pendingDecisions.isEmpty {
                    Button {
                        selectedTab = .tasks
                        triggerHaptic(.light)
                    } label: {
                        Text("\(store.pendingDecisions.count)")
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
    }

    // MARK: - Tab 1: Unified Multi-Host Group Parallel Workbench & 1v1 Direct Chat

    private var chatPage: some View {
        VStack(spacing: 0) {
            // Clean Direct vs Multi-Host Parallel Group Switcher
            HStack(spacing: PipiTokens.spacing8) {
                Picker("", selection: $chatSurfaceMode) {
                    Text(s.t("1v1 管家", "1v1 Direct")).tag(0)
                    Text(s.t("多机并行群聊", "Multi-Host Group")).tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if chatSurfaceMode == 1 {
                    Button {
                        let allIds = Array(store.personas.prefix(4).map(\.id))
                        let created = store.createGroupChat(
                            title: s.t("多机协作群", "Multi-Host Swarm"),
                            participantPersonaIds: allIds.isEmpty ? [store.activePersona.id] : allIds,
                            swarmMode: .mentionOnly
                        )
                        store.selectGroupChat(created.id)
                        triggerHaptic(.light)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(activeAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, PipiTokens.spacing16)
            .padding(.bottom, PipiTokens.spacing8)

            if chatSurfaceMode == 1 {
                iosParallelGroupView
            } else {
                iosDirectChatView
            }
        }
    }

    private var iosDirectChatView: some View {
        VStack(spacing: 0) {
            // Compact session picker pills so sessions never feel messy
            if !store.conversations.filter({ !$0.isArchived }).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PipiTokens.spacing8) {
                        Button {
                            _ = store.createConversation(for: store.activePersona.id, activate: true)
                            triggerHaptic(.light)
                        } label: {
                            Label(s.t("新会话", "New"), systemImage: "plus")
                                .font(PipiTokens.fontMicro.weight(.semibold))
                                .foregroundStyle(activeAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(PipiTokens.bgSurface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        ForEach(store.conversations.filter { !$0.isArchived }.sorted { $0.updatedAt > $1.updatedAt }.prefix(8)) { conv in
                            let isCur = conv.id == store.activeConversationId
                            Button {
                                store.selectConversation(conv.id)
                                triggerHaptic(.light)
                            } label: {
                                Text(conv.title)
                                    .font(PipiTokens.fontMicro.weight(isCur ? .semibold : .regular))
                                    .foregroundStyle(isCur ? PipiTokens.textInverse : PipiTokens.textSecondary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isCur ? activeAccent : PipiTokens.bgSurface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, PipiTokens.spacing16)
                    .padding(.bottom, PipiTokens.spacing8)
                }
            }

            ScrollView {
                VStack(spacing: PipiTokens.spacing12) {
                    if let conv = store.activeConversation, !conv.messages.isEmpty {
                        ForEach(conv.messages) { msg in
                            HStack {
                                if msg.role == .user { Spacer(minLength: 40) }
                                Text(msg.content)
                                    .font(PipiTokens.fontBody)
                                    .foregroundStyle(msg.role == .user ? PipiTokens.textInverse : PipiTokens.textPrimary)
                                    .padding(PipiTokens.spacing12)
                                    .background(msg.role == .user ? activeAccent : PipiTokens.bgSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                                if msg.role != .user { Spacer(minLength: 40) }
                            }
                        }
                    } else {
                        VStack(spacing: PipiTokens.spacing16) {
                            Spacer(minLength: 20)
                            PipiAvatarView(
                                engine: store.avatarEngine,
                                size: 76,
                                accentOverride: activeAccent,
                                personaAccent: store.activePersona.accent,
                                motif: PipiPersonaMotif.resolve(for: store.activePersona)
                            )
                            Text(store.activePersona.hostBadgeLabel(lang))
                                .font(PipiTokens.fontMicro.weight(.semibold))
                                .foregroundStyle(activeAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(PipiTokens.bgSurface)
                                .clipShape(Capsule())
                            Text(store.activePersona.greeting(lang))
                                .font(PipiTokens.fontBody)
                                .foregroundStyle(PipiTokens.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, PipiTokens.spacing16)

                            ForEach(store.activePersona.starterPrompts(lang), id: \.self) { prompt in
                                Button {
                                    Task { await store.sendPersonalMessage(prompt) }
                                } label: {
                                    Text(prompt)
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(PipiTokens.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(PipiTokens.spacing12)
                                        .background(PipiTokens.bgSurface)
                                        .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusMD).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, PipiTokens.spacing16)
                .padding(.bottom, PipiTokens.spacing16)
            }

            HStack(spacing: PipiTokens.spacing8) {
                TextField(s.chatPlaceholderCompact, text: $draftInput)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, PipiTokens.spacing12)
                    .frame(height: PipiTokens.buttonHeightMobile)
                    .background(PipiTokens.bgSurface)
                    .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusMD).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))

                PipiActionButton(s.send, systemImage: "arrow.up", tone: .primary, density: .mobile) {
                    let text = draftInput
                    draftInput = ""
                    Task {
                        await store.sendPersonalMessage(text)
                        triggerHaptic(.light)
                    }
                }
            }
            .padding(.horizontal, PipiTokens.spacing16)
            .padding(.vertical, PipiTokens.spacing8)
        }
    }

    private var iosParallelGroupView: some View {
        let activeGroup = store.groupChats.first(where: { $0.id == store.activeGroupChatId }) ?? store.sortedGroupChats.first
        return VStack(spacing: 0) {
            // Group & Topic Selector
            if !store.sortedGroupChats.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PipiTokens.spacing8) {
                        ForEach(store.sortedGroupChats.prefix(8)) { grp in
                            let selected = grp.id == activeGroup?.id
                            Button {
                                store.selectGroupChat(grp.id)
                                triggerHaptic(.light)
                            } label: {
                                Text("👥 \(grp.title)")
                                    .font(PipiTokens.fontMicro.weight(selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? PipiTokens.textInverse : PipiTokens.textPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(selected ? activeAccent : PipiTokens.bgSurface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, PipiTokens.spacing16)
                    .padding(.bottom, PipiTokens.spacing8)
                }
            }

            if let group = activeGroup {
                // Live Per-Task Parallel Multi-Host Lanes Strip
                let lanes = store.activeLanes(forGroup: group.id)
                if !lanes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: PipiTokens.spacing8) {
                            ForEach(lanes) { lane in
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.mini)
                                    Text("\(lane.personaName) [\(lane.hostLabel)]")
                                        .font(PipiTokens.fontMicro.weight(.semibold))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Button {
                                        store.stopGroupLane(lane.runId)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(PipiTokens.textMuted)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(PipiTokens.bgSurface)
                                .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, PipiTokens.spacing16)
                        .padding(.bottom, PipiTokens.spacing8)
                    }
                }

                // Group Messages
                ScrollView {
                    VStack(spacing: PipiTokens.spacing12) {
                        let msgs = group.messages(forTopic: group.effectiveActiveTopicId)
                        if msgs.isEmpty {
                            Text(s.t("点击下方任意主机的 @助手 即可并行派活，多个机器的 Agent 同时执行、互不卡队！", "Tap any @Agent below across your machines to run tasks in true parallel!"))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textMuted)
                                .multilineTextAlignment(.center)
                                .padding(PipiTokens.spacing20)
                        } else {
                            ForEach(msgs) { msg in
                                iosGroupMessageBubble(msg)
                            }
                        }
                    }
                    .padding(.horizontal, PipiTokens.spacing16)
                    .padding(.bottom, PipiTokens.spacing16)
                }

                // Quick @Bot Mention Bar (shows every participant with its Host badge!)
                let members = group.participantPersonaIds.compactMap { pid in store.personas.first(where: { $0.id == pid }) }
                if !members.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(members) { bot in
                                Button {
                                    let tag = "@\(bot.name(lang)) "
                                    if !groupDraftInput.contains(tag) {
                                        groupDraftInput = tag + groupDraftInput
                                    }
                                    triggerHaptic(.light)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("@\(bot.name(lang))")
                                            .font(PipiTokens.fontMicro.weight(.semibold))
                                        Text(bot.hostBadgeLabel(lang))
                                            .font(PipiTokens.fontMicro)
                                            .foregroundStyle(PipiTokens.textMuted)
                                    }
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(PipiTokens.bgSurface)
                                    .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, PipiTokens.spacing16)
                        .padding(.bottom, 6)
                    }
                }

                // Non-blocking parallel composer
                HStack(spacing: PipiTokens.spacing8) {
                    TextField(s.t("@任意主机助手并行派活…", "@mention any host agent in parallel…"), text: $groupDraftInput)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, PipiTokens.spacing12)
                        .frame(height: PipiTokens.buttonHeightMobile)
                        .background(PipiTokens.bgSurface)
                        .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusMD).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))

                    PipiActionButton(s.send, systemImage: "paperplane.fill", tone: .primary, density: .mobile) {
                        let text = groupDraftInput
                        groupDraftInput = ""
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        Task {
                            await store.sendGroupMessage(text, toGroupId: group.id, topicId: group.effectiveActiveTopicId)
                            triggerHaptic(.light)
                        }
                    }
                }
                .padding(.horizontal, PipiTokens.spacing16)
                .padding(.vertical, PipiTokens.spacing8)
            } else {
                VStack(spacing: PipiTokens.spacing16) {
                    Spacer()
                    Text(s.t("还没有多机协作群聊", "No multi-host group chats yet"))
                        .font(PipiTokens.fontHeadline)
                        .foregroundStyle(PipiTokens.textPrimary)
                    PipiActionButton(s.t("创建第一个多机并行群", "Create Multi-Host Group"), systemImage: "person.3.fill", tone: .primary, density: .mobile) {
                        let ids = Array(store.personas.prefix(4).map(\.id))
                        let created = store.createGroupChat(
                            title: s.t("多机协作群", "Multi-Host Swarm"),
                            participantPersonaIds: ids.isEmpty ? [store.activePersona.id] : ids,
                            swarmMode: .mentionOnly
                        )
                        store.selectGroupChat(created.id)
                    }
                    Spacer()
                }
                .padding(PipiTokens.spacing20)
            }
        }
    }

    private func iosGroupMessageBubble(_ msg: PipiGroupMessage) -> some View {
        let isUser: Bool = {
            if case .user = msg.senderKind { return true }
            return false
        }()
        let senderLabel: String = {
            switch msg.senderKind {
            case .user: return s.t("你", "You")
            case .system: return s.appName
            case .bot(let pid):
                if let p = store.personas.first(where: { $0.id == pid }) {
                    return "\(p.name(lang)) · \(p.hostBadgeLabel(lang))"
                }
                return pid
            }
        }()
        return VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            Text(senderLabel)
                .font(PipiTokens.fontMicro)
                .foregroundStyle(PipiTokens.textMuted)
            HStack {
                if isUser { Spacer(minLength: 40) }
                Text(msg.content.isEmpty ? "…" : msg.content)
                    .font(PipiTokens.fontBody)
                    .foregroundStyle(isUser ? PipiTokens.textInverse : PipiTokens.textPrimary)
                    .padding(PipiTokens.spacing12)
                    .background(isUser ? activeAccent : PipiTokens.bgSurface)
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                if !isUser { Spacer(minLength: 40) }
            }
        }
    }

    // MARK: - Tab 2: Multi-Machine Fleet & Cross-Host Agents

    private var botsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                // Multi-Machine Online Nodes Section
                HStack {
                    Text(s.t("多机节点舰队", "Connected Host Nodes"))
                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Spacer()
                    Button {
                        Task { _ = await store.refreshMeshNodes() }
                        triggerHaptic(.light)
                    } label: {
                        Label(s.refresh, systemImage: "arrow.clockwise")
                            .font(PipiTokens.fontMicro.weight(.semibold))
                            .foregroundStyle(activeAccent)
                    }
                    .buttonStyle(.plain)
                }

                if store.meshHubClient.nodes.isEmpty {
                    PipiListCard(
                        title: s.t("本机 Mac（默认主节点）", "Local Mac (Primary Node)"),
                        subtitle: s.t("在 Linux/其他 Mac 上运行 pipibot node join 后，所有远程主机将自动出现在此处，点击即可直连协作。", "Run pipibot node join on Linux or other Macs to see all hosts here with zero workspace switching."),
                        badgeText: s.t("本机在线", "Local Ready"),
                        badgeColor: PipiTokens.stateSuccess
                    )
                } else {
                    ForEach(store.meshHubClient.nodes) { node in
                        PipiListCard(
                            title: "\(node.name) · \(node.platformBadge)/\(node.arch)",
                            subtitle: node.workspacePath + (node.telemetry.gpuSummary.map { " · GPU: \($0)" } ?? ""),
                            badgeText: node.isOnline ? s.t("在线", "Online") : s.t("离线", "Offline"),
                            badgeColor: node.isOnline ? PipiTokens.stateSuccess : PipiTokens.textMuted,
                            footer: {
                                PipiActionButton(
                                    s.t("直连该主机 Agent", "Chat with Host Agent"),
                                    systemImage: "bolt.horizontal.fill",
                                    tone: .primary,
                                    density: .mobile,
                                    fullWidth: true
                                ) {
                                    let bot = store.ensurePersonaForMeshNode(node)
                                    store.selectPersona(bot.id)
                                    chatSurfaceMode = 0
                                    selectedTab = .chat
                                    triggerHaptic(.light)
                                }
                            }
                        )
                    }
                }

                Text(s.t("全部智能体（跨主机统一目录）", "All Agents (Unified Across Hosts)"))
                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                    .padding(.top, PipiTokens.spacing8)

                PipiListCard(
                    title: s.t("蛋宝 · AI 访谈设计新 Bot", "Eggbot · Interview-Driven Bot Architect"),
                    subtitle: s.t("用语音或文字倒出想法，蛋宝一次只问一个问题，帮你理清目标、流程与验收标准并一键装配上线。", "Brain-dump your goal via voice or text; Eggbot interviews you one question at a time and builds the Bot + Routine."),
                    badgeText: s.t("推荐", "Recommended"),
                    badgeColor: PipiTokens.soulPrimary,
                    footer: {
                        PipiActionButton(
                            s.t("开始和蛋宝设计新 Bot", "Design Bot with Eggbot"),
                            systemImage: "sparkles",
                            tone: .primary,
                            density: .mobile,
                            fullWidth: true
                        ) {
                            _ = store.openBotArchitectSession()
                            chatSurfaceMode = 0
                            selectedTab = .chat
                            triggerHaptic(.success)
                        }
                    }
                )

                Text(s.t("MIT 精选人设市场（一键装配蓝图与技能）", "Curated MIT Bot Marketplace"))
                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                    .padding(.top, PipiTokens.spacing8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PipiTokens.spacing12) {
                        ForEach(PipiBotMarketplaceCatalog.curatedBots) { item in
                            let installed = store.personas.contains(where: { $0.id == item.id })
                            PipiListCard(
                                title: item.name(lang),
                                subtitle: item.tagline(lang),
                                badgeText: installed ? s.t("已装", "Added") : item.license,
                                badgeColor: PipiTokens.stateSuccess,
                                footer: {
                                    PipiActionButton(
                                        installed ? s.t("进入对话", "Open Chat") : s.t("一键安装", "Install"),
                                        systemImage: installed ? "bubble.left.fill" : "plus.circle.fill",
                                        tone: installed ? .secondary : .primary,
                                        density: .mobile,
                                        fullWidth: true
                                    ) {
                                        let bot = store.installMarketplaceBot(item)
                                        store.selectPersona(bot.id)
                                        chatSurfaceMode = 0
                                        selectedTab = .chat
                                        triggerHaptic(.success)
                                    }
                                }
                            )
                            .frame(width: 260)
                        }
                    }
                }

                ForEach(store.personas) { persona in
                    let isSelected = store.activePersona.id == persona.id
                    let accent = PipiTokens.color(for: persona.accent)
                    PipiListCard(
                        title: persona.name(lang),
                        subtitle: "[\(persona.hostBadgeLabel(lang))] \(persona.role(lang))",
                        badgeText: persona.isRemoteHost ? persona.hostBadgeLabel(lang) : (isSelected ? s.enabled : nil),
                        badgeColor: accent,
                        leading: {
                            PipiBotPersonaGlyph(persona: persona, size: 38, isSelected: isSelected)
                        },
                        footer: {
                            HStack(spacing: PipiTokens.spacing8) {
                                PipiActionButton(
                                    s.t("1v1 对话", "Direct Chat"),
                                    systemImage: "bubble.left.fill",
                                    tone: isSelected ? .primary : .secondary,
                                    density: .mobile,
                                    fullWidth: true
                                ) {
                                    store.selectPersona(persona.id)
                                    chatSurfaceMode = 0
                                    selectedTab = .chat
                                    triggerHaptic(.light)
                                }
                                PipiActionButton(
                                    s.t("拉入群聊", "Add to Group"),
                                    systemImage: "person.3.fill",
                                    tone: .secondary,
                                    density: .mobile,
                                    fullWidth: true
                                ) {
                                    if let grpId = store.activeGroupChatId ?? store.sortedGroupChats.first?.id,
                                       let idx = store.groupChats.firstIndex(where: { $0.id == grpId }) {
                                        if !store.groupChats[idx].participantPersonaIds.contains(persona.id) {
                                            store.groupChats[idx].participantPersonaIds.append(persona.id)
                                            store.saveResidentState()
                                        }
                                        store.selectGroupChat(grpId)
                                    } else {
                                        let created = store.createGroupChat(
                                            title: s.t("多机协作群", "Multi-Host Swarm"),
                                            participantPersonaIds: [store.activePersona.id, persona.id],
                                            swarmMode: .mentionOnly
                                        )
                                        store.selectGroupChat(created.id)
                                    }
                                    chatSurfaceMode = 1
                                    selectedTab = .chat
                                    triggerHaptic(.success)
                                }
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, PipiTokens.spacing16)
            .padding(.bottom, PipiTokens.spacing24)
        }
    }

    // MARK: - Tab 4: Settings, Mesh Hub Pairing & Open-Source Ecosystem

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                PipiListCard(
                    title: s.t("多机 Mesh Hub 连接（免费自托管）", "Multi-Host Mesh Hub (Free Self-Hosted)"),
                    subtitle: store.meshHubClient.isConnected
                        ? s.t("已连接 · \(store.meshHubClient.nodes.filter(\.isOnline).count) 台主机在线", "Connected · \(store.meshHubClient.nodes.filter(\.isOnline).count) hosts online")
                        : s.t("填写你的 Mac 或 Linux VPS Hub 地址，免切工作区访问全部机器", "Enter your Mac or Linux VPS Hub URL to reach all hosts"),
                    badgeText: store.meshHubClient.isConnected ? s.t("已连接", "Live") : nil,
                    badgeColor: PipiTokens.stateSuccess,
                    footer: {
                        VStack(spacing: PipiTokens.spacing8) {
                            TextField("http://127.0.0.1:4242", text: $meshHubURLDraft)
                                .textFieldStyle(.plain)
                                .padding(PipiTokens.spacing12)
                                .background(PipiTokens.bgInset)
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                            SecureField(s.t("可选 Hub Token", "Optional Hub Token"), text: $meshHubTokenDraft)
                                .textFieldStyle(.plain)
                                .padding(PipiTokens.spacing12)
                                .background(PipiTokens.bgInset)
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                            PipiActionButton(s.t("连接并同步主机节点", "Connect & Sync Nodes"), systemImage: "network", tone: .primary, density: .mobile, fullWidth: true) {
                                Task {
                                    await store.connectMeshHub(url: meshHubURLDraft, token: meshHubTokenDraft)
                                    triggerHaptic(.success)
                                }
                            }
                        }
                    }
                )

                PipiListCard(
                    title: s.t("社区 MCP & SKILL.md 生态", "Community MCP & SKILL.md Ecosystem"),
                    subtitle: s.t("已安装 \(store.ecosystemManager.installedSkills.count) 个技能包 · \(store.ecosystemManager.installedMCPServers.count) 个 MCP 服务", "\(store.ecosystemManager.installedSkills.count) skills · \(store.ecosystemManager.installedMCPServers.count) MCP servers"),
                    footer: {
                        VStack(spacing: PipiTokens.spacing8) {
                            TextField(s.t("粘贴 GitHub 仓库或 SKILL.md 链接", "Paste GitHub repo or SKILL.md URL"), text: $ecoSkillURLDraft)
                                .textFieldStyle(.plain)
                                .padding(PipiTokens.spacing12)
                                .background(PipiTokens.bgInset)
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                            PipiActionButton(s.t("一键安装社区 Skill", "Install Skill Pack"), systemImage: "square.and.arrow.down", tone: .secondary, density: .mobile, fullWidth: true) {
                                let src = ecoSkillURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !src.isEmpty else { return }
                                ecoSkillURLDraft = ""
                                Task {
                                    _ = await store.installCommunitySkill(source: src)
                                    triggerHaptic(.success)
                                }
                            }
                        }
                    }
                )

                PipiListCard(
                    title: s.languageSectionTitle,
                    subtitle: s.languageSectionDesc,
                    footer: {
                        Picker("", selection: Binding(
                            get: { store.language },
                            set: { store.setLanguage($0) }
                        )) {
                            ForEach(PipiAppLanguage.allCases) { option in
                                Text(option.displayName(in: lang)).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                )

                PipiListCard(
                    title: s.appearanceSectionTitle,
                    subtitle: s.t("外观模式", "Theme mode"),
                    footer: {
                        Picker("", selection: Binding(
                            get: { store.themeMode },
                            set: { store.setThemeMode($0) }
                        )) {
                            ForEach(PipiThemeMode.allCases) { mode in
                                Text(mode.localizedLabel(lang)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                )

                PipiListCard(
                    title: s.settingsModels,
                    subtitle: store.hasConfiguredEngine ? store.activeEngineDisplayLabel() : s.engineStatusUnconfigured,
                    badgeText: store.hasConfiguredEngine ? s.agentStatusReady : nil,
                    badgeColor: PipiTokens.stateSuccess,
                    footer: {
                        PipiActionButton(s.addModelProvider, systemImage: "plus", tone: .primary, density: .mobile, fullWidth: true) {
                            showAddModelSheet = true
                        }
                    }
                )

                PipiListCard(
                    title: s.companionSyncToggleTitle,
                    subtitle: store.companionSyncEnabled ? store.daemonEndpoint : s.companionSyncToggleDesc,
                    badgeText: store.companionSyncEnabled ? (store.connectionMode == .liveDaemon ? s.agentStatusReady : s.t("已开启", "On")) : s.disabled,
                    badgeColor: store.companionSyncEnabled ? PipiTokens.stateSuccess : PipiTokens.textMuted,
                    trailing: {
                        Toggle("", isOn: Binding(
                            get: { store.companionSyncEnabled },
                            set: { store.setCompanionSyncEnabled($0) }
                        ))
                        .labelsHidden()
                    },
                    footer: {
                        if store.companionSyncEnabled {
                            PipiActionButton(s.refresh, systemImage: "arrow.clockwise", tone: .secondary, density: .mobile, fullWidth: true) {
                                Task { await store.refreshAllFromDaemon() }
                            }
                        }
                    }
                )
            }
            .padding(.horizontal, PipiTokens.spacing16)
            .padding(.bottom, PipiTokens.spacing24)
        }
    }

    // MARK: - iOS Mission Hub (Approvals + Evolution + Worktree Diff + Triggers & Usage)

    private var iosMissionHubPage: some View {
        VStack(spacing: PipiTokens.spacing12) {
            Picker("", selection: $tasksSubTab) {
                Text(s.t("审批与进化", "Review & Evolve")).tag(0)
                Text(s.t("代码 Diff", "Diffs")).tag(1)
                Text(s.t("事件与用量", "Triggers & Usage")).tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, PipiTokens.spacing16)

            if tasksSubTab == 0 {
                ScrollView {
                    VStack(spacing: PipiTokens.spacing12) {
                        NeedsYouSwipeDeckView(store: store, onHaptic: triggerHaptic)
                            .frame(minHeight: 260)

                        if !store.blueprintEvolutionProposals.isEmpty {
                            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                                Text(s.t("蓝图自进化提案（EvolutionDiff）", "Blueprint Self-Evolution"))
                                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .padding(.horizontal, PipiTokens.spacing16)

                                ForEach(store.blueprintEvolutionProposals) { prop in
                                    PipiListCard(
                                        title: "\(prop.botName) · \(prop.diffs.count) Diff",
                                        subtitle: prop.rationale,
                                        badgeText: prop.status.rawValue,
                                        badgeColor: prop.status == .pending ? PipiTokens.stateWarning : PipiTokens.stateSuccess,
                                        footer: {
                                            if prop.status == .pending {
                                                HStack(spacing: PipiTokens.spacing8) {
                                                    PipiActionButton(s.t("批准生效", "Approve"), systemImage: "checkmark", tone: .primary, density: .mobile, fullWidth: true) {
                                                        store.approveBlueprintEvolutionProposal(id: prop.id)
                                                        triggerHaptic(.success)
                                                    }
                                                    PipiActionButton(s.t("拒绝", "Reject"), systemImage: "xmark", tone: .secondary, density: .mobile, fullWidth: true) {
                                                        store.rejectBlueprintEvolutionProposal(id: prop.id)
                                                        triggerHaptic(.light)
                                                    }
                                                }
                                            }
                                        }
                                    )
                                    .padding(.horizontal, PipiTokens.spacing16)
                                }
                            }
                        }
                    }
                    .padding(.bottom, PipiTokens.spacing24)
                }
            } else if tasksSubTab == 1 {
                ScrollView {
                    VStack(spacing: PipiTokens.spacing12) {
                        if store.worktreeSessions.isEmpty {
                            PipiListCard(
                                title: s.t("暂无隔离 Worktree Diff", "No Active Worktree Diffs"),
                                subtitle: s.t("当群聊并行写代码或 Mac/Linux 节点拉起隔离分支时，代码 Diff 会实时同步到这里，支持手机打回续改或一键合并。", "Parallel coding Worktree Diffs from your Mac/Linux nodes appear here for mobile review, feedback, or merge."),
                                badgeText: s.t("智能隔离就绪", "Auto-Isolation Ready"),
                                badgeColor: PipiTokens.stateSuccess
                            )
                        } else {
                            ForEach(store.worktreeSessions) { wt in
                                PipiListCard(
                                    title: "\(wt.taskTitle) · \(wt.branchName)",
                                    subtitle: "\(wt.botName) · \(wt.diffSummary)",
                                    badgeText: wt.status.label(lang),
                                    badgeColor: wt.status == .readyForReview ? PipiTokens.stateWarning : PipiTokens.soulPrimary,
                                    footer: {
                                        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                                            if let proof = store.proofBundle(for: wt.id) {
                                                Text("🛡️ \(proof.overallStatus.label(lang)) · \(proof.evidenceSummary)")
                                                    .font(PipiTokens.fontCaption.weight(.semibold))
                                                    .foregroundStyle(proof.overallStatus == .verified ? PipiTokens.stateSuccess : PipiTokens.stateWarning)
                                            }
                                            PipiActionButton(s.t("生成验证证据包 (Checks + Panel)", "Verify Proof Bundle"), systemImage: "checkmark.shield.fill", tone: .secondary, density: .mobile, fullWidth: true) {
                                                Task {
                                                    _ = await store.verifyWorktreeProof(sessionId: wt.id)
                                                    triggerHaptic(.success)
                                                }
                                            }
                                            if !wt.unifiedDiff.isEmpty {
                                                Text(String(wt.unifiedDiff.prefix(600)))
                                                    .font(PipiTokens.fontMonoSmall)
                                                    .foregroundStyle(PipiTokens.textSecondary)
                                                    .padding(8)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .background(PipiTokens.bgInset)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                            }
                                            TextField(s.t("输入修改意见打回给 Agent…", "Review comment to send back…"), text: $iosWorktreeFeedbackDraft)
                                                .textFieldStyle(.plain)
                                                .padding(10)
                                                .background(PipiTokens.bgInset)
                                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                                            HStack(spacing: PipiTokens.spacing8) {
                                                PipiActionButton(s.t("打回修改", "Send Back"), systemImage: "arrow.uturn.backward", tone: .secondary, density: .mobile, fullWidth: true) {
                                                    let fb = iosWorktreeFeedbackDraft
                                                    iosWorktreeFeedbackDraft = ""
                                                    Task {
                                                        await store.sendBackWorktreeFeedback(sessionId: wt.id, feedback: fb)
                                                        triggerHaptic(.medium)
                                                    }
                                                }
                                                PipiActionButton(s.t("合并清理", "Merge"), systemImage: "checkmark.circle.fill", tone: .primary, density: .mobile, fullWidth: true) {
                                                    _ = store.mergeWorktreeSession(sessionId: wt.id)
                                                    triggerHaptic(.success)
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
            } else {
                let summary = store.usageSummary
                ScrollView {
                    VStack(spacing: PipiTokens.spacing12) {
                        PipiListCard(
                            title: s.t("Token 与估算费用（仅统计提醒不拦截）", "Tokens & Est. Spend (Alert-Only)"),
                            subtitle: s.t("今日：\(summary.todayTokens) tokens（~$\(String(format: "%.3f", summary.todayCostUSD))） · 7日：\(summary.sevenDayTokens) tokens（~$\(String(format: "%.3f", summary.sevenDayCostUSD))）", "Today: \(summary.todayTokens) tok (~$\(String(format: "%.3f", summary.todayCostUSD))) · 7d: \(summary.sevenDayTokens) tok (~$\(String(format: "%.3f", summary.sevenDayCostUSD)))"),
                            badgeText: s.t("不阻断执行", "Non-Blocking"),
                            badgeColor: PipiTokens.stateSuccess
                        )

                        ForEach(store.routines) { rt in
                            PipiListCard(
                                title: rt.title.isEmpty ? rt.triggerKind.label(lang) : rt.title,
                                subtitle: "\(rt.triggerKind.label(lang)) · \(rt.scheduleBadge(lang))",
                                badgeText: rt.isEnabled ? s.enabled : s.disabled,
                                badgeColor: rt.isEnabled ? PipiTokens.soulPrimary : PipiTokens.textMuted,
                                footer: {
                                    PipiActionButton(s.t("立即触发运行", "Run Now"), systemImage: "play.fill", tone: .secondary, density: .mobile, fullWidth: true) {
                                        Task {
                                            await store.runRoutineNow(rt)
                                            triggerHaptic(.light)
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, PipiTokens.spacing16)
                    .padding(.bottom, PipiTokens.spacing24)
                }
            }
        }
    }

    private var iosModelFormFields: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            Picker(s.providerPreset, selection: $modelPreset) {
                ForEach(PipiLLMProviderKind.allCases) { kind in
                    Text(kind.localizedName(lang)).tag(kind)
                }
            }
            .onChange(of: modelPreset) { _, next in
                modelBaseURL = next.defaultBaseURL
                modelId = next.defaultModelId
            }

            SecureField(s.apiKeyPlaceholder, text: $modelApiKey)
                .textFieldStyle(.plain)
                .padding(PipiTokens.spacing12)
                .background(PipiTokens.bgInset)
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

            TextField(s.modelNameLabel, text: $modelId)
                .textFieldStyle(.plain)
                .padding(PipiTokens.spacing12)
                .background(PipiTokens.bgInset)
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

            TextField(s.baseUrlLabel, text: $modelBaseURL)
                .textFieldStyle(.plain)
                .font(PipiTokens.fontMono)
                .padding(PipiTokens.spacing12)
                .background(PipiTokens.bgInset)
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

            if let testResultText {
                Text(testResultText)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
            }
        }
    }

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

                    if tab == .tasks && !store.pendingDecisions.isEmpty {
                        Circle()
                            .fill(PipiTokens.stateError)
                            .frame(width: 7, height: 7)
                            .offset(x: 5, y: -1)
                    }
                }

                Text(tab.title(s))
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
