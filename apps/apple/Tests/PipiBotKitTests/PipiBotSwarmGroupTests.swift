import XCTest
@testable import PipiBotKit

final class PipiBotSwarmGroupTests: XCTestCase {

    private func makeTempStateUrl() throws -> (dir: URL, stateUrl: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-swarm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("resident-state.json"))
    }

    private func makeTestPersonas() -> [PipiBotPersona] {
        [
            PipiBotPersona(
                id: "bot_lead",
                nameZh: "主控皮",
                nameEn: "Lead",
                roleZh: "架构统筹",
                roleEn: "Lead Coordinator",
                greetingZh: "你好",
                greetingEn: "Hello",
                systemPrompt: "Lead coordinator",
                accent: .iris
            ),
            PipiBotPersona(
                id: "bot_coder",
                nameZh: "代码皮",
                nameEn: "Coder",
                roleZh: "全栈开发",
                roleEn: "Fullstack Engineer",
                greetingZh: "你好",
                greetingEn: "Hello",
                systemPrompt: "Coder",
                accent: .sky
            ),
            PipiBotPersona(
                id: "bot_researcher",
                nameZh: "研究皮",
                nameEn: "Researcher",
                roleZh: "深度调研",
                roleEn: "Research Analyst",
                greetingZh: "你好",
                greetingEn: "Hello",
                systemPrompt: "Researcher",
                accent: .emerald
            ),
            PipiBotPersona(
                id: "bot_reviewer",
                nameZh: "审查皮",
                nameEn: "Reviewer",
                roleZh: "代码审查",
                roleEn: "Code Reviewer",
                greetingZh: "你好",
                greetingEn: "Hello",
                systemPrompt: "Reviewer",
                accent: .amber
            ),
            PipiBotPersona(
                id: "bot_qa",
                nameZh: "测试皮",
                nameEn: "Tester",
                roleZh: "质量保障",
                roleEn: "QA Specialist",
                greetingZh: "你好",
                greetingEn: "Hello",
                systemPrompt: "QA",
                accent: .coral
            )
        ]
    }

    @MainActor
    private func makeStore(
        stateUrl: URL,
        executor: (@Sendable (PipiExecutionTarget, PipiLLMProviderConfig?, String, [PipiChatMessage], String?, (@Sendable (String) -> Void)?) async throws -> PipiInferenceResult)? = nil
    ) -> PipiAppStore {
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore(),
            inferenceExecutor: executor
        )
        store.personas = makeTestPersonas()
        store.upsertLLMProvider(
            PipiLLMProviderConfig(
                id: "llm_mock",
                name: "MockAI",
                kind: .openai,
                apiKey: "sk-mock",
                modelId: "gpt-4o"
            ),
            setAsDefault: true
        )
        return store
    }

    // MARK: - 1. Legacy State Migration & Group Persistence

    @MainActor
    func testLegacyStateDecodesWithoutGroupChatsAndRoundTrips() async throws {
        let (dir, stateUrl) = try makeTempStateUrl()
        defer { try? FileManager.default.removeItem(at: dir) }

        let legacyJson: [String: Any] = [
            "hasCompletedOnboarding": true,
            "activePersonaId": "bot_pipi_general",
            "conversations": []
        ]
        try JSONSerialization.data(withJSONObject: legacyJson).write(to: stateUrl, options: .atomic)

        let store1 = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore()
        )
        XCTAssertTrue(store1.groupChats.isEmpty)
        XCTAssertNil(store1.activeGroupChatId)

        let created = store1.createGroupChat(
            title: "Launch Squad",
            participantPersonaIds: ["bot_pipi_general", "bot_pipi_coder"],
            leadPersonaId: "bot_pipi_general",
            swarmMode: .swarm,
            activate: true
        )
        if let gIdx = store1.groupChats.firstIndex(where: { $0.id == created.id }) {
            store1.groupChats[gIdx].assignments = [
                PipiSwarmTaskAssignment(personaId: "bot_pipi_coder", taskTitle: "Build API", status: .working)
            ]
        }
        store1.flush()

        let store2 = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore()
        )
        XCTAssertEqual(store2.groupChats.count, 1)
        XCTAssertEqual(store2.activeGroupChatId, created.id)
        let loaded = try XCTUnwrap(store2.groupChats.first)
        XCTAssertEqual(loaded.title, "Launch Squad")
        XCTAssertEqual(loaded.swarmMode, .swarm)
        // Stale .working assignment from killed session must sanitize cleanly on load
        XCTAssertEqual(loaded.assignments.first?.status, .done)
    }

    // MARK: - 2. @Mention Parsing

    @MainActor
    func testParseGroupMentionsAndAll() throws {
        let (dir, stateUrl) = try makeTempStateUrl()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = makeStore(stateUrl: stateUrl)
        let participants = ["bot_lead", "bot_coder", "bot_researcher"]

        let m1 = store.parseGroupMentions(in: "@coder Please check @研究皮's notes", participantPersonaIds: participants)
        XCTAssertFalse(m1.isAll)
        XCTAssertEqual(m1.mentionedIds, ["bot_coder", "bot_researcher"])

        let m2 = store.parseGroupMentions(in: "@all Let's review the release", participantPersonaIds: participants)
        XCTAssertTrue(m2.isAll)
        XCTAssertEqual(Set(m2.mentionedIds), Set(participants))

        // Should ignore emails and partial word false positives
        let m3 = store.parseGroupMentions(in: "Email dev@coder.io and ask @allow", participantPersonaIds: participants)
        XCTAssertFalse(m3.isAll)
        XCTAssertTrue(m3.mentionedIds.isEmpty)
    }

    // MARK: - 3. Mention-Only Parallel Dispatch

    @MainActor
    func testMentionOnlyParallelDispatchAndAll() async throws {
        let (dir, stateUrl) = try makeTempStateUrl()
        defer { try? FileManager.default.removeItem(at: dir) }

        actor Recorder {
            var prompts: [String] = []
            func append(_ s: String) { prompts.append(s) }
            func all() -> [String] { prompts }
        }
        let recorder = Recorder()

        let store = makeStore(stateUrl: stateUrl) { _, _, systemPrompt, _, _, onDelta in
            await recorder.append(systemPrompt)
            onDelta?("Chunk ")
            if systemPrompt.contains("Fullstack Engineer") || systemPrompt.contains("Coder") {
                return PipiInferenceResult(text: "Coder ready", engineLabel: "MockAI")
            }
            if systemPrompt.contains("Research Analyst") || systemPrompt.contains("Researcher") {
                return PipiInferenceResult(text: "Researcher ready", engineLabel: "MockAI")
            }
            return PipiInferenceResult(text: "Lead ready", engineLabel: "MockAI")
        }

        let group = store.createGroupChat(
            title: "Mention Test",
            participantPersonaIds: ["bot_lead", "bot_coder", "bot_researcher"],
            leadPersonaId: "bot_lead",
            swarmMode: .mentionOnly
        )

        await store.sendGroupMessage("@Coder @Researcher please weigh in", toGroupId: group.id)

        let updated = try XCTUnwrap(store.groupChats.first(where: { $0.id == group.id }))
        let botSenders = updated.messages.compactMap { msg -> String? in
            if case .bot(let pid) = msg.senderKind { return pid }
            return nil
        }
        XCTAssertEqual(botSenders, ["bot_coder", "bot_researcher"])
        XCTAssertFalse(botSenders.contains("bot_lead"))

        // Now test @all
        await store.sendGroupMessage("@all summarize status", toGroupId: group.id)
        let afterAll = try XCTUnwrap(store.groupChats.first(where: { $0.id == group.id }))
        let allSenders = afterAll.messages.suffix(3).compactMap { msg -> String? in
            if case .bot(let pid) = msg.senderKind { return pid }
            return nil
        }
        XCTAssertEqual(Set(allSenders), Set(["bot_lead", "bot_coder", "bot_researcher"]))
    }

    // MARK: - 4. Sequential Relay Mode

    @MainActor
    func testRelaySequentialExecutionPassesPreviousContext() async throws {
        let (dir, stateUrl) = try makeTempStateUrl()
        defer { try? FileManager.default.removeItem(at: dir) }

        actor RelayLog {
            var order: [String] = []
            var lastPrompts: [String] = []
            func record(bot: String, prompt: String) {
                order.append(bot)
                lastPrompts.append(prompt)
            }
            func getOrder() -> [String] { order }
            func getPrompts() -> [String] { lastPrompts }
        }
        let log = RelayLog()

        let store = makeStore(stateUrl: stateUrl) { _, _, systemPrompt, history, _, onDelta in
            let lastUserMsg = history.last?.content ?? ""
            if systemPrompt.contains("Lead coordinator") {
                await log.record(bot: "bot_lead", prompt: lastUserMsg)
                onDelta?("Step1")
                return PipiInferenceResult(text: "Lead architecture draft", engineLabel: "MockAI")
            } else if systemPrompt.contains("Coder") {
                await log.record(bot: "bot_coder", prompt: lastUserMsg)
                onDelta?("Step2")
                return PipiInferenceResult(text: "Coder implementation plan", engineLabel: "MockAI")
            } else {
                await log.record(bot: "bot_reviewer", prompt: lastUserMsg)
                onDelta?("Step3")
                return PipiInferenceResult(text: "Reviewer approved", engineLabel: "MockAI")
            }
        }

        let group = store.createGroupChat(
            title: "Relay Squad",
            participantPersonaIds: ["bot_lead", "bot_coder", "bot_reviewer"],
            leadPersonaId: "bot_lead",
            swarmMode: .relay
        )

        await store.sendGroupMessage("Design user profile sync", toGroupId: group.id)

        let order = await log.getOrder()
        let prompts = await log.getPrompts()
        XCTAssertEqual(order, ["bot_lead", "bot_coder", "bot_reviewer"])
        XCTAssertEqual(prompts.count, 3)
        XCTAssertTrue(prompts[1].contains("Lead architecture draft"))
        XCTAssertTrue(prompts[2].contains("Coder implementation plan"))
    }

    // MARK: - 5. Swarm Lead Decomposition & Assignment Tracking

    @MainActor
    func testSwarmLeadDecompositionAndParallelDispatch() async throws {
        let (dir, stateUrl) = try makeTempStateUrl()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = makeStore(stateUrl: stateUrl) { _, _, systemPrompt, _, _, _ in
            if systemPrompt.contains("Lead coordinator") {
                return PipiInferenceResult(
                    text: """
                    Splitting the launch plan:
                    @Coder: Implement OAuth callback handler
                    @Researcher: Benchmark PKCE token storage
                    """,
                    engineLabel: "MockAI"
                )
            }
            if systemPrompt.contains("Coder") {
                try? await Task.sleep(for: .milliseconds(30))
                return PipiInferenceResult(text: "OAuth callback PR ready.", engineLabel: "MockAI")
            }
            if systemPrompt.contains("Researcher") {
                try? await Task.sleep(for: .milliseconds(30))
                return PipiInferenceResult(text: "Keychain benchmark complete.", engineLabel: "MockAI")
            }
            return PipiInferenceResult(text: "Done", engineLabel: "MockAI")
        }

        let group = store.createGroupChat(
            title: "Swarm Launch",
            participantPersonaIds: ["bot_lead", "bot_coder", "bot_researcher"],
            leadPersonaId: "bot_lead",
            swarmMode: .swarm
        )

        await store.sendGroupMessage("Ship OAuth login safely", toGroupId: group.id)

        let updated = try XCTUnwrap(store.groupChats.first(where: { $0.id == group.id }))
        XCTAssertEqual(updated.assignments.count, 2)
        XCTAssertTrue(updated.assignments.allSatisfy { $0.status == .done })
        XCTAssertEqual(updated.assignments.map(\.personaId), ["bot_coder", "bot_researcher"])
        XCTAssertTrue(updated.assignments[0].taskTitle.contains("OAuth callback"))
        XCTAssertTrue(updated.assignments[1].taskTitle.contains("PKCE"))
        XCTAssertFalse(store.isGroupRunning(group.id))
        XCTAssertTrue(store.collaboratingBotIds.isEmpty)
    }

    // MARK: - 6. Bounded Bot-to-Bot Handoffs (Max 2 Rounds, No Infinite Cycles)

    @MainActor
    func testSwarmBoundedHandoffPreventsCyclesAndCapsAtTwoRounds() async throws {
        let (dir, stateUrl) = try makeTempStateUrl()
        defer { try? FileManager.default.removeItem(at: dir) }

        actor CallCounter {
            var bots: [String] = []
            func add(_ b: String) { bots.append(b) }
            func all() -> [String] { bots }
        }
        let counter = CallCounter()

        let store = makeStore(stateUrl: stateUrl) { _, _, systemPrompt, _, _, _ in
            if systemPrompt.contains("Lead coordinator") {
                await counter.add("bot_lead")
                return PipiInferenceResult(
                    text: "@Coder: Start feature implementation",
                    engineLabel: "MockAI"
                )
            }
            if systemPrompt.contains("Coder") {
                await counter.add("bot_coder")
                return PipiInferenceResult(
                    text: "Implemented! @Researcher please verify security spec.",
                    engineLabel: "MockAI"
                )
            }
            if systemPrompt.contains("Researcher") {
                await counter.add("bot_researcher")
                // Try both a new bot (@Reviewer) AND an already-spoken bot (@Coder)
                return PipiInferenceResult(
                    text: "Spec looks solid. @Reviewer please review, cc @Coder",
                    engineLabel: "MockAI"
                )
            }
            if systemPrompt.contains("Code Reviewer") || systemPrompt.contains("Reviewer") {
                await counter.add("bot_reviewer")
                // Handoff round 2 tries to trigger @Tester, which exceeds max 2 handoff rounds!
                return PipiInferenceResult(
                    text: "Review passed. @Tester run final smoke suite.",
                    engineLabel: "MockAI"
                )
            }
            await counter.add("bot_qa")
            return PipiInferenceResult(text: "QA finished.", engineLabel: "MockAI")
        }

        let group = store.createGroupChat(
            title: "Bounded Handoff",
            participantPersonaIds: ["bot_lead", "bot_coder", "bot_researcher", "bot_reviewer", "bot_qa"],
            leadPersonaId: "bot_lead",
            swarmMode: .swarm
        )

        await store.sendGroupMessage("Build & review billing module", toGroupId: group.id)

        let calls = await counter.all()
        // Expected chain:
        // Lead -> Coder (initial assignment) -> Researcher (handoff round 1) -> Reviewer (handoff round 2).
        // Coder must NOT be re-invoked (cycle prevented), and QA must NOT be invoked (exceeds 2 handoff rounds).
        XCTAssertEqual(calls, ["bot_lead", "bot_coder", "bot_researcher", "bot_reviewer"])
    }

    // MARK: - 7. PiPi Default Persona Casing & Persisted Migration

    @MainActor
    func testPiPiDefaultPersonaCasingAndPersistedStateMigration() throws {
        // 1. Built-in default general assistant uses capital PiPi
        let defaultGeneral = try XCTUnwrap(PipiBotPersona.defaultPersonas.first(where: { $0.id == "bot_pipi_general" }))
        XCTAssertEqual(defaultGeneral.nameZh, "PiPi · 全能助手")
        XCTAssertEqual(defaultGeneral.nameEn, "PiPi · Assistant")
        XCTAssertTrue(defaultGeneral.greetingZh.contains("PiPi"))
        XCTAssertTrue(defaultGeneral.greetingEn.contains("PiPi"))
        XCTAssertTrue(defaultGeneral.systemPrompt.contains("PiPi"))

        // 2. Loading persisted state with legacy "Pipi · 全能助手" upgrades in-place and preserves user chats
        let (dir, stateUrl) = try makeTempStateUrl()
        defer { try? FileManager.default.removeItem(at: dir) }

        let legacyPayload: [String: Any] = [
            "hasCompletedOnboarding": true,
            "activePersonaId": "bot_pipi_general",
            "personas": [
                [
                    "id": "bot_pipi_general",
                    "nameZh": "Pipi · 全能助手",
                    "nameEn": "Pipi · Assistant",
                    "roleZh": "日常问答与规划",
                    "roleEn": "Daily assistant",
                    "greetingZh": "你好，我是 Pipi。今天有什么想法？",
                    "greetingEn": "Hi, I'm Pipi. How can I help?",
                    "systemPrompt": "You are Pipi, a personal assistant inside PipiBot.",
                    "isBuiltIn": true
                ],
                [
                    "id": "bot_custom",
                    "nameZh": "Pipi 自定义好友",
                    "nameEn": "Custom Friend",
                    "roleZh": "测试保留",
                    "roleEn": "Preserve user persona",
                    "greetingZh": "你好",
                    "greetingEn": "Hi",
                    "systemPrompt": "Custom prompt",
                    "isBuiltIn": false
                ]
            ],
            "conversations": [
                [
                    "id": "conv_user_history",
                    "personaId": "bot_pipi_general",
                    "title": "Important History",
                    "messages": [
                        ["id": "m1", "role": "user", "content": "Remember my launch plan"]
                    ]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: legacyPayload).write(to: stateUrl, options: .atomic)

        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore()
        )

        let migrated = try XCTUnwrap(store.personas.first(where: { $0.id == "bot_pipi_general" }))
        XCTAssertEqual(migrated.nameZh, "PiPi · 全能助手")
        XCTAssertEqual(migrated.nameEn, "PiPi · Assistant")
        XCTAssertEqual(migrated.greetingZh, "你好，我是 PiPi。今天有什么想法？")
        XCTAssertEqual(migrated.greetingEn, "Hi, I'm PiPi. How can I help?")
        XCTAssertTrue(migrated.systemPrompt.contains("You are PiPi"))
        XCTAssertTrue(migrated.systemPrompt.contains("PiPiBot"))

        // User-created custom personas and chat history must remain untouched
        let custom = try XCTUnwrap(store.personas.first(where: { $0.id == "bot_custom" }))
        XCTAssertEqual(custom.nameZh, "Pipi 自定义好友")
        XCTAssertEqual(store.conversations.first?.id, "conv_user_history")
        XCTAssertEqual(store.conversations.first?.messages.first?.content, "Remember my launch plan")
    }

    // MARK: - 8. Group Topics, Long Tasks, Deliverables, Skills, Shared Memory & Prompt Injection

    @MainActor
    func testGroupWorkspaceModelsLegacyDecodingCRUDAndPromptInjection() async throws {
        let (dir, stateUrl) = try makeTempStateUrl()
        defer { try? FileManager.default.removeItem(at: dir) }

        // 1. Legacy GroupChat JSON decodes cleanly with default General topic and default skills
        let legacyGroupJson = """
        {
          "id": "grp_legacy",
          "title": "Legacy Squad",
          "participantPersonaIds": ["bot_lead", "bot_coder"],
          "messages": [
            { "id": "gm_1", "senderKind": { "user": {} }, "content": "General thread question" }
          ]
        }
        """
        let decodedLegacy = try JSONDecoder().decode(PipiGroupChat.self, from: Data(legacyGroupJson.utf8))
        XCTAssertEqual(decodedLegacy.topics.count, 1)
        XCTAssertTrue(decodedLegacy.topics[0].isDefault)
        XCTAssertEqual(decodedLegacy.activeTopic.localizedTitle(.zhHans), "综合讨论")
        XCTAssertEqual(decodedLegacy.activeTopic.localizedTitle(.en), "General")
        XCTAssertEqual(decodedLegacy.activeTopicMessages.count, 1)
        XCTAssertEqual(decodedLegacy.skills.count, PipiGroupSkill.defaultSkills.count)
        XCTAssertTrue(decodedLegacy.longTasks.isEmpty)
        XCTAssertTrue(decodedLegacy.deliverables.isEmpty)
        XCTAssertTrue(decodedLegacy.sharedMemories.isEmpty)

        // 2. Full CRUD + Prompt Injection + Topic Scoping
        actor Capture {
            var systemPrompts: [String] = []
            var historyContents: [[String]] = []
            func record(system: String, history: [PipiChatMessage]) {
                systemPrompts.append(system)
                historyContents.append(history.map(\.content))
            }
            func latestSystem() -> String { systemPrompts.last ?? "" }
            func latestHistory() -> [String] { historyContents.last ?? [] }
        }
        let capture = Capture()

        let store = makeStore(stateUrl: stateUrl) { _, _, systemPrompt, history, _, _ in
            await capture.record(system: systemPrompt, history: history)
            return PipiInferenceResult(
                text: "# Weekly Release Plan\n\nAll services verified and ready.",
                engineLabel: "MockAI"
            )
        }

        let group = store.createGroupChat(
            title: "Product Launch",
            participantPersonaIds: ["bot_lead", "bot_coder"],
            leadPersonaId: "bot_lead",
            swarmMode: .mentionOnly
        )

        // Create & select a custom topic
        let sprintTopic = try XCTUnwrap(store.createGroupTopic(groupId: group.id, title: "Release Readiness"))
        store.selectGroupTopic(groupId: group.id, topicId: sprintTopic.id)

        // Toggle skills + add custom skill
        if let disabledSkill = PipiGroupSkill.defaultSkills.first(where: { !$0.isEnabled }) {
            store.toggleGroupSkill(groupId: group.id, skillId: disabledSkill.id, enabled: false)
        }
        let customSkill = try XCTUnwrap(store.addGroupSkill(groupId: group.id, name: "Zero-Downtime Rule", instruction: "Always check rollback plan before deployment."))
        let offSkill = try XCTUnwrap(store.addGroupSkill(groupId: group.id, name: "Disabled Skill", instruction: "MUST_NOT_APPEAR_IN_PROMPT"))
        store.toggleGroupSkill(groupId: group.id, skillId: offSkill.id, enabled: false)

        // Shared memories (pinned + unpinned)
        let unpinnedMem = try XCTUnwrap(store.addGroupMemory(groupId: group.id, content: "Staging runs on port 4242", source: "Ops", pinned: false))
        let pinnedMem = try XCTUnwrap(store.addGroupMemory(groupId: group.id, content: "Production freezes Friday 18:00", source: "Lead", pinned: true))

        // Long tasks (one active, one paused)
        let activeTask = try XCTUnwrap(store.addGroupLongTask(
            groupId: group.id,
            task: PipiGroupLongTask(
                title: "API Latency Watch",
                goal: "Keep p95 under 180ms before release",
                ownerPersonaId: "bot_coder",
                schedule: .daily,
                status: .active,
                topicId: sprintTopic.id
            )
        ))
        let pausedTask = try XCTUnwrap(store.addGroupLongTask(
            groupId: group.id,
            task: PipiGroupLongTask(
                title: "Paused Cleanup",
                goal: "PAUSED_TASK_SHOULD_NOT_INJECT",
                ownerPersonaId: "bot_lead",
                schedule: .weekly,
                status: .paused
            )
        ))

        // Send a message into the custom topic
        await store.sendGroupMessage("@Coder check staging status", toGroupId: group.id)

        let injectedPrompt = await capture.latestSystem()
        XCTAssertTrue(injectedPrompt.contains("#Release Readiness"))
        XCTAssertTrue(injectedPrompt.contains(customSkill.name))
        XCTAssertTrue(injectedPrompt.contains("Always check rollback plan"))
        XCTAssertFalse(injectedPrompt.contains("MUST_NOT_APPEAR_IN_PROMPT"))
        XCTAssertTrue(injectedPrompt.contains("[Pinned] Production freezes Friday 18:00"))
        XCTAssertTrue(injectedPrompt.contains("Staging runs on port 4242"))
        XCTAssertTrue(injectedPrompt.contains("API Latency Watch"))
        XCTAssertFalse(injectedPrompt.contains("PAUSED_TASK_SHOULD_NOT_INJECT"))

        // Pinned memory appears before unpinned memory in prompt
        let pinnedRange = try XCTUnwrap(injectedPrompt.range(of: "Production freezes Friday 18:00"))
        let unpinnedRange = try XCTUnwrap(injectedPrompt.range(of: "Staging runs on port 4242"))
        XCTAssertLessThan(pinnedRange.lowerBound, unpinnedRange.lowerBound)

        // Switching back to General topic isolates history cleanly
        store.selectGroupTopic(groupId: group.id, topicId: nil)
        let updatedGroupAfterMsg = try XCTUnwrap(store.groupChats.first(where: { $0.id == group.id }))
        XCTAssertTrue(updatedGroupAfterMsg.activeTopicMessages.isEmpty)

        // Switch back to sprint topic and promote bot reply to deliverable
        store.selectGroupTopic(groupId: group.id, topicId: sprintTopic.id)
        let sprintMessages = try XCTUnwrap(store.groupChats.first(where: { $0.id == group.id })?.activeTopicMessages)
        let botReply = try XCTUnwrap(sprintMessages.last(where: {
            if case .bot = $0.senderKind { return true }
            return false
        }))
        let deliverable = try XCTUnwrap(store.promoteMessageToDeliverable(groupId: group.id, messageId: botReply.id, kind: .plan))
        XCTAssertEqual(deliverable.title, "Weekly Release Plan")
        XCTAssertEqual(deliverable.topicId, sprintTopic.id)
        XCTAssertEqual(deliverable.producedByPersonaId, "bot_coder")

        // Run long task now -> executes on owner, updates lastRunAt and lastSummary
        await store.runGroupLongTaskNow(groupId: group.id, taskId: activeTask.id)
        let refreshedGroup = try XCTUnwrap(store.groupChats.first(where: { $0.id == group.id }))
        let refreshedTask = try XCTUnwrap(refreshedGroup.longTasks.first(where: { $0.id == activeTask.id }))
        XCTAssertNotNil(refreshedTask.lastRunAt)
        XCTAssertTrue(refreshedTask.lastSummary?.contains("Weekly Release Plan") == true)

        // Context estimation
        let estimate = store.estimateGroupContextUsage(for: refreshedGroup)
        XCTAssertGreaterThan(estimate.estimatedTokens, 50)
        XCTAssertEqual(estimate.messageCount, refreshedGroup.activeTopicMessages.count)
        XCTAssertEqual(estimate.attachmentCount, 1)

        // Toggle, pin & delete CRUD operations + flush reload check
        store.togglePinGroupMemory(groupId: group.id, memoryId: unpinnedMem.id)
        store.deleteGroupMemory(groupId: group.id, memoryId: pinnedMem.id)
        store.toggleGroupLongTask(groupId: group.id, taskId: pausedTask.id, status: .completed)
        store.deleteGroupLongTask(groupId: group.id, taskId: pausedTask.id)
        store.deleteGroupSkill(groupId: group.id, skillId: offSkill.id)
        store.deleteGroupDeliverable(groupId: group.id, deliverableId: deliverable.id)
        store.flush()

        let reloadedStore = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateUrl,
            secretStore: PipiInMemorySecretStore()
        )
        let reloadedGroup = try XCTUnwrap(reloadedStore.groupChats.first(where: { $0.id == group.id }))
        XCTAssertEqual(reloadedGroup.topics.count, 2)
        XCTAssertEqual(reloadedGroup.longTasks.count, 1)
        XCTAssertEqual(reloadedGroup.deliverables.count, 0)
        XCTAssertEqual(reloadedGroup.sharedMemories.count, 1)
        XCTAssertTrue(reloadedGroup.sharedMemories[0].isPinned)

        // Delete non-default topic resets active topic to default General
        reloadedStore.deleteGroupTopic(groupId: group.id, topicId: sprintTopic.id)
        let afterTopicDelete = try XCTUnwrap(reloadedStore.groupChats.first(where: { $0.id == group.id }))
        XCTAssertEqual(afterTopicDelete.topics.count, 1)
        XCTAssertTrue(afterTopicDelete.activeTopic.isDefault)
    }
}
