// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// v0.15.0 AppStore Integration:
// - Universal E2EE Relay (`https://pipibot.jimizhou.com/c/<hostId>#t=...&k=...`) & Device Pairing
// - Three-Tier Fast Group Auto-Routing (Decision Model)
// - Portable Redacted Team / Bot Templates (`bot.md` / `team.md`)
// - Sentinel Zero-LLM Health Scanner -> Self-Evolution Proposal Closure
// - Bot Self-Service Trigger Tool (Write-Only Webhook Secret)
// - Layered Bot Box Self-Check & Custom ACP Engine Registry

import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
extension PipiAppStore {

    // MARK: 1. System Sleep/Wake Auto-Recovery (WeChat iLink + E2EE Relay)

    internal func installSystemWakeRecoveryObserver() {
        #if os(macOS)
        guard systemWakeObserver == nil else { return }
        systemWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.wechatAutoConnectEnabled && self.wechatILinkManager.hasSavedCredentials {
                    self.wechatILinkManager.handleSystemWake(bridge: self.makeWeChatMessageBridge())
                }
                self.e2eeRelayClient.handleSystemWake()
            }
        }
        #endif
    }

    // MARK: 2. Universal E2EE Relay & Device Pairing (`pipibot.jimizhou.com/c/...`)

    @discardableResult
    public func startUniversalE2EERelay(
        relayOrigin: String = PipiE2EERelayClient.defaultRelayOrigin,
        inviteKey: String? = nil
    ) -> PipiUniversalPairingLink {
        e2eeRelayClient.start(relayOrigin: relayOrigin, inviteKey: inviteKey) { [weak self] method, path, token, body in
            guard let self else {
                return Data("{\"error\":\"host_unavailable\"}".utf8)
            }
            return await self.handleUniversalMobileAPI(method: method, path: path, token: token, body: body)
        }
        return generateUniversalPairingLink(scope: .owner)
    }

    public func stopUniversalE2EERelay() {
        e2eeRelayClient.stop()
    }

    @discardableResult
    public func generateUniversalPairingLink(
        scope: PipiPairingScope = .owner,
        lanHintURL: String? = nil
    ) -> PipiUniversalPairingLink {
        let link = e2eeRelayClient.generateUniversalPairingLink(
            scope: scope,
            lanHintURL: lanHintURL
        )
        lastUniversalPairingURL = link.urlString
        return link
    }

    public func listPairedDevices() -> [PipiPairedDevice] {
        e2eeRelayClient.pairingRegistry.listDevices()
    }

    @discardableResult
    public func revokePairedDevice(id: String) -> Bool {
        e2eeRelayClient.pairingRegistry.revokeDevice(id: id)
    }

    private static var localHostDisplayName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "PiPiBot Mac"
        #else
        return ProcessInfo.processInfo.hostName.isEmpty ? "PiPiBot iOS" : ProcessInfo.processInfo.hostName
        #endif
    }

    /// Unified encrypted request router shared by E2EE Relay (`pipibot.jimizhou.com`), local PWA, and future iOS App.
    public func handleUniversalMobileAPI(
        method: String,
        path: String,
        token: String?,
        body: Data?
    ) async -> Data {
        let cleanPath = path.split(separator: "?").first.map(String.init) ?? path

        if method == "POST" && cleanPath == "/api/v1/auth/pair" {
            let obj = body.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
            let code = (obj["code"] as? String) ?? ""
            let label = (obj["label"] as? String) ?? "Remote Device"
            let pubKey = obj["clientPublicKey"] as? String
            guard let redeemed = e2eeRelayClient.pairingRegistry.redeemChallenge(
                code: code,
                label: label,
                clientPublicKeyB64: pubKey
            ) else {
                return Self.jsonBytes(["error": "invalid_or_expired_pairing_code"])
            }
            return Self.jsonBytes([
                "ok": true,
                "token": redeemed.rawToken,
                "deviceId": redeemed.device.id,
                "scope": redeemed.device.scope.rawValue,
                "hostName": Self.localHostDisplayName
            ])
        }

        guard let rawToken = token, !rawToken.isEmpty else {
            return Self.jsonBytes(["error": "unauthorized"])
        }

        if method == "GET" && cleanPath == "/api/v1/auth/devices" {
            guard e2eeRelayClient.pairingRegistry.authorize(rawToken: rawToken, requiredAction: "read") != nil else {
                return Self.jsonBytes(["error": "unauthorized"])
            }
            let list = listPairedDevices().map { d in
                [
                    "id": d.id,
                    "label": d.label,
                    "scope": d.scope.rawValue,
                    "revoked": d.revoked
                ] as [String: Any]
            }
            return Self.jsonBytes(["devices": list])
        }

        if method == "GET" && cleanPath == "/api/v1/mobile/snapshot" {
            guard e2eeRelayClient.pairingRegistry.authorize(rawToken: rawToken, requiredAction: "read") != nil else {
                return Self.jsonBytes(["error": "unauthorized"])
            }
            let activeConv = activeConversation ?? conversations.first
            let messages = (activeConv?.messages.suffix(40) ?? []).map { m in
                [
                    "id": m.id,
                    "role": m.role == .user ? "user" : "assistant",
                    "author": m.engineLabel ?? activePersona.name(resolvedLanguage),
                    "content": m.content
                ] as [String: Any]
            }
            let bots = personas.map { p in
                [
                    "id": p.id,
                    "name": p.name(resolvedLanguage),
                    "role": p.role(resolvedLanguage),
                    "isolation": p.executionIsolation.rawValue
                ] as [String: Any]
            }
            let pendingApprovals = decisions.filter { $0.status == .pending }.map { d in
                ["id": d.id, "title": d.title, "summary": d.summary] as [String: Any]
            }
            let pendingDrafts = loopDrafts.filter { $0.status == .pendingGate }.map { d in
                ["id": d.id, "draftContent": d.draftContent] as [String: Any]
            }
            let pendingEvos = blueprintEvolutionProposals.filter { $0.status == .pending }.map { e in
                ["id": e.id, "rationale": e.rationale, "proposedRule": e.goalSummary] as [String: Any]
            }
            let wts = worktreeSessions.filter { $0.status == .readyForReview }.map { w in
                [
                    "id": w.id,
                    "branchName": w.branchName,
                    "summary": w.diffSummary,
                    "diffText": w.unifiedDiff,
                    "proofScore": proofBundlesByWorktreeId[w.id]?.proofScore ?? 0
                ] as [String: Any]
            }
            let sentinel = sentinelIssues.prefix(10).map { it in
                [
                    "signature": it.signature,
                    "severity": it.severity.rawValue,
                    "normalizedTitle": it.normalizedTitle,
                    "count": it.count
                ] as [String: Any]
            }
            let trigs = routines.map { r in
                ["id": r.id, "title": r.title, "enabled": r.isEnabled, "kind": r.triggerKind.rawValue] as [String: Any]
            }
            let summary = PipiUsageMeteringEngine.summarize(records: usageRecords)
            return Self.jsonBytes([
                "hostName": Self.localHostDisplayName,
                "messages": messages,
                "bots": bots,
                "approvals": pendingApprovals,
                "draftGates": pendingDrafts,
                "evolutions": pendingEvos,
                "worktrees": wts,
                "sentinelIssues": sentinel,
                "triggers": trigs,
                "usageSummary": [
                    "todayTokens": summary.todayTokens,
                    "todayCostUSD": summary.todayCostUSD
                ]
            ])
        }

        if method == "POST" && cleanPath == "/api/v1/mobile/chat" {
            guard e2eeRelayClient.pairingRegistry.authorize(rawToken: rawToken, requiredAction: "read") != nil else {
                return Self.jsonBytes(["error": "unauthorized"])
            }
            let obj = body.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
            let text = ((obj["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return Self.jsonBytes(["error": "empty_message"]) }
            Task { @MainActor in
                await self.sendPersonalMessage(text)
            }
            return Self.jsonBytes(["ok": true, "queued": true])
        }

        if method == "POST" && cleanPath == "/api/v1/mobile/action" {
            let obj = body.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
            let action = (obj["action"] as? String) ?? ""
            let itemId = (obj["id"] as? String) ?? ""

            // Hard bounded MCP enforcement: privileged actions require `.owner` scope
            guard e2eeRelayClient.pairingRegistry.authorize(rawToken: rawToken, requiredAction: action) != nil else {
                return Self.jsonBytes(["error": "forbidden_bounded_scope"])
            }

            switch action {
            case "approve":
                await resolveDecision(itemId, optionId: "approve")
            case "deny":
                await resolveDecision(itemId, optionId: "reject")
            case "draft-approve":
                approveLoopDraft(id: itemId)
            case "draft-reject":
                discardLoopDraft(id: itemId)
            case "evo-approve":
                approveBlueprintEvolutionProposal(id: itemId)
            case "evo-reject":
                rejectBlueprintEvolutionProposal(id: itemId, note: "Rejected from Mobile PWA")
            case "worktree-merge":
                _ = mergeWorktreeSession(sessionId: itemId)
            case "worktree-discard":
                discardWorktreeSession(sessionId: itemId)
            default:
                return Self.jsonBytes(["error": "unknown_action"])
            }
            return Self.jsonBytes(["ok": true, "action": action, "id": itemId])
        }

        return Self.jsonBytes(["error": "not_found"])
    }

    // MARK: 3. Three-Tier Fast Group Auto-Routing

    public func autoRouteGroupMessage(
        groupId: String,
        text: String,
        executor: PipiDecisionModelHTTPExecutor? = nil
    ) async -> PipiGroupRouteDecision {
        guard let group = groupChats.first(where: { $0.id == groupId }) else {
            return PipiGroupRouteDecision(tier: .leadFallback, picks: [], latencyMs: 0, note: "Group not found")
        }
        let members = personas.filter { group.participantPersonaIds.contains($0.id) }
        let candidates = members.map { p in
            PipiGroupRouterCandidate(
                id: p.id,
                name: p.name(resolvedLanguage),
                roleTitle: p.role(resolvedLanguage),
                keywords: p.assignedSkillSlugs
            )
        }
        let leadId = group.leadPersonaId ?? group.participantPersonaIds.first ?? activePersona.id
        let apiKey = secretStore.secret(for: decisionModelConfig.secretAccountKey)
        let decision = await PipiGroupAutoRouter.route(
            message: text,
            candidates: candidates,
            leadBotId: leadId,
            config: decisionModelConfig,
            apiKey: apiKey,
            executor: executor
        )
        lastGroupRouteDecision = decision
        return decision
    }

    // MARK: 4. Portable Redacted Team / Bot Templates (`bot.md` / `team.md`)

    public func exportTeamAsPortableMarkdown(
        personaIds: [String]? = nil,
        name: String? = nil,
        tagline: String? = nil
    ) -> (markdown: String, package: PipiPortableTemplatePackage) {
        let selectedBots: [PipiBotPersona]
        if let ids = personaIds, !ids.isEmpty {
            selectedBots = personas.filter { ids.contains($0.id) }
        } else {
            selectedBots = [activePersona]
        }
        let botIdSet = Set(selectedBots.map(\.id))
        let relatedRoutines = routines.filter { botIdSet.contains($0.personaId) }
        let relatedSkills = ecosystemManager.installedSkills.filter { $0.enabled }
        return PipiPortableTemplateEngine.exportToMarkdown(
            name: name ?? (selectedBots.count > 1 ? "PiPiBot Team" : (selectedBots.first?.name(resolvedLanguage) ?? "PiPiBot")),
            tagline: tagline ?? "Portable clean-room PiPiBot template",
            bots: selectedBots,
            skills: relatedSkills,
            routines: relatedRoutines
        )
    }

    public func previewPortableTemplate(markdown: String, sourceDescription: String = "Local Markdown") -> PipiPortableTemplatePackage {
        let pkg = PipiPortableTemplateEngine.parseMarkdown(markdown, sourceDescription: sourceDescription)
        pendingPortableTemplatePreview = pkg
        return pkg
    }

    @discardableResult
    public func applyPortableTemplate(_ package: PipiPortableTemplatePackage) -> [PipiBotPersona] {
        var created: [PipiBotPersona] = []
        var slugToBotId: [String: String] = [:]

        for spec in package.bots {
            let newBot = PipiBotPersona(
                nameZh: spec.name,
                nameEn: spec.name,
                roleZh: spec.roleTitle,
                roleEn: spec.roleTitle,
                greetingZh: "你好，我是已导入的「\(spec.name)」（默认运行于 Bot Box 隔离模式）。",
                greetingEn: "Hi, I'm imported '\(spec.name)' (running in Bot Box isolation by default).",
                systemPrompt: spec.instructionsMarkdown.isEmpty ? "You are \(spec.name), \(spec.roleTitle)." : spec.instructionsMarkdown,
                assignedSkillSlugs: spec.skillNames,
                automationBlueprint: spec.automationBlueprint,
                executionIsolation: .sandboxBox
            )
            personas.append(newBot)
            slugToBotId[spec.slug] = newBot.id
            created.append(newBot)
        }

        for r in package.routines {
            let targetBotId = slugToBotId[r.botSlug] ?? created.first?.id ?? activePersona.id
            var evCfg = PipiRoutineEventConfig()
            evCfg.cronExpression = r.cronExpression
            let routine = PipiBotRoutine(
                personaId: targetBotId,
                title: r.title,
                prompt: r.prompt,
                triggerKind: r.triggerKind,
                eventConfig: evCfg,
                isEnabled: false // Security invariant: imported routines always arrive paused
            )
            routines.append(routine)
        }

        pendingPortableTemplatePreview = nil
        saveResidentState()
        return created
    }

    // MARK: 5. Sentinel Zero-LLM Health Scanner -> Self-Evolution Closure

    @discardableResult
    public func runSentinelHealthScan(
        extraSamples: [PipiSentinelEventSample] = [],
        recurrenceThreshold: Int = 3
    ) -> PipiSentinelReport {
        var samples = extraSamples
        for outcome in runOutcomeRecords where !outcome.succeeded {
            samples.append(PipiSentinelEventSample(
                id: outcome.id,
                kind: .routineFailure,
                toolName: outcome.routineId,
                botId: outcome.botId,
                rawMessage: outcome.verificationNotes.isEmpty ? outcome.taskTitle : outcome.verificationNotes
            ))
        }
        for usage in usageRecords where usage.estimatedCostUSD >= 2.0 {
            samples.append(PipiSentinelEventSample(
                id: usage.id,
                kind: .highCostTurn,
                toolName: usage.modelId,
                botId: usage.botId,
                rawMessage: "High cost turn on \(usage.modelId)",
                costUSD: usage.estimatedCostUSD
            ))
        }

        var merged = PipiSentinelHealthScanner.scan(
            samples: samples,
            existingIssues: sentinelIssues
        )
        let proposals = PipiSentinelHealthScanner.synthesizeEvolutionProposals(
            issues: &merged,
            recurrenceThreshold: recurrenceThreshold
        )
        sentinelIssues = merged
        for prop in proposals {
            if !blueprintEvolutionProposals.contains(where: { $0.id == prop.id }) {
                blueprintEvolutionProposals.insert(prop, at: 0)
            }
        }
        let report = PipiSentinelReport(
            scannedAt: Date(),
            issues: merged,
            promotedProposalsCount: proposals.count,
            skippedUnchanged: false
        )
        lastSentinelReport = report
        if !proposals.isEmpty {
            saveResidentState()
        }
        return report
    }

    // MARK: 6. Bot Self-Service Trigger Tool (Write-Only Webhook Secret)

    public func handleBotTriggerTool(action: String, args: [String: String], callerBotId: String) -> String {
        switch action {
        case "trigger_list":
            let filter = args["bot_query"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matching = routines.filter { r in
                guard let filter, !filter.isEmpty else { return true }
                return r.personaId.lowercased().contains(filter) || r.title.lowercased().contains(filter)
            }
            if matching.isEmpty {
                return "当前没有配置任何自动化触发器。"
            }
            // NEVER expose webhookSecret to the LLM
            return matching.map { r in
                let status = r.isEnabled ? "active" : "paused"
                let detail = r.triggerKind == .webhook ? "/api/v1/webhooks/\(r.id) (secret write-only)" : (r.eventConfig.cronExpression ?? r.eventConfig.watchPath ?? r.schedule.rawValue)
                return "• [\(r.id)] \(r.title) | \(r.triggerKind.rawValue) | \(status) | \(detail)"
            }.joined(separator: "\n")

        case "trigger_upsert":
            let title = (args["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let prompt = (args["prompt"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !prompt.isEmpty else {
                return "创建/更新触发器需要提供 title 与 prompt。"
            }
            let kind = PipiRoutineTriggerKind(rawValue: args["trigger_kind"] ?? "schedule") ?? .schedule
            let enabled = (args["enabled"]?.lowercased() != "false")
            let existingId = args["routine_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let existingId, !existingId.isEmpty, let idx = routines.firstIndex(where: { $0.id == existingId }) {
                routines[idx].title = title
                routines[idx].prompt = prompt
                routines[idx].triggerKind = kind
                routines[idx].isEnabled = enabled
                if let cron = args["cron"] { routines[idx].eventConfig.cronExpression = cron }
                if let watch = args["watch_path"] { routines[idx].eventConfig.watchPath = watch }
                saveResidentState()
                return "✅ 已更新触发器 `\(existingId)`（\(title)，状态：\(enabled ? "运行中" : "已暂停")）。"
            }

            var cfg = PipiRoutineEventConfig()
            cfg.cronExpression = args["cron"]
            cfg.watchPath = args["watch_path"]
            if kind == .webhook {
                // Generate secret on host; NEVER echo it back to the LLM!
                cfg.webhookSecret = "whsec_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
            }
            let routine = PipiBotRoutine(
                personaId: callerBotId,
                title: title,
                prompt: prompt,
                triggerKind: kind,
                eventConfig: cfg,
                isEnabled: enabled
            )
            routines.append(routine)
            saveResidentState()
            if kind == .webhook {
                return "✅ 已创建 Webhook 触发器 `\(routine.id)`（路径 `/api/v1/webhooks/\(routine.id)`）。出于安全隔离，Webhook 密钥不会返回给模型上下文，请前往 Mission Board 或手机 PWA 卡片中一次性复制完整密钥。"
            }
            return "✅ 已创建触发器 `\(routine.id)`（\(title)，类型：\(kind.rawValue)）。"

        case "trigger_delete":
            guard let rid = args["routine_id"]?.trimmingCharacters(in: .whitespacesAndNewlines), !rid.isEmpty else {
                return "请提供要删除的 routine_id。"
            }
            let before = routines.count
            routines.removeAll { $0.id == rid }
            if routines.count < before {
                saveResidentState()
                return "🗑️ 已删除触发器 `\(rid)`。"
            }
            return "未找到触发器 `\(rid)`。"

        default:
            return "不支持的触发器操作：\(action)"
        }
    }

    // MARK: 7. Bot Box Self-Check & Custom ACP Engines

    @discardableResult
    public func runBotBoxSelfCheck() -> PipiBoxSelfCheckResult {
        let res = PipiBotBoxSandbox.runSelfCheck()
        lastBoxSelfCheck = res
        return res
    }

    public func registerCustomACPEngine(_ engine: PipiCustomACPEngineConfig) {
        if let idx = customACPEngines.firstIndex(where: { $0.id == engine.id }) {
            customACPEngines[idx] = engine
        } else {
            customACPEngines.append(engine)
        }
        saveResidentState()
    }

    private static func jsonBytes(_ obj: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
    }
}
