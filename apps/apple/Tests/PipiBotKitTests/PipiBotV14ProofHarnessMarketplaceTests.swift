import Foundation
import Testing
@testable import PipiBotKit

@Suite("PiPiBot v0.14.0 Review Proof, Harness/Loop Engineering & MIT Marketplace")
struct PipiBotV14ProofHarnessMarketplaceTests {

    @MainActor
    @Test("Review Proof, Not Code: deterministic checks block excuse comments & verify clean worktree; prose rule graduates to check")
    func reviewProofAndRuleGraduation() async throws {
        let store = PipiAppStore(autoConnect: false, enableNativeRuntime: false)

        // Create a temporary worktree-like directory with a HACK excuse comment
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pipi-proof-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let targetFile = tmpDir.appendingPathComponent("worker.ts")
        try "// HACK temporary workaround\nexport const ok = true;\n".write(to: targetFile, atomically: true, encoding: .utf8)

        let session = PipiWorktreeReviewSession(
            repoPath: tmpDir.path,
            worktreePath: tmpDir.path,
            branchName: "pipi/test-proof",
            baseBranch: "main",
            taskTitle: "Proof Check Demo",
            botId: "bot_pipi_coder",
            botName: "Coder",
            status: .readyForReview,
            files: [PipiWorktreeFileChange(path: "worker.ts", status: "A", additions: 2, deletions: 0)],
            unifiedDiff: "+// HACK temporary workaround\n+export const ok = true;"
        )
        store.worktreeSessions.insert(session, at: 0)

        let blockedBundle = await PipiProofVerificationEngine.buildProofBundle(
            session: session,
            checks: store.deterministicChecks,
            panelProviders: [],
            lang: .zhHans
        )
        #expect(blockedBundle.overallStatus == .blocked)
        #expect(blockedBundle.checkResults.contains(where: { !$0.passed && $0.name.contains("Excuse") }))

        // Fix the excuse comment -> proof bundle becomes verified (score 100)
        try "export const ok = true;\n".write(to: targetFile, atomically: true, encoding: .utf8)
        let verifiedBundle = await PipiProofVerificationEngine.buildProofBundle(
            session: session,
            checks: store.deterministicChecks,
            panelProviders: [],
            lang: .zhHans
        )
        #expect(verifiedBundle.overallStatus == .verified)
        #expect(verifiedBundle.proofScore == 100)

        // Graduate a prose hex-color rule into a deterministic regex ratchet check
        let graduated = store.graduateRuleToDeterministicCheck(rule: "禁止在 SwiftUI 里写 raw hex 颜色值")
        #expect(graduated.kind == .regexBan)
        #expect(graduated.commandOrPattern.contains("#[0-9A-Fa-f]{6}"))
        #expect(store.deterministicChecks.contains(where: { $0.id == graduated.id }))

        // Parse multi-model panel reviewer verdict
        let parsedVote = PipiProofVerificationEngine.parsePanelVote(
            rawText: "VERDICT: BLOCK\nSUMMARY: Missing auth check on webhook endpoint.\nBLOCKING: Missing HMAC check, Race condition",
            reviewerLabel: "Security Reviewer",
            modelId: "gemini-pro",
            focusArea: "security"
        )
        #expect(parsedVote.verdict == .block)
        #expect(parsedVote.blockingIssues.count == 2)
    }

    @MainActor
    @Test("Day-Shift Loop & Harness: hard no-draft escalation, approved tone examples, add-rule on edit, and knowledge gaps roadmap")
    func dayShiftLoopHarnessAndKnowledgeGaps() {
        let store = PipiAppStore(autoConnect: false, enableNativeRuntime: false)
        let loop = store.installDayShiftLoop(.supportFromDocs)
        #expect(loop.requiresHumanGate == true)
        #expect(loop.harness.docsOnlyMode == true)

        // 1. Refund/angry message -> flagged UNDRAFTED immediately
        let flagged = store.enqueueLoopDraft(
            loopId: loop.id,
            inputSummary: "I want a refund immediately, this is broken!",
            draftContent: "should not be kept"
        )
        #expect(flagged?.status == .flaggedUndrafted)
        #expect(flagged?.draftContent.isEmpty == true)
        #expect(flagged?.escalationReason != nil)

        // 2. Normal docs question -> waits at Human Gate & records missing doc into Knowledge Gaps
        let draft1 = store.enqueueLoopDraft(
            loopId: loop.id,
            inputSummary: "How do I reset my API key?",
            draftContent: "Open Settings -> Local Vault -> Rotate Key (see docs/keys.md).",
            citedSources: ["docs/keys.md"],
            missingDocQuestion: "How do I export CSV with custom delimiter?"
        )
        #expect(draft1?.status == .pendingGate)
        #expect(store.knowledgeGaps.count == 1)
        #expect(store.knowledgeGaps[0].status == .open)

        // Approve draft1 -> becomes golden Approved Tone Example!
        store.approveLoopDraft(id: draft1!.id)
        #expect(store.approvedExamples.count == 1)
        #expect(store.approvedExamples[0].approvedOutput.contains("Rotate Key"))
        let tonePrompt = PipiLoopHarnessEngine.renderApprovedExamplesBlock(examples: store.approvedExamples)
        #expect(tonePrompt.contains("Owner-Approved Tone Examples"))

        // 3. "Don't fix the draft — add a rule": edit draft2 and accumulate a durable Harness rule
        let draft2 = store.enqueueLoopDraft(
            loopId: loop.id,
            inputSummary: "When is v2.0 shipping?",
            draftContent: "Next Tuesday!"
        )
        store.editLoopDraftAndAddRule(
            id: draft2!.id,
            editedDraft: "We don't have a fixed date yet; follow our GitHub Releases.",
            newRuleNote: "绝不向用户承诺具体发版日期"
        )
        let updatedLoop = store.operationalLoops.first(where: { $0.id == loop.id })
        #expect(updatedLoop?.harness.hardRules.contains("绝不向用户承诺具体发版日期") == true)

        // Resolve knowledge gap -> closes the feedback loop
        store.resolveKnowledgeGap(id: store.knowledgeGaps[0].id, docPath: "docs/csv-export.md")
        #expect(store.knowledgeGaps[0].status == .resolved)
    }

    @MainActor
    @Test("Clean-room MIT Bot & Lean Skill Marketplace adheres to <300 token pruning budget and installs Blueprint + Skills + Loop")
    func mitMarketplaceAndSkillPruning() {
        // Every curated skill must be clean-room MIT and strictly pruned (<300 tokens)
        #expect(PipiBotMarketplaceCatalog.curatedBots.count >= 6)
        #expect(PipiBotMarketplaceCatalog.curatedSkills.count >= 7)
        for sk in PipiBotMarketplaceCatalog.curatedSkills {
            #expect(sk.license == "MIT")
            #expect(sk.estimatedTokens < 300)
        }
        for bot in PipiBotMarketplaceCatalog.curatedBots {
            #expect(bot.license == "MIT")
            #expect(bot.blueprint.isConfigured)
        }

        let store = PipiAppStore(autoConnect: false, enableNativeRuntime: false)
        let supportListing = PipiBotMarketplaceCatalog.curatedBots.first(where: { $0.id == "mkt_bot_dayshift_support" })!
        let installedBot = store.installMarketplaceBot(supportListing)

        #expect(store.personas.contains(where: { $0.id == installedBot.id }))
        #expect(installedBot.automationBlueprint?.goal == supportListing.blueprint.goal)
        #expect(store.operationalLoops.contains(where: { $0.preset == .supportFromDocs && $0.botId == installedBot.id }))
        #expect(store.ecosystemManager.installedSkills.contains(where: { $0.id == "skill_docs_gap_tracker" }))

        // Skill bloat audit detects oversized skills & prose rules ready for deterministic graduation
        let bloatedSkill = PipiInstalledSkillPack(
            id: "skill_huge_test",
            name: "Bloated Prompt",
            description: "Too long",
            source: "local",
            scope: .global,
            bodyMarkdown: String(repeating: "Always write detailed markdown instructions carefully without mistakes. ", count: 90),
            enabled: true
        )
        store.ecosystemManager.upsertSkillPack(bloatedSkill)
        let report = store.auditPromptBloat(for: installedBot)
        #expect(report.skillWeights.contains(where: { $0.name == "Bloated Prompt" && $0.isBloated }))
    }
}
