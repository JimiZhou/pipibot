// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
//
// Consumer-Grade Minimalist iOS Personal Assistant Experience:
// Inspired by warm-paper tactile surfaces, living procedural presence, fluid sheets,
// high-contrast conversation rhythm, live Board tasks, and ambient voice companionship.

import SwiftUI
import PipiBotKit
#if canImport(PhotosUI)
import PhotosUI
#endif

#if os(iOS)
import UIKit
#endif

public enum PipiIOSTab: String, CaseIterable, Sendable, Identifiable {
    case chat
    case tasks
    case bots
    case settings

    public var id: String { rawValue }

    public func title(_ s: PipiStrings) -> String {
        switch self {
        case .chat: return s.t("对话", "Chat")
        case .tasks: return s.t("任务", "Tasks")
        case .bots: return s.t("伙伴", "Agents")
        case .settings: return s.t("我的", "Me")
        }
    }

    public var iconName: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .tasks: return "checklist"
        case .bots: return "person.2"
        case .settings: return "slider.horizontal.3"
        }
    }

    public var selectedIconName: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .tasks: return "checklist"
        case .bots: return "person.2.fill"
        case .settings: return "slider.horizontal.3"
        }
    }
}

public struct PipiIOSCompanionRootView: View {
    @Bindable public var store: PipiAppStore

    @State private var selectedTab: PipiIOSTab = .chat
    @State private var isInGroupRoom: Bool = false
    @State private var draftInput: String = ""
    @State private var groupDraftInput: String = ""

    // Clean Modal Sheets (replaces triple-stacked headers & inline form clutter)
    @State private var showThreadsDrawer: Bool = false
    @State private var showBotSwitcher: Bool = false
    @State private var showVoiceSheet: Bool = false
    @State private var showTerminalSheet: Bool = false
    @State private var showNewBoardTaskSheet: Bool = false
    @State private var showAddBotSheet: Bool = false
    @State private var showAddModelSheet: Bool = false
    @State private var showAdvancedConnection: Bool = false
    #if canImport(PhotosUI)
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isRunningVisionOCR: Bool = false
    #endif

    // Tasks & Board State
    @State private var tasksSegment: Int = 0 // 0 = Needs You, 1 = Live Board
    @State private var boardChannelFilter: String? = nil
    @State private var newTaskTitle: String = ""
    @State private var newTaskChannel: String = "inbox"
    @State private var newTaskPriority: PipiBoardTaskPriority = .normal
    @State private var iosWorktreeFeedbackDraft: String = ""

    // Settings / Model Form State
    @State private var meshHubURLDraft: String = "http://127.0.0.1:4242"
    @State private var meshHubTokenDraft: String = ""
    @State private var ecoSkillURLDraft: String = ""
    @State private var modelPreset: PipiLLMProviderKind = .openai
    @State private var modelApiKey: String = ""
    @State private var modelBaseURL: String = PipiLLMProviderKind.openai.defaultBaseURL
    @State private var modelId: String = PipiLLMProviderKind.openai.defaultModelId

    public init(store: PipiAppStore) {
        self.store = store
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }
    private var activeAccent: Color { PipiTokens.color(for: store.activePersona.accent) }

    private var totalPendingAttentionCount: Int {
        store.pendingDecisions.count
            + store.boardNeedsYouThreads.count
            + store.worktreeSessions.filter { $0.status == .readyForReview }.count
            + store.blueprintEvolutionProposals.filter { $0.status == .pending }.count
    }

    private var activeGroup: PipiGroupChat? {
        store.groupChats.first(where: { $0.id == store.activeGroupChatId }) ?? store.sortedGroupChats.first
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            (selectedTab == .chat ? PipiTokens.bgCanvas : PipiTokens.bgWindowTray)
                .ignoresSafeArea()

            if !store.hasCompletedOnboarding {
                iosOnboardingView
            } else {
                mainConsumerShell
            }

            if showAddModelSheet {
                PipiFormSheet(
                    title: s.addModelProvider,
                    subtitle: s.t("连接任意兼容 OpenAI / Anthropic 的模型服务", "Connect any OpenAI or Anthropic compatible model"),
                    detent: .compact,
                    submitLabel: s.saveAndUse,
                    submitIcon: "checkmark",
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
        .sheet(isPresented: $showThreadsDrawer) {
            threadsAndRoomsSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBotSwitcher) {
            botSwitcherSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showVoiceSheet) {
            PipiIOSVoiceSheetView(
                store: store,
                onDismiss: { showVoiceSheet = false },
                onHaptic: triggerHaptic
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTerminalSheet) {
            PipiIOSTerminalSheetView(
                store: store,
                onDismiss: { showTerminalSheet = false },
                onHaptic: triggerHaptic
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showNewBoardTaskSheet) {
            newBoardTaskSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddBotSheet) {
            addBotCatalogSheet
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onOpenURL { url in
            if let action = PipiIOSDeepLinkRouter.parse(url) {
                if case .openVoice = action {
                    selectedTab = .chat
                    showVoiceSheet = true
                    triggerHaptic(.medium)
                } else {
                    PipiIOSDeepLinkRouter.apply(action, to: store, selectedTab: &selectedTab)
                    triggerHaptic(.medium)
                }
            }
        }
        #if canImport(PhotosUI)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            isRunningVisionOCR = true
            Task {
                defer {
                    isRunningVisionOCR = false
                    selectedPhotoItem = nil
                }
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    let ocr = await PipiOnDeviceNPUEngine.analyzeImageData(data)
                    let header = s.t("[本机 Apple Vision NPU 识图结果 · \(ocr.elapsedMs)ms]", "[On-Device Vision NPU · \(ocr.elapsedMs)ms]")
                    var snippet = header
                    if !ocr.recognizedText.isEmpty {
                        snippet += "\n\(ocr.recognizedText)"
                    }
                    if !ocr.barcodes.isEmpty {
                        snippet += "\nQR/条码: \(ocr.barcodes.joined(separator: ", "))"
                    }
                    if !ocr.sceneLabels.isEmpty {
                        snippet += "\n画面元素: \(ocr.sceneLabels.joined(separator: ", "))"
                    }
                    draftInput = draftInput.isEmpty ? snippet : "\(draftInput)\n\n\(snippet)"
                    triggerHaptic(.success)
                }
            }
        }
        #endif
    }

    // MARK: - 1. Serene First-Launch Onboarding (Warm Paper)

    private var iosOnboardingView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: PipiTokens.spacing24) {
                Spacer(minLength: 44)

                PipiAvatarView(engine: store.avatarEngine, size: 104, accentOverride: activeAccent)

                VStack(spacing: PipiTokens.spacing8) {
                    Text(s.onboardingWelcomeTitle)
                        .font(PipiTokens.fontHero)
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text(s.t("常驻你设备的私人 AI 伙伴，随时对话、语音和推进任务。", "Your private personal AI companion for chat, voice, and real work."))
                        .font(PipiTokens.fontBody)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    iosModelFormFields
                }
                .padding(PipiTokens.spacing20)
                .background(PipiTokens.bgCanvas, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(PipiTokens.sheetBorder, lineWidth: 1)
                )

                VStack(spacing: PipiTokens.spacing12) {
                    Button {
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
                    } label: {
                        Text(s.onboardingStartChatting)
                            .font(PipiTokens.fontSubheadline)
                            .foregroundStyle(PipiTokens.textInverse)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(PipiTokens.soulPrimary, in: Capsule())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))

                    Button(s.skipForNow) {
                        store.completeOnboarding()
                        triggerHaptic(.light)
                    }
                    .buttonStyle(.plain)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textMuted)
                }
            }
            .padding(.horizontal, PipiTokens.spacing24)
            .padding(.bottom, PipiTokens.spacing32)
        }
    }

    // MARK: - 2. Main Consumer Shell (Single Calm Top Bar + Floating Pill Dock)

    private var mainConsumerShell: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                minimalTopBar
                    .padding(.horizontal, PipiTokens.spacing16)
                    .padding(.top, 6)
                    .padding(.bottom, 8)

                Group {
                    switch selectedTab {
                    case .chat:
                        chatExperienceView
                    case .tasks:
                        tasksAndBoardView
                    case .bots:
                        companionsGalleryView
                    case .settings:
                        consumerProfileSettingsView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Floating Translucent Capsule Navigation Dock (Muse / Apple iOS Fluid craft)
            floatingTabDock
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
        }
    }

    private var minimalTopBar: some View {
        HStack(spacing: PipiTokens.spacing8) {
            if selectedTab == .chat {
                // Left: Borderless Apple-native Threads & Rooms Trigger
                Button {
                    triggerHaptic(.light)
                    showThreadsDrawer = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(PipiTokens.textPrimary)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.90))
                .accessibilityLabel(s.t("对话与群聊列表", "Conversations and rooms"))

                Spacer(minLength: 4)

                // Center: Borderless Companion Title & Subtle Chevron
                Button {
                    triggerHaptic(.light)
                    if isInGroupRoom {
                        showThreadsDrawer = true
                    } else {
                        showBotSwitcher = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isInGroupRoom, let grp = activeGroup {
                            Image(systemName: "person.2")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(PipiTokens.textSecondary)
                            Text(grp.title)
                                .font(PipiTokens.fontHeadline)
                                .tracking(PipiTokens.trackingHeadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                                .lineLimit(1)
                        } else {
                            PipiBotPersonaGlyph(persona: store.activePersona, size: 20, isSelected: true)
                            Text(store.activePersona.name(lang))
                                .font(PipiTokens.fontHeadline)
                                .tracking(PipiTokens.trackingHeadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .contentShape(Capsule())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))

                Spacer(minLength: 4)

                // Right: Borderless Voice Mode + Quick New Chat
                HStack(spacing: 2) {
                    Button {
                        triggerHaptic(.medium)
                        showVoiceSheet = true
                    } label: {
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(store.isVoiceCallActive ? PipiTokens.stateSuccess : PipiTokens.textPrimary)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.90))
                    .accessibilityLabel(s.t("语音伴随模式", "Voice companion"))

                    Button {
                        triggerHaptic(.light)
                        isInGroupRoom = false
                        _ = store.createConversation(for: store.activePersona.id, activate: true)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(PipiTokens.textPrimary)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.90))
                    .accessibilityLabel(s.newChat)
                }
            } else {
                // Clean Editorial Title for Tasks / Agents / Me
                Text(selectedTab.title(s))
                    .font(PipiTokens.fontTitle)
                    .tracking(PipiTokens.trackingTitle)
                    .foregroundStyle(PipiTokens.textPrimary)

                Spacer()

                if selectedTab == .tasks {
                    Button {
                        triggerHaptic(.light)
                        newTaskTitle = ""
                        newTaskChannel = boardChannelFilter ?? "inbox"
                        newTaskPriority = .normal
                        showNewBoardTaskSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PipiTokens.textInverse)
                            .frame(width: 32, height: 32)
                            .background(PipiTokens.soulPrimary, in: Circle())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                    .accessibilityLabel(s.t("新建任务", "New task"))
                } else if selectedTab == .bots {
                    Button {
                        triggerHaptic(.light)
                        showAddBotSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PipiTokens.textInverse)
                            .frame(width: 32, height: 32)
                            .background(PipiTokens.soulPrimary, in: Circle())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                    .accessibilityLabel(s.t("发现或新建伙伴", "Add companion"))
                }
            }
        }
        .frame(height: 40)
    }

    private var floatingTabDock: some View {
        HStack(spacing: 4) {
            ForEach(PipiIOSTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(PipiMotion.press) {
                        selectedTab = tab
                    }
                    triggerHaptic(.light)
                } label: {
                    HStack(spacing: 5) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: isSelected ? tab.selectedIconName : tab.iconName)
                                .font(.system(size: 15, weight: isSelected ? .medium : .regular))
                                .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textMuted)

                            if tab == .tasks && totalPendingAttentionCount > 0 {
                                Circle()
                                    .fill(PipiTokens.stateWarning)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 4, y: -2)
                            }
                        }

                        if isSelected {
                            Text(tab.title(s))
                                .font(PipiTokens.fontCaption.weight(.medium))
                                .foregroundStyle(PipiTokens.textPrimary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, isSelected ? 15 : 13)
                    .frame(height: 36)
                    .background(
                        isSelected ? PipiTokens.bgSurfaceHover : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.94))
                .accessibilityLabel(tab.title(s))
            }
        }
        .padding(4)
        .pipiLiquidGlassCapsule()
    }

    // MARK: - 3. Tab 1: Chat-First Minimalist Home (Linger x Grok Bot x Muse)

    private var chatExperienceView: some View {
        VStack(spacing: 0) {
            if isInGroupRoom, let group = activeGroup {
                iosGroupRoomStream(group: group)
            } else {
                iosDirectChatStream
            }
        }
        // Leave comfortable room for the floating capsule dock below
        .padding(.bottom, 64)
    }

    private var iosDirectChatStream: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: PipiTokens.spacing16) {
                        if let conv = store.activeConversation, !conv.messages.isEmpty {
                            ForEach(conv.messages) { msg in
                                iosDirectMessageRow(msg)
                                    .id(msg.id)
                            }
                            if store.isGeneratingReply, let status = store.generatingStatusText, !status.isEmpty {
                                HStack(spacing: 8) {
                                    PipiDotIndicator(vitality: .busy, color: PipiTokens.textMuted, size: 6)
                                    Text(status)
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(PipiTokens.textMuted)
                                        .lineLimit(2)
                                    Spacer()
                                }
                                .padding(.horizontal, 4)
                                .padding(.top, 2)
                            }
                        } else {
                            // Grok Bot x Muse Serene Empty Home
                            VStack(spacing: PipiTokens.spacing20) {
                                Spacer(minLength: 28)

                                PipiAvatarView(
                                    engine: store.avatarEngine,
                                    size: 88,
                                    accentOverride: activeAccent,
                                    personaAccent: store.activePersona.accent,
                                    motif: PipiPersonaMotif.resolve(for: store.activePersona)
                                )

                                VStack(spacing: 6) {
                                    Text(timeOfDayGreeting)
                                        .font(PipiTokens.fontTitle)
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Text(store.activePersona.greeting(lang))
                                        .font(PipiTokens.fontBody)
                                        .foregroundStyle(PipiTokens.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .lineSpacing(4)
                                        .padding(.horizontal, PipiTokens.spacing12)
                                }

                                VStack(spacing: 8) {
                                    ForEach(store.activePersona.starterPrompts(lang).prefix(3), id: \.self) { prompt in
                                        Button {
                                            triggerHaptic(.light)
                                            Task { await store.sendPersonalMessage(prompt) }
                                        } label: {
                                            HStack(spacing: 10) {
                                                Text(prompt)
                                                    .font(PipiTokens.fontCaption)
                                                    .foregroundStyle(PipiTokens.textPrimary)
                                                    .multilineTextAlignment(.leading)
                                                    .lineLimit(2)
                                                Spacer()
                                                Image(systemName: "arrow.up.right")
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(PipiTokens.textMuted)
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 12)
                                            .background(PipiTokens.bgCanvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .stroke(PipiTokens.sheetBorder, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.98))
                                    }
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    .padding(.horizontal, PipiTokens.spacing16)
                    .padding(.top, PipiTokens.spacing8)
                    .padding(.bottom, PipiTokens.spacing16)
                }
                .onChange(of: store.activeConversation?.messages.count ?? 0) { _, _ in
                    if let lastId = store.activeConversation?.messages.last?.id {
                        withAnimation(PipiMotion.open) {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            iosFloatingComposer(
                text: $draftInput,
                placeholder: s.t("给 \(store.activePersona.name(lang)) 发消息…", "Message \(store.activePersona.name(lang))…"),
                isGenerating: store.isGeneratingReply,
                onSend: {
                    let clean = draftInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !clean.isEmpty else { return }
                    draftInput = ""
                    triggerHaptic(.light)
                    Task { await store.sendPersonalMessage(clean) }
                },
                onStop: {
                    store.stopGenerating()
                    triggerHaptic(.medium)
                }
            )
            .padding(.horizontal, PipiTokens.spacing12)
            .padding(.bottom, 8)
        }
    }

    private func iosDirectMessageRow(_ msg: PipiChatMessage) -> some View {
        Group {
            if msg.role == .user {
                HStack {
                    Spacer(minLength: 52)
                    Text(msg.content)
                        .font(PipiTokens.fontBody)
                        .foregroundStyle(PipiTokens.userBubbleFg)
                        .lineSpacing(4.5)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(PipiTokens.userBubbleBg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            } else {
                // Apple / Claude Editorial Borderless Assistant Stream (zero boxed bubble clutter)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        PipiBotPersonaGlyph(persona: store.activePersona, size: 20, isSelected: true)
                        Text(store.activePersona.name(lang))
                            .font(PipiTokens.fontMicro.weight(.medium))
                            .foregroundStyle(PipiTokens.textMuted)
                    }

                    iosFormattedMessageText(msg.content.isEmpty ? "…" : msg.content)
                        .padding(.leading, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
        }
    }

    private func iosGroupRoomStream(group: PipiGroupChat) -> some View {
        let lanes = store.activeLanes(forGroup: group.id)
        let members = group.participantPersonaIds.compactMap { pid in store.personas.first(where: { $0.id == pid }) }
        let msgs = group.messages(forTopic: group.effectiveActiveTopicId)

        return VStack(spacing: 0) {
            if !lanes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(lanes) { lane in
                            HStack(spacing: 6) {
                                PipiDotIndicator(vitality: .busy, color: PipiTokens.textPrimary, size: 5.5)
                                Text(lane.personaName)
                                    .font(PipiTokens.fontMicro.weight(.medium))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Button {
                                    store.stopGroupLane(lane.runId)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(PipiTokens.textMuted)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(PipiTokens.bgCanvas, in: Capsule())
                            .overlay(Capsule().stroke(PipiTokens.sheetBorder, lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, PipiTokens.spacing16)
                    .padding(.bottom, 8)
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: PipiTokens.spacing12) {
                    if msgs.isEmpty {
                        Text(s.t("点一下底部 @伙伴 即可同时委派多位助手一起协作。", "Tap any @companion below to collaborate in parallel."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 36)
                    } else {
                        ForEach(msgs) { msg in
                            iosGroupMessageRow(msg)
                        }
                    }
                }
                .padding(.horizontal, PipiTokens.spacing16)
                .padding(.top, PipiTokens.spacing8)
                .padding(.bottom, PipiTokens.spacing16)
            }

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
                                Text("@\(bot.name(lang))")
                                    .font(PipiTokens.fontMicro.weight(.medium))
                                    .foregroundStyle(PipiTokens.textSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(PipiTokens.bgCanvas, in: Capsule())
                                    .overlay(Capsule().stroke(PipiTokens.sheetBorder, lineWidth: 1))
                            }
                            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.95))
                        }
                    }
                    .padding(.horizontal, PipiTokens.spacing16)
                    .padding(.bottom, 6)
                }
            }

            iosFloatingComposer(
                text: $groupDraftInput,
                placeholder: s.t("在「\(group.title)」里发消息…", "Message \(group.title)…"),
                isGenerating: false,
                onSend: {
                    let clean = groupDraftInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !clean.isEmpty else { return }
                    groupDraftInput = ""
                    triggerHaptic(.light)
                    Task {
                        await store.sendGroupMessage(clean, toGroupId: group.id, topicId: group.effectiveActiveTopicId)
                    }
                },
                onStop: {}
            )
            .padding(.horizontal, PipiTokens.spacing12)
            .padding(.bottom, 8)
        }
    }

    private func iosGroupMessageRow(_ msg: PipiGroupMessage) -> some View {
        let isUser: Bool = {
            if case .user = msg.senderKind { return true }
            return false
        }()
        if isUser {
            return AnyView(
                HStack {
                    Spacer(minLength: 48)
                    Text(msg.content)
                        .font(PipiTokens.fontBody)
                        .foregroundStyle(PipiTokens.userBubbleFg)
                        .lineSpacing(4.5)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 11)
                        .background(PipiTokens.userBubbleBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            )
        }
        let bot: PipiBotPersona? = {
            if case .bot(let pid) = msg.senderKind {
                return store.personas.first(where: { $0.id == pid })
            }
            return nil
        }()
        let senderName = bot?.name(lang) ?? s.appName
        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    if let bot {
                        PipiBotPersonaGlyph(persona: bot, size: 20, isSelected: true)
                    }
                    Text(senderName)
                        .font(PipiTokens.fontMicro.weight(.medium))
                        .foregroundStyle(PipiTokens.textMuted)
                }
                iosFormattedMessageText(msg.content.isEmpty ? "…" : msg.content)
                    .padding(.leading, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        )
    }

    /// Linger-inspired Tactile Floating Pill Composer
    private func iosFloatingComposer(
        text: Binding<String>,
        placeholder: String,
        isGenerating: Bool,
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) -> some View {
        let canSend = !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button {
                    isInGroupRoom = false
                    _ = store.createConversation(for: store.activePersona.id, activate: true)
                } label: {
                    Label(s.newChat, systemImage: "square.and.pencil")
                }
                Button {
                    newTaskTitle = text.wrappedValue
                    newTaskChannel = "inbox"
                    showNewBoardTaskSheet = true
                } label: {
                    Label(s.t("发布到任务板", "Post to Board"), systemImage: "rectangle.3.group")
                }
                Button {
                    if let clip = PipiOnDeviceNPUEngine.readClipboardText()?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
                        text.wrappedValue = text.wrappedValue.isEmpty ? clip : "\(text.wrappedValue)\n\(clip)"
                        triggerHaptic(.light)
                    }
                } label: {
                    Label(s.t("粘贴剪贴板内容", "Paste clipboard"), systemImage: "doc.on.clipboard")
                }
                Button {
                    showThreadsDrawer = true
                } label: {
                    Label(s.t("切换对话或群聊", "Switch thread or room"), systemImage: "bubble.left.and.bubble.right")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PipiTokens.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(PipiTokens.bgSurface, in: Circle())
            }
            .pipiPlainMenu()
            .fixedSize()
            .padding(.bottom, 3)

            #if canImport(PhotosUI)
            let ocrBusy = isRunningVisionOCR
            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                Image(systemName: ocrBusy ? "viewfinder.circle.fill" : "camera.viewfinder")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(ocrBusy ? PipiTokens.soulPrimary : PipiTokens.textSecondary)
                    .frame(width: 32, height: 34)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 3)
            .accessibilityLabel(s.t("本机 NPU 识图识字", "On-device NPU photo OCR"))
            #endif

            TextField(placeholder, text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(PipiTokens.fontBody)
                .foregroundStyle(PipiTokens.textPrimary)
                .lineLimit(1...5)
                .padding(.vertical, 9)

            if isGenerating {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(PipiTokens.textInverse)
                        .frame(width: 34, height: 34)
                        .background(PipiTokens.soulPrimary, in: Circle())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.90))
                .padding(.bottom, 3)
            } else if canSend {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PipiTokens.textInverse)
                        .frame(width: 34, height: 34)
                        .background(PipiTokens.soulPrimary, in: Circle())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.90))
                .padding(.bottom, 3)
            } else {
                Button {
                    triggerHaptic(.medium)
                    showVoiceSheet = true
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(PipiTokens.textInverse)
                        .frame(width: 34, height: 34)
                        .background(PipiTokens.soulPrimary, in: Circle())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.90))
                .padding(.bottom, 3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .pipiLiquidGlassChrome(cornerRadius: 24)
    }

    // MARK: - 4. Tab 2: Tasks (Fluid Swipe Approvals + Live Board Engine)

    private var tasksAndBoardView: some View {
        VStack(spacing: PipiTokens.spacing12) {
            // Calm 2-segment capsule switcher
            HStack(spacing: 4) {
                segmentPill(
                    title: totalPendingAttentionCount > 0
                        ? s.t("待确认 \(totalPendingAttentionCount)", "Needs you \(totalPendingAttentionCount)")
                        : s.t("待确认", "Needs you"),
                    isSelected: tasksSegment == 0
                ) {
                    withAnimation(PipiMotion.press) { tasksSegment = 0 }
                    triggerHaptic(.light)
                }

                segmentPill(
                    title: s.t("任务板 \(store.boardThreads.count)", "Board \(store.boardThreads.count)"),
                    isSelected: tasksSegment == 1
                ) {
                    withAnimation(PipiMotion.press) { tasksSegment = 1 }
                    triggerHaptic(.light)
                }
            }
            .padding(4)
            .background(PipiTokens.bgSurface, in: Capsule())
            .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
            .padding(.horizontal, PipiTokens.spacing16)

            if tasksSegment == 0 {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: PipiTokens.spacing16) {
                        NeedsYouSwipeDeckView(store: store, onHaptic: triggerHaptic)

                        // Board threads flagged as Needs You
                        if !store.boardNeedsYouThreads.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(s.t("任务板待拍板", "Board decisions"))
                                    .font(PipiTokens.fontSubheadline)
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .padding(.horizontal, PipiTokens.spacing16)

                                ForEach(store.boardNeedsYouThreads) { thread in
                                    iosBoardThreadCard(thread)
                                        .padding(.horizontal, PipiTokens.spacing16)
                                }
                            }
                        }

                        // Pending Worktree Code Reviews (consumer-friendly copy)
                        let pendingWorktrees = store.worktreeSessions.filter { $0.status == .readyForReview }
                        if !pendingWorktrees.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(s.t("代码改动待确认", "Code changes ready"))
                                    .font(PipiTokens.fontSubheadline)
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .padding(.horizontal, PipiTokens.spacing16)

                                ForEach(pendingWorktrees) { wt in
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack {
                                            Text(wt.taskTitle)
                                                .font(PipiTokens.fontSubheadline)
                                                .foregroundStyle(PipiTokens.textPrimary)
                                            Spacer()
                                            Text(wt.diffSummary)
                                                .font(PipiTokens.fontMonoSmall)
                                                .foregroundStyle(PipiTokens.textMuted)
                                        }
                                        Text("\(wt.botName) · \(wt.branchName)")
                                            .font(PipiTokens.fontCaption)
                                            .foregroundStyle(PipiTokens.textSecondary)

                                        HStack(spacing: 8) {
                                            Button {
                                                _ = store.mergeWorktreeSession(sessionId: wt.id)
                                                triggerHaptic(.success)
                                            } label: {
                                                Text(s.t("合并改动", "Merge"))
                                                    .font(PipiTokens.fontCaption.weight(.medium))
                                                    .foregroundStyle(PipiTokens.textInverse)
                                                    .frame(maxWidth: .infinity)
                                                    .frame(height: 38)
                                                    .background(PipiTokens.soulPrimary, in: Capsule())
                                            }
                                            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))

                                            Button {
                                                Task {
                                                    await store.sendBackWorktreeFeedback(sessionId: wt.id, feedback: iosWorktreeFeedbackDraft.isEmpty ? "请再自检优化一下" : iosWorktreeFeedbackDraft)
                                                    triggerHaptic(.light)
                                                }
                                            } label: {
                                                Text(s.t("继续优化", "Revise"))
                                                    .font(PipiTokens.fontCaption.weight(.medium))
                                                    .foregroundStyle(PipiTokens.textPrimary)
                                                    .frame(maxWidth: .infinity)
                                                    .frame(height: 38)
                                                    .background(PipiTokens.bgSurface, in: Capsule())
                                                    .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                                            }
                                            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                                        }
                                    }
                                    .padding(PipiTokens.spacing16)
                                    .background(PipiTokens.bgCanvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PipiTokens.sheetBorder, lineWidth: 1))
                                    .padding(.horizontal, PipiTokens.spacing16)
                                }
                            }
                        }

                        // Pending Blueprint Proposals
                        let pendingProps = store.blueprintEvolutionProposals.filter { $0.status == .pending }
                        if !pendingProps.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(s.t("助手习惯优化建议", "Assistant improvements"))
                                    .font(PipiTokens.fontSubheadline)
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .padding(.horizontal, PipiTokens.spacing16)

                                ForEach(pendingProps) { prop in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(prop.botName)
                                            .font(PipiTokens.fontCaption.weight(.medium))
                                            .foregroundStyle(PipiTokens.textSecondary)
                                        Text(prop.rationale)
                                            .font(PipiTokens.fontBody)
                                            .foregroundStyle(PipiTokens.textPrimary)
                                        HStack(spacing: 8) {
                                            Button {
                                                store.approveBlueprintEvolutionProposal(id: prop.id)
                                                triggerHaptic(.success)
                                            } label: {
                                                Text(s.t("采纳", "Adopt"))
                                                    .font(PipiTokens.fontCaption.weight(.medium))
                                                    .foregroundStyle(PipiTokens.textInverse)
                                                    .frame(maxWidth: .infinity)
                                                    .frame(height: 38)
                                                    .background(PipiTokens.soulPrimary, in: Capsule())
                                            }
                                            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))

                                            Button {
                                                store.rejectBlueprintEvolutionProposal(id: prop.id)
                                                triggerHaptic(.light)
                                            } label: {
                                                Text(s.t("暂不", "Skip"))
                                                    .font(PipiTokens.fontCaption.weight(.medium))
                                                    .foregroundStyle(PipiTokens.textSecondary)
                                                    .frame(maxWidth: .infinity)
                                                    .frame(height: 38)
                                                    .background(PipiTokens.bgSurface, in: Capsule())
                                            }
                                            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                                        }
                                    }
                                    .padding(PipiTokens.spacing16)
                                    .background(PipiTokens.bgCanvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PipiTokens.sheetBorder, lineWidth: 1))
                                    .padding(.horizontal, PipiTokens.spacing16)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 88)
                }
            } else {
                // Live Board View (Phase 2/3 Engine)
                VStack(spacing: PipiTokens.spacing12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            boardFilterChip(slug: nil, title: s.t("全部", "All"))
                            ForEach(store.boardChannels) { ch in
                                boardFilterChip(slug: ch.slug, title: "#\(ch.slug)")
                            }
                        }
                        .padding(.horizontal, PipiTokens.spacing16)
                    }

                    let threads = boardChannelFilter == nil
                        ? store.boardThreads
                        : store.boardThreads.filter { $0.channelSlug == boardChannelFilter }

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            if threads.isEmpty {
                                VStack(spacing: 10) {
                                    Text(s.t("当前频道暂无任务", "No tasks in this channel"))
                                        .font(PipiTokens.fontSubheadline)
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Text(s.t("点右上角 + 发布一条任务，Mac 与远程节点上的助手会自动认领推进。", "Tap + above to post a task for your agents to claim."))
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(PipiTokens.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 36)
                                .padding(.horizontal, PipiTokens.spacing20)
                                .background(PipiTokens.bgCanvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PipiTokens.sheetBorder, lineWidth: 1))
                            } else {
                                ForEach(threads) { thread in
                                    iosBoardThreadCard(thread)
                                }
                            }
                        }
                        .padding(.horizontal, PipiTokens.spacing16)
                        .padding(.bottom, 88)
                    }
                }
            }
        }
    }

    private func iosBoardThreadCard(_ thread: PipiBoardThread) -> some View {
        let ownerActor = PipiBoardActorRef(id: "human:ios", name: s.t("我", "Owner"), kind: .human)
        let activeBot = PipiBoardActorRef(id: "bot:\(store.activePersona.id)", name: store.activePersona.name(lang), kind: .bot)
        let dotColor: Color = {
            switch thread.status {
            case .claimed: return PipiTokens.soulPrimary
            case .needsYou, .blocked: return PipiTokens.stateWarning
            case .done: return PipiTokens.stateSuccess
            default: return PipiTokens.textMuted
            }
        }()
        let statusName: String = {
            switch thread.status {
            case .open: return s.t("待认领", "Open")
            case .claimed: return s.t("进行中", "In progress")
            case .blocked: return s.t("已阻塞", "Blocked")
            case .needsYou: return s.t("待确认", "Needs you")
            case .done: return s.t("已完成", "Done")
            case .cancelled: return s.t("已取消", "Cancelled")
            }
        }()

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("#\(thread.channelSlug)")
                    .font(PipiTokens.fontMonoSmall)
                    .foregroundStyle(PipiTokens.textMuted)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(dotColor).frame(width: 6, height: 6)
                    Text(statusName)
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textSecondary)
                }
            }

            Text(thread.title)
                .font(PipiTokens.fontSubheadline)
                .foregroundStyle(PipiTokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let claim = thread.claim, thread.status == .claimed {
                let mins = PipiBoardEngine.parseISO(claim.expiresAt).map { max(1, Int(($0.timeIntervalSinceNow + 59) / 60)) } ?? 15
                Text(s.t("\(claim.actor.name) 执行中 · 租约剩余 \(mins)m", "\(claim.actor.name) · \(mins)m left"))
                    .font(PipiTokens.fontCaption)
                    .monospacedDigit()
                    .foregroundStyle(PipiTokens.textSecondary)
            } else if let latestMsg = thread.messages.last?.body, !latestMsg.isEmpty {
                Text(latestMsg)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .lineLimit(2)
            }

            if thread.status != .done && thread.status != .cancelled && thread.status != .blocked {
                HStack(spacing: 8) {
                    if thread.status == .open {
                        Button {
                            _ = store.claimBoardTask(threadId: thread.id, actor: activeBot)
                            triggerHaptic(.light)
                        } label: {
                            Text(s.t("派给 \(store.activePersona.name(lang))", "Assign"))
                                .font(PipiTokens.fontCaption.weight(.medium))
                                .foregroundStyle(PipiTokens.textPrimary)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(PipiTokens.bgSurface, in: Capsule())
                                .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.95))
                    }

                    Button {
                        _ = store.completeBoardTask(
                            threadId: thread.id,
                            actor: thread.claim?.actor ?? ownerActor,
                            summary: s.t("已在 iPhone 端确认完成。", "Completed from iPhone."),
                            leaseToken: thread.claim?.leaseToken
                        )
                        triggerHaptic(.success)
                    } label: {
                        Text(s.t("标记完成", "Done"))
                            .font(PipiTokens.fontCaption.weight(.medium))
                            .foregroundStyle(PipiTokens.textInverse)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(PipiTokens.soulPrimary, in: Capsule())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.95))

                    Spacer()
                }
            }
        }
        .padding(PipiTokens.spacing16)
        .background(PipiTokens.bgCanvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(PipiTokens.sheetBorder, lineWidth: 1)
        )
    }

    // MARK: - 5. Tab 3: Companions Gallery (Consumer-Clean, Zero DevOps Jargon)

    private var companionsGalleryView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                // Quiet 1-line device presence pill
                let onlineNodes = store.meshHubClient.nodes.filter(\.isOnline).count
                HStack(spacing: 8) {
                    Circle()
                        .fill(PipiTokens.stateSuccess)
                        .frame(width: 7, height: 7)
                    Text(
                        onlineNodes > 0
                            ? s.t("Mac 与 \(onlineNodes) 台设备在线协同", "Mac + \(onlineNodes) node(s) online")
                            : s.t("本机私人助手已就绪", "Personal assistant ready")
                    )
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                    Spacer()
                    Button {
                        Task { _ = await store.refreshMeshNodes() }
                        triggerHaptic(.light)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(PipiTokens.bgCanvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PipiTokens.sheetBorder, lineWidth: 1))

                // Companion Cards
                VStack(spacing: 12) {
                    ForEach(store.personas) { persona in
                        let isSelected = store.activePersona.id == persona.id
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                PipiBotPersonaGlyph(persona: persona, size: 42, isSelected: isSelected)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(persona.name(lang))
                                            .font(PipiTokens.fontSubheadline)
                                            .foregroundStyle(PipiTokens.textPrimary)
                                        if isSelected {
                                            Circle()
                                                .fill(PipiTokens.stateSuccess)
                                                .frame(width: 6, height: 6)
                                        }
                                    }
                                    Text(persona.role(lang))
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(PipiTokens.textSecondary)
                                        .lineLimit(2)
                                }
                                Spacer()
                            }

                            HStack(spacing: 8) {
                                Button {
                                    store.selectPersona(persona.id)
                                    isInGroupRoom = false
                                    selectedTab = .chat
                                    triggerHaptic(.light)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "bubble.left")
                                            .font(.system(size: 12, weight: .medium))
                                        Text(s.t("发消息", "Chat"))
                                            .font(PipiTokens.fontCaption.weight(.medium))
                                    }
                                    .foregroundStyle(isSelected ? PipiTokens.textInverse : PipiTokens.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(isSelected ? PipiTokens.soulPrimary : PipiTokens.bgSurface, in: Capsule())
                                    .overlay(Capsule().stroke(isSelected ? Color.clear : PipiTokens.borderSubtle, lineWidth: 1))
                                }
                                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))

                                Button {
                                    store.selectPersona(persona.id)
                                    triggerHaptic(.medium)
                                    showVoiceSheet = true
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 12, weight: .medium))
                                        Text(s.t("语音聊", "Voice"))
                                            .font(PipiTokens.fontCaption.weight(.medium))
                                    }
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(PipiTokens.bgSurface, in: Capsule())
                                    .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                                }
                                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                            }
                        }
                        .padding(PipiTokens.spacing16)
                        .background(PipiTokens.bgCanvas, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(PipiTokens.sheetBorder, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, PipiTokens.spacing16)
            .padding(.top, 4)
            .padding(.bottom, 88)
        }
    }

    // MARK: - 6. Tab 4: Clean Consumer Settings (Advanced Dev Controls Tucked Away)

    private var consumerProfileSettingsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                // Appearance & Language Group
                settingsCardGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(s.appearanceSectionTitle)
                            .font(PipiTokens.fontSubheadline)
                            .foregroundStyle(PipiTokens.textPrimary)
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
                    .padding(PipiTokens.spacing16)

                    Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1).padding(.leading, 16)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(s.languageSectionTitle)
                            .font(PipiTokens.fontSubheadline)
                            .foregroundStyle(PipiTokens.textPrimary)
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
                    .padding(PipiTokens.spacing16)
                }

                // On-Device Apple Neural Engine & Mobile Hardware Capabilities Card
                let npu = PipiOnDeviceNPUEngine.currentProfile()
                settingsCardGroup {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.t("端侧 NPU 与本机能力", "On-device NPU & hardware"))
                                .font(PipiTokens.fontSubheadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text(s.t(
                                "\(npu.platform) · \(String(format: "%.0f", npu.physicalMemoryGB)) GB 内存 · \(npu.recommendedTier.label(lang))",
                                "\(npu.platform) · \(String(format: "%.0f", npu.physicalMemoryGB)) GB RAM · \(npu.recommendedTier.label(lang))"
                            ))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                        }
                        Spacer()
                        Circle()
                            .fill(npu.recommendedTier == .cloudOffloadRecommended ? PipiTokens.stateWarning : PipiTokens.stateSuccess)
                            .frame(width: 7, height: 7)
                    }
                    .padding(PipiTokens.spacing16)

                    Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1).padding(.leading, 16)

                    VStack(alignment: .leading, spacing: 8) {
                        npuCapabilityRow(
                            title: s.t("端侧语音识别与回声消除", "Neural Speech & Hardware AEC"),
                            ready: npu.supportsOnDeviceSpeechNPU
                        )
                        npuCapabilityRow(
                            title: s.t("Apple Vision NPU 识字/扫码", "Apple Vision NPU OCR & QR"),
                            ready: npu.supportsVisionNPU
                        )
                        npuCapabilityRow(
                            title: s.t("端侧语义检索与实体理解", "NaturalLanguage NPU Recall"),
                            ready: npu.supportsNaturalLanguageNPU
                        )
                        npuCapabilityRow(
                            title: s.t("内置 WebKit 网页 CUA 浏览", "In-App WebKit Browser CUA"),
                            ready: true
                        )
                        npuCapabilityRow(
                            title: s.t("助手沙箱执行引擎（POSIX + JSC）", "Agent Sandbox Runtime (POSIX + JSC)"),
                            ready: true
                        )
                        if npu.supportsAppleFoundationModels {
                            npuCapabilityRow(
                                title: s.t("Apple Foundation Models 端侧大模型", "Apple Intelligence On-Device LLM"),
                                ready: true
                            )
                        }
                    }
                    .padding(PipiTokens.spacing16)

                    Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1).padding(.leading, 16)

                    Button {
                        showTerminalSheet = true
                        triggerHaptic(.light)
                    } label: {
                        HStack {
                            Text(s.t("查看助手沙箱执行记录", "Agent sandbox activity"))
                                .font(PipiTokens.fontSubheadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                            Spacer()
                            if !PipiMobileTerminalLog.shared.entries.isEmpty {
                                Text("\(PipiMobileTerminalLog.shared.entries.count)")
                                    .font(PipiTokens.fontMicro)
                                    .monospacedDigit()
                                    .foregroundStyle(PipiTokens.textMuted)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                        .padding(PipiTokens.spacing16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // AI Engine & Today Usage
                settingsCardGroup {
                    Button {
                        showAddModelSheet = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.settingsModels)
                                    .font(PipiTokens.fontSubheadline)
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Text(store.hasConfiguredEngine ? store.activeEngineDisplayLabel() : s.engineStatusUnconfigured)
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textSecondary)
                            }
                            Spacer()
                            Text(s.t("配置", "Configure"))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textMuted)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                        .padding(PipiTokens.spacing16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1).padding(.leading, 16)

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.t("今日用量估算", "Today's usage"))
                                .font(PipiTokens.fontSubheadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text("\(store.usageSummary.todayTokens) tokens")
                                .font(PipiTokens.fontCaption)
                                .monospacedDigit()
                                .foregroundStyle(PipiTokens.textSecondary)
                        }
                        Spacer()
                        Text("$\(String(format: "%.3f", store.usageSummary.todayCostUSD))")
                            .font(PipiTokens.fontMonoSmall)
                            .monospacedDigit()
                            .foregroundStyle(PipiTokens.textPrimary)
                    }
                    .padding(PipiTokens.spacing16)
                }

                // Sync & Collapsible Advanced Connection
                settingsCardGroup {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.companionSyncToggleTitle)
                                .font(PipiTokens.fontSubheadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text(store.companionSyncEnabled ? store.daemonEndpoint : s.companionSyncToggleDesc)
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { store.companionSyncEnabled },
                            set: { store.setCompanionSyncEnabled($0) }
                        ))
                        .labelsHidden()
                    }
                    .padding(PipiTokens.spacing16)

                    Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1).padding(.leading, 16)

                    Button {
                        withAnimation(PipiMotion.open) {
                            showAdvancedConnection.toggle()
                        }
                    } label: {
                        HStack {
                            Text(s.t("多机节点与扩展技能", "Multi-host & skills"))
                                .font(PipiTokens.fontSubheadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                            Spacer()
                            Image(systemName: showAdvancedConnection ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                        .padding(PipiTokens.spacing16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showAdvancedConnection {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("http://127.0.0.1:4242", text: $meshHubURLDraft)
                                .textFieldStyle(.plain)
                                .font(PipiTokens.fontCaption)
                                .padding(10)
                                .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            SecureField(s.t("可选 Hub Token", "Optional Hub Token"), text: $meshHubTokenDraft)
                                .textFieldStyle(.plain)
                                .font(PipiTokens.fontCaption)
                                .padding(10)
                                .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Button {
                                Task {
                                    await store.connectMeshHub(url: meshHubURLDraft, token: meshHubTokenDraft)
                                    triggerHaptic(.success)
                                }
                            } label: {
                                Text(s.t("连接节点 Hub", "Connect Hub"))
                                    .font(PipiTokens.fontCaption.weight(.medium))
                                    .foregroundStyle(PipiTokens.textInverse)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(PipiTokens.soulPrimary, in: Capsule())
                            }
                            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))

                            TextField(s.t("粘贴社区 SKILL.md 链接", "Paste SKILL.md URL"), text: $ecoSkillURLDraft)
                                .textFieldStyle(.plain)
                                .font(PipiTokens.fontCaption)
                                .padding(10)
                                .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Button {
                                let src = ecoSkillURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !src.isEmpty else { return }
                                ecoSkillURLDraft = ""
                                Task {
                                    _ = await store.installCommunitySkill(source: src)
                                    triggerHaptic(.success)
                                }
                            } label: {
                                Text(s.t("安装技能包", "Install skill"))
                                    .font(PipiTokens.fontCaption.weight(.medium))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(PipiTokens.bgSurface, in: Capsule())
                                    .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                            }
                            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                        }
                        .padding(.horizontal, PipiTokens.spacing16)
                        .padding(.bottom, PipiTokens.spacing16)
                    }
                }
            }
            .padding(.horizontal, PipiTokens.spacing16)
            .padding(.top, 4)
            .padding(.bottom, 88)
        }
    }

    // MARK: - 7. Clean Modal Sheets (Threads Drawer, Bot Switcher, New Board Task, Add Bot)

    private var threadsAndRoomsSheet: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            HStack {
                Text(s.t("对话与协作群", "Threads & Rooms"))
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                Spacer()
                Button {
                    isInGroupRoom = false
                    _ = store.createConversation(for: store.activePersona.id, activate: true)
                    showThreadsDrawer = false
                    triggerHaptic(.light)
                } label: {
                    Text(s.t("+ 新对话", "+ New"))
                        .font(PipiTokens.fontCaption.weight(.medium))
                        .foregroundStyle(PipiTokens.textInverse)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(PipiTokens.soulPrimary, in: Capsule())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.95))
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    // Group Rooms
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(s.t("多助手协作群", "Rooms"))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textMuted)
                            Spacer()
                            Button(s.t("新建群", "New room")) {
                                let ids = Array(store.personas.prefix(4).map(\.id))
                                let created = store.createGroupChat(
                                    title: s.t("协同工作群", "Team Room"),
                                    participantPersonaIds: ids.isEmpty ? [store.activePersona.id] : ids,
                                    swarmMode: .mentionOnly
                                )
                                store.selectGroupChat(created.id)
                                isInGroupRoom = true
                                showThreadsDrawer = false
                                triggerHaptic(.light)
                            }
                            .buttonStyle(.plain)
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textSecondary)
                        }

                        ForEach(store.sortedGroupChats.prefix(6)) { grp in
                            let selected = isInGroupRoom && activeGroup?.id == grp.id
                            Button {
                                store.selectGroupChat(grp.id)
                                isInGroupRoom = true
                                showThreadsDrawer = false
                                triggerHaptic(.light)
                            } label: {
                                HStack {
                                    Image(systemName: "person.2")
                                        .font(.system(size: 13))
                                        .foregroundStyle(PipiTokens.textSecondary)
                                    Text(grp.title)
                                        .font(PipiTokens.fontSubheadline)
                                        .foregroundStyle(PipiTokens.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(selected ? PipiTokens.bgSurfaceHover : PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Recent 1v1 Conversations
                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.t("最近对话", "Recent chats"))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textMuted)

                        ForEach(store.conversations.filter { !$0.isArchived }.sorted { $0.updatedAt > $1.updatedAt }.prefix(12)) { conv in
                            let selected = !isInGroupRoom && conv.id == store.activeConversationId
                            Button {
                                store.selectConversation(conv.id)
                                isInGroupRoom = false
                                showThreadsDrawer = false
                                triggerHaptic(.light)
                            } label: {
                                HStack {
                                    Text(conv.title)
                                        .font(PipiTokens.fontSubheadline)
                                        .foregroundStyle(PipiTokens.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(selected ? PipiTokens.bgSurfaceHover : PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(PipiTokens.spacing20)
        .background(PipiTokens.bgCanvas.ignoresSafeArea())
    }

    private var botSwitcherSheet: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            Text(s.t("切换当前助手", "Switch companion"))
                .font(PipiTokens.fontHeadline)
                .foregroundStyle(PipiTokens.textPrimary)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(store.personas) { persona in
                        let selected = store.activePersona.id == persona.id
                        Button {
                            store.selectPersona(persona.id)
                            isInGroupRoom = false
                            showBotSwitcher = false
                            triggerHaptic(.light)
                        } label: {
                            HStack(spacing: 12) {
                                PipiBotPersonaGlyph(persona: persona, size: 36, isSelected: selected)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(persona.name(lang))
                                        .font(PipiTokens.fontSubheadline)
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Text(persona.role(lang))
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(PipiTokens.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                }
                            }
                            .padding(12)
                            .background(selected ? PipiTokens.bgSurfaceHover : PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(PipiTokens.spacing20)
        .background(PipiTokens.bgCanvas.ignoresSafeArea())
    }

    private var newBoardTaskSheet: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            Text(s.t("发布任务到看板", "Post task to Board"))
                .font(PipiTokens.fontHeadline)
                .foregroundStyle(PipiTokens.textPrimary)

            HStack(spacing: 8) {
                ForEach(store.boardChannels.prefix(4)) { ch in
                    let selected = newTaskChannel == ch.slug
                    Button {
                        newTaskChannel = ch.slug
                    } label: {
                        Text("#\(ch.slug)")
                            .font(PipiTokens.fontCaption.weight(selected ? .medium : .regular))
                            .foregroundStyle(selected ? PipiTokens.textInverse : PipiTokens.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selected ? PipiTokens.soulPrimary : PipiTokens.bgSurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField(s.t("需要助手搞定什么事？", "What should your agents get done?"), text: $newTaskTitle, axis: .vertical)
                .textFieldStyle(.plain)
                .font(PipiTokens.fontBody)
                .lineLimit(2...4)
                .padding(14)
                .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))

            Spacer()

            Button {
                let clean = newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { return }
                _ = store.createBoardThread(
                    channelSlug: newTaskChannel,
                    title: clean,
                    kind: .task,
                    priority: newTaskPriority,
                    author: PipiBoardActorRef(id: "human:ios", name: s.t("我", "Owner"), kind: .human)
                )
                newTaskTitle = ""
                tasksSegment = 1
                selectedTab = .tasks
                showNewBoardTaskSheet = false
                triggerHaptic(.success)
            } label: {
                Text(s.t("发布任务", "Post task"))
                    .font(PipiTokens.fontSubheadline)
                    .foregroundStyle(PipiTokens.textInverse)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(PipiTokens.soulPrimary, in: Capsule())
            }
            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))
            .disabled(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(PipiTokens.spacing20)
        .background(PipiTokens.bgCanvas.ignoresSafeArea())
    }

    private var addBotCatalogSheet: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            Text(s.t("添加新伙伴", "Add companion"))
                .font(PipiTokens.fontHeadline)
                .foregroundStyle(PipiTokens.textPrimary)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    Button {
                        _ = store.openBotArchitectSession()
                        isInGroupRoom = false
                        selectedTab = .chat
                        showAddBotSheet = false
                        triggerHaptic(.success)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.t("定制专属助手（对话式引导）", "Design a custom companion"))
                                    .font(PipiTokens.fontSubheadline)
                                    .foregroundStyle(PipiTokens.textInverse)
                                Text(s.t("聊几句你的目标，自动装配角色、规则与定时任务", "Describe your goal and build a tailored agent"))
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textInverse.opacity(0.8))
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(PipiTokens.textInverse)
                        }
                        .padding(PipiTokens.spacing16)
                        .background(PipiTokens.soulPrimary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))

                    ForEach(PipiBotMarketplaceCatalog.curatedBots) { item in
                        let installed = store.personas.contains(where: { $0.id == item.id })
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name(lang))
                                    .font(PipiTokens.fontSubheadline)
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Text(item.tagline(lang))
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textSecondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button {
                                let bot = store.installMarketplaceBot(item)
                                store.selectPersona(bot.id)
                                isInGroupRoom = false
                                selectedTab = .chat
                                showAddBotSheet = false
                                triggerHaptic(.success)
                            } label: {
                                Text(installed ? s.t("打开", "Open") : s.t("添加", "Add"))
                                    .font(PipiTokens.fontCaption.weight(.medium))
                                    .foregroundStyle(installed ? PipiTokens.textPrimary : PipiTokens.textInverse)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(installed ? PipiTokens.bgSurface : PipiTokens.soulPrimary, in: Capsule())
                            }
                            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.95))
                        }
                        .padding(PipiTokens.spacing16)
                        .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
        .padding(PipiTokens.spacing20)
        .background(PipiTokens.bgCanvas.ignoresSafeArea())
    }

    // MARK: - Helpers

    /// Editorial Apple / Claude Markdown renderer: proper hanging-indent bullet lists,
    /// subtle inline code pills, and calm paragraph breathing rhythm.
    @ViewBuilder
    private func iosFormattedMessageText(_ raw: String) -> some View {
        let lines = raw.components(separatedBy: .newlines)
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    Spacer().frame(height: 2)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") || trimmed.hasPrefix("* ") {
                    let bodyText = String(trimmed.dropFirst(2))
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle()
                            .fill(PipiTokens.textMuted.opacity(0.65))
                            .frame(width: 4.5, height: 4.5)
                            .offset(y: -2)
                        iosInlineStyledText(bodyText)
                    }
                } else {
                    iosInlineStyledText(trimmed)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iosInlineStyledText(_ text: String) -> some View {
        let styled: AttributedString = {
            guard var attr = try? AttributedString(
                markdown: text,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) else {
                return AttributedString(text)
            }
            for run in attr.runs {
                if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                    attr[run.range].font = PipiTokens.fontMonoSmall
                    attr[run.range].backgroundColor = PipiTokens.inlineCodeBg
                }
            }
            return attr
        }()
        return Text(styled)
            .font(PipiTokens.fontBody)
            .foregroundStyle(PipiTokens.textPrimary)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return s.t("早安，今天先从哪件开始？", "Good morning")
        case 12..<18: return s.t("下午好，有什么交给我办？", "Good afternoon")
        default: return s.t("晚上好，随时为你待命", "Good evening")
        }
    }

    private func segmentPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(PipiTokens.fontCaption.weight(isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(isSelected ? PipiTokens.bgCanvas : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func boardFilterChip(slug: String?, title: String) -> some View {
        let selected = boardChannelFilter == slug
        return Button {
            withAnimation(PipiMotion.press) { boardChannelFilter = slug }
            triggerHaptic(.light)
        } label: {
            Text(title)
                .font(PipiTokens.fontCaption.weight(selected ? .medium : .regular))
                .foregroundStyle(selected ? PipiTokens.textInverse : PipiTokens.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? PipiTokens.soulPrimary : PipiTokens.bgCanvas, in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : PipiTokens.sheetBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func npuCapabilityRow(title: String, ready: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ready ? PipiTokens.stateSuccess : PipiTokens.textMuted.opacity(0.45))
                .frame(width: 6, height: 6)
            Text(title)
                .font(PipiTokens.fontCaption)
                .foregroundStyle(PipiTokens.textPrimary)
            Spacer()
            Text(ready ? s.t("已就绪", "Ready") : s.t("云端回退", "Cloud"))
                .font(PipiTokens.fontMicro)
                .foregroundStyle(PipiTokens.textMuted)
        }
    }

    private func settingsCardGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .pipiAppleCard(cornerRadius: 16, elevated: false)
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
                .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            TextField(s.modelNameLabel, text: $modelId)
                .textFieldStyle(.plain)
                .padding(PipiTokens.spacing12)
                .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            TextField(s.baseUrlLabel, text: $modelBaseURL)
                .textFieldStyle(.plain)
                .font(PipiTokens.fontMono)
                .padding(PipiTokens.spacing12)
                .background(PipiTokens.bgSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
