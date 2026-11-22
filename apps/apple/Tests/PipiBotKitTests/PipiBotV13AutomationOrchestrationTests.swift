import Foundation
import Testing
@testable import PipiBotKit

@Suite("PiPiBot v0.13.0 Automation Closure & Orchestration Control Plane")
struct PipiBotV13AutomationOrchestrationTests {

    // MARK: 1. Goal-First Blueprint & Dr Eggbot Architect Materialization

    @MainActor
    @Test("Dr Eggbot Architect materializes a Goal-First Bot with Blueprint and Event Routine")
    func architectMaterializesBlueprintBot() {
        let store = PipiAppStore(autoConnect: false, enableNativeRuntime: false)
        let res = store.materializeBlueprintBot(from: [
            "name": "客户体验巡检官",
            "role": "追踪预约与客户反馈",
            "goal": "缩短客户到店等待时间并提升 5 星评价",
            "process_steps": "拉取每日到店时间轴; 对照客户评价定位等待超长订单; 输出排班优化建议",
            "source_of_truth_rules": "到店时间以门店签到系统为准，不以邮件为准",
            "verification_criteria": "每条差评都已关联客户ID并给出根因",
            "escalation_rules": "发现连续 3 条投诉时立即通知主人",
            "feedback_sources": "Yelp评价; 微信回访",
            "entity_ids": "customer_email; order_id",
            "trigger_kind": "webhook",
            "trigger_value": "whsec_demo_123"
        ])

        #expect(res.persona.nameZh == "客户体验巡检官")
        #expect(res.persona.automationBlueprint?.goal == "缩短客户到店等待时间并提升 5 星评价")
        #expect(res.persona.automationBlueprint?.processSteps.count == 3)
        #expect(res.persona.automationBlueprint?.sourceOfTruthRules.count == 1)
        #expect(res.persona.automationBlueprint?.verificationCriteria.count == 1)
        #expect(res.persona.automationBlueprint?.entityIdSchema == ["customer_email", "order_id"])
        #expect(res.routine?.triggerKind == .webhook)
        #expect(res.routine?.eventConfig.webhookSecret == "whsec_demo_123")

        let promptBlock = res.persona.automationBlueprint?.renderedPromptBlock() ?? ""
        #expect(promptBlock.contains("Primary Goal"))
        #expect(promptBlock.contains("Source-of-Truth"))
        #expect(promptBlock.contains("customer_email"))
    }

    // MARK: 2. Entity Correlation Ledger & Approval-Gated Self-Evolution + Rollback

    @MainActor
    @Test("Entity ledger correlates cross-source IDs and Self-Evolution proposes, approves, and rolls back Blueprint Diff")
    func entityLedgerAndSelfEvolutionCycle() {
        let store = PipiAppStore(autoConnect: false, enableNativeRuntime: false)
        let created = store.materializeBlueprintBot(from: [
            "name": "OrderBot",
            "role": "Order tracker",
            "goal": "Zero missed orders",
            "process_steps": "Read email; Confirm booking"
        ]).persona

        let e1 = store.upsertEntityLedgerEntry(
            botId: created.id,
            entityKey: "ORD-9001",
            entityType: "order",
            source: "email",
            status: "waiting_details",
            summary: "Customer asked to reschedule"
        )
        let e2 = store.upsertEntityLedgerEntry(
            botId: created.id,
            entityKey: "ord-9001",
            entityType: "order",
            source: "booking_db",
            status: "confirmed",
            summary: "Confirmed for 15:00"
        )
        #expect(e1.id == e2.id)
        #expect(e2.status == "confirmed")
        let hits = store.queryEntityLedger(botId: created.id, entityKey: "ORD-9001")
        #expect(hits.count == 1)

        // Simulate 2 user corrections -> auto-proposes approval-gated Blueprint EvolutionDiff
        store.recordRunOutcome(
            botId: created.id,
            taskTitle: "Confirm ORD-9001",
            succeeded: false,
            verificationNotes: "Sent email before DB save",
            userCorrection: "必须先写入预约系统再发确认邮件"
        )
        store.recordRunOutcome(
            botId: created.id,
            taskTitle: "Confirm ORD-9002",
            succeeded: false,
            verificationNotes: "Duplicate booking created",
            userCorrection: "先查 entity ledger 避免重复建单"
        )

        #expect(store.blueprintEvolutionProposals.count == 1)
        let propId = store.blueprintEvolutionProposals[0].id
        #expect(store.blueprintEvolutionProposals[0].status == .pending)
        #expect(!store.blueprintEvolutionProposals[0].diffs.isEmpty)

        // Approve proposal -> bumps blueprint version to v2
        store.approveBlueprintEvolutionProposal(id: propId)
        let updatedBot = store.personas.first(where: { $0.id == created.id })
        #expect(updatedBot?.automationBlueprint?.blueprintVersion == 2)
        #expect(updatedBot?.automationBlueprint?.verificationCriteria.contains("必须先写入预约系统再发确认邮件") == true)

        // Rollback proposal -> restores v1 cleanly
        store.rollbackBlueprintEvolutionProposal(id: propId)
        let rolledBackBot = store.personas.first(where: { $0.id == created.id })
        #expect(rolledBackBot?.automationBlueprint?.blueprintVersion == 1)
        #expect(store.blueprintEvolutionProposals.first(where: { $0.id == propId })?.status == .rolledBack)
    }

    // MARK: 3. Event-Driven Triggers (Cron, HMAC Webhook, Channel Rule, Host Health)

    @Test("Event trigger engine matches 5-field Cron, verifies HMAC-SHA256 Webhooks, Channel regex, and Host Health")
    func eventTriggerMatchers() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        // 2026-11-23 is a Monday (weekday=2, cron dow=1)
        let monday0930 = cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 9, minute: 30))!
        let sunday0930 = cal.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 9, minute: 30))!

        #expect(PipiEventTriggerEngine.matchesCron("30 9 * * 1-5", date: monday0930, calendar: cal) == true)
        #expect(PipiEventTriggerEngine.matchesCron("30 9 * * 1-5", date: sunday0930, calendar: cal) == false)
        #expect(PipiEventTriggerEngine.matchesCron("*/15 * * * *", date: monday0930, calendar: cal) == true)

        let secret = "super_secret_key"
        let body = Data(#"{"event":"pr_opened","pr":42}"#.utf8)
        let validSig = PipiEventTriggerEngine.computeWebhookHMAC(secret: secret, body: body)
        #expect(PipiEventTriggerEngine.verifyWebhookAuth(secret: secret, authorizationHeader: nil, signatureHeader: validSig, body: body) == true)
        #expect(PipiEventTriggerEngine.verifyWebhookAuth(secret: secret, authorizationHeader: "Bearer \(secret)", signatureHeader: nil, body: body) == true)
        #expect(PipiEventTriggerEngine.verifyWebhookAuth(secret: secret, authorizationHeader: "Bearer wrong", signatureHeader: "sha256=deadbeef", body: body) == false)

        let msgRoutine = PipiBotRoutine(
            personaId: "bot_pipi_general",
            title: "Incident Alert",
            prompt: "Investigate",
            triggerKind: .channelMessage,
            eventConfig: PipiRoutineEventConfig(messageKeyword: "/故障|报警|P0/", channelFilter: "wechat")
        )
        #expect(PipiEventTriggerEngine.matchesChannelMessage(routine: msgRoutine, channel: "wechat", text: "线上出现 P0 故障了") == true)
        #expect(PipiEventTriggerEngine.matchesChannelMessage(routine: msgRoutine, channel: "group", text: "线上出现 P0 故障了") == false)

        let healthRoutine = PipiBotRoutine(
            personaId: "bot_pipi_operator",
            title: "CPU Sentinel",
            prompt: "Inspect CPU",
            triggerKind: .hostHealth,
            eventConfig: PipiRoutineEventConfig(healthMetric: .cpuPercent, healthThreshold: 80)
        )
        #expect(PipiEventTriggerEngine.evaluateHostHealth(routine: healthRoutine, cpuPercent: 92, memoryPercent: 40, diskFreeGB: 50, offlineHostNames: []) != nil)
        #expect(PipiEventTriggerEngine.evaluateHostHealth(routine: healthRoutine, cpuPercent: 45, memoryPercent: 40, diskFreeGB: 50, offlineHostNames: []) == nil)
    }

    // MARK: 4. Real Git Worktree Auto-Isolation, Diff Snapshot & Squash Merge Closure

    #if os(macOS)
    @Test("Git Worktree smart auto-isolation creates branch, captures diff, builds send-back prompt, and squash-merges cleanly")
    func gitWorktreeEndToEndLifecycle() throws {
        // Smart isolation policy verification
        #expect(PipiWorktreeManager.shouldIsolateWithWorktree(repoPath: "/tmp/r", isGroupParallel: false, activeRepoTaskCount: 0, projectAlwaysUseWorktree: false) == false)
        #expect(PipiWorktreeManager.shouldIsolateWithWorktree(repoPath: "/tmp/r", isGroupParallel: true, activeRepoTaskCount: 0, projectAlwaysUseWorktree: false) == true)
        #expect(PipiWorktreeManager.shouldIsolateWithWorktree(repoPath: "/tmp/r", isGroupParallel: false, activeRepoTaskCount: 1, projectAlwaysUseWorktree: false) == true)
        #expect(PipiWorktreeManager.shouldIsolateWithWorktree(repoPath: "/tmp/r", isGroupParallel: false, activeRepoTaskCount: 0, projectAlwaysUseWorktree: true) == true)

        let tmpRoot = FileManager.default.temporaryDirectory.appendingPathComponent("pipi-wt-test-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpRoot) }

        func git(_ args: [String], cwd: URL) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = args
            p.currentDirectoryURL = cwd
            try p.run()
            p.waitUntilExit()
            #expect(p.terminationStatus == 0)
        }

        try git(["init", "-b", "main"], cwd: tmpRoot)
        try git(["config", "user.email", "test@pipibot.dev"], cwd: tmpRoot)
        try git(["config", "user.name", "PiPi Test"], cwd: tmpRoot)
        try "hello v1\n".write(to: tmpRoot.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try git(["add", "-A"], cwd: tmpRoot)
        try git(["commit", "-m", "initial"], cwd: tmpRoot)

        // Create isolated worktree
        let wt = try PipiWorktreeManager.createWorktree(
            repoPath: tmpRoot.path,
            taskTitle: "Add Feature X",
            botId: "bot_pipi_coder",
            botName: "Coder"
        )
        #expect(wt.branchName.hasPrefix("pipi/add-feature-x-"))
        #expect(FileManager.default.fileExists(atPath: wt.worktreePath))

        // Modify file inside worktree; main repo remains untouched!
        let wtDir = URL(fileURLWithPath: wt.worktreePath)
        try "hello v2 from worktree\n".write(to: wtDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "export const x = 42;\n".write(to: wtDir.appendingPathComponent("feature.ts"), atomically: true, encoding: .utf8)
        #expect((try String(contentsOf: tmpRoot.appendingPathComponent("README.md"), encoding: .utf8)) == "hello v1\n")

        // Capture diff snapshot
        let snap = PipiWorktreeManager.captureDiffSnapshot(for: wt)
        #expect(snap.status == .readyForReview)
        #expect(snap.files.count == 2)
        #expect(snap.unifiedDiff.contains("hello v2 from worktree"))
        #expect(snap.unifiedDiff.contains("export const x = 42"))

        let feedbackPrompt = PipiWorktreeManager.buildSendBackPrompt(session: snap, feedback: "请补充注释", filePath: "feature.ts", lineNumber: 1, lang: .zhHans)
        #expect(feedbackPrompt.contains("feature.ts:L1"))
        #expect(feedbackPrompt.contains(snap.worktreePath))

        // Squash merge back to main & verify worktree cleanup
        let mergeMsg = try PipiWorktreeManager.mergeAndCleanup(session: snap, strategy: .squash, commitMessage: "feat: add feature x")
        #expect(mergeMsg.contains("Merged"))
        #expect(!FileManager.default.fileExists(atPath: wt.worktreePath))
        #expect((try String(contentsOf: tmpRoot.appendingPathComponent("README.md"), encoding: .utf8)) == "hello v2 from worktree\n")
        #expect(FileManager.default.fileExists(atPath: tmpRoot.appendingPathComponent("feature.ts").path))
    }
    #endif

    // MARK: 5. Token & Cost Metering (Alert-Only, Non-Blocking)

    @Test("Usage metering records cloud & local-free tokens and emits alert-only notices without blocking")
    func usageMeteringAndGentleAlerts() {
        let localRec = PipiUsageMeteringEngine.makeRecord(
            botId: "bot_local",
            botName: "Local Bot",
            taskTitle: "Local summary",
            modelId: "qwen2.5:latest",
            providerKind: "ollama",
            promptTokens: 10_000,
            completionTokens: 2_000
        )
        #expect(localRec.isLocalFree == true)
        #expect(localRec.estimatedCostUSD == 0.0)
        #expect(localRec.totalTokens == 12_000)

        let cloudRec = PipiUsageMeteringEngine.makeRecord(
            botId: "bot_cloud",
            botName: "Cloud Coder",
            taskTitle: "Deep Refactor",
            modelId: "claude-sonnet-4-5",
            providerKind: "anthropic",
            promptTokens: 100_000,
            completionTokens: 50_000,
            cachedTokens: 20_000
        )
        #expect(cloudRec.isLocalFree == false)
        #expect(cloudRec.estimatedCostUSD > 0.9)

        let config = PipiUsageAlertConfig(enableAlerts: true, dailyCostAlertUSD: 0.5, perTaskCostAlertUSD: 0.5)
        let alerts = PipiUsageMeteringEngine.evaluateAlerts(
            latestRecord: cloudRec,
            allRecords: [localRec, cloudRec],
            config: config,
            existingAlerts: []
        )
        #expect(alerts.count == 2) // 1 per-task + 1 daily gentle alert
        // Re-evaluating same day dedupes daily alert
        let secondPass = PipiUsageMeteringEngine.evaluateAlerts(
            latestRecord: cloudRec,
            allRecords: [localRec, cloudRec],
            config: config,
            existingAlerts: alerts
        )
        #expect(secondPass.isEmpty)
    }
}
