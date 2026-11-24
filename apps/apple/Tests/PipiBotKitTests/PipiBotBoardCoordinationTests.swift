// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
//
// Phase 2 Tests: Native Swift PipiBoardEngine & PipiAppStore Board Coordination + Persistence

import Foundation
import Testing
@testable import PipiBotKit

@Suite("Phase 2 — Vercel Board-Inspired Coordination Layer (Channels, Claims, Leases, Dependencies & Follow-Ups)")
struct PipiBotBoardCoordinationTests {

    @Test("Atomic claim conflict, lease renewal, claim_lost expiry escalation, dependency unlocking, follow-ups, and persistence")
    @MainActor
    func testFullBoardLifecycleAndPersistence() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-board-swift-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let stateFile = tempDir.appendingPathComponent("resident-state.json")

        let baseTime = Date(timeIntervalSince1970: 1_764_000_000)
        let secrets = PipiInMemorySecretStore()
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateFile,
            secretStore: secrets,
            saveDebounceMilliseconds: 0
        )

        #expect(PipiBoardEngine.normalizeSlug("#Dev / PiPiBot!") == "dev/pipibot")
        let channel = store.ensureBoardChannel(slug: "#dev/pipibot", title: "PiPiBot Dev")
        #expect(channel.slug == "dev/pipibot")

        let owner = PipiBoardActorRef(id: "human:owner", name: "Owner", kind: .human)
        let codex = PipiBoardActorRef(id: "harness:codex", name: "Codex", kind: .harness, harness: "codex")
        let claude = PipiBoardActorRef(id: "harness:claude", name: "Claude Code", kind: .harness, harness: "claude-code")
        let writer = PipiBoardActorRef(id: "bot:writer", name: "Writer", kind: .bot)

        // 1. Prerequisite task + dependent blocked task
        let t1 = store.createBoardThread(
            channelSlug: "dev/pipibot",
            title: "Ship Board lease sweeper",
            body: "Add deterministic TTL lease recovery.",
            priority: .high,
            labels: ["board", "core"],
            author: owner,
            now: baseTime
        )
        #expect(t1.status == PipiBoardTaskStatus.open)

        let t2 = store.createBoardThread(
            channelSlug: "dev/pipibot",
            title: "Write release summary",
            body: "Summarize Board improvements after merge.",
            blockedBy: [t1.id],
            author: owner,
            now: baseTime
        )
        #expect(t2.status == PipiBoardTaskStatus.blocked)

        // Blocked task cannot be claimed
        let blockedAttempt = store.claimBoardTask(threadId: t2.id, actor: writer, now: baseTime)
        #expect(blockedAttempt.ok == false)
        #expect(blockedAttempt.reason == "blocked")
        #expect(blockedAttempt.unresolvedBlockers == [t1.id])

        // 2. Atomic claim + conflict rejection
        let c1 = store.claimBoardTask(threadId: t1.id, actor: codex, leaseSeconds: 10, now: baseTime)
        #expect(c1.ok == true)
        let leaseToken = try #require(c1.claim?.leaseToken)

        let conflict = store.claimBoardTask(threadId: t1.id, actor: claude, now: baseTime.addingTimeInterval(2))
        #expect(conflict.ok == false)
        #expect(conflict.reason == "already_claimed")
        #expect(conflict.conflictClaim?.actor.id == codex.id)

        // 3. Lease renewal succeeds with valid token and rejects wrong token
        let badRenew = store.renewBoardLease(threadId: t1.id, actorId: codex.id, leaseToken: "bad", now: baseTime.addingTimeInterval(5))
        #expect(badRenew.ok == false)
        #expect(badRenew.reason == "token_mismatch")

        let okRenew = store.renewBoardLease(threadId: t1.id, actorId: codex.id, leaseToken: leaseToken, leaseSeconds: 10, now: baseTime.addingTimeInterval(5))
        #expect(okRenew.ok == true)
        #expect(okRenew.claim?.renewCount == 1)

        // 4. Lease expiry -> claim_lost returns task to open queue
        let expired1 = store.sweepExpiredBoardLeases(now: baseTime.addingTimeInterval(20))
        #expect(expired1.count == 1)
        #expect(expired1[0].status == PipiBoardTaskStatus.open)
        #expect(expired1[0].claimLostCount == 1)

        // 5. Scheduled follow-up triggers when due
        let fup = store.scheduleBoardFollowUp(threadId: t1.id, actor: claude, prompt: "Verify swift test green", inSeconds: 30, now: baseTime.addingTimeInterval(20))
        #expect(fup != nil)
        #expect(store.collectDueBoardFollowUps(now: baseTime.addingTimeInterval(35)).isEmpty)
        let triggered = store.collectDueBoardFollowUps(now: baseTime.addingTimeInterval(55))
        #expect(triggered.count == 1)
        #expect(triggered[0].status == PipiBoardScheduledFollowUp.Status.triggered)

        // 6. Complete t1 -> automatically unblocks t2
        let completed = store.completeBoardTask(
            threadId: t1.id,
            actor: codex,
            summary: "Lease sweeper implemented & verified.",
            deliverableRef: "worktree:pipi/wt-board",
            now: baseTime.addingTimeInterval(60)
        )
        #expect(completed.ok == true)
        #expect(completed.unblockedThreadIds == [t2.id])

        // Queue claim picks up newly unblocked t2
        let nextClaim = store.claimNextBoardTask(actor: writer, channelSlug: "dev/pipibot", now: baseTime.addingTimeInterval(65))
        #expect(nextClaim.ok == true)
        #expect(nextClaim.thread?.id == t2.id)

        // 7. Flush & reload verifies persistence across restarts
        store.flush()
        let reloaded = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            stateFileUrl: stateFile,
            secretStore: secrets,
            saveDebounceMilliseconds: 0
        )

        let hasDevChannel = reloaded.boardChannels.contains(where: { $0.slug == "dev/pipibot" })
        let reloadedT1 = reloaded.boardThreads.first(where: { $0.id == t1.id })
        let reloadedT2 = reloaded.boardThreads.first(where: { $0.id == t2.id })
        #expect(hasDevChannel)
        #expect(reloadedT1?.status == PipiBoardTaskStatus.done)
        #expect(reloadedT2?.status == PipiBoardTaskStatus.claimed)
        #expect(reloadedT2?.claim?.actor.id == writer.id)
    }
}
