// PiPiBot — Clean-room MIT implementation.
// Wave 3 (#11): Versioned Builtin Office & Daily Skill Packs with CryptoKit SHA-256 Verification
// and Read-Only Projection (0444) into Local Agent Context Views.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

import CryptoKit
import Foundation

public struct PipiBuiltinSkillPack: Codable, Identifiable, Equatable, Sendable {
    public enum Category: String, Codable, CaseIterable, Sendable, Equatable {
        case office
        case personal
        case automation

        public func label(_ lang: PipiResolvedLanguage) -> String {
            switch self {
            case .office: return lang == .zhHans ? "办公文档" : "Office"
            case .personal: return lang == .zhHans ? "个人日常" : "Personal"
            case .automation: return lang == .zhHans ? "信息检索" : "Automation"
            }
        }
    }

    public var id: String { slug }
    public let slug: String
    public let version: String
    public let titleZh: String
    public let titleEn: String
    public let category: Category
    public let description: String
    public let markdownBody: String
    public let sha256: String

    public func title(_ lang: PipiResolvedLanguage) -> String {
        lang == .zhHans ? titleZh : titleEn
    }
}

public struct PipiProjectedSkillReceipt: Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable, Equatable {
        case projected
        case verified
        case repaired
    }

    public var id: String { slug }
    public let slug: String
    public let version: String
    public let sha256: String
    public let filePath: String
    public let status: Status
}

public struct PipiSkillIntegrityMismatch: Equatable, Sendable {
    public let slug: String
    public let expectedSha256: String
    public let actualSha256: String?
}

public struct PipiSkillIntegrityReport: Equatable, Sendable {
    public let valid: Bool
    public let mismatches: [PipiSkillIntegrityMismatch]
}

public enum PipiBuiltinSkillsRegistry {
    private static func sha256Hex(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func makePack(
        slug: String,
        version: String,
        titleZh: String,
        titleEn: String,
        category: PipiBuiltinSkillPack.Category,
        description: String,
        body: String
    ) -> PipiBuiltinSkillPack {
        let fullMarkdown = [
            "---",
            "slug: \"\(slug)\"",
            "version: \"\(version)\"",
            "category: \"\(category.rawValue)\"",
            "readonly: true",
            "---",
            "",
            body.trimmingCharacters(in: .whitespacesAndNewlines),
            "",
        ].joined(separator: "\n")

        return PipiBuiltinSkillPack(
            slug: slug,
            version: version,
            titleZh: titleZh,
            titleEn: titleEn,
            category: category,
            description: description,
            markdownBody: fullMarkdown,
            sha256: sha256Hex(fullMarkdown)
        )
    }

    public static let allPacks: [PipiBuiltinSkillPack] = [
        makePack(
            slug: "docx",
            version: "1.0.0",
            titleZh: "Word 文档生成与修订",
            titleEn: "DOCX Document Authoring",
            category: .office,
            description: "Create, inspect, and refine structured Word (.docx) documents with clean headings and tables.",
            body: "# DOCX Skill\n\n- Produce clean outline hierarchy (H1/H2/H3), consistent tables, and UTF-8 CJK typography.\n- Never overwrite user files in place without an explicit backup or new revision filename.\n- Summarize key changes and output file path at completion."
        ),
        makePack(
            slug: "pdf",
            version: "1.0.0",
            titleZh: "PDF 审阅与版式输出",
            titleEn: "PDF Inspection & Export",
            category: .office,
            description: "Extract structured sections/tables from PDFs and generate crisp print-ready PDF deliverables.",
            body: "# PDF Skill\n\n- Verify page count, margins, and embedded CJK fonts before finalizing exported PDFs.\n- When summarizing source PDFs, cite exact page numbers for every key claim."
        ),
        makePack(
            slug: "pptx",
            version: "1.0.0",
            titleZh: "演示文稿制作 (PPTX)",
            titleEn: "PPTX Presentation Builder",
            category: .office,
            description: "Author clear executive and technical slide decks with restrained visual hierarchy.",
            body: "# PPTX Skill\n\n- Keep one core message per slide, generous whitespace, and legible body sizing (>=14pt).\n- Separate speaker notes from slide bullet points."
        ),
        makePack(
            slug: "xlsx",
            version: "1.0.0",
            titleZh: "电子表格与公式建模",
            titleEn: "Spreadsheet & Formula Modeling",
            category: .office,
            description: "Analyze CSV/XLSX tables, validate formulas, and construct auditable personal budget or tracking sheets.",
            body: "# XLSX Skill\n\n- Prefer explicit formulas over hardcoded totals and keep raw input sheets separated from summary views.\n- Validate numeric rounding and currency/date formatting."
        ),
        makePack(
            slug: "slide-deck",
            version: "1.0.0",
            titleZh: "结构化演讲故事线",
            titleEn: "Structured Slide Storyboarding",
            category: .office,
            description: "Plan narrative arcs, section transitions, and visual pacing before generating slides.",
            body: "# Slide Deck Storyboarding\n\n- Open with the conclusion (Pyramid Principle), back each claim with concrete evidence, and close with clear decisions."
        ),
        makePack(
            slug: "humanlike-browse",
            version: "1.0.0",
            titleZh: "克制浏览器信息检索",
            titleEn: "Human-Paced Web Research",
            category: .automation,
            description: "Navigate pages calmly, verify primary sources, and pause immediately for authentication or CAPTCHAs.",
            body: "# Human-Paced Browse Skill\n\n- Read primary documentation directly, cite URLs, and never attempt to bypass logins, paywalls, or anti-bot gates.\n- Any form submission or external post requires explicit user approval."
        ),
        makePack(
            slug: "personal-profile",
            version: "1.0.0",
            titleZh: "个人画像与 Wiki 整理",
            titleEn: "Personal Profile & Wiki Curation",
            category: .personal,
            description: "Distill durable personal preferences, projects, and life notes into clean Personal Wiki entries.",
            body: "# Personal Profile & Wiki Skill\n\n- Organize personal knowledge into People, Projects, Topics, Life, and Repos.\n- Strip credentials or tokens before writing any Wiki page or memory summary."
        ),
        makePack(
            slug: "proactive-response",
            version: "1.0.0",
            titleZh: "克制主动响应与备料",
            titleEn: "Restrained Proactive Prepare",
            category: .personal,
            description: "Prepare read-only context briefings ahead of events while respecting quiet hours and user feedback.",
            body: "# Proactive Response Skill\n\n- Favor silent read-only Prepare briefings over disruptive pings.\n- Never execute external side effects autonomously during proactive runs."
        ),
    ]

    public static func skill(slug: String) -> PipiBuiltinSkillPack? {
        allPacks.first { $0.slug == slug }
    }

    @discardableResult
    public static func projectReadOnly(
        to rootURL: URL,
        slugs: [String]? = nil
    ) throws -> [PipiProjectedSkillReceipt] {
        let fm = FileManager.default
        let selected = slugs.map { set in allPacks.filter { set.contains($0.slug) } } ?? allPacks
        var receipts: [PipiProjectedSkillReceipt] = []

        for skill in selected {
            let skillDir = rootURL
                .appendingPathComponent("skills", isDirectory: true)
                .appendingPathComponent("builtin", isDirectory: true)
                .appendingPathComponent(skill.slug, isDirectory: true)
            let fileURL = skillDir.appendingPathComponent("SKILL.md")
            try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)

            let existingDigest: String? = (try? String(contentsOf: fileURL, encoding: .utf8)).map(sha256Hex)
            if existingDigest == skill.sha256 {
                try? fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: fileURL.path)
                receipts.append(PipiProjectedSkillReceipt(
                    slug: skill.slug,
                    version: skill.version,
                    sha256: skill.sha256,
                    filePath: fileURL.path,
                    status: .verified
                ))
                continue
            }

            let wasTampered = (existingDigest != nil)
            if wasTampered {
                try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
                try? fm.removeItem(at: fileURL)
            }

            try Data(skill.markdownBody.utf8).write(to: fileURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: fileURL.path)

            receipts.append(PipiProjectedSkillReceipt(
                slug: skill.slug,
                version: skill.version,
                sha256: skill.sha256,
                filePath: fileURL.path,
                status: wasTampered ? .repaired : .projected
            ))
        }

        return receipts
    }

    public static func verifyIntegrity(
        at rootURL: URL,
        slugs: [String]? = nil
    ) -> PipiSkillIntegrityReport {
        let selected = slugs.map { set in allPacks.filter { set.contains($0.slug) } } ?? allPacks
        var mismatches: [PipiSkillIntegrityMismatch] = []

        for skill in selected {
            let fileURL = rootURL
                .appendingPathComponent("skills", isDirectory: true)
                .appendingPathComponent("builtin", isDirectory: true)
                .appendingPathComponent(skill.slug, isDirectory: true)
                .appendingPathComponent("SKILL.md")
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                let actual = sha256Hex(content)
                if actual != skill.sha256 {
                    mismatches.append(PipiSkillIntegrityMismatch(
                        slug: skill.slug,
                        expectedSha256: skill.sha256,
                        actualSha256: actual
                    ))
                }
            } else {
                mismatches.append(PipiSkillIntegrityMismatch(
                    slug: skill.slug,
                    expectedSha256: skill.sha256,
                    actualSha256: nil
                ))
            }
        }

        return PipiSkillIntegrityReport(valid: mismatches.isEmpty, mismatches: mismatches)
    }
}
