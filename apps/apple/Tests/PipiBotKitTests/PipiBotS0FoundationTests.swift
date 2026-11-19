import XCTest
@testable import PipiBotKit

final class PipiBotS0FoundationTests: XCTestCase {

    // MARK: - 1. Keychain / SecretStore & Plaintext Migration

    @MainActor
    func testSecretStoreMigrationAndZeroApiKeyInResidentStateJSON() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-s0-keychain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let stateUrl = dir.appendingPathComponent("resident-state.json")

        // Write legacy JSON containing a plaintext apiKey
        let legacyJson: [String: Any] = [
            "updatedAt": "2026-11-19T00:00:00Z",
            "hasCompletedOnboarding": true,
            "llmProviders": [
                [
                    "id": "llm_legacy_1",
                    "name": "OpenAI",
                    "kind": "openai",
                    "baseURL": "https://api.openai.com/v1",
                    "apiKey": "sk-legacy-plaintext-999",
                    "modelId": "gpt-4o",
                    "isEnabled": true,
                    "temperature": 0.7
                ]
            ],
            "defaultLLMProviderId": "llm_legacy_1"
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJson, options: [.prettyPrinted])
        try legacyData.write(to: stateUrl, options: .atomic)

        let secrets = PipiInMemorySecretStore()
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: secrets
        )

        // Plaintext key migrated into secret store and hydrated in memory
        XCTAssertEqual(secrets.secret(for: "llm_legacy_1"), "sk-legacy-plaintext-999")
        XCTAssertEqual(store.llmProviders.first?.apiKey, "sk-legacy-plaintext-999")
        XCTAssertTrue(store.llmProviders.first?.isReady ?? false)

        // Re-saved JSON must NOT contain the plaintext apiKey anywhere on disk
        let migratedText = try String(contentsOf: stateUrl, encoding: .utf8)
        XCTAssertFalse(migratedText.contains("sk-legacy-plaintext-999"))
        XCTAssertFalse(migratedText.contains("\"apiKey\""))

        // Reloading from disk with the same secretStore hydrates apiKey back cleanly
        let reloaded = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: secrets
        )
        XCTAssertEqual(reloaded.llmProviders.first?.apiKey, "sk-legacy-plaintext-999")

        // Adding a new provider writes secret to secretStore and never to JSON
        let second = PipiLLMProviderConfig(
            id: "llm_anthropic_2",
            name: "Anthropic",
            kind: .anthropic,
            apiKey: "sk-ant-secret-42",
            modelId: "claude-sonnet-4-20250514"
        )
        reloaded.upsertLLMProvider(second, setAsDefault: false)
        reloaded.flush()

        XCTAssertEqual(secrets.secret(for: "llm_anthropic_2"), "sk-ant-secret-42")
        let updatedText = try String(contentsOf: stateUrl, encoding: .utf8)
        XCTAssertFalse(updatedText.contains("sk-ant-secret-42"))
        XCTAssertFalse(updatedText.contains("\"apiKey\""))

        // Deleting provider removes secret from secretStore
        reloaded.deleteLLMProvider(id: "llm_anthropic_2")
        XCTAssertNil(secrets.secret(for: "llm_anthropic_2"))
    }

    // MARK: - 2. Safe Persistence (Corrupt Backup, Lenient Decoding, Debounce & Flush)

    @MainActor
    func testCorruptStateCreatesBackupNoticeAndNeverOverwritesOriginal() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-s0-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let stateUrl = dir.appendingPathComponent("resident-state.json")
        let corruptPayload = "{ definitely not valid json !!!"
        try corruptPayload.write(to: stateUrl, atomically: true, encoding: .utf8)

        let secrets = PipiInMemorySecretStore()
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: secrets
        )

        XCTAssertTrue(store.corruptStateDetected)
        XCTAssertNotNil(store.persistenceWarning)
        XCTAssertEqual(store.noticeBanner, store.persistenceWarning)
        let backupUrl = try XCTUnwrap(store.corruptStateBackupUrl)
        XCTAssertTrue(backupUrl.lastPathComponent.hasPrefix("resident-state.corrupt-"))
        XCTAssertTrue(backupUrl.lastPathComponent.hasSuffix(".json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupUrl.path))
        XCTAssertEqual(try String(contentsOf: backupUrl, encoding: .utf8), corruptPayload)

        // Even if theme toggles or flush() / stopLiveSync() runs, the original corrupt file is NOT overwritten with empty state
        store.setThemeMode(.dark)
        store.flush()
        store.stopLiveSync()
        XCTAssertEqual(try String(contentsOf: stateUrl, encoding: .utf8), corruptPayload)
    }

    @MainActor
    func testLenientDecodingWithMissingOptionalAndNewFields() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-s0-lenient-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let stateUrl = dir.appendingPathComponent("resident-state.json")
        // Minimal JSON missing top-level outcomes/decisions/museCards/activeHarness and missing weekday on routine
        let minimalJson: [String: Any] = [
            "hasCompletedOnboarding": true,
            "routines": [
                [
                    "id": "rt_old",
                    "personaId": "bot_pipi_general",
                    "title": "Legacy Weekly",
                    "prompt": "Check inbox",
                    "schedule": "weekly",
                    "hour": 8,
                    "minute": 15
                ]
            ],
            "conversations": [
                [
                    "id": "conv_old",
                    "personaId": "bot_pipi_general",
                    "title": "Old Thread",
                    "messages": [
                        [
                            "id": "msg_1",
                            "role": "user",
                            "content": "Hi there"
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: minimalJson)
        try data.write(to: stateUrl, options: .atomic)

        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore()
        )
        XCTAssertFalse(store.corruptStateDetected)
        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertEqual(store.routines.count, 1)
        XCTAssertEqual(store.routines.first?.weekday, 2) // default Monday
        XCTAssertEqual(store.conversations.first?.isArchived, false)
        XCTAssertEqual(store.conversations.first?.messages.first?.content, "Hi there")
    }

    @MainActor
    func testDebouncedPersistenceCoalescesWritesAndFlushIsSynchronous() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-s0-debounce-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let stateUrl = dir.appendingPathComponent("resident-state.json")
        let secrets = PipiInMemorySecretStore()
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: secrets,
            saveDebounceMilliseconds: 250
        )

        // Rapid keystroke-like edits must NOT write synchronously on the calling turn
        store.setPersonalProfileNote("A")
        store.setPersonalProfileNote("AB")
        store.setPersonalProfileNote("ABC final")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateUrl.path))

        // After debounce window, background serial queue writes latest value
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateUrl.path))
        let reloadedAfterDebounce = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: secrets
        )
        XCTAssertEqual(reloadedAfterDebounce.personalProfileNote, "ABC final")

        // Synchronous flush writes immediately without waiting
        store.setPersonalProfileNote("Flushed immediately")
        store.flush()
        let reloadedAfterFlush = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: secrets
        )
        XCTAssertEqual(reloadedAfterFlush.personalProfileNote, "Flushed immediately")
    }

    // MARK: - 3. Per-Session Run State & Host Concurrency Cap

    @MainActor
    func testPerConversationRunStateConcurrentStreamingAndTargetedStop() async throws {
        let secrets = PipiInMemorySecretStore()
        let provider = PipiLLMProviderConfig(
            id: "llm_mock",
            name: "Mock",
            kind: .openai,
            apiKey: "sk-mock",
            modelId: "gpt-4o"
        )

        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            secretStore: secrets,
            inferenceExecutor: { _, _, _, history, _, onDelta in
                let userPrompt = history.last?.content ?? ""
                onDelta?("chunk1:")
                try await Task.sleep(for: .milliseconds(180))
                onDelta?(userPrompt)
                try await Task.sleep(for: .milliseconds(180))
                return PipiInferenceResult(text: "done:\(userPrompt)", engineLabel: "Mock · gpt-4o")
            }
        )
        store.upsertLLMProvider(provider, setAsDefault: true)

        let convX = store.createConversation(for: "bot_pipi_general")
        let convY = store.createConversation(for: "bot_pipi_coder")

        // Start convX in background, then switch to convY and start convY
        store.selectConversation(convX.id)
        let taskX = Task { await store.sendPersonalMessage("Alpha") }
        try await Task.sleep(for: .milliseconds(40))

        store.selectConversation(convY.id)
        XCTAssertFalse(store.isGeneratingReply) // active is convY, which is not running yet
        XCTAssertTrue(store.isRunning(conversationId: convX.id))

        let taskY = Task { await store.sendPersonalMessage("Beta") }
        try await Task.sleep(for: .milliseconds(60))

        // Both X and Y are running simultaneously; neither cancelled the other
        XCTAssertTrue(store.isRunning(conversationId: convX.id))
        XCTAssertTrue(store.isRunning(conversationId: convY.id))
        XCTAssertTrue(store.isGeneratingReply) // convY is active and running

        // Stop ONLY convX; convY must continue and finish cleanly
        store.stopGenerating(conversationId: convX.id)
        XCTAssertFalse(store.isRunning(conversationId: convX.id))
        XCTAssertTrue(store.isRunning(conversationId: convY.id))

        await taskX.value
        await taskY.value

        XCTAssertFalse(store.isRunning(conversationId: convY.id))
        let updatedY = try XCTUnwrap(store.conversations.first(where: { $0.id == convY.id }))
        XCTAssertEqual(updatedY.messages.last?.content, "done:Beta")
    }

    @MainActor
    func testHostConcurrencyCapsQueueAndDrainForLLMAndLocalAgents() async throws {
        let tracker = ConcurrencyPeakTracker()
        let provider = PipiLLMProviderConfig(
            id: "llm_cap",
            name: "CapLLM",
            kind: .openai,
            apiKey: "sk-cap",
            modelId: "gpt-4o"
        )

        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            secretStore: PipiInMemorySecretStore(),
            inferenceExecutor: { target, _, _, history, _, _ in
                let bucket: String
                switch target {
                case .localAgent: bucket = "cli"
                case .llm, .auto: bucket = "llm"
                }
                tracker.enter(bucket)
                defer { tracker.exit(bucket) }
                try await Task.sleep(for: .milliseconds(160))
                return PipiInferenceResult(text: "ok:\(history.last?.content ?? "")", engineLabel: bucket)
            }
        )
        store.upsertLLMProvider(provider, setAsDefault: true)

        // 1. Launch 6 LLM conversations -> cap is 4, 2 should enter .queued state
        var llmConvs: [PipiConversation] = []
        var llmTasks: [Task<Void, Never>] = []
        for i in 0..<6 {
            let conv = store.createConversation(for: "bot_pipi_general", activate: false)
            llmConvs.append(conv)
            llmTasks.append(Task {
                await store.sendPersonalMessage("LLM-\(i)", conversationId: conv.id, activateTargetConversation: false)
            })
        }

        try await Task.sleep(for: .milliseconds(50))
        let queuedLLMCount = llmConvs.filter { store.isQueued(conversationId: $0.id) }.count
        let runningLLMCount = llmConvs.filter { store.runPhase(for: $0.id) == .running }.count
        XCTAssertEqual(runningLLMCount, PipiAppStore.maxConcurrentLLMRuns)
        XCTAssertEqual(queuedLLMCount, 2)

        for t in llmTasks { await t.value }
        XCTAssertEqual(tracker.peak("llm"), 4)
        for conv in llmConvs {
            XCTAssertFalse(store.isRunning(conversationId: conv.id))
            XCTAssertEqual(store.conversations.first(where: { $0.id == conv.id })?.messages.last?.content.hasPrefix("ok:LLM-"), true)
        }

        // 2. Launch 4 local agent conversations -> cap is 2, 2 should enter .queued state
        var cliConvs: [PipiConversation] = []
        var cliTasks: [Task<Void, Never>] = []
        for i in 0..<4 {
            let conv = store.createConversation(for: "bot_pipi_coder", activate: false)
            cliConvs.append(conv)
            cliTasks.append(Task {
                await store.sendPersonalMessage(
                    "CLI-\(i)",
                    targetOverride: .localAgent(.claudeCode),
                    conversationId: conv.id,
                    activateTargetConversation: false
                )
            })
        }

        try await Task.sleep(for: .milliseconds(50))
        let queuedCLICount = cliConvs.filter { store.isQueued(conversationId: $0.id) }.count
        let runningCLICount = cliConvs.filter { store.runPhase(for: $0.id) == .running }.count
        XCTAssertEqual(runningCLICount, PipiAppStore.maxConcurrentLocalAgentRuns)
        XCTAssertEqual(queuedCLICount, 2)

        for t in cliTasks { await t.value }
        XCTAssertEqual(tracker.peak("cli"), 2)
    }

    // MARK: - 4. Routines (Background Execution, Minute/Weekday Scheduling, No Skip)

    @MainActor
    func testRoutinesDoNotStealFocusAndRunWhileAnotherSessionIsActive() async throws {
        let provider = PipiLLMProviderConfig(
            id: "llm_rt",
            name: "RoutineLLM",
            kind: .openai,
            apiKey: "sk-rt",
            modelId: "gpt-4o"
        )
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            secretStore: PipiInMemorySecretStore(),
            inferenceExecutor: { _, _, _, history, _, _ in
                try await Task.sleep(for: .milliseconds(120))
                return PipiInferenceResult(text: "routine-ok:\(history.last?.content ?? "")", engineLabel: "RoutineLLM")
            }
        )
        store.upsertLLMProvider(provider, setAsDefault: true)

        let userConv = store.createConversation(for: "bot_pipi_general")
        store.selectConversation(userConv.id)
        let originalPersonaId = store.activePersonaId
        let originalConvId = store.activeConversationId

        // Start a user session in foreground
        let userTask = Task { await store.sendPersonalMessage("Foreground chat") }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(store.isRunning(conversationId: userConv.id))

        // Weekly routine for a DIFFERENT persona (Friday = 6, 14:35)
        let routine = PipiBotRoutine(
            personaId: "bot_pipi_coder",
            title: "Friday Audit",
            prompt: "Run weekly audit",
            schedule: .weekly,
            hour: 14,
            minute: 35,
            weekday: 6
        )
        store.addRoutine(routine)
        XCTAssertTrue(routine.scheduleBadge(.en).contains("Fri 14:35"))

        // Build a Date matching Friday 14:35 local time
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 11
        comps.day = 20 // Nov 20, 2026 is a Friday (weekday 6)
        comps.hour = 14
        comps.minute = 35
        let fridayAt1435 = try XCTUnwrap(Calendar.current.date(from: comps))

        // Must NOT skip even though userConv is currently running!
        await store.checkDueRoutines(now: fridayAt1435)
        try await Task.sleep(for: .milliseconds(220))
        await userTask.value

        // Active persona & active conversation must NEVER be stolen
        XCTAssertEqual(store.activePersonaId, originalPersonaId)
        XCTAssertEqual(store.activeConversationId, originalConvId)

        // A new background conversation for bot_pipi_coder was created and completed
        let routineConv = store.conversations.first(where: { $0.id != userConv.id && $0.personaId == "bot_pipi_coder" })
        XCTAssertNotNil(routineConv)
        XCTAssertEqual(routineConv?.messages.last?.content, "routine-ok:Run weekly audit")
    }

    // MARK: - 5. UTF-8-Safe Subprocess Streaming

    func testUTF8StreamDecoderPreservesMultibyteChineseAndEmojiAcrossArbitrarySplits() {
        let sample = "你好世界🚀🎉PipiBot中文流式输出测试！"
        let bytes = Array(sample.utf8)

        // Feed 1 byte at a time (worst-case split across every multibyte boundary)
        var decoder = PipiInferenceEngine.PipiUTF8StreamDecoder()
        var reconstructed = ""
        for b in bytes {
            reconstructed += decoder.append(Data([b]))
        }
        reconstructed += decoder.finish()
        XCTAssertEqual(reconstructed, sample)

        // Feed 2 bytes at a time
        var decoder2 = PipiInferenceEngine.PipiUTF8StreamDecoder()
        var reconstructed2 = ""
        var i = 0
        while i < bytes.count {
            let end = min(bytes.count, i + 2)
            reconstructed2 += decoder2.append(Data(bytes[i..<end]))
            i = end
        }
        reconstructed2 += decoder2.finish()
        XCTAssertEqual(reconstructed2, sample)
    }

    func testSubprocessStreamingHandlesSplitMultibyteUTF8PipeChunks() async throws {
        // Emit first 2 bytes of "你" (E4 BD), pause so pipe delivers chunk 1, then emit remaining byte (A0) + "好🚀"
        let script = #"printf '\344\275'; sleep 0.08; printf '\240\345\245\275\360\237\232\200'"#
        let deltaCollector = LockedDeltaCollector()

        let output = try await PipiInferenceEngine.runSubprocessStreaming(
            executablePath: "/bin/sh",
            arguments: ["-c", script],
            workingDirectory: FileManager.default.temporaryDirectory.path,
            onDelta: { chunk in
                deltaCollector.append(chunk)
            }
        )

        XCTAssertEqual(output, "你好🚀")
        XCTAssertEqual(deltaCollector.joined(), "你好🚀")
    }

    // MARK: - 6. Destructive Actions & Store-Level Undo

    @MainActor
    func testUndoableConversationAndProjectDeletionAndPersonaConversationCount() {
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            secretStore: PipiInMemorySecretStore()
        )

        let project = PipiProject(name: "Release S0")
        store.upsertProject(project)
        let conv1 = store.createConversation(for: "bot_pipi_general", projectId: project.id, title: "Thread One")
        let conv2 = store.createConversation(for: "bot_pipi_coder", projectId: project.id, title: "Thread Two")
        store.selectConversation(conv1.id)

        XCTAssertEqual(store.conversationCount(forPersona: "bot_pipi_general"), 1)
        XCTAssertEqual(store.conversationCount(forPersona: "bot_pipi_coder"), 1)

        // 1. Delete active conversation -> immediate removal + undo toast -> undo restores it & active selection
        store.deleteConversation(conv1.id)
        XCTAssertNil(store.conversations.first(where: { $0.id == conv1.id }))
        XCTAssertTrue(store.showUndoToast)
        XCTAssertTrue(store.canUndoLastDeletion)

        XCTAssertTrue(store.undoLastDeletion())
        XCTAssertFalse(store.showUndoToast)
        XCTAssertFalse(store.canUndoLastDeletion)
        XCTAssertEqual(store.activeConversationId, conv1.id)
        XCTAssertEqual(store.conversations.first(where: { $0.id == conv1.id })?.title, "Thread One")

        // 2. Delete project -> unlinks conversations -> undo restores project and conversation links
        store.deleteProject(project.id)
        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertNil(store.conversations.first(where: { $0.id == conv1.id })?.projectId)
        XCTAssertNil(store.conversations.first(where: { $0.id == conv2.id })?.projectId)
        XCTAssertTrue(store.showUndoToast)

        XCTAssertTrue(store.undoLastDeletion())
        XCTAssertEqual(store.projects.count, 1)
        XCTAssertEqual(store.conversations.first(where: { $0.id == conv1.id })?.projectId, project.id)
        XCTAssertEqual(store.conversations.first(where: { $0.id == conv2.id })?.projectId, project.id)
    }
}

private final class ConcurrencyPeakTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var current: [String: Int] = [:]
    private var maxSeen: [String: Int] = [:]

    func enter(_ bucket: String) {
        lock.lock()
        let next = (current[bucket] ?? 0) + 1
        current[bucket] = next
        if next > (maxSeen[bucket] ?? 0) {
            maxSeen[bucket] = next
        }
        lock.unlock()
    }

    func exit(_ bucket: String) {
        lock.lock()
        current[bucket] = max(0, (current[bucket] ?? 0) - 1)
        lock.unlock()
    }

    func peak(_ bucket: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return maxSeen[bucket] ?? 0
    }
}

private final class LockedDeltaCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [String] = []

    func append(_ chunk: String) {
        lock.lock()
        chunks.append(chunk)
        lock.unlock()
    }

    func joined() -> String {
        lock.lock()
        defer { lock.unlock() }
        return chunks.joined()
    }
}
