import SwiftUI
import UniformTypeIdentifiers
import PipiBotKit

#if os(macOS)
import AppKit
#endif

public struct PipiWorkspaceView: View {
    @Bindable public var store: PipiAppStore
    public var onToggleQuickBar: () -> Void
    public var onOpenSettings: (PipiSettingsTab) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.pipiTextScale) private var textScale

    private enum WorkspaceDestination: Equatable {
        case home
        case deviceNodes
        case missionBoard
        case needsYou
        case knowledge
        case session(String)
        case group(String)
    }

    private enum SidebarTaskFilter: Equatable {
        case all
        case groupsOnly
        case singleOnly
    }

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var destination: WorkspaceDestination = .home
    @State private var sidebarFilter: SidebarTaskFilter = .all
    @State private var selectedGroupInspectorTab: PipiGroupInspectorTab = .membersTasks
    @State private var pendingGroupMentionInsert: String? = nil
    @State private var showHostPopover: Bool = false
    @State private var lastKnownConversationCount: Int = 0
    @State private var lastKnownGroupCount: Int = 0

    @State private var draftMessage: String = ""
    @State private var draftAttachments: [PipiChatAttachment] = []
    @State private var selectedExecutionNodeHostId: String? = nil
    @State private var selectedExecutionNodeHarness: String? = nil
    @State private var selectedExecutionNodeModel: String = ""
    @State private var selectedExecutionNodeMode: String = "acp"
    @State private var showRemoteNodePickerPopover: Bool = false
    @State private var remoteNodeHarnessesCache: [String: [PipiAppStore.PipiRemoteHarnessDescriptor]] = [:]
    @State private var isLoadingRemoteHarnesses: Bool = false
    @State private var isDropTargeted: Bool = false
    @State private var showSlashPalette: Bool = false
    @State private var showArchived: Bool = false
    @State private var hoveredProjectId: String?
    @State private var hoveredConversationId: String?
    @State private var hoveredGroupId: String?
    @State private var hoveredStarterPrompt: String?
    @State private var hoveredMessageId: String?
    @State private var hoveredToolbarChip: String?
    @State private var copiedMessageId: String?
    @State private var showNewPersonaSheet = false
    @State private var editingPersona: PipiBotPersona?
    @State private var inspectingRoutinePersona: PipiBotPersona?
    @State private var showGroupCreatorSheet = false
    @State private var editingGroupChat: PipiGroupChat?
    @State private var groupCreatorPreselectedBotIds: Set<String> = []
    @State private var showNewProjectSheet = false
    @State private var editingProject: PipiProject?
    @State private var renamingConversation: PipiConversation?
    @State private var renameDraftTitle: String = ""
    @State private var renamingGroupChat: PipiGroupChat?
    @State private var renameGroupDraftTitle: String = ""
    @State private var pendingDeletePersona: PipiBotPersona?
    @State private var showHelpSheet: Bool = false
    @State private var helpTopic: PipiHelpTopic = .gettingStarted
    @State private var homeResetCameraTrigger: Int = 0
    #if os(macOS)
    @State private var undoKeyMonitor: Any?
    #endif
    @FocusState private var isComposerFocused: Bool
    @State private var isNativeComposerFocused: Bool = false
    @State private var composerFocusToken: Int = 0

    public init(
        store: PipiAppStore,
        onToggleQuickBar: @escaping () -> Void = {},
        onOpenSettings: @escaping (PipiSettingsTab) -> Void = { _ in }
    ) {
        self.store = store
        self.onToggleQuickBar = onToggleQuickBar
        self.onOpenSettings = onOpenSettings
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }
    private var activeAccent: Color { PipiTokens.color(for: store.activePersona.accent) }
    private var activeMotif: PipiPersonaMotif { PipiPersonaMotif.resolve(for: store.activePersona) }
    private var isConversationEmpty: Bool {
        store.activeConversation?.messages.isEmpty ?? true
    }

    private struct SlashCommandItem: Identifiable {
        let id: String
        let command: String
        let title: String
        let subtitle: String
        let icon: String
    }

    private var slashCommandCatalog: [SlashCommandItem] {
        [
            SlashCommandItem(
                id: "summarize",
                command: "/summarize",
                title: s.t("提炼要点 / 审阅文档", "Summarize / Review Doc"),
                subtitle: s.t("提炼附件文档（WPS/Word/PDF/表格）核心结论与修改建议", "Distill attached documents or long text into crisp takeaways"),
                icon: "text.alignleft"
            ),
            SlashCommandItem(
                id: "plan",
                command: "/plan",
                title: s.t("先规划再执行", "Plan First"),
                subtitle: s.t("让助手先拆解方案与关键步骤再动手", "Ask the assistant to outline steps before executing"),
                icon: "list.bullet.clipboard"
            ),
            SlashCommandItem(
                id: "screenshot",
                command: "/screenshot",
                title: s.t("截取本机屏幕", "Capture Screenshot"),
                subtitle: s.t("截屏并将图片直接发到对话里", "Capture screen PNG and deliver in chat"),
                icon: "camera.viewfinder"
            ),
            SlashCommandItem(
                id: "sms",
                command: "/sms",
                title: s.t("查看本机短信", "Read Recent SMS"),
                subtitle: s.t("读取最近短信与验证码摘要", "Read recent local Messages/SMS summary"),
                icon: "message"
            ),
            SlashCommandItem(
                id: "mail",
                command: "/mail",
                title: s.t("查看 Apple 邮件", "Read Apple Mail"),
                subtitle: s.t("查看收件箱最近邮件主题与发件人", "Inspect recent Apple Mail inbox"),
                icon: "envelope"
            ),
            SlashCommandItem(
                id: "voice",
                command: "/voice",
                title: s.museHandsFreeAction,
                subtitle: s.t("打开语音口述与免提对话", "Open dictation and hands-free voice chat"),
                icon: "waveform"
            ),
            SlashCommandItem(
                id: "sendfile",
                command: "/sendfile",
                title: s.t("发送本机文件", "Send Local File"),
                subtitle: s.t("将指定文件直接发送给你", "Deliver a local file in chat"),
                icon: "doc.badge.arrow.up"
            ),
            SlashCommandItem(
                id: "wiki",
                command: "/wiki",
                title: s.knowledgeHubTitle,
                subtitle: s.t("打开个人词条、日程简报与助手记忆", "Open entries, schedule briefs, and memory"),
                icon: "books.vertical"
            ),
            SlashCommandItem(
                id: "new",
                command: "/new",
                title: s.newChat,
                subtitle: s.t("开启一段全新空白对话", "Start a fresh conversation"),
                icon: "square.and.pencil"
            ),
            SlashCommandItem(
                id: "clear",
                command: "/clear",
                title: s.clearConversation,
                subtitle: s.t("清空当前会话消息记录", "Clear messages in current thread"),
                icon: "trash"
            ),
            SlashCommandItem(
                id: "settings",
                command: "/settings",
                title: s.settings,
                subtitle: s.t("打开模型、远程与界面设置", "Open model, remote, and app settings"),
                icon: "gearshape"
            )
        ]
    }

    private var filteredSlashCommands: [SlashCommandItem] {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("/") {
            let query = String(trimmed.dropFirst()).lowercased()
            if query.isEmpty { return slashCommandCatalog }
            return slashCommandCatalog.filter {
                $0.command.lowercased().contains(query) ||
                $0.title.lowercased().contains(query) ||
                $0.id.lowercased().contains(query)
            }
        }
        return slashCommandCatalog
    }

    private var shouldShowSlashMenu: Bool {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespaces)
        let typedSlash = trimmed.hasPrefix("/") && !trimmed.contains(" ") && !trimmed.contains("\n")
        return (showSlashPalette || typedSlash) && !filteredSlashCommands.isEmpty
    }

    public var body: some View {
        let _ = textScale

        ZStack {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
                    .navigationSplitViewColumnWidth(min: 248, ideal: 272, max: 340)
                    .toolbar(removing: .sidebarToggle)
            } detail: {
                detailStage
                    .toolbar {
                        toolbarContent
                    }
                    .toolbar(removing: .sidebarToggle)
                    .inspector(isPresented: $store.isInspectorPresented) {
                        Group {
                            switch destination {
                            case .home, .deviceNodes:
                                PipiHomeInspectorView(
                                    store: store,
                                    onSelectBotChat: { persona in
                                        let existing = store.conversations
                                            .filter { $0.personaId == persona.id && !$0.isArchived }
                                            .sorted { $0.updatedAt > $1.updatedAt }
                                            .first
                                        let target = existing ?? store.createConversation(for: persona.id, activate: true)
                                        store.selectConversation(target.id)
                                        destination = .session(target.id)
                                    },
                                    onEditBot: { bot in
                                        editingPersona = bot
                                    },
                                    onCreateBot: {
                                        showNewPersonaSheet = true
                                    },
                                    onCreateGroup: {
                                        groupCreatorPreselectedBotIds = []
                                        editingGroupChat = nil
                                        showGroupCreatorSheet = true
                                    },
                                    onReset3DCamera: {
                                        homeResetCameraTrigger &+= 1
                                    },
                                    onOpenHelp: { topic in
                                        helpTopic = topic
                                        showHelpSheet = true
                                    }
                                )

                            case .session(let sessionId):
                                PipiSessionInspectorView(
                                    store: store,
                                    sessionId: sessionId,
                                    onEditBot: { bot in
                                        editingPersona = bot
                                    },
                                    onOpenBotRoutines: { bot in
                                        inspectingRoutinePersona = bot
                                    },
                                    onClose: {
                                        withAnimation(PipiMotion.adaptive(PipiMotion.drawer, reduceMotion: reduceMotion)) {
                                            store.isInspectorPresented = false
                                        }
                                    },
                                    onOpenHelp: { topic in
                                        helpTopic = topic
                                        showHelpSheet = true
                                    }
                                )

                            case .group(let groupId):
                                PipiGroupInspectorView(
                                    store: store,
                                    groupId: groupId,
                                    selectedTab: $selectedGroupInspectorTab,
                                    onMentionBot: { token in
                                        pendingGroupMentionInsert = token
                                    },
                                    onManageMembers: { grp in
                                        editingGroupChat = grp
                                        groupCreatorPreselectedBotIds = []
                                        showGroupCreatorSheet = true
                                    }
                                )

                            case .knowledge:
                                PipiKnowledgeInspectorView(
                                    store: store,
                                    onOpenSettings: onOpenSettings,
                                    onOpenHelp: { topic in
                                        helpTopic = topic
                                        showHelpSheet = true
                                    }
                                )

                            case .needsYou, .missionBoard:
                                PipiNeedsYouInspectorView(
                                    store: store,
                                    onOpenSettings: onOpenSettings,
                                    onOpenHelp: { topic in
                                        helpTopic = topic
                                        showHelpSheet = true
                                    }
                                )
                            }
                        }
                        .inspectorColumnWidth(min: 300, ideal: 344, max: 420)
                    }
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar(removing: .sidebarToggle)

            if store.isCommandPalettePresented {
                PipiCommandPaletteView(
                    store: store,
                    onSelectConversation: { convId in
                        store.selectConversation(convId)
                        destination = .session(convId)
                    },
                    onSelectGroupChat: { groupId in
                        store.selectGroupChat(groupId)
                        destination = .group(groupId)
                    },
                    onSelectBot: { personaId in
                        sidebarFilter = .all
                        store.selectedBotFilterId = personaId
                        store.activePersonaId = personaId
                        if let latest = store.conversations
                            .filter({ $0.personaId == personaId && !$0.isArchived })
                            .sorted(by: { $0.updatedAt > $1.updatedAt })
                            .first {
                            store.selectConversation(latest.id)
                            destination = .session(latest.id)
                        } else {
                            destination = .home
                        }
                    },
                    onOpenHome: {
                        destination = .home
                    },
                    onNewGroupChat: {
                        groupCreatorPreselectedBotIds = []
                        editingGroupChat = nil
                        showGroupCreatorSheet = true
                    },
                    onOpenNeedsYouInbox: {
                        destination = .needsYou
                    },
                    onToggleQuickBar: onToggleQuickBar,
                    onOpenSettings: onOpenSettings,
                    onDismiss: {
                        withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                            store.isCommandPalettePresented = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(50)
            }
        }
        .background(PipiTokens.bgCanvas)
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
        .sheet(isPresented: $showNewPersonaSheet) {
            PipiBotCreatorSheet(
                store: store,
                existing: nil,
                onDismiss: { showNewPersonaSheet = false }
            )
            .environment(\.pipiTextScale, store.uiZoomScale)
        }
        .sheet(item: $editingPersona) { persona in
            PipiBotCreatorSheet(
                store: store,
                existing: persona,
                onDismiss: { editingPersona = nil }
            )
            .environment(\.pipiTextScale, store.uiZoomScale)
        }
        .sheet(item: $inspectingRoutinePersona) { persona in
            PipiBotDetailSheet(
                store: store,
                persona: persona,
                onEditBot: {
                    let target = persona
                    inspectingRoutinePersona = nil
                    editingPersona = target
                },
                onOpenConversation: { convId in
                    inspectingRoutinePersona = nil
                    store.selectConversation(convId)
                    destination = .session(convId)
                },
                onClose: {
                    inspectingRoutinePersona = nil
                }
            )
            .environment(\.pipiTextScale, store.uiZoomScale)
            .frame(minWidth: 540, minHeight: 520)
        }
        .sheet(isPresented: $showGroupCreatorSheet) {
            PipiGroupCreatorSheet(
                store: store,
                editingGroup: editingGroupChat,
                preselectedBotIds: groupCreatorPreselectedBotIds
            )
            .environment(\.pipiTextScale, store.uiZoomScale)
        }
        .sheet(isPresented: $showNewProjectSheet) {
            PipiProjectEditorSheet(store: store, existing: nil) {
                showNewProjectSheet = false
            }
            .environment(\.pipiTextScale, store.uiZoomScale)
            .frame(minWidth: 480, minHeight: 440)
        }
        .sheet(item: $editingProject) { project in
            PipiProjectEditorSheet(store: store, existing: project) {
                editingProject = nil
            }
            .environment(\.pipiTextScale, store.uiZoomScale)
            .frame(minWidth: 480, minHeight: 440)
        }
        .onAppear {
            syncVisibleDestinationState(destination)
        }
        .onChange(of: destination) { _, next in
            syncVisibleDestinationState(next)
        }
        .sheet(isPresented: $showHelpSheet) {
            PipiHelpSheetView(
                store: store,
                initialTopic: helpTopic,
                onClose: { showHelpSheet = false }
            )
            .environment(\.pipiTextScale, store.uiZoomScale)
            .frame(minWidth: 760, minHeight: 540)
        }
        .alert(s.renameChat, isPresented: Binding(
            get: { renamingConversation != nil },
            set: { if !$0 { renamingConversation = nil } }
        )) {
            TextField(s.renameChat, text: $renameDraftTitle)
            Button(s.cancel, role: .cancel) { renamingConversation = nil }
            Button(s.save) {
                if let conv = renamingConversation {
                    store.renameConversation(conv.id, title: renameDraftTitle)
                }
                renamingConversation = nil
            }
        }
        .alert(s.renameGroupChat, isPresented: Binding(
            get: { renamingGroupChat != nil },
            set: { if !$0 { renamingGroupChat = nil } }
        )) {
            TextField(s.renameGroupChat, text: $renameGroupDraftTitle)
            Button(s.cancel, role: .cancel) { renamingGroupChat = nil }
            Button(s.save) {
                if let grp = renamingGroupChat {
                    store.renameGroupChat(id: grp.id, title: renameGroupDraftTitle)
                }
                renamingGroupChat = nil
            }
        }
        .onAppear {
            lastKnownConversationCount = store.conversations.count
            lastKnownGroupCount = store.groupChats.count
        }
        .onChange(of: store.activeConversationId) { oldId, newId in
            let prevCount = lastKnownConversationCount
            lastKnownConversationCount = store.conversations.count
            if case .session(let currentSid) = destination,
               !store.conversations.contains(where: { $0.id == currentSid }) {
                destination = newId.map { .session($0) } ?? .home
                return
            }
            if let newId, newId != oldId,
               store.conversations.contains(where: { $0.id == newId }),
               store.conversations.count >= prevCount {
                destination = .session(newId)
            }
        }
        .onChange(of: store.conversations.count) { _, newCount in
            if case .session(let currentSid) = destination,
               !store.conversations.contains(where: { $0.id == currentSid }) {
                destination = store.activeConversationId.map { .session($0) } ?? .home
            }
            lastKnownConversationCount = newCount
        }
        .onChange(of: store.activeGroupChatId) { oldId, newId in
            let prevCount = lastKnownGroupCount
            lastKnownGroupCount = store.groupChats.count
            if case .group(let currentGid) = destination,
               !store.groupChats.contains(where: { $0.id == currentGid }) {
                destination = .home
                return
            }
            if let newId, newId != oldId,
               store.groupChats.contains(where: { $0.id == newId }),
               store.groupChats.count >= prevCount {
                destination = .group(newId)
            }
        }
        .onChange(of: store.groupChats.count) { _, newCount in
            if case .group(let currentGid) = destination,
               !store.groupChats.contains(where: { $0.id == currentGid }) {
                destination = .home
            }
            lastKnownGroupCount = newCount
        }
        .confirmationDialog(
            pendingDeletePersona.map { s.deleteBotConfirmTitle($0.name(lang)) } ?? "",
            isPresented: Binding(
                get: { pendingDeletePersona != nil },
                set: { if !$0 { pendingDeletePersona = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletePersona
        ) { persona in
            Button(s.delete, role: .destructive) {
                store.deletePersona(persona.id)
                if store.selectedBotFilterId == persona.id {
                    store.selectedBotFilterId = nil
                }
                pendingDeletePersona = nil
            }
            Button(s.cancel, role: .cancel) {
                pendingDeletePersona = nil
            }
        } message: { persona in
            Text(s.deleteBotConfirmMessage(store.conversationCount(forPersona: persona.id)))
        }
        #if os(macOS)
        .onAppear {
            if undoKeyMonitor == nil {
                undoKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    guard mods == .command,
                          event.charactersIgnoringModifiers?.lowercased() == "z",
                          store.canUndoLastDeletion else {
                        return event
                    }
                    if let tv = NSApp.keyWindow?.firstResponder as? NSTextView,
                       tv.undoManager?.canUndo == true {
                        return event
                    }
                    _ = store.undoLastDeletion()
                    return nil
                }
            }
        }
        .onDisappear {
            if let monitor = undoKeyMonitor {
                NSEvent.removeMonitor(monitor)
                undoKeyMonitor = nil
            }
        }
        #endif
    }

    // MARK: - Native Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: PipiTokens.spacing8) {
                if columnVisibility == .detailOnly {
                    PipiGhostIconButton(
                        systemImage: "sidebar.left",
                        size: 28,
                        iconSize: 13.5,
                        cornerRadius: PipiTokens.radiusSM,
                        accessibilityLabel: s.toggleSidebar
                    ) {
                        withAnimation(PipiMotion.adaptive(PipiMotion.drawer, reduceMotion: reduceMotion)) {
                            columnVisibility = .all
                        }
                    }
                    .help("\(s.toggleSidebar) (⌃⌘S)")
                }

                switch destination {
                case .home:
                    HStack(spacing: PipiTokens.spacing8) {
                        Image(systemName: "cpu")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.botHome)
                            .font(PipiTokens.fontHeadline)
                            .foregroundStyle(PipiTokens.textPrimary)
                    }

                case .deviceNodes:
                    HStack(spacing: PipiTokens.spacing8) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.t("我的设备节点", "My Device Nodes"))
                            .font(PipiTokens.fontHeadline)
                            .foregroundStyle(PipiTokens.textPrimary)
                    }

                case .missionBoard:
                    HStack(spacing: PipiTokens.spacing8) {
                        Image(systemName: "rectangle.3.group")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(PipiTokens.soulPrimary)
                        Text(s.t("任务台", "Mission Board"))
                            .font(PipiTokens.fontHeadline)
                            .foregroundStyle(PipiTokens.textPrimary)
                    }

                case .needsYou:
                    HStack(spacing: PipiTokens.spacing8) {
                        Image(systemName: "bell")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(store.totalNeedsYouCount > 0 ? PipiTokens.stateWarning : PipiTokens.textPrimary)
                        Text(s.needsYouInboxTitle)
                            .font(PipiTokens.fontHeadline)
                            .foregroundStyle(PipiTokens.textPrimary)
                    }

                case .knowledge:
                    HStack(spacing: PipiTokens.spacing8) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(s.knowledgeHubTitle)
                            .font(PipiTokens.fontHeadline)
                            .foregroundStyle(PipiTokens.textPrimary)
                    }

                case .group(let groupId):
                    if let grp = store.groupChats.first(where: { $0.id == groupId }) {
                        let members = grp.participantPersonaIds.compactMap { pid in
                            store.personas.first(where: { $0.id == pid })
                        }
                        HStack(spacing: PipiTokens.spacing12) {
                            Button {
                                selectedGroupInspectorTab = .membersTasks
                                withAnimation(PipiMotion.adaptive(PipiMotion.drawer, reduceMotion: reduceMotion)) {
                                    store.isInspectorPresented = true
                                }
                            } label: {
                                HStack(spacing: -6) {
                                    ForEach(members.prefix(4)) { bot in
                                        let isBusy = store.isBotWorkingInGroup(bot.id, groupId: grp.id)
                                        ZStack(alignment: .bottomTrailing) {
                                            PipiBotPersonaGlyph(persona: bot, size: 24, isSelected: true)
                                                .overlay(
                                                    Circle()
                                                        .strokeBorder(PipiTokens.bgCanvas, lineWidth: 1.5)
                                                )
                                            if isBusy {
                                                PipiDotIndicator(
                                                    vitality: .busy,
                                                    color: PipiTokens.color(for: bot.accent),
                                                    size: 5.5
                                                )
                                                .background(Circle().fill(PipiTokens.bgCanvas).padding(-1))
                                            }
                                        }
                                    }
                                    if members.count > 4 {
                                        Text("+\(members.count - 4)")
                                            .font(PipiTokens.fontMicro)
                                            .foregroundStyle(PipiTokens.textSecondary)
                                            .padding(.horizontal, 5)
                                            .frame(height: 20)
                                            .background(PipiTokens.bgSurface, in: Capsule())
                                            .overlay(Capsule().strokeBorder(PipiTokens.borderSubtle, lineWidth: 1))
                                            .padding(.leading, 8)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                            .help(s.t("查看群成员与长期任务", "View Group Members & Tasks"))

                            Text(grp.title)
                                .font(PipiTokens.fontHeadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(-1)

                            groupSwarmModeMenu(for: grp)

                            if store.isGroupRunning(grp.id) {
                                let workingCount = store.activeGroupRuns[grp.id]?.count ?? 0
                                HStack(spacing: 4) {
                                    PipiDotIndicator(vitality: .busy, color: PipiTokens.soulPrimary, size: 5.5)
                                    Text(s.t("\(workingCount) 协作中", "\(workingCount) running"))
                                        .font(PipiTokens.fontMicro)
                                        .foregroundStyle(PipiTokens.textPrimary)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(PipiTokens.bgSurfaceHover, in: Capsule())
                                .fixedSize()
                            }
                        }
                    } else {
                        HStack(spacing: PipiTokens.spacing8) {
                            Image(systemName: "person.2")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text(s.groupChatsSection)
                                .font(PipiTokens.fontHeadline)
                                .foregroundStyle(PipiTokens.textPrimary)
                        }
                    }

                case .session:
                    HStack(spacing: PipiTokens.spacing8) {
                        sessionBotSwitcherMenu

                        Text("·")
                            .font(PipiTokens.fontSubheadline)
                            .foregroundStyle(PipiTokens.textMuted)

                        Text(store.activeConversation?.title ?? store.activePersona.name(lang))
                            .font(PipiTokens.fontHeadline)
                            .tracking(PipiTokens.trackingHeadline)
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(-1)

                        if store.isGeneratingReply, let startedAt = store.activeRunStartedAt {
                            HStack(spacing: 5) {
                                PipiDotIndicator(vitality: .busy, color: activeAccent, size: 5)
                                Text(store.generatingStatusText ?? s.thinkingStatus)
                                PipiElapsedTimerLabel(startedAt: startedAt, color: activeAccent)
                            }
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textPrimary)
                            .padding(.horizontal, PipiTokens.spacing8)
                            .padding(.vertical, 3)
                            .background(PipiTokens.bgSurfaceHover)
                            .clipShape(Capsule())
                            .fixedSize()
                        }
                    }
                }
            }
            .padding(.leading, 14)
        }

        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if case .session = destination {
                sessionWorkspaceFolderButton
            }

            if case .group(let groupId) = destination,
               let grp = store.groupChats.first(where: { $0.id == groupId }) {
                Button {
                    selectedGroupInspectorTab = .membersTasks
                    editingGroupChat = grp
                    groupCreatorPreselectedBotIds = []
                    showGroupCreatorSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(s.t("成员 (\(grp.participantPersonaIds.count))", "Members (\(grp.participantPersonaIds.count))"))
                            .font(PipiTokens.fontCaption.weight(.medium))
                            .monospacedDigit()
                    }
                    .foregroundStyle(PipiTokens.textSecondary)
                }
                .help(s.editGroupChat)
            }

            if case .group(let groupId) = destination, store.isGroupRunning(groupId) {
                Button {
                    store.stopGroupChat(groupId)
                } label: {
                    Label(s.stop, systemImage: "stop.fill")
                        .foregroundStyle(PipiTokens.stateError)
                }
                .help(s.stop)
                .accessibilityLabel(s.stop)
            } else if case .session = destination, store.isGeneratingReply {
                Button {
                    store.stopGenerating()
                } label: {
                    Label(s.stop, systemImage: "stop.fill")
                        .foregroundStyle(PipiTokens.stateError)
                }
                .help(s.stop)
                .accessibilityLabel(s.stop)
            }

            PipiTelemetryToolbarButton(store: store) {
                onOpenSettings(.aiEngine)
            }

            Button {
                switch destination {
                case .home: helpTopic = .gettingStarted
                case .session, .group: helpTopic = .shortcuts
                case .knowledge: helpTopic = .knowledgeMemory
                case .needsYou, .missionBoard, .deviceNodes: helpTopic = .desktopSafety
                }
                showHelpSheet = true
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .help(s.t("帮助中心", "Help Center"))
            .accessibilityLabel(s.t("帮助中心", "Help Center"))

            let artifactCount = (store.activeConversation?.planItems.count ?? 0) + (store.activeConversation?.fileChanges.count ?? 0)
            let contextualInspectorHelp: String = {
                switch destination {
                case .home: return s.t("显示或隐藏空间概览", "Toggle Space Overview")
                case .session: return s.t("显示或隐藏会话详情", "Toggle Session Details")
                case .group: return s.t("显示或隐藏协作群详情", "Toggle Group Inspector")
                case .knowledge: return s.t("显示或隐藏知识库概览", "Toggle Knowledge Overview")
                case .needsYou, .missionBoard, .deviceNodes: return s.t("显示或隐藏安全策略栏", "Toggle Policy Sidebar")
                }
            }()
            Button {
                withAnimation(PipiMotion.adaptive(PipiMotion.drawer, reduceMotion: reduceMotion)) {
                    store.isInspectorPresented.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sidebar.right")
                    if case .session = destination, artifactCount > 0 {
                        Text("\(artifactCount)")
                            .font(PipiTokens.fontMonoSmall.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(PipiTokens.textSecondary)
                    } else if case .group(let gid) = destination,
                              let grp = store.groupChats.first(where: { $0.id == gid }) {
                        let badgeCount = grp.deliverables.count + grp.longTasks.filter { $0.status == .active }.count
                        if badgeCount > 0 {
                            Text("\(badgeCount)")
                                .font(PipiTokens.fontMonoSmall.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(PipiTokens.textSecondary)
                        }
                    }
                }
            }
            .help(contextualInspectorHelp)
            .accessibilityLabel(artifactCount > 0 ? "\(contextualInspectorHelp) (\(artifactCount))" : contextualInspectorHelp)
        }
    }

    private func groupSwarmModeMenu(for group: PipiGroupChat) -> some View {
        let isHovered = hoveredToolbarChip == "group_swarm_mode"
        return Menu {
            ForEach(PipiSwarmMode.allCases) { mode in
                Button {
                    store.updateGroupChat(id: group.id, swarmMode: mode)
                } label: {
                    Label {
                        Text(mode.label(lang))
                    } icon: {
                        Image(systemName: group.swarmMode == mode ? "checkmark" : mode.iconName)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: group.swarmMode.iconName)
                    .font(.system(size: 11, weight: .semibold))
                Text(group.swarmMode.label(lang))
                    .font(PipiTokens.fontCaption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(PipiTokens.textMuted)
            }
            .foregroundStyle(isHovered ? PipiTokens.textPrimary : PipiTokens.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .fill(isHovered ? PipiTokens.bgSurfaceHover : PipiTokens.bgSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )
        }
        .pipiPlainMenu()
        .fixedSize()
        .onHover { hoveredToolbarChip = $0 ? "group_swarm_mode" : (hoveredToolbarChip == "group_swarm_mode" ? nil : hoveredToolbarChip) }
        .help(s.t("切换协作模式", "Switch collaboration mode"))
    }

    private var sessionBotSwitcherMenu: some View {
        let isBotHovered = hoveredToolbarChip == "header_bot"
        return Menu {
            ForEach(store.personas) { persona in
                Button {
                    if isConversationEmpty {
                        store.assignActiveConversationPersona(persona.id)
                    } else {
                        let created = store.createConversation(
                            for: persona.id,
                            projectId: store.activeConversation?.projectId
                        )
                        destination = .session(created.id)
                        isComposerFocused = true
                    }
                } label: {
                    HStack {
                        Text(persona.name(lang))
                        if persona.id == store.activePersona.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                PipiBotPersonaGlyph(persona: store.activePersona, size: 22, isSelected: true)
                Text(store.activePersona.name(lang))
                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(PipiTokens.textMuted)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .fill(isBotHovered ? PipiTokens.buttonGhostHoverBg : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .pipiPlainMenu()
        .fixedSize()
        .onHover { hoveredToolbarChip = $0 ? "header_bot" : (hoveredToolbarChip == "header_bot" ? nil : hoveredToolbarChip) }
        .help(s.myBots)
    }

    private var sessionWorkspaceFolderButton: some View {
        let rawPath = store.effectiveWorkspaceDirectory
        let folderName = URL(fileURLWithPath: rawPath).lastPathComponent
        let displayPath = folderName.isEmpty ? rawPath : folderName
        let isFolderHovered = hoveredToolbarChip == "header_folder"

        return Button {
            chooseWorkspaceFolderInPlace()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(store.activeProject.map { PipiTokens.color(for: $0.accent) } ?? PipiTokens.textSecondary)
                Text(displayPath)
                    .font(PipiTokens.fontCaption.weight(.medium))
                    .foregroundStyle(isFolderHovered ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hoveredToolbarChip = $0 ? "header_folder" : (hoveredToolbarChip == "header_folder" ? nil : hoveredToolbarChip) }
        .help(rawPath)
        .accessibilityLabel("\(s.chooseFolder): \(displayPath)")
    }

    // MARK: - Left Sidebar (Devin Split New Task + 2 Nav Links + Unified Tasks + Quiet Host/Settings Footer)

    private enum SidebarTaskEntry: Identifiable {
        case group(PipiGroupChat)
        case session(PipiConversation)

        var id: String {
            switch self {
            case .group(let group): return "grp:\(group.id)"
            case .session(let conv): return "conv:\(conv.id)"
            }
        }

        var sortTimestamp: String {
            switch self {
            case .group(let group): return group.updatedAt.isEmpty ? group.createdAt : group.updatedAt
            case .session(let conv): return conv.updatedAt.isEmpty ? conv.createdAt : conv.updatedAt
            }
        }
    }

    private func groupTimeBucket(for group: PipiGroupChat, now: Date = Date()) -> PipiSessionTimeBucket {
        if store.isGroupRunning(group.id) {
            return .activeOrNeedsYou
        }
        if group.isPinned {
            return .pinned
        }
        let date = store.parseSessionDate(group.updatedAt) ?? store.parseSessionDate(group.createdAt) ?? Date.distantPast
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return .today
        }
        if cal.isDateInYesterday(date) {
            return .yesterday
        }
        if let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: now), date >= sevenDaysAgo {
            return .last7Days
        }
        return .earlier
    }

    private var groupedSidebarTasks: [(bucket: PipiSessionTimeBucket, entries: [SidebarTaskEntry])] {
        var bucketed: [PipiSessionTimeBucket: [SidebarTaskEntry]] = [:]

        if sidebarFilter != .singleOnly {
            for group in store.sortedGroupChats where !group.isArchived {
                if let botFilterId = store.selectedBotFilterId,
                   !group.participantPersonaIds.contains(botFilterId) {
                    continue
                }
                let bucket = groupTimeBucket(for: group)
                bucketed[bucket, default: []].append(.group(group))
            }
        }

        if sidebarFilter != .groupsOnly {
            let sessionGroups = store.groupedGlobalSessions(
                searchQuery: "",
                botFilterId: store.selectedBotFilterId
            )
            for item in sessionGroups {
                for conv in item.conversations {
                    bucketed[item.bucket, default: []].append(.session(conv))
                }
            }
        }

        return PipiSessionTimeBucket.allCases.compactMap { bucket in
            guard var entries = bucketed[bucket], !entries.isEmpty else { return nil }
            entries.sort { lhs, rhs in
                let d1 = store.parseSessionDate(lhs.sortTimestamp) ?? Date.distantPast
                let d2 = store.parseSessionDate(rhs.sortTimestamp) ?? Date.distantPast
                if d1 != d2 { return d1 > d2 }
                return lhs.id < rhs.id
            }
            return (bucket: bucket, entries: entries)
        }
    }

    private static let sidebarMinWidth: CGFloat = 248

    private var sidebar: some View {
        GeometryReader { proxy in
            let currentWidth = proxy.size.width
            let layoutWidth = max(currentWidth, Self.sidebarMinWidth)
            let collapseOpacity = currentWidth < 140 ? max(0, Double(currentWidth) / 140.0) : 1.0

            VStack(spacing: 0) {
                // 1. Sidebar Header Strip + Unified Flat Navigation Group
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: PipiTokens.spacing8) {
                        HStack(spacing: 7) {
                            PipiBotLogoMark(size: 18)
                            Text("PiPi")
                                .font(PipiTokens.fontHeadline.weight(.semibold))
                                .foregroundStyle(PipiTokens.textPrimary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }

                    Spacer(minLength: 4)

                    PipiGhostIconButton(
                        systemImage: "magnifyingglass",
                        size: 28,
                        iconSize: 12.5,
                        cornerRadius: PipiTokens.radiusSM,
                        accessibilityLabel: s.openCommandPalette
                    ) {
                        withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                            store.isCommandPalettePresented = true
                        }
                    }
                    .help("\(s.openCommandPalette) (⌘K)")

                    PipiGhostIconButton(
                        systemImage: "sidebar.left",
                        size: 28,
                        iconSize: 12.5,
                        cornerRadius: PipiTokens.radiusSM,
                        accessibilityLabel: s.toggleSidebar
                    ) {
                        withAnimation(PipiMotion.adaptive(PipiMotion.drawer, reduceMotion: reduceMotion)) {
                            columnVisibility = .detailOnly
                        }
                    }
                    .help("\(s.toggleSidebar) (⌃⌘S)")
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

                // 1. 新对话 (⌘N)
                sidebarNavRow(
                    icon: "square.and.pencil",
                    title: s.newChat,
                    isSelected: false,
                    trailingHint: "⌘N"
                ) {
                    let created = store.createConversation(projectId: store.activeConversation?.projectId)
                    destination = .session(created.id)
                    isComposerFocused = true
                }

                // 2. 新建群聊
                sidebarNavRow(
                    icon: "person.2",
                    title: s.newGroupChat,
                    isSelected: false
                ) {
                    groupCreatorPreselectedBotIds = []
                    editingGroupChat = nil
                    showGroupCreatorSheet = true
                }

                // 2.5 我的设备节点（主控 + 所有纳管节点硬件状态与 Harness 看板）
                sidebarNavRow(
                    icon: "server.rack",
                    title: s.t("我的设备节点", "My Device Nodes"),
                    isSelected: destination == .deviceNodes,
                    showPulseDot: false
                ) {
                    destination = .deviceNodes
                }

                // 3. 任务台 (Mission Board — 看板 / Worktree Diff / 事件与进化 / 用量)
                let missionBadge = store.worktreeSessions.filter { $0.status == .readyForReview }.count
                    + store.blueprintEvolutionProposals.filter { $0.status == .pending }.count
                sidebarNavRow(
                    icon: "rectangle.3.group",
                    title: s.t("任务台", "Mission Board"),
                    isSelected: destination == .missionBoard,
                    badgeCount: missionBadge,
                    showPulseDot: !store.activeGroupLanes.isEmpty
                ) {
                    destination = .missionBoard
                }

                // 4. 待我确认
                sidebarNavRow(
                    icon: "bell",
                    title: s.needsYouInboxTitle,
                    isSelected: destination == .needsYou,
                    badgeCount: store.totalNeedsYouCount
                ) {
                    destination = .needsYou
                }

                // 4. 智能体
                sidebarNavRow(
                    icon: "cpu",
                    title: s.botHome,
                    isSelected: destination == .home,
                    showPulseDot: !store.activeRuns.isEmpty || !store.collaboratingBotIds.isEmpty
                ) {
                    destination = .home
                }

                // 5. 知识与主动简报 (Wave 2)
                sidebarNavRow(
                    icon: "books.vertical",
                    title: s.knowledgeHubTitle,
                    isSelected: destination == .knowledge,
                    badgeCount: store.proactiveBriefings.filter { $0.feedback == nil }.count
                ) {
                    destination = .knowledge
                }
            }
            .padding(.horizontal, PipiTokens.spacing12)
            .padding(.top, 4)
            .padding(.bottom, PipiTokens.spacing12)

            Rectangle()
                .fill(PipiTokens.borderSubtle)
                .frame(height: 1)
                .padding(.horizontal, PipiTokens.spacing12)

            // Pinned Section Header for Conversations & Collaboration
            HStack(spacing: PipiTokens.spacing8) {
                Text(s.sessionsSection)
                    .font(PipiTokens.fontMicro.weight(.semibold))
                    .tracking(PipiTokens.trackingMicro)
                    .foregroundStyle(PipiTokens.textMuted)
                    .textCase(.uppercase)

                if let filterId = store.selectedBotFilterId,
                   let bot = store.personas.first(where: { $0.id == filterId }) {
                    Button {
                        store.selectedBotFilterId = nil
                    } label: {
                        HStack(spacing: 4) {
                            Text(bot.name(lang))
                                .lineLimit(1)
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PipiTokens.bgSurfaceHover)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(s.clearFilter)
                    .accessibilityLabel("\(s.clearFilter): \(bot.name(lang))")
                }

                Spacer()

                let filterTitle: String = {
                    if sidebarFilter == .groupsOnly { return s.groupChatsSection }
                    if sidebarFilter == .singleOnly { return s.singleChatFilter }
                    if let filterId = store.selectedBotFilterId,
                       let bot = store.personas.first(where: { $0.id == filterId }) {
                        return bot.name(lang)
                    }
                    return s.allBotsFilter
                }()

                Menu {
                    Button {
                        sidebarFilter = .all
                        store.selectedBotFilterId = nil
                    } label: {
                        HStack {
                            Text(s.allBotsFilter)
                            if sidebarFilter == .all && store.selectedBotFilterId == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Button {
                        sidebarFilter = .groupsOnly
                    } label: {
                        HStack {
                            Text(s.groupChatsSection)
                            if sidebarFilter == .groupsOnly {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Button {
                        sidebarFilter = .singleOnly
                    } label: {
                        HStack {
                            Text(s.singleChatFilter)
                            if sidebarFilter == .singleOnly {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    Section(s.myBots) {
                        ForEach(store.personas) { persona in
                            Button {
                                sidebarFilter = .all
                                store.selectedBotFilterId = persona.id
                            } label: {
                                HStack {
                                    Text(persona.name(lang))
                                    if sidebarFilter == .all && store.selectedBotFilterId == persona.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(filterTitle)
                            .font(PipiTokens.fontMicro.weight(.medium))
                            .foregroundStyle(
                                (sidebarFilter != .all || store.selectedBotFilterId != nil)
                                    ? PipiTokens.textPrimary
                                    : PipiTokens.textMuted
                            )
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        (sidebarFilter != .all || store.selectedBotFilterId != nil)
                            ? PipiTokens.bgSurfaceHover
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .pipiPlainMenu()
                .fixedSize()
                .help(s.filterByBotLabel)
            }
            .padding(.horizontal, PipiTokens.spacing12 + PipiTokens.spacing8)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // 2. Scrollable Unified 对话与协作 + 项目
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                    // Unified Tasks List (Single-bot Sessions + Group Chats)
                    VStack(alignment: .leading, spacing: 3) {
                        let taskGroups = groupedSidebarTasks
                        if taskGroups.isEmpty {
                            Text(s.noChatsYet)
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textMuted)
                                .padding(.horizontal, PipiTokens.spacing8)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(Array(taskGroups.enumerated()), id: \.element.bucket.id) { idx, group in
                                Text(group.bucket.title(s))
                                    .font(PipiTokens.fontMicro.weight(.medium))
                                    .foregroundStyle(PipiTokens.textMuted)
                                    .padding(.horizontal, PipiTokens.spacing8)
                                    .padding(.top, idx == 0 ? 2 : 12)
                                    .padding(.bottom, 3)

                                ForEach(group.entries) { entry in
                                    switch entry {
                                    case .group(let chatGroup):
                                        groupChatSidebarRow(chatGroup)
                                    case .session(let conv):
                                        conversationSidebarRow(conv, isArchived: false, indented: false)
                                    }
                                }
                            }
                        }

                        // Archived Conversations Section
                        if sidebarFilter != .groupsOnly {
                            let archivedConvs = store.allArchivedConversations.filter { conv in
                                if let filterId = store.selectedBotFilterId, conv.personaId != filterId { return false }
                                return true
                            }
                            if !archivedConvs.isEmpty {
                                Button {
                                    withAnimation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion)) {
                                        showArchived.toggle()
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 9, weight: .bold))
                                        Image(systemName: "archivebox")
                                            .font(.system(size: 10, weight: .medium))
                                        Text("\(s.archivedSection) · \(archivedConvs.count)")
                                            .font(PipiTokens.fontMicro)
                                            .monospacedDigit()
                                        Spacer()
                                    }
                                    .foregroundStyle(PipiTokens.textMuted)
                                    .padding(.horizontal, PipiTokens.spacing8)
                                    .padding(.top, PipiTokens.spacing12)
                                    .padding(.bottom, 2)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.98))

                                if showArchived {
                                    ForEach(archivedConvs) { conv in
                                        conversationSidebarRow(conv, isArchived: true, indented: false)
                                    }
                                    .transition(.opacity)
                                }
                            }
                        }
                    }

                    // Projects Section (only shown once the user has created at least one project)
                    if !store.projects.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(s.projectsSection)
                                    .font(PipiTokens.fontMicro)
                                    .tracking(PipiTokens.trackingMicro)
                                    .foregroundStyle(PipiTokens.textMuted)
                                    .textCase(.uppercase)
                                Spacer()
                                PipiGhostIconButton(
                                    systemImage: "plus",
                                    size: 22,
                                    iconSize: 10,
                                    cornerRadius: 6,
                                    accessibilityLabel: s.newProject
                                ) {
                                    showNewProjectSheet = true
                                }
                                .help(s.newProject)
                            }
                            .padding(.horizontal, PipiTokens.spacing8)
                            .padding(.bottom, 2)

                            ForEach(store.projects) { project in
                                projectSidebarGroup(project)
                            }
                        }
                    }
                }
                .padding(.horizontal, PipiTokens.spacing12)
                .padding(.bottom, PipiTokens.spacing12)
            }
            .pipiHideScrollbars()

            // 3. Compact Single-Row Host & Settings Footer (Guided Setup lives in Settings -> General)
            VStack(spacing: 0) {
                Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)

                HStack(spacing: PipiTokens.spacing8) {
                    let isHostHovered = hoveredToolbarChip == "sidebar_host"
                    Button {
                        showHostPopover.toggle()
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(hostLinkColor(store.localHost.linkState))
                                .frame(width: 7, height: 7)
                            Text(store.localHost.displayName(lang))
                                .font(PipiTokens.fontCaption.weight(.medium))
                                .foregroundStyle(isHostHovered ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .padding(.horizontal, PipiTokens.spacing8)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                .fill(isHostHovered || showHostPopover ? PipiTokens.bgSurfaceHover : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.98))
                    .onHover { hovering in
                        hoveredToolbarChip = hovering ? "sidebar_host" : (hoveredToolbarChip == "sidebar_host" ? nil : hoveredToolbarChip)
                    }
                    .accessibilityLabel(store.localHost.statusBadgeText(lang))
                    .popover(
                        isPresented: $showHostPopover,
                        attachmentAnchor: .point(UnitPoint(x: 0.95, y: 0.0)),
                        arrowEdge: .top
                    ) {
                        sidebarHostPopover
                    }

                    Spacer(minLength: 4)

                    if !store.accountClient.isSignedIn {
                        Button {
                            Task {
                                await store.accountClient.startBrowserOAuthLogin {
                                    Task { await store.syncAccountAndAutoConnectRelay() }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 11.5, weight: .medium))
                                Text(s.t("登录", "Sign In"))
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(PipiTokens.textPrimary)
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(PipiTokens.bgSurfaceHover)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                        .help(s.t("登录 PiPiBot 统一账号，同步所有设备与远程节点", "Sign in to sync all enrolled devices & nodes"))
                    }

                    PipiGhostIconButton(
                        systemImage: "gearshape",
                        size: 32,
                        iconSize: 14,
                        cornerRadius: PipiTokens.radiusSM,
                        accessibilityLabel: s.settings
                    ) {
                        onOpenSettings(.general)
                    }
                    .help("\(s.settings) (⌘,)")
                }
                .padding(.horizontal, PipiTokens.spacing12)
                .frame(height: 48)
            }
            }
            .frame(width: layoutWidth, height: proxy.size.height, alignment: .leading)
            .opacity(collapseOpacity)
            .clipped()
        }
        .clipped()
        .scrollContentBackground(.hidden)
        .pipiStructuralMaterial()
    }

    private func sidebarNavRow(
        icon: String,
        title: String,
        isSelected: Bool,
        trailingHint: String? = nil,
        badgeCount: Int = 0,
        showPulseDot: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let navKey = "nav_\(title)"
        let isHovered = hoveredToolbarChip == navKey
        return Button(action: action) {
            HStack(spacing: PipiTokens.spacing8) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(isSelected || isHovered ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                    .frame(width: 20)

                Text(title)
                    .font(PipiTokens.fontSubheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected || isHovered ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(PipiTokens.fontMonoSmall.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(PipiTokens.textInverse)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(PipiTokens.stateWarning)
                        .clipShape(Capsule())
                }

                if showPulseDot {
                    PipiDotIndicator(vitality: .busy, color: PipiTokens.textSecondary, size: 5)
                }

                if let trailingHint {
                    Text(trailingHint)
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                }
            }
            .padding(.horizontal, PipiTokens.spacing8)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? PipiTokens.bgElevated : (isHovered ? PipiTokens.buttonGhostHoverBg : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? PipiTokens.borderSubtle : Color.clear, lineWidth: 1)
            )
            .shadow(
                color: isSelected ? PipiTokens.subtleShadow.opacity(0.65) : Color.clear,
                radius: 2,
                y: 1
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.985))
        .onHover { hovering in
            hoveredToolbarChip = hovering ? navKey : (hoveredToolbarChip == navKey ? nil : hoveredToolbarChip)
        }
    }

    private var sidebarHostPopover: some View {
        let hostRuntimeSubtitle: String = {
            switch store.localHost.linkState {
            case .online: return s.t("运行中", "Running")
            case .degraded: return s.t("信号弱", "Degraded")
            case .offline: return s.t("离线", "Offline")
            }
        }()
        let isQuickBarHovered = hoveredToolbarChip == "popover_quickbar"
        let isSettingsHovered = hoveredToolbarChip == "popover_runtime"

        return VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            // Header: 32x32 desktopcomputer badge + bold machine name + macOS · 运行中
            HStack(spacing: PipiTokens.spacing12) {
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .fill(PipiTokens.bgSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                            .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.localHost.displayName(lang))
                        .font(PipiTokens.fontHeadline)
                        .foregroundStyle(PipiTokens.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(hostLinkColor(store.localHost.linkState))
                            .frame(width: 6, height: 6)
                        Text("\(store.localHost.capabilities.osName) · \(hostRuntimeSubtitle)")
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            // Unified Account Card (Bottom-Left Login / Signed-In Identity)
            VStack(alignment: .leading, spacing: 8) {
                if let user = store.accountClient.currentUser {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PipiTokens.stateSuccess)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(user.displayName)
                                .font(PipiTokens.fontCaption.weight(.semibold))
                                .foregroundStyle(PipiTokens.textPrimary)
                                .lineLimit(1)
                            Text(user.email ?? s.t("已登录统一账号", "Signed in"))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textMuted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(s.t("设备看板", "Nodes")) {
                            showHostPopover = false
                            destination = .deviceNodes
                        }
                        .font(.system(size: 10.5, weight: .medium))
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(PipiTokens.textSecondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.t("未登录 PiPiBot 账号", "Not signed in"))
                                .font(PipiTokens.fontCaption.weight(.semibold))
                                .foregroundStyle(PipiTokens.textPrimary)
                            Text(s.t("登录后打通网页端与多机节点", "Sync WebUI & remote nodes"))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                        Spacer()
                        Button(s.t("登录", "Sign In")) {
                            Task {
                                await store.accountClient.startBrowserOAuthLogin {
                                    Task { await store.syncAccountAndAutoConnectRelay() }
                                }
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    }
                    if let code = store.accountClient.pendingBrowserUserCode {
                        Text(s.t("浏览器授权码：\(code)", "Browser code: \(code)"))
                            .font(PipiTokens.fontMonoSmall)
                            .foregroundStyle(PipiTokens.textPrimary)
                    }
                }
            }
            .padding(.horizontal, PipiTokens.spacing12)
            .padding(.vertical, 10)
            .background(PipiTokens.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))

            // Grouped Rounded Card: Keep Mac Awake + Local Engines
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(s.keepAwakeTitle)
                        .font(PipiTokens.fontCaption.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(
                        get: { store.bridgeSupervisor.keepAwakeEnabled },
                        set: { store.setKeepAwake($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                .padding(.horizontal, PipiTokens.spacing12)
                .padding(.vertical, 10)

                if !store.localAgentStatuses.isEmpty {
                    Rectangle()
                        .fill(PipiTokens.borderSubtle)
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(s.t("本地执行引擎", "Local Engines"))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textMuted)

                        ForEach(store.localAgentStatuses) { agent in
                            let statusColor: Color = agent.authenticated ? PipiTokens.stateSuccess : (agent.installed ? PipiTokens.stateWarning : PipiTokens.textMuted.opacity(0.6))
                            let statusLabel: String = agent.authenticated
                                ? s.t("就绪", "Ready")
                                : (agent.installed ? s.t("需登录", "Sign in") : s.t("未安装", "Not installed"))
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 6, height: 6)
                                Text(agent.kind.displayName)
                                    .font(PipiTokens.fontCaption.weight(.medium))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Spacer()
                                Text(statusLabel)
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(agent.authenticated ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                            }
                        }
                    }
                    .padding(.horizontal, PipiTokens.spacing12)
                    .padding(.vertical, 10)
                }

                // Enrolled Remote Nodes under the same Unified Account
                if store.accountClient.isSignedIn {
                    Rectangle()
                        .fill(PipiTokens.borderSubtle)
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text(s.t("已纳管远程节点", "Enrolled Remote Nodes"))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textMuted)
                            Spacer()
                            Button {
                                Task { await store.accountClient.refreshProfile() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(PipiTokens.textMuted)
                            }
                            .buttonStyle(.plain)
                            .help(s.t("刷新已纳管设备列表", "Refresh enrolled devices"))
                        }

                        let remoteNodes = store.enrolledRemoteDevices
                        if remoteNodes.isEmpty {
                            Text(s.t("在其他机器运行 pipibot login && pipibot up 即可接入并上报 Harness", "Run pipibot login && pipibot up on any machine to enroll"))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(remoteNodes.prefix(5)) { dev in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(dev.isOnline ? PipiTokens.stateSuccess : PipiTokens.textMuted.opacity(0.45))
                                            .frame(width: 6, height: 6)
                                        Text(dev.name)
                                            .font(PipiTokens.fontCaption.weight(.medium))
                                            .foregroundStyle(PipiTokens.textPrimary)
                                            .lineLimit(1)
                                        Spacer(minLength: 4)
                                        if dev.isOnline {
                                            Button(s.t("排查", "Inspect")) {
                                                showHostPopover = false
                                                let prompt = s.t(
                                                    "请通过远程守护进程检查节点「\(dev.name)」的系统状态、Git 分支和已安装的 Agent Harness",
                                                    "Inspect remote node '\(dev.name)' system status, git branch, and installed agent harnesses via its daemon."
                                                )
                                                Task { await store.sendPersonalMessage(prompt) }
                                            }
                                            .font(.system(size: 10.5, weight: .medium))
                                            .buttonStyle(.bordered)
                                            .controlSize(.mini)

                                            Button(s.t("调用", "Run")) {
                                                showHostPopover = false
                                                let defaultHarness = dev.capabilities.first ?? "Claude Code"
                                                draftMessage = s.t(
                                                    "请在远程节点「\(dev.name)」上调用 \(defaultHarness) 执行：",
                                                    "Run \(defaultHarness) on remote node '\(dev.name)' to: "
                                                )
                                            }
                                            .font(.system(size: 10.5, weight: .medium))
                                            .buttonStyle(.bordered)
                                            .controlSize(.mini)
                                        } else {
                                            Text(s.t("离线", "Offline"))
                                                .font(PipiTokens.fontMicro)
                                                .foregroundStyle(PipiTokens.textMuted)
                                        }
                                    }
                                    if !dev.capabilities.isEmpty {
                                        Text(dev.capabilities.prefix(4).joined(separator: " · "))
                                            .font(.system(size: 10))
                                            .foregroundStyle(PipiTokens.textMuted)
                                            .lineLimit(1)
                                            .padding(.leading, 12)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, PipiTokens.spacing12)
                    .padding(.vertical, 10)
                }
            }
            .onAppear {
                if store.accountClient.isSignedIn {
                    Task { await store.accountClient.refreshProfile() }
                }
            }
            .background(PipiTokens.bgSurface)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                    .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))

            // Clean Bottom Action Section
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    showHostPopover = false
                    onToggleQuickBar()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(isQuickBarHovered ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                            .frame(width: 18)
                        Text(s.quickBar)
                            .font(PipiTokens.fontCaption.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Spacer()
                        Text("⌥Space")
                            .font(PipiTokens.fontMonoSmall)
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                            .fill(isQuickBarHovered ? PipiTokens.buttonGhostHoverBg : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.985))
                .onHover { hovering in
                    hoveredToolbarChip = hovering ? "popover_quickbar" : (hoveredToolbarChip == "popover_quickbar" ? nil : hoveredToolbarChip)
                }

                Button {
                    showHostPopover = false
                    onOpenSettings(.remoteAccess)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(isSettingsHovered ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                            .frame(width: 18)
                        Text(s.settingsRemoteAccess)
                            .font(PipiTokens.fontCaption.weight(.medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                            .fill(isSettingsHovered ? PipiTokens.buttonGhostHoverBg : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.985))
                .onHover { hovering in
                    hoveredToolbarChip = hovering ? "popover_runtime" : (hoveredToolbarChip == "popover_runtime" ? nil : hoveredToolbarChip)
                }
            }
        }
        .padding(PipiTokens.spacing16)
        .frame(width: 288)
        .background(PipiTokens.bgElevated)
    }

    private func hostLinkColor(_ state: PipiHostLinkState) -> Color {
        switch state {
        case .online: return PipiTokens.stateSuccess
        case .degraded: return PipiTokens.stateWarning
        case .offline: return PipiTokens.textMuted
        }
    }

    private func groupChatSidebarRow(_ group: PipiGroupChat) -> some View {
        let isSelected = destination == .group(group.id)
        let isHovered = hoveredGroupId == group.id
        let isRunning = store.isGroupRunning(group.id)
        let members = group.participantPersonaIds.compactMap { pid in
            store.personas.first(where: { $0.id == pid })
        }

        return Button {
            store.selectGroupChat(group.id)
            destination = .group(group.id)
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: -6) {
                    ForEach(members.prefix(3)) { bot in
                        PipiBotPersonaGlyph(persona: bot, size: 20, isSelected: isSelected)
                            .overlay(Circle().stroke(PipiTokens.bgElevated, lineWidth: 1.2))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(group.title)
                            .font(PipiTokens.fontCaption.weight((isSelected || store.unreadCount(forGroup: group.id) > 0) ? .semibold : .medium))
                            .foregroundStyle((isSelected || store.unreadCount(forGroup: group.id) > 0) ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if group.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(PipiTokens.textMuted)
                        }

                        if isRunning {
                            sidebarStatusPill(
                                label: s.t("处理中", "Running"),
                                color: PipiTokens.soulPrimary,
                                isPulsing: true
                            )
                        } else if store.unreadCount(forGroup: group.id) > 0 {
                            sidebarUnreadBadge(count: store.unreadCount(forGroup: group.id))
                        } else {
                            Text(store.relativeTimeLabel(for: group.updatedAt))
                                .font(PipiTokens.fontMicro)
                                .monospacedDigit()
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                    }

                    Text(s.t("群聊 · \(members.count) 位助手", "Group · \(members.count) assistants"))
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? PipiTokens.bgElevated : (isHovered ? PipiTokens.buttonGhostHoverBg : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(isSelected ? PipiTokens.borderSubtle : Color.clear, lineWidth: 1)
            )
            .shadow(
                color: isSelected ? PipiTokens.subtleShadow.opacity(0.65) : Color.clear,
                radius: 2,
                y: 1
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.985))
        .onHover { hovering in
            hoveredGroupId = hovering ? group.id : nil
        }
        .contextMenu {
            Button(group.isPinned ? s.unpinChat : s.pinChat) {
                store.togglePinGroupChat(id: group.id)
            }
            Button(s.renameGroupChat) {
                renameGroupDraftTitle = group.title
                renamingGroupChat = group
            }
            Button(s.editGroupChat) {
                editingGroupChat = group
                groupCreatorPreselectedBotIds = []
                showGroupCreatorSheet = true
            }
            Divider()
            Button(s.delete, role: .destructive) {
                store.deleteGroupChat(id: group.id)
                if destination == .group(group.id) {
                    destination = .home
                }
            }
        }
        .accessibilityAction(named: group.isPinned ? s.unpinChat : s.pinChat) {
            store.togglePinGroupChat(id: group.id)
        }
        .accessibilityAction(named: s.editGroupChat) {
            editingGroupChat = group
            groupCreatorPreselectedBotIds = []
            showGroupCreatorSheet = true
        }
        .accessibilityAction(named: s.delete) {
            store.deleteGroupChat(id: group.id)
            if destination == .group(group.id) {
                destination = .home
            }
        }
    }

    private func projectSidebarGroup(_ project: PipiProject) -> some View {
        let projColor = PipiTokens.color(for: project.accent)
        let projConvs = store.conversations(inProject: project.id)
        let isHovered = hoveredProjectId == project.id
        let isActiveProject = store.activeConversation?.projectId == project.id

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button {
                    withAnimation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion)) {
                        store.toggleProjectCollapsed(project.id)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: project.isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(PipiTokens.textMuted)
                            .frame(width: 10)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(projColor)
                        Text(project.name)
                            .font(PipiTokens.fontCaption.weight(isActiveProject ? .semibold : .medium))
                            .foregroundStyle(isActiveProject ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if !isHovered && !projConvs.isEmpty {
                            Text("\(projConvs.count)")
                                .font(PipiTokens.fontMonoSmall)
                                .monospacedDigit()
                                .foregroundStyle(PipiTokens.textMuted)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.985))

                if isHovered {
                    PipiGhostIconButton(
                        systemImage: "plus",
                        size: 20,
                        iconSize: 10,
                        cornerRadius: 5,
                        accessibilityLabel: s.newChatInProject
                    ) {
                        let created = store.createConversation(projectId: project.id)
                        destination = .session(created.id)
                        isComposerFocused = true
                    }
                    .help(s.newChatInProject)
                }
            }
            .padding(.horizontal, PipiTokens.spacing8)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .fill(isHovered ? PipiTokens.buttonGhostHoverBg : Color.clear)
            )
            .onHover { hovering in
                hoveredProjectId = hovering ? project.id : nil
            }
            .contextMenu {
                Button(s.newChatInProject) {
                    let created = store.createConversation(projectId: project.id)
                    destination = .session(created.id)
                    isComposerFocused = true
                }
                Button(s.editProject) {
                    editingProject = project
                }
                Divider()
                Button(s.delete, role: .destructive) {
                    store.deleteProject(project.id)
                }
            }
            .accessibilityAction(named: s.newChatInProject) {
                let created = store.createConversation(projectId: project.id)
                destination = .session(created.id)
            }
            .accessibilityAction(named: s.editProject) {
                editingProject = project
            }
            .accessibilityAction(named: s.delete) {
                store.deleteProject(project.id)
            }

            if !project.isCollapsed {
                if projConvs.isEmpty {
                    Text(s.noChatsYet)
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textMuted)
                        .padding(.leading, 28)
                        .padding(.vertical, 3)
                } else {
                    ForEach(projConvs) { conv in
                        conversationSidebarRow(conv, isArchived: false, indented: true)
                    }
                }
            }
        }
    }

    private func syncVisibleDestinationState(_ dest: WorkspaceDestination) {
        switch dest {
        case .session(let convId):
            store.currentlyVisibleSessionId = convId
            store.currentlyVisibleGroupId = nil
            store.markConversationRead(convId)
        case .group(let groupId):
            store.currentlyVisibleSessionId = nil
            store.currentlyVisibleGroupId = groupId
            store.markGroupRead(groupId)
        default:
            store.currentlyVisibleSessionId = nil
            store.currentlyVisibleGroupId = nil
        }
    }

    private func sidebarStatusPill(
        label: String,
        color: Color,
        systemImage: String? = nil,
        isPulsing: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            if isPulsing {
                PipiDotIndicator(vitality: .busy, color: color, size: 5)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(color)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func sidebarUnreadBadge(count: Int) -> some View {
        Text(count > 9 ? "9+" : "\(count)")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .padding(.horizontal, 5.5)
            .frame(minWidth: 18, minHeight: 16)
            .background(PipiTokens.soulPrimary)
            .clipShape(Capsule())
    }

    private func conversationSidebarRow(_ conv: PipiConversation, isArchived: Bool, indented: Bool) -> some View {
        let isSelected = destination == .session(conv.id)
        let isHovered = hoveredConversationId == conv.id
        let bot = store.personas.first(where: { $0.id == conv.personaId }) ?? store.activePersona
        let botAccent = PipiTokens.color(for: bot.accent)
        let isHostOffline = store.hostDescriptor(for: conv.hostId).linkState == .offline
        let rowStatus = store.conversationRowStatus(for: conv)
        let hasUnread: Bool = {
            if case .unread = rowStatus { return true }
            return false
        }()

        return HStack(spacing: 6) {
            Button {
                store.selectConversation(conv.id)
                destination = .session(conv.id)
            } label: {
                HStack(spacing: 10) {
                    PipiBotPersonaGlyph(persona: bot, size: 24, isSelected: isSelected)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(conv.title)
                                .font(PipiTokens.fontCaption.weight((isSelected || hasUnread) ? .semibold : .medium))
                                .foregroundStyle(isHostOffline ? PipiTokens.textMuted : ((isSelected || hasUnread) ? PipiTokens.textPrimary : PipiTokens.textSecondary))
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            if conv.isPinned && !isArchived {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundStyle(PipiTokens.textMuted)
                            }

                            if !isHovered {
                                switch rowStatus {
                                case .processing:
                                    sidebarStatusPill(
                                        label: s.t("处理中", "Running"),
                                        color: botAccent,
                                        isPulsing: true
                                    )
                                case .queued:
                                    sidebarStatusPill(
                                        label: s.t("排队", "Queued"),
                                        color: PipiTokens.stateWarning
                                    )
                                case .needsApproval:
                                    sidebarStatusPill(
                                        label: s.t("待确认", "Confirm"),
                                        color: PipiTokens.stateWarning,
                                        systemImage: "hand.raised.fill"
                                    )
                                case .failed:
                                    sidebarStatusPill(
                                        label: s.t("失败", "Failed"),
                                        color: PipiTokens.stateError,
                                        systemImage: "exclamationmark.circle.fill"
                                    )
                                case .unread(let count):
                                    sidebarUnreadBadge(count: count)
                                case .idle:
                                    if isHostOffline {
                                        PipiSessionStateDot(state: conv.state, accent: botAccent, isHostOffline: true)
                                    }
                                    Text(store.relativeTimeLabel(for: conv.updatedAt))
                                        .font(PipiTokens.fontMicro)
                                        .monospacedDigit()
                                        .foregroundStyle(PipiTokens.textMuted)
                                }
                            }
                        }

                        Text(bot.name(lang))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textMuted)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.985))

            if isHovered {
                PipiGhostIconButton(
                    systemImage: isArchived ? "arrow.uturn.backward" : "archivebox",
                    size: 24,
                    iconSize: 11,
                    cornerRadius: 6,
                    accessibilityLabel: isArchived ? s.unarchiveChat : s.archiveChat
                ) {
                    withAnimation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion)) {
                        store.toggleArchiveConversation(conv.id)
                    }
                }
                .help(isArchived ? s.unarchiveChat : s.archiveChat)
            }
        }
        .padding(.leading, indented ? 24 : 10)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? PipiTokens.bgElevated : (isHovered ? PipiTokens.buttonGhostHoverBg : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? PipiTokens.borderSubtle : Color.clear, lineWidth: 1)
        )
        .shadow(
            color: isSelected ? PipiTokens.subtleShadow.opacity(0.65) : Color.clear,
            radius: 2,
            y: 1
        )
        .onHover { hovering in
            hoveredConversationId = hovering ? conv.id : nil
        }
        .contextMenu {
            Button(conv.isPinned ? s.unpinChat : s.pinChat) {
                store.togglePinConversation(conv.id)
            }

            Button(s.renameChat) {
                renameDraftTitle = conv.title
                renamingConversation = conv
            }

            if !store.projects.isEmpty || conv.projectId != nil {
                Menu(s.moveToProject) {
                    ForEach(store.projects) { project in
                        Button {
                            store.moveConversation(conv.id, toProject: project.id)
                        } label: {
                            HStack {
                                Text(project.name)
                                if conv.projectId == project.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    if conv.projectId != nil {
                        Divider()
                        Button(s.removeFromProject) {
                            store.moveConversation(conv.id, toProject: nil)
                        }
                    }
                }
            }

            Button(isArchived ? s.unarchiveChat : s.archiveChat) {
                store.toggleArchiveConversation(conv.id)
            }

            Divider()

            Button(s.delete, role: .destructive) {
                store.deleteConversation(conv.id)
            }
        }
        .accessibilityAction(named: conv.isPinned ? s.unpinChat : s.pinChat) {
            store.togglePinConversation(conv.id)
        }
        .accessibilityAction(named: isArchived ? s.unarchiveChat : s.archiveChat) {
            store.toggleArchiveConversation(conv.id)
        }
        .accessibilityAction(named: s.delete) {
            store.deleteConversation(conv.id)
        }
    }

    // MARK: - Detail Stage (3D Bot Home, Needs You Inbox, Group Swarm, or 1:1 Session)

    @ViewBuilder
    private var detailStage: some View {
        switch destination {
        case .home:
            PipiBotsHubView(
                store: store,
                collaboratingBotIds: store.collaboratingBotIds,
                externalResetTrigger: homeResetCameraTrigger,
                onOpenBotChat: { persona in
                    let existing = store.conversations
                        .filter { $0.personaId == persona.id && !$0.isArchived }
                        .sorted { $0.updatedAt > $1.updatedAt }
                        .first
                    let target = existing ?? store.createConversation(for: persona.id, activate: true)
                    store.selectConversation(target.id)
                    destination = .session(target.id)
                },
                onQuickSendToBot: { persona, prompt in
                    let created = store.createConversation(for: persona.id, activate: true)
                    destination = .session(created.id)
                    Task {
                        await store.sendPersonalMessage(
                            prompt,
                            conversationId: created.id,
                            personaId: persona.id,
                            activateTargetConversation: true
                        )
                    }
                },
                onStartVoiceCall: { persona in
                    let existing = store.conversations
                        .filter { $0.personaId == persona.id && !$0.isArchived }
                        .sorted { $0.updatedAt > $1.updatedAt }
                        .first
                    let target = existing ?? store.createConversation(for: persona.id, activate: true)
                    store.selectConversation(target.id)
                    destination = .session(target.id)
                    Task {
                        await store.startVoiceCall(with: persona.id)
                    }
                },
                onCreateBot: {
                    showNewPersonaSheet = true
                },
                onEditBot: { persona in
                    editingPersona = persona
                },
                onDeleteBot: { persona in
                    pendingDeletePersona = persona
                },
                onCreateGroupChat: { preselectedBotId in
                    groupCreatorPreselectedBotIds = preselectedBotId.map { [$0] } ?? []
                    editingGroupChat = nil
                    showGroupCreatorSheet = true
                },
                onOpenSession: { convId in
                    store.selectConversation(convId)
                    destination = .session(convId)
                }
            )
        case .deviceNodes:
            PipiDeviceNodesDashboardView(
                store: store,
                onSelectNodeForChat: { hostId, harness in
                    selectedExecutionNodeHostId = hostId
                    selectedExecutionNodeHarness = harness
                    let targetConvId = store.activeConversationId ?? store.createConversation(projectId: store.activeConversation?.projectId).id
                    store.selectConversation(targetConvId)
                    destination = .session(targetConvId)
                    isComposerFocused = true
                },
                onInspectRemoteNode: { dev in
                    let targetConvId = store.activeConversationId ?? store.createConversation(projectId: store.activeConversation?.projectId).id
                    store.selectConversation(targetConvId)
                    destination = .session(targetConvId)
                    let prompt = s.t(
                        "请通过远程守护进程检查节点「\(dev.name)」的系统状态、硬件资源、Git 分支和已安装的 Agent Harness",
                        "Inspect remote node '\(dev.name)' system status, hardware resources, git branch, and installed agent harnesses via its daemon."
                    )
                    Task { await store.sendPersonalMessage(prompt) }
                },
                onOpenRemoteSettings: {
                    onOpenSettings(.remoteAccess)
                }
            )
        case .missionBoard:
            PipiMissionBoardView(
                store: store,
                onOpenArchitect: {
                    let conv = store.openBotArchitectSession()
                    destination = .session(conv.id)
                },
                onOpenConversation: { sessionId in
                    store.selectConversation(sessionId)
                    destination = .session(sessionId)
                }
            )
        case .needsYou:
            PipiNeedsYouInboxView(store: store) { sessionId in
                store.selectConversation(sessionId)
                destination = .session(sessionId)
            }
        case .knowledge:
            PipiKnowledgeHubView(store: store) { sessionId in
                store.selectConversation(sessionId)
                destination = .session(sessionId)
            }
        case .group(let groupId):
            PipiGroupChatView(
                store: store,
                groupId: groupId,
                pendingMentionInsert: $pendingGroupMentionInsert,
                onOpenSettings: { onOpenSettings(.aiEngine) },
                onOpenMembersInspector: {
                    selectedGroupInspectorTab = .membersTasks
                    withAnimation(PipiMotion.adaptive(PipiMotion.drawer, reduceMotion: reduceMotion)) {
                        store.isInspectorPresented = true
                    }
                }
            )
        case .session:
            chatStage
        }
    }

    // MARK: - Center Workbench Stage

    private var chatStage: some View {
        ZStack {
            if isConversationEmpty {
                centeredEmptyStage
                    .transaction { $0.animation = nil }
            } else {
                activeTranscriptStage
            }

            VStack(spacing: 0) {
                if let warning = store.persistenceWarning {
                    persistenceWarningBanner(warning)
                        .padding(.horizontal, PipiTokens.spacing24)
                        .padding(.top, PipiTokens.spacing8)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                if let topDecision = store.pendingDecisions.first {
                    inlineAttentionBanner(topDecision)
                        .padding(.horizontal, PipiTokens.spacing24)
                        .padding(.top, PipiTokens.spacing8)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                if let activeConvId = store.activeConversationId,
                   !store.alterEgoTasks(forSession: activeConvId).isEmpty {
                    PipiAlterEgoBarView(store: store, sessionId: activeConvId)
                        .padding(.horizontal, PipiTokens.spacing24)
                        .padding(.top, PipiTokens.spacing8)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                if store.hasComputerUseAttention {
                    PipiComputerUseBarView(
                        store: store,
                        onOpenSettings: { onOpenSettings(.permissionsControl) }
                    )
                    .padding(.horizontal, PipiTokens.spacing24)
                    .padding(.top, PipiTokens.spacing8)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                if store.showUndoToast, let deletedItem = store.lastDeletedItem {
                    undoDeletionToast(deletedItem)
                        .padding(.bottom, isConversationEmpty ? PipiTokens.spacing24 : 132)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: store.showUndoToast)
        }
        .background(alignment: .top) {
            PipiTokens.bgCanvas
                .frame(height: 72)
                .ignoresSafeArea(.container, edges: .top)
        }
    }

    private func persistenceWarningBanner(_ message: String) -> some View {
        HStack(spacing: PipiTokens.spacing12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PipiTokens.stateWarning)
            Text(message)
                .font(PipiTokens.fontCaption)
                .foregroundStyle(PipiTokens.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                store.dismissPersistenceWarning()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(PipiTokens.textMuted)
                    .frame(width: 22, height: 22)
                    .background(PipiTokens.buttonGhostHoverBg)
                    .clipShape(Circle())
            }
            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
            .accessibilityLabel(s.close)
        }
        .padding(.horizontal, PipiTokens.spacing16)
        .padding(.vertical, PipiTokens.spacing8)
        .background(PipiTokens.stateWarningBg)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.stateWarning.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }

    private func undoDeletionToast(_ item: PipiUndoableDeletion) -> some View {
        HStack(spacing: PipiTokens.spacing12) {
            Text(item.toastLabel(lang))
                .font(PipiTokens.fontCaption.weight(.medium))
                .foregroundStyle(PipiTokens.textPrimary)
                .lineLimit(1)

            Text("·")
                .font(PipiTokens.fontCaption)
                .foregroundStyle(PipiTokens.textMuted)

            Button {
                _ = store.undoLastDeletion()
            } label: {
                HStack(spacing: 4) {
                    Text(s.undoAction)
                        .font(PipiTokens.fontCaption.weight(.semibold))
                    Text("⌘Z")
                        .font(PipiTokens.fontMonoSmall)
                        .foregroundStyle(PipiTokens.textMuted)
                }
                .foregroundStyle(PipiTokens.textPrimary)
                .padding(.horizontal, PipiTokens.spacing8)
                .padding(.vertical, 4)
                .background(PipiTokens.bgSurfaceHover)
                .clipShape(Capsule())
            }
            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.95))

            Button {
                store.dismissUndoToast()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(PipiTokens.textMuted)
                    .frame(width: 20, height: 20)
                    .background(PipiTokens.buttonGhostHoverBg)
                    .clipShape(Circle())
            }
            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
            .accessibilityLabel(s.close)
        }
        .padding(.horizontal, PipiTokens.spacing16)
        .padding(.vertical, PipiTokens.spacing8)
        .pipiLiquidGlass(cornerRadius: PipiTokens.radiusPill, shadowRadius: 16, shadowY: 6)
    }

    // MARK: - Empty Stage

    private var centeredEmptyStage: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(PipiTokens.borderSubtle)
                .frame(height: 1)

            Spacer(minLength: 48)

            VStack(spacing: PipiTokens.spacing24) {
                VStack(spacing: PipiTokens.spacing12) {
                    PipiAvatarView(
                        engine: store.avatarEngine,
                        size: 96,
                        accentOverride: activeAccent,
                        personaAccent: store.activePersona.accent,
                        motif: activeMotif
                    )

                    Text(store.activePersona.name(lang))
                        .font(PipiTokens.fontHero)
                        .tracking(PipiTokens.trackingHero)
                        .foregroundStyle(PipiTokens.textPrimary)

                    Text(store.activePersona.greeting(lang))
                        .font(PipiTokens.fontBody)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 500)
                }

                composerStack
                    .frame(maxWidth: 700)

                let prompts = Array(store.activePersona.starterPrompts(lang).prefix(3))
                if !prompts.isEmpty {
                    HStack(spacing: PipiTokens.spacing8) {
                        ForEach(prompts, id: \.self) { prompt in
                            let isChipHovered = hoveredStarterPrompt == prompt
                            Button {
                                Task { await store.sendPersonalMessage(prompt) }
                            } label: {
                                HStack(spacing: 5) {
                                    Text(prompt)
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(isChipHovered ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                                        .lineLimit(1)
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(isChipHovered ? PipiTokens.textPrimary : PipiTokens.textMuted)
                                }
                                .padding(.horizontal, 13)
                                .frame(height: 34)
                                .background(isChipHovered ? PipiTokens.buttonSecondaryHoverBg : PipiTokens.buttonSecondaryBg)
                                .overlay(
                                    Capsule()
                                        .stroke(isChipHovered ? PipiTokens.buttonHoverBorder : PipiTokens.borderSubtle, lineWidth: 1)
                                )
                                .clipShape(Capsule())
                                .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: isChipHovered)
                            }
                            .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))
                            .onHover { hovering in
                                hoveredStarterPrompt = hovering ? prompt : nil
                            }
                        }
                    }
                    .frame(maxWidth: 700)
                }
            }
            .padding(.horizontal, 38)

            Spacer(minLength: 64)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PipiTokens.bgCanvas)
    }

    // MARK: - Active Transcript Stage

    private var activeTranscriptStage: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(PipiTokens.borderSubtle)
                .frame(height: 1)

            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 26) {
                            Spacer().frame(height: store.pendingDecisions.isEmpty ? 24 : 76)

                            if let conv = store.activeConversation {
                                ForEach(conv.messages) { msg in
                                    let isStreamingThis = store.isGeneratingReply && store.streamingMessageId == msg.id
                                    let isLastAssistant = msg.id == conv.messages.last?.id && msg.role == .assistant
                                    messageRow(msg, conversation: conv, isStreaming: isStreamingThis, isLastAssistant: isLastAssistant)
                                        .id(msg.id)
                                }
                                .transaction { $0.animation = nil }

                                Color.clear
                                    .frame(height: 1)
                                    .id("pipi-chat-bottom")
                            }

                            Spacer().frame(height: 28)
                        }
                        .frame(maxWidth: 780)
                        .padding(.horizontal, 38)
                        .frame(maxWidth: .infinity)
                    }
                    .pipiHideScrollbars()
                    .clipped()
                    .onChange(of: store.activeConversation?.messages.count ?? 0) { _, _ in
                        scrollToBottom(proxy: proxy, animated: !reduceMotion)
                    }
                    .onChange(of: store.activeConversation?.messages.last?.content.count ?? 0) { _, _ in
                        if store.isGeneratingReply {
                            scrollToBottom(proxy: proxy, animated: false)
                        }
                    }
                }

                LinearGradient(
                    colors: [PipiTokens.bgCanvas.opacity(0), PipiTokens.bgCanvas],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 24)
                .allowsHitTesting(false)
            }

            composerStack
                .frame(maxWidth: 780)
                .padding(.horizontal, 38)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
                .background(PipiTokens.bgCanvas)
        }
        .background(PipiTokens.bgCanvas)
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                proxy.scrollTo("pipi-chat-bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("pipi-chat-bottom", anchor: .bottom)
        }
    }

    private func inlineAttentionBanner(_ decision: NeedsYouDecision) -> some View {
        HStack(spacing: PipiTokens.spacing12) {
            Circle()
                .fill(PipiTokens.stateWarning)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(decision.title)
                    .font(PipiTokens.fontCaption.weight(.semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)
                Text(decision.summary)
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if let rec = decision.options.first(where: { $0.id == decision.recommendedOptionId }) {
                PipiActionButton(rec.label, systemImage: "checkmark", tone: .primary, density: .desktopCompact) {
                    Task { await store.resolveDecision(decision.id, optionId: rec.id) }
                }
            }
            if let deferOpt = decision.options.last, deferOpt.id != decision.recommendedOptionId {
                PipiActionButton(s.reject, tone: .secondary, density: .desktopCompact) {
                    Task { await store.resolveDecision(decision.id, optionId: deferOpt.id) }
                }
            }
        }
        .padding(.horizontal, PipiTokens.spacing16)
        .padding(.vertical, PipiTokens.spacing8)
        .pipiLiquidGlass(cornerRadius: PipiTokens.radiusMD, shadowRadius: 12, shadowY: 4)
    }

    // MARK: - Workbench Turn Layout

    private func messageRow(
        _ msg: PipiChatMessage,
        conversation: PipiConversation,
        isStreaming: Bool,
        isLastAssistant: Bool
    ) -> some View {
        let isHovered = hoveredMessageId == msg.id
        let runStartedAt = store.runStartedAt(for: conversation.id)

        return Group {
            if msg.role == .user {
                VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                    if let files = msg.attachments, !files.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(files) { file in
                                    HStack(spacing: 4) {
                                        Image(systemName: file.iconName)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(PipiTokens.textSecondary)
                                        Text(file.name)
                                            .font(PipiTokens.fontMonoSmall)
                                            .foregroundStyle(PipiTokens.textSecondary)
                                            .lineLimit(1)
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2.5)
                                    .background(PipiTokens.bgElevated)
                                    .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }

                    Text(msg.content)
                        .font(PipiTokens.fontBody)
                        .foregroundStyle(PipiTokens.textPrimary)
                        .textSelection(.enabled)
                        .lineSpacing(5.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, PipiTokens.spacing16)
                .padding(.vertical, PipiTokens.spacing12)
                .background(PipiTokens.userBubbleBg)
                .overlay(
                    RoundedRectangle(cornerRadius: PipiTokens.radiusComposer, style: .continuous)
                        .stroke(PipiTokens.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusComposer, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if isHovered || copiedMessageId == msg.id {
                        Button {
                            triggerCopy(msg.content, messageId: msg.id)
                        } label: {
                            Image(systemName: copiedMessageId == msg.id ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(copiedMessageId == msg.id ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                .frame(width: 24, height: 24)
                                .background(PipiTokens.bgElevated)
                                .overlay(Circle().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                                .clipShape(Circle())
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                        .padding(PipiTokens.spacing8)
                        .accessibilityLabel(s.copy)
                    }
                }
                .onHover { hovering in
                    hoveredMessageId = hovering ? msg.id : nil
                }
                .contextMenu {
                    Button(s.copy) {
                        triggerCopy(msg.content, messageId: msg.id)
                    }
                }
                .accessibilityAction(named: s.copy) {
                    triggerCopy(msg.content, messageId: msg.id)
                }
            } else {
                HStack(alignment: .top, spacing: PipiTokens.spacing12) {
                    VStack(spacing: 6) {
                        if msg.isError {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(PipiTokens.stateWarningBg)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(PipiTokens.stateWarning)
                                )
                        } else {
                            PipiBotPersonaGlyph(persona: store.activePersona, size: 30, isSelected: true)
                        }

                        if isStreaming {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(PipiTokens.borderStrong)
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: PipiTokens.spacing8) {
                            Text(store.activePersona.name(lang))
                                .font(PipiTokens.fontCaption.weight(.semibold))
                                .foregroundStyle(PipiTokens.textPrimary)

                            if let label = msg.engineLabel {
                                Text(label)
                                    .font(PipiTokens.fontMonoSmall)
                                    .foregroundStyle(PipiTokens.textMuted)
                            }

                            if isStreaming, let runStartedAt {
                                HStack(spacing: 4) {
                                    PipiDotIndicator(vitality: .busy, color: PipiTokens.textSecondary, size: 5)
                                    PipiElapsedTimerLabel(startedAt: runStartedAt, color: PipiTokens.textSecondary)
                                }
                            }
                        }

                        if !msg.planItems.isEmpty {
                            PipiPlanChecklistCard(
                                items: msg.planItems,
                                strings: s,
                                accent: activeAccent
                            )
                        }

                        if !msg.steps.isEmpty {
                            PipiCollapsedStepsCard(
                                steps: msg.steps,
                                strings: s,
                                accent: activeAccent
                            )
                        }

                        if !msg.fileChanges.isEmpty {
                            PipiFileChangesCard(
                                changes: msg.fileChanges,
                                strings: s,
                                accent: activeAccent
                            ) { change in
                                withAnimation(PipiMotion.adaptive(PipiMotion.drawer, reduceMotion: reduceMotion)) {
                                    store.openInspectorForChange(change)
                                }
                            }
                        }

                        let hasStructuredCards = !msg.planItems.isEmpty || !msg.steps.isEmpty || !msg.fileChanges.isEmpty
                        if isStreaming && msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasStructuredCards {
                            HStack(spacing: PipiTokens.spacing8) {
                                PipiDotIndicator(vitality: .busy, color: activeAccent, size: 7)
                                Text(store.generatingStatusText ?? s.thinkingStatus)
                                    .font(PipiTokens.fontCaption.weight(.medium))
                                    .foregroundStyle(PipiTokens.textSecondary)
                                Spacer(minLength: 8)
                                if let runStartedAt {
                                    PipiElapsedTimerLabel(startedAt: runStartedAt, color: PipiTokens.textMuted)
                                }
                            }
                            .padding(.horizontal, PipiTokens.spacing12)
                            .padding(.vertical, PipiTokens.spacing8)
                            .background(PipiTokens.bgSurface.opacity(0.75))
                            .overlay(
                                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                    .stroke(activeAccent.opacity(0.28), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                        } else if msg.isError {
                            PipiActionableErrorCard(
                                message: msg,
                                store: store,
                                onRetry: {
                                    Task { await store.retryTurn(conversationId: conversation.id, errorMessageId: msg.id) }
                                },
                                onSwitchEngine: { target in
                                    Task { await store.switchEngineAndRetry(conversationId: conversation.id, errorMessageId: msg.id, target: target) }
                                },
                                onOpenSettings: { tab in
                                    onOpenSettings(tab)
                                }
                            )
                        } else if !msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            PipiMarkdownView(
                                content: msg.content,
                                strings: s,
                                accent: activeAccent,
                                isStreaming: isStreaming
                            )
                        }

                        if let delivered = msg.attachments, !delivered.isEmpty {
                            VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
                                ForEach(delivered) { att in
                                    let (kind, _) = PipiDeliverableArtifact.inferKindAndMime(for: att.path)
                                    VStack(alignment: .leading, spacing: 6) {
                                        #if os(macOS)
                                        if kind == .image, let img = NSImage(contentsOfFile: att.path) {
                                            Image(nsImage: img)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(maxWidth: 420, maxHeight: 260, alignment: .leading)
                                                .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                                        .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                                                )
                                        }
                                        #endif
                                        HStack(spacing: PipiTokens.spacing8) {
                                            Image(systemName: kind == .image ? "photo" : (kind == .audio ? "waveform" : (kind == .video ? "video" : "doc")))
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(PipiTokens.textSecondary)
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(att.name)
                                                    .font(PipiTokens.fontCaption.weight(.medium))
                                                    .foregroundStyle(PipiTokens.textPrimary)
                                                    .lineLimit(1)
                                                Text("\(kind.label(lang)) · \(PipiMacOmnipotentEngine.formatBytes(Int64(att.sizeBytes)))")
                                                    .font(PipiTokens.fontMonoSmall)
                                                    .foregroundStyle(PipiTokens.textMuted)
                                            }
                                            Spacer(minLength: 8)
                                            #if os(macOS)
                                            PipiActionButton(s.t("打开", "Open"), tone: .secondary, density: .desktopCompact) {
                                                NSWorkspace.shared.open(URL(fileURLWithPath: att.path))
                                            }
                                            PipiActionButton(s.t("访达显示", "Reveal"), tone: .ghost, density: .desktopCompact) {
                                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: att.path)])
                                            }
                                            #endif
                                        }
                                    }
                                    .padding(10)
                                    .background(PipiTokens.bgElevated)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                                            .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
                                }
                            }
                        }

                        if let approvalId = msg.approvalId,
                           let approval = conversation.approvals.first(where: { $0.id == approvalId }) {
                            PipiInlineApprovalCard(
                                approval: approval,
                                strings: s
                            ) { optionId in
                                Task { await store.resolveApproval(approval.id, optionId: optionId) }
                            }
                        }

                        if let summaryInfo = msg.summaryInfo, !isStreaming {
                            PipiSummaryEvidenceCard(summary: summaryInfo, strings: s)
                        }

                        if !isStreaming && !msg.content.isEmpty {
                            HStack(spacing: PipiTokens.spacing8) {
                                Button {
                                    triggerCopy(msg.content, messageId: msg.id)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: copiedMessageId == msg.id ? "checkmark" : "doc.on.doc")
                                            .contentTransition(.symbolEffect(.replace))
                                        Text(copiedMessageId == msg.id ? s.copied : s.copy)
                                    }
                                    .font(PipiTokens.fontMicro)
                                    .foregroundStyle(copiedMessageId == msg.id ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(PipiTokens.buttonGhostHoverBg)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.94))

                                if isLastAssistant && !store.isGeneratingReply {
                                    Button {
                                        Task { await store.regenerateLastReply() }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.clockwise")
                                            Text(s.regenerate)
                                        }
                                        .font(PipiTokens.fontMicro)
                                        .foregroundStyle(PipiTokens.textMuted)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(PipiTokens.buttonGhostHoverBg)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.94))
                                }
                            }
                            // Last assistant message actions stay visible; earlier messages fade in on hover + stay in context menu & VoiceOver actions
                            .opacity(isLastAssistant || isHovered || copiedMessageId == msg.id ? 1.0 : 0.0)
                            .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: isHovered)
                        }
                    }

                    Spacer(minLength: 8)
                }
                .padding(.top, 2)
                .onHover { hovering in
                    hoveredMessageId = hovering ? msg.id : nil
                }
                .contextMenu {
                    if !msg.content.isEmpty {
                        Button(s.copy) {
                            triggerCopy(msg.content, messageId: msg.id)
                        }
                    }
                    if isLastAssistant && !store.isGeneratingReply {
                        Button(s.regenerate) {
                            Task { await store.regenerateLastReply() }
                        }
                    }
                }
                .accessibilityAction(named: s.copy) {
                    if !msg.content.isEmpty {
                        triggerCopy(msg.content, messageId: msg.id)
                    }
                }
                .accessibilityAction(named: s.regenerate) {
                    if isLastAssistant && !store.isGeneratingReply {
                        Task { await store.regenerateLastReply() }
                    }
                }
            }
        }
    }

    // MARK: - Harmonized Workbench Composer

    private var composerStack: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            if store.voiceIsOverlayPresented || store.voiceSessionState != .idle {
                PipiMuseVoiceBarView(
                    store: store,
                    onInsertDictation: { dictated in
                        if draftMessage.isEmpty {
                            draftMessage = dictated
                        } else {
                            draftMessage += " " + dictated
                        }
                        isComposerFocused = true
                    },
                    onOpenVoiceSettings: {
                        onOpenSettings(.voice)
                    }
                )
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }

            if shouldShowSlashMenu {
                slashCommandPopover
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }

            composerExecutionNodeStrip

            composerDock
        }
        .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: shouldShowSlashMenu)
        .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: store.voiceIsOverlayPresented)
        .onChange(of: store.voicePendingDictationText) { _, newValue in
            guard let text = newValue, !text.isEmpty else { return }
            draftMessage = draftMessage.isEmpty ? text : "\(draftMessage) \(text)"
            store.voicePendingDictationText = nil
            isComposerFocused = true
        }
    }

    private var slashCommandPopover: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(filteredSlashCommands) { item in
                Button {
                    executeSlashCommand(item)
                } label: {
                    HStack(spacing: PipiTokens.spacing12) {
                        Image(systemName: item.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PipiTokens.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(PipiTokens.bgSurfaceHover)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(item.command)
                                    .font(PipiTokens.fontMonoSmall.weight(.semibold))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                Text(item.title)
                                    .font(PipiTokens.fontCaption.weight(.medium))
                                    .foregroundStyle(PipiTokens.textSecondary)
                            }
                            Text(item.subtitle)
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textMuted)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, PipiTokens.spacing12)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.99))
            }
        }
        .padding(6)
        .background(PipiTokens.composerSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.composerBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        .shadow(color: PipiTokens.composerShadow, radius: 14, y: 6)
    }

    private var composerDock: some View {
        let canSend = !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draftAttachments.isEmpty
        let shape = RoundedRectangle(cornerRadius: PipiTokens.radiusComposer, style: .continuous)

        return VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            if !draftAttachments.isEmpty || isDropTargeted {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PipiTokens.spacing8) {
                        ForEach(draftAttachments) { file in
                            HStack(spacing: 6) {
                                Image(systemName: file.iconName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(PipiTokens.textSecondary)
                                Text(file.name)
                                    .font(PipiTokens.fontMonoSmall)
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .lineLimit(1)
                                if !file.formattedSize.isEmpty {
                                    Text(file.formattedSize)
                                        .font(PipiTokens.fontMonoSmall)
                                        .foregroundStyle(PipiTokens.textMuted)
                                }
                                Button {
                                    withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                                        draftAttachments.removeAll { $0.id == file.id }
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8.5, weight: .bold))
                                        .foregroundStyle(PipiTokens.textMuted)
                                        .frame(width: 16, height: 16)
                                        .background(PipiTokens.buttonGhostHoverBg)
                                        .clipShape(Circle())
                                }
                                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.90))
                                .accessibilityLabel(s.t("移除附件 \(file.name)", "Remove \(file.name)"))
                            }
                            .padding(.leading, 9)
                            .padding(.trailing, 5)
                            .frame(height: 26)
                            .background(PipiTokens.bgSurface)
                            .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                            .clipShape(Capsule())
                        }

                        if isDropTargeted {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.down.doc")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(s.dropFilesHint)
                                    .font(PipiTokens.fontMicro)
                            }
                            .foregroundStyle(PipiTokens.textPrimary)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(PipiTokens.bgSurfaceHover)
                            .clipShape(Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.bottom, 2)
                .transition(.opacity)
            }

            PipiAutoGrowingComposerEditor(
                text: $draftMessage,
                placeholder: s.chatPlaceholder,
                minHeight: 44,
                maxHeight: 220,
                focusRequestToken: composerFocusToken,
                onFocusChanged: { focused in
                    isNativeComposerFocused = focused
                },
                onSubmit: {
                    submitDraft()
                }
            )
            .padding(.top, 2)
            .onChange(of: isComposerFocused) { _, newValue in
                if newValue {
                    composerFocusToken += 1
                }
            }

            // Clean Minimal Bottom Row: + Menu (includes Engine/Model), Permission Picker, Voice, Send/Stop
            HStack(spacing: 6) {
                composerPlusMenu

                permissionTierPicker

                Spacer(minLength: 6)

                Button {
                    if store.isVoiceCallActive {
                        store.endVoiceCall()
                    } else {
                        Task { await store.startVoiceCall(with: store.activePersona.id) }
                    }
                } label: {
                    Image(systemName: store.isVoiceCallActive ? "phone.down.fill" : "phone.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(store.isVoiceCallActive ? PipiTokens.textInverse : PipiTokens.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(store.isVoiceCallActive ? PipiTokens.stateSuccess : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                .help(store.isVoiceCallActive ? s.t("结束语音通话", "End Voice Call") : s.t("语音通话", "Voice Call"))
                .accessibilityLabel(s.t("语音通话", "Voice Call"))

                Button {
                    if store.voiceIsOverlayPresented && store.voiceSessionState == .idle && !store.isVoiceCallActive {
                        store.voiceIsOverlayPresented = false
                    } else if store.voiceSessionState == .listening || store.voiceSessionState == .transcribing {
                        Task { await store.stopVoiceCapture(commitTranscript: true) }
                    } else {
                        store.voiceActiveMode = .dictation
                        store.voiceIsOverlayPresented = true
                    }
                } label: {
                    Image(systemName: store.voiceSessionState == .idle ? "waveform" : "waveform.circle.fill")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(store.voiceIsOverlayPresented && !store.isVoiceCallActive ? PipiTokens.soulPrimary : PipiTokens.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(store.voiceIsOverlayPresented && !store.isVoiceCallActive ? PipiTokens.bgSurfaceHover : Color.clear)
                        .clipShape(Circle())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                .help(s.voiceDictationAction)
                .accessibilityLabel(s.voiceDictationAction)

                if store.isGeneratingReply {
                    Button {
                        store.stopGenerating()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(PipiTokens.textInverse)
                            .frame(width: 32, height: 32)
                            .background(PipiTokens.stateError)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                    .help(s.stop)
                    .accessibilityLabel(s.stop)
                } else {
                    Button(action: submitDraft) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(canSend ? PipiTokens.textInverse : PipiTokens.textMuted)
                            .frame(width: 32, height: 32)
                            .background(canSend ? PipiTokens.soulPrimary : PipiTokens.bgSurfaceHover)
                            .clipShape(Circle())
                            .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: canSend)
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                    .disabled(!canSend)
                    .help(s.send)
                    .accessibilityLabel(s.send)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            ZStack {
                if !reduceTransparency {
                    shape.fill(.ultraThinMaterial)
                }
                shape.fill(PipiTokens.composerSurface.opacity(reduceTransparency ? 1.0 : 0.92))
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.4)
                    )
                )
            }
        )
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.45)
                ),
                lineWidth: 0.85
            )
        )
        .overlay(
            shape.stroke(
                isDropTargeted ? PipiTokens.soulPrimary : ((isComposerFocused || isNativeComposerFocused) ? PipiTokens.composerBorderFocused : PipiTokens.composerBorder),
                lineWidth: isDropTargeted ? 1.5 : 1
            )
        )
        .clipShape(shape)
        .shadow(
            color: Color.black.opacity(0.06),
            radius: 2,
            y: 1
        )
        .shadow(
            color: PipiTokens.composerShadow,
            radius: (isComposerFocused || isNativeComposerFocused) ? 20 : 12,
            y: (isComposerFocused || isNativeComposerFocused) ? 7 : 4
        )
        .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: isComposerFocused || isNativeComposerFocused)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDroppedFiles(providers)
        }
    }

    private var composerPlusMenu: some View {
        let isHovered = hoveredToolbarChip == "plus"
        return Menu {
            Button {
                pickAttachmentFiles()
            } label: {
                Label(s.attachFiles, systemImage: "paperclip")
            }

            Divider()

            let promptCommands = slashCommandCatalog.filter { ["plan", "review", "summarize"].contains($0.id) }
            ForEach(promptCommands) { item in
                Button {
                    executeSlashCommand(item)
                } label: {
                    Label("\(item.command) · \(item.title)", systemImage: item.icon)
                }
            }

            Divider()

            Menu {
                Button {
                    store.overrideExecutionTarget = nil
                } label: {
                    HStack {
                        Text(s.t("默认 PiPi（自动路由）", "Default PiPi (Auto)"))
                        if store.overrideExecutionTarget == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                if !store.readyLLMProviders.isEmpty {
                    Section(s.cloudAndLocalLLMs) {
                        ForEach(store.readyLLMProviders) { cfg in
                            Button {
                                store.overrideExecutionTarget = .llm(providerId: cfg.id)
                            } label: {
                                HStack {
                                    Text("\(cfg.name) · \(cfg.modelId)")
                                    if store.overrideExecutionTarget == .llm(providerId: cfg.id) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                if !store.usableLocalAgents.isEmpty {
                    Section(s.t("本机外接 Agent", "Local External Agents")) {
                        ForEach(store.usableLocalAgents) { ag in
                            Button {
                                let cmdPrefix: String
                                switch ag.kind {
                                case .claudeCode: cmdPrefix = "/claude "
                                case .codex: cmdPrefix = "/codex "
                                case .opencode: cmdPrefix = "/opencode "
                                }
                                if !draftMessage.hasPrefix(cmdPrefix) {
                                    draftMessage = cmdPrefix + draftMessage
                                }
                                isComposerFocused = true
                            } label: {
                                Label(ag.kind.displayName, systemImage: "terminal")
                            }
                        }
                    }
                }

                Divider()
                Button(s.engineSettingsShort) {
                    onOpenSettings(.aiEngine)
                }
            } label: {
                Label(
                    s.t("执行引擎与模型：\(store.overrideExecutionTarget == nil ? "PiPi" : store.activeEngineDisplayLabel())", "Engine: \(store.overrideExecutionTarget == nil ? "PiPi" : store.activeEngineDisplayLabel())"),
                    systemImage: "cpu"
                )
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(isHovered ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                        .fill(isHovered ? PipiTokens.buttonGhostHoverBg : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
        }
        .pipiPlainMenu()
        .fixedSize()
        .onHover { hoveredToolbarChip = $0 ? "plus" : (hoveredToolbarChip == "plus" ? nil : hoveredToolbarChip) }
        .help("\(s.attachFiles) · \(s.slashCommands)")
        .accessibilityLabel(s.attachFiles)
    }

    private var permissionTierPicker: some View {
        let currentTier = store.effectivePermissionTier()
        let isHovered = hoveredToolbarChip == "permission"
        return Menu {
            ForEach(PipiPermissionTier.allCases) { tier in
                Button {
                    store.setEffectivePermissionTier(tier)
                } label: {
                    HStack {
                        Image(systemName: tier.iconName)
                        Text(tier.label(lang))
                        if currentTier == tier {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: currentTier.iconName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isHovered ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                Text(currentTier.label(lang))
                    .font(PipiTokens.fontCaption.weight(.medium))
                    .foregroundStyle(isHovered ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(PipiTokens.textMuted)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .fill(isHovered ? PipiTokens.buttonGhostHoverBg : Color.clear)
            )
            .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: isHovered)
        }
        .pipiPlainMenu()
        .fixedSize()
        .onHover { hoveredToolbarChip = $0 ? "permission" : (hoveredToolbarChip == "permission" ? nil : hoveredToolbarChip) }
        .help(currentTier.description(lang))
    }

    private var composerEnginePicker: some View {
        let isHovered = hoveredToolbarChip == "engine"
        return Menu {
            Button {
                store.overrideExecutionTarget = nil
            } label: {
                HStack {
                    Text(s.autoRouteEngine)
                    if store.overrideExecutionTarget == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if !store.readyLLMProviders.isEmpty {
                Section(s.cloudAndLocalLLMs) {
                    ForEach(store.readyLLMProviders) { cfg in
                        Button {
                            store.overrideExecutionTarget = .llm(providerId: cfg.id)
                        } label: {
                            HStack {
                                Text("\(cfg.name) · \(cfg.modelId)")
                                if store.overrideExecutionTarget == .llm(providerId: cfg.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            if !store.usableLocalAgents.isEmpty {
                Section(s.t("外部协作 Agent（由 PiPi 按需调用）", "External Sub-Agents (Invoke via PiPi)")) {
                    ForEach(store.usableLocalAgents) { ag in
                        Button {
                            let cmdPrefix: String
                            switch ag.kind {
                            case .claudeCode: cmdPrefix = "/claude "
                            case .codex: cmdPrefix = "/codex "
                            case .opencode: cmdPrefix = "/opencode "
                            }
                            if !draftMessage.hasPrefix(cmdPrefix) {
                                draftMessage = cmdPrefix + draftMessage
                            }
                            isComposerFocused = true
                        } label: {
                            Label(
                                s.t("按需调用 \(ag.kind.displayName)", "Invoke \(ag.kind.displayName)"),
                                systemImage: "terminal"
                            )
                        }
                    }
                }
            }

            Divider()

            Button(s.engineSettingsShort) {
                onOpenSettings(.aiEngine)
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(store.hasConfiguredEngine ? PipiTokens.stateSuccess : PipiTokens.stateWarning)
                    .frame(width: 6.5, height: 6.5)
                Text(store.hasConfiguredEngine ? store.activeEngineDisplayLabel() : s.configureNow)
                    .font(PipiTokens.fontCaption.weight(.medium))
                    .foregroundStyle(store.hasConfiguredEngine ? (isHovered ? PipiTokens.textPrimary : PipiTokens.textSecondary) : PipiTokens.stateWarning)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(PipiTokens.textMuted)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .fill(isHovered ? PipiTokens.buttonGhostHoverBg : Color.clear)
            )
            .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: isHovered)
        }
        .pipiPlainMenu()
        .fixedSize()
        .onHover { hoveredToolbarChip = $0 ? "engine" : (hoveredToolbarChip == "engine" ? nil : hoveredToolbarChip) }
    }

    // MARK: - Actions & Helpers

    private func executeSlashCommand(_ item: SlashCommandItem) {
        showSlashPalette = false
        switch item.id {
        case "new":
            draftMessage = ""
            draftAttachments = []
            _ = store.createConversation(projectId: store.activeConversation?.projectId)
            isComposerFocused = true
        case "clear":
            draftMessage = ""
            draftAttachments = []
            store.clearActiveConversation()
            isComposerFocused = true
        case "delegate":
            draftMessage = "/delegate "
            isComposerFocused = true
        case "wiki":
            draftMessage = ""
            destination = .knowledge
        case "compact":
            draftMessage = ""
            if let convId = store.activeConversationId {
                Task { _ = await store.compactConversation(id: convId) }
            }
        case "voice":
            draftMessage = ""
            store.voiceIsOverlayPresented = true
            store.voiceActiveMode = store.voiceConfig.defaultMode
        case "screenshot":
            draftMessage = "/screenshot"
            submitDraft()
        case "record":
            draftMessage = "/record 5"
            submitDraft()
        case "sms":
            draftMessage = "/sms"
            submitDraft()
        case "mail":
            draftMessage = "/mail"
            submitDraft()
        case "build":
            draftMessage = "/build "
            isComposerFocused = true
        case "sendfile":
            draftMessage = "/sendfile "
            isComposerFocused = true
        case "voiceclip":
            draftMessage = "/voiceclip "
            isComposerFocused = true
        case "computer":
            draftMessage = ""
            store.computerUseBarPresented.toggle()
            Task { _ = await store.refreshComputerUseEnvironment() }
        case "settings":
            draftMessage = ""
            onOpenSettings(.aiEngine)
        case "plan":
            draftMessage = s.t("请先帮我制定清晰的执行计划（列出步骤与权衡），再给出实现：", "First outline a clear step-by-step plan and trade-offs before implementing: ")
            isComposerFocused = true
        case "review":
            draftMessage = s.t("请帮我做一次严格的代码审查，重点关注潜在 Bug、边界条件和可维护性：", "Please perform a thorough code review focusing on bugs, edge cases, and maintainability: ")
            isComposerFocused = true
        case "summarize":
            draftMessage = s.t("请用结构化要点提炼以下内容的核心结论与行动项：", "Summarize the key takeaways and action items concisely: ")
            isComposerFocused = true
        default:
            break
        }
    }

    private func submitDraft() {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == "/new" {
            executeSlashCommand(slashCommandCatalog.first { $0.id == "new" }!)
            return
        }
        if text == "/clear" {
            executeSlashCommand(slashCommandCatalog.first { $0.id == "clear" }!)
            return
        }
        if text.hasPrefix("/delegate ") {
            let goal = String(text.dropFirst("/delegate ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !goal.isEmpty {
                let targetConvId = store.activeConversationId ?? store.createConversation(projectId: store.activeConversation?.projectId).id
                _ = store.spawnAlterEgoTask(
                    sessionId: targetConvId,
                    title: String(goal.prefix(36)),
                    goal: goal
                )
                draftMessage = ""
                showSlashPalette = false
                return
            }
        }
        if text == "/wiki" {
            executeSlashCommand(slashCommandCatalog.first { $0.id == "wiki" }!)
            return
        }
        if text == "/compact" {
            executeSlashCommand(slashCommandCatalog.first { $0.id == "compact" }!)
            return
        }
        if text == "/settings" {
            executeSlashCommand(slashCommandCatalog.first { $0.id == "settings" }!)
            return
        }
        guard !text.isEmpty || !draftAttachments.isEmpty else { return }
        let filesToSend = draftAttachments
        draftMessage = ""
        draftAttachments = []
        showSlashPalette = false
        if let targetHostId = selectedExecutionNodeHostId,
           let targetDev = store.enrolledRemoteDevices.first(where: { $0.hostId == targetHostId && $0.isOnline }) {
            let targetHarness = selectedExecutionNodeHarness
            let targetModel = selectedExecutionNodeModel
            let targetMode = selectedExecutionNodeMode
            Task {
                await store.sendDirectToRemoteNode(
                    device: targetDev,
                    harness: targetHarness,
                    model: targetModel.isEmpty ? nil : targetModel,
                    mode: targetMode,
                    prompt: text
                )
            }
        } else {
            Task { await store.sendPersonalMessage(text, attachments: filesToSend) }
        }
    }

    private var composerExecutionNodeStrip: some View {
        let remotes = store.enrolledRemoteDevices
        let activeRemote = remotes.first(where: { $0.hostId == selectedExecutionNodeHostId })
        let isRemoteSelected = activeRemote != nil

        return HStack(spacing: 8) {
            HStack(spacing: 2) {
                // Local Primary Pill
                Button {
                    selectedExecutionNodeHostId = nil
                    selectedExecutionNodeHarness = nil
                    selectedExecutionNodeModel = ""
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(s.t("本地", "Local"))
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(!isRemoteSelected ? PipiTokens.textInverse : PipiTokens.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(!isRemoteSelected ? PipiTokens.textPrimary : Color.clear)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Remote Node Pill + Popover for Node / Harness / Model selection
                Button {
                    if !isRemoteSelected, let firstOnline = remotes.first(where: \.isOnline) {
                        selectedExecutionNodeHostId = firstOnline.hostId
                        selectedExecutionNodeHarness = firstOnline.capabilities.first
                        selectedExecutionNodeModel = ""
                        Task { await loadRemoteHarnesses(for: firstOnline) }
                    } else if let cur = activeRemote {
                        Task { await loadRemoteHarnesses(for: cur) }
                    }
                    showRemoteNodePickerPopover.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isRemoteSelected ? PipiTokens.stateSuccess : (remotes.contains(where: \.isOnline) ? PipiTokens.stateSuccess.opacity(0.75) : PipiTokens.textMuted.opacity(0.45)))
                            .frame(width: 6, height: 6)
                        Text(activeRemote.map { dev in
                            let h = selectedExecutionNodeHarness ?? dev.capabilities.first
                            return h != nil ? "\(dev.name) · \(h!)" : dev.name
                        } ?? s.t("远程节点", "Remote Node"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .opacity(0.7)
                    }
                    .foregroundStyle(isRemoteSelected ? PipiTokens.textInverse : PipiTokens.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(isRemoteSelected ? PipiTokens.textPrimary : Color.clear)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showRemoteNodePickerPopover, arrowEdge: .top) {
                    remoteNodeSelectionPopover
                }
            }
            .padding(2)
            .background(PipiTokens.bgSurface)
            .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
            .clipShape(Capsule())

            if isRemoteSelected, !selectedExecutionNodeModel.isEmpty, !selectedExecutionNodeModel.hasPrefix("(") {
                Text(selectedExecutionNodeModel)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(PipiTokens.textMuted)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(PipiTokens.bgSurface)
                    .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                    .clipShape(Capsule())
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var remoteNodeSelectionPopover: some View {
        let remotes = store.enrolledRemoteDevices
        let activeRemote = remotes.first(where: { $0.hostId == selectedExecutionNodeHostId })
        let harnesses = activeRemote.flatMap { remoteNodeHarnessesCache[$0.hostId] } ?? []
        let activeHarness = harnesses.first(where: { $0.id == selectedExecutionNodeHarness || $0.name == selectedExecutionNodeHarness }) ?? harnesses.first

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(s.t("选择远程节点与 Agent Harness", "Remote Node & Harness"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                Spacer()
                Button(s.t("设备看板", "Nodes")) {
                    showRemoteNodePickerPopover = false
                    destination = .deviceNodes
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(PipiTokens.textSecondary)
            }

            if remotes.isEmpty {
                Text(s.t("当前账号下暂无远程节点。可在「我的设备节点」复制接入命令纳管 Linux / 远程开发机。", "No remote nodes enrolled yet. Copy the install command in Device Nodes."))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // 1. Node List
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.t("目标节点", "Target Node"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(PipiTokens.textMuted)
                    ForEach(remotes) { dev in
                        let isSelected = dev.hostId == selectedExecutionNodeHostId
                        Button {
                            selectedExecutionNodeHostId = dev.hostId
                            selectedExecutionNodeHarness = dev.capabilities.first
                            selectedExecutionNodeModel = ""
                            Task { await loadRemoteHarnesses(for: dev) }
                        } label: {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(dev.isOnline ? PipiTokens.stateSuccess : PipiTokens.textMuted.opacity(0.4))
                                    .frame(width: 6, height: 6)
                                Text(dev.name)
                                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(PipiTokens.textPrimary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(isSelected ? PipiTokens.bgSurfaceHover : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!dev.isOnline)
                        .opacity(dev.isOnline ? 1.0 : 0.45)
                    }
                }

                // 2. Harness Picker
                if let dev = activeRemote {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(s.t("Agent Harness", "Agent Harness"))
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(PipiTokens.textMuted)
                            Spacer()
                            if isLoadingRemoteHarnesses {
                                ProgressView().controlSize(.mini)
                            }
                        }

                        if harnesses.isEmpty && dev.capabilities.isEmpty {
                            Text(s.t("该节点未检测到外接 Harness", "No CLI harness detected on this node"))
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(PipiTokens.textMuted)
                        } else {
                            let displayList: [(id: String, name: String)] = harnesses.isEmpty
                                ? dev.capabilities.map { ($0, $0) }
                                : harnesses.map { ($0.id, $0.name) }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], spacing: 6) {
                                ForEach(displayList, id: \.id) { item in
                                    let isAct = selectedExecutionNodeHarness == item.id || selectedExecutionNodeHarness == item.name
                                    Button {
                                        selectedExecutionNodeHarness = item.id
                                        if let match = harnesses.first(where: { $0.id == item.id }) {
                                            selectedExecutionNodeModel = match.defaultModel
                                        }
                                    } label: {
                                        Text(item.name)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .foregroundStyle(isAct ? PipiTokens.textInverse : PipiTokens.textPrimary)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 26)
                                            .background(isAct ? PipiTokens.textPrimary : PipiTokens.bgCanvas)
                                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(isAct ? Color.clear : PipiTokens.borderSubtle, lineWidth: 1))
                                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // 3. Model (from Remote Harness Config) & Mode Picker
                    if let ah = activeHarness, !ah.models.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(s.t("模型（读取自远端配置）", "Model (from Remote Config)"))
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(PipiTokens.textMuted)
                            Picker("", selection: $selectedExecutionNodeModel) {
                                ForEach(ah.models, id: \.self) { m in
                                    Text(m).tag(m)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(s.t("执行模式", "Execution Mode"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(PipiTokens.textMuted)
                        Picker("", selection: $selectedExecutionNodeMode) {
                            Text(s.t("ACP 协议（推荐）", "ACP (Recommended)")).tag("acp")
                            Text(s.t("TUI 终端 PTY", "TUI PTY")).tag("tui")
                            Text(s.t("CLI 无头", "CLI Headless")).tag("cli")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 310)
    }

    private func loadRemoteHarnesses(for device: PipiAccountDevice) async {
        isLoadingRemoteHarnesses = true
        defer { isLoadingRemoteHarnesses = false }
        let fetched = await store.fetchRemoteNodeHarnesses(device: device)
        remoteNodeHarnessesCache[device.hostId] = fetched
        if let first = fetched.first {
            if selectedExecutionNodeHarness == nil || !fetched.contains(where: { $0.id == selectedExecutionNodeHarness || $0.name == selectedExecutionNodeHarness }) {
                selectedExecutionNodeHarness = first.id
            }
            if let current = fetched.first(where: { $0.id == selectedExecutionNodeHarness || $0.name == selectedExecutionNodeHarness }) {
                selectedExecutionNodeModel = current.defaultModel.isEmpty ? (current.models.first ?? "") : current.defaultModel
            }
        }
    }

    private func pickAttachmentFiles() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            let added = panel.urls.map { PipiChatAttachment.fromFileURL($0) }
            withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                for item in added where !draftAttachments.contains(where: { $0.path == item.path }) {
                    draftAttachments.append(item)
                }
            }
            isComposerFocused = true
        }
        #endif
    }

    private func chooseWorkspaceFolderInPlace() {
        #if os(macOS)
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
        #endif
    }

    private func handleDroppedFiles(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let resolvedUrl: URL? = {
                    if let data = item as? Data {
                        return URL(dataRepresentation: data, relativeTo: nil)
                    }
                    if let url = item as? URL {
                        return url
                    }
                    return nil
                }()
                guard let url = resolvedUrl, url.isFileURL else { return }
                let attachment = PipiChatAttachment.fromFileURL(url)
                Task { @MainActor in
                    withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                        if !draftAttachments.contains(where: { $0.path == attachment.path }) {
                            draftAttachments.append(attachment)
                        }
                    }
                }
            }
        }
        return accepted
    }

    private func triggerCopy(_ text: String, messageId: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
        withAnimation(PipiMotion.adaptive(PipiMotion.tactile, reduceMotion: reduceMotion)) {
            copiedMessageId = messageId
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                if copiedMessageId == messageId { copiedMessageId = nil }
            }
        }
    }
}
