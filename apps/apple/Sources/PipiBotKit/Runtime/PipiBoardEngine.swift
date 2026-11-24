// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
//
// Phase 2: Native Swift Multi-Agent Coordination Board (`PipiBoardEngine`)
// 1:1 behavioral parity with `packages/core/src/board-engine.ts`:
// - Channels -> Threads -> Tasks
// - Atomic claims with TTL leases, heartbeat renewal, and `claim_lost` recovery/escalation
// - Task dependency DAG (`blockedBy`) with automatic downstream unlocking on completion
// - Thread-scoped scheduled follow-ups & live activity event ring buffer

import Foundation

public struct PipiBoardClaimResult: Equatable, Sendable {
    public let ok: Bool
    public let reason: String?
    public let thread: PipiBoardThread?
    public let claim: PipiBoardTaskClaim?
    public let conflictClaim: PipiBoardTaskClaim?
    public let unresolvedBlockers: [String]
    public let renewed: Bool

    public init(
        ok: Bool,
        reason: String? = nil,
        thread: PipiBoardThread? = nil,
        claim: PipiBoardTaskClaim? = nil,
        conflictClaim: PipiBoardTaskClaim? = nil,
        unresolvedBlockers: [String] = [],
        renewed: Bool = false
    ) {
        self.ok = ok
        self.reason = reason
        self.thread = thread
        self.claim = claim
        self.conflictClaim = conflictClaim
        self.unresolvedBlockers = unresolvedBlockers
        self.renewed = renewed
    }
}

public struct PipiBoardRenewResult: Equatable, Sendable {
    public let ok: Bool
    public let reason: String?
    public let thread: PipiBoardThread?
    public let claim: PipiBoardTaskClaim?
}

public struct PipiBoardCompleteResult: Equatable, Sendable {
    public let ok: Bool
    public let reason: String?
    public let thread: PipiBoardThread?
    public let unblockedThreadIds: [String]
}

public enum PipiBoardEngine {
    public static let defaultLeaseSeconds: TimeInterval = 15 * 60
    public static let minLeaseSeconds: TimeInterval = 5
    public static let maxLeaseSeconds: TimeInterval = 2 * 60 * 60
    public static let maxRecentEvents: Int = 500

    public static let systemActor = PipiBoardActorRef(
        id: "system:board",
        name: "Board",
        kind: .system
    )

    public static func normalizeSlug(_ raw: String?) -> String {
        let trimmed = (raw ?? "inbox")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "^#+", with: "", options: .regularExpression)
        let parts = trimmed
            .split(separator: "/")
            .map { seg in
                String(seg)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "[^a-z0-9_-]+", with: "-", options: .regularExpression)
                    .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "inbox" : parts.joined(separator: "/")
    }

    public static func defaultChannels(now: Date = Date()) -> [PipiBoardChannel] {
        let iso = isoString(now)
        return [
            PipiBoardChannel(id: "ch_inbox", slug: "inbox", title: "Inbox", description: "Personal capture and uncategorized threads", createdAt: iso, updatedAt: iso),
            PipiBoardChannel(id: "ch_dev", slug: "dev", title: "Engineering", description: "Code changes, worktree diffs, tests, and local CLI runs", createdAt: iso, updatedAt: iso),
            PipiBoardChannel(id: "ch_ops", slug: "ops", title: "Operations", description: "Device nodes, scheduled checks, and health", createdAt: iso, updatedAt: iso),
        ]
    }

    public static func clampedLeaseSeconds(_ raw: TimeInterval?) -> TimeInterval {
        let val = raw ?? defaultLeaseSeconds
        return max(minLeaseSeconds, min(maxLeaseSeconds, val))
    }

    public static func isoString(_ date: Date) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.string(from: date)
    }

    public static func parseISO(_ raw: String) -> Date? {
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    public static func unresolvedBlockers(for blockedBy: [String], in threads: [PipiBoardThread]) -> [String] {
        blockedBy.filter { depId in
            guard let dep = threads.first(where: { $0.id == depId }) else { return true }
            return dep.status != .done
        }
    }

    public static func appendEvent(
        _ event: PipiBoardActivityEvent,
        into events: inout [PipiBoardActivityEvent]
    ) {
        events.append(event)
        if events.count > maxRecentEvents {
            events.removeFirst(events.count - maxRecentEvents)
        }
    }

    @discardableResult
    public static func sweepExpiredLeases(
        threads: inout [PipiBoardThread],
        events: inout [PipiBoardActivityEvent],
        now: Date = Date()
    ) -> [PipiBoardThread] {
        let nowIso = isoString(now)
        var expired: [PipiBoardThread] = []

        for idx in threads.indices {
            guard threads[idx].status == .claimed, let claim = threads[idx].claim else { continue }
            guard let expiresDate = parseISO(claim.expiresAt), expiresDate <= now else { continue }

            let lostActor = claim.actor
            threads[idx].claim = nil
            threads[idx].claimLostCount += 1
            let escalated = threads[idx].claimLostCount >= max(1, threads[idx].maxClaimRetries)
            threads[idx].status = escalated ? .needsYou : .open
            threads[idx].updatedAt = nowIso

            let msg = PipiBoardMessage(
                threadId: threads[idx].id,
                author: systemActor,
                body: escalated
                    ? "Lease expired for \(lostActor.name) (\(threads[idx].claimLostCount)/\(threads[idx].maxClaimRetries)). Escalated to Needs You."
                    : "Lease expired for \(lostActor.name) (\(threads[idx].claimLostCount)/\(threads[idx].maxClaimRetries)). Returned to open queue.",
                createdAt: nowIso
            )
            threads[idx].messages.append(msg)

            appendEvent(
                PipiBoardActivityEvent(
                    kind: .claimLost,
                    channelSlug: threads[idx].channelSlug,
                    threadId: threads[idx].id,
                    actor: lostActor,
                    summary: "Lease expired for \(lostActor.name) on \"\(threads[idx].title)\"",
                    detail: [
                        "escalatedToNeedsYou": String(escalated),
                        "claimLostCount": String(threads[idx].claimLostCount)
                    ],
                    createdAt: nowIso
                ),
                into: &events
            )

            if escalated {
                appendEvent(
                    PipiBoardActivityEvent(
                        kind: .taskNeedsYou,
                        channelSlug: threads[idx].channelSlug,
                        threadId: threads[idx].id,
                        actor: systemActor,
                        summary: "Task \"\(threads[idx].title)\" needs human review after repeated lease expiry",
                        createdAt: nowIso
                    ),
                    into: &events
                )
            }

            expired.append(threads[idx])
        }

        return expired
    }

    public static func claimTask(
        threadId: String,
        actor: PipiBoardActorRef,
        leaseSeconds: TimeInterval? = nil,
        note: String? = nil,
        threads: inout [PipiBoardThread],
        events: inout [PipiBoardActivityEvent],
        now: Date = Date()
    ) -> PipiBoardClaimResult {
        _ = sweepExpiredLeases(threads: &threads, events: &events, now: now)

        guard let idx = threads.firstIndex(where: { $0.id == threadId }) else {
            return PipiBoardClaimResult(ok: false, reason: "not_found")
        }

        if threads[idx].status == .done || threads[idx].status == .cancelled {
            return PipiBoardClaimResult(ok: false, reason: "terminal_status", thread: threads[idx])
        }

        let unresolved = unresolvedBlockers(for: threads[idx].blockedBy, in: threads)
        if !unresolved.isEmpty || threads[idx].status == .blocked {
            threads[idx].status = .blocked
            return PipiBoardClaimResult(ok: false, reason: "blocked", thread: threads[idx], unresolvedBlockers: unresolved)
        }

        let ttl = clampedLeaseSeconds(leaseSeconds)
        let nowIso = isoString(now)
        let expiresIso = isoString(now.addingTimeInterval(ttl))

        if threads[idx].status == .claimed, var existing = threads[idx].claim {
            if existing.actor.id == actor.id {
                existing.expiresAt = expiresIso
                existing.renewCount += 1
                if let note, !note.isEmpty { existing.note = note }
                threads[idx].claim = existing
                threads[idx].updatedAt = nowIso
                appendEvent(
                    PipiBoardActivityEvent(
                        kind: .leaseRenewed,
                        channelSlug: threads[idx].channelSlug,
                        threadId: threads[idx].id,
                        actor: actor,
                        summary: "\(actor.name) renewed lease on \"\(threads[idx].title)\"",
                        detail: ["expiresAt": expiresIso, "renewCount": String(existing.renewCount)],
                        createdAt: nowIso
                    ),
                    into: &events
                )
                return PipiBoardClaimResult(ok: true, thread: threads[idx], claim: existing, renewed: true)
            }
            return PipiBoardClaimResult(ok: false, reason: "already_claimed", thread: threads[idx], conflictClaim: existing)
        }

        let claim = PipiBoardTaskClaim(
            actor: actor,
            claimedAt: nowIso,
            expiresAt: expiresIso,
            renewCount: 0,
            note: note
        )
        threads[idx].claim = claim
        threads[idx].status = .claimed
        threads[idx].updatedAt = nowIso

        appendEvent(
            PipiBoardActivityEvent(
                kind: .taskClaimed,
                channelSlug: threads[idx].channelSlug,
                threadId: threads[idx].id,
                actor: actor,
                summary: "\(actor.name) claimed \"\(threads[idx].title)\"",
                detail: ["expiresAt": expiresIso],
                createdAt: nowIso
            ),
            into: &events
        )
        return PipiBoardClaimResult(ok: true, thread: threads[idx], claim: claim, renewed: false)
    }

    public static func renewLease(
        threadId: String,
        actorId: String,
        leaseToken: String,
        leaseSeconds: TimeInterval? = nil,
        threads: inout [PipiBoardThread],
        events: inout [PipiBoardActivityEvent],
        now: Date = Date()
    ) -> PipiBoardRenewResult {
        _ = sweepExpiredLeases(threads: &threads, events: &events, now: now)

        guard let idx = threads.firstIndex(where: { $0.id == threadId }) else {
            return PipiBoardRenewResult(ok: false, reason: "not_found", thread: nil, claim: nil)
        }
        guard threads[idx].status == .claimed, var claim = threads[idx].claim else {
            return PipiBoardRenewResult(ok: false, reason: "not_claimed", thread: threads[idx], claim: nil)
        }
        guard claim.actor.id == actorId else {
            return PipiBoardRenewResult(ok: false, reason: "actor_mismatch", thread: threads[idx], claim: claim)
        }
        guard claim.leaseToken == leaseToken else {
            return PipiBoardRenewResult(ok: false, reason: "token_mismatch", thread: threads[idx], claim: claim)
        }

        let ttl = clampedLeaseSeconds(leaseSeconds)
        let nowIso = isoString(now)
        let expiresIso = isoString(now.addingTimeInterval(ttl))
        claim.expiresAt = expiresIso
        claim.renewCount += 1
        threads[idx].claim = claim
        threads[idx].updatedAt = nowIso

        appendEvent(
            PipiBoardActivityEvent(
                kind: .leaseRenewed,
                channelSlug: threads[idx].channelSlug,
                threadId: threads[idx].id,
                actor: claim.actor,
                summary: "\(claim.actor.name) renewed lease on \"\(threads[idx].title)\"",
                detail: ["expiresAt": expiresIso, "renewCount": String(claim.renewCount)],
                createdAt: nowIso
            ),
            into: &events
        )
        return PipiBoardRenewResult(ok: true, reason: nil, thread: threads[idx], claim: claim)
    }

    public static func completeTask(
        threadId: String,
        actor: PipiBoardActorRef,
        summary: String? = nil,
        deliverableRef: String? = nil,
        leaseToken: String? = nil,
        threads: inout [PipiBoardThread],
        events: inout [PipiBoardActivityEvent],
        now: Date = Date()
    ) -> PipiBoardCompleteResult {
        guard let idx = threads.firstIndex(where: { $0.id == threadId }) else {
            return PipiBoardCompleteResult(ok: false, reason: "not_found", thread: nil, unblockedThreadIds: [])
        }
        if threads[idx].status == .done || threads[idx].status == .cancelled {
            return PipiBoardCompleteResult(ok: false, reason: "already_terminal", thread: threads[idx], unblockedThreadIds: [])
        }
        if let leaseToken, let active = threads[idx].claim, active.leaseToken != leaseToken {
            return PipiBoardCompleteResult(ok: false, reason: "token_mismatch", thread: threads[idx], unblockedThreadIds: [])
        }

        let nowIso = isoString(now)
        threads[idx].status = .done
        threads[idx].claim = nil
        threads[idx].completedAt = nowIso
        threads[idx].updatedAt = nowIso
        if let deliverableRef, !deliverableRef.isEmpty {
            threads[idx].deliverableRef = deliverableRef
        }

        let trimmedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedSummary.isEmpty || (deliverableRef?.isEmpty == false) {
            threads[idx].messages.append(
                PipiBoardMessage(
                    threadId: threadId,
                    author: actor,
                    body: trimmedSummary.isEmpty ? "Completed task with deliverable \(deliverableRef ?? "")" : trimmedSummary,
                    artifactRef: deliverableRef,
                    createdAt: nowIso
                )
            )
        }

        let completedTitle = threads[idx].title
        appendEvent(
            PipiBoardActivityEvent(
                kind: .taskCompleted,
                channelSlug: threads[idx].channelSlug,
                threadId: threadId,
                actor: actor,
                summary: "\(actor.name) completed \"\(completedTitle)\"",
                detail: deliverableRef.map { ["deliverableRef": $0] },
                createdAt: nowIso
            ),
            into: &events
        )

        var unblockedIds: [String] = []
        for cIdx in threads.indices {
            guard threads[cIdx].status == .blocked else { continue }
            guard threads[cIdx].blockedBy.contains(threadId) else { continue }
            if unresolvedBlockers(for: threads[cIdx].blockedBy, in: threads).isEmpty {
                threads[cIdx].status = .open
                threads[cIdx].updatedAt = nowIso
                threads[cIdx].messages.append(
                    PipiBoardMessage(
                        threadId: threads[cIdx].id,
                        author: systemActor,
                        body: "Unblocked after \"\(completedTitle)\" (\(threadId)) completed. Ready to claim.",
                        createdAt: nowIso
                    )
                )
                unblockedIds.append(threads[cIdx].id)
                appendEvent(
                    PipiBoardActivityEvent(
                        kind: .taskUnblocked,
                        channelSlug: threads[cIdx].channelSlug,
                        threadId: threads[cIdx].id,
                        actor: systemActor,
                        summary: "Unblocked \"\(threads[cIdx].title)\" after \"\(completedTitle)\" completed",
                        detail: ["unblockedBy": threadId],
                        createdAt: nowIso
                    ),
                    into: &events
                )
            }
        }

        return PipiBoardCompleteResult(ok: true, reason: nil, thread: threads[idx], unblockedThreadIds: unblockedIds)
    }

    @discardableResult
    public static func collectDueFollowUps(
        threads: inout [PipiBoardThread],
        events: inout [PipiBoardActivityEvent],
        now: Date = Date()
    ) -> [PipiBoardScheduledFollowUp] {
        let nowIso = isoString(now)
        var triggered: [PipiBoardScheduledFollowUp] = []

        for tIdx in threads.indices {
            for fIdx in threads[tIdx].followUps.indices {
                guard threads[tIdx].followUps[fIdx].status == .pending else { continue }
                guard let dueDate = parseISO(threads[tIdx].followUps[fIdx].dueAt), dueDate <= now else { continue }
                threads[tIdx].followUps[fIdx].status = .triggered
                threads[tIdx].followUps[fIdx].triggeredAt = nowIso
                threads[tIdx].updatedAt = nowIso
                let fup = threads[tIdx].followUps[fIdx]
                threads[tIdx].messages.append(
                    PipiBoardMessage(
                        threadId: threads[tIdx].id,
                        author: systemActor,
                        body: "Scheduled follow-up due (\(fup.actor.name)): \(fup.prompt)",
                        createdAt: nowIso
                    )
                )
                triggered.append(fup)
                appendEvent(
                    PipiBoardActivityEvent(
                        kind: .followupTriggered,
                        channelSlug: threads[tIdx].channelSlug,
                        threadId: threads[tIdx].id,
                        actor: fup.actor,
                        summary: "Follow-up due on \"\(threads[tIdx].title)\": \(fup.prompt)",
                        detail: ["followUpId": fup.id],
                        createdAt: nowIso
                    ),
                    into: &events
                )
            }
        }
        return triggered
    }
}
