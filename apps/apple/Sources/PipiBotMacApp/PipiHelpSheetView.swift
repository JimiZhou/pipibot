import SwiftUI
import PipiBotKit

public enum PipiHelpTopic: String, CaseIterable, Identifiable, Sendable {
    case gettingStarted
    case shortcuts
    case remoteAndMac
    case knowledgeMemory
    case localModels
    case dailyVoice
    case desktopSafety

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .gettingStarted: return "book"
        case .shortcuts: return "command"
        case .remoteAndMac: return "antenna.radiowaves.left.and.right"
        case .knowledgeMemory: return "books.vertical"
        case .localModels: return "cpu"
        case .dailyVoice: return "waveform"
        case .desktopSafety: return "shield.lefthalf.filled"
        }
    }

    public func title(_ s: PipiStrings) -> String {
        switch self {
        case .gettingStarted: return s.t("快速入门", "Getting Started")
        case .shortcuts: return s.t("快捷键与指令", "Shortcuts & Commands")
        case .remoteAndMac: return s.t("远程操控与系统接管", "Remote & Mac Control")
        case .knowledgeMemory: return s.t("知识、日程与记忆", "Knowledge & Memory")
        case .localModels: return s.t("本地模型与服务", "Local Models & Gateway")
        case .dailyVoice: return s.t("语音通话与音色", "Voice Calls & Timbres")
        case .desktopSafety: return s.t("桌面协作与安全审批", "Desktop Control & Safety")
        }
    }
}

/// Reusable embedded Help Content rendered directly inside Settings -> "帮助说明"
/// as well as inside the standalone `PipiHelpSheetView`.
public struct PipiHelpEmbeddedView: View {
    @Bindable public var store: PipiAppStore
    @State public var selectedTopic: PipiHelpTopic

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: PipiAppStore, initialTopic: PipiHelpTopic = .gettingStarted) {
        self.store = store
        self._selectedTopic = State(initialValue: initialTopic)
    }

    private var s: PipiStrings { store.strings }

    public var body: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
            // Horizontal clean topic chips (no double sidebar inside Settings)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PipiHelpTopic.allCases) { topic in
                        let active = selectedTopic == topic
                        Button {
                            selectedTopic = topic
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: topic.iconName)
                                    .font(.system(size: 11.5, weight: .medium))
                                Text(topic.title(s))
                                    .font(PipiTokens.fontCaption.weight(active ? .semibold : .medium))
                            }
                            .foregroundStyle(active ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(active ? PipiTokens.bgElevated : PipiTokens.bgSurface.opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                    .strokeBorder(active ? PipiTokens.composerBorderFocused : PipiTokens.borderSubtle, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        }
                        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.98))
                    }
                }
            }
            .pipiHideScrollbars()

            PipiHelpTopicBodyView(store: store, topic: selectedTopic)
        }
    }
}

/// Centralized Help Center holding all beginner guides, shortcuts, and technical reference notes
/// folded out of primary workspace surfaces.
public struct PipiHelpSheetView: View {
    @Bindable public var store: PipiAppStore
    @State public var selectedTopic: PipiHelpTopic
    public var onClose: () -> Void

    @Environment(\.pipiTextScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        store: PipiAppStore,
        initialTopic: PipiHelpTopic = .gettingStarted,
        onClose: @escaping () -> Void
    ) {
        self.store = store
        self._selectedTopic = State(initialValue: initialTopic)
        self.onClose = onClose
    }

    private var s: PipiStrings { store.strings }

    public var body: some View {
        let _ = textScale
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: PipiTokens.spacing8) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text(s.t("帮助中心", "Help Center"))
                        .font(PipiTokens.fontHeadline)
                        .foregroundStyle(PipiTokens.textPrimary)
                }
                .padding(.horizontal, PipiTokens.spacing8)
                .padding(.top, PipiTokens.spacing20)
                .padding(.bottom, PipiTokens.spacing12)

                ForEach(PipiHelpTopic.allCases) { topic in
                    let isSelected = selectedTopic == topic
                    Button {
                        selectedTopic = topic
                    } label: {
                        HStack(spacing: PipiTokens.spacing8) {
                            Image(systemName: topic.iconName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                                .frame(width: 18)
                            Text(topic.title(s))
                                .font(PipiTokens.fontSubheadline.weight(isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? PipiTokens.textPrimary : PipiTokens.textSecondary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, PipiTokens.spacing8)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                                .fill(isSelected ? PipiTokens.bgSurfaceHover : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: selectedTopic)
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.985))
                }

                Spacer()
            }
            .padding(.horizontal, PipiTokens.spacing12)
            .frame(width: 212)
            .pipiStructuralMaterial()

            Rectangle()
                .fill(PipiTokens.borderSubtle)
                .frame(width: 1)

            VStack(spacing: 0) {
                HStack {
                    Text(selectedTopic.title(s))
                        .font(PipiTokens.fontTitle)
                        .tracking(PipiTokens.trackingTitle)
                        .foregroundStyle(PipiTokens.textPrimary)
                    Spacer()
                    PipiGhostIconButton(
                        systemImage: "xmark",
                        size: 28,
                        iconSize: 12,
                        cornerRadius: PipiTokens.radiusPill,
                        accessibilityLabel: s.close,
                        action: onClose
                    )
                }
                .padding(.horizontal, PipiTokens.spacing24)
                .padding(.vertical, PipiTokens.spacing16)
                .background(PipiTokens.bgCanvas)

                Rectangle()
                    .fill(PipiTokens.borderSubtle)
                    .frame(height: 1)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                        PipiHelpTopicBodyView(store: store, topic: selectedTopic)
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(PipiTokens.spacing24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .pipiHideScrollbars()
                .background(PipiTokens.bgCanvas)
            }
        }
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
    }
}

public struct PipiHelpTopicBodyView: View {
    @Bindable public var store: PipiAppStore
    public let topic: PipiHelpTopic

    public init(store: PipiAppStore, topic: PipiHelpTopic) {
        self.store = store
        self.topic = topic
    }

    private var s: PipiStrings { store.strings }

    public var body: some View {
        switch topic {
        case .gettingStarted:
            helpCard(
                title: s.t("页面定位", "Workspace Surfaces"),
                items: [
                    (s.t("智能体", "Agents"), s.t("管理个人助手、查看实时状态，并可在卡片视图与 3D 空间视图之间切换。", "Manage assistants, monitor status, and switch between Cards and 3D Space.")),
                    (s.t("对话与协作群", "Chats & Groups"), s.t("与单个助手对话，或组建多位助手协作处理复杂任务。", "Chat 1:1 with an assistant or coordinate multiple assistants in a group thread.")),
                    (s.t("知识与简报", "Knowledge & Briefs"), s.t("统一管理个人词条、日程准备简报、随手记待办、文档以及助手记忆。", "Manage personal entries, schedule briefs, notes, documents, and assistant memories.")),
                    (s.t("待我确认", "Needs You"), s.t("集中处理权限审批、决策请求与动态成员加入建议。", "Review all pending permission requests, decisions, and team proposals."))
                ]
            )
            helpCard(
                title: s.t("右侧栏说明", "Contextual Inspector"),
                items: [
                    (s.t("随页面切换", "Context-Aware"), s.t("右侧栏内容随当前功能页面自动切换，分别展示空间概览、会话详情、群协作信息、知识统计或安全策略。", "The right sidebar adapts to each page, displaying space overview, session details, group controls, knowledge stats, or safety policies."))
                ]
            )

        case .shortcuts:
            helpCard(
                title: s.t("全局与窗口快捷键", "Keyboard Shortcuts"),
                items: [
                    ("⌥Space", s.t("呼出或收起桌面快捷浮窗。", "Toggle the global floating Quick Bar.")),
                    ("⌘K", s.t("打开命令面板，检索对话、助手或功能命令。", "Open the Command Palette to search chats, agents, and commands.")),
                    ("⌘N", s.t("新建对话。", "Start a new conversation.")),
                    ("⌘,", s.t("打开设置窗口。", "Open Settings.")),
                    ("⌘. ", s.t("停止当前正在生成的回复。", "Stop the active response generation.")),
                    ("⌘+ / ⌘- / ⌘0", s.t("放大、缩小或恢复默认界面比例。", "Zoom interface in, out, or reset to 100%.")),
                    ("⌘1 – ⌘4", s.t("快速切换前四位助手。", "Switch rapidly among the first four assistants."))
                ]
            )
            helpCard(
                title: s.t("对话斜杠指令", "Chat Slash Commands"),
                items: [
                    ("/plan · /review · /summarize", s.t("要求助手先制定计划、执行代码审查或提炼要点。", "Ask the assistant to plan first, review code, or summarize context.")),
                    ("/delegate · /compact", s.t("派生后台分身并行执行，或压缩当前对话上下文。", "Delegate background subtasks or compact active conversation context.")),
                    ("/wiki · /voice · /computer", s.t("快速打开知识库、语音栏或桌面协作状态栏。", "Open Knowledge Hub, Voice Bar, or Desktop Control strip.")),
                    ("/screenshot · /record <秒数>", s.t("截取本机屏幕图片或录制屏幕视频并直接发送至当前对话/远程端。", "Capture a Mac screenshot or screen recording and send it directly.")),
                    ("/sms · /mail", s.t("读取本机最近短信（iMessage/SMS）与 Apple 邮件收件箱摘要。", "Inspect recent local Messages/SMS and Apple Mail inbox summaries.")),
                    ("/build <命令> · /sendfile <路径> · /voiceclip <文本>", s.t("在 Mac 执行编译打包命令、投递本机文件或生成语音消息文件。", "Run local build/package commands, deliver files, or synthesize voice clips."))
                ]
            )

        case .remoteAndMac:
            helpCard(
                title: s.t("远程操控渠道", "Remote Access Channels"),
                items: [
                    (s.t("Cloudflare Tunnel · PWA 模式", "Cloudflare Tunnel · PWA"), s.t("在「设置 → 运行与远程操控」开启后，通过 cloudflared 临时生成 HTTPS 链接与二维码。手机扫码打开并「添加到主屏幕」即可 PWA 全屏操控本台 Mac；关闭并再次开启后地址与口令将重新生成。", "Generates a temporary Cloudflare Quick Tunnel URL and QR code. Scan on mobile and Add to Home Screen for PWA remote control; URL rotates each time it restarts.")),
                    (s.t("微信 iLink 协议（扫码绑定）", "WeChat iLink Protocol"), s.t("通过官方 iLink Bot 协议扫码绑定个人微信，默认与主 PiPiBot 1v1 对话；支持切换「群聊模式」，通过消息前缀（如【助手名称】）区分多位智能体回复，也可使用「@助手名 指令」或 /mode group 随时切换。", "Bind personal WeChat via iLink QR scan. Defaults to 1v1 main PiPiBot; toggle Group Mode to distinguish multiple agents via message prefixes and @mentions."))
                ]
            )
            helpCard(
                title: s.t("本机系统接管与富媒体投递", "Native Mac Takeover & Media Delivery"),
                items: [
                    (s.t("短信与邮件授权", "Messages & Mail Permissions"), s.t("在「设置 → 运行与远程操控」按指引授予完全磁盘访问（读取短信数据库）及自动化（控制信息与邮件应用）权限后，助手可代查摘要并辅助回复。", "Grant Full Disk Access and Automation in Settings to let assistants summarize and draft Messages & Mail locally.")),
                    (s.t("编译打包与媒体回传", "Builds & Rich Media"), s.t("助手可在工作区执行编译、测试与打包，并将截屏图片、录屏视频、语音消息和任意本机文件直接发送至 Mac 会话、远程 PWA 或微信。", "Run builds/packaging on your Mac and receive real screenshots, videos, voice clips, and files across Mac Chat, Remote PWA, and WeChat."))
                ]
            )

        case .knowledgeMemory:
            helpCard(
                title: s.t("个人词条与离线检索", "Personal Wiki & Local Search"),
                items: [
                    (s.t("本地存储", "Local Storage"), s.t("所有词条基于 SQLite WAL 与 FTS5 全文索引保存在本机，无需配置向量模型即可进行中英文检索。", "Entries are stored locally in SQLite WAL with FTS5 full-text indexing for instant bilingual search without embeddings.")),
                    (s.t("时间窗与同义词", "Time Window & Alternates"), s.t("搜索栏展开筛选后，可指定起止日期与最多 6 组同义词提升命中率。", "Expand search filters to narrow by date range or up to 6 alternate terms."))
                ]
            )
            helpCard(
                title: s.t("日程准备、笔记与记忆", "Briefs, Notes & Memory"),
                items: [
                    (s.t("日程准备", "Schedule Preparation"), s.t("授权 Apple 日历与提醒事项后，系统会读取近期日程与本地代码库状态，自动生成只读准备简报。", "Reads authorized Apple Calendar, Reminders, and local Git status to prepare read-only context briefs.")),
                    (s.t("随手记待办提炼", "Pocket Note Extraction"), s.t("在每日随手记中编写待办条目，编辑静默 5 分钟后或点击提炼按钮即可自动汇总为待办清单。", "Tasks written in Daily Notes automatically reconcile after 5 minutes of inactivity or on demand.")),
                    (s.t("助手独立记忆", "Isolated Assistant Memory"), s.t("每位助手拥有独立经验档案，仅在会话首轮或上下文压缩后注入，避免破坏提示词缓存（Prompt Cache）。", "Each assistant keeps isolated experience notes injected only on initial or post-compaction turns to preserve Prompt Cache.")),
                    (s.t("内置技能校验", "Builtin Skill Verification"), s.t("内置技能包带 SHA-256 校验并以只读权限投影至工作区，防止运行中被意外篡改。", "Builtin skill packs carry SHA-256 checksums and project read-only into the workspace."))
                ]
            )

        case .localModels:
            helpCard(
                title: s.t("硬件自动规划与加速", "Hardware Plan & Acceleration"),
                items: [
                    (s.t("自动选型", "Model Autopilot"), s.t("系统依据本机芯片、内存与可用磁盘空间自动计算可用模型内存预算，并推荐匹配模型与上下文长度。", "Detects CPU, RAM, and free disk space to calculate memory budgets and recommend models and context limits.")),
                    (s.t("PolyStrata 预取模式", "PolyStrata Prefetch"), s.t("基于 MIT 许可的 PolyStrata 引擎在 Apple Silicon 上可将常用参数常驻统一内存并按层预取；未安装时自动回退至 llama.cpp、Ollama 或 MLX。", "MIT-licensed PolyStrata keeps active MoE layers in unified memory and prefetches cold layers from SSD; falls back to llama.cpp, Ollama, or MLX.")),
                    (s.t("问答自测门禁", "QA Self-Test Gate"), s.t("通过发送真实推理请求检测首字延迟（TTFT）与生成速率，确认本地服务可用。", "Runs a live prompt check measuring TTFT and token throughput to confirm readiness."))
                ]
            )
            helpCard(
                title: s.t("本地统一服务与工具隔离注入", "Local Gateway & CLI Isolation"),
                items: [
                    (s.t("本机回环监听", "Loopback Only"), s.t("本地模型服务仅绑定 127.0.0.1，兼容 OpenAI 与 Anthropic 接口格式，不会向局域网暴露。", "Local gateway binds strictly to 127.0.0.1 with OpenAI and Anthropic protocol compatibility.")),
                    (s.t("隔离环境变量注入", "Isolated CLI Overlays"), s.t("开启反向注入后，系统通过独立目录（CLAUDE_CONFIG_DIR / CODEX_HOME / PI_CODING_AGENT_DIR）向本地命令行工具传递配置，不修改用户的默认配置文件。", "Passes configuration via isolated environment directories without modifying ~/.claude or ~/.codex."))
                ]
            )

        case .dailyVoice:
            helpCard(
                title: s.t("日常语音模式", "Voice Interaction Modes"),
                items: [
                    (s.t("口述输入", "Dictation"), s.t("将语音实时转为文字并填入输入框。", "Transcribes speech directly into the message input.")),
                    (s.t("连续语音对话", "Hands-Free Voice"), s.t("免提对话并支持自动播报回复，播报期间随时开口即可打断。", "Hands-free conversation with automatic speech playback and instant interruption.")),
                    (s.t("语音创建任务", "Voice to Task"), s.t("将口述内容直接转为后台任务、待办事项或随手记。", "Turns spoken instructions directly into background tasks, to-dos, or notes."))
                ]
            )
            helpCard(
                title: s.t("隐私与防回声打断", "Privacy & Echo-Gated VAD"),
                items: [
                    (s.t("端侧优先策略", "On-Device First"), s.t("默认优先使用 Apple 本机语音识别与合成；选择「仅端侧」后绝不向外部发送任何音频数据。", "Prefers Apple on-device speech engines; On-Device Only mode guarantees zero audio egress.")),
                    (s.t("人声检测与回声门控", "VAD & Echo Gate"), s.t("在语音播报期间自动提高收音能量门槛过滤扬声器回声，检测到连续人声时立即停止播报并切换聆听。", "Raises threshold while speaking to suppress speaker echo and switches to listening on sustained user speech.")),
                    (s.t("云端密钥安全", "Cloud API Keychain"), s.t("可选配置的云端 STT/TTS 接口密钥仅保存在 macOS 钥匙串（Keychain）中，不以明文落盘。", "Optional cloud STT/TTS API keys are stored exclusively in macOS Keychain."))
                ]
            )

        case .desktopSafety:
            helpCard(
                title: s.t("浏览器与桌面协作", "Browser & Desktop Control"),
                items: [
                    (s.t("浏览器协作（阶段 A）", "Chrome Collaboration (Phase A)"), s.t("通过本机调试端口附着已登录的 Chrome 会话，为不同助手分配独立标签席位并发浏览，凭证留存本机。", "Attaches via loopback port to signed-in Chrome using isolated per-assistant tab seats.")),
                    (s.t("桌面辅助控制（阶段 B）", "macOS Accessibility (Phase B)"), s.t("读取系统辅助功能元素树而非盲目坐标点击；桌面通道同时仅允许单任务操作，一旦您切换前景窗口即自动暂停礼让。", "Uses structured macOS Accessibility trees on a single desktop lane that yields immediately when you switch windows.")),
                    (s.t("操作保护日志（WAL）", "Write-Ahead Journal (WAL)"), s.t("执行外部写入或点击前先记录日志；若执行结果未知会自动锁定通道，防止重复提交，待您核查后解锁。", "Records high-impact actions prior to execution and locks the lane if an outcome is uncertain, preventing duplicate clicks."))
                ]
            )
            helpCard(
                title: s.t("分级审批与风险评估", "Approvals & Safety Guardrail"),
                items: [
                    (s.t("多粒度授权", "Granular Approvals"), s.t("遇到文件写入或高风险操作时，可选择仅允许本次、本会话同类允许、本项目允许或保持只读。", "Approve actions once, for the current session, for the project, or keep read-only.")),
                    (s.t("风险评估护栏", "Risk Assessment Guardrail"), s.t("高危或外部生效操作会触发风险评估检查；敏感凭证外发与篡改审批规则默认禁止。", "Evaluates risk on external or destructive actions; credential exfiltration and policy tampering are always blocked."))
                ]
            )
        }
    }

    private func helpCard(title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing8) {
            Text(title)
                .font(PipiTokens.fontCaption.weight(.semibold))
                .foregroundStyle(PipiTokens.textSecondary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    if idx > 0 {
                        Rectangle()
                            .fill(PipiTokens.borderSubtle)
                            .frame(height: 1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.0)
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Text(item.1)
                            .font(PipiTokens.fontCaption)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PipiTokens.bgElevated)
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                    .strokeBorder(PipiTokens.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
        }
    }
}
