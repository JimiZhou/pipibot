// PiPiBot — Clean-room MIT implementation.
// Wave 2 (#01): Personal Entity Wiki + Dual-Channel Zero-Embedding Search + Native SQLite3 WAL & FTS5.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

import CryptoKit
import Foundation
import SQLite3

// MARK: - 1. Public Wiki Models

public enum PipiWikiPageStatus: String, Codable, CaseIterable, Sendable, Equatable {
    case draft
    case stable
    case deprecated
}

public struct PipiWikiFactInput: Codable, Equatable, Sendable {
    public var factText: String
    public var entities: [String]
    public var eventDate: String?
    public var confidence: Double

    public init(
        factText: String,
        entities: [String] = [],
        eventDate: String? = nil,
        confidence: Double = 0.85
    ) {
        self.factText = factText
        self.entities = entities
        self.eventDate = eventDate
        self.confidence = confidence
    }
}

public struct PipiWikiPageInput: Sendable {
    public var id: String?
    public var slug: String?
    public var category: PipiWikiEntityCategory
    public var title: String
    public var aliases: [String]
    public var summary: String
    public var bodyMarkdown: String
    public var tags: [String]
    public var sourceRefs: [String]
    public var eventDate: String?
    public var status: PipiWikiPageStatus
    public var facts: [PipiWikiFactInput]
    public var optionalEmbedding: [Double]?

    public init(
        id: String? = nil,
        slug: String? = nil,
        category: PipiWikiEntityCategory,
        title: String,
        aliases: [String] = [],
        summary: String,
        bodyMarkdown: String,
        tags: [String] = [],
        sourceRefs: [String] = [],
        eventDate: String? = nil,
        status: PipiWikiPageStatus = .stable,
        facts: [PipiWikiFactInput] = [],
        optionalEmbedding: [Double]? = nil
    ) {
        self.id = id
        self.slug = slug
        self.category = category
        self.title = title
        self.aliases = aliases
        self.summary = summary
        self.bodyMarkdown = bodyMarkdown
        self.tags = tags
        self.sourceRefs = sourceRefs
        self.eventDate = eventDate
        self.status = status
        self.facts = facts
        self.optionalEmbedding = optionalEmbedding
    }
}

public struct PipiPersonalWikiPage: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var slug: String
    public var category: PipiWikiEntityCategory
    public var title: String
    public var aliases: [String]
    public var summary: String
    public var bodyMarkdown: String
    public var tags: [String]
    public var sourceRefs: [String]
    public var eventDate: String?
    public var status: PipiWikiPageStatus
    public var contentHash: String
    public let createdAt: String
    public var updatedAt: String

    public init(
        id: String,
        slug: String,
        category: PipiWikiEntityCategory,
        title: String,
        aliases: [String],
        summary: String,
        bodyMarkdown: String,
        tags: [String],
        sourceRefs: [String],
        eventDate: String?,
        status: PipiWikiPageStatus,
        contentHash: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.slug = slug
        self.category = category
        self.title = title
        self.aliases = aliases
        self.summary = summary
        self.bodyMarkdown = bodyMarkdown
        self.tags = tags
        self.sourceRefs = sourceRefs
        self.eventDate = eventDate
        self.status = status
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PipiWikiChunkHit: Identifiable, Equatable, Sendable {
    public var id: String { chunkId }
    public let chunkId: String
    public let pageId: String
    public let category: PipiWikiEntityCategory
    public let title: String
    public let sectionHeading: String
    public let content: String
    public let eventDate: String?
    public let inTimeWindow: Bool
    public let score: Double
}

public struct PipiWikiFactHit: Identifiable, Equatable, Sendable {
    public var id: String { factId }
    public let factId: String
    public let pageId: String
    public let chunkId: String?
    public let category: PipiWikiEntityCategory
    public let pageTitle: String
    public let factText: String
    public let entities: [String]
    public let eventDate: String?
    public let confidence: Double
    public let inTimeWindow: Bool
    public let score: Double
}

public struct PipiWikiSummaryHit: Identifiable, Equatable, Sendable {
    public var id: String { pageId }
    public let pageId: String
    public let slug: String
    public let category: PipiWikiEntityCategory
    public let title: String
    public let aliases: [String]
    public let summary: String
    public let eventDate: String?
    public let score: Double
    public let matchedAlias: String?
}

public struct PipiWikiSearchOptions: Sendable {
    public var query: String
    public var alternates: [String]
    public var startDate: String?
    public var endDate: String?
    public var category: PipiWikiEntityCategory?
    public var scope: PipiWikiSearchScope
    public var limit: Int
    public var factLimit: Int
    public var optionalQueryEmbedding: [Double]?

    public init(
        query: String,
        alternates: [String] = [],
        startDate: String? = nil,
        endDate: String? = nil,
        category: PipiWikiEntityCategory? = nil,
        scope: PipiWikiSearchScope = .all,
        limit: Int = 10,
        factLimit: Int = 12,
        optionalQueryEmbedding: [Double]? = nil
    ) {
        self.query = query
        self.alternates = alternates
        self.startDate = startDate
        self.endDate = endDate
        self.category = category
        self.scope = scope
        self.limit = limit
        self.factLimit = factLimit
        self.optionalQueryEmbedding = optionalQueryEmbedding
    }
}

public struct PipiWikiSearchResult: Equatable, Sendable {
    public let query: String
    public let effectiveQueries: [String]
    public let scope: PipiWikiSearchScope
    public let usedFts5: Bool
    public let usedVectorChannel: Bool
    public let chunks: [PipiWikiChunkHit]
    public let facts: [PipiWikiFactHit]
    public let summaries: [PipiWikiSummaryHit]
}

public enum PipiWikiStoreError: Error, LocalizedError, Sendable {
    case openFailed(String)
    case sqlFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "Failed to open SQLite wiki database: \(msg)"
        case .sqlFailed(let msg): return "SQLite wiki query failed: \(msg)"
        }
    }
}

// MARK: - 2. Secret Scrubber & CJK Bigram Tokenizer

public enum PipiWikiTextUtilities {
    public static let maxAlternates = 6
    public static let rrfK: Double = 60.0
    public static let softWindowBonusWeight: Double = 0.85

    private static let secretPatterns: [(category: String, regex: NSRegularExpression)] = {
        let defs: [(String, String)] = [
            ("PEM_PRIVATE_KEY", "-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----"),
            ("OPENAI_OR_SK_KEY", "\\bsk-(?:proj-|ant-|live-|test-)?[A-Za-z0-9_-]{20,}\\b"),
            ("GITHUB_TOKEN", "\\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\\b|\\bgithub_pat_[A-Za-z0-9_]{22,}\\b"),
            ("AWS_ACCESS_KEY", "\\bAKIA[0-9A-Z]{16}\\b"),
            ("BEARER_SECRET", "\\bBearer\\s+[A-Za-z0-9._~+/=-]{24,}\\b"),
        ]
        return defs.compactMap { cat, pat in
            guard let re = try? NSRegularExpression(pattern: pat, options: []) else { return nil }
            return (cat, re)
        }
    }()

    public static func scrubSecrets(_ input: String) -> String {
        var result = input
        for (category, regex) in secretPatterns {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = regex.matches(in: result, options: [], range: range).reversed()
            for match in matches {
                guard let swiftRange = Range(match.range, in: result) else { continue }
                let secret = String(result[swiftRange])
                let hashPrefix = sha256Hex(secret).prefix(8)
                result.replaceSubrange(swiftRange, with: "[REDACTED:\(category):\(hashPrefix)]")
            }
        }
        return result
    }

    public static func sha256Hex(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func expandTokensWithCjkBigrams(_ text: String) -> [String] {
        let lower = text.lowercased()
        var tokens: [String] = []
        var asciiBuffer = ""
        var cjkRun: [Character] = []

        func flushAscii() {
            let trimmed = asciiBuffer.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
            if trimmed.count >= 2 {
                tokens.append(trimmed)
            }
            asciiBuffer.removeAll(keepingCapacity: true)
        }

        func flushCjk() {
            guard !cjkRun.isEmpty else { return }
            if cjkRun.count == 1 {
                tokens.append(String(cjkRun[0]))
            } else {
                for i in 0..<(cjkRun.count - 1) {
                    tokens.append(String(cjkRun[i]) + String(cjkRun[i + 1]))
                }
                if cjkRun.count <= 4 {
                    tokens.append(String(cjkRun))
                }
            }
            cjkRun.removeAll(keepingCapacity: true)
        }

        for ch in lower {
            guard let scalar = ch.unicodeScalars.first else { continue }
            let v = scalar.value
            let isCjk = (0x3400...0x4DBF).contains(v)
                || (0x4E00...0x9FFF).contains(v)
                || (0x3040...0x30FF).contains(v)
                || (0xAC00...0xD7AF).contains(v)
            if isCjk {
                flushAscii()
                cjkRun.append(ch)
            } else if ch.isASCII && (ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == ".") {
                flushCjk()
                asciiBuffer.append(ch)
            } else {
                flushAscii()
                flushCjk()
            }
        }
        flushAscii()
        flushCjk()
        return tokens
    }

    public static func slugify(_ title: String, fallback: String) -> String {
        var out = ""
        var prevDash = false
        for ch in title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                prevDash = false
            } else if (ch.isWhitespace || ch == "-" || ch == "_") && !prevDash && !out.isEmpty {
                out.append("-")
                prevDash = true
            }
            if out.count >= 64 { break }
        }
        let cleaned = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cleaned.isEmpty ? fallback : cleaned
    }

    public static func splitMarkdownChunks(_ bodyMarkdown: String, maxChars: Int = 900) -> [(heading: String, content: String)] {
        let normalized = bodyMarkdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var sections: [(String, String)] = []
        var currentHeading = "Overview"
        var buffer: [String] = []

        func flush() {
            let raw = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeAll(keepingCapacity: true)
            guard !raw.isEmpty else { return }
            if raw.count <= maxChars {
                sections.append((currentHeading, raw))
                return
            }
            let paragraphs = raw.components(separatedBy: "\n\n")
            var acc = ""
            for para in paragraphs {
                if !acc.isEmpty && acc.count + para.count + 2 > maxChars {
                    sections.append((currentHeading, acc.trimmingCharacters(in: .whitespacesAndNewlines)))
                    acc = para
                } else {
                    acc = acc.isEmpty ? para : "\(acc)\n\n\(para)"
                }
            }
            let tail = acc.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                sections.append((currentHeading, tail))
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") {
                flush()
                currentHeading = trimmed.drop(while: { $0 == "#" || $0 == " " }).trimmingCharacters(in: .whitespaces)
                if currentHeading.isEmpty { currentHeading = "Overview" }
            } else {
                buffer.append(line)
            }
        }
        flush()

        if sections.isEmpty {
            let fallback = bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallback.isEmpty {
                sections.append(("Overview", fallback))
            }
        }
        return sections
    }

    public static func isWithinDateWindow(_ eventDate: String?, startDate: String?, endDate: String?) -> Bool {
        guard let eventDate, !eventDate.isEmpty, (startDate != nil || endDate != nil) else { return false }
        if let startDate, !startDate.isEmpty, eventDate < startDate { return false }
        if let endDate, !endDate.isEmpty, eventDate > endDate { return false }
        return true
    }

    public static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        var dot = 0.0
        var normA = 0.0
        var normB = 0.0
        for i in 0..<count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }
}

// MARK: - 3. PipiPersonalWikiStore (Native Apple SQLite3 WAL + FTS5 + Markdown Projection)

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class PipiPersonalWikiStore: @unchecked Sendable {
    public let dbPath: String
    public let markdownRootURL: URL?
    public private(set) var supportsFts5: Bool = false

    private let lock = NSLock()
    private var db: OpaquePointer?

    public static func defaultStorageDirectory() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("PipiBot", isDirectory: true)
    }

    public init(dbPath: String, markdownRootURL: URL? = nil) throws {
        self.dbPath = dbPath
        self.markdownRootURL = markdownRootURL

        if dbPath != ":memory:" {
            let parent = URL(fileURLWithPath: dbPath).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(dbPath, &handle, flags, nil)
        guard rc == SQLITE_OK, let opened = handle else {
            let errMsg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            if let handle { sqlite3_close(handle) }
            throw PipiWikiStoreError.openFailed(errMsg)
        }
        self.db = opened

        if dbPath != ":memory:" {
            try execLocked("PRAGMA journal_mode = WAL;")
        }
        try execLocked("PRAGMA synchronous = NORMAL;")
        try execLocked("PRAGMA busy_timeout = 5000;")
        try execLocked("PRAGMA foreign_keys = ON;")

        try createSchemaLocked()
        self.supportsFts5 = createFts5TablesLocked()
    }

    deinit {
        lock.lock()
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
        lock.unlock()
    }

    public func journalMode() -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return "closed" }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA journal_mode;", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW,
              let cStr = sqlite3_column_text(stmt, 0) else {
            return "unknown"
        }
        return String(cString: cStr).lowercased()
    }

    // MARK: - Schema Setup

    private func createSchemaLocked() throws {
        let ddl = """
        CREATE TABLE IF NOT EXISTS wiki_pages (
          id               TEXT PRIMARY KEY,
          slug             TEXT NOT NULL,
          category         TEXT NOT NULL,
          title            TEXT NOT NULL,
          aliases_json     TEXT NOT NULL DEFAULT '[]',
          summary          TEXT NOT NULL,
          body_markdown    TEXT NOT NULL,
          tags_json        TEXT NOT NULL DEFAULT '[]',
          source_refs_json TEXT NOT NULL DEFAULT '[]',
          event_date       TEXT,
          status           TEXT NOT NULL DEFAULT 'stable',
          content_hash     TEXT NOT NULL,
          created_at       TEXT NOT NULL,
          updated_at       TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_wiki_pages_category ON wiki_pages(category);
        CREATE INDEX IF NOT EXISTS idx_wiki_pages_event_date ON wiki_pages(event_date);

        CREATE TABLE IF NOT EXISTS wiki_chunks (
          id               TEXT PRIMARY KEY,
          page_id          TEXT NOT NULL REFERENCES wiki_pages(id) ON DELETE CASCADE,
          section_heading  TEXT NOT NULL,
          content          TEXT NOT NULL,
          token_count      INTEGER NOT NULL DEFAULT 0,
          event_date       TEXT,
          content_hash     TEXT NOT NULL,
          embedding_json   TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_wiki_chunks_page ON wiki_chunks(page_id);
        CREATE INDEX IF NOT EXISTS idx_wiki_chunks_date ON wiki_chunks(event_date);

        CREATE TABLE IF NOT EXISTS wiki_facts (
          id               TEXT PRIMARY KEY,
          page_id          TEXT NOT NULL REFERENCES wiki_pages(id) ON DELETE CASCADE,
          chunk_id         TEXT,
          fact_text        TEXT NOT NULL,
          entities_json    TEXT NOT NULL DEFAULT '[]',
          token_count      INTEGER NOT NULL DEFAULT 0,
          event_date       TEXT,
          confidence       REAL NOT NULL DEFAULT 0.85,
          created_at       TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_wiki_facts_page ON wiki_facts(page_id);
        CREATE INDEX IF NOT EXISTS idx_wiki_facts_date ON wiki_facts(event_date);
        """
        try execLocked(ddl)
    }

    private func createFts5TablesLocked() -> Bool {
        let ftsDdl = """
        CREATE VIRTUAL TABLE IF NOT EXISTS fts_wiki_chunks USING fts5(
          chunk_id UNINDEXED,
          page_id UNINDEXED,
          title_tokens,
          body_tokens,
          tokenize='unicode61'
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS fts_wiki_facts USING fts5(
          fact_id UNINDEXED,
          page_id UNINDEXED,
          fact_tokens,
          tokenize='unicode61'
        );
        """
        do {
            try execLocked(ftsDdl)
            return true
        } catch {
            return false
        }
    }

    private func execLocked(_ sql: String) throws {
        guard let db else { throw PipiWikiStoreError.sqlFailed("Database closed") }
        var errPtr: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errPtr)
        if rc != SQLITE_OK {
            let msg = errPtr.map { String(cString: $0) } ?? "SQLite error \(rc)"
            sqlite3_free(errPtr)
            throw PipiWikiStoreError.sqlFailed(msg)
        }
    }

    // MARK: - CRUD & Atomic Markdown Projection

    @discardableResult
    public func upsertPage(_ input: PipiWikiPageInput) throws -> PipiPersonalWikiPage {
        let nowIso = ISO8601DateFormatter().string(from: Date())
        let pageId = (input.id?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "wiki_\(UUID().uuidString.prefix(10).lowercased())"
        let cleanTitle = PipiWikiTextUtilities.scrubSecrets(input.title.trimmingCharacters(in: .whitespacesAndNewlines))
        let cleanSummary = PipiWikiTextUtilities.scrubSecrets(input.summary.trimmingCharacters(in: .whitespacesAndNewlines))
        let cleanBody = PipiWikiTextUtilities.scrubSecrets(input.bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines))
        let aliases = input.aliases
            .map { PipiWikiTextUtilities.scrubSecrets($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
        let tags = input.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let sourceRefs = input.sourceRefs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let slug = (input.slug?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? PipiWikiTextUtilities.slugify(cleanTitle, fallback: pageId)
        let contentHash = PipiWikiTextUtilities.sha256Hex(
            "\(input.category.rawValue)|\(cleanTitle)|\(aliases.joined(separator: ","))|\(cleanSummary)|\(cleanBody)|\(input.eventDate ?? "")"
        )

        let page: PipiPersonalWikiPage = try {
            lock.lock()
            defer { lock.unlock() }
            guard let db else { throw PipiWikiStoreError.sqlFailed("Database closed") }

            let createdAt = fetchCreatedAtLocked(pageId: pageId) ?? nowIso

            try execLocked("BEGIN IMMEDIATE;")
            do {
                if supportsFts5 {
                    try runDeleteLocked(sql: "DELETE FROM fts_wiki_chunks WHERE page_id = ?;", param: pageId)
                    try runDeleteLocked(sql: "DELETE FROM fts_wiki_facts WHERE page_id = ?;", param: pageId)
                }
                try runDeleteLocked(sql: "DELETE FROM wiki_chunks WHERE page_id = ?;", param: pageId)
                try runDeleteLocked(sql: "DELETE FROM wiki_facts WHERE page_id = ?;", param: pageId)

                let upsertSql = """
                INSERT INTO wiki_pages (
                  id, slug, category, title, aliases_json, summary, body_markdown,
                  tags_json, source_refs_json, event_date, status, content_hash, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  slug = excluded.slug,
                  category = excluded.category,
                  title = excluded.title,
                  aliases_json = excluded.aliases_json,
                  summary = excluded.summary,
                  body_markdown = excluded.body_markdown,
                  tags_json = excluded.tags_json,
                  source_refs_json = excluded.source_refs_json,
                  event_date = excluded.event_date,
                  status = excluded.status,
                  content_hash = excluded.content_hash,
                  updated_at = excluded.updated_at;
                """
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, upsertSql, -1, &stmt, nil) == SQLITE_OK else {
                    throw PipiWikiStoreError.sqlFailed(String(cString: sqlite3_errmsg(db)))
                }
                defer { sqlite3_finalize(stmt) }
                bindText(stmt, 1, pageId)
                bindText(stmt, 2, slug)
                bindText(stmt, 3, input.category.rawValue)
                bindText(stmt, 4, cleanTitle)
                bindText(stmt, 5, encodeJsonArray(aliases))
                bindText(stmt, 6, cleanSummary)
                bindText(stmt, 7, cleanBody)
                bindText(stmt, 8, encodeJsonArray(tags))
                bindText(stmt, 9, encodeJsonArray(sourceRefs))
                bindOptionalText(stmt, 10, input.eventDate)
                bindText(stmt, 11, input.status.rawValue)
                bindText(stmt, 12, contentHash)
                bindText(stmt, 13, createdAt)
                bindText(stmt, 14, nowIso)
                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw PipiWikiStoreError.sqlFailed(String(cString: sqlite3_errmsg(db)))
                }

                // Insert chunks + FTS5 tokens
                let sections = PipiWikiTextUtilities.splitMarkdownChunks(cleanBody.isEmpty ? cleanSummary : cleanBody)
                let titleHeader = ([cleanTitle] + aliases + tags).joined(separator: " ")
                let titleTokens = PipiWikiTextUtilities.expandTokensWithCjkBigrams(titleHeader).joined(separator: " ")
                let embeddingJson: String? = input.optionalEmbedding.flatMap { vec in
                    (try? JSONEncoder().encode(vec)).flatMap { String(data: $0, encoding: .utf8) }
                }

                var firstChunkId: String?
                for (idx, sec) in sections.enumerated() {
                    let chunkId = "\(pageId)_c\(idx)"
                    if firstChunkId == nil { firstChunkId = chunkId }
                    let bodyText = "\(sec.heading)\n\(sec.content)"
                    let bodyTokenArr = PipiWikiTextUtilities.expandTokensWithCjkBigrams("\(cleanSummary) \(bodyText)")
                    let bodyTokens = bodyTokenArr.joined(separator: " ")

                    var cStmt: OpaquePointer?
                    let cSql = """
                    INSERT INTO wiki_chunks (id, page_id, section_heading, content, token_count, event_date, content_hash, embedding_json)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?);
                    """
                    guard sqlite3_prepare_v2(db, cSql, -1, &cStmt, nil) == SQLITE_OK else {
                        throw PipiWikiStoreError.sqlFailed(String(cString: sqlite3_errmsg(db)))
                    }
                    defer { sqlite3_finalize(cStmt) }
                    bindText(cStmt, 1, chunkId)
                    bindText(cStmt, 2, pageId)
                    bindText(cStmt, 3, sec.heading)
                    bindText(cStmt, 4, sec.content)
                    sqlite3_bind_int(cStmt, 5, Int32(max(1, bodyTokenArr.count)))
                    bindOptionalText(cStmt, 6, input.eventDate)
                    bindText(cStmt, 7, PipiWikiTextUtilities.sha256Hex(bodyText))
                    bindOptionalText(cStmt, 8, embeddingJson)
                    guard sqlite3_step(cStmt) == SQLITE_DONE else {
                        throw PipiWikiStoreError.sqlFailed(String(cString: sqlite3_errmsg(db)))
                    }

                    if supportsFts5 {
                        var ftsStmt: OpaquePointer?
                        let ftsSql = "INSERT INTO fts_wiki_chunks (chunk_id, page_id, title_tokens, body_tokens) VALUES (?, ?, ?, ?);"
                        guard sqlite3_prepare_v2(db, ftsSql, -1, &ftsStmt, nil) == SQLITE_OK else {
                            throw PipiWikiStoreError.sqlFailed(String(cString: sqlite3_errmsg(db)))
                        }
                        defer { sqlite3_finalize(ftsStmt) }
                        bindText(ftsStmt, 1, chunkId)
                        bindText(ftsStmt, 2, pageId)
                        bindText(ftsStmt, 3, titleTokens)
                        bindText(ftsStmt, 4, bodyTokens)
                        guard sqlite3_step(ftsStmt) == SQLITE_DONE else {
                            throw PipiWikiStoreError.sqlFailed(String(cString: sqlite3_errmsg(db)))
                        }
                    }
                }

                // Insert atomic facts + FTS5 fact index
                let effectiveFacts: [PipiWikiFactInput] = !input.facts.isEmpty
                    ? input.facts
                    : (!cleanSummary.isEmpty
                        ? [PipiWikiFactInput(
                            factText: "\(cleanTitle): \(cleanSummary)",
                            entities: [cleanTitle] + aliases,
                            eventDate: input.eventDate,
                            confidence: 0.85
                        )]
                        : [])

                for (idx, fact) in effectiveFacts.enumerated() {
                    let cleanFact = PipiWikiTextUtilities.scrubSecrets(fact.factText.trimmingCharacters(in: .whitespacesAndNewlines))
                    guard !cleanFact.isEmpty else { continue }
                    let factId = "\(pageId)_f\(idx)"
                    let entities = fact.entities.isEmpty ? [cleanTitle] : fact.entities
                    let factTokenArr = PipiWikiTextUtilities.expandTokensWithCjkBigrams("\(cleanFact) \(entities.joined(separator: " "))")

                    var fStmt: OpaquePointer?
                    let fSql = """
                    INSERT INTO wiki_facts (id, page_id, chunk_id, fact_text, entities_json, token_count, event_date, confidence, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """
                    guard sqlite3_prepare_v2(db, fSql, -1, &fStmt, nil) == SQLITE_OK else {
                        throw PipiWikiStoreError.sqlFailed(String(cString: sqlite3_errmsg(db)))
                    }
                    defer { sqlite3_finalize(fStmt) }
                    bindText(fStmt, 1, factId)
                    bindText(fStmt, 2, pageId)
                    bindOptionalText(fStmt, 3, firstChunkId)
                    bindText(fStmt, 4, cleanFact)
                    bindText(fStmt, 5, encodeJsonArray(entities))
                    sqlite3_bind_int(fStmt, 6, Int32(max(1, factTokenArr.count)))
                    bindOptionalText(fStmt, 7, fact.eventDate ?? input.eventDate)
                    sqlite3_bind_double(fStmt, 8, min(1.0, max(0.1, fact.confidence)))
                    bindText(fStmt, 9, nowIso)
                    guard sqlite3_step(fStmt) == SQLITE_DONE else {
                        throw PipiWikiStoreError.sqlFailed(String(cString: sqlite3_errmsg(db)))
                    }

                    if supportsFts5 {
                        var ffStmt: OpaquePointer?
                        let ffSql = "INSERT INTO fts_wiki_facts (fact_id, page_id, fact_tokens) VALUES (?, ?, ?);"
                        guard sqlite3_prepare_v2(db, ffSql, -1, &ffStmt, nil) == SQLITE_OK else {
                            throw PipiWikiStoreError.sqlFailed(String(cString: sqlite3_errmsg(db)))
                        }
                        defer { sqlite3_finalize(ffStmt) }
                        bindText(ffStmt, 1, factId)
                        bindText(ffStmt, 2, pageId)
                        bindText(ffStmt, 3, factTokenArr.joined(separator: " "))
                        guard sqlite3_step(ffStmt) == SQLITE_DONE else {
                            throw PipiWikiStoreError.sqlFailed(String(cString: sqlite3_errmsg(db)))
                        }
                    }
                }

                try execLocked("COMMIT;")
            } catch {
                try? execLocked("ROLLBACK;")
                throw error
            }

            return PipiPersonalWikiPage(
                id: pageId,
                slug: slug,
                category: input.category,
                title: cleanTitle,
                aliases: aliases,
                summary: cleanSummary,
                bodyMarkdown: cleanBody,
                tags: tags,
                sourceRefs: sourceRefs,
                eventDate: input.eventDate,
                status: input.status,
                contentHash: contentHash,
                createdAt: createdAt,
                updatedAt: nowIso
            )
        }()

        if let rootURL = markdownRootURL {
            _ = try? projectMarkdownFile(page, rootURL: rootURL)
        }
        return page
    }

    public func getPage(id: String) -> PipiPersonalWikiPage? {
        lock.lock()
        defer { lock.unlock() }
        guard let db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT * FROM wiki_pages WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        bindText(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return readPageRow(stmt)
    }

    public func listPages(category: PipiWikiEntityCategory? = nil) -> [PipiPersonalWikiPage] {
        lock.lock()
        defer { lock.unlock() }
        return listPagesLocked(category: category)
    }

    private func listPagesLocked(category: PipiWikiEntityCategory? = nil) -> [PipiPersonalWikiPage] {
        guard let db else { return [] }
        let sql = category == nil
            ? "SELECT * FROM wiki_pages ORDER BY updated_at DESC;"
            : "SELECT * FROM wiki_pages WHERE category = ? ORDER BY updated_at DESC;"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        if let category {
            bindText(stmt, 1, category.rawValue)
        }
        var results: [PipiPersonalWikiPage] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let page = readPageRow(stmt) {
                results.append(page)
            }
        }
        return results
    }

    @discardableResult
    public func deletePage(id: String) -> Bool {
        let existing = getPage(id: id)
        guard let existing else { return false }
        lock.lock()
        defer { lock.unlock() }
        do {
            try execLocked("BEGIN IMMEDIATE;")
            if supportsFts5 {
                try runDeleteLocked(sql: "DELETE FROM fts_wiki_chunks WHERE page_id = ?;", param: id)
                try runDeleteLocked(sql: "DELETE FROM fts_wiki_facts WHERE page_id = ?;", param: id)
            }
            try runDeleteLocked(sql: "DELETE FROM wiki_pages WHERE id = ?;", param: id)
            try execLocked("COMMIT;")
        } catch {
            try? execLocked("ROLLBACK;")
            return false
        }
        if let rootURL = markdownRootURL {
            let fileURL = rootURL
                .appendingPathComponent("knowledge", isDirectory: true)
                .appendingPathComponent(existing.category.rawValue, isDirectory: true)
                .appendingPathComponent("\(existing.slug).md")
            try? FileManager.default.removeItem(at: fileURL)
        }
        return true
    }

    public func renderMarkdown(for page: PipiPersonalWikiPage) -> String {
        func q(_ value: String) -> String {
            let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        var lines = [
            "---",
            "pipibot_wiki_version: \"1.0\"",
            "id: \(q(page.id))",
            "category: \(page.category.rawValue)",
            "title: \(q(page.title))",
            "status: \(page.status.rawValue)",
            "updated_at: \(q(page.updatedAt))",
        ]
        if let eventDate = page.eventDate, !eventDate.isEmpty {
            lines.append("event_date: \(q(eventDate))")
        }
        if !page.aliases.isEmpty {
            lines.append("aliases: [\(page.aliases.map(q).joined(separator: ", "))]")
        }
        if !page.tags.isEmpty {
            lines.append("tags: [\(page.tags.map(q).joined(separator: ", "))]")
        }
        if !page.sourceRefs.isEmpty {
            lines.append("sources: [\(page.sourceRefs.map(q).joined(separator: ", "))]")
        }
        lines.append(contentsOf: ["---", "", "# \(page.title)", "", page.summary, "", page.bodyMarkdown, ""])
        return lines.joined(separator: "\n")
    }

    @discardableResult
    public func projectMarkdownFile(_ page: PipiPersonalWikiPage, rootURL: URL) throws -> URL {
        let dir = rootURL
            .appendingPathComponent("knowledge", isDirectory: true)
            .appendingPathComponent(page.category.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let targetURL = dir.appendingPathComponent("\(page.slug).md")
        let data = Data(renderMarkdown(for: page).utf8)
        try data.write(to: targetURL, options: .atomic)
        return targetURL
    }

    // MARK: - Dual-Channel Zero-Embedding Search + Soft Time-Window RRF

    public func search(_ options: PipiWikiSearchOptions) -> PipiWikiSearchResult {
        let trimmedQuery = options.query.trimmingCharacters(in: .whitespacesAndNewlines)
        var seenLower = Set<String>()
        if !trimmedQuery.isEmpty { seenLower.insert(trimmedQuery.lowercased()) }
        var effectiveQueries: [String] = trimmedQuery.isEmpty ? [] : [trimmedQuery]
        var altCount = 0
        for rawAlt in options.alternates {
            let alt = rawAlt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !alt.isEmpty, seenLower.insert(alt.lowercased()).inserted else { continue }
            effectiveQueries.append(alt)
            altCount += 1
            if altCount >= PipiWikiTextUtilities.maxAlternates { break }
        }

        guard !effectiveQueries.isEmpty else {
            return PipiWikiSearchResult(
                query: options.query,
                effectiveQueries: [],
                scope: options.scope,
                usedFts5: supportsFts5,
                usedVectorChannel: false,
                chunks: [],
                facts: [],
                summaries: []
            )
        }

        lock.lock()
        defer { lock.unlock() }

        let limit = max(1, min(30, options.limit))
        let factLimit = max(1, min(30, options.factLimit))
        let hasWindow = (options.startDate?.isEmpty == false) || (options.endDate?.isEmpty == false)

        let chunks: [PipiWikiChunkHit] = options.scope == .summaries
            ? []
            : searchChunksLocked(queries: effectiveQueries, options: options, limit: limit, hasWindow: hasWindow)
        let facts: [PipiWikiFactHit] = options.scope == .summaries
            ? []
            : searchFactsLocked(queries: effectiveQueries, options: options, limit: factLimit, hasWindow: hasWindow)
        let summaries: [PipiWikiSummaryHit] = options.scope == .originals
            ? []
            : searchSummariesLocked(queries: effectiveQueries, options: options, limit: limit, hasWindow: hasWindow)

        return PipiWikiSearchResult(
            query: options.query,
            effectiveQueries: effectiveQueries,
            scope: options.scope,
            usedFts5: supportsFts5,
            usedVectorChannel: !(options.optionalQueryEmbedding ?? []).isEmpty,
            chunks: chunks,
            facts: facts,
            summaries: summaries
        )
    }

    private func searchChunksLocked(
        queries: [String],
        options: PipiWikiSearchOptions,
        limit: Int,
        hasWindow: Bool
    ) -> [PipiWikiChunkHit] {
        var rrfScores: [String: Double] = [:]

        for (qIdx, q) in queries.enumerated() {
            let weight = qIdx == 0 ? 1.25 : 0.85
            let ranked = rankChunksLexicallyLocked(query: q, category: options.category)
            for (rankIdx, item) in ranked.prefix(32).enumerated() {
                rrfScores[item.chunkId, default: 0] += weight / (PipiWikiTextUtilities.rrfK + Double(rankIdx + 1))
            }
            if hasWindow {
                let inWindow = ranked.filter {
                    PipiWikiTextUtilities.isWithinDateWindow($0.eventDate, startDate: options.startDate, endDate: options.endDate)
                }
                for (rankIdx, item) in inWindow.prefix(24).enumerated() {
                    let bonus = (weight * PipiWikiTextUtilities.softWindowBonusWeight) / (PipiWikiTextUtilities.rrfK + Double(rankIdx + 1))
                    rrfScores[item.chunkId, default: 0] += bonus
                }
            }
        }

        // Optional vector channel (0 embedding calls by default)
        if let qVec = options.optionalQueryEmbedding, !qVec.isEmpty, let db {
            let sql = options.category == nil
                ? "SELECT id, embedding_json FROM wiki_chunks WHERE embedding_json IS NOT NULL;"
                : """
                  SELECT c.id, c.embedding_json FROM wiki_chunks c
                  JOIN wiki_pages p ON p.id = c.page_id
                  WHERE c.embedding_json IS NOT NULL AND p.category = ?;
                  """
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                if let cat = options.category { bindText(stmt, 1, cat.rawValue) }
                var vecScored: [(String, Double)] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let idStr = colText(stmt, 0),
                       let embStr = colText(stmt, 1),
                       let data = embStr.data(using: .utf8),
                       let emb = try? JSONDecoder().decode([Double].self, from: data) {
                        let sim = PipiWikiTextUtilities.cosineSimilarity(qVec, emb)
                        if sim > 0.15 { vecScored.append((idStr, sim)) }
                    }
                }
                vecScored.sort { $0.1 > $1.1 }
                for (rankIdx, item) in vecScored.prefix(24).enumerated() {
                    rrfScores[item.0, default: 0] += 0.9 / (PipiWikiTextUtilities.rrfK + Double(rankIdx + 1))
                }
            }
        }

        let topIds = rrfScores.sorted { $0.value > $1.value }.prefix(limit)
        guard let db else { return [] }

        var hits: [PipiWikiChunkHit] = []
        let fetchSql = """
        SELECT c.id, c.page_id, c.section_heading, c.content, c.event_date, p.category, p.title
        FROM wiki_chunks c JOIN wiki_pages p ON p.id = c.page_id
        WHERE c.id = ?;
        """
        for (chunkId, score) in topIds {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, fetchSql, -1, &stmt, nil) == SQLITE_OK else { continue }
            bindText(stmt, 1, chunkId)
            guard sqlite3_step(stmt) == SQLITE_ROW,
                  let id = colText(stmt, 0),
                  let pageId = colText(stmt, 1),
                  let heading = colText(stmt, 2),
                  let content = colText(stmt, 3),
                  let catRaw = colText(stmt, 5),
                  let category = PipiWikiEntityCategory(rawValue: catRaw),
                  let title = colText(stmt, 6) else { continue }
            let eventDate = colText(stmt, 4)
            hits.append(PipiWikiChunkHit(
                chunkId: id,
                pageId: pageId,
                category: category,
                title: title,
                sectionHeading: heading,
                content: content,
                eventDate: eventDate,
                inTimeWindow: PipiWikiTextUtilities.isWithinDateWindow(eventDate, startDate: options.startDate, endDate: options.endDate),
                score: score
            ))
        }
        return hits
    }

    private func rankChunksLexicallyLocked(
        query: String,
        category: PipiWikiEntityCategory?
    ) -> [(chunkId: String, eventDate: String?, score: Double)] {
        guard let db, supportsFts5 else { return [] }
        let terms = Array(Set(PipiWikiTextUtilities.expandTokensWithCjkBigrams(query)))
        guard !terms.isEmpty else { return [] }
        let matchExpr = terms.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: " OR ")

        let sql = category == nil
            ? """
              SELECT f.chunk_id, c.event_date, bm25(fts_wiki_chunks, 0.0, 0.0, 2.5, 1.0) AS rank_score
              FROM fts_wiki_chunks f
              JOIN wiki_chunks c ON c.id = f.chunk_id
              WHERE fts_wiki_chunks MATCH ?
              ORDER BY rank_score ASC LIMIT 40;
              """
            : """
              SELECT f.chunk_id, c.event_date, bm25(fts_wiki_chunks, 0.0, 0.0, 2.5, 1.0) AS rank_score
              FROM fts_wiki_chunks f
              JOIN wiki_chunks c ON c.id = f.chunk_id
              JOIN wiki_pages p ON p.id = f.page_id
              WHERE fts_wiki_chunks MATCH ? AND p.category = ?
              ORDER BY rank_score ASC LIMIT 40;
              """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        bindText(stmt, 1, matchExpr)
        if let category { bindText(stmt, 2, category.rawValue) }

        var rows: [(String, String?, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let chunkId = colText(stmt, 0) {
                let eventDate = colText(stmt, 1)
                let score = -sqlite3_column_double(stmt, 2)
                rows.append((chunkId, eventDate, score))
            }
        }
        return rows
    }

    private func searchFactsLocked(
        queries: [String],
        options: PipiWikiSearchOptions,
        limit: Int,
        hasWindow: Bool
    ) -> [PipiWikiFactHit] {
        var rrfScores: [String: Double] = [:]

        for (qIdx, q) in queries.enumerated() {
            let weight = qIdx == 0 ? 1.25 : 0.85
            let ranked = rankFactsLexicallyLocked(query: q, category: options.category)
            for (rankIdx, item) in ranked.prefix(32).enumerated() {
                rrfScores[item.factId, default: 0] += weight / (PipiWikiTextUtilities.rrfK + Double(rankIdx + 1))
            }
            if hasWindow {
                let inWindow = ranked.filter {
                    PipiWikiTextUtilities.isWithinDateWindow($0.eventDate, startDate: options.startDate, endDate: options.endDate)
                }
                for (rankIdx, item) in inWindow.prefix(24).enumerated() {
                    let bonus = (weight * PipiWikiTextUtilities.softWindowBonusWeight) / (PipiWikiTextUtilities.rrfK + Double(rankIdx + 1))
                    rrfScores[item.factId, default: 0] += bonus
                }
            }
        }

        let topIds = rrfScores.sorted { $0.value > $1.value }.prefix(limit)
        guard let db else { return [] }

        var hits: [PipiWikiFactHit] = []
        let fetchSql = """
        SELECT f.id, f.page_id, f.chunk_id, f.fact_text, f.entities_json, f.event_date, f.confidence, p.category, p.title
        FROM wiki_facts f JOIN wiki_pages p ON p.id = f.page_id
        WHERE f.id = ?;
        """
        for (factId, score) in topIds {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, fetchSql, -1, &stmt, nil) == SQLITE_OK else { continue }
            bindText(stmt, 1, factId)
            guard sqlite3_step(stmt) == SQLITE_ROW,
                  let id = colText(stmt, 0),
                  let pageId = colText(stmt, 1),
                  let factText = colText(stmt, 3),
                  let catRaw = colText(stmt, 7),
                  let category = PipiWikiEntityCategory(rawValue: catRaw),
                  let pageTitle = colText(stmt, 8) else { continue }
            let chunkId = colText(stmt, 2)
            let entities = decodeJsonArray(colText(stmt, 4) ?? "[]")
            let eventDate = colText(stmt, 5)
            let confidence = sqlite3_column_double(stmt, 6)
            hits.append(PipiWikiFactHit(
                factId: id,
                pageId: pageId,
                chunkId: chunkId,
                category: category,
                pageTitle: pageTitle,
                factText: factText,
                entities: entities,
                eventDate: eventDate,
                confidence: confidence,
                inTimeWindow: PipiWikiTextUtilities.isWithinDateWindow(eventDate, startDate: options.startDate, endDate: options.endDate),
                score: score
            ))
        }
        return hits
    }

    private func rankFactsLexicallyLocked(
        query: String,
        category: PipiWikiEntityCategory?
    ) -> [(factId: String, eventDate: String?, score: Double)] {
        guard let db, supportsFts5 else { return [] }
        let terms = Array(Set(PipiWikiTextUtilities.expandTokensWithCjkBigrams(query)))
        guard !terms.isEmpty else { return [] }
        let matchExpr = terms.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: " OR ")

        let sql = category == nil
            ? """
              SELECT ff.fact_id, f.event_date, bm25(fts_wiki_facts) AS rank_score
              FROM fts_wiki_facts ff
              JOIN wiki_facts f ON f.id = ff.fact_id
              WHERE fts_wiki_facts MATCH ?
              ORDER BY rank_score ASC LIMIT 40;
              """
            : """
              SELECT ff.fact_id, f.event_date, bm25(fts_wiki_facts) AS rank_score
              FROM fts_wiki_facts ff
              JOIN wiki_facts f ON f.id = ff.fact_id
              JOIN wiki_pages p ON p.id = ff.page_id
              WHERE fts_wiki_facts MATCH ? AND p.category = ?
              ORDER BY rank_score ASC LIMIT 40;
              """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        bindText(stmt, 1, matchExpr)
        if let category { bindText(stmt, 2, category.rawValue) }

        var rows: [(String, String?, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let factId = colText(stmt, 0) {
                let eventDate = colText(stmt, 1)
                let score = -sqlite3_column_double(stmt, 2)
                rows.append((factId, eventDate, score))
            }
        }
        return rows
    }

    private func searchSummariesLocked(
        queries: [String],
        options: PipiWikiSearchOptions,
        limit: Int,
        hasWindow: Bool
    ) -> [PipiWikiSummaryHit] {
        let pages = listPagesLocked(category: options.category)
        let querySpecs = queries.map { q in
            (rawLower: q.lowercased(), terms: Set(PipiWikiTextUtilities.expandTokensWithCjkBigrams(q)))
        }

        var hits: [PipiWikiSummaryHit] = []
        for page in pages {
            let titleLower = page.title.lowercased()
            let aliasLowers = page.aliases.map { $0.lowercased() }
            let docTerms = Set(PipiWikiTextUtilities.expandTokensWithCjkBigrams(
                "\(page.title) \(page.aliases.joined(separator: " ")) \(page.summary) \(page.tags.joined(separator: " "))"
            ))

            var score = 0.0
            var matchedAlias: String?

            for (idx, spec) in querySpecs.enumerated() {
                let w = idx == 0 ? 1.25 : 0.85
                if titleLower == spec.rawLower || titleLower.contains(spec.rawLower) {
                    score += 3.0 * w
                }
                for (aIdx, al) in aliasLowers.enumerated() {
                    if al == spec.rawLower || al.contains(spec.rawLower) || spec.rawLower.contains(al) {
                        score += 2.6 * w
                        matchedAlias = page.aliases[aIdx]
                    }
                }
                if !spec.terms.isEmpty {
                    let overlap = spec.terms.reduce(0) { $0 + (docTerms.contains($1) ? 1 : 0) }
                    if overlap > 0 {
                        score += (Double(overlap) / Double(spec.terms.count)) * 1.8 * w
                    }
                }
            }

            guard score > 0 else { continue }
            if hasWindow && PipiWikiTextUtilities.isWithinDateWindow(page.eventDate, startDate: options.startDate, endDate: options.endDate) {
                score *= 1.35
            }

            hits.append(PipiWikiSummaryHit(
                pageId: page.id,
                slug: page.slug,
                category: page.category,
                title: page.title,
                aliases: page.aliases,
                summary: page.summary,
                eventDate: page.eventDate,
                score: score,
                matchedAlias: matchedAlias
            ))
        }

        return hits.sorted { $0.score > $1.score }.prefix(limit).map { $0 }
    }

    // MARK: - SQLite Binding Helpers

    private func fetchCreatedAtLocked(pageId: String) -> String? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT created_at FROM wiki_pages WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        bindText(stmt, 1, pageId)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return colText(stmt, 0)
    }

    private func runDeleteLocked(sql: String, param: String) throws {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw PipiWikiStoreError.sqlFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, param)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw PipiWikiStoreError.sqlFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func readPageRow(_ stmt: OpaquePointer?) -> PipiPersonalWikiPage? {
        guard let id = colText(stmt, 0),
              let slug = colText(stmt, 1),
              let catRaw = colText(stmt, 2),
              let category = PipiWikiEntityCategory(rawValue: catRaw),
              let title = colText(stmt, 3) else {
            return nil
        }
        return PipiPersonalWikiPage(
            id: id,
            slug: slug,
            category: category,
            title: title,
            aliases: decodeJsonArray(colText(stmt, 4) ?? "[]"),
            summary: colText(stmt, 5) ?? "",
            bodyMarkdown: colText(stmt, 6) ?? "",
            tags: decodeJsonArray(colText(stmt, 7) ?? "[]"),
            sourceRefs: decodeJsonArray(colText(stmt, 8) ?? "[]"),
            eventDate: colText(stmt, 9),
            status: PipiWikiPageStatus(rawValue: colText(stmt, 10) ?? "stable") ?? .stable,
            contentHash: colText(stmt, 11) ?? "",
            createdAt: colText(stmt, 12) ?? "",
            updatedAt: colText(stmt, 13) ?? ""
        )
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func colText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: ptr)
    }

    private func encodeJsonArray(_ array: [String]) -> String {
        guard let data = try? JSONEncoder().encode(array),
              let str = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return str
    }

    private func decodeJsonArray(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }
}
