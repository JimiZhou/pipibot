import Foundation

// MARK: - v0.13.0 Automation Closure & Multi-Agent Orchestration Control Plane

@MainActor
extension PipiAppStore {

    // MARK: 1. Bot Architect (Dr Eggbot) Materialization & Blueprint Editing

    public var botArchitectPersona: PipiBotPersona {
        personas.first(where: { $0.id == PipiBotPersona.botArchitectId }) ?? PipiBotPersona.botArchitectDefault
    }

    public func openBotArchitectSession() -> PipiConversation {
        if !personas.contains(where: { $0.id == PipiBotPersona.botArchitectId }) {
            personas.append(PipiBotPersona.botArchitectDefault)
        }
        selectPersona(PipiBotPersona.botArchitectId)
        if let existing = conversations.first(where: { $0.personaId == PipiBotPersona.botArchitectId && !$0.isArchived }) {
            activeConversationId = existing.id
            saveResidentState()
            return existing
        }
        return createConversation(for: PipiBotPersona.botArchitectId, title: resolvedLanguage == .zhHans ? "设计新 Bot" : "Design New Bot", activate: true)
    }

    /// Materializes or upgrades a Bot with a full Goal-First Automation Blueprint and optional Event-Driven Routine.
    @discardableResult
    public func materializeBlueprintBot(from args: [String: String]) -> (persona: PipiBotPersona, routine: PipiBotRoutine?, summary: String) {
        let lang = resolvedLanguage
        let name = (args["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (lang == .zhHans ? "自动化助手" : "Automation Bot")
        let role = (args["role"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (args["goal"] ?? name)
        let goal = (args["goal"] ?? role).trimmingCharacters(in: .whitespacesAndNewlines)

        func splitSemi(_ key: String) -> [String] {
            guard let raw = args[key], !raw.isEmpty else { return [] }
            return raw
                .replacingOccurrences(of: "；", with: ";")
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        let steps = splitSemi("process_steps")
        let rules = splitSemi("source_of_truth_rules")
        let checks = splitSemi("verification_criteria")
        let escalations = splitSemi("escalation_rules")
        let feedbacks = splitSemi("feedback_sources")
        let entityIds = splitSemi("entity_ids")
        let modelId = args["model_id"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let blueprint = PipiBotAutomationBlueprint(
            goal: goal,
            processSteps: steps,
            sourceOfTruthRules: rules,
            verificationCriteria: checks,
            escalationRules: escalations,
            feedbackSources: feedbacks,
            entityIdSchema: entityIds
        )

        let persona: PipiBotPersona
        if let idx = personas.firstIndex(where: { $0.nameZh.caseInsensitiveCompare(name) == .orderedSame || $0.nameEn.caseInsensitiveCompare(name) == .orderedSame }) {
            var updated = personas[idx]
            updated.roleZh = role
            updated.roleEn = role
            if let modelId { updated.preferredModelId = modelId }
            var nextBp = blueprint
            nextBp.blueprintVersion = (updated.automationBlueprint?.blueprintVersion ?? 0) + 1
            updated.automationBlueprint = nextBp
            personas[idx] = updated
            persona = updated
        } else {
            let tpl = PipiBotPersonaTemplate.catalog.last!
            var created = tpl.instantiate(
                customName: name,
                customPrompt: "You are \(name), a goal-driven full-stack worker inside PiPiBot. Follow your Automation Blueprint strictly, verify your work before finishing, and log cross-source entity states.",
                permissionTier: .autoEdit,
                preferredTarget: .auto,
                preferredModelId: modelId
            )
            created.roleZh = role
            created.roleEn = role
            created.automationBlueprint = blueprint
            personas.append(created)
            persona = created
        }

        var createdRoutine: PipiBotRoutine? = nil
        if let rawTrigger = args["trigger_kind"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !rawTrigger.isEmpty {
            let triggerKind = PipiRoutineTriggerKind(rawValue: rawTrigger) ?? .schedule
            let triggerValue = args["trigger_value"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            var eventCfg = PipiRoutineEventConfig()
            switch triggerKind {
            case .schedule:
                if let triggerValue, triggerValue.split(separator: " ").count == 5 {
                    eventCfg.cronExpression = triggerValue
                }
            case .webhook:
                eventCfg.webhookSecret = triggerValue?.nilIfEmpty ?? "whsec_\(UUID().uuidString.prefix(12).lowercased())"
            case .fileOrGitWatch:
                eventCfg.watchPath = triggerValue?.nilIfEmpty ?? workspaceDirectory
                eventCfg.watchGitEvents = true
            case .channelMessage:
                eventCfg.messageKeyword = triggerValue?.nilIfEmpty ?? name
                eventCfg.channelFilter = "any"
            case .hostHealth:
                eventCfg.healthMetric = PipiHealthTriggerMetric(rawValue: triggerValue ?? "") ?? .cpuPercent
                eventCfg.healthThreshold = 85
            }
            let rt = PipiBotRoutine(
                personaId: persona.id,
                title: lang == .zhHans ? "\(name) · 自动触发任务" : "\(name) · Automated Routine",
                prompt: "Goal: \(goal)\nExecute your Automation Blueprint steps and verify completion criteria.",
                schedule: .daily,
                triggerKind: triggerKind,
                eventConfig: eventCfg,
                isEnabled: true
            )
            routines.insert(rt, at: 0)
            createdRoutine = rt
        }

        saveResidentState()
        let routineLine: String
        if let rt = createdRoutine {
            routineLine = lang == .zhHans
                ? "\n• 自动触发器：\(rt.triggerKind.label(lang))（\(rt.scheduleBadge(lang))）"
                : "\n• Trigger: \(rt.triggerKind.label(lang)) (\(rt.scheduleBadge(lang)))"
        } else {
            routineLine = ""
        }
        let summary = lang == .zhHans
            ? "✅ 已为你装配自动化 Bot「\(persona.name(lang))」（蓝图 v\(persona.automationBlueprint?.blueprintVersion ?? 1)）：\n• 终极目标：\(goal)\n• 流程步骤：\(steps.count) 步 | 验收项：\(checks.count) 条 | 数据源规则：\(rules.count) 条\(routineLine)"
            : "✅ Materialized automated Bot \"\(persona.name(lang))\" (Blueprint v\(persona.automationBlueprint?.blueprintVersion ?? 1)):\n• Goal: \(goal)\n• Steps: \(steps.count) | Verification checks: \(checks.count) | Rules: \(rules.count)\(routineLine)"
        return (persona, createdRoutine, summary)
    }

    // MARK: 2. Entity Correlation Ledger & Goal-Driven Self-Evolution

    @discardableResult
    public func upsertEntityLedgerEntry(
        botId: String,
        entityKey: String,
        entityType: String = "generic",
        source: String = "pipibot",
        status: String = "active",
        summary: String,
        attributes: [String: String] = [:]
    ) -> PipiEntityLedgerEntry {
        let entry = PipiEntityLedgerEntry(
            botId: botId,
            entityKey: entityKey,
            entityType: entityType,
            source: source,
            status: status,
            summary: summary,
            attributes: attributes
        )
        let merged = PipiEntityLedgerStore.upsert(entry, in: &entityLedgerEntries)
        PipiEntityLedgerStore.save(entityLedgerEntries)
        return merged
    }

    public func queryEntityLedger(botId: String? = nil, entityKey: String? = nil, search: String? = nil) -> [PipiEntityLedgerEntry] {
        PipiEntityLedgerStore.query(entries: entityLedgerEntries, botId: botId, entityKey: entityKey, search: search)
    }

    public func recordRunOutcome(
        botId: String,
        routineId: String? = nil,
        taskTitle: String,
        succeeded: Bool,
        verificationNotes: String,
        userCorrection: String? = nil,
        entityKeys: [String] = [],
        durationMs: Int = 0
    ) {
        let rec = PipiRunOutcomeRecord(
            botId: botId,
            routineId: routineId,
            taskTitle: taskTitle,
            succeeded: succeeded,
            verificationNotes: verificationNotes,
            userCorrection: userCorrection,
            entityKeys: entityKeys,
            durationMs: durationMs
        )
        runOutcomeRecords.insert(rec, at: 0)
        if runOutcomeRecords.count > 300 {
            runOutcomeRecords = Array(runOutcomeRecords.prefix(300))
        }
        // Automatically synthesize an approval-gated EvolutionDiff proposal when failures/corrections accumulate
        if PipiSelfEvolutionEngine.shouldSuggestEvolution(
            botId: botId,
            outcomes: runOutcomeRecords,
            existingPendingProposals: blueprintEvolutionProposals,
            failureThreshold: 2
        ), let persona = personas.first(where: { $0.id == botId }) {
            let proposal = PipiSelfEvolutionEngine.synthesizeProposalFromOutcomes(
                persona: persona,
                outcomes: runOutcomeRecords,
                lang: resolvedLanguage
            )
            blueprintEvolutionProposals.insert(proposal, at: 0)
            noticeBanner = resolvedLanguage == .zhHans
                ? "✨ 「\(persona.name(resolvedLanguage))」基于执行反馈生成了 1 条蓝图自进化 Diff 提案，请在任务台审批。"
                : "✨ \"\(persona.name(resolvedLanguage))\" proposed a Blueprint EvolutionDiff for your approval."
        }
    }

    @discardableResult
    public func proposeBlueprintEvolution(
        botId: String,
        rationale: String,
        proposedGoal: String? = nil,
        proposedSteps: [String]? = nil,
        addedRules: [String] = [],
        addedVerification: [String] = [],
        addedEscalation: [String] = []
    ) -> PipiBlueprintEvolutionProposal? {
        guard let persona = personas.first(where: { $0.id == botId }) else { return nil }
        let proposal = PipiSelfEvolutionEngine.buildProposal(
            persona: persona,
            proposedGoal: proposedGoal,
            proposedSteps: proposedSteps,
            addedRules: addedRules,
            addedVerification: addedVerification,
            addedEscalation: addedEscalation,
            rationale: rationale,
            lang: resolvedLanguage
        )
        blueprintEvolutionProposals.insert(proposal, at: 0)
        return proposal
    }

    public func approveBlueprintEvolutionProposal(id: String) {
        guard let pIdx = blueprintEvolutionProposals.firstIndex(where: { $0.id == id }),
              let botIdx = personas.firstIndex(where: { $0.id == blueprintEvolutionProposals[pIdx].botId }) else { return }
        PipiSelfEvolutionEngine.applyApprovedProposal(&blueprintEvolutionProposals[pIdx], to: &personas[botIdx])
        saveResidentState()
        noticeBanner = resolvedLanguage == .zhHans
            ? "✅ 已批准「\(blueprintEvolutionProposals[pIdx].botName)」的蓝图进化（v\(personas[botIdx].automationBlueprint?.blueprintVersion ?? 1)）"
            : "✅ Approved blueprint evolution for \(blueprintEvolutionProposals[pIdx].botName)"
    }

    public func rejectBlueprintEvolutionProposal(id: String, note: String? = nil) {
        guard let pIdx = blueprintEvolutionProposals.firstIndex(where: { $0.id == id }) else { return }
        blueprintEvolutionProposals[pIdx].status = .rejected
        blueprintEvolutionProposals[pIdx].resolvedAt = ISO8601DateFormatter().string(from: Date())
        blueprintEvolutionProposals[pIdx].resolutionNote = note
    }

    public func rollbackBlueprintEvolutionProposal(id: String) {
        guard let pIdx = blueprintEvolutionProposals.firstIndex(where: { $0.id == id }),
              let botIdx = personas.firstIndex(where: { $0.id == blueprintEvolutionProposals[pIdx].botId }) else { return }
        PipiSelfEvolutionEngine.rollbackProposal(&blueprintEvolutionProposals[pIdx], on: &personas[botIdx])
        saveResidentState()
        noticeBanner = resolvedLanguage == .zhHans
            ? "↩️ 已回滚「\(blueprintEvolutionProposals[pIdx].botName)」到上一个蓝图版本"
            : "↩️ Rolled back blueprint for \(blueprintEvolutionProposals[pIdx].botName)"
    }

    // MARK: 3. Event-Driven Routine Engine (Webhook, FS/Git, Channel, Health, Cron)

    public func webhookURLString(for routine: PipiBotRoutine) -> String {
        let port = remoteTunnelManager.state.localPort ?? 18792
        return "http://127.0.0.1:\(port)/api/v1/webhooks/\(routine.id)"
    }

    public func handleIncomingWebhook(
        routineId: String,
        authorizationHeader: String?,
        signatureHeader: String?,
        body: Data
    ) async -> (status: Int, message: String) {
        guard let routine = routines.first(where: { $0.id == routineId }) else {
            return (404, "Routine not found: \(routineId)")
        }
        guard routine.isEnabled, routine.triggerKind == .webhook else {
            return (409, "Routine is disabled or not a webhook trigger")
        }
        guard PipiEventTriggerEngine.verifyWebhookAuth(
            secret: routine.eventConfig.webhookSecret,
            authorizationHeader: authorizationHeader,
            signatureHeader: signatureHeader,
            body: body
        ) else {
            return (401, "Invalid webhook signature or Bearer secret")
        }
        if PipiEventTriggerEngine.isWithinCooldown(
            lastRunAt: routine.lastRunAt,
            cooldownSeconds: routine.eventConfig.cooldownSeconds
        ) {
            return (429, "Cooldown active for routine \(routineId)")
        }
        let bodyText = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        await triggerEventRoutine(
            routine,
            triggerSummary: "HTTP Webhook POST /api/v1/webhooks/\(routineId)",
            payloadPreview: bodyText.isEmpty ? nil : String(bodyText.prefix(500))
        )
        return (202, "Triggered routine \(routine.title)")
    }

    /// Check channel-message routines whenever an inbound WeChat or Group message arrives.
    public func evaluateChannelMessageRoutines(channel: String, text: String) {
        let matched = routines.filter { routine in
            PipiEventTriggerEngine.matchesChannelMessage(routine: routine, channel: channel, text: text)
                && !PipiEventTriggerEngine.isWithinCooldown(lastRunAt: routine.lastRunAt, cooldownSeconds: routine.eventConfig.cooldownSeconds)
        }
        for routine in matched {
            Task { @MainActor [weak self] in
                await self?.triggerEventRoutine(
                    routine,
                    triggerSummary: "Channel(\(channel)) matched \"\(routine.eventConfig.messageKeyword ?? "")\"",
                    payloadPreview: String(text.prefix(280))
                )
            }
        }
    }

    /// Periodic sweep for `.fileOrGitWatch` and `.hostHealth` event routines.
    public func evaluateEventDrivenRoutines(now: Date = Date()) async {
        // 1. File / Git Watchers
        for routine in routines where routine.isEnabled && routine.triggerKind == .fileOrGitWatch {
            guard let watchPath = routine.eventConfig.watchPath, !watchPath.isEmpty else { continue }
            guard let fp = PipiEventTriggerEngine.computeWorkspaceFingerprint(
                path: watchPath,
                watchGitEvents: routine.eventConfig.watchGitEvents
            ) else { continue }
            if let prev = watchFingerprintsByRoutineId[routine.id] {
                if prev != fp && !PipiEventTriggerEngine.isWithinCooldown(
                    lastRunAt: routine.lastRunAt,
                    cooldownSeconds: routine.eventConfig.cooldownSeconds,
                    now: now
                ) {
                    watchFingerprintsByRoutineId[routine.id] = fp
                    await triggerEventRoutine(
                        routine,
                        triggerSummary: "Workspace/Git changed at \((watchPath as NSString).lastPathComponent)",
                        payloadPreview: "Path: \(watchPath)"
                    )
                }
            } else {
                // Baseline fingerprint on first sweep
                watchFingerprintsByRoutineId[routine.id] = fp
            }
        }

        // 2. Host Health Thresholds
        let healthRoutines = routines.filter { $0.isEnabled && $0.triggerKind == .hostHealth }
        if !healthRoutines.isEmpty {
            let cpuPct = telemetryMonitor.snapshot.cpuUsagePercent
            let memPct = telemetryMonitor.snapshot.memoryUsagePercent
            let diskFree: Double = {
                if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
                   let freeBytes = attrs[.systemFreeSize] as? NSNumber {
                    return freeBytes.doubleValue / 1_073_741_824.0
                }
                return 100.0
            }()
            let offlineNodes = meshHubClient.nodes.filter { !$0.isOnline }.map(\.name)
            for routine in healthRoutines {
                guard !PipiEventTriggerEngine.isWithinCooldown(
                    lastRunAt: routine.lastRunAt,
                    cooldownSeconds: routine.eventConfig.cooldownSeconds,
                    now: now
                ) else { continue }
                if let reason = PipiEventTriggerEngine.evaluateHostHealth(
                    routine: routine,
                    cpuPercent: cpuPct,
                    memoryPercent: memPct,
                    diskFreeGB: diskFree,
                    offlineHostNames: offlineNodes
                ) {
                    await triggerEventRoutine(
                        routine,
                        triggerSummary: "Host Health: \(reason)",
                        payloadPreview: reason
                    )
                }
            }
        }
    }

    public func triggerEventRoutine(
        _ routine: PipiBotRoutine,
        triggerSummary: String,
        payloadPreview: String? = nil
    ) async {
        let start = Date()
        let logId = "rtlog_\(UUID().uuidString.prefix(8).lowercased())"
        let log = PipiRoutineRunLog(
            id: logId,
            routineId: routine.id,
            routineTitle: routine.title,
            botId: routine.personaId,
            triggerKind: routine.triggerKind,
            triggerSummary: triggerSummary,
            payloadPreview: payloadPreview,
            status: .running
        )
        routineRunLogs.insert(log, at: 0)
        if routineRunLogs.count > 80 {
            routineRunLogs = Array(routineRunLogs.prefix(80))
        }

        let nowIso = ISO8601DateFormatter().string(from: start)
        if let idx = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[idx].lastRunAt = nowIso
            saveResidentState()
        }

        let augmentedPrompt: String
        if let payloadPreview, !payloadPreview.isEmpty {
            augmentedPrompt = "\(routine.prompt)\n\n[Event Trigger: \(triggerSummary)]\n\(payloadPreview)"
        } else {
            augmentedPrompt = "\(routine.prompt)\n\n[Event Trigger: \(triggerSummary)]"
        }

        let bgConv = createConversation(
            for: routine.personaId,
            title: routine.title.isEmpty ? triggerSummary : routine.title,
            activate: false
        )
        await sendPersonalMessage(
            augmentedPrompt,
            conversationId: bgConv.id,
            personaId: routine.personaId,
            activateTargetConversation: false,
            priority: .proactiveRoutine
        )

        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        let latestReply = conversations.first(where: { $0.id == bgConv.id })?.messages.last(where: { $0.role == .assistant })?.content ?? ""
        if let lIdx = routineRunLogs.firstIndex(where: { $0.id == logId }) {
            routineRunLogs[lIdx].status = latestReply.isEmpty ? .failed : .succeeded
            routineRunLogs[lIdx].outputPreview = String(latestReply.prefix(240))
            routineRunLogs[lIdx].durationMs = elapsedMs
        }
        recordRunOutcome(
            botId: routine.personaId,
            routineId: routine.id,
            taskTitle: routine.title.isEmpty ? triggerSummary : routine.title,
            succeeded: !latestReply.isEmpty,
            verificationNotes: String(latestReply.prefix(180)),
            durationMs: elapsedMs
        )
    }

    // MARK: 4. Git Worktree Smart Auto-Isolation & Diff Review Closure

    public func activeWorktreeCount(forRepoPath repoPath: String) -> Int {
        guard let root = PipiWorktreeManager.detectGitRepoRoot(for: repoPath) else { return 0 }
        return worktreeSessions.filter {
            $0.repoPath == root && ($0.status == .active || $0.status == .changesRequested)
        }.count
    }

    /// Prepares an isolated Git Worktree when smart auto-isolation policy applies (or manual isolation is requested).
    @discardableResult
    public func prepareWorktreeIfNeeded(
        repoPath: String,
        taskTitle: String,
        persona: PipiBotPersona,
        conversationId: String? = nil,
        groupId: String? = nil,
        isGroupParallel: Bool = false,
        projectAlwaysUseWorktree: Bool = false,
        forceCreate: Bool = false
    ) -> PipiWorktreeReviewSession? {
        let activeCount = activeWorktreeCount(forRepoPath: repoPath)
        let shouldIsolate = forceCreate || PipiWorktreeManager.shouldIsolateWithWorktree(
            repoPath: repoPath,
            isGroupParallel: isGroupParallel,
            activeRepoTaskCount: activeCount,
            projectAlwaysUseWorktree: projectAlwaysUseWorktree
        )
        guard shouldIsolate else { return nil }
        do {
            let session = try PipiWorktreeManager.createWorktree(
                repoPath: repoPath,
                taskTitle: taskTitle,
                botId: persona.id,
                botName: persona.name(resolvedLanguage),
                conversationId: conversationId,
                groupId: groupId
            )
            worktreeSessions.insert(session, at: 0)
            return session
        } catch {
            return nil
        }
    }

    @discardableResult
    public func refreshWorktreeDiff(sessionId: String) -> PipiWorktreeReviewSession? {
        guard let idx = worktreeSessions.firstIndex(where: { $0.id == sessionId }) else { return nil }
        let updated = PipiWorktreeManager.captureDiffSnapshot(for: worktreeSessions[idx])
        worktreeSessions[idx] = updated
        return updated
    }

    public func sendBackWorktreeFeedback(
        sessionId: String,
        feedback: String,
        filePath: String? = nil,
        lineNumber: Int? = nil
    ) async {
        let trimmed = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = worktreeSessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let cmt = PipiWorktreeReviewComment(filePath: filePath, lineNumber: lineNumber, comment: trimmed)
        worktreeSessions[idx].comments.append(cmt)
        worktreeSessions[idx].status = .changesRequested
        worktreeSessions[idx].updatedAt = ISO8601DateFormatter().string(from: Date())

        let session = worktreeSessions[idx]
        let prompt = PipiWorktreeManager.buildSendBackPrompt(
            session: session,
            feedback: trimmed,
            filePath: filePath,
            lineNumber: lineNumber,
            lang: resolvedLanguage
        )
        let targetConvId = session.conversationId
            ?? createConversation(for: session.botId, title: "Fix: \(session.taskTitle)", activate: false).id
        await sendPersonalMessage(
            prompt,
            conversationId: targetConvId,
            personaId: session.botId,
            activateTargetConversation: false
        )
        _ = refreshWorktreeDiff(sessionId: sessionId)
    }

    public func mergeWorktreeSession(
        sessionId: String,
        strategy: PipiWorktreeMergeStrategy = .squash,
        commitMessage: String? = nil
    ) -> (succeeded: Bool, message: String) {
        guard let idx = worktreeSessions.firstIndex(where: { $0.id == sessionId }) else {
            return (false, "Worktree session not found.")
        }
        do {
            let msg = try PipiWorktreeManager.mergeAndCleanup(
                session: worktreeSessions[idx],
                strategy: strategy,
                commitMessage: commitMessage
            )
            worktreeSessions[idx].status = .merged
            worktreeSessions[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
            noticeBanner = "✅ \(msg)"
            return (true, msg)
        } catch {
            let errMsg = error.localizedDescription
            noticeBanner = "⚠️ \(errMsg)"
            return (false, errMsg)
        }
    }

    public func discardWorktreeSession(sessionId: String) {
        guard let idx = worktreeSessions.firstIndex(where: { $0.id == sessionId }) else { return }
        try? PipiWorktreeManager.discardAndCleanup(session: worktreeSessions[idx])
        worktreeSessions[idx].status = .discarded
        worktreeSessions[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
    }

    // MARK: 5. Token & Cost Metering (Alert-Only, Non-Blocking)

    public var usageSummary: PipiUsageSummary {
        PipiUsageMeteringEngine.summarize(records: usageRecords)
    }

    public var unacknowledgedUsageAlerts: [PipiUsageAlertNotice] {
        usageAlertNotices.filter { !$0.acknowledged }
    }

    public func acknowledgeUsageAlert(id: String) {
        if let idx = usageAlertNotices.firstIndex(where: { $0.id == id }) {
            usageAlertNotices[idx].acknowledged = true
        }
    }

    public func recordLLMUsage(
        persona: PipiBotPersona,
        conversationId: String?,
        taskTitle: String,
        config: PipiLLMProviderConfig,
        promptTokens: Int?,
        completionTokens: Int?,
        cachedTokens: Int = 0,
        fallbackPromptText: String = "",
        fallbackCompletionText: String = ""
    ) {
        let rec = PipiUsageMeteringEngine.makeRecord(
            botId: persona.id,
            botName: persona.name(resolvedLanguage),
            hostId: persona.hostId,
            conversationId: conversationId,
            taskTitle: taskTitle,
            modelId: config.modelId,
            providerKind: config.kind.rawValue,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            cachedTokens: cachedTokens,
            fallbackPromptText: fallbackPromptText,
            fallbackCompletionText: fallbackCompletionText
        )
        usageRecords.append(rec)
        if usageRecords.count > 1500 {
            usageRecords = Array(usageRecords.suffix(1500))
        }
        PipiUsageMeteringEngine.saveLedger(usageRecords)

        // Alert-only gentle notices — never pauses or interrupts tasks
        let newAlerts = PipiUsageMeteringEngine.evaluateAlerts(
            latestRecord: rec,
            allRecords: usageRecords,
            config: usageAlertConfig,
            existingAlerts: usageAlertNotices
        )
        if !newAlerts.isEmpty {
            usageAlertNotices.insert(contentsOf: newAlerts, at: 0)
            if let first = newAlerts.first {
                noticeBanner = first.message(resolvedLanguage)
            }
        }
    }
}
