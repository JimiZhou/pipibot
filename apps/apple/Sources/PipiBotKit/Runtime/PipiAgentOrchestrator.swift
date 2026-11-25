// PiPiBot — Clean-room MIT implementation.
// Multi-Agent DAG Orchestrator V2 (T3 Code + OMP `task` Subagents + Claude Agent Teams parity).
// - Structured DAG task graph with Kahn topological wave scheduling & cycle detection
// - Cross-provider / cross-harness handoff & fallback chains
// - Automatic Git Worktree isolation when >= 2 writable workers share a parallel wave
// - Selective Shared Blackboard context bus (downstream tasks only receive declared `dependsOn` outputs)
// - Built-in OMP-style role presets (scout, coder, reviewer, researcher, architect, verifier, general)
// - Real structured verdict extraction (APPROVE/REVISE, DONE/CONTINUE, SELECT) + Supervisor final synthesis

import Foundation

public enum PipiSubagentRolePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case scout
    case coder
    case reviewer
    case researcher
    case architect
    case verifier
    case general

    public var id: String { rawValue }

    public var isReadOnlyDefault: Bool {
        switch self {
        case .scout, .reviewer, .researcher, .architect, .verifier:
            return true
        case .coder, .general:
            return false
        }
    }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .scout: return lang == .zhHans ? "侦察" : "Scout"
        case .coder: return lang == .zhHans ? "编码" : "Coder"
        case .reviewer: return lang == .zhHans ? "审查" : "Reviewer"
        case .researcher: return lang == .zhHans ? "调研" : "Researcher"
        case .architect: return lang == .zhHans ? "架构" : "Architect"
        case .verifier: return lang == .zhHans ? "验证" : "Verifier"
        case .general: return lang == .zhHans ? "协作" : "Specialist"
        }
    }

    public var systemGuidance: String {
        switch self {
        case .scout:
            return "You are a fast read-only Scout subagent. Inspect files, symbols, and call graphs concisely; return exact paths, line numbers, and key invariants without editing files."
        case .researcher:
            return "You are a Research subagent. Gather concrete evidence, compare trade-offs in structured tables, and summarize clearly."
        case .architect:
            return "You are an Architect subagent. Produce clear interfaces, invariants, and inline SVG or Mermaid diagrams illustrating dataflow and boundaries."
        case .coder:
            return "You are a Coder subagent working in a scoped workspace or isolated Git worktree. Implement clean changes and verify with build/tests before reporting."
        case .reviewer:
            return "You are an Adversarial Code Reviewer subagent. Audit diffs for regressions, edge cases, and missing tests. End with VERDICT: APPROVE or VERDICT: REVISE."
        case .verifier:
            return "You are a Verification Gate subagent. Validate outputs against the task goal. End with VERDICT: APPROVE or VERDICT: REVISE."
        case .general:
            return "You are a focused Specialist subagent. Complete your assigned subtask end-to-end and return a crisp summary."
        }
    }
}

public struct PipiOrchestrationTaskNode: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var prompt: String
    public var rolePreset: PipiSubagentRolePreset
    public var actorId: String?
    public var harness: String?
    public var modelId: String?
    public var dependsOn: [String]
    public var isolateWorktree: Bool?
    public var readOnly: Bool?
    public var maxRetries: Int?
    public var fallbackHarnesses: [String]?
    public var verifyWithActorId: String?

    public init(
        id: String,
        title: String,
        prompt: String,
        rolePreset: PipiSubagentRolePreset = .general,
        actorId: String? = nil,
        harness: String? = nil,
        modelId: String? = nil,
        dependsOn: [String] = [],
        isolateWorktree: Bool? = nil,
        readOnly: Bool? = nil,
        maxRetries: Int? = nil,
        fallbackHarnesses: [String]? = nil,
        verifyWithActorId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.rolePreset = rolePreset
        self.actorId = actorId
        self.harness = harness
        self.modelId = modelId
        self.dependsOn = dependsOn
        self.isolateWorktree = isolateWorktree
        self.readOnly = readOnly
        self.maxRetries = maxRetries
        self.fallbackHarnesses = fallbackHarnesses
        self.verifyWithActorId = verifyWithActorId
    }
}

public struct PipiOrchestrationPlan: Codable, Equatable, Sendable {
    public let planId: String
    public var goal: String
    public var supervisorId: String
    public var nodes: [PipiOrchestrationTaskNode]
    public var synthesizeFinal: Bool
    public var maxConcurrency: Int
    public var autoWorktreeOnParallelWrite: Bool

    public init(
        planId: String = "plan_\(UUID().uuidString.prefix(8).lowercased())",
        goal: String,
        supervisorId: String,
        nodes: [PipiOrchestrationTaskNode],
        synthesizeFinal: Bool = true,
        maxConcurrency: Int = 3,
        autoWorktreeOnParallelWrite: Bool = true
    ) {
        self.planId = planId
        self.goal = goal
        self.supervisorId = supervisorId
        self.nodes = nodes
        self.synthesizeFinal = synthesizeFinal
        self.maxConcurrency = max(1, min(6, maxConcurrency))
        self.autoWorktreeOnParallelWrite = autoWorktreeOnParallelWrite
    }
}

public struct PipiOrchestrationValidationIssue: Equatable, Sendable {
    public let path: String
    public let code: String
    public let message: String
}

public struct PipiOrchestrationValidationResult: Equatable, Sendable {
    public let valid: Bool
    public let issues: [PipiOrchestrationValidationIssue]
    public let waves: [[String]]
    public let autoIsolatedNodeIds: [String]
}

public struct PipiBlackboardArtifact: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let fromNodeId: String
    public let actorId: String
    public let title: String
    public let content: String
    public let worktreeBranch: String?
    public let createdAt: String

    public init(
        id: String,
        fromNodeId: String,
        actorId: String,
        title: String,
        content: String,
        worktreeBranch: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.fromNodeId = fromNodeId
        self.actorId = actorId
        self.title = title
        self.content = content
        self.worktreeBranch = worktreeBranch
        self.createdAt = createdAt
    }
}

public struct PipiOrchestrationNodeRequest: Sendable {
    public let planId: String
    public let node: PipiOrchestrationTaskNode
    public let waveIndex: Int
    public let attempt: Int
    public let effectiveHarness: String?
    public let effectiveWorktreeIsolation: Bool
    public let upstreamContext: [PipiBlackboardArtifact]
    public let revisionFeedback: String?
}

public struct PipiOrchestrationNodeResponse: Sendable {
    public let output: String
    public let succeeded: Bool
    public let harnessUsed: String?
    public let worktreeBranch: String?
    public let diffSummary: String?
    public let errorMessage: String?

    public init(
        output: String,
        succeeded: Bool,
        harnessUsed: String? = nil,
        worktreeBranch: String? = nil,
        diffSummary: String? = nil,
        errorMessage: String? = nil
    ) {
        self.output = output
        self.succeeded = succeeded
        self.harnessUsed = harnessUsed
        self.worktreeBranch = worktreeBranch
        self.diffSummary = diffSummary
        self.errorMessage = errorMessage
    }
}

public struct PipiOrchestrationNodeOutcome: Equatable, Sendable {
    public let nodeId: String
    public let title: String
    public let actorId: String
    public let rolePreset: PipiSubagentRolePreset
    public let waveIndex: Int
    public let succeeded: Bool
    public let skipped: Bool
    public let attempts: Int
    public let harnessUsed: String?
    public let worktreeIsolated: Bool
    public let worktreeBranch: String?
    public let diffSummary: String?
    public let output: String
    public let verifiedApproved: Bool?
}

public struct PipiOrchestrationResult: Equatable, Sendable {
    public let planId: String
    public let goal: String
    public let completed: Bool
    public let wavesExecuted: Int
    public let nodeOutcomes: [PipiOrchestrationNodeOutcome]
    public let blackboard: [PipiBlackboardArtifact]
    public let finalOutput: String
}

public struct PipiStructuredTurnVerdict: Equatable, Sendable {
    public var approved: Bool?
    public var done: Bool?
    public var selectedActorId: String?
}

public typealias PipiOrchestrationNodeRunner = @Sendable (PipiOrchestrationNodeRequest) async -> PipiOrchestrationNodeResponse
public typealias PipiOrchestrationSynthesizer = @Sendable (String, [PipiOrchestrationNodeOutcome], [PipiBlackboardArtifact]) async -> String

public enum PipiAgentOrchestrator {

    // MARK: - 1. Kahn DAG Validation & Auto Worktree Isolation

    public static func validate(_ plan: PipiOrchestrationPlan) -> PipiOrchestrationValidationResult {
        var issues: [PipiOrchestrationValidationIssue] = []
        if plan.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(PipiOrchestrationValidationIssue(path: "goal", code: "orch_goal_empty", message: "Goal must not be empty."))
        }
        if plan.nodes.isEmpty {
            issues.append(PipiOrchestrationValidationIssue(path: "nodes", code: "orch_nodes_empty", message: "At least one task node is required."))
            return PipiOrchestrationValidationResult(valid: false, issues: issues, waves: [], autoIsolatedNodeIds: [])
        }

        var nodeById: [String: PipiOrchestrationTaskNode] = [:]
        for (idx, node) in plan.nodes.enumerated() {
            if node.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(PipiOrchestrationValidationIssue(path: "nodes[\(idx)].id", code: "orch_node_id_missing", message: "Node ID is required."))
                continue
            }
            if nodeById[node.id] != nil {
                issues.append(PipiOrchestrationValidationIssue(path: "nodes[\(idx)].id", code: "orch_node_id_duplicated", message: "Duplicate node ID \"\(node.id)\"."))
                continue
            }
            nodeById[node.id] = node
        }

        var deps: [String: Set<String>] = [:]
        for node in plan.nodes where !node.id.isEmpty {
            var set = Set<String>()
            for depId in node.dependsOn {
                if depId == node.id {
                    issues.append(PipiOrchestrationValidationIssue(path: "nodes.\(node.id).dependsOn", code: "orch_self_dependency", message: "Node \"\(node.id)\" cannot depend on itself."))
                } else if nodeById[depId] == nil {
                    issues.append(PipiOrchestrationValidationIssue(path: "nodes.\(node.id).dependsOn", code: "orch_unknown_dependency", message: "Node \"\(node.id)\" references unknown dependency \"\(depId)\"."))
                } else {
                    set.insert(depId)
                }
            }
            deps[node.id] = set
        }

        var waves: [[String]] = []
        var remaining = deps
        let orderedIds = plan.nodes.map(\.id).filter { !$0.isEmpty }

        while !remaining.isEmpty {
            let ready = orderedIds.filter { id in
                if let d = remaining[id] { return d.isEmpty }
                return false
            }
            if ready.isEmpty {
                issues.append(PipiOrchestrationValidationIssue(path: "dag", code: "orch_cycle_detected", message: "Circular dependency detected in orchestration DAG."))
                break
            }
            waves.append(ready)
            for id in ready { remaining.removeValue(forKey: id) }
            for key in Array(remaining.keys) {
                for id in ready { remaining[key]?.remove(id) }
            }
        }

        var autoIsolated: [String] = []
        for wave in waves {
            let writable = wave.filter { id in
                guard let node = nodeById[id] else { return false }
                let ro = node.readOnly ?? node.rolePreset.isReadOnlyDefault
                return !ro
            }
            for id in wave {
                guard let node = nodeById[id] else { continue }
                let explicit = node.isolateWorktree == true
                let autoParallel = plan.autoWorktreeOnParallelWrite && writable.count >= 2 && writable.contains(id)
                if explicit || autoParallel {
                    autoIsolated.append(id)
                }
            }
        }

        return PipiOrchestrationValidationResult(
            valid: issues.isEmpty,
            issues: issues,
            waves: waves,
            autoIsolatedNodeIds: autoIsolated
        )
    }

    // MARK: - 2. Real Structured Verdict & Plan Parsing

    public static func parseVerdict(
        from text: String,
        candidateActorIds: [String] = []
    ) -> PipiStructuredTurnVerdict {
        var verdict = PipiStructuredTurnVerdict()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Attempt embedded JSON verdict object first
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}"),
           start < end,
           let data = String(trimmed[start...end]).data(using: .utf8),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let b = obj["approved"] as? Bool { verdict.approved = b }
            if let d = obj["done"] as? Bool { verdict.done = d }
            if let s = obj["selectedActorId"] as? String, !s.isEmpty { verdict.selectedActorId = s }
        }

        let upper = trimmed.uppercased()
        if verdict.approved == nil {
            if upper.contains("VERDICT: APPROVE") || upper.contains("VERDICT:APPROVED")
                || upper.contains("REVIEW: APPROVE") || upper.contains("VERDICT: PASS")
                || upper.contains("VERDICT: LGTM") || trimmed.contains("【通过】") || trimmed.contains("【批准】") {
                verdict.approved = true
            } else if upper.contains("VERDICT: REVISE") || upper.contains("VERDICT: REJECT")
                || upper.contains("VERDICT: FAIL") || upper.contains("CHANGES_REQUESTED")
                || trimmed.contains("【打回】") || trimmed.contains("【需修改】") || trimmed.contains("【拒绝】") {
                verdict.approved = false
            }
        }

        if verdict.done == nil {
            if upper.contains("STATUS: DONE") || upper.contains("STATUS: COMPLETE")
                || upper.contains("LOOP: DONE") || trimmed.contains("【完成】") {
                verdict.done = true
            } else if upper.contains("STATUS: CONTINUE") || upper.contains("STATUS: RETRY")
                || upper.contains("LOOP: CONTINUE") || trimmed.contains("【继续】") {
                verdict.done = false
            }
        }

        if verdict.selectedActorId == nil, !candidateActorIds.isEmpty {
            let pattern = #"(?:SELECT|WINNER|ASSIGN)\s*[:：]\s*([A-Za-z0-9_.:-]+)"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
               let range = Range(match.range(at: 1), in: trimmed) {
                let rawPick = String(trimmed[range]).lowercased()
                verdict.selectedActorId = candidateActorIds.first { $0.lowercased() == rawPick }
            }
            if verdict.selectedActorId == nil {
                let lower = trimmed.lowercased()
                verdict.selectedActorId = candidateActorIds.first { lower.contains($0.lowercased()) }
            }
        }

        return verdict
    }

    public static func parsePlanFromLeadReply(
        text: String,
        goal: String,
        supervisorId: String,
        candidates: [(id: String, nameZh: String, nameEn: String)]
    ) -> PipiOrchestrationPlan? {
        // 1. Try `<pipibot_plan>{...}</pipibot_plan>` JSON
        if let open = text.range(of: "<pipibot_plan>", options: .caseInsensitive),
           let close = text.range(of: "</pipibot_plan>", options: .caseInsensitive, range: open.upperBound..<text.endIndex) {
            let jsonSlice = String(text[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = jsonSlice.data(using: .utf8),
               let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let rawNodes = root["nodes"] as? [[String: Any]], !rawNodes.isEmpty {
                var nodes: [PipiOrchestrationTaskNode] = []
                for (idx, item) in rawNodes.enumerated() {
                    let id = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "t\(idx + 1)"
                    let prompt = (item["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? goal
                    let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? String(prompt.prefix(72))
                    let rawPreset = (item["rolePreset"] as? String ?? "general").lowercased()
                    let preset = PipiSubagentRolePreset(rawValue: rawPreset) ?? .general
                    let rawActor = (item["actorId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedActor = rawActor.flatMap { raw -> String? in
                        let low = raw.lowercased()
                        return candidates.first {
                            $0.id.lowercased() == low || $0.nameEn.lowercased() == low || $0.nameZh.lowercased() == low
                        }?.id ?? raw
                    }
                    let deps = (item["dependsOn"] as? [String]) ?? []
                    nodes.append(PipiOrchestrationTaskNode(
                        id: id,
                        title: title,
                        prompt: prompt,
                        rolePreset: preset,
                        actorId: resolvedActor,
                        harness: item["harness"] as? String,
                        modelId: item["modelId"] as? String,
                        dependsOn: deps,
                        isolateWorktree: item["isolateWorktree"] as? Bool,
                        readOnly: item["readOnly"] as? Bool,
                        maxRetries: item["maxRetries"] as? Int,
                        verifyWithActorId: item["verifyWithActorId"] as? String
                    ))
                }
                if !nodes.isEmpty {
                    return PipiOrchestrationPlan(
                        goal: goal,
                        supervisorId: supervisorId,
                        nodes: nodes,
                        synthesizeFinal: (root["synthesizeFinal"] as? Bool) ?? true,
                        maxConcurrency: (root["maxConcurrency"] as? Int) ?? 3,
                        autoWorktreeOnParallelWrite: true
                    )
                }
            }
        }

        // 2. Parse `@Member: subtask [id: t1] [depends: t0] [worktree] [harness: codex] [role: coder]`
        var nodes: [PipiOrchestrationTaskNode] = []
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            for bullet in ["- ", "* ", "• "] where line.hasPrefix(bullet) {
                line = String(line.dropFirst(bullet.count)).trimmingCharacters(in: .whitespaces)
            }
            guard line.hasPrefix("@") else { continue }
            guard let colonIdx = line.firstIndex(where: { $0 == ":" || $0 == "：" }) else { continue }
            let mentionToken = String(line[line.index(after: line.startIndex)..<colonIdx])
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            guard let matched = candidates.first(where: {
                $0.id.lowercased() == mentionToken
                    || $0.nameEn.lowercased() == mentionToken
                    || $0.nameZh.lowercased() == mentionToken
            }) else { continue }

            var body = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            let idVal = extractBracketTag("id", from: body)
            let depsVal = extractBracketTag("depends", from: body)
            let harnessVal = extractBracketTag("harness", from: body)
            let roleVal = extractBracketTag("role", from: body)?.lowercased()
            let hasWorktree = body.range(of: "[worktree]", options: .caseInsensitive) != nil

            body = stripOrchestrationTags(from: body)
            guard !body.isEmpty else { continue }

            let deps = (depsVal ?? "")
                .components(separatedBy: CharacterSet(charactersIn: ",，"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            nodes.append(PipiOrchestrationTaskNode(
                id: idVal ?? "t\(nodes.count + 1)",
                title: String(body.prefix(72)),
                prompt: body,
                rolePreset: roleVal.flatMap { PipiSubagentRolePreset(rawValue: $0) } ?? .general,
                actorId: matched.id,
                harness: harnessVal,
                dependsOn: deps,
                isolateWorktree: hasWorktree ? true : nil
            ))
        }

        guard !nodes.isEmpty else { return nil }
        return PipiOrchestrationPlan(
            goal: goal,
            supervisorId: supervisorId,
            nodes: nodes,
            synthesizeFinal: true,
            maxConcurrency: 3,
            autoWorktreeOnParallelWrite: true
        )
    }

    private static func extractBracketTag(_ key: String, from text: String) -> String? {
        let pattern = #"\[\#(key)\s*:\s*([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let val = String(text[range]).trimmingCharacters(in: .whitespaces)
        return val.isEmpty ? nil : val
    }

    private static func stripOrchestrationTags(from text: String) -> String {
        let patterns = [
            #"\[(?:id|depends|harness|role)\s*:[^\]]+\]"#,
            #"\[worktree\]"#
        ]
        var out = text
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
            }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 3. Wave-Based Async Executor with Blackboard & Synthesis

    public static func execute(
        plan: PipiOrchestrationPlan,
        runNode: @escaping PipiOrchestrationNodeRunner,
        synthesize: PipiOrchestrationSynthesizer? = nil
    ) async -> PipiOrchestrationResult {
        let validation = validate(plan)
        guard validation.valid else {
            let summary = validation.issues.map { "\($0.code): \($0.message)" }.joined(separator: "; ")
            return PipiOrchestrationResult(
                planId: plan.planId,
                goal: plan.goal,
                completed: false,
                wavesExecuted: 0,
                nodeOutcomes: [],
                blackboard: [],
                finalOutput: "Invalid orchestration plan: \(summary)"
            )
        }

        let nodeById = Dictionary(uniqueKeysWithValues: plan.nodes.map { ($0.id, $0) })
        let isolatedSet = Set(validation.autoIsolatedNodeIds)
        var blackboard: [PipiBlackboardArtifact] = []
        var artifactsByNode: [String: [PipiBlackboardArtifact]] = [:]
        var outcomesById: [String: PipiOrchestrationNodeOutcome] = [:]

        for (waveIndex, waveIds) in validation.waves.enumerated() {
            let upstreamSnapshot = artifactsByNode
            let outcomesSnapshot = outcomesById

            let waveOutcomes: [(PipiOrchestrationNodeOutcome, PipiBlackboardArtifact?)] = await withTaskGroup(
                of: (Int, PipiOrchestrationNodeOutcome, PipiBlackboardArtifact?).self
            ) { group in
                for (offset, nodeId) in waveIds.enumerated() {
                    guard let node = nodeById[nodeId] else { continue }
                    let actorId = node.actorId ?? "\(node.rolePreset.rawValue):\(node.id)"
                    let shouldIsolate = isolatedSet.contains(node.id)
                    let failedDep = node.dependsOn.first { dep in
                        if let prev = outcomesSnapshot[dep] {
                            return !prev.succeeded || prev.skipped
                        }
                        return false
                    }
                    var upstream: [PipiBlackboardArtifact] = []
                    for dep in node.dependsOn {
                        upstream.append(contentsOf: upstreamSnapshot[dep] ?? [])
                    }
                    let capturedUpstream = upstream

                    group.addTask {
                        if let failedDep {
                            let skipped = PipiOrchestrationNodeOutcome(
                                nodeId: node.id,
                                title: node.title,
                                actorId: actorId,
                                rolePreset: node.rolePreset,
                                waveIndex: waveIndex,
                                succeeded: false,
                                skipped: true,
                                attempts: 0,
                                harnessUsed: node.harness,
                                worktreeIsolated: shouldIsolate,
                                worktreeBranch: nil,
                                diffSummary: nil,
                                output: "Skipped because dependency \(failedDep) did not succeed.",
                                verifiedApproved: nil
                            )
                            return (offset, skipped, nil)
                        }

                        var harnessChain: [String?] = [node.harness]
                        if let fallbacks = node.fallbackHarnesses {
                            harnessChain.append(contentsOf: fallbacks.map { Optional($0) })
                        }
                        let maxAttempts = max(1, (node.maxRetries ?? 1) + 1)
                        var attempt = 0
                        var revisionFeedback: String?
                        var lastResp: PipiOrchestrationNodeResponse?
                        var verifiedApproved: Bool?

                        while attempt < maxAttempts {
                            attempt += 1
                            let effHarness = harnessChain[min(attempt - 1, harnessChain.count - 1)]
                            let resp = await runNode(PipiOrchestrationNodeRequest(
                                planId: plan.planId,
                                node: node,
                                waveIndex: waveIndex,
                                attempt: attempt,
                                effectiveHarness: effHarness,
                                effectiveWorktreeIsolation: shouldIsolate,
                                upstreamContext: capturedUpstream,
                                revisionFeedback: revisionFeedback
                            ))
                            lastResp = resp
                            if !resp.succeeded {
                                revisionFeedback = resp.errorMessage ?? "Previous attempt failed."
                                continue
                            }

                            if let verifierId = node.verifyWithActorId {
                                let verifyNode = PipiOrchestrationTaskNode(
                                    id: "\(node.id)_verify_\(attempt)",
                                    title: "Verify \(node.title)",
                                    prompt: "Review output for \"\(node.title)\" against goal \"\(plan.goal)\".\n\nOutput:\n\(resp.output)\n\nEnd with VERDICT: APPROVE or VERDICT: REVISE.",
                                    rolePreset: .verifier,
                                    actorId: verifierId,
                                    dependsOn: [node.id],
                                    readOnly: true
                                )
                                let verResp = await runNode(PipiOrchestrationNodeRequest(
                                    planId: plan.planId,
                                    node: verifyNode,
                                    waveIndex: waveIndex,
                                    attempt: 1,
                                    effectiveHarness: nil,
                                    effectiveWorktreeIsolation: false,
                                    upstreamContext: capturedUpstream,
                                    revisionFeedback: nil
                                ))
                                let parsed = parseVerdict(from: verResp.output)
                                verifiedApproved = parsed.approved ?? verResp.succeeded
                                if verifiedApproved == false && attempt < maxAttempts {
                                    revisionFeedback = verResp.output
                                    continue
                                }
                            }
                            break
                        }

                        let ok = (lastResp?.succeeded ?? false) && verifiedApproved != false
                        let outcome = PipiOrchestrationNodeOutcome(
                            nodeId: node.id,
                            title: node.title,
                            actorId: actorId,
                            rolePreset: node.rolePreset,
                            waveIndex: waveIndex,
                            succeeded: ok,
                            skipped: false,
                            attempts: attempt,
                            harnessUsed: lastResp?.harnessUsed ?? node.harness,
                            worktreeIsolated: shouldIsolate,
                            worktreeBranch: lastResp?.worktreeBranch,
                            diffSummary: lastResp?.diffSummary,
                            output: lastResp?.output ?? lastResp?.errorMessage ?? "",
                            verifiedApproved: verifiedApproved
                        )
                        let artifact: PipiBlackboardArtifact? = ok
                            ? PipiBlackboardArtifact(
                                id: "bb_\(node.id)",
                                fromNodeId: node.id,
                                actorId: actorId,
                                title: node.title,
                                content: outcome.output,
                                worktreeBranch: outcome.worktreeBranch
                            )
                            : nil
                        return (offset, outcome, artifact)
                    }
                }

                var collected: [(Int, PipiOrchestrationNodeOutcome, PipiBlackboardArtifact?)] = []
                for await item in group {
                    collected.append(item)
                }
                return collected.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
            }

            for (outcome, artifact) in waveOutcomes {
                outcomesById[outcome.nodeId] = outcome
                if let artifact {
                    blackboard.append(artifact)
                    artifactsByNode[outcome.nodeId, default: []].append(artifact)
                }
            }
        }

        let orderedOutcomes = plan.nodes.compactMap { outcomesById[$0.id] }
        let allOk = !orderedOutcomes.isEmpty && orderedOutcomes.allSatisfy { $0.succeeded && !$0.skipped }

        let finalOutput: String
        if plan.synthesizeFinal, let synthesize {
            finalOutput = await synthesize(plan.goal, orderedOutcomes, blackboard)
        } else {
            finalOutput = orderedOutcomes
                .map { "### \($0.title) (\($0.actorId))\n\($0.output)" }
                .joined(separator: "\n\n")
        }

        return PipiOrchestrationResult(
            planId: plan.planId,
            goal: plan.goal,
            completed: allOk,
            wavesExecuted: validation.waves.count,
            nodeOutcomes: orderedOutcomes,
            blackboard: blackboard,
            finalOutput: finalOutput
        )
    }
}
