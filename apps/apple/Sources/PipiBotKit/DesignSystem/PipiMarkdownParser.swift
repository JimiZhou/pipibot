import Foundation

public enum PipiDiagramKind: String, Codable, Equatable, Sendable {
    case svg
    case mermaid
    case canvas
    case chart

    public var displayLabel: String {
        switch self {
        case .svg: return "SVG"
        case .mermaid: return "Mermaid"
        case .canvas: return "Canvas"
        case .chart: return "Chart"
        }
    }
}

public enum PipiMarkdownBlock: Identifiable, Equatable, Sendable {
    case thinking(id: Int, text: String, isOpen: Bool)
    case prose(id: Int, text: String)
    case code(id: Int, language: String, code: String)
    case diff(id: Int, code: String)
    case terminal(id: Int, language: String, code: String)
    case table(id: Int, headers: [String], rows: [[String]])
    case diagram(id: Int, kind: PipiDiagramKind, source: String, title: String?, isComplete: Bool)

    public var id: Int {
        switch self {
        case .thinking(let id, _, _): return id
        case .prose(let id, _): return id
        case .code(let id, _, _): return id
        case .diff(let id, _): return id
        case .terminal(let id, _, _): return id
        case .table(let id, _, _): return id
        case .diagram(let id, _, _, _, _): return id
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

    /// Sanitizes inline SVG/HTML diagram payloads to strip active script vectors before WebView rendering.
    public static func sanitizeDiagramSource(_ raw: String) -> String {
        var out = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let dangerousPatterns = [
            #"<script\b[\s\S]*?</script>"#,
            #"<foreignObject\b[\s\S]*?</foreignObject>"#,
            #"<iframe\b[\s\S]*?</iframe>"#,
            #"<object\b[\s\S]*?</object>"#,
            #"<embed\b[^>]*?/?>"#,
            #"\s+on[a-z]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#
        ]
        for p in dangerousPatterns {
            if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
            }
        }
        if let jsHrefRegex = try? NSRegularExpression(
            pattern: #"(xlink:href|href|src)\s*=\s*["']\s*(?:javascript:|data:text/html)[^"']*["']"#,
            options: [.caseInsensitive]
        ) {
            out = jsHrefRegex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "$1=\"#\"")
        }
        return out
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
        var codeInfo = ""

        func flushProseTablesAndRawSvg() {
            guard !buffer.isEmpty else { return }
            let subBlocks = splitRawSvgAndProseTables(buffer, nextId: &nextId)
            result.append(contentsOf: subBlocks)
            buffer.removeAll()
        }

        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    let codeText = buffer.joined(separator: "\n")
                    result.append(classifyFencedBlock(id: nextId, infoString: codeInfo, code: codeText, isComplete: true))
                    nextId += 1
                    buffer.removeAll()
                    codeInfo = ""
                    inCode = false
                } else {
                    flushProseTablesAndRawSvg()
                    codeInfo = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCode = true
                }
            } else {
                buffer.append(line)
            }
        }

        if !buffer.isEmpty {
            if inCode {
                let codeText = buffer.joined(separator: "\n")
                result.append(classifyFencedBlock(id: nextId, infoString: codeInfo, code: codeText, isComplete: false))
                nextId += 1
            } else {
                flushProseTablesAndRawSvg()
            }
        }

        return result
    }

    private static func parseFenceTitle(from info: String) -> String? {
        let patterns = [
            #"title\s*=\s*"([^"]+)""#,
            #"title\s*=\s*'([^']+)'"#,
            #"title\s*=\s*(\S+)"#
        ]
        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: info, range: NSRange(info.startIndex..., in: info)),
               let range = Range(match.range(at: 1), in: info) {
                let val = String(info[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !val.isEmpty { return val }
            }
        }
        return nil
    }

    private static func extractSvgTitle(from svg: String) -> String? {
        if let regex = try? NSRegularExpression(pattern: #"<title[^>]*>([\s\S]*?)</title>"#, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg)),
           let range = Range(match.range(at: 1), in: svg) {
            let t = String(svg[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return nil
    }

    private static func classifyFencedBlock(id: Int, infoString: String, code: String, isComplete: Bool) -> PipiMarkdownBlock {
        let firstToken = infoString.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        let lower = firstToken.lowercased()
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = parseFenceTitle(from: infoString)

        if lower == "svg" || (lower == "xml" && trimmedCode.lowercased().hasPrefix("<svg")) {
            let cleaned = sanitizeDiagramSource(trimmedCode)
            return .diagram(id: id, kind: .svg, source: cleaned, title: title ?? extractSvgTitle(from: cleaned), isComplete: isComplete)
        }
        if lower == "mermaid" || lower == "mmd" {
            return .diagram(id: id, kind: .mermaid, source: trimmedCode, title: title, isComplete: isComplete)
        }
        if lower == "chart" || lower == "xychart" || lower == "plot" {
            return .diagram(id: id, kind: .chart, source: trimmedCode, title: title, isComplete: isComplete)
        }
        if lower == "canvas" || lower == "diagram" || lower == "html-diagram" {
            let cleaned = sanitizeDiagramSource(trimmedCode)
            return .diagram(id: id, kind: .canvas, source: cleaned, title: title, isComplete: isComplete)
        }
        if lower == "diff" || lower == "patch" || code.hasPrefix("diff --git") || code.hasPrefix("@@ ") {
            return .diff(id: id, code: code)
        }
        if ["bash", "sh", "zsh", "shell", "console", "terminal"].contains(lower) {
            return .terminal(id: id, language: lower, code: code)
        }
        return .code(id: id, language: firstToken, code: code)
    }

    /// Detects standalone raw `<svg ...>...</svg>` blocks directly inside Markdown prose (streaming-safe).
    private static func splitRawSvgAndProseTables(_ lines: [String], nextId: inout Int) -> [PipiMarkdownBlock] {
        let joined = lines.joined(separator: "\n")
        guard joined.range(of: "<svg", options: .caseInsensitive) != nil else {
            return splitProseAndTables(lines, nextId: &nextId)
        }

        var blocks: [PipiMarkdownBlock] = []
        var cursor = joined.startIndex

        while cursor < joined.endIndex {
            guard let openRange = joined.range(of: "<svg", options: .caseInsensitive, range: cursor..<joined.endIndex) else {
                let tail = String(joined[cursor..<joined.endIndex])
                if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(contentsOf: splitProseAndTables(tail.components(separatedBy: .newlines), nextId: &nextId))
                }
                break
            }

            if openRange.lowerBound > cursor {
                let before = String(joined[cursor..<openRange.lowerBound])
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(contentsOf: splitProseAndTables(before.components(separatedBy: .newlines), nextId: &nextId))
                }
            }

            if let closeRange = joined.range(of: "</svg>", options: .caseInsensitive, range: openRange.lowerBound..<joined.endIndex) {
                let rawSvg = String(joined[openRange.lowerBound..<closeRange.upperBound])
                let cleaned = sanitizeDiagramSource(rawSvg)
                blocks.append(.diagram(
                    id: nextId,
                    kind: .svg,
                    source: cleaned,
                    title: extractSvgTitle(from: cleaned),
                    isComplete: true
                ))
                nextId += 1
                cursor = closeRange.upperBound
            } else {
                // Streaming unclosed `<svg ...` block
                let partialSvg = String(joined[openRange.lowerBound..<joined.endIndex])
                blocks.append(.diagram(
                    id: nextId,
                    kind: .svg,
                    source: sanitizeDiagramSource(partialSvg),
                    title: nil,
                    isComplete: false
                ))
                nextId += 1
                break
            }
        }

        return blocks
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
