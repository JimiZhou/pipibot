// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Jarvis-Grade Native Agent Toolbox:
// - Multi-step ReAct / Function-Calling tool schemas & execution engine
// - Workspace-wide autonomous execution with Guard safety boundary
// - Lively, human-like step-by-step progress narration
// - Native file/code/shell/web/system/visual-card/image-gen/media/butler-control tools

import Foundation
#if os(macOS)
import AppKit
#endif

// MARK: - Tool Schema & Multi-Turn Wire Types (Swift 6 Sendable)

public struct PipiAgentToolParam: Sendable, Equatable {
    public let name: String
    public let type: String
    public let description: String
    public let required: Bool
    public let enumValues: [String]?

    public init(
        name: String,
        type: String = "string",
        description: String,
        required: Bool = false,
        enumValues: [String]? = nil
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.enumValues = enumValues
    }
}

public struct PipiAgentToolDefinition: Sendable, Equatable {
    public let name: String
    public let description: String
    public let parameters: [PipiAgentToolParam]

    public init(name: String, description: String, parameters: [PipiAgentToolParam]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    public func openAISchema() -> [String: Any] {
        var props: [String: Any] = [:]
        var req: [String] = []
        for p in parameters {
            var schema: [String: Any] = [
                "type": p.type,
                "description": p.description
            ]
            if let ev = p.enumValues, !ev.isEmpty {
                schema["enum"] = ev
            }
            props[p.name] = schema
            if p.required { req.append(p.name) }
        }
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": props,
                    "required": req
                ]
            ]
        ]
    }

    public func anthropicSchema() -> [String: Any] {
        var props: [String: Any] = [:]
        var req: [String] = []
        for p in parameters {
            var schema: [String: Any] = [
                "type": p.type,
                "description": p.description
            ]
            if let ev = p.enumValues, !ev.isEmpty {
                schema["enum"] = ev
            }
            props[p.name] = schema
            if p.required { req.append(p.name) }
        }
        return [
            "name": name,
            "description": description,
            "input_schema": [
                "type": "object",
                "properties": props,
                "required": req
            ]
        ]
    }
}

public struct PipiLLMToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }

    public func argumentsDictionary() -> [String: Any] {
        guard let data = argumentsJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    public func string(_ key: String) -> String? {
        let dict = argumentsDictionary()
        if let s = dict[key] as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let n = dict[key] as? NSNumber {
            return n.stringValue
        }
        return nil
    }

    public func int(_ key: String) -> Int? {
        let dict = argumentsDictionary()
        if let n = dict[key] as? Int { return n }
        if let n = dict[key] as? NSNumber { return n.intValue }
        if let s = dict[key] as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    public func bool(_ key: String) -> Bool? {
        let dict = argumentsDictionary()
        if let b = dict[key] as? Bool { return b }
        if let s = dict[key] as? String {
            let low = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes", "on"].contains(low) { return true }
            if ["false", "0", "no", "off"].contains(low) { return false }
        }
        return nil
    }
}

public struct PipiEncodedImagePart: Sendable, Equatable {
    public let mimeType: String
    public let base64: String

    public init(mimeType: String, base64: String) {
        self.mimeType = mimeType
        self.base64 = base64
    }
}

public enum PipiAgentWireMessage: Sendable, Equatable {
    case system(String)
    case user(text: String, images: [PipiEncodedImagePart])
    case assistant(text: String, toolCalls: [PipiLLMToolCall])
    case toolResult(callId: String, toolName: String, content: String)
}

public struct PipiLLMToolStepResult: Sendable, Equatable {
    public let text: String
    public let toolCalls: [PipiLLMToolCall]
    public let engineLabel: String
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let cachedTokens: Int?

    public init(
        text: String,
        toolCalls: [PipiLLMToolCall] = [],
        engineLabel: String,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        cachedTokens: Int? = nil
    ) {
        self.text = text
        self.toolCalls = toolCalls
        self.engineLabel = engineLabel
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.cachedTokens = cachedTokens
    }
}

// MARK: - Tool Risk Classification (Workspace-Wide Autonomous Execution)

public struct PipiToolRiskAssessment: Sendable, Equatable {
    public let requiresApproval: Bool
    public let isHardDenied: Bool
    public let actionKind: PipiActionKind
    public let target: String
    public let summary: String
    public let reason: String

    public init(
        requiresApproval: Bool,
        isHardDenied: Bool = false,
        actionKind: PipiActionKind,
        target: String,
        summary: String,
        reason: String
    ) {
        self.requiresApproval = requiresApproval
        self.isHardDenied = isHardDenied
        self.actionKind = actionKind
        self.target = target
        self.summary = summary
        self.reason = reason
    }
}

public enum PipiJarvisToolRiskEvaluator {
    /// Evaluates whether a tool call can execute silently (workspace-wide auto-execution policy)
    /// or requires Guard Security Auditor + user confirmation.
    public static func evaluate(
        toolCall: PipiLLMToolCall,
        workspaceDirectory: String
    ) -> PipiToolRiskAssessment {
        let normalizedWorkspace = resolveExpandedPath(workspaceDirectory, workspaceDirectory: workspaceDirectory)
        let deliverablesRoot = PipiPersonalWikiStore.defaultStorageDirectory()
            .appendingPathComponent("deliverables", isDirectory: true)
            .standardizedFileURL.path

        switch toolCall.name {
        case "list_directory", "read_file", "search_files", "get_system_status",
             "web_search", "fetch_webpage", "read_calendar_and_reminders", "read_mail_or_sms",
             "capture_screenshot", "record_screen", "synthesize_voice", "send_local_file",
             "render_visual_card", "generate_image",
             "show_control_menu", "list_or_switch_bot", "create_bot", "switch_session_or_project",
             "configure_group_mode", "update_settings", "check_updates", "create_routine_or_reminder",
             "materialize_blueprint_bot", "record_entity_ledger", "query_entity_ledger", "propose_blueprint_evolution",
             "trigger_list", "trigger_upsert", "trigger_delete",
             "remote_nodes_list", "remote_node_inspect", "remote_node_run_harness", "remote_node_exec",
             "browser_snapshot", "device_vision_ocr", "device_clipboard", "device_npu_status", "run_script":
            return PipiToolRiskAssessment(
                requiresApproval: false,
                actionKind: .readOnly,
                target: toolCall.string("path") ?? normalizedWorkspace,
                summary: "\(toolCall.name)",
                reason: "只读探索、富媒体交付或管家控制操作，静默放行。"
            )

        case "browser_browse", "browser_open":
            let rawURL = toolCall.string("url") ?? ""
            let check = PipiBrowserCUASafetyPolicy.validateNavigationURL(rawURL)
            if !check.allowed, let risk = check.assessment {
                return risk
            }
            return PipiToolRiskAssessment(
                requiresApproval: false,
                actionKind: .readOnly,
                target: check.normalizedURL,
                summary: "\(toolCall.name): \(check.normalizedURL.prefix(100))",
                reason: "真实浏览器打开公开网页并提取内容，静默放行。"
            )

        case "browser_act":
            return PipiToolRiskAssessment(
                requiresApproval: false,
                actionKind: .readOnly,
                target: toolCall.string("ref") ?? toolCall.string("action") ?? "page",
                summary: "browser_act(\(toolCall.string("action") ?? "act"))",
                reason: "浏览器交互由 CUA 安全策略实时校验（高敏支付/删除/密码自动拦截确认）。"
            )

        case "write_file", "edit_file":
            let rawPath = toolCall.string("path") ?? ""
            let resolved = resolveExpandedPath(rawPath, workspaceDirectory: normalizedWorkspace)
            let insideWorkspace = isPath(resolved, inside: normalizedWorkspace) || isPath(resolved, inside: deliverablesRoot)
            if insideWorkspace {
                return PipiToolRiskAssessment(
                    requiresApproval: false,
                    actionKind: .localWrite,
                    target: resolved,
                    summary: "\(toolCall.name): \(resolved)",
                    reason: "工作区内文件修改，按策略自动放行。"
                )
            }
            return PipiToolRiskAssessment(
                requiresApproval: true,
                actionKind: .localWrite,
                target: resolved,
                summary: "\(toolCall.name)（工作区外）: \(resolved)",
                reason: "目标路径位于当前项目工作区外，需要你的安全确认。"
            )

        case "run_shell":
            let cmd = toolCall.string("command") ?? ""
            let lower = cmd.lowercased()
            let cwd = resolveExpandedPath(toolCall.string("working_directory") ?? normalizedWorkspace, workspaceDirectory: normalizedWorkspace)

            // Hard deny catastrophic patterns
            let catastrophic = ["rm -rf /", "rm -rf ~", "mkfs.", "dd if=", ":(){:|:&};:", "diskutil erase"]
            if catastrophic.contains(where: { lower.contains($0) }) {
                return PipiToolRiskAssessment(
                    requiresApproval: true,
                    isHardDenied: true,
                    actionKind: .destructive,
                    target: cwd,
                    summary: "危险命令: \(cmd.prefix(120))",
                    reason: "检测到灾难性破坏指令，安全护栏已直接拦截。"
                )
            }

            // High-risk operations requiring confirmation even inside workspace
            let needsConfirmPatterns = [
                "sudo ", "rm -rf", "rm -fr", "git push", "git reset --hard", "git clean -f",
                "npm publish", "gh release", "launchctl ", "defaults write", "killall ", "shutdown", "reboot",
                "chmod -r 777", "chown -r"
            ]
            if needsConfirmPatterns.contains(where: { lower.contains($0) }) {
                return PipiToolRiskAssessment(
                    requiresApproval: true,
                    actionKind: lower.contains("git push") || lower.contains("publish") || lower.contains("release")
                        ? .externalEffect : .destructive,
                    target: cwd,
                    summary: "高风险命令: \(cmd.prefix(140))",
                    reason: "涉及破坏性删除、系统/sudo 配置或远程推送，需先经你确认。"
                )
            }

            // Read-only commands allowed anywhere; write/build commands allowed inside workspace
            let isReadOnlyCmd = isLikelyReadOnlyShellCommand(lower)
            if isReadOnlyCmd || isPath(cwd, inside: normalizedWorkspace) {
                return PipiToolRiskAssessment(
                    requiresApproval: false,
                    actionKind: isReadOnlyCmd ? .readOnly : .localWrite,
                    target: cwd,
                    summary: "执行命令: \(cmd.prefix(120))",
                    reason: isReadOnlyCmd ? "只读诊断命令，静默放行。" : "工作区内构建/测试/本地 Git 操作，静默放行。"
                )
            }

            return PipiToolRiskAssessment(
                requiresApproval: true,
                actionKind: .localWrite,
                target: cwd,
                summary: "工作区外命令: \(cmd.prefix(120))",
                reason: "该命令在当前工作区外执行且可能产生写入副作用，需要确认。"
            )

        case "delegate_cli_agent":
            let mode = (toolCall.string("mode") ?? "readonly").lowercased()
            let dir = resolveExpandedPath(toolCall.string("working_directory") ?? normalizedWorkspace, workspaceDirectory: normalizedWorkspace)
            let isWrite = (mode == "write" || mode == "autoedit")
            if !isWrite || isPath(dir, inside: normalizedWorkspace) {
                return PipiToolRiskAssessment(
                    requiresApproval: false,
                    actionKind: isWrite ? .localWrite : .readOnly,
                    target: dir,
                    summary: "调度 CLI Agent (\(mode)): \(dir)",
                    reason: isWrite ? "工作区内 CLI 协作修改，静默放行。" : "只读 CLI 研究分析，静默放行。"
                )
            }
            return PipiToolRiskAssessment(
                requiresApproval: true,
                actionKind: .localWrite,
                target: dir,
                summary: "工作区外 CLI 写入任务: \(dir)",
                reason: "CLI 将在工作区外修改文件，需要你的安全确认。"
            )

        case "send_mail_or_sms":
            return PipiToolRiskAssessment(
                requiresApproval: true,
                actionKind: .externalEffect,
                target: toolCall.string("recipient") ?? "external",
                summary: "对外发送消息给 \(toolCall.string("recipient") ?? "收件人")",
                reason: "涉及向外发送邮件或短信，需要你的最终确认。"
            )

        default:
            return PipiToolRiskAssessment(
                requiresApproval: false,
                actionKind: .readOnly,
                target: normalizedWorkspace,
                summary: toolCall.name,
                reason: "默认放行。"
            )
        }
    }

    public static func resolveExpandedPath(_ raw: String, workspaceDirectory: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned == "." {
            return URL(fileURLWithPath: (workspaceDirectory as NSString).expandingTildeInPath).standardizedFileURL.path
        }
        // Friendly Chinese/colloquial desktop & home shortcuts
        let home = NSHomeDirectory()
        if cleaned.hasPrefix("桌面/") || cleaned.hasPrefix("桌面上/") {
            let tail = cleaned.replacingOccurrences(of: "桌面上/", with: "").replacingOccurrences(of: "桌面/", with: "")
            cleaned = "\(home)/Desktop/\(tail)"
        } else if cleaned == "桌面" || cleaned == "桌面上" {
            cleaned = "\(home)/Desktop"
        } else if cleaned.hasPrefix("Desktop/") {
            cleaned = "\(home)/\(cleaned)"
        } else if cleaned.hasPrefix("~/") || cleaned == "~" {
            cleaned = (cleaned as NSString).expandingTildeInPath
        } else if !cleaned.hasPrefix("/") {
            let base = (workspaceDirectory as NSString).expandingTildeInPath
            let candidateInWorkspace = URL(fileURLWithPath: base).appendingPathComponent(cleaned).standardizedFileURL.path
            if FileManager.default.fileExists(atPath: candidateInWorkspace) {
                return candidateInWorkspace
            }
            let candidateDesktop = URL(fileURLWithPath: "\(home)/Desktop").appendingPathComponent(cleaned).standardizedFileURL.path
            if FileManager.default.fileExists(atPath: candidateDesktop) {
                return candidateDesktop
            }
            return candidateInWorkspace
        }
        return URL(fileURLWithPath: cleaned).standardizedFileURL.path
    }

    public static func isPath(_ candidate: String, inside root: String) -> Bool {
        let c = URL(fileURLWithPath: candidate).standardizedFileURL.path
        let r = URL(fileURLWithPath: root).standardizedFileURL.path
        if c == r { return true }
        let prefix = r.hasSuffix("/") ? r : r + "/"
        return c.hasPrefix(prefix)
    }

    private static func isLikelyReadOnlyShellCommand(_ lowerCmd: String) -> Bool {
        let trimmed = lowerCmd.trimmingCharacters(in: .whitespacesAndNewlines)
        let writeTokens = [">", ">>", " tee ", "rm ", "mv ", "cp ", "mkdir ", "touch ", "chmod ", "chown ", "sed -i", "perl -i", "git commit", "git checkout", "git reset", "git push", "npm install", "brew install"]
        if writeTokens.contains(where: { trimmed.contains($0) }) { return false }
        let readPrefixes = [
            "ls", "ll", "pwd", "find ", "cat ", "head ", "tail ", "wc ", "rg ", "grep ",
            "git status", "git log", "git diff", "git branch", "git show",
            "du ", "df ", "ps ", "top -l", "uptime", "whoami", "sw_vers", "uname", "which ", "file ", "stat ", "tree "
        ]
        return readPrefixes.contains(where: { trimmed == $0.trimmingCharacters(in: .whitespaces) || trimmed.hasPrefix($0) })
    }
}

// MARK: - Lively Companion-Style Progress Narration

public enum PipiLivelyProgressNarrator {
    public static func initialAck(for userPrompt: String, lang: PipiResolvedLanguage) -> String {
        let lower = userPrompt.lowercased()
        if lang == .en {
            if lower.contains("voice") || lower.contains("audio") { return "On it! Recording a quick voice reply for you 🎙️" }
            if lower.contains("screenshot") || lower.contains("screen") { return "Got it! Grabbing a fresh screenshot right now 📸" }
            if lower.contains("image") || lower.contains("picture") || lower.contains("file") { return "Sure thing! Putting that image/file together for you now ✨" }
            if lower.contains("remind") || lower.contains("schedule") || lower.contains("brief") { return "Gotcha! Checking your schedule & setting things up ⏰" }
            return "On it! Let me jump in and check that for you right away 🚀"
        }
        if lower.contains("语音") || lower.contains("读给我") || lower.contains("念给我") {
            return "好嘞！我这就给你录一条语音消息 🎙️"
        }
        if lower.contains("截屏") || lower.contains("截图") || lower.contains("屏幕") {
            return "收到！马上帮你截一张现在的屏幕 📸"
        }
        if lower.contains("图片") || lower.contains("画") || lower.contains("附件") || lower.contains("发个文件") {
            return "没问题！我这就给你准备图片/附件，马上发你 ✨"
        }
        if lower.contains("提醒") || lower.contains("定时") || lower.contains("早报") || lower.contains("日程") {
            return "好哒！这就去查下日程/帮你安排上 ⏰"
        }
        if lower.contains("目录") || lower.contains("项目") || lower.contains("代码") || lower.contains("研究") || lower.contains("文件") {
            return "收到！我这就亲自去翻一下本地目录和代码，稍等几秒 👀"
        }
        return "好嘞，我这就动手帮你处理，马上回来汇报 🚀"
    }

    public static func narrateToolStep(_ call: PipiLLMToolCall, stepIndex: Int, lang: PipiResolvedLanguage) -> String {
        let isZh = (lang == .zhHans)
        switch call.name {
        case "list_directory":
            let shortName = shortPathLabel(call.string("path") ?? "目录")
            return isZh ? "正在翻看「\(shortName)」里面的目录结构 📂" : "Browsing \(shortName) 📂"
        case "read_file":
            let shortName = shortPathLabel(call.string("path") ?? "文件")
            return isZh ? "正在细读 \(shortName)，看看核心内容 🔍" : "Reading \(shortName) 🔍"
        case "search_files":
            let q = call.string("query") ?? ""
            return isZh ? "正在项目里搜索「\(q.prefix(24))」🔎" : "Searching for \"\(q.prefix(24))\" 🔎"
        case "write_file", "edit_file":
            let shortName = shortPathLabel(call.string("path") ?? "文件")
            return isZh ? "正在帮你修改 \(shortName) ✍️" : "Updating \(shortName) ✍️"
        case "run_shell":
            let cmd = call.string("command") ?? ""
            return isZh ? "在终端里跑一下检查：\(cmd.prefix(36)) ⚡" : "Running command: \(cmd.prefix(36)) ⚡"
        case "run_script":
            return isZh ? "正在本机沙箱引擎里运行脚本计算 ⚡" : "Running sandboxed JS script locally ⚡"
        case "get_system_status":
            return isZh ? "顺手看一眼你这台 Mac 的实时状态 💻" : "Checking your Mac's live health 💻"
        case "web_search", "fetch_webpage":
            let q = call.string("query") ?? call.string("url") ?? "资料"
            return isZh ? "去网上帮你搜一下「\(q.prefix(28))」🌐" : "Searching the web for \(q.prefix(28)) 🌐"
        case "capture_screenshot":
            return isZh ? "咔嚓！正在截屏并准备图片 📸" : "Snapping a screenshot 📸"
        case "record_screen":
            return isZh ? "正在录制一小段屏幕视频 🎬" : "Recording a short screen clip 🎬"
        case "synthesize_voice":
            return isZh ? "正在把回复合成语音发给你 🎙️" : "Synthesizing a voice message for you 🎙️"
        case "send_local_file":
            let shortName = shortPathLabel(call.string("path") ?? "文件")
            return isZh ? "找到啦！正在打包发送 \(shortName) 📎" : "Packaging \(shortName) to send 📎"
        case "render_visual_card":
            let title = call.string("title") ?? "卡片"
            return isZh ? "正在把「\(title.prefix(20))」渲染成高清图片卡片 🖼️" : "Rendering visual card \"\(title.prefix(20))\" 🖼️"
        case "generate_image":
            return isZh ? "正在帮你生成图片，马上出图 🎨" : "Generating your image 🎨"
        case "delegate_cli_agent":
            let agent = call.string("agent") ?? "codex"
            return isZh ? "叫上 \(agent) 一起深度分析，有结果马上同步你 🤝" : "Collaborating with \(agent) on this 🤝"
        case "read_calendar_and_reminders":
            return isZh ? "正在翻看你的 Apple 日历和提醒事项 📅" : "Checking your Calendar & Reminders 📅"
        case "create_routine_or_reminder":
            return isZh ? "正在把定时提醒/周期任务给你记到日程里 ⏰" : "Scheduling your routine/reminder ⏰"
        case "read_mail_or_sms":
            return isZh ? "正在帮你看最近的邮件/短信摘要 📬" : "Checking recent Mail/Messages 📬"
        case "send_mail_or_sms":
            return isZh ? "正在准备外发内容并做安全确认 ✉️" : "Preparing outbound message for confirmation ✉️"
        case "show_control_menu":
            return isZh ? "马上给你展开交互菜单 📋" : "Opening the control menu 📋"
        case "list_or_switch_bot", "create_bot", "switch_session_or_project", "configure_group_mode", "update_settings":
            return isZh ? "收到，正在帮你调整助手和配置 ⚙️" : "Updating your assistant settings ⚙️"
        case "check_updates":
            return isZh ? "正在查一下 GitHub 有没有新版本 🚀" : "Checking GitHub Releases for updates 🚀"
        case "trigger_list", "trigger_upsert", "trigger_delete":
            return isZh ? "正在管理自动化触发器 ⏱️" : "Managing automation triggers ⏱️"
        case "remote_nodes_list":
            return isZh ? "正在查看账号下已纳管的远程设备 🌐" : "Listing enrolled remote devices 🌐"
        case "remote_node_inspect":
            return isZh ? "正在通过端到端加密通道检查远程节点状态 🔍" : "Inspecting remote node over E2EE 🔍"
        case "remote_node_run_harness":
            return isZh ? "正在调度远程节点上的 Agent Harness 执行任务 🤖" : "Invoking remote node agent harness 🤖"
        case "remote_node_exec":
            return isZh ? "正在通过远程守护进程执行排查/开发操作 🛠️" : "Running remote daemon command 🛠️"
        case "browser_browse":
            let u = call.string("url") ?? "网页"
            return isZh ? "正在启动独立浏览器子代理打开并深度阅读 \(u.prefix(40)) 🌐" : "Browsing \(u.prefix(40)) with Web CUA subagent 🌐"
        case "browser_open":
            let u = call.string("url") ?? "网页"
            return isZh ? "正在用真实浏览器打开 \(u.prefix(40)) 并截取页面快照 🌐" : "Opening \(u.prefix(40)) in live browser 🌐"
        case "browser_act":
            let act = call.string("action") ?? "交互"
            return isZh ? "正在网页中执行 \(act) 操作并刷新视图 🖱️" : "Performing browser \(act) action 🖱️"
        case "browser_snapshot":
            return isZh ? "正在读取当前网页内容与视口截图 👀" : "Inspecting live browser viewport 👀"
        case "device_vision_ocr":
            return isZh ? "正在调用本机 Apple Vision NPU 识字与析图 🧠" : "Running on-device Apple Vision NPU OCR 🧠"
        case "device_clipboard":
            return isZh ? "正在访问本机剪贴板 📋" : "Accessing device clipboard 📋"
        case "device_npu_status":
            return isZh ? "正在检测本机 NPU 算力与设备状态 ⚡" : "Inspecting Apple Neural Engine status ⚡"
        default:
            return isZh ? "正在处理第 \(stepIndex) 步，马上好啦 ✨" : "Working on step \(stepIndex) ✨"
        }
    }

    private static func shortPathLabel(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "工作区" }
        let comps = trimmed.split(separator: "/").map(String.init)
        if comps.count >= 2 {
            return "\(comps[comps.count - 2])/\(comps[comps.count - 1])"
        }
        return comps.last ?? trimmed
    }
}

// MARK: - Tool Execution Result & Host Bridge Callbacks

public struct PipiAgentToolExecutionResult: Sendable {
    public let output: String
    public let artifacts: [PipiDeliverableArtifact]
    public let visionImages: [PipiEncodedImagePart]
    public let isError: Bool
    public let needsApproval: PipiToolRiskAssessment?

    public init(
        output: String,
        artifacts: [PipiDeliverableArtifact] = [],
        visionImages: [PipiEncodedImagePart] = [],
        isError: Bool = false,
        needsApproval: PipiToolRiskAssessment? = nil
    ) {
        self.output = output
        self.artifacts = artifacts
        self.visionImages = visionImages
        self.isError = isError
        self.needsApproval = needsApproval
    }
}

public struct PipiAgentHostCallbacks: Sendable {
    public var captureScreenshot: @Sendable () async -> PipiMacOmnipotentCommandResult
    public var recordScreen: @Sendable (Int) async -> PipiMacOmnipotentCommandResult
    public var synthesizeVoice: @Sendable (String) async -> PipiMacOmnipotentCommandResult
    public var prepareLocalFile: @Sendable (String) async -> PipiMacOmnipotentCommandResult
    public var registerArtifact: @Sendable (PipiDeliverableArtifact) async -> Void
    public var delegateCLIAgent: @Sendable (_ agent: String, _ mode: String, _ prompt: String, _ workingDirectory: String) async -> (succeeded: Bool, output: String)
    public var readCalendarAndReminders: @Sendable () async -> String
    public var createRoutineOrReminder: @Sendable (_ title: String, _ prompt: String, _ intervalMinutes: Int, _ scheduleHint: String) async -> String
    public var readMailOrSMS: @Sendable (_ channel: String, _ limit: Int) async -> String
    public var sendMailOrSMS: @Sendable (_ channel: String, _ recipient: String, _ subject: String, _ body: String) async -> PipiMacOmnipotentCommandResult
    public var showControlMenu: @Sendable () async -> String
    public var listOrSwitchBot: @Sendable (_ targetQuery: String?) async -> String
    public var createBot: @Sendable (_ name: String, _ role: String, _ modelId: String?) async -> String
    public var switchSessionOrProject: @Sendable (_ kind: String, _ query: String?) async -> String
    public var configureGroupMode: @Sendable (_ enable: Bool, _ memberQuery: String?) async -> String
    public var updateSettings: @Sendable (_ settingKey: String, _ value: String?) async -> String
    public var checkUpdates: @Sendable () async -> String
    public var materializeBlueprintBot: @Sendable (_ args: [String: String]) async -> String
    public var recordEntityLedger: @Sendable (_ entityKey: String, _ entityType: String, _ source: String, _ status: String, _ summary: String) async -> String
    public var queryEntityLedger: @Sendable (_ entityKey: String?, _ search: String?) async -> String
    public var proposeBlueprintEvolution: @Sendable (_ botQuery: String?, _ rationale: String, _ newRule: String?, _ newVerification: String?, _ newStepsCSV: String?) async -> String
    public var manageTriggers: @Sendable (_ action: String, _ args: [String: String]) async -> String
    public var remoteNodeAction: @Sendable (_ action: String, _ args: [String: String]) async -> String

    public init(
        captureScreenshot: @escaping @Sendable () async -> PipiMacOmnipotentCommandResult,
        recordScreen: @escaping @Sendable (Int) async -> PipiMacOmnipotentCommandResult,
        synthesizeVoice: @escaping @Sendable (String) async -> PipiMacOmnipotentCommandResult,
        prepareLocalFile: @escaping @Sendable (String) async -> PipiMacOmnipotentCommandResult,
        registerArtifact: @escaping @Sendable (PipiDeliverableArtifact) async -> Void,
        delegateCLIAgent: @escaping @Sendable (String, String, String, String) async -> (Bool, String),
        readCalendarAndReminders: @escaping @Sendable () async -> String,
        createRoutineOrReminder: @escaping @Sendable (String, String, Int, String) async -> String,
        readMailOrSMS: @escaping @Sendable (String, Int) async -> String,
        sendMailOrSMS: @escaping @Sendable (String, String, String, String) async -> PipiMacOmnipotentCommandResult,
        showControlMenu: @escaping @Sendable () async -> String,
        listOrSwitchBot: @escaping @Sendable (String?) async -> String,
        createBot: @escaping @Sendable (String, String, String?) async -> String,
        switchSessionOrProject: @escaping @Sendable (String, String?) async -> String,
        configureGroupMode: @escaping @Sendable (Bool, String?) async -> String,
        updateSettings: @escaping @Sendable (String, String?) async -> String,
        checkUpdates: @escaping @Sendable () async -> String,
        materializeBlueprintBot: @escaping @Sendable ([String: String]) async -> String = { _ in "Blueprint materialization is not connected in this host context." },
        recordEntityLedger: @escaping @Sendable (String, String, String, String, String) async -> String = { key, _, _, status, _ in "Recorded entity \(key) (\(status))." },
        queryEntityLedger: @escaping @Sendable (String?, String?) async -> String = { _, _ in "No matching entity records." },
        proposeBlueprintEvolution: @escaping @Sendable (String?, String, String?, String?, String?) async -> String = { _, rationale, _, _, _ in "Evolution proposal queued: \(rationale)" },
        manageTriggers: @escaping @Sendable (String, [String: String]) async -> String = { action, _ in "Trigger action '\(action)' queued." },
        remoteNodeAction: @escaping @Sendable (String, [String: String]) async -> String = { action, _ in "Remote node action '\(action)' is not connected in this host context." }
    ) {
        self.captureScreenshot = captureScreenshot
        self.recordScreen = recordScreen
        self.synthesizeVoice = synthesizeVoice
        self.prepareLocalFile = prepareLocalFile
        self.registerArtifact = registerArtifact
        self.delegateCLIAgent = delegateCLIAgent
        self.readCalendarAndReminders = readCalendarAndReminders
        self.createRoutineOrReminder = createRoutineOrReminder
        self.readMailOrSMS = readMailOrSMS
        self.sendMailOrSMS = sendMailOrSMS
        self.showControlMenu = showControlMenu
        self.listOrSwitchBot = listOrSwitchBot
        self.createBot = createBot
        self.switchSessionOrProject = switchSessionOrProject
        self.configureGroupMode = configureGroupMode
        self.updateSettings = updateSettings
        self.checkUpdates = checkUpdates
        self.materializeBlueprintBot = materializeBlueprintBot
        self.recordEntityLedger = recordEntityLedger
        self.queryEntityLedger = queryEntityLedger
        self.proposeBlueprintEvolution = proposeBlueprintEvolution
        self.manageTriggers = manageTriggers
        self.remoteNodeAction = remoteNodeAction
    }
}

// MARK: - Native Agent Toolbox Catalog & Executor

public enum PipiAgentToolbox {

    public static let allTools: [PipiAgentToolDefinition] = [
        PipiAgentToolDefinition(
            name: "list_directory",
            description: "List files and folders inside a directory on this Mac (supports ~, 桌面/Desktop, or absolute/workspace-relative paths). Use this first whenever the user asks about local folders or projects.",
            parameters: [
                PipiAgentToolParam(name: "path", description: "Directory path (e.g. ~/Desktop/Projects/FSD or 桌面/Projects/FSD or .)", required: true),
                PipiAgentToolParam(name: "max_depth", type: "integer", description: "Max recursion depth (1 to 3, default 2)", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "read_file",
            description: "Read the text contents of a local file (README, source code, config, logs). Supports optional line range.",
            parameters: [
                PipiAgentToolParam(name: "path", description: "File path to read", required: true),
                PipiAgentToolParam(name: "start_line", type: "integer", description: "1-based start line (optional)", required: false),
                PipiAgentToolParam(name: "end_line", type: "integer", description: "1-based end line (optional, max ~250 lines per call)", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "search_files",
            description: "Search file names or text inside a directory (skips .git, node_modules, .build).",
            parameters: [
                PipiAgentToolParam(name: "query", description: "Keyword or substring to search for", required: true),
                PipiAgentToolParam(name: "path", description: "Root directory to search (default current workspace)", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "write_file",
            description: "Create or overwrite a file with given UTF-8 content (auto-allowed inside workspace).",
            parameters: [
                PipiAgentToolParam(name: "path", description: "Destination file path", required: true),
                PipiAgentToolParam(name: "content", description: "Full file contents", required: true)
            ]
        ),
        PipiAgentToolDefinition(
            name: "edit_file",
            description: "Replace an exact target substring in an existing file.",
            parameters: [
                PipiAgentToolParam(name: "path", description: "Target file path", required: true),
                PipiAgentToolParam(name: "target", description: "Exact substring to replace", required: true),
                PipiAgentToolParam(name: "replacement", description: "Replacement text", required: true)
            ]
        ),
        PipiAgentToolDefinition(
            name: "run_shell",
            description: "Execute a shell command. On macOS runs native zsh (git, ls, swift, npm, python3, curl, etc.); on iPhone runs the built-in sandboxed POSIX shell (ls, cat, grep, wc, sort, find, curl, pipes, js) locally and automatically routes heavy desktop toolchains (python3, git, swift, npm, ffmpeg) to an online enrolled Mac/Linux host over E2EE. Prefer batching related steps with &&.",
            parameters: [
                PipiAgentToolParam(name: "command", description: "Shell command string to execute (compound commands encouraged for efficiency)", required: true),
                PipiAgentToolParam(name: "working_directory", description: "Optional working directory", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "run_script",
            description: "Execute sandboxed JavaScript directly on Apple's built-in JavaScriptCore engine (works offline on both iPhone and Mac with zero latency). Provides `console.log` and workspace-jailed `fs.read/write/append/list/exists/remove` for exact math, JSON/CSV transforms, data analysis, and file processing.",
            parameters: [
                PipiAgentToolParam(name: "code", description: "JavaScript source code to evaluate; return a value or use console.log()", required: true)
            ]
        ),
        PipiAgentToolDefinition(
            name: "get_system_status",
            description: "Inspect live Mac health: CPU/RAM/disk free space, top processes, and battery status.",
            parameters: []
        ),
        PipiAgentToolDefinition(
            name: "web_search",
            description: "Search the web for up-to-date information, news, documentation, or answers.",
            parameters: [
                PipiAgentToolParam(name: "query", description: "Search query", required: true)
            ]
        ),
        PipiAgentToolDefinition(
            name: "fetch_webpage",
            description: "Fast plain-HTTP fetch for static docs/JSON/API URLs. For JS-rendered sites (X/Twitter, SPAs, web apps, dashboards, or pages needing clicks/scrolling/screenshots), use `browser_browse` or `browser_open` instead.",
            parameters: [
                PipiAgentToolParam(name: "url", description: "Full URL to fetch", required: true)
            ]
        ),
        PipiAgentToolDefinition(
            name: "browser_browse",
            description: "Launch an isolated Web CUA (Computer Use Agent) Browser Subagent with real Chromium + visual screenshot feedback to open a JS-rendered webpage (X/Twitter posts, articles, dashboards, SPAs), scroll, click 'Show more'/tabs, read diagrams, and return a clean factual summary + evidence screenshot without bloating the main conversation.",
            parameters: [
                PipiAgentToolParam(name: "url", description: "Target http/https URL to open", required: true),
                PipiAgentToolParam(name: "goal", description: "Clear objective of what information to extract or verify on the site", required: true),
                PipiAgentToolParam(name: "use_signed_in_session", description: "Optional 'true' to attach to user's signed-in Chrome CDP (port 9222); default 'false' uses an isolated silent headless Chromium", required: false),
                PipiAgentToolParam(name: "max_steps", description: "Optional max browsing steps (default 8, max 12)", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "browser_open",
            description: "Open a URL in a live Chromium session, wait for full JS rendering, and return structured visible text, numbered interactive elements ([e1]..[eN]), and a live viewport screenshot for visual inspection.",
            parameters: [
                PipiAgentToolParam(name: "url", description: "Target http/https URL", required: true),
                PipiAgentToolParam(name: "use_signed_in_session", description: "Optional 'true' to attach to signed-in Chrome CDP on port 9222", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "browser_act",
            description: "Interact with the currently open live browser page (click by ref like 'e3', type text, scroll up/down/bottom, press_key, wait, back, reload) and return the updated DOM snapshot + viewport screenshot.",
            parameters: [
                PipiAgentToolParam(name: "action", description: "click | type | scroll | press_key | wait | back | reload", required: true),
                PipiAgentToolParam(name: "ref", description: "Interactive element ref from snapshot (e.g. 'e1', 'e7') for click/type", required: false),
                PipiAgentToolParam(name: "text", description: "Text to type when action=type", required: false),
                PipiAgentToolParam(name: "submit", description: "Set 'true' to press Enter after typing", required: false),
                PipiAgentToolParam(name: "direction", description: "down | up | top | bottom (for action=scroll)", required: false),
                PipiAgentToolParam(name: "key", description: "Key name (Enter, Escape, Tab, PageDown, Space) for action=press_key", required: false),
                PipiAgentToolParam(name: "seconds", description: "Seconds to wait (for action=wait)", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "browser_snapshot",
            description: "Capture a fresh structured DOM snapshot (visible text + numbered interactive elements) and live viewport screenshot from the current Chromium page.",
            parameters: []
        ),
        PipiAgentToolDefinition(
            name: "device_vision_ocr",
            description: "Run on-device Apple Neural Engine (Vision NPU) OCR, QR/barcode decoding, and scene tagging on a local image or screenshot file with zero cloud latency.",
            parameters: [
                PipiAgentToolParam(name: "path", description: "Local image file path (JPG/PNG/HEIC)", required: true)
            ]
        ),
        PipiAgentToolDefinition(
            name: "device_clipboard",
            description: "Read or write text on the user's iPhone/Mac system clipboard (UIPasteboard / NSPasteboard).",
            parameters: [
                PipiAgentToolParam(name: "operation", description: "read (default) | write", required: false),
                PipiAgentToolParam(name: "text", description: "Text to copy when operation=write", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "device_npu_status",
            description: "Inspect live Apple Neural Engine (NPU) readiness, thermal state, battery/low-power mode, Vision/Speech/NaturalLanguage/FoundationModels availability, and recommended local workload tier.",
            parameters: []
        ),
        PipiAgentToolDefinition(
            name: "capture_screenshot",
            description: "Capture a live screenshot of this Mac and attach/send it directly to the user in Mac chat and WeChat.",
            parameters: []
        ),
        PipiAgentToolDefinition(
            name: "record_screen",
            description: "Record a short screen video clip (3-15 seconds) and send it to the user.",
            parameters: [
                PipiAgentToolParam(name: "seconds", type: "integer", description: "Duration in seconds (default 5)", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "synthesize_voice",
            description: "Synthesize spoken audio (voice clip) from text and send it as an audio attachment to the user in Mac chat and WeChat. ALWAYS call this when the user asks you to send a voice message.",
            parameters: [
                PipiAgentToolParam(name: "text", description: "Natural spoken text to read aloud (concise, friendly, no markdown symbols)", required: true)
            ]
        ),
        PipiAgentToolDefinition(
            name: "send_local_file",
            description: "Package and send any existing local file or image from this Mac directly to the user in Mac chat and WeChat.",
            parameters: [
                PipiAgentToolParam(name: "path", description: "Absolute or ~/ path to the file or image", required: true)
            ]
        ),
        PipiAgentToolDefinition(
            name: "render_visual_card",
            description: "Render a crisp PNG visual summary / architecture diagram / checklist card image and send it directly to the user. Great when the user asks you to send a picture, chart, or visual report!",
            parameters: [
                PipiAgentToolParam(name: "title", description: "Card header title", required: true),
                PipiAgentToolParam(name: "body", description: "Structured bullet points, diagram text, or key summary lines", required: true),
                PipiAgentToolParam(name: "subtitle", description: "Optional short subtitle or tag", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "generate_image",
            description: "Generate an image from a prompt using the configured LLM provider's image API (falls back to a visual card if unsupported) and send it to the user.",
            parameters: [
                PipiAgentToolParam(name: "prompt", description: "Visual description of the image to create", required: true),
                PipiAgentToolParam(name: "title", description: "Short caption/title for fallback card", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "delegate_cli_agent",
            description: "Delegate heavy multi-file software engineering or deep codebase refactoring to an installed local CLI agent (codex / claude-code / opencode). For simple directory/file research, prefer list_directory + read_file directly first.",
            parameters: [
                PipiAgentToolParam(name: "agent", description: "Preferred CLI: codex, claude-code, or opencode", required: false),
                PipiAgentToolParam(name: "mode", description: "readonly or write", required: false, enumValues: ["readonly", "write"]),
                PipiAgentToolParam(name: "task", description: "Detailed engineering task instruction", required: true),
                PipiAgentToolParam(name: "working_directory", description: "Target directory path", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "read_calendar_and_reminders",
            description: "Read upcoming Apple Calendar events and due Apple Reminders on this Mac.",
            parameters: []
        ),
        PipiAgentToolDefinition(
            name: "create_routine_or_reminder",
            description: "Create a persistent scheduled routine or reminder that runs automatically and pushes results to Mac & WeChat.",
            parameters: [
                PipiAgentToolParam(name: "title", description: "Short title of the routine/reminder", required: true),
                PipiAgentToolParam(name: "prompt", description: "What PiPi should do or remind when triggered", required: true),
                PipiAgentToolParam(name: "interval_minutes", type: "integer", description: "Repeat interval in minutes (e.g. 30, 60, 1440 for daily)", required: false),
                PipiAgentToolParam(name: "schedule_hint", description: "Human-readable time expression (e.g. 每天早上9点, 30分钟后)", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "read_mail_or_sms",
            description: "Read recent Apple Mail emails or Messages SMS summaries.",
            parameters: [
                PipiAgentToolParam(name: "channel", description: "mail or sms", required: true, enumValues: ["mail", "sms"]),
                PipiAgentToolParam(name: "limit", type: "integer", description: "Number of recent items (default 6)", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "send_mail_or_sms",
            description: "Send an email or SMS (always asks user for safety confirmation before sending).",
            parameters: [
                PipiAgentToolParam(name: "channel", description: "mail or sms", required: true, enumValues: ["mail", "sms"]),
                PipiAgentToolParam(name: "recipient", description: "Recipient email address or phone/contact", required: true),
                PipiAgentToolParam(name: "subject", description: "Email subject (optional for SMS)", required: false),
                PipiAgentToolParam(name: "body", description: "Message body", required: true)
            ]
        ),
        PipiAgentToolDefinition(
            name: "show_control_menu",
            description: "Show PiPiBot's real interactive control menu (bots, sessions, projects, group mode, settings, updates).",
            parameters: []
        ),
        PipiAgentToolDefinition(
            name: "list_or_switch_bot",
            description: "List all available Bots or switch the active conversation Bot by name or role.",
            parameters: [
                PipiAgentToolParam(name: "target", description: "Optional Bot name/keyword to switch to; omit to list all Bots", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "create_bot",
            description: "Create a new Bot persona right away and optionally assign a model.",
            parameters: [
                PipiAgentToolParam(name: "name", description: "New Bot name", required: true),
                PipiAgentToolParam(name: "role", description: "Short role/responsibility description", required: true),
                PipiAgentToolParam(name: "model_id", description: "Optional specific model ID; omit to inherit default model", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "switch_session_or_project",
            description: "List, create, or switch conversations/sessions or bound projects.",
            parameters: [
                PipiAgentToolParam(name: "kind", description: "session or project", required: true, enumValues: ["session", "project"]),
                PipiAgentToolParam(name: "query", description: "Target name, 'new' to create a new session, or omit to list", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "configure_group_mode",
            description: "Enter or exit WeChat multi-bot Group Mode.",
            parameters: [
                PipiAgentToolParam(name: "enable", type: "boolean", description: "true to enter Group Mode, false to return to 1v1", required: true),
                PipiAgentToolParam(name: "members", description: "Optional bot names/keywords for group", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "update_settings",
            description: "Inspect or toggle PiPiBot settings (proactive_cli, llm_judge, typing, memory, auto_update, bot_model).",
            parameters: [
                PipiAgentToolParam(name: "key", description: "Setting key or 'status' to view current settings", required: true),
                PipiAgentToolParam(name: "value", description: "Optional value (e.g. model ID or on/off)", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "check_updates",
            description: "Check GitHub Releases for a newer PiPiBot version.",
            parameters: []
        ),
        PipiAgentToolDefinition(
            name: "materialize_blueprint_bot",
            description: "Create or upgrade an autonomous Bot with a full Goal-First Automation Blueprint (goal, process steps, source-of-truth rules, verification criteria, escalation rules, entity IDs) and an optional event/schedule Routine. Call this only after confirming the Goal & Process with the user.",
            parameters: [
                PipiAgentToolParam(name: "name", description: "Bot display name", required: true),
                PipiAgentToolParam(name: "role", description: "Concise one-line role summary", required: true),
                PipiAgentToolParam(name: "goal", description: "The true end Goal this Bot owns", required: true),
                PipiAgentToolParam(name: "process_steps", description: "Semicolon-separated ordered process steps (e.g. 'Step 1; Step 2; Step 3')", required: true),
                PipiAgentToolParam(name: "source_of_truth_rules", description: "Optional semicolon-separated conflict resolution rules", required: false),
                PipiAgentToolParam(name: "verification_criteria", description: "Optional semicolon-separated checks that define Done", required: false),
                PipiAgentToolParam(name: "escalation_rules", description: "Optional semicolon-separated conditions when the Bot must ask the owner", required: false),
                PipiAgentToolParam(name: "feedback_sources", description: "Optional semicolon-separated feedback sources for self-improvement", required: false),
                PipiAgentToolParam(name: "entity_ids", description: "Optional semicolon-separated cross-source entity ID names (e.g. 'order_id; customer_email')", required: false),
                PipiAgentToolParam(name: "trigger_kind", description: "Optional Routine trigger: schedule, webhook, file_or_git_watch, channel_message, or host_health", required: false),
                PipiAgentToolParam(name: "trigger_value", description: "Optional trigger detail (cron expr, watch path, keyword, or metric)", required: false),
                PipiAgentToolParam(name: "model_id", description: "Optional dedicated model ID; omit to inherit default model", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "record_entity_ledger",
            description: "Record or update a structured cross-source entity record (keyed by unique ID such as order_id, PR#, or customer_email) so the Bot remembers state across tools and runs.",
            parameters: [
                PipiAgentToolParam(name: "entity_key", description: "Unique entity identifier (e.g. PR-142, order_8821, alice@example.com)", required: true),
                PipiAgentToolParam(name: "entity_type", description: "Entity category (e.g. pr, customer, booking, task)", required: false),
                PipiAgentToolParam(name: "source", description: "Data source (e.g. github, wechat, email, local_git)", required: false),
                PipiAgentToolParam(name: "status", description: "Current lifecycle status (e.g. waiting_details, confirmed, resolved)", required: false),
                PipiAgentToolParam(name: "summary", description: "Concise structured summary of the latest known state", required: true)
            ]
        ),
        PipiAgentToolDefinition(
            name: "query_entity_ledger",
            description: "Search previously recorded cross-source entity ledger entries by entity_key or free-text query.",
            parameters: [
                PipiAgentToolParam(name: "entity_key", description: "Exact or partial entity key", required: false),
                PipiAgentToolParam(name: "search", description: "Keyword to search across entity summaries and sources", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "propose_blueprint_evolution",
            description: "Propose a structured EvolutionDiff improvement to a Bot's Automation Blueprint based on execution outcomes or feedback. Always routed for owner approval (never silently mutates rules).",
            parameters: [
                PipiAgentToolParam(name: "bot_query", description: "Optional Bot name or ID (defaults to current Bot)", required: false),
                PipiAgentToolParam(name: "rationale", description: "Why this change improves attainment of the original Goal", required: true),
                PipiAgentToolParam(name: "new_rule", description: "Optional new source-of-truth or decision rule to add", required: false),
                PipiAgentToolParam(name: "new_verification", description: "Optional new verification criterion to add", required: false),
                PipiAgentToolParam(name: "new_steps", description: "Optional semicolon-separated revised process steps", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "trigger_list",
            description: "List active or paused schedules, webhooks, and event triggers for this Bot or the workspace. Never exposes raw webhook secrets.",
            parameters: [
                PipiAgentToolParam(name: "bot_query", description: "Optional Bot name or ID filter", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "trigger_upsert",
            description: "Create, update, pause, or resume a schedule/webhook/file_watch/channel_message/host_health trigger. Webhook secrets are write-only and shown once to the human in UI, never returned to the bot.",
            parameters: [
                PipiAgentToolParam(name: "routine_id", description: "Existing routine ID to update (omit to create new)", required: false),
                PipiAgentToolParam(name: "title", description: "Short human-readable trigger title", required: true),
                PipiAgentToolParam(name: "prompt", description: "Task prompt executed when triggered", required: true),
                PipiAgentToolParam(name: "trigger_kind", description: "schedule | webhook | file_or_git_watch | channel_message | host_health", required: false),
                PipiAgentToolParam(name: "cron", description: "Optional 5-field cron expression", required: false),
                PipiAgentToolParam(name: "watch_path", description: "Optional directory or Git repo path for file_or_git_watch", required: false),
                PipiAgentToolParam(name: "enabled", description: "true or false", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "trigger_delete",
            description: "Delete a routine trigger by its ID.",
            parameters: [
                PipiAgentToolParam(name: "routine_id", description: "Routine ID to remove", required: true)
            ]
        ),
        PipiAgentToolDefinition(
            name: "remote_nodes_list",
            description: "List all enrolled machines/nodes under the user's unified PiPiBot account, including online status, platform, workspace path, and each node's reported local agent harnesses (e.g. Claude Code, Codex, OpenCode, Pi).",
            parameters: []
        ),
        PipiAgentToolDefinition(
            name: "remote_node_inspect",
            description: "Connect over E2EE to an enrolled remote node's daemon to inspect live system health (OS, CPU, memory, uptime, git branch/status), installed agent harnesses, and running agent sessions.",
            parameters: [
                PipiAgentToolParam(name: "device", description: "Target device name, hostId, or partial match (omit to auto-pick the first online remote node)", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "remote_node_run_harness",
            description: "Invoke an installed agent harness (such as Claude Code, Codex, OpenCode, or Pi) directly on an enrolled remote node over E2EE.",
            parameters: [
                PipiAgentToolParam(name: "device", description: "Target device name or hostId", required: true),
                PipiAgentToolParam(name: "agent", description: "Harness ID or name (e.g. claude-code, codex, opencode, pi). Omit to use the node's primary harness.", required: false),
                PipiAgentToolParam(name: "prompt", description: "Task prompt to execute on the remote node's harness", required: true),
                PipiAgentToolParam(name: "cwd", description: "Optional working directory on the remote node", required: false)
            ]
        ),
        PipiAgentToolDefinition(
            name: "remote_node_exec",
            description: "Connect directly through an enrolled remote node's daemon over E2EE to perform troubleshooting or development actions: run a bounded shell command, list a directory, or read a file. Batch multi-step inspection or fix+verify commands with && into one call to minimize network round-trips.",
            parameters: [
                PipiAgentToolParam(name: "device", description: "Target device name or hostId", required: true),
                PipiAgentToolParam(name: "operation", description: "exec (default) | list_files | read_file | upgrade (self-upgrade remote node CLI over E2EE)", required: false),
                PipiAgentToolParam(name: "command", description: "Shell command to execute when operation=exec (combine fix + verification in one command when safe)", required: false),
                PipiAgentToolParam(name: "path", description: "Directory or file path when operation=list_files or read_file", required: false),
                PipiAgentToolParam(name: "cwd", description: "Optional working directory when operation=exec", required: false),
                PipiAgentToolParam(name: "timeout_seconds", description: "Optional timeout in seconds (default 45, max 120; use 90-120 for npm/apt/build installs)", required: false)
            ]
        )
    ]

    /// Autonomous execution guardrails for the native Jarvis tool loop:
    /// detects premature "almost done / 1 line left / should I proceed?" mid-task handoffs
    /// and classifies read-only tools safe for concurrent batch execution.
    public enum ContinuationGuard {
        public static let defaultMaxSteps: Int = 20
        public static let maxAutoContinues: Int = 2

        private static let parallelReadOnlyTools: Set<String> = [
            "list_directory",
            "read_file",
            "search_files",
            "get_system_status",
            "web_search",
            "fetch_webpage",
            "read_calendar_and_reminders",
            "read_mail_or_sms",
            "remote_nodes_list",
            "remote_node_inspect",
            "query_entity_ledger",
            "trigger_list"
        ]

        public static func isReadOnlyParallelizableTool(_ name: String) -> Bool {
            parallelReadOnlyTools.contains(name)
        }

        /// Returns `true` when the assistant stopped emitting tool calls mid-task and produced a
        /// half-finished "almost there / one step left / should I fix it?" status update instead of
        /// finishing and verifying the work.
        public static func shouldAutoContinue(
            replyText: String,
            executedStepCount: Int,
            autoContinueCount: Int,
            maxAutoContinues: Int = ContinuationGuard.maxAutoContinues
        ) -> Bool {
            guard executedStepCount > 0, autoContinueCount < maxAutoContinues else { return false }
            let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            let lower = trimmed.lowercased()

            // Respect genuine hard blockers: approvals, credentials, explicit user choices
            let genuineBlockerSignals = [
                "审批", "确认卡片", "安全确认", "高危", "安全护栏",
                "需要你提供", "请提供", "密码", "token", "api key", "apikey", "密钥", "登录", "扫码",
                "不可逆", "无法连接", "离线", "not connected", "permission denied by user"
            ]
            if genuineBlockerSignals.contains(where: { lower.contains($0) }) {
                return false
            }

            // Respect verified completion signals
            let verifiedCompletionSignals = [
                "搞定，收工", "已搞定", "已全部完成", "已完成并验证", "验证通过", "exit=0",
                "all tests pass", "verified and complete", "已全局可用"
            ]
            if verifiedCompletionSignals.contains(where: { lower.contains($0) }) {
                return false
            }

            // Detect premature mid-task handoff / "almost done" / "should I proceed" phrasing
            let prematureStopSignals = [
                "还差最后", "就差一行", "就差最后一步", "还差一步", "还差一小步", "离成功就差",
                "快出锅", "修整汇报", "进度汇报", "阶段性汇报", "还没完全跑通",
                "要不要我继续", "要不要我直接", "要不要继续", "要我继续", "需要我继续",
                "等你指示", "下一步我打算", "如果你同意", "你定", "改吗", "继续改吗",
                "should i proceed", "would you like me to continue", "one last step left", "almost done, just need to"
            ]
            return prematureStopSignals.contains(where: { lower.contains($0) })
        }

        public static func continuationNudgePrompt() -> String {
            """
            [系统执行指令 · 禁止中途交球]
            不要停在半路汇报或反问主人。你刚才已经定位到了根因或下一步方案，且该操作在允许范围内——请立刻继续调用工具完成剩余修改，并运行验证命令确认真正跑通（如检查 exit=0 / 版本输出 / 测试通过），全部验证成功后再一次性把最终结果发给主人。尽量把修改与验证合并为一次 compound shell 命令以节省耗时。
            """
        }

        public static func remainingBudgetHint(remainingSteps: Int) -> String {
            "[步数提醒] 当前仅剩 \(remainingSteps) 轮工具调用额度。请把剩余修复动作和最终验证命令合并在一次执行中完成，确认成功后再直接给出最终结果。"
        }

        public static func repeatedCallPivotHint(toolName: String) -> String {
            "[防原地打转提醒] 你连续多次重复调用了相同的 `\(toolName)` 参数但未推进进展。请立即切换排查思路或合并命令直接验证根因，不要再重复执行相同命令。"
        }
    }

    /// Compact prompt-protocol instructions appended when an endpoint falls back from native `tools` JSON to `<pipi_tool>`.
    public static func structuredToolFallbackPrompt() -> String {
        let names = allTools.map { "\($0.name)(\($0.parameters.map(\.name).joined(separator: ", ")))" }.joined(separator: "\n- ")
        return """
        [Tool Invocation Fallback Format]
        If you need to invoke any local tool, emit one or more blocks using this exact XML tag format:
        <pipi_tool name="TOOL_NAME">{"arg":"value"}</pipi_tool>
        Available tools:
        - \(names)
        Wait for tool results before writing your final answer. Never fabricate file contents or command output.
        """
    }

    /// Parses `<pipi_tool name="...">...</pipi_tool>` tags from assistant text (used for non-function-calling models or fallback).
    public static func extractInlineToolCalls(from text: String) -> (calls: [PipiLLMToolCall], cleanedText: String) {
        let pattern = #"<pipi_tool\s+name="([^"]+)"\s*>([\s\S]*?)</pipi_tool>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ([], text)
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return ([], text) }

        var calls: [PipiLLMToolCall] = []
        for (idx, m) in matches.enumerated() where m.numberOfRanges >= 3 {
            let name = nsText.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            var rawJson = nsText.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if rawJson.isEmpty { rawJson = "{}" }
            calls.append(PipiLLMToolCall(
                id: "inline_\(idx + 1)_\(UUID().uuidString.prefix(6))",
                name: name,
                argumentsJSON: rawJson
            ))
        }
        let cleaned = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: nsText.length), withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (calls, cleaned)
    }

    /// Executes a single tool call after risk classification (returns `needsApproval` if caller must pause for user confirmation).
    public static func execute(
        toolCall: PipiLLMToolCall,
        workspaceDirectory: String,
        llmConfig: PipiLLMProviderConfig?,
        deliverablesDirectory: URL,
        callbacks: PipiAgentHostCallbacks,
        skipRiskCheck: Bool = false
    ) async -> PipiAgentToolExecutionResult {
        if !skipRiskCheck {
            let risk = PipiJarvisToolRiskEvaluator.evaluate(toolCall: toolCall, workspaceDirectory: workspaceDirectory)
            if risk.isHardDenied {
                return PipiAgentToolExecutionResult(
                    output: "🛡️ 安全护栏已拦截高危操作：\(risk.reason)",
                    isError: true,
                    needsApproval: risk
                )
            }
            if risk.requiresApproval {
                return PipiAgentToolExecutionResult(
                    output: "⏸️ 该操作需要安全确认：\(risk.reason)",
                    isError: false,
                    needsApproval: risk
                )
            }
        }

        switch toolCall.name {
        case "list_directory":
            let rawPath = toolCall.string("path") ?? workspaceDirectory
            let depth = min(3, max(1, toolCall.int("max_depth") ?? 2))
            let resolved = PipiJarvisToolRiskEvaluator.resolveExpandedPath(rawPath, workspaceDirectory: workspaceDirectory)
            return executeListDirectory(path: resolved, maxDepth: depth)

        case "read_file":
            let rawPath = toolCall.string("path") ?? ""
            let resolved = PipiJarvisToolRiskEvaluator.resolveExpandedPath(rawPath, workspaceDirectory: workspaceDirectory)
            return executeReadFile(path: resolved, startLine: toolCall.int("start_line"), endLine: toolCall.int("end_line"))

        case "search_files":
            let query = toolCall.string("query") ?? ""
            let rawPath = toolCall.string("path") ?? workspaceDirectory
            let resolved = PipiJarvisToolRiskEvaluator.resolveExpandedPath(rawPath, workspaceDirectory: workspaceDirectory)
            return executeSearchFiles(query: query, rootPath: resolved)

        case "write_file":
            let rawPath = toolCall.string("path") ?? ""
            let content = toolCall.string("content") ?? (toolCall.argumentsDictionary()["content"] as? String ?? "")
            let resolved = PipiJarvisToolRiskEvaluator.resolveExpandedPath(rawPath, workspaceDirectory: workspaceDirectory)
            return executeWriteFile(path: resolved, content: content)

        case "edit_file":
            let rawPath = toolCall.string("path") ?? ""
            let dict = toolCall.argumentsDictionary()
            let target = dict["target"] as? String ?? ""
            let replacement = dict["replacement"] as? String ?? ""
            let resolved = PipiJarvisToolRiskEvaluator.resolveExpandedPath(rawPath, workspaceDirectory: workspaceDirectory)
            return executeEditFile(path: resolved, target: target, replacement: replacement)

        case "run_shell":
            let cmd = toolCall.string("command") ?? ""
            let rawCwd = toolCall.string("working_directory") ?? workspaceDirectory
            let cwd = PipiJarvisToolRiskEvaluator.resolveExpandedPath(rawCwd, workspaceDirectory: workspaceDirectory)
            return await executeRunShell(command: cmd, workingDirectory: cwd, callbacks: callbacks)

        case "run_script":
            let code = (toolCall.argumentsDictionary()["code"] as? String) ?? (toolCall.string("code") ?? "")
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return PipiAgentToolExecutionResult(output: "run_script 的 code 参数不能为空。", isError: true)
            }
            let shell: PipiMobileSandboxShell
            if !workspaceDirectory.isEmpty, FileManager.default.fileExists(atPath: workspaceDirectory) {
                shell = PipiMobileSandboxShell(rootDirectory: URL(fileURLWithPath: workspaceDirectory, isDirectory: true))
            } else {
                shell = PipiMobileSandboxShell.shared
            }
            let res = await shell.runJavaScript(trimmed, source: "agent", recordTranscript: true)
            let header = "[JavaScriptCore Sandbox · exit \(res.exitCode) · \(res.durationMs)ms]"
            return PipiAgentToolExecutionResult(
                output: "\(header)\n\(res.combinedOutput)",
                isError: res.exitCode != 0
            )

        case "get_system_status":
            return await executeGetSystemStatus()

        case "web_search":
            let query = toolCall.string("query") ?? ""
            return await executeWebSearch(query: query)

        case "fetch_webpage":
            let urlStr = toolCall.string("url") ?? ""
            return await executeFetchWebpage(urlString: urlStr)

        case "capture_screenshot":
            let res = await callbacks.captureScreenshot()
            return PipiAgentToolExecutionResult(output: res.summary, artifacts: res.artifacts, isError: !res.succeeded)

        case "record_screen":
            let secs = min(15, max(3, toolCall.int("seconds") ?? 5))
            let res = await callbacks.recordScreen(secs)
            return PipiAgentToolExecutionResult(output: res.summary, artifacts: res.artifacts, isError: !res.succeeded)

        case "synthesize_voice":
            let text = toolCall.string("text") ?? ""
            guard !text.isEmpty else {
                return PipiAgentToolExecutionResult(output: "语音文本不能为空", isError: true)
            }
            let res = await callbacks.synthesizeVoice(text)
            return PipiAgentToolExecutionResult(output: res.summary, artifacts: res.artifacts, isError: !res.succeeded)

        case "send_local_file":
            let rawPath = toolCall.string("path") ?? ""
            let resolved = PipiJarvisToolRiskEvaluator.resolveExpandedPath(rawPath, workspaceDirectory: workspaceDirectory)
            let res = await callbacks.prepareLocalFile(resolved)
            return PipiAgentToolExecutionResult(output: res.summary, artifacts: res.artifacts, isError: !res.succeeded)

        case "render_visual_card":
            let title = toolCall.string("title") ?? "PiPiBot 摘要卡片"
            let body = (toolCall.argumentsDictionary()["body"] as? String) ?? ""
            let subtitle = toolCall.string("subtitle")
            if let art = renderVisualCardPNG(title: title, subtitle: subtitle, body: body, deliverablesDir: deliverablesDirectory) {
                await callbacks.registerArtifact(art)
                return PipiAgentToolExecutionResult(
                    output: "已生成可视化图片卡片：\(art.fileName)（将直接作为图片附件发送给用户）",
                    artifacts: [art],
                    isError: false
                )
            }
            return PipiAgentToolExecutionResult(output: "图片渲染失败，请改用文字回复。", isError: true)

        case "generate_image":
            let prompt = toolCall.string("prompt") ?? ""
            let title = toolCall.string("title") ?? "PiPiBot 创作图"
            if let llmConfig, let art = await executeOpenAIImageGeneration(prompt: prompt, config: llmConfig, deliverablesDir: deliverablesDirectory) {
                await callbacks.registerArtifact(art)
                return PipiAgentToolExecutionResult(
                    output: "已通过模型绘图接口生成图片：\(art.fileName)",
                    artifacts: [art],
                    isError: false
                )
            }
            // Graceful fallback to visual card so user always gets a real image deliverable
            if let fallbackArt = renderVisualCardPNG(
                title: title,
                subtitle: "当前模型未开启独立绘图接口 · 已自动生成精美图文卡片",
                body: prompt,
                deliverablesDir: deliverablesDirectory
            ) {
                await callbacks.registerArtifact(fallbackArt)
                return PipiAgentToolExecutionResult(
                    output: "当前默认模型不支持独立生图接口，已为你生成高清图文卡片：\(fallbackArt.fileName)",
                    artifacts: [fallbackArt],
                    isError: false
                )
            }
            return PipiAgentToolExecutionResult(output: "当前模型不支持生图且卡片渲染失败。", isError: true)

        case "delegate_cli_agent":
            let agent = toolCall.string("agent") ?? "codex"
            let mode = toolCall.string("mode") ?? "readonly"
            let task = toolCall.string("task") ?? ""
            let rawDir = toolCall.string("working_directory") ?? workspaceDirectory
            let dir = PipiJarvisToolRiskEvaluator.resolveExpandedPath(rawDir, workspaceDirectory: workspaceDirectory)
            let res = await callbacks.delegateCLIAgent(agent, mode, task, dir)
            return PipiAgentToolExecutionResult(output: res.output, isError: !res.succeeded)

        case "read_calendar_and_reminders":
            let text = await callbacks.readCalendarAndReminders()
            return PipiAgentToolExecutionResult(output: text)

        case "create_routine_or_reminder":
            let title = toolCall.string("title") ?? "定时提醒"
            let prompt = toolCall.string("prompt") ?? title
            let interval = max(1, toolCall.int("interval_minutes") ?? 1440)
            let hint = toolCall.string("schedule_hint") ?? "每 \(interval) 分钟"
            let text = await callbacks.createRoutineOrReminder(title, prompt, interval, hint)
            return PipiAgentToolExecutionResult(output: text)

        case "read_mail_or_sms":
            let channel = (toolCall.string("channel") ?? "mail").lowercased()
            let limit = min(15, max(1, toolCall.int("limit") ?? 6))
            let text = await callbacks.readMailOrSMS(channel, limit)
            return PipiAgentToolExecutionResult(output: text)

        case "send_mail_or_sms":
            let channel = (toolCall.string("channel") ?? "mail").lowercased()
            let recipient = toolCall.string("recipient") ?? ""
            let subject = toolCall.string("subject") ?? "来自 PiPiBot 的消息"
            let body = (toolCall.argumentsDictionary()["body"] as? String) ?? ""
            let res = await callbacks.sendMailOrSMS(channel, recipient, subject, body)
            return PipiAgentToolExecutionResult(output: res.summary, artifacts: res.artifacts, isError: !res.succeeded)

        case "show_control_menu":
            return PipiAgentToolExecutionResult(output: await callbacks.showControlMenu())

        case "list_or_switch_bot":
            return PipiAgentToolExecutionResult(output: await callbacks.listOrSwitchBot(toolCall.string("target")))

        case "create_bot":
            let name = toolCall.string("name") ?? "新助手"
            let role = toolCall.string("role") ?? "智能助手"
            let modelId = toolCall.string("model_id")
            return PipiAgentToolExecutionResult(output: await callbacks.createBot(name, role, modelId))

        case "switch_session_or_project":
            let kind = (toolCall.string("kind") ?? "session").lowercased()
            return PipiAgentToolExecutionResult(output: await callbacks.switchSessionOrProject(kind, toolCall.string("query")))

        case "configure_group_mode":
            let enable = toolCall.bool("enable") ?? true
            return PipiAgentToolExecutionResult(output: await callbacks.configureGroupMode(enable, toolCall.string("members")))

        case "update_settings":
            let key = toolCall.string("key") ?? "status"
            return PipiAgentToolExecutionResult(output: await callbacks.updateSettings(key, toolCall.string("value")))

        case "check_updates":
            return PipiAgentToolExecutionResult(output: await callbacks.checkUpdates())

        case "materialize_blueprint_bot":
            var payload: [String: String] = [:]
            for key in ["name", "role", "goal", "process_steps", "source_of_truth_rules",
                        "verification_criteria", "escalation_rules", "feedback_sources",
                        "entity_ids", "trigger_kind", "trigger_value", "model_id"] {
                if let val = toolCall.string(key) {
                    payload[key] = val
                }
            }
            return PipiAgentToolExecutionResult(output: await callbacks.materializeBlueprintBot(payload))

        case "record_entity_ledger":
            let key = toolCall.string("entity_key") ?? "entity_\(UUID().uuidString.prefix(6))"
            let type = toolCall.string("entity_type") ?? "generic"
            let source = toolCall.string("source") ?? "pipibot"
            let status = toolCall.string("status") ?? "active"
            let summary = toolCall.string("summary") ?? ""
            return PipiAgentToolExecutionResult(
                output: await callbacks.recordEntityLedger(key, type, source, status, summary)
            )

        case "query_entity_ledger":
            return PipiAgentToolExecutionResult(
                output: await callbacks.queryEntityLedger(toolCall.string("entity_key"), toolCall.string("search"))
            )

        case "propose_blueprint_evolution":
            let rationale = toolCall.string("rationale") ?? "Workflow optimization against Goal"
            return PipiAgentToolExecutionResult(
                output: await callbacks.proposeBlueprintEvolution(
                    toolCall.string("bot_query"),
                    rationale,
                    toolCall.string("new_rule"),
                    toolCall.string("new_verification"),
                    toolCall.string("new_steps")
                )
            )

        case "trigger_list", "trigger_upsert", "trigger_delete":
            var argMap: [String: String] = [:]
            for key in ["bot_query", "routine_id", "title", "prompt", "trigger_kind", "cron", "watch_path", "enabled"] {
                if let val = toolCall.string(key) { argMap[key] = val }
            }
            return PipiAgentToolExecutionResult(
                output: await callbacks.manageTriggers(toolCall.name, argMap)
            )

        case "remote_nodes_list", "remote_node_inspect", "remote_node_run_harness", "remote_node_exec":
            var argMap: [String: String] = [:]
            for key in ["device", "agent", "prompt", "cwd", "operation", "command", "path", "timeout_seconds"] {
                if let val = toolCall.string(key) { argMap[key] = val }
            }
            return PipiAgentToolExecutionResult(
                output: await callbacks.remoteNodeAction(toolCall.name, argMap)
            )

        case "browser_browse":
            let urlStr = toolCall.string("url") ?? ""
            let goal = toolCall.string("goal") ?? "Extract and summarize the full page content."
            let useSignedIn = (toolCall.string("use_signed_in_session") ?? "").lowercased() == "true"
            let maxSteps = toolCall.int("max_steps") ?? 8
            guard let cfg = llmConfig else {
                // Fallback to single live browser_open snapshot when no LLM config was passed
                return await executeBrowserOpen(urlString: urlStr, useSignedIn: useSignedIn, deliverablesDir: deliverablesDirectory, callbacks: callbacks)
            }
            do {
                let res = try await PipiBrowserCUASubagent.run(
                    url: urlStr,
                    goal: goal,
                    llmConfig: cfg,
                    deliverablesDirectory: deliverablesDirectory,
                    useSignedInSession: useSignedIn,
                    maxSteps: maxSteps
                )
                if let blocked = res.blockedAssessment {
                    return PipiAgentToolExecutionResult(
                        output: res.summary,
                        visionImages: res.latestImage.map { [$0] } ?? [],
                        isError: false,
                        needsApproval: blocked
                    )
                }
                let visitedLine = res.visitedURLs.isEmpty ? "" : "\n\n[Visited: \(res.visitedURLs.joined(separator: ", ")) · \(res.stepsExecuted) step(s)]"
                return PipiAgentToolExecutionResult(
                    output: res.summary + visitedLine,
                    visionImages: res.latestImage.map { [$0] } ?? [],
                    isError: false
                )
            } catch {
                return PipiAgentToolExecutionResult(
                    output: "浏览器子代理执行失败：\(error.localizedDescription)",
                    isError: true
                )
            }

        case "browser_open":
            let urlStr = toolCall.string("url") ?? ""
            let useSignedIn = (toolCall.string("use_signed_in_session") ?? "").lowercased() == "true"
            return await executeBrowserOpen(urlString: urlStr, useSignedIn: useSignedIn, deliverablesDir: deliverablesDirectory, callbacks: callbacks)

        case "browser_act":
            let kind = PipiBrowserCUAActionKind(rawValue: (toolCall.string("action") ?? "scroll").lowercased()) ?? .scroll
            let req = PipiBrowserCUAActionRequest(
                action: kind,
                ref: toolCall.string("ref"),
                text: toolCall.string("text"),
                key: toolCall.string("key"),
                direction: toolCall.string("direction"),
                seconds: toolCall.int("seconds").map { Double($0) },
                submit: (toolCall.string("submit") ?? "").lowercased() == "true"
            )
            do {
                let (snap, blocked) = try await PipiBrowserCUADriver.shared.perform(
                    request: req,
                    deliverablesDirectory: deliverablesDirectory,
                    skipSafetyCheck: skipRiskCheck
                )
                if let blocked {
                    return PipiAgentToolExecutionResult(
                        output: "⏸️ 浏览器操作触发安全护栏：\(blocked.summary) — \(blocked.reason)",
                        visionImages: snap.encodedImagePart.map { [$0] } ?? [],
                        isError: false,
                        needsApproval: blocked
                    )
                }
                return PipiAgentToolExecutionResult(
                    output: snap.formattedForModel(),
                    visionImages: snap.encodedImagePart.map { [$0] } ?? [],
                    isError: false
                )
            } catch {
                return PipiAgentToolExecutionResult(
                    output: "浏览器交互失败：\(error.localizedDescription)",
                    isError: true
                )
            }

        case "browser_snapshot":
            do {
                let snap = try await PipiBrowserCUADriver.shared.captureSnapshot(deliverablesDirectory: deliverablesDirectory)
                return PipiAgentToolExecutionResult(
                    output: snap.formattedForModel(),
                    visionImages: snap.encodedImagePart.map { [$0] } ?? [],
                    isError: false
                )
            } catch {
                return PipiAgentToolExecutionResult(
                    output: "获取当前页面快照失败：\(error.localizedDescription)",
                    isError: true
                )
            }

        case "device_vision_ocr":
            let rawPath = toolCall.string("path") ?? ""
            let resolved = PipiJarvisToolRiskEvaluator.resolveExpandedPath(rawPath, workspaceDirectory: workspaceDirectory)
            guard let res = await PipiOnDeviceNPUEngine.analyzeImageFile(at: resolved) else {
                return PipiAgentToolExecutionResult(output: "无法读取或解析图片文件：\(resolved)", isError: true)
            }
            return PipiAgentToolExecutionResult(output: res.formattedSummary(), isError: false)

        case "device_clipboard":
            let op = (toolCall.string("operation") ?? "read").lowercased()
            if op == "write" {
                let text = toolCall.string("text") ?? ""
                await MainActor.run { PipiOnDeviceNPUEngine.writeClipboardText(text) }
                return PipiAgentToolExecutionResult(output: "已写入系统剪贴板（\(text.count) 字符）。", isError: false)
            }
            let clip = await MainActor.run { PipiOnDeviceNPUEngine.readClipboardText() } ?? ""
            if clip.isEmpty {
                return PipiAgentToolExecutionResult(output: "当前系统剪贴板为空。", isError: false)
            }
            return PipiAgentToolExecutionResult(output: "[System Clipboard]\n\(clip.prefix(4000))", isError: false)

        case "device_npu_status":
            let p = await MainActor.run { PipiOnDeviceNPUEngine.currentProfile() }
            let batteryLine = p.batteryLevelPercent.map { "\($0)% (\(p.isCharging ? "charging" : "battery"))" } ?? "AC / N/A"
            let summary = """
            [Apple Device & Neural Engine Status]
            Platform: \(p.platform) · \(p.processorCount) cores · \(p.physicalMemoryGB) GB unified memory
            Thermal: \(p.thermalState) · Low Power Mode: \(p.isLowPowerMode) · Battery: \(batteryLine)
            Recommended NPU Tier: \(p.recommendedTier.rawValue)
            On-Device Capabilities:
            - Apple Vision NPU (OCR / QR / Scene): \(p.supportsVisionNPU ? "ready" : "unavailable")
            - On-Device Speech NPU (STT): \(p.supportsOnDeviceSpeechNPU ? "ready" : "cloud fallback")
            - NaturalLanguage NPU (Entities / Embeddings): \(p.supportsNaturalLanguageNPU ? "ready" : "unavailable")
            - Apple Foundation Models (On-Device 3B LLM): \(p.supportsAppleFoundationModels ? "available" : "not on this OS")
            """
            return PipiAgentToolExecutionResult(output: summary, isError: false)

        default:
            return PipiAgentToolExecutionResult(output: "未知工具：\(toolCall.name)", isError: true)
        }
    }

    private static func executeBrowserOpen(
        urlString: String,
        useSignedIn: Bool,
        deliverablesDir: URL,
        callbacks: PipiAgentHostCallbacks
    ) async -> PipiAgentToolExecutionResult {
        do {
            let snap = try await PipiBrowserCUADriver.shared.navigate(
                url: urlString,
                useSignedInSession: useSignedIn,
                deliverablesDirectory: deliverablesDir
            )
            return PipiAgentToolExecutionResult(
                output: snap.formattedForModel(),
                visionImages: snap.encodedImagePart.map { [$0] } ?? [],
                isError: false
            )
        } catch {
            return PipiAgentToolExecutionResult(
                output: "真实浏览器打开网页失败：\(error.localizedDescription)",
                isError: true
            )
        }
    }

    // MARK: - Native Filesystem, Shell, System, Web & Visual Card Implementations

    private static let ignoredDirNames: Set<String> = [
        ".git", "node_modules", ".build", "DerivedData", ".next", "dist", "__pycache__", ".venv", "venv", ".DS_Store"
    ]

    private static func executeListDirectory(path: String, maxDepth: Int) -> PipiAgentToolExecutionResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            return PipiAgentToolExecutionResult(output: "目录不存在：\(path)", isError: true)
        }
        guard isDir.boolValue else {
            return PipiAgentToolExecutionResult(output: "该路径是一个文件而非目录：\(path)，请直接用 read_file 读取。", isError: false)
        }

        var lines: [String] = ["📂 \(path)"]
        var itemCount = 0
        let maxItems = 180

        func walk(_ dirPath: String, depth: Int, prefix: String) {
            guard depth <= maxDepth, itemCount < maxItems else { return }
            guard let names = try? fm.contentsOfDirectory(atPath: dirPath).sorted() else { return }
            for name in names {
                if ignoredDirNames.contains(name) { continue }
                if itemCount >= maxItems {
                    lines.append("\(prefix)... (已截断，仅展示前 \(maxItems) 项)")
                    return
                }
                let child = (dirPath as NSString).appendingPathComponent(name)
                var childIsDir: ObjCBool = false
                fm.fileExists(atPath: child, isDirectory: &childIsDir)
                itemCount += 1
                if childIsDir.boolValue {
                    lines.append("\(prefix)📁 \(name)/")
                    if depth < maxDepth {
                        walk(child, depth: depth + 1, prefix: prefix + "  ")
                    }
                } else {
                    let size = (try? fm.attributesOfItem(atPath: child)[.size] as? NSNumber)?.intValue ?? 0
                    lines.append("\(prefix)📄 \(name) (\(formatBytes(size)))")
                }
            }
        }

        walk(path, depth: 1, prefix: "  ")
        if lines.count == 1 {
            lines.append("  (空目录)")
        }
        return PipiAgentToolExecutionResult(output: lines.joined(separator: "\n"))
    }

    private static func executeReadFile(path: String, startLine: Int?, endLine: Int?) -> PipiAgentToolExecutionResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else {
            return PipiAgentToolExecutionResult(output: "文件不存在：\(path)", isError: true)
        }
        let fileURL = URL(fileURLWithPath: path)
        let ext = fileURL.pathExtension.lowercased()
        let text: String
        if PipiDocumentExtractor.officeAndRichDocExtensions.contains(ext) {
            guard let extracted = PipiDocumentExtractor.extractText(from: fileURL, maxChars: 60_000), !extracted.isEmpty else {
                return PipiAgentToolExecutionResult(output: "未能从该文档提取出有效文本内容：\(path)", isError: true)
            }
            text = extracted
        } else {
            guard let data = try? Data(contentsOf: fileURL) else {
                return PipiAgentToolExecutionResult(output: "无法读取文件（可能无权限或被占用）：\(path)", isError: true)
            }
            let maxRaw = 512 * 1024
            let slice = data.count > maxRaw ? data.prefix(maxRaw) : data
            guard let decoded = String(data: slice, encoding: .utf8) ?? PipiDocumentExtractor.extractText(from: fileURL, maxChars: 60_000) else {
                return PipiAgentToolExecutionResult(output: "该文件为二进制文件（\(formatBytes(data.count))），无法按纯文本读取。", isError: true)
            }
            text = decoded
        }

        let allLines = text.components(separatedBy: .newlines)
        let start = max(1, startLine ?? 1)
        let defaultEnd = min(allLines.count, start + 220)
        let end = min(allLines.count, max(start, endLine ?? defaultEnd))
        guard start <= allLines.count else {
            return PipiAgentToolExecutionResult(output: "文件共 \(allLines.count) 行，请求的起始行 \(start) 超出范围。", isError: false)
        }

        var out: [String] = ["📄 \(path) (lines \(start)-\(end) of \(allLines.count))"]
        var totalChars = 0
        for lineNo in start...end {
            let line = allLines[lineNo - 1]
            totalChars += line.count + 8
            if totalChars > 14_000 {
                out.append("... (输出已截断至 ~14KB，可指定 start_line/end_line 分段继续读)")
                break
            }
            out.append("\(lineNo): \(line)")
        }
        return PipiAgentToolExecutionResult(output: out.joined(separator: "\n"))
    }

    private static func executeSearchFiles(query: String, rootPath: String) -> PipiAgentToolExecutionResult {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            return PipiAgentToolExecutionResult(output: "搜索关键词不能为空。", isError: true)
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootPath) else {
            return PipiAgentToolExecutionResult(output: "搜索目录不存在：\(rootPath)", isError: true)
        }

        let lowerQ = q.lowercased()
        var fileHits: [String] = []
        var contentHits: [String] = []
        var scannedFiles = 0

        if let enumerator = fm.enumerator(atPath: rootPath) {
            while let rel = enumerator.nextObject() as? String {
                let comps = rel.split(separator: "/").map(String.init)
                if comps.contains(where: { ignoredDirNames.contains($0) }) {
                    enumerator.skipDescendants()
                    continue
                }
                if rel.lowercased().contains(lowerQ) && fileHits.count < 25 {
                    fileHits.append(rel)
                }
                let full = (rootPath as NSString).appendingPathComponent(rel)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue {
                    scannedFiles += 1
                    if scannedFiles > 800 || contentHits.count >= 35 { continue }
                    let size = (try? fm.attributesOfItem(atPath: full)[.size] as? NSNumber)?.intValue ?? 0
                    guard size > 0 && size < 256 * 1024,
                          let text = try? String(contentsOfFile: full, encoding: .utf8) else { continue }
                    if text.lowercased().contains(lowerQ) {
                        for (idx, line) in text.components(separatedBy: .newlines).enumerated() {
                            if line.lowercased().contains(lowerQ) {
                                contentHits.append("\(rel):\(idx + 1): \(line.trimmingCharacters(in: .whitespaces).prefix(120))")
                                if contentHits.count >= 35 { break }
                            }
                        }
                    }
                }
            }
        }

        var parts: [String] = ["🔎 搜索「\(q)」@ \(rootPath)"]
        if !fileHits.isEmpty {
            parts.append("匹配文件名：\n" + fileHits.map { "  • \($0)" }.joined(separator: "\n"))
        }
        if !contentHits.isEmpty {
            parts.append("匹配内容：\n" + contentHits.map { "  • \($0)" }.joined(separator: "\n"))
        }
        if fileHits.isEmpty && contentHits.isEmpty {
            parts.append("未找到匹配项（已扫描 \(scannedFiles) 个文件）。")
        }
        return PipiAgentToolExecutionResult(output: parts.joined(separator: "\n\n"))
    }

    private static func executeWriteFile(path: String, content: String) -> PipiAgentToolExecutionResult {
        let url = URL(fileURLWithPath: path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            return PipiAgentToolExecutionResult(output: "✅ 已写入文件：\(path)（\(content.utf8.count) 字节）")
        } catch {
            return PipiAgentToolExecutionResult(output: "写入文件失败：\(error.localizedDescription)", isError: true)
        }
    }

    private static func executeEditFile(path: String, target: String, replacement: String) -> PipiAgentToolExecutionResult {
        guard !target.isEmpty else {
            return PipiAgentToolExecutionResult(output: "edit_file 的 target 不能为空。", isError: true)
        }
        let url = URL(fileURLWithPath: path)
        guard let original = try? String(contentsOf: url, encoding: .utf8) else {
            return PipiAgentToolExecutionResult(output: "无法读取待编辑文件：\(path)", isError: true)
        }
        guard original.contains(target) else {
            return PipiAgentToolExecutionResult(output: "未在 \(path) 中找到精确匹配的目标文本。", isError: true)
        }
        let updated = original.replacingOccurrences(of: target, with: replacement)
        do {
            try updated.write(to: url, atomically: true, encoding: .utf8)
            return PipiAgentToolExecutionResult(output: "✅ 已更新文件：\(path)")
        } catch {
            return PipiAgentToolExecutionResult(output: "保存编辑失败：\(error.localizedDescription)", isError: true)
        }
    }

    private static func executeRunShell(
        command: String,
        workingDirectory: String,
        callbacks: PipiAgentHostCallbacks? = nil
    ) async -> PipiAgentToolExecutionResult {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PipiAgentToolExecutionResult(output: "命令为空。", isError: true)
        }
        #if os(macOS)
        let started = Date()
        let cwd = FileManager.default.fileExists(atPath: workingDirectory) ? workingDirectory : NSHomeDirectory()
        let execResult = await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-lc", trimmed]
            proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
            var env = ProcessInfo.processInfo.environment
            let extra = PipiNativeMacRuntime.searchBinaryPaths().joined(separator: ":")
            let existing = env["PATH"] ?? ""
            env["PATH"] = existing.isEmpty ? extra : "\(extra):\(existing)"
            env["NO_COLOR"] = "1"
            proc.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            proc.standardInput = FileHandle.nullDevice

            do {
                try proc.run()
            } catch {
                return (exitCode: 127, output: "无法启动命令：\(error.localizedDescription)", isError: true)
            }

            let deadline = Date().addingTimeInterval(35)
            while proc.isRunning && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            var timedOut = false
            if proc.isRunning {
                timedOut = true
                proc.terminate()
                try? await Task.sleep(for: .milliseconds(200))
            }

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let outStr = PipiInferenceEngine.stripAnsiEscapeCodes(String(data: outData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let errStr = PipiInferenceEngine.stripAnsiEscapeCodes(String(data: errData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            var combined = [outStr, errStr.isEmpty ? "" : "[stderr]\n\(errStr)"].filter { !$0.isEmpty }.joined(separator: "\n")
            if combined.count > 10_000 {
                combined = String(combined.prefix(10_000)) + "\n... (输出已截断)"
            }
            if timedOut {
                return (exitCode: 124, output: "命令执行超过 35 秒已超时中止。\n\(combined)", isError: true)
            }
            let code = Int(proc.terminationStatus)
            let ok = (code == 0)
            let header = ok ? "$ \(trimmed) (exit 0)" : "$ \(trimmed) (exit \(code))"
            return (exitCode: code, output: combined.isEmpty ? "\(header)\n(无输出)" : "\(header)\n\(combined)", isError: !ok)
        }.value
        let elapsedMs = max(1, Int(Date().timeIntervalSince(started) * 1000))
        await MainActor.run {
            PipiMobileTerminalLog.shared.append(
                PipiTerminalTranscriptEntry(
                    source: "agent",
                    targetLabel: "Mac Shell",
                    command: trimmed,
                    output: execResult.output,
                    exitCode: execResult.exitCode,
                    durationMs: elapsedMs
                )
            )
        }
        return PipiAgentToolExecutionResult(output: execResult.output, isError: execResult.isError)
        #else
        // iOS / iPadOS: Tier 2 E2EE Relay for heavy toolchains -> fallback to Tier 1 Native Sandbox Shell
        if PipiMobileSandboxShell.requiresDesktopHostRelay(command: trimmed) {
            if let cb = callbacks {
                let started = Date()
                let remoteOut = await cb.remoteNodeAction("remote_node_exec", ["command": trimmed])
                let unavailableSignals = ["未找到目标远程节点", "没有在线", "未启用远程节点", "未连接"]
                if !remoteOut.isEmpty && !unavailableSignals.contains(where: { remoteOut.contains($0) }) {
                    let elapsedMs = max(1, Int(Date().timeIntervalSince(started) * 1000))
                    await MainActor.run {
                        PipiMobileTerminalLog.shared.append(
                            PipiTerminalTranscriptEntry(
                                source: "agent",
                                targetLabel: "Remote Host",
                                command: trimmed,
                                output: remoteOut,
                                exitCode: 0,
                                durationMs: elapsedMs
                            )
                        )
                    }
                    return PipiAgentToolExecutionResult(output: "[Remote Host Relay]\n\(remoteOut)", isError: false)
                }
            }
            return PipiAgentToolExecutionResult(
                output: "命令 `\(trimmed.prefix(40))` 需要桌面级工具链（如 python3 / git / swift / npm），但当前没有在线的 Mac/Linux 托管节点。如需在 iPhone 本地做数据处理或文件操作，请改用 `run_script`（内置 JavaScriptCore 引擎）或沙箱 POSIX 命令（ls / cat / grep / sort / wc / find / curl）。",
                isError: true
            )
        }

        let shell = PipiMobileSandboxShell.shared
        let res = await shell.execute(trimmed, source: "agent", recordTranscript: true)
        let header = "$ \(trimmed) (exit \(res.exitCode) · \(res.cwd))"
        return PipiAgentToolExecutionResult(
            output: "\(header)\n\(res.combinedOutput)",
            isError: res.exitCode != 0
        )
        #endif
    }

    private static func executeGetSystemStatus() async -> PipiAgentToolExecutionResult {
        #if os(macOS)
        let snap = await executeRunShell(
            command: "echo '--- DISK ---'; df -h /; echo '--- TOP CPU ---'; ps -Ao pid,pcpu,pmem,comm -r | head -n 8; echo '--- UPTIME ---'; uptime; pmset -g batt 2>/dev/null | head -n 3",
            workingDirectory: NSHomeDirectory()
        )
        return snap
        #else
        let p = await MainActor.run { PipiOnDeviceNPUEngine.currentProfile() }
        let batt = p.batteryLevelPercent.map { "\($0)% (\(p.isCharging ? "charging" : "battery"))" } ?? "N/A"
        let text = "iPhone System Status: \(p.processorCount) cores · \(p.physicalMemoryGB) GB RAM · Thermal: \(p.thermalState) · LowPower: \(p.isLowPowerMode) · Battery: \(batt) · NPU Tier: \(p.recommendedTier.rawValue)"
        return PipiAgentToolExecutionResult(output: text)
        #endif
    }

    private static func executeWebSearch(query: String) async -> PipiAgentToolExecutionResult {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return PipiAgentToolExecutionResult(output: "搜索关键词无效。", isError: true)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let html = String(data: data, encoding: .utf8) ?? ""
            let snippets = extractDuckDuckGoResults(from: html)
            if snippets.isEmpty {
                return PipiAgentToolExecutionResult(output: "未检索到直接结果，可尝试换个关键词或直接用 fetch_webpage 访问特定网址。")
            }
            return PipiAgentToolExecutionResult(output: "🌐 网页搜索「\(q)」结果：\n" + snippets.joined(separator: "\n"))
        } catch {
            return PipiAgentToolExecutionResult(output: "网页搜索网络不可达：\(error.localizedDescription)", isError: true)
        }
    }

    private static func extractDuckDuckGoResults(from html: String) -> [String] {
        let pattern = #"<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var results: [String] = []
        for (idx, m) in matches.prefix(6).enumerated() where m.numberOfRanges >= 3 {
            let href = ns.substring(with: m.range(at: 1))
            let title = stripHTMLTags(ns.substring(with: m.range(at: 2))).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                results.append("\(idx + 1). \(title) — \(href)")
            }
        }
        return results
    }

    private static func executeFetchWebpage(urlString: String) async -> PipiAgentToolExecutionResult {
        guard let url = URL(string: urlString), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return PipiAgentToolExecutionResult(output: "无效 URL：\(urlString)", isError: true)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 14
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) PiPiBot/0.11", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 200
            let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            let plain = stripHTMLTags(raw)
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let clipped = plain.count > 6000 ? String(plain.prefix(6000)) + "\n...(已截断)" : plain
            return PipiAgentToolExecutionResult(output: "HTTP \(code) · \(urlString)\n\n\(clipped)")
        } catch {
            return PipiAgentToolExecutionResult(output: "抓取网页失败：\(error.localizedDescription)", isError: true)
        }
    }

    private static func stripHTMLTags(_ html: String) -> String {
        var text = html
        for block in ["<script[\\s\\S]*?</script>", "<style[\\s\\S]*?</style>", "<[^>]+>"] {
            if let rx = try? NSRegularExpression(pattern: block, options: [.caseInsensitive]) {
                text = rx.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text), withTemplate: " ")
            }
        }
        return text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    /// Renders a clean, warm-vellum PNG summary/diagram card on macOS using CoreGraphics/AppKit (0 raw hex literals).
    public static func renderVisualCardPNG(
        title: String,
        subtitle: String?,
        body: String,
        deliverablesDir: URL
    ) -> PipiDeliverableArtifact? {
        #if os(macOS)
        try? FileManager.default.createDirectory(at: deliverablesDir, withIntermediateDirectories: true)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "PiPiBot Card" : title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let width: CGFloat = 1080
        let padding: CGFloat = 56
        let contentWidth = width - padding * 2

        let titleFont = NSFont.systemFont(ofSize: 34, weight: .bold)
        let subtitleFont = NSFont.systemFont(ofSize: 18, weight: .medium)
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 20, weight: .regular)
        let footerFont = NSFont.systemFont(ofSize: 15, weight: .medium)

        let bgPaper = NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.95, alpha: 1.0)
        let cardSurface = NSColor(calibratedRed: 1.0, green: 0.995, blue: 0.985, alpha: 1.0)
        let inkPrimary = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1.0)
        let inkSecondary = NSColor(calibratedRed: 0.42, green: 0.45, blue: 0.50, alpha: 1.0)
        let accentWarm = NSColor(calibratedRed: 0.85, green: 0.45, blue: 0.24, alpha: 1.0)
        let hairline = NSColor(calibratedRed: 0.88, green: 0.86, blue: 0.82, alpha: 1.0)

        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.lineSpacing = 8

        let bodyAttr = NSAttributedString(
            string: cleanBody.isEmpty ? "PiPiBot 管家已为你整理完毕" : cleanBody,
            attributes: [
                .font: bodyFont,
                .foregroundColor: inkPrimary,
                .paragraphStyle: bodyParagraph
            ]
        )
        let bodyRect = bodyAttr.boundingRect(with: NSSize(width: contentWidth - 48, height: 2400), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let height = max(560, min(2200, ceil(bodyRect.height) + 270))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width),
            pixelsHigh: Int(height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        // Outer vellum canvas
        bgPaper.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        // Inner elevated card
        let cardRect = NSRect(x: 32, y: 32, width: width - 64, height: height - 64)
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 28, yRadius: 28)
        cardSurface.setFill()
        cardPath.fill()
        hairline.setStroke()
        cardPath.lineWidth = 2
        cardPath.stroke()

        // Accent top bar
        let accentBar = NSBezierPath(roundedRect: NSRect(x: padding, y: height - 80, width: 72, height: 8), xRadius: 4, yRadius: 4)
        accentWarm.setFill()
        accentBar.fill()

        // Title
        let titleAttr = NSAttributedString(
            string: cleanTitle,
            attributes: [.font: titleFont, .foregroundColor: inkPrimary]
        )
        titleAttr.draw(in: NSRect(x: padding, y: height - 146, width: contentWidth, height: 54))

        // Subtitle
        let subText = subtitle ?? "PiPiBot · 个人管家可视化卡片"
        let subAttr = NSAttributedString(
            string: subText,
            attributes: [.font: subtitleFont, .foregroundColor: inkSecondary]
        )
        subAttr.draw(in: NSRect(x: padding, y: height - 180, width: contentWidth, height: 28))

        // Divider
        hairline.setFill()
        NSRect(x: padding, y: height - 196, width: contentWidth, height: 1.5).fill()

        // Body text
        bodyAttr.draw(in: NSRect(x: padding, y: 74, width: contentWidth - 16, height: height - 290))

        // Footer
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(16).replacingOccurrences(of: "T", with: " ")
        let footerAttr = NSAttributedString(
            string: "🐾 PiPiBot Jarvis · \(stamp)",
            attributes: [.font: footerFont, .foregroundColor: inkSecondary]
        )
        footerAttr.draw(in: NSRect(x: padding, y: 46, width: contentWidth, height: 24))

        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = rep.representation(using: .png, properties: [:]) else { return nil }
        let fileName = "pipi_card_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(4).lowercased()).png"
        let outURL = deliverablesDir.appendingPathComponent(fileName)
        do {
            try pngData.write(to: outURL, options: [.atomic])
            return PipiDeliverableArtifact(
                id: "art_\(UUID().uuidString.prefix(8))",
                kind: .image,
                fileName: fileName,
                filePath: outURL.path,
                mimeType: "image/png",
                byteSize: Int64(pngData.count)
            )
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    private static func executeOpenAIImageGeneration(
        prompt: String,
        config: PipiLLMProviderConfig,
        deliverablesDir: URL
    ) async -> PipiDeliverableArtifact? {
        guard [.openai, .customOpenAI, .openrouter].contains(config.kind),
              !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let base = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let imageURLString: String
        if base.hasSuffix("/chat/completions") {
            imageURLString = String(base.dropLast("/chat/completions".count)) + "/images/generations"
        } else {
            imageURLString = "\(base)/images/generations"
        }
        guard let url = URL(string: imageURLString) else { return nil }

        let payload: [String: Any] = [
            "model": "gpt-image-1",
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024",
            "response_format": "b64_json"
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["data"] as? [[String: Any]],
              let first = items.first else {
            return nil
        }

        var imgData: Data? = nil
        if let b64 = first["b64_json"] as? String {
            imgData = Data(base64Encoded: b64)
        } else if let remoteStr = first["url"] as? String, let remoteURL = URL(string: remoteStr) {
            imgData = try? await URLSession.shared.data(from: remoteURL).0
        }
        guard let imgData, !imgData.isEmpty else { return nil }

        try? FileManager.default.createDirectory(at: deliverablesDir, withIntermediateDirectories: true)
        let fileName = "pipi_gen_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(4).lowercased()).png"
        let outURL = deliverablesDir.appendingPathComponent(fileName)
        do {
            try imgData.write(to: outURL, options: [.atomic])
            return PipiDeliverableArtifact(
                id: "art_\(UUID().uuidString.prefix(8))",
                kind: .image,
                fileName: fileName,
                filePath: outURL.path,
                mimeType: "image/png",
                byteSize: Int64(imgData.count)
            )
        } catch {
            return nil
        }
    }

    private static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return String(format: "%.1fKB", Double(bytes) / 1024.0) }
        return String(format: "%.1fMB", Double(bytes) / (1024.0 * 1024.0))
    }
}
