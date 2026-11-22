import Foundation

// MARK: - Loop & Harness Engineering Engine (@N01ennn + @poteto Skill Pruning)

public enum PipiLoopHarnessEngine {

    // MARK: 1. Hard No-Draft Escalation Fence

    /// Returns the matched hard-escalation trigger if this message must go straight to the owner UNDRAFTED.
    public static func detectHardEscalation(input: String, fence: PipiHarnessFence) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for trigger in fence.hardNoDraftTriggers where !trigger.isEmpty {
            if trimmed.localizedCaseInsensitiveContains(trigger) {
                return trigger
            }
        }
        return nil
    }

    // MARK: 2. Tone Learning from Real Approved Replies (Not Style Guides)

    public static func renderApprovedExamplesBlock(examples: [PipiApprovedExample], limit: Int = 5) -> String {
        let picked = Array(examples.prefix(max(1, limit)))
        guard !picked.isEmpty else { return "" }
        var lines = ["## Owner-Approved Tone Examples (Match This Real Voice)"]
        for (idx, ex) in picked.enumerated() {
            lines.append("\(idx + 1). Input: \(ex.inputSummary)")
            lines.append("   Approved Reply: \(ex.approvedOutput)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: 3. "Don't Fix the Draft — Add a Rule" Rule Extractor

    public static func synthesizeHarnessRule(
        ownerFeedback: String,
        originalDraft: String,
        editedDraft: String?,
        lang: PipiResolvedLanguage = .zhHans
    ) -> String {
        let note = ownerFeedback.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            return note
        }
        if let edited = editedDraft?.trimmingCharacters(in: .whitespacesAndNewlines),
           !edited.isEmpty, edited != originalDraft.trimmingCharacters(in: .whitespacesAndNewlines) {
            return lang == .zhHans
                ? "优先按主人修订后的口径起草（参考范例：\(String(edited.prefix(64)))）"
                : "Match owner's revised phrasing style (example: \(String(edited.prefix(64))))"
        }
        return lang == .zhHans ? "草稿发送前需更贴近文档原意与主人简洁语气" : "Keep drafts concise and strictly grounded in docs."
    }

    // MARK: 4. Four Turnkey "Day Shift" Operational Loop Presets (@N01ennn)

    public static func makeDayShiftPreset(
        _ preset: PipiOperationalLoopPreset,
        botId: String,
        lang: PipiResolvedLanguage = .zhHans
    ) -> PipiOperationalLoop {
        switch preset {
        case .supportFromDocs:
            return PipiOperationalLoop(
                botId: botId,
                name: preset.title(lang),
                preset: preset,
                triggerKind: .channelMessage,
                contextSources: ["docs/", "approved_replies", "knowledge_gaps"],
                draftInstruction: lang == .zhHans
                    ? "当收到用户问题时，仅依据文档起草回复并附上引用文档路径；若文档未覆盖，不要编造，直接标注「文档缺失」并写入知识缺口清单；若像 Bug 则转交报错转工单环。所有回复必须经主人 Gate 批准后才能发出。"
                    : "Draft a reply using only our docs and link the doc page used. If docs do not cover it, say 'not in docs' and add it to the knowledge-gaps list. If it looks like a bug, hand it to the Bug Loop. Never send without owner approval.",
                requiresHumanGate: true,
                reportFeedsContext: true,
                harness: PipiHarnessFence(
                    allowedToolNames: ["read_file", "search_files", "query_entity_ledger"],
                    hardRules: [
                        "Answer strictly from docs; never guess undocumented behavior.",
                        "Never promise a release date.",
                        "Never send any user reply without owner Gate approval."
                    ],
                    docsOnlyMode: true
                )
            )

        case .bugToIssue:
            return PipiOperationalLoop(
                botId: botId,
                name: preset.title(lang),
                preset: preset,
                triggerKind: .channelMessage,
                contextSources: ["repo", "open_issues", "docs/"],
                draftInstruction: lang == .zhHans
                    ? "当消息描述功能异常或附带报错截图时，起草结构化 Issue（标题、现象、复现步骤、期望 vs 实际、运行环境、疑似重复 Issue 链接）；若缺少复现步骤，则改为起草简短追问。全部草稿停在 Gate 等待主人拍板。"
                    : "Draft a structured GitHub issue (title, what happened, repro steps, expected vs actual, environment, similar open issues). If repro steps are missing, draft a brief follow-up question instead. Wait at the Gate before creating or sending.",
                requiresHumanGate: true,
                reportFeedsContext: true,
                harness: PipiHarnessFence(
                    allowedToolNames: ["read_file", "search_files", "list_directory", "record_entity_ledger"],
                    hardRules: [
                        "Always check for duplicate open issues before drafting.",
                        "Never open an issue or message a user without Gate approval."
                    ],
                    docsOnlyMode: false
                )
            )

        case .weeklyChangelog:
            return PipiOperationalLoop(
                botId: botId,
                name: preset.title(lang),
                preset: preset,
                triggerKind: .schedule,
                contextSources: ["git_merged_this_week", "closed_issues"],
                draftInstruction: lang == .zhHans
                    ? "每周五读取本周合入主分支的变更，用面向用户的平实语言起草更新日志（新增 / 修复 / 调整），禁止直接贴 commit message 或内部代号；若某修复源自用户反馈则反链对应问题。发布前停在 Gate 等主人确认。"
                    : "Every Friday, read what merged into main this week and draft a user-facing changelog (New, Fixed, Changed) in plain language with no raw commit hashes or internal names. Link fixes back to user reports. Wait for owner approval before publishing.",
                requiresHumanGate: true,
                reportFeedsContext: true,
                harness: PipiHarnessFence(
                    allowedToolNames: ["run_shell", "read_file", "query_entity_ledger"],
                    hardRules: [
                        "Plain user language only — no raw commit messages or internal variable names.",
                        "Wait for owner Gate approval before publishing."
                    ],
                    docsOnlyMode: false
                )
            )

        case .weeklyPulse:
            return PipiOperationalLoop(
                botId: botId,
                name: preset.title(lang),
                preset: preset,
                triggerKind: .schedule,
                contextSources: ["usage_ledger", "open_issues", "merged_worktrees", "knowledge_gaps"],
                draftInstruction: lang == .zhHans
                    ? "每周一早上生成一条「上周一图流」简报：数字先行（任务完成数、Token 消耗、已合并改动、本周新增知识缺口 Top 3），最后列出需要主人拍板的事项。只读汇总，直接推送。"
                    : "Every Monday morning, compile a single-message weekly pulse: numbers first (runs completed, token usage, merged changes, top unanswered docs gaps), followed by anything needing owner decisions.",
                requiresHumanGate: false,
                reportFeedsContext: true,
                harness: PipiHarnessFence(
                    allowedToolNames: ["query_entity_ledger", "get_system_status"],
                    hardRules: ["Read-only digest; numbers first, then decisions needed."],
                    docsOnlyMode: false
                )
            )
        }
    }

    // MARK: 5. Skill Pruning & Prompt Bloat Audit (pstack v0.15.46)

    public static func auditPromptBloat(
        persona: PipiBotPersona,
        installedSkills: [PipiInstalledSkillPack],
        lang: PipiResolvedLanguage = .zhHans
    ) -> PipiContextBloatReport {
        let sysTokens = PipiUsageMeteringEngine.estimateTokens(for: persona.systemPrompt)
        let bpBlock = persona.automationBlueprint?.renderedPromptBlock() ?? ""
        let bpTokens = PipiUsageMeteringEngine.estimateTokens(for: bpBlock)

        let attachedSkills = installedSkills.filter {
            $0.enabled && (persona.assignedSkillSlugs.contains($0.id) || $0.scope == .global || $0.targetId == persona.id)
        }

        var weights: [PipiSkillWeightItem] = []
        var skillTokensTotal = 0
        for sk in attachedSkills {
            let t = PipiUsageMeteringEngine.estimateTokens(for: sk.bodyMarkdown)
            skillTokensTotal += t
            let bloated = t > 600
            let tip: String
            if bloated {
                tip = lang == .zhHans
                    ? "偏长（~\(t) tok），建议按 pstack 思路瘦身裁剪，并将重复规范晋升为确定性 Lint/校验规则。"
                    : "Bloated (~\(t) tok); prune prose and graduate repeatable checks into deterministic lint rules."
            } else {
                tip = lang == .zhHans ? "精炼健康" : "Lean & crisp"
            }
            weights.append(PipiSkillWeightItem(name: sk.name, estimatedTokens: t, isBloated: bloated, suggestion: tip))
        }
        weights.sort { $0.estimatedTokens > $1.estimatedTokens }

        // Detect Blueprint prose rules that should graduate to deterministic checks (Poteto Pyramid)
        let allRules = (persona.automationBlueprint?.sourceOfTruthRules ?? []) + (persona.automationBlueprint?.verificationCriteria ?? [])
        let gradKeywords = ["comment", "注释", "hex", "颜色", "secret", "密钥", "test", "单测", "lint", "格式", "todo", "hack", "build"]
        let candidates = allRules.filter { rule in
            let low = rule.lowercased()
            return gradKeywords.contains(where: { low.contains($0) })
        }

        let total = sysTokens + bpTokens + skillTokensTotal
        let bloatedCount = weights.filter(\.isBloated).count
        let summaryZh = bloatedCount == 0 && candidates.isEmpty
            ? "当前上下文精炼（约 \(total) tokens），无需大幅修剪。"
            : "总计约 \(total) tokens：发现 \(bloatedCount) 个偏长 Skill、\(candidates.count) 条可晋升为确定性校验的蓝图规则。"
        let summaryEn = bloatedCount == 0 && candidates.isEmpty
            ? "Prompt budget is lean (~\(total) tokens)."
            : "Total ~\(total) tokens: \(bloatedCount) bloated skill(s) to prune and \(candidates.count) rule(s) ready to graduate into deterministic checks."

        return PipiContextBloatReport(
            totalPromptTokens: total,
            systemPromptTokens: sysTokens,
            blueprintTokens: bpTokens,
            skillWeights: weights,
            graduationCandidates: candidates,
            summaryZh: summaryZh,
            summaryEn: summaryEn
        )
    }
}
