// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
//
// Brigade AI Teammate Integration on PipiAppStore:
// - Stacked Paid Subscription Account Pool (Claude Pro/Max + ChatGPT Plus/Pro) with automatic failover
// - Teammate Org Chart (`reportsToBotId`), 24/7 Cloud Runtime Sync & Health Probe
// - Per-Teammate Persistent Isolated Browser Profile Handoff (LinkedIn / X / Reddit)

import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
extension PipiAppStore {

    // MARK: - 1. Stacked Subscription Account Pool

    public func subscriptionAccounts(for provider: PipiSubscriptionProviderKind) -> [PipiSubscriptionAccountRecord] {
        _ = PipiSubscriptionAccountPoolEngine.recoverExpiredCooldowns(in: &subscriptionAccounts)
        return subscriptionAccounts
            .filter { $0.provider == provider }
            .sorted { $0.priority < $1.priority || $0.createdAt < $1.createdAt }
    }

    public func availableSubscriptionCount(for provider: PipiSubscriptionProviderKind) -> Int {
        subscriptionAccounts(for: provider).filter { $0.status == .ready || $0.status == .active }.count
    }

    @discardableResult
    public func addSubscriptionAccount(
        provider: PipiSubscriptionProviderKind,
        label: String,
        planTier: String? = nil,
        emailHint: String? = nil,
        useSystemDefaultProfile: Bool = false,
        baseURL: String? = nil,
        modelId: String? = nil,
        apiKey: String = ""
    ) -> PipiSubscriptionAccountRecord {
        let sameCount = subscriptionAccounts.filter { $0.provider == provider }.count
        let id = "sub_\(provider.rawValue.prefix(8))_\(UUID().uuidString.prefix(8).lowercased())"
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "\(provider.displayName) #\(sameCount + 1)"
            : label.trimmingCharacters(in: .whitespacesAndNewlines)
        let profileDir = (provider.isOpenAICompatibleApiPool || useSystemDefaultProfile)
            ? nil
            : PipiSubscriptionAccountPoolEngine.defaultProfileDirectory(provider: provider, accountId: id)

        if let profileDir {
            try? FileManager.default.createDirectory(atPath: profileDir, withIntermediateDirectories: true)
        }

        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = PipiSubscriptionAccountRecord(
            id: id,
            label: cleanLabel,
            provider: provider,
            planTier: planTier,
            emailHint: emailHint,
            profileDir: profileDir,
            useSystemDefaultProfile: useSystemDefaultProfile,
            baseURL: baseURL,
            modelId: modelId,
            apiKey: cleanKey,
            priority: sameCount + 1
        )
        if !cleanKey.isEmpty {
            secretStore.setSecret(cleanKey, for: record.secretAccountKey)
        }
        subscriptionAccounts.append(record)
        saveResidentState()
        return record
    }

    public func hydrateSubscriptionAccountSecrets() {
        for idx in subscriptionAccounts.indices {
            if subscriptionAccounts[idx].provider.isOpenAICompatibleApiPool,
               subscriptionAccounts[idx].apiKey.isEmpty,
               let stored = secretStore.secret(for: subscriptionAccounts[idx].secretAccountKey),
               !stored.isEmpty {
                subscriptionAccounts[idx].apiKey = stored
            }
        }
    }

    public func removeSubscriptionAccount(id: String) {
        if let existing = subscriptionAccounts.first(where: { $0.id == id }) {
            secretStore.deleteSecret(for: existing.secretAccountKey)
        }
        subscriptionAccounts.removeAll { $0.id == id }
        for idx in personas.indices where personas[idx].subscriptionAccountId == id {
            personas[idx].subscriptionAccountId = nil
        }
        saveResidentState()
    }

    public static let poolProviderIdPrefix = "pool:"

    public func resolvedPooledLLMConfig(
        for provider: PipiSubscriptionProviderKind,
        persona: PipiBotPersona,
        excludeIds: Set<String> = []
    ) -> (account: PipiSubscriptionAccountRecord, config: PipiLLMProviderConfig)? {
        guard provider.isOpenAICompatibleApiPool else { return nil }
        let cursor = subscriptionRoundRobinCursors[provider] ?? 0
        guard let picked = PipiSubscriptionAccountPoolEngine.selectAccount(
            provider: provider,
            strategy: subscriptionPoolStrategy,
            accounts: subscriptionAccounts,
            preferredAccountId: excludeIds.isEmpty ? persona.subscriptionAccountId : nil,
            excludeIds: excludeIds,
            roundRobinCursor: cursor
        ) else {
            return nil
        }
        let account = picked.account
        let key = account.apiKey.isEmpty
            ? (secretStore.secret(for: account.secretAccountKey) ?? "")
            : account.apiKey
        let cfg = PipiSubscriptionAccountPoolEngine.buildLLMProviderConfig(
            from: account,
            modelOverride: persona.preferredModelId,
            apiKeyOverride: key
        )
        return (account, cfg)
    }

    /// Runs the Jarvis LLM tool loop backed by stacked Mainland China / third-party OpenAI-compatible
    /// accounts/keys, automatically rotating to the next key on 429 / 402 / quota / balance limits.
    public func runJarvisAgentLoopWithSubscriptionPool(
        provider: PipiSubscriptionProviderKind,
        systemPrompt: String,
        history: [PipiChatMessage],
        conversationId: String,
        persona: PipiBotPersona,
        workDir: String,
        runId: String,
        placeholderMessageId: String,
        onDelta: (@Sendable (String) -> Void)? = nil
    ) async throws -> PipiInferenceResult {
        var triedIds: Set<String> = []
        var lastError: Error? = nil

        while true {
            guard let resolved = resolvedPooledLLMConfig(for: provider, persona: persona, excludeIds: triedIds) else {
                if let lastError { throw lastError }
                throw PipiInferenceError.missingApiKey(provider.displayName)
            }

            let cursor = subscriptionRoundRobinCursors[provider] ?? 0
            subscriptionRoundRobinCursors[provider] = cursor + 1
            triedIds.insert(resolved.account.id)

            do {
                let res = try await runJarvisAgentLoop(
                    config: resolved.config,
                    systemPrompt: systemPrompt,
                    history: history,
                    conversationId: conversationId,
                    persona: persona,
                    workDir: workDir,
                    runId: runId,
                    placeholderMessageId: placeholderMessageId,
                    onDelta: onDelta
                )
                markSubscriptionAccountSuccess(
                    id: resolved.account.id,
                    tokens: (res.promptTokens ?? 0) + (res.completionTokens ?? 0)
                )
                return res
            } catch {
                let errText = error.localizedDescription
                let classified = PipiSubscriptionAccountPoolEngine.classifyError(errText)
                if classified.isRateLimited {
                    markSubscriptionAccountRateLimited(
                        id: resolved.account.id,
                        reason: classified.reason ?? errText,
                        cooldownSeconds: classified.cooldownSeconds
                    )
                    lastError = error
                    continue
                }
                if classified.isAuthExpired {
                    markSubscriptionAccountAuthExpired(id: resolved.account.id, reason: classified.reason ?? errText)
                    lastError = error
                    continue
                }
                throw error
            }
        }
    }

    public func setSubscriptionAccountEnabled(id: String, enabled: Bool) {
        guard let idx = subscriptionAccounts.firstIndex(where: { $0.id == id }) else { return }
        subscriptionAccounts[idx].status = enabled ? .ready : .disabled
        if enabled {
            subscriptionAccounts[idx].cooldownUntil = nil
            subscriptionAccounts[idx].rateLimitReason = nil
        }
        subscriptionAccounts[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
    }

    public func resetSubscriptionCooldown(accountId: String? = nil) {
        let nowIso = ISO8601DateFormatter().string(from: Date())
        for idx in subscriptionAccounts.indices {
            if let accountId, subscriptionAccounts[idx].id != accountId { continue }
            if subscriptionAccounts[idx].status == .rateLimited || subscriptionAccounts[idx].status == .authExpired {
                subscriptionAccounts[idx].status = .ready
                subscriptionAccounts[idx].cooldownUntil = nil
                subscriptionAccounts[idx].rateLimitReason = nil
                subscriptionAccounts[idx].updatedAt = nowIso
            }
        }
        saveResidentState()
    }

    public func setSubscriptionPoolStrategy(_ strategy: PipiSubscriptionPoolStrategy) {
        subscriptionPoolStrategy = strategy
        saveResidentState()
    }

    /// Invokes a local CLI agent (`claude` or `codex`) backed by stacked subscription accounts,
    /// automatically rotating to the next healthy account if a usage limit / 429 occurs mid-task.
    public func invokeLocalAgentWithSubscriptionPool(
        kind: PipiLocalAgentKind,
        persona: PipiBotPersona,
        systemPrompt: String,
        history: [PipiChatMessage],
        workingDirectory: String,
        permissionTier: PipiPermissionTier,
        cliSessionId: String?,
        modelOverride: String?,
        onDelta: (@Sendable (String) -> Void)? = nil,
        onEvent: (@Sendable (PipiParsedCLIEvent) -> Void)? = nil
    ) async throws -> PipiInferenceResult {
        let mappedProvider: PipiSubscriptionProviderKind? = {
            switch kind {
            case .claudeCode: return .claudeSubscription
            case .codex: return .chatgptSubscription
            case .opencode: return nil
            }
        }()

        guard let provider = mappedProvider,
              !subscriptionAccounts(for: provider).isEmpty else {
            return try await PipiInferenceEngine.invokeLocalAgent(
                kind: kind,
                systemPrompt: systemPrompt,
                history: history,
                workingDirectory: workingDirectory,
                permissionTier: permissionTier,
                cliSessionId: cliSessionId,
                modelOverride: modelOverride,
                onDelta: onDelta,
                onEvent: onEvent
            )
        }

        var triedIds: Set<String> = []
        var lastError: Error? = nil

        while true {
            let cursor = subscriptionRoundRobinCursors[provider] ?? 0
            guard let picked = PipiSubscriptionAccountPoolEngine.selectAccount(
                provider: provider,
                strategy: subscriptionPoolStrategy,
                accounts: subscriptionAccounts,
                preferredAccountId: triedIds.isEmpty ? persona.subscriptionAccountId : nil,
                excludeIds: triedIds,
                roundRobinCursor: cursor
            ) else {
                if let lastError { throw lastError }
                return try await PipiInferenceEngine.invokeLocalAgent(
                    kind: kind,
                    systemPrompt: systemPrompt,
                    history: history,
                    workingDirectory: workingDirectory,
                    permissionTier: permissionTier,
                    cliSessionId: cliSessionId,
                    modelOverride: modelOverride,
                    onDelta: onDelta,
                    onEvent: onEvent
                )
            }

            subscriptionRoundRobinCursors[provider] = picked.nextCursor
            let account = picked.account
            triedIds.insert(account.id)
            let env = PipiSubscriptionAccountPoolEngine.cliEnvironment(for: account)
            let effectiveSessionId = triedIds.count == 1 ? cliSessionId : nil

            do {
                let res = try await PipiInferenceEngine.invokeLocalAgent(
                    kind: kind,
                    systemPrompt: systemPrompt,
                    history: history,
                    workingDirectory: workingDirectory,
                    permissionTier: permissionTier,
                    cliSessionId: effectiveSessionId,
                    modelOverride: modelOverride ?? persona.preferredModelId,
                    extraEnvironment: env,
                    onDelta: onDelta,
                    onEvent: onEvent
                )
                markSubscriptionAccountSuccess(id: account.id, tokens: (res.promptTokens ?? 0) + (res.completionTokens ?? 0))
                let labeledEngine = "\(res.engineLabel) · \(account.label)"
                return PipiInferenceResult(
                    text: res.text,
                    engineLabel: labeledEngine,
                    cliSessionId: res.cliSessionId,
                    steps: res.steps,
                    planItems: res.planItems,
                    fileChanges: res.fileChanges,
                    summaryInfo: res.summaryInfo,
                    attachments: res.attachments,
                    promptTokens: res.promptTokens,
                    completionTokens: res.completionTokens,
                    cachedTokens: res.cachedTokens
                )
            } catch {
                let errText = error.localizedDescription
                let classified = PipiSubscriptionAccountPoolEngine.classifyError(errText)
                if classified.isRateLimited {
                    markSubscriptionAccountRateLimited(
                        id: account.id,
                        reason: classified.reason ?? errText,
                        cooldownSeconds: classified.cooldownSeconds
                    )
                    lastError = error
                    continue
                }
                if classified.isAuthExpired {
                    markSubscriptionAccountAuthExpired(id: account.id, reason: classified.reason ?? errText)
                    lastError = error
                    continue
                }
                throw error
            }
        }
    }

    private func markSubscriptionAccountSuccess(id: String, tokens: Int) {
        guard let idx = subscriptionAccounts.firstIndex(where: { $0.id == id }) else { return }
        let nowIso = ISO8601DateFormatter().string(from: Date())
        subscriptionAccounts[idx].status = .ready
        subscriptionAccounts[idx].cooldownUntil = nil
        subscriptionAccounts[idx].rateLimitReason = nil
        subscriptionAccounts[idx].requestsCount += 1
        subscriptionAccounts[idx].estimatedTokensUsed += max(0, tokens)
        subscriptionAccounts[idx].lastUsedAt = nowIso
        subscriptionAccounts[idx].updatedAt = nowIso
        saveResidentState()
    }

    private func markSubscriptionAccountRateLimited(id: String, reason: String, cooldownSeconds: TimeInterval) {
        guard let idx = subscriptionAccounts.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        let iso = ISO8601DateFormatter()
        subscriptionAccounts[idx].status = .rateLimited
        subscriptionAccounts[idx].cooldownUntil = iso.string(from: now.addingTimeInterval(cooldownSeconds))
        subscriptionAccounts[idx].rateLimitReason = String(reason.prefix(200))
        subscriptionAccounts[idx].failoverCount += 1
        subscriptionAccounts[idx].updatedAt = iso.string(from: now)
        lastBrigadeNotice = resolvedLanguage == .zhHans
            ? "账号「\(subscriptionAccounts[idx].label)」触发用量上限，已自动切换至账号池下一个可用订阅。"
            : "Account \"\(subscriptionAccounts[idx].label)\" hit its usage limit; automatically rotating to the next stacked subscription."
        saveResidentState()
    }

    private func markSubscriptionAccountAuthExpired(id: String, reason: String) {
        guard let idx = subscriptionAccounts.firstIndex(where: { $0.id == id }) else { return }
        subscriptionAccounts[idx].status = .authExpired
        subscriptionAccounts[idx].rateLimitReason = String(reason.prefix(200))
        subscriptionAccounts[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
        saveResidentState()
    }

    // MARK: - 2. Org Chart & Teammate Brigade Settings

    public func updateBotBrigadeSettings(
        personaId: String,
        runtimeMode: PipiTeammateRuntimeMode? = nil,
        reportsToBotId: String?? = nil,
        subscriptionProvider: PipiSubscriptionProviderKind?? = nil,
        subscriptionAccountId: String?? = nil,
        browserConfig: PipiTeammateBrowserConfig? = nil
    ) {
        guard let idx = personas.firstIndex(where: { $0.id == personaId }) else { return }
        if let runtimeMode { personas[idx].runtimeMode = runtimeMode }
        if let reportsToBotId {
            // Prevent self-reporting cycle
            personas[idx].reportsToBotId = (reportsToBotId == personaId) ? nil : reportsToBotId
        }
        if let subscriptionProvider {
            personas[idx].subscriptionProvider = subscriptionProvider
            if let sub = subscriptionProvider {
                if let mapped = sub.mappedLocalAgentKind {
                    personas[idx].preferredTarget = .localAgent(mapped)
                } else if sub.isOpenAICompatibleApiPool {
                    personas[idx].preferredTarget = .llm(providerId: "\(Self.poolProviderIdPrefix)\(sub.rawValue)")
                }
            }
        }
        if let subscriptionAccountId {
            personas[idx].subscriptionAccountId = subscriptionAccountId
        }
        if let browserConfig {
            personas[idx].browserConfig = browserConfig
            if browserConfig.enabled && !personas[idx].enabledTools.contains(PipiBotToolKind.browserSeat.rawValue) {
                personas[idx].enabledTools.append(PipiBotToolKind.browserSeat.rawValue)
            }
        }
        saveResidentState()
    }

    public func orgChartRoots() -> [PipiBotPersona] {
        let ids = Set(personas.map(\.id))
        return personas.filter { bot in
            guard let manager = bot.reportsToBotId, !manager.isEmpty else { return true }
            return manager == bot.id || !ids.contains(manager)
        }
    }

    public func orgChartChildren(of managerBotId: String) -> [PipiBotPersona] {
        personas.filter { $0.reportsToBotId == managerBotId && $0.id != managerBotId }
    }

    public var cloud24x7TeammatesCount: Int {
        personas.filter { $0.runtimeMode == .cloud24x7 || $0.runtimeMode == .hybridFailover }.count
    }

    public var isolatedBrowserTeammatesCount: Int {
        personas.filter { $0.browserConfig.enabled }.count
    }

    // MARK: - 3. Interactive Per-Teammate Browser Login Window (macOS)

    public func launchIsolatedBrowserLoginWindow(botId: String, platformSlug: String = "x") -> (ok: Bool, message: String) {
        #if os(macOS)
        guard let chromeBin = PipiBrowserCUADriver.detectChromeBinary() else {
            return (false, resolvedLanguage == .zhHans ? "未检测到 Chrome / Chromium 浏览器。" : "Chrome / Chromium not found.")
        }
        let profileDir = PipiSubscriptionAccountPoolEngine.defaultBrowserProfileDirectory(botId: botId)
        try? FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let targetURL = PipiTeammateBrowserConfig.platformLoginURL(platformSlug)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: chromeBin)
        proc.arguments = [
            "--user-data-dir=\(profileDir.path)",
            "--no-first-run",
            "--no-default-browser-check",
            targetURL
        ]
        do {
            try proc.run()
            return (
                true,
                resolvedLanguage == .zhHans
                    ? "已打开该队友的独立浏览器窗口（登录后 Cookie 将持久化保存，与其他队友完全隔离）。"
                    : "Opened this teammate's isolated browser window (cookies persist separately from other teammates)."
            )
        } catch {
            return (false, error.localizedDescription)
        }
        #else
        return (false, "Interactive browser login window is available on macOS or via Cloud Host.")
        #endif
    }

    // MARK: - 4. 24/7 Cloud Brigade Host Sync & Health Probe

    public func updateCloudBrigadeConfig(hostURL: String, hubToken: String, autoSync: Bool) {
        cloudBrigadeConfig.cloudHostURL = hostURL.trimmingCharacters(in: .whitespacesAndNewlines)
        cloudBrigadeConfig.cloudHubToken = hubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        cloudBrigadeConfig.autoSyncEnabled = autoSync
        saveResidentState()
    }

    public func probeAndSyncCloudBrigadeHost() async -> (ok: Bool, summary: String) {
        let base = cloudBrigadeConfig.cloudHostURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let overviewURL = URL(string: "\(base)/api/v1/brigade/overview") else {
            let msg = resolvedLanguage == .zhHans ? "云端主机地址格式无效" : "Invalid cloud host URL"
            cloudBrigadeConfig.isCloudReachable = false
            cloudBrigadeConfig.lastHealthSummary = msg
            saveResidentState()
            return (false, msg)
        }

        var req = URLRequest(url: overviewURL)
        req.timeoutInterval = 8
        if !cloudBrigadeConfig.cloudHubToken.isEmpty {
            req.setValue("Bearer \(cloudBrigadeConfig.cloudHubToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let msg = resolvedLanguage == .zhHans ? "云端主机返回 HTTP \(code)" : "Cloud host returned HTTP \(code)"
                cloudBrigadeConfig.isCloudReachable = false
                cloudBrigadeConfig.lastHealthSummary = msg
                saveResidentState()
                return (false, msg)
            }

            // Push all configured teammates to the 24/7 cloud host
            if let syncURL = URL(string: "\(base)/api/v1/cloud/teammates") {
                for bot in personas {
                    var post = URLRequest(url: syncURL)
                    post.httpMethod = "POST"
                    post.timeoutInterval = 6
                    post.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if !cloudBrigadeConfig.cloudHubToken.isEmpty {
                        post.setValue("Bearer \(cloudBrigadeConfig.cloudHubToken)", forHTTPHeaderField: "Authorization")
                    }
                    var payload: [String: Any] = [
                        "botId": bot.id,
                        "name": bot.name(resolvedLanguage),
                        "role": bot.role(resolvedLanguage),
                        "runtimeMode": bot.runtimeMode.rawValue,
                        "browserEnabled": bot.browserConfig.enabled,
                        "browserPlatforms": bot.browserConfig.platforms,
                        "requireApprovalBeforePost": bot.browserConfig.requireApprovalBeforePost
                    ]
                    if let manager = bot.reportsToBotId { payload["reportsToBotId"] = manager }
                    if let subProv = bot.subscriptionProvider { payload["subscriptionProvider"] = subProv.rawValue }
                    if let subAcc = bot.subscriptionAccountId { payload["subscriptionAccountId"] = subAcc }
                    if let model = bot.preferredModelId { payload["modelId"] = model }
                    if let proxy = bot.browserConfig.proxyURL { payload["proxyUrl"] = proxy }
                    post.httpBody = try? JSONSerialization.data(withJSONObject: payload)
                    _ = try? await URLSession.shared.data(for: post)
                }
            }

            let nowIso = ISO8601DateFormatter().string(from: Date())
            let summary = resolvedLanguage == .zhHans
                ? "24/7 云端主机在线 · 已同步 \(personas.count) 位 AI 队友与独立浏览器配置"
                : "24/7 Cloud host online · synced \(personas.count) AI teammates & isolated browser configs"
            cloudBrigadeConfig.isCloudReachable = true
            cloudBrigadeConfig.lastSyncAt = nowIso
            cloudBrigadeConfig.lastHealthSummary = summary
            saveResidentState()
            return (true, summary)
        } catch {
            let msg = resolvedLanguage == .zhHans
                ? "无法连接云端主机：\(error.localizedDescription)"
                : "Cloud host unreachable: \(error.localizedDescription)"
            cloudBrigadeConfig.isCloudReachable = false
            cloudBrigadeConfig.lastHealthSummary = msg
            saveResidentState()
            return (false, msg)
        }
    }
}
