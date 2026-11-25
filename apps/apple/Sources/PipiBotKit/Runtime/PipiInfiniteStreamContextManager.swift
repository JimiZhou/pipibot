// PiPiBot — Clean-room MIT implementation.
// Infinite-Stream Conversation Auto-Topic Segmentation & Bounded Context Engine.
// - Keeps user chat history 100% continuous & non-destructive (infinite scroll in Mac & WeChat)
// - Automatically detects topic boundaries (time gap, explicit cues, standalone new URL, low lexical overlap)
// - Strictly bounds LLM prompt context (recent verbatim turns of active topic + rolling capsule + last 3 topic index)
// - Filters out stale error turns from prior topics so failed calls never pollute new conversations.

import Foundation

public struct PipiConversationTopicSegment: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var summary: String
    public var startMessageIndex: Int
    public var endMessageIndex: Int
    public var startedAt: String
    public var endedAt: String
    public var messageCount: Int

    public init(
        id: String = "seg_\(UUID().uuidString.prefix(8).lowercased())",
        title: String,
        summary: String,
        startMessageIndex: Int,
        endMessageIndex: Int,
        startedAt: String,
        endedAt: String,
        messageCount: Int
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.startMessageIndex = startMessageIndex
        self.endMessageIndex = endMessageIndex
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.messageCount = messageCount
    }
}

public enum PipiTopicBoundaryReason: String, Sendable, Equatable {
    case none
    case timeGap = "time_gap"
    case explicitCue = "explicit_cue"
    case urlTopicShift = "url_topic_shift"
    case semanticShift = "semantic_shift"
}

public struct PipiTopicShiftDecision: Sendable, Equatable {
    public let shouldSplit: Bool
    public let reason: PipiTopicBoundaryReason
    public let newTopicTitle: String
}

public struct PipiBoundedContextWindow: Sendable, Equatable {
    public let messages: [PipiChatMessage]
    public let activeTopicTitle: String?
    public let archivedSegmentCount: Int
    public let foldedActiveMessageCount: Int
    public let estimatedChars: Int
}

public enum PipiInfiniteStreamContextManager {
    /// Gap threshold (25 minutes) after which a new user turn automatically starts a fresh topic segment.
    public static let defaultTimeGapSeconds: TimeInterval = 25 * 60
    /// Maximum verbatim messages kept from the active topic before folding older active turns into a rolling capsule.
    public static let maxVerbatimActiveMessages: Int = 12
    /// Hard character budget for outbound prompt history so context never balloons across infinite streams.
    public static let maxPromptHistoryChars: Int = 10_000
    /// Number of archived recent topic capsules kept as ultra-compact background continuity index.
    public static let maxArchivedTopicCapsules: Int = 3

    private static let explicitSwitchCues: [String] = [
        "换个话题", "说个别的", "聊点别的", "顺便问", "另外问", "对了帮我", "对了，帮我",
        "新话题", "插一句", "问个无关的", "另外一件事", "还有个事",
        "by the way", "new topic", "change topic", "unrelated question", "switching gears"
    ]

    private static let followUpIndicators: [String] = [
        "为什么", "为啥", "怎么", "原理", "继续", "展开", "详细", "具体", "还有呢", "然后呢",
        "那它", "那他", "这个", "那个", "上面", "刚才", "不对", "改吧", "修一下", "帮我修",
        "回滚", "允许", "同意", "确认", "选第", "好的", "可以", "行", "嗯",
        "why", "how", "continue", "more detail", "fix it", "go ahead", "yes", "ok"
    ]

    /// Evaluates whether `incomingUserText` starts a new topic segment relative to the active segment of `existingMessages`.
    public static func evaluateTopicShift(
        existingMessages: [PipiChatMessage],
        activeTopicStartIndex: Int,
        incomingUserText: String,
        now: Date = Date(),
        timeGapSeconds: TimeInterval = defaultTimeGapSeconds
    ) -> PipiTopicShiftDecision {
        let trimmed = incomingUserText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = deriveTopicTitle(from: trimmed)
        let clampedStart = max(0, min(activeTopicStartIndex, existingMessages.count))
        let activeSlice = Array(existingMessages[clampedStart...])
        guard !activeSlice.isEmpty else {
            return PipiTopicShiftDecision(shouldSplit: false, reason: .none, newTopicTitle: title)
        }

        // 1. Time-gap boundary (>= 25 min idle -> fresh topic, prevents stale topic bleed!)
        if let lastTs = activeSlice.last?.createdAt,
           let lastDate = parseISO8601(lastTs),
           now.timeIntervalSince(lastDate) >= timeGapSeconds {
            return PipiTopicShiftDecision(shouldSplit: true, reason: .timeGap, newTopicTitle: title)
        }

        let lower = trimmed.lowercased()

        // 2. Explicit topic-switch phrases
        if explicitSwitchCues.contains(where: { lower.contains($0) }) {
            return PipiTopicShiftDecision(shouldSplit: true, reason: .explicitCue, newTopicTitle: title)
        }

        // Short follow-ups or pronoun references ALWAYS stay inside the current active topic
        if isLikelyFollowUp(trimmed, lower: lower) {
            return PipiTopicShiftDecision(shouldSplit: false, reason: .none, newTopicTitle: title)
        }

        // 3. Standalone URL whose host does not appear in the current active topic
        if let incomingHost = extractFirstURLHost(from: trimmed) {
            let activeText = activeSlice.suffix(6).map(\.content).joined(separator: " ").lowercased()
            if !activeText.contains(incomingHost) && activeSlice.count >= 2 {
                return PipiTopicShiftDecision(shouldSplit: true, reason: .urlTopicShift, newTopicTitle: title)
            }
        }

        // 4. Lexical / entity shift once active segment already has >= 4 messages
        if activeSlice.count >= 4 && trimmed.count >= 12 {
            let incomingTokens = extractSalientTokens(trimmed)
            if incomingTokens.count >= 3 {
                let activeTokens = extractSalientTokens(
                    activeSlice.suffix(6).map(\.content).joined(separator: " ")
                )
                let overlap = jaccardOverlap(incomingTokens, activeTokens)
                if overlap < 0.05 {
                    return PipiTopicShiftDecision(shouldSplit: true, reason: .semanticShift, newTopicTitle: title)
                }
            }
        }

        return PipiTopicShiftDecision(shouldSplit: false, reason: .none, newTopicTitle: title)
    }

    /// Seals the previous active segment (if a boundary triggered) directly on `conversation` WITHOUT deleting any messages.
    @discardableResult
    public static func applyAutoTopicSegmentation(
        to conversation: inout PipiConversation,
        incomingUserText: String,
        now: Date = Date()
    ) -> PipiTopicShiftDecision {
        let decision = evaluateTopicShift(
            existingMessages: conversation.messages,
            activeTopicStartIndex: conversation.activeTopicStartIndex,
            incomingUserText: incomingUserText,
            now: now
        )

        if decision.shouldSplit {
            let clampedStart = max(0, min(conversation.activeTopicStartIndex, conversation.messages.count))
            let endIdx = conversation.messages.count - 1
            if endIdx >= clampedStart {
                let segmentSlice = Array(conversation.messages[clampedStart...endIdx])
                let segTitle = conversation.activeTopicTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty ?? deriveTopicTitle(from: segmentSlice.first(where: { $0.role == .user })?.content ?? "历史话题")
                let segSummary = buildCompactSegmentSummary(segmentSlice)
                let segment = PipiConversationTopicSegment(
                    title: segTitle,
                    summary: segSummary,
                    startMessageIndex: clampedStart,
                    endMessageIndex: endIdx,
                    startedAt: segmentSlice.first?.createdAt ?? conversation.createdAt,
                    endedAt: segmentSlice.last?.createdAt ?? conversation.updatedAt,
                    messageCount: segmentSlice.count
                )
                conversation.topicSegments.append(segment)
                // Keep archived metadata list tidy (max 40 segments retained in persisted state)
                if conversation.topicSegments.count > 40 {
                    conversation.topicSegments = Array(conversation.topicSegments.suffix(40))
                }
            }
            conversation.activeTopicStartIndex = conversation.messages.count
            conversation.activeTopicTitle = decision.newTopicTitle
            conversation.compactionGeneration += 1
        } else if (conversation.activeTopicTitle ?? "").isEmpty {
            conversation.activeTopicTitle = decision.newTopicTitle
        }

        return decision
    }

    /// Builds a strictly bounded LLM prompt history from an infinite-stream conversation:
    /// - Keeps ONLY the current active topic's recent verbatim turns (filtering stale errors)
    /// - Folds older turns of the active topic into a compact rolling capsule if active topic grows large
    /// - Optionally prepends a tiny 3-line index of recent archived topics for seamless continuity.
    public static func buildBoundedPromptHistory(
        messages: [PipiChatMessage],
        topicSegments: [PipiConversationTopicSegment],
        activeTopicStartIndex: Int,
        activeTopicTitle: String?,
        maxVerbatimMessages: Int = maxVerbatimActiveMessages,
        maxChars: Int = maxPromptHistoryChars
    ) -> PipiBoundedContextWindow {
        let clampedStart = max(0, min(activeTopicStartIndex, messages.count))
        let activeAll = Array(messages[clampedStart...])
        // Drop empty placeholders and prior-turn hard error dumps (keep the latest user message always)
        let lastIndex = activeAll.count - 1
        let activeClean: [PipiChatMessage] = activeAll.enumerated().compactMap { idx, msg in
            if idx == lastIndex { return msg }
            if msg.isError { return nil }
            if msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
            return msg
        }

        var foldedCount = 0
        var keptVerbatim: [PipiChatMessage]
        var activeFoldedCapsule: String? = nil

        if activeClean.count > maxVerbatimMessages {
            let cut = activeClean.count - maxVerbatimMessages
            let olderInTopic = Array(activeClean[..<cut])
            keptVerbatim = Array(activeClean[cut...])
            foldedCount = olderInTopic.count
            activeFoldedCapsule = buildCompactSegmentSummary(olderInTopic)
        } else {
            keptVerbatim = activeClean
        }

        // Enforce strict character budget by trimming oldest verbatim turns first (always keeping at least the last 2 turns)
        while keptVerbatim.count > 2,
              keptVerbatim.reduce(0, { $0 + $1.content.count }) > maxChars {
            let dropped = keptVerbatim.removeFirst()
            foldedCount += 1
            let line = compactMessageSnippet(dropped, maxLen: 100)
            if let existing = activeFoldedCapsule {
                activeFoldedCapsule = existing + "\n" + line
            } else {
                activeFoldedCapsule = line
            }
        }

        // Trim any overly long single older assistant message in verbatim window (never truncate the latest user message)
        for i in 0..<keptVerbatim.count {
            if i == keptVerbatim.count - 1 && keptVerbatim[i].role == .user { continue }
            if keptVerbatim[i].content.count > 2400 {
                keptVerbatim[i].content = String(keptVerbatim[i].content.prefix(2200)) + "\n…[历史长回复已折叠]"
            }
        }

        // Build ultra-compact rolling background context capsule (at most last 3 archived topics + active folded turns)
        var memoryLines: [String] = []
        let recentArchived = Array(topicSegments.suffix(maxArchivedTopicCapsules))
        if !recentArchived.isEmpty {
            let indexText = recentArchived.map { seg in
                let shortSummary = seg.summary.replacingOccurrences(of: "\n", with: " ").prefix(110)
                return "- 《\(seg.title)》(\(seg.messageCount)条): \(shortSummary)"
            }.joined(separator: "\n")
            memoryLines.append("[近期已归档话题摘要（仅作背景参考，除非用户主动提及否则专注当前话题）]\n\(indexText)")
        }
        if let activeFoldedCapsule, !activeFoldedCapsule.isEmpty {
            let capped = String(activeFoldedCapsule.prefix(900))
            memoryLines.append("[当前话题早期要点（已压缩 \(foldedCount) 条）]\n\(capped)")
        }

        var result: [PipiChatMessage] = []
        if !memoryLines.isEmpty {
            result.append(PipiChatMessage(
                role: .assistant,
                content: memoryLines.joined(separator: "\n\n"),
                engineLabel: "Topic Stream Context"
            ))
        }
        result.append(contentsOf: keptVerbatim)

        let totalChars = result.reduce(0) { $0 + $1.content.count }
        return PipiBoundedContextWindow(
            messages: result,
            activeTopicTitle: activeTopicTitle,
            archivedSegmentCount: topicSegments.count,
            foldedActiveMessageCount: foldedCount,
            estimatedChars: totalChars
        )
    }

    // MARK: - Helpers

    public static func deriveTopicTitle(from text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "新话题" }
        if let host = extractFirstURLHost(from: cleaned), cleaned.hasPrefix("http") {
            return host
        }
        return cleaned.count > 26 ? String(cleaned.prefix(26)) + "…" : cleaned
    }

    private static func buildCompactSegmentSummary(_ messages: [PipiChatMessage]) -> String {
        let meaningful = messages.filter { !$0.isError && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let picks = meaningful.count <= 4
            ? meaningful
            : Array(meaningful.prefix(2)) + Array(meaningful.suffix(2))
        return picks.map { compactMessageSnippet($0, maxLen: 95) }.joined(separator: " | ")
    }

    private static func compactMessageSnippet(_ msg: PipiChatMessage, maxLen: Int) -> String {
        let roleTag = msg.role == .user ? "U" : "A"
        let single = msg.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = single.count > maxLen ? String(single.prefix(maxLen)) + "…" : single
        return "\(roleTag): \(clipped)"
    }

    private static func isLikelyFollowUp(_ text: String, lower: String) -> Bool {
        if text.count <= 10 && extractFirstURLHost(from: text) == nil {
            return true
        }
        return followUpIndicators.contains(where: { lower.hasPrefix($0) || (text.count <= 36 && lower.contains($0)) })
    }

    private static func extractFirstURLHost(from text: String) -> String? {
        guard let range = text.range(of: #"https?://[^\s\)\]]+"#, options: .regularExpression),
              let url = URL(string: String(text[range])),
              let host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func extractSalientTokens(_ text: String) -> Set<String> {
        let lower = text.lowercased()
        var tokens = Set<String>()

        // Latin / numeric words (>= 3 chars)
        let latinParts = lower.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let stopWords: Set<String> = ["the", "and", "for", "with", "that", "this", "from", "have", "http", "https", "www", "com"]
        for w in latinParts where w.count >= 3 && !stopWords.contains(w) {
            if w.unicodeScalars.allSatisfy({ $0.isASCII }) {
                tokens.insert(w)
            }
        }

        // CJK character bigrams for zero-dependency Chinese topic overlap
        let cjkChars = lower.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.map { Character($0) }
        if cjkChars.count >= 2 {
            for i in 0..<(cjkChars.count - 1) {
                tokens.insert("\(cjkChars[i])\(cjkChars[i + 1])")
            }
        }

        return tokens
    }

    private static func jaccardOverlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty && !b.isEmpty else { return 0 }
        let inter = a.intersection(b).count
        let union = a.union(b).count
        return union > 0 ? Double(inter) / Double(union) : 0
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: raw) { return d }
        let basic = ISO8601DateFormatter()
        return basic.date(from: raw)
    }
}
