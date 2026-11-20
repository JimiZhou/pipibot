// PiPiBot — Clean-room MIT implementation.
// Wave 3 (#06): Structured `team.md` Multi-Bot Collaboration Protocol (All 5 Topologies,
// Pure Multi-Issue Parser, Kahn DAG Cycle Checker & Dynamic Bot Invite/Create Approval).
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

import Foundation

// MARK: - 1. Public `team.md` & Dynamic Proposal Contracts

public struct PipiTeamMdIssue: Codable, Identifiable, Equatable, Sendable {
    public var id: String { "\(path)::\(code)::\(message)" }
    public let path: String
    public let code: String
    public let message: String

    public init(path: String, code: String, message: String) {
        self.path = path
        self.code = code
        self.message = message
    }
}

public struct PipiTeamParticipant: Codable, Identifiable, Equatable, Sendable {
    public var id: String { actorId.isEmpty ? name : actorId }
    public var name: String
    public var actorId: String
    public var role: String
    public var reportTo: [String]
    public var receiveFrom: [String]

    public init(
        name: String,
        actorId: String,
        role: String = "",
        reportTo: [String] = [],
        receiveFrom: [String] = []
    ) {
        self.name = name
        self.actorId = actorId
        self.role = role
        self.reportTo = reportTo
        self.receiveFrom = receiveFrom
    }
}

public struct PipiTeamMdDocument: Codable, Equatable, Sendable {
    public var pattern: PipiTeamCollaborationPattern
    public var maxRounds: Int
    public var taskGoal: String
    public var orchestrator: PipiTeamParticipant
    public var members: [PipiTeamParticipant]

    public init(
        pattern: PipiTeamCollaborationPattern,
        maxRounds: Int = 3,
        taskGoal: String,
        orchestrator: PipiTeamParticipant,
        members: [PipiTeamParticipant]
    ) {
        self.pattern = pattern
        self.maxRounds = maxRounds
        self.taskGoal = taskGoal
        self.orchestrator = orchestrator
        self.members = members
    }
}

public struct PipiTeamMdValidationResult: Equatable, Sendable {
    public let valid: Bool
    public let document: PipiTeamMdDocument?
    public let issues: [PipiTeamMdIssue]
    public let executionWaves: [[String]]
    public let missingMemberActorIds: [String]
}

public struct PipiDynamicBotProposal: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let groupId: String
    public var action: PipiDynamicBotProposalAction
    public var status: PipiDynamicBotProposalStatus
    public var requestedActorId: String
    public var existingBotId: String?
    public var proposedName: String
    public var proposedRole: String
    public var proposedSystemPrompt: String
    public var rationale: String
    public let createdAt: String

    public init(
        id: String = "dbp_\(UUID().uuidString.prefix(8).lowercased())",
        groupId: String,
        action: PipiDynamicBotProposalAction,
        status: PipiDynamicBotProposalStatus = .pending,
        requestedActorId: String,
        existingBotId: String? = nil,
        proposedName: String,
        proposedRole: String,
        proposedSystemPrompt: String,
        rationale: String,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.groupId = groupId
        self.action = action
        self.status = status
        self.requestedActorId = requestedActorId
        self.existingBotId = existingBotId
        self.proposedName = proposedName
        self.proposedRole = proposedRole
        self.proposedSystemPrompt = proposedSystemPrompt
        self.rationale = rationale
        self.createdAt = createdAt
    }
}

public enum PipiTeamTurnPhase: String, Codable, Sendable, Equatable {
    case classify
    case execute
    case verify
    case judge
    case synthesize
    case loopStep = "loop_step"
}

public struct PipiTeamUpstreamOutput: Equatable, Sendable {
    public let actorId: String
    public let memberName: String
    public let output: String

    public init(actorId: String, memberName: String, output: String) {
        self.actorId = actorId
        self.memberName = memberName
        self.output = output
    }
}

public struct PipiTeamBotTurnRequest: Sendable {
    public let actorId: String
    public let memberName: String
    public let role: String
    public let pattern: PipiTeamCollaborationPattern
    public let phase: PipiTeamTurnPhase
    public let round: Int
    public let prompt: String
    public let upstreamOutputs: [PipiTeamUpstreamOutput]
}

public struct PipiTeamBotTurnResponse: Sendable {
    public let output: String
    public let selectedActorId: String?
    public let approved: Bool?
    public let done: Bool?

    public init(
        output: String,
        selectedActorId: String? = nil,
        approved: Bool? = nil,
        done: Bool? = nil
    ) {
        self.output = output
        self.selectedActorId = selectedActorId
        self.approved = approved
        self.done = done
    }
}

public typealias PipiTeamBotExecutor = @Sendable (PipiTeamBotTurnRequest) async throws -> PipiTeamBotTurnResponse

public struct PipiTeamExecutionTraceEntry: Equatable, Sendable {
    public let phase: PipiTeamTurnPhase
    public let round: Int
    public let actorId: String
    public let memberName: String
    public let output: String
}

public struct PipiTeamExecutionResult: Equatable, Sendable {
    public let pattern: PipiTeamCollaborationPattern
    public let roundsExecuted: Int
    public let winnerActorId: String?
    public let verifiedApproved: Bool?
    public let completed: Bool
    public let finalOutput: String
    public let trace: [PipiTeamExecutionTraceEntry]
}

// MARK: - 2. Localized Labels for All 5 Patterns

public extension PipiTeamCollaborationPattern {
    func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .classifyAndAct: return lang == .zhHans ? "分类路由 (Classify & Act)" : "Classify & Act"
        case .fanOutAndSynthesize: return lang == .zhHans ? "扇出汇聚 (Fan-out & Synthesize)" : "Fan-out & Synthesize"
        case .adversarialVerification: return lang == .zhHans ? "对抗验证 (Adversarial)" : "Adversarial Verification"
        case .tournament: return lang == .zhHans ? "锦标赛择优 (Tournament)" : "Tournament"
        case .loopUntilDone: return lang == .zhHans ? "循环迭代 (Loop Until Done)" : "Loop Until Done"
        }
    }
}

// MARK: - 3. Pure Parser, Validator, DAG Checker, Template & 5-Pattern Executor

public enum PipiTeamProtocol {
    public static let maxContentBytes = 64 * 1024
    public static let maxMembers = 50
    public static let defaultMaxRounds = 3
    public static let maxAllowedRounds = 6

    private static func splitCsvList(_ raw: String) -> [String] {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty || cleaned.lowercased() == "none" || cleaned == "-" || cleaned == "[]" {
            return []
        }
        let stripped = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return stripped
            .components(separatedBy: CharacterSet(charactersIn: ",，"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseParticipant(
        lines: [String],
        defaultName: String,
        pathPrefix: String,
        issues: inout [PipiTeamMdIssue]
    ) -> PipiTeamParticipant {
        var name = defaultName
        var actorId = ""
        var role = ""
        var reportTo: [String] = []
        var receiveFrom: [String] = []
        var seenAttrs = Set<String>()

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("## ") {
                name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard (line.hasPrefix("- ") || line.hasPrefix("* ")),
                  let colonIdx = line.firstIndex(of: ":") else {
                continue
            }
            let rawKey = String(line[line.index(line.startIndex, offsetBy: 2)..<colonIdx])
                .trimmingCharacters(in: .whitespaces)
            let key = rawKey.lowercased().replacingOccurrences(of: " ", with: "_")
            let val = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

            if !seenAttrs.insert(key).inserted {
                issues.append(PipiTeamMdIssue(
                    path: "\(pathPrefix).\(key)",
                    code: "team_md_attribute_duplicated",
                    message: "Duplicate attribute \"\(rawKey)\" for participant \"\(name)\"."
                ))
                continue
            }

            switch key {
            case "name": name = val
            case "actor_id": actorId = val
            case "role": role = val
            case "report_to": reportTo = splitCsvList(val)
            case "receive_from": receiveFrom = splitCsvList(val)
            default:
                issues.append(PipiTeamMdIssue(
                    path: "\(pathPrefix).\(key)",
                    code: "team_md_attribute_unknown",
                    message: "Unknown participant attribute \"\(rawKey)\"."
                ))
            }
        }

        if name.isEmpty {
            issues.append(PipiTeamMdIssue(path: "\(pathPrefix).name", code: "team_md_name_invalid", message: "Participant name is required."))
        }
        if actorId.isEmpty {
            issues.append(PipiTeamMdIssue(path: "\(pathPrefix).actor_id", code: "team_md_actor_id_missing", message: "Participant \"\(name)\" is missing Actor ID."))
        }

        return PipiTeamParticipant(name: name, actorId: actorId, role: role, reportTo: reportTo, receiveFrom: receiveFrom)
    }

    public static func parseAndValidate(
        _ content: String,
        roomMemberActorIds: [String]? = nil
    ) -> PipiTeamMdValidationResult {
        var issues: [PipiTeamMdIssue] = []
        let trimmedAll = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAll.isEmpty else {
            issues.append(PipiTeamMdIssue(path: "document", code: "team_md_content_invalid", message: "team.md content is empty."))
            return PipiTeamMdValidationResult(valid: false, document: nil, issues: issues, executionWaves: [], missingMemberActorIds: [])
        }
        guard content.utf8.count <= maxContentBytes else {
            issues.append(PipiTeamMdIssue(path: "document", code: "team_md_content_too_large", message: "team.md exceeds 64 KB limit."))
            return PipiTeamMdValidationResult(valid: false, document: nil, issues: issues, executionWaves: [], missingMemberActorIds: [])
        }

        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let allLines = normalized.components(separatedBy: "\n")
        guard allLines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let closingIdx = allLines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            issues.append(PipiTeamMdIssue(path: "frontmatter", code: "team_md_frontmatter_missing", message: "YAML frontmatter (--- ... ---) is required."))
            return PipiTeamMdValidationResult(valid: false, document: nil, issues: issues, executionWaves: [], missingMemberActorIds: [])
        }

        let fmLines = Array(allLines[1..<closingIdx])
        let bodyLines = Array(allLines[(closingIdx + 1)...])

        var rawPattern = ""
        var maxRounds = defaultMaxRounds

        for rawLine in fmLines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let colonIdx = line.firstIndex(of: ":") else {
                issues.append(PipiTeamMdIssue(path: "frontmatter", code: "team_md_frontmatter_invalid", message: "Malformed frontmatter line: \"\(line)\"."))
                continue
            }
            let key = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let val = String(line[line.index(after: colonIdx)...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
            if key == "collaborate_pattern" {
                rawPattern = val
            } else if key == "max_rounds" {
                if let n = Int(val), (1...maxAllowedRounds).contains(n) {
                    maxRounds = n
                } else {
                    issues.append(PipiTeamMdIssue(
                        path: "frontmatter.max_rounds",
                        code: "team_md_frontmatter_invalid",
                        message: "max_rounds must be between 1 and \(maxAllowedRounds)."
                    ))
                }
            }
        }

        let parsedPattern = PipiTeamCollaborationPattern(rawValue: rawPattern)
        if rawPattern.isEmpty {
            issues.append(PipiTeamMdIssue(path: "frontmatter.collaborate_pattern", code: "team_md_pattern_missing", message: "collaborate_pattern is required."))
        } else if parsedPattern == nil {
            issues.append(PipiTeamMdIssue(
                path: "frontmatter.collaborate_pattern",
                code: "team_md_pattern_invalid",
                message: "Unsupported collaborate_pattern \"\(rawPattern)\"."
            ))
        }

        // Split H1 sections
        let knownSections: Set<String> = ["task goal", "orchestrator", "team members"]
        var sections: [String: [String]] = [:]
        var activeSection: String?
        for line in bodyLines {
            if line.hasPrefix("# ") {
                let secName = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces).lowercased()
                if !knownSections.contains(secName) {
                    issues.append(PipiTeamMdIssue(path: "sections.\(secName)", code: "team_md_section_unknown", message: "Unknown section \"# \(secName)\"."))
                    activeSection = nil
                    continue
                }
                if sections[secName] != nil {
                    issues.append(PipiTeamMdIssue(path: "sections.\(secName)", code: "team_md_section_duplicated", message: "Duplicate section \"# \(secName)\"."))
                    activeSection = nil
                    continue
                }
                sections[secName] = []
                activeSection = secName
            } else if let activeSection {
                sections[activeSection, default: []].append(line)
            }
        }

        for req in ["task goal", "orchestrator", "team members"] where sections[req] == nil {
            issues.append(PipiTeamMdIssue(path: "sections.\(req)", code: "team_md_section_missing", message: "Missing required section \"# \(req)\"."))
        }

        let taskGoal = (sections["task goal"] ?? []).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if taskGoal.isEmpty {
            issues.append(PipiTeamMdIssue(path: "task_goal", code: "team_md_task_goal_missing", message: "Task Goal must be non-empty."))
        }

        let orchestrator = parseParticipant(
            lines: sections["orchestrator"] ?? [],
            defaultName: "Orchestrator",
            pathPrefix: "orchestrator",
            issues: &issues
        )

        // Split Team Members by H2 (`## Name`)
        var memberBlocks: [(name: String, lines: [String])] = []
        var currentBlock: (name: String, lines: [String])?
        for line in sections["team members"] ?? [] {
            if line.hasPrefix("## ") {
                if let currentBlock { memberBlocks.append(currentBlock) }
                currentBlock = (String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces), [])
            } else if currentBlock != nil {
                currentBlock?.lines.append(line)
            }
        }
        if let currentBlock { memberBlocks.append(currentBlock) }

        if memberBlocks.isEmpty {
            issues.append(PipiTeamMdIssue(path: "members", code: "team_md_member_missing", message: "At least one team member is required."))
        } else if memberBlocks.count > maxMembers {
            issues.append(PipiTeamMdIssue(path: "members", code: "team_md_too_many_members", message: "Too many team members (max \(maxMembers))."))
        }

        let members = memberBlocks.enumerated().map { idx, blk in
            parseParticipant(lines: blk.lines, defaultName: blk.name, pathPrefix: "members[\(idx)]", issues: &issues)
        }

        // Duplicate checks & reference lookup
        let allParticipants = [orchestrator] + members
        var seenNames = Set<String>()
        var seenActorIds = Set<String>()
        var refToActorId: [String: String] = [:]

        for p in allParticipants {
            let nl = p.name.lowercased()
            if !nl.isEmpty && !seenNames.insert(nl).inserted {
                issues.append(PipiTeamMdIssue(path: "participant.\(p.name)", code: "team_md_name_duplicated", message: "Duplicate participant name \"\(p.name)\"."))
            }
            if !p.actorId.isEmpty && !seenActorIds.insert(p.actorId).inserted {
                issues.append(PipiTeamMdIssue(path: "participant.\(p.actorId)", code: "team_md_actor_id_duplicated", message: "Duplicate Actor ID \"\(p.actorId)\"."))
            }
            if !p.actorId.isEmpty {
                refToActorId[p.actorId.lowercased()] = p.actorId
                if !nl.isEmpty { refToActorId[nl] = p.actorId }
            }
        }

        let memberIdSet = Set(members.map(\.actorId).filter { !$0.isEmpty })
        var deps: [String: Set<String>] = [:]
        for m in members where !m.actorId.isEmpty {
            deps[m.actorId] = []
        }

        for p in allParticipants {
            for ref in p.receiveFrom + p.reportTo {
                if refToActorId[ref.lowercased()] == nil {
                    issues.append(PipiTeamMdIssue(
                        path: "participant.\(p.name).references",
                        code: "team_md_reference_unknown",
                        message: "Unknown participant reference \"\(ref)\" in \"\(p.name)\"."
                    ))
                }
            }
            if memberIdSet.contains(p.actorId) {
                for upRef in p.receiveFrom {
                    if let upId = refToActorId[upRef.lowercased()], memberIdSet.contains(upId), upId != p.actorId {
                        deps[p.actorId, default: []].insert(upId)
                    }
                }
            }
        }

        var missingMembers: [String] = []
        if let roomMemberActorIds {
            let roomSet = Set(roomMemberActorIds)
            for p in allParticipants where !p.actorId.isEmpty && !roomSet.contains(p.actorId) {
                missingMembers.append(p.actorId)
                issues.append(PipiTeamMdIssue(
                    path: "participant.\(p.actorId)",
                    code: "team_md_actor_not_room_member",
                    message: "Actor \"\(p.actorId)\" (\(p.name)) is not in this group chat."
                ))
            }
        }

        // Kahn DAG topological sort
        let resolvedPattern = parsedPattern ?? .fanOutAndSynthesize
        let allowsBoundedCycle = (resolvedPattern == .adversarialVerification || resolvedPattern == .loopUntilDone)
        var remaining = deps
        var waves: [[String]] = []
        let orderedMemberIds = members.map(\.actorId).filter { !$0.isEmpty }

        while !remaining.isEmpty {
            let ready = orderedMemberIds.filter { id in
                if let d = remaining[id] { return d.isEmpty }
                return false
            }
            if ready.isEmpty {
                if !allowsBoundedCycle {
                    issues.append(PipiTeamMdIssue(
                        path: "dag",
                        code: "team_md_cycle_detected",
                        message: "Circular dependency detected in pattern \"\(resolvedPattern.rawValue)\"."
                    ))
                } else {
                    waves.append(orderedMemberIds.filter { remaining[$0] != nil })
                }
                break
            }
            waves.append(ready)
            for id in ready { remaining.removeValue(forKey: id) }
            for key in Array(remaining.keys) {
                for id in ready { remaining[key]?.remove(id) }
            }
        }

        let doc: PipiTeamMdDocument? = (parsedPattern != nil && !taskGoal.isEmpty && !orchestrator.actorId.isEmpty && !members.isEmpty)
            ? PipiTeamMdDocument(
                pattern: resolvedPattern,
                maxRounds: maxRounds,
                taskGoal: taskGoal,
                orchestrator: orchestrator,
                members: members
            )
            : nil

        return PipiTeamMdValidationResult(
            valid: issues.isEmpty && doc != nil,
            document: doc,
            issues: issues,
            executionWaves: waves,
            missingMemberActorIds: missingMembers
        )
    }

    public static func renderTemplate(
        pattern: PipiTeamCollaborationPattern,
        taskGoal: String,
        orchestrator: PipiTeamParticipant,
        members: [PipiTeamParticipant],
        maxRounds: Int = defaultMaxRounds
    ) -> String {
        var lines: [String] = [
            "---",
            "collaborate_pattern: \(pattern.rawValue)",
        ]
        if pattern == .adversarialVerification || pattern == .loopUntilDone {
            lines.append("max_rounds: \(max(1, min(maxAllowedRounds, maxRounds)))")
        }
        lines.append(contentsOf: [
            "---",
            "",
            "# Task Goal",
            taskGoal.trimmingCharacters(in: .whitespacesAndNewlines),
            "",
            "# Orchestrator",
            "## \(orchestrator.name)",
            "- Actor ID: \(orchestrator.actorId)",
            "- Role: \(orchestrator.role.isEmpty ? "Lead coordinator & synthesizer" : orchestrator.role)",
            "- Report to: none",
            "- Receive from: \(members.isEmpty ? "none" : members.map(\.name).joined(separator: ", "))",
            "",
            "# Team Members",
        ])

        for member in members {
            let recv = member.receiveFrom.isEmpty ? orchestrator.name : member.receiveFrom.joined(separator: ", ")
            let rep = member.reportTo.isEmpty ? orchestrator.name : member.reportTo.joined(separator: ", ")
            lines.append(contentsOf: [
                "## \(member.name)",
                "- Actor ID: \(member.actorId)",
                "- Role: \(member.role.isEmpty ? "Specialist collaborator" : member.role)",
                "- Receive from: \(recv)",
                "- Report to: \(rep)",
                "",
            ])
        }
        return lines.joined(separator: "\n")
    }

    public static func buildDynamicBotProposals(
        groupId: String,
        document: PipiTeamMdDocument,
        groupMemberIds: [String],
        allPersonas: [PipiBotPersona],
        language: PipiResolvedLanguage = .zhHans
    ) -> [PipiDynamicBotProposal] {
        let groupSet = Set(groupMemberIds)
        var proposals: [PipiDynamicBotProposal] = []
        let allParticipants = [document.orchestrator] + document.members

        for p in allParticipants where !p.actorId.isEmpty && !groupSet.contains(p.actorId) {
            let existing = allPersonas.first {
                $0.id == p.actorId
                    || $0.nameZh.lowercased() == p.name.lowercased()
                    || $0.nameEn.lowercased() == p.name.lowercased()
            }
            let rationale: String
            if let existing {
                rationale = language == .zhHans
                    ? "team.md 为「\(p.role.isEmpty ? p.name : p.role)」指定了现有智能体 \(existing.name(language))，批准后将自动拉入本群。"
                    : "team.md assigns \"\(p.role.isEmpty ? p.name : p.role)\" to existing agent \(existing.name(language)). Approve to invite it."
            } else {
                rationale = language == .zhHans
                    ? "team.md 需要新角色「\(p.name)」(\(p.actorId))，批准后将自动创建并拉入本群参与协作。"
                    : "team.md requests new specialist \"\(p.name)\" (\(p.actorId)). Approve to create and invite it."
            }
            proposals.append(PipiDynamicBotProposal(
                groupId: groupId,
                action: existing != nil ? .inviteExisting : .createAndInvite,
                status: .pending,
                requestedActorId: p.actorId,
                existingBotId: existing?.id,
                proposedName: existing?.name(language) ?? p.name,
                proposedRole: p.role.isEmpty ? (existing?.role(language) ?? "Specialist Collaborator") : p.role,
                proposedSystemPrompt: "You are \(p.name), specializing in \(p.role.isEmpty ? "collaborative problem solving" : p.role). Follow the group's team.md protocol strictly.",
                rationale: rationale
            ))
        }

        return proposals
    }

    // MARK: - 4. All 5 Topologies Async Executor

    public static func execute(
        document doc: PipiTeamMdDocument,
        userPrompt: String,
        executor: @escaping PipiTeamBotExecutor
    ) async throws -> PipiTeamExecutionResult {
        var trace: [PipiTeamExecutionTraceEntry] = []
        let memberById = Dictionary(uniqueKeysWithValues: doc.members.map { ($0.actorId, $0) })

        switch doc.pattern {
        case .classifyAndAct:
            let classifyReq = PipiTeamBotTurnRequest(
                actorId: doc.orchestrator.actorId,
                memberName: doc.orchestrator.name,
                role: doc.orchestrator.role,
                pattern: doc.pattern,
                phase: .classify,
                round: 1,
                prompt: "Goal: \(doc.taskGoal)\nRequest: \(userPrompt)\nSelect best specialist from: \(doc.members.map { "\($0.actorId)(\($0.role))" }.joined(separator: ", "))",
                upstreamOutputs: []
            )
            let classifyResp = try await executor(classifyReq)
            trace.append(PipiTeamExecutionTraceEntry(
                phase: .classify, round: 1, actorId: doc.orchestrator.actorId,
                memberName: doc.orchestrator.name, output: classifyResp.output
            ))

            let chosen = classifyResp.selectedActorId.flatMap { memberById[$0] } ?? doc.members[0]
            let actResp = try await executor(PipiTeamBotTurnRequest(
                actorId: chosen.actorId,
                memberName: chosen.name,
                role: chosen.role,
                pattern: doc.pattern,
                phase: .execute,
                round: 1,
                prompt: userPrompt,
                upstreamOutputs: [PipiTeamUpstreamOutput(actorId: doc.orchestrator.actorId, memberName: doc.orchestrator.name, output: classifyResp.output)]
            ))
            trace.append(PipiTeamExecutionTraceEntry(
                phase: .execute, round: 1, actorId: chosen.actorId, memberName: chosen.name, output: actResp.output
            ))
            return PipiTeamExecutionResult(
                pattern: doc.pattern,
                roundsExecuted: 1,
                winnerActorId: chosen.actorId,
                verifiedApproved: nil,
                completed: true,
                finalOutput: actResp.output,
                trace: trace
            )

        case .fanOutAndSynthesize:
            let validation = parseAndValidate(renderTemplate(
                pattern: doc.pattern,
                taskGoal: doc.taskGoal,
                orchestrator: doc.orchestrator,
                members: doc.members,
                maxRounds: doc.maxRounds
            ))
            let waves = validation.executionWaves.isEmpty ? [doc.members.map(\.actorId)] : validation.executionWaves
            var collected: [PipiTeamUpstreamOutput] = []

            for (wIdx, wave) in waves.enumerated() {
                let upstreamSnap = collected
                let waveItems = try await withThrowingTaskGroup(of: (Int, PipiTeamParticipant, String)?.self) { group in
                    for (offset, actorId) in wave.enumerated() {
                        guard let member = memberById[actorId] else { continue }
                        group.addTask {
                            let resp = try await executor(PipiTeamBotTurnRequest(
                                actorId: member.actorId,
                                memberName: member.name,
                                role: member.role,
                                pattern: doc.pattern,
                                phase: .execute,
                                round: wIdx + 1,
                                prompt: userPrompt,
                                upstreamOutputs: upstreamSnap
                            ))
                            return (offset, member, resp.output)
                        }
                    }
                    var out: [(Int, PipiTeamParticipant, String)] = []
                    for try await item in group {
                        if let item { out.append(item) }
                    }
                    return out.sorted { $0.0 < $1.0 }
                }

                for (_, member, output) in waveItems {
                    collected.append(PipiTeamUpstreamOutput(actorId: member.actorId, memberName: member.name, output: output))
                    trace.append(PipiTeamExecutionTraceEntry(
                        phase: .execute, round: wIdx + 1, actorId: member.actorId, memberName: member.name, output: output
                    ))
                }
            }

            let synthResp = try await executor(PipiTeamBotTurnRequest(
                actorId: doc.orchestrator.actorId,
                memberName: doc.orchestrator.name,
                role: doc.orchestrator.role,
                pattern: doc.pattern,
                phase: .synthesize,
                round: waves.count + 1,
                prompt: "Synthesize all teammate outputs for: \(userPrompt)",
                upstreamOutputs: collected
            ))
            trace.append(PipiTeamExecutionTraceEntry(
                phase: .synthesize, round: waves.count + 1, actorId: doc.orchestrator.actorId,
                memberName: doc.orchestrator.name, output: synthResp.output
            ))
            return PipiTeamExecutionResult(
                pattern: doc.pattern,
                roundsExecuted: waves.count,
                winnerActorId: nil,
                verifiedApproved: nil,
                completed: true,
                finalOutput: synthResp.output,
                trace: trace
            )

        case .adversarialVerification:
            let producer = doc.members[0]
            let verifier = doc.members.count > 1 ? doc.members[1] : doc.orchestrator
            let maxRounds = max(1, min(maxAllowedRounds, doc.maxRounds))
            var latestDraft = ""
            var latestCritique = ""
            var approved = false
            var rounds = 0

            for r in 1...maxRounds {
                rounds = r
                let prodResp = try await executor(PipiTeamBotTurnRequest(
                    actorId: producer.actorId,
                    memberName: producer.name,
                    role: producer.role,
                    pattern: doc.pattern,
                    phase: .execute,
                    round: r,
                    prompt: r == 1 ? userPrompt : "Revise draft addressing verifier feedback:\n\(latestCritique)",
                    upstreamOutputs: latestCritique.isEmpty
                        ? []
                        : [PipiTeamUpstreamOutput(actorId: verifier.actorId, memberName: verifier.name, output: latestCritique)]
                ))
                latestDraft = prodResp.output
                trace.append(PipiTeamExecutionTraceEntry(
                    phase: .execute, round: r, actorId: producer.actorId, memberName: producer.name, output: latestDraft
                ))

                let verResp = try await executor(PipiTeamBotTurnRequest(
                    actorId: verifier.actorId,
                    memberName: verifier.name,
                    role: verifier.role,
                    pattern: doc.pattern,
                    phase: .verify,
                    round: r,
                    prompt: "Adversarially verify draft against goal (\(doc.taskGoal)):\n\(latestDraft)",
                    upstreamOutputs: [PipiTeamUpstreamOutput(actorId: producer.actorId, memberName: producer.name, output: latestDraft)]
                ))
                latestCritique = verResp.output
                trace.append(PipiTeamExecutionTraceEntry(
                    phase: .verify, round: r, actorId: verifier.actorId, memberName: verifier.name, output: latestCritique
                ))
                if verResp.approved == true {
                    approved = true
                    break
                }
            }

            return PipiTeamExecutionResult(
                pattern: doc.pattern,
                roundsExecuted: rounds,
                winnerActorId: nil,
                verifiedApproved: approved,
                completed: approved,
                finalOutput: latestDraft,
                trace: trace
            )

        case .tournament:
            let submissions = try await withThrowingTaskGroup(of: (Int, PipiTeamUpstreamOutput).self) { group in
                for (idx, member) in doc.members.enumerated() {
                    group.addTask {
                        let resp = try await executor(PipiTeamBotTurnRequest(
                            actorId: member.actorId,
                            memberName: member.name,
                            role: member.role,
                            pattern: doc.pattern,
                            phase: .execute,
                            round: 1,
                            prompt: userPrompt,
                            upstreamOutputs: []
                        ))
                        return (idx, PipiTeamUpstreamOutput(actorId: member.actorId, memberName: member.name, output: resp.output))
                    }
                }
                var out: [(Int, PipiTeamUpstreamOutput)] = []
                for try await item in group { out.append(item) }
                return out.sorted { $0.0 < $1.0 }.map(\.1)
            }
            for sub in submissions {
                trace.append(PipiTeamExecutionTraceEntry(
                    phase: .execute, round: 1, actorId: sub.actorId, memberName: sub.memberName, output: sub.output
                ))
            }

            let judgeResp = try await executor(PipiTeamBotTurnRequest(
                actorId: doc.orchestrator.actorId,
                memberName: doc.orchestrator.name,
                role: doc.orchestrator.role,
                pattern: doc.pattern,
                phase: .judge,
                round: 2,
                prompt: "Judge competing tournament entries for: \(userPrompt)",
                upstreamOutputs: submissions
            ))
            trace.append(PipiTeamExecutionTraceEntry(
                phase: .judge, round: 2, actorId: doc.orchestrator.actorId,
                memberName: doc.orchestrator.name, output: judgeResp.output
            ))
            let winnerId = judgeResp.selectedActorId.flatMap { cand in
                submissions.contains(where: { $0.actorId == cand }) ? cand : nil
            } ?? submissions.first?.actorId

            return PipiTeamExecutionResult(
                pattern: doc.pattern,
                roundsExecuted: 1,
                winnerActorId: winnerId,
                verifiedApproved: nil,
                completed: true,
                finalOutput: judgeResp.output,
                trace: trace
            )

        case .loopUntilDone:
            let worker = doc.members[0]
            let maxRounds = max(1, min(maxAllowedRounds, doc.maxRounds))
            var lastOutput = ""
            var done = false
            var rounds = 0

            for r in 1...maxRounds {
                rounds = r
                let resp = try await executor(PipiTeamBotTurnRequest(
                    actorId: worker.actorId,
                    memberName: worker.name,
                    role: worker.role,
                    pattern: doc.pattern,
                    phase: .loopStep,
                    round: r,
                    prompt: r == 1 ? userPrompt : "Continue iterating toward goal (\(doc.taskGoal)). Previous:\n\(lastOutput)",
                    upstreamOutputs: lastOutput.isEmpty
                        ? []
                        : [PipiTeamUpstreamOutput(actorId: worker.actorId, memberName: worker.name, output: lastOutput)]
                ))
                lastOutput = resp.output
                trace.append(PipiTeamExecutionTraceEntry(
                    phase: .loopStep, round: r, actorId: worker.actorId, memberName: worker.name, output: lastOutput
                ))
                if resp.done == true {
                    done = true
                    break
                }
            }

            return PipiTeamExecutionResult(
                pattern: doc.pattern,
                roundsExecuted: rounds,
                winnerActorId: nil,
                verifiedApproved: nil,
                completed: done,
                finalOutput: lastOutput,
                trace: trace
            )
        }
    }
}
