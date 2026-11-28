import Foundation
import Testing
@testable import PipiBotKit

@Suite("Brigade Upgrade — Stacked Subscriptions, 24/7 Cloud Teammates & Isolated Browsers")
struct PipiBotBrigadeParityTests {

    @Test("Stacked subscription accounts build isolated CLAUDE_CONFIG_DIR / CODEX_HOME and scrub API keys")
    func testStackedSubscriptionEnvironmentIsolation() {
        let claudeAcc = PipiSubscriptionAccountRecord(
            id: "sub_claude_2",
            label: "Claude Max #2",
            provider: .claudeSubscription,
            profileDir: "/tmp/pipibot-test-sub-claude-2",
            useSystemDefaultProfile: false,
            priority: 2
        )
        let claudeEnv = PipiSubscriptionAccountPoolEngine.cliEnvironment(for: claudeAcc)
        #expect(claudeEnv["CLAUDE_CONFIG_DIR"] == "/tmp/pipibot-test-sub-claude-2")
        #expect(claudeEnv["ANTHROPIC_API_KEY"] == "")
        #expect(claudeEnv["ANTHROPIC_AUTH_TOKEN"] == "")

        let codexAcc = PipiSubscriptionAccountRecord(
            id: "sub_codex_2",
            label: "ChatGPT Pro #2",
            provider: .chatgptSubscription,
            profileDir: "/tmp/pipibot-test-sub-codex-2",
            useSystemDefaultProfile: false,
            priority: 2
        )
        let codexEnv = PipiSubscriptionAccountPoolEngine.cliEnvironment(for: codexAcc)
        #expect(codexEnv["CODEX_HOME"] == "/tmp/pipibot-test-sub-codex-2")
        #expect(codexEnv["OPENAI_API_KEY"] == "")

        let loginCmd = PipiSubscriptionAccountPoolEngine.interactiveLoginCommand(for: codexAcc)
        #expect(loginCmd.contains("CODEX_HOME="))
        #expect(loginCmd.contains("codex login"))
    }

    @Test("Subscription pool classifies rate limits, selects across strategies, and recovers cooldowns")
    func testSubscriptionPoolRotationAndRecovery() {
        let limit = PipiSubscriptionAccountPoolEngine.classifyError("HTTP 429: usage limit reached, try again in 45 minutes")
        #expect(limit.isRateLimited == true)
        #expect(limit.isAuthExpired == false)
        #expect(limit.cooldownSeconds == 45 * 60)

        let auth = PipiSubscriptionAccountPoolEngine.classifyError("401 Unauthorized: please log in")
        #expect(auth.isAuthExpired == true)
        #expect(auth.isRateLimited == false)

        let now = Date()
        let futureCooldown = ISO8601DateFormatter().string(from: now.addingTimeInterval(600))
        let pastCooldown = ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))

        var accounts: [PipiSubscriptionAccountRecord] = [
            PipiSubscriptionAccountRecord(
                id: "acc_1",
                label: "Claude #1",
                provider: .claudeSubscription,
                priority: 1,
                status: .rateLimited,
                cooldownUntil: futureCooldown,
                requestsCount: 10
            ),
            PipiSubscriptionAccountRecord(
                id: "acc_2",
                label: "Claude #2",
                provider: .claudeSubscription,
                priority: 2,
                status: .ready,
                requestsCount: 4
            ),
            PipiSubscriptionAccountRecord(
                id: "acc_3",
                label: "Claude #3",
                provider: .claudeSubscription,
                priority: 3,
                status: .rateLimited,
                cooldownUntil: pastCooldown,
                requestsCount: 1
            )
        ]

        // acc_3 cooldown already expired -> recovered to ready, and leastUsed picks acc_3 (1 req vs 4 reqs)
        let pickedLeast = PipiSubscriptionAccountPoolEngine.selectAccount(
            provider: .claudeSubscription,
            strategy: .leastUsed,
            accounts: accounts,
            now: now
        )
        #expect(pickedLeast?.account.id == "acc_3")

        // priorityFailover skips cooling acc_1 and picks acc_2
        let pickedPriority = PipiSubscriptionAccountPoolEngine.selectAccount(
            provider: .claudeSubscription,
            strategy: .priorityFailover,
            accounts: accounts,
            now: now
        )
        #expect(pickedPriority?.account.id == "acc_2")

        // recoverExpiredCooldowns mutates acc_3 back to ready
        let recovered = PipiSubscriptionAccountPoolEngine.recoverExpiredCooldowns(in: &accounts, now: now)
        #expect(recovered == 1)
        #expect(accounts[2].status == .ready)
    }

    @Test("Isolated Browser Safety Policy gates LinkedIn/X/Reddit external posts while allowing reading")
    func testSocialPlatformBrowserGuardrails() {
        let postButton = PipiBrowserCUAElement(
            ref: "e7",
            tag: "button",
            role: "button",
            label: "Post",
            x: 200,
            y: 300,
            width: 80,
            height: 36
        )
        let blockedX = PipiBrowserCUASafetyPolicy.evaluateAction(
            request: PipiBrowserCUAActionRequest(action: .click, ref: "e7"),
            targetElement: postButton,
            currentURL: "https://x.com/compose/post"
        )
        #expect(blockedX?.requiresApproval == true)
        #expect(blockedX?.actionKind == .externalEffect)

        let connectButton = PipiBrowserCUAElement(
            ref: "e3",
            tag: "button",
            role: "button",
            label: "Connect",
            x: 120,
            y: 180,
            width: 90,
            height: 32
        )
        let blockedLinkedIn = PipiBrowserCUASafetyPolicy.evaluateAction(
            request: PipiBrowserCUAActionRequest(action: .click, ref: "e3"),
            targetElement: connectButton,
            currentURL: "https://www.linkedin.com/in/founder"
        )
        #expect(blockedLinkedIn?.requiresApproval == true)

        let scrollAllowed = PipiBrowserCUASafetyPolicy.evaluateAction(
            request: PipiBrowserCUAActionRequest(action: .scroll, direction: "down"),
            targetElement: nil,
            currentURL: "https://www.reddit.com/r/LocalLLaMA"
        )
        #expect(scrollAllowed == nil)
    }

    @Test("Per-teammate browser registry assigns isolated persistent profiles per botId")
    func testTeammateBrowserRegistryIsolation() async {
        let registry = PipiTeammateBrowserRegistry()
        let growthDriver = await registry.driver(forBotId: "bot_growth_x")
        let researchDriver = await registry.driver(forBotId: "bot_research_reddit")

        let growthDir = await growthDriver.persistentProfileDirectory?.path
        let researchDir = await researchDriver.persistentProfileDirectory?.path
        #expect(growthDir != nil)
        #expect(researchDir != nil)
        #expect(growthDir != researchDir)
        #expect(growthDir?.contains("bot_growth_x") == true)
        #expect(researchDir?.contains("bot_research_reddit") == true)

        let activeIds = await registry.activeBotIds()
        #expect(activeIds == ["bot_growth_x", "bot_research_reddit"])
        await registry.closeAll()
    }

    @Test("AppStore Brigade org chart, subscription stacking, and backward-compatible persona decoding")
    @MainActor
    func testAppStoreBrigadeOrgAndPersistence() throws {
        let store = PipiAppStore(enableNativeRuntime: false)

        let acc1 = store.addSubscriptionAccount(provider: .claudeSubscription, label: "Claude Max #1", useSystemDefaultProfile: true)
        let acc2 = store.addSubscriptionAccount(provider: .claudeSubscription, label: "Claude Max #2")
        #expect(store.subscriptionAccounts(for: .claudeSubscription).count == 2)
        #expect(acc1.id != acc2.id)

        let lead = store.personas[0]
        let coder = store.personas[1]
        store.updateBotBrigadeSettings(
            personaId: coder.id,
            runtimeMode: .cloud24x7,
            reportsToBotId: lead.id,
            subscriptionProvider: .claudeSubscription,
            subscriptionAccountId: acc1.id,
            browserConfig: PipiTeammateBrowserConfig(enabled: true, platforms: ["x", "linkedin", "reddit"])
        )

        #expect(store.orgChartChildren(of: lead.id).contains(where: { $0.id == coder.id }))
        #expect(store.cloud24x7TeammatesCount >= 1)
        #expect(store.isolatedBrowserTeammatesCount >= 1)

        // Prevent self-reporting cycle
        store.updateBotBrigadeSettings(personaId: lead.id, reportsToBotId: lead.id)
        #expect(store.personas.first(where: { $0.id == lead.id })?.reportsToBotId == nil)

        // Backward-compatible decoding of legacy persona JSON without Brigade fields
        let legacyJSON = """
        {
          "id": "bot_legacy_1",
          "nameZh": "旧版助手",
          "nameEn": "Legacy Bot",
          "roleZh": "测试",
          "roleEn": "Test",
          "greetingZh": "你好",
          "greetingEn": "Hi",
          "systemPrompt": "Test prompt"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PipiBotPersona.self, from: legacyJSON)
        #expect(decoded.runtimeMode == .local)
        #expect(decoded.reportsToBotId == nil)
        #expect(decoded.browserConfig.enabled == false)
    }

    @Test("Mainland China social platforms (小红书 / 公众号 / 抖音 / 知乎 / B站) guardrails & login URLs")
    func testMainlandChinaSocialPlatformSupport() {
        #expect(PipiTeammateBrowserConfig.platformDisplayName("xiaohongshu", lang: .zhHans) == "小红书")
        #expect(PipiTeammateBrowserConfig.platformDisplayName("wechat_mp", lang: .zhHans) == "微信公众号")
        #expect(PipiTeammateBrowserConfig.platformLoginURL("xiaohongshu").contains("xiaohongshu.com"))
        #expect(PipiTeammateBrowserConfig.platformLoginURL("wechat_mp").contains("mp.weixin.qq.com"))
        #expect(PipiTeammateBrowserConfig.platformLoginURL("douyin").contains("douyin.com"))
        #expect(PipiTeammateBrowserConfig.platformLoginURL("bilibili").contains("bilibili.com"))

        let publishNoteBtn = PipiBrowserCUAElement(
            ref: "e5", tag: "button", role: "button", label: "发布笔记",
            x: 100, y: 200, width: 90, height: 36
        )
        let xhsVerdict = PipiBrowserCUASafetyPolicy.evaluateAction(
            request: PipiBrowserCUAActionRequest(action: .click, ref: "e5"),
            targetElement: publishNoteBtn,
            currentURL: "https://creator.xiaohongshu.com/publish/publish"
        )
        #expect(xhsVerdict?.requiresApproval == true)
        #expect(xhsVerdict?.actionKind == .externalEffect)

        let groupSendBtn = PipiBrowserCUAElement(
            ref: "e8", tag: "button", role: "button", label: "群发",
            x: 100, y: 200, width: 90, height: 36
        )
        let mpVerdict = PipiBrowserCUASafetyPolicy.evaluateAction(
            request: PipiBrowserCUAActionRequest(action: .click, ref: "e8"),
            targetElement: groupSendBtn,
            currentURL: "https://mp.weixin.qq.com/cgi-bin/appmsg"
        )
        #expect(mpVerdict?.requiresApproval == true)

        let browseZhihu = PipiBrowserCUASafetyPolicy.evaluateAction(
            request: PipiBrowserCUAActionRequest(action: .scroll, direction: "down"),
            targetElement: nil,
            currentURL: "https://www.zhihu.com/hot"
        )
        #expect(browseZhihu == nil)
    }

    @Test("Mainland China & third-party OpenAI-compatible stacked pool resolves LLM config without persisting raw keys")
    @MainActor
    func testMainlandChinaAndOpenAICompatibleAccountPool() throws {
        // Verify first-class Mainland China presets on PipiLLMProviderKind
        #expect(PipiLLMProviderKind.kimi.defaultBaseURL == "https://api.moonshot.cn/v1")
        #expect(PipiLLMProviderKind.zhipu.defaultBaseURL == "https://open.bigmodel.cn/api/paas/v4")
        #expect(PipiLLMProviderKind.qwen.defaultBaseURL == "https://dashscope.aliyuncs.com/compatible-mode/v1")
        #expect(PipiLLMProviderKind.minimax.defaultBaseURL == "https://api.minimaxi.com/v1")
        #expect(PipiLLMProviderKind.volcengine.defaultBaseURL == "https://ark.cn-beijing.volces.com/api/v3")
        #expect(PipiLLMProviderKind.siliconflow.defaultBaseURL == "https://api.siliconflow.cn/v1")

        // Chinese balance/quota error classification
        let cnBalanceErr = PipiSubscriptionAccountPoolEngine.classifyError("HTTP 402: 账户余额不足，无法调用")
        #expect(cnBalanceErr.isRateLimited == true)
        let cnAuthErr = PipiSubscriptionAccountPoolEngine.classifyError("401: invalid_api_key 密钥无效")
        #expect(cnAuthErr.isAuthExpired == true)

        let store = PipiAppStore(enableNativeRuntime: false)
        let acc = store.addSubscriptionAccount(
            provider: .openaiCompatible,
            label: "NewAPI 中转 #1",
            baseURL: "https://relay.example.cn/v1",
            modelId: "deepseek-chat",
            apiKey: "sk-cn-secret-never-on-disk"
        )

        // Ensure raw apiKey is NEVER encoded to JSON
        let encoded = try JSONEncoder().encode(acc)
        let jsonStr = String(data: encoded, encoding: .utf8) ?? ""
        #expect(!jsonStr.contains("sk-cn-secret-never-on-disk"))

        let bot = store.personas[0]
        store.updateBotBrigadeSettings(personaId: bot.id, subscriptionProvider: .openaiCompatible)
        let updatedBot = store.personas[0]

        #expect(store.hasConfiguredEngine == true)
        let target = store.resolvedActiveTarget(for: updatedBot)
        #expect(target == .llm(providerId: "pool:openai_compatible"))

        let resolvedCfg = store.resolvedEffectiveLLMConfig(providerId: "pool:openai_compatible", for: updatedBot)
        #expect(resolvedCfg?.baseURL == "https://relay.example.cn/v1")
        #expect(resolvedCfg?.modelId == "deepseek-chat")
        #expect(resolvedCfg?.apiKey == "sk-cn-secret-never-on-disk")
    }
}
