import Foundation

// MARK: - Entity Correlation Ledger & Goal-Driven Self-Evolution Engine

public enum PipiEntityLedgerStore {

    public static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("PiPiBot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("entity-ledger.json")
    }

    public static func load(from url: URL = defaultStorageURL()) -> [PipiEntityLedgerEntry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([PipiEntityLedgerEntry].self, from: data) else {
            return []
        }
        return entries
    }

    public static func save(_ entries: [PipiEntityLedgerEntry], to url: URL = defaultStorageURL()) {
        let capped = Array(entries.suffix(1000))
        if let data = try? JSONEncoder().encode(capped) {
            try? data.write(to: url, options: .atomic)
        }
    }

    @discardableResult
    public static func upsert(
        _ entry: PipiEntityLedgerEntry,
        in entries: inout [PipiEntityLedgerEntry]
    ) -> PipiEntityLedgerEntry {
        if let idx = entries.firstIndex(where: {
            $0.botId == entry.botId && $0.entityKey.caseInsensitiveCompare(entry.entityKey) == .orderedSame
        }) {
            var merged = entries[idx]
            merged.entityType = entry.entityType.isEmpty ? merged.entityType : entry.entityType
            merged.source = entry.source.isEmpty ? merged.source : entry.source
            merged.status = entry.status.isEmpty ? merged.status : entry.status
            merged.summary = entry.summary
            for (k, v) in entry.attributes {
                merged.attributes[k] = v
            }
            merged.updatedAt = entry.updatedAt
            entries[idx] = merged
            return merged
        } else {
            entries.append(entry)
            return entry
        }
    }

    public static func query(
        entries: [PipiEntityLedgerEntry],
        botId: String? = nil,
        entityKey: String? = nil,
        search: String? = nil,
        limit: Int = 20
    ) -> [PipiEntityLedgerEntry] {
        entries.filter { item in
            if let botId, !botId.isEmpty, item.botId != botId { return false }
            if let entityKey, !entityKey.isEmpty,
               !item.entityKey.localizedCaseInsensitiveContains(entityKey) { return false }
            if let search, !search.isEmpty {
                let hay = "\(item.entityKey) \(item.entityType) \(item.source) \(item.status) \(item.summary) \(item.attributes.values.joined(separator: " "))"
                if !hay.localizedCaseInsensitiveContains(search) { return false }
            }
            return true
        }
        .sorted { $0.updatedAt > $1.updatedAt }
        .prefix(max(1, limit))
        .map { $0 }
    }
}

public enum PipiSelfEvolutionEngine {

    /// Determine whether a Bot has accumulated enough failures or user corrections to warrant proposing a Blueprint EvolutionDiff.
    public static func shouldSuggestEvolution(
        botId: String,
        outcomes: [PipiRunOutcomeRecord],
        existingPendingProposals: [PipiBlueprintEvolutionProposal],
        failureThreshold: Int = 2
    ) -> Bool {
        if existingPendingProposals.contains(where: { $0.botId == botId && $0.status == .pending }) {
            return false
        }
        let recent = outcomes.filter { $0.botId == botId }.suffix(10)
        let issueCount = recent.filter { !$0.succeeded || ($0.userCorrection?.isEmpty == false) }.count
        return issueCount >= max(1, failureThreshold)
    }

    /// Build a structured Blueprint EvolutionDiff proposal comparing the previous blueprint to a proposed upgrade.
    public static func buildProposal(
        persona: PipiBotPersona,
        proposedGoal: String? = nil,
        proposedSteps: [String]? = nil,
        addedRules: [String] = [],
        addedVerification: [String] = [],
        addedEscalation: [String] = [],
        addedFeedbackSources: [String] = [],
        addedEdgeCases: [PipiBlueprintEdgeCase] = [],
        rationale: String,
        lang: PipiResolvedLanguage = .zhHans
    ) -> PipiBlueprintEvolutionProposal {
        let current = persona.automationBlueprint ?? PipiBotAutomationBlueprint(goal: persona.role(lang))
        var next = current
        next.blueprintVersion = current.blueprintVersion + 1
        next.updatedAt = ISO8601DateFormatter().string(from: Date())
        next.lastReviewedAt = next.updatedAt

        var diffs: [EvolutionDiffItem] = []
        let targetFile = "bots/\(persona.id)/blueprint.md"

        if let proposedGoal = proposedGoal?.trimmingCharacters(in: .whitespacesAndNewlines),
           !proposedGoal.isEmpty, proposedGoal != current.goal {
            next.goal = proposedGoal
            diffs.append(EvolutionDiffItem(
                diffId: "diff_goal_\(UUID().uuidString.prefix(6).lowercased())",
                operation: current.goal.isEmpty ? .add : .supersede,
                targetFile: targetFile,
                domain: .workContext,
                title: "Goal",
                previousValue: current.goal.isEmpty ? nil : current.goal,
                proposedValue: proposedGoal,
                confidence: 0.9,
                evidenceSummary: rationale
            ))
        }

        if let proposedSteps, !proposedSteps.isEmpty, proposedSteps != current.processSteps {
            next.processSteps = proposedSteps
            diffs.append(EvolutionDiffItem(
                diffId: "diff_steps_\(UUID().uuidString.prefix(6).lowercased())",
                operation: current.processSteps.isEmpty ? .add : .supersede,
                targetFile: targetFile,
                domain: .workContext,
                title: "Process Steps",
                previousValue: current.processSteps.isEmpty ? nil : current.processSteps.joined(separator: " → "),
                proposedValue: proposedSteps.joined(separator: " → "),
                confidence: 0.88,
                evidenceSummary: rationale
            ))
        }

        for rule in addedRules where !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !next.sourceOfTruthRules.contains(rule) {
            next.sourceOfTruthRules.append(rule)
            diffs.append(EvolutionDiffItem(
                diffId: "diff_rule_\(UUID().uuidString.prefix(6).lowercased())",
                operation: .add,
                targetFile: targetFile,
                domain: .workContext,
                title: "Source-of-Truth Rule",
                previousValue: nil,
                proposedValue: rule,
                confidence: 0.86,
                evidenceSummary: rationale
            ))
        }

        for check in addedVerification where !check.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !next.verificationCriteria.contains(check) {
            next.verificationCriteria.append(check)
            diffs.append(EvolutionDiffItem(
                diffId: "diff_verify_\(UUID().uuidString.prefix(6).lowercased())",
                operation: .add,
                targetFile: targetFile,
                domain: .workContext,
                title: "Verification Criterion",
                previousValue: nil,
                proposedValue: check,
                confidence: 0.9,
                evidenceSummary: rationale
            ))
        }

        for esc in addedEscalation where !esc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !next.escalationRules.contains(esc) {
            next.escalationRules.append(esc)
            diffs.append(EvolutionDiffItem(
                diffId: "diff_esc_\(UUID().uuidString.prefix(6).lowercased())",
                operation: .add,
                targetFile: targetFile,
                domain: .workContext,
                title: "Escalation Rule",
                previousValue: nil,
                proposedValue: esc,
                confidence: 0.85,
                evidenceSummary: rationale
            ))
        }

        for fb in addedFeedbackSources where !fb.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !next.feedbackSources.contains(fb) {
            next.feedbackSources.append(fb)
            diffs.append(EvolutionDiffItem(
                diffId: "diff_fb_\(UUID().uuidString.prefix(6).lowercased())",
                operation: .add,
                targetFile: targetFile,
                domain: .workContext,
                title: "Feedback Source",
                previousValue: nil,
                proposedValue: fb,
                confidence: 0.84,
                evidenceSummary: rationale
            ))
        }

        for edge in addedEdgeCases {
            next.dryRunExamples.append(edge)
            diffs.append(EvolutionDiffItem(
                diffId: "diff_edge_\(UUID().uuidString.prefix(6).lowercased())",
                operation: .add,
                targetFile: targetFile,
                domain: .workContext,
                title: "Edge-Case Rule",
                previousValue: nil,
                proposedValue: "\(edge.scenario) → \(edge.expectedBehavior)",
                confidence: 0.87,
                evidenceSummary: rationale
            ))
        }

        if diffs.isEmpty {
            diffs.append(EvolutionDiffItem(
                diffId: "diff_review_\(UUID().uuidString.prefix(6).lowercased())",
                operation: .updateSoul,
                targetFile: targetFile,
                domain: .workContext,
                title: "Blueprint Review",
                previousValue: "v\(current.blueprintVersion)",
                proposedValue: "v\(next.blueprintVersion): \(rationale)",
                confidence: 0.82,
                evidenceSummary: rationale
            ))
        }

        return PipiBlueprintEvolutionProposal(
            botId: persona.id,
            botName: persona.name(lang),
            goalSummary: next.goal.isEmpty ? persona.role(lang) : next.goal,
            rationale: rationale,
            diffs: diffs,
            proposedBlueprint: next,
            previousBlueprint: persona.automationBlueprint,
            status: .pending
        )
    }

    /// Generate a heuristic self-review proposal directly from recent failure/correction outcome records.
    public static func synthesizeProposalFromOutcomes(
        persona: PipiBotPersona,
        outcomes: [PipiRunOutcomeRecord],
        lang: PipiResolvedLanguage = .zhHans
    ) -> PipiBlueprintEvolutionProposal {
        let relevant = outcomes.filter { $0.botId == persona.id && (!$0.succeeded || ($0.userCorrection?.isEmpty == false)) }.suffix(5)
        var newChecks: [String] = []
        var newEdges: [PipiBlueprintEdgeCase] = []
        for rec in relevant {
            if let correction = rec.userCorrection, !correction.isEmpty {
                newChecks.append(correction)
                newEdges.append(PipiBlueprintEdgeCase(
                    scenario: rec.taskTitle,
                    expectedBehavior: correction,
                    verificationCheck: rec.verificationNotes
                ))
            } else if !rec.verificationNotes.isEmpty {
                newChecks.append("Verify before completion: \(rec.verificationNotes)")
            }
        }
        let rationale = lang == .zhHans
            ? "基于最近 \(relevant.count) 次执行异常/人工纠偏，对照原始目标自动提炼的蓝图验收与边界规则补丁。"
            : "Synthesized from \(relevant.count) recent failed or user-corrected runs against the original Goal."
        return buildProposal(
            persona: persona,
            addedVerification: newChecks,
            addedEdgeCases: newEdges,
            rationale: rationale,
            lang: lang
        )
    }

    /// Apply an approved proposal onto a Bot persona (mutating blueprint & recording learned upgrade).
    public static func applyApprovedProposal(
        _ proposal: inout PipiBlueprintEvolutionProposal,
        to persona: inout PipiBotPersona
    ) {
        proposal.previousBlueprint = persona.automationBlueprint
        persona.automationBlueprint = proposal.proposedBlueprint
        proposal.status = .approved
        proposal.resolvedAt = ISO8601DateFormatter().string(from: Date())
    }

    /// Roll back a previously approved proposal to restore the prior blueprint snapshot.
    public static func rollbackProposal(
        _ proposal: inout PipiBlueprintEvolutionProposal,
        on persona: inout PipiBotPersona
    ) {
        persona.automationBlueprint = proposal.previousBlueprint
        proposal.status = .rolledBack
        proposal.resolvedAt = ISO8601DateFormatter().string(from: Date())
    }
}
