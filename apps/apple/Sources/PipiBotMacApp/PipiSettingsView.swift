import SwiftUI
import PipiBotKit

#if os(macOS)
import AppKit
#endif

public enum PipiSettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case aiEngine
    case skillsMCP
    case voice
    case remoteAccess
    case permissionsControl
    case memoryPrivacy

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .aiEngine: return "cpu"
        case .skillsMCP: return "puzzlepiece.extension"
        case .voice: return "waveform"
        case .remoteAccess: return "iphone.radiowaves.left.and.right"
        case .permissionsControl: return "hand.raised.app"
        case .memoryPrivacy: return "lock.shield"
        }
    }

    public func title(_ s: PipiStrings) -> String {
        switch self {
        case .general: return s.settingsGeneral
        case .aiEngine: return s.settingsAIEngine
        case .skillsMCP: return s.settingsSkillsMCP
        case .voice: return s.settingsVoice
        case .remoteAccess: return s.settingsRemoteAccess
        case .permissionsControl: return s.settingsPermissionsControl
        case .memoryPrivacy: return s.settingsMemory
        }
    }
}

private enum PipiAddLocalModelMode: String, CaseIterable, Identifiable {
    case hardwarePlan
    case existingPlatform

    var id: String { rawValue }

    func title(_ s: PipiStrings) -> String {
        switch self {
        case .hardwarePlan: return s.t("智能硬件规划", "Smart Hardware Plan")
        case .existingPlatform: return s.t("接入已有平台", "Existing Platform")
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

    // Wave 4 (#07 Local Model Autopilot / Gateway & #10 Daily Voice BYOK Keychain Inputs)
    @State private var gatewayActionFeedback: String? = nil
    @State private var overlayPreviewMessage: String? = nil
    @State private var cloudSttKeyDraft: String = ""
    @State private var cloudTtsKeyDraft: String = ""
    @State private var voiceKeysLoaded: Bool = false
    @State private var voiceKeysSavedBanner: Bool = false
    @State private var showAboutSheet: Bool = false
    @State private var isVersionFooterHovered: Bool = false
    @State private var showAdvancedLocalRuntime: Bool = false
    @State private var showLocalCLIAgentsSection: Bool = false
    @State private var showAdvancedVoiceSettings: Bool = false
    @State private var showMemorySharingDetails: Bool = false
    @State private var showSafetyProactiveDrawer: Bool = false
    @State private var showAdvancedMultiMachineMesh: Bool = false
    @State private var showCustomSkillImport: Bool = false
    @State private var showPermissionDiagnostics: Bool = false
    @State private var accountEmailDraft: String = ""
    @State private var accountOtpDraft: String = ""
    @State private var accountOtpSent: Bool = false
    @State private var accountFeedback: String? = nil
    @State private var showAccountQuickQR: Bool = false
    @State private var selectedPlatformModels: [PipiLocalModelPlatformKind: String] = [:]
    @State private var localPlatformFeedback: String? = nil
    @State private var showAddLocalModelSheet: Bool = false
    @State private var addLocalModelMode: PipiAddLocalModelMode = .hardwarePlan
    @State private var selectedPlannedCatalogModelId: String = ""
    @State private var selectedDeployPlatformOption: String = "auto"
    @State private var customLocalEndpointDraft: String = "http://127.0.0.1:11434"
    @State private var customLocalModelDraft: String = "qwen2.5:14b"
    @State private var customLocalPlatformDraft: PipiLocalModelPlatformKind = .ollama
    @State private var copiedRemoteLink: Bool = false
    @State private var showLegacyDaemonBridge: Bool = false
    @State private var macTestFeedback: String? = nil
    @State private var meshHubURLDraft: String = "http://127.0.0.1:4242"
    @State private var meshHubTokenDraft: String = ""
    @State private var meshNodeJoinNameDraft: String = "linux-4090"
    @State private var copiedMeshJoinCmd: Bool = false
    @State private var communitySkillSourceDraft: String = ""
    // Brigade Stacked Subscription Pool & 24/7 Cloud Host drafts
    @State private var newSubProvider: PipiSubscriptionProviderKind = .claudeSubscription
    @State private var newSubLabel: String = ""
    @State private var newSubUseSystemDefault: Bool = false
    @State private var newSubBaseURL: String = ""
    @State private var newSubModelId: String = ""
    @State private var newSubApiKey: String = ""
    @State private var copiedSubLoginId: String? = nil
    @State private var cloudBrigadeURLDraft: String = ""
    @State private var cloudBrigadeTokenDraft: String = ""
    @State private var cloudBrigadeSyncing: Bool = false
    @State private var copiedCloudDeployCmd: Bool = false

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
                                .fill(isSelected ? PipiTokens.bgElevated : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                .strokeBorder(isSelected ? PipiTokens.borderSubtle : Color.clear, lineWidth: 1)
                        )
                        .shadow(color: isSelected ? PipiTokens.subtleShadow.opacity(0.65) : Color.clear, radius: 2, y: 1)
                        .contentShape(Rectangle())
                        .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: selectedTab)
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.985))
                }

                Spacer()

                Button {
                    showAboutSheet = true
                } label: {
                    HStack(spacing: PipiTokens.spacing8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.appName)
                                .font(PipiTokens.fontCaption.weight(.semibold))
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text("\(s.versionLabel) \(store.appDisplayVersion)")
                                .font(PipiTokens.fontMonoSmall)
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "info.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isVersionFooterHovered ? PipiTokens.textPrimary : PipiTokens.textMuted)
                    }
                    .padding(.horizontal, PipiTokens.spacing8)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                            .fill(isVersionFooterHovered ? PipiTokens.bgSurfaceHover : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.985))
                .onHover { isVersionFooterHovered = $0 }
                .help(s.aboutTitle)
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
                        case .skillsMCP:
                            skillsMCPTab
                        case .voice:
                            voiceTab
                        case .remoteAccess:
                            remoteAccessTab
                        case .permissionsControl:
                            permissionsControlTab
                        case .memoryPrivacy:
                            memoryPrivacyTab
                        }
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(PipiTokens.spacing24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .pipiHideScrollbars()
                .background(PipiTokens.bgCanvas)
            }
        }
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
        .sheet(isPresented: $showModelEditor) {
            modelEditorSheet
                .frame(minWidth: 500, minHeight: 460)
        }
        .sheet(isPresented: $showAddLocalModelSheet) {
            addLocalModelSheet
                .frame(minWidth: 560, minHeight: 520)
        }
        .sheet(isPresented: $showAboutSheet) {
            PipiAboutSheetView(
                store: store,
                onClose: { showAboutSheet = false }
            )
            .environment(\.pipiTextScale, store.uiZoomScale)
            .frame(minWidth: 580, minHeight: 560)
        }
    }

    // MARK: - 1. General Tab (Appearance & Language + Shortcuts + Quiet Onboarding Replay)

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
            settingsGroup(title: s.t("外观与语言", "Appearance & Language")) {
                HStack {
                    HStack(spacing: 6) {
                        Text(s.languageSectionTitle)
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(title: s.languageSectionTitle, message: s.languageSectionDesc)
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    PipiSelectMenu(
                        options: PipiAppLanguage.allCases,
                        selection: Binding(
                            get: { store.language },
                            set: { store.setLanguage($0) }
                        ),
                        width: 156
                    ) { option in
                        option.displayName(in: lang)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                settingsRowDivider

                HStack {
                    Text(s.appearanceSectionTitle)
                        .font(PipiTokens.fontSubheadline.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Spacer(minLength: PipiTokens.spacing12)
                    PipiSegmentedControl(
                        options: PipiThemeMode.allCases,
                        selection: Binding(
                            get: { store.themeMode },
                            set: { store.setThemeMode($0) }
                        )
                    ) { mode in
                        mode.localizedLabel(lang)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                settingsRowDivider

                HStack {
                    HStack(spacing: 6) {
                        Text(s.zoomSectionTitle)
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(title: s.zoomSectionTitle, message: s.zoomSectionDesc)
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
                                .background(PipiTokens.buttonSecondaryBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                        .strokeBorder(PipiTokens.composerBorder, lineWidth: 1)
                                )
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
                                        .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
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
                                .background(PipiTokens.buttonSecondaryBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                        .strokeBorder(PipiTokens.composerBorder, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                        .disabled(store.uiZoomScale >= PipiAppStore.maxZoomScale - 0.001)
                        .accessibilityLabel(s.zoomIn)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            settingsGroup(title: s.t("快捷键", "Shortcuts")) {
                HStack {
                    HStack(spacing: 6) {
                        Text(s.t("全局快捷浮窗", "Global Quick Bar"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(
                            title: s.t("全局快捷浮窗", "Global Quick Bar"),
                            message: s.t("按 ⌥Space 在任意应用前方呼出或收起悬浮输入框。", "Press ⌥Space anywhere on macOS to toggle the floating prompt bar.")
                        )
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    shortcutBadge("⌥Space")
                    PipiActionButton(s.t("打开", "Open"), tone: .secondary, density: .desktopCompact) {
                        onToggleQuickBar()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

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

            // Software Updates via GitHub Releases
            settingsGroup(title: s.t("版本与自动更新", "Software Updates")) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    HStack(spacing: PipiTokens.spacing12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.t("当前版本 v\(store.appDisplayVersion)", "Current Version v\(store.appDisplayVersion)"))
                                .font(PipiTokens.fontSubheadline.weight(.semibold))
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text(softwareUpdateSubtitle)
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(softwareUpdateSubtitleColor)
                        }
                        Spacer()
                        softwareUpdateActionButton
                    }

                    if case .updateAvailable(let release) = store.updateManager.state,
                       !release.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(release.body.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .lineLimit(4)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PipiTokens.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                    } else if case .downloading(_, let progress) = store.updateManager.state {
                        ProgressView(value: progress)
                    }

                    settingsRowDivider

                    HStack {
                        Text(s.t("启动时自动从 GitHub Release 检查更新", "Automatically check GitHub Releases on launch"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { store.autoCheckUpdatesEnabled },
                            set: { store.setAutoCheckUpdatesEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Guided Setup re-entry card (only lives in Settings, no longer pinned in sidebar)
            settingsGroup(title: s.t("引导式配置", "Guided Setup")) {
                HStack(spacing: PipiTokens.spacing12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.t("逐步配置模型、系统权限与默认助手", "Configure models, macOS permissions, and assistants step by step"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.t("如初次启动时跳过了配置，可随时由此重新进入分步向导。", "Reopen the guided wizard anytime if you skipped initial setup."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer()
                    PipiActionButton(
                        s.t("启动引导式配置", "Launch guided setup"),
                        systemImage: "checklist",
                        tone: .secondary,
                        density: .desktopCompact
                    ) {
                        onClose?()
                        store.reopenOnboarding(atStep: 0)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - 1.5 Skills & MCP Tab

    private var skillsMCPTab: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
            settingsGroup(title: s.t("已安装本领概览", "Installed Capabilities")) {
                HStack(spacing: PipiTokens.spacing12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            s.t(
                                "已安装 \(store.ecosystemManager.installedSkills.count) 项技能 · \(store.ecosystemManager.installedMCPServers.count) 项工具",
                                "\(store.ecosystemManager.installedSkills.count) Skills · \(store.ecosystemManager.installedMCPServers.count) Tools installed"
                            )
                        )
                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.t("一键安装后会自动生效，所有助手都能直接使用，无需手动配置。", "Installed capabilities are immediately available to all your assistants."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            settingsGroup(title: s.t("精选技能与工具（一键安装）", "Featured Skills & Tools")) {
                VStack(spacing: PipiTokens.spacing8) {
                    ForEach(PipiEcosystemCatalogEntry.curated) { item in
                        let alreadyInstalled = item.kind == .skill
                            ? store.ecosystemManager.installedSkills.contains(where: { $0.id == item.id })
                            : store.ecosystemManager.installedMCPServers.contains(where: { $0.id == item.id })
                        HStack(spacing: PipiTokens.spacing12) {
                            Image(systemName: item.kind == .mcp ? "powerplug" : "book.pages")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(PipiTokens.textSecondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(item.name)
                                        .font(PipiTokens.fontSubheadline.weight(.medium))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Text(item.kind == .mcp ? "MCP" : s.t("技能", "Skill"))
                                        .font(PipiTokens.fontMicro.weight(.medium))
                                        .foregroundStyle(PipiTokens.textSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(PipiTokens.bgSurfaceHover, in: Capsule())
                                }
                                Text(item.description)
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textMuted)
                                    .lineLimit(2)
                            }
                            Spacer()
                            PipiActionButton(
                                alreadyInstalled ? s.t("已安装", "Installed") : s.t("安装", "Install"),
                                systemImage: alreadyInstalled ? "checkmark" : "plus",
                                tone: alreadyInstalled ? .ghost : .secondary,
                                density: .desktopCompact
                            ) {
                                guard !alreadyInstalled else { return }
                                Task {
                                    if item.kind == .skill {
                                        _ = await store.installCommunitySkill(source: item.id)
                                    } else {
                                        _ = await store.installCommunityMCP(
                                            id: item.id,
                                            name: item.name,
                                            description: item.description,
                                            transport: .stdio,
                                            command: item.mcpCommand,
                                            args: item.mcpArgs
                                        )
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(PipiTokens.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            settingsDisclosureCard(
                icon: "square.and.arrow.down",
                title: s.t("高级：从链接或本地导入技能", "Advanced: Import Custom Skill"),
                summary: s.t("支持粘贴 GitHub 链接、SKILL.md 地址或本地目录", "Paste a GitHub repo, SKILL.md URL, or local folder"),
                isExpanded: $showCustomSkillImport
            ) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    HStack(spacing: PipiTokens.spacing8) {
                        TextField(s.t("粘贴 GitHub 仓库链接、SKILL.md URL 或本地目录路径", "Paste GitHub repo URL, SKILL.md URL, or local path"), text: $communitySkillSourceDraft)
                            .textFieldStyle(.roundedBorder)
                        PipiActionButton(
                            s.t("一键安装", "Install"),
                            systemImage: "square.and.arrow.down",
                            tone: .primary,
                            density: .desktopCompact
                        ) {
                            let src = communitySkillSourceDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !src.isEmpty else { return }
                            communitySkillSourceDraft = ""
                            Task { _ = await store.installCommunitySkill(source: src) }
                        }
                    }
                    Text(s.t("支持标准开源 SKILL.md 格式，安装后可在对话中直接让助手调用。", "Supports standard SKILL.md format. Assistants can use installed skills right away."))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - 2. Models & Engines Tab

    private var defaultRoutingSelection: Binding<PipiExecutionTarget> {
        Binding(
            get: {
                switch store.defaultExecutionTarget {
                case .llm(let pid):
                    if store.readyLLMProviders.contains(where: { $0.id == pid }) {
                        return .llm(providerId: pid)
                    }
                    return .auto
                case .auto, .localAgent:
                    return .auto
                }
            },
            set: { newTarget in
                store.setDefaultExecutionTarget(newTarget)
            }
        )
    }

    private var defaultRoutingDisplayName: String {
        switch defaultRoutingSelection.wrappedValue {
        case .auto:
            return s.t("自动选择默认模型", "Auto Default Model")
        case .llm(let pid):
            if let cfg = store.readyLLMProviders.first(where: { $0.id == pid }) {
                return "\(cfg.name) · \(cfg.modelId)"
            }
            return s.t("自动选择默认模型", "Auto Default Model")
        case .localAgent:
            return s.t("自动选择默认模型", "Auto Default Model")
        }
    }

    private var aiEngineTab: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
            // Group 1: Built-in PiPi Engine + Backing LLM Strategy
            settingsGroup(title: s.t("默认执行引擎", "Default Execution Engine")) {
                HStack(spacing: PipiTokens.spacing12) {
                    HStack(spacing: 6) {
                        Text(s.t("核心智能体引擎", "Core Agent Engine"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(
                            title: s.t("PiPi 内置引擎（基于 Pi 内核）", "PiPi Built-in Engine (pi Core)"),
                            message: s.t(
                                "PiPi 是以 pi 为底层的内置智能体执行引擎，负责工具调用、上下文记忆与多助手协同；Claude Code / Codex / OpenCode 作为外部协作 Agent 由 PiPi 按需调用。",
                                "PiPi is the built-in agent engine powered by pi core. External CLI agents (Claude Code, Codex, OpenCode) are invoked on demand by PiPi rather than replacing it."
                            )
                        )
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(PipiTokens.stateSuccess)
                            .frame(width: 6, height: 6)
                        Text(s.t("PiPi（内置 Pi 引擎）", "PiPi (Built-in pi Core)"))
                            .font(PipiTokens.fontCaption.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(PipiTokens.bgSurfaceHover)
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                            .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                settingsRowDivider

                HStack {
                    HStack(spacing: 6) {
                        Text(s.t("默认驱动模型", "Default Backing Model"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(
                            title: s.t("默认驱动模型", "Default Backing Model"),
                            message: s.t("为 PiPi 内置引擎选择默认使用的云端或本地大模型；助手未单独覆盖时均使用该模型。", "Select the default cloud or local LLM powering the built-in PiPi engine.")
                        )
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    Menu {
                        Button {
                            defaultRoutingSelection.wrappedValue = .auto
                        } label: {
                            if defaultRoutingSelection.wrappedValue == .auto {
                                Label(s.t("自动选择默认模型", "Auto Default Model"), systemImage: "checkmark")
                            } else {
                                Text(s.t("自动选择默认模型", "Auto Default Model"))
                            }
                        }
                        if !store.readyLLMProviders.isEmpty {
                            Divider()
                            ForEach(store.readyLLMProviders) { cfg in
                                let target = PipiExecutionTarget.llm(providerId: cfg.id)
                                Button {
                                    defaultRoutingSelection.wrappedValue = target
                                } label: {
                                    if defaultRoutingSelection.wrappedValue == target {
                                        Label("\(cfg.name) · \(cfg.modelId)", systemImage: "checkmark")
                                    } else {
                                        Text("\(cfg.name) · \(cfg.modelId)")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: PipiTokens.spacing8) {
                            Text(defaultRoutingDisplayName)
                                .font(PipiTokens.fontCaption.weight(.medium))
                                .foregroundStyle(PipiTokens.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                        .padding(.horizontal, 10)
                        .frame(width: 216, height: 32)
                        .background(PipiTokens.buttonSecondaryBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                .strokeBorder(PipiTokens.composerBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                    }
                    .pipiPlainMenu()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

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

            // Group 2: Installed Local Model Platforms (Ollama / LM Studio / llama.cpp / MLX / vLLM / PolyStrata)
            localModelPlatformsSection

            // Group 3: Cloud & Custom LLM APIs
            settingsGroup(
                title: s.t("云端与自定义模型", "Cloud & Custom Models"),
                trailing: {
                    PipiActionButton(s.t("添加模型", "Add Model"), systemImage: "plus", tone: .primary, density: .desktopCompact) {
                        openNewModelEditor()
                    }
                }
            ) {
                if store.llmProviders.isEmpty {
                    HStack(spacing: PipiTokens.spacing12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 15))
                            .foregroundStyle(PipiTokens.textMuted)
                        Text(s.t("尚未配置云端模型，可直接点击上方「添加模型」或拉起本地模型。", "No cloud model added yet. Add a model or launch a local platform above."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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
                                        .frame(width: 32, height: 32)
                                        .background(
                                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                                .fill(PipiTokens.buttonSecondaryBg)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                                .strokeBorder(PipiTokens.composerBorder, lineWidth: 1)
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
                        .padding(.vertical, 12)
                    }
                }
            }

            // Group 3.5: Stacked Paid Subscription Account Pool (Claude Pro/Max + ChatGPT Plus/Pro)
            subscriptionAccountPoolSection

            // Group 4 (Collapsible): External Sub-Agents invoked on-demand by PiPi
            settingsDisclosureCard(
                icon: "terminal",
                title: s.localAgents,
                summary: s.t("已挂载 \(store.usableLocalAgents.count) 项 · 由 PiPi 按需委派执行代码与终端任务", "\(store.usableLocalAgents.count) mounted · Invoked on demand by PiPi"),
                isExpanded: $showLocalCLIAgentsSection
            ) {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text(s.t("PiPi 可根据任务需要主动调度已启用的 Codex / Claude Code / OpenCode，也支持用自然语言或 /codex 直接调用。", "PiPi proactively delegates coding & terminal tasks to enabled Codex / Claude Code / OpenCode without needing /codex."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                        Spacer()
                        PipiActionButton(s.rescanAgents, systemImage: "arrow.clockwise", tone: .ghost, density: .desktopCompact) {
                            Task { await store.refreshLocalAgents() }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    settingsRowDivider

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.t("允许 PiPi 主动调用命令行 Agent", "Proactive CLI Sub-Agent Delegation"))
                                .font(PipiTokens.fontSubheadline.weight(.medium))
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text(s.t("遇到本地代码检查、测试或终端任务时，无需输入 /codex，由 PiPi 主动调起并受安全审计护栏保护。", "Automatically dispatches repo/terminal tasks to Codex or Claude Code under Safety Guardrail review."))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                        }
                        Spacer(minLength: PipiTokens.spacing12)
                        Toggle("", isOn: Binding(
                            get: { store.proactiveCLIDelegationEnabled },
                            set: { store.setProactiveCLIDelegationEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    settingsRowDivider

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
                            Text(agent.kind.displayName)
                                .font(PipiTokens.fontSubheadline.weight(.medium))
                                .foregroundStyle(PipiTokens.textPrimary)

                            HStack(spacing: 4) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 6, height: 6)
                                Text(statusText)
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(statusColor)
                            }

                            Spacer(minLength: PipiTokens.spacing12)

                            Toggle("", isOn: Binding(
                                get: { store.enabledLocalAgents.contains(agent.kind) },
                                set: { store.toggleLocalAgent(agent.kind, enabled: $0, setAsDefaultIfFirst: false) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .disabled(!agent.installed)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
            }

            // Group 5 (Collapsible Advanced): Loopback Unified Gateway & Isolated CLI Injection
            settingsDisclosureCard(
                icon: "slider.horizontal.3",
                title: s.t("高级：本地统一网关与 CLI 隔离注入", "Advanced: Loopback Gateway & CLI Overlays"),
                summary: store.localGatewayStatus.isRunning
                    ? s.t("网关运行中 · \(store.localGatewayStatus.origin)", "Gateway running · \(store.localGatewayStatus.origin)")
                    : s.t("本机回环 OpenAI/Anthropic 兼容网关 · 外部工具环境变量注入", "Loopback OpenAI/Anthropic gateway · Isolated CLI overlays"),
                isExpanded: $showAdvancedLocalRuntime
            ) {
                localUnifiedGatewaySection
                    .padding(PipiTokens.spacing12)
            }
        }
        .task {
            _ = await store.scanLocalModelPlatforms()
        }
    }

    // MARK: - Brigade: Stacked Subscription & CN / OpenAI-Compatible Account Pool

    private var subscriptionAccountPoolSection: some View {
        settingsGroup(
            title: s.t("订阅与国内 / OpenAI 兼容多账号叠加池", "Stacked Subscription & API Account Pool"),
            trailing: {
                Menu {
                    ForEach(PipiSubscriptionPoolStrategy.allCases) { strategy in
                        Button {
                            store.setSubscriptionPoolStrategy(strategy)
                        } label: {
                            if store.subscriptionPoolStrategy == strategy {
                                Label(strategy.label(lang), systemImage: "checkmark")
                            } else {
                                Text(strategy.label(lang))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(store.subscriptionPoolStrategy.label(lang))
                            .font(PipiTokens.fontCaption.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(PipiTokens.buttonSecondaryBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                            .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                }
                .pipiPlainMenu()
            }
        ) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    Text(
                        s.t(
                            "支持复用已付费的 Claude / ChatGPT 订阅，同时支持叠加 DeepSeek、Kimi、智谱 GLM、通义千问、MiniMax、火山方舟、硅基流动及任意第三方 OpenAI 兼容接口的多个账号/Key；单号限流或余额不足时自动无缝切换。",
                            "Stack paid Claude/ChatGPT CLI subscriptions alongside Mainland China providers (DeepSeek, Kimi, Zhipu GLM, Qwen, MiniMax, Volcengine Ark, SiliconFlow) and any OpenAI-compatible relay with automatic failover on 429/quota errors."
                        )
                    )
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)

                    HStack(spacing: PipiTokens.spacing8) {
                        Picker("", selection: $newSubProvider) {
                            ForEach(PipiSubscriptionProviderKind.allCases) { prov in
                                Text(prov.localizedName(lang)).tag(prov)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 185)
                        .onChange(of: newSubProvider) { _, next in
                            newSubBaseURL = next.defaultBaseURL ?? ""
                            newSubModelId = next.defaultModelId
                        }

                        TextField(
                            newSubProvider.isOpenAICompatibleApiPool
                                ? s.t("账号/Key 备注（如 DeepSeek 主号 / 中转站 #2）", "Account/Key label (e.g. DeepSeek Key #2)")
                                : s.t("账号备注（如 Claude Max #2 / 工作号）", "Account label (e.g. Claude Max #2)"),
                            text: $newSubLabel
                        )
                        .textFieldStyle(.roundedBorder)

                        if newSubProvider.isCliSubscription {
                            Toggle(s.t("复用系统默认登录", "System profile"), isOn: $newSubUseSystemDefault)
                                .toggleStyle(.checkbox)
                                .font(PipiTokens.fontCaption)
                        }

                        PipiActionButton(
                            s.t("添加账号", "Add account"),
                            systemImage: "plus",
                            tone: .primary,
                            density: .desktopCompact
                        ) {
                            _ = store.addSubscriptionAccount(
                                provider: newSubProvider,
                                label: newSubLabel,
                                useSystemDefaultProfile: newSubUseSystemDefault,
                                baseURL: newSubProvider.isOpenAICompatibleApiPool ? newSubBaseURL : nil,
                                modelId: newSubModelId.isEmpty ? newSubProvider.defaultModelId : newSubModelId,
                                apiKey: newSubProvider.isOpenAICompatibleApiPool ? newSubApiKey : ""
                            )
                            newSubLabel = ""
                            newSubApiKey = ""
                        }
                    }

                    if newSubProvider.isOpenAICompatibleApiPool {
                        HStack(spacing: PipiTokens.spacing8) {
                            TextField(
                                newSubProvider.defaultBaseURL ?? "https://api.openai.com/v1",
                                text: $newSubBaseURL
                            )
                            .textFieldStyle(.roundedBorder)

                            TextField(
                                newSubProvider.defaultModelId,
                                text: $newSubModelId
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 165)

                            SecureField(
                                s.t("API Key（安全存入钥匙串）", "API Key (saved in Keychain)"),
                                text: $newSubApiKey
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 190)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if !store.subscriptionAccounts.isEmpty {
                    ForEach(store.subscriptionAccounts) { acc in
                        settingsRowDivider
                        subscriptionAccountRow(acc)
                    }
                } else {
                    settingsRowDivider
                    HStack(spacing: PipiTokens.spacing8) {
                        Circle()
                            .fill(PipiTokens.textMuted.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text(s.t("尚未添加叠加账号。支持同时叠加 Claude/ChatGPT 订阅与 DeepSeek/Kimi/智谱/通义千问/第三方 OpenAI 兼容 Key。", "No stacked accounts yet. Add Claude/ChatGPT plans or Mainland China / OpenAI-compatible API keys above for automatic failover."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textMuted)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func subscriptionAccountRow(_ acc: PipiSubscriptionAccountRecord) -> some View {
        let dotColor: Color = {
            switch acc.status {
            case .ready, .active: return PipiTokens.stateSuccess
            case .rateLimited: return PipiTokens.stateWarning
            case .authExpired: return PipiTokens.stateError
            case .disabled: return PipiTokens.textMuted
            }
        }()
        let loginCmd = PipiSubscriptionAccountPoolEngine.interactiveLoginCommand(for: acc)
        let detailText: String = {
            if acc.provider.isOpenAICompatibleApiPool {
                let modelText = acc.modelId ?? acc.provider.defaultModelId
                let endpointHost = URL(string: acc.baseURL ?? "")?.host ?? (acc.baseURL ?? "")
                return s.t(
                    "\(acc.status.label(lang)) · \(modelText) · \(endpointHost) · 请求 \(acc.requestsCount) 次 · 切换 \(acc.failoverCount) 次",
                    "\(acc.status.label(lang)) · \(modelText) · \(endpointHost) · \(acc.requestsCount) reqs · \(acc.failoverCount) failovers"
                )
            }
            return s.t(
                "\(acc.status.label(lang)) · 请求 \(acc.requestsCount) 次 · 切换 \(acc.failoverCount) 次 · \(acc.useSystemDefaultProfile ? "系统默认登录" : "独立隔离目录")",
                "\(acc.status.label(lang)) · \(acc.requestsCount) reqs · \(acc.failoverCount) failovers · \(acc.useSystemDefaultProfile ? "System login" : "Isolated profile")"
            )
        }()

        return HStack(spacing: PipiTokens.spacing12) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(acc.label) · \(acc.provider.localizedName(lang))")
                    .font(PipiTokens.fontSubheadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)

                Text(detailText)
                    .font(PipiTokens.fontMicro.weight(.regular))
                    .foregroundStyle(PipiTokens.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: PipiTokens.spacing8)

            #if os(macOS)
            if acc.provider.isCliSubscription {
                PipiActionButton(
                    copiedSubLoginId == acc.id ? s.t("已复制登录命令", "Copied login") : s.t("复制登录命令", "Login cmd"),
                    systemImage: "terminal",
                    tone: .ghost,
                    density: .desktopCompact
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(loginCmd, forType: .string)
                    copiedSubLoginId = acc.id
                }
            }
            #endif

            if acc.status == .rateLimited || acc.status == .authExpired {
                PipiActionButton(
                    s.t("重置冷却", "Reset"),
                    systemImage: "arrow.clockwise",
                    tone: .secondary,
                    density: .desktopCompact
                ) {
                    store.resetSubscriptionCooldown(accountId: acc.id)
                }
            }

            PipiGhostIconButton(
                systemImage: "trash",
                size: 28,
                iconSize: 12,
                accessibilityLabel: s.delete
            ) {
                store.removeSubscriptionAccount(id: acc.id)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Brigade: 24/7 Cloud Host & Isolated Browsers

    private var cloudBrigadeHostSection: some View {
        let deployCmd = "docker compose -f deploy/cloud/docker-compose.yml up -d"

        return settingsGroup(
            title: s.t("24/7 云端团队主机与独立浏览器", "24/7 Cloud Brigade Host & Isolated Browsers")
        ) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    Text(
                        s.t(
                            "将 AI 队友团队托管在 24/7 云端主机（Docker / VPS / Fly.io），即使合上 Mac 也能持续运行；云端模式下每位队友拥有独立 Chromium 浏览器档案，适配小红书、微信公众号、抖音、微博、知乎、B站、即刻及 LinkedIn、Reddit、X 等平台。",
                            "Run your AI teammate team 24/7 on a cloud host (Docker / VPS / Fly.io) even when your Mac sleeps. Each teammate gets an isolated persistent Chromium browser for Xiaohongshu, WeChat MP, Douyin, Weibo, Zhihu, Bilibili, Jike, LinkedIn, Reddit, and X."
                        )
                    )
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)

                    HStack(spacing: PipiTokens.spacing8) {
                        TextField(
                            "http://127.0.0.1:4242",
                            text: $cloudBrigadeURLDraft
                        )
                        .textFieldStyle(.roundedBorder)

                        SecureField(
                            s.t("可选 Hub Token", "Optional Hub Token"),
                            text: $cloudBrigadeTokenDraft
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)

                        PipiActionButton(
                            cloudBrigadeSyncing ? s.t("同步中…", "Syncing…") : s.t("连接并同步队友", "Connect & sync"),
                            systemImage: "arrow.triangle.2.circlepath",
                            tone: .primary,
                            density: .desktopCompact
                        ) {
                            cloudBrigadeSyncing = true
                            store.updateCloudBrigadeConfig(
                                hostURL: cloudBrigadeURLDraft.isEmpty ? store.cloudBrigadeConfig.cloudHostURL : cloudBrigadeURLDraft,
                                hubToken: cloudBrigadeTokenDraft,
                                autoSync: true
                            )
                            Task {
                                _ = await store.probeAndSyncCloudBrigadeHost()
                                cloudBrigadeSyncing = false
                            }
                        }
                        .disabled(cloudBrigadeSyncing)
                    }

                    HStack(spacing: PipiTokens.spacing8) {
                        Circle()
                            .fill(store.cloudBrigadeConfig.isCloudReachable ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                            .frame(width: 6, height: 6)
                        Text(
                            store.cloudBrigadeConfig.lastHealthSummary
                                ?? s.t(
                                    "当前配置：\(store.cloud24x7TeammatesCount) 位 24/7 云端队友 · \(store.isolatedBrowserTeammatesCount) 个独立浏览器",
                                    "Configured: \(store.cloud24x7TeammatesCount) 24/7 cloud teammates · \(store.isolatedBrowserTeammatesCount) isolated browsers"
                                )
                        )
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                settingsRowDivider

                HStack(spacing: PipiTokens.spacing8) {
                    Text(deployCmd)
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer()
                    #if os(macOS)
                    PipiActionButton(
                        copiedCloudDeployCmd ? s.t("已复制", "Copied") : s.t("复制一键部署命令", "Copy deploy cmd"),
                        systemImage: "doc.on.doc",
                        tone: .ghost,
                        density: .desktopCompact
                    ) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(deployCmd, forType: .string)
                        copiedCloudDeployCmd = true
                    }
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onAppear {
                if cloudBrigadeURLDraft.isEmpty {
                    cloudBrigadeURLDraft = store.cloudBrigadeConfig.cloudHostURL
                }
                if cloudBrigadeTokenDraft.isEmpty {
                    cloudBrigadeTokenDraft = store.cloudBrigadeConfig.cloudHubToken
                }
            }
        }
    }

    // MARK: - Mainstream Installed Local Model Platforms (Ollama / LM Studio / llama.cpp / MLX / vLLM / PolyStrata)

    private var localModelPlatformsSection: some View {
        let installed = store.localModelPlatformManager.installedPlatforms

        return settingsGroup(
            title: s.t("本地模型", "Local Models"),
            trailing: {
                HStack(spacing: 6) {
                    PipiActionButton(
                        store.localModelPlatformManager.isScanning ? s.t("扫描中...", "Scanning...") : s.t("检测", "Scan"),
                        systemImage: "arrow.clockwise",
                        tone: .ghost,
                        density: .desktopCompact
                    ) {
                        Task { _ = await store.scanLocalModelPlatforms() }
                    }

                    PipiActionButton(
                        s.t("添加本地模型", "Add Local Model"),
                        systemImage: "plus",
                        tone: .primary,
                        density: .desktopCompact
                    ) {
                        selectedPlannedCatalogModelId = store.modelAutopilotPlan.primaryModel.id
                        addLocalModelMode = .hardwarePlan
                        showAddLocalModelSheet = true
                    }
                }
            }
        ) {
            if installed.isEmpty {
                HStack(spacing: PipiTokens.spacing12) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 14))
                        .foregroundStyle(PipiTokens.textMuted)
                    Text(s.t("未检测到已启动的本地模型平台，点击右上角「添加本地模型」进行智能规划部署或接入本地引擎。", "No running local platform detected. Click Add Local Model to plan & deploy or connect a local engine."))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                ForEach(Array(installed.enumerated()), id: \.element.id) { idx, platform in
                    if idx > 0 {
                        settingsRowDivider
                    }
                    localPlatformRow(platform)
                }
            }

            if let feedback = localPlatformFeedback ?? store.localModelDeployStatus ?? store.localModelPlatformManager.lastLaunchNote {
                settingsRowDivider
                Text(feedback)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
    }

    private func localPlatformRow(_ platform: PipiLocalPlatformStatus) -> some View {
        let isLaunching = store.localModelPlatformManager.launchingPlatform == platform.kind
        let selectedModel = selectedPlatformModels[platform.kind] ?? platform.availableModels.first ?? platform.kind.defaultFallbackModelId

        return HStack(spacing: PipiTokens.spacing12) {
            Circle()
                .fill(platform.running ? PipiTokens.stateSuccess : PipiTokens.stateWarning)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(platform.kind.displayName)
                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text(platform.running ? s.t("运行中", "Running") : s.t("已安装", "Installed"))
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(platform.running ? PipiTokens.stateSuccess : PipiTokens.stateWarning)
                }
                Text(
                    platform.availableModels.isEmpty
                        ? ":\(platform.kind.defaultPort)"
                        : s.t("发现 \(platform.availableModels.count) 个本地模型", "\(platform.availableModels.count) local models")
                )
                .font(PipiTokens.fontMonoSmall)
                .foregroundStyle(PipiTokens.textMuted)
            }

            Spacer(minLength: 8)

            if !platform.availableModels.isEmpty {
                Menu {
                    ForEach(platform.availableModels, id: \.self) { m in
                        Button {
                            selectedPlatformModels[platform.kind] = m
                        } label: {
                            let display = (m as NSString).lastPathComponent
                            if selectedModel == m {
                                Label(display, systemImage: "checkmark")
                            } else {
                                Text(display)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text((selectedModel as NSString).lastPathComponent)
                            .font(PipiTokens.fontMonoSmall)
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: 164, minHeight: 28, maxHeight: 28)
                    .background(PipiTokens.buttonSecondaryBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                            .strokeBorder(PipiTokens.composerBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                }
                .pipiPlainMenu()
            }

            PipiActionButton(
                isLaunching ? s.t("拉起中...", "Starting...") : s.t("拉起并使用", "Launch & Use"),
                systemImage: platform.running ? "bolt.fill" : "play.fill",
                tone: platform.running ? .secondary : .primary,
                density: .desktopCompact
            ) {
                Task {
                    let res = await store.launchAndUseLocalPlatformModel(
                        platform: platform.kind,
                        modelId: selectedModel
                    )
                    localPlatformFeedback = res.message
                }
            }
            .disabled(isLaunching)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func settingsDisclosureCard<Content: View>(
        icon: String,
        title: String,
        summary: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: PipiTokens.spacing12) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(summary)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PipiTokens.textMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                settingsRowDivider
                content()
            }
        }
        .background(PipiTokens.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }

    // MARK: - Unified Add Local Model Sheet (Option 1: Smart Hardware Plan & Immediate Deploy · Option 2: Connect Existing Platform)

    private var addLocalModelSheet: some View {
        let plan = store.modelAutopilotPlan
        let hw = store.hardwareProfile
        let allCatalogEntries: [PipiLocalModelCatalogEntry] = {
            var seen = Set<String>()
            var ordered: [PipiLocalModelCatalogEntry] = []
            for item in ([plan.primaryModel] + plan.alternatives + PipiModelAutopilot.polyStrataMoECatalog) {
                if seen.insert(item.id).inserted {
                    ordered.append(item)
                }
            }
            return ordered
        }()
        let chosenEntry = allCatalogEntries.first(where: { $0.id == selectedPlannedCatalogModelId }) ?? plan.primaryModel
        let preferredPlatform: PipiLocalModelPlatformKind? = PipiLocalModelPlatformKind(rawValue: selectedDeployPlatformOption)
        let resolvedDeploy = PipiLocalModelPlatformManager.resolveDeploymentTarget(
            for: chosenEntry,
            preferredPlatform: preferredPlatform,
            installed: store.localModelPlatformManager.platforms
        )

        return VStack(spacing: 0) {
            HStack {
                Text(s.t("添加本地模型", "Add Local Model"))
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                Spacer()
                PipiGhostIconButton(
                    systemImage: "xmark",
                    size: 28,
                    iconSize: 12,
                    cornerRadius: PipiTokens.radiusPill,
                    accessibilityLabel: s.close
                ) {
                    showAddLocalModelSheet = false
                }
            }
            .padding(.horizontal, PipiTokens.spacing20)
            .padding(.vertical, PipiTokens.spacing12)
            .background(PipiTokens.bgCanvas)

            Rectangle()
                .fill(PipiTokens.borderSubtle)
                .frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                    PipiSegmentedControl(
                        options: PipiAddLocalModelMode.allCases,
                        selection: $addLocalModelMode,
                        label: { $0.title(s) }
                    )

                    if addLocalModelMode == .hardwarePlan {
                        // Hardware Profile Summary
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "memorychip")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Text("\(hw.cpuModel) · \(hw.cpuCores)C · \(String(format: "%.0f", hw.totalRamGb))GB RAM")
                                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Spacer()
                                Button {
                                    _ = store.refreshHardwareAndModelPlan()
                                    selectedPlannedCatalogModelId = store.modelAutopilotPlan.primaryModel.id
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(PipiTokens.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .help(s.refresh)
                            }
                            Text(
                                s.t(
                                    "可用磁盘 \(String(format: "%.0f", hw.freeDiskGb)) GB · 语言模型内存预算 \(String(format: "%.1f", plan.languageModelMemoryBudgetGb)) GB · 推荐上下文 \(plan.plannedContextWindow / 1024)K",
                                    "Free SSD \(String(format: "%.0f", hw.freeDiskGb)) GB · LM Budget \(String(format: "%.1f", plan.languageModelMemoryBudgetGb)) GB · Context \(plan.plannedContextWindow / 1024)K"
                                )
                            )
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                        }
                        .padding(12)
                        .background(PipiTokens.bgElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))

                        // Planned Model & Engine Selection
                        settingsGroup(title: s.t("选择部署模型与推理平台", "Model & Inference Platform")) {
                            HStack(spacing: PipiTokens.spacing12) {
                                Text(s.t("部署模型", "Model"))
                                    .font(PipiTokens.fontSubheadline.weight(.medium))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Spacer()
                                Menu {
                                    ForEach(allCatalogEntries) { entry in
                                        Button {
                                            selectedPlannedCatalogModelId = entry.id
                                        } label: {
                                            let tag = entry.id == plan.primaryModel.id ? " (\(s.t("推荐", "Recommended")))" : ""
                                            if chosenEntry.id == entry.id {
                                                Label("\(entry.displayName)\(tag)", systemImage: "checkmark")
                                            } else {
                                                Text("\(entry.displayName)\(tag)")
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(chosenEntry.displayName)
                                            .font(PipiTokens.fontCaption.weight(.medium))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                            .lineLimit(1)
                                        Spacer(minLength: 4)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .foregroundStyle(PipiTokens.textMuted)
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(width: 248, height: 32)
                                    .background(PipiTokens.buttonSecondaryBg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                            .strokeBorder(PipiTokens.composerBorder, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                                }
                                .pipiPlainMenu()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)

                            settingsRowDivider

                            HStack(spacing: PipiTokens.spacing12) {
                                Text(s.t("目标推理引擎", "Target Platform"))
                                    .font(PipiTokens.fontSubheadline.weight(.medium))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Spacer()
                                Menu {
                                    Button {
                                        selectedDeployPlatformOption = "auto"
                                    } label: {
                                        let autoLabel = s.t("自动匹配（\(resolvedDeploy.platform.displayName)）", "Auto (\(resolvedDeploy.platform.displayName))")
                                        if selectedDeployPlatformOption == "auto" {
                                            Label(autoLabel, systemImage: "checkmark")
                                        } else {
                                            Text(autoLabel)
                                        }
                                    }
                                    Divider()
                                    ForEach(PipiLocalModelPlatformKind.allCases) { kind in
                                        Button {
                                            selectedDeployPlatformOption = kind.rawValue
                                        } label: {
                                            if selectedDeployPlatformOption == kind.rawValue {
                                                Label(kind.displayName, systemImage: "checkmark")
                                            } else {
                                                Text(kind.displayName)
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(
                                            selectedDeployPlatformOption == "auto"
                                                ? s.t("自动（\(resolvedDeploy.platform.displayName)）", "Auto (\(resolvedDeploy.platform.displayName))")
                                                : (preferredPlatform?.displayName ?? resolvedDeploy.platform.displayName)
                                        )
                                        .font(PipiTokens.fontCaption.weight(.medium))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                        .lineLimit(1)
                                        Spacer(minLength: 4)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .foregroundStyle(PipiTokens.textMuted)
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(width: 248, height: 32)
                                    .background(PipiTokens.buttonSecondaryBg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                            .strokeBorder(PipiTokens.composerBorder, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                                }
                                .pipiPlainMenu()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)

                            settingsRowDivider

                            HStack(spacing: PipiTokens.spacing12) {
                                HStack(spacing: 6) {
                                    Text(s.t("Apple Silicon 分层预取（PolyStrata）", "Apple Silicon Tiered Prefetch"))
                                        .font(PipiTokens.fontSubheadline.weight(.medium))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    PipiInfoHelpButton(
                                        title: s.t("PolyStrata 内存分层预取", "PolyStrata Tiered Prefetch"),
                                        message: s.t("常用模型层常驻统一内存、冷层从 SSD 按需预取；未安装时自动选用 Ollama / LM Studio / MLX / llama.cpp。", "Keeps hot layers in unified memory and prefetches cold layers from SSD; falls back to Ollama, LM Studio, MLX, or llama.cpp.")
                                    )
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { store.localGatewayConfig.enableMacPolyStrataBeta },
                                    set: { next in
                                        var cfg = store.localGatewayConfig
                                        cfg.enableMacPolyStrataBeta = next
                                        store.updateLocalGatewayConfig(cfg)
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }

                        if let status = store.localModelDeployStatus {
                            Text(status)
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(PipiTokens.bgElevated)
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        }

                        HStack(spacing: PipiTokens.spacing8) {
                            PipiActionButton(
                                store.isRunningModelSelfTest ? s.t("自测中...", "Testing...") : s.runQASelfTestAction,
                                systemImage: "checkmark.seal",
                                tone: .secondary,
                                density: .desktopCompact
                            ) {
                                Task { _ = await store.runLocalModelSelfTest() }
                            }
                            .disabled(store.isRunningModelSelfTest)

                            Spacer()

                            PipiActionButton(
                                store.isDeployingLocalModel ? s.t("正在部署...", "Deploying...") : s.t("立即部署", "Deploy Now"),
                                systemImage: "arrow.down.circle.fill",
                                tone: .primary,
                                density: .desktopCompact
                            ) {
                                Task {
                                    let res = await store.deployPlannedLocalModel(
                                        entry: chosenEntry,
                                        preferredPlatform: preferredPlatform
                                    )
                                    localPlatformFeedback = res.message
                                    if res.succeeded {
                                        showAddLocalModelSheet = false
                                    }
                                }
                            }
                            .disabled(store.isDeployingLocalModel)
                        }
                    } else {
                        // Option 2: Connect Existing Local Platform or Custom Loopback Server
                        settingsGroup(title: s.t("接入已安装平台或自定义回环服务", "Connect Local Platform or Loopback Server")) {
                            HStack(spacing: PipiTokens.spacing12) {
                                Text(s.t("本地平台", "Platform"))
                                    .font(PipiTokens.fontSubheadline.weight(.medium))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Spacer()
                                PipiSelectMenu(
                                    options: PipiLocalModelPlatformKind.allCases,
                                    selection: $customLocalPlatformDraft,
                                    width: 220
                                ) { kind in
                                    kind.displayName
                                }
                                .onChange(of: customLocalPlatformDraft) { _, next in
                                    customLocalEndpointDraft = next.openAIBaseURL
                                    if let found = store.localModelPlatformManager.platforms.first(where: { $0.kind == next }),
                                       let firstModel = found.availableModels.first {
                                        customLocalModelDraft = firstModel
                                    } else {
                                        customLocalModelDraft = next.defaultFallbackModelId
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)

                            settingsRowDivider

                            VStack(alignment: .leading, spacing: 8) {
                                Text(s.t("本地服务地址", "Local Endpoint URL"))
                                    .font(PipiTokens.fontMicro.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textMuted)
                                PipiTextField("http://127.0.0.1:11434", text: $customLocalEndpointDraft, monospaced: true, height: 32)

                                Text(s.t("模型名称 / 本地权重路径", "Model ID / GGUF Path"))
                                    .font(PipiTokens.fontMicro.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textMuted)
                                    .padding(.top, 2)
                                PipiTextField(customLocalPlatformDraft.defaultFallbackModelId, text: $customLocalModelDraft, monospaced: true, height: 32)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }

                        HStack {
                            Spacer()
                            PipiActionButton(
                                s.t("拉起并添加", "Launch & Add"),
                                systemImage: "play.fill",
                                tone: .primary,
                                density: .desktopCompact
                            ) {
                                let trimmedURL = customLocalEndpointDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                let trimmedModel = customLocalModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmedModel.isEmpty else { return }
                                Task {
                                    let res = await store.launchAndUseLocalPlatformModel(
                                        platform: customLocalPlatformDraft,
                                        modelId: trimmedModel
                                    )
                                    if !res.succeeded && !trimmedURL.isEmpty {
                                        // Allow registering a running custom loopback endpoint directly
                                        let cfg = PipiLLMProviderConfig(
                                            id: "local_\(customLocalPlatformDraft.rawValue)_\(UUID().uuidString.prefix(4).lowercased())",
                                            name: customLocalPlatformDraft.displayName,
                                            kind: customLocalPlatformDraft.providerKind,
                                            baseURL: trimmedURL,
                                            apiKey: customLocalPlatformDraft == .ollama ? "" : "local-engine",
                                            modelId: trimmedModel,
                                            isEnabled: true
                                        )
                                        store.upsertLLMProvider(cfg, setAsDefault: true)
                                        localPlatformFeedback = s.t("已添加本地模型 \(trimmedModel)", "Added local model \(trimmedModel)")
                                    } else {
                                        localPlatformFeedback = res.message
                                    }
                                    showAddLocalModelSheet = false
                                }
                            }
                        }
                    }
                }
                .padding(PipiTokens.spacing20)
            }
            .pipiHideScrollbars()
            .background(PipiTokens.bgCanvas)
        }
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
        .task {
            _ = await store.scanLocalModelPlatforms()
        }
    }

    // MARK: - Wave 4 (#07) Local Unified LLM Gateway & CLI Reverse Injection Section

    private var localUnifiedGatewaySection: some View {
        settingsGroup(
            title: s.localGatewayTitle,
            trailing: {
                if store.localGatewayStatus.isRunning {
                    PipiActionButton(s.stopGatewayAction, systemImage: "stop.circle", tone: .ghost, density: .desktopCompact) {
                        Task {
                            await store.stopLocalGateway()
                            gatewayActionFeedback = s.t("本地服务已停止", "Local service stopped")
                        }
                    }
                } else {
                    PipiActionButton(s.startGatewayAction, systemImage: "play.circle.fill", tone: .primary, density: .desktopCompact) {
                        Task {
                            do {
                                let status = try await store.startLocalGateway()
                                gatewayActionFeedback = s.t("已监听 \(status.origin)", "Listening on \(status.origin)")
                            } catch {
                                gatewayActionFeedback = error.localizedDescription
                            }
                        }
                    }
                }
            }
        ) {
            // Active Model Source Mode
            HStack(spacing: PipiTokens.spacing12) {
                HStack(spacing: 6) {
                    Text(s.t("模型来源", "Model Source"))
                        .font(PipiTokens.fontSubheadline.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)
                    PipiInfoHelpButton(
                        title: s.t("模型来源", "Model Source"),
                        message: s.t("在本地模型、订阅工具与自定义 API 间切换；离开本地模式时自动释放内存。", "Switch among Local, Subscription, and BYOK; leaving Local automatically frees memory.")
                    )
                }
                Spacer(minLength: PipiTokens.spacing12)
                PipiSelectMenu(
                    options: PipiModelSourceMode.allCases,
                    selection: Binding(
                        get: { store.localGatewayConfig.sourceMode },
                        set: { nextMode in
                            Task {
                                let res = await store.switchModelSourceMode(nextMode, confirmedInterruptActiveRuns: true)
                                gatewayActionFeedback = res.message
                            }
                        }
                    ),
                    width: 204
                ) { mode in
                    mode.label(lang)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            settingsRowDivider

            // Loopback Status & Local Upstream Endpoint
            VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                HStack(spacing: PipiTokens.spacing8) {
                    Circle()
                        .fill(store.localGatewayStatus.isRunning ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                        .frame(width: 7, height: 7)
                    Text(
                        store.localGatewayStatus.isRunning
                            ? s.t("运行中 · \(store.localGatewayStatus.origin)", "Running · \(store.localGatewayStatus.origin)")
                            : s.t("未启动 · 仅监听本机 127.0.0.1", "Stopped · Loopback 127.0.0.1 only")
                    )
                    .font(PipiTokens.fontCaption.weight(.medium))
                    .foregroundStyle(PipiTokens.textPrimary)
                    Spacer()
                }

                HStack(spacing: PipiTokens.spacing12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.t("本地上游地址", "Upstream URL"))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textMuted)
                        PipiTextField(
                            "http://127.0.0.1:11438/v1",
                            text: Binding(
                                get: { store.localGatewayConfig.localUpstreamBaseURL },
                                set: { val in
                                    var cfg = store.localGatewayConfig
                                    cfg.localUpstreamBaseURL = val
                                    store.updateLocalGatewayConfig(cfg)
                                }
                            ),
                            monospaced: true,
                            height: 32
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.t("模型标识", "Model ID"))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textMuted)
                        PipiTextField(
                            "qwen3.8-27b-ud-q4_k_m",
                            text: Binding(
                                get: { store.localGatewayConfig.selectedLocalModelId },
                                set: { val in
                                    var cfg = store.localGatewayConfig
                                    cfg.selectedLocalModelId = val
                                    store.updateLocalGatewayConfig(cfg)
                                }
                            ),
                            monospaced: true,
                            height: 32
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            settingsRowDivider

            // Reverse-Inject into CLI Agents via Isolated Environment Overlays
            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                HStack(spacing: PipiTokens.spacing12) {
                    HStack(spacing: 6) {
                        Text(s.reverseInjectCLITitle)
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(title: s.reverseInjectCLITitle, message: s.reverseInjectCLIDesc)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { store.localGatewayConfig.reverseInjectCLIAgents },
                        set: { next in
                            var cfg = store.localGatewayConfig
                            cfg.reverseInjectCLIAgents = next
                            store.updateLocalGatewayConfig(cfg)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                HStack(spacing: PipiTokens.spacing8) {
                    PipiActionButton(s.t("查看隔离目录", "Inspect Isolation Paths"), systemImage: "folder.badge.gearshape", tone: .ghost, density: .desktopCompact) {
                        Task {
                            do {
                                let claude = try await store.prepareIsolatedCLIOverlay(for: .claudeCode)
                                let codex = try await store.prepareIsolatedCLIOverlay(for: .codex)
                                let pi = try await store.prepareIsolatedCLIOverlay(for: .pi)
                                overlayPreviewMessage = "CLAUDE_CONFIG_DIR=\(claude.overlayDir.path)\nCODEX_HOME=\(codex.overlayDir.path)\nPI_CODING_AGENT_DIR=\(pi.overlayDir.path)"
                            } catch {
                                overlayPreviewMessage = error.localizedDescription
                            }
                        }
                    }
                    Spacer()
                }

                if let msg = overlayPreviewMessage ?? gatewayActionFeedback {
                    Text(msg)
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PipiTokens.bgSurfaceHover)
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 2.5 Personal Daily Voice Tab (Wave 4 · #10: On-Device First + BYOK Cloud API)

    private var voiceTab: some View {
        let allowsCloud = store.voiceConfig.privacyPolicy != .onDeviceOnly
        let timbres = PipiDailyVoiceEngine.availableVoiceTimbres()
        let selectedTimbre = PipiDailyVoiceEngine.resolveTimbre(id: store.voiceConfig.selectedVoiceProfileId)

        return VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
            // Group 1: Timbre, Speech Rate & Auto Playback
            settingsGroup(title: s.t("音色与通话播报", "Voice Timbre & Playback")) {
                // Multi-voice timbre selector + live preview
                HStack(spacing: PipiTokens.spacing8) {
                    HStack(spacing: 6) {
                        Text(s.t("默认音色", "Default Timbre"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(
                            title: s.t("多音色配置", "Voice Timbres"),
                            message: s.t("选择全局默认音色；您也可以在每个智能体的编辑页为其指定专属音色。", "Choose the global default voice; each assistant can also override with its own dedicated timbre.")
                        )
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    PipiSelectMenu(
                        options: timbres,
                        selection: Binding(
                            get: { selectedTimbre },
                            set: { next in
                                var cfg = store.voiceConfig
                                cfg.selectedVoiceProfileId = next.id
                                if let cloudVoice = next.cloudVoiceName {
                                    cfg.cloudTts.voiceName = cloudVoice
                                }
                                store.updateVoiceConfig(cfg)
                            }
                        ),
                        width: 212
                    ) { option in
                        option.displayName(lang)
                    }
                    PipiActionButton(s.t("试听", "Preview"), systemImage: "play.fill", tone: .secondary, density: .desktopCompact) {
                        store.previewVoiceProfile(selectedTimbre.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                settingsRowDivider

                // Speech rate slider
                HStack(spacing: PipiTokens.spacing12) {
                    Text(s.t("播报语速", "Speech Rate"))
                        .font(PipiTokens.fontSubheadline.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Spacer()
                    Text(String(format: "%.2fx", store.voiceConfig.speechRate))
                        .font(PipiTokens.fontMonoSmall)
                        .monospacedDigit()
                        .foregroundStyle(PipiTokens.textSecondary)
                        .frame(width: 44, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { store.voiceConfig.speechRate },
                            set: { val in
                                var cfg = store.voiceConfig
                                cfg.speechRate = val
                                store.updateVoiceConfig(cfg)
                            }
                        ),
                        in: 0.70...1.40,
                        step: 0.05
                    )
                    .frame(width: 176)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                settingsRowDivider

                // Auto speak replies
                HStack(spacing: PipiTokens.spacing12) {
                    HStack(spacing: 6) {
                        Text(s.t("回复自动语音播报", "Auto-Speak Replies"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(
                            title: s.t("回复自动语音播报", "Auto-Speak Replies"),
                            message: s.t("语音通话模式下自动播报回复内容，播报期间开口可随时打断。", "Reads responses aloud in Voice Call mode with instant speech interruption.")
                        )
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { store.voiceConfig.autoSpeakMuseReplies },
                        set: { val in
                            var cfg = store.voiceConfig
                            cfg.autoSpeakMuseReplies = val
                            store.updateVoiceConfig(cfg)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                settingsRowDivider

                HStack(spacing: PipiTokens.spacing12) {
                    HStack(spacing: 6) {
                        Text(s.t("语音隐私策略", "Voice Privacy Policy"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(
                            title: s.t("语音隐私策略", "Voice Privacy Policy"),
                            message: s.t("「仅端侧」模式下所有识别与合成均在本机完成，不向外部发送音频数据。", "On-Device Only processes all speech locally with zero audio egress.")
                        )
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    PipiSelectMenu(
                        options: PipiVoicePrivacyPolicy.allCases,
                        selection: Binding(
                            get: { store.voiceConfig.privacyPolicy },
                            set: { val in
                                var cfg = store.voiceConfig
                                cfg.privacyPolicy = val
                                store.updateVoiceConfig(cfg)
                            }
                        ),
                        width: 212
                    ) { policy in
                        policy.label(lang)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Collapsible Advanced Voice Parameters & Cloud BYOK Engines
            settingsDisclosureCard(
                icon: "slider.horizontal.3",
                title: s.t("高级：识别灵敏度与语音引擎", "Advanced: Recognition & Voice Engines"),
                summary: s.t(
                    "\(store.voiceConfig.preferredSttProvider.label(lang)) · \(store.voiceConfig.preferredTtsProvider.label(lang))",
                    "\(store.voiceConfig.preferredSttProvider.label(lang)) · \(store.voiceConfig.preferredTtsProvider.label(lang))"
                ),
                isExpanded: $showAdvancedVoiceSettings
            ) {
                VStack(spacing: 0) {
                    HStack(spacing: PipiTokens.spacing12) {
                        Text(s.t("默认语音模式", "Default Voice Mode"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Spacer()
                        PipiSelectMenu(
                            options: PipiVoiceInteractionMode.allCases,
                            selection: Binding(
                                get: { store.voiceConfig.defaultMode },
                                set: { val in
                                    var cfg = store.voiceConfig
                                    cfg.defaultMode = val
                                    store.updateVoiceConfig(cfg)
                                }
                            ),
                            width: 212
                        ) { mode in
                            mode.label(lang)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)

                    settingsRowDivider

                    HStack(spacing: PipiTokens.spacing12) {
                        HStack(spacing: 6) {
                            Text(s.t("人声检测灵敏度", "Voice Sensitivity"))
                                .font(PipiTokens.fontSubheadline.weight(.medium))
                                .foregroundStyle(PipiTokens.textPrimary)
                            PipiInfoHelpButton(
                                title: s.t("人声检测与回声过滤", "Voice Detection & Echo Gate"),
                                message: s.t("播音期间自动提高收音门槛以过滤扬声器回声，检测到连续人声即停止播报并切换聆听。", "Raises threshold while speaking to reject speaker echo and switches to listening on sustained user speech.")
                            )
                        }
                        Spacer()
                        Text(String(format: "%.2f", store.voiceConfig.vadSensitivity))
                            .font(PipiTokens.fontMonoSmall)
                            .monospacedDigit()
                            .foregroundStyle(PipiTokens.textSecondary)
                            .frame(width: 44, alignment: .trailing)
                        Slider(
                            value: Binding(
                                get: { store.voiceConfig.vadSensitivity },
                                set: { val in
                                    var cfg = store.voiceConfig
                                    cfg.vadSensitivity = val
                                    store.updateVoiceConfig(cfg)
                                }
                            ),
                            in: 0.15...0.95,
                            step: 0.05
                        )
                        .frame(width: 176)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)

                    settingsRowDivider

                    HStack(spacing: PipiTokens.spacing12) {
                        Text(s.t("播音期防回声倍率", "Echo Filter Multiplier"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Spacer()
                        Text(String(format: "%.1fx", store.voiceConfig.echoGateMultiplier))
                            .font(PipiTokens.fontMonoSmall)
                            .monospacedDigit()
                            .foregroundStyle(PipiTokens.textSecondary)
                            .frame(width: 44, alignment: .trailing)
                        Slider(
                            value: Binding(
                                get: { store.voiceConfig.echoGateMultiplier },
                                set: { val in
                                    var cfg = store.voiceConfig
                                    cfg.echoGateMultiplier = val
                                    store.updateVoiceConfig(cfg)
                                }
                            ),
                            in: 1.6...4.0,
                            step: 0.2
                        )
                        .frame(width: 176)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)

                    settingsRowDivider

                    HStack(spacing: PipiTokens.spacing12) {
                        Text(s.t("语音识别引擎", "Speech Recognition"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Spacer()
                        PipiSelectMenu(
                            options: [PipiVoiceEngineProvider.appleOnDevice, .whisperKit, .mlxAudio, .openaiByok, .deepgramByok, .customByok],
                            selection: Binding(
                                get: { store.voiceConfig.preferredSttProvider },
                                set: { val in
                                    var cfg = store.voiceConfig
                                    cfg.preferredSttProvider = val
                                    store.updateVoiceConfig(cfg)
                                }
                            ),
                            width: 212
                        ) { p in
                            p.label(lang)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)

                    settingsRowDivider

                    HStack(spacing: PipiTokens.spacing12) {
                        Text(s.t("语音合成引擎", "Speech Synthesis"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Spacer()
                        PipiSelectMenu(
                            options: [PipiVoiceEngineProvider.appleOnDevice, .mlxAudio, .openaiByok, .elevenlabsByok, .customByok],
                            selection: Binding(
                                get: { store.voiceConfig.preferredTtsProvider },
                                set: { val in
                                    var cfg = store.voiceConfig
                                    cfg.preferredTtsProvider = val
                                    store.updateVoiceConfig(cfg)
                                }
                            ),
                            width: 212
                        ) { p in
                            p.label(lang)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)

                    if allowsCloud {
                        settingsRowDivider

                        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                            HStack(spacing: 6) {
                                Text(s.t("云端语音接口与音色", "Cloud Voice API & Timbre"))
                                    .font(PipiTokens.fontCaption.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textSecondary)
                                PipiInfoHelpButton(
                                    title: s.t("密钥存储", "Credential Storage"),
                                    message: s.t("云端语音密钥仅存储于 macOS 钥匙串（Keychain），不以明文写入本地文件。", "Cloud voice API keys are stored exclusively in macOS Keychain.")
                                )
                                Spacer()
                                Menu {
                                    ForEach(PipiVoiceTimbreOption.cloudVoiceNames, id: \.self) { voiceName in
                                        Button {
                                            var cfg = store.voiceConfig
                                            cfg.cloudTts.voiceName = voiceName
                                            store.updateVoiceConfig(cfg)
                                        } label: {
                                            if store.voiceConfig.cloudTts.voiceName == voiceName {
                                                Label(voiceName, systemImage: "checkmark")
                                            } else {
                                                Text(voiceName)
                                            }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(s.t("云端音色：\(store.voiceConfig.cloudTts.voiceName)", "Cloud Voice: \(store.voiceConfig.cloudTts.voiceName)"))
                                            .font(PipiTokens.fontCaption.weight(.medium))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .foregroundStyle(PipiTokens.textMuted)
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background(PipiTokens.buttonSecondaryBg)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                            .strokeBorder(PipiTokens.composerBorder, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                                }
                                .pipiPlainMenu()
                            }

                            HStack(spacing: PipiTokens.spacing12) {
                                PipiTextField(
                                    "https://api.openai.com/v1",
                                    text: Binding(
                                        get: { store.voiceConfig.cloudStt.baseURL },
                                        set: { val in
                                            var cfg = store.voiceConfig
                                            cfg.cloudStt.baseURL = val
                                            store.updateVoiceConfig(cfg)
                                        }
                                    ),
                                    monospaced: true,
                                    height: 32
                                )
                                PipiTextField(
                                    "gpt-4o-mini-transcribe",
                                    text: Binding(
                                        get: { store.voiceConfig.cloudStt.modelId },
                                        set: { val in
                                            var cfg = store.voiceConfig
                                            cfg.cloudStt.modelId = val
                                            store.updateVoiceConfig(cfg)
                                        }
                                    ),
                                    monospaced: true,
                                    height: 32
                                )
                            }

                            HStack(spacing: PipiTokens.spacing12) {
                                PipiSecureField(s.t("识别 API Key", "STT API Key"), text: $cloudSttKeyDraft, height: 32)
                                PipiSecureField(s.t("合成 API Key", "TTS API Key"), text: $cloudTtsKeyDraft, height: 32)
                                PipiActionButton(s.save, systemImage: "key.fill", tone: .secondary, density: .desktopCompact) {
                                    store.setVoiceCloudSttApiKey(cloudSttKeyDraft)
                                    store.setVoiceCloudTtsApiKey(cloudTtsKeyDraft)
                                    voiceKeysSavedBanner = true
                                }
                            }

                            if voiceKeysSavedBanner {
                                Text(s.t("密钥已保存至系统钥匙串。", "Credentials saved to Keychain."))
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.stateSuccess)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .onAppear {
                            if !voiceKeysLoaded {
                                cloudSttKeyDraft = store.voiceCloudSttApiKey()
                                cloudTtsKeyDraft = store.voiceCloudTtsApiKey()
                                voiceKeysLoaded = true
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 3. Remote Access Tab (Unified Account Auto-Relay + WeChat iLink + Advanced)

    private var remoteAccessTab: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
            // Section 1: Unified Account & My Devices (Auto-Connects Free E2EE Relay seamlessly)
            unifiedAccountSection

            // Section 2: WeChat iLink Remote Assistant
            wechatILinkRemoteSection

            // Section 2.5: 24/7 Cloud Brigade Host & Per-Teammate Isolated Browsers
            cloudBrigadeHostSection

            // Section 3 (Collapsed): Advanced Multi-Machine Mesh & Local Bridge
            settingsDisclosureCard(
                icon: "network",
                title: s.t("高级：多机互联与本地桥接", "Advanced: Multi-Machine Mesh & Local Bridge"),
                summary: store.meshHubClient.isConnected
                    ? s.t("已连接 Mesh Hub · 在线 \(store.meshHubClient.nodes.filter(\.isOnline).count) 台节点", "Mesh Hub connected · \(store.meshHubClient.nodes.filter(\.isOnline).count) nodes online")
                    : s.t("面向开发者：连接 Linux / GPU 节点或本地 HTTP 桥接", "For power users: connect Linux/GPU nodes or local HTTP bridge"),
                isExpanded: $showAdvancedMultiMachineMesh
            ) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                        Text(s.t("多机互联 Mesh Hub（Linux / Mac / GPU 节点）", "Multi-Machine Mesh Hub (Linux / Mac / GPU Nodes)"))
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)

                        Text(s.t("支持连接本机或自建 Linux VPS Hub，加入后的远程主机可直接参与对话与群聊 @协作。", "Connect to a local or self-hosted Linux VPS Hub so remote machines can join chats and @mentions."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textMuted)

                        HStack(spacing: PipiTokens.spacing8) {
                            TextField("http://127.0.0.1:4242", text: $meshHubURLDraft)
                                .textFieldStyle(.roundedBorder)
                            SecureField(s.t("可选 Hub Token", "Optional Hub Token"), text: $meshHubTokenDraft)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                            PipiActionButton(
                                s.t("连接节点", "Connect"),
                                systemImage: "network",
                                tone: .primary,
                                density: .desktopCompact
                            ) {
                                Task { await store.connectMeshHub(url: meshHubURLDraft, token: meshHubTokenDraft) }
                            }
                        }

                        HStack(spacing: PipiTokens.spacing8) {
                            Circle()
                                .fill(store.meshHubClient.isConnected ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                .frame(width: 7, height: 7)
                            Text(store.meshHubClient.isConnected
                                 ? s.t("已连接 · 在线节点 \(store.meshHubClient.nodes.filter(\.isOnline).count) 台", "Connected · \(store.meshHubClient.nodes.filter(\.isOnline).count) online nodes")
                                 : (store.meshHubClient.lastError ?? s.t("未连接 Mesh Hub", "Mesh Hub offline")))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                            Spacer()
                        }

                        if !store.meshHubClient.nodes.isEmpty {
                            VStack(spacing: PipiTokens.spacing8) {
                                ForEach(store.meshHubClient.nodes) { node in
                                    HStack(spacing: PipiTokens.spacing8) {
                                        Circle()
                                            .fill(node.isOnline ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                            .frame(width: 7, height: 7)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(node.name) · \(node.platformBadge)/\(node.arch)")
                                                .font(PipiTokens.fontCaption.weight(.semibold))
                                                .foregroundStyle(PipiTokens.textPrimary)
                                            Text("\(node.workspacePath)" + (node.telemetry.gpuSummary.map { " · GPU: \($0)" } ?? ""))
                                                .font(PipiTokens.fontMicro)
                                                .foregroundStyle(PipiTokens.textMuted)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Text(node.activeTaskCount > 0 ? s.t("并行 \(node.activeTaskCount) 任务", "\(node.activeTaskCount) active") : (node.isOnline ? s.t("在线", "Online") : s.t("离线", "Offline")))
                                            .font(PipiTokens.fontMicro.weight(.medium))
                                            .foregroundStyle(node.isOnline ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(PipiTokens.bgSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                                }
                            }
                        }

                        HStack(spacing: PipiTokens.spacing8) {
                            TextField(s.t("新节点名（如 linux-4090）", "Node name (e.g. linux-4090)"), text: $meshNodeJoinNameDraft)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                            Text(store.meshHubClient.buildNodeJoinCommand(nodeName: meshNodeJoinNameDraft))
                                .font(PipiTokens.fontMonoSmall)
                                .foregroundStyle(PipiTokens.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            PipiActionButton(
                                copiedMeshJoinCmd ? s.t("已复制", "Copied") : s.t("复制接入命令", "Copy Cmd"),
                                systemImage: copiedMeshJoinCmd ? "checkmark" : "doc.on.doc",
                                tone: .secondary,
                                density: .desktopCompact
                            ) {
                                copyToPasteboard(store.meshHubClient.buildNodeJoinCommand(nodeName: meshNodeJoinNameDraft))
                                copiedMeshJoinCmd = true
                            }
                        }
                    }

                    settingsRowDivider

                    VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                        HStack {
                            HStack(spacing: 6) {
                                Text(s.companionSyncToggleTitle)
                                    .font(PipiTokens.fontSubheadline.weight(.medium))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                PipiInfoHelpButton(title: s.companionSyncToggleTitle, message: s.companionSyncToggleDesc)
                            }
                            Spacer(minLength: PipiTokens.spacing12)
                            Toggle("", isOn: Binding(
                                get: { store.companionSyncEnabled },
                                set: { store.setCompanionSyncEnabled($0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }

                        if store.companionSyncEnabled {
                            HStack(spacing: PipiTokens.spacing12) {
                                Text(s.endpointUrlLabel)
                                    .font(PipiTokens.fontCaption.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textSecondary)
                                PipiTextField("http://127.0.0.1:4242", text: $store.daemonEndpoint, monospaced: true, height: 32)
                                PipiActionButton(s.refresh, systemImage: "arrow.clockwise", tone: .secondary, density: .desktopCompact) {
                                    Task {
                                        await store.bridgeSupervisor.ensureBridgeRunning()
                                        await store.refreshAllFromDaemon()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Remote Section 0: Unified Account & My Devices

    private var unifiedAccountSection: some View {
        let acct = store.accountClient
        return settingsGroup(
            title: s.t("PiPiBot 统一账号与我的设备", "PiPiBot Account & My Devices"),
            trailing: {
                if acct.isSignedIn {
                    HStack(spacing: 6) {
                        #if os(macOS)
                        PipiActionButton(s.t("打开网页端", "Open Web"), systemImage: "safari", tone: .primary, density: .desktopCompact) {
                            if let url = URL(string: "\(acct.relayOrigin)/login") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        #endif
                        PipiActionButton(s.t("退出", "Sign Out"), tone: .ghost, density: .desktopCompact) {
                            Task {
                                await acct.logout()
                                store.e2eeRelayClient.accountAccessToken = nil
                                accountOtpSent = false
                                accountOtpDraft = ""
                            }
                        }
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                if let user = acct.currentUser {
                    HStack(spacing: PipiTokens.spacing12) {
                        Circle()
                            .fill(PipiTokens.stateSuccess)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.email ?? user.displayName)
                                .font(PipiTokens.fontSubheadline.weight(.semibold))
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text(s.t("已自动接入 pipibot.jimizhou.com 免费加密中转 · 手机/网页端登录即可秒连", "Auto-connected to pipibot.jimizhou.com free E2EE relay"))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                        }
                        Spacer()
                    }

                    if !acct.devices.isEmpty {
                        settingsRowDivider
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.t("账号下的设备（\(acct.devices.count) 台）", "Devices on Your Account (\(acct.devices.count))"))
                                .font(PipiTokens.fontCaption.weight(.semibold))
                                .foregroundStyle(PipiTokens.textSecondary)

                            ForEach(acct.devices) { dev in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(dev.isOnline ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                        .frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("\(dev.name) · \(dev.platform)")
                                            .font(PipiTokens.fontCaption.weight(.semibold))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                        if !dev.capabilities.isEmpty {
                                            Text(dev.capabilities.joined(separator: " · "))
                                                .font(PipiTokens.fontMicro)
                                                .foregroundStyle(PipiTokens.textMuted)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Text(dev.isOnline ? s.t("在线", "Online") : s.t("离线", "Offline"))
                                        .font(PipiTokens.fontMicro.weight(.medium))
                                        .foregroundStyle(dev.isOnline ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                    PipiActionButton(s.t("移除", "Remove"), tone: .ghost, density: .desktopCompact) {
                                        Task { await acct.removeDevice(id: dev.id) }
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(PipiTokens.bgSurface)
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                            }
                        }
                    }
                } else {
                    Text(s.t("登录一次即可让 Mac 自动常驻免费加密中转，手机 iOS、网页端与 Linux/PC CLI 共用同一套账号与设备列表（聊天与文件绝不上传明文）。", "Sign in once so this Mac auto-connects to the free E2EE relay across Mac, iOS, Web, and CLI (zero plaintext stored on relay)."))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)

                    HStack(spacing: PipiTokens.spacing8) {
                        TextField(s.t("输入邮箱（QQ / 163 / 企业邮箱 / Gmail）", "Enter email address"), text: $accountEmailDraft)
                            .textFieldStyle(.roundedBorder)
                        PipiActionButton(
                            accountOtpSent ? s.t("重新发送", "Resend") : s.t("获取验证码", "Send Code"),
                            tone: .secondary,
                            density: .desktopCompact
                        ) {
                            Task {
                                let res = await acct.sendEmailOtp(email: accountEmailDraft)
                                accountFeedback = res.message
                                if res.ok { accountOtpSent = true }
                            }
                        }
                    }

                    if accountOtpSent {
                        HStack(spacing: PipiTokens.spacing8) {
                            TextField(s.t("输入 6 位邮箱验证码", "6-digit code"), text: $accountOtpDraft)
                                .textFieldStyle(.roundedBorder)
                            PipiActionButton(s.t("验证并登录", "Sign In"), tone: .primary, density: .desktopCompact) {
                                Task {
                                    let res = await acct.verifyEmailOtp(email: accountEmailDraft, code: accountOtpDraft)
                                    accountFeedback = res.message
                                    if res.ok {
                                        accountOtpSent = false
                                        accountOtpDraft = ""
                                        await store.syncAccountAndAutoConnectRelay()
                                    }
                                }
                            }
                        }
                    }

                    HStack(spacing: PipiTokens.spacing8) {
                        PipiActionButton(
                            s.t("使用 Apple / GitHub / Google 登录", "Sign in with Apple / GitHub / Google"),
                            systemImage: "person.badge.key",
                            tone: .primary,
                            density: .desktopCompact
                        ) {
                            Task {
                                await acct.startBrowserOAuthLogin {
                                    Task { await store.syncAccountAndAutoConnectRelay() }
                                }
                            }
                        }
                        if let code = acct.pendingBrowserUserCode {
                            Text(s.t("授权码：\(code)", "Code: \(code)"))
                                .font(PipiTokens.fontMonoSmall.weight(.semibold))
                                .foregroundStyle(PipiTokens.textPrimary)
                        }
                    }

                    if let fb = accountFeedback ?? acct.statusMessage {
                        Text(fb)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .task {
            await store.syncAccountAndAutoConnectRelay()
        }
    }

    // MARK: - Remote Section A: PiPiBot Encrypted Relay Service (pipibot.jimizhou.com)

    private var pipibotEncryptedRelaySection: some View {
        let relayState = store.e2eeRelayClient.state
        let isConnected = (relayState == .connected)
        let isConnecting = (relayState == .connecting || relayState == .reconnecting)
        let devices = store.listPairedDevices().filter { !$0.revoked }

        let statusDotColor: Color = {
            switch relayState {
            case .connected: return PipiTokens.stateSuccess
            case .connecting, .reconnecting: return PipiTokens.stateWarning
            case .error: return PipiTokens.stateError
            case .disabled: return PipiTokens.textMuted
            }
        }()
        let statusText: String = {
            switch relayState {
            case .connected:
                return s.t("已连接加密中转（手机扫码即可访问）", "Connected · Ready for Mobile Scan")
            case .connecting:
                return s.t("正在连接加密中转服务...", "Connecting to Encrypted Relay...")
            case .reconnecting:
                return s.t("网络波动，正在自动重连...", "Reconnecting...")
            case .error:
                return store.e2eeRelayClient.lastStatusMessage ?? s.t("连接异常，请稍后重试", "Connection error")
            case .disabled:
                return s.t("未开启", "Off")
            }
        }()

        return settingsGroup(
            title: s.t("PiPiBot 加密中转服务（手机 / 网页远程访问）", "PiPiBot Encrypted Relay (Mobile & Web)"),
            trailing: {
                HStack(spacing: 6) {
                    if isConnected || isConnecting {
                        PipiActionButton(
                            s.t("刷新配对码", "Refresh QR"),
                            systemImage: "arrow.clockwise",
                            tone: .secondary,
                            density: .desktopCompact
                        ) {
                            _ = store.generateUniversalPairingLink()
                        }
                        PipiActionButton(
                            s.t("断开连接", "Disconnect"),
                            systemImage: "stop.fill",
                            tone: .destructive,
                            density: .desktopCompact
                        ) {
                            store.stopUniversalE2EERelay()
                        }
                    } else {
                        PipiActionButton(
                            s.t("开启加密中转", "Enable Relay"),
                            systemImage: "qrcode",
                            tone: .primary,
                            density: .desktopCompact
                        ) {
                            _ = store.startUniversalE2EERelay()
                        }
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                HStack(spacing: PipiTokens.spacing8) {
                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Spacer()
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PipiTokens.stateSuccess)
                        Text("pipibot.jimizhou.com")
                            .font(PipiTokens.fontMonoSmall)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PipiTokens.bgSurface, in: Capsule())

                    PipiInfoHelpButton(
                        title: s.t("PiPiBot 免费加密中转说明", "About PiPiBot Encrypted Relay"),
                        message: s.t(
                            "无需安装第三方命令行组件，也无需配置公网 IP。开启后使用免费公共中转（pipibot.jimizhou.com），手机浏览器扫码即可添加到主屏幕远程对话与审批；所有消息均在设备端到端加密，中转服务器无法解密。",
                            "No third-party CLI or public IP needed. Connects via the free public relay (pipibot.jimizhou.com) with end-to-end encryption—scan from your phone browser to chat and approve tasks anywhere."
                        )
                    )
                }

                Text(
                    s.t(
                        "公共免费中转 · 手机扫码即可在浏览器远程对话、截屏与审批，全程端到端加密，无需安装额外组件。",
                        "Free public relay · Scan on your phone to chat, capture screen, and approve tasks with end-to-end encryption."
                    )
                )
                .font(PipiTokens.fontCaption)
                .foregroundStyle(PipiTokens.textMuted)

                if let pairingURL = store.lastUniversalPairingURL, (isConnected || isConnecting) {
                    settingsRowDivider

                    HStack(alignment: .top, spacing: PipiTokens.spacing16) {
                        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.t("专属加密配对链接", "Encrypted Pairing Link"))
                                    .font(PipiTokens.fontMicro.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textMuted)
                                Text(pairingURL)
                                    .font(PipiTokens.fontMonoSmall)
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .textSelection(.enabled)
                                    .lineLimit(3)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(PipiTokens.composerSurface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                            .strokeBorder(PipiTokens.composerBorder, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                            }

                            HStack(spacing: PipiTokens.spacing8) {
                                PipiActionButton(
                                    copiedRemoteLink ? s.copied : s.t("复制链接", "Copy Link"),
                                    systemImage: copiedRemoteLink ? "checkmark" : "doc.on.doc",
                                    tone: .primary,
                                    density: .desktopCompact
                                ) {
                                    copyToPasteboard(pairingURL)
                                    copiedRemoteLink = true
                                    Task {
                                        try? await Task.sleep(for: .seconds(2))
                                        copiedRemoteLink = false
                                    }
                                }
                                #if os(macOS)
                                PipiActionButton(
                                    s.t("浏览器打开", "Open in Browser"),
                                    systemImage: "safari",
                                    tone: .secondary,
                                    density: .desktopCompact
                                ) {
                                    if let url = URL(string: pairingURL) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                #endif
                            }
                        }

                        VStack(spacing: 6) {
                            PipiQRCodeView(payload: pairingURL, size: 138)
                            Text(s.t("手机扫码远程访问", "Scan on Phone"))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                    }
                }

                if !devices.isEmpty {
                    settingsRowDivider

                    VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                        Text(s.t("已配对设备（\(devices.count)）", "Paired Devices (\(devices.count))"))
                            .font(PipiTokens.fontCaption.weight(.semibold))
                            .foregroundStyle(PipiTokens.textSecondary)

                        ForEach(devices) { dev in
                            HStack(spacing: PipiTokens.spacing8) {
                                Image(systemName: "iphone")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(PipiTokens.textSecondary)
                                Text(dev.label)
                                    .font(PipiTokens.fontCaption.weight(.medium))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Spacer()
                                PipiActionButton(
                                    s.t("移除", "Revoke"),
                                    tone: .ghost,
                                    density: .desktopCompact
                                ) {
                                    _ = store.revokePairedDevice(id: dev.id)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(PipiTokens.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 3.5 Permissions & Computer Control Tab

    private var permissionsControlTab: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
            // Group 1: This Mac Status & Keep Awake
            settingsGroup(title: s.t("本机运行与防休眠", "This Mac & Keep Awake")) {
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
                                "已授权 \(store.macPermissionsSnapshot.items.filter { $0.state == .granted }.count)/\(PipiMacPermissionKind.allCases.count) 项系统权限 · 已配置 \(store.readyLLMProviders.count) 个模型",
                                "\(store.macPermissionsSnapshot.items.filter { $0.state == .granted }.count)/\(PipiMacPermissionKind.allCases.count) permissions granted · \(store.readyLLMProviders.count) models ready"
                            )
                        )
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                settingsRowDivider

                HStack {
                    HStack(spacing: 6) {
                        Text(s.keepAwakeTitle)
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(title: s.keepAwakeTitle, message: s.keepAwakeDesc)
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
                .padding(.vertical, 12)
            }

            // Group 2: Native macOS Permissions (directly visible)
            settingsGroup(title: s.t("macOS 系统权限", "macOS Permissions")) {
                macNativePermissionsDrawerBody
            }

            // Group 3: Computer Use (Browser & Desktop Control, directly visible)
            settingsGroup(title: s.computerUseSectionTitle) {
                computerUseSettingsSection
            }
        }
        .task {
            store.refreshMacPermissions()
            _ = await store.refreshComputerUseEnvironment()
        }
    }

    // MARK: - Remote Control Section B: WeChat iLink Protocol (QR Bind + 1v1 / Prefix Group Mode)

    private var wechatILinkRemoteSection: some View {
        let wxState = store.wechatILinkManager.state
        let wxDotColor: Color = {
            switch wxState {
            case .connected: return PipiTokens.stateSuccess
            case .requestingQR, .awaitingScan: return PipiTokens.stateWarning
            case .sessionExpired, .error: return PipiTokens.stateError
            case .disconnected: return PipiTokens.textMuted
            }
        }()
        let wxStatusText: String = {
            switch wxState {
            case .connected(let botId, _, _):
                return s.t("已绑定并在线（\(botId)）", "Connected (\(botId))")
            case .requestingQR:
                return s.t("正在申请微信绑定二维码...", "Requesting WeChat QR Code...")
            case .awaitingScan(_, _, let scanned):
                return scanned
                    ? s.t("已扫码，请在手机微信确认绑定", "Scanned · Confirm on WeChat")
                    : s.t("等待手机微信扫码绑定", "Awaiting WeChat QR Scan")
            case .sessionExpired(let msg):
                return msg
            case .error(let msg):
                return msg
            case .disconnected:
                return store.wechatILinkManager.hasSavedCredentials
                    ? s.t("已保存授权 · 未连接", "Credentials Saved · Disconnected")
                    : s.t("未绑定微信", "Not Connected")
            }
        }()

        return settingsGroup(
            title: s.t("微信远程助手（微信 iLink）", "WeChat Remote Assistant (WeChat iLink)"),
            trailing: {
                HStack(spacing: 6) {
                    if wxState.isConnected {
                        PipiActionButton(
                            s.t("断开连接", "Disconnect"),
                            systemImage: "bolt.slash",
                            tone: .secondary,
                            density: .desktopCompact
                        ) {
                            store.disconnectWeChatILink(forgetBinding: false)
                        }
                        PipiActionButton(
                            s.t("解除绑定", "Unbind"),
                            systemImage: "trash",
                            tone: .destructive,
                            density: .desktopCompact
                        ) {
                            store.disconnectWeChatILink(forgetBinding: true)
                        }
                    } else {
                        if store.wechatILinkManager.hasSavedCredentials {
                            PipiActionButton(
                                s.t("恢复连接", "Reconnect"),
                                systemImage: "arrow.clockwise",
                                tone: .secondary,
                                density: .desktopCompact
                            ) {
                                store.reconnectWeChatILink()
                            }
                        }
                        PipiActionButton(
                            s.t("扫码绑定微信", "Bind via QR"),
                            systemImage: "qrcode",
                            tone: .primary,
                            density: .desktopCompact
                        ) {
                            Task { await store.startWeChatILinkQRLogin() }
                        }
                    }
                }
            }
        ) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                HStack(spacing: PipiTokens.spacing8) {
                    Circle()
                        .fill(wxDotColor)
                        .frame(width: 7, height: 7)
                    Text(wxStatusText)
                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Spacer()
                    if store.wechatILinkManager.messagesHandledCount > 0 {
                        Text(s.t("已处理 \(store.wechatILinkManager.messagesHandledCount) 条", "\(store.wechatILinkManager.messagesHandledCount) msgs"))
                            .font(PipiTokens.fontMonoSmall)
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    PipiInfoHelpButton(
                        title: s.t("微信 iLink 协议说明", "WeChat iLink Protocol"),
                        message: s.t(
                            "通过微信官方 iLink Bot 协议（ilinkai.weixin.qq.com）扫码授权。绑定后可直接在微信内收发消息、让 Mac 截屏/查短信/查邮件/执行打包，并接收图片、语音、视频和文件。",
                            "Connects via official WeChat iLink Bot HTTP protocol. Chat with your Mac agents directly from WeChat and receive screenshots, voice clips, videos, and files."
                        )
                    )
                }

                // Live QR Code Display when awaiting scan
                if case .awaitingScan(_, let qrContent, let scanned) = wxState {
                    settingsRowDivider
                    HStack(alignment: .center, spacing: PipiTokens.spacing16) {
                        PipiQRCodeView(payload: qrContent, size: 148)
                        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                            Text(scanned ? s.t("扫码成功，请在手机点击「确认」", "Scanned · Tap Confirm on WeChat") : s.t("使用手机微信扫一扫绑定", "Scan with WeChat to Bind"))
                                .font(PipiTokens.fontSubheadline.weight(.semibold))
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text(
                                s.t(
                                    "授权凭证仅加密保存在本机。绑定成功后无需任何公网配置，直接在微信即可远程调度这台 Mac。",
                                    "Credentials are stored encrypted locally on this Mac. Once bound, control your Mac directly from WeChat."
                                )
                            )
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: PipiTokens.spacing8) {
                                PipiActionButton(
                                    s.t("刷新二维码", "Refresh QR"),
                                    systemImage: "arrow.clockwise",
                                    tone: .secondary,
                                    density: .desktopCompact
                                ) {
                                    Task { await store.startWeChatILinkQRLogin() }
                                }
                                PipiActionButton(
                                    s.cancel,
                                    tone: .ghost,
                                    density: .desktopCompact
                                ) {
                                    store.disconnectWeChatILink(forgetBinding: false)
                                }
                            }
                        }
                    }
                }

                settingsRowDivider

                // Dialogue Mode Switch: Default 1v1 Main PiPiBot vs Prefix Group Mode
                HStack(spacing: PipiTokens.spacing12) {
                    HStack(spacing: 6) {
                        Text(s.t("微信对话模式", "WeChat Routing Mode"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(
                            title: s.t("1v1 与群聊前缀模式", "1v1 vs Prefix Group Mode"),
                            message: s.t(
                                "默认 1v1 与主智能体对话；切换群聊模式后，系统通过【助手名称】消息前缀区分多位智能体，并支持 @助手名 或 @全体。",
                                "Defaults to 1v1 main PiPiBot. Group Mode distinguishes multiple agents with 【AgentName】 prefixes and supports @mentions."
                            )
                        )
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    PipiSegmentedControl(
                        options: PipiWeChatRoutingMode.allCases,
                        selection: Binding(
                            get: { store.wechatILinkManager.routingMode },
                            set: { store.setWeChatRoutingMode($0) }
                        ),
                        label: { $0.shortLabel(lang) }
                    )
                    .frame(width: 244)
                }

                if store.wechatILinkManager.routingMode == .directMainBot {
                    wechatPrimaryBotPickerRow
                } else {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                        Text(s.t("群聊参与智能体（按前缀【助手名称】区分回复）", "Group Participants (Distinguished by 【AgentName】 Prefix)"))
                            .font(PipiTokens.fontCaption.weight(.semibold))
                            .foregroundStyle(PipiTokens.textSecondary)

                        FlowWrapChips(items: store.personas) { persona in
                            let selected = store.wechatILinkManager.groupMemberBotIds.contains(persona.id)
                                || (store.wechatILinkManager.groupMemberBotIds.isEmpty && store.personas.prefix(3).contains(where: { $0.id == persona.id }))
                            Button {
                                store.toggleWeChatGroupMember(persona.id)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(selected ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                    Text("【\(persona.name(lang))】")
                                        .font(PipiTokens.fontCaption.weight(selected ? .semibold : .regular))
                                        .foregroundStyle(selected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selected ? PipiTokens.bgSurfaceHover : PipiTokens.bgSurface.opacity(0.6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                        .strokeBorder(selected ? PipiTokens.composerBorderFocused : PipiTokens.borderSubtle, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        Text(s.t("微信内自然语言引导：直接说「菜单」「创建bot」「切换bot」「切换会话」「切换项目」「进入群聊」「更多配置」「检查更新」，支持语音转文字、图片、附件与正在输入状态。", "In-WeChat natural language: say 菜单 / 创建bot / 切换bot / 切换会话 / 切换项目 / 进入群聊 / 更多配置 / 检查更新. Supports voice ASR, images, files, and typing indicator."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                }

                settingsRowDivider

                HStack {
                    Text(s.t("实时同步「正在输入」状态", "Sync Typing Indicator"))
                        .font(PipiTokens.fontCaption.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { store.wechatILinkManager.typingIndicatorEnabled },
                        set: {
                            store.wechatILinkManager.typingIndicatorEnabled = $0
                            store.saveResidentState()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                HStack {
                    Text(s.t("应用启动时自动恢复微信连接", "Auto-Reconnect WeChat on Launch"))
                        .font(PipiTokens.fontCaption.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { store.wechatAutoConnectEnabled },
                        set: {
                            store.wechatAutoConnectEnabled = $0
                            store.saveResidentState()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private var wechatPrimaryBotPickerRow: some View {
        let candidates: [PipiWeChatBotCandidate] = store.personas.map {
            PipiWeChatBotCandidate(id: $0.id, name: $0.name(lang))
        }
        let fallback = candidates.first ?? PipiWeChatBotCandidate(id: "pipibot-main", name: s.appName)
        let current = candidates.first(where: { $0.id == store.wechatILinkManager.primaryBotId }) ?? fallback
        return HStack(spacing: PipiTokens.spacing12) {
            Text(s.t("1v1 默认主智能体", "Primary 1v1 Agent"))
                .font(PipiTokens.fontCaption.weight(.semibold))
                .foregroundStyle(PipiTokens.textSecondary)
            Spacer()
            PipiSelectMenu(
                options: candidates.isEmpty ? [fallback] : candidates,
                selection: Binding(
                    get: { current },
                    set: { store.wechatILinkManager.primaryBotId = $0.id }
                ),
                width: 212
            ) { candidate in
                candidate.name
            }
        }
    }

    // MARK: - Native macOS System Takeover, Permissions & Omnipotent Media/Build Guidance

    private var macNativePermissionsDrawerBody: some View {
        let snapshot = store.macPermissionsSnapshot
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                HStack(spacing: PipiTokens.spacing8) {
                    Text(s.t("按需授予系统权限，即可支持短信、邮件、截屏录屏及桌面操作。", "Authorize system permissions for SMS, Mail, screen capture, and desktop workflows."))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                    Spacer()
                    PipiActionButton(s.t("逐步授权向导", "Guided permissions"), systemImage: "checkmark.shield", tone: .primary, density: .desktopCompact) {
                        onClose?()
                        store.reopenOnboarding(atStep: 2)
                    }
                    PipiActionButton(s.t("重新检测", "Re-check"), systemImage: "arrow.clockwise", tone: .ghost, density: .desktopCompact) {
                        store.refreshMacPermissions()
                    }
                }

                if showPermissionDiagnostics {
                    HStack(spacing: PipiTokens.spacing8) {
                        Text(s.t("当前运行包：\(PipiMacOmnipotentEngine.currentBundleLocationPath())", "Running app: \(PipiMacOmnipotentEngine.currentBundleLocationPath())"))
                            .font(PipiTokens.fontMonoSmall)
                            .foregroundStyle(PipiTokens.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        PipiActionButton(s.t("定位应用", "Reveal App"), systemImage: "folder", tone: .ghost, density: .desktopCompact) {
                            store.revealCurrentAppInFinder()
                        }
                        PipiActionButton(s.t("重启生效", "Relaunch"), systemImage: "arrow.triangle.2.circlepath", tone: .ghost, density: .desktopCompact) {
                            store.relaunchAppForPermissions()
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            settingsRowDivider

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(PipiMacPermissionKind.allCases.enumerated()), id: \.element.id) { idx, kind in
                    if idx > 0 {
                        settingsRowDivider
                    }
                    let item = snapshot.items.first(where: { $0.kind == kind })
                    let state = item?.state ?? .notGranted
                    let dotColor: Color = {
                        switch state {
                        case .granted: return PipiTokens.stateSuccess
                        case .manualVerify: return PipiTokens.stateWarning
                        case .notGranted: return PipiTokens.stateError
                        case .unavailable: return PipiTokens.textMuted
                        }
                    }()

                    HStack(spacing: PipiTokens.spacing12) {
                        Image(systemName: kind.iconName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PipiTokens.textSecondary)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(kind.title(lang))
                                    .font(PipiTokens.fontSubheadline.weight(.medium))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Circle()
                                    .fill(dotColor)
                                    .frame(width: 6, height: 6)
                                Text(state.label(lang))
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(dotColor)
                                PipiInfoHelpButton(title: kind.title(lang), message: kind.capabilitySummary(lang))
                            }
                            Text(item?.detail ?? kind.capabilitySummary(lang))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                                .lineLimit(2)
                        }

                        Spacer(minLength: PipiTokens.spacing8)

                        PipiActionButton(
                            state == .granted ? s.t("系统设置", "Settings") : s.t("前往授权", "Authorize"),
                            tone: state == .granted ? .ghost : .secondary,
                            density: .desktopCompact
                        ) {
                            Task { await store.requestMacPermission(kind) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                settingsRowDivider

                // Quick Verification Bar + Collapsible Diagnostics
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    HStack(spacing: 6) {
                        Text(s.t("权限功能自检", "Quick Permission Check"))
                            .font(PipiTokens.fontCaption.weight(.semibold))
                            .foregroundStyle(PipiTokens.textSecondary)
                        Spacer()
                        Button {
                            showPermissionDiagnostics.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Text(s.t("诊断信息", "Diagnostics"))
                                    .font(PipiTokens.fontMicro)
                                Image(systemName: showPermissionDiagnostics ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8.5, weight: .semibold))
                            }
                            .foregroundStyle(PipiTokens.textMuted)
                        }
                        .buttonStyle(.plain)
                    }

                    if showPermissionDiagnostics {
                        Text(
                            snapshot.detectedToolchains.isEmpty
                                ? s.t("工具链：等待检测", "Toolchains: Pending scan")
                                : s.t("已检测工具链：\(snapshot.detectedToolchains.joined(separator: " · "))", "Detected toolchains: \(snapshot.detectedToolchains.joined(separator: " · "))")
                        )
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                    }

                    HStack(spacing: PipiTokens.spacing8) {
                        PipiActionButton(s.t("测试截屏", "Test Screenshot"), systemImage: "camera.viewfinder", tone: .secondary, density: .desktopCompact) {
                            Task {
                                let res = await store.macOmnipotentEngine.captureScreenshot()
                                macTestFeedback = res.summary
                            }
                        }
                        PipiActionButton(s.t("测试读短信", "Test SMS"), systemImage: "message", tone: .secondary, density: .desktopCompact) {
                            Task {
                                let res = await store.macOmnipotentEngine.readRecentSMS(limit: 3)
                                macTestFeedback = res.summary
                            }
                        }
                        PipiActionButton(s.t("测试读邮件", "Test Mail"), systemImage: "envelope", tone: .secondary, density: .desktopCompact) {
                            Task {
                                let res = await store.macOmnipotentEngine.readRecentMail(limit: 3)
                                macTestFeedback = res.summary
                            }
                        }
                    }

                    if let feedback = macTestFeedback {
                        Text(feedback)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .lineLimit(4)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PipiTokens.bgSurface.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private var computerUseSettingsSection: some View {
        let env = store.computerUseEnvironment
        let lockedLanes = store.computerUseLanes.filter { $0.state == .blockedUnknownOutcome }
        return VStack(spacing: 0) {
            // Master toggle
            HStack(spacing: PipiTokens.spacing12) {
                HStack(spacing: 6) {
                    Text(s.t("启用桌面与浏览器协作", "Enable Browser & Desktop Control"))
                        .font(PipiTokens.fontSubheadline.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)
                    PipiInfoHelpButton(
                        title: s.t("桌面与浏览器协作", "Browser & Desktop Control"),
                        message: s.t("支持通过本机 Chrome 独立标签协作及 macOS 辅助功能窗口操作；所有高风险或外发动作均需经安全审批。", "Supports isolated Chrome tab collaboration and macOS Accessibility controls, gated by safety approvals.")
                    )
                }
                Spacer()
                PipiActionButton(s.refresh, systemImage: "arrow.clockwise", tone: .ghost, density: .desktopCompact) {
                    Task { _ = await store.refreshComputerUseEnvironment() }
                }
                Toggle("", isOn: Binding(
                    get: { store.computerUseConfig.enabled },
                    set: { val in
                        var cfg = store.computerUseConfig
                        cfg.enabled = val
                        store.updateComputerUseConfig(cfg)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            settingsRowDivider

            // Phase A: Chrome Seat Mode & Debug Port
            HStack(spacing: PipiTokens.spacing12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.t("浏览器协作模式", "Browser Mode"))
                        .font(PipiTokens.fontSubheadline.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text(
                        env?.chromeDebugReachable == true
                            ? s.t("已连接 Chrome（\(env?.chromeBrowserVersion ?? "Chrome")）", "Chrome connected (\(env?.chromeBrowserVersion ?? "Chrome"))")
                            : (env?.chromeInstalled == true
                                ? s.t("已检测到 Chrome · 端口 \(store.computerUseConfig.chromeDebugPort)", "Chrome detected · Port \(store.computerUseConfig.chromeDebugPort)")
                                : s.t("未检测到本地 Chrome", "Google Chrome not detected"))
                    )
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(env?.chromeDebugReachable == true ? PipiTokens.stateSuccess : PipiTokens.textSecondary)
                }
                Spacer()
                PipiSelectMenu(
                    options: PipiBrowserSeatMode.allCases,
                    selection: Binding(
                        get: { store.computerUseConfig.browserSeatMode },
                        set: { val in
                            var cfg = store.computerUseConfig
                            cfg.browserSeatMode = val
                            store.updateComputerUseConfig(cfg)
                        }
                    ),
                    width: 240
                ) { mode in
                    mode.label(lang)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            settingsRowDivider

            // Phase B: macOS Accessibility Permission & Human-Focus Immediate Yield
            VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                HStack(spacing: PipiTokens.spacing12) {
                    HStack(spacing: 6) {
                        Text(s.t("系统辅助功能权限", "macOS Accessibility"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Circle()
                            .fill(env?.accessibilityTrusted == true ? PipiTokens.stateSuccess : PipiTokens.stateWarning)
                            .frame(width: 6, height: 6)
                        Text(env?.accessibilityTrusted == true ? s.t("已授权", "Trusted") : s.t("未授权", "Not Granted"))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(env?.accessibilityTrusted == true ? PipiTokens.stateSuccess : PipiTokens.stateWarning)
                        PipiInfoHelpButton(
                            title: s.t("系统辅助功能权限", "macOS Accessibility"),
                            message: s.t("用于读取原生应用窗口结构树；系统权限由您在 macOS 系统设置中手动授予或撤销。", "Reads structured native app window trees; always granted or revoked manually in System Settings.")
                        )
                    }
                    Spacer()
                    #if os(macOS)
                    PipiActionButton(s.computerUseOpenAccessibility, systemImage: "hand.raised.circle", tone: .secondary, density: .desktopCompact) {
                        PipiComputerUseCoordinator.openAccessibilityPrivacySettings()
                    }
                    #endif
                }

                HStack(spacing: PipiTokens.spacing12) {
                    HStack(spacing: 6) {
                        Text(s.t("切窗自动暂停", "Pause on Window Switch"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(
                            title: s.t("切窗自动暂停", "Pause on Window Switch"),
                            message: s.t("当您切换前景窗口或点击接管时，立即暂停助手的桌面操作。", "Immediately pauses desktop automation when you switch foreground windows or take control.")
                        )
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { store.computerUseConfig.autoYieldOnHumanFocus },
                        set: { val in
                            var cfg = store.computerUseConfig
                            cfg.autoYieldOnHumanFocus = val
                            store.updateComputerUseConfig(cfg)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            settingsRowDivider

            // Operation Protection Log Summary
            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                HStack {
                    HStack(spacing: 6) {
                        Text(s.computerUseJournalTitle)
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(
                            title: s.computerUseJournalTitle,
                            message: s.t("执行写入或点击前会记录保护日志；若结果未知将自动锁定通道，避免重复操作。", "Records write actions beforehand and locks the lane if an outcome is uncertain to prevent duplicate actions.")
                        )
                    }
                    Spacer()
                    if let locked = lockedLanes.first {
                        PipiActionButton(s.computerUseUnlockLane, systemImage: "lock.open", tone: .primary, density: .desktopCompact) {
                            _ = store.acknowledgeAndUnlockComputerUseLane(locked.laneId, note: "Verified in Settings")
                        }
                    } else if store.computerUseYieldedToHuman {
                        PipiActionButton(s.computerUseResume, systemImage: "play.fill", tone: .secondary, density: .desktopCompact) {
                            store.resumeComputerUseAfterHumanYield()
                        }
                    }
                }

                Text(
                    s.t(
                        "通道 \(store.computerUseLanes.count) · 浏览器标签 \(store.computerUseSeats.count) · 日志 \(store.computerUseJournal.count)",
                        "Lanes \(store.computerUseLanes.count) · Browser Seats \(store.computerUseSeats.count) · Logs \(store.computerUseJournal.count)"
                    )
                )
                .font(PipiTokens.fontMonoSmall)
                .foregroundStyle(PipiTokens.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - 4. Memory & Data Tab (Clean Primary Switches + Progressive Disclosure)

    private var memoryPrivacyTab: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
            settingsGroup(title: s.t("记忆与能力共享", "Memory & Sharing")) {
                HStack {
                    HStack(spacing: 6) {
                        Text(s.memoryEnabledTitle)
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(title: s.memoryEnabledTitle, message: s.memoryEnabledDesc)
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
                .padding(.vertical, 12)

                settingsRowDivider

                HStack(spacing: PipiTokens.spacing12) {
                    HStack(spacing: 6) {
                        Text(s.t("允许全局共享助手记忆", "Share Assistant Memory Globally"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(
                            title: s.t("全局共享记忆", "Global Shared Memory"),
                            message: s.t("开启后，允许共享记忆的助手可在执行任务时参考同伴沉淀的经验摘要。", "Allows assistants that enable memory sharing to consult peer experience summaries.")
                        )
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { store.globalCapabilityPool.sharedMemoryEnabled },
                        set: { val in
                            var pool = store.globalCapabilityPool
                            pool.sharedMemoryEnabled = val
                            store.updateGlobalCapabilityPool(pool)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                settingsRowDivider

                HStack(spacing: PipiTokens.spacing12) {
                    HStack(spacing: 6) {
                        Text(s.t("允许助手按需互相学习升级", "Autonomous Peer Capability Upgrade"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(
                            title: s.t("按需互相升级", "Autonomous Peer Upgrade"),
                            message: s.t("当某助手遇到自身未配置的技能、工具或连接器时，自动向具备且允许共享的同伴学习并同步能力。", "When an assistant lacks a skill, tool, or connector required by a task, it automatically learns from consenting peers.")
                        )
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { store.globalCapabilityPool.autoPeerUpgradeEnabled },
                        set: { val in
                            var pool = store.globalCapabilityPool
                            pool.autoPeerUpgradeEnabled = val
                            store.updateGlobalCapabilityPool(pool)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Collapsible: Personal Profile Note & Global Shared Tools / Connectors
            settingsDisclosureCard(
                icon: "person.text.rectangle",
                title: s.t("个人背景与共享能力池", "Personal Note & Shared Capability Pool"),
                summary: s.t(
                    "共享工具 \(store.globalCapabilityPool.sharedTools.count) · 连接器 \(store.globalCapabilityPool.sharedConnectors.count)",
                    "Shared tools \(store.globalCapabilityPool.sharedTools.count) · Connectors \(store.globalCapabilityPool.sharedConnectors.count)"
                ),
                isExpanded: $showMemorySharingDetails
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                        HStack(spacing: 6) {
                            Text(s.t("个人背景与偏好", "Background & Preferences"))
                                .font(PipiTokens.fontSubheadline.weight(.medium))
                                .foregroundStyle(PipiTokens.textPrimary)
                            PipiInfoHelpButton(
                                title: s.t("个人背景与偏好", "Background & Preferences"),
                                message: s.t("填写个人背景、常用语言或工作习惯，供助手在对话中参考。", "Describe your background, preferred language, or conventions for assistant reference.")
                            )
                        }

                        TextEditor(text: Binding(
                            get: { store.personalProfileNote },
                            set: { store.setPersonalProfileNote($0) }
                        ))
                        .onDisappear {
                            store.flush()
                        }
                        .font(PipiTokens.fontBody)
                        .scrollContentBackground(.hidden)
                        .pipiHideScrollbars()
                        .padding(PipiTokens.spacing8)
                        .frame(height: 84)
                        .background(PipiTokens.composerSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                .strokeBorder(PipiTokens.composerBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    settingsRowDivider

                    VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                        Text(s.t("全局共享工具", "Globally Shared Tools"))
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textSecondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 6)], spacing: 6) {
                        ForEach(PipiBotToolKind.allCases) { tool in
                            let selected = store.globalCapabilityPool.sharedTools.contains(tool.rawValue)
                            Button {
                                var pool = store.globalCapabilityPool
                                if selected {
                                    pool.sharedTools.removeAll { $0 == tool.rawValue }
                                } else {
                                    pool.sharedTools.append(tool.rawValue)
                                }
                                store.updateGlobalCapabilityPool(pool)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: tool.iconName)
                                        .font(.system(size: 10.5, weight: .semibold))
                                    Text(tool.label(lang))
                                        .font(PipiTokens.fontMicro.weight(selected ? .semibold : .regular))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(selected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                                .background(selected ? PipiTokens.bgSurfaceHover : PipiTokens.bgSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                        .strokeBorder(selected ? PipiTokens.borderStrong : PipiTokens.borderSubtle, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                            }
                            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))
                        }
                    }

                    Text(s.t("全局共享连接器", "Globally Shared Connectors"))
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                        .padding(.top, 4)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 6)], spacing: 6) {
                        ForEach(PipiBotConnectorKind.allCases) { conn in
                            let selected = store.globalCapabilityPool.sharedConnectors.contains(conn.rawValue)
                            Button {
                                var pool = store.globalCapabilityPool
                                if selected {
                                    pool.sharedConnectors.removeAll { $0 == conn.rawValue }
                                } else {
                                    pool.sharedConnectors.append(conn.rawValue)
                                }
                                store.updateGlobalCapabilityPool(pool)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: conn.iconName)
                                        .font(.system(size: 10.5, weight: .semibold))
                                    Text(conn.label(lang))
                                        .font(PipiTokens.fontMicro.weight(selected ? .semibold : .regular))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(selected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                                .background(selected ? PipiTokens.bgSurfaceHover : PipiTokens.bgSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                        .strokeBorder(selected ? PipiTokens.borderStrong : PipiTokens.borderSubtle, lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                            }
                            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                }
            }

            // Collapsible: Guardrail Whitelists & Proactive Anti-Fatigue Rules
            settingsDisclosureCard(
                icon: "shield.lefthalf.filled",
                title: s.t("安全审批白名单与主动提醒规则", "Guardrail Whitelists & Proactive Rules"),
                summary: s.t(
                    "白名单 \(store.approvalWhitelistRules.count) 项 · 提醒规则 \(store.proactiveRules.count) 项",
                    "Whitelists \(store.approvalWhitelistRules.count) · Proactive rules \(store.proactiveRules.count)"
                ),
                isExpanded: $showSafetyProactiveDrawer
            ) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                    settingsGroup(
                        title: s.guardrailSectionTitle,
                        trailing: {
                            if !store.approvalWhitelistRules.isEmpty {
                                PipiActionButton(s.clearWhitelistRules, tone: .ghost, density: .desktopCompact) {
                                    store.clearApprovalWhitelistRules()
                                }
                            }
                        }
                    ) {
                HStack {
                    HStack(spacing: 6) {
                        Text(s.guardrailJudgeToggleTitle)
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        PipiInfoHelpButton(title: s.guardrailJudgeToggleTitle, message: s.guardrailJudgeToggleDesc)
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    Toggle("", isOn: Binding(
                        get: { store.llmGuardrailJudgeEnabled },
                        set: { store.setLLMGuardrailJudgeEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                settingsRowDivider

                HStack(spacing: PipiTokens.spacing12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.t("安全审计智能体", "Security Auditor Agent"))
                            .font(PipiTokens.fontSubheadline.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.t("当前模型：\(store.activeEngineDisplayLabel(for: store.securityAuditorPersona))", "Model: \(store.activeEngineDisplayLabel(for: store.securityAuditorPersona))"))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer()
                    let candidates = store.personas.map { PipiWeChatBotCandidate(id: $0.id, name: $0.name(lang)) }
                    let fallback = PipiWeChatBotCandidate(
                        id: store.securityAuditorPersona.id,
                        name: store.securityAuditorPersona.name(lang)
                    )
                    let currentAuditor = candidates.first(where: { $0.id == store.securityAuditorBotId }) ?? fallback
                    PipiSelectMenu(
                        options: candidates.isEmpty ? [fallback] : candidates,
                        selection: Binding(
                            get: { currentAuditor },
                            set: { store.setSecurityAuditorBotId($0.id) }
                        ),
                        width: 196
                    ) { bot in
                        bot.name
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                settingsRowDivider

                if store.approvalWhitelistRules.isEmpty {
                    Text(s.guardrailWhitelistEmpty)
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textMuted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                } else {
                    ForEach(Array(store.approvalWhitelistRules.enumerated()), id: \.element.id) { idx, rule in
                        if idx > 0 {
                            settingsRowDivider
                        }
                        HStack(spacing: PipiTokens.spacing12) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(rule.toolName)
                                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Text(rule.granularity.label(lang))
                                        .font(PipiTokens.fontMicro)
                                        .foregroundStyle(PipiTokens.textSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(PipiTokens.bgInset)
                                        .clipShape(Capsule())
                                }
                                Text(rule.targetPattern ?? rule.actionKind.rawValue)
                                    .font(PipiTokens.fontMonoSmall)
                                    .foregroundStyle(PipiTokens.textMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: PipiTokens.spacing8)
                            PipiGhostIconButton(
                                systemImage: "trash",
                                size: 28,
                                iconSize: 12,
                                cornerRadius: PipiTokens.radiusSM,
                                accessibilityLabel: s.delete
                            ) {
                                store.revokeApprovalWhitelistRule(id: rule.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }

            settingsGroup(
                title: s.proactiveSectionTitle,
                trailing: {
                    HStack(spacing: PipiTokens.spacing8) {
                        if let prevVersion = store.proactiveHistoryVersions.dropLast().last {
                            PipiActionButton("\(s.proactiveRollback) (v\(prevVersion))", tone: .ghost, density: .desktopCompact) {
                                _ = store.rollbackProactiveGuideline(toVersion: prevVersion)
                            }
                        }
                        PipiActionButton(s.proactiveRunDreaming, systemImage: "moon.stars", tone: .secondary, density: .desktopCompact) {
                            _ = store.runProactiveNightlyDreaming()
                        }
                    }
                }
            ) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.proactiveQuietHoursTitle)
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text("\(s.proactiveQuietHoursDesc) (\(store.proactivePolicy.quietHoursStart):00–\(store.proactivePolicy.quietHoursEnd):00)")
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    Toggle("", isOn: Binding(
                        get: { store.proactivePolicy.quietHoursEnabled },
                        set: { enabled in
                            var next = store.proactivePolicy
                            next.quietHoursEnabled = enabled
                            store.updateProactivePolicy(next)
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                settingsRowDivider

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.proactiveDailyCapTitle)
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.t("每日最多主动提醒 \(store.proactivePolicy.maxDailyNotifications) 条 · 对话静默退让 \(store.proactivePolicy.chatSilenceSeconds / 60) 分钟",
                                 "Max \(store.proactivePolicy.maxDailyNotifications)/day · \(store.proactivePolicy.chatSilenceSeconds / 60)m chat silence"))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer(minLength: PipiTokens.spacing12)
                    Stepper(
                        "\(store.proactivePolicy.maxDailyNotifications)",
                        value: Binding(
                            get: { store.proactivePolicy.maxDailyNotifications },
                            set: { val in
                                var next = store.proactivePolicy
                                next.maxDailyNotifications = val
                                store.updateProactivePolicy(next)
                            }
                        ),
                        in: 1...15
                    )
                    .frame(width: 110)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                settingsRowDivider

                HStack(spacing: PipiTokens.spacing8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.t("macOS 原生事件源权限 (EventKit)", "macOS Native Sources (EventKit)"))
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.t("日历：\(store.eventKitCalendarAuth.label(lang)) · 提醒事项：\(store.eventKitRemindersAuth.label(lang))",
                                 "Calendar: \(store.eventKitCalendarAuth.label(lang)) · Reminders: \(store.eventKitRemindersAuth.label(lang))"))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                    Spacer()
                    if store.eventKitCalendarAuth != .authorized {
                        PipiActionButton(s.t("授权日历", "Calendar"), tone: .secondary, density: .desktopCompact) {
                            Task { await store.requestEventKitCalendarAccess() }
                        }
                    }
                    if store.eventKitRemindersAuth != .authorized {
                        PipiActionButton(s.t("授权提醒", "Reminders"), tone: .secondary, density: .desktopCompact) {
                            Task { await store.requestEventKitRemindersAccess() }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                settingsRowDivider

                if store.proactiveRules.isEmpty && store.proactiveClues.isEmpty {
                    HStack(spacing: 6) {
                        Text(s.t("暂无已学习的提醒规则。", "No learned notification rules."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textMuted)
                        PipiInfoHelpButton(
                            title: s.t("自动学习规则", "Learned Rules"),
                            message: s.t("对简报重复标记「有帮助」或「不再提醒」达到 2 次后，系统将自动整理为可回退的提醒规则。", "Repeated feedback on briefs (2+ times within 14 days) automatically promotes into rollbackable rules.")
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                } else {
                    ForEach(Array(store.proactiveRules.enumerated()), id: \.element.id) { idx, rule in
                        if idx > 0 { settingsRowDivider }
                        HStack(spacing: PipiTokens.spacing12) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(rule.matter)
                                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Text(rule.leaning.label(lang))
                                        .font(PipiTokens.fontMicro)
                                        .foregroundStyle(PipiTokens.textSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(PipiTokens.bgInset, in: Capsule())
                                }
                                Text(rule.text)
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textSecondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: PipiTokens.spacing8)
                            Toggle("", isOn: Binding(
                                get: { rule.enabled },
                                set: { store.toggleProactiveRule(id: rule.id, enabled: $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            PipiGhostIconButton(
                                systemImage: "trash",
                                size: 28,
                                iconSize: 12,
                                cornerRadius: PipiTokens.radiusSM,
                                accessibilityLabel: s.delete
                            ) {
                                store.deleteProactiveRule(id: rule.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }

                    if !store.proactiveClues.isEmpty {
                        settingsRowDivider
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.t("观察中的线索（14 天内达到 2 次自动升格规则）", "Active Clues (auto-promotes at seen >= 2 within 14 days)"))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textMuted)
                            ForEach(store.proactiveClues.prefix(5)) { clue in
                                Text("• \(clue.matter) (\(clue.kind)) → \(clue.leaning.label(lang)) · seen \(clue.seen)/2")
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textSecondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
                }
                }
                .padding(PipiTokens.spacing12)
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
                PipiSelectMenu(
                    options: PipiLLMProviderKind.allCases,
                    selection: $formPreset
                ) { kind in
                    kind.localizedName(lang)
                }
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
            .pipiTactileCard(cornerRadius: PipiTokens.radiusMD)
        }
    }

    private var settingsRowDivider: some View {
        Rectangle()
            .fill(PipiTokens.borderSubtle)
            .frame(height: 1)
    }

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(PipiTokens.fontMonoSmall.weight(.medium))
            .foregroundStyle(PipiTokens.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(PipiTokens.bgElevated)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusXS, style: .continuous)
                    .stroke(PipiTokens.borderStrong.opacity(0.6), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusXS, style: .continuous))
            .shadow(color: PipiTokens.subtleShadow, radius: 0.5, y: 1)
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

    private var softwareUpdateSubtitle: String {
        switch store.updateManager.state {
        case .idle:
            return s.t("可从 GitHub Release 检查并自动安装最新版本", "Check and auto-install latest GitHub Release")
        case .checking:
            return s.t("正在连接 GitHub Releases...", "Checking GitHub Releases...")
        case .upToDate(let version, _):
            return s.t("已是最新版本（v\(version)）", "Up to date (v\(version))")
        case .updateAvailable(let rel):
            return s.t("发现新版本 \(rel.tagName)：\(rel.title)", "Update available \(rel.tagName): \(rel.title)")
        case .downloading(let rel, let p):
            return s.t("正在下载 \(rel.tagName) (\(Int(p * 100))%)...", "Downloading \(rel.tagName) (\(Int(p * 100))%)...")
        case .verifying(let rel):
            return s.t("正在校验 \(rel.tagName) 安装包完整性...", "Verifying \(rel.tagName) checksum & signature...")
        case .installing(let rel):
            return s.t("正在安装 \(rel.tagName) 并准备重启...", "Installing \(rel.tagName) & relaunching...")
        case .error(let msg):
            return msg
        }
    }

    private var softwareUpdateSubtitleColor: Color {
        switch store.updateManager.state {
        case .updateAvailable, .upToDate, .installing:
            return PipiTokens.stateSuccess
        case .error:
            return PipiTokens.stateError
        default:
            return PipiTokens.textSecondary
        }
    }

    @ViewBuilder
    private var softwareUpdateActionButton: some View {
        switch store.updateManager.state {
        case .updateAvailable(let rel):
            PipiActionButton(
                s.t("下载并更新", "Update Now"),
                systemImage: "arrow.down.circle.fill",
                tone: .primary,
                density: .desktopCompact
            ) {
                store.updateManager.downloadAndInstallUpdate(rel) {
                    store.prepareForAppUpgrade()
                }
            }
        case .checking, .downloading, .verifying, .installing:
            ProgressView().controlSize(.small)
        default:
            PipiActionButton(
                s.t("检查更新", "Check Updates"),
                systemImage: "arrow.triangle.2.circlepath",
                tone: .secondary,
                density: .desktopCompact
            ) {
                Task {
                    _ = await store.updateManager.checkForUpdates(currentVersion: store.appDisplayVersion, silent: false)
                }
            }
        }
    }
}

private struct FlowWrapChips<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 116), spacing: 8, alignment: .leading)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}
