// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
//
// Phase 2: AppStore Integration for Vercel Board-Inspired Coordination Layer

import Foundation

@MainActor
extension PipiAppStore {

    public var boardNeedsYouThreads: [PipiBoardThread] {
        boardThreads.filter { $0.status == .needsYou }
    }

    @discardableResult
    public func ensureBoardChannel(
        slug: String,
        title: String? = nil,
        description: String? = nil
    ) -> PipiBoardChannel {
        let norm = PipiBoardEngine.normalizeSlug(slug)
        if let idx = boardChannels.firstIndex(where: { $0.slug == norm }) {
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                boardChannels[idx].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let description {
                boardChannels[idx].description = description
            }
            boardChannels[idx].updatedAt = PipiBoardEngine.isoString(Date())
            saveResidentState()
            return boardChannels[idx]
        }

        let nowIso = PipiBoardEngine.isoString(Date())
        let channel = PipiBoardChannel(
            slug: norm,
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title! : norm,
            description: description,
            createdAt: nowIso,
            updatedAt: nowIso
        )
        boardChannels.append(channel)
        PipiBoardEngine.appendEvent(
            PipiBoardActivityEvent(
                kind: .channelCreated,
                channelSlug: norm,
                actor: PipiBoardEngine.systemActor,
                summary: "Created channel #\(norm)",
                createdAt: nowIso
            ),
            into: &boardEvents
        )
        saveResidentState()
        return channel
    }

    @discardableResult
    public func createBoardThread(
        channelSlug: String = "inbox",
        title: String,
        body: String = "",
        kind: PipiBoardThreadKind = .task,
        priority: PipiBoardTaskPriority = .normal,
        labels: [String] = [],
        blockedBy: [String] = [],
        author: PipiBoardActorRef = PipiBoardActorRef(id: "human:owner", name: "Owner", kind: .human),
        linkedConversationId: String? = nil,
        linkedWorktreeId: String? = nil,
        now: Date = Date()
    ) -> PipiBoardThread {
        let slug = PipiBoardEngine.normalizeSlug(channelSlug)
        if !boardChannels.contains(where: { $0.slug == slug }) {
            _ = ensureBoardChannel(slug: slug)
        }

        let nowIso = PipiBoardEngine.isoString(now)
        let unresolved = PipiBoardEngine.unresolvedBlockers(for: blockedBy, in: boardThreads)
        let initialStatus: PipiBoardTaskStatus = unresolved.isEmpty ? .open : .blocked

        let threadId = "bth_\(UUID().uuidString.prefix(8).lowercased())"
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let messages: [PipiBoardMessage] = trimmedBody.isEmpty ? [] : [
            PipiBoardMessage(threadId: threadId, author: author, body: trimmedBody, createdAt: nowIso)
        ]

        let thread = PipiBoardThread(
            id: threadId,
            channelSlug: slug,
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled thread" : title.trimmingCharacters(in: .whitespacesAndNewlines),
            status: initialStatus,
            priority: priority,
            labels: Array(Set(labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })).sorted(),
            blockedBy: blockedBy,
            messages: messages,
            linkedConversationId: linkedConversationId,
            linkedWorktreeId: linkedWorktreeId,
            createdBy: author,
            createdAt: nowIso,
            updatedAt: nowIso
        )

        boardThreads.insert(thread, at: 0)
        PipiBoardEngine.appendEvent(
            PipiBoardActivityEvent(
                kind: .threadCreated,
                channelSlug: slug,
                threadId: threadId,
                actor: author,
                summary: "\(author.name) created \(kind.rawValue) \"\(thread.title)\" in #\(slug)",
                detail: ["status": thread.status.rawValue, "priority": thread.priority.rawValue],
                createdAt: nowIso
            ),
            into: &boardEvents
        )
        saveResidentState()
        return thread
    }

    @discardableResult
    public func postBoardMessage(
        threadId: String,
        author: PipiBoardActorRef,
        body: String,
        artifactRef: String? = nil,
        now: Date = Date()
    ) -> PipiBoardMessage? {
        guard let idx = boardThreads.firstIndex(where: { $0.id == threadId }) else { return nil }
        let nowIso = PipiBoardEngine.isoString(now)
        let msg = PipiBoardMessage(
            threadId: threadId,
            author: author,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            artifactRef: artifactRef,
            createdAt: nowIso
        )
        boardThreads[idx].messages.append(msg)
        boardThreads[idx].updatedAt = nowIso
        PipiBoardEngine.appendEvent(
            PipiBoardActivityEvent(
                kind: .messagePosted,
                channelSlug: boardThreads[idx].channelSlug,
                threadId: threadId,
                actor: author,
                summary: "\(author.name) posted in \"\(boardThreads[idx].title)\"",
                detail: artifactRef.map { ["artifactRef": $0] },
                createdAt: nowIso
            ),
            into: &boardEvents
        )
        saveResidentState()
        return msg
    }

    @discardableResult
    public func claimBoardTask(
        threadId: String,
        actor: PipiBoardActorRef,
        leaseSeconds: TimeInterval? = nil,
        note: String? = nil,
        now: Date = Date()
    ) -> PipiBoardClaimResult {
        let result = PipiBoardEngine.claimTask(
            threadId: threadId,
            actor: actor,
            leaseSeconds: leaseSeconds,
            note: note,
            threads: &boardThreads,
            events: &boardEvents,
            now: now
        )
        if result.ok {
            saveResidentState()
        }
        return result
    }

    @discardableResult
    public func claimNextBoardTask(
        actor: PipiBoardActorRef,
        channelSlug: String? = nil,
        label: String? = nil,
        leaseSeconds: TimeInterval? = nil,
        note: String? = nil,
        now: Date = Date()
    ) -> PipiBoardClaimResult {
        _ = PipiBoardEngine.sweepExpiredLeases(threads: &boardThreads, events: &boardEvents, now: now)
        let normChannel = channelSlug.map { PipiBoardEngine.normalizeSlug($0) }
        let normLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let candidate = boardThreads
            .filter { th in
                guard th.status == .open else { return false }
                if let normChannel, th.channelSlug != normChannel { return false }
                if let normLabel, !normLabel.isEmpty, !th.labels.contains(normLabel) { return false }
                return PipiBoardEngine.unresolvedBlockers(for: th.blockedBy, in: boardThreads).isEmpty
            }
            .sorted { lhs, rhs in
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank < rhs.priority.sortRank
                }
                return lhs.createdAt < rhs.createdAt
            }
            .first

        guard let next = candidate else {
            return PipiBoardClaimResult(ok: false, reason: "no_open_tasks")
        }
        return claimBoardTask(threadId: next.id, actor: actor, leaseSeconds: leaseSeconds, note: note, now: now)
    }

    @discardableResult
    public func renewBoardLease(
        threadId: String,
        actorId: String,
        leaseToken: String,
        leaseSeconds: TimeInterval? = nil,
        now: Date = Date()
    ) -> PipiBoardRenewResult {
        let result = PipiBoardEngine.renewLease(
            threadId: threadId,
            actorId: actorId,
            leaseToken: leaseToken,
            leaseSeconds: leaseSeconds,
            threads: &boardThreads,
            events: &boardEvents,
            now: now
        )
        if result.ok {
            saveResidentState()
        }
        return result
    }

    @discardableResult
    public func sweepExpiredBoardLeases(now: Date = Date()) -> [PipiBoardThread] {
        let expired = PipiBoardEngine.sweepExpiredLeases(threads: &boardThreads, events: &boardEvents, now: now)
        if !expired.isEmpty {
            saveResidentState()
        }
        return expired
    }

    @discardableResult
    public func completeBoardTask(
        threadId: String,
        actor: PipiBoardActorRef,
        summary: String? = nil,
        deliverableRef: String? = nil,
        leaseToken: String? = nil,
        now: Date = Date()
    ) -> PipiBoardCompleteResult {
        let result = PipiBoardEngine.completeTask(
            threadId: threadId,
            actor: actor,
            summary: summary,
            deliverableRef: deliverableRef,
            leaseToken: leaseToken,
            threads: &boardThreads,
            events: &boardEvents,
            now: now
        )
        if result.ok {
            saveResidentState()
        }
        return result
    }

    @discardableResult
    public func scheduleBoardFollowUp(
        threadId: String,
        actor: PipiBoardActorRef,
        prompt: String,
        inSeconds: TimeInterval = 300,
        now: Date = Date()
    ) -> PipiBoardScheduledFollowUp? {
        guard let idx = boardThreads.firstIndex(where: { $0.id == threadId }) else { return nil }
        let nowIso = PipiBoardEngine.isoString(now)
        let dueIso = PipiBoardEngine.isoString(now.addingTimeInterval(max(1, inSeconds)))
        let fup = PipiBoardScheduledFollowUp(
            threadId: threadId,
            actor: actor,
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            dueAt: dueIso,
            createdAt: nowIso
        )
        boardThreads[idx].followUps.append(fup)
        boardThreads[idx].updatedAt = nowIso
        PipiBoardEngine.appendEvent(
            PipiBoardActivityEvent(
                kind: .followupScheduled,
                channelSlug: boardThreads[idx].channelSlug,
                threadId: threadId,
                actor: actor,
                summary: "\(actor.name) scheduled follow-up on \"\(boardThreads[idx].title)\"",
                detail: ["followUpId": fup.id, "dueAt": dueIso],
                createdAt: nowIso
            ),
            into: &boardEvents
        )
        saveResidentState()
        return fup
    }

    @discardableResult
    public func collectDueBoardFollowUps(now: Date = Date()) -> [PipiBoardScheduledFollowUp] {
        let due = PipiBoardEngine.collectDueFollowUps(threads: &boardThreads, events: &boardEvents, now: now)
        if !due.isEmpty {
            saveResidentState()
        }
        return due
    }

    @discardableResult
    public func requestBoardNeedsYou(
        threadId: String,
        actor: PipiBoardActorRef,
        reason: String,
        now: Date = Date()
    ) -> PipiBoardThread? {
        guard let idx = boardThreads.firstIndex(where: { $0.id == threadId }) else { return nil }
        let nowIso = PipiBoardEngine.isoString(now)
        boardThreads[idx].status = .needsYou
        boardThreads[idx].claim = nil
        boardThreads[idx].updatedAt = nowIso
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            boardThreads[idx].messages.append(
                PipiBoardMessage(threadId: threadId, author: actor, body: trimmed, createdAt: nowIso)
            )
        }
        PipiBoardEngine.appendEvent(
            PipiBoardActivityEvent(
                kind: .taskNeedsYou,
                channelSlug: boardThreads[idx].channelSlug,
                threadId: threadId,
                actor: actor,
                summary: "\(actor.name) flagged \"\(boardThreads[idx].title)\" as needs you",
                detail: trimmed.isEmpty ? nil : ["reason": trimmed],
                createdAt: nowIso
            ),
            into: &boardEvents
        )
        saveResidentState()
        return boardThreads[idx]
    }

    @discardableResult
    public func releaseBoardClaim(
        threadId: String,
        actor: PipiBoardActorRef,
        reason: String? = nil,
        now: Date = Date()
    ) -> PipiBoardThread? {
        guard let idx = boardThreads.firstIndex(where: { $0.id == threadId }) else { return nil }
        let nowIso = PipiBoardEngine.isoString(now)
        boardThreads[idx].claim = nil
        let unresolved = PipiBoardEngine.unresolvedBlockers(for: boardThreads[idx].blockedBy, in: boardThreads)
        boardThreads[idx].status = unresolved.isEmpty ? .open : .blocked
        boardThreads[idx].updatedAt = nowIso
        if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            boardThreads[idx].messages.append(
                PipiBoardMessage(threadId: threadId, author: actor, body: reason.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: nowIso)
            )
        }
        PipiBoardEngine.appendEvent(
            PipiBoardActivityEvent(
                kind: .claimLost,
                channelSlug: boardThreads[idx].channelSlug,
                threadId: threadId,
                actor: actor,
                summary: "\(actor.name) released claim on \"\(boardThreads[idx].title)\"",
                createdAt: nowIso
            ),
            into: &boardEvents
        )
        saveResidentState()
        return boardThreads[idx]
    }
}
