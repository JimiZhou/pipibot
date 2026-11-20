// PiPiBot — Clean-room MIT implementation.
// Wave 2 (#02): Per-Bot Isolated Experiential Memory + Prompt-Cache-Safe Recall.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

import Foundation

// MARK: - 1. Public Models & Cadence Config

public struct PipiBotMemoryCadenceConfig: Codable, Equatable, Sendable {
    public var extractEveryRuns: Int
    public var idleConsolidationHours: Double
    public var maxUnconsolidatedBytes: Int
    public var maxChatsBeforeConsolidation: Int
    public var maxSummaryBytes: Int

    public init(
        extractEveryRuns: Int = 5,
        idleConsolidationHours: Double = 6.0,
        maxUnconsolidatedBytes: Int = 64 * 1024,
        maxChatsBeforeConsolidation: Int = 30,
        maxSummaryBytes: Int = 8 * 1024
    ) {
        self.extractEveryRuns = max(1, extractEveryRuns)
        self.idleConsolidationHours = max(0.01, idleConsolidationHours)
        self.maxUnconsolidatedBytes = max(256, maxUnconsolidatedBytes)
        self.maxChatsBeforeConsolidation = max(1, maxChatsBeforeConsolidation)
        self.maxSummaryBytes = max(512, maxSummaryBytes)
    }
}

public struct PipiBotMemoryCandidate: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let botId: String
    public let sessionId: String
    public var lesson: String
    public var stage: PipiBotMemoryLifecycleStage
    public let fingerprint: String
    public let createdAt: String

    public init(
        id: String = "bmc_\(UUID().uuidString.prefix(8).lowercased())",
        botId: String,
        sessionId: String,
        lesson: String,
        stage: PipiBotMemoryLifecycleStage = .candidate,
        fingerprint: String,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.botId = botId
        self.sessionId = sessionId
        self.lesson = lesson
        self.stage = stage
        self.fingerprint = fingerprint
        self.createdAt = createdAt
    }
}

public struct PipiBotMemoryState: Codable, Equatable, Sendable {
    public let botId: String
    public var revision: Int
    public var totalSuccessfulRuns: Int
    public var successfulRunsSinceLastExtract: Int
    public var chatsSinceLastConsolidation: Int
    public var lastActivityAt: String?
    public var lastExtractedAt: String?
    public var lastConsolidatedAt: String?
    public var summaryByteSize: Int
    public var candidateByteSize: Int

    public init(
        botId: String,
        revision: Int = 0,
        totalSuccessfulRuns: Int = 0,
        successfulRunsSinceLastExtract: Int = 0,
        chatsSinceLastConsolidation: Int = 0,
        lastActivityAt: String? = nil,
        lastExtractedAt: String? = nil,
        lastConsolidatedAt: String? = nil,
        summaryByteSize: Int = 0,
        candidateByteSize: Int = 0
    ) {
        self.botId = botId
        self.revision = revision
        self.totalSuccessfulRuns = totalSuccessfulRuns
        self.successfulRunsSinceLastExtract = successfulRunsSinceLastExtract
        self.chatsSinceLastConsolidation = chatsSinceLastConsolidation
        self.lastActivityAt = lastActivityAt
        self.lastExtractedAt = lastExtractedAt
        self.lastConsolidatedAt = lastConsolidatedAt
        self.summaryByteSize = summaryByteSize
        self.candidateByteSize = candidateByteSize
    }
}

public struct PipiBotMemoryRunInput: Sendable {
    public let botId: String
    public let sessionId: String
    public let userPrompt: String
    public let assistantReply: String
    public let toolSummary: String?
    public let now: Date

    public init(
        botId: String,
        sessionId: String,
        userPrompt: String,
        assistantReply: String,
        toolSummary: String? = nil,
        now: Date = Date()
    ) {
        self.botId = botId
        self.sessionId = sessionId
        self.userPrompt = userPrompt
        self.assistantReply = assistantReply
        self.toolSummary = toolSummary
        self.now = now
    }
}

public enum PipiBotMemoryConsolidationTrigger: String, Sendable, Equatable {
    case idleCheck = "idle_check"
    case compaction
    case manual
}

public enum PipiBotMemoryConsolidationReason: String, Sendable, Equatable {
    case idleTimeout = "idle_timeout"
    case compaction
    case byteLimit = "byte_limit"
    case chatCount = "chat_count"
    case manual
}

public struct PipiBotMemoryRecordOutcome: Sendable {
    public let state: PipiBotMemoryState
    public let extractedCandidates: [PipiBotMemoryCandidate]
    public let consolidated: Bool
    public let consolidationReason: PipiBotMemoryConsolidationReason?
}

public struct PipiBotMemoryConsolidationOutcome: Sendable {
    public let consolidated: Bool
    public let reason: PipiBotMemoryConsolidationReason?
    public let state: PipiBotMemoryState
    public let summary: String
}

public enum PipiPromptCacheRecallReason: String, Sendable, Equatable {
    case firstTurn = "first_turn"
    case postCompaction = "post_compaction"
    case skippedCachePreserved = "skipped_cache_preserved"
    case emptyMemory = "empty_memory"
}

public struct PipiPromptCacheSafeRecallResult: Equatable, Sendable {
    public let injected: Bool
    public let reason: PipiPromptCacheRecallReason
    public let hiddenNote: String?
    public let memoryRevision: Int
}

public typealias PipiBotMemoryExtractor = @Sendable (
    _ botId: String,
    _ recentRuns: [PipiBotMemoryRunInput],
    _ existingSummary: String
) async -> [String]

public typealias PipiBotMemoryConsolidator = @Sendable (
    _ botId: String,
    _ existingSummary: String,
    _ candidates: [PipiBotMemoryCandidate],
    _ maxSummaryBytes: Int
) async -> String

// MARK: - 2. PipiBotMemoryEngine (Per-Bot Isolated & Prompt-Cache Safe)

@MainActor
public final class PipiBotMemoryEngine {
    public let rootURL: URL
    public var cadence: PipiBotMemoryCadenceConfig

    private let extractor: PipiBotMemoryExtractor
    private let consolidator: PipiBotMemoryConsolidator
    private var pendingRunBuffers: [String: [PipiBotMemoryRunInput]] = [:]
    /// Tracks `botId::sessionId` -> last injected compaction generation so mid-session turns preserve KV Prompt Cache.
    private var injectedSessionCompactionGen: [String: Int] = [:]

    public init(
        rootURL: URL,
        cadence: PipiBotMemoryCadenceConfig = PipiBotMemoryCadenceConfig(),
        extractor: PipiBotMemoryExtractor? = nil,
        consolidator: PipiBotMemoryConsolidator? = nil
    ) {
        self.rootURL = rootURL
        self.cadence = cadence
        self.extractor = extractor ?? Self.defaultDeterministicExtract
        self.consolidator = consolidator ?? Self.defaultDeterministicConsolidate
    }

    public static func sanitizeBotId(_ botId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let cleaned = botId.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "_"
        }
        let result = String(cleaned)
        return result.isEmpty ? "default_bot" : result
    }

    public func memoryDirectory(for botId: String) -> URL {
        rootURL
            .appendingPathComponent("bots", isDirectory: true)
            .appendingPathComponent(Self.sanitizeBotId(botId), isDirectory: true)
            .appendingPathComponent("memory", isDirectory: true)
    }

    private func summaryURL(for botId: String) -> URL {
        memoryDirectory(for: botId).appendingPathComponent("summary.md")
    }

    private func candidatesURL(for botId: String) -> URL {
        memoryDirectory(for: botId).appendingPathComponent("candidates.json")
    }

    private func stateURL(for botId: String) -> URL {
        memoryDirectory(for: botId).appendingPathComponent("state.json")
    }

    public func readSummary(for botId: String) -> String {
        (try? String(contentsOf: summaryURL(for: botId), encoding: .utf8)) ?? ""
    }

    public func readCandidates(for botId: String) -> [PipiBotMemoryCandidate] {
        guard let data = try? Data(contentsOf: candidatesURL(for: botId)),
              let decoded = try? JSONDecoder().decode([PipiBotMemoryCandidate].self, from: data) else {
            return []
        }
        return decoded
    }

    public func readState(for botId: String) -> PipiBotMemoryState {
        if let data = try? Data(contentsOf: stateURL(for: botId)),
           let decoded = try? JSONDecoder().decode(PipiBotMemoryState.self, from: data) {
            return decoded
        }
        return PipiBotMemoryState(botId: botId)
    }

    public func writeSummaryManually(for botId: String, summary: String) {
        let clean = PipiWikiTextUtilities.scrubSecrets(summary.trimmingCharacters(in: .whitespacesAndNewlines))
        var state = readState(for: botId)
        state.summaryByteSize = persistSummary(clean, for: botId)
        state.revision += 1
        state.lastConsolidatedAt = ISO8601DateFormatter().string(from: Date())
        persistState(state, for: botId)
    }

    private func persistSummary(_ summary: String, for botId: String) -> Int {
        let dir = memoryDirectory(for: botId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = Data(summary.utf8)
        try? data.write(to: summaryURL(for: botId), options: .atomic)
        return data.count
    }

    private func persistCandidates(_ candidates: [PipiBotMemoryCandidate], for botId: String) -> Int {
        let dir = memoryDirectory(for: botId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(candidates) else { return 0 }
        try? data.write(to: candidatesURL(for: botId), options: .atomic)
        return data.count
    }

    private func persistState(_ state: PipiBotMemoryState, for botId: String) {
        let dir = memoryDirectory(for: botId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(state) {
            try? data.write(to: stateURL(for: botId), options: .atomic)
        }
    }

    nonisolated private static func lessonFingerprint(_ lesson: String) -> String {
        let normalized = lesson
            .lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-*•")))
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(PipiWikiTextUtilities.sha256Hex(normalized).prefix(16))
    }

    // MARK: - Lifecycle: Extract Every 5 Successful Runs -> Consolidate on 6h Idle / Compaction / 64KB / 30 Chats

    @discardableResult
    public func recordSuccessfulRun(_ input: PipiBotMemoryRunInput) async -> PipiBotMemoryRecordOutcome {
        let iso = ISO8601DateFormatter()
        let nowIso = iso.string(from: input.now)
        var state = readState(for: input.botId)
        state.totalSuccessfulRuns += 1
        state.successfulRunsSinceLastExtract += 1
        state.chatsSinceLastConsolidation += 1
        state.lastActivityAt = nowIso

        var buffer = pendingRunBuffers[input.botId] ?? []
        buffer.append(input)
        pendingRunBuffers[input.botId] = buffer

        var extracted: [PipiBotMemoryCandidate] = []
        if state.successfulRunsSinceLastExtract >= cadence.extractEveryRuns {
            let existingSummary = readSummary(for: input.botId)
            var candidates = readCandidates(for: input.botId)
            var known = Set(candidates.map(\.fingerprint))
            let rawLessons = await extractor(input.botId, buffer, existingSummary)

            for raw in rawLessons {
                let clean = PipiWikiTextUtilities.scrubSecrets(raw.trimmingCharacters(in: .whitespacesAndNewlines))
                guard !clean.isEmpty else { continue }
                let fp = Self.lessonFingerprint(clean)
                guard known.insert(fp).inserted else { continue }
                let cand = PipiBotMemoryCandidate(
                    botId: input.botId,
                    sessionId: input.sessionId,
                    lesson: clean,
                    stage: .candidate,
                    fingerprint: fp,
                    createdAt: nowIso
                )
                candidates.append(cand)
                extracted.append(cand)
            }

            state.candidateByteSize = persistCandidates(candidates, for: input.botId)
            state.successfulRunsSinceLastExtract = 0
            state.lastExtractedAt = nowIso
            pendingRunBuffers[input.botId] = []
        }

        persistState(state, for: input.botId)

        let cons = await consolidateIfDue(botId: input.botId, now: input.now, trigger: .idleCheck)
        return PipiBotMemoryRecordOutcome(
            state: cons.state,
            extractedCandidates: extracted,
            consolidated: cons.consolidated,
            consolidationReason: cons.reason
        )
    }

    @discardableResult
    public func consolidateIfDue(
        botId: String,
        now: Date = Date(),
        trigger: PipiBotMemoryConsolidationTrigger = .idleCheck
    ) async -> PipiBotMemoryConsolidationOutcome {
        let iso = ISO8601DateFormatter()
        let nowIso = iso.string(from: now)
        var state = readState(for: botId)
        var candidates = readCandidates(for: botId)
        let existingSummary = readSummary(for: botId)

        // On compaction or manual consolidate, flush buffered runs into candidates first
        if (trigger == .compaction || trigger == .manual),
           let buffered = pendingRunBuffers[botId],
           !buffered.isEmpty {
            var known = Set(candidates.map(\.fingerprint))
            let rawLessons = await extractor(botId, buffered, existingSummary)
            for raw in rawLessons {
                let clean = PipiWikiTextUtilities.scrubSecrets(raw.trimmingCharacters(in: .whitespacesAndNewlines))
                guard !clean.isEmpty else { continue }
                let fp = Self.lessonFingerprint(clean)
                guard known.insert(fp).inserted else { continue }
                candidates.append(PipiBotMemoryCandidate(
                    botId: botId,
                    sessionId: buffered.last?.sessionId ?? "manual",
                    lesson: clean,
                    stage: .candidate,
                    fingerprint: fp,
                    createdAt: nowIso
                ))
            }
            pendingRunBuffers[botId] = []
            state.successfulRunsSinceLastExtract = 0
            state.lastExtractedAt = nowIso
        }

        let pending = candidates.filter { $0.stage == .candidate }
        guard !pending.isEmpty else {
            return PipiBotMemoryConsolidationOutcome(consolidated: false, reason: nil, state: state, summary: existingSummary)
        }

        let reason: PipiBotMemoryConsolidationReason?
        switch trigger {
        case .manual:
            reason = .manual
        case .compaction:
            reason = .compaction
        case .idleCheck:
            if (state.summaryByteSize + state.candidateByteSize) >= cadence.maxUnconsolidatedBytes {
                reason = .byteLimit
            } else if state.chatsSinceLastConsolidation >= cadence.maxChatsBeforeConsolidation {
                reason = .chatCount
            } else if let lastStr = state.lastActivityAt, let lastDate = iso.date(from: lastStr) {
                let idleHours = now.timeIntervalSince(lastDate) / 3600.0
                reason = idleHours >= cadence.idleConsolidationHours ? .idleTimeout : nil
            } else {
                reason = nil
            }
        }

        guard let resolvedReason = reason else {
            return PipiBotMemoryConsolidationOutcome(consolidated: false, reason: nil, state: state, summary: existingSummary)
        }

        let mergedRaw = await consolidator(botId, existingSummary, pending, cadence.maxSummaryBytes)
        let cleanSummary = PipiWikiTextUtilities.scrubSecrets(mergedRaw)

        let updatedCandidates = candidates.map { cand -> PipiBotMemoryCandidate in
            guard cand.stage == .candidate else { return cand }
            var copy = cand
            copy.stage = .consolidated
            return copy
        }

        state.summaryByteSize = persistSummary(cleanSummary, for: botId)
        state.candidateByteSize = persistCandidates(updatedCandidates, for: botId)
        state.revision += 1
        state.chatsSinceLastConsolidation = 0
        state.lastConsolidatedAt = nowIso
        persistState(state, for: botId)

        return PipiBotMemoryConsolidationOutcome(
            consolidated: true,
            reason: resolvedReason,
            state: state,
            summary: cleanSummary
        )
    }

    // MARK: - Prompt-Cache-Safe Hidden Note Injection (NEVER mutates System Prompt)

    public func buildPromptCacheSafeRecall(
        botId: String,
        sessionId: String,
        compactionGeneration: Int,
        wikiRecallSnippets: [String] = []
    ) -> PipiPromptCacheSafeRecallResult {
        let sanitizedId = Self.sanitizeBotId(botId)
        let key = "\(sanitizedId)::\(sessionId)"
        let state = readState(for: botId)
        let lastGen = injectedSessionCompactionGen[key]

        let isFirstTurn = (lastGen == nil)
        let isPostCompaction = (!isFirstTurn && compactionGeneration > (lastGen ?? 0))

        guard isFirstTurn || isPostCompaction else {
            return PipiPromptCacheSafeRecallResult(
                injected: false,
                reason: .skippedCachePreserved,
                hiddenNote: nil,
                memoryRevision: state.revision
            )
        }

        let summary = readSummary(for: botId).trimmingCharacters(in: .whitespacesAndNewlines)
        let wikiLines = wikiRecallSnippets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        guard !summary.isEmpty || !wikiLines.isEmpty else {
            return PipiPromptCacheSafeRecallResult(
                injected: false,
                reason: .emptyMemory,
                hiddenNote: nil,
                memoryRevision: state.revision
            )
        }

        injectedSessionCompactionGen[key] = compactionGeneration

        var blocks: [String] = [
            "<pipibot_bot_memory bot=\"\(sanitizedId)\" rev=\"\(state.revision)\" mode=\"\(isPostCompaction ? "post_compaction" : "session_start")\">"
        ]
        if !summary.isEmpty {
            blocks.append(summary)
        }
        if !wikiLines.isEmpty {
            blocks.append("## Related Personal Wiki Context")
            blocks.append(contentsOf: wikiLines.map { "- \($0)" })
        }
        blocks.append("</pipibot_bot_memory>")

        return PipiPromptCacheSafeRecallResult(
            injected: true,
            reason: isPostCompaction ? .postCompaction : .firstTurn,
            hiddenNote: blocks.joined(separator: "\n"),
            memoryRevision: state.revision
        )
    }

    public func resetSessionInjectionTracking(botId: String, sessionId: String) {
        injectedSessionCompactionGen.removeValue(forKey: "\(Self.sanitizeBotId(botId))::\(sessionId)")
    }

    // MARK: - Default Deterministic Offline Extractor & Consolidator

    public static let defaultDeterministicExtract: PipiBotMemoryExtractor = { _, recentRuns, _ in
        var lessons: [String] = []
        for run in recentRuns {
            let prompt = PipiWikiTextUtilities.scrubSecrets(run.userPrompt.trimmingCharacters(in: .whitespacesAndNewlines))
            let reply = PipiWikiTextUtilities.scrubSecrets(run.assistantReply.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !prompt.isEmpty || !reply.isEmpty else { continue }
            let compactPrompt = prompt
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .prefix(120)
            let firstLine = reply
                .components(separatedBy: CharacterSet(charactersIn: "\n。!?"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { $0.count >= 6 })
            if let firstLine {
                lessons.append("When handling \"\(compactPrompt)\": \(firstLine.prefix(180))")
            } else if !compactPrompt.isEmpty {
                lessons.append("Recurring user focus: \(compactPrompt)")
            }
        }
        return Array(lessons.prefix(6))
    }

    public static let defaultDeterministicConsolidate: PipiBotMemoryConsolidator = { _, existingSummary, candidates, maxBytes in
        var seen = Set<String>()
        var bullets: [String] = []

        func appendBullet(_ raw: String) {
            let cleaned = PipiWikiTextUtilities.scrubSecrets(
                raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-*•")))
            )
            guard !cleaned.isEmpty else { return }
            let fp = lessonFingerprint(cleaned)
            guard seen.insert(fp).inserted else { return }
            bullets.append("- \(cleaned)")
        }

        for line in existingSummary.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                appendBullet(trimmed)
            }
        }
        for cand in candidates where cand.stage == .candidate {
            appendBullet(cand.lesson)
        }

        let header = "# Bot Experiential Memory\n\n"
        var kept: [String] = []
        var byteCount = header.utf8.count
        for bullet in bullets.reversed() {
            let line = "\(bullet)\n"
            let size = line.utf8.count
            if byteCount + size > maxBytes { break }
            kept.insert(line, at: 0)
            byteCount += size
        }
        return kept.isEmpty ? "" : header + kept.joined()
    }
}
