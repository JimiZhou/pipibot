// PiPiBot — Clean-room MIT implementation.
// Renders real Retina screenshots of the actual SwiftUI macOS views when launched with:
//   PipiBotMacApp --export-showcase-screenshots <output-dir>

#if os(macOS)
import AppKit
import SwiftUI
import PipiBotKit
import PipiBotIOSUI

@MainActor
enum PipiShowcaseScreenshotExporter {
    static func exportIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--export-showcase-screenshots"),
              idx + 1 < args.count else {
            return false
        }
        let outDir = URL(fileURLWithPath: args[idx + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        let store = buildShowcaseStore()

        let canvasSize = CGSize(width: 1360, height: 850)

        // 1. Real Workspace View (Agents Hub + Sidebar, Light)
        let workspaceView = PipiWorkspaceView(store: store)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .background(PipiTokens.bgCanvas)
            .environment(\.colorScheme, .light)
        renderViaHostingWindow(view: workspaceView, size: canvasSize, appearance: .aqua, splitSidebarWidth: 256, to: outDir.appendingPathComponent("mac-workspace.png"))

        // 2. Real Group Chat View (Parallel Multi-Bot Collaboration, Light)
        if let gid = store.groupChats.first?.id {
            let groupView = PipiGroupChatView(store: store, groupId: gid)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .background(PipiTokens.bgCanvas)
                .environment(\.colorScheme, .light)
            renderViaHostingWindow(view: groupView, size: canvasSize, appearance: .aqua, splitSidebarWidth: nil, to: outDir.appendingPathComponent("mac-group.png"))
        }

        // 3. Real Mission Board View (Kanban + Proof/Diff + E2EE Pairing QR + Sentinel, Light)
        let missionView = PipiMissionBoardView(store: store, onOpenArchitect: {}, onOpenConversation: { _ in })
            .frame(width: canvasSize.width, height: canvasSize.height)
            .background(PipiTokens.bgCanvas)
            .environment(\.colorScheme, .light)
        renderViaHostingWindow(view: missionView, size: canvasSize, appearance: .aqua, splitSidebarWidth: nil, to: outDir.appendingPathComponent("mac-mission.png"))

        // 4. Real Workspace View (Obsidian Dark)
        store.themeMode = .dark
        let workspaceDark = PipiWorkspaceView(store: store)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .background(PipiTokens.bgCanvas)
            .environment(\.colorScheme, .dark)
        renderViaHostingWindow(view: workspaceDark, size: canvasSize, appearance: .darkAqua, splitSidebarWidth: 256, to: outDir.appendingPathComponent("mac-workspace-dark.png"))

        // 5. Real Consumer iOS App (iPhone 16 Pro 393x852, Warm Paper Light)
        let iosSize = CGSize(width: 393, height: 852)
        store.themeMode = .light
        let iosLight = PipiIOSCompanionRootView(store: store)
            .frame(width: iosSize.width, height: iosSize.height)
            .environment(\.colorScheme, .light)
        renderViaHostingWindow(view: iosLight, size: iosSize, appearance: .aqua, splitSidebarWidth: nil, to: outDir.appendingPathComponent("ios-chat.png"))

        // 6. Real Consumer iOS App (Obsidian Dark)
        store.themeMode = .dark
        let iosDark = PipiIOSCompanionRootView(store: store)
            .frame(width: iosSize.width, height: iosSize.height)
            .environment(\.colorScheme, .dark)
        renderViaHostingWindow(view: iosDark, size: iosSize, appearance: .darkAqua, splitSidebarWidth: nil, to: outDir.appendingPathComponent("ios-chat-dark.png"))

        // 7. Muse-Inspired Floating Voice Companion Sheet (Light)
        store.themeMode = .light
        let iosVoice = PipiIOSVoiceSheetView(store: store, onDismiss: {})
            .frame(width: iosSize.width, height: 560)
            .environment(\.colorScheme, .light)
        renderViaHostingWindow(view: iosVoice, size: CGSize(width: iosSize.width, height: 560), appearance: .aqua, splitSidebarWidth: nil, to: outDir.appendingPathComponent("ios-voice.png"))

        // 8. Read-Only Agent Sandbox Execution Activity Sheet (Light)
        PipiMobileTerminalLog.shared.clear()
        PipiMobileTerminalLog.shared.append(
            PipiTerminalTranscriptEntry(
                source: "agent",
                targetLabel: "iPhone 本机沙箱 · POSIX",
                command: "ls -la && wc -l notes.md",
                output: "drwxr-xr-x   notes/\n-rw-r--r--   412B  notes.md\n-rw-r--r--   1.4K  metrics.csv\n      18 notes.md",
                exitCode: 0,
                durationMs: 4
            )
        )
        PipiMobileTerminalLog.shared.append(
            PipiTerminalTranscriptEntry(
                source: "agent",
                targetLabel: "iPhone 本机沙箱 · JavaScriptCore",
                command: "const rows = fs.read('metrics.csv').split('\\n'); rows.length",
                output: "42",
                exitCode: 0,
                durationMs: 7
            )
        )
        PipiMobileTerminalLog.shared.append(
            PipiTerminalTranscriptEntry(
                source: "agent",
                targetLabel: "MacBook Pro · E2EE 自动中继",
                command: "swift test --filter MobileSandbox",
                output: "Executed 6 tests, with 0 failures in 0.084 seconds",
                exitCode: 0,
                durationMs: 312
            )
        )
        let iosTerminal = PipiIOSTerminalSheetView(store: store, onDismiss: {})
            .frame(width: iosSize.width, height: 640)
            .environment(\.colorScheme, .light)
        renderViaHostingWindow(view: iosTerminal, size: CGSize(width: iosSize.width, height: 640), appearance: .aqua, splitSidebarWidth: nil, to: outDir.appendingPathComponent("ios-terminal.png"))
        PipiMobileTerminalLog.shared.clear()

        return true
    }

    private static func buildShowcaseStore() -> PipiAppStore {
        let store = PipiAppStore(enableNativeRuntime: false)
        store.hasCompletedOnboarding = true
        store.isInspectorPresented = false
        store.language = .zhHans
        store.themeMode = .light

        // Populate a realistic, crisp conversation in active workspace
        let conv = store.createConversation(activate: true)
        if let idx = store.conversations.firstIndex(where: { $0.id == conv.id }) {
            store.conversations[idx].title = "服务端性能排查与发布准备"
            store.conversations[idx].messages = [
                PipiChatMessage(
                    role: .user,
                    content: "帮我检查一下 relay 服务的内存占用，顺便把单测补齐放到隔离分支里。"
                ),
                PipiChatMessage(
                    role: .assistant,
                    content: """
                    已完成排查并在隔离分支 `pipi/wt-relay-audit` 补齐验证：

                    - **内存与连接**：常驻约 28 MB，单 IP 并发限流与空闲回收正常生效
                    - **端到端加密**：P-256 ECDH + AES-256-GCM 双向收发及防重放单测全部通过
                    - **Review Proof**：确定性检查 4/4 通过，评分 **96%**，可在任务台一键 Squash 合入
                    """,
                    engineLabel: "PiPi · 全能助手"
                )
            ]
        }

        // Populate realistic Group Chat
        let members = Array(store.personas.prefix(4).map(\.id))
        let group = PipiGroupChat(
            title: "发布攻关群",
            participantPersonaIds: members,
            leadPersonaId: members.first,
            messages: [
                PipiGroupMessage(
                    senderKind: .user,
                    content: "同步检查一下 Mac 端与 Linux 节点的构建状态，没问题就整理发布摘要。"
                ),
                PipiGroupMessage(
                    senderKind: .bot(personaId: members.count > 1 ? members[1] : store.activePersona.id),
                    content: "Mac Release 构建与 47 项 Swift 单元测试全部通过，零警告。隔离分支 `pipi/wt-relay-audit` diff 已就绪。",
                    engineLabel: "Coder · 工程助手"
                ),
                PipiGroupMessage(
                    senderKind: .bot(personaId: members.count > 2 ? members[2] : store.activePersona.id),
                    content: "更新摘要已整理完毕，并按变更模块拆分成三段，已提交草稿队列等待确认。",
                    engineLabel: "Writer · 写作助手"
                ),
                PipiGroupMessage(
                    senderKind: .bot(personaId: members.count > 3 ? members[3] : store.activePersona.id),
                    content: "Linux 节点健康巡检正常，端到端加密中继延迟 24ms，无积压审批项。",
                    engineLabel: "Operator · 任务管家"
                ),
                PipiGroupMessage(
                    senderKind: .user,
                    content: "很好，把 diff 发到任务台，我切到手机端确认后合入。"
                )
            ]
        )
        store.groupChats = [group]

        // Populate Mission Board columns (In Progress, Needs Review, Completed) + Pairing & Security
        let coderId = members.count > 1 ? members[1] : store.activePersona.id
        let writerId = members.count > 2 ? members[2] : store.activePersona.id
        let operatorId = members.count > 3 ? members[3] : store.activePersona.id

        store.activeRuns = [
            conv.id: PipiConversationRunState(
                conversationId: conv.id,
                personaId: coderId,
                runId: "run_showcase_1",
                streamingMessageId: "msg_showcase_1",
                startedAt: Date().addingTimeInterval(-18),
                phase: .running,
                statusText: "正在优化长文本输入滚动与内存占用",
                isLocalAgent: true
            ),
            "conv_showcase_2": PipiConversationRunState(
                conversationId: "conv_showcase_2",
                personaId: writerId,
                runId: "run_showcase_2",
                streamingMessageId: "msg_showcase_2",
                startedAt: Date().addingTimeInterval(-9),
                phase: .running,
                statusText: "整理本周产品更新摘要与双语文案",
                isLocalAgent: false
            )
        ]

        store.worktreeSessions = [
            PipiWorktreeReviewSession(
                repoPath: "/Users/demo/pipibot",
                worktreePath: "/tmp/pipi-wt-relay-audit",
                branchName: "pipi/wt-relay-audit",
                baseBranch: "main",
                taskTitle: "中继端到端加密限流与回归测试",
                botId: coderId,
                botName: "Coder · 编程搭档",
                status: .readyForReview,
                unifiedDiff: "+ export function sealE2EEFrame() { ... }",
                diffSummary: "3 files · +214 / -18"
            ),
            PipiWorktreeReviewSession(
                repoPath: "/Users/demo/pipibot",
                worktreePath: "/tmp/pipi-wt-composer",
                branchName: "pipi/wt-composer",
                baseBranch: "main",
                taskTitle: "多行输入框自动增高与滚轮滚动",
                botId: coderId,
                botName: "Coder · 编程搭档",
                status: .merged,
                unifiedDiff: "+ final class PipiAutoGrowingComposerEditor {}",
                diffSummary: "2 files · +162 / -11"
            )
        ]

        store.runRecords = [
            PipiRunRecord(
                personaId: operatorId,
                conversationId: conv.id,
                engineLabel: "Operator · 任务管家",
                promptPreview: "晨间日程汇总与待办优先级排序",
                status: .succeeded,
                durationMs: 2400
            ),
            PipiRunRecord(
                personaId: writerId,
                conversationId: conv.id,
                engineLabel: "Writer · 写作与研究",
                promptPreview: "整理本周用户反馈要点",
                status: .succeeded,
                durationMs: 3800
            )
        ]

        // Seed realistic Phase 3 Board coordination threads across channels
        let ownerActor = PipiBoardActorRef(id: "human:owner", name: "Jimi", kind: .human)
        let coderActor = PipiBoardActorRef(id: "bot:\(coderId)", name: "Coder · 编程搭档", kind: .bot, harness: "codex")
        let operatorActor = PipiBoardActorRef(id: "bot:\(operatorId)", name: "Operator · 任务管家", kind: .bot)

        let tClaimed = store.createBoardThread(
            channelSlug: "dev",
            title: "补齐 Jarvis 早停自动续跑与并发只读工具单测",
            body: "确保工具步数预算与并发只读批次全部验证通过。",
            priority: .high,
            labels: ["jarvis", "harness"],
            author: ownerActor
        )
        _ = store.claimBoardTask(threadId: tClaimed.id, actor: coderActor, leaseSeconds: 840)

        _ = store.createBoardThread(
            channelSlug: "ops",
            title: "云主机节点巡检与 omp CLI 版本核验",
            body: "批量检测三台在线节点的可用内存、磁盘及 harness 状态。",
            priority: .normal,
            labels: ["fleet"],
            author: ownerActor
        )

        _ = store.createBoardThread(
            channelSlug: "dev",
            title: "打包 v0.13.0 Release 并推送更新说明",
            body: "待前置单测任务完成后自动解锁认领。",
            priority: .normal,
            labels: ["release"],
            blockedBy: [tClaimed.id],
            author: ownerActor
        )

        let tNeedsYou = store.createBoardThread(
            channelSlug: "inbox",
            title: "确认是否启用远程节点自动续租提醒推送",
            body: "已整理默认 15 分钟续租阈值，等待你拍板是否同步推送到微信。",
            priority: .high,
            author: operatorActor
        )
        _ = store.requestBoardNeedsYou(
            threadId: tNeedsYou.id,
            actor: operatorActor,
            reason: "是否同步开启微信到期提醒？"
        )

        let tDone = store.createBoardThread(
            channelSlug: "dev",
            title: "统一协议层 39 项枚举 1:1 校验",
            body: "JSON Schema、TypeScript 与 Swift 端保持严格一致。",
            priority: .normal,
            author: coderActor
        )
        _ = store.completeBoardTask(
            threadId: tDone.id,
            actor: coderActor,
            summary: "audit:protocol 39/39 PASS",
            deliverableRef: "scripts/audit-protocol-parity.mjs"
        )

        _ = store.generateUniversalPairingLink(scope: .owner)
        store.lastBoxSelfCheck = PipiBoxSelfCheckResult(
            backend: "seatbelt",
            checks: [
                PipiBoxSelfCheckItem(name: "block_secret_read", passed: true, detail: "OK"),
                PipiBoxSelfCheckItem(name: "block_outside_write", passed: true, detail: "OK"),
                PipiBoxSelfCheckItem(name: "allow_workspace_write", passed: true, detail: "OK"),
                PipiBoxSelfCheckItem(name: "profile_integrity", passed: true, detail: "OK")
            ]
        )
        return store
    }

    private static func renderViaHostingWindow<V: View>(
        view: V,
        size: CGSize,
        appearance: NSAppearance.Name,
        splitSidebarWidth: CGFloat?,
        to url: URL
    ) {
        let rect = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = true

        let hosting = NSHostingView(rootView: view)
        hosting.frame = rect
        hosting.wantsLayer = true
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderBack(nil)

        // Pump main RunLoop briefly so SwiftUI & AppKit lay out NavigationSplitView, ScrollViews, and TextViews
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        if let sidebarWidth = splitSidebarWidth {
            if let outerSplit = findSubviews(ofType: NSSplitView.self, in: hosting).first,
               outerSplit.arrangedSubviews.count >= 2 {
                outerSplit.setPosition(sidebarWidth, ofDividerAt: 0)
            }
        }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.20))

        let scale: CGFloat = 2.0
        let pixelW = Int(size.width * scale)
        let pixelH = Int(size.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            window.orderOut(nil)
            return
        }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url, options: .atomic)
        }
        window.orderOut(nil)
    }

    private static func findSubviews<T: NSView>(ofType type: T.Type, in root: NSView) -> [T] {
        var found: [T] = []
        for subview in root.subviews {
            if let match = subview as? T {
                found.append(match)
            }
            found.append(contentsOf: findSubviews(ofType: type, in: subview))
        }
        return found
    }
}
#endif
