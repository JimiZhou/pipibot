// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Portable Redacted Bot / Team Template Engine (`bot.md` / `team.md` + `skills/*/SKILL.md`).
// Bidirectional compatibility with community Markdown+YAML frontmatter team templates AND PiPiBot Blueprint/Proof extensions.

import Foundation

public enum PipiPortableTemplateEngine {
    private static let secretPatterns: [(String, String)] = [
        ("sk-[A-Za-z0-9_-]{16,}", "<REDACTED_API_KEY>"),
        ("sk-ant-[A-Za-z0-9_-]{16,}", "<REDACTED_ANTHROPIC_KEY>"),
        ("AIza[0-9A-Za-z_-]{25,}", "<REDACTED_GOOGLE_KEY>"),
        ("gh[pousr]_[A-Za-z0-9]{20,}", "<REDACTED_GITHUB_TOKEN>"),
        ("xox[baprs]-[A-Za-z0-9-]{16,}", "<REDACTED_SLACK_TOKEN>"),
        ("Bearer\\s+[A-Za-z0-9._-]{20,}", "Bearer <REDACTED_TOKEN>"),
        ("pipi_(?:dev|brk)_[A-Za-z0-9_-]{12,}", "<REDACTED_PIPIBOT_TOKEN>"),
        ("-----BEGIN [A-Z ]+PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]+PRIVATE KEY-----", "<REDACTED_PRIVATE_KEY>"),
        ("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", "<REDACTED_EMAIL>"),
        ("/Users/[A-Za-z0-9._-]+", "<HOME>"),
        ("/home/[A-Za-z0-9._-]+", "<HOME>")
    ]

    private static let forbiddenFilenames: Set<String> = [
        ".env", ".env.local", ".env.production", "credentials.json", "id_rsa", "id_ed25519", "vault.enc"
    ]

    /// Redacts secrets, emails, private keys, and local home paths from text, returning `(cleaned, redactionCount)`.
    public static func redactSensitiveText(_ input: String) -> (cleaned: String, count: Int) {
        var text = input
        var total = 0
        for (pattern, replacement) in secretPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = regex.numberOfMatches(in: text, options: [], range: range)
            if matches > 0 {
                total += matches
                text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
            }
        }
        return (text, total)
    }

    public static func isFileAllowedForExport(relativePath: String, byteCount: Int) -> Bool {
        if byteCount > 128 * 1024 { return false }
        let lower = relativePath.lowercased()
        let parts = lower.split(separator: "/").map(String.init)
        if parts.contains("node_modules") || parts.contains("__pycache__") || parts.contains(".git") || parts.contains("venv") {
            return false
        }
        if let file = parts.last {
            if forbiddenFilenames.contains(file) { return false }
            if file.hasPrefix(".") || file.hasSuffix(".pem") || file.hasSuffix(".key") || file.hasSuffix(".p12") || file.hasSuffix(".sqlite") {
                return false
            }
        }
        return true
    }

    /// Exports a single Bot or whole Team into a portable, privacy-redacted Markdown + YAML Frontmatter document.
    /// Routines are ALWAYS exported paused (`enabled: false`); chat transcripts, memory, and secrets are NEVER included.
    public static func exportToMarkdown(
        name: String,
        tagline: String,
        bots: [PipiBotPersona],
        skills: [PipiInstalledSkillPack] = [],
        routines: [PipiBotRoutine] = [],
        channelName: String? = nil
    ) -> (markdown: String, package: PipiPortableTemplatePackage) {
        let scope = bots.count > 1 ? "team" : "bot"
        var redactions = 0

        let cleanName = redactSensitiveText(name)
        redactions += cleanName.count
        let cleanTagline = redactSensitiveText(tagline)
        redactions += cleanTagline.count

        var portableBots: [PipiPortableBotSpec] = []
        for bot in bots {
            let botName = bot.name(.zhHans)
            let botRole = bot.role(.zhHans)
            let cleanPrompt = redactSensitiveText(bot.systemPrompt)
            redactions += cleanPrompt.count
            let cleanRole = redactSensitiveText(botRole)
            redactions += cleanRole.count
            let slug = slugify(botName)
            var cleanBlueprint = bot.automationBlueprint
            if var bp = cleanBlueprint {
                let g = redactSensitiveText(bp.goal)
                redactions += g.count
                bp.goal = g.cleaned
                cleanBlueprint = bp
            }
            portableBots.append(PipiPortableBotSpec(
                slug: slug,
                name: botName,
                roleTitle: cleanRole.cleaned,
                tagline: cleanRole.cleaned,
                instructionsMarkdown: cleanPrompt.cleaned,
                skillNames: bot.assignedSkillSlugs,
                recommendedIsolation: .sandboxBox,
                automationBlueprint: cleanBlueprint
            ))
        }

        var portableSkills: [PipiPortableSkillSpec] = []
        for skill in skills {
            let cleanBody = redactSensitiveText(skill.bodyMarkdown)
            redactions += cleanBody.count
            portableSkills.append(PipiPortableSkillSpec(
                slug: slugify(skill.name),
                name: skill.name,
                description: skill.description,
                markdownBody: cleanBody.cleaned
            ))
        }

        var portableRoutines: [PipiPortableRoutineSpec] = []
        for r in routines {
            let cleanPrompt = redactSensitiveText(r.prompt)
            redactions += cleanPrompt.count
            let ownerBotName = bots.first(where: { $0.id == r.personaId })?.name(.zhHans) ?? bots.first?.name(.zhHans) ?? "lead"
            portableRoutines.append(PipiPortableRoutineSpec(
                title: r.title,
                botSlug: slugify(ownerBotName),
                prompt: cleanPrompt.cleaned,
                triggerKind: r.triggerKind,
                cronExpression: r.eventConfig.cronExpression,
                enabled: false // Security invariant: imported/exported routines always arrive paused
            ))
        }

        let pkg = PipiPortableTemplatePackage(
            scope: scope,
            name: cleanName.cleaned,
            tagline: cleanTagline.cleaned,
            bots: portableBots,
            skills: portableSkills,
            routines: portableRoutines,
            channelName: channelName,
            redactedSecretsCount: redactions,
            skippedFiles: [],
            sourceDescription: "Exported from PiPiBot (redacted)"
        )

        let md = renderMarkdown(package: pkg)
        return (md, pkg)
    }

    public static func renderMarkdown(package: PipiPortableTemplatePackage) -> String {
        var lines: [String] = [
            "---",
            "format: \(package.formatVersion)",
            "scope: \(package.scope)",
            "name: \(yamlEscape(package.name))",
            "tagline: \(yamlEscape(package.tagline))"
        ]
        if let ch = package.channelName, !ch.isEmpty {
            lines.append("channel: \(yamlEscape(ch))")
        }
        lines.append("bots:")
        for b in package.bots {
            lines.append("  - slug: \(b.slug)")
            lines.append("    name: \(yamlEscape(b.name))")
            lines.append("    role: \(yamlEscape(b.roleTitle))")
            lines.append("    isolation: \(b.recommendedIsolation.rawValue)")
            if let bp = b.automationBlueprint {
                lines.append("    goal: \(yamlEscape(bp.goal))")
            }
        }
        if !package.routines.isEmpty {
            lines.append("routines:")
            for r in package.routines {
                lines.append("  - title: \(yamlEscape(r.title))")
                lines.append("    bot: \(r.botSlug)")
                lines.append("    trigger: \(r.triggerKind.rawValue)")
                if let cron = r.cronExpression, !cron.isEmpty {
                    lines.append("    cron: \(yamlEscape(cron))")
                }
                lines.append("    enabled: false")
            }
        }
        lines.append("---")
        lines.append("")
        lines.append("# \(package.name)")
        lines.append("")
        if !package.tagline.isEmpty {
            lines.append("> \(package.tagline)")
            lines.append("")
        }
        for b in package.bots {
            lines.append("## Bot: \(b.name)")
            lines.append("- **Role**: \(b.roleTitle)")
            if let bp = b.automationBlueprint {
                lines.append("- **Goal**: \(bp.goal)")
            }
            lines.append("")
            lines.append(b.instructionsMarkdown.isEmpty ? "Follow your role and verification criteria carefully." : b.instructionsMarkdown)
            lines.append("")
        }
        if !package.skills.isEmpty {
            lines.append("## Skills")
            for sk in package.skills {
                lines.append("### Skill: \(sk.name)")
                lines.append(sk.markdownBody)
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Parses either PiPiBot `pipibot-portable-v1` or community OpenMausBot/BotMRR `bot.md` / `team.md` Markdown+YAML templates.
    public static func parseMarkdown(_ rawMarkdown: String, sourceDescription: String = "Imported template") -> PipiPortableTemplatePackage {
        let redacted = redactSensitiveText(rawMarkdown)
        let text = redacted.cleaned
        let (frontmatter, body) = splitFrontmatter(text)

        var scope = "bot"
        var name = "Imported Bot"
        var tagline = ""
        var channelName: String? = nil
        var parsedBots: [PipiPortableBotSpec] = []
        var parsedRoutines: [PipiPortableRoutineSpec] = []

        var inBotsList = false
        var inRoutinesList = false
        var currentBot: [String: String] = [:]
        var currentRoutine: [String: String] = [:]

        func flushBot() {
            guard let bName = currentBot["name"]?.trimmingCharacters(in: .whitespacesAndNewlines), !bName.isEmpty else {
                currentBot = [:]
                return
            }
            let slug = currentBot["slug"] ?? slugify(bName)
            let role = currentBot["role"] ?? currentBot["tagline"] ?? "Specialist Agent"
            let goal = currentBot["goal"]
            let bp = goal.map { PipiBotAutomationBlueprint(goal: $0, processSteps: [], verificationCriteria: ["Verify completion before replying."]) }
            parsedBots.append(PipiPortableBotSpec(
                slug: slug,
                name: bName,
                roleTitle: role,
                tagline: role,
                instructionsMarkdown: "",
                recommendedIsolation: .sandboxBox,
                automationBlueprint: bp
            ))
            currentBot = [:]
        }

        func flushRoutine() {
            guard let title = currentRoutine["title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                currentRoutine = [:]
                return
            }
            let trig = PipiRoutineTriggerKind(rawValue: currentRoutine["trigger"] ?? "schedule") ?? .schedule
            parsedRoutines.append(PipiPortableRoutineSpec(
                title: title,
                botSlug: currentRoutine["bot"] ?? parsedBots.first?.slug ?? "lead",
                prompt: currentRoutine["prompt"] ?? title,
                triggerKind: trig,
                cronExpression: currentRoutine["cron"],
                enabled: false
            ))
            currentRoutine = [:]
        }

        for rawLine in frontmatter.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if !rawLine.hasPrefix(" ") && !rawLine.hasPrefix("\t") {
                flushBot()
                flushRoutine()
                inBotsList = false
                inRoutinesList = false
                if let idx = trimmed.firstIndex(of: ":") {
                    let key = String(trimmed[..<idx]).trimmingCharacters(in: .whitespaces).lowercased()
                    let val = unquoteYAML(String(trimmed[trimmed.index(after: idx)...]))
                    switch key {
                    case "scope": scope = val.isEmpty ? scope : val
                    case "name", "title": if !val.isEmpty { name = val }
                    case "tagline", "description": tagline = val
                    case "channel", "department": if !val.isEmpty { channelName = val }
                    case "bots", "agents", "members": inBotsList = true
                    case "routines", "triggers", "schedules": inRoutinesList = true
                    default: break
                    }
                }
            } else if inBotsList {
                if trimmed.hasPrefix("- ") {
                    flushBot()
                    let rest = String(trimmed.dropFirst(2))
                    if let idx = rest.firstIndex(of: ":") {
                        let k = String(rest[..<idx]).trimmingCharacters(in: .whitespaces).lowercased()
                        let v = unquoteYAML(String(rest[rest.index(after: idx)...]))
                        currentBot[k] = v
                    }
                } else if let idx = trimmed.firstIndex(of: ":") {
                    let k = String(trimmed[..<idx]).trimmingCharacters(in: .whitespaces).lowercased()
                    let v = unquoteYAML(String(trimmed[trimmed.index(after: idx)...]))
                    currentBot[k] = v
                }
            } else if inRoutinesList {
                if trimmed.hasPrefix("- ") {
                    flushRoutine()
                    let rest = String(trimmed.dropFirst(2))
                    if let idx = rest.firstIndex(of: ":") {
                        let k = String(rest[..<idx]).trimmingCharacters(in: .whitespaces).lowercased()
                        let v = unquoteYAML(String(rest[rest.index(after: idx)...]))
                        currentRoutine[k] = v
                    }
                } else if let idx = trimmed.firstIndex(of: ":") {
                    let k = String(trimmed[..<idx]).trimmingCharacters(in: .whitespaces).lowercased()
                    let v = unquoteYAML(String(trimmed[trimmed.index(after: idx)...]))
                    currentRoutine[k] = v
                }
            }
        }
        flushBot()
        flushRoutine()

        // Extract per-bot instructions from `## Bot: <name>` sections, or fallback to body for single-bot `bot.md`
        let sectionMap = extractBotSections(from: body)
        if parsedBots.isEmpty {
            parsedBots.append(PipiPortableBotSpec(
                slug: slugify(name),
                name: name,
                roleTitle: tagline.isEmpty ? "Imported Specialist" : tagline,
                tagline: tagline,
                instructionsMarkdown: body.trimmingCharacters(in: .whitespacesAndNewlines),
                recommendedIsolation: .sandboxBox
            ))
        } else {
            parsedBots = parsedBots.map { bot in
                let matchedBody = sectionMap[bot.name.lowercased()] ?? (parsedBots.count == 1 ? body.trimmingCharacters(in: .whitespacesAndNewlines) : bot.instructionsMarkdown)
                return PipiPortableBotSpec(
                    slug: bot.slug,
                    name: bot.name,
                    roleTitle: bot.roleTitle,
                    tagline: bot.tagline,
                    instructionsMarkdown: matchedBody,
                    skillNames: bot.skillNames,
                    recommendedIsolation: .sandboxBox,
                    automationBlueprint: bot.automationBlueprint
                )
            }
        }

        if parsedBots.count > 1 { scope = "team" }
        return PipiPortableTemplatePackage(
            scope: scope,
            name: name,
            tagline: tagline,
            bots: parsedBots,
            skills: [],
            routines: parsedRoutines,
            channelName: channelName,
            redactedSecretsCount: redacted.count,
            skippedFiles: [],
            sourceDescription: sourceDescription
        )
    }

    private static func splitFrontmatter(_ text: String) -> (String, String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("---") else { return ("", trimmed) }
        let afterOpen = trimmed.dropFirst(3)
        if let closeRange = afterOpen.range(of: "\n---") {
            let fm = String(afterOpen[..<closeRange.lowerBound])
            let body = String(afterOpen[closeRange.upperBound...])
            return (fm, body)
        }
        return ("", trimmed)
    }

    private static func extractBotSections(from body: String) -> [String: String] {
        var result: [String: String] = [:]
        var activeName: String? = nil
        var buffer: [String] = []
        for line in body.components(separatedBy: .newlines) {
            if line.hasPrefix("## Bot:") {
                if let activeName {
                    result[activeName.lowercased()] = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                activeName = String(line.dropFirst("## Bot:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                buffer = []
            } else if line.hasPrefix("## ") {
                if let activeName {
                    result[activeName.lowercased()] = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                activeName = nil
                buffer = []
            } else if activeName != nil {
                buffer.append(line)
            }
        }
        if let activeName {
            result[activeName.lowercased()] = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func yamlEscape(_ value: String) -> String {
        let clean = value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\"", with: "'")
        return "\"\(clean)\""
    }

    private static func unquoteYAML(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")), s.count >= 2 {
            s = String(s.dropFirst().dropLast())
        }
        return s
    }

    private static func slugify(_ raw: String) -> String {
        let lower = raw.lowercased()
        let allowed = lower.map { ch -> Character in
            if ch.isASCII && (ch.isLetter || ch.isNumber) { return ch }
            return "-"
        }
        let collapsed = String(allowed).replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "bot-\(UUID().uuidString.prefix(6).lowercased())" : collapsed
    }
}
