// PiPiBot — Clean-room MIT implementation.
// Wave 3 (#11): Daily Pocket Notes (5-Minute Silence Tracking Item Extraction & Reconciliation)
// + Editable Artifact Documents (Revision History, SHA-256 & Personal Wiki Sync).
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

import CryptoKit
import Foundation

// MARK: - 1. Public Models

public struct PipiDailyPocketNote: Codable, Identifiable, Equatable, Sendable {
    public var id: String { dateYmd }
    public let dateYmd: String // YYYY-MM-DD
    public var content: String
    public var contentSha256: String
    public var lastEditedAt: Date
    public var lastExtractedAt: Date?
    public var lastExtractedHash: String?

    public init(
        dateYmd: String,
        content: String,
        contentSha256: String,
        lastEditedAt: Date = Date(),
        lastExtractedAt: Date? = nil,
        lastExtractedHash: String? = nil
    ) {
        self.dateYmd = dateYmd
        self.content = content
        self.contentSha256 = contentSha256
        self.lastEditedAt = lastEditedAt
        self.lastExtractedAt = lastExtractedAt
        self.lastExtractedHash = lastExtractedHash
    }
}

public struct PipiTrackingItem: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let sourceDateYmd: String
    public var title: String
    public var dueDateYmd: String?
    public var status: PipiTrackingItemStatus
    public let fingerprint: String
    public let createdAt: String
    public var updatedAt: String

    public init(
        id: String = "trk_\(UUID().uuidString.prefix(8).lowercased())",
        sourceDateYmd: String,
        title: String,
        dueDateYmd: String? = nil,
        status: PipiTrackingItemStatus = .open,
        fingerprint: String,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.sourceDateYmd = sourceDateYmd
        self.title = title
        self.dueDateYmd = dueDateYmd
        self.status = status
        self.fingerprint = fingerprint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum PipiPocketReconcileReason: String, Sendable, Equatable {
    case reconciled
    case waitingSilenceWindow = "waiting_silence_window"
    case unchanged
    case noteNotFound = "note_not_found"
}

public struct PipiPocketReconcileResult: Equatable, Sendable {
    public let dateYmd: String
    public let extracted: Bool
    public let reason: PipiPocketReconcileReason
    public let added: [PipiTrackingItem]
    public let keptCount: Int
    public let removedOpenIds: [String]
    public let openItems: [PipiTrackingItem]
}

public struct PipiArtifactDocument: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var kind: PipiArtifactDocumentKind
    public var markdown: String
    public var revision: Int
    public var contentSha256: String
    public var sessionId: String?
    public var groupId: String?
    public var tags: [String]
    public let createdAt: String
    public var updatedAt: String

    public init(
        id: String = "doc_\(UUID().uuidString.prefix(8).lowercased())",
        title: String,
        kind: PipiArtifactDocumentKind = .note,
        markdown: String,
        revision: Int = 1,
        contentSha256: String,
        sessionId: String? = nil,
        groupId: String? = nil,
        tags: [String] = [],
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        updatedAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.markdown = markdown
        self.revision = revision
        self.contentSha256 = contentSha256
        self.sessionId = sessionId
        self.groupId = groupId
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct PipiPocketNotesPersistedState: Codable, Equatable, Sendable {
    public var notes: [String: PipiDailyPocketNote]
    public var trackingItems: [PipiTrackingItem]
    public var documents: [PipiArtifactDocument]

    public init(
        notes: [String: PipiDailyPocketNote] = [:],
        trackingItems: [PipiTrackingItem] = [],
        documents: [PipiArtifactDocument] = []
    ) {
        self.notes = notes
        self.trackingItems = trackingItems
        self.documents = documents
    }
}

// MARK: - 2. PipiPocketNotesEngine

@MainActor
public final class PipiPocketNotesEngine {
    public static let defaultSilenceSeconds: TimeInterval = 300.0 // 5 minutes

    public let rootURL: URL
    public var silenceSeconds: TimeInterval
    public private(set) var notes: [String: PipiDailyPocketNote] = [:]
    public private(set) var trackingItems: [PipiTrackingItem] = []
    public private(set) var documents: [PipiArtifactDocument] = []

    public init(
        rootURL: URL,
        silenceSeconds: TimeInterval = PipiPocketNotesEngine.defaultSilenceSeconds
    ) {
        self.rootURL = rootURL
        self.silenceSeconds = max(0, silenceSeconds)
    }

    public func exportPersistedState() -> PipiPocketNotesPersistedState {
        PipiPocketNotesPersistedState(
            notes: notes,
            trackingItems: trackingItems,
            documents: documents
        )
    }

    public func restorePersistedState(_ state: PipiPocketNotesPersistedState) {
        self.notes = state.notes
        self.trackingItems = state.trackingItems
        self.documents = state.documents
    }

    private static func sha256Hex(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func todoFingerprint(_ title: String) -> String {
        let norm = title
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(sha256Hex(norm).prefix(16))
    }

    public static func extractTodos(from markdown: String) -> [(title: String, dueDateYmd: String?, completed: Bool)] {
        var results: [(String, String?, Bool)] = []
        let dateRegex = try? NSRegularExpression(pattern: "\\b(20\\d{2}-\\d{2}-\\d{2})\\b")
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            var completed = false
            var body: String?

            if line.hasPrefix("- [ ] ") || line.hasPrefix("* [ ] ") {
                body = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") || line.hasPrefix("* [x] ") || line.hasPrefix("* [X] ") {
                completed = true
                body = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else {
                let strippedBullet = (line.hasPrefix("- ") || line.hasPrefix("* "))
                    ? String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    : line
                for prefix in ["TODO:", "TODO：", "todo:", "待办:", "待办：", "跟进:", "跟进："] {
                    if strippedBullet.hasPrefix(prefix) {
                        body = String(strippedBullet.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                        break
                    }
                }
            }

            guard let rawBody = body, !rawBody.isEmpty else { continue }
            let clean = PipiWikiTextUtilities.scrubSecrets(rawBody)
            var dueDate: String?
            if let dateRegex {
                let nsRange = NSRange(clean.startIndex..<clean.endIndex, in: clean)
                if let match = dateRegex.firstMatch(in: clean, range: nsRange),
                   let swiftRange = Range(match.range(at: 1), in: clean) {
                    dueDate = String(clean[swiftRange])
                }
            }
            results.append((clean, dueDate, completed))
        }
        return results
    }

    // MARK: - Daily Pocket Notes

    @discardableResult
    public func saveDailyNote(dateYmd: String, content: String, now: Date = Date()) -> PipiDailyPocketNote {
        let clean = PipiWikiTextUtilities.scrubSecrets(content)
        let hash = Self.sha256Hex(clean)
        let existing = notes[dateYmd]
        let note = PipiDailyPocketNote(
            dateYmd: dateYmd,
            content: clean,
            contentSha256: hash,
            lastEditedAt: now,
            lastExtractedAt: existing?.lastExtractedAt,
            lastExtractedHash: existing?.lastExtractedHash
        )
        notes[dateYmd] = note

        let dir = rootURL.appendingPathComponent("pocket-notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data(clean.utf8).write(to: dir.appendingPathComponent("\(dateYmd).md"), options: .atomic)
        return note
    }

    public func dailyNote(for dateYmd: String) -> PipiDailyPocketNote? {
        notes[dateYmd]
    }

    public func setTrackingItemStatus(id: String, status: PipiTrackingItemStatus) {
        guard let idx = trackingItems.firstIndex(where: { $0.id == id }) else { return }
        trackingItems[idx].status = status
        trackingItems[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
    }

    @discardableResult
    public func reconcileDailyNoteIfQuiet(
        dateYmd: String,
        now: Date = Date(),
        force: Bool = false
    ) -> PipiPocketReconcileResult {
        guard var note = notes[dateYmd] else {
            return PipiPocketReconcileResult(
                dateYmd: dateYmd,
                extracted: false,
                reason: .noteNotFound,
                added: [],
                keptCount: 0,
                removedOpenIds: [],
                openItems: trackingItems.filter { $0.status == .open }
            )
        }

        if !force && note.lastExtractedHash == note.contentSha256 {
            return PipiPocketReconcileResult(
                dateYmd: dateYmd,
                extracted: false,
                reason: .unchanged,
                added: [],
                keptCount: 0,
                removedOpenIds: [],
                openItems: trackingItems.filter { $0.status == .open }
            )
        }

        if !force && now.timeIntervalSince(note.lastEditedAt) < silenceSeconds {
            return PipiPocketReconcileResult(
                dateYmd: dateYmd,
                extracted: false,
                reason: .waitingSilenceWindow,
                added: [],
                keptCount: 0,
                removedOpenIds: [],
                openItems: trackingItems.filter { $0.status == .open }
            )
        }

        let parsedTodos = Self.extractTodos(from: note.content)
        let activeFps = Set(parsedTodos.map { Self.todoFingerprint($0.title) })
        let nowIso = ISO8601DateFormatter().string(from: now)

        var removedIds: [String] = []
        trackingItems.removeAll { existing in
            let shouldRemove = existing.sourceDateYmd == dateYmd
                && existing.status == .open
                && !activeFps.contains(existing.fingerprint)
            if shouldRemove { removedIds.append(existing.id) }
            return shouldRemove
        }

        var added: [PipiTrackingItem] = []
        var keptCount = 0

        for todo in parsedTodos {
            let fp = Self.todoFingerprint(todo.title)
            if let idx = trackingItems.firstIndex(where: { $0.sourceDateYmd == dateYmd && $0.fingerprint == fp }) {
                trackingItems[idx].title = todo.title
                trackingItems[idx].dueDateYmd = todo.dueDateYmd
                if todo.completed && trackingItems[idx].status == .open {
                    trackingItems[idx].status = .done
                }
                trackingItems[idx].updatedAt = nowIso
                keptCount += 1
            } else {
                let item = PipiTrackingItem(
                    sourceDateYmd: dateYmd,
                    title: todo.title,
                    dueDateYmd: todo.dueDateYmd,
                    status: todo.completed ? .done : .open,
                    fingerprint: fp,
                    createdAt: nowIso,
                    updatedAt: nowIso
                )
                trackingItems.insert(item, at: 0)
                added.append(item)
            }
        }

        note.lastExtractedAt = now
        note.lastExtractedHash = note.contentSha256
        notes[dateYmd] = note

        return PipiPocketReconcileResult(
            dateYmd: dateYmd,
            extracted: true,
            reason: .reconciled,
            added: added,
            keptCount: keptCount,
            removedOpenIds: removedIds,
            openItems: trackingItems.filter { $0.status == .open }
        )
    }

    // MARK: - Editable Artifact Documents

    @discardableResult
    public func upsertDocument(
        id: String? = nil,
        title: String,
        kind: PipiArtifactDocumentKind = .note,
        markdown: String,
        sessionId: String? = nil,
        groupId: String? = nil,
        tags: [String] = []
    ) -> PipiArtifactDocument {
        let nowIso = ISO8601DateFormatter().string(from: Date())
        let cleanTitle = PipiWikiTextUtilities.scrubSecrets(title.trimmingCharacters(in: .whitespacesAndNewlines))
        let cleanBody = PipiWikiTextUtilities.scrubSecrets(markdown)
        let hash = Self.sha256Hex("\(cleanTitle)\n\(cleanBody)")

        let saved: PipiArtifactDocument
        if let id, let idx = documents.firstIndex(where: { $0.id == id }) {
            documents[idx].title = cleanTitle
            documents[idx].kind = kind
            documents[idx].markdown = cleanBody
            documents[idx].revision += 1
            documents[idx].contentSha256 = hash
            if let sessionId { documents[idx].sessionId = sessionId }
            if let groupId { documents[idx].groupId = groupId }
            if !tags.isEmpty { documents[idx].tags = tags }
            documents[idx].updatedAt = nowIso
            saved = documents[idx]
        } else {
            let doc = PipiArtifactDocument(
                id: (id?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                    ?? "doc_\(UUID().uuidString.prefix(8).lowercased())",
                title: cleanTitle,
                kind: kind,
                markdown: cleanBody,
                revision: 1,
                contentSha256: hash,
                sessionId: sessionId,
                groupId: groupId,
                tags: tags,
                createdAt: nowIso,
                updatedAt: nowIso
            )
            documents.insert(doc, at: 0)
            saved = doc
        }

        let dir = rootURL.appendingPathComponent("documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data(saved.markdown.utf8).write(to: dir.appendingPathComponent("\(saved.id).md"), options: .atomic)
        return saved
    }

    public func deleteDocument(id: String) {
        documents.removeAll { $0.id == id }
        let fileURL = rootURL
            .appendingPathComponent("documents", isDirectory: true)
            .appendingPathComponent("\(id).md")
        try? FileManager.default.removeItem(at: fileURL)
    }

    @discardableResult
    public func syncDocumentToWiki(docId: String, wiki: PipiPersonalWikiStore) -> PipiPersonalWikiPage? {
        guard let doc = documents.first(where: { $0.id == docId }) else { return nil }
        let firstLine = doc.markdown
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "#"))) }
            .first { !$0.isEmpty } ?? doc.title
        return try? wiki.upsertPage(PipiWikiPageInput(
            id: "wiki_doc_\(doc.id)",
            category: doc.kind == .note ? .life : .projects,
            title: doc.title,
            summary: String(firstLine.prefix(180)),
            bodyMarkdown: doc.markdown,
            tags: doc.tags + [doc.kind.rawValue],
            sourceRefs: ["pipibot://documents/\(doc.id)@rev\(doc.revision)"]
        ))
    }
}
