import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PipiBotKit

final class PipiBotS1SessionCoreTests: XCTestCase {

    // MARK: - 1. Host Seam, Legacy Migration & PipiHostConnection Protocol

    @MainActor
    func testHostSeamLegacyMigrationAndLocalHostConnectionRouting() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-s1-host-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let stateUrl = dir.appendingPathComponent("resident-state.json")
        let legacyJson: [String: Any] = [
            "hasCompletedOnboarding": true,
            "personas": [
                [
                    "id": "bot_legacy",
                    "nameZh": "旧版助手",
                    "nameEn": "Legacy Bot",
                    "roleZh": "助手",
                    "roleEn": "Helper",
                    "greetingZh": "你好",
                    "greetingEn": "Hi",
                    "systemPrompt": "Be helpful."
                ]
            ],
            "conversations": [
                [
                    "id": "conv_legacy",
                    "personaId": "bot_legacy",
                    "title": "Legacy Session",
                    "state": "running", // simulate crash mid-run
                    "messages": [
                        [
                            "id": "msg_1",
                            "role": "user",
                            "content": "Hello"
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: legacyJson)
        try data.write(to: stateUrl, options: .atomic)

        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore(),
            inferenceExecutor: { _, _, _, _, _, onDelta in
                onDelta?("Hi ")
                return PipiInferenceResult(text: "Hi from host", engineLabel: "Mock · gpt-4o")
            }
        )

        // Default-decoded hostId & permissionTier
        let bot = try XCTUnwrap(store.personas.first(where: { $0.id == "bot_legacy" }))
        XCTAssertEqual(bot.hostId, PipiHostDescriptor.localHostId)
        XCTAssertEqual(bot.permissionTier, .ask)

        let conv = try XCTUnwrap(store.conversations.first(where: { $0.id == "conv_legacy" }))
        XCTAssertEqual(conv.hostId, PipiHostDescriptor.localHostId)
        // Stale running state sanitized on load
        XCTAssertEqual(conv.state, .cancelled)
        XCTAssertEqual(store.localHost.id, PipiHostDescriptor.localHostId)
        XCTAssertEqual(store.localHost.kind, .local)
        XCTAssertEqual(store.localHost.linkState, .online)

        // Route via PipiHostConnection
        let provider = PipiLLMProviderConfig(
            id: "llm_host_test",
            name: "Mock",
            kind: .openai,
            apiKey: "sk-test",
            modelId: "gpt-4o"
        )
        store.upsertLLMProvider(provider, setAsDefault: true)

        let conn: any PipiHostConnection = store.activeHostConnection
        let bots = try await conn.listBots()
        XCTAssertTrue(bots.contains(where: { $0.id == "bot_legacy" }))

        let sessionId = try await conn.send(
            sessionId: conv.id,
            botId: bot.id,
            input: PipiUserInput(text: "Ping host")
        )
        XCTAssertEqual(sessionId, conv.id)

        // Wait for run completion
        for _ in 0..<40 {
            if !store.isRunning(conversationId: conv.id) { break }
            try await Task.sleep(for: .milliseconds(25))
        }

        let sessions = try await conn.listSessions(since: nil)
        let summary = try XCTUnwrap(sessions.first(where: { $0.id == conv.id }))
        XCTAssertEqual(summary.hostId, PipiHostDescriptor.localHostId)
        XCTAssertGreaterThan(summary.lastEventSeq, 0)

        // Replay events via AsyncThrowingStream
        var replayed: [PipiSessionEvent] = []
        let stream = conn.events(sessionId: conv.id, afterSeq: 0)
        let collectTask = Task {
            for try await evt in stream {
                replayed.append(evt)
                if replayed.count >= summary.lastEventSeq { break }
            }
        }
        try await Task.sleep(for: .milliseconds(80))
        collectTask.cancel()
        XCTAssertFalse(replayed.isEmpty)
    }

    // MARK: - 2. Claude Code & Codex CLI Arguments & Defensive JSONL Parsing

    func testLocalAgentArgumentsAndPermissionMapping() {
        let claudeReadOnly = PipiInferenceEngine.localAgentArguments(
            for: .claudeCode,
            prompt: "audit",
            permissionTier: .readOnly,
            cliSessionId: nil
        )
        XCTAssertTrue(claudeReadOnly.contains("--output-format"))
        XCTAssertTrue(claudeReadOnly.contains("stream-json"))
        XCTAssertTrue(claudeReadOnly.contains("--verbose"))
        XCTAssertTrue(claudeReadOnly.contains("--permission-mode"))
        XCTAssertTrue(claudeReadOnly.contains("plan"))
        XCTAssertFalse(claudeReadOnly.contains("--resume"))

        let claudeResumeAsk = PipiInferenceEngine.localAgentArguments(
            for: .claudeCode,
            prompt: "next",
            permissionTier: .ask,
            cliSessionId: "sess_abc"
        )
        XCTAssertTrue(claudeResumeAsk.contains("default"))
        XCTAssertTrue(claudeResumeAsk.contains("--resume"))
        XCTAssertTrue(claudeResumeAsk.contains("sess_abc"))

        let claudeAutoEdit = PipiInferenceEngine.localAgentArguments(
            for: .claudeCode,
            prompt: "fix",
            permissionTier: .autoEdit,
            cliSessionId: nil
        )
        XCTAssertTrue(claudeAutoEdit.contains("acceptEdits"))

        let codexReadOnly = PipiInferenceEngine.localAgentArguments(
            for: .codex,
            prompt: "inspect",
            permissionTier: .readOnly,
            cliSessionId: nil
        )
        XCTAssertEqual(codexReadOnly.first, "exec")
        XCTAssertTrue(codexReadOnly.contains("--json"))
        XCTAssertTrue(codexReadOnly.contains("--sandbox"))
        XCTAssertTrue(codexReadOnly.contains("read-only"))

        let codexAutoEdit = PipiInferenceEngine.localAgentArguments(
            for: .codex,
            prompt: "edit",
            permissionTier: .autoEdit,
            cliSessionId: nil
        )
        XCTAssertTrue(codexAutoEdit.contains("workspace-write"))

        let codexResume = PipiInferenceEngine.localAgentArguments(
            for: .codex,
            prompt: "continue",
            permissionTier: .autoEdit,
            cliSessionId: "thread_xyz"
        )
        XCTAssertEqual(Array(codexResume.prefix(2)), ["exec", "resume"])
        XCTAssertTrue(codexResume.contains("--json"))
        XCTAssertTrue(codexResume.contains("thread_xyz"))
    }

    func testClaudeStreamJsonParserFixtureLines() {
        var parser = PipiCLIAgentParser(kind: .claudeCode)
        let lines = [
            #"{"type":"system","subtype":"init","session_id":"claude_sess_42"}"#,
            #"{"type":"unknown_future_event","payload":{"foo":1}}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Checking "}}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_1","name":"Read","input":{"file_path":"/repo/App.swift"}},{"type":"tool_use","id":"tu_2","name":"TodoWrite","input":{"todos":[{"content":"Inspect App.swift","status":"completed"},{"content":"Patch bug","status":"pending"}]}},{"type":"tool_use","id":"tu_3","name":"Edit","input":{"file_path":"/repo/App.swift","old_string":"let a = 1","new_string":"let a = 2\nlet b = 3"}}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_1","content":"file contents","is_error":false}]}}"#,
            #"non-json warning line"#,
            #"{"type":"result","subtype":"success","is_error":false,"duration_ms":1450,"result":"Done updating App.swift","session_id":"claude_sess_42"}"#
        ].joined(separator: "\n") + "\n"

        let events = parser.feedChunk(lines) + parser.finish()

        XCTAssertTrue(events.contains(.sessionId("claude_sess_42")))
        XCTAssertTrue(events.contains(.textDelta("Checking ")))
        XCTAssertTrue(events.contains(.textDelta("non-json warning line\n")))

        let startedSteps = events.compactMap { ev -> PipiStepEvent? in
            if case .stepStarted(let step) = ev { return step }
            return nil
        }
        XCTAssertEqual(startedSteps.count, 3)
        XCTAssertEqual(startedSteps.first?.verbPhrase, "Read App.swift")

        let finishedRead = events.contains { ev in
            if case .stepFinished(let id, let status, _, _, _) = ev {
                return id == "tu_1" && status == .succeeded
            }
            return false
        }
        XCTAssertTrue(finishedRead)

        let plans = events.compactMap { ev -> [PipiPlanItem]? in
            if case .planUpdated(let items) = ev { return items }
            return nil
        }.last
        XCTAssertEqual(plans?.count, 2)
        XCTAssertEqual(plans?.first?.isCompleted, true)
        XCTAssertEqual(plans?.last?.isCompleted, false)

        let fileChanges = events.compactMap { ev -> PipiFileChange? in
            if case .fileChanged(let fc) = ev { return fc }
            return nil
        }
        XCTAssertEqual(fileChanges.count, 1)
        XCTAssertEqual(fileChanges.first?.fileName, "App.swift")
        XCTAssertEqual(fileChanges.first?.additions, 2)
        XCTAssertEqual(fileChanges.first?.deletions, 1)

        let hasSummary = events.contains { ev in
            if case .summary(let s) = ev { return s.durationMs == 1450 && s.exitCode == 0 }
            return false
        }
        XCTAssertTrue(hasSummary)
    }

    func testCodexJsonParserFixtureLines() {
        var parser = PipiCLIAgentParser(kind: .codex)
        let lines = [
            #"{"type":"thread.started","thread_id":"codex_thread_99"}"#,
            #"{"type":"weird_unseen_event","x":true}"#,
            #"{"type":"item.started","item":{"id":"cmd_1","type":"command_execution","command":"swift test","status":"in_progress"}}"#,
            #"{"type":"item.completed","item":{"id":"cmd_1","type":"command_execution","command":"swift test","aggregated_output":"All tests passed","exit_code":0,"status":"completed"}}"#,
            #"{"type":"item.completed","item":{"id":"fc_1","type":"file_change","changes":[{"path":"Sources/Foo.swift","kind":"update","additions":5,"deletions":2}]}}"#,
            #"{"type":"item.completed","item":{"id":"todo_1","type":"todo_list","items":[{"text":"Run tests","completed":true}]}}"#,
            #"{"type":"item.completed","item":{"id":"msg_1","type":"agent_message","text":"All green!"}}"#
        ].joined(separator: "\n") + "\n"

        let events = parser.feedChunk(lines) + parser.finish()

        XCTAssertTrue(events.contains(.sessionId("codex_thread_99")))
        XCTAssertTrue(events.contains(.textDelta("All green!")))

        XCTAssertTrue(events.contains { ev in
            if case .stepStarted(let s) = ev { return s.id == "cmd_1" && s.verbPhrase.contains("swift test") }
            return false
        })
        XCTAssertTrue(events.contains { ev in
            if case .stepFinished(let id, let status, _, _, let code) = ev {
                return id == "cmd_1" && status == .succeeded && code == 0
            }
            return false
        })
        XCTAssertTrue(events.contains { ev in
            if case .fileChanged(let fc) = ev {
                return fc.path == "Sources/Foo.swift" && fc.additions == 5 && fc.deletions == 2
            }
            return false
        })
        XCTAssertTrue(events.contains { ev in
            if case .planUpdated(let items) = ev {
                return items.count == 1 && items[0].title == "Run tests" && items[0].isCompleted
            }
            return false
        })
    }

    // MARK: - 3. Permission Tiers, `ask` Approval Flow, CLI Resume & Persistence

    @MainActor
    func testAskPermissionTierEmitsApprovalResumesWithAutoEditAndPersistsStructuredTurn() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-s1-approval-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let stateUrl = dir.appendingPathComponent("resident-state.json")

        let tracker = ExecutorRecorder()
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore(),
            saveDebounceMilliseconds: 0,
            sessionInferenceExecutor: { target, _, _, history, _, tier, cliSessionId, onDelta, onEvent in
                tracker.record(tier: tier, cliSessionId: cliSessionId, historyCount: history.count)
                if tier == .readOnly {
                    onEvent?(.sessionId("cli_sess_1"))
                    let plan = [PipiPlanItem(title: "Inspect code", isCompleted: true), PipiPlanItem(title: "Apply fix", isCompleted: false)]
                    onEvent?(.planUpdated(plan))
                    onEvent?(.stepStarted(PipiStepEvent(id: "s1", verbPhrase: "Read main.swift", status: .succeeded, durationMs: 120)))
                    onDelta?("Proposed plan ready.")
                    return PipiInferenceResult(
                        text: "Proposed plan ready.",
                        engineLabel: "Claude Code",
                        cliSessionId: "cli_sess_1",
                        steps: [PipiStepEvent(id: "s1", verbPhrase: "Read main.swift", status: .succeeded, durationMs: 120)],
                        planItems: plan
                    )
                } else {
                    onEvent?(.fileChanged(PipiFileChange(path: "main.swift", additions: 4, deletions: 1)))
                    onDelta?("Changes applied.")
                    return PipiInferenceResult(
                        text: "Changes applied.",
                        engineLabel: "Claude Code",
                        cliSessionId: cliSessionId ?? "cli_sess_1",
                        fileChanges: [PipiFileChange(path: "main.swift", additions: 4, deletions: 1)],
                        summaryInfo: PipiSessionSummaryInfo(conclusion: "Done", exitCode: 0, changedFilesCount: 1, durationMs: 500)
                    )
                }
            }
        )
        store.toggleLocalAgent(.claudeCode, enabled: true, setAsDefaultIfFirst: true)

        // Ensure project override works too
        var bot = store.activePersona
        bot.permissionTier = .readOnly
        store.upsertPersona(bot)
        let proj = PipiProject(name: "AskProj", permissionTierOverride: .ask)
        store.upsertProject(proj)
        XCTAssertEqual(store.effectivePermissionTier(for: bot, project: proj), .ask)

        let conv = store.createConversation(for: bot.id, projectId: proj.id)
        await store.sendPersonalMessage("Refactor main.swift", targetOverride: .localAgent(.claudeCode), conversationId: conv.id)

        // Pass 1 must run read-only and emit an approval card setting session to .needsYou
        XCTAssertEqual(tracker.calls.count, 1)
        XCTAssertEqual(tracker.calls[0].tier, .readOnly)
        XCTAssertNil(tracker.calls[0].cliSessionId)

        let afterRead = try XCTUnwrap(store.conversations.first(where: { $0.id == conv.id }))
        XCTAssertEqual(afterRead.state, .needsYou)
        XCTAssertEqual(afterRead.cliSessionId, "cli_sess_1")
        XCTAssertEqual(store.pendingApprovals.count, 1)

        let approval = try XCTUnwrap(store.pendingApprovals.first)
        XCTAssertEqual(approval.recommendedOptionId, "allow_changes")

        // Approve -> resumes same session with .autoEdit and stored cliSessionId
        await store.resolveApproval(approval.id, optionId: "allow_changes")

        XCTAssertEqual(tracker.calls.count, 2)
        XCTAssertEqual(tracker.calls[1].tier, .autoEdit)
        XCTAssertEqual(tracker.calls[1].cliSessionId, "cli_sess_1")
        XCTAssertEqual(tracker.calls[1].historyCount, 1) // resume does NOT re-send full history

        let afterWrite = try XCTUnwrap(store.conversations.first(where: { $0.id == conv.id }))
        XCTAssertEqual(afterWrite.state, .done)
        XCTAssertTrue(store.pendingApprovals.isEmpty)
        XCTAssertEqual(afterWrite.fileChanges.count, 1)
        XCTAssertEqual(afterWrite.messages.last?.summaryInfo?.exitCode, 0)

        // Flush and reload from disk to verify structured persistence round-trip
        store.flush()
        let reloaded = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore()
        )
        let reloadedConv = try XCTUnwrap(reloaded.conversations.first(where: { $0.id == conv.id }))
        XCTAssertEqual(reloadedConv.state, .done)
        XCTAssertEqual(reloadedConv.cliSessionId, "cli_sess_1")
        XCTAssertEqual(reloadedConv.planItems.count, 2)
        XCTAssertEqual(reloadedConv.fileChanges.count, 1)
        XCTAssertEqual(reloadedConv.approvals.first?.status, .approved)
    }

    // MARK: - 4. No-Engine Guide & Retry / Switch Engine

    @MainActor
    func testNoEngineGuideAndActionableRetrySwitchEngine() async throws {
        let tracker = ExecutorRecorder()
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            secretStore: PipiInMemorySecretStore(),
            inferenceExecutor: { target, _, _, _, _, _ in
                tracker.record(tier: .ask, cliSessionId: nil, historyCount: 1)
                if case .llm(let pid) = target, pid == "llm_bad" {
                    throw PipiInferenceError.httpError(500, "Server exploded")
                }
                return PipiInferenceResult(text: "Recovered", engineLabel: "GoodLLM · gpt-4o")
            }
        )

        let conv = store.createConversation(for: "bot_pipi_general")
        await store.sendPersonalMessage("Hello", conversationId: conv.id)

        let noEngineMsg = try XCTUnwrap(store.conversations.first(where: { $0.id == conv.id })?.messages.last)
        XCTAssertTrue(noEngineMsg.isError)
        XCTAssertTrue(noEngineMsg.isNoEngineGuide)
        XCTAssertFalse(noEngineMsg.content.contains("左下角"))
        XCTAssertFalse(noEngineMsg.content.lowercased().contains("bottom-left"))

        // Configure a failing provider and a healthy provider
        let bad = PipiLLMProviderConfig(id: "llm_bad", name: "Bad", kind: .openai, apiKey: "sk-1", modelId: "gpt-bad")
        let good = PipiLLMProviderConfig(id: "llm_good", name: "Good", kind: .openai, apiKey: "sk-2", modelId: "gpt-4o")
        store.upsertLLMProvider(bad, setAsDefault: true)
        store.upsertLLMProvider(good, setAsDefault: false)

        await store.sendPersonalMessage("Run task", conversationId: conv.id)
        let errConv = try XCTUnwrap(store.conversations.first(where: { $0.id == conv.id }))
        XCTAssertEqual(errConv.state, .failed)
        let errMsg = try XCTUnwrap(errConv.messages.last)
        XCTAssertTrue(errMsg.isError)
        XCTAssertFalse(errMsg.isNoEngineGuide)

        // Switch engine and retry
        await store.switchEngineAndRetry(
            conversationId: conv.id,
            errorMessageId: errMsg.id,
            target: .llm(providerId: "llm_good")
        )
        let recoveredConv = try XCTUnwrap(store.conversations.first(where: { $0.id == conv.id }))
        XCTAssertEqual(recoveredConv.messages.last?.content, "Recovered")
        XCTAssertFalse(recoveredConv.messages.last?.isError ?? true)
    }

    // MARK: - 5. Vision Attachment Base64 Encoding & Size Cap

    func testVisionImageAttachmentsAcrossProvidersAndSizeCap() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-s1-vision-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let imgUrl = dir.appendingPathComponent("sample.png")
        try writeTinyPNG(to: imgUrl)

        let att = PipiChatAttachment.fromFileURL(imgUrl)
        XCTAssertTrue(att.isImage)
        let msg = PipiChatMessage(role: .user, content: "Describe this image", attachments: [att])

        // OpenAI-compatible payload
        let openAIMsgs = PipiInferenceEngine.buildOpenAIChatMessages(systemPrompt: "sys", history: [msg])
        let openAIUser = try XCTUnwrap(openAIMsgs.last)
        let openAIParts = try XCTUnwrap(openAIUser["content"] as? [[String: Any]])
        XCTAssertTrue(openAIParts.contains { ($0["type"] as? String) == "image_url" })

        // Anthropic payload
        let anthropicMsgs = PipiInferenceEngine.buildAnthropicMessages(history: [msg])
        let antUser = try XCTUnwrap(anthropicMsgs.first)
        let antBlocks = try XCTUnwrap(antUser["content"] as? [[String: Any]])
        let imgBlock = try XCTUnwrap(antBlocks.first(where: { ($0["type"] as? String) == "image" }))
        let source = try XCTUnwrap(imgBlock["source"] as? [String: Any])
        XCTAssertEqual(source["media_type"] as? String, "image/png")
        XCTAssertFalse((source["data"] as? String ?? "").isEmpty)

        // Gemini payload
        let geminiContents = PipiInferenceEngine.buildGeminiContents(history: [msg])
        let gemUser = try XCTUnwrap(geminiContents.first)
        let gemParts = try XCTUnwrap(gemUser["parts"] as? [[String: Any]])
        let inlineBlock = try XCTUnwrap(gemParts.first(where: { $0["inline_data"] != nil }))
        let inlineData = try XCTUnwrap(inlineBlock["inline_data"] as? [String: Any])
        XCTAssertEqual(inlineData["mime_type"] as? String, "image/png")

        // Size cap enforcement on non-compressible / tiny cap
        let capped = PipiInferenceEngine.encodeImageAttachmentBase64(att, maxBytes: 10)
        XCTAssertNil(capped)
    }

    // MARK: - 6. Markdown Block Parse Cache

    func testMarkdownBlockCacheReturnsIdenticalBlocks() {
        let sample = """
        # Heading

        Some prose with **bold** and `code`.

        ```swift
        let x = 42
        ```
        """
        let first = PipiMarkdownParser.parseBlocksCached(sample)
        let second = PipiMarkdownParser.parseBlocksCached(sample)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 2)
        if case .prose(_, let text) = first[0] {
            XCTAssertTrue(text.contains("# Heading"))
        } else {
            XCTFail("Expected prose block")
        }
        if case .code(_, let lang, _) = first[1] {
            XCTAssertEqual(lang, "swift")
        } else {
            XCTFail("Expected code block")
        }
    }

    @MainActor
    func testAskPermissionTierDenialTransitionsToDoneWithoutWriteResume() async throws {
        let tracker = ExecutorRecorder()
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            secretStore: PipiInMemorySecretStore(),
            sessionInferenceExecutor: { _, _, _, history, _, tier, cliSessionId, onDelta, _ in
                tracker.record(tier: tier, cliSessionId: cliSessionId, historyCount: history.count)
                onDelta?("Read-only analysis.")
                return PipiInferenceResult(
                    text: "Read-only analysis.",
                    engineLabel: "Codex CLI",
                    cliSessionId: "codex_t1"
                )
            }
        )
        store.toggleLocalAgent(.codex, enabled: true, setAsDefaultIfFirst: true)
        let conv = store.createConversation(for: "bot_pipi_coder")
        await store.sendPersonalMessage("Inspect repo", targetOverride: .localAgent(.codex), conversationId: conv.id)

        XCTAssertEqual(tracker.calls.count, 1)
        let approval = try XCTUnwrap(store.pendingApprovals.first)
        await store.resolveApproval(approval.id, optionId: "keep_readonly")

        XCTAssertEqual(tracker.calls.count, 1) // no write resume
        let updated = try XCTUnwrap(store.conversations.first(where: { $0.id == conv.id }))
        XCTAssertEqual(updated.state, .done)
        XCTAssertEqual(updated.approvals.first?.status, .denied)
        XCTAssertTrue(store.pendingApprovals.isEmpty)
    }

    @MainActor
    func testComposerPermissionTierAndPersonaAssignmentSafety() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-s1-composer-safe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let stateUrl = dir.appendingPathComponent("resident-state.json")

        let tracker = ExecutorRecorder()
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore(),
            saveDebounceMilliseconds: 0,
            sessionInferenceExecutor: { _, _, _, history, _, tier, cliSessionId, onDelta, _ in
                tracker.record(tier: tier, cliSessionId: cliSessionId, historyCount: history.count)
                onDelta?("Applied")
                return PipiInferenceResult(
                    text: "Applied",
                    engineLabel: "Claude Code",
                    cliSessionId: cliSessionId ?? "cli_composer_1"
                )
            }
        )
        store.toggleLocalAgent(.claudeCode, enabled: true, setAsDefaultIfFirst: true)

        // 1. Rebind Bot on an empty draft conversation safely
        let emptyConv = store.createConversation(for: "bot_pipi_general", activate: true)
        XCTAssertEqual(emptyConv.personaId, "bot_pipi_general")
        store.assignActiveConversationPersona("bot_pipi_coder")
        XCTAssertEqual(store.activePersonaId, "bot_pipi_coder")
        XCTAssertEqual(store.activeConversation?.personaId, "bot_pipi_coder")

        // 2. Switch permission tier to .autoEdit via composer helper and send message:
        // must NOT trigger isApprovalResume skip, so user message MUST be appended and tier MUST be .autoEdit
        store.setEffectivePermissionTier(.autoEdit)
        XCTAssertEqual(store.effectivePermissionTier(), .autoEdit)
        XCTAssertEqual(store.activePersona.permissionTier, .autoEdit)

        await store.sendPersonalMessage("Implement feature X", conversationId: emptyConv.id)
        let afterSend = try XCTUnwrap(store.conversations.first(where: { $0.id == emptyConv.id }))
        XCTAssertEqual(afterSend.messages.filter { $0.role == .user }.count, 1)
        XCTAssertEqual(afterSend.messages.first(where: { $0.role == .user })?.content, "Implement feature X")
        XCTAssertEqual(tracker.calls.count, 1)
        XCTAssertEqual(tracker.calls[0].tier, .autoEdit)
        XCTAssertEqual(tracker.calls[0].historyCount, 1)

        // 3. Calling assignActiveConversationPersona when active conversation is NON-empty must NOT mutate past conversation's personaId
        store.assignActiveConversationPersona("bot_pipi_writer")
        XCTAssertEqual(store.activePersonaId, "bot_pipi_writer")
        XCTAssertEqual(store.conversations.first(where: { $0.id == emptyConv.id })?.personaId, "bot_pipi_coder")

        // 4. Project-scoped permission override via setEffectivePermissionTier
        let proj = PipiProject(name: "Strict Project", permissionTierOverride: .ask)
        store.upsertProject(proj)
        let projConv = store.createConversation(for: "bot_pipi_coder", projectId: proj.id, activate: true)
        XCTAssertEqual(store.effectivePermissionTier(), .ask)
        store.setEffectivePermissionTier(.readOnly)
        XCTAssertEqual(store.effectivePermissionTier(), .readOnly)
        XCTAssertEqual(store.projects.first(where: { $0.id == proj.id })?.permissionTierOverride, .readOnly)
        // Original persona tier stays .autoEdit while project override is .readOnly
        XCTAssertEqual(store.personas.first(where: { $0.id == "bot_pipi_coder" })?.permissionTier, .autoEdit)
        _ = projConv

        // 5. Default execution target persistence
        store.setDefaultExecutionTarget(.localAgent(.claudeCode))
        store.flush()
        let reloaded = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore()
        )
        XCTAssertEqual(reloaded.defaultExecutionTarget, .localAgent(.claudeCode))
        XCTAssertEqual(reloaded.personas.first(where: { $0.id == "bot_pipi_coder" })?.permissionTier, .autoEdit)
        XCTAssertEqual(reloaded.projects.first(where: { $0.id == proj.id })?.permissionTierOverride, .readOnly)
    }

    // MARK: - Helpers

    private func writeTinyPNG(to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 8 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = ctx.makeImage() else {
            throw NSError(domain: "PipiTest", code: 1)
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "PipiTest", code: 2)
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
}

private final class ExecutorRecorder: @unchecked Sendable {
    struct Call {
        let tier: PipiPermissionTier
        let cliSessionId: String?
        let historyCount: Int
    }

    private let lock = NSLock()
    private var _calls: [Call] = []

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    func record(tier: PipiPermissionTier, cliSessionId: String?, historyCount: Int) {
        lock.lock()
        _calls.append(Call(tier: tier, cliSessionId: cliSessionId, historyCount: historyCount))
        lock.unlock()
    }
}
