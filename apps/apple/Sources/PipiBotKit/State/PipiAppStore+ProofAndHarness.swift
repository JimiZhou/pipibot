import Foundation

// MARK: - v0.14.0 "Review Proof, Not Code" + Harness & Loop Engineering Store Extension

@MainActor
extension PipiAppStore {

    // MARK: 1. Review Proof, Not Code (Deterministic Checks + Multi-Model Panel)

    public func proofBundle(for worktreeSessionId: String) -> PipiVerificationProofBundle? {
        proofBundlesByWorktreeId[worktreeSessionId]
    }

    @discardableResult
    public func verifyWorktreeProof(sessionId: String) async -> PipiVerificationProofBundle? {
        guard let session = worktreeSessions.first(where: { $0.id == sessionId }) else { return nil }
        let refreshed = refreshWorktreeDiff(sessionId: sessionId) ?? session
        let bundle = await PipiProofVerificationEngine.buildProofBundle(
            session: refreshed,
            checks: deterministicChecks,
            panelProviders: readyLLMProviders,
            lang: resolvedLanguage
        )
        proofBundlesByWorktreeId[sessionId] = bundle
        if let idx = worktreeSessions.firstIndex(where: { $0.id == sessionId }) {
            worktreeSessions[idx].testSummary = bundle.evidenceSummary
        }
        return bundle
    }

    /// Graduate a repeatable prose Blueprint rule into an executable deterministic check (Poteto Pyramid).
    @discardableResult
    public func graduateRuleToDeterministicCheck(rule: String, removeFromBotId: String? = nil) -> PipiDeterministicCheckSpec {
        let spec = PipiProofVerificationEngine.graduateRuleToDeterministicCheck(rule: rule)
        if !deterministicChecks.contains(where: { $0.name == spec.name && $0.commandOrPattern == spec.commandOrPattern }) {
            deterministicChecks.insert(spec, at: 0)
        }
        if let botId = removeFromBotId,
           let idx = personas.firstIndex(where: { $0.id == botId }),
           var bp = personas[idx].automationBlueprint {
            bp.sourceOfTruthRules.removeAll { $0 == rule }
            bp.verificationCriteria.removeAll { $0 == rule }
            bp.blueprintVersion += 1
            personas[idx].automationBlueprint = bp
            saveResidentState()
        }
        noticeBanner = resolvedLanguage == .zhHans
            ? "🛡️ 已将规则晋升为确定性校验：「\(spec.name)」（从此由程序硬核兜底，不再耗费 Prompt 赌模型听话）"
            : "🛡️ Graduated prose rule into deterministic check: \(spec.name)"
        return spec
    }

    public func addDeterministicCheck(_ spec: PipiDeterministicCheckSpec) {
        deterministicChecks.insert(spec, at: 0)
    }

    public func toggleDeterministicCheck(id: String, enabled: Bool) {
        if let idx = deterministicChecks.firstIndex(where: { $0.id == id }) {
            deterministicChecks[idx].isEnabled = enabled
        }
    }

    // MARK: 2. Harness & 5-Part Operational Loops (Day Shift)

    @discardableResult
    public func installDayShiftLoop(_ preset: PipiOperationalLoopPreset, botId: String? = nil) -> PipiOperationalLoop {
        let targetBotId = botId ?? personas.first(where: { $0.id == "bot_pipi_operator" })?.id ?? activePersona.id
        if let existing = operationalLoops.first(where: { $0.preset == preset && $0.botId == targetBotId }) {
            return existing
        }
        let loop = PipiLoopHarnessEngine.makeDayShiftPreset(preset, botId: targetBotId, lang: resolvedLanguage)
        operationalLoops.insert(loop, at: 0)
        noticeBanner = resolvedLanguage == .zhHans
            ? "✅ 已启用 Day Shift 运营环：「\(loop.name)」（人工 Gate 闸门已就绪）"
            : "✅ Installed Day Shift loop: \(loop.name)"
        return loop
    }

    /// Submit a loop event through the Harness Fence:
    /// - Hard no-draft triggers (refunds/account/angry) bypass drafting and flag straight to the owner!
    /// - Normal items queue a Draft at the Human Gate waiting for owner Approve / Edit+Add-Rule / Discard.
    @discardableResult
    public func enqueueLoopDraft(
        loopId: String,
        inputSummary: String,
        draftContent: String,
        citedSources: [String] = [],
        missingDocQuestion: String? = nil
    ) -> PipiLoopDraftItem? {
        guard let loop = operationalLoops.first(where: { $0.id == loopId }) else { return nil }
        let botName = personas.first(where: { $0.id == loop.botId })?.name(resolvedLanguage) ?? strings.appName

        if let missingQ = missingDocQuestion?.trimmingCharacters(in: .whitespacesAndNewlines), !missingQ.isEmpty {
            recordKnowledgeGap(botId: loop.botId, loopId: loop.id, question: missingQ, sourceChannel: loop.name)
        }

        // Hard Escalation Fence: never draft sensitive/angry/refund messages
        if let matchedTrigger = PipiLoopHarnessEngine.detectHardEscalation(input: inputSummary, fence: loop.harness) {
            let flagged = PipiLoopDraftItem(
                loopId: loop.id,
                loopName: loop.name,
                botId: loop.botId,
                botName: botName,
                inputSummary: inputSummary,
                draftContent: "",
                citedSources: [],
                status: .flaggedUndrafted,
                escalationReason: resolvedLanguage == .zhHans
                    ? "命中高敏直转规则「\(matchedTrigger)」，按 Harness 护栏未代拟草稿，请主人亲自处理。"
                    : "Matched hard no-draft trigger \"\(matchedTrigger)\". Flagged undrafted for direct owner handling."
            )
            loopDrafts.insert(flagged, at: 0)
            return flagged
        }

        let item = PipiLoopDraftItem(
            loopId: loop.id,
            loopName: loop.name,
            botId: loop.botId,
            botName: botName,
            inputSummary: inputSummary,
            draftContent: draftContent,
            citedSources: citedSources,
            status: loop.requiresHumanGate ? .pendingGate : .approvedAndSent
        )
        loopDrafts.insert(item, at: 0)
        return item
    }

    /// Owner approves a Draft at the Gate -> automatically archives it as an Approved Tone Example!
    public func approveLoopDraft(id: String) {
        guard let idx = loopDrafts.firstIndex(where: { $0.id == id }) else { return }
        loopDrafts[idx].status = .approvedAndSent
        loopDrafts[idx].resolvedAt = ISO8601DateFormatter().string(from: Date())
        let item = loopDrafts[idx]

        if let lIdx = operationalLoops.firstIndex(where: { $0.id == item.loopId }) {
            operationalLoops[lIdx].approvedCount += 1
        }
        // Real approved reply becomes a golden few-shot tone example!
        let ex = PipiApprovedExample(
            botId: item.botId,
            loopId: item.loopId,
            inputSummary: item.inputSummary,
            approvedOutput: item.draftContent
        )
        approvedExamples.insert(ex, at: 0)
        if approvedExamples.count > 100 {
            approvedExamples = Array(approvedExamples.prefix(100))
        }
    }

    /// "Don't fix the draft — add a rule!" (@N01ennn):
    /// Owner edits/corrects a draft and turns the lesson into a persistent Harness rule (and optional Blueprint EvolutionDiff).
    public func editLoopDraftAndAddRule(
        id: String,
        editedDraft: String,
        newRuleNote: String,
        alsoGraduateToCheck: Bool = false
    ) {
        guard let idx = loopDrafts.firstIndex(where: { $0.id == id }) else { return }
        let original = loopDrafts[idx].draftContent
        let rule = PipiLoopHarnessEngine.synthesizeHarnessRule(
            ownerFeedback: newRuleNote,
            originalDraft: original,
            editedDraft: editedDraft,
            lang: resolvedLanguage
        )
        loopDrafts[idx].draftContent = editedDraft.isEmpty ? original : editedDraft
        loopDrafts[idx].addedHarnessRule = rule
        loopDrafts[idx].status = .editedAndSent
        loopDrafts[idx].resolvedAt = ISO8601DateFormatter().string(from: Date())
        let item = loopDrafts[idx]

        if let lIdx = operationalLoops.firstIndex(where: { $0.id == item.loopId }) {
            if !operationalLoops[lIdx].harness.hardRules.contains(rule) {
                operationalLoops[lIdx].harness.hardRules.append(rule)
            }
            operationalLoops[lIdx].approvedCount += 1
        }

        // Archive the revised version as an approved example for tone learning
        approvedExamples.insert(
            PipiApprovedExample(
                botId: item.botId,
                loopId: item.loopId,
                inputSummary: item.inputSummary,
                approvedOutput: item.draftContent
            ),
            at: 0
        )

        if alsoGraduateToCheck {
            _ = graduateRuleToDeterministicCheck(rule: rule)
        } else {
            _ = proposeBlueprintEvolution(
                botId: item.botId,
                rationale: resolvedLanguage == .zhHans ? "来自 Gate 草稿修订沉淀的 Harness 规则" : "Rule extracted from Gate draft revision",
                addedRules: [rule]
            )
        }
    }

    public func discardLoopDraft(id: String) {
        if let idx = loopDrafts.firstIndex(where: { $0.id == id }) {
            loopDrafts[idx].status = .discarded
            loopDrafts[idx].resolvedAt = ISO8601DateFormatter().string(from: Date())
        }
    }

    // MARK: 3. Knowledge Gaps Roadmap ("The Report Feeds the Context")

    @discardableResult
    public func recordKnowledgeGap(
        botId: String,
        loopId: String? = nil,
        question: String,
        sourceChannel: String = "support"
    ) -> PipiKnowledgeGapItem {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let nowIso = ISO8601DateFormatter().string(from: Date())
        if let idx = knowledgeGaps.firstIndex(where: {
            $0.status == .open && $0.question.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            knowledgeGaps[idx].occurrenceCount += 1
            knowledgeGaps[idx].updatedAt = nowIso
            return knowledgeGaps[idx]
        }
        let gap = PipiKnowledgeGapItem(
            botId: botId,
            loopId: loopId,
            question: trimmed,
            sourceChannel: sourceChannel,
            updatedAt: nowIso
        )
        knowledgeGaps.insert(gap, at: 0)
        return gap
    }

    public func resolveKnowledgeGap(id: String, docPath: String? = nil) {
        if let idx = knowledgeGaps.firstIndex(where: { $0.id == id }) {
            knowledgeGaps[idx].status = .resolved
            knowledgeGaps[idx].resolvedDocPath = docPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            knowledgeGaps[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        }
    }

    // MARK: 4. Skill Pruning & Context Bloat Audit (pstack)

    public func auditPromptBloat(for persona: PipiBotPersona) -> PipiContextBloatReport {
        PipiLoopHarnessEngine.auditPromptBloat(
            persona: persona,
            installedSkills: ecosystemManager.installedSkills,
            lang: resolvedLanguage
        )
    }

    public func pendingGateDraftCount() -> Int {
        loopDrafts.filter { $0.status == .pendingGate || $0.status == .flaggedUndrafted }.count
    }

    // MARK: 5. Clean-Room MIT Bot Persona & Lean Skill Marketplace Installation

    @discardableResult
    public func installMarketplaceBot(_ listing: PipiMarketplaceBotListing) -> PipiBotPersona {
        if let existing = personas.first(where: { $0.id == listing.id }) {
            selectPersona(existing.id)
            return existing
        }
        // Install any recommended lean skills cleanly as MIT packs
        for skillId in listing.recommendedSkills {
            if let sk = PipiBotMarketplaceCatalog.curatedSkills.first(where: { $0.id == skillId }) {
                _ = installMarketplaceSkill(sk, targetBotId: listing.id)
            }
        }
        let persona = PipiBotPersona(
            id: listing.id,
            nameZh: listing.nameZh,
            nameEn: listing.nameEn,
            roleZh: listing.taglineZh,
            roleEn: listing.taglineEn,
            greetingZh: "你好，我是「\(listing.nameZh)」。我的核心目标是：\(listing.blueprint.goal)",
            greetingEn: "Hi, I'm \(listing.nameEn). My goal: \(listing.blueprint.goal)",
            systemPrompt: listing.systemPrompt,
            accent: listing.accent,
            avatarShape: listing.avatarShape,
            idleAvatarState: .ambientBreathe,
            preferredTarget: .auto,
            permissionTier: .autoEdit,
            isBuiltIn: false,
            assignedSkillSlugs: listing.recommendedSkills,
            enabledTools: [
                PipiBotToolKind.personalWiki.rawValue,
                PipiBotToolKind.fileWorkspace.rawValue,
                PipiBotToolKind.terminalCli.rawValue
            ],
            enabledConnectors: [PipiBotConnectorKind.localGit.rawValue, PipiBotConnectorKind.localMcp.rawValue],
            automationBlueprint: listing.blueprint
        )
        personas.append(persona)
        if let loopPreset = listing.defaultLoopPreset {
            _ = installDayShiftLoop(loopPreset, botId: persona.id)
        }
        saveResidentState()
        noticeBanner = resolvedLanguage == .zhHans
            ? "✅ 已从 MIT 市场安装人设「\(listing.nameZh)」（附带蓝图与 \(listing.recommendedSkills.count) 个精炼技能）"
            : "✅ Installed MIT Marketplace Bot \"\(listing.nameEn)\" with Blueprint & \(listing.recommendedSkills.count) lean skills"
        return persona
    }

    @discardableResult
    public func installMarketplaceSkill(_ listing: PipiMarketplaceSkillListing, targetBotId: String? = nil) -> PipiInstalledSkillPack {
        let pack = PipiInstalledSkillPack(
            id: listing.id,
            name: listing.name(resolvedLanguage),
            description: "[\(listing.license)] \(listing.summary(resolvedLanguage))",
            source: "pipibot-mit-marketplace://\(listing.id)",
            scope: targetBotId == nil ? .global : .bot,
            targetId: targetBotId,
            tags: listing.tags,
            bodyMarkdown: listing.bodyMarkdown,
            enabled: true
        )
        ecosystemManager.upsertSkillPack(pack)
        if let targetBotId, let bIdx = personas.firstIndex(where: { $0.id == targetBotId }),
           !personas[bIdx].assignedSkillSlugs.contains(pack.id) {
            personas[bIdx].assignedSkillSlugs.append(pack.id)
        }
        noticeBanner = resolvedLanguage == .zhHans
            ? "✅ 已安装 MIT 精炼技能「\(listing.nameZh)」（约 \(listing.estimatedTokens) tokens）"
            : "✅ Installed MIT lean skill \"\(listing.nameEn)\" (~\(listing.estimatedTokens) tokens)"
        return pack
    }
}
