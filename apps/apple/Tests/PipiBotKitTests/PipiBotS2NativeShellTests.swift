import XCTest
@testable import PipiBotKit

final class PipiBotS2NativeShellTests: XCTestCase {

    @MainActor
    func testConversationPinDefaultDecodingAndToggle() throws {
        let legacyJson = """
        {
          "id": "conv_old",
          "personaId": "bot_pipi_general",
          "title": "Legacy Thread",
          "messages": []
        }
        """
        let decoded = try JSONDecoder().decode(PipiConversation.self, from: Data(legacyJson.utf8))
        XCTAssertFalse(decoded.isPinned)

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-s2-pin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let stateUrl = dir.appendingPathComponent("resident-state.json")
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore()
        )
        let conv = store.createConversation(title: "Pin Test")
        XCTAssertFalse(conv.isPinned)

        store.togglePinConversation(conv.id)
        XCTAssertTrue(store.conversations.first(where: { $0.id == conv.id })?.isPinned == true)

        store.flush()
        let reloaded = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore()
        )
        XCTAssertTrue(reloaded.conversations.first(where: { $0.id == conv.id })?.isPinned == true)
    }

    @MainActor
    func testGlobalSessionGroupingBotFilterAndMessageSearch() {
        let now = Date()
        let cal = Calendar.current
        let iso = ISO8601DateFormatter()

        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            secretStore: PipiInMemorySecretStore()
        )

        let todayStr = iso.string(from: now)
        let yesterdayStr = iso.string(from: cal.date(byAdding: .day, value: -1, to: now)!)
        let threeDaysAgoStr = iso.string(from: cal.date(byAdding: .day, value: -3, to: now)!)
        let twentyDaysAgoStr = iso.string(from: cal.date(byAdding: .day, value: -20, to: now)!)

        store.conversations = [
            PipiConversation(
                id: "c_needs",
                personaId: "bot_pipi_coder",
                title: "Approval Task",
                state: .needsYou,
                createdAt: twentyDaysAgoStr,
                updatedAt: twentyDaysAgoStr
            ),
            PipiConversation(
                id: "c_pinned",
                personaId: "bot_pipi_writer",
                title: "Pinned Memo",
                isPinned: true,
                createdAt: twentyDaysAgoStr,
                updatedAt: twentyDaysAgoStr
            ),
            PipiConversation(
                id: "c_today",
                personaId: "bot_pipi_general",
                title: "Today Chat",
                messages: [PipiChatMessage(role: .user, content: "Check SwiftUI NavigationSplitView migration")],
                createdAt: todayStr,
                updatedAt: todayStr
            ),
            PipiConversation(
                id: "c_yesterday",
                personaId: "bot_pipi_coder",
                title: "Yesterday Bug",
                createdAt: yesterdayStr,
                updatedAt: yesterdayStr
            ),
            PipiConversation(
                id: "c_week",
                personaId: "bot_pipi_operator",
                title: "Weekly Plan",
                createdAt: threeDaysAgoStr,
                updatedAt: threeDaysAgoStr
            ),
            PipiConversation(
                id: "c_old",
                personaId: "bot_pipi_general",
                title: "Old Archive Candidate",
                createdAt: twentyDaysAgoStr,
                updatedAt: twentyDaysAgoStr
            ),
            PipiConversation(
                id: "c_arch",
                personaId: "bot_pipi_general",
                title: "Archived Chat",
                isArchived: true,
                createdAt: todayStr,
                updatedAt: todayStr
            )
        ]

        let grouped = store.groupedGlobalSessions(now: now)
        XCTAssertEqual(grouped.map(\.bucket), [.activeOrNeedsYou, .pinned, .today, .yesterday, .last7Days, .earlier])
        XCTAssertEqual(grouped[0].conversations.map(\.id), ["c_needs"])
        XCTAssertEqual(grouped[1].conversations.map(\.id), ["c_pinned"])
        XCTAssertEqual(grouped[2].conversations.map(\.id), ["c_today"])
        XCTAssertEqual(grouped[3].conversations.map(\.id), ["c_yesterday"])
        XCTAssertEqual(grouped[4].conversations.map(\.id), ["c_week"])
        XCTAssertEqual(grouped[5].conversations.map(\.id), ["c_old"])

        // Bot filter restricts global sessions to that bot
        let coderOnly = store.groupedGlobalSessions(botFilterId: "bot_pipi_coder", now: now)
        XCTAssertEqual(coderOnly.flatMap(\.conversations).map(\.id), ["c_needs", "c_yesterday"])

        // Search matches message body text even when title doesn't match
        let bodyMatches = store.searchConversations(query: "NavigationSplitView")
        XCTAssertEqual(bodyMatches.map(\.conversation.id), ["c_today"])
        XCTAssertNotNil(bodyMatches.first?.matchedMessageSnippet)
    }

    @MainActor
    func testTextScaleSyncAndClamping() {
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            secretStore: PipiInMemorySecretStore()
        )
        defer { PipiTokens.textScale = 1.0 }

        store.resetZoom()
        XCTAssertEqual(PipiTokens.textScale, 1.0, accuracy: 0.001)
        XCTAssertEqual(PipiTokens.scaledPointSize(14), 14.0, accuracy: 0.001)

        store.setZoomScale(1.3)
        XCTAssertEqual(store.uiZoomScale, 1.3, accuracy: 0.001)
        XCTAssertEqual(PipiTokens.textScale, 1.3, accuracy: 0.001)
        XCTAssertEqual(PipiTokens.scaledPointSize(14), 18.0, accuracy: 0.5)

        store.setZoomScale(5.0)
        XCTAssertEqual(store.uiZoomScale, PipiAppStore.maxZoomScale, accuracy: 0.001)
        XCTAssertEqual(PipiTokens.textScale, CGFloat(PipiAppStore.maxZoomScale), accuracy: 0.001)

        store.setZoomScale(0.2)
        XCTAssertEqual(store.uiZoomScale, PipiAppStore.minZoomScale, accuracy: 0.001)
        XCTAssertEqual(PipiTokens.textScale, CGFloat(PipiAppStore.minZoomScale), accuracy: 0.001)
    }

    @MainActor
    func testNeedsYouInboxAndInlineApprovalConsistency() async {
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            secretStore: PipiInMemorySecretStore()
        )

        let approval = PipiSessionApproval(
            id: "appr_inbox_1",
            sessionId: "conv_inbox_1",
            question: "Allow running git status?",
            options: [
                .init(id: "allow", label: "Allow", style: .primary),
                .init(id: "deny", label: "Deny", style: .secondary)
            ],
            recommendedOptionId: "allow"
        )
        let conv = PipiConversation(
            id: "conv_inbox_1",
            personaId: "bot_pipi_coder",
            title: "Git Check",
            state: .needsYou,
            approvals: [approval]
        )
        store.conversations = [conv]

        XCTAssertEqual(store.pendingApprovals.map(\.id), ["appr_inbox_1"])
        XCTAssertEqual(store.totalNeedsYouCount, 1)

        await store.resolveApproval("appr_inbox_1", optionId: "deny")

        XCTAssertTrue(store.pendingApprovals.isEmpty)
        XCTAssertEqual(store.totalNeedsYouCount, 0)
        XCTAssertEqual(store.conversations.first?.approvals.first?.status, .denied)
    }

    @MainActor
    func testHostDisplayNameAndContextUsageEstimation() {
        let namedHost = PipiHostDescriptor.local(name: "Yujie的Mac Mini")
        XCTAssertEqual(namedHost.displayName(.zhHans), "Yujie的Mac Mini")
        XCTAssertEqual(namedHost.displayName(.en), "Yujie的Mac Mini")

        let blankLocalHost = PipiHostDescriptor(name: "   ", kind: .local)
        XCTAssertEqual(blankLocalHost.displayName(.zhHans), "本机")
        XCTAssertEqual(blankLocalHost.displayName(.en), "This Mac")
        XCTAssertFalse(PipiHostDescriptor.currentLocalMachineName().isEmpty)

        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            secretStore: PipiInMemorySecretStore()
        )
        store.memoryEnabled = true
        store.personalProfileNote = "Prefer concise replies in Chinese with concrete checklists."

        let attachment = PipiChatAttachment(
            name: "notes.md",
            path: "/tmp/notes.md",
            sizeBytes: 120,
            textContent: "Check nginx, k8s pods, and postgres backups."
        )
        let conv = PipiConversation(
            personaId: "bot_pipi_general",
            title: "Daily Checklist",
            lastEngineLabel: "Codex CLI",
            messages: [
                PipiChatMessage(role: .user, content: "帮我整理今天的服务器巡检清单", attachments: [attachment]),
                PipiChatMessage(role: .assistant, content: "好的，这是今天的结构化检查清单：1. 检查网关健康 2. 核对数据库备份。")
            ]
        )
        store.conversations = [conv]
        store.selectConversation(conv.id)

        let usageWithMemory = store.estimateContextUsage(for: conv)
        XCTAssertEqual(usageWithMemory.contextWindowTokens, 128_000)
        XCTAssertEqual(usageWithMemory.formattedWindowTokens, "128k")
        XCTAssertEqual(usageWithMemory.messageCount, 2)
        XCTAssertEqual(usageWithMemory.turnCount, 1)
        XCTAssertEqual(usageWithMemory.attachmentCount, 1)
        XCTAssertTrue(usageWithMemory.isMemoryEnabled)
        XCTAssertTrue(usageWithMemory.hasPersonalProfile)
        XCTAssertGreaterThan(usageWithMemory.estimatedTokens, 50)

        store.memoryEnabled = false
        let usageWithoutMemory = store.estimateContextUsage(for: conv)
        XCTAssertFalse(usageWithoutMemory.isMemoryEnabled)
        XCTAssertLessThan(usageWithoutMemory.estimatedTokens, usageWithMemory.estimatedTokens)

        var claudeConv = conv
        claudeConv.lastEngineLabel = "Claude Code"
        XCTAssertEqual(store.estimateContextUsage(for: claudeConv).contextWindowTokens, 200_000)
    }
}
