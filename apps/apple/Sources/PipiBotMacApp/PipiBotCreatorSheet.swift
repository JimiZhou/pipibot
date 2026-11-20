import SwiftUI
import PipiBotKit

/// Dynamic Bot Creation & Persona Studio Sheet.
/// Supports Create mode (`existing == nil`, with an interactive template gallery and live avatar preview)
/// and Edit mode (`existing != nil`, updating an existing `PipiBotPersona`).
public struct PipiBotCreatorSheet: View {
    @Bindable public var store: PipiAppStore
    public var existing: PipiBotPersona?
    public var onDismiss: () -> Void
    public var onSaved: ((PipiBotPersona) -> Void)?

    @Environment(\.pipiTextScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum EditorTab: String, CaseIterable, Identifiable {
        case basic
        case capabilities
        case sharing

        var id: String { rawValue }

        func label(_ s: PipiStrings) -> String {
            switch self {
            case .basic: return s.t("基础人设", "Persona")
            case .capabilities: return s.t("音色与能力", "Voice & Skills")
            case .sharing: return s.t("共享与升级", "Sharing")
            }
        }
    }

    @State private var editorTab: EditorTab = .basic
    @State private var selectedCategory: PipiBotPersonaTemplate.Category? = nil
    @State private var selectedTemplateId: String = PipiBotPersonaTemplate.catalog.first?.id ?? "tpl_general"
    @State private var name: String = ""
    @State private var role: String = ""
    @State private var systemPrompt: String = ""
    @State private var accent: PipiPersonaAccent = .iris
    @State private var shape: AvatarShape = .orb
    @State private var idleState: AvatarState53 = .ambientBreathe
    @State private var preferredTarget: PipiExecutionTarget = .auto
    @State private var permissionTier: PipiPermissionTier = .ask
    @State private var voiceProfileId: String = ""
    @State private var assignedSkillSlugs: Set<String> = []
    @State private var enabledTools: Set<String> = [PipiBotToolKind.personalWiki.rawValue, PipiBotToolKind.voiceCall.rawValue]
    @State private var enabledConnectors: Set<String> = []
    @State private var sharingPolicy: PipiBotSharingPolicy = .default
    @State private var previewEngine = PipiProceduralAvatarEngine(initialState: .ambientBreathe)

    public init(
        store: PipiAppStore,
        existing: PipiBotPersona? = nil,
        onDismiss: @escaping () -> Void,
        onSaved: ((PipiBotPersona) -> Void)? = nil
    ) {
        self.store = store
        self.existing = existing
        self.onDismiss = onDismiss
        self.onSaved = onSaved
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }
    private var isCreateMode: Bool { existing == nil }
    private var activeAccentColor: Color { PipiTokens.color(for: accent) }

    private var selectedTemplate: PipiBotPersonaTemplate {
        PipiBotPersonaTemplate.catalog.first(where: { $0.id == selectedTemplateId })
            ?? PipiBotPersonaTemplate.catalog[0]
    }

    private var filteredTemplates: [PipiBotPersonaTemplate] {
        guard let selectedCategory else { return PipiBotPersonaTemplate.catalog }
        return PipiBotPersonaTemplate.catalog.filter { $0.category == selectedCategory }
    }

    private var previewMotif: PipiPersonaMotif {
        switch shape {
        case .terminal, .bolt: return .caret
        case .cloud, .dream: return .nib
        case .shield, .squircle: return .loop
        case .orb, .spark: return .haloPip
        }
    }

    public var body: some View {
        let _ = textScale
        VStack(spacing: 0) {
            headerBar

            Rectangle()
                .fill(PipiTokens.borderSubtle)
                .frame(height: 1)

            Group {
                if isCreateMode {
                    HStack(spacing: 0) {
                        templateGalleryPane
                            .frame(width: 280)

                        Rectangle()
                            .fill(PipiTokens.borderSubtle)
                            .frame(width: 1)

                        studioConfigurationPane
                    }
                } else {
                    studioConfigurationPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(PipiTokens.borderSubtle)
                .frame(height: 1)

            footerBar
        }
        .frame(
            minWidth: isCreateMode ? 780 : 540,
            minHeight: isCreateMode ? 580 : 540
        )
        .background(PipiTokens.bgElevated)
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
        .onAppear {
            if let existing {
                name = existing.name(lang)
                role = existing.role(lang)
                systemPrompt = existing.systemPrompt
                accent = existing.accent
                shape = existing.avatarShape
                idleState = existing.idleAvatarState
                preferredTarget = existing.preferredTarget
                permissionTier = existing.permissionTier
                voiceProfileId = existing.voiceProfileId ?? ""
                assignedSkillSlugs = Set(existing.assignedSkillSlugs)
                enabledTools = Set(existing.enabledTools)
                enabledConnectors = Set(existing.enabledConnectors)
                sharingPolicy = existing.sharingPolicy
                previewEngine.setState(existing.idleAvatarState)
            } else if let first = PipiBotPersonaTemplate.catalog.first {
                applyTemplate(first)
            }
        }
    }

    // MARK: - Header & Footer

    private var headerBar: some View {
        HStack(spacing: PipiTokens.spacing12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isCreateMode ? s.createBotTitle : s.editBotTitle)
                    .font(PipiTokens.fontTitle)
                    .tracking(PipiTokens.trackingTitle)
                    .foregroundStyle(PipiTokens.textPrimary)
                Text(isCreateMode
                     ? s.t("从动态模板快速起步，或自由定制专属智能体的指令与权限", "Start from a dynamic template or craft your own agent, prompt, and permissions")
                     : s.createBotSubtitle)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PipiTokens.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(PipiTokens.bgSurfaceHover)
                    .clipShape(Circle())
            }
            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
            .accessibilityLabel(s.close)
        }
        .padding(.horizontal, PipiTokens.spacing24)
        .padding(.vertical, PipiTokens.spacing16)
    }

    private var footerBar: some View {
        HStack {
            PipiActionButton(s.cancel, tone: .secondary, density: .desktopCompact, action: onDismiss)
            Spacer()
            PipiActionButton(
                isCreateMode ? s.t("创建智能体", "Create Agent") : s.save,
                systemImage: isCreateMode ? "plus.circle.fill" : "checkmark",
                tone: .primary,
                density: .desktopCompact
            ) {
                savePersona()
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, PipiTokens.spacing24)
        .padding(.vertical, PipiTokens.spacing16)
        .background(PipiTokens.bgCanvas.opacity(0.45))
    }

    // MARK: - Left Rail: Dynamic Template Gallery

    private var templateGalleryPane: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            Text(s.t("角色模板", "Persona Templates"))
                .font(PipiTokens.fontMicro)
                .tracking(PipiTokens.trackingMicro)
                .foregroundStyle(PipiTokens.textMuted)
                .textCase(.uppercase)
                .padding(.horizontal, PipiTokens.spacing16)
                .padding(.top, PipiTokens.spacing16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PipiTokens.spacing4) {
                    categoryChip(title: s.t("全部", "All"), category: nil)
                    ForEach(PipiBotPersonaTemplate.Category.allCases) { category in
                        categoryChip(title: category.label(lang), category: category)
                    }
                }
                .padding(.horizontal, PipiTokens.spacing16)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: PipiTokens.spacing8) {
                    ForEach(filteredTemplates) { template in
                        templateCard(template)
                    }
                }
                .padding(.horizontal, PipiTokens.spacing16)
                .padding(.bottom, PipiTokens.spacing16)
            }
        }
        .background(PipiTokens.bgSidebar)
    }

    private func categoryChip(title: String, category: PipiBotPersonaTemplate.Category?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                selectedCategory = category
            }
        } label: {
            Text(title)
                .font(PipiTokens.fontMicro)
                .foregroundStyle(isSelected ? PipiTokens.textInverse : PipiTokens.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? PipiTokens.soulPrimary : PipiTokens.bgSurface)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : PipiTokens.borderSubtle, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
    }

    private func templateCard(_ template: PipiBotPersonaTemplate) -> some View {
        let isSelected = selectedTemplateId == template.id
        let tplColor = PipiTokens.color(for: template.defaultAccent)

        return Button {
            withAnimation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion)) {
                applyTemplate(template)
            }
        } label: {
            HStack(alignment: .top, spacing: PipiTokens.spacing12) {
                ZStack {
                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                        .fill(tplColor.opacity(isSelected ? 0.22 : 0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: template.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tplColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(template.name(lang))
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Circle()
                            .fill(tplColor)
                            .frame(width: 7, height: 7)
                    }

                    Text(template.tagline(lang))
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(PipiTokens.spacing12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? PipiTokens.bgSurfaceHover : PipiTokens.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                    .stroke(isSelected ? tplColor.opacity(0.75) : PipiTokens.borderSubtle, lineWidth: isSelected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.985))
        .accessibilityLabel("\(template.name(lang)), \(template.tagline(lang))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Right Studio Pane: Live Avatar Preview & Configuration

    private var studioConfigurationPane: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                livePreviewCard

                PipiSegmentedControl(options: EditorTab.allCases, selection: $editorTab) { tab in
                    tab.label(s)
                }

                switch editorTab {
                case .basic:
                    basicPersonaFields
                case .capabilities:
                    capabilitiesFields
                case .sharing:
                    sharingAndUpgradesFields
                }
            }
            .padding(PipiTokens.spacing24)
        }
        .pipiHideScrollbars()
    }

    private var preferredTargetLabel: String {
        switch preferredTarget {
        case .auto: return s.autoRouteEngine
        case .llm(let pid):
            if let cfg = store.readyLLMProviders.first(where: { $0.id == pid }) {
                return "\(cfg.name) · \(cfg.modelId)"
            }
            return s.autoRouteEngine
        case .localAgent(let kind):
            return kind.displayName
        }
    }

    private var basicPersonaFields: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                Text(s.personaName)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)
                PipiTextField(s.t("例如：架构师 / 英语口语教练", "e.g., Systems Architect / Language Coach"), text: $name, height: 34)
            }

            VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                Text(s.personaRole)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)
                PipiTextField(s.t("一句话描述该助手的职责", "One-line summary of this assistant's role"), text: $role, height: 34)
            }

            VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                Text(s.personaSystemPrompt)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)
                TextEditor(text: $systemPrompt)
                    .font(PipiTokens.fontBody)
                    .scrollContentBackground(.hidden)
                    .pipiHideScrollbars()
                    .padding(PipiTokens.spacing8)
                    .frame(height: 100)
                    .background(PipiTokens.composerSurface)
                    .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous).strokeBorder(PipiTokens.composerBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
            }

            HStack(alignment: .top, spacing: PipiTokens.spacing16) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    Text(s.personaAccent)
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                    HStack(spacing: PipiTokens.spacing8) {
                        ForEach(PipiPersonaAccent.allCases) { item in
                            let itemColor = PipiTokens.color(for: item)
                            Button {
                                accent = item
                            } label: {
                                Circle()
                                    .fill(itemColor)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .stroke(PipiTokens.textPrimary, lineWidth: accent == item ? 2 : 0)
                                            .padding(-3)
                                    )
                            }
                            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.90))
                            .accessibilityLabel(item.label(lang))
                            .accessibilityAddTraits(accent == item ? [.isSelected] : [])
                        }
                    }
                }

                Spacer()

                VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                    Text(s.personaDefaultEngine)
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                    Menu {
                        Button {
                            preferredTarget = .auto
                        } label: {
                            if preferredTarget == .auto {
                                Label(s.autoRouteEngine, systemImage: "checkmark")
                            } else {
                                Text(s.autoRouteEngine)
                            }
                        }
                        if !store.readyLLMProviders.isEmpty {
                            Divider()
                            ForEach(store.readyLLMProviders) { cfg in
                                let t = PipiExecutionTarget.llm(providerId: cfg.id)
                                Button {
                                    preferredTarget = t
                                } label: {
                                    if preferredTarget == t {
                                        Label("\(cfg.name) · \(cfg.modelId)", systemImage: "checkmark")
                                    } else {
                                        Text("\(cfg.name) · \(cfg.modelId)")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: PipiTokens.spacing8) {
                            Text(preferredTargetLabel)
                                .font(PipiTokens.fontCaption.weight(.medium))
                                .foregroundStyle(PipiTokens.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                        .padding(.horizontal, 10)
                        .frame(width: 210, height: 32)
                        .background(PipiTokens.buttonSecondaryBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                .strokeBorder(PipiTokens.composerBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                    }
                    .pipiPlainMenu()
                }
            }

            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                Text(s.personaShape)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)

                HStack(spacing: PipiTokens.spacing8) {
                    ForEach(AvatarShape.allCases) { candidate in
                        let isChosen = shape == candidate
                        Button {
                            shape = candidate
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: iconForAvatarShape(candidate))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isChosen ? activeAccentColor : PipiTokens.textSecondary)
                                Text(labelForAvatarShape(candidate))
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(isChosen ? PipiTokens.textPrimary : PipiTokens.textMuted)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(isChosen ? activeAccentColor.opacity(0.14) : PipiTokens.bgSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                    .stroke(isChosen ? activeAccentColor.opacity(0.70) : PipiTokens.borderSubtle, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.95))
                        .accessibilityLabel(labelForAvatarShape(candidate))
                        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
                    }
                }
            }

            VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                HStack(spacing: 6) {
                    Text(s.permissionTierTitle)
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                    PipiInfoHelpButton(
                        title: s.permissionTierTitle,
                        message: permissionTier.description(lang)
                    )
                }

                PipiSegmentedControl(
                    options: PipiPermissionTier.allCases,
                    selection: $permissionTier
                ) { tier in
                    tier.label(lang)
                }
            }
        }
    }

    private var capabilitiesFields: some View {
        let timbres = PipiDailyVoiceEngine.availableVoiceTimbres()
        let currentVoiceLabel: String = {
            if voiceProfileId.isEmpty {
                return s.t("跟随全局默认音色", "Follow Global Voice")
            }
            return PipiDailyVoiceEngine.resolveTimbre(id: voiceProfileId).displayName(lang)
        }()

        return VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            // 1. Dedicated Voice Timbre
            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                Text(s.t("专属音色", "Dedicated Voice Timbre"))
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)
                HStack(spacing: PipiTokens.spacing8) {
                    Menu {
                        Button {
                            voiceProfileId = ""
                        } label: {
                            if voiceProfileId.isEmpty {
                                Label(s.t("跟随全局默认音色", "Follow Global Voice"), systemImage: "checkmark")
                            } else {
                                Text(s.t("跟随全局默认音色", "Follow Global Voice"))
                            }
                        }
                        Divider()
                        ForEach(timbres) { option in
                            Button {
                                voiceProfileId = option.id
                            } label: {
                                if voiceProfileId == option.id {
                                    Label(option.displayName(lang), systemImage: "checkmark")
                                } else {
                                    Text(option.displayName(lang))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: PipiTokens.spacing8) {
                            Image(systemName: "waveform")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(PipiTokens.textMuted)
                            Text(currentVoiceLabel)
                                .font(PipiTokens.fontCaption.weight(.medium))
                                .foregroundStyle(PipiTokens.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(PipiTokens.buttonSecondaryBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                .strokeBorder(PipiTokens.composerBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                    }
                    .pipiPlainMenu()

                    PipiActionButton(s.t("试听", "Preview"), systemImage: "play.fill", tone: .secondary, density: .desktopCompact) {
                        let resolved = voiceProfileId.isEmpty ? store.voiceConfig.selectedVoiceProfileId : voiceProfileId
                        store.previewVoiceProfile(resolved)
                    }
                }
            }

            // 2. Skills
            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                Text(s.t("专属技能 (\(assignedSkillSlugs.count))", "Skills (\(assignedSkillSlugs.count))"))
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    ForEach(PipiBuiltinSkillsRegistry.allPacks) { skill in
                        let isOn = assignedSkillSlugs.contains(skill.slug)
                        capabilityChip(title: skill.title(lang), icon: "sparkles", isSelected: isOn) {
                            if isOn {
                                assignedSkillSlugs.remove(skill.slug)
                            } else {
                                assignedSkillSlugs.insert(skill.slug)
                            }
                        }
                    }
                }
            }

            // 3. Tools
            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                Text(s.t("可用工具 (\(enabledTools.count))", "Tools (\(enabledTools.count))"))
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    ForEach(PipiBotToolKind.allCases) { tool in
                        let isOn = enabledTools.contains(tool.rawValue)
                        capabilityChip(title: tool.label(lang), icon: tool.iconName, isSelected: isOn) {
                            if isOn {
                                enabledTools.remove(tool.rawValue)
                            } else {
                                enabledTools.insert(tool.rawValue)
                            }
                        }
                    }
                }
            }

            // 4. Connectors
            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                Text(s.t("连接器 (\(enabledConnectors.count))", "Connectors (\(enabledConnectors.count))"))
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    ForEach(PipiBotConnectorKind.allCases) { conn in
                        let isOn = enabledConnectors.contains(conn.rawValue)
                        capabilityChip(title: conn.label(lang), icon: conn.iconName, isSelected: isOn) {
                            if isOn {
                                enabledConnectors.remove(conn.rawValue)
                            } else {
                                enabledConnectors.insert(conn.rawValue)
                            }
                        }
                    }
                }
            }
        }
    }

    private var sharingAndUpgradesFields: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            VStack(alignment: .leading, spacing: 0) {
                policyToggleRow(
                    title: s.t("继承全局共享池能力", "Inherit Global Shared Pool"),
                    isOn: $sharingPolicy.inheritGlobalPool
                )
                Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
                policyToggleRow(
                    title: s.t("允许按需向同伴学习升级", "Learn & Upgrade from Peers"),
                    isOn: $sharingPolicy.allowPeerUpgrade
                )
                Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
                policyToggleRow(
                    title: s.t("向同伴共享技能", "Share Skills with Peers"),
                    isOn: $sharingPolicy.shareSkills
                )
                Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
                policyToggleRow(
                    title: s.t("向同伴共享工具", "Share Tools with Peers"),
                    isOn: $sharingPolicy.shareTools
                )
                Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
                policyToggleRow(
                    title: s.t("向同伴共享连接器", "Share Connectors with Peers"),
                    isOn: $sharingPolicy.shareConnectors
                )
                Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
                policyToggleRow(
                    title: s.t("向同伴共享记忆摘要", "Share Memory Summary"),
                    isOn: $sharingPolicy.shareMemory
                )
            }
            .background(PipiTokens.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                    .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))

            if let existing, !existing.learnedUpgrades.isEmpty {
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    Text(s.t("已习得的同伴升级记录 (\(existing.learnedUpgrades.count))", "Learned Peer Upgrades (\(existing.learnedUpgrades.count))"))
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textSecondary)

                    ForEach(existing.learnedUpgrades.prefix(6)) { rec in
                        HStack(spacing: PipiTokens.spacing8) {
                            Text(rec.kind.label(lang))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(PipiTokens.bgInset, in: Capsule())
                            Text(rec.summary)
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textPrimary)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func capabilityChip(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(PipiTokens.fontCaption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(isSelected ? activeAccentColor.opacity(0.14) : PipiTokens.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .strokeBorder(isSelected ? activeAccentColor.opacity(0.65) : PipiTokens.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))
    }

    private func policyToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(PipiTokens.fontCaption.weight(.medium))
                .foregroundStyle(PipiTokens.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var livePreviewCard: some View {
        HStack(spacing: PipiTokens.spacing16) {
            PipiAvatarView(
                engine: previewEngine,
                size: 64,
                accentOverride: activeAccentColor,
                personaAccent: accent,
                motif: previewMotif,
                interactive: false
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: PipiTokens.spacing8) {
                    Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? s.t("未命名智能体", "Untitled Agent")
                         : name)
                        .font(PipiTokens.fontHeadline)
                        .foregroundStyle(PipiTokens.textPrimary)
                        .lineLimit(1)

                    Text(permissionTier.label(lang))
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(activeAccentColor)
                        .padding(.horizontal, PipiTokens.spacing8)
                        .padding(.vertical, 2)
                        .background(activeAccentColor.opacity(0.14))
                        .clipShape(Capsule())
                }

                Text(role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? s.t("自定义专属工作流与指令", "Custom workflow & instructions")
                     : role)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(PipiTokens.spacing16)
        .background(PipiTokens.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(activeAccentColor.opacity(0.32), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }

    // MARK: - Actions & Helpers

    private func applyTemplate(_ template: PipiBotPersonaTemplate) {
        selectedTemplateId = template.id
        if template.category == .custom {
            name = ""
            role = ""
            systemPrompt = ""
        } else {
            name = template.name(lang)
            role = template.tagline(lang)
            systemPrompt = template.systemPrompt
        }
        accent = template.defaultAccent
        shape = template.defaultAvatarShape
        idleState = template.defaultIdleAvatarState
        permissionTier = template.defaultPermissionTier
        previewEngine.setState(template.defaultIdleAvatarState)
    }

    private func savePersona() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        let cleanRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        let savedPersona: PipiBotPersona
        if var ex = existing {
            if lang == .zhHans {
                ex.nameZh = cleanName
                ex.roleZh = cleanRole
            } else {
                ex.nameEn = cleanName
                ex.roleEn = cleanRole
            }
            let fallbackPrompt = "You are \(cleanName), a helpful personal AI bot inside PiPiBot. \(cleanRole)"
            ex.systemPrompt = cleanPrompt.isEmpty ? fallbackPrompt : cleanPrompt
            ex.accent = accent
            ex.avatarShape = shape
            ex.preferredTarget = preferredTarget
            ex.permissionTier = permissionTier
            ex.voiceProfileId = voiceProfileId.isEmpty ? nil : voiceProfileId
            ex.assignedSkillSlugs = Array(assignedSkillSlugs).sorted()
            ex.enabledTools = Array(enabledTools).sorted()
            ex.enabledConnectors = Array(enabledConnectors).sorted()
            ex.sharingPolicy = sharingPolicy
            savedPersona = ex
        } else {
            var created = selectedTemplate.instantiate(
                customName: cleanName,
                customPrompt: cleanPrompt.isEmpty ? nil : cleanPrompt,
                accent: accent,
                avatarShape: shape,
                permissionTier: permissionTier,
                preferredTarget: preferredTarget
            )
            if !cleanRole.isEmpty {
                created.roleZh = cleanRole
                created.roleEn = cleanRole
            }
            created.greetingZh = "你好，我是 \(cleanName)。请问有什么可以协助？"
            created.greetingEn = "Hi, I'm \(cleanName). How can I assist you?"
            created.voiceProfileId = voiceProfileId.isEmpty ? nil : voiceProfileId
            created.assignedSkillSlugs = Array(assignedSkillSlugs).sorted()
            created.enabledTools = Array(enabledTools).sorted()
            created.enabledConnectors = Array(enabledConnectors).sorted()
            created.sharingPolicy = sharingPolicy
            savedPersona = created
        }

        store.upsertPersona(savedPersona)
        onSaved?(savedPersona)
        onDismiss()
    }

    private func iconForAvatarShape(_ candidate: AvatarShape) -> String {
        switch candidate {
        case .orb: return "circle.fill"
        case .squircle: return "app.fill"
        case .cloud: return "cloud.fill"
        case .spark: return "rays"
        case .bolt: return "bolt.fill"
        case .shield: return "shield.fill"
        case .dream: return "moon.stars.fill"
        case .terminal: return "terminal.fill"
        }
    }

    private func labelForAvatarShape(_ candidate: AvatarShape) -> String {
        switch candidate {
        case .orb: return s.t("圆球", "Orb")
        case .squircle: return s.t("方圆", "Tile")
        case .cloud: return s.t("云朵", "Cloud")
        case .spark: return s.t("星芒", "Spark")
        case .bolt: return s.t("脉冲", "Bolt")
        case .shield: return s.t("盾徽", "Shield")
        case .dream: return s.t("星月", "Dream")
        case .terminal: return s.t("终端", "Term")
        }
    }
}
