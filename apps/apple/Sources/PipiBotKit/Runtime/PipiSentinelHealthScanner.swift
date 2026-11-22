// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Sentinel: Zero-LLM Read-Only Health Scanner & Error Signature Clustering Engine.
// Redacts paths/numbers/UUIDs/URLs/emails/quotes before SHA-256 hashing so recurring errors collapse
// into one clean issue and automatically propose approval-gated Self-Evolution fixes when count >= 3.

import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct PipiSentinelEventSample: Sendable, Equatable {
    public let id: String
    public let kind: PipiSentinelIssueKind
    public let toolName: String?
    public let botId: String?
    public let rawMessage: String
    public let exitCode: Int?
    public let costUSD: Double?
    public let queueWaitSeconds: Double?
    public let timestamp: Date

    public init(
        id: String = UUID().uuidString,
        kind: PipiSentinelIssueKind,
        toolName: String? = nil,
        botId: String? = nil,
        rawMessage: String,
        exitCode: Int? = nil,
        costUSD: Double? = nil,
        queueWaitSeconds: Double? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.toolName = toolName
        self.botId = botId
        self.rawMessage = rawMessage
        self.exitCode = exitCode
        self.costUSD = costUSD
        self.queueWaitSeconds = queueWaitSeconds
        self.timestamp = timestamp
    }
}

public enum PipiSentinelHealthScanner {
    /// Normalizes a raw error line by redacting paths, URLs, emails, UUIDs, hex IDs, quoted literals, and numbers.
    public static func normalizeErrorLine(_ raw: String, exitCode: Int? = nil, isShell: Bool = false) -> String {
        let lower = raw.lowercased()
        if isShell {
            let errClass: String
            if lower.contains("timed out") || lower.contains("timeout") {
                return "shell: timed out"
            } else if lower.contains("command not found") {
                errClass = "command not found"
            } else if lower.contains("permission denied") {
                errClass = "permission denied"
            } else if lower.contains("no such file") {
                errClass = "no such file"
            } else if lower.contains("syntax error") {
                errClass = "syntax error"
            } else {
                errClass = "execution failed"
            }
            let code = exitCode ?? 1
            return "exit \(code): \(errClass)"
        }

        var line = raw.components(separatedBy: .newlines).first ?? raw
        let rules: [(String, String)] = [
            ("https?://[^\\s\"']+", "<url>"),
            ("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", "<email>"),
            ("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", "<uuid>"),
            ("(?:/[A-Za-z0-9._-]+){2,}", "<path>"),
            ("\"[^\"]{1,120}\"", "<str>"),
            ("'[^']{1,120}'", "<str>"),
            ("0x[0-9a-fA-F]{4,}", "<hex>"),
            ("\\b[0-9a-fA-F]{16,}\\b", "<hex>"),
            ("\\b\\d+\\b", "<n>")
        ]
        for (pattern, repl) in rules {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                line = regex.stringByReplacingMatches(in: line, options: [], range: range, withTemplate: repl)
            }
        }
        line = line.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(line.prefix(160))
    }

    public static func computeSignature(kind: PipiSentinelIssueKind, toolName: String?, normalizedTitle: String) -> String {
        let seed = "\(kind.rawValue)|\(toolName ?? "-")|\(normalizedTitle)"
        let hex = PipiE2EECrypto.sha256Hex(Data(seed.utf8))
        return "\(kind.rawValue):\(hex.prefix(16))"
    }

    /// Scans samples with zero LLM calls, clusters identical signatures, and returns ranked issues.
    public static func scan(
        samples: [PipiSentinelEventSample],
        existingIssues: [PipiSentinelIssue] = [],
        queueWaitThresholdSeconds: Double = 120,
        highCostThresholdUSD: Double = 2.0
    ) -> [PipiSentinelIssue] {
        var bySig: [String: PipiSentinelIssue] = [:]
        for issue in existingIssues {
            bySig[issue.signature] = issue
        }

        for sample in samples {
            var effectiveKind = sample.kind
            var normalized = ""
            var severity: PipiSentinelSeverity = .medium

            if let wait = sample.queueWaitSeconds, wait >= queueWaitThresholdSeconds {
                effectiveKind = .queueStall
                normalized = "queue wait exceeded \(Int(queueWaitThresholdSeconds))s threshold"
                severity = .high
            } else if let cost = sample.costUSD, cost >= highCostThresholdUSD {
                effectiveKind = .highCostTurn
                normalized = "single turn cost exceeded $\(String(format: "%.2f", highCostThresholdUSD))"
                severity = .medium
            } else {
                normalized = normalizeErrorLine(
                    sample.rawMessage,
                    exitCode: sample.exitCode,
                    isShell: sample.kind == .shellError
                )
                severity = (sample.kind == .routineFailure || sample.kind == .shellError) ? .high : .medium
            }

            let sig = computeSignature(kind: effectiveKind, toolName: sample.toolName, normalizedTitle: normalized)
            if var existing = bySig[sig] {
                if !existing.evidenceRefIds.contains(sample.id) {
                    existing.count += 1
                    existing.wastedTurns += 1
                    existing.lastSeenAt = max(existing.lastSeenAt, sample.timestamp)
                    existing.evidenceRefIds.append(sample.id)
                    if existing.evidenceRefIds.count > 20 {
                        existing.evidenceRefIds = Array(existing.evidenceRefIds.suffix(20))
                    }
                    bySig[sig] = existing
                }
            } else {
                bySig[sig] = PipiSentinelIssue(
                    signature: sig,
                    kind: effectiveKind,
                    severity: severity,
                    normalizedTitle: normalized,
                    toolName: sample.toolName,
                    botId: sample.botId,
                    count: 1,
                    wastedTurns: 1,
                    firstSeenAt: sample.timestamp,
                    lastSeenAt: sample.timestamp,
                    evidenceRefIds: [sample.id]
                )
            }
        }

        return Array(bySig.values).sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.lastSeenAt > $1.lastSeenAt
        }
    }

    /// Synthesizes approval-gated Self-Evolution proposals for recurring Sentinel issues (`count >= threshold`)
    /// that have not yet been promoted. Never auto-mutates any bot config.
    public static func synthesizeEvolutionProposals(
        issues: inout [PipiSentinelIssue],
        recurrenceThreshold: Int = 3
    ) -> [PipiBlueprintEvolutionProposal] {
        var proposals: [PipiBlueprintEvolutionProposal] = []
        for idx in issues.indices {
            guard issues[idx].count >= recurrenceThreshold,
                  issues[idx].promotedToEvolutionId == nil else { continue }
            let issue = issues[idx]
            let targetPersonaId = issue.botId ?? "bot_pipi_general"
            let guardRule = "Sentinel Guard (\(issue.signature)): Before invoking \(issue.toolName ?? "tool"), pre-check inputs to avoid recurring '\(issue.normalizedTitle)'."
            let diff = EvolutionDiffItem(
                diffId: "diff_sent_\(UUID().uuidString.prefix(6).lowercased())",
                operation: .add,
                targetFile: "bots/\(targetPersonaId)/blueprint.md",
                domain: .workContext,
                title: "Sentinel Guard Rule",
                previousValue: nil,
                proposedValue: guardRule,
                confidence: 0.92,
                evidenceSummary: "Detected \(issue.count) occurrences of \(issue.signature)"
            )
            let proposedBP = PipiBotAutomationBlueprint(
                goal: "Eliminate recurring error: \(issue.normalizedTitle)",
                sourceOfTruthRules: [guardRule],
                verificationCriteria: ["Zero recurrence of \(issue.signature)"]
            )
            let proposal = PipiBlueprintEvolutionProposal(
                botId: targetPersonaId,
                botName: issue.botId ?? "PiPiBot Fleet",
                goalSummary: "Sentinel 零 LLM 哨兵检测到重复故障（\(issue.count) 次）：\(issue.normalizedTitle)",
                rationale: "通过将高频失败模式固化为前置约束或确定性检查，可显著减少无效 Turn 与 Token 浪费。",
                diffs: [diff],
                proposedBlueprint: proposedBP
            )
            issues[idx].promotedToEvolutionId = proposal.id
            proposals.append(proposal)
        }
        return proposals
    }
}
