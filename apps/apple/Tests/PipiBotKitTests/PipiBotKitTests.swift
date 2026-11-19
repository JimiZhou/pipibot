import XCTest
@testable import PipiBotKit
@testable import PipiBotIOSUI
#if canImport(UserNotifications)
import UserNotifications
#endif

final class PipiBotKitTests: XCTestCase {

    @MainActor
    func testCanonical53AvatarStatesAnd9ExpressionsAnd8Shapes() {
        XCTAssertEqual(AvatarState53.allCases.count, 53)
        XCTAssertEqual(AvatarExpression9.allCases.count, 9)
        XCTAssertEqual(AvatarShape.allCases.count, 8)

        var groupCounts: [AvatarLifecycleGroup: Int] = [:]
        for state in AvatarState53.allCases {
            let meta = PipiProceduralAvatarEngine.metadata(for: state)
            groupCounts[meta.group, default: 0] += 1
        }
        XCTAssertEqual(groupCounts[.idleAmbient], 10)
        XCTAssertEqual(groupCounts[.thinkingReasoning], 11)
        XCTAssertEqual(groupCounts[.toolHarnessExecution], 14)
        XCTAssertEqual(groupCounts[.cueNeedsYouAlert], 10)
        XCTAssertEqual(groupCounts[.selfEvolutionDreaming], 8)
    }

    func test192RaySamplingAndInterpolationAndContourPath() {
        let orb = PipiAvatarMath.sampleShape192(.orb)
        let spark = PipiAvatarMath.sampleShape192(.spark)
        XCTAssertEqual(orb.count, 192)
        XCTAssertEqual(spark.count, 192)

        let mid = PipiAvatarMath.interpolateRays192(from: orb, to: spark, t: 0.5)
        XCTAssertEqual(mid.count, 192)
        XCTAssertEqual(mid[0], (orb[0] + spark[0]) * 0.5, accuracy: 1e-6)

        let path = PipiAvatarMath.buildSmoothContourPath(
            radii: mid,
            center: CGPoint(x: 60, y: 60),
            baseRadius: 36,
            scaleX: 1,
            scaleY: 1,
            rotationRad: 0
        )
        XCTAssertFalse(path.isEmpty)
    }

    func testRodrigues3DRotationPreservesUnitLength() {
        let v = PipiProceduralAvatarEngine.leftEyeSphereBase
        let axis = SIMD3<Double>(0.2, 0.9, -0.3)
        let rotated = PipiAvatarMath.rodriguesRotate(v, axis: axis, theta: 0.42)
        let norm = (rotated.x * rotated.x + rotated.y * rotated.y + rotated.z * rotated.z).squareRoot()
        XCTAssertEqual(norm, 1.0, accuracy: 1e-6)
        XCTAssertNotEqual(rotated.x, v.x)
    }

    func testCubicBezierBoundariesAndOvershoot() {
        XCTAssertEqual(PipiAvatarMath.cubicBezier(p1x: 0.34, p1y: 1.56, p2x: 0.64, p2y: 1.0, t: 0.0), 0.0, accuracy: 1e-6)
        XCTAssertEqual(PipiAvatarMath.cubicBezier(p1x: 0.34, p1y: 1.56, p2x: 0.64, p2y: 1.0, t: 1.0), 1.0, accuracy: 1e-6)
        let peak = PipiAvatarMath.cubicBezier(p1x: 0.34, p1y: 1.56, p2x: 0.64, p2y: 1.0, t: 0.55)
        XCTAssertGreaterThan(peak, 1.0)
    }

    @MainActor
    func test120HzPhysicsBlinkPeakAt45PercentAndStateTransitions() {
        let engine = PipiProceduralAvatarEngine(initialState: .idle)
        engine.autoBlink = false
        engine.blink()

        // Step right up to 45% of 0.26s = 0.117s (14 fixed steps of 1/120s = 0.1167s)
        engine.step(deltaSec: 0.117)
        XCTAssertTrue(engine.blinkActive)
        XCTAssertGreaterThan(engine.blinkClosure, 0.92)

        // Complete blink cycle
        engine.step(deltaSec: 0.20)
        XCTAssertFalse(engine.blinkActive)
        XCTAssertEqual(engine.blinkClosure, 0.0, accuracy: 1e-6)

        // Transition to claude-routing triggers morph & springs
        engine.setState(.claudeRouting)
        engine.step(deltaSec: 0.05)
        let snap = engine.telemetrySnapshot()
        XCTAssertEqual(snap.state, .claudeRouting)
        XCTAssertEqual(snap.shape, .squircle)
        XCTAssertGreaterThan(snap.springSwap, 0.0)
    }

    func testDesignGovernanceMetricConstants() {
        XCTAssertEqual(PipiTokens.buttonHeightMobile, 44)
        XCTAssertEqual(PipiTokens.buttonIconMobile, 18)
        XCTAssertEqual(PipiTokens.buttonGapMobile, 8)
        XCTAssertEqual(PipiTokens.buttonHeightDesktop, 32)
        XCTAssertEqual(PipiTokens.buttonIconDesktop, 16)
        XCTAssertEqual(PipiTokens.buttonGapDesktop, 6)
        XCTAssertEqual(PipiTokens.sheetTopEdgeCompact, 54)
        XCTAssertEqual(PipiTokens.sheetTopEdgeExpanded, 102)
    }

    @MainActor
    func testAppStoreOfflineLifecycleAndProtocolCodableRoundTrip() async throws {
        let store = PipiAppStore(autoConnect: false, seedDemoData: true)
        XCTAssertEqual(store.outcomes.count, 4)
        XCTAssertEqual(store.pendingDecisions.count, 3)
        XCTAssertEqual(store.fleetNodes.count, 5)

        // Create and evaluate outcome
        await store.createOutcome(
            title: "Nightly Backup Guard",
            domain: .infra,
            goal: "Verify encrypted SQLite backup uploaded to R2",
            preferredHarness: .pi,
            dailyBudgetUsd: 1.0
        )
        XCTAssertEqual(store.outcomes.count, 5)
        let newOutcome = try XCTUnwrap(store.outcomes.first)
        await store.evaluateOutcome(newOutcome.id)
        XCTAssertEqual(store.outcomes.first?.status, .achieved)

        // Resolve Needs You decision
        let pending = try XCTUnwrap(store.pendingDecisions.first)
        await store.resolveDecision(pending.id, optionId: pending.recommendedOptionId)
        XCTAssertEqual(store.pendingDecisions.count, 2)

        // Run Nightly Dreaming & approve diff
        let scoreBefore = store.understandingScore.overall
        await store.runNightlyDreaming()
        XCTAssertGreaterThan(store.understandingScore.overall, scoreBefore)
        if let firstDiff = store.lastDigest?.diffs.first {
            await store.reviewEvolutionDiff(diffId: firstDiff.diffId, approve: true)
            XCTAssertEqual(store.lastDigest?.diffs.first?.reviewStatus, .approved)
        }

        // Codable round-trip verification matching daemon JSON schema
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let encoded = try encoder.encode(store.tunnelStatus)
        let decoded = try decoder.decode(CloudflareTunnelStatus.self, from: encoded)
        XCTAssertEqual(decoded.tunnelUrl, store.tunnelStatus.tunnelUrl)
        XCTAssertEqual(decoded.freeTierQuota.monthlyCostUsd, 0.0)
    }

    @MainActor
    func testNativeMacRuntimeProbesTelemetryCueAndPersistence() async throws {
        // 1. Harness binary probing across macOS search paths
        let probes = PipiNativeMacRuntime.probeInstalledHarnesses()
        XCTAssertEqual(probes.count, 5)
        XCTAssertTrue(probes.contains(where: { $0.provider == .pi && $0.installed }))
        XCTAssertTrue(probes.contains(where: { $0.provider == .byok }))

        // 2. Host telemetry reading live OS metrics
        let host = PipiNativeMacRuntime.sampleHostTelemetry(activeSessionsCount: 2)
        XCTAssertEqual(host.nodeId, "mac-resident")
        XCTAssertEqual(host.kind, .mac)
        XCTAssertEqual(host.vitality, .busy)
        XCTAssertGreaterThan(host.cpuLoadPct, 0.0)
        XCTAssertGreaterThan(host.memoryUsedPct, 0.0)

        // 3. Frontmost app & git branch Cue detection
        let cue = PipiNativeMacRuntime.detectFrontmostAppContext(
            workspacePath: "/Users/jimizhou/Desktop/Projects/pipibot"
        )
        XCTAssertFalse(cue.activeAppName.isEmpty)
        XCTAssertEqual(cue.actions.count, 3)

        // 4. All-in-one persistence round-trip in isolated temp file
        let tempUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        let secrets = PipiInMemorySecretStore()
        let storeA = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            enableEmbeddedBridge: false,
            stateFileUrl: tempUrl,
            secretStore: secrets
        )
        XCTAssertEqual(storeA.connectionMode, .nativeResident)
        await storeA.createOutcome(
            title: "All-in-One Persist Check",
            domain: .work,
            goal: "Verify resident-state.json reloads across restarts",
            preferredHarness: .claudeCode,
            dailyBudgetUsd: 1.5
        )
        storeA.setKeepAwake(true)
        XCTAssertTrue(storeA.bridgeSupervisor.keepAwakeEnabled)
        storeA.setKeepAwake(false)
        storeA.flush()

        let storeB = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            enableEmbeddedBridge: false,
            stateFileUrl: tempUrl,
            secretStore: secrets
        )
        XCTAssertTrue(storeB.outcomes.contains(where: { $0.title == "All-in-One Persist Check" }))
        XCTAssertFalse(storeB.bridgeSupervisor.keepAwakeEnabled)
    }

    @MainActor
    func testIOSSystemIntegrationDeepLinksAndLiveActivitySnapshot() throws {
        // 1. Deep-link parser across all supported routes
        XCTAssertNil(PipiIOSDeepLinkRouter.parse(URL(string: "https://example.com")!))
        XCTAssertEqual(
            PipiIOSDeepLinkRouter.parse(URL(string: "pipibot://pair?tunnel=https://mac-origin.pipibot.dev")!),
            .pairTunnel(urlString: "https://mac-origin.pipibot.dev")
        )
        XCTAssertEqual(
            PipiIOSDeepLinkRouter.parse(URL(string: "pipibot://tab/chat")!),
            .openTab(.chat)
        )
        XCTAssertEqual(
            PipiIOSDeepLinkRouter.parse(URL(string: "pipibot://tab/bots")!),
            .openTab(.bots)
        )
        XCTAssertEqual(
            PipiIOSDeepLinkRouter.parse(URL(string: "pipibot://tab/tasks")!),
            .openTab(.tasks)
        )
        XCTAssertEqual(
            PipiIOSDeepLinkRouter.parse(URL(string: "pipibot://tab/needs-you")!),
            .openTab(.tasks)
        )
        XCTAssertEqual(
            PipiIOSDeepLinkRouter.parse(URL(string: "pipibot://tab/settings")!),
            .openTab(.settings)
        )
        XCTAssertEqual(
            PipiIOSDeepLinkRouter.parse(URL(string: "pipibot://decision/dec_pr_142/approve")!),
            .approveDecision(decisionId: "dec_pr_142")
        )

        // 2. Apply deep-link actions against store & active tab
        let store = PipiAppStore(autoConnect: false)
        var activeTab: PipiIOSTab = .chat

        if let tabAction = PipiIOSDeepLinkRouter.parse(URL(string: "pipibot://tab/bots")!) {
            PipiIOSDeepLinkRouter.apply(tabAction, to: store, selectedTab: &activeTab)
            XCTAssertEqual(activeTab, .bots)
        }
        if let pairAction = PipiIOSDeepLinkRouter.parse(URL(string: "pipibot://pair?tunnel=https://edge.pipibot.dev")!) {
            PipiIOSDeepLinkRouter.apply(pairAction, to: store, selectedTab: &activeTab)
            XCTAssertEqual(store.daemonEndpoint, "https://edge.pipibot.dev")
        }
        if let approveAction = PipiIOSDeepLinkRouter.parse(URL(string: "pipibot://decision/dec_pr_142/approve")!) {
            PipiIOSDeepLinkRouter.apply(approveAction, to: store, selectedTab: &activeTab)
            XCTAssertEqual(activeTab, .tasks)
        }

        // 3. Dynamic Island / Live Activity snapshot persistence round-trip
        let snapshot = PipiIOSWidgetBridge.snapshot(from: store)
        let snapUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-ios-snap-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: snapUrl) }

        try PipiIOSWidgetBridge.saveSnapshot(snapshot, to: snapUrl)
        let loaded = try XCTUnwrap(PipiIOSWidgetBridge.loadSnapshot(from: snapUrl))
        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded.pendingDecisionsCount, store.pendingDecisions.count)

        // 4. Lock-screen notification categories (including UNTextInputNotificationAction)
        #if canImport(UserNotifications)
        let categories = PipiIOSNotificationManager.buildNotificationCategories()
        XCTAssertEqual(categories.count, 2)
        let needsYouCat = try XCTUnwrap(categories.first(where: { $0.identifier == PipiIOSNotificationManager.needsYouCategory }))
        XCTAssertTrue(needsYouCat.actions.contains(where: { $0 is UNTextInputNotificationAction && $0.identifier == PipiIOSNotificationManager.steerActionId }))
        #endif
    }

    @MainActor
    func testCommercialPersonalBotOnboardingPersonasLocalizationAndInferenceURLs() throws {
        // 1. System language auto-detection
        XCTAssertEqual(PipiAppLanguage.detectSystemLanguage(preferredLanguages: ["zh-Hans-CN", "en-US"]), .zhHans)
        XCTAssertEqual(PipiAppLanguage.detectSystemLanguage(preferredLanguages: ["en-US", "zh-Hans"]), .en)
        XCTAssertEqual(PipiStrings(resolved: .zhHans).onboardingWelcomeTitle, "欢迎使用 PiPiBot")
        XCTAssertEqual(PipiStrings(resolved: .en).onboardingWelcomeTitle, "Welcome to PiPiBot")

        // 2. Endpoint URL normalization for OpenAI / Anthropic / Gemini
        XCTAssertEqual(
            PipiInferenceEngine.buildOpenAIChatCompletionsURL(baseURL: "https://api.openai.com/v1/")?.absoluteString,
            "https://api.openai.com/v1/chat/completions"
        )
        XCTAssertEqual(
            PipiInferenceEngine.buildAnthropicMessagesURL(baseURL: "https://api.anthropic.com")?.absoluteString,
            "https://api.anthropic.com/v1/messages"
        )
        XCTAssertEqual(
            PipiInferenceEngine.buildGeminiGenerateURL(baseURL: "https://generativelanguage.googleapis.com/v1beta", modelId: "gemini-2.5-flash", apiKey: "test-key")?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=test-key"
        )

        // 3. Onboarding, LLM config, Personas & Persistence round-trip
        let tempUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-commercial-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        let secrets = PipiInMemorySecretStore()
        let store = PipiAppStore(autoConnect: false, enableNativeRuntime: true, stateFileUrl: tempUrl, secretStore: secrets)
        XCTAssertFalse(store.hasCompletedOnboarding)
        XCTAssertEqual(store.personas.count, 4)

        let cfg = PipiLLMProviderConfig(
            name: "DeepSeek",
            kind: .deepseek,
            apiKey: "sk-test-1234",
            modelId: "deepseek-chat"
        )
        store.upsertLLMProvider(cfg, setAsDefault: true)
        XCTAssertTrue(store.hasConfiguredEngine)
        XCTAssertEqual(store.resolvedActiveTarget(), .llm(providerId: cfg.id))

        let customBot = PipiBotPersona(
            nameZh: "产品顾问",
            nameEn: "Product Coach",
            roleZh: "帮你打磨商业化体验",
            roleEn: "Helps refine commercial UX",
            greetingZh: "你好，聊聊你的产品想法？",
            greetingEn: "Hi, let's refine your product.",
            systemPrompt: "You are a sharp product strategist.",
            accent: .coral
        )
        store.upsertPersona(customBot)
        store.setLanguage(.zhHans)
        store.completeOnboarding(selectedPersonaId: customBot.id)
        let conv = store.createConversation(for: customBot.id)
        store.flush()

        // Reload in fresh instance
        let reloaded = PipiAppStore(autoConnect: false, enableNativeRuntime: true, stateFileUrl: tempUrl, secretStore: secrets)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
        XCTAssertEqual(reloaded.language, .zhHans)
        XCTAssertEqual(reloaded.llmProviders.first?.modelId, "deepseek-chat")
        XCTAssertEqual(reloaded.activePersona.id, customBot.id)
        XCTAssertEqual(reloaded.activeConversation?.id, conv.id)
    }

    @MainActor
    func testZeroDirtyDataCleanSlateMigrationCodexFlagsStreamingAndRoutines() throws {
        // 1. Production store starts completely clean with zero demo records
        let cleanStore = PipiAppStore(autoConnect: false, enableNativeRuntime: false, seedDemoData: false)
        XCTAssertTrue(cleanStore.outcomes.isEmpty)
        XCTAssertTrue(cleanStore.decisions.isEmpty)
        XCTAssertTrue(cleanStore.fleetNodes.isEmpty)
        XCTAssertNil(cleanStore.lastDigest)
        XCTAssertFalse(cleanStore.companionSyncEnabled)

        // 2. Codex CLI arguments include --skip-git-repo-check so non-git directories succeed
        let codexArgs = PipiInferenceEngine.localAgentArguments(for: .codex, prompt: "hello")
        XCTAssertTrue(codexArgs.contains("--skip-git-repo-check"))
        XCTAssertTrue(codexArgs.contains("exec"))

        // 3. Streaming SSE parsers & ANSI stripper
        XCTAssertEqual(
            PipiInferenceEngine.parseOpenAISSEDataLine("data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}"),
            "Hello"
        )
        XCTAssertNil(PipiInferenceEngine.parseOpenAISSEDataLine("data: [DONE]"))
        XCTAssertEqual(
            PipiInferenceEngine.parseAnthropicSSEDataLine("data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"World\"}}"),
            "World"
        )
        XCTAssertEqual(
            PipiInferenceEngine.parseGeminiSSEDataLine("data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hi\"}]}}]}"),
            "Hi"
        )
        XCTAssertEqual(PipiInferenceEngine.stripAnsiEscapeCodes("\u{001B}[32mOK\u{001B}[0m"), "OK")

        // 4. Legacy dirty state migration strips demo entries while preserving real user config & chats
        let tempUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-dirty-migration-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        let seededRef = PipiAppStore(autoConnect: false, seedDemoData: true, secretStore: PipiInMemorySecretStore())
        let realProvider = PipiLLMProviderConfig(name: "OpenAI", kind: .openai, apiKey: "sk-real-key", modelId: "gpt-4o")
        let realConv = PipiConversation(personaId: "bot_pipi_general", title: "My Real Chat", messages: [PipiChatMessage(role: .user, content: "Hello")])
        let legacyDirty = PipiResidentPersistedState(
            outcomes: seededRef.outcomes,
            decisions: seededRef.decisions,
            museCards: seededRef.museCards,
            activeHarness: .pi,
            themeModeRaw: "system",
            keepAwakeEnabled: false,
            updatedAt: "2026-11-19T00:00:00Z",
            hasCompletedOnboarding: true,
            languageRaw: "zh-Hans",
            llmProviders: [realProvider],
            defaultLLMProviderId: realProvider.id,
            enabledLocalAgents: [.codex],
            conversations: [realConv],
            activeConversationId: realConv.id,
            schemaMigrationVersion: nil
        )
        // Simulate pre-S0 resident-state.json that still contained plaintext "apiKey" in JSON
        let rawEncoded = try JSONEncoder().encode(legacyDirty)
        var jsonObj = try XCTUnwrap(try JSONSerialization.jsonObject(with: rawEncoded) as? [String: Any])
        if var providersJson = jsonObj["llmProviders"] as? [[String: Any]], !providersJson.isEmpty {
            providersJson[0]["apiKey"] = "sk-real-key"
            jsonObj["llmProviders"] = providersJson
        }
        let legacyBytes = try JSONSerialization.data(withJSONObject: jsonObj, options: [.prettyPrinted])
        try legacyBytes.write(to: tempUrl, options: .atomic)

        let secrets = PipiInMemorySecretStore()
        let migrated = PipiAppStore(autoConnect: false, enableNativeRuntime: true, stateFileUrl: tempUrl, secretStore: secrets)
        XCTAssertTrue(migrated.outcomes.isEmpty)
        XCTAssertTrue(migrated.decisions.isEmpty)
        XCTAssertTrue(migrated.museCards.isEmpty)
        XCTAssertEqual(migrated.llmProviders.first?.apiKey, "sk-real-key")
        XCTAssertEqual(secrets.secret(for: realProvider.secretAccountKey), "sk-real-key")
        XCTAssertEqual(migrated.enabledLocalAgents, [.codex])
        XCTAssertEqual(migrated.conversations.count, 1)
        XCTAssertEqual(migrated.conversations.first?.title, "My Real Chat")

        // 5. Conversation archive & Bot Routine persistence round-trip
        migrated.toggleArchiveConversation(realConv.id)
        XCTAssertTrue(migrated.conversationsForActivePersona.isEmpty)
        XCTAssertEqual(migrated.archivedConversationsForActivePersona.count, 1)

        let routine = PipiBotRoutine(
            personaId: "bot_pipi_general",
            title: "Morning Brief",
            prompt: "Summarize today's focus",
            schedule: .daily,
            hour: 9,
            minute: 0
        )
        migrated.addRoutine(routine)
        migrated.flush()
        let reloaded2 = PipiAppStore(autoConnect: false, enableNativeRuntime: true, stateFileUrl: tempUrl, secretStore: secrets)
        XCTAssertEqual(reloaded2.routines.count, 1)
        XCTAssertEqual(reloaded2.routines.first?.title, "Morning Brief")
        XCTAssertEqual(reloaded2.archivedConversationsForActivePersona.count, 1)
    }

    @MainActor
    func testAvatarStepDeduplicationAndOriginalRobotIconGrammar() throws {
        // 1. Multi-view wall-clock tick deduplication prevents double-stepping glitches
        let engine = PipiProceduralAvatarEngine()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000.0)
        engine.stepIfNeeded(at: t0)
        let afterFirst = engine.telemetrySnapshot().elapsed
        XCTAssertGreaterThan(afterFirst, 0)

        // Rapid duplicate call 2ms later from a second mounted view must be ignored
        engine.stepIfNeeded(at: t0.addingTimeInterval(0.002))
        XCTAssertEqual(engine.telemetrySnapshot().elapsed, afterFirst, accuracy: 1e-9)

        // Normal next frame (16.6ms later) advances cleanly
        engine.stepIfNeeded(at: t0.addingTimeInterval(0.017))
        XCTAssertGreaterThan(engine.telemetrySnapshot().elapsed, afterFirst)

        // 2. Original 4-persona hardware-robot motif mapping
        let personas = PipiBotPersona.defaultPersonas
        XCTAssertEqual(personas.count, 4)
        XCTAssertEqual(PipiPersonaMotif.resolve(for: personas[0]), .haloPip)
        XCTAssertEqual(PipiPersonaMotif.resolve(for: personas[1]), .caret)
        XCTAssertEqual(PipiPersonaMotif.resolve(for: personas[2]), .nib)
        XCTAssertEqual(PipiPersonaMotif.resolve(for: personas[3]), .loop)

        // 3. Signature "Pipi Halo" chassis path bounds validity
        let path = PipiRobotGeometry.chassisPath(in: CGRect(x: 0, y: 0, width: 100, height: 108))
        XCTAssertFalse(path.isEmpty)
        XCTAssertGreaterThan(path.boundingRect.width, 95)
        XCTAssertGreaterThan(path.boundingRect.height, 100)

        // 4. All 4 persona motifs produce distinct non-empty chassis silhouettes
        let rect = CGRect(x: 0, y: 0, width: 100, height: 108)
        let rects = PipiPersonaMotif.allCases.map { PipiRobotGeometry.chassisPath(in: rect, motif: $0).boundingRect }
        XCTAssertEqual(rects.count, 4)
        for r in rects {
            XCTAssertGreaterThan(r.width, 80)
            XCTAssertGreaterThan(r.height, 85)
        }
        XCTAssertNotEqual(rects[0], rects[1])
        XCTAssertNotEqual(rects[2], rects[3])
    }

    @MainActor
    func testZoomScalePersistenceAndAttachmentsRoundTrip() throws {
        let tempUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-zoom-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        let secrets = PipiInMemorySecretStore()
        let store = PipiAppStore(autoConnect: false, enableNativeRuntime: true, stateFileUrl: tempUrl, secretStore: secrets)
        XCTAssertEqual(store.uiZoomScale, 1.0, accuracy: 1e-6)
        XCTAssertEqual(store.uiZoomPercentLabel, "100%")

        store.zoomIn()
        store.zoomIn()
        XCTAssertEqual(store.uiZoomScale, 1.2, accuracy: 1e-6)
        XCTAssertEqual(store.uiZoomPercentLabel, "120%")

        // Clamp upper bound at 1.40
        store.setZoomScale(2.5)
        XCTAssertEqual(store.uiZoomScale, 1.4, accuracy: 1e-6)

        // Clamp lower bound at 0.80
        store.setZoomScale(0.3)
        XCTAssertEqual(store.uiZoomScale, 0.8, accuracy: 1e-6)

        store.setZoomScale(1.1)
        store.flush()
        let reloaded = PipiAppStore(autoConnect: false, enableNativeRuntime: true, stateFileUrl: tempUrl, secretStore: secrets)
        XCTAssertEqual(reloaded.uiZoomScale, 1.1, accuracy: 1e-6)

        reloaded.resetZoom()
        XCTAssertEqual(reloaded.uiZoomScale, 1.0, accuracy: 1e-6)

        // File attachment loading + PipiChatMessage Codable round-trip
        let txtUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-sample-\(UUID().uuidString).swift")
        defer { try? FileManager.default.removeItem(at: txtUrl) }
        try "let answer = 42\n".write(to: txtUrl, atomically: true, encoding: .utf8)

        let att = PipiChatAttachment.fromFileURL(txtUrl)
        XCTAssertEqual(att.name, txtUrl.lastPathComponent)
        XCTAssertEqual(att.textContent, "let answer = 42\n")
        XCTAssertEqual(att.iconName, "doc.text")

        let msg = PipiChatMessage(role: .user, content: "Review this", attachments: [att])
        let encoded = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(PipiChatMessage.self, from: encoded)
        XCTAssertEqual(decoded.attachments?.count, 1)
        XCTAssertEqual(decoded.attachments?.first?.name, att.name)
    }

    @MainActor
    func testProjectSessionManagementRenameMoveArchiveAndPersistence() throws {
        let tempUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-projects-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        let secrets = PipiInMemorySecretStore()
        let store = PipiAppStore(autoConnect: false, enableNativeRuntime: true, stateFileUrl: tempUrl, secretStore: secrets)
        let project = PipiProject(
            name: "Core Refactor",
            accent: .emerald,
            workspacePath: "/tmp/pipi-proj",
            instructions: "Keep modules small."
        )
        store.upsertProject(project)
        XCTAssertEqual(store.projects.count, 1)

        let conv = store.createConversation(projectId: project.id)
        XCTAssertEqual(store.conversations(inProject: project.id).count, 1)
        XCTAssertEqual(store.effectiveWorkspaceDirectory, "/tmp/pipi-proj")

        store.renameConversation(conv.id, title: "Refactor Plan")
        XCTAssertEqual(store.activeConversation?.title, "Refactor Plan")

        // Move out to ungrouped & archive
        store.moveConversation(conv.id, toProject: nil)
        XCTAssertEqual(store.conversations(inProject: project.id).count, 0)
        XCTAssertEqual(store.ungroupedConversationsForActivePersona.count, 1)

        store.toggleArchiveConversation(conv.id)
        XCTAssertEqual(store.allArchivedConversations.count, 1)

        // Move back into project automatically unarchives
        store.moveConversation(conv.id, toProject: project.id)
        XCTAssertEqual(store.allArchivedConversations.count, 0)
        XCTAssertEqual(store.conversations(inProject: project.id).count, 1)
        store.flush()

        // Persistence round-trip
        let reloaded = PipiAppStore(autoConnect: false, enableNativeRuntime: true, stateFileUrl: tempUrl, secretStore: secrets)
        XCTAssertEqual(reloaded.projects.first?.name, "Core Refactor")
        XCTAssertEqual(reloaded.conversations(inProject: project.id).first?.title, "Refactor Plan")

        // Deleting a project preserves its conversations as ungrouped
        reloaded.deleteProject(project.id)
        XCTAssertTrue(reloaded.projects.isEmpty)
        XCTAssertEqual(reloaded.ungroupedConversationsForActivePersona.count, 1)
    }
}
