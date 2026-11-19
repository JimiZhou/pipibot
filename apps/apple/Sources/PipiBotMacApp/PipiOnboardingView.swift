import SwiftUI
import PipiBotKit

#if os(macOS)
import AppKit
#endif

public struct PipiOnboardingView: View {
    @Bindable public var store: PipiAppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pipiTextScale) private var textScale

    @State private var step: Int = 0
    @State private var stepForward: Bool = true
    @State private var connectTab: ConnectTab = .llm

    // LLM Form State
    @State private var selectedPreset: PipiLLMProviderKind = .openai
    @State private var providerName: String = "OpenAI"
    @State private var apiKey: String = ""
    @State private var baseURL: String = PipiLLMProviderKind.openai.defaultBaseURL
    @State private var modelId: String = PipiLLMProviderKind.openai.defaultModelId
    @State private var isTesting: Bool = false
    @State private var testStatusOk: Bool?
    @State private var testStatusMessage: String?

    // Persona Selection State
    @State private var selectedPersonaId: String = "bot_pipi_general"
    @State private var showCustomBotCreator: Bool = false

    private enum ConnectTab: String, CaseIterable, Identifiable {
        case llm
        case localAgent
        var id: String { rawValue }
    }

    public init(store: PipiAppStore) {
        self.store = store
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    public var body: some View {
        let _ = textScale
        ZStack {
            PipiTokens.bgCanvas.ignoresSafeArea()

            RadialGradient(
                colors: [PipiTokens.soulPrimary.opacity(0.11), Color.clear],
                center: .init(x: 0.5, y: 0.24),
                startRadius: 12,
                endRadius: 380
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                Spacer(minLength: PipiTokens.spacing12)

                ZStack {
                    if step == 0 {
                        welcomeStep
                            .transition(stepTransition)
                    } else if step == 1 {
                        connectEngineStep
                            .transition(stepTransition)
                    } else {
                        personaStep
                            .transition(stepTransition)
                    }
                }
                .frame(maxWidth: 700, minHeight: 430, maxHeight: 460, alignment: .center)
                .padding(.horizontal, PipiTokens.spacing24)

                Spacer(minLength: PipiTokens.spacing12)

                bottomNavigationBar
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
        .sheet(isPresented: $showCustomBotCreator) {
            PipiBotCreatorSheet(
                store: store,
                existing: nil,
                onDismiss: { showCustomBotCreator = false },
                onSaved: { created in
                    selectedPersonaId = created.id
                    store.avatarEngine.setState(created.idleAvatarState)
                }
            )
            .environment(\.pipiTextScale, store.uiZoomScale)
        }
        .onAppear {
            store.avatarEngine.setState(.ambientWarmWelcome)
            selectedPersonaId = store.activePersonaId
            if let existing = store.llmProviders.first {
                selectedPreset = existing.kind
                providerName = existing.name
                apiKey = existing.apiKey
                baseURL = existing.baseURL
                modelId = existing.modelId
            }
            Task { await store.refreshLocalAgents() }
        }
    }

    // MARK: - Top Bar (Step Indicator + Quick Language & Theme Controls)

    private var topBar: some View {
        HStack(spacing: PipiTokens.spacing12) {
            HStack(spacing: PipiTokens.spacing8) {
                PipiBotLogoMark(size: 24)
                Text(s.appName)
                    .font(PipiTokens.fontHeadline)
                    .tracking(PipiTokens.trackingHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)
            }

            Spacer()

            // Step dots
            HStack(spacing: PipiTokens.spacing8) {
                ForEach(0..<3, id: \.self) { idx in
                    Capsule()
                        .fill(idx == step ? PipiTokens.soulPrimary : PipiTokens.borderStrong)
                        .frame(width: idx == step ? 24 : 8, height: 6)
                        .animation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion), value: step)
                }
            }

            Spacer()

            // Language Picker
            Menu {
                ForEach(PipiAppLanguage.allCases) { option in
                    Button {
                        store.setLanguage(option)
                    } label: {
                        HStack {
                            Text(option.displayName(in: lang))
                            if store.language == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .font(.system(size: 13, weight: .medium))
                    Text(store.language.displayName(in: lang))
                        .font(PipiTokens.fontCaption)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(PipiTokens.textMuted)
                }
                .foregroundStyle(PipiTokens.textSecondary)
                .padding(.horizontal, PipiTokens.spacing12)
                .frame(height: PipiTokens.buttonHeightDesktop)
                .background(PipiTokens.bgSurface)
                .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                .clipShape(Capsule())
            }
            .pipiPlainMenu()
            .fixedSize()
        }
        .padding(.top, 36)
        .padding(.horizontal, PipiTokens.spacing24)
        .padding(.bottom, PipiTokens.spacing12)
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: stepForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: stepForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: PipiTokens.spacing24) {
            PipiAvatarView(engine: store.avatarEngine, size: 112)

            VStack(spacing: PipiTokens.spacing12) {
                Text(s.onboardingWelcomeTitle)
                    .font(PipiTokens.fontHero)
                    .foregroundStyle(PipiTokens.textPrimary)

                Text(s.onboardingWelcomeSubtitle)
                    .font(PipiTokens.fontBody)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 540)
            }

            HStack(spacing: PipiTokens.spacing16) {
                featureCard(
                    icon: "cpu",
                    color: PipiTokens.soulPrimary,
                    title: s.onboardingFeature1Title,
                    description: s.onboardingFeature1Desc
                )
                featureCard(
                    icon: "terminal.fill",
                    color: PipiTokens.stateSuccess,
                    title: s.onboardingFeature2Title,
                    description: s.onboardingFeature2Desc
                )
                featureCard(
                    icon: "person.2.fill",
                    color: PipiTokens.soulSecondary,
                    title: s.onboardingFeature3Title,
                    description: s.onboardingFeature3Desc
                )
            }
        }
    }

    private func featureCard(icon: String, color: Color, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

            Text(title)
                .font(PipiTokens.fontHeadline)
                .foregroundStyle(PipiTokens.textPrimary)

            Text(description)
                .font(PipiTokens.fontCaption)
                .foregroundStyle(PipiTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(PipiTokens.spacing16)
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .background(PipiTokens.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous))
    }

    // MARK: - Step 1: Connect LLM API or Local Agents

    private var connectEngineStep: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                Text(s.onboardingStepConnectTitle)
                    .font(PipiTokens.fontHero)
                    .foregroundStyle(PipiTokens.textPrimary)
                Text(s.onboardingStepConnectSubtitle)
                    .font(PipiTokens.fontBody)
                    .foregroundStyle(PipiTokens.textSecondary)
            }

            Picker("", selection: $connectTab) {
                Text(s.onboardingTabLLM).tag(ConnectTab.llm)
                Text(s.onboardingTabLocalAgent).tag(ConnectTab.localAgent)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                if connectTab == .llm {
                    llmSetupCard
                } else {
                    localAgentsSetupCard
                }
            }
            .frame(maxHeight: 380)
        }
    }

    private var llmSetupCard: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            // Provider preset chips
            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                Text(s.providerPreset)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: PipiTokens.spacing8)], spacing: PipiTokens.spacing8) {
                    ForEach(PipiLLMProviderKind.allCases) { preset in
                        let isSelected = selectedPreset == preset
                        Button {
                            applyPreset(preset)
                        } label: {
                            Text(preset.localizedName(lang))
                                .font(PipiTokens.fontCaption.weight(isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? PipiTokens.textInverse : PipiTokens.textPrimary)
                                .lineLimit(1)
                                .padding(.horizontal, PipiTokens.spacing12)
                                .frame(maxWidth: .infinity)
                                .frame(height: PipiTokens.buttonHeightDesktop)
                                .background(isSelected ? PipiTokens.soulPrimary : PipiTokens.bgElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                        .stroke(isSelected ? PipiTokens.soulPrimary : PipiTokens.borderSubtle, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                    }
                }
            }

            HStack(spacing: PipiTokens.spacing12) {
                labeledField(title: s.displayNameLabel) {
                    TextField(selectedPreset.displayName, text: $providerName)
                        .textFieldStyle(.plain)
                }

                labeledField(title: s.modelNameLabel) {
                    TextField(selectedPreset.defaultModelId, text: $modelId)
                        .textFieldStyle(.plain)
                }
            }

            // Quick suggested model chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PipiTokens.spacing8) {
                    ForEach(selectedPreset.suggestedModels, id: \.self) { suggested in
                        Button {
                            modelId = suggested
                        } label: {
                            Text(suggested)
                                .font(PipiTokens.fontMonoSmall)
                                .foregroundStyle(modelId == suggested ? PipiTokens.soulPrimary : PipiTokens.textSecondary)
                                .padding(.horizontal, PipiTokens.spacing8)
                                .padding(.vertical, 4)
                                .background(modelId == suggested ? PipiTokens.soulPrimary.opacity(0.14) : PipiTokens.bgInset)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                    }
                }
            }

            labeledField(title: s.apiKeyLabel) {
                SecureField(s.apiKeyPlaceholder, text: $apiKey)
                    .textFieldStyle(.plain)
            }

            labeledField(title: s.baseUrlLabel) {
                TextField(selectedPreset.defaultBaseURL, text: $baseURL)
                    .textFieldStyle(.plain)
                    .font(PipiTokens.fontMono)
            }

            HStack(spacing: PipiTokens.spacing12) {
                PipiActionButton(
                    isTesting ? s.testingConnection : s.testConnection,
                    systemImage: "bolt.horizontal.circle",
                    tone: .secondary,
                    density: .desktopCompact
                ) {
                    runConnectionTest()
                }
                .disabled(isTesting)

                PipiActionButton(
                    s.saveAndUse,
                    systemImage: "checkmark.circle.fill",
                    tone: .primary,
                    density: .desktopCompact
                ) {
                    saveCurrentLLMConfig()
                }

                Spacer()

                if let ok = testStatusOk, let msg = testStatusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(ok ? PipiTokens.stateSuccess : PipiTokens.stateError)
                        Text(msg)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(ok ? PipiTokens.stateSuccess : PipiTokens.stateError)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(PipiTokens.spacing20)
        .background(PipiTokens.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous))
    }

    private var localAgentsSetupCard: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack {
                Text(s.localAgentHint)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                Spacer()
                PipiActionButton(s.rescanAgents, systemImage: "arrow.clockwise", tone: .secondary, density: .desktopCompact) {
                    Task { await store.refreshLocalAgents() }
                }
            }

            ForEach(store.localAgentStatuses) { agent in
                let badgeText: String = {
                    if agent.authenticated { return s.agentStatusReady }
                    if agent.installed { return s.agentStatusNeedsLogin }
                    return s.agentStatusNotInstalled
                }()
                let badgeColor: Color = {
                    if agent.authenticated { return PipiTokens.stateSuccess }
                    if agent.installed { return PipiTokens.stateWarning }
                    return PipiTokens.textMuted
                }()

                PipiListCard(
                    title: agent.kind.displayName,
                    subtitle: agent.kind.description(lang),
                    badgeText: badgeText,
                    badgeColor: badgeColor,
                    trailing: {
                        Toggle("", isOn: Binding(
                            get: { store.enabledLocalAgents.contains(agent.kind) },
                            set: { store.toggleLocalAgent(agent.kind, enabled: $0, setAsDefaultIfFirst: true) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!agent.installed)
                    },
                    footer: {
                        if let path = agent.binaryPath {
                            Text(path)
                                .font(PipiTokens.fontMonoSmall)
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                    }
                )
            }

            #if os(macOS)
            HStack(spacing: PipiTokens.spacing12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.workspaceDirectory)
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                    Text(store.workspaceDirectory)
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                PipiActionButton(s.chooseFolder, systemImage: "folder", tone: .secondary, density: .desktopCompact) {
                    chooseWorkspaceFolder()
                }
            }
            .padding(PipiTokens.spacing12)
            .background(PipiTokens.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
            #endif
        }
    }

    // MARK: - Step 2: Choose Starting Bot Persona

    private var personaStep: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                    Text(s.onboardingStepPersonaTitle)
                        .font(PipiTokens.fontHero)
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text(s.onboardingStepPersonaSubtitle)
                        .font(PipiTokens.fontBody)
                        .foregroundStyle(PipiTokens.textSecondary)
                }
                Spacer()
                PipiActionButton(s.createCustomBot, systemImage: "plus", tone: .secondary, density: .desktopCompact) {
                    showCustomBotCreator = true
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: PipiTokens.spacing12), GridItem(.flexible(), spacing: PipiTokens.spacing12)], spacing: PipiTokens.spacing12) {
                ForEach(store.personas) { persona in
                    let isSelected = selectedPersonaId == persona.id
                    let accent = PipiTokens.color(for: persona.accent)

                    Button {
                        selectedPersonaId = persona.id
                        store.avatarEngine.setState(persona.idleAvatarState)
                    } label: {
                        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                            HStack(spacing: PipiTokens.spacing12) {
                                PipiBotPersonaGlyph(persona: persona, size: 38, isSelected: isSelected)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(persona.name(lang))
                                        .font(PipiTokens.fontHeadline)
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Text(persona.role(lang))
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(PipiTokens.textSecondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(accent)
                                }
                            }
                        }
                        .padding(PipiTokens.spacing16)
                        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
                        .background(isSelected ? accent.opacity(0.08) : PipiTokens.bgSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous)
                                .stroke(isSelected ? accent : PipiTokens.borderSubtle, lineWidth: isSelected ? 1.5 : 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous))
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.98))
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomNavigationBar: some View {
        HStack(spacing: PipiTokens.spacing12) {
            if step > 0 {
                PipiActionButton(s.back, systemImage: "chevron.left", tone: .secondary, density: .desktopCompact) {
                    stepForward = false
                    withAnimation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion)) { step -= 1 }
                }
            } else {
                Button(s.skipForNow) {
                    store.completeOnboarding(selectedPersonaId: selectedPersonaId)
                }
                .buttonStyle(PipiPressButtonStyle())
                .font(PipiTokens.fontCaption)
                .foregroundStyle(PipiTokens.textMuted)
            }

            Spacer()

            if step == 1 {
                HStack(spacing: 6) {
                    Circle()
                        .fill(store.hasConfiguredEngine ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                        .frame(width: 7, height: 7)
                    Text(store.hasConfiguredEngine ? store.activeEngineDisplayLabel() : s.engineStatusUnconfigured)
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                }
            }

            if step == 0 {
                PipiActionButton(s.onboardingGetStarted, systemImage: "arrow.right", tone: .primary, density: .mobile) {
                    stepForward = true
                    withAnimation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion)) { step = 1 }
                }
            } else if step == 1 {
                PipiActionButton(s.next, systemImage: "arrow.right", tone: .primary, density: .mobile) {
                    if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (selectedPreset == .ollama && !store.hasConfiguredEngine) {
                        saveCurrentLLMConfig()
                    }
                    stepForward = true
                    withAnimation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion)) { step = 2 }
                }
            } else {
                PipiActionButton(s.onboardingStartChatting, systemImage: "bubble.left.and.bubble.right.fill", tone: .primary, density: .mobile) {
                    store.completeOnboarding(selectedPersonaId: selectedPersonaId)
                }
            }
        }
        .padding(.horizontal, PipiTokens.spacing24)
        .padding(.vertical, PipiTokens.spacing16)
        .background(PipiTokens.bgElevated)
        .overlay(alignment: .top) {
            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
        }
    }

    // MARK: - Helpers

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
            Text(title)
                .font(PipiTokens.fontCaption.weight(.semibold))
                .foregroundStyle(PipiTokens.textSecondary)
            content()
                .padding(.horizontal, PipiTokens.spacing12)
                .frame(height: 36)
                .background(PipiTokens.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                        .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
        }
    }

    private func applyPreset(_ preset: PipiLLMProviderKind) {
        selectedPreset = preset
        providerName = preset.displayName
        baseURL = preset.defaultBaseURL
        modelId = preset.defaultModelId
        testStatusOk = nil
        testStatusMessage = nil
    }

    private func buildConfigFromForm() -> PipiLLMProviderConfig {
        let existingId = store.llmProviders.first(where: { $0.kind == selectedPreset })?.id
            ?? "llm_\(selectedPreset.rawValue)_\(UUID().uuidString.prefix(4).lowercased())"
        return PipiLLMProviderConfig(
            id: existingId,
            name: providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedPreset.displayName : providerName,
            kind: selectedPreset,
            baseURL: baseURL,
            apiKey: apiKey,
            modelId: modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? selectedPreset.defaultModelId : modelId,
            isEnabled: true
        )
    }

    private func saveCurrentLLMConfig() {
        let cfg = buildConfigFromForm()
        guard cfg.isReady else {
            testStatusOk = false
            testStatusMessage = s.t("请填写完整的模型名称与 API Key", "Please enter a valid API key and model name")
            return
        }
        store.upsertLLMProvider(cfg, setAsDefault: true)
        testStatusOk = true
        testStatusMessage = s.t("已保存：\(cfg.name) · \(cfg.modelId)", "Saved: \(cfg.name) · \(cfg.modelId)")
    }

    private func runConnectionTest() {
        let cfg = buildConfigFromForm()
        isTesting = true
        testStatusOk = nil
        testStatusMessage = nil
        let currentLang = lang
        Task {
            let result = await PipiInferenceEngine.testLLMConnection(config: cfg, language: currentLang)
            isTesting = false
            testStatusOk = result.ok
            testStatusMessage = result.message
            if result.ok {
                store.upsertLLMProvider(cfg, setAsDefault: true)
            }
        }
    }

    #if os(macOS)
    private func chooseWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: store.workspaceDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            store.workspaceDirectory = url.path
            store.saveResidentState()
        }
    }
    #endif
}
