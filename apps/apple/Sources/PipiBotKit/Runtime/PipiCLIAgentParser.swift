import Foundation

public enum PipiParsedCLIEvent: Sendable, Equatable {
    case sessionId(String)
    case textDelta(String)
    case finalText(String)
    case planUpdated([PipiPlanItem])
    case stepStarted(PipiStepEvent)
    case stepFinished(id: String, status: PipiStepEvent.Status, detail: String?, durationMs: Int?, exitCode: Int?)
    case fileChanged(PipiFileChange)
    case summary(PipiSessionSummaryInfo)
}

/// Defensive JSONL parser for Claude Code (`--output-format stream-json --verbose`)
/// and Codex CLI (`exec --json`). Unknown JSON events are ignored; non-JSON lines
/// are treated as plain text deltas.
public struct PipiCLIAgentParser: Sendable {
    public let kind: PipiLocalAgentKind
    private var lineBuffer: String = ""
    private var sawTextDeltas: Bool = false
    private var streamedItemIds: Set<String> = []
    private var stepStartTimes: [String: Date] = [:]

    public init(kind: PipiLocalAgentKind) {
        self.kind = kind
    }

    public mutating func feedChunk(_ chunk: String) -> [PipiParsedCLIEvent] {
        guard !chunk.isEmpty else { return [] }
        if kind == .opencode {
            return [.textDelta(chunk)]
        }

        lineBuffer += chunk
        var events: [PipiParsedCLIEvent] = []

        while let newlineIdx = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<newlineIdx])
            lineBuffer.removeSubrange(...newlineIdx)
            events.append(contentsOf: parseLine(line))
        }
        return events
    }

    public mutating func finish() -> [PipiParsedCLIEvent] {
        let remaining = lineBuffer
        lineBuffer = ""
        guard !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        if kind == .opencode {
            return [.textDelta(remaining)]
        }
        return parseLine(remaining)
    }

    public mutating func parseLine(_ rawLine: String) -> [PipiParsedCLIEvent] {
        if kind == .opencode {
            return rawLine.isEmpty ? [] : [.textDelta(rawLine)]
        }

        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Non-JSON lines are treated defensively as text.
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            sawTextDeltas = true
            return [.textDelta(rawLine + (rawLine.hasSuffix("\n") ? "" : "\n"))]
        }

        switch kind {
        case .claudeCode:
            return parseClaudeEvent(json)
        case .codex:
            return parseCodexEvent(json)
        case .opencode:
            return [.textDelta(rawLine)]
        }
    }

    // MARK: - Claude Code stream-json

    private mutating func parseClaudeEvent(_ json: [String: Any]) -> [PipiParsedCLIEvent] {
        var out: [PipiParsedCLIEvent] = []

        if let sid = json["session_id"] as? String, !sid.isEmpty {
            out.append(.sessionId(sid))
        }

        let type = (json["type"] as? String) ?? ""
        switch type {
        case "system":
            break

        case "stream_event":
            if let event = json["event"] as? [String: Any] {
                out.append(contentsOf: parseClaudeStreamInner(event))
            }

        case "content_block_delta":
            out.append(contentsOf: parseClaudeStreamInner(json))

        case "assistant":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    let blockType = (block["type"] as? String) ?? ""
                    if blockType == "text", let text = block["text"] as? String, !text.isEmpty {
                        if !sawTextDeltas {
                            out.append(.textDelta(text))
                        }
                    } else if blockType == "tool_use" {
                        let toolId = (block["id"] as? String) ?? "tool_\(UUID().uuidString.prefix(8).lowercased())"
                        let name = (block["name"] as? String) ?? "Tool"
                        let input = block["input"] as? [String: Any] ?? [:]

                        stepStartTimes[toolId] = Date()
                        let step = Self.makeStep(id: toolId, toolName: name, input: input)
                        out.append(.stepStarted(step))

                        if let plan = Self.extractClaudePlanItems(toolName: name, input: input) {
                            out.append(.planUpdated(plan))
                        }
                        if let fileChange = Self.extractClaudeFileChange(toolName: name, input: input) {
                            out.append(.fileChanged(fileChange))
                        }
                    }
                }
            }

        case "user":
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content where (block["type"] as? String) == "tool_result" {
                    let toolId = (block["tool_use_id"] as? String) ?? ""
                    guard !toolId.isEmpty else { continue }
                    let isError = (block["is_error"] as? Bool) ?? false
                    let detail = Self.extractToolResultText(block["content"])
                    let durationMs: Int? = stepStartTimes.removeValue(forKey: toolId).map {
                        max(1, Int(Date().timeIntervalSince($0) * 1000))
                    }
                    out.append(.stepFinished(
                        id: toolId,
                        status: isError ? .failed : .succeeded,
                        detail: detail,
                        durationMs: durationMs,
                        exitCode: isError ? 1 : 0
                    ))
                }
            }

        case "result":
            let isError = (json["is_error"] as? Bool) ?? false
            let durationMs = json["duration_ms"] as? Int
            let resultText = (json["result"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let resultText, !resultText.isEmpty {
                if !sawTextDeltas {
                    out.append(.textDelta(resultText))
                }
                out.append(.finalText(resultText))
            }
            if let resultText, !resultText.isEmpty {
                out.append(.summary(PipiSessionSummaryInfo(
                    conclusion: resultText,
                    exitCode: isError ? 1 : 0,
                    testSummary: nil,
                    changedFilesCount: 0,
                    durationMs: durationMs
                )))
            }

        default:
            // Unknown events are safely ignored.
            break
        }

        return out
    }

    private mutating func parseClaudeStreamInner(_ event: [String: Any]) -> [PipiParsedCLIEvent] {
        let innerType = (event["type"] as? String) ?? ""
        if innerType == "content_block_delta",
           let delta = event["delta"] as? [String: Any],
           (delta["type"] as? String) == "text_delta",
           let text = delta["text"] as? String,
           !text.isEmpty {
            sawTextDeltas = true
            return [.textDelta(text)]
        }
        return []
    }

    // MARK: - Codex exec --json

    private mutating func parseCodexEvent(_ json: [String: Any]) -> [PipiParsedCLIEvent] {
        var out: [PipiParsedCLIEvent] = []

        if let tid = json["thread_id"] as? String, !tid.isEmpty {
            out.append(.sessionId(tid))
        } else if let sid = json["session_id"] as? String, !sid.isEmpty {
            out.append(.sessionId(sid))
        }

        let type = (json["type"] as? String) ?? ""
        switch type {
        case "thread.started", "turn.started":
            break

        case "item.delta", "agent_message_delta", "response.output_text.delta":
            if let itemId = json["item_id"] as? String, !itemId.isEmpty {
                streamedItemIds.insert(itemId)
            }
            if let delta = (json["delta"] as? String) ?? (json["text"] as? String), !delta.isEmpty {
                sawTextDeltas = true
                out.append(.textDelta(delta))
            }

        case "item.started", "item.updated", "item.completed":
            guard let item = json["item"] as? [String: Any] else { break }
            let itemId = (item["id"] as? String) ?? "codex_\(UUID().uuidString.prefix(8).lowercased())"
            let itemType = (item["type"] as? String) ?? ""
            let isCompleted = (type == "item.completed") || ((item["status"] as? String) == "completed")

            switch itemType {
            case "agent_message":
                if isCompleted, let text = item["text"] as? String, !text.isEmpty {
                    if !streamedItemIds.contains(itemId) {
                        sawTextDeltas = true
                        out.append(.textDelta(text))
                    }
                    out.append(.finalText(text))
                }

            case "command_execution":
                let command = (item["command"] as? String) ?? ""
                if type == "item.started" {
                    stepStartTimes[itemId] = Date()
                    out.append(.stepStarted(PipiStepEvent(
                        id: itemId,
                        verbPhrase: command.isEmpty ? "Run command" : "Run \(Self.shortCommand(command))",
                        detail: command,
                        toolName: "Bash",
                        status: .running
                    )))
                } else if isCompleted {
                    let exitCode = item["exit_code"] as? Int
                    let failed = (item["status"] as? String) == "failed" || (exitCode != nil && exitCode != 0)
                    let durationMs: Int? = (item["duration_ms"] as? Int) ?? stepStartTimes.removeValue(forKey: itemId).map {
                        max(1, Int(Date().timeIntervalSince($0) * 1000))
                    }
                    let output = (item["aggregated_output"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let detailText = Self.compactDetail(command: command, output: output)
                    if stepStartTimes[itemId] == nil && type == "item.completed" && durationMs == nil {
                        // Emit complete step if started event wasn't seen
                        out.append(.stepStarted(PipiStepEvent(
                            id: itemId,
                            verbPhrase: command.isEmpty ? "Run command" : "Run \(Self.shortCommand(command))",
                            detail: detailText,
                            toolName: "Bash",
                            status: failed ? .failed : .succeeded,
                            durationMs: item["duration_ms"] as? Int,
                            exitCode: exitCode
                        )))
                    } else {
                        out.append(.stepFinished(
                            id: itemId,
                            status: failed ? .failed : .succeeded,
                            detail: detailText,
                            durationMs: durationMs,
                            exitCode: exitCode
                        ))
                    }
                }

            case "file_change":
                if let changes = item["changes"] as? [[String: Any]] {
                    for ch in changes {
                        if let path = ch["path"] as? String, !path.isEmpty {
                            let kindStr = (ch["kind"] as? String) ?? "update"
                            let diff = (ch["diff"] as? String) ?? (ch["patch"] as? String)
                            let counts = Self.countDiffLines(diff)
                            let adds = (ch["additions"] as? Int) ?? counts.additions
                            let dels = (ch["deletions"] as? Int) ?? counts.deletions
                            out.append(.fileChanged(PipiFileChange(
                                path: path,
                                additions: adds,
                                deletions: dels,
                                diffPreview: diff,
                                operation: kindStr
                            )))
                        }
                    }
                    if isCompleted {
                        let summaryName = changes.compactMap { ($0["path"] as? String).map { ($0 as NSString).lastPathComponent } }.joined(separator: ", ")
                        out.append(.stepStarted(PipiStepEvent(
                            id: itemId,
                            verbPhrase: summaryName.isEmpty ? "Edit files" : "Edit \(summaryName)",
                            detail: summaryName,
                            toolName: "Edit",
                            status: (item["status"] as? String) == "failed" ? .failed : .succeeded
                        )))
                    }
                }

            case "todo_list":
                if let items = item["items"] as? [[String: Any]] {
                    let plan = items.enumerated().compactMap { idx, entry -> PipiPlanItem? in
                        guard let text = entry["text"] as? String, !text.isEmpty else { return nil }
                        let done = (entry["completed"] as? Bool) ?? false
                        return PipiPlanItem(id: "codex_plan_\(idx)", title: text, isCompleted: done)
                    }
                    if !plan.isEmpty {
                        out.append(.planUpdated(plan))
                    }
                }

            case "mcp_tool_call", "web_search", "function_call":
                let name = (item["tool"] as? String) ?? (item["name"] as? String) ?? itemType
                if type == "item.started" {
                    stepStartTimes[itemId] = Date()
                    out.append(.stepStarted(PipiStepEvent(
                        id: itemId,
                        verbPhrase: "Call \(name)",
                        detail: item["server"] as? String,
                        toolName: name,
                        status: .running
                    )))
                } else if isCompleted {
                    let failed = (item["status"] as? String) == "failed"
                    let durationMs = stepStartTimes.removeValue(forKey: itemId).map { max(1, Int(Date().timeIntervalSince($0) * 1000)) }
                    out.append(.stepFinished(
                        id: itemId,
                        status: failed ? .failed : .succeeded,
                        detail: item["server"] as? String,
                        durationMs: durationMs,
                        exitCode: nil
                    ))
                }

            default:
                break
            }

        case "error", "turn.failed":
            let errText: String? = (json["message"] as? String)
                ?? ((json["error"] as? [String: Any])?["message"] as? String)
            if let errText, !errText.isEmpty {
                out.append(.stepStarted(PipiStepEvent(
                    verbPhrase: "Error",
                    detail: errText,
                    toolName: "error",
                    status: .failed
                )))
            }

        default:
            // Unknown Codex events are safely ignored.
            break
        }

        return out
    }

    // MARK: - Tool & Diff Helpers

    private static func makeStep(id: String, toolName: String, input: [String: Any]) -> PipiStepEvent {
        let lower = toolName.lowercased()
        let filePath = (input["file_path"] as? String) ?? (input["path"] as? String)
        let command = input["command"] as? String
        let pattern = input["pattern"] as? String

        let verb: String
        let detail: String?

        switch lower {
        case "read":
            let name = filePath.map { ($0 as NSString).lastPathComponent } ?? "file"
            verb = "Read \(name)"
            detail = filePath
        case "edit", "multiedit", "write", "notebookedit":
            let name = filePath.map { ($0 as NSString).lastPathComponent } ?? "file"
            verb = (lower == "write" ? "Write " : "Edit ") + name
            detail = filePath
        case "bash":
            verb = command.map { "Run \(shortCommand($0))" } ?? "Run command"
            detail = command
        case "grep", "glob":
            verb = pattern.map { "Search “\($0)”" } ?? "Search files"
            detail = pattern ?? (input["path"] as? String)
        case "todowrite":
            verb = "Update plan"
            detail = nil
        default:
            verb = toolName
            detail = filePath ?? command ?? pattern
        }

        return PipiStepEvent(
            id: id,
            verbPhrase: verb,
            detail: detail,
            toolName: toolName,
            status: .running
        )
    }

    private static func extractClaudePlanItems(toolName: String, input: [String: Any]) -> [PipiPlanItem]? {
        guard toolName.lowercased() == "todowrite",
              let todos = input["todos"] as? [[String: Any]] else {
            return nil
        }
        let items = todos.enumerated().compactMap { idx, todo -> PipiPlanItem? in
            let title = (todo["content"] as? String) ?? (todo["title"] as? String) ?? ""
            guard !title.isEmpty else { return nil }
            let status = (todo["status"] as? String) ?? ""
            let completed = (status == "completed") || ((todo["completed"] as? Bool) ?? false)
            return PipiPlanItem(id: "claude_plan_\(idx)", title: title, isCompleted: completed)
        }
        return items.isEmpty ? nil : items
    }

    private static func extractClaudeFileChange(toolName: String, input: [String: Any]) -> PipiFileChange? {
        let lower = toolName.lowercased()
        guard ["edit", "write", "multiedit"].contains(lower) else { return nil }
        guard let filePath = (input["file_path"] as? String) ?? (input["path"] as? String), !filePath.isEmpty else {
            return nil
        }
        let oldStr = (input["old_string"] as? String) ?? ""
        let newStr = (input["new_string"] as? String) ?? (input["content"] as? String) ?? ""
        let oldLines = oldStr.isEmpty ? 0 : oldStr.components(separatedBy: .newlines).count
        let newLines = newStr.isEmpty ? 0 : newStr.components(separatedBy: .newlines).count

        var previewLines: [String] = []
        if !oldStr.isEmpty {
            previewLines.append(contentsOf: oldStr.components(separatedBy: .newlines).prefix(20).map { "- \($0)" })
        }
        if !newStr.isEmpty {
            previewLines.append(contentsOf: newStr.components(separatedBy: .newlines).prefix(20).map { "+ \($0)" })
        }

        return PipiFileChange(
            path: filePath,
            additions: newLines,
            deletions: oldLines,
            diffPreview: previewLines.isEmpty ? nil : previewLines.joined(separator: "\n"),
            operation: lower == "write" ? "write" : "edit"
        )
    }

    private static func extractToolResultText(_ raw: Any?) -> String? {
        if let str = raw as? String {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(240))
        }
        if let blocks = raw as? [[String: Any]] {
            let joined = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return joined.isEmpty ? nil : String(joined.prefix(240))
        }
        return nil
    }

    private static func shortCommand(_ cmd: String) -> String {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 36 { return trimmed }
        return String(trimmed.prefix(36)) + "…"
    }

    private static func compactDetail(command: String, output: String?) -> String? {
        if let output, !output.isEmpty {
            let shortOut = String(output.prefix(200))
            return command.isEmpty ? shortOut : "\(command)\n\(shortOut)"
        }
        return command.isEmpty ? nil : command
    }

    private static func countDiffLines(_ diff: String?) -> (additions: Int, deletions: Int) {
        guard let diff, !diff.isEmpty else { return (0, 0) }
        var adds = 0
        var dels = 0
        for line in diff.components(separatedBy: .newlines) {
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                adds += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                dels += 1
            }
        }
        return (adds, dels)
    }
}
