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
    @State private var draftInput: String = ""
    @State private var showAddModelSheet = false
    @State private var modelPreset: PipiLLMProviderKind = .openai
    @State private var modelApiKey: String = ""
    @State private var modelBaseURL: String = PipiLLMProviderKind.openai.defaultBaseURL
    @State private var modelId: String = PipiLLMProviderKind.openai.defaultModelId
    @State private var testResultText: String?

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
                    NeedsYouSwipeDeckView(store: store, onHaptic: triggerHaptic)
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

    // MARK: - Tab 1: Chat

    private var chatPage: some View {
        VStack(spacing: 0) {
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

    // MARK: - Tab 2: Bots (Personas)

    private var botsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                ForEach(store.personas) { persona in
                    let isSelected = store.activePersona.id == persona.id
                    let accent = PipiTokens.color(for: persona.accent)
                    PipiListCard(
                        title: persona.name(lang),
                        subtitle: persona.role(lang),
                        badgeText: isSelected ? s.enabled : nil,
                        badgeColor: accent,
                        leading: {
                            PipiBotPersonaGlyph(persona: persona, size: 38, isSelected: isSelected)
                        },
                        footer: {
                            PipiActionButton(
                                s.t("开始对话", "Chat Now"),
                                systemImage: "bubble.left.fill",
                                tone: isSelected ? .primary : .secondary,
                                density: .mobile,
                                fullWidth: true
                            ) {
                                store.selectPersona(persona.id)
                                selectedTab = .chat
                                triggerHaptic(.light)
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, PipiTokens.spacing16)
            .padding(.bottom, PipiTokens.spacing24)
        }
    }

    // MARK: - Tab 4: Settings

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
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
