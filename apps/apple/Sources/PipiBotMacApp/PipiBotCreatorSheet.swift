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

    private enum CreationMode: String, CaseIterable, Identifiable {
        case aiInterview
        case manualForm

        var id: String { rawValue }
    }

    @State private var creationMode: CreationMode = .aiInterview
    @State private var architectBotName: String = ""
    @State private var architectGoal: String = ""
    @State private var architectProcessDump: String = ""
    @State private var architectSourceRules: String = ""
    @State private var architectVerification: String = ""
    @State private var architectTriggerKind: PipiRoutineTriggerKind = .schedule
    @State private var architectTriggerValue: String = ""
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
    @State private var preferredModelId: String = ""
    @State private var permissionTier: PipiPermissionTier = .ask
    @State private var voiceProfileId: String = ""
    @State private var assignedSkillSlugs: Set<String> = []
    @State private var enabledTools: Set<String> = [PipiBotToolKind.personalWiki.rawValue, PipiBotToolKind.voiceCall.rawValue]
    @State private var enabledConnectors: Set<String> = []
    @State private var sharingPolicy: PipiBotSharingPolicy = .default
    @State private var runtimeMode: PipiTeammateRuntimeMode = .local
    @State private var reportsToBotId: String = ""
    @State private var subscriptionProvider: PipiSubscriptionProviderKind? = nil
    @State private var subscriptionAccountId: String = ""
    @State private var browserConfig: PipiTeammateBrowserConfig = .default
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
                    if creationMode == .aiInterview {
                        architectInterviewPane
                    } else {
                        HStack(spacing: 0) {
                            templateGalleryPane
                                .frame(width: 280)

                            Rectangle()
                                .fill(PipiTokens.borderSubtle)
                                .frame(width: 1)

                            studioConfigurationPane
                        }
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
                preferredModelId = existing.preferredModelId ?? ""
                permissionTier = existing.permissionTier
                voiceProfileId = existing.voiceProfileId ?? ""
                assignedSkillSlugs = Set(existing.assignedSkillSlugs)
                enabledTools = Set(existing.enabledTools)
                enabledConnectors = Set(existing.enabledConnectors)
                sharingPolicy = existing.sharingPolicy
                runtimeMode = existing.runtimeMode
                reportsToBotId = existing.reportsToBotId ?? ""
                subscriptionProvider = existing.subscriptionProvider
                subscriptionAccountId = existing.subscriptionAccountId ?? ""
                browserConfig = existing.browserConfig
                previewEngine.setState(existing.idleAvatarState)
            } else if let first = PipiBotPersonaTemplate.catalog.first {
                applyTemplate(first)
            }
        }
    }

    // MARK: - Dr Eggbot AI Architect Interview Mode

    private var architectInterviewPane: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.t("蛋宝 · 目标优先自动化蓝图设计器", "Eggbot · Goal-First Automation Designer"))
                                .font(PipiTokens.fontHeadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text(s.t("先说清楚终极目标，再倒出你平时的步骤、裁决规则与验收标准；也可直接启动 1v1 语音/文字逐题访谈。", "Start with the Goal, brain-dump your process & verification criteria, or launch a live 1v1 voice/text interview with Eggbot."))
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                        }
                    }
                    .padding(PipiTokens.spacing12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PipiTokens.soulPrimary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(s.t("1. 终极目标（Goal — 你真正想要的结果，而不是某个步骤）", "1. Primary Goal (End outcome, not a single step)"))
                            .font(PipiTokens.fontCaption.weight(.semibold))
                            .foregroundStyle(PipiTokens.textSecondary)
                        TextField(
                            s.t("例如：每天自动汇总客户反馈并定位体验瓶颈，给出改进行动建议", "e.g. Automatically track PR reviews and verify tests pass before merge"),
                            text: $architectGoal,
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(s.t("2. 平时做法脑暴（用分号或换行分隔步骤）", "2. Current Process Brain-Dump (steps separated by ; or newlines)"))
                                .font(PipiTokens.fontCaption.weight(.semibold))
                                .foregroundStyle(PipiTokens.textSecondary)
                            Spacer()
                            if !store.voiceLiveTranscript.isEmpty {
                                Button(s.t("填入语音转写", "Insert Voice Transcript")) {
                                    let spoken = store.voiceLiveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !spoken.isEmpty {
                                        architectProcessDump = architectProcessDump.isEmpty ? spoken : "\(architectProcessDump)\n\(spoken)"
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                        TextEditor(text: $architectProcessDump)
                            .font(PipiTokens.fontBody)
                            .frame(height: 86)
                            .padding(6)
                            .background(PipiTokens.bgSurface)
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                            )
                    }

                    HStack(spacing: PipiTokens.spacing12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.t("3. 冲突数据源优先级（信谁？）", "3. Source-of-Truth Rules"))
                                .font(PipiTokens.fontCaption.weight(.semibold))
                                .foregroundStyle(PipiTokens.textSecondary)
                            TextField(s.t("例：以系统记录为准，不以邮件为准", "e.g. Booking DB wins over email"), text: $architectSourceRules)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.t("4. 验收完成标准（怎样算做完？）", "4. Verification Criteria"))
                                .font(PipiTokens.fontCaption.weight(.semibold))
                                .foregroundStyle(PipiTokens.textSecondary)
                            TextField(s.t("例：单测通过且已回复确认回执", "e.g. Tests pass and receipt sent"), text: $architectVerification)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    HStack(spacing: PipiTokens.spacing12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.t("5. Bot 名称（留空自动起名）", "5. Bot Name (optional)"))
                                .font(PipiTokens.fontCaption.weight(.semibold))
                                .foregroundStyle(PipiTokens.textSecondary)
                            TextField(s.t("例：巡检管家 / Potato", "e.g. Release Guardian"), text: $architectBotName)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.t("6. 自动触发方式（Routine）", "6. Event / Schedule Trigger"))
                                .font(PipiTokens.fontCaption.weight(.semibold))
                                .foregroundStyle(PipiTokens.textSecondary)
                            Picker("", selection: $architectTriggerKind) {
                                ForEach(PipiRoutineTriggerKind.allCases) { k in
                                    Text(k.label(lang)).tag(k)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    TextField(
                        s.t("触发参数（可选：Cron 如 30 9 * * 1-5 / Webhook 密钥 / 监听目录 / 微信关键词）", "Optional trigger detail (cron, webhook secret, path, or keyword)"),
                        text: $architectTriggerValue
                    )
                    .textFieldStyle(.roundedBorder)

                    HStack(spacing: PipiTokens.spacing12) {
                        Button {
                            let stepsJoined = architectProcessDump
                                .replacingOccurrences(of: "\n", with: ";")
                            let result = store.materializeBlueprintBot(from: [
                                "name": architectBotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? (lang == .zhHans ? "自动化伙伴" : "Auto Worker")
                                    : architectBotName,
                                "role": architectGoal,
                                "goal": architectGoal,
                                "process_steps": stepsJoined,
                                "source_of_truth_rules": architectSourceRules,
                                "verification_criteria": architectVerification,
                                "trigger_kind": architectTriggerKind.rawValue,
                                "trigger_value": architectTriggerValue
                            ])
                            onSaved?(result.persona)
                            onDismiss()
                        } label: {
                            Label(s.t("一键装配蓝图并上线", "Materialize Bot & Routine"), systemImage: "checkmark.seal.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(architectGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            _ = store.openBotArchitectSession()
                            onDismiss()
                        } label: {
                            Label(s.t("和蛋宝 1v1 逐题访谈", "1v1 Interview with Eggbot"), systemImage: "bubble.left.and.bubble.right")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(PipiTokens.spacing20)
            }

            Rectangle().fill(PipiTokens.borderSubtle).frame(width: 1)

            // Live Blueprint Preview Column
            ScrollView {
                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    Text(s.t("实时蓝图预览", "Live Blueprint Preview"))
                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                        .foregroundStyle(PipiTokens.textSecondary)

                    let previewSteps = architectProcessDump
                        .replacingOccurrences(of: "\n", with: ";")
                        .replacingOccurrences(of: "；", with: ";")
                        .split(separator: ";")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let previewBp = PipiBotAutomationBlueprint(
                        goal: architectGoal.isEmpty ? s.t("等待输入终极目标…", "Waiting for primary goal…") : architectGoal,
                        processSteps: previewSteps,
                        sourceOfTruthRules: architectSourceRules.isEmpty ? [] : [architectSourceRules],
                        verificationCriteria: architectVerification.isEmpty ? [] : [architectVerification]
                    )
                    Text(previewBp.renderedPromptBlock())
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(PipiTokens.spacing12)
                        .background(PipiTokens.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                }
                .padding(PipiTokens.spacing16)
            }
            .frame(width: 280)
            .background(PipiTokens.bgCanvas)
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
            if isCreateMode {
                Picker("", selection: $creationMode) {
                    Text(s.t("AI 访谈生成（推荐）", "AI Architect")).tag(CreationMode.aiInterview)
                    Text(s.t("手动表单", "Manual Form")).tag(CreationMode.manualForm)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
            }
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
            Text(s.t("角色模板", "Persona templates"))
                .font(PipiTokens.fontMicro)
                .foregroundStyle(PipiTokens.textMuted)
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

    private var suggestedModelChoicesForForm: [String] {
        var list: [String] = []
        let targetProvider: PipiLLMProviderConfig? = {
            if case .llm(let pid) = preferredTarget {
                return store.readyLLMProviders.first(where: { $0.id == pid })
            }
            if let defId = store.defaultLLMProviderId {
                return store.readyLLMProviders.first(where: { $0.id == defId }) ?? store.readyLLMProviders.first
            }
            return store.readyLLMProviders.first
        }()
        if let cfg = targetProvider {
            if let discovered = store.availableModelsByProviderId[cfg.id] {
                for m in discovered where !list.contains(m) { list.append(m) }
            }
            if !list.contains(cfg.modelId) { list.append(cfg.modelId) }
            for s in cfg.kind.suggestedModels where !list.contains(s) { list.append(s) }
        }
        return list
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
                        if !store.usableLocalAgents.isEmpty {
                            Divider()
                            ForEach(store.usableLocalAgents) { agent in
                                let t = PipiExecutionTarget.localAgent(agent.kind)
                                Button {
                                    preferredTarget = t
                                } label: {
                                    if preferredTarget == t {
                                        Label(agent.kind.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(agent.kind.displayName)
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

            // Optional per-bot specific model override (leave blank to follow global default model)
            VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                HStack {
                    Text(s.t("专属模型 ID（留空则使用默认模型）", "Specific Model ID (blank = use default model)"))
                        .font(PipiTokens.fontCaption.weight(.semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                    Spacer()
                    if !preferredModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(s.t("恢复默认", "Use Default")) {
                            preferredModelId = ""
                        }
                        .font(PipiTokens.fontMicro)
                        .buttonStyle(.plain)
                        .foregroundStyle(PipiTokens.textSecondary)
                    }
                }
                HStack(spacing: PipiTokens.spacing8) {
                    PipiTextField(
                        s.t("留空使用默认模型，或输入如 gpt-4o / deepseek-reasoner", "Leave blank for default model, or enter e.g. gpt-4o"),
                        text: $preferredModelId,
                        height: 32
                    )
                    if !suggestedModelChoicesForForm.isEmpty {
                        Menu {
                            Button(s.t("跟随默认模型（不指定）", "Use Default Model")) {
                                preferredModelId = ""
                            }
                            Divider()
                            ForEach(suggestedModelChoicesForForm, id: \.self) { m in
                                Button {
                                    preferredModelId = m
                                } label: {
                                    if preferredModelId == m {
                                        Label(m, systemImage: "checkmark")
                                    } else {
                                        Text(m)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(s.t("快速选择", "Pick"))
                                    .font(PipiTokens.fontCaption.weight(.medium))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(PipiTokens.textPrimary)
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
                    }
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
                        .font(PipiTokens.fontCaption.weight(.medium))
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

            // Brigade: 24/7 Cloud Residency, Org Reporting Line & Stacked Subscription Binding
            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                Text(s.t("运行模式（本机 / 24/7 云端）", "Runtime residency (Local / 24/7 Cloud)"))
                    .font(PipiTokens.fontCaption.weight(.medium))
                    .foregroundStyle(PipiTokens.textSecondary)

                PipiSegmentedControl(
                    options: PipiTeammateRuntimeMode.allCases,
                    selection: $runtimeMode
                ) { mode in
                    mode.label(lang)
                }

                HStack(spacing: PipiTokens.spacing12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.t("汇报对象（团队架构）", "Reports to (Org)"))
                            .font(PipiTokens.fontCaption.weight(.medium))
                            .foregroundStyle(PipiTokens.textSecondary)
                        Picker("", selection: $reportsToBotId) {
                            Text(s.t("团队负责人（Owner）", "Team Owner")).tag("")
                            ForEach(store.personas.filter { $0.id != existing?.id }) { candidate in
                                Text(candidate.name(lang)).tag(candidate.id)
                            }
                        }
                        .labelsHidden()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.t("绑定订阅 / 叠加账号池", "Stacked account pool"))
                            .font(PipiTokens.fontCaption.weight(.medium))
                            .foregroundStyle(PipiTokens.textSecondary)
                        Menu {
                            Button(s.t("不绑定（使用上方默认引擎）", "None (use engine above)")) {
                                subscriptionProvider = nil
                                subscriptionAccountId = ""
                            }
                            Divider()
                            ForEach(PipiSubscriptionProviderKind.allCases) { prov in
                                Button {
                                    subscriptionProvider = prov
                                    subscriptionAccountId = ""
                                    if let mapped = prov.mappedLocalAgentKind {
                                        preferredTarget = .localAgent(mapped)
                                    } else if prov.isOpenAICompatibleApiPool {
                                        preferredTarget = .llm(providerId: "\(PipiAppStore.poolProviderIdPrefix)\(prov.rawValue)")
                                    }
                                    if preferredModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        preferredModelId = prov.defaultModelId
                                    }
                                } label: {
                                    let count = store.subscriptionAccounts(for: prov).count
                                    if subscriptionProvider == prov {
                                        Label("\(prov.localizedName(lang)) (\(count))", systemImage: "checkmark")
                                    } else {
                                        Text("\(prov.localizedName(lang)) (\(count))")
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(subscriptionProvider?.localizedName(lang) ?? s.t("未绑定账号池", "Not bound"))
                                    .font(PipiTokens.fontCaption.weight(.medium))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9.5, weight: .medium))
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
                    }
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
                        capabilityChip(title: skill.title(lang), icon: "cube", isSelected: isOn) {
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
                    .font(PipiTokens.fontCaption.weight(.medium))
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

            // 5. Dedicated Isolated Cloud / Local Browser (Mainland China + Global Social Platforms)
            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.t("独立浏览器环境（云端 / 本机隔离 Cookie）", "Dedicated isolated browser (persistent cookies)"))
                            .font(PipiTokens.fontCaption.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.t("为该 AI 队友分配独立浏览器档案，适配小红书、微信公众号、抖音、微博、知乎、B站、即刻及 LinkedIn、Reddit、X。", "Assigns an isolated browser profile for Xiaohongshu, WeChat MP, Douyin, Weibo, Zhihu, Bilibili, Jike, LinkedIn, Reddit, and X."))
                            .font(PipiTokens.fontMicro.weight(.regular))
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    Spacer()
                    Toggle("", isOn: $browserConfig.enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if browserConfig.enabled {
                    Text(s.t("中国大陆平台", "Mainland China platforms"))
                        .font(PipiTokens.fontMicro.weight(.medium))
                        .foregroundStyle(PipiTokens.textMuted)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 98), spacing: 8)], spacing: 8) {
                        ForEach(PipiTeammateBrowserConfig.mainlandChinaPlatforms, id: \.self) { slug in
                            let isOn = browserConfig.platforms.contains(slug)
                            capabilityChip(
                                title: PipiTeammateBrowserConfig.platformDisplayName(slug, lang: lang),
                                icon: "globe",
                                isSelected: isOn
                            ) {
                                if isOn {
                                    browserConfig.platforms.removeAll { $0 == slug }
                                } else {
                                    browserConfig.platforms.append(slug)
                                }
                            }
                        }
                    }

                    Text(s.t("海外与通用平台", "Global platforms"))
                        .font(PipiTokens.fontMicro.weight(.medium))
                        .foregroundStyle(PipiTokens.textMuted)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 98), spacing: 8)], spacing: 8) {
                        ForEach(PipiTeammateBrowserConfig.globalPlatforms, id: \.self) { slug in
                            let isOn = browserConfig.platforms.contains(slug)
                            capabilityChip(
                                title: PipiTeammateBrowserConfig.platformDisplayName(slug, lang: lang),
                                icon: "globe",
                                isSelected: isOn
                            ) {
                                if isOn {
                                    browserConfig.platforms.removeAll { $0 == slug }
                                } else {
                                    browserConfig.platforms.append(slug)
                                }
                            }
                        }
                    }

                    HStack {
                        Text(s.t("在社交平台发布笔记、群发、评论或私信前送审确认", "Require approval before posting, replying, or sending DMs"))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                        Spacer()
                        Toggle("", isOn: $browserConfig.requireApprovalBeforePost)
                            .labelsHidden()
                            .toggleStyle(.switch)
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
            let cleanModel = preferredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
            ex.preferredModelId = cleanModel.isEmpty ? nil : cleanModel
            ex.permissionTier = permissionTier
            ex.voiceProfileId = voiceProfileId.isEmpty ? nil : voiceProfileId
            ex.assignedSkillSlugs = Array(assignedSkillSlugs).sorted()
            ex.enabledTools = Array(enabledTools).sorted()
            ex.enabledConnectors = Array(enabledConnectors).sorted()
            ex.sharingPolicy = sharingPolicy
            ex.runtimeMode = runtimeMode
            ex.reportsToBotId = reportsToBotId.isEmpty ? nil : reportsToBotId
            ex.subscriptionProvider = subscriptionProvider
            ex.subscriptionAccountId = subscriptionAccountId.isEmpty ? nil : subscriptionAccountId
            ex.browserConfig = browserConfig
            if browserConfig.enabled && !ex.enabledTools.contains(PipiBotToolKind.browserSeat.rawValue) {
                ex.enabledTools.append(PipiBotToolKind.browserSeat.rawValue)
            }
            savedPersona = ex
        } else {
            var created = selectedTemplate.instantiate(
                customName: cleanName,
                customPrompt: cleanPrompt.isEmpty ? nil : cleanPrompt,
                accent: accent,
                avatarShape: shape,
                permissionTier: permissionTier,
                preferredTarget: preferredTarget,
                preferredModelId: preferredModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : preferredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
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
            created.runtimeMode = runtimeMode
            created.reportsToBotId = reportsToBotId.isEmpty ? nil : reportsToBotId
            created.subscriptionProvider = subscriptionProvider
            created.subscriptionAccountId = subscriptionAccountId.isEmpty ? nil : subscriptionAccountId
            created.browserConfig = browserConfig
            if browserConfig.enabled && !created.enabledTools.contains(PipiBotToolKind.browserSeat.rawValue) {
                created.enabledTools.append(PipiBotToolKind.browserSeat.rawValue)
            }
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
