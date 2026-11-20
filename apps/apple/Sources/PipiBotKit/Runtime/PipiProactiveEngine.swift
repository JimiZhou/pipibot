// PiPiBot — Clean-room MIT implementation.
// Wave 2 (#03): Native Proactive Anti-Fatigue Guardrails + `Prepare` Pre-Briefing +
// Nightly `Clue -> Rule` Implicit Self-Learning with Versioned Rollback.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

import CryptoKit
import Foundation

// MARK: - 1. Guardrail Policy & Signal Models

public struct PipiProactiveGuardrailPolicy: Codable, Equatable, Sendable {
    public var quietHoursEnabled: Bool
    public var quietHoursStart: Int // 0...23 (default 22)
    public var quietHoursEnd: Int // 0...23 (default 8)
    public var maxDailyNotifications: Int // default 5
    public var chatSilenceSeconds: Int // default 180 (3 minutes)
    public var prepareLeadMinutes: Int // default 120 (2 hours)
    public var enabledSources: [PipiProactiveSourceKind]

    public init(
        quietHoursEnabled: Bool = true,
        quietHoursStart: Int = 22,
        quietHoursEnd: Int = 8,
        maxDailyNotifications: Int = 5,
        chatSilenceSeconds: Int = 180,
        prepareLeadMinutes: Int = 120,
        enabledSources: [PipiProactiveSourceKind] = PipiProactiveSourceKind.allCases
    ) {
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHoursStart = ((quietHoursStart % 24) + 24) % 24
        self.quietHoursEnd = ((quietHoursEnd % 24) + 24) % 24
        self.maxDailyNotifications = max(0, maxDailyNotifications)
        self.chatSilenceSeconds = max(0, chatSilenceSeconds)
        self.prepareLeadMinutes = max(5, prepareLeadMinutes)
        self.enabledSources = enabledSources
    }
}

public struct PipiProactiveSignal: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var source: PipiProactiveSourceKind
    public var kind: String
    public var matter: String
    public var title: String
    public var content: String
    public var dueAtIso: String?
    public var workspacePath: String?
    public var isUrgent: Bool
    public var supportsPrepare: Bool?

    public init(
        id: String = "sig_\(UUID().uuidString.prefix(8).lowercased())",
        source: PipiProactiveSourceKind,
        kind: String,
        matter: String,
        title: String,
        content: String,
        dueAtIso: String? = nil,
        workspacePath: String? = nil,
        isUrgent: Bool = false,
        supportsPrepare: Bool? = nil
    ) {
        self.id = id
        self.source = source
        self.kind = kind
        self.matter = matter
        self.title = title
        self.content = content
        self.dueAtIso = dueAtIso
        self.workspacePath = workspacePath
        self.isUrgent = isUrgent
        self.supportsPrepare = supportsPrepare
    }
}

public struct PipiPreparedBriefing: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let signalKey: String
    public var source: PipiProactiveSourceKind
    public var matter: String
    public var kind: String
    public var title: String
    public var summary: String
    public var bulletPoints: [String]
    public var relatedWikiPageIds: [String]
    public var relatedWikiTitles: [String]
    public var dueAtIso: String?
    public let createdAt: String
    public var decision: PipiProactiveActionDecision
    public var feedback: PipiProactiveFeedbackSignal?

    public init(
        id: String = "brf_\(UUID().uuidString.prefix(8).lowercased())",
        signalKey: String,
        source: PipiProactiveSourceKind,
        matter: String,
        kind: String,
        title: String,
        summary: String,
        bulletPoints: [String],
        relatedWikiPageIds: [String] = [],
        relatedWikiTitles: [String] = [],
        dueAtIso: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        decision: PipiProactiveActionDecision,
        feedback: PipiProactiveFeedbackSignal? = nil
    ) {
        self.id = id
        self.signalKey = signalKey
        self.source = source
        self.matter = matter
        self.kind = kind
        self.title = title
        self.summary = summary
        self.bulletPoints = bulletPoints
        self.relatedWikiPageIds = relatedWikiPageIds
        self.relatedWikiTitles = relatedWikiTitles
        self.dueAtIso = dueAtIso
        self.createdAt = createdAt
        self.decision = decision
        self.feedback = feedback
    }
}

public enum PipiProactiveDeferReason: String, Codable, Sendable, Equatable {
    case duplicateToday = "duplicate_today"
    case quietHours = "quiet_hours"
    case dailyCapReached = "daily_cap_reached"
    case chatActiveSilence = "chat_active_silence"
    case sourceDisabled = "source_disabled"
    case mutedByRule = "muted_by_rule"
}

public struct PipiProactiveEvaluationResult: Equatable, Sendable {
    public let signalKey: String
    public let decision: PipiProactiveActionDecision
    public let deferredReason: PipiProactiveDeferReason?
    public let matchedRuleId: String?
    public let notifiedUser: Bool
    public let briefing: PipiPreparedBriefing?
}

public enum PipiProactiveLeaning: String, Codable, CaseIterable, Sendable, Equatable {
    case remindDirectly = "remind_directly"
    case trackForFollowUp = "track_for_follow_up"
    case staySilent = "stay_silent"

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .remindDirectly: return lang == .zhHans ? "优先提醒" : "Prioritize"
        case .trackForFollowUp: return lang == .zhHans ? "静默跟进" : "Track Quietly"
        case .staySilent: return lang == .zhHans ? "保持静音" : "Stay Silent"
        }
    }
}

public struct PipiProactiveClue: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(matter.lowercased())::\(kind.lowercased())" }
    public var matter: String
    public var kind: String
    public var leaning: PipiProactiveLeaning
    public var seen: Int
    public var lastSeenDate: String // YYYY-MM-DD

    public init(
        matter: String,
        kind: String,
        leaning: PipiProactiveLeaning,
        seen: Int,
        lastSeenDate: String
    ) {
        self.matter = matter
        self.kind = kind
        self.leaning = leaning
        self.seen = max(1, seen)
        self.lastSeenDate = lastSeenDate
    }
}

public struct PipiLearnedProactiveRule: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var matter: String
    public var kind: String
    public var leaning: PipiProactiveLeaning
    public var text: String
    public var enabled: Bool
    public let createdAt: String

    public init(
        id: String = "prule_\(UUID().uuidString.prefix(8).lowercased())",
        matter: String,
        kind: String,
        leaning: PipiProactiveLeaning,
        text: String,
        enabled: Bool = true,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.matter = matter
        self.kind = kind
        self.leaning = leaning
        self.text = text
        self.enabled = enabled
        self.createdAt = createdAt
    }
}

public struct PipiProactiveGuidelineSnapshot: Codable, Identifiable, Equatable, Sendable {
    public var id: Int { version }
    public let version: Int
    public let rules: [PipiLearnedProactiveRule]
    public let clues: [PipiProactiveClue]
    public let changeNote: String
    public let createdAt: String
}

public struct PipiProactiveFeedbackRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let briefingId: String
    public let source: PipiProactiveSourceKind
    public let matter: String
    public let kind: String
    public let signal: PipiProactiveFeedbackSignal
    public let recordedAt: String
}

public struct PipiNightlyDreamResult: Equatable, Sendable {
    public let previousVersion: Int
    public let newVersion: Int
    public let promotedRules: [PipiLearnedProactiveRule]
    public let activeCluesCount: Int
    public let totalRulesCount: Int
    public let changeNote: String
}

public struct PipiProactivePersistedState: Codable, Equatable, Sendable {
    public var policy: PipiProactiveGuardrailPolicy
    public var guidelineVersion: Int
    public var rules: [PipiLearnedProactiveRule]
    public var clues: [PipiProactiveClue]
    public var history: [PipiProactiveGuidelineSnapshot]
    public var briefings: [PipiPreparedBriefing]
    public var pendingFeedback: [PipiProactiveFeedbackRecord]
    public var lastDreamDateYmd: String?

    public init(
        policy: PipiProactiveGuardrailPolicy = PipiProactiveGuardrailPolicy(),
        guidelineVersion: Int = 1,
        rules: [PipiLearnedProactiveRule] = [],
        clues: [PipiProactiveClue] = [],
        history: [PipiProactiveGuidelineSnapshot] = [],
        briefings: [PipiPreparedBriefing] = [],
        pendingFeedback: [PipiProactiveFeedbackRecord] = [],
        lastDreamDateYmd: String? = nil
    ) {
        self.policy = policy
        self.guidelineVersion = guidelineVersion
        self.rules = rules
        self.clues = clues
        self.history = history
        self.briefings = briefings
        self.pendingFeedback = pendingFeedback
        self.lastDreamDateYmd = lastDreamDateYmd
    }
}

// MARK: - 2. PipiProactiveEngine

@MainActor
public final class PipiProactiveEngine {
    public static let clueRetentionDays: Int = 14
    public static let maxSpecificRules: Int = 20
    public static let maxClues: Int = 40
    public static let promotionSeenThreshold: Int = 2

    public var policy: PipiProactiveGuardrailPolicy
    public private(set) var guidelineVersion: Int = 1
    public private(set) var rules: [PipiLearnedProactiveRule] = []
    public private(set) var clues: [PipiProactiveClue] = []
    public private(set) var history: [PipiProactiveGuidelineSnapshot] = []
    public private(set) var briefings: [PipiPreparedBriefing] = []
    public private(set) var pendingFeedback: [PipiProactiveFeedbackRecord] = []
    public private(set) var lastDreamDateYmd: String?

    private weak var wikiStore: PipiPersonalWikiStore?
    private var seenKeysByDay: [String: Set<String>] = [:]
    private var notificationsByDay: [String: Int] = [:]
    private var lastUserChatActivityAt: Date?

    public init(
        policy: PipiProactiveGuardrailPolicy = PipiProactiveGuardrailPolicy(),
        wikiStore: PipiPersonalWikiStore? = nil
    ) {
        self.policy = policy
        self.wikiStore = wikiStore
        self.history = [
            PipiProactiveGuidelineSnapshot(
                version: 1,
                rules: [],
                clues: [],
                changeNote: "Initial proactive guideline",
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
        ]
    }

    public func attachWikiStore(_ store: PipiPersonalWikiStore?) {
        self.wikiStore = store
    }

    public func exportPersistedState() -> PipiProactivePersistedState {
        PipiProactivePersistedState(
            policy: policy,
            guidelineVersion: guidelineVersion,
            rules: rules,
            clues: clues,
            history: Array(history.suffix(20)),
            briefings: Array(briefings.prefix(40)),
            pendingFeedback: Array(pendingFeedback.suffix(60)),
            lastDreamDateYmd: lastDreamDateYmd
        )
    }

    public func restorePersistedState(_ state: PipiProactivePersistedState) {
        self.policy = state.policy
        self.guidelineVersion = max(1, state.guidelineVersion)
        self.rules = Array(state.rules.prefix(Self.maxSpecificRules))
        self.clues = Array(state.clues.prefix(Self.maxClues))
        self.history = state.history.isEmpty
            ? [PipiProactiveGuidelineSnapshot(
                version: guidelineVersion,
                rules: rules,
                clues: clues,
                changeNote: "Restored proactive guideline",
                createdAt: ISO8601DateFormatter().string(from: Date())
            )]
            : state.history
        self.briefings = state.briefings
        self.pendingFeedback = state.pendingFeedback
        self.lastDreamDateYmd = state.lastDreamDateYmd
    }

    public func recordUserChatActivity(at date: Date = Date()) {
        if let existing = lastUserChatActivityAt, existing > date { return }
        lastUserChatActivityAt = date
    }

    public static func computeDailySignalKey(source: PipiProactiveSourceKind, content: String, ymd: String) -> String {
        let payload = "\(source.rawValue)\u{0000}\(content.trimmingCharacters(in: .whitespacesAndNewlines))\u{0000}\(ymd)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    public static func formatLocalYmd(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 2026, comps.month ?? 1, comps.day ?? 1)
    }

    public static func isHourWithinQuietWindow(hour: Int, start: Int, end: Int) -> Bool {
        let h = ((hour % 24) + 24) % 24
        let s = ((start % 24) + 24) % 24
        let e = ((end % 24) + 24) % 24
        if s == e { return false }
        if s < e { return h >= s && h < e }
        return h >= s || h < e
    }

    // MARK: - Evaluate Native Signal + Anti-Fatigue + Read-Only Prepare

    @discardableResult
    public func evaluateSignal(
        _ signal: PipiProactiveSignal,
        now: Date = Date(),
        localHourOverride: Int? = nil
    ) -> PipiProactiveEvaluationResult {
        let ymd = Self.formatLocalYmd(now)
        let localHour = localHourOverride ?? Calendar.current.component(.hour, from: now)
        let signalKey = Self.computeDailySignalKey(
            source: signal.source,
            content: "\(signal.matter)::\(signal.title)::\(signal.content)",
            ymd: ymd
        )

        guard policy.enabledSources.contains(signal.source) else {
            return PipiProactiveEvaluationResult(
                signalKey: signalKey,
                decision: .staySilent,
                deferredReason: .sourceDisabled,
                matchedRuleId: nil,
                notifiedUser: false,
                briefing: nil
            )
        }

        if seenKeysByDay[ymd, default: []].contains(signalKey) {
            return PipiProactiveEvaluationResult(
                signalKey: signalKey,
                decision: .staySilent,
                deferredReason: .duplicateToday,
                matchedRuleId: nil,
                notifiedUser: false,
                briefing: nil
            )
        }

        let matchedRule = findMatchingRule(matter: signal.matter, kind: signal.kind)
        if let matchedRule, matchedRule.leaning == .staySilent {
            seenKeysByDay[ymd, default: []].insert(signalKey)
            return PipiProactiveEvaluationResult(
                signalKey: signalKey,
                decision: .staySilent,
                deferredReason: .mutedByRule,
                matchedRuleId: matchedRule.id,
                notifiedUser: false,
                briefing: nil
            )
        }

        let inQuietHours = policy.quietHoursEnabled
            && Self.isHourWithinQuietWindow(hour: localHour, start: policy.quietHoursStart, end: policy.quietHoursEnd)
        if inQuietHours && !signal.isUrgent {
            return PipiProactiveEvaluationResult(
                signalKey: signalKey,
                decision: .staySilent,
                deferredReason: .quietHours,
                matchedRuleId: matchedRule?.id,
                notifiedUser: false,
                briefing: nil
            )
        }

        let sentToday = notificationsByDay[ymd, default: 0]
        if sentToday >= policy.maxDailyNotifications {
            return PipiProactiveEvaluationResult(
                signalKey: signalKey,
                decision: .trackForFollowUp,
                deferredReason: .dailyCapReached,
                matchedRuleId: matchedRule?.id,
                notifiedUser: false,
                briefing: nil
            )
        }

        if let lastChat = lastUserChatActivityAt,
           now.timeIntervalSince(lastChat) < Double(policy.chatSilenceSeconds),
           !signal.isUrgent {
            return PipiProactiveEvaluationResult(
                signalKey: signalKey,
                decision: .trackForFollowUp,
                deferredReason: .chatActiveSilence,
                matchedRuleId: matchedRule?.id,
                notifiedUser: false,
                briefing: nil
            )
        }

        let decision: PipiProactiveActionDecision
        if matchedRule?.leaning == .trackForFollowUp {
            decision = .trackForFollowUp
        } else if shouldPrepareBriefing(for: signal, now: now) {
            decision = .prepareBriefing
        } else {
            decision = .remindDirectly
        }

        let briefing = buildPreparedBriefing(signal: signal, signalKey: signalKey, decision: decision, now: now)
        briefings.insert(briefing, at: 0)
        if briefings.count > 60 {
            briefings = Array(briefings.prefix(60))
        }
        seenKeysByDay[ymd, default: []].insert(signalKey)

        let notifiedUser = (decision == .remindDirectly || decision == .prepareBriefing)
        if notifiedUser {
            notificationsByDay[ymd, default: 0] += 1
        }

        return PipiProactiveEvaluationResult(
            signalKey: signalKey,
            decision: decision,
            deferredReason: nil,
            matchedRuleId: matchedRule?.id,
            notifiedUser: notifiedUser,
            briefing: briefing
        )
    }

    private func findMatchingRule(matter: String, kind: String) -> PipiLearnedProactiveRule? {
        let m = matter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let k = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return rules.first { rule in
            guard rule.enabled else { return false }
            let rm = rule.matter.lowercased()
            let matterMatch = rm == m || m.contains(rm) || rm.contains(m)
            let kindMatch = rule.kind.isEmpty || rule.kind.lowercased() == k
            return matterMatch && kindMatch
        }
    }

    private func shouldPrepareBriefing(for signal: PipiProactiveSignal, now: Date) -> Bool {
        if let explicit = signal.supportsPrepare { return explicit }
        guard signal.source == .calendarEventKit || signal.source == .gitWorkspace else { return false }
        guard let dueStr = signal.dueAtIso,
              let dueDate = ISO8601DateFormatter().date(from: dueStr) else {
            return true
        }
        let minsUntil = dueDate.timeIntervalSince(now) / 60.0
        return minsUntil >= -15 && minsUntil <= Double(policy.prepareLeadMinutes)
    }

    private func buildPreparedBriefing(
        signal: PipiProactiveSignal,
        signalKey: String,
        decision: PipiProactiveActionDecision,
        now: Date
    ) -> PipiPreparedBriefing {
        var wikiIds: [String] = []
        var wikiTitles: [String] = []
        var bullets: [String] = [signal.content.trimmingCharacters(in: .whitespacesAndNewlines)]

        if let wikiStore {
            let searchRes = wikiStore.search(PipiWikiSearchOptions(
                query: "\(signal.title) \(signal.matter)",
                alternates: [signal.matter, signal.title],
                scope: .all,
                limit: 4,
                factLimit: 4
            ))
            for s in searchRes.summaries.prefix(3) {
                wikiIds.append(s.pageId)
                wikiTitles.append(s.title)
                bullets.append("Wiki [\(s.category.rawValue)] \(s.title): \(s.summary)")
            }
            for f in searchRes.facts.prefix(2) {
                bullets.append("Fact: \(f.factText)")
            }
        }

        let summaryText: String
        if decision == .prepareBriefing {
            summaryText = wikiTitles.isEmpty
                ? signal.content.trimmingCharacters(in: .whitespacesAndNewlines)
                : "Prepared read-only brief for \(signal.title) (\(wikiTitles.count) Wiki links: \(wikiTitles.joined(separator: ", ")))"
        } else {
            summaryText = String(signal.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(180))
        }

        return PipiPreparedBriefing(
            signalKey: signalKey,
            source: signal.source,
            matter: signal.matter.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: signal.kind.trimmingCharacters(in: .whitespacesAndNewlines),
            title: signal.title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summaryText,
            bulletPoints: bullets,
            relatedWikiPageIds: wikiIds,
            relatedWikiTitles: wikiTitles,
            dueAtIso: signal.dueAtIso,
            createdAt: ISO8601DateFormatter().string(from: now),
            decision: decision
        )
    }

    // MARK: - User Feedback & Nightly `Clue -> Rule` Dreaming + Rollback

    @discardableResult
    public func recordFeedback(
        briefingId: String,
        signal: PipiProactiveFeedbackSignal,
        now: Date = Date()
    ) -> PipiProactiveFeedbackRecord? {
        guard let idx = briefings.firstIndex(where: { $0.id == briefingId }) else { return nil }
        briefings[idx].feedback = signal
        let item = briefings[idx]
        let rec = PipiProactiveFeedbackRecord(
            id: "fb_\(UUID().uuidString.prefix(8).lowercased())",
            briefingId: item.id,
            source: item.source,
            matter: item.matter,
            kind: item.kind,
            signal: signal,
            recordedAt: ISO8601DateFormatter().string(from: now)
        )
        pendingFeedback.append(rec)
        return rec
    }

    public func toggleRule(id: String, enabled: Bool) {
        guard let idx = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[idx].enabled = enabled
    }

    public func deleteRule(id: String) {
        rules.removeAll { $0.id == id }
    }

    @discardableResult
    public func runNightlyDreaming(
        todayYmd: String? = nil,
        removedRuleIds: [String] = [],
        extraFeedback: [PipiProactiveFeedbackRecord] = []
    ) -> PipiNightlyDreamResult {
        let today = todayYmd ?? Self.formatLocalYmd(Date())
        let prevVersion = guidelineVersion
        let batch = pendingFeedback + extraFeedback
        pendingFeedback.removeAll()

        // 1. Retain clues within 14-day window
        var clueMap: [String: PipiProactiveClue] = [:]
        for clue in clues {
            if Self.daysBetween(earlierYmd: clue.lastSeenDate, laterYmd: today) <= Self.clueRetentionDays {
                clueMap[clue.id] = clue
            }
        }

        // 2. Fold feedback records into clues
        for fb in batch {
            let key = "\(fb.matter.lowercased())::\(fb.kind.lowercased())"
            let leaning = Self.leaning(for: fb.signal)
            if var existing = clueMap[key], existing.leaning == leaning {
                existing.seen += 1
                existing.lastSeenDate = today
                clueMap[key] = existing
            } else {
                clueMap[key] = PipiProactiveClue(
                    matter: fb.matter,
                    kind: fb.kind,
                    leaning: leaning,
                    seen: 1,
                    lastSeenDate: today
                )
            }
        }

        // 3. Non-destructive rule retention (remove only explicitly named IDs)
        let removedSet = Set(removedRuleIds)
        var nextRules = rules.filter { !removedSet.contains($0.id) }
        var promoted: [PipiLearnedProactiveRule] = []
        var remainingClues: [PipiProactiveClue] = []

        // 4. Promote clues with seen >= 2 into active rules (max 20)
        for clue in clueMap.values {
            if clue.seen >= Self.promotionSeenThreshold {
                let text = Self.formatRuleText(clue)
                if let existingIdx = nextRules.firstIndex(where: {
                    $0.matter.lowercased() == clue.matter.lowercased() &&
                    $0.kind.lowercased() == clue.kind.lowercased()
                }) {
                    let updated = PipiLearnedProactiveRule(
                        id: nextRules[existingIdx].id,
                        matter: clue.matter,
                        kind: clue.kind,
                        leaning: clue.leaning,
                        text: text,
                        enabled: true,
                        createdAt: ISO8601DateFormatter().string(from: Date())
                    )
                    nextRules[existingIdx] = updated
                    promoted.append(updated)
                } else if nextRules.count < Self.maxSpecificRules {
                    let created = PipiLearnedProactiveRule(
                        matter: clue.matter,
                        kind: clue.kind,
                        leaning: clue.leaning,
                        text: text,
                        enabled: true
                    )
                    nextRules.insert(created, at: 0)
                    promoted.append(created)
                }
            } else {
                remainingClues.append(clue)
            }
        }

        self.rules = Array(nextRules.prefix(Self.maxSpecificRules))
        self.clues = Array(remainingClues.sorted { $0.lastSeenDate > $1.lastSeenDate }.prefix(Self.maxClues))
        self.guidelineVersion += 1
        self.lastDreamDateYmd = today

        let changeNote = promoted.isEmpty
            ? "Updated \(clues.count) active clue(s) on \(today)."
            : "Promoted \(promoted.count) rule(s) from repeated clues on \(today)."

        history.append(PipiProactiveGuidelineSnapshot(
            version: guidelineVersion,
            rules: rules,
            clues: clues,
            changeNote: changeNote,
            createdAt: ISO8601DateFormatter().string(from: Date())
        ))
        if history.count > 20 {
            history = Array(history.suffix(20))
        }

        return PipiNightlyDreamResult(
            previousVersion: prevVersion,
            newVersion: guidelineVersion,
            promotedRules: promoted,
            activeCluesCount: clues.count,
            totalRulesCount: rules.count,
            changeNote: changeNote
        )
    }

    @discardableResult
    public func rollbackGuideline(toVersion targetVersion: Int) -> Bool {
        guard let snap = history.first(where: { $0.version == targetVersion }) else { return false }
        self.rules = snap.rules
        self.clues = snap.clues
        self.guidelineVersion = snap.version
        return true
    }

    private static func leaning(for signal: PipiProactiveFeedbackSignal) -> PipiProactiveLeaning {
        switch signal {
        case .acted, .thanked:
            return .remindDirectly
        case .snoozed, .ignored:
            return .trackForFollowUp
        case .dismissed, .mutedTopic:
            return .staySilent
        }
    }

    private static func formatRuleText(_ clue: PipiProactiveClue) -> String {
        switch clue.leaning {
        case .staySilent:
            return "Stay silent for \"\(clue.matter)\" (\(clue.kind)) unless explicitly requested."
        case .trackForFollowUp:
            return "Track \"\(clue.matter)\" (\(clue.kind)) quietly without interrupting."
        case .remindDirectly:
            return "Prioritize reminding and preparing context for \"\(clue.matter)\" (\(clue.kind))."
        }
    }

    private static func daysBetween(earlierYmd: String, laterYmd: String) -> Int {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyy-MM-dd"
        guard let a = fmt.date(from: earlierYmd), let b = fmt.date(from: laterYmd) else { return 0 }
        return Int(b.timeIntervalSince(a) / 86_400.0)
    }
}
