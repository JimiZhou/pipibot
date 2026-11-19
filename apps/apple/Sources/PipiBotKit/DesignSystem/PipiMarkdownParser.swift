import Foundation

public enum PipiMarkdownBlock: Identifiable, Equatable, Sendable {
    case thinking(id: Int, text: String, isOpen: Bool)
    case prose(id: Int, text: String)
    case code(id: Int, language: String, code: String)
    case diff(id: Int, code: String)
    case terminal(id: Int, language: String, code: String)
    case table(id: Int, headers: [String], rows: [[String]])

    public var id: Int {
        switch self {
        case .thinking(let id, _, _): return id
        case .prose(let id, _): return id
        case .code(let id, _, _): return id
        case .diff(let id, _): return id
        case .terminal(let id, _, _): return id
        case .table(let id, _, _): return id
        }
    }
}

public enum PipiMarkdownParser {
    private final class CachedBlocksBox: NSObject {
        let blocks: [PipiMarkdownBlock]
        init(_ blocks: [PipiMarkdownBlock]) {
            self.blocks = blocks
        }
    }

    private nonisolated(unsafe) static let parsedBlocksCache: NSCache<NSString, CachedBlocksBox> = {
        let cache = NSCache<NSString, CachedBlocksBox>()
        cache.countLimit = 256
        return cache
    }()

    public static func parseBlocksCached(_ raw: String) -> [PipiMarkdownBlock] {
        let key = raw as NSString
        if let hit = parsedBlocksCache.object(forKey: key) {
            return hit.blocks
        }
        let parsed = parseBlocks(raw)
        parsedBlocksCache.setObject(CachedBlocksBox(parsed), forKey: key)
        return parsed
    }

    public static func parseBlocks(_ raw: String) -> [PipiMarkdownBlock] {
        var result: [PipiMarkdownBlock] = []
        var nextId = 0

        let segments = extractThinkingSegments(raw)

        for seg in segments {
            switch seg {
            case .thinking(let text, let isOpen):
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty || isOpen {
                    result.append(.thinking(id: nextId, text: cleaned, isOpen: isOpen))
                    nextId += 1
                }
            case .standard(let body):
                let parsed = parseStandardMarkdown(body, startId: &nextId)
                result.append(contentsOf: parsed)
            }
        }

        if result.isEmpty && !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(.prose(id: 0, text: raw))
        }
        return result
    }

    private enum TopSegment {
        case thinking(String, isOpen: Bool)
        case standard(String)
    }

    private static func extractThinkingSegments(_ raw: String) -> [TopSegment] {
        let openTags = ["<think>", "<thinking>"]
        let closeTags = ["</think>", "</thinking>"]
        var out: [TopSegment] = []
        var cursor = raw.startIndex

        while cursor < raw.endIndex {
            var earliestOpen: (Range<String.Index>, String)? = nil
            for tag in openTags {
                if let range = raw.range(of: tag, options: .caseInsensitive, range: cursor..<raw.endIndex) {
                    if earliestOpen == nil || range.lowerBound < earliestOpen!.0.lowerBound {
                        earliestOpen = (range, tag)
                    }
                }
            }

            guard let (openRange, _) = earliestOpen else {
                let tail = String(raw[cursor..<raw.endIndex])
                if !tail.isEmpty { out.append(.standard(tail)) }
                break
            }

            if openRange.lowerBound > cursor {
                out.append(.standard(String(raw[cursor..<openRange.lowerBound])))
            }

            var earliestClose: Range<String.Index>? = nil
            for tag in closeTags {
                if let range = raw.range(of: tag, options: .caseInsensitive, range: openRange.upperBound..<raw.endIndex) {
                    if earliestClose == nil || range.lowerBound < earliestClose!.lowerBound {
                        earliestClose = range
                    }
                }
            }

            if let closeRange = earliestClose {
                let thought = String(raw[openRange.upperBound..<closeRange.lowerBound])
                out.append(.thinking(thought, isOpen: false))
                cursor = closeRange.upperBound
            } else {
                let thought = String(raw[openRange.upperBound..<raw.endIndex])
                out.append(.thinking(thought, isOpen: true))
                break
            }
        }
        return out
    }

    private static func parseStandardMarkdown(_ body: String, startId nextId: inout Int) -> [PipiMarkdownBlock] {
        var result: [PipiMarkdownBlock] = []
        var buffer: [String] = []
        var inCode = false
        var codeLang = ""

        func flushProseAndTables() {
            guard !buffer.isEmpty else { return }
            let subBlocks = splitProseAndTables(buffer, nextId: &nextId)
            result.append(contentsOf: subBlocks)
            buffer.removeAll()
        }

        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    let codeText = buffer.joined(separator: "\n")
                    result.append(classifyFencedBlock(id: nextId, language: codeLang, code: codeText))
                    nextId += 1
                    buffer.removeAll()
                    codeLang = ""
                    inCode = false
                } else {
                    flushProseAndTables()
                    codeLang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCode = true
                }
            } else {
                buffer.append(line)
            }
        }

        if !buffer.isEmpty {
            if inCode {
                let codeText = buffer.joined(separator: "\n")
                result.append(classifyFencedBlock(id: nextId, language: codeLang, code: codeText))
                nextId += 1
            } else {
                flushProseAndTables()
            }
        }

        return result
    }

    private static func classifyFencedBlock(id: Int, language: String, code: String) -> PipiMarkdownBlock {
        let lower = language.lowercased()
        if lower == "diff" || lower == "patch" || code.hasPrefix("diff --git") || code.hasPrefix("@@ ") {
            return .diff(id: id, code: code)
        }
        if ["bash", "sh", "zsh", "shell", "console", "terminal"].contains(lower) {
            return .terminal(id: id, language: lower, code: code)
        }
        return .code(id: id, language: language, code: code)
    }

    private static func splitProseAndTables(_ lines: [String], nextId: inout Int) -> [PipiMarkdownBlock] {
        var blocks: [PipiMarkdownBlock] = []
        var proseLines: [String] = []
        var i = 0

        func flushProse() {
            let text = proseLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                blocks.append(.prose(id: nextId, text: text))
                nextId += 1
            }
            proseLines.removeAll()
        }

        while i < lines.count {
            if i + 1 < lines.count,
               isTableRow(lines[i]),
               isTableSeparator(lines[i + 1]) {
                flushProse()
                let headers = parseTableCells(lines[i])
                i += 2
                var rows: [[String]] = []
                while i < lines.count && isTableRow(lines[i]) {
                    rows.append(parseTableCells(lines[i]))
                    i += 1
                }
                blocks.append(.table(id: nextId, headers: headers, rows: rows))
                nextId += 1
            } else {
                proseLines.append(lines[i])
                i += 1
            }
        }
        flushProse()
        return blocks
    }

    private static func isTableRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.contains("|") && t.count >= 3
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("|"), t.contains("-") else { return false }
        let allowed = CharacterSet(charactersIn: "|-: ")
        return t.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func parseTableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
