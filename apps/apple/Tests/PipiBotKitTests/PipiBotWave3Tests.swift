import Foundation
import XCTest
@testable import PipiBotKit

@MainActor
final class PipiBotWave3Tests: XCTestCase {

    private func makeTempDir(_ prefix: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - #05 Meta / AlterEgo Autonomous Delegation, Isolated Playground & Steer/Cancel/Resume

    func testAlterEgoAutonomousDirectiveSameSessionReadOnlySharingAndCancelResume() async throws {
        let dir = try makeTempDir("pipibot-w3-alterego")
        defer { try? FileManager.default.removeItem(at: dir) }

        let stateUrl = dir.appendingPathComponent("resident-state.json")
        let executor: PipiSessionInferenceExecutor = { _, _, _, _, _, _, _, _, _ in
            PipiInferenceResult(
                text: "我先继续和你讨论，同时派分身后台整理调研报告：\n<pipibot_delegate>{\"title\":\"SQLite WAL 对比\",\"goal\":\"Compare WAL vs rollback journal\"}</pipibot_delegate>",
                engineLabel: "Mock Meta LLM"
            )
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
        let conv = store.createConversation(for: store.activePersona.id, title: "Meta Chat", activate: true)

        // 1. Meta reply with <pipibot_delegate> autonomously spawns an AlterEgo background task!
        await store.sendPersonalMessage("请帮我做一次 SQLite WAL 深度调研", conversationId: conv.id)
        let autoTasks = store.alterEgoTasks(forSession: conv.id)
        XCTAssertEqual(autoTasks.count, 1)
        let autoTask = try XCTUnwrap(autoTasks.first)
        XCTAssertEqual(autoTask.title, "SQLite WAL 对比")
        _ = await store.alterEgoCoordinator.waitForTask(id: autoTask.id)
        XCTAssertEqual(store.alterEgoCoordinator.task(id: autoTask.id)?.status, .completed)

        // 2. Sibling task in SAME session can read autoTask's playground read-only, rejects path traversal
        let sibling = store.spawnAlterEgoTask(
            sessionId: conv.id,
            title: "Sibling Reader",
            goal: "Read sibling artifact",
            runner: { ctx in
                let content = try await ctx.readSessionArtifact(autoTask.id, "result.md")
                XCTAssertTrue(content.contains("SQLite WAL"))
                do {
                    _ = try await ctx.writeArtifact("../escape.txt", "blocked")
                    XCTFail("Path traversal must throw")
                } catch PipiAlterEgoError.pathTraversalDenied {
                    // expected
                }
                _ = try await ctx.writeArtifact("sibling.md", "Read OK: \(content.prefix(32))")
                return "Sibling done"
            }
        )
        let finishedSibling = await store.alterEgoCoordinator.waitForTask(id: sibling.id)
        XCTAssertEqual(finishedSibling?.status, .completed)
        XCTAssertTrue(finishedSibling?.artifacts.contains("sibling.md") ?? false)

        // 3. Task in DIFFERENT session is strictly denied cross-session reads
        let otherConv = store.createConversation(for: store.activePersona.id, title: "Other Session", activate: false)
        let crossTask = store.spawnAlterEgoTask(
            sessionId: otherConv.id,
            title: "Cross Session Probe",
            goal: "Must fail cross-session read",
            runner: { ctx in
                do {
                    _ = try await ctx.readSessionArtifact(autoTask.id, "result.md")
                    XCTFail("Cross-session read must fail")
                } catch PipiAlterEgoError.crossSessionDenied {
                    // expected
                }
                return "Isolation verified"
            }
        )
        let finishedCross = await store.alterEgoCoordinator.waitForTask(id: crossTask.id)
        XCTAssertEqual(finishedCross?.status, .completed)

        // 4. Cancel mid-flight, steer, and resume preserving playground!
        let cancellable = store.spawnAlterEgoTask(
            sessionId: conv.id,
            title: "Cancellable Task",
            goal: "Long task",
            runner: { ctx in
                _ = try await ctx.writeArtifact("checkpoint.txt", "saved_before_cancel")
                try await Task.sleep(for: .seconds(5))
                return "Should cancel"
            }
        )
        try await Task.sleep(for: .milliseconds(40))
        store.cancelAlterEgoTask(id: cancellable.id)
        let cancelledSnap = await store.alterEgoCoordinator.waitForTask(id: cancellable.id)
        XCTAssertEqual(cancelledSnap?.status, .cancelled)

        _ = store.resumeAlterEgoTask(
            id: cancellable.id,
            additionalInstruction: "Add Swift 6 notes",
            runner: { ctx in
                let steers = await ctx.consumeSteerInstructions()
                let prev = try await ctx.readSessionArtifact(cancellable.id, "checkpoint.txt")
                _ = try await ctx.writeArtifact("final.md", "\(prev) | \(steers.joined(separator: ","))")
                return "Resumed OK"
            }
        )
        let resumedSnap = await store.alterEgoCoordinator.waitForTask(id: cancellable.id)
        XCTAssertEqual(resumedSnap?.status, .completed)
        XCTAssertTrue(resumedSnap?.artifacts.contains("final.md") ?? false)
        XCTAssertTrue(resumedSnap?.steerInstructions.contains("Add Swift 6 notes") ?? false)
    }

    // MARK: - #06 `team.md` All 5 Topologies, DAG Cycle Rejection & Dynamic Bot Invite/Create Approval

    func testTeamMdAllFivePatternsDagValidationAndDynamicBotApprovalInStore() async throws {
        let dir = try makeTempDir("pipibot-w3-team")
        defer { try? FileManager.default.removeItem(at: dir) }

        // 1. Cycle detection on fan-out-and-synthesize MUST fail
        let cyclic = """
        ---
        collaborate_pattern: fan-out-and-synthesize
        ---

        # Task Goal
        Ship safely

        # Orchestrator
        ## Lead
        - Actor ID: bot_lead
        - Role: Coordinator
        - Report to: none
        - Receive from: Alice, Bob

        # Team Members
        ## Alice
        - Actor ID: bot_alice
        - Role: Coder
        - Receive from: Bob
        - Report to: Lead

        ## Bob
        - Actor ID: bot_bob
        - Role: Reviewer
        - Receive from: Alice
        - Report to: Lead
        """
        let cyclicRes = PipiTeamProtocol.parseAndValidate(cyclic, roomMemberActorIds: ["bot_lead", "bot_alice", "bot_bob"])
        XCTAssertFalse(cyclicRes.valid)
        XCTAssertTrue(cyclicRes.issues.contains(where: { $0.code == "team_md_cycle_detected" }))

        // 2. All 5 topologies deterministic execution
        let orch = PipiTeamParticipant(name: "Lead", actorId: "bot_lead", role: "Lead")
        let m1 = PipiTeamParticipant(name: "Coder", actorId: "bot_coder", role: "Coder")
        let m2 = PipiTeamParticipant(name: "Critic", actorId: "bot_critic", role: "Critic")

        // (a) classify-and-act
        let rClassify = try await PipiTeamProtocol.execute(
            document: PipiTeamMdDocument(pattern: .classifyAndAct, taskGoal: "Route", orchestrator: orch, members: [m1, m2]),
            userPrompt: "Fix bug",
            executor: { req in
                req.phase == .classify
                    ? PipiTeamBotTurnResponse(output: "Send to Coder", selectedActorId: "bot_coder")
                    : PipiTeamBotTurnResponse(output: "Fixed by \(req.actorId)")
            }
        )
        XCTAssertEqual(rClassify.winnerActorId, "bot_coder")
        XCTAssertEqual(rClassify.finalOutput, "Fixed by bot_coder")

        // (b) fan-out-and-synthesize
        let rFanOut = try await PipiTeamProtocol.execute(
            document: PipiTeamMdDocument(pattern: .fanOutAndSynthesize, taskGoal: "Synthesize", orchestrator: orch, members: [m1, m2]),
            userPrompt: "Compare approaches",
            executor: { req in
                PipiTeamBotTurnResponse(output: req.phase == .synthesize ? "Merged \(req.upstreamOutputs.count)" : "Work \(req.actorId)")
            }
        )
        XCTAssertEqual(rFanOut.finalOutput, "Merged 2")

        // (c) adversarial-verification (reject round 1 -> approve round 2)
        let rAdv = try await PipiTeamProtocol.execute(
            document: PipiTeamMdDocument(pattern: .adversarialVerification, maxRounds: 3, taskGoal: "Verify", orchestrator: orch, members: [m1, m2]),
            userPrompt: "Write parser",
            executor: { req in
                if req.phase == .verify {
                    return req.round == 1
                        ? PipiTeamBotTurnResponse(output: "Need boundary checks", approved: false)
                        : PipiTeamBotTurnResponse(output: "Approved", approved: true)
                }
                return PipiTeamBotTurnResponse(output: "Draft v\(req.round)")
            }
        )
        XCTAssertEqual(rAdv.roundsExecuted, 2)
        XCTAssertEqual(rAdv.verifiedApproved, true)
        XCTAssertEqual(rAdv.finalOutput, "Draft v2")

        // (d) tournament
        let rTour = try await PipiTeamProtocol.execute(
            document: PipiTeamMdDocument(pattern: .tournament, taskGoal: "Best design", orchestrator: orch, members: [m1, m2]),
            userPrompt: "Design cache",
            executor: { req in
                req.phase == .judge
                    ? PipiTeamBotTurnResponse(output: "Critic wins", selectedActorId: "bot_critic")
                    : PipiTeamBotTurnResponse(output: "Entry \(req.actorId)")
            }
        )
        XCTAssertEqual(rTour.winnerActorId, "bot_critic")

        // (e) loop-until-done
        let rLoop = try await PipiTeamProtocol.execute(
            document: PipiTeamMdDocument(pattern: .loopUntilDone, maxRounds: 4, taskGoal: "Green tests", orchestrator: orch, members: [m1]),
            userPrompt: "Iterate tests",
            executor: { req in
                PipiTeamBotTurnResponse(output: "Pass \(req.round)", done: req.round >= 3)
            }
        )
        XCTAssertEqual(rLoop.roundsExecuted, 3)
        XCTAssertTrue(rLoop.completed)

        // 3. End-to-end Store Dynamic Bot Invite + Create Proposal approval & protocol run
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            stateFileUrl: dir.appendingPathComponent("resident-state.json"),
            secretStore: PipiInMemorySecretStore(),
            saveDebounceMilliseconds: 0
        )
        let leadId = store.personas[0].id
        let existingOtherId = store.personas[1].id
        let group = store.createGroupChat(title: "Release War Room", participantPersonaIds: [leadId], swarmMode: .swarm)

        let protocolMd = PipiTeamProtocol.renderTemplate(
            pattern: .fanOutAndSynthesize,
            taskGoal: "Ship release with security signoff",
            orchestrator: PipiTeamParticipant(name: store.personas[0].nameEn, actorId: leadId, role: "Lead"),
            members: [
                PipiTeamParticipant(name: store.personas[1].nameEn, actorId: existingOtherId, role: "Coder"),
                PipiTeamParticipant(name: "Security Auditor", actorId: "bot_sec_auditor", role: "Security Audit"),
            ]
        )

        let valBefore = store.updateGroupTeamProtocol(groupId: group.id, markdown: protocolMd)
        XCTAssertEqual(valBefore?.valid, false)
        XCTAssertEqual(store.pendingDynamicBotProposals.count, 2, "Must generate 1 invite_existing + 1 create_and_invite proposal")
        XCTAssertEqual(store.totalNeedsYouCount, 2)

        for prop in store.pendingDynamicBotProposals {
            let joined = store.resolveDynamicBotProposal(groupId: group.id, proposalId: prop.id, approve: true)
            XCTAssertNotNil(joined)
        }
        XCTAssertTrue(store.pendingDynamicBotProposals.isEmpty)
        XCTAssertTrue(store.personas.contains(where: { $0.id == "bot_sec_auditor" }), "New role Bot must be created dynamically")

        let valAfter = store.validateGroupTeamProtocol(groupId: group.id)
        XCTAssertEqual(valAfter?.valid, true)

        let execResult = try await store.runGroupTeamProtocol(groupId: group.id, userPrompt: "Run release audit")
        XCTAssertEqual(execResult?.completed, true)
        let updatedGroup = store.groupChats.first(where: { $0.id == group.id })
        XCTAssertFalse(updatedGroup?.deliverables.isEmpty ?? true)
    }

    // MARK: - #11 Builtin Versioned Skills (0444 + SHA-256), Pocket Notes (5m Silence) & Editable Docs

    func testBuiltinSkillsReadOnlyProjectionPocketNotesFiveMinSilenceAndEditableDocsSync() throws {
        let dir = try makeTempDir("pipibot-w3-skills-notes")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            stateFileUrl: dir.appendingPathComponent("resident-state.json"),
            secretStore: PipiInMemorySecretStore(),
            saveDebounceMilliseconds: 0
        )

        // 1. Builtin Skills SHA-256 read-only (0444) projection + tamper detection + auto-repair
        let receipts = store.projectBuiltinSkillsNow()
        XCTAssertEqual(receipts.count, 8)
        XCTAssertTrue(store.verifyBuiltinSkillsNow().valid)

        let firstFile = try XCTUnwrap(receipts.first?.filePath)
        let attrs = try FileManager.default.attributesOfItem(atPath: firstFile)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(perms & 0o777, 0o444, "Projected builtin skill must be 0444 read-only")

        // Tamper file -> verify catches mismatch -> re-project repairs cleanly
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: firstFile)
        try Data("TAMPERED".utf8).write(to: URL(fileURLWithPath: firstFile))
        XCTAssertFalse(store.verifyBuiltinSkillsNow().valid)
        let repaired = store.projectBuiltinSkillsNow()
        XCTAssertEqual(repaired.first?.status, .repaired)
        XCTAssertTrue(store.verifyBuiltinSkillsNow().valid)

        // 2. Daily Pocket Notes 5-minute silence extraction & reconciliation
        let t0 = Date(timeIntervalSince1970: 1_795_170_000)
        _ = store.saveDailyPocketNote(
            dateYmd: "2026-11-20",
            content: "- [ ] 准备 Wave 3 发布说明 2026-11-21\n- [ ] 预约洗牙\n待办：更新个人 Wiki 露营装备",
            now: t0
        )

        // After 2m -> must wait for 5-minute silence window
        let early = store.reconcileDailyPocketNote(dateYmd: "2026-11-20", now: t0.addingTimeInterval(120), force: false)
        XCTAssertFalse(early.extracted)
        XCTAssertEqual(early.reason, .waitingSilenceWindow)

        // After 6m -> extracts all 3 open Tracking Items
        let ready = store.reconcileDailyPocketNote(dateYmd: "2026-11-20", now: t0.addingTimeInterval(360), force: false)
        XCTAssertTrue(ready.extracted)
        XCTAssertEqual(ready.added.count, 3)
        XCTAssertEqual(ready.openItems.count, 3)

        // User edits note removing one item and completing another -> reconciliation updates in-place & prunes deleted open item!
        _ = store.saveDailyPocketNote(
            dateYmd: "2026-11-20",
            content: "- [x] 准备 Wave 3 发布说明 2026-11-21\n待办：更新个人 Wiki 露营装备",
            now: t0.addingTimeInterval(400)
        )
        let reconciled = store.reconcileDailyPocketNote(dateYmd: "2026-11-20", now: t0.addingTimeInterval(760), force: false)
        XCTAssertTrue(reconciled.extracted)
        XCTAssertEqual(reconciled.removedOpenIds.count, 1)
        XCTAssertEqual(reconciled.openItems.count, 1)

        // 3. Editable Artifact Document revisions + 1-click Personal Wiki sync
        let d1 = store.upsertArtifactDocument(title: "高原徒步清单", kind: .plan, markdown: "# 清单\n冲锋衣、保温壶")
        XCTAssertEqual(d1.revision, 1)
        let d2 = store.upsertArtifactDocument(id: d1.id, title: "高原徒步清单", kind: .plan, markdown: "# 清单\n冲锋衣、保温壶、登山杖")
        XCTAssertEqual(d2.revision, 2)
        XCTAssertNotEqual(d1.contentSha256, d2.contentSha256)

        let syncedPage = store.syncArtifactDocumentToWiki(docId: d2.id)
        XCTAssertNotNil(syncedPage)
        let search = store.searchPersonalWiki(PipiWikiSearchOptions(query: "登山杖"))
        XCTAssertEqual(search.chunks.first?.pageId, syncedPage?.id)
    }
}
