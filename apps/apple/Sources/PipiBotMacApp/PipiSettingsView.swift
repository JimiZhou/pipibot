import SwiftUI
import PipiBotKit

#if os(macOS)
import AppKit
#endif

public enum PipiSettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case aiEngine
    case runtimeSync
    case memoryPrivacy

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .aiEngine: return "cpu"
        case .runtimeSync: return "desktopcomputer"
        case .memoryPrivacy: return "lock.shield"
        }
    }

    public func title(_ s: PipiStrings) -> String {
        switch self {
        case .general: return s.settingsGeneral
        case .aiEngine: return s.settingsAIEngine
        case .runtimeSync: return s.settingsRuntimeSync
        case .memoryPrivacy: return s.settingsMemory
        }
    }
}

public struct PipiSettingsView: View {
    @Bindable public var store: PipiAppStore
    @State public var selectedTab: PipiSettingsTab
    public var onClose: (() -> Void)?
    public var onToggleQuickBar: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pipiTextScale) private var textScale

    // Add / Edit Model Provider Form
    @State private var showModelEditor = false
    @State private var editingModelId: String?
    @State private var formPreset: PipiLLMProviderKind = .openai
    @State private var formName: String = "OpenAI"
    @State private var formApiKey: String = ""
    @State private var formBaseURL: String = PipiLLMProviderKind.openai.defaultBaseURL
    @State private var formModelId: String = PipiLLMProviderKind.openai.defaultModelId
    @State private var formTemp: Double = 0.7
    @State private var testingProviderId: String?
    @State private var testFeedback: [String: (ok: Bool, message: String)] = [:]

    // Destructive confirmations
    @State private var showClearAllChatsConfirmation = false
    @State private var clearedBanner = false

    public init(
        store: PipiAppStore,
        initialTab: PipiSettingsTab = .general,
        onClose: (() -> Void)? = nil,
        onToggleQuickBar: @escaping () -> Void = {}
    ) {
        self.store = store
        self._selectedTab = State(initialValue: initialTab)
        self.onClose = onClose
        self.onToggleQuickBar = onToggleQuickBar
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    public var body: some View {
        let _ = textScale
        HStack(spacing: 0) {
            // Neutral Monochrome 4-Tab Settings Rail (192pt, #F7F7F8 Light / #141518 Dark)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: PipiTokens.spacing8) {
                    PipiBotLogoMark(size: 20)
                    Text(s.settings)
                        .font(PipiTokens.fontHeadline)
                        .foregroundStyle(PipiTokens.textPrimary)
                }
                .padding(.horizontal, PipiTokens.spacing8)
                .padding(.top, PipiTokens.spacing20)
                .padding(.bottom, PipiTokens.spacing12)

                ForEach(PipiSettingsTab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: PipiTokens.spacing8) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                                .frame(width: 18)
                            Text(tab.title(s))
                                .font(PipiTokens.fontSubheadline.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                            Spacer()
                        }
                        .padding(.horizontal, PipiTokens.spacing8)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                .fill(isSelected ? PipiTokens.bgSurfaceHover : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: selectedTab)
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.985))
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text(s.appName)
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                    Text("\(s.versionLabel) \(store.daemonVersion)")
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                }
                .padding(.horizontal, PipiTokens.spacing8)
                .padding(.bottom, PipiTokens.spacing16)
            }
            .padding(.horizontal, PipiTokens.spacing12)
            .frame(width: 208)
            .pipiStructuralMaterial()

            Rectangle()
                .fill(PipiTokens.borderSubtle)
                .frame(width: 1)

            // Pure White (#FFFFFF) / Obsidian (#0F1012) Content Plane
            VStack(spacing: 0) {
                HStack {
                    Text(selectedTab.title(s))
                        .font(PipiTokens.fontTitle)
                        .tracking(PipiTokens.trackingTitle)
                        .foregroundStyle(PipiTokens.textPrimary)
                    Spacer()
                    if let onClose {
                        PipiGhostIconButton(
                            systemImage: "xmark",
                            size: 28,
                            iconSize: 12,
                            cornerRadius: PipiTokens.radiusPill,
                            accessibilityLabel: s.close,
                            action: onClose
                        )
                    }
                }
                .padding(.horizontal, PipiTokens.spacing24)
                .padding(.vertical, PipiTokens.spacing16)
                .background(PipiTokens.bgCanvas)

                Rectangle()
                    .fill(PipiTokens.borderSubtle)
                    .frame(height: 1)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing24) {
                        switch selectedTab {
                        case .general:
                            generalTab
                        case .aiEngine:
                            aiEngineTab
                        case .runtimeSync:
                            runtimeSyncTab
                        case .memoryPrivacy:
                            memoryPrivacyTab
                        }
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(PipiTokens.spacing24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .background(PipiTokens.bgCanvas)
            }
        }
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
        .sheet(isPresented: $showModelEditor) {
            modelEditorSheet
                .frame(minWidth: 500, minHeight: 460)
        }
    }

    // MARK: - 1. General Tab (Appearance & Language + Shortcuts + Quiet Onboarding Replay)

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
            settingsGroup(title: s.t("外观与语言", "Appearance & Language")) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.languageSectionTitle)
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.languageSectionDesc)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    Picker("", selection: Binding(
                        get: { store.language },
                        set: { store.setLanguage($0) }
                    )) {
                        ForEach(PipiAppLanguage.allCases) { option in
                            Text(option.displayName(in: lang)).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                settingsRowDivider

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.appearanceSectionTitle)
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.t("自动适配系统深浅色，或手动固定外观", "Match system appearance or pick a fixed mode"))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer(minLength: PipiTokens.spacing12)
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
                    .frame(width: 210)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                settingsRowDivider

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.zoomSectionTitle)
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.zoomSectionDesc)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    HStack(spacing: PipiTokens.spacing8) {
                        Button {
                            store.zoomOut()
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(PipiTokens.textPrimary)
                                .frame(width: 28, height: 28)
                                .background(PipiTokens.bgSurfaceHover)
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                        .disabled(store.uiZoomScale <= PipiAppStore.minZoomScale + 0.001)
                        .accessibilityLabel(s.zoomOut)

                        Button {
                            store.resetZoom()
                        } label: {
                            Text(store.uiZoomPercentLabel)
                                .font(PipiTokens.fontMono.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(PipiTokens.textPrimary)
                                .frame(minWidth: 52, minHeight: 28)
                                .background(PipiTokens.bgInset)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                        .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                        .help(s.zoomReset)

                        Button {
                            store.zoomIn()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(PipiTokens.textPrimary)
                                .frame(width: 28, height: 28)
                                .background(PipiTokens.bgSurfaceHover)
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                        .disabled(store.uiZoomScale >= PipiAppStore.maxZoomScale - 0.001)
                        .accessibilityLabel(s.zoomIn)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            settingsGroup(title: s.t("快捷键", "Shortcuts")) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.t("全局快捷浮窗", "Global Quick Bar"))
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.t("随时通过 ⌥Space 呼出桌面悬浮对话框，快速向当前 Bot 提问", "Press ⌥Space anywhere on your Mac to summon the floating PiPiBot bar"))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    shortcutBadge("⌥Space")
                    PipiActionButton(s.t("打开浮窗", "Open"), tone: .secondary, density: .desktopCompact) {
                        onToggleQuickBar()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                settingsRowDivider

                HStack {
                    Text(s.openCommandPalette)
                        .font(PipiTokens.fontSubheadline.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Spacer()
                    shortcutBadge("⌘K")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                settingsRowDivider

                HStack {
                    Text(s.newTask)
                        .font(PipiTokens.fontSubheadline.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Spacer()
                    shortcutBadge("⌘N")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Quiet bottom action row for onboarding replay
            HStack {
                PipiActionButton(
                    s.onboardingReopenGuide,
                    systemImage: "arrow.counterclockwise",
                    tone: .ghost,
                    density: .desktopCompact
                ) {
                    onClose?()
                    store.reopenOnboarding()
                }
                Spacer()
            }
        }
    }

    // MARK: - 2. Models & Engines Tab

    private var defaultRoutingSelection: Binding<PipiExecutionTarget> {
        Binding(
            get: {
                switch store.defaultExecutionTarget {
                case .auto:
                    return .auto
                case .llm(let pid):
                    if store.readyLLMProviders.contains(where: { $0.id == pid }) {
                        return .llm(providerId: pid)
                    }
                    return .auto
                case .localAgent(let kind):
                    if store.usableLocalAgents.contains(where: { $0.kind == kind }) {
                        return .localAgent(kind)
                    }
                    return .auto
                }
            },
            set: { newTarget in
                store.setDefaultExecutionTarget(newTarget)
            }
        )
    }

    private var aiEngineTab: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
            // Group 1: Default Strategy
            settingsGroup(title: s.t("默认策略", "Default Strategy")) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.t("默认执行路由", "Default Execution Route"))
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.t("未单独指定引擎时优先使用该目标", "Used when a Bot or turn does not override the engine"))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    Picker("", selection: defaultRoutingSelection) {
                        Text(s.autoRouteEngine).tag(PipiExecutionTarget.auto)
                        if !store.readyLLMProviders.isEmpty {
                            Section(s.cloudAndLocalLLMs) {
                                ForEach(store.readyLLMProviders) { cfg in
                                    Text("\(cfg.name) · \(cfg.modelId)").tag(PipiExecutionTarget.llm(providerId: cfg.id))
                                }
                            }
                        }
                        if !store.usableLocalAgents.isEmpty {
                            Section(s.localAgents) {
                                ForEach(store.usableLocalAgents) { ag in
                                    Text(ag.kind.displayName).tag(PipiExecutionTarget.localAgent(ag.kind))
                                }
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                #if os(macOS)
                settingsRowDivider

                HStack(spacing: PipiTokens.spacing12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.workspaceDirectory)
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(store.workspaceDirectory)
                            .font(PipiTokens.fontMonoSmall)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    PipiActionButton(s.t("更改", "Change"), systemImage: "folder", tone: .secondary, density: .desktopCompact) {
                        chooseWorkspaceFolder()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                #endif
            }

            // Group 2: Local CLI Agents
            settingsGroup(
                title: s.localAgents,
                trailing: {
                    PipiActionButton(s.rescanAgents, systemImage: "arrow.clockwise", tone: .ghost, density: .desktopCompact) {
                        Task { await store.refreshLocalAgents() }
                    }
                }
            ) {
                ForEach(Array(store.localAgentStatuses.enumerated()), id: \.element.id) { idx, agent in
                    if idx > 0 {
                        settingsRowDivider
                    }

                    let statusText: String = {
                        if agent.authenticated { return s.agentStatusReady }
                        if agent.installed { return s.agentStatusNeedsLogin }
                        return s.agentStatusNotInstalled
                    }()
                    let statusColor: Color = {
                        if agent.authenticated { return PipiTokens.stateSuccess }
                        if agent.installed { return PipiTokens.stateWarning }
                        return PipiTokens.textMuted
                    }()

                    HStack(spacing: PipiTokens.spacing12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: PipiTokens.spacing8) {
                                Text(agent.kind.displayName)
                                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textPrimary)

                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(statusColor)
                                        .frame(width: 6, height: 6)
                                    Text(statusText)
                                        .font(PipiTokens.fontMicro)
                                        .foregroundStyle(statusColor)
                                }
                            }

                            Text(agent.binaryPath ?? agent.authHint)
                                .font(PipiTokens.fontMonoSmall)
                                .foregroundStyle(PipiTokens.textMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer(minLength: PipiTokens.spacing12)

                        Toggle("", isOn: Binding(
                            get: { store.enabledLocalAgents.contains(agent.kind) },
                            set: { store.toggleLocalAgent(agent.kind, enabled: $0, setAsDefaultIfFirst: true) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!agent.installed)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
            }

            // Group 3: Cloud & Local LLM APIs
            settingsGroup(
                title: s.cloudAndLocalLLMs,
                trailing: {
                    PipiActionButton(s.t("添加模型", "Add Model"), systemImage: "plus", tone: .primary, density: .desktopCompact) {
                        openNewModelEditor()
                    }
                }
            ) {
                if store.llmProviders.isEmpty {
                    HStack(spacing: PipiTokens.spacing12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 16))
                            .foregroundStyle(PipiTokens.textMuted)
                        Text(s.t("尚未添加大模型 API（也可直接使用上方的本地 CLI Agent）。", "No LLM API added yet (or use a local CLI agent above)."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                } else {
                    ForEach(Array(store.llmProviders.enumerated()), id: \.element.id) { idx, cfg in
                        if idx > 0 {
                            settingsRowDivider
                        }

                        let isDefault = store.defaultLLMProviderId == cfg.id
                        let fb = testFeedback[cfg.id]

                        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                            HStack(spacing: PipiTokens.spacing12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("\(cfg.name) · \(cfg.modelId)")
                                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                            .lineLimit(1)

                                        if isDefault {
                                            Text(s.defaultEngine)
                                                .font(PipiTokens.fontMicro)
                                                .foregroundStyle(PipiTokens.textPrimary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1.5)
                                                .background(PipiTokens.bgSurfaceHover)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    Text("\(cfg.kind.localizedName(lang)) · \(cfg.baseURL)")
                                        .font(PipiTokens.fontMonoSmall)
                                        .foregroundStyle(PipiTokens.textMuted)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer(minLength: PipiTokens.spacing8)

                                PipiActionButton(
                                    testingProviderId == cfg.id ? s.testingConnection : s.t("测试", "Test"),
                                    systemImage: "bolt.horizontal.circle",
                                    tone: .ghost,
                                    density: .desktopCompact
                                ) {
                                    testProvider(cfg)
                                }

                                Menu {
                                    if !isDefault {
                                        Button {
                                            store.setDefaultLLMProvider(id: cfg.id)
                                        } label: {
                                            Label(s.setAsDefault, systemImage: "star")
                                        }
                                    }

                                    Button {
                                        openEditModelEditor(cfg)
                                    } label: {
                                        Label(s.edit, systemImage: "pencil")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        store.deleteLLMProvider(id: cfg.id)
                                    } label: {
                                        Label(s.delete, systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(PipiTokens.textSecondary)
                                        .frame(width: 28, height: 28)
                                        .background(
                                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                                .fill(PipiTokens.bgSurface)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                                        )
                                }
                                .pipiPlainMenu()
                                .fixedSize()
                                .help(s.t("更多操作", "More actions"))
                                .accessibilityLabel(s.t("更多操作", "More actions"))
                            }

                            if let fb {
                                HStack(spacing: 6) {
                                    Image(systemName: fb.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(fb.ok ? PipiTokens.stateSuccess : PipiTokens.stateError)
                                    Text(fb.message)
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(fb.ok ? PipiTokens.stateSuccess : PipiTokens.stateError)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
            }
        }
    }

    // MARK: - 3. Runtime & Sync Tab (This Mac Host + Keep Awake + Companion Sync)

    private var runtimeSyncTab: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
            // Group 1: This Mac Host
            settingsGroup(title: s.t("本机大本营", "This Mac")) {
                HStack(spacing: PipiTokens.spacing12) {
                    Circle()
                        .fill(hostDotColor)
                        .frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.localHost.statusBadgeText(lang))
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(
                            s.t(
                                "\(store.readyLLMProviders.count) 个模型就绪 · \(store.usableLocalAgents.count) 个本地 CLI Agent",
                                "\(store.readyLLMProviders.count) model(s) ready · \(store.usableLocalAgents.count) local CLI agent(s)"
                            )
                        )
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                settingsRowDivider

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.keepAwakeTitle)
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.keepAwakeDesc)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    Toggle("", isOn: Binding(
                        get: { store.bridgeSupervisor.keepAwakeEnabled },
                        set: { store.setKeepAwake($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            // Group 2: Mobile Companion Sync
            settingsGroup(title: s.syncBridgeTitle) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.companionSyncToggleTitle)
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.companionSyncToggleDesc)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    Toggle("", isOn: Binding(
                        get: { store.companionSyncEnabled },
                        set: { store.setCompanionSyncEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if store.companionSyncEnabled {
                    settingsRowDivider

                    HStack(spacing: PipiTokens.spacing12) {
                        Text(s.endpointUrlLabel)
                            .font(PipiTokens.fontCaption.weight(.semibold))
                            .foregroundStyle(PipiTokens.textSecondary)
                        TextField("http://127.0.0.1:4242", text: $store.daemonEndpoint)
                            .textFieldStyle(.plain)
                            .font(PipiTokens.fontMono)
                            .padding(.horizontal, PipiTokens.spacing8)
                            .frame(height: 32)
                            .background(PipiTokens.bgInset)
                            .overlay(
                                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        PipiActionButton(s.refresh, systemImage: "arrow.clockwise", tone: .secondary, density: .desktopCompact) {
                            Task {
                                await store.bridgeSupervisor.ensureBridgeRunning()
                                await store.refreshAllFromDaemon()
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    // MARK: - 4. Memory & Data Tab

    private var memoryPrivacyTab: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
            settingsGroup(title: s.t("个人记忆", "Personal Memory")) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.memoryEnabledTitle)
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.memoryEnabledDesc)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    Toggle("", isOn: Binding(
                        get: { store.memoryEnabled },
                        set: {
                            store.memoryEnabled = $0
                            store.saveResidentState()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                settingsRowDivider

                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    Text(s.t("个人背景与偏好", "Background & Preferences"))
                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text(s.t("填写你的个人背景、常用语言、代码偏好或工作习惯，PiPiBot 会在对话中自动参考。", "Describe your preferences, style, or background so PiPiBot adapts naturally across conversations."))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)

                    TextEditor(text: Binding(
                        get: { store.personalProfileNote },
                        set: { store.setPersonalProfileNote($0) }
                    ))
                    .onDisappear {
                        store.flush()
                    }
                    .font(PipiTokens.fontBody)
                    .scrollContentBackground(.hidden)
                    .padding(PipiTokens.spacing8)
                    .frame(height: 96)
                    .background(PipiTokens.bgInset)
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                            .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            settingsGroup(title: s.t("数据管理", "Data Management")) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.clearAllChatsTitle)
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(clearedBanner ? s.t("历史对话已清空。", "Conversation history cleared.") : s.clearAllChatsDesc)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(clearedBanner ? PipiTokens.stateSuccess : PipiTokens.textSecondary)
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    PipiActionButton(s.clearNow, systemImage: "trash", tone: .destructive, density: .desktopCompact) {
                        showClearAllChatsConfirmation = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .confirmationDialog(
            s.clearAllChatsConfirmTitle,
            isPresented: $showClearAllChatsConfirmation,
            titleVisibility: .visible
        ) {
            Button(s.clearNow, role: .destructive) {
                store.clearAllConversations()
                clearedBanner = true
            }
            Button(s.cancel, role: .cancel) {}
        } message: {
            Text(s.clearAllChatsConfirmMessage(store.conversations.count))
        }
    }

    // MARK: - Model Editor Sheet

    private var modelEditorSheet: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            HStack {
                Text(editingModelId == nil ? s.addModelProvider : s.t("编辑模型配置", "Edit Model Provider"))
                    .font(PipiTokens.fontTitle)
                    .foregroundStyle(PipiTokens.textPrimary)
                Spacer()
                PipiGhostIconButton(
                    systemImage: "xmark",
                    size: 28,
                    iconSize: 12,
                    cornerRadius: PipiTokens.radiusPill,
                    accessibilityLabel: s.close
                ) {
                    showModelEditor = false
                }
            }

            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                Text(s.providerPreset)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)
                Picker("", selection: $formPreset) {
                    ForEach(PipiLLMProviderKind.allCases) { kind in
                        Text(kind.localizedName(lang)).tag(kind)
                    }
                }
                .labelsHidden()
                .onChange(of: formPreset) { _, newKind in
                    if editingModelId == nil {
                        formName = newKind.displayName
                        formBaseURL = newKind.defaultBaseURL
                        formModelId = newKind.defaultModelId
                    }
                }
            }

            HStack(spacing: PipiTokens.spacing12) {
                fieldBlock(s.displayNameLabel) {
                    TextField(formPreset.displayName, text: $formName).textFieldStyle(.plain)
                }
                fieldBlock(s.modelNameLabel) {
                    TextField(formPreset.defaultModelId, text: $formModelId).textFieldStyle(.plain)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PipiTokens.spacing8) {
                    ForEach(formPreset.suggestedModels, id: \.self) { m in
                        Button {
                            formModelId = m
                        } label: {
                            Text(m)
                                .font(PipiTokens.fontMonoSmall)
                                .foregroundStyle(formModelId == m ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                                .padding(.horizontal, PipiTokens.spacing8)
                                .padding(.vertical, 4)
                                .background(formModelId == m ? PipiTokens.bgSurfaceHover : PipiTokens.bgInset)
                                .overlay(
                                    Capsule()
                                        .stroke(formModelId == m ? PipiTokens.borderStrong : Color.clear, lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            fieldBlock(s.apiKeyLabel) {
                SecureField(s.apiKeyPlaceholder, text: $formApiKey).textFieldStyle(.plain)
            }

            fieldBlock(s.baseUrlLabel) {
                TextField(formPreset.defaultBaseURL, text: $formBaseURL)
                    .textFieldStyle(.plain)
                    .font(PipiTokens.fontMono)
            }

            HStack {
                Text(String(format: "Temperature: %.2f", formTemp))
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                Slider(value: $formTemp, in: 0...1.5, step: 0.05)
            }

            Spacer()

            HStack {
                PipiActionButton(s.cancel, tone: .secondary, density: .desktopCompact) {
                    showModelEditor = false
                }
                Spacer()
                PipiActionButton(s.save, systemImage: "checkmark", tone: .primary, density: .desktopCompact) {
                    let cfg = PipiLLMProviderConfig(
                        id: editingModelId ?? "llm_\(UUID().uuidString.prefix(8).lowercased())",
                        name: formName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? formPreset.displayName : formName,
                        kind: formPreset,
                        baseURL: formBaseURL,
                        apiKey: formApiKey,
                        modelId: formModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? formPreset.defaultModelId : formModelId,
                        isEnabled: true,
                        temperature: formTemp
                    )
                    store.upsertLLMProvider(cfg, setAsDefault: editingModelId == nil)
                    showModelEditor = false
                }
            }
        }
        .padding(PipiTokens.spacing24)
        .background(PipiTokens.bgCanvas)
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
    }

    // MARK: - Local Group & Divider Helpers

    private var hostDotColor: Color {
        switch store.localHost.linkState {
        case .online: return PipiTokens.stateSuccess
        case .degraded: return PipiTokens.stateWarning
        case .offline: return PipiTokens.textMuted
        }
    }

    private func settingsGroup<Content: View, Trailing: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack(alignment: .center) {
                Text(title)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)
                Spacer()
                trailing()
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
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

    private var settingsRowDivider: some View {
        Rectangle()
            .fill(PipiTokens.borderSubtle)
            .frame(height: 1)
    }

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(PipiTokens.fontMonoSmall)
            .foregroundStyle(PipiTokens.textMuted)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(PipiTokens.bgInset)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusXS, style: .continuous)
                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusXS, style: .continuous))
    }

    private func fieldBlock<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
            Text(label)
                .font(PipiTokens.fontCaption.weight(.semibold))
                .foregroundStyle(PipiTokens.textSecondary)
            content()
                .padding(.horizontal, PipiTokens.spacing12)
                .frame(height: 36)
                .background(PipiTokens.bgSurface)
                .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
        }
    }

    private func openNewModelEditor() {
        editingModelId = nil
        formPreset = .openai
        formName = "OpenAI"
        formApiKey = ""
        formBaseURL = PipiLLMProviderKind.openai.defaultBaseURL
        formModelId = PipiLLMProviderKind.openai.defaultModelId
        formTemp = 0.7
        showModelEditor = true
    }

    private func openEditModelEditor(_ cfg: PipiLLMProviderConfig) {
        editingModelId = cfg.id
        formPreset = cfg.kind
        formName = cfg.name
        formApiKey = cfg.apiKey
        formBaseURL = cfg.baseURL
        formModelId = cfg.modelId
        formTemp = cfg.temperature
        showModelEditor = true
    }

    private func testProvider(_ cfg: PipiLLMProviderConfig) {
        testingProviderId = cfg.id
        let currentLang = lang
        Task {
            let res = await PipiInferenceEngine.testLLMConnection(config: cfg, language: currentLang)
            testFeedback[cfg.id] = res
            testingProviderId = nil
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
