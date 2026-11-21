// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// WeChat 1v1 Conversational Control Coordinator:
// - Natural-language interactive menus, multi-turn Bot creation wizard, Bot/Session/Project switching,
//   Group Mode onboarding & member selection, rich configuration, update checks, and risk approval replies.

import Foundation

public struct PipiWeChatBotInfo: Identifiable, Hashable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let role: String
    public let modelLabel: String
    public let permissionTier: PipiPermissionTier

    public init(
        id: String,
        name: String,
        role: String,
        modelLabel: String,
        permissionTier: PipiPermissionTier
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.modelLabel = modelLabel
        self.permissionTier = permissionTier
    }
}

public struct PipiWeChatProjectInfo: Identifiable, Hashable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let workspacePath: String?

    public init(id: String, name: String, workspacePath: String?) {
        self.id = id
        self.name = name
        self.workspacePath = workspacePath
    }
}

public struct PipiWeChatConversationInfo: Identifiable, Hashable, Sendable, Equatable {
    public let id: String
    public let personaId: String
    public let personaName: String
    public let title: String
    public let projectId: String?
    public let projectName: String?
    public let messageCount: Int

    public init(
        id: String,
        personaId: String,
        personaName: String,
        title: String,
        projectId: String?,
        projectName: String?,
        messageCount: Int
    ) {
        self.id = id
        self.personaId = personaId
        self.personaName = personaName
        self.title = title
        self.projectId = projectId
        self.projectName = projectName
        self.messageCount = messageCount
    }
}

public struct PipiWeChatModelChoice: Identifiable, Hashable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let target: PipiExecutionTarget
    public let modelId: String?

    public init(id: String, label: String, target: PipiExecutionTarget, modelId: String? = nil) {
        self.id = id
        self.label = label
        self.target = target
        self.modelId = modelId
    }
}

public struct PipiWeChatPendingApprovalInfo: Sendable, Equatable {
    public let approvalId: String
    public let question: String
    public let rationale: String
    public let riskLevel: PipiRiskLevel
    public let options: [(id: String, label: String)]

    public static func == (lhs: PipiWeChatPendingApprovalInfo, rhs: PipiWeChatPendingApprovalInfo) -> Bool {
        lhs.approvalId == rhs.approvalId &&
            lhs.question == rhs.question &&
            lhs.rationale == rhs.rationale &&
            lhs.riskLevel == rhs.riskLevel &&
            lhs.options.map(\.id) == rhs.options.map(\.id)
    }

    public init(
        approvalId: String,
        question: String,
        rationale: String,
        riskLevel: PipiRiskLevel,
        options: [(id: String, label: String)]
    ) {
        self.approvalId = approvalId
        self.question = question
        self.rationale = rationale
        self.riskLevel = riskLevel
        self.options = options
    }
}

public struct PipiWeChatConfigSnapshot: Sendable, Equatable {
    public let primaryBotId: String
    public let primaryBotName: String
    public let routingMode: PipiWeChatRoutingMode
    public let activeConversationTitle: String?
    public let activeProjectName: String?
    public let defaultModelLabel: String
    public let llmJudgeEnabled: Bool
    public let proactiveCLIDelegationEnabled: Bool
    public let typingIndicatorEnabled: Bool
    public let memoryEnabled: Bool
    public let appVersion: String

    public init(
        primaryBotId: String,
        primaryBotName: String,
        routingMode: PipiWeChatRoutingMode,
        activeConversationTitle: String?,
        activeProjectName: String?,
        defaultModelLabel: String,
        llmJudgeEnabled: Bool,
        proactiveCLIDelegationEnabled: Bool,
        typingIndicatorEnabled: Bool,
        memoryEnabled: Bool,
        appVersion: String
    ) {
        self.primaryBotId = primaryBotId
        self.primaryBotName = primaryBotName
        self.routingMode = routingMode
        self.activeConversationTitle = activeConversationTitle
        self.activeProjectName = activeProjectName
        self.defaultModelLabel = defaultModelLabel
        self.llmJudgeEnabled = llmJudgeEnabled
        self.proactiveCLIDelegationEnabled = proactiveCLIDelegationEnabled
        self.typingIndicatorEnabled = typingIndicatorEnabled
        self.memoryEnabled = memoryEnabled
        self.appVersion = appVersion
    }
}

public enum PipiWeChatNaturalIntent: Sendable, Equatable {
    case showMenu
    case switchBot(targetQuery: String?)
    case createBot(prefilledName: String?, prefilledRole: String?)
    case manageSessions(createNew: Bool)
    case switchProject(targetQuery: String?)
    case enterGroupMode(memberQuery: String?)
    case exitGroupMode
    case showConfig
    case checkUpdate
    case confirmInstallUpdate
    case cancelFlow
}

public enum PipiWeChatWizardState: Sendable, Equatable {
    case idle
    case mainMenu
    case selectingBot(botIds: [String])
    case creatingBotName(templateIds: [String])
    case creatingBotRole(name: String, templateId: String?)
    case creatingBotModel(name: String, role: String, templateId: String?, choiceIds: [String])
    case creatingBotPermission(name: String, role: String, templateId: String?, target: PipiExecutionTarget, modelId: String?)
    case selectingSession(sessionIds: [String])
    case selectingProject(projectIds: [String])
    case configuringGroupMembers(botIds: [String])
    case configMenu
    case configSelectingBotModel(botId: String, choiceIds: [String])
    case configSelectingBotPermission(botId: String)
    case awaitingUpdateConfirm(release: PipiGitHubReleaseInfo)
    case awaitingApproval(approval: PipiWeChatPendingApprovalInfo)
}

public struct PipiWeChatUserSessionContext: Sendable, Equatable {
    public var activeConversationIdByBot: [String: String] = [:]
    public var activeConversationId: String? = nil
    public var activeProjectId: String? = nil
    public var wizard: PipiWeChatWizardState = .idle
    public var lastInteractionAt: Date = Date()

    public init() {}
}

public enum PipiWeChatIntentParser {
    /// Detects explicit 1v1 conversational control intents from natural language or slash commands
    /// while avoiding false positives on normal user tasks.
    public static func parse(_ rawText: String, availableBots: [PipiWeChatBotInfo] = []) -> PipiWeChatNaturalIntent? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        // Cancel / back
        if ["取消", "退出菜单", "返回", "不改了", "算了", "/cancel", "/exit"].contains(lower) {
            return .cancelFlow
        }

        // Main menu
        if ["/menu", "/help", "菜单", "功能菜单", "主菜单", "帮助", "交互菜单", "打开菜单", "你能做什么", "怎么用", "指令列表"].contains(lower) {
            return .showMenu
        }

        // Mode switches: 1v1 vs group
        if lower == "/mode 1v1" || lower == "/单聊" || [
            "切换单聊", "切回单聊", "切回1v1", "回到1v1", "退出群聊", "关闭群聊", "结束群聊", "1v1模式", "单聊模式"
        ].contains(where: { lower == $0 || lower.contains($0) && trimmed.count <= 16 }) {
            return .exitGroupMode
        }

        if lower == "/mode group" || lower == "/群聊" || lower == "/group" || [
            "切换群聊", "进入群聊", "群聊模式", "开启群聊", "打开群聊", "拉群", "多助手群聊"
        ].contains(where: { lower == $0 || (lower.contains($0) && trimmed.count <= 24) }) {
            return .enterGroupMode(memberQuery: trimmed)
        }

        // Bot switching
        if lower == "/bots" || lower == "/助手" || [
            "切换bot", "切换 bot", "换个bot", "换个 bot", "切换助手", "换个助手", "换助手",
            "切换智能体", "有哪些bot", "有哪些助手", "查看bot", "查看助手", "bot列表", "助手列表"
        ].contains(where: { lower == $0 }) {
            return .switchBot(targetQuery: nil)
        }
        for prefix in ["切换到", "换到", "切到", "切换bot到", "切换助手到", "换个bot叫", "我要和", "我想和"] {
            if lower.hasPrefix(prefix) && trimmed.count <= 28 {
                var rest = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                for suffix in ["对话", "聊天", "聊", "回答", "bot", "助手"] {
                    if rest.lowercased().hasSuffix(suffix) && rest.count > suffix.count {
                        rest = String(rest.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                if rest.contains("项目") { break }
                if !rest.isEmpty && availableBots.contains(where: { $0.name.lowercased().contains(rest.lowercased()) || rest.lowercased().contains($0.name.lowercased()) }) {
                    return .switchBot(targetQuery: rest)
                }
                if prefix.contains("切换") || prefix.contains("换到") {
                    return .switchBot(targetQuery: rest.isEmpty ? nil : rest)
                }
            }
        }

        // Create new bot (supports natural phrasing like "创建一个叫翻译官的bot" or "/newbot")
        let createBotMatched: Bool = {
            if lower == "/newbot" || lower == "/createbot" { return true }
            guard trimmed.count <= 48,
                  let regex = try? NSRegularExpression(pattern: #"(创建|新建|添加|加一个).{0,24}(bot|智能体|助手)"#, options: [.caseInsensitive]) else {
                return false
            }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            return regex.firstMatch(in: trimmed, options: [], range: range) != nil
        }()
        if createBotMatched {
            return .createBot(prefilledName: extractInlineBotName(from: trimmed), prefilledRole: nil)
        }

        // Sessions
        if lower == "/sessions" || lower == "/会话" || [
            "切换会话", "会话列表", "历史会话", "查看会话", "换个会话", "选择会话"
        ].contains(where: { lower == $0 || (lower.contains($0) && trimmed.count <= 18) }) {
            return .manageSessions(createNew: false)
        }
        if lower == "/new" || [
            "新建会话", "新会话", "新对话", "开个新会话", "开启新对话", "重新开始对话"
        ].contains(where: { lower == $0 || (lower.contains($0) && trimmed.count <= 16) }) {
            return .manageSessions(createNew: true)
        }

        // Projects
        if lower == "/projects" || lower == "/项目" || [
            "切换项目", "项目列表", "查看项目", "绑定项目", "选择项目", "换个项目"
        ].contains(where: { lower == $0 || (lower.contains($0) && trimmed.count <= 20) }) {
            return .switchProject(targetQuery: nil)
        }
        if (lower.hasPrefix("切换到") || lower.hasPrefix("绑定到") || lower.hasPrefix("切换项目到")) && lower.contains("项目") && trimmed.count <= 32 {
            return .switchProject(targetQuery: trimmed)
        }

        // Config menu
        if lower == "/config" || lower == "/settings" || lower == "/status" || [
            "更多配置", "配置菜单", "打开配置", "查看配置", "修改配置", "系统配置", "当前配置", "设置菜单", "修改模型", "切换模型", "安全审计配置"
        ].contains(where: { lower == $0 || (lower.contains($0) && trimmed.count <= 18) }) {
            return .showConfig
        }

        // Update check
        if lower == "/update" || [
            "检查更新", "查看更新", "版本更新", "检查新版本", "升级版本", "自动更新"
        ].contains(where: { lower == $0 || (lower.contains($0) && trimmed.count <= 18) }) {
            return .checkUpdate
        }

        return nil
    }

    private static func extractInlineBotName(from text: String) -> String? {
        for marker in ["叫", "名为", "名称为", "名称是"] {
            if let range = text.range(of: marker) {
                let tail = String(text[range.upperBound...])
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                if !tail.isEmpty {
                    let firstPart = tail.split(whereSeparator: { $0 == "，" || $0 == "," || $0 == " " || $0 == "的" }).first.map(String.init) ?? tail
                    if !firstPart.isEmpty && firstPart.count <= 20 {
                        return firstPart
                    }
                }
            }
        }
        return nil
    }

    public static func parseIndexSelection(_ text: String, maxCount: Int) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int(cleaned), n >= 1, n <= maxCount {
            return n - 1
        }
        return nil
    }

    public static func parseMultiIndexSelection(_ text: String, maxCount: Int) -> [Int] {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned == "全部" || cleaned == "all" || cleaned == "全选" {
            return Array(0..<maxCount)
        }
        let tokens = cleaned.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " || $0 == "、" })
        var indices: [Int] = []
        for tok in tokens {
            if let n = Int(tok), n >= 1, n <= maxCount, !indices.contains(n - 1) {
                indices.append(n - 1)
            }
        }
        return indices
    }
}

@MainActor
public final class PipiWeChatConversationCoordinator {
    private var sessionsByUser: [String: PipiWeChatUserSessionContext] = [:]

    public init() {}

    public func context(for userId: String) -> PipiWeChatUserSessionContext {
        sessionsByUser[userId] ?? PipiWeChatUserSessionContext()
    }

    public func updateContext(for userId: String, _ mutate: (inout PipiWeChatUserSessionContext) -> Void) {
        var ctx = sessionsByUser[userId] ?? PipiWeChatUserSessionContext()
        ctx.lastInteractionAt = Date()
        mutate(&ctx)
        sessionsByUser[userId] = ctx
    }

    public func setPendingApproval(_ approval: PipiWeChatPendingApprovalInfo, for userId: String) {
        updateContext(for: userId) { ctx in
            ctx.wizard = .awaitingApproval(approval: approval)
        }
    }

    public func renderMainMenu(config: PipiWeChatConfigSnapshot) -> String {
        let modeLabel = config.routingMode == .directMainBot ? "1v1 单聊模式" : "群聊模式（【助手】前缀）"
        let sessLabel = config.activeConversationTitle ?? "默认微信会话"
        let projLabel = config.activeProjectName ?? "未绑定项目（默认工作区）"
        return """
        🐾 PiPiBot 微信交互菜单（v\(config.appVersion)）

        当前状态：
        • 对话助手：\(config.primaryBotName)
        • 交互模式：\(modeLabel)
        • 默认模型：\(config.defaultModelLabel)
        • 当前会话：\(sessLabel)
        • 当前项目：\(projLabel)

        请直接回复数字或用自然语言告诉我：
        1. 切换对话的 Bot
        2. 创建新的 Bot（引导式创建）
        3. 切换或新建会话
        4. 切换或绑定项目
        5. 进入 / 配置群聊模式
        6. 更多配置（模型 / 权限 / 安全审计 / 输入状态）
        7. 检查 GitHub Release 版本更新
        8. 常用 Mac 能力说明（截屏 / 语音 / 文件 / Codex）

        提示：随时发送「菜单」打开本菜单，「取消」退出当前引导。
        """
    }

    public func renderBotPicker(bots: [PipiWeChatBotInfo], primaryBotId: String) -> String {
        var lines = ["🤖 请选择要切换的对话 Bot（回复编号或名称）："]
        for (idx, bot) in bots.enumerated() {
            let currentMark = bot.id == primaryBotId ? " ✅当前" : ""
            lines.append("\(idx + 1). \(bot.name)\(currentMark)")
            lines.append("   模型：\(bot.modelLabel) · \(bot.permissionTier.label(.zhHans))")
            if !bot.role.isEmpty {
                lines.append("   职责：\(bot.role)")
            }
        }
        lines.append("\n回复「取消」返回正常对话。")
        return lines.joined(separator: "\n")
    }

    public func renderSessionPicker(conversations: [PipiWeChatConversationInfo], currentId: String?) -> String {
        var lines = ["💬 会话管理（回复编号切换，或回复「0」新建会话）：", "0. ＋ 新建空白会话"]
        for (idx, conv) in conversations.prefix(12).enumerated() {
            let currentMark = conv.id == currentId ? " ✅当前" : ""
            let projTag = conv.projectName.map { " · 📁\($0)" } ?? ""
            lines.append("\(idx + 1). [\(conv.personaName)] \(conv.title)（\(conv.messageCount)条\(projTag)）\(currentMark)")
        }
        lines.append("\n回复「取消」返回。")
        return lines.joined(separator: "\n")
    }

    public func renderProjectPicker(projects: [PipiWeChatProjectInfo], currentId: String?) -> String {
        var lines = ["📁 项目切换（回复编号绑定工作区，或回复「0」解绑）：", "0. 默认工作区（不绑定项目）"]
        if projects.isEmpty {
            lines.append("\n当前尚未创建项目，可在 Mac 端新建项目后再绑定。")
        } else {
            for (idx, proj) in projects.enumerated() {
                let currentMark = proj.id == currentId ? " ✅当前" : ""
                let dirHint = proj.workspacePath.map { " (\($0))" } ?? ""
                lines.append("\(idx + 1). \(proj.name)\(dirHint)\(currentMark)")
            }
        }
        lines.append("\n回复「取消」返回。")
        return lines.joined(separator: "\n")
    }

    public func renderConfigMenu(config: PipiWeChatConfigSnapshot) -> String {
        let judgeText = config.llmJudgeEnabled ? "已开启" : "已关闭"
        let cliText = config.proactiveCLIDelegationEnabled ? "已开启" : "已关闭"
        let typingText = config.typingIndicatorEnabled ? "已开启" : "已关闭"
        let memText = config.memoryEnabled ? "已开启" : "已关闭"
        return """
        ⚙️ 更多配置（回复编号修改）：

        1. 修改当前 Bot（\(config.primaryBotName)）的专属模型
        2. 修改当前 Bot 的风险执行权限
        3. 切换「安全审计官自动评估」：\(judgeText)
        4. 切换「主动调用 Codex/CLI 工具」：\(cliText)
        5. 切换「微信正在输入状态」：\(typingText)
        6. 切换「跨会话长期记忆」：\(memText)
        7. 查看或切换工作区 / 项目

        回复「取消」返回正常对话。
        """
    }

    public func renderApprovalPrompt(_ approval: PipiWeChatPendingApprovalInfo) -> String {
        var lines = [
            "🛡️ 风险操作需要您的确认（风险等级：\(approval.riskLevel.label(.zhHans))）",
            "操作：\(approval.question)",
            "审计说明：\(approval.rationale)",
            ""
        ]
        for (idx, opt) in approval.options.enumerated() {
            lines.append("\(idx + 1). \(opt.label)")
        }
        lines.append("\n请回复编号（1-\(approval.options.count)）或直接回复「同意」/「拒绝」。")
        return lines.joined(separator: "\n")
    }

    public static func formatCapabilitiesGuide() -> String {
        """
        ✨ PiPiBot 微信端已支持的全部能力：
        • 语音消息：发送微信语音（支持微信转文字或本机语音识别）即可直接对话或触发菜单
        • 图片与附件：发送图片（自动视觉分析）或文档/代码文件（自动解析内容）
        • 正在输入状态：处理期间实时向微信同步「正在输入...」
        • 主动工程能力：需要看代码/跑测试时 PiPi 会主动调用 Codex / Claude Code（无需输 /codex）
        • 风险审计守护：涉及修改文件/发邮件/高危命令时由「Guard · 安全审计官」评估并请您确认
        • 自然语言交互：直接说「菜单」「创建bot」「切换bot」「切换会话」「切换项目」「进入群聊」「检查更新」「更多配置」即可引导完成
        """
    }
}
