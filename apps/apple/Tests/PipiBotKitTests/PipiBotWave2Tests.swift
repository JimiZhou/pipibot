import Foundation
import XCTest
@testable import PipiBotKit

private final class Wave2MockSignalProvider: PipiNativeSignalProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var queuedSignals: [PipiProactiveSignal]

    init(signals: [PipiProactiveSignal] = []) {
        self.queuedSignals = signals
    }

    func setSignals(_ signals: [PipiProactiveSignal]) {
        lock.lock()
        self.queuedSignals = signals
        lock.unlock()
    }

    private func snapshotSignals() -> [PipiProactiveSignal] {
        lock.withLock { queuedSignals }
    }

    func collectSignals(input: PipiNativeSignalCollectorInput) async -> [PipiProactiveSignal] {
        snapshotSignals()
    }

    func calendarAuthorizationState() -> PipiEventKitAuthState { .authorized }
    func remindersAuthorizationState() -> PipiEventKitAuthState { .authorized }
    func requestCalendarAccess() async -> PipiEventKitAuthState { .authorized }
    func requestRemindersAccess() async -> PipiEventKitAuthState { .authorized }
}

private final class Wave2CallCapture: @unchecked Sendable {
    private let lock = NSLock()
    var systemPrompts: [String] = []
    var lastUserMessages: [String] = []

    func record(systemPrompt: String, history: [PipiChatMessage]) {
        lock.lock()
        systemPrompts.append(systemPrompt)
        lastUserMessages.append(history.last(where: { $0.role == .user })?.content ?? "")
        lock.unlock()
    }
}

@MainActor
final class PipiBotWave2Tests: XCTestCase {

    private func makeTempDir(_ prefix: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - #01 Personal Entity Wiki (SQLite3 WAL + FTS5 + CJK Bigram + Dual-Channel + Soft Window RRF)

    func testPersonalWikiSQLiteWalFts5DualChannelSearchAndMarkdownProjection() throws {
        let dir = try makeTempDir("pipibot-w2-wiki")
        defer { try? FileManager.default.removeItem(at: dir) }

        let dbPath = dir.appendingPathComponent("wiki.sqlite").path
        let wiki = try PipiPersonalWikiStore(dbPath: dbPath, markdownRootURL: dir)

        XCTAssertEqual(wiki.journalMode(), "wal", "Personal Wiki must use SQLite WAL mode")
        XCTAssertTrue(wiki.supportsFts5, "Apple native SQLite3 must enable FTS5")

        let octPage = try wiki.upsertPage(PipiWikiPageInput(
            category: .life,
            title: "秋季川西露营计划",
            aliases: ["川西自驾", "高原露营"],
            summary: "川西高原露营装备清单与便携咖啡壶备忘",
            bodyMarkdown: "## 装备\n准备 -10℃ 羽绒睡袋、户外电源与便携咖啡壶。\n切勿明文记录 sk-proj-1234567890abcdefghijklmno。",
            eventDate: "2026-10-18",
            facts: [
                PipiWikiFactInput(
                    factText: "川西露营需要 -10℃ 羽绒睡袋和便携咖啡壶",
                    entities: ["川西露营", "便携咖啡壶"],
                    eventDate: "2026-10-18",
                    confidence: 0.94
                )
            ]
        ))

        _ = try wiki.upsertPage(PipiWikiPageInput(
            category: .life,
            title: "春季杭州露营复盘",
            aliases: ["春游露营"],
            summary: "杭州周边草坪露营与便携咖啡壶体验",
            bodyMarkdown: "## 营地\n杭州草坪营地轻松露营，带便携咖啡壶即可。",
            eventDate: "2026-04-12",
            facts: [
                PipiWikiFactInput(
                    factText: "杭州春季露营带轻量化便携咖啡壶最省心",
                    entities: ["杭州露营"],
                    eventDate: "2026-04-12",
                    confidence: 0.88
                )
            ]
        ))

        _ = try wiki.upsertPage(PipiWikiPageInput(
            category: .repos,
            title: "PiPiBot Native Host",
            aliases: ["pipibot", "Swift6"],
            summary: "原生 macOS Swift 6 个人智能体宿主与本地 SQLite 知识库",
            bodyMarkdown: "## 架构\n双层风控护栏与 7 级优先级模型调度。",
            eventDate: "2026-11-20"
        ))

        // Verify projected Markdown has YAML frontmatter and scrubbed secret
        let mdUrl = dir
            .appendingPathComponent("knowledge", isDirectory: true)
            .appendingPathComponent("life", isDirectory: true)
            .appendingPathComponent("\(octPage.slug).md")
        let mdText = try String(contentsOf: mdUrl, encoding: .utf8)
        XCTAssertTrue(mdText.contains("pipibot_wiki_version: \"1.0\""))
        XCTAssertTrue(mdText.contains("category: life"))
        XCTAssertFalse(mdText.contains("sk-proj-1234567890abcdefghijklmno"))
        XCTAssertTrue(mdText.contains("[REDACTED:OPENAI_OR_SK_KEY:"))

        // Zero-embedding dual-channel search with >6 alternates (clamped to 6) + soft time-window RRF
        let result = wiki.search(PipiWikiSearchOptions(
            query: "露营咖啡壶",
            alternates: ["川西自驾", "羽绒睡袋", "户外电源", "营地", "高原", "装备", "超额第七个改写词"],
            startDate: "2026-10-01",
            endDate: "2026-10-31",
            scope: .all
        ))

        XCTAssertTrue(result.usedFts5)
        XCTAssertFalse(result.usedVectorChannel, "Default search must use zero embedding calls")
        XCTAssertEqual(result.effectiveQueries.count, 7, "1 primary + max 6 alternates")
        XCTAssertGreaterThanOrEqual(result.chunks.count, 2, "Soft time window preserves relevant out-of-window hit")
        XCTAssertEqual(result.chunks.first?.pageId, octPage.id, "In-window October page must rank #1 via soft window RRF")
        XCTAssertEqual(result.chunks.first?.inTimeWindow, true)
        XCTAssertEqual(result.facts.first?.pageId, octPage.id, "Independent facts channel returns atomic fact")
        XCTAssertFalse(result.summaries.isEmpty)

        // Summaries-only scope omits chunks and facts
        let summaryOnly = wiki.search(PipiWikiSearchOptions(query: "Swift6", scope: .summaries))
        XCTAssertTrue(summaryOnly.chunks.isEmpty)
        XCTAssertTrue(summaryOnly.facts.isEmpty)
        XCTAssertEqual(summaryOnly.summaries.first?.category, .repos)
    }

    // MARK: - #02 Per-Bot Isolated Memory + 5-Run Extraction + 6h Idle Consolidation

    func testPerBotIsolatedMemoryCadenceAndZeroCrossBotLeakage() async throws {
        let dir = try makeTempDir("pipibot-w2-botmem")
        defer { try? FileManager.default.removeItem(at: dir) }

        let engine = PipiBotMemoryEngine(
            rootURL: dir,
            cadence: PipiBotMemoryCadenceConfig(
                extractEveryRuns: 5,
                idleConsolidationHours: 6,
                maxUnconsolidatedBytes: 64 * 1024,
                maxChatsBeforeConsolidation: 30
            )
        )

        let t0 = Date(timeIntervalSince1970: 1_795_165_200) // 2026-11-20T09:00:00Z
        for i in 1...4 {
            let outcome = await engine.recordSuccessfulRun(PipiBotMemoryRunInput(
                botId: "bot_coder",
                sessionId: "sess_1",
                userPrompt: "Audit Swift module \(i)",
                assistantReply: "Always verify Sendable conformance and PipiTokens compliance in view \(i).",
                now: t0.addingTimeInterval(Double(i * 60))
            ))
            XCTAssertTrue(outcome.extractedCandidates.isEmpty)
            XCTAssertFalse(outcome.consolidated)
        }

        // 5th successful run triggers extraction
        let run5 = await engine.recordSuccessfulRun(PipiBotMemoryRunInput(
            botId: "bot_coder",
            sessionId: "sess_1",
            userPrompt: "Audit Swift module 5",
            assistantReply: "Keep deterministic offline tests passing before merge.",
            now: t0.addingTimeInterval(5 * 60)
        ))
        XCTAssertFalse(run5.extractedCandidates.isEmpty, "Every 5th successful run must extract candidates")
        XCTAssertEqual(run5.state.successfulRunsSinceLastExtract, 0)
        XCTAssertFalse(run5.consolidated)

        // 3h idle -> not yet consolidated
        let idle3h = await engine.consolidateIfDue(botId: "bot_coder", now: t0.addingTimeInterval(3 * 3600), trigger: .idleCheck)
        XCTAssertFalse(idle3h.consolidated)

        // 7h idle -> consolidates into summary.md
        let idle7h = await engine.consolidateIfDue(botId: "bot_coder", now: t0.addingTimeInterval(7 * 3600), trigger: .idleCheck)
        XCTAssertTrue(idle7h.consolidated)
        XCTAssertEqual(idle7h.reason, .idleTimeout)
        XCTAssertEqual(idle7h.state.revision, 1)
        XCTAssertTrue(idle7h.summary.contains("Sendable conformance"))

        // Strict isolation: bot_writer never sees bot_coder's memory
        XCTAssertEqual(engine.readSummary(for: "bot_writer"), "")
        let writerRecall = engine.buildPromptCacheSafeRecall(botId: "bot_writer", sessionId: "sess_w", compactionGeneration: 0)
        XCTAssertFalse(writerRecall.injected)
        XCTAssertEqual(writerRecall.reason, .emptyMemory)
    }

    // MARK: - #02 Store-Level Prompt-Cache-Safe Recall & Compaction Re-Injection

    func testStorePromptCacheSafeRecallNeverMutatesSystemPromptAndReinjectsAfterCompaction() async throws {
        let dir = try makeTempDir("pipibot-w2-store-cache")
        defer { try? FileManager.default.removeItem(at: dir) }

        let stateUrl = dir.appendingPathComponent("resident-state.json")
        let capture = Wave2CallCapture()
        let executor: PipiSessionInferenceExecutor = { _, _, systemPrompt, history, _, _, _, _, _ in
            capture.record(systemPrompt: systemPrompt, history: history)
            return PipiInferenceResult(text: "Acknowledged and keeping code minimal with PipiTokens.", engineLabel: "Mock LLM")
        }

        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore(),
            saveDebounceMilliseconds: 0,
            sessionInferenceExecutor: executor
        )
        let provider = PipiLLMProviderConfig(id: "llm_mock", name: "Mock", kind: .openai, apiKey: "sk-test", modelId: "gpt-4o")
        store.upsertLLMProvider(provider, setAsDefault: true)
        store.saveBotMemorySummary(for: store.activePersona.id, summary: "# Bot Memory\n- Always answer concisely in Chinese.")

        let conv = store.createConversation(for: store.activePersona.id, title: "Cache Test", activate: true)

        // Turn 1: injects hidden note in outbound user message ONLY, keeps systemPrompt pristine & UI messages clean
        await store.sendPersonalMessage("First turn question", conversationId: conv.id)
        XCTAssertEqual(store.lastPromptCacheRecallResult?.injected, true)
        XCTAssertEqual(store.lastPromptCacheRecallResult?.reason, .firstTurn)
        XCTAssertEqual(capture.lastUserMessages.count, 1)
        XCTAssertTrue(capture.lastUserMessages[0].contains("<pipibot_bot_memory"))
        XCTAssertTrue(capture.lastUserMessages[0].contains("Always answer concisely in Chinese."))
        XCTAssertFalse(capture.systemPrompts[0].contains("<pipibot_bot_memory"), "Memory MUST NOT enter System Prompt")
        let visibleFirstUser = store.conversations.first(where: { $0.id == conv.id })?.messages.first(where: { $0.role == .user })?.content ?? ""
        XCTAssertFalse(visibleFirstUser.contains("<pipibot_bot_memory"), "Visible chat bubble must stay clean")

        // Turn 2 (same session, no compaction): SKIPPED to preserve Prompt Cache, byte-identical System Prompt!
        await store.sendPersonalMessage("Second turn follow-up", conversationId: conv.id)
        XCTAssertEqual(store.lastPromptCacheRecallResult?.injected, false)
        XCTAssertEqual(store.lastPromptCacheRecallResult?.reason, .skippedCachePreserved)
        XCTAssertEqual(capture.systemPrompts[0], capture.systemPrompts[1], "System Prompt must remain byte-identical for KV cache hit")
        XCTAssertFalse(capture.lastUserMessages[1].contains("<pipibot_bot_memory"))

        // Compact conversation -> increments compactionGeneration & consolidates -> Turn 3 re-injects!
        let compacted = await store.compactConversation(id: conv.id)
        XCTAssertTrue(compacted)
        XCTAssertEqual(store.conversations.first(where: { $0.id == conv.id })?.compactionGeneration, 1)

        await store.sendPersonalMessage("Third turn after compaction", conversationId: conv.id)
        XCTAssertEqual(store.lastPromptCacheRecallResult?.injected, true)
        XCTAssertEqual(store.lastPromptCacheRecallResult?.reason, .postCompaction)
        XCTAssertEqual(capture.systemPrompts[0], capture.systemPrompts[2], "System Prompt remains invariant even after compaction")
        XCTAssertTrue(capture.lastUserMessages[2].contains("<pipibot_bot_memory"))
        XCTAssertTrue(capture.lastUserMessages[2].contains("mode=\"post_compaction\""))
    }

    // MARK: - #03 Native Proactive Guardrails, Prepare + Wiki Enrichment, Clue->Rule Dreaming & Rollback Persistence

    func testProactiveGuardrailsPrepareWikiEnrichmentAndClueToRuleRollback() async throws {
        let dir = try makeTempDir("pipibot-w2-proactive")
        defer { try? FileManager.default.removeItem(at: dir) }

        let stateUrl = dir.appendingPathComponent("resident-state.json")
        let mockSignals = Wave2MockSignalProvider()

        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore(),
            saveDebounceMilliseconds: 0,
            nativeSignalProvider: mockSignals
        )

        // Seed Personal Wiki entity for Prepare enrichment
        _ = store.upsertWikiPage(PipiWikiPageInput(
            category: .people,
            title: "林远",
            aliases: ["Lin Yuan"],
            summary: "SwiftUI 动效设计师，合作打磨无边框极简组件",
            bodyMarkdown: "## 偏好\n偏爱克制的原生材质与响应迅速的弹簧动效。",
            eventDate: "2026-11-19"
        ))

        store.updateProactivePolicy(PipiProactiveGuardrailPolicy(
            quietHoursEnabled: true,
            quietHoursStart: 22,
            quietHoursEnd: 8,
            maxDailyNotifications: 2,
            chatSilenceSeconds: 180,
            prepareLeadMinutes: 120
        ))

        let daytime = Date(timeIntervalSince1970: 1_795_170_600) // 10:30 local reference
        let dueSoonIso = ISO8601DateFormatter().string(from: daytime.addingTimeInterval(45 * 60))

        mockSignals.setSignals([
            PipiProactiveSignal(
                source: .calendarEventKit,
                kind: "upcoming_event",
                matter: "林远设计评审",
                title: "和林远评审界面动效",
                content: "确认卡片留白与弹簧参数",
                dueAtIso: dueSoonIso,
                supportsPrepare: true
            )
        ])

        // 1. Quiet hours (23:00) suppresses notification
        let quietOutcomes = await store.scanNativeProactiveSignals(now: daytime, localHourOverride: 23)
        XCTAssertEqual(quietOutcomes.first?.deferredReason, .quietHours)
        XCTAssertEqual(quietOutcomes.first?.notifiedUser, false)

        // 2. Active chat within 3 minutes defers notification
        store.proactiveEngine.recordUserChatActivity(at: daytime.addingTimeInterval(-60))
        let silenceOutcomes = await store.scanNativeProactiveSignals(now: daytime, localHourOverride: 10)
        XCTAssertEqual(silenceOutcomes.first?.deferredReason, .chatActiveSilence)

        // 3. After 3+ minutes silence -> Prepare briefing enriched with Personal Wiki!
        let afterSilence = daytime.addingTimeInterval(240)
        let prepOutcomes = await store.scanNativeProactiveSignals(now: afterSilence, localHourOverride: 10)
        XCTAssertEqual(prepOutcomes.first?.decision, .prepareBriefing)
        XCTAssertEqual(prepOutcomes.first?.notifiedUser, true)
        XCTAssertTrue(prepOutcomes.first?.briefing?.relatedWikiTitles.contains("林远") ?? false)

        // 4. Open briefing in chat creates a conversation seeded with Prepare context
        if let brief = prepOutcomes.first?.briefing {
            let chat = store.openBriefingInChat(brief)
            XCTAssertTrue(chat.messages.first?.content.contains("林远") ?? false)
        }

        // 5. Git signal + two dismissals across 2 days -> promotes Clue -> Rule, suppresses Day 3, and supports Rollback!
        mockSignals.setSignals([
            PipiProactiveSignal(
                source: .gitWorkspace,
                kind: "dirty_repo",
                matter: "周报分支提醒",
                title: "pipibot 有未推送提交",
                content: "main 分支 ahead 2 commits"
            )
        ])
        let day1Git = await store.scanNativeProactiveSignals(now: afterSilence, localHourOverride: 10)
        let briefDay1 = try XCTUnwrap(day1Git.first?.briefing)
        store.recordProactiveFeedback(briefingId: briefDay1.id, signal: .dismissed, now: afterSilence)
        let dream1 = store.runProactiveNightlyDreaming(todayYmd: "2026-11-20")
        XCTAssertEqual(dream1.promotedRules.count, 0, "seen = 1 must remain a clue")
        XCTAssertEqual(dream1.activeCluesCount, 2, "1 positive acted clue from openBriefingInChat + 1 dismissed clue")
        XCTAssertTrue(store.proactiveClues.contains(where: { $0.matter == "林远设计评审" && $0.leaning == .remindDirectly && $0.seen == 1 }))
        XCTAssertTrue(store.proactiveClues.contains(where: { $0.matter == "周报分支提醒" && $0.leaning == .staySilent && $0.seen == 1 }))

        // Day 2: second negative feedback promotes to rule
        let day2 = afterSilence.addingTimeInterval(86_400)
        mockSignals.setSignals([
            PipiProactiveSignal(
                source: .gitWorkspace,
                kind: "dirty_repo",
                matter: "周报分支提醒",
                title: "pipibot 有未推送提交",
                content: "main 分支 ahead 3 commits"
            )
        ])
        let day2Git = await store.scanNativeProactiveSignals(now: day2, localHourOverride: 10)
        let briefDay2 = try XCTUnwrap(day2Git.first?.briefing)
        store.recordProactiveFeedback(briefingId: briefDay2.id, signal: .mutedTopic, now: day2)
        let dream2 = store.runProactiveNightlyDreaming(todayYmd: "2026-11-21")
        XCTAssertEqual(dream2.promotedRules.count, 1, "seen >= 2 within 14 days must promote to rule")
        XCTAssertEqual(dream2.promotedRules.first?.leaning, .staySilent)
        store.flush()

        // Reload store from disk to verify persistence of learned proactive rules & history
        let reloaded = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore(),
            saveDebounceMilliseconds: 0,
            nativeSignalProvider: mockSignals
        )
        XCTAssertEqual(reloaded.proactiveRules.count, 1)

        // Day 3: learned rule suppresses signal automatically
        let day3 = day2.addingTimeInterval(86_400)
        mockSignals.setSignals([
            PipiProactiveSignal(
                source: .gitWorkspace,
                kind: "dirty_repo",
                matter: "周报分支提醒",
                title: "pipibot 有未推送提交",
                content: "main 分支 ahead 4 commits"
            )
        ])
        let day3Outcomes = await reloaded.scanNativeProactiveSignals(now: day3, localHourOverride: 10)
        XCTAssertEqual(day3Outcomes.first?.decision, .staySilent)
        XCTAssertEqual(day3Outcomes.first?.deferredReason, .mutedByRule)

        // 1-click rollback to pre-promotion version removes the learned rule cleanly
        let rolledBack = reloaded.rollbackProactiveGuideline(toVersion: dream1.newVersion)
        XCTAssertTrue(rolledBack)
        XCTAssertTrue(reloaded.proactiveRules.isEmpty)
    }
}
