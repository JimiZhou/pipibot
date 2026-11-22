// PiPiBot — Clean-room MIT implementation.
// Renders real Retina screenshots of the actual SwiftUI macOS views when launched with:
//   PipiBotMacApp --export-showcase-screenshots <output-dir>

#if os(macOS)
import AppKit
import SwiftUI
import PipiBotKit

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

        return true
    }

    private static func buildShowcaseStore() -> PipiAppStore {
        let store = PipiAppStore(enableNativeRuntime: false)
        store.hasCompletedOnboarding = true
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
            for splitView in findSubviews(ofType: NSSplitView.self, in: hosting) {
                if splitView.arrangedSubviews.count >= 2 {
                    splitView.setPosition(sidebarWidth, ofDividerAt: 0)
                }
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
