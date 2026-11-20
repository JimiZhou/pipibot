// PiPiBot — Clean-room MIT implementation.
// Wave 2 Native macOS Hub for #01 Personal Wiki, #02 Per-Bot Memory & #03 Native Proactive Prepare.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

import SwiftUI
import PipiBotKit

public enum PipiKnowledgeHubTab: String, CaseIterable, Identifiable, Sendable {
    case wiki
    case proactive
    case pocketNotes
    case botMemory
    case builtinSkills

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .wiki: return "books.vertical"
        case .proactive: return "sparkles.rectangle.stack"
        case .pocketNotes: return "note.text"
        case .botMemory: return "brain.head.profile"
        case .builtinSkills: return "shippingbox"
        }
    }

    public func title(_ s: PipiStrings) -> String {
        switch self {
        case .wiki: return s.wikiTabTitle
        case .proactive: return s.proactiveTabTitle
        case .pocketNotes: return s.pocketNotesTabTitle
        case .botMemory: return s.botMemoryTabTitle
        case .builtinSkills: return s.builtinSkillsTabTitle
        }
    }
}

public struct PipiKnowledgeHubView: View {
    @Bindable public var store: PipiAppStore
    public var onOpenSession: (String) -> Void

    @Environment(\.pipiTextScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedTab: PipiKnowledgeHubTab = .wiki
    @State private var selectedWikiCategory: PipiWikiEntityCategory? = nil
    @State private var wikiSearchQuery: String = ""
    @State private var wikiAlternatesText: String = ""
    @State private var wikiStartDate: String = ""
    @State private var wikiEndDate: String = ""
    @State private var showAdvancedSearch: Bool = false

    // Wiki Editor Sheet State
    @State private var showWikiEditor: Bool = false
    @State private var editingWikiPageId: String? = nil
    @State private var formCategory: PipiWikiEntityCategory = .projects
    @State private var formTitle: String = ""
    @State private var formAliases: String = ""
    @State private var formSummary: String = ""
    @State private var formEventDate: String = ""
    @State private var formBody: String = ""

    // Proactive Scan State
    @State private var isScanningSignals: Bool = false
    @State private var lastScanStatus: String? = nil

    // Bot Memory Editor State
    @State private var selectedBotId: String = ""
    @State private var draftBotSummary: String = ""
    @State private var botMemoryFeedback: String? = nil

    // Wave 3 (#11) Pocket Notes, Editable Artifact Docs & Builtin Skills State
    @State private var pocketNoteDateYmd: String = PipiProactiveEngine.formatLocalYmd(Date())
    @State private var pocketNoteDraft: String = ""
    @State private var pocketNoteFeedback: String? = nil
    @State private var showDocEditor: Bool = false
    @State private var editingDocId: String? = nil
    @State private var docTitleDraft: String = ""
    @State private var docKindDraft: PipiArtifactDocumentKind = .note
    @State private var docBodyDraft: String = ""
    @State private var skillsStatusBanner: String? = nil
    @State private var previewSkillPack: PipiBuiltinSkillPack? = nil

    public init(
        store: PipiAppStore,
        onOpenSession: @escaping (String) -> Void
    ) {
        self.store = store
        self.onOpenSession = onOpenSession
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    private var resolvedBotId: String {
        if !selectedBotId.isEmpty, store.personas.contains(where: { $0.id == selectedBotId }) {
            return selectedBotId
        }
        return store.activePersona.id
    }

    public var body: some View {
        let _ = textScale
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

            switch selectedTab {
            case .wiki:
                wikiTabBody
            case .proactive:
                proactiveTabBody
            case .pocketNotes:
                pocketNotesTabBody
            case .botMemory:
                botMemoryTabBody
            case .builtinSkills:
                builtinSkillsTabBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PipiTokens.bgCanvas)
        .background(alignment: .top) {
            PipiTokens.bgCanvas
                .frame(height: 72)
                .ignoresSafeArea(.container, edges: .top)
        }
        .onAppear {
            store.refreshWikiPages()
            store.refreshEventKitAuthStates()
            if selectedBotId.isEmpty {
                selectedBotId = store.activePersona.id
            }
            draftBotSummary = store.botMemorySummary(for: resolvedBotId)
            pocketNoteDraft = store.dailyPocketNoteText(for: pocketNoteDateYmd)
        }
        .onChange(of: selectedBotId) { _, newId in
            draftBotSummary = store.botMemorySummary(for: newId)
            botMemoryFeedback = nil
        }
        .sheet(isPresented: $showWikiEditor) {
            wikiEditorSheet
                .frame(minWidth: 540, minHeight: 500)
        }
        .sheet(isPresented: $showDocEditor) {
            docEditorSheet
                .frame(minWidth: 540, minHeight: 480)
        }
        .sheet(item: $previewSkillPack) { skill in
            skillPreviewSheet(skill)
                .frame(minWidth: 500, minHeight: 420)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: PipiTokens.spacing12) {
            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                .fill(PipiTokens.bgSurfaceHover)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: selectedTab.iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                )

            HStack(spacing: PipiTokens.spacing8) {
                Text(s.knowledgeHubTitle)
                    .font(PipiTokens.fontTitle)
                    .tracking(PipiTokens.trackingTitle)
                    .foregroundStyle(PipiTokens.textPrimary)
                PipiInfoHelpButton(
                    title: s.knowledgeHubTitle,
                    message: s.knowledgeHubSubtitle
                )
            }

            Spacer()

            PipiSegmentedControl(
                options: PipiKnowledgeHubTab.allCases,
                selection: $selectedTab
            ) { tab in
                tab.title(s)
            }
        }
        .padding(.horizontal, PipiTokens.spacing24)
        .padding(.vertical, PipiTokens.spacing16)
    }

    // MARK: - Tab 1: #01 Personal Entity Wiki (SQLite WAL + FTS5 Dual-Channel Search)

    private var wikiTabBody: some View {
        let trimmedQuery = wikiSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchResult: PipiWikiSearchResult? = trimmedQuery.isEmpty ? nil : store.searchPersonalWiki(
            PipiWikiSearchOptions(
                query: trimmedQuery,
                alternates: wikiAlternatesText
                    .components(separatedBy: CharacterSet(charactersIn: ",，"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty },
                startDate: wikiStartDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : wikiStartDate.trimmingCharacters(in: .whitespacesAndNewlines),
                endDate: wikiEndDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : wikiEndDate.trimmingCharacters(in: .whitespacesAndNewlines),
                category: selectedWikiCategory,
                scope: .all,
                limit: 12,
                factLimit: 12
            )
        )
        let filteredPages: [PipiPersonalWikiPage] = {
            if let cat = selectedWikiCategory {
                return store.wikiPages.filter { $0.category == cat }
            }
            return store.wikiPages
        }()

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                HStack(spacing: PipiTokens.spacing8) {
                    PipiTextField(
                        s.wikiSearchPlaceholder,
                        text: $wikiSearchQuery,
                        systemImage: "magnifyingglass",
                        height: 34
                    )

                    PipiActionButton(
                        s.t("筛选", "Filter"),
                        systemImage: "slider.horizontal.3",
                        tone: showAdvancedSearch ? .primary : .secondary,
                        density: .desktopCompact
                    ) {
                        withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                            showAdvancedSearch.toggle()
                        }
                    }

                    PipiActionButton(
                        s.wikiNewPage,
                        systemImage: "plus",
                        tone: .primary,
                        density: .desktopCompact
                    ) {
                        openNewWikiPageSheet()
                    }
                }

                if showAdvancedSearch {
                    HStack(spacing: PipiTokens.spacing8) {
                        PipiTextField(s.t("同义词（逗号分隔）", "Alternates (comma-separated)"), text: $wikiAlternatesText, height: 30)
                        PipiTextField("Start YYYY-MM-DD", text: $wikiStartDate, monospaced: true, height: 30)
                            .frame(width: 142)
                        PipiTextField("End YYYY-MM-DD", text: $wikiEndDate, monospaced: true, height: 30)
                            .frame(width: 142)
                    }
                }

                // Category Filter Pills
                HStack(spacing: PipiTokens.spacing8) {
                    categoryFilterPill(label: s.allBotsFilter, icon: "square.grid.2x2", isSelected: selectedWikiCategory == nil) {
                        selectedWikiCategory = nil
                    }
                    ForEach(PipiWikiEntityCategory.allCases) { cat in
                        categoryFilterPill(label: cat.label(lang), icon: cat.iconName, isSelected: selectedWikiCategory == cat) {
                            selectedWikiCategory = cat
                        }
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, PipiTokens.spacing24)
            .padding(.vertical, PipiTokens.spacing12)

            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

            if let searchResult {
                wikiSearchResultsList(searchResult)
            } else if filteredPages.isEmpty {
                PipiEmptyState(
                    systemImage: "books.vertical",
                    title: s.wikiEmptyTitle,
                    message: s.wikiEmptyMessage,
                    buttonTitle: s.wikiNewPage
                ) {
                    openNewWikiPageSheet()
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                        ForEach(filteredPages) { page in
                            wikiPageCard(page)
                        }
                    }
                    .frame(maxWidth: 820)
                    .padding(PipiTokens.spacing24)
                    .frame(maxWidth: .infinity)
                }
                .pipiHideScrollbars()
            }
        }
    }

    private func categoryFilterPill(label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(label)
                    .font(PipiTokens.fontCaption.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? PipiTokens.bgSurfaceHover : PipiTokens.bgElevated, in: Capsule())
            .overlay(Capsule().stroke(isSelected ? PipiTokens.borderStrong : PipiTokens.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.98))
    }

    private func wikiPageCard(_ page: PipiPersonalWikiPage) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            HStack(spacing: PipiTokens.spacing8) {
                Image(systemName: page.category.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PipiTokens.textSecondary)
                Text(page.title)
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)
                Text(page.category.label(lang))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(PipiTokens.bgInset, in: Capsule())
                if let eventDate = page.eventDate, !eventDate.isEmpty {
                    Text(eventDate)
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                }
                Spacer()
                PipiActionButton(s.t("编辑", "Edit"), systemImage: "pencil", tone: .ghost, density: .desktopCompact) {
                    openEditWikiPageSheet(page)
                }
                PipiGhostIconButton(
                    systemImage: "trash",
                    size: 26,
                    iconSize: 11.5,
                    accessibilityLabel: s.delete
                ) {
                    store.deleteWikiPage(id: page.id)
                }
            }

            if !page.aliases.isEmpty {
                Text("\(s.t("别名", "Aliases")): \(page.aliases.joined(separator: " · "))")
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textMuted)
            }

            Text(page.summary)
                .font(PipiTokens.fontBody)
                .foregroundStyle(PipiTokens.textSecondary)
                .lineLimit(3)
        }
        .padding(PipiTokens.spacing16)
        .background(PipiTokens.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }

    private func wikiSearchResultsList(_ res: PipiWikiSearchResult) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                HStack(spacing: PipiTokens.spacing8) {
                    Text(s.t("检索词：\(res.effectiveQueries.joined(separator: " / "))", "Queries: \(res.effectiveQueries.joined(separator: " / "))"))
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                    Spacer()
                    Text("\(res.summaries.count) pages · \(res.chunks.count) chunks · \(res.facts.count) facts")
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                }

                if res.summaries.isEmpty && res.chunks.isEmpty && res.facts.isEmpty {
                    PipiEmptyState(
                        systemImage: "magnifyingglass",
                        title: s.t("没有找到匹配结果", "No Matching Wiki Results"),
                        message: s.t("尝试换个关键词或添加同义改写词。", "Try another keyword or add alternate wordings.")
                    )
                } else {
                    if !res.summaries.isEmpty {
                        sectionHeader(s.t("实体摘要通道 (Summaries)", "Entity Summaries Channel"))
                        ForEach(res.summaries) { hit in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(hit.title)
                                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Text(hit.category.label(lang))
                                        .font(PipiTokens.fontMicro)
                                        .foregroundStyle(PipiTokens.textSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(PipiTokens.bgInset, in: Capsule())
                                    Spacer()
                                    if let page = store.personalWiki?.getPage(id: hit.pageId) {
                                        PipiActionButton(s.t("查看", "Open"), tone: .ghost, density: .desktopCompact) {
                                            openEditWikiPageSheet(page)
                                        }
                                    }
                                }
                                Text(hit.summary)
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textSecondary)
                            }
                            .padding(PipiTokens.spacing12)
                            .background(PipiTokens.bgElevated)
                            .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        }
                    }

                    if !res.facts.isEmpty {
                        sectionHeader(s.t("独立事实通道 (Facts)", "Independent Facts Channel"))
                        ForEach(res.facts) { fact in
                            HStack(alignment: .top, spacing: PipiTokens.spacing8) {
                                Image(systemName: "sparkle")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(PipiTokens.textSecondary)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fact.factText)
                                        .font(PipiTokens.fontBody)
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    HStack(spacing: 6) {
                                        Text(fact.pageTitle)
                                            .font(PipiTokens.fontMicro)
                                            .foregroundStyle(PipiTokens.textMuted)
                                        if let date = fact.eventDate {
                                            Text(date)
                                                .font(PipiTokens.fontMonoSmall)
                                                .foregroundStyle(fact.inTimeWindow ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                        }
                                    }
                                }
                                Spacer()
                            }
                            .padding(PipiTokens.spacing12)
                            .background(PipiTokens.bgElevated)
                            .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        }
                    }

                    if !res.chunks.isEmpty {
                        sectionHeader(s.t("原文片段通道 (Originals Chunks)", "Originals Chunks Channel"))
                        ForEach(res.chunks) { chunk in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("\(chunk.title) · \(chunk.sectionHeading)")
                                        .font(PipiTokens.fontSubheadline.weight(.semibold))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                    Spacer()
                                    if chunk.inTimeWindow {
                                        Text(s.t("时间窗加权", "In Window"))
                                            .font(PipiTokens.fontMicro)
                                            .foregroundStyle(PipiTokens.stateSuccess)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(PipiTokens.bgInset, in: Capsule())
                                    }
                                }
                                Text(chunk.content)
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.textSecondary)
                                    .lineLimit(4)
                            }
                            .padding(PipiTokens.spacing12)
                            .background(PipiTokens.bgElevated)
                            .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        }
                    }
                }
            }
            .frame(maxWidth: 820)
            .padding(PipiTokens.spacing24)
            .frame(maxWidth: .infinity)
        }
        .pipiHideScrollbars()
    }

    // MARK: - Tab 2: #03 macOS Native Proactive & Prepare Briefings

    private var proactiveTabBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: PipiTokens.spacing12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: PipiTokens.spacing8) {
                        Text(s.t("macOS 原生事件源", "macOS Native Sources"))
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text("v\(store.proactiveGuidelineVersion) · \(store.proactiveRules.count) rules")
                            .font(PipiTokens.fontMonoSmall)
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    Text(
                        lastScanStatus ?? s.t(
                            "日历: \(store.eventKitCalendarAuth.label(lang)) · 提醒: \(store.eventKitRemindersAuth.label(lang)) · 静音窗 \(store.proactivePolicy.quietHoursStart):00–\(store.proactivePolicy.quietHoursEnd):00",
                            "Calendar: \(store.eventKitCalendarAuth.label(lang)) · Reminders: \(store.eventKitRemindersAuth.label(lang)) · Quiet \(store.proactivePolicy.quietHoursStart):00–\(store.proactivePolicy.quietHoursEnd):00"
                        )
                    )
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                }

                Spacer()

                if store.eventKitCalendarAuth == .notDetermined {
                    PipiActionButton(s.t("授权日历", "Allow Calendar"), systemImage: "calendar", tone: .secondary, density: .desktopCompact) {
                        Task { await store.requestEventKitCalendarAccess() }
                    }
                }

                PipiActionButton(
                    isScanningSignals ? s.t("扫描中...", "Scanning...") : s.proactiveScanNow,
                    systemImage: "arrow.clockwise",
                    tone: .primary,
                    density: .desktopCompact
                ) {
                    guard !isScanningSignals else { return }
                    isScanningSignals = true
                    Task {
                        let results = await store.scanNativeProactiveSignals()
                        let preparedCount = results.filter { $0.briefing != nil }.count
                        lastScanStatus = s.t(
                            "本次扫描发现 \(results.count) 条原生信号，生成 \(preparedCount) 条主动简报/备料。",
                            "Scanned \(results.count) native signal(s), generated \(preparedCount) briefing(s)."
                        )
                        isScanningSignals = false
                    }
                }
            }
            .padding(.horizontal, PipiTokens.spacing24)
            .padding(.vertical, PipiTokens.spacing12)

            Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

            if store.proactiveBriefings.isEmpty {
                PipiEmptyState(
                    systemImage: "sparkles.rectangle.stack",
                    title: s.proactiveEmptyTitle,
                    message: s.proactiveEmptyMessage,
                    buttonTitle: s.proactiveScanNow
                ) {
                    Task {
                        _ = await store.scanNativeProactiveSignals()
                    }
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                        ForEach(store.proactiveBriefings) { briefing in
                            briefingCard(briefing)
                        }
                    }
                    .frame(maxWidth: 820)
                    .padding(PipiTokens.spacing24)
                    .frame(maxWidth: .infinity)
                }
                .pipiHideScrollbars()
            }
        }
    }

    private func briefingCard(_ briefing: PipiPreparedBriefing) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack(spacing: PipiTokens.spacing8) {
                Image(systemName: briefing.source.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PipiTokens.textSecondary)
                Text(briefing.title)
                    .font(PipiTokens.fontHeadline)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)
                Text(briefing.decision.label(lang))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(briefing.decision == .prepareBriefing ? PipiTokens.stateSuccess : PipiTokens.textSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(PipiTokens.bgInset, in: Capsule())
                Spacer()
                if let fb = briefing.feedback {
                    Text(fb.label(lang))
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textMuted)
                }
            }

            Text(briefing.summary)
                .font(PipiTokens.fontBody)
                .foregroundStyle(PipiTokens.textSecondary)

            if !briefing.bulletPoints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(briefing.bulletPoints.prefix(5).enumerated()), id: \.offset) { _, line in
                        Text("• \(line)")
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                }
            }

            HStack(spacing: PipiTokens.spacing8) {
                PipiActionButton(s.t("在对话中继续", "Open in Chat"), systemImage: "arrow.up.right", tone: .primary, density: .desktopCompact) {
                    let conv = store.openBriefingInChat(briefing)
                    onOpenSession(conv.id)
                }
                PipiActionButton(s.t("有帮助", "Helpful"), systemImage: "hand.thumbsup", tone: .secondary, density: .desktopCompact) {
                    store.recordProactiveFeedback(briefingId: briefing.id, signal: .thanked)
                }
                PipiActionButton(s.t("稍后", "Snooze"), tone: .ghost, density: .desktopCompact) {
                    store.recordProactiveFeedback(briefingId: briefing.id, signal: .snoozed)
                }
                PipiActionButton(s.t("不再提醒此类", "Mute Topic"), tone: .ghost, density: .desktopCompact) {
                    store.recordProactiveFeedback(briefingId: briefing.id, signal: .mutedTopic)
                }
            }
        }
        .padding(PipiTokens.spacing16)
        .background(PipiTokens.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }

    // MARK: - Tab 3: #02 Per-Bot Isolated Experiential Memory

    private var botMemoryTabBody: some View {
        let state = store.botMemoryState(for: resolvedBotId)
        let candidates = store.botMemoryCandidates(for: resolvedBotId)
        let pendingCandidates = candidates.filter { $0.stage == .candidate }

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PipiTokens.spacing8) {
                        ForEach(store.personas) { persona in
                            let isSel = persona.id == resolvedBotId
                            Button {
                                selectedBotId = persona.id
                            } label: {
                                HStack(spacing: 6) {
                                    PipiBotPersonaGlyph(persona: persona, size: 18, isSelected: isSel)
                                    Text(persona.name(lang))
                                        .font(PipiTokens.fontCaption.weight(isSel ? .semibold : .regular))
                                        .foregroundStyle(isSel ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isSel ? PipiTokens.bgSurfaceHover : PipiTokens.bgElevated, in: Capsule())
                                .overlay(Capsule().stroke(isSel ? PipiTokens.borderStrong : PipiTokens.borderSubtle, lineWidth: 1))
                            }
                            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.98))
                        }
                    }
                }

                // Memory Telemetry Card (Key-Value + Folded Help)
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    HStack {
                        Text(s.t("版本 rev \(state.revision) · 成功 \(state.totalSuccessfulRuns) 次", "rev \(state.revision) · \(state.totalSuccessfulRuns) runs"))
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.botMemoryCacheSafeBadge)
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.stateSuccess)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(PipiTokens.bgInset, in: Capsule())
                        PipiInfoHelpButton(
                            title: s.t("助手独立记忆", "Isolated Assistant Memory"),
                            message: s.t("每位助手的经验摘要相互隔离，仅在会话首轮或上下文压缩后注入，不破坏提示词缓存。", "Strictly isolated per assistant and injected only on first or post-compaction turns to preserve prompt caching.")
                        )
                        Spacer()
                        PipiActionButton(s.botMemoryConsolidateNow, systemImage: "sparkles", tone: .secondary, density: .desktopCompact) {
                            Task {
                                let res = await store.consolidateBotMemoryNow(for: resolvedBotId)
                                draftBotSummary = res.summary
                                botMemoryFeedback = res.consolidated
                                    ? s.t("已更新至 rev \(res.state.revision)。", "Updated to rev \(res.state.revision).")
                                    : s.t("暂无待合并记录。", "No pending items to consolidate.")
                            }
                        }
                    }

                    Text(
                        s.t(
                            "提炼进度 \(state.successfulRunsSinceLastExtract)/5 · 待合并 \(pendingCandidates.count) 条 · 大小 \(state.summaryByteSize) B",
                            "Progress \(state.successfulRunsSinceLastExtract)/5 · Pending \(pendingCandidates.count) · Size \(state.summaryByteSize) B"
                        )
                    )
                    .font(PipiTokens.fontMonoSmall)
                    .foregroundStyle(PipiTokens.textSecondary)

                    if let botMemoryFeedback {
                        Text(botMemoryFeedback)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.stateSuccess)
                    }
                }
                .padding(PipiTokens.spacing16)
                .background(PipiTokens.bgElevated)
                .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))

                // Editable summary.md
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    HStack {
                        Text("summary.md")
                            .font(PipiTokens.fontMono.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Spacer()
                        PipiActionButton(s.save, systemImage: "checkmark", tone: .primary, density: .desktopCompact) {
                            store.saveBotMemorySummary(for: resolvedBotId, summary: draftBotSummary)
                            botMemoryFeedback = s.t("已保存 Bot 经验摘要。", "Saved Bot memory summary.")
                        }
                    }

                    TextEditor(text: $draftBotSummary)
                        .font(PipiTokens.fontMono)
                        .scrollContentBackground(.hidden)
                        .padding(PipiTokens.spacing12)
                        .frame(minHeight: 200)
                        .background(PipiTokens.bgInset)
                        .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                }
                .padding(PipiTokens.spacing16)
                .background(PipiTokens.bgElevated)
                .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
            }
            .frame(maxWidth: 820)
            .padding(PipiTokens.spacing24)
            .frame(maxWidth: .infinity)
        }
        .pipiHideScrollbars()
    }

    // MARK: - Tab 4: #11 Daily Pocket Notes (5m Silence) & Editable Artifact Documents

    private var pocketNotesTabBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing20) {
                // Daily Pocket Note Card
                VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                    HStack {
                        HStack(spacing: 6) {
                            Text(s.t("每日随手记 · \(pocketNoteDateYmd)", "Daily Note · \(pocketNoteDateYmd)"))
                                .font(PipiTokens.fontHeadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                            PipiInfoHelpButton(
                                title: s.t("自动提炼待办", "Auto-Extract To-Dos"),
                                message: s.t("使用 `- [ ] 任务` 或 `待办：...` 记录事项；停止编辑 5 分钟后或点击「提炼待办」将自动汇总。", "Write `- [ ] task` or `TODO: ...` lines; items automatically sync after 5 minutes of inactivity or on demand.")
                            )
                        }
                        Spacer()
                        PipiActionButton(s.save, tone: .secondary, density: .desktopCompact) {
                            _ = store.saveDailyPocketNote(dateYmd: pocketNoteDateYmd, content: pocketNoteDraft)
                            pocketNoteFeedback = s.t("已保存。", "Saved.")
                        }
                        PipiActionButton(s.extractTodosNow, systemImage: "checklist", tone: .primary, density: .desktopCompact) {
                            _ = store.saveDailyPocketNote(dateYmd: pocketNoteDateYmd, content: pocketNoteDraft)
                            let res = store.reconcileDailyPocketNote(dateYmd: pocketNoteDateYmd, force: true)
                            pocketNoteFeedback = s.t(
                                "新增 \(res.added.count) 条 · 当前待办 \(res.openItems.count) 条",
                                "+\(res.added.count) added · \(res.openItems.count) open"
                            )
                        }
                    }

                    TextEditor(text: $pocketNoteDraft)
                        .font(PipiTokens.fontBody)
                        .scrollContentBackground(.hidden)
                        .pipiHideScrollbars()
                        .padding(PipiTokens.spacing12)
                        .frame(minHeight: 140)
                        .background(PipiTokens.composerSurface)
                        .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous).strokeBorder(PipiTokens.composerBorder, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

                    if let pocketNoteFeedback {
                        Text(pocketNoteFeedback)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.stateSuccess)
                    }
                }
                .padding(PipiTokens.spacing16)
                .background(PipiTokens.bgElevated)
                .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))

                // Extracted Tracking Items
                if !store.pocketTrackingItems.isEmpty {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                        sectionHeader(s.t("已提炼待办事项 (\(store.pocketTrackingItems.count))", "Tracking Items (\(store.pocketTrackingItems.count))"))
                        ForEach(store.pocketTrackingItems) { item in
                            HStack(spacing: PipiTokens.spacing12) {
                                Button {
                                    let next: PipiTrackingItemStatus = item.status == .done ? .open : .done
                                    store.setTrackingItemStatus(id: item.id, status: next)
                                } label: {
                                    Image(systemName: item.status == .done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(item.status == .done ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(item.title)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(PipiTokens.fontBody)
                                        .strikethrough(item.status == .done)
                                        .foregroundStyle(item.status == .done ? PipiTokens.textMuted : PipiTokens.textPrimary)
                                    Text("\(item.sourceDateYmd)\(item.dueDateYmd.map { " · due \($0)" } ?? "")")
                                        .font(PipiTokens.fontMonoSmall)
                                        .foregroundStyle(PipiTokens.textMuted)
                                }
                                Spacer()
                            }
                            .padding(PipiTokens.spacing12)
                            .background(PipiTokens.bgElevated)
                            .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        }
                    }
                }

                // Editable Artifact Documents
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    HStack {
                        sectionHeader(s.t("可编辑产物文档 (\(store.artifactDocuments.count))", "Editable Artifact Documents (\(store.artifactDocuments.count))"))
                        Spacer()
                        PipiActionButton(s.newDocumentAction, systemImage: "plus", tone: .secondary, density: .desktopCompact) {
                            editingDocId = nil
                            docTitleDraft = ""
                            docKindDraft = .plan
                            docBodyDraft = "# \n"
                            showDocEditor = true
                        }
                    }

                    if store.artifactDocuments.isEmpty {
                        Text(s.t("暂无文档，点击「新建文档」创建。", "No documents yet. Click New Document to create one."))
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textMuted)
                            .padding(PipiTokens.spacing16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PipiTokens.bgElevated)
                            .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                    } else {
                        ForEach(store.artifactDocuments) { doc in
                            HStack(spacing: PipiTokens.spacing12) {
                                Image(systemName: doc.kind.iconName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(PipiTokens.textSecondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(doc.title)
                                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                        Text("rev \(doc.revision) · \(doc.kind.label(lang))")
                                            .font(PipiTokens.fontMicro)
                                            .foregroundStyle(PipiTokens.textSecondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1.5)
                                            .background(PipiTokens.bgInset, in: Capsule())
                                    }
                                    Text("sha256: \(doc.contentSha256.prefix(12))")
                                        .font(PipiTokens.fontMonoSmall)
                                        .foregroundStyle(PipiTokens.textMuted)
                                }
                                Spacer()
                                PipiActionButton(s.syncToWikiAction, systemImage: "arrow.triangle.2.circlepath", tone: .ghost, density: .desktopCompact) {
                                    _ = store.syncArtifactDocumentToWiki(docId: doc.id)
                                    pocketNoteFeedback = s.t("已将「\(doc.title)」同步至个人 Wiki。", "Synced \"\(doc.title)\" to Personal Wiki.")
                                }
                                PipiActionButton(s.t("编辑", "Edit"), systemImage: "pencil", tone: .secondary, density: .desktopCompact) {
                                    editingDocId = doc.id
                                    docTitleDraft = doc.title
                                    docKindDraft = doc.kind
                                    docBodyDraft = doc.markdown
                                    showDocEditor = true
                                }
                                PipiGhostIconButton(systemImage: "trash", size: 26, iconSize: 11.5, accessibilityLabel: s.delete) {
                                    store.deleteArtifactDocument(id: doc.id)
                                }
                            }
                            .padding(PipiTokens.spacing12)
                            .background(PipiTokens.bgElevated)
                            .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                        }
                    }
                }
            }
            .frame(maxWidth: 820)
            .padding(PipiTokens.spacing24)
            .frame(maxWidth: .infinity)
        }
        .pipiHideScrollbars()
    }

    // MARK: - Tab 5: #11 Versioned Builtin Read-Only Skill Packs

    private var builtinSkillsTabBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(s.t("内置技能 (\(PipiBuiltinSkillsRegistry.allPacks.count))",
                                     "Builtin Skills (\(PipiBuiltinSkillsRegistry.allPacks.count))"))
                                .font(PipiTokens.fontHeadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                            PipiInfoHelpButton(
                                title: s.t("只读技能校验", "Read-Only Skill Verification"),
                                message: s.t("内置技能包带 SHA-256 摘要校验，以只读权限同步至工作区，防止运行中被修改。", "Builtin skills include SHA-256 checksums and sync read-only into the workspace.")
                            )
                        }
                        if let skillsStatusBanner {
                            Text(skillsStatusBanner)
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.stateSuccess)
                        }
                    }
                    Spacer()
                    PipiActionButton(s.projectSkillsAction, systemImage: "checkmark.shield", tone: .primary, density: .desktopCompact) {
                        let receipts = store.projectBuiltinSkillsNow()
                        let report = store.verifyBuiltinSkillsNow()
                        skillsStatusBanner = report.valid
                            ? s.t("已校验 \(receipts.count) 项内置技能，完整性通过。",
                                  "Verified \(receipts.count) builtin skill(s).")
                            : s.t("发现 \(report.mismatches.count) 处校验异常。", "Found \(report.mismatches.count) mismatch(es).")
                    }
                }
                .padding(PipiTokens.spacing16)
                .background(PipiTokens.bgElevated)
                .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))

                ForEach(PipiBuiltinSkillsRegistry.allPacks) { skill in
                    let receipt = store.builtinSkillReceipts.first(where: { $0.slug == skill.slug })
                    HStack(spacing: PipiTokens.spacing12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(skill.title(lang))
                                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Text("\(skill.slug) · v\(skill.version)")
                                    .font(PipiTokens.fontMonoSmall)
                                    .foregroundStyle(PipiTokens.textSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(PipiTokens.bgInset, in: Capsule())
                                if let receipt {
                                    Text(receipt.status.rawValue)
                                        .font(PipiTokens.fontMicro)
                                        .foregroundStyle(PipiTokens.stateSuccess)
                                }
                            }
                            Text(skill.description)
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                            Text("sha256: \(skill.sha256.prefix(16))…")
                                .font(PipiTokens.fontMonoSmall)
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                        Spacer()
                        PipiActionButton(s.t("查看", "Inspect"), tone: .secondary, density: .desktopCompact) {
                            previewSkillPack = skill
                        }
                    }
                    .padding(PipiTokens.spacing12)
                    .background(PipiTokens.bgElevated)
                    .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                }
            }
            .frame(maxWidth: 820)
            .padding(PipiTokens.spacing24)
            .frame(maxWidth: .infinity)
        }
        .pipiHideScrollbars()
    }

    private var docEditorSheet: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack {
                Text(editingDocId == nil ? s.newDocumentAction : s.t("编辑产物文档", "Edit Artifact Document"))
                    .font(PipiTokens.fontTitle)
                    .foregroundStyle(PipiTokens.textPrimary)
                Spacer()
                PipiGhostIconButton(systemImage: "xmark", size: 28, iconSize: 12, accessibilityLabel: s.close) {
                    showDocEditor = false
                }
            }

            HStack(spacing: PipiTokens.spacing12) {
                PipiSelectMenu(
                    options: PipiArtifactDocumentKind.allCases,
                    selection: $docKindDraft,
                    width: 132
                ) { kind in
                    kind.label(lang)
                }

                PipiTextField(s.t("文档标题", "Document title"), text: $docTitleDraft, height: 32)
            }

            TextEditor(text: $docBodyDraft)
                .font(PipiTokens.fontMono)
                .scrollContentBackground(.hidden)
                .pipiHideScrollbars()
                .padding(PipiTokens.spacing8)
                .frame(minHeight: 240)
                .background(PipiTokens.composerSurface)
                .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous).strokeBorder(PipiTokens.composerBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

            HStack {
                PipiActionButton(s.cancel, tone: .secondary, density: .desktopCompact) {
                    showDocEditor = false
                }
                Spacer()
                PipiActionButton(s.save, systemImage: "checkmark", tone: .primary, density: .desktopCompact) {
                    let cleanTitle = docTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanTitle.isEmpty else { return }
                    _ = store.upsertArtifactDocument(
                        id: editingDocId,
                        title: cleanTitle,
                        kind: docKindDraft,
                        markdown: docBodyDraft
                    )
                    showDocEditor = false
                }
            }
        }
        .padding(PipiTokens.spacing24)
        .background(PipiTokens.bgCanvas)
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
    }

    private func skillPreviewSheet(_ skill: PipiBuiltinSkillPack) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(skill.title(lang)) (v\(skill.version))")
                        .font(PipiTokens.fontTitle)
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text("sha256: \(skill.sha256)")
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                }
                Spacer()
                PipiGhostIconButton(systemImage: "xmark", size: 28, iconSize: 12, accessibilityLabel: s.close) {
                    previewSkillPack = nil
                }
            }
            ScrollView(showsIndicators: false) {
                Text(skill.markdownBody)
                    .font(PipiTokens.fontMono)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .pipiHideScrollbars()
            .padding(PipiTokens.spacing12)
            .background(PipiTokens.bgInset)
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
        }
        .padding(PipiTokens.spacing24)
        .background(PipiTokens.bgCanvas)
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
    }

    // MARK: - Wiki Page Editor Sheet

    private var wikiEditorSheet: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack {
                Text(editingWikiPageId == nil ? s.wikiNewPage : s.t("编辑词条", "Edit Entry"))
                    .font(PipiTokens.fontTitle)
                    .foregroundStyle(PipiTokens.textPrimary)
                Spacer()
                PipiGhostIconButton(systemImage: "xmark", size: 28, iconSize: 12, accessibilityLabel: s.close) {
                    showWikiEditor = false
                }
            }

            HStack(spacing: PipiTokens.spacing12) {
                PipiSelectMenu(
                    options: PipiWikiEntityCategory.allCases,
                    selection: $formCategory,
                    width: 136
                ) { cat in
                    cat.label(lang)
                }

                PipiTextField(s.t("词条标题", "Title"), text: $formTitle, height: 32)

                PipiTextField("YYYY-MM-DD", text: $formEventDate, monospaced: true, height: 32)
                    .frame(width: 124)
            }

            PipiTextField(s.t("别名（逗号分隔，可选）", "Aliases (comma-separated, optional)"), text: $formAliases, height: 32)

            PipiTextField(s.t("核心摘要", "Summary"), text: $formSummary, height: 32)

            TextEditor(text: $formBody)
                .font(PipiTokens.fontMono)
                .scrollContentBackground(.hidden)
                .pipiHideScrollbars()
                .padding(PipiTokens.spacing8)
                .frame(minHeight: 200)
                .background(PipiTokens.composerSurface)
                .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous).strokeBorder(PipiTokens.composerBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))

            HStack {
                PipiActionButton(s.cancel, tone: .secondary, density: .desktopCompact) {
                    showWikiEditor = false
                }
                Spacer()
                PipiActionButton(s.save, systemImage: "checkmark", tone: .primary, density: .desktopCompact) {
                    let cleanTitle = formTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanTitle.isEmpty else { return }
                    let aliases = formAliases
                        .components(separatedBy: CharacterSet(charactersIn: ",，"))
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    let eventDate = formEventDate.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = store.upsertWikiPage(PipiWikiPageInput(
                        id: editingWikiPageId,
                        category: formCategory,
                        title: cleanTitle,
                        aliases: aliases,
                        summary: formSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cleanTitle : formSummary,
                        bodyMarkdown: formBody,
                        eventDate: eventDate.isEmpty ? nil : eventDate
                    ))
                    showWikiEditor = false
                }
            }
        }
        .padding(PipiTokens.spacing24)
        .background(PipiTokens.bgCanvas)
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(PipiTokens.fontCaption.weight(.semibold))
            .foregroundStyle(PipiTokens.textSecondary)
            .textCase(.uppercase)
    }

    private func openNewWikiPageSheet() {
        editingWikiPageId = nil
        formCategory = selectedWikiCategory ?? .projects
        formTitle = ""
        formAliases = ""
        formSummary = ""
        formEventDate = PipiProactiveEngine.formatLocalYmd(Date())
        formBody = "## Notes\n"
        showWikiEditor = true
    }

    private func openEditWikiPageSheet(_ page: PipiPersonalWikiPage) {
        editingWikiPageId = page.id
        formCategory = page.category
        formTitle = page.title
        formAliases = page.aliases.joined(separator: ", ")
        formSummary = page.summary
        formEventDate = page.eventDate ?? ""
        formBody = page.bodyMarkdown
        showWikiEditor = true
    }
}
