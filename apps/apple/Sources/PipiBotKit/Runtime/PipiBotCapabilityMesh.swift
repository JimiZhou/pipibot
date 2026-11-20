import Foundation

// MARK: - Effective Capability Snapshot & Autonomous Bot-to-Bot Peer Upgrade Engine

public struct PipiEffectiveBotCapabilities: Equatable, Sendable {
    public let botId: String
    public let resolvedVoiceProfileId: String
    public let skills: [String]
    public let tools: [String]
    public let connectors: [String]
    public let sharedMemoryPeers: [String]
}

public struct PipiPeerUpgradeOutcome: Equatable, Sendable {
    public let updatedBot: PipiBotPersona
    public let newUpgrades: [PipiBotPeerUpgradeRecord]
    public let borrowedMemorySnippets: [String]
}

/// Resolves per-agent + globally shared capabilities (voice, skills, tools, connectors, memory)
/// and enables autonomous bot-to-bot consultation and on-demand capability upgrades.
public enum PipiBotCapabilityMesh {

    public static func effectiveCapabilities(
        for bot: PipiBotPersona,
        allPersonas: [PipiBotPersona],
        globalPool: PipiGlobalCapabilityPool,
        globalDefaultVoiceId: String
    ) -> PipiEffectiveBotCapabilities {
        var skills = OrderedSet(bot.assignedSkillSlugs)
        var tools = OrderedSet(bot.enabledTools)
        var connectors = OrderedSet(bot.enabledConnectors)

        if bot.sharingPolicy.inheritGlobalPool {
            skills.append(contentsOf: globalPool.sharedSkillSlugs)
            tools.append(contentsOf: globalPool.sharedTools)
            connectors.append(contentsOf: globalPool.sharedConnectors)
        }

        // Learned peer upgrades remain active on this bot
        for upgrade in bot.learnedUpgrades {
            switch upgrade.kind {
            case .skill: skills.append(upgrade.capabilityId)
            case .tool: tools.append(upgrade.capabilityId)
            case .connector: connectors.append(upgrade.capabilityId)
            case .memory: break
            }
        }

        let memoryPeers: [String] = {
            guard globalPool.sharedMemoryEnabled && bot.sharingPolicy.inheritGlobalPool else { return [] }
            return allPersonas
                .filter { $0.id != bot.id && $0.sharingPolicy.shareMemory }
                .map(\.id)
        }()

        let voiceId: String = {
            if let explicit = bot.voiceProfileId, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return explicit
            }
            return globalDefaultVoiceId
        }()

        return PipiEffectiveBotCapabilities(
            botId: bot.id,
            resolvedVoiceProfileId: voiceId,
            skills: skills.elements,
            tools: tools.elements,
            connectors: connectors.elements,
            sharedMemoryPeers: memoryPeers
        )
    }

    /// Evaluates whether `targetBot` needs a skill, tool, connector, or peer memory insight for `prompt`,
    /// and autonomously consults eligible peers to upgrade `targetBot`'s capabilities when permitted.
    public static func evaluateAndUpgradeOnDemand(
        targetBot: PipiBotPersona,
        prompt: String,
        allPersonas: [PipiBotPersona],
        globalPool: PipiGlobalCapabilityPool,
        peerMemorySummaryLookup: (String) -> String? = { _ in nil },
        lang: PipiResolvedLanguage = .zhHans
    ) -> PipiPeerUpgradeOutcome {
        guard targetBot.sharingPolicy.allowPeerUpgrade && globalPool.autoPeerUpgradeEnabled else {
            return PipiPeerUpgradeOutcome(updatedBot: targetBot, newUpgrades: [], borrowedMemorySnippets: [])
        }

        let lower = prompt.lowercased()
        var wantedTools: [String] = []
        var wantedSkills: [String] = []
        var wantedConnectors: [String] = []

        // Intent-to-capability matching rules
        if lower.contains("git") || lower.contains("代码") || lower.contains("重构") || lower.contains("终端") || lower.contains("bug") || lower.contains("code") || lower.contains("build") {
            wantedTools.append(contentsOf: [PipiBotToolKind.terminalCli.rawValue, PipiBotToolKind.fileWorkspace.rawValue])
            wantedConnectors.append(PipiBotConnectorKind.localGit.rawValue)
        }
        if lower.contains("ppt") || lower.contains("幻灯片") || lower.contains("slide") || lower.contains("汇报") || lower.contains("演示") {
            wantedSkills.append(contentsOf: ["pptx", "slide-deck"])
        }
        if lower.contains("excel") || lower.contains("表格") || lower.contains("xlsx") || lower.contains("账单") || lower.contains("预算") {
            wantedSkills.append("xlsx")
        }
        if lower.contains("word") || lower.contains("docx") || lower.contains("pdf") || lower.contains("文档") || lower.contains("报告") {
            wantedSkills.append(contentsOf: ["docx", "pdf"])
        }
        if lower.contains("网页") || lower.contains("chrome") || lower.contains("浏览器") || lower.contains("browser") || lower.contains("桌面") || lower.contains("点击") {
            wantedTools.append(contentsOf: [PipiBotToolKind.browserSeat.rawValue, PipiBotToolKind.desktopControl.rawValue])
            wantedConnectors.append(PipiBotConnectorKind.chromeSession.rawValue)
            wantedSkills.append("humanlike-browse")
        }
        if lower.contains("日历") || lower.contains("日程") || lower.contains("提醒") || lower.contains("calendar") || lower.contains("schedule") {
            wantedConnectors.append(contentsOf: [PipiBotConnectorKind.appleCalendar.rawValue, PipiBotConnectorKind.appleReminders.rawValue])
            wantedSkills.append("proactive-response")
        }

        var updated = targetBot
        var newUpgrades: [PipiBotPeerUpgradeRecord] = []
        var borrowedMemory: [String] = []

        let peers = allPersonas.filter { $0.id != targetBot.id }

        // 1. Learn missing skills from consenting peers
        for slug in wantedSkills where !updated.assignedSkillSlugs.contains(slug) {
            if let donor = peers.first(where: { $0.sharingPolicy.shareSkills && $0.assignedSkillSlugs.contains(slug) }) {
                updated.assignedSkillSlugs.append(slug)
                let record = PipiBotPeerUpgradeRecord(
                    fromBotId: donor.id,
                    fromBotName: donor.name(lang),
                    toBotId: updated.id,
                    kind: .skill,
                    capabilityId: slug,
                    summary: lang == .zhHans
                        ? "按需向 \(donor.name(lang)) 学习并同步了技能「\(slug)」"
                        : "Learned skill '\(slug)' from \(donor.name(lang))"
                )
                updated.learnedUpgrades.insert(record, at: 0)
                newUpgrades.append(record)
            }
        }

        // 2. Learn missing tools from consenting peers
        for toolId in wantedTools where !updated.enabledTools.contains(toolId) {
            if let donor = peers.first(where: { $0.sharingPolicy.shareTools && $0.enabledTools.contains(toolId) }) {
                updated.enabledTools.append(toolId)
                let toolLabel = PipiBotToolKind(rawValue: toolId)?.label(lang) ?? toolId
                let record = PipiBotPeerUpgradeRecord(
                    fromBotId: donor.id,
                    fromBotName: donor.name(lang),
                    toBotId: updated.id,
                    kind: .tool,
                    capabilityId: toolId,
                    summary: lang == .zhHans
                        ? "按需向 \(donor.name(lang)) 同步并启用了工具「\(toolLabel)」"
                        : "Adopted tool '\(toolLabel)' from \(donor.name(lang))"
                )
                updated.learnedUpgrades.insert(record, at: 0)
                newUpgrades.append(record)
            }
        }

        // 3. Learn missing connectors from consenting peers
        for connId in wantedConnectors where !updated.enabledConnectors.contains(connId) {
            if let donor = peers.first(where: { $0.sharingPolicy.shareConnectors && $0.enabledConnectors.contains(connId) }) {
                updated.enabledConnectors.append(connId)
                let connLabel = PipiBotConnectorKind(rawValue: connId)?.label(lang) ?? connId
                let record = PipiBotPeerUpgradeRecord(
                    fromBotId: donor.id,
                    fromBotName: donor.name(lang),
                    toBotId: updated.id,
                    kind: .connector,
                    capabilityId: connId,
                    summary: lang == .zhHans
                        ? "按需向 \(donor.name(lang)) 共享接入了连接器「\(connLabel)」"
                        : "Shared connector '\(connLabel)' from \(donor.name(lang))"
                )
                updated.learnedUpgrades.insert(record, at: 0)
                newUpgrades.append(record)
            }
        }

        // 4. Borrow concise shared peer memory snippets when shared memory is enabled
        if globalPool.sharedMemoryEnabled {
            for peer in peers where peer.sharingPolicy.shareMemory {
                if let mem = peerMemorySummaryLookup(peer.id)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !mem.isEmpty {
                    let excerpt = String(mem.prefix(240))
                    borrowedMemory.append("[\(peer.name(lang))]: \(excerpt)")
                }
            }
        }

        if updated.learnedUpgrades.count > 30 {
            updated.learnedUpgrades = Array(updated.learnedUpgrades.prefix(30))
        }

        return PipiPeerUpgradeOutcome(
            updatedBot: updated,
            newUpgrades: newUpgrades,
            borrowedMemorySnippets: borrowedMemory
        )
    }

    /// Explicit peer sync: imports all shareable skills, tools, and connectors from consenting team peers.
    public static func syncAllShareableCapabilities(
        for targetBot: PipiBotPersona,
        allPersonas: [PipiBotPersona],
        peerMemorySummaryLookup: (String) -> String? = { _ in nil },
        lang: PipiResolvedLanguage = .zhHans
    ) -> PipiPeerUpgradeOutcome {
        guard targetBot.sharingPolicy.allowPeerUpgrade else {
            return PipiPeerUpgradeOutcome(updatedBot: targetBot, newUpgrades: [], borrowedMemorySnippets: [])
        }
        var updated = targetBot
        var newUpgrades: [PipiBotPeerUpgradeRecord] = []
        var borrowedMemory: [String] = []
        let peers = allPersonas.filter { $0.id != targetBot.id }

        for peer in peers {
            if peer.sharingPolicy.shareSkills {
                for slug in peer.assignedSkillSlugs where !updated.assignedSkillSlugs.contains(slug) {
                    updated.assignedSkillSlugs.append(slug)
                    let rec = PipiBotPeerUpgradeRecord(
                        fromBotId: peer.id,
                        fromBotName: peer.name(lang),
                        toBotId: updated.id,
                        kind: .skill,
                        capabilityId: slug,
                        summary: lang == .zhHans
                            ? "从 \(peer.name(lang)) 习得技能「\(slug)」"
                            : "Learned skill '\(slug)' from \(peer.name(lang))"
                    )
                    updated.learnedUpgrades.insert(rec, at: 0)
                    newUpgrades.append(rec)
                }
            }
            if peer.sharingPolicy.shareTools {
                for toolId in peer.enabledTools where !updated.enabledTools.contains(toolId) {
                    updated.enabledTools.append(toolId)
                    let label = PipiBotToolKind(rawValue: toolId)?.label(lang) ?? toolId
                    let rec = PipiBotPeerUpgradeRecord(
                        fromBotId: peer.id,
                        fromBotName: peer.name(lang),
                        toBotId: updated.id,
                        kind: .tool,
                        capabilityId: toolId,
                        summary: lang == .zhHans
                            ? "从 \(peer.name(lang)) 同步工具「\(label)」"
                            : "Synced tool '\(label)' from \(peer.name(lang))"
                    )
                    updated.learnedUpgrades.insert(rec, at: 0)
                    newUpgrades.append(rec)
                }
            }
            if peer.sharingPolicy.shareConnectors {
                for connId in peer.enabledConnectors where !updated.enabledConnectors.contains(connId) {
                    updated.enabledConnectors.append(connId)
                    let label = PipiBotConnectorKind(rawValue: connId)?.label(lang) ?? connId
                    let rec = PipiBotPeerUpgradeRecord(
                        fromBotId: peer.id,
                        fromBotName: peer.name(lang),
                        toBotId: updated.id,
                        kind: .connector,
                        capabilityId: connId,
                        summary: lang == .zhHans
                            ? "从 \(peer.name(lang)) 接入连接器「\(label)」"
                            : "Connected '\(label)' from \(peer.name(lang))"
                    )
                    updated.learnedUpgrades.insert(rec, at: 0)
                    newUpgrades.append(rec)
                }
            }
            if peer.sharingPolicy.shareMemory,
               let mem = peerMemorySummaryLookup(peer.id)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !mem.isEmpty {
                borrowedMemory.append("[\(peer.name(lang))]: \(String(mem.prefix(240)))")
            }
        }

        if updated.learnedUpgrades.count > 30 {
            updated.learnedUpgrades = Array(updated.learnedUpgrades.prefix(30))
        }
        return PipiPeerUpgradeOutcome(
            updatedBot: updated,
            newUpgrades: newUpgrades,
            borrowedMemorySnippets: borrowedMemory
        )
    }

    /// Formats an agent's active capabilities + shared peer memory into a concise runtime context addendum.
    public static func capabilityContextAddendum(
        for bot: PipiBotPersona,
        allPersonas: [PipiBotPersona],
        globalPool: PipiGlobalCapabilityPool,
        globalDefaultVoiceId: String,
        borrowedMemorySnippets: [String],
        lang: PipiResolvedLanguage
    ) -> String {
        let caps = effectiveCapabilities(
            for: bot,
            allPersonas: allPersonas,
            globalPool: globalPool,
            globalDefaultVoiceId: globalDefaultVoiceId
        )
        var lines: [String] = []
        if !caps.skills.isEmpty {
            lines.append("Active Skills: \(caps.skills.joined(separator: ", "))")
        }
        if !caps.tools.isEmpty {
            let toolNames = caps.tools.map { PipiBotToolKind(rawValue: $0)?.label(lang) ?? $0 }
            lines.append("Enabled Tools: \(toolNames.joined(separator: ", "))")
        }
        if !caps.connectors.isEmpty {
            let connNames = caps.connectors.map { PipiBotConnectorKind(rawValue: $0)?.label(lang) ?? $0 }
            lines.append("Connected Sources: \(connNames.joined(separator: ", "))")
        }
        if !borrowedMemorySnippets.isEmpty {
            lines.append("Shared Peer Memory:\n" + borrowedMemorySnippets.prefix(3).joined(separator: "\n"))
        }
        return lines.joined(separator: "\n")
    }
}

private struct OrderedSet<Element: Hashable> {
    private var seen = Set<Element>()
    private(set) var elements: [Element] = []

    init(_ items: [Element] = []) {
        append(contentsOf: items)
    }

    mutating func append(_ item: Element) {
        if seen.insert(item).inserted {
            elements.append(item)
        }
    }

    mutating func append(contentsOf items: [Element]) {
        for item in items {
            append(item)
        }
    }
}
