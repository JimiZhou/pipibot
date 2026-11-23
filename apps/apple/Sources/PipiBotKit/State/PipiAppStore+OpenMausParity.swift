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

    private func isAuthorizedRemotePeer(rawToken: String, requiredAction: String) async -> Bool {
        if e2eeRelayClient.pairingRegistry.authorize(rawToken: rawToken, requiredAction: requiredAction) != nil {
            return true
        }
        return await accountClient.verifyPeerAccountToken(rawToken)
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
            guard await isAuthorizedRemotePeer(rawToken: rawToken, requiredAction: "read") else {
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
            guard await isAuthorizedRemotePeer(rawToken: rawToken, requiredAction: "read") else {
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
            guard await isAuthorizedRemotePeer(rawToken: rawToken, requiredAction: "read") else {
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

            // Hard bounded MCP enforcement: privileged actions require `.owner` scope or verified same-account session
            guard await isAuthorizedRemotePeer(rawToken: rawToken, requiredAction: action) else {
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

    // MARK: 8. Unified Account Auto-Relay & Direct Multi-Harness Orchestration

    /// Synchronizes account profile, registers this Mac in the unified Device Registry,
    /// and automatically connects the free E2EE relay (`pipibot.jimizhou.com`) so mobile/web can connect anytime.
    public func syncAccountAndAutoConnectRelay() async {
        await accountClient.refreshProfile()
        guard accountClient.isSignedIn, let token = accountClient.accessToken else { return }

        let installedCapabilities: [String] = ["PiPi"] + usableLocalAgents.map(\.kind.displayName)
        let hostName = localHost.displayName(resolvedLanguage)
        e2eeRelayClient.accountAccessToken = token
        e2eeRelayClient.accountDeviceName = hostName
        e2eeRelayClient.accountCapabilities = installedCapabilities
        e2eeRelayClient.accountWorkspacePath = workspaceDirectory

        if e2eeRelayClient.state == .disabled || e2eeRelayClient.state == .error {
            _ = startUniversalE2EERelay(relayOrigin: accountClient.relayOrigin)
        }

        await accountClient.registerCurrentHost(
            name: hostName,
            hostId: e2eeRelayClient.hostId,
            hostPubKey: e2eeRelayClient.hostPublicKeyB64Url,
            capabilities: installedCapabilities,
            workspacePath: workspaceDirectory
        )
    }

    /// Materializes direct first-class Agent Harness members (Claude Code, Codex, OpenCode, Pi)
    /// without requiring users to design custom personas.
    @discardableResult
    public func ensureDirectHarnessMembers() -> [PipiBotPersona] {
        let specs: [(id: String, name: String, roleZh: String, roleEn: String, target: PipiExecutionTarget, accent: PipiPersonaAccent)] = [
            ("harness_claude_code", "Claude Code", "直连 Claude Code 执行引擎", "Direct Claude Code Harness", .localAgent(.claudeCode), .coral),
            ("harness_codex", "Codex", "直连 OpenAI Codex 执行引擎", "Direct OpenAI Codex Harness", .localAgent(.codex), .sky),
            ("harness_opencode", "OpenCode", "直连 OpenCode 执行引擎", "Direct OpenCode Harness", .localAgent(.opencode), .iris),
            ("harness_pi", "Pi", "直连 PiPi 内置 Pi 引擎", "Direct Pi Core Harness", .auto, .emerald)
        ]

        var result: [PipiBotPersona] = []
        var mutated = false
        for spec in specs {
            if let existing = personas.first(where: { $0.id == spec.id }) {
                result.append(existing)
                continue
            }
            let directMember = PipiBotPersona(
                id: spec.id,
                nameZh: spec.name,
                nameEn: spec.name,
                roleZh: spec.roleZh,
                roleEn: spec.roleEn,
                greetingZh: "已直连 \(spec.name) Harness，直接发任务即可开始执行。",
                greetingEn: "Connected directly to \(spec.name) harness. Send any task to run.",
                systemPrompt: "You are the direct \(spec.name) execution harness inside a multi-harness orchestration workspace. Be concise, concrete, and collaborate directly with sibling harnesses.",
                accent: spec.accent,
                preferredTarget: spec.target,
                isBuiltIn: true
            )
            personas.append(directMember)
            result.append(directMember)
            mutated = true
        }
        if mutated {
            saveResidentState()
        }
        return result
    }

    /// One-click creates a Multi-Harness Orchestration Group (Claude Code + Codex + Pi, plus OpenCode if installed)
    /// so users can directly @mention and orchestrate multiple harnesses in parallel without custom personas.
    @discardableResult
    public func createMultiHarnessGroup(title: String? = nil) -> PipiGroupChat {
        let harnessMembers = ensureDirectHarnessMembers()
        let installedKinds = Set(usableLocalAgents.map(\.kind))
        var selectedIds: [String] = []
        if installedKinds.contains(.claudeCode) || selectedIds.isEmpty {
            selectedIds.append("harness_claude_code")
        }
        if installedKinds.contains(.codex) || selectedIds.count < 2 {
            selectedIds.append("harness_codex")
        }
        if installedKinds.contains(.opencode) {
            selectedIds.append("harness_opencode")
        }
        selectedIds.append("harness_pi")

        let validIds = selectedIds.filter { id in harnessMembers.contains(where: { $0.id == id }) }
        let finalTitle = title ?? (resolvedLanguage == .zhHans ? "多 Harness 协同（Claude / Codex / Pi）" : "Multi-Harness Swarm (Claude / Codex / Pi)")
        return createGroupChat(
            title: finalTitle,
            participantPersonaIds: validIds,
            leadPersonaId: validIds.last,
            swarmMode: .swarm
        )
    }

    // MARK: 9. Primary Control Plane -> Enrolled Remote Nodes & Remote Harnesses

    /// All other enrolled devices under the same unified account (excluding this local Mac host).
    public var enrolledRemoteDevices: [PipiAccountDevice] {
        let localHostId = e2eeRelayClient.hostId
        return accountClient.devices.filter { $0.hostId != localHostId }
    }

    public func resolveEnrolledRemoteDevice(query: String?) -> PipiAccountDevice? {
        let candidates = enrolledRemoteDevices
        let q = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return candidates.first(where: { $0.isOnline }) ?? candidates.first
        }
        return candidates.first(where: {
            $0.hostId.lowercased() == q ||
            $0.id.lowercased() == q ||
            $0.name.lowercased() == q ||
            $0.name.lowercased().contains(q) ||
            $0.hostId.lowercased().contains(q)
        })
    }

    public func invokeRemoteNodeRPC(
        device: PipiAccountDevice,
        method: String,
        path: String,
        body: [String: Any]? = nil,
        timeoutSeconds: TimeInterval = 30
    ) async -> PipiRemoteNodeRPCResult {
        guard let token = accountClient.accessToken, !token.isEmpty else {
            return PipiRemoteNodeRPCResult(ok: false, status: 401, rawText: "", errorMessage: "尚未登录 PiPiBot 统一账号，请先在「设置 → 远程访问」登录。")
        }
        let bodyData: Data? = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        return await PipiRemoteNodeClient.sendEncryptedRPC(
            relayOrigin: accountClient.relayOrigin,
            targetHostId: device.hostId,
            targetHostPubKey: device.hostPubKey,
            accountAccessToken: token,
            method: method,
            path: path,
            bodyJSONData: bodyData,
            timeoutSeconds: timeoutSeconds
        )
    }

    public func handleRemoteNodeTool(action: String, args: [String: String]) async -> String {
        await accountClient.refreshProfile()

        switch action {
        case "remote_nodes_list":
            let all = accountClient.devices
            if all.isEmpty {
                return "当前账号下暂无已纳管设备。请在目标机器运行 `pipibot login && pipibot up` 即可自动上线并上报本地 Agent Harness。"
            }
            let localId = e2eeRelayClient.hostId
            let lines = all.map { dev -> String in
                let selfTag = dev.hostId == localId ? "（本机主控）" : ""
                let state = dev.isOnline ? "🟢 在线" : "⚪ 离线"
                let caps = dev.capabilities.isEmpty ? "未上报 Harness" : dev.capabilities.joined(separator: ", ")
                let ws = dev.workspacePath.map { " | 目录: \($0)" } ?? ""
                return "• \(state) \(dev.name)\(selfTag) [\(dev.platform)] · hostId=`\(dev.hostId)` · Harness: [\(caps)]\(ws)"
            }
            return "已纳管设备（共 \(all.count) 台）：\n" + lines.joined(separator: "\n")

        case "remote_node_inspect":
            guard let dev = resolveEnrolledRemoteDevice(query: args["device"]) else {
                return "未找到匹配的远程纳管节点。可先调用 `remote_nodes_list` 查看所有在线设备。"
            }
            let res = await invokeRemoteNodeRPC(device: dev, method: "GET", path: "/api/system/info", timeoutSeconds: 18)
            if !res.ok {
                return "连接节点「\(dev.name)」失败：\(res.errorMessage ?? "HTTP \(res.status)")"
            }
            return "🔍 节点「\(dev.name)」(\(dev.platform), hostId=`\(dev.hostId)`) 实时状态：\n```json\n\(res.rawText)\n```"

        case "remote_node_run_harness":
            guard let dev = resolveEnrolledRemoteDevice(query: args["device"]) else {
                return "未找到目标远程节点（\(args["device"] ?? "未指定")）。请先调用 `remote_nodes_list` 确认设备名称或 hostId。"
            }
            let prompt = (args["prompt"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { return "调用远程节点 Harness 需要提供 prompt。" }
            var reqBody: [String: Any] = [
                "prompt": prompt,
                "waitMs": 20_000
            ]
            if let agent = args["agent"], !agent.isEmpty {
                reqBody["agent"] = agent
            }
            if let cwd = args["cwd"], !cwd.isEmpty {
                reqBody["cwd"] = cwd
            }
            let res = await invokeRemoteNodeRPC(
                device: dev,
                method: "POST",
                path: "/api/agents/run",
                body: reqBody,
                timeoutSeconds: 30
            )
            if !res.ok {
                return "在节点「\(dev.name)」启动远程 Harness 失败：\(res.errorMessage ?? "HTTP \(res.status)")"
            }
            if let session = res.body["session"] as? [String: Any] {
                let sid = (session["id"] as? String) ?? "-"
                let agentName = (session["agent"] as? String) ?? (args["agent"] ?? "Agent")
                let status = (session["status"] as? String) ?? "running"
                let lines = (session["outputLines"] as? [String]) ?? []
                let outputPreview = lines.suffix(40).joined(separator: "\n")
                return "🤖 已在远程节点「\(dev.name)」通过 \(agentName) 执行（会话 `\(sid)` · 状态: \(status)）：\n```\n\(outputPreview)\n```"
            }
            return "🤖 已在远程节点「\(dev.name)」派发任务：\n```json\n\(res.rawText)\n```"

        case "remote_node_exec":
            guard let dev = resolveEnrolledRemoteDevice(query: args["device"]) else {
                return "未找到目标远程节点（\(args["device"] ?? "未指定")）。"
            }
            let op = (args["operation"] ?? "exec").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if op == "list_files" {
                var body: [String: Any] = [:]
                if let path = args["path"], !path.isEmpty { body["path"] = path }
                let res = await invokeRemoteNodeRPC(device: dev, method: "POST", path: "/api/files/list", body: body, timeoutSeconds: 18)
                guard res.ok else { return "列出节点「\(dev.name)」目录失败：\(res.errorMessage ?? "HTTP \(res.status)")" }
                return "📂 远程节点「\(dev.name)」目录列表：\n```json\n\(res.rawText)\n```"
            }
            if op == "read_file" {
                guard let path = args["path"], !path.isEmpty else { return "读取远程文件需要提供 path。" }
                let res = await invokeRemoteNodeRPC(device: dev, method: "POST", path: "/api/files/read", body: ["path": path], timeoutSeconds: 18)
                guard res.ok else { return "读取节点「\(dev.name)」文件失败：\(res.errorMessage ?? "HTTP \(res.status)")" }
                let content = (res.body["content"] as? String) ?? res.rawText
                return "📄 远程节点「\(dev.name)」文件 `\(path)`：\n```\n\(content)\n```"
            }
            let cmd = (args["command"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cmd.isEmpty else { return "执行远程命令需要提供 command。" }
            var body: [String: Any] = ["command": cmd, "timeoutMs": 20_000]
            if let cwd = args["cwd"], !cwd.isEmpty { body["cwd"] = cwd }
            let res = await invokeRemoteNodeRPC(device: dev, method: "POST", path: "/api/shell/exec", body: body, timeoutSeconds: 28)
            guard res.ok else { return "在节点「\(dev.name)」执行命令失败：\(res.errorMessage ?? "HTTP \(res.status)")" }
            let exitCode = (res.body["exitCode"] as? Int) ?? 0
            let stdout = (res.body["stdout"] as? String) ?? ""
            let stderr = (res.body["stderr"] as? String) ?? ""
            let cwd = (res.body["cwd"] as? String) ?? ""
            var out = "🛠️ 远程节点「\(dev.name)」(`\(cwd)`) 执行完毕 (exit=\(exitCode))："
            if !stdout.isEmpty { out += "\n```\n\(stdout)\n```" }
            if !stderr.isEmpty { out += "\nstderr:\n```\n\(stderr)\n```" }
            return out

        default:
            return "未知远程节点操作：\(action)"
        }
    }

    public func fetchRemoteNodeTelemetry(device: PipiAccountDevice) async -> PipiRemoteNodeLiveTelemetry? {
        guard device.isOnline else { return nil }
        let res = await invokeRemoteNodeRPC(device: device, method: "GET", path: "/api/system/info", timeoutSeconds: 12)
        guard res.ok else { return nil }
        let b = res.body
        let agentList = (b["installedAgents"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? device.capabilities
        return PipiRemoteNodeLiveTelemetry(
            hostId: device.hostId,
            hostname: (b["hostname"] as? String) ?? device.name,
            platform: (b["platform"] as? String) ?? device.platform,
            arch: (b["arch"] as? String) ?? "unknown",
            cpuCount: (b["cpuCount"] as? Int) ?? 0,
            totalMemoryMB: (b["totalMemoryMB"] as? Int) ?? 0,
            freeMemoryMB: (b["freeMemoryMB"] as? Int) ?? 0,
            uptimeSeconds: (b["uptimeSeconds"] as? Int) ?? 0,
            workspacePath: (b["workspacePath"] as? String) ?? (device.workspacePath ?? ""),
            gitBranch: b["gitBranch"] as? String,
            gitDirtyCount: b["gitDirtyCount"] as? Int,
            activeSessions: (b["activeSessions"] as? Int) ?? 0,
            installedAgentNames: agentList,
            refreshedAt: Date()
        )
    }

    public struct PipiRemoteHarnessDescriptor: Identifiable, Sendable, Equatable {
        public let id: String
        public let name: String
        public let defaultModel: String
        public let models: [String]
        public let configSource: String?
    }

    public func fetchRemoteNodeHarnesses(device: PipiAccountDevice) async -> [PipiRemoteHarnessDescriptor] {
        guard device.isOnline else { return [] }
        let res = await invokeRemoteNodeRPC(device: device, method: "GET", path: "/api/agents", timeoutSeconds: 12)
        guard res.ok, let list = res.body["installedAgents"] as? [[String: Any]] else {
            return device.capabilities.map {
                PipiRemoteHarnessDescriptor(id: $0, name: $0, defaultModel: "", models: [], configSource: nil)
            }
        }
        return list.compactMap { item in
            guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
            let defaultModel = (item["defaultModel"] as? String) ?? ""
            let models = (item["models"] as? [String]) ?? (defaultModel.isEmpty ? [] : [defaultModel])
            let source = item["configSource"] as? String
            return PipiRemoteHarnessDescriptor(id: id, name: name, defaultModel: defaultModel, models: models, configSource: source)
        }
    }

    /// Directly dispatches a user prompt from the Mac chat composer to a chosen enrolled remote node's Agent Harness over E2EE.
    public func sendDirectToRemoteNode(
        device: PipiAccountDevice,
        harness: String?,
        model: String? = nil,
        mode: String = "acp",
        prompt: String
    ) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let convId: String
        if let active = activeConversationId, conversations.contains(where: { $0.id == active }) {
            convId = active
        } else {
            let created = createConversation(projectId: activeConversation?.projectId)
            convId = created.id
        }

        let targetHarness = (harness?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? harness!
            : (device.capabilities.first ?? "claude-code")
        let cleanModel = (model ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let modelTag = cleanModel.isEmpty || cleanModel.hasPrefix("(") ? "" : " · \(cleanModel)"

        if let idx = conversations.firstIndex(where: { $0.id == convId }) {
            conversations[idx].messages.append(
                PipiChatMessage(role: .user, content: "[\(device.name) · \(targetHarness)\(modelTag)] \(trimmed)")
            )
            let placeholderId = UUID().uuidString
            conversations[idx].messages.append(
                PipiChatMessage(
                    id: placeholderId,
                    role: .assistant,
                    content: "⚡ 正在通过端到端加密通道调度节点「\(device.name)」上的 \(targetHarness)\(modelTag) 执行…",
                    engineLabel: "\(device.name) · \(targetHarness)"
                )
            )
            conversations[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
            saveResidentState()

            var rpcBody: [String: Any] = [
                "agent": targetHarness,
                "prompt": trimmed,
                "mode": mode,
                "waitMs": 24_000
            ]
            if !cleanModel.isEmpty && !cleanModel.hasPrefix("(") {
                rpcBody["model"] = cleanModel
            }

            let res = await invokeRemoteNodeRPC(
                device: device,
                method: "POST",
                path: "/api/agents/run",
                body: rpcBody,
                timeoutSeconds: 32
            )

            let replyText: String
            if res.ok, let sess = res.body["session"] as? [String: Any] {
                let lines = (sess["outputLines"] as? [String]) ?? []
                let bodyLines = lines.dropFirst()
                let status = (sess["status"] as? String) ?? "exited"
                let sid = (sess["id"] as? String) ?? "-"
                if bodyLines.isEmpty {
                    replyText = "✅ 已在「\(device.name)」启动 \(targetHarness)（会话 `\(sid)` · 状态：\(status)）。"
                } else {
                    replyText = bodyLines.joined(separator: "\n")
                }
            } else {
                replyText = "❌ 调度远程节点「\(device.name)」失败：\(res.errorMessage ?? "HTTP \(res.status)")"
            }

            if let cIdx = conversations.firstIndex(where: { $0.id == convId }),
               let mIdx = conversations[cIdx].messages.firstIndex(where: { $0.id == placeholderId }) {
                conversations[cIdx].messages[mIdx].content = replyText
                conversations[cIdx].updatedAt = ISO8601DateFormatter().string(from: Date())
                saveResidentState()
            }
        }
    }

    private static func jsonBytes(_ obj: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
    }
}
