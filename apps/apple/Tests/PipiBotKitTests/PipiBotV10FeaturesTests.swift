// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.

import Foundation
import Testing
@testable import PipiBotKit

@Suite("v0.10.0 Features: GitHub Updater, Proactive CLI, Security Auditor, Per-Bot Model & WeChat 1v1")
struct PipiBotV10FeaturesTests {

    @Test("GitHub Release SemVer comparison, asset selection, and SHA-256 parsing")
    func testGitHubUpdaterLogic() {
        #expect(PipiGitHubUpdaterLogic.compareSemVer("0.10.0", "0.9.0") == .orderedDescending)
        #expect(PipiGitHubUpdaterLogic.compareSemVer("v0.10.0", "0.10.0") == .orderedSame)
        #expect(PipiGitHubUpdaterLogic.compareSemVer("0.10.0-beta", "0.10.0") == .orderedAscending)
        #expect(PipiGitHubUpdaterLogic.compareSemVer("0.9.0", "0.10.0") == .orderedAscending)

        let releaseJSON = """
        {
          "tag_name": "v0.10.0",
          "name": "PiPiBot v0.10.0",
          "body": "- Auto-update from GitHub Releases\\n- Proactive CLI delegation",
          "html_url": "https://github.com/JimiZhou/pipibot/releases/tag/v0.10.0",
          "draft": false,
          "assets": [
            { "name": "PiPiBot-0.10.0-x86_64.dmg", "browser_download_url": "https://example.com/x64.dmg", "size": 1024 },
            { "name": "PiPiBot-0.10.0-arm64.dmg", "browser_download_url": "https://example.com/arm64.dmg", "size": 2048 },
            { "name": "PiPiBot-0.10.0-arm64.dmg.sha256", "browser_download_url": "https://example.com/arm64.dmg.sha256", "size": 88 }
          ]
        }
        """
        let parsed = PipiGitHubUpdaterLogic.parseReleaseJSON(
            Data(releaseJSON.utf8),
            currentVersion: "0.9.0",
            preferredArch: "arm64"
        )
        #expect(parsed != nil)
        #expect(parsed?.isNewer == true)
        #expect(parsed?.info.version == "0.10.0")
        #expect(parsed?.info.dmgAsset?.name == "PiPiBot-0.10.0-arm64.dmg")
        #expect(parsed?.info.sha256Asset?.name == "PiPiBot-0.10.0-arm64.dmg.sha256")

        let notNewer = PipiGitHubUpdaterLogic.parseReleaseJSON(
            Data(releaseJSON.utf8),
            currentVersion: "0.10.0",
            preferredArch: "arm64"
        )
        #expect(notNewer?.isNewer == false)

        let validHash = "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90  PiPiBot-0.10.0-arm64.dmg\n"
        #expect(PipiGitHubUpdaterLogic.parseSHA256Text(validHash) == "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90")
    }

    @Test("Per-bot model selection resolves custom model override or falls back to global default")
    @MainActor
    func testPerBotModelSelectionAndCLIArgs() async {
        let recordedModels = LockedModelRecorder()
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            secretStore: PipiInMemorySecretStore(),
            inferenceExecutor: { target, cfg, _, _, _, _ in
                if case .llm = target, let cfg {
                    recordedModels.append(cfg.modelId)
                    return PipiInferenceResult(text: "model=\(cfg.modelId)", engineLabel: "\(cfg.name) · \(cfg.modelId)")
                }
                return PipiInferenceResult(text: "ok", engineLabel: "ok")
            }
        )

        let provider = PipiLLMProviderConfig(
            id: "llm_default",
            name: "Gateway",
            kind: .customOpenAI,
            baseURL: "https://api.example.com/v1",
            apiKey: "sk-test",
            modelId: "deepseek-v4.1-flash"
        )
        store.upsertLLMProvider(provider, setAsDefault: true)

        // Default bot without override -> uses global default model
        let generalConv = store.createConversation(for: "bot_pipi_general", activate: true)
        await store.sendPersonalMessage("hello", conversationId: generalConv.id, personaId: "bot_pipi_general")
        #expect(recordedModels.values.last == "deepseek-v4.1-flash")

        // Coder bot with specific model override -> uses gpt-4o while general stays on default!
        store.setPersonaExecutionModel(personaId: "bot_pipi_coder", target: .auto, modelId: "gpt-4o")
        #expect(store.activeEngineDisplayLabel(for: store.personas.first(where: { $0.id == "bot_pipi_coder" })).contains("gpt-4o"))
        let coderConv = store.createConversation(for: "bot_pipi_coder", activate: false)
        await store.sendPersonalMessage("review", conversationId: coderConv.id, personaId: "bot_pipi_coder", activateTargetConversation: false)
        #expect(recordedModels.values.last == "gpt-4o")

        // CLI argument model overrides
        let codexArgs = PipiInferenceEngine.localAgentArguments(
            for: .codex,
            prompt: "check tests",
            permissionTier: .readOnly,
            cliSessionId: nil,
            modelOverride: "o3"
        )
        #expect(codexArgs.contains("-m"))
        #expect(codexArgs.contains("o3"))

        let claudeArgs = PipiInferenceEngine.localAgentArguments(
            for: .claudeCode,
            prompt: "audit",
            permissionTier: .readOnly,
            cliSessionId: nil,
            modelOverride: "claude-sonnet-4"
        )
        #expect(claudeArgs.contains("--model"))
        #expect(claudeArgs.contains("claude-sonnet-4"))
    }

    @Test("Proactive CLI delegation invokes Codex without /codex via natural language and <pipibot_cli_delegate>")
    @MainActor
    func testProactiveCLIDelegation() async {
        // 1. Natural language detection
        let nat = PipiExternalSubAgentRouter.detectNaturalLanguageInvocation(
            "用 codex 帮我检查当前仓库的 git diff",
            usableAgents: [.codex, .claudeCode]
        )
        #expect(nat?.kind == .codex)

        // 2. XML tag extraction
        let rawReply = """
        我来调用 Codex 检查工程状态。
        <pipibot_cli_delegate agent="codex" mode="readonly" reason="检查测试状态">Run npm test and summarize</pipibot_cli_delegate>
        """
        let extracted = PipiExternalSubAgentRouter.extractCLIDelegation(from: rawReply)
        #expect(extracted?.directive.agent == .codex)
        #expect(extracted?.directive.isWriteMode == false)
        #expect(extracted?.directive.taskPrompt == "Run npm test and summarize")
        #expect(extracted?.cleanedText == "我来调用 Codex 检查工程状态。")

        // 3. End-to-end Store autonomous delegation without /codex
        let cliCalls = LockedModelRecorder()
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            secretStore: PipiInMemorySecretStore(),
            sessionInferenceExecutor: { target, _, _, history, _, tier, _, _, _ in
                switch target {
                case .llm:
                    return PipiInferenceResult(
                        text: "好的，我来检查仓库。\n<pipibot_cli_delegate agent=\"codex\" mode=\"readonly\" reason=\"检查构建\">check status</pipibot_cli_delegate>",
                        engineLabel: "PiPi"
                    )
                case .localAgent(let kind):
                    cliCalls.append("\(kind.rawValue):\(tier.rawValue):\(history.last?.content ?? "")")
                    return PipiInferenceResult(text: "Codex 检查通过：0 errors", engineLabel: "Codex CLI")
                case .auto:
                    return PipiInferenceResult(text: "", engineLabel: "Auto")
                }
            }
        )
        store.upsertLLMProvider(
            PipiLLMProviderConfig(id: "llm_1", name: "LLM", kind: .customOpenAI, baseURL: "https://api.example.com/v1", apiKey: "sk-1", modelId: "m1"),
            setAsDefault: true
        )
        // Force codex status usable in test
        store.localAgentStatuses = [
            PipiLocalAgentStatus(kind: .codex, installed: true, authenticated: true, binaryPath: "/usr/local/bin/codex", authHint: "ok", enabled: true)
        ]
        store.enabledLocalAgents = [.codex]

        let conv = store.createConversation(for: "bot_pipi_general", activate: true)
        await store.sendPersonalMessage("帮我检查这个项目目前的测试能不能过", conversationId: conv.id)
        #expect(cliCalls.values == ["codex:readOnly:check status"])
        let lastMsg = store.conversations.first(where: { $0.id == conv.id })?.messages.last?.content ?? ""
        #expect(lastMsg.contains("Codex 检查通过"))
        #expect(!lastMsg.contains("<pipibot_cli_delegate"))
    }

    @Test("Security Auditor judge parsing, prompt risk classification, and PiPi task approval gate")
    @MainActor
    func testSecurityAuditorAndRiskTaskApproval() async throws {
        // 1. JSON parsing (including fenced JSON)
        let fenced = """
        ```json
        {"risk_level":"high","user_authorization":"low","decision":"needs_approval","rationale":"Deleting workspace files requires confirmation."}
        ```
        """
        let parsed = PipiPermissionGuardrail.parseLLMJudgeResponse(fenced)
        #expect(parsed?.riskLevel == .high)
        #expect(parsed?.userAuthorization == .low)
        #expect(parsed?.decision == .needsApproval)

        // 2. Prompt risk classification
        let risky = PipiPermissionGuardrail.classifyPromptRisk("请帮我执行 git push origin main 推送代码")
        #expect(risky.isRisky == true)
        #expect(risky.actionKind == .externalEffect)

        let safe = PipiPermissionGuardrail.classifyPromptRisk("解释一下 Swift Concurrency 的 Sendable 协议")
        #expect(safe.isRisky == false)

        // 3. PiPi LLM turn hits Security Auditor and pauses for approval before executing risky task
        let llmInvocations = LockedModelRecorder()
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            secretStore: PipiInMemorySecretStore(),
            inferenceExecutor: { _, _, _, history, _, _ in
                llmInvocations.append(history.last?.content ?? "")
                return PipiInferenceResult(text: "已执行推送。", engineLabel: "PiPi")
            },
            llmGuardrailJudge: { _ in
                PipiLLMJudgeResponse(
                    riskLevel: .high,
                    userAuthorization: .low,
                    decision: .needsApproval,
                    rationale: "安全审计官：涉及向远端仓库推送，需主人确认。"
                )
            }
        )
        store.upsertLLMProvider(
            PipiLLMProviderConfig(id: "llm_1", name: "LLM", kind: .customOpenAI, baseURL: "https://api.example.com/v1", apiKey: "sk-1", modelId: "m1"),
            setAsDefault: true
        )
        let conv = store.createConversation(for: "bot_pipi_general", activate: true)
        await store.sendPersonalMessage("帮我执行 git push origin main", conversationId: conv.id)

        // Must pause before calling LLM execution and emit approval card!
        #expect(llmInvocations.values.isEmpty)
        #expect(store.conversations.first(where: { $0.id == conv.id })?.state == .needsYou)
        let approval = try #require(store.pendingApprovals.first)
        #expect(approval.rationale?.contains("安全审计官") == true)

        // Approving resumes execution
        await store.resolveApproval(approval.id, optionId: "allow_changes")
        #expect(llmInvocations.values.count == 1)
    }

    @Test("WeChat rich media parsing, AES-128-ECB decryption, and 1v1 conversational intent routing")
    func testWeChatRichMediaCryptoAndConversationalIntents() {
        // 1. AES-128-ECB round-trip + all 3 iLink key encodings
        let rawKey = Data((0..<16).map { UInt8($0 + 1) })
        let hexKey = rawKey.map { String(format: "%02x", $0) }.joined()
        let b64OfHex = Data(hexKey.utf8).base64EncodedString()
        let b64OfRaw = rawKey.base64EncodedString()

        #expect(PipiWeChatILinkProtocol.decodeILinkAESKey(hexKey) == rawKey)
        #expect(PipiWeChatILinkProtocol.decodeILinkAESKey(b64OfHex) == rawKey)
        #expect(PipiWeChatILinkProtocol.decodeILinkAESKey(b64OfRaw) == rawKey)

        let plaintext = Data("WeChat rich media payload test 123".utf8)
        let cipher = PipiWeChatILinkProtocol.aes128ECBEncrypt(plaintext, key16: rawKey)
        #expect(cipher != nil)
        let decrypted = cipher.flatMap { PipiWeChatILinkProtocol.aes128ECBDecrypt($0, key16: rawKey) }
        #expect(decrypted == plaintext)

        // 2. Inbound voice (with & without text), image, and file parsing
        let updatesJSON = """
        {
          "ret": 0,
          "get_updates_buf": "buf_99",
          "msgs": [
            {
              "message_id": "v1",
              "message_type": 1,
              "from_user_id": "wx_u1",
              "context_token": "ctx_1",
              "item_list": [
                {
                  "type": 3,
                  "voice_item": {
                    "text": "帮我切换到编程搭档",
                    "playtime": 3200,
                    "media": { "encrypt_query_param": "eqp_v1", "aes_key": "\(b64OfHex)" }
                  }
                }
              ]
            },
            {
              "message_id": "img1",
              "message_type": 1,
              "from_user_id": "wx_u1",
              "context_token": "ctx_2",
              "item_list": [
                {
                  "type": 2,
                  "image_item": {
                    "mid_size": 12000,
                    "media": { "encrypt_query_param": "eqp_img1", "aes_key": "\(b64OfRaw)" }
                  }
                }
              ]
            },
            {
              "message_id": "file1",
              "message_type": 1,
              "from_user_id": "wx_u1",
              "context_token": "ctx_3",
              "item_list": [
                {
                  "type": 4,
                  "file_item": {
                    "file_name": "report.md",
                    "len": "512",
                    "media": { "encrypt_query_param": "eqp_f1", "aes_key": "\(hexKey)" }
                  }
                }
              ]
            }
          ]
        }
        """
        let parsed = PipiWeChatILinkProtocol.parseGetUpdatesResponse(Data(updatesJSON.utf8))
        #expect(parsed.messages.count == 3)
        #expect(parsed.messages[0].hasVoice == true)
        #expect(parsed.messages[0].voiceText == "帮我切换到编程搭档")
        #expect(parsed.messages[1].imageMedias.count == 1)
        #expect(parsed.messages[1].imageMedias[0].encryptQueryParam == "eqp_img1")
        #expect(parsed.messages[2].fileMedias.count == 1)
        #expect(parsed.messages[2].fileMedias[0].fileName == "report.md")

        // 3. Natural language 1v1 intents without false positives
        let bots = [
            PipiWeChatBotInfo(id: "bot_pipi_general", name: "PiPi · 全能助手", role: "助手", modelLabel: "default", permissionTier: .ask),
            PipiWeChatBotInfo(id: "bot_pipi_coder", name: "Coder · 编程搭档", role: "编程", modelLabel: "gpt-4o", permissionTier: .ask)
        ]
        #expect(PipiWeChatIntentParser.parse("菜单", availableBots: bots) == .showMenu)
        #expect(PipiWeChatIntentParser.parse("创建一个叫翻译官的bot", availableBots: bots) == .createBot(prefilledName: "翻译官", prefilledRole: nil))
        #expect(PipiWeChatIntentParser.parse("切换到 Coder", availableBots: bots) == .switchBot(targetQuery: "Coder"))
        #expect(PipiWeChatIntentParser.parse("切换会话", availableBots: bots) == .manageSessions(createNew: false))
        #expect(PipiWeChatIntentParser.parse("新建会话", availableBots: bots) == .manageSessions(createNew: true))
        #expect(PipiWeChatIntentParser.parse("切换项目", availableBots: bots) == .switchProject(targetQuery: nil))
        #expect(PipiWeChatIntentParser.parse("进入群聊模式", availableBots: bots) == .enterGroupMode(memberQuery: "进入群聊模式"))
        #expect(PipiWeChatIntentParser.parse("切回1v1", availableBots: bots) == .exitGroupMode)
        #expect(PipiWeChatIntentParser.parse("更多配置", availableBots: bots) == .showConfig)
        #expect(PipiWeChatIntentParser.parse("检查更新", availableBots: bots) == .checkUpdate)

        // Normal coding/project chat must NOT be hijacked by menu parser!
        #expect(PipiWeChatIntentParser.parse("帮我用 Swift 写一个群聊和项目切换的界面", availableBots: bots) == nil)
    }
}

private final class LockedModelRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [String] = []
    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _values
    }
    func append(_ v: String) {
        lock.lock()
        _values.append(v)
        lock.unlock()
    }
}
