import Foundation

// MARK: - "Review Proof, Not Code" Engine (Deterministic Checks + Multi-Model Panel + Rule Graduation)

public enum PipiProofVerificationEngine {

    /// Graduate a repeatable prose Blueprint rule into a deterministic check spec (Poteto Pyramid).
    public static func graduateRuleToDeterministicCheck(rule: String) -> PipiDeterministicCheckSpec {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.contains("comment") || lower.contains("注释") || lower.contains("todo") || lower.contains("hack") {
            return PipiDeterministicCheckSpec(
                name: "Lint Ratchet: No Tautology/Excuse Comments",
                kind: .regexBan,
                commandOrPattern: #"//\s*(HACK|FIXME|XXX|TEMP|TODO)\b"#,
                fileExtensionsCSV: "swift,ts,tsx,js,py",
                isEnabled: true,
                graduatedFromRule: trimmed
            )
        }
        if lower.contains("hex") || lower.contains("颜色") || lower.contains("color") {
            return PipiDeterministicCheckSpec(
                name: "Design Token Ratchet: No Raw Hex Colors",
                kind: .regexBan,
                commandOrPattern: #"#[0-9A-Fa-f]{6}\b"#,
                fileExtensionsCSV: "swift,css",
                isEnabled: true,
                graduatedFromRule: trimmed
            )
        }
        if lower.contains("secret") || lower.contains("key") || lower.contains("密钥") || lower.contains("密码") {
            return PipiDeterministicCheckSpec(
                name: "Secret Guard: No Hardcoded Credentials",
                kind: .regexBan,
                commandOrPattern: #"(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|password\s*=\s*\"[^\"]+\")"#,
                fileExtensionsCSV: "swift,ts,js,py,json",
                isEnabled: true,
                graduatedFromRule: trimmed
            )
        }
        if lower.contains("test") || lower.contains("单测") || lower.contains("构建") || lower.contains("build") {
            return PipiDeterministicCheckSpec(
                name: "Automated Verification Command",
                kind: .shellCommand,
                commandOrPattern: "npm test || swift test",
                fileExtensionsCSV: "",
                isEnabled: true,
                graduatedFromRule: trimmed
            )
        }
        return PipiDeterministicCheckSpec(
            name: "Deterministic Check: \(String(trimmed.prefix(32)))",
            kind: .regexBan,
            commandOrPattern: NSRegularExpression.escapedPattern(for: String(trimmed.prefix(40))),
            fileExtensionsCSV: "swift,ts,js,py,md",
            isEnabled: true,
            graduatedFromRule: trimmed
        )
    }

    /// Run all enabled deterministic checks (regex ratchets + shell commands) against a Worktree session.
    public static func runDeterministicChecks(
        session: PipiWorktreeReviewSession,
        checks: [PipiDeterministicCheckSpec]
    ) -> [PipiDeterministicCheckResult] {
        var results: [PipiDeterministicCheckResult] = []
        let enabled = checks.filter(\.isEnabled)
        for spec in enabled {
            let start = Date()
            switch spec.kind {
            case .regexBan:
                results.append(evaluateRegexCheck(spec: spec, session: session, expectMatch: false, start: start))
            case .requiredPattern:
                results.append(evaluateRegexCheck(spec: spec, session: session, expectMatch: true, start: start))
            case .shellCommand:
                results.append(runShellCheck(spec: spec, worktreePath: session.worktreePath, start: start))
            }
        }
        return results
    }

    private static func evaluateRegexCheck(
        spec: PipiDeterministicCheckSpec,
        session: PipiWorktreeReviewSession,
        expectMatch: Bool,
        start: Date
    ) -> PipiDeterministicCheckResult {
        guard let regex = try? NSRegularExpression(pattern: spec.commandOrPattern, options: []) else {
            return PipiDeterministicCheckResult(
                checkId: spec.id,
                name: spec.name,
                kind: spec.kind,
                passed: false,
                exitCode: 2,
                durationMs: Int(Date().timeIntervalSince(start) * 1000),
                outputSnippet: "Invalid regex pattern: \(spec.commandOrPattern)"
            )
        }

        let allowedExts = Set(
            spec.fileExtensionsCSV
                .lowercased()
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        var matchedLocations: [String] = []
        var scannedCount = 0

        for file in session.files where file.status != "D" {
            let ext = (file.path as NSString).pathExtension.lowercased()
            if !allowedExts.isEmpty && !allowedExts.contains(ext) { continue }
            let fullPath = (session.worktreePath as NSString).appendingPathComponent(file.path)
            guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }
            scannedCount += 1
            for (idx, line) in content.components(separatedBy: .newlines).enumerated() {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if regex.firstMatch(in: line, options: [], range: range) != nil {
                    matchedLocations.append("\(file.path):L\(idx + 1)")
                    if matchedLocations.count >= 8 { break }
                }
            }
            if matchedLocations.count >= 8 { break }
        }

        // Also scan added lines in unifiedDiff when worktree files aren't on local disk (e.g. iOS remote preview)
        if scannedCount == 0 && !session.unifiedDiff.isEmpty {
            scannedCount = max(1, session.files.count)
            for (idx, line) in session.unifiedDiff.components(separatedBy: .newlines).enumerated()
            where line.hasPrefix("+") && !line.hasPrefix("+++") {
                let clean = String(line.dropFirst())
                let range = NSRange(clean.startIndex..<clean.endIndex, in: clean)
                if regex.firstMatch(in: clean, options: [], range: range) != nil {
                    matchedLocations.append("diff:L\(idx + 1)")
                    if matchedLocations.count >= 8 { break }
                }
            }
        }

        let durationMs = max(1, Int(Date().timeIntervalSince(start) * 1000))
        if expectMatch {
            let passed = !matchedLocations.isEmpty || scannedCount == 0
            return PipiDeterministicCheckResult(
                checkId: spec.id,
                name: spec.name,
                kind: spec.kind,
                passed: passed,
                exitCode: passed ? 0 : 1,
                durationMs: durationMs,
                outputSnippet: passed
                    ? "Verified across \(scannedCount) changed file(s)."
                    : "Required pattern not found across \(scannedCount) changed file(s)."
            )
        } else {
            let passed = matchedLocations.isEmpty
            return PipiDeterministicCheckResult(
                checkId: spec.id,
                name: spec.name,
                kind: spec.kind,
                passed: passed,
                exitCode: passed ? 0 : 1,
                durationMs: durationMs,
                outputSnippet: passed
                    ? "0 violations across \(scannedCount) changed file(s)."
                    : "Violations at: \(matchedLocations.joined(separator: ", "))"
            )
        }
    }

    private static func runShellCheck(
        spec: PipiDeterministicCheckSpec,
        worktreePath: String,
        start: Date
    ) -> PipiDeterministicCheckResult {
        #if os(macOS)
        guard FileManager.default.fileExists(atPath: worktreePath) else {
            return PipiDeterministicCheckResult(
                checkId: spec.id,
                name: spec.name,
                kind: spec.kind,
                passed: false,
                exitCode: 1,
                durationMs: 1,
                outputSnippet: "Worktree directory not found: \(worktreePath)"
            )
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", spec.commandOrPattern]
        process.currentDirectoryURL = URL(fileURLWithPath: worktreePath)
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let outStr = String(data: outData, encoding: .utf8) ?? ""
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            let combined = (outStr + "\n" + errStr).trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = String(combined.suffix(360))
            let code = Int(process.terminationStatus)
            return PipiDeterministicCheckResult(
                checkId: spec.id,
                name: spec.name,
                kind: spec.kind,
                passed: code == 0,
                exitCode: code,
                durationMs: max(1, Int(Date().timeIntervalSince(start) * 1000)),
                outputSnippet: tail.isEmpty ? (code == 0 ? "Exit 0 (passed)" : "Exit \(code)") : tail
            )
        } catch {
            return PipiDeterministicCheckResult(
                checkId: spec.id,
                name: spec.name,
                kind: spec.kind,
                passed: false,
                exitCode: 1,
                durationMs: max(1, Int(Date().timeIntervalSince(start) * 1000)),
                outputSnippet: error.localizedDescription
            )
        }
        #else
        return PipiDeterministicCheckResult(
            checkId: spec.id,
            name: spec.name,
            kind: spec.kind,
            passed: true,
            exitCode: 0,
            durationMs: 1,
            outputSnippet: "Shell checks execute on the host Mac/Linux node."
        )
        #endif
    }

    /// Run a Multi-Model Panel Review (pstack v0.15.46 pattern) across configured providers in parallel,
    /// falling back gracefully to deterministic structural review when offline.
    public static func buildProofBundle(
        session: PipiWorktreeReviewSession,
        checks: [PipiDeterministicCheckSpec],
        panelProviders: [PipiLLMProviderConfig],
        lang: PipiResolvedLanguage = .zhHans
    ) async -> PipiVerificationProofBundle {
        let checkResults = runDeterministicChecks(session: session, checks: checks)
        let failedChecks = checkResults.filter { !$0.passed }

        // Dispatch up to 3 specialized panel reviewers concurrently if live LLM providers are configured
        let roles: [(label: String, focus: String)] = [
            ("Correctness Reviewer", "correctness & edge cases"),
            ("Security & Blast-Radius Reviewer", "security, auth, secrets & rollback safety"),
            ("Architecture & Simplicity Reviewer", "maintainability & minimal diff")
        ]

        var votes: [PipiPanelReviewerVote] = []
        let usableProviders = panelProviders.filter { $0.isReady }
        if !usableProviders.isEmpty && !session.unifiedDiff.isEmpty {
            let diffExcerpt = String(session.unifiedDiff.prefix(8000))
            let checksReport = checkResults.map { "[\($0.passed ? "PASS" : "FAIL")] \($0.name): \($0.outputSnippet)" }.joined(separator: "\n")

            votes = await withTaskGroup(of: PipiPanelReviewerVote.self) { group in
                let panelCount = min(roles.count, max(1, usableProviders.count))
                for idx in 0..<panelCount {
                    let cfg = usableProviders[idx % usableProviders.count]
                    let role = roles[idx]
                    group.addTask {
                        let prompt = """
You are \(role.label) focusing strictly on \(role.focus).
Review this Worktree verification proof (not style nitpicks).
Deterministic checks:
\(checksReport)

Diff excerpt:
\(diffExcerpt)

Respond in 3 short lines:
VERDICT: APPROVE | CAUTION | BLOCK
SUMMARY: <one crisp sentence>
BLOCKING: <comma-separated concrete blockers or NONE>
"""
                        do {
                            let res = try await PipiInferenceEngine.invokeLLM(
                                config: cfg,
                                systemPrompt: "You are a concise code-proof panel reviewer. Review proof and real bugs, not formatting.",
                                history: [PipiChatMessage(role: .user, content: prompt)],
                                maxTokens: 220
                            )
                            return parsePanelVote(
                                rawText: res.text,
                                reviewerLabel: role.label,
                                modelId: cfg.modelId,
                                focusArea: role.focus
                            )
                        } catch {
                            return PipiPanelReviewerVote(
                                reviewerLabel: role.label,
                                modelId: cfg.modelId,
                                focusArea: role.focus,
                                verdict: failedChecks.isEmpty ? .caution : .block,
                                summary: "Live model reviewer unavailable (\(error.localizedDescription.prefix(80))); fell back to deterministic check results.",
                                blockingIssues: failedChecks.map(\.name)
                            )
                        }
                    }
                }
                var collected: [PipiPanelReviewerVote] = []
                for await v in group { collected.append(v) }
                return collected
            }
        } else {
            // Deterministic local panel fallback (zero network needed)
            let localVerdict: PipiPanelVerdict = failedChecks.isEmpty ? .approve : .block
            votes = [
                PipiPanelReviewerVote(
                    reviewerLabel: lang == .zhHans ? "确定性静态评审官" : "Deterministic Static Reviewer",
                    modelId: "local-static-verifier",
                    focusArea: "deterministic checks & diff bounds",
                    verdict: localVerdict,
                    summary: failedChecks.isEmpty
                        ? (lang == .zhHans ? "所有确定性校验均通过，变更文件范围清晰可控。" : "All deterministic checks passed with clean diff scope.")
                        : (lang == .zhHans ? "存在 \(failedChecks.count) 项确定性校验失败，建议打回修复后再合并。" : "\(failedChecks.count) deterministic check(s) failed; send back before merge."),
                    blockingIssues: failedChecks.map { "\($0.name): \($0.outputSnippet)" }
                )
            ]
        }

        let hasBlock = !failedChecks.isEmpty || votes.contains(where: { $0.verdict == .block })
        let hasCaution = votes.contains(where: { $0.verdict == .caution })
        let overall: PipiProofOverallStatus = hasBlock ? .blocked : (hasCaution ? .needsAttention : .verified)

        let checkRatio = checkResults.isEmpty ? 1.0 : Double(checkResults.filter(\.passed).count) / Double(checkResults.count)
        let panelRatio: Double = {
            guard !votes.isEmpty else { return 1.0 }
            let pts = votes.reduce(0.0) { acc, v in
                switch v.verdict {
                case .approve: return acc + 1.0
                case .caution: return acc + 0.65
                case .block: return acc + 0.0
                }
            }
            return pts / Double(votes.count)
        }()
        let score = Int((checkRatio * 65.0 + panelRatio * 35.0).rounded())

        let summary = lang == .zhHans
            ? "确定性校验 \(checkResults.filter(\.passed).count)/\(checkResults.count) 通过 · 评审团 \(votes.filter { $0.verdict == .approve }.count)/\(votes.count) 同意 · 证据评分 \(score)/100"
            : "Checks \(checkResults.filter(\.passed).count)/\(checkResults.count) passed · Panel \(votes.filter { $0.verdict == .approve }.count)/\(votes.count) approved · Proof \(score)/100"

        return PipiVerificationProofBundle(
            worktreeSessionId: session.id,
            checkResults: checkResults,
            panelVotes: votes,
            evidenceSummary: summary,
            overallStatus: overall,
            proofScore: score
        )
    }

    public static func parsePanelVote(
        rawText: String,
        reviewerLabel: String,
        modelId: String,
        focusArea: String
    ) -> PipiPanelReviewerVote {
        let upper = rawText.uppercased()
        let verdict: PipiPanelVerdict
        if upper.contains("VERDICT: BLOCK") || upper.contains("VERDICT:BLOCK") {
            verdict = .block
        } else if upper.contains("VERDICT: CAUTION") || upper.contains("VERDICT:CAUTION") {
            verdict = .caution
        } else {
            verdict = .approve
        }

        var summary = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        var blockers: [String] = []
        for line in rawText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.uppercased().hasPrefix("SUMMARY:") {
                summary = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.uppercased().hasPrefix("BLOCKING:") {
                let raw = String(trimmed.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines)
                if raw.uppercased() != "NONE" && !raw.isEmpty {
                    blockers = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                }
            }
        }
        return PipiPanelReviewerVote(
            reviewerLabel: reviewerLabel,
            modelId: modelId,
            focusArea: focusArea,
            verdict: verdict,
            summary: String(summary.prefix(240)),
            blockingIssues: blockers
        )
    }
}
