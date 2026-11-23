import Foundation

// MARK: - App Language Preference (Auto-Adapts to System Language)

public enum PipiAppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case zhHans = "zh-Hans"
    case en

    public var id: String { rawValue }

    /// Resolves `.system` against `Locale.preferredLanguages` (defaults to `.en` unless Chinese).
    public var resolved: PipiResolvedLanguage {
        switch self {
        case .zhHans:
            return .zhHans
        case .en:
            return .en
        case .system:
            return Self.detectSystemLanguage()
        }
    }

    public static func detectSystemLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> PipiResolvedLanguage {
        for raw in preferredLanguages {
            let lower = raw.lowercased()
            if lower.hasPrefix("zh") {
                return .zhHans
            }
            if lower.hasPrefix("en") {
                return .en
            }
        }
        return .en
    }

    public func displayName(in lang: PipiResolvedLanguage) -> String {
        switch self {
        case .system:
            return lang == .zhHans ? "跟随系统" : "System Default"
        case .zhHans:
            return "简体中文"
        case .en:
            return "English"
        }
    }
}

public enum PipiResolvedLanguage: String, Sendable, Equatable {
    case zhHans = "zh-Hans"
    case en
}

// MARK: - Centralized Commercial Localization Catalog

public struct PipiStrings: Sendable {
    public let lang: PipiResolvedLanguage

    public init(_ preference: PipiAppLanguage) {
        self.lang = preference.resolved
    }

    public init(resolved: PipiResolvedLanguage) {
        self.lang = resolved
    }

    public var isChinese: Bool { lang == .zhHans }

    public func t(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }

    // MARK: Brand & Navigation
    public var appName: String { "PiPiBot" }
    public var appTagline: String {
        t("个人智能体工作台",
          "Personal AI Agent Workspace")
    }
    public var newChat: String { t("新对话", "New Chat") }
    public var myBots: String { t("智能体", "Agents") }
    public var recentChats: String { t("最近对话", "Recent Chats") }
    public var newBot: String { t("新建智能体", "New Agent") }
    public var tasksAndApprovals: String { t("任务与审批", "Tasks & Approvals") }
    public var settings: String { t("设置", "Settings") }
    public var quickBar: String { t("快捷浮窗", "Quick Bar") }
    public var quickBarShortcut: String { t("快捷浮窗 (⌥Space)", "Quick Bar (⌥Space)") }
    public var openPipiBot: String { t("打开 PiPiBot", "Open PiPiBot") }
    public var close: String { t("关闭", "Close") }
    public var cancel: String { t("取消", "Cancel") }
    public var save: String { t("保存", "Save") }
    public var delete: String { t("删除", "Delete") }
    public var edit: String { t("编辑", "Edit") }
    public var done: String { t("完成", "Done") }
    public var back: String { t("上一步", "Back") }
    public var next: String { t("下一步", "Next") }
    public var skipForNow: String { t("稍后配置，先体验", "Skip for now") }
    public var refresh: String { t("刷新", "Refresh") }
    public var copy: String { t("复制", "Copy") }
    public var copied: String { t("已复制", "Copied") }
    public var regenerate: String { t("重新生成", "Regenerate") }
    public var stop: String { t("停止", "Stop") }
    public var send: String { t("发送", "Send") }
    public var enabled: String { t("已启用", "Enabled") }
    public var disabled: String { t("未启用", "Disabled") }

    // MARK: Onboarding
    public var onboardingWelcomeTitle: String { t("欢迎使用 PiPiBot", "Welcome to PiPiBot") }
    public var onboardingWelcomeSubtitle: String {
        t("连接云端或本地模型及命令行工具，在统一工作台中管理个人助手与任务。",
          "Connect cloud or local models and CLI tools to manage assistants and workflows.")
    }
    public var onboardingFeature1Title: String { t("接入多类模型", "Bring Your Own Model") }
    public var onboardingFeature1Desc: String {
        t("支持 OpenAI、Anthropic、Gemini、DeepSeek、Ollama 及兼容接口，配置仅保存于本机。",
          "Supports OpenAI, Anthropic, Gemini, DeepSeek, Ollama, and compatible APIs stored locally.")
    }
    public var onboardingFeature2Title: String { t("调用本地工具", "Connect Local Tools") }
    public var onboardingFeature2Desc: String {
        t("自动检测本机已安装的 Claude Code、Codex 与 OpenCode，复用已有工作区配置。",
          "Detects installed Claude Code, Codex, and OpenCode CLIs directly in your workspace.")
    }
    public var onboardingFeature3Title: String { t("多助手协同", "Multi-Agent Collaboration") }
    public var onboardingFeature3Desc: String {
        t("按场景配置不同助手，支持单聊与多助手协作群。",
          "Configure specialized assistants for 1:1 conversations or multi-agent groups.")
    }
    public var onboardingGetStarted: String { t("开始配置", "Get Started") }
    public var onboardingStepConnectTitle: String { t("连接 AI 引擎", "Connect AI Engine") }
    public var onboardingStepConnectSubtitle: String {
        t("配置云端或本地模型接口，或启用本机已安装的命令行工具。",
          "Configure a model API or enable installed local CLI tools.")
    }
    public var onboardingTabLLM: String { t("配置模型接口", "Model API") }
    public var onboardingTabLocalAgent: String { t("本地工具", "Local Tools") }
    public var onboardingStepPersonaTitle: String { t("选择默认助手", "Choose Default Assistant") }
    public var onboardingStepPersonaSubtitle: String {
        t("后续可随时切换助手或调整底层模型。",
          "You can switch assistants or change engines anytime.")
    }
    public var onboardingStartChatting: String { t("进入对话", "Start Chatting") }
    public var onboardingReopenGuide: String { t("重新打开新手引导", "Re-run Setup Guide") }

    // MARK: Engine / Model Configuration
    public var providerPreset: String { t("模型服务商", "Provider") }
    public var apiKeyLabel: String { t("API Key", "API Key") }
    public var apiKeyPlaceholder: String { t("粘贴你的 API Key（Ollama 本地模型可留空）", "Paste your API key (optional for local Ollama)") }
    public var baseUrlLabel: String { t("接口地址 (Base URL)", "Base URL") }
    public var modelNameLabel: String { t("模型名称", "Model") }
    public var displayNameLabel: String { t("显示名称", "Display Name") }
    public var testConnection: String { t("测试连接", "Test Connection") }
    public var testingConnection: String { t("正在测试...", "Testing...") }
    public var saveAndUse: String { t("保存并设为默认", "Save & Set as Default") }
    public var addModelProvider: String { t("添加模型配置", "Add Model Provider") }
    public var defaultEngine: String { t("默认", "Default") }
    public var setAsDefault: String { t("设为默认", "Set Default") }
    public var notConfiguredTitle: String { t("尚未配置大模型或本地 Agent", "No LLM or Local Agent Configured") }
    public var notConfiguredBanner: String {
        t("请先在设置中配置一个大模型 API，或启用本机已安装的本地 Agent，即可开始真实对话。",
          "Connect an LLM API key or enable an installed local agent in Settings to start chatting.")
    }
    public var configureNow: String { t("立即配置", "Configure Now") }
    public var engineStatusUnconfigured: String { t("未配置驱动模型", "No Model Configured") }
    public var autoRouteEngine: String { t("PiPi（自动选择模型）", "PiPi (Auto Model)") }
    public var cloudAndLocalLLMs: String { t("云端与自定义模型", "Cloud & Custom Models") }
    public var localAgents: String { t("外部协作 Agent（PiPi 按需调用）", "External Sub-Agents (On-Demand)") }
    public var rescanAgents: String { t("重新检测", "Re-scan") }
    public var agentStatusReady: String { t("已就绪", "Ready") }
    public var agentStatusNeedsLogin: String { t("需在终端登录", "Sign in via CLI") }
    public var agentStatusNotInstalled: String { t("未安装", "Not Installed") }
    public var workspaceDirectory: String { t("默认工作目录", "Default Working Directory") }
    public var chooseFolder: String { t("选择目录", "Choose Folder") }
    public var localAgentHint: String {
        t("启用后，PiPi 内置引擎在处理代码、文件或终端任务时将按需调用这些外部 Agent，不替代 PiPi 作为主引擎。",
          "When enabled, PiPi invokes these external CLI agents on demand for coding/terminal tasks without replacing PiPi.")
    }

    // MARK: Chat Experience
    public var chatPlaceholder: String { t("输入消息（Enter 发送，/ 查看指令）", "Type a message (Enter to send, / for commands)") }
    public var chatPlaceholderCompact: String { t("输入问题或指令", "Type a prompt...") }
    public var youLabel: String { t("我", "You") }
    public var thinkingStatus: String { t("正在思考...", "Thinking...") }
    public func runningAgentStatus(_ name: String) -> String {
        t("正在调用 \(name)...", "Running \(name)...")
    }
    public var readyStatus: String { t("在线就绪", "Ready") }
    public var queuedStatus: String { t("排队中...", "Queued...") }
    public var clearConversation: String { t("清空当前对话", "Clear Chat") }
    public var noChatsYet: String { t("暂无历史对话", "No conversations yet") }
    public var startWithPrompt: String { t("试试这样开始", "Try asking") }
    public var enginePickerTitle: String { t("选择本次对话引擎", "Select Engine") }

    // MARK: Personas
    public var personaName: String { t("智能体名称", "Agent Name") }
    public var personaRole: String { t("角色简介", "Role Summary") }
    public var personaSystemPrompt: String { t("系统提示词 (人设指令)", "System Prompt (Instructions)") }
    public var personaAccent: String { t("主题色", "Accent Color") }
    public var personaShape: String { t("形象形态", "Avatar Form") }
    public var personaDefaultEngine: String { t("驱动大模型", "Backing Model") }
    public var createBotTitle: String { t("创建新智能体", "Create Agent") }
    public var createBotSubtitle: String { t("为不同场景定制专属的性格、指令与默认模型", "Customize personality, instructions, and preferred engine for any workflow") }
    public var editBotTitle: String { t("编辑智能体", "Edit Agent") }
    public var builtInBadge: String { t("内置", "Built-in") }
    public var customBadge: String { t("自定义", "Custom") }

    // MARK: Tasks & Approvals
    public var tasksTitle: String { t("自动任务", "Autonomous Tasks") }
    public var tasksSubtitle: String { t("让 PiPiBot 在后台持续跟进目标，仅在关键节点向你确认", "Let PiPiBot track ongoing goals and notify you only when approval is needed") }
    public var newTask: String { t("新建任务", "New Task") }
    public var approvalsTitle: String { t("待你确认", "Pending Approvals") }
    public var approvalsEmptyTitle: String { t("暂无待确认事项", "No Pending Items") }
    public var approvalsEmptyMessage: String {
        t("当前无待处理的权限审批或确认请求。",
          "No pending permission approvals or decisions.")
    }
    public var runCheck: String { t("立即检查", "Run Check") }
    public var taskTitleField: String { t("任务名称", "Task Title") }
    public var taskGoalField: String { t("目标与验收标准", "Goal & Success Criteria") }
    public var taskDomainField: String { t("分类", "Category") }
    public var approve: String { t("批准", "Approve") }
    public var reject: String { t("暂缓", "Defer") }

    // MARK: Quick Bar
    public var quickBarTitle: String { t("PiPiBot 快捷浮窗", "PiPiBot Quick Bar") }
    public var quickBarInputPlaceholder: String { t("输入问题或指令，按 Enter 发送", "Type a prompt and press Enter") }
    public var detectedContext: String { t("当前上下文", "Active Context") }

    // MARK: Settings Sections
    public var settingsGeneral: String { t("通用", "General") }
    public var settingsAIEngine: String { t("模型与引擎", "Models & Engines") }
    public var settingsSkillsMCP: String { t("技能与 MCP", "Skills & MCP") }
    public var settingsRemoteAccess: String { t("远程互联", "Remote Access") }
    public var settingsPermissionsControl: String { t("权限与电脑操控", "Permissions & Control") }
    public var settingsRuntimeSync: String { t("远程互联", "Remote Access") }
    public var settingsHelp: String { t("帮助说明", "Help") }
    public var aboutTitle: String { t("关于 PiPiBot", "About PiPiBot") }
    public var settingsModels: String { t("大模型配置", "LLM Models") }
    public var settingsLocalAgents: String { t("本地 Agent", "Local Agents") }
    public var settingsPersonas: String { t("Bot 人设", "Bot Personas") }
    public var settingsMemory: String { t("记忆与数据", "Memory & Data") }
    public var settingsSync: String { t("多端同步", "Remote Sync") }

    // MARK: Archive, Projects, Inspector, Routines & Streaming Polish
    public var archiveChat: String { t("归档", "Archive") }
    public var unarchiveChat: String { t("取消归档", "Unarchive") }
    public var archivedSection: String { t("已归档", "Archived") }
    public var projectsSection: String { t("项目", "Projects") }
    public var newProject: String { t("新建项目", "New Project") }
    public var editProject: String { t("编辑项目", "Edit Project") }
    public var projectNameLabel: String { t("项目名称", "Project Name") }
    public var projectNamePlaceholder: String { t("例如：iOS 客户端重构 / 论文写作", "e.g., iOS App Refactor / Research Paper") }
    public var projectFolderLabel: String { t("关联工作目录（可选）", "Linked Workspace Folder (Optional)") }
    public var projectInstructionsLabel: String { t("项目专属上下文 / 指令（可选）", "Project Instructions & Context (Optional)") }
    public var moveToProject: String { t("移入项目", "Move to Project") }
    public var removeFromProject: String { t("移出项目", "Remove from Project") }
    public var newChatInProject: String { t("在项目中新建对话", "New Chat in Project") }
    public var renameChat: String { t("重命名", "Rename") }
    public var noProjectsYet: String { t("点击 + 创建项目分组", "Click + to organize chats by project") }
    public var inspectorTitle: String { t("助手与会话详情", "Assistant & Session") }
    public var toggleInspector: String { t("展开或收起助手详情", "Toggle Assistant Inspector") }
    public var routinesTitle: String { t("例行任务", "Routines") }
    public var addRoutine: String { t("新建例行任务", "New Routine") }
    public var routineTitlePlaceholder: String { t("例如：每日工作晨报 / 周五仓库巡检", "e.g., Daily Morning Brief / Friday Repo Check") }
    public var routinePromptPlaceholder: String { t("输入定时触发时要发送给该 Bot 的指令...", "Instruction sent to this bot when triggered...") }
    public var routinesEmpty: String {
        t("还没有例行任务。可随时添加一条定时或一键执行的个人例程。",
          "No routines yet. Add a recurring schedule or one-click prompt for this bot.")
    }
    public var runNow: String { t("立即运行", "Run Now") }
    public var activityTitle: String { t("最近运行", "Recent Activity") }
    public var activityEmpty: String {
        t("开始对话后，这里会记录每次调用的引擎与耗时。",
          "Engine calls and durations will appear here once you start chatting.")
    }
    public var botInstructionsTitle: String { t("人设指令", "Instructions") }
    public var copyCode: String { t("复制代码", "Copy code") }
    public var streamingStatus: String { t("正在回复...", "Responding...") }
    public var thoughtProcess: String { t("思考过程", "Thought Process") }
    public var thinkingInProgress: String { t("深度思考中...", "Reasoning...") }
    public var diffChanges: String { t("代码变更", "Diff") }
    public var terminalOutput: String { t("终端命令", "Terminal") }
    public var expandCode: String { t("展开全部", "Expand") }
    public var collapseCode: String { t("收起", "Collapse") }
    public var attachFiles: String { t("附加文件上下文", "Attach Files") }
    public var slashCommands: String { t("快捷指令", "Slash Commands") }
    public var dropFilesHint: String { t("松开以附加文件上下文", "Drop files to attach context") }
    public var zoomSectionTitle: String { t("界面缩放", "Interface Zoom") }
    public var zoomSectionDesc: String { t("支持 ⌘+ / ⌘- 缩放界面，⌘0 恢复 100%", "Use ⌘+ / ⌘- to scale the UI and ⌘0 to reset to 100%") }
    public var zoomIn: String { t("放大界面", "Zoom In") }
    public var zoomOut: String { t("缩小界面", "Zoom Out") }
    public var zoomReset: String { t("恢复默认缩放 (100%)", "Actual Size (100%)") }
    public var companionSyncToggleTitle: String { t("移动端多端同步（可选）", "Mobile Companion Sync (Optional)") }
    public var companionSyncToggleDesc: String {
        t("默认关闭以保持极简低功耗。开启后将启动本机同步服务供 iPhone 端连接。",
          "Off by default for minimal overhead. Turn on to sync with your iPhone companion.")
    }
    public var clearAllChatsTitle: String { t("清空所有历史对话", "Clear All Conversations") }
    public var clearAllChatsDesc: String { t("仅删除历史消息，保留你的模型配置、本地 Agent 与自定义智能体。", "Deletes chat history while keeping your models, local agents, and agents.") }
    public var clearNow: String { t("立即清空", "Clear") }
    public var clearAllChatsConfirmTitle: String { t("确定要清空所有历史对话吗？", "Clear All Conversations?") }
    public func clearAllChatsConfirmMessage(_ count: Int) -> String {
        t("将永久删除全部 \(count) 条历史对话，但保留模型配置、本地 Agent 与自定义智能体。此操作无法撤销。",
          "This will permanently delete all \(count) conversation(s) while keeping your models, local agents, and agents. This cannot be undone.")
    }
    public func deleteBotConfirmTitle(_ name: String) -> String {
        t("删除智能体「\(name)」？", "Delete Agent “\(name)”?")
    }
    public func deleteBotConfirmMessage(_ count: Int) -> String {
        t("将永久删除该智能体及其关联的 \(count) 条对话记录，此操作无法撤销。",
          "This will permanently delete this agent and its \(count) conversation(s). This cannot be undone.")
    }
    public var deletedToastPrefix: String { t("已删除", "Deleted") }
    public var undoAction: String { t("撤销", "Undo") }
    public var routineHourLabel: String { t("小时", "Hour") }
    public var routineMinuteLabel: String { t("分钟", "Minute") }
    public var routineWeekdayLabel: String { t("星期", "Weekday") }
    public func corruptStateNotice(backupName: String) -> String {
        t("检测到状态文件解码失败，已备份至 \(backupName)。为防止数据丢失，已保留原文件且不会用空状态覆盖。",
          "State file failed to decode and was backed up to \(backupName). Original file was preserved without overwriting.")
    }

    public var languageSectionTitle: String { t("界面语言", "Interface Language") }
    public var languageSectionDesc: String { t("默认自动跟随系统语言，也可手动切换", "Follows your system language automatically, or pick one manually") }
    public var appearanceSectionTitle: String { t("外观主题", "Appearance") }
    public var appearanceAuto: String { t("跟随系统", "Auto") }
    public var appearanceDark: String { t("深色", "Dark") }
    public var appearanceLight: String { t("浅色", "Light") }
    public var keepAwakeTitle: String { t("保持 Mac 唤醒", "Keep Mac Awake") }
    public var keepAwakeDesc: String { t("开启后防止系统空闲休眠，便于后台任务与移动端远程访问", "Prevent idle sleep so background tasks and mobile companion stay reachable") }
    public var memoryEnabledTitle: String { t("启用个人记忆", "Enable Personal Memory") }
    public var memoryEnabledDesc: String { t("在对话中记住你的偏好与常用约定，仅存储于本地", "Remember your preferences and conventions locally across chats") }
    public var memorySummaryTitle: String { t("偏好档案", "Personal Profile") }
    public var runMemoryConsolidation: String { t("立即整理记忆", "Consolidate Memory") }
    public var syncBridgeTitle: String { t("移动端伴侣同步服务", "Mobile Companion Sync") }
    public var syncBridgeDesc: String { t("本机局域网服务与远程加密隧道，供 iPhone 端随时连接", "Local bridge and optional encrypted tunnel for your iPhone companion") }
    public var endpointUrlLabel: String { t("连接地址", "Endpoint URL") }
    public var connectedDevicesTitle: String { t("已连接设备", "Connected Devices") }
    public var aboutPipiBot: String { t("关于 PiPiBot", "About PiPiBot") }
    public var versionLabel: String { t("版本", "Version") }

    // MARK: Session Core, Permissions, Timeline & Inspector (S1)
    public var permissionTierTitle: String { t("执行权限", "Permission Tier") }
    public var projectPermissionOverrideTitle: String { t("项目权限覆盖", "Project Permission Override") }
    public var followBotDefaultPermission: String { t("跟随智能体默认", "Follow Agent Default") }
    public var inspectorTabPlan: String { t("计划", "Plan") }
    public var inspectorTabChanges: String { t("改动", "Changes") }
    public var inspectorTabContext: String { t("上下文", "Context") }
    public var planTitle: String { t("执行计划", "Execution Plan") }
    public var planEmpty: String { t("当前会话暂无结构化计划。", "No execution plan items in this session yet.") }
    public var changesEmpty: String { t("当前会话暂未检测到文件改动。", "No file changes recorded in this session yet.") }
    public var summaryTitle: String { t("执行总结", "Summary") }
    public var exitCodeLabel: String { t("退出码", "Exit") }
    public var retryAction: String { t("重试", "Retry") }
    public var switchEngineAction: String { t("换引擎", "Switch Engine") }
    public var openAIEngineSettings: String { t("打开 AI 引擎设置", "Open AI Engine Settings") }
    public var engineSettingsShort: String { t("引擎设置", "Engine Settings") }
    public var allowChangesAction: String { t("允许执行修改", "Allow changes") }
    public var allowOnceAction: String { t("仅允许本次", "Allow once") }
    public var allowSessionAction: String { t("本会话同类允许", "Allow in session") }
    public var allowProjectAction: String { t("本项目允许", "Allow in project") }
    public var allowAlwaysAction: String { t("始终允许", "Always allow") }
    public var keepReadOnlyAction: String { t("保持只读", "Keep read-only") }
    public var yieldedStatus: String { t("已暂停以优先响应当前对话，完成后自动恢复", "Paused for active chat; will resume automatically") }
    public var guardrailSectionTitle: String { t("安全审批与授权规则", "Safety & Approval Rules") }
    public var guardrailJudgeToggleTitle: String { t("高风险操作独立评估", "High-Risk Action Review") }
    public var guardrailJudgeToggleDesc: String {
        t("对外部写入或高危命令执行额外风险检查，敏感信息外发默认拦截。",
          "Evaluates risk before high-risk or external actions; credential exfiltration is always blocked.")
    }
    public var guardrailWhitelistEmpty: String {
        t("暂无已保存的授权规则。",
          "No saved approval rules.")
    }
    public var clearWhitelistRules: String { t("清空全部规则", "Clear All Rules") }
    public var approvalApprovedBadge: String { t("已批准执行", "Approved") }
    public var approvalDeniedBadge: String { t("已保持只读", "Read-only kept") }
    public var approvalExpiredBadge: String { t("已过期", "Expired") }
    public var needsYouLabel: String { t("待确认", "Needs You") }
    public var noConfiguredEngineGuide: String {
        t("尚未连接大模型或本地 Agent。请打开 AI 引擎设置添加 API Key（支持 OpenAI、Anthropic、Gemini、DeepSeek、Ollama）或启用本机已安装的本地 Agent。",
          "No LLM API or local agent is configured yet. Open AI Engine settings to add an API key (OpenAI, Anthropic, Gemini, DeepSeek, Ollama) or enable a local CLI agent.")
    }
    public func stepsCountLabel(_ count: Int) -> String {
        t("\(count) 个步骤", count == 1 ? "1 step" : "\(count) steps")
    }
    public func filesChangedCountLabel(_ count: Int) -> String {
        t("\(count) 个改动文件", count == 1 ? "1 file changed" : "\(count) files changed")
    }

    // MARK: Native Shell, Global Sessions, Command Palette & Needs You Inbox (S2)
    public var searchOrCommand: String { t("搜索 / 命令", "Search / Commands") }
    public var commandPalettePlaceholder: String { t("搜索对话标题、消息内容、智能体或命令...", "Search chats, messages, agents, or commands...") }
    public var commandPaletteEmpty: String { t("没有匹配的对话、智能体或命令", "No matching chats, agents, or commands") }
    public var commandPaletteSectionCommands: String { t("命令", "Commands") }
    public var commandPaletteSectionBots: String { t("智能体", "Agents") }
    public var commandPaletteSectionSessions: String { t("对话", "Chats") }
    public var pinChat: String { t("置顶", "Pin") }
    public var unpinChat: String { t("取消置顶", "Unpin") }
    public var sessionGroupActive: String { t("进行中 · 待我确认", "Active & Needs You") }
    public var sessionGroupPinned: String { t("置顶", "Pinned") }
    public var sessionGroupToday: String { t("今天", "Today") }
    public var sessionGroupYesterday: String { t("昨天", "Yesterday") }
    public var sessionGroupLast7Days: String { t("前 7 天", "Previous 7 Days") }
    public var sessionGroupEarlier: String { t("更早", "Earlier") }
    public var allBotsFilter: String { t("全部", "All") }
    public var singleChatFilter: String { t("单聊", "1:1 Chats") }
    public var filterByBotLabel: String { t("筛选", "Filter") }
    public var clearFilter: String { t("清除筛选", "Clear filter") }
    public var needsYouInboxTitle: String { t("待我确认", "Needs You") }
    public var needsYouInboxSubtitle: String { t("待处理的权限审批与确认事项", "Pending permission approvals and decisions") }
    public var openSession: String { t("打开对话", "Open Chat") }
    public var continueInMainWindow: String { t("在主窗口继续", "Continue in main window") }
    public var newQuickChat: String { t("新提问", "New Prompt") }
    public var toggleSidebar: String { t("显示或隐藏侧边栏", "Toggle Sidebar") }
    public var openCommandPalette: String { t("打开命令面板", "Open Command Palette") }
    public var toggleThemeAction: String { t("切换外观主题", "Switch Appearance") }
    public var menuBarNewSessionHint: String { t("发送将创建新对话", "Sends into a new chat") }
    public var sessionsSection: String { t("对话与协作", "Conversations & Swarm") }
    public var relativeTimeJustNow: String { t("刚刚", "now") }
    public func relativeTimeMinutes(_ m: Int) -> String { t("\(m)分钟", "\(m)m") }
    public func relativeTimeHours(_ h: Int) -> String { t("\(h)小时", "\(h)h") }
    public var relativeTimeYesterday: String { t("昨天", "1d") }
    public func relativeTimeDays(_ d: Int) -> String { t("\(d)天", "\(d)d") }

    // MARK: V2 3D Bot Home, Dynamic Bot Creator & Group Swarm
    public var botHome: String { t("智能体", "Agents") }
    public var backToBotHome: String { t("智能体", "Agents") }
    public var groupChatsSection: String { t("协作群", "Groups") }
    public var newGroupChat: String { t("新建群聊", "New Group Chat") }
    public var renameGroupChat: String { t("重命名群聊", "Rename Group Chat") }
    public var editGroupChat: String { t("编辑群成员与模式", "Edit Group & Mode") }
    public var commandPaletteSectionGroups: String { t("协作群", "Groups") }
    public var createCustomBot: String { t("创建自定义智能体", "Create Custom Agent") }

    // MARK: Wave 2 (#01 Personal Wiki, #02 Per-Bot Memory, #03 Native Proactive & Prepare)
    public var knowledgeHubTitle: String { t("知识与简报", "Knowledge & Briefs") }
    public var knowledgeHubSubtitle: String {
        t("个人词条、日程简报、笔记文档与助手记忆",
          "Personal entries, schedule briefs, notes, and assistant memory")
    }
    public var wikiTabTitle: String { t("词条", "Entries") }
    public var proactiveTabTitle: String { t("日程简报", "Briefs") }
    public var botMemoryTabTitle: String { t("助手记忆", "Memory") }
    public var wikiSearchPlaceholder: String { t("搜索词条标题、正文或别名", "Search entries, content, or aliases") }
    public var wikiNewPage: String { t("新建词条", "New Entry") }
    public var wikiEmptyTitle: String { t("暂无词条", "No Entries") }
    public var wikiEmptyMessage: String {
        t("可新建词条记录人物、项目、主题或笔记，所有内容均保存于本地。",
          "Create entries for people, projects, topics, or notes stored locally on this Mac.")
    }
    public var proactiveScanNow: String { t("扫描更新", "Scan") }
    public var proactiveEmptyTitle: String { t("暂无日程简报", "No Briefs") }
    public var proactiveEmptyMessage: String {
        t("点击扫描更新以读取已授权的日程与本地项目状态。",
          "Click Scan to read authorized calendar events and local project status.")
    }
    public var proactiveSectionTitle: String { t("主动提醒与防打扰", "Proactive Notifications") }
    public var proactiveQuietHoursTitle: String { t("夜间免打扰", "Quiet Hours") }
    public var proactiveQuietHoursDesc: String { t("免打扰时段内暂缓推送非紧急提醒", "Pause non-urgent notifications during quiet hours") }
    public var proactiveDailyCapTitle: String { t("每日提醒上限", "Daily Cap") }
    public var proactiveChatSilenceTitle: String { t("对话期间静默", "Active-Chat Silence") }
    public var proactiveRunDreaming: String { t("整理规则", "Consolidate") }
    public var proactiveRollback: String { t("回退版本", "Rollback") }
    public var botMemoryConsolidateNow: String { t("合并整理", "Consolidate") }
    public var botMemoryCacheSafeBadge: String { t("缓存保护", "Cache Safe") }
    public var compactContextAction: String { t("压缩上下文", "Compact Context") }

    // MARK: Wave 3 (#05 AlterEgo, #06 team.md, #11 Pocket Notes, Editable Docs & Builtin Skills)
    public var alterEgoSectionTitle: String { t("后台任务", "Background Tasks") }
    public var alterEgoSteerPlaceholder: String { t("补充执行说明", "Add instruction") }
    public var alterEgoResumeAction: String { t("继续执行", "Resume") }
    public var teamProtocolTitle: String { t("协作协议", "Team Protocol") }
    public var teamProtocolGenerate: String { t("生成模板", "Generate Template") }
    public var teamProtocolRun: String { t("按协议执行", "Run Protocol") }
    public var dynamicBotProposalsTitle: String { t("成员变更建议", "Team Proposals") }
    public var approveAndJoinAction: String { t("批准加入", "Approve & Join") }
    public var pocketNotesTabTitle: String { t("笔记与文档", "Notes & Docs") }
    public var builtinSkillsTabTitle: String { t("内置技能", "Skills") }
    public var extractTodosNow: String { t("提炼待办", "Extract To-Dos") }
    public var syncToWikiAction: String { t("同步至词条", "Sync to Entries") }
    public var newDocumentAction: String { t("新建文档", "New Document") }
    public var projectSkillsAction: String { t("校验技能", "Verify Skills") }

    // MARK: Wave 4 (#07 Local Model Autopilot, PolyStrata, Unified Gateway & #10 Personal Daily Voice)
    public var settingsVoice: String { t("语音交互", "Voice") }
    public var modelAutopilotTitle: String { t("本地模型规划", "Local Model Plan") }
    public var localGatewayTitle: String { t("本地模型服务", "Local Model Service") }
    public var reverseInjectCLITitle: String { t("向本地工具注入配置", "Inject into Local Tools") }
    public var reverseInjectCLIDesc: String {
        t("通过隔离环境变量向本地命令行工具传递模型配置，不修改原有配置文件。",
          "Passes model configuration to local CLI tools via isolated environment directories.")
    }
    public var runQASelfTestAction: String { t("连通自测", "Run Self-Test") }
    public var startGatewayAction: String { t("启动服务", "Start Service") }
    public var stopGatewayAction: String { t("停止服务", "Stop Service") }
    public var dailyVoiceTitle: String { t("日常语音", "Daily Voice") }
    public var voiceDictationAction: String { t("语音输入", "Dictation") }
    public var museHandsFreeAction: String { t("语音对话", "Voice Chat") }
    public var voiceBargeInHint: String { t("播报期间开口可随时打断", "Speak anytime to interrupt playback") }

    // MARK: Wave 5 (#09 Dual-Phase Computer Use: Chrome Seats & macOS Accessibility Cua)
    public var computerUseSectionTitle: String { t("桌面与浏览器协作", "Browser & Desktop Control") }
    public var computerUseTakeOver: String { t("手动接管", "Take Over") }
    public var computerUseResume: String { t("恢复协作", "Resume") }
    public var computerUseUnlockLane: String { t("核查并解锁", "Verify & Unlock") }
    public var computerUseOpenAccessibility: String { t("打开系统设置", "Open System Settings") }
    public var computerUseJournalTitle: String { t("操作保护日志", "Action Protection Log") }

    // MARK: iOS Tabs
    public var tabChat: String { t("对话", "Chat") }
    public var tabBots: String { t("人设", "Bots") }
    public var tabTasks: String { t("任务", "Tasks") }
    public var tabSettings: String { t("设置", "Settings") }
}
