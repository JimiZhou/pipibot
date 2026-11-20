// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.

import Foundation
import Testing
@testable import PipiBotKit

@Suite("Remote Control (Cloudflare PWA & WeChat iLink) + macOS Omnipotent Engine")
struct PipiRemoteAndOmnipotentTests {
    @Test("Cloudflare Quick Tunnel URL extraction and authenticated URL formatting")
    func testCloudflareTunnelURLParsing() {
        let sampleLog = """
        2026-11-20T08:15:10Z INF +--------------------------------------------------------------------------------------------+
        2026-11-20T08:15:10Z INF |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |
        2026-11-20T08:15:10Z INF |  https://porcelain-agent-4219.trycloudflare.com                                            |
        2026-11-20T08:15:10Z INF +--------------------------------------------------------------------------------------------+
        """
        let extracted = PipiCloudflareTunnelManager.extractTryCloudflareURL(from: sampleLog)
        #expect(extracted == "https://porcelain-agent-4219.trycloudflare.com")

        let authURL = PipiCloudflareTunnelManager.buildAuthenticatedRemoteURL(
            tunnelBaseURL: "https://porcelain-agent-4219.trycloudflare.com/",
            accessToken: "abc123token"
        )
        #expect(authURL == "https://porcelain-agent-4219.trycloudflare.com/?token=abc123token")
        #expect(PipiCloudflareTunnelManager.extractTryCloudflareURL(from: "no url here") == nil)
    }

    @Test("Remote PWA HTTP server enforces token auth, serves PWA manifest, and streams media")
    func testRemotePWAServerRoutesAndAuth() async {
        let samplePNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let bridge = PipiRemoteControlBridge(
            fetchSnapshot: { _ in
                PipiRemoteControlSnapshot(
                    hostName: "Jimi-Mac",
                    appVersion: "0.9.0",
                    activeModelLabel: "OpenAI · gpt-4o",
                    language: "zh-Hans",
                    bots: [PipiRemoteBotDTO(id: "pipi", name: "PiPiBot", role: "主助手", isRunning: false, skillCount: 3)],
                    conversations: [],
                    selectedConversationId: nil,
                    messages: [],
                    isSelectedConversationRunning: false,
                    pendingItems: []
                )
            },
            sendMessage: { convId, _, _ in convId ?? "conv_new_1" },
            createConversation: { _ in "conv_new_2" },
            stopGeneration: { _ in },
            resolvePending: { _, _, _, _ in true },
            loadDeliverableData: { id in
                id == "shot_1" ? (data: samplePNG, mimeType: "image/png", fileName: "shot.png") : nil
            }
        )

        let server = PipiRemotePWAServer(bridge: bridge, accessToken: "secret_tok_99")

        // 1. Index HTML & PWA tags
        let htmlResp = await server.processRawHTTPRequest(Data("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8))
        let htmlText = String(decoding: htmlResp, as: UTF8.self)
        #expect(htmlText.contains("HTTP/1.1 200 OK"))
        #expect(htmlText.contains("apple-mobile-web-app-capable"))
        #expect(htmlText.contains("/manifest.webmanifest"))

        // 2. Web App Manifest
        let manifestResp = await server.processRawHTTPRequest(Data("GET /manifest.webmanifest HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8))
        let manifestText = String(decoding: manifestResp, as: UTF8.self)
        #expect(manifestText.contains("HTTP/1.1 200 OK"))
        #expect(manifestText.contains("\"display\": \"standalone\""))

        // 3. Unauthorized /api/state -> 401
        let unauthResp = await server.processRawHTTPRequest(Data("GET /api/state HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8))
        #expect(String(decoding: unauthResp, as: UTF8.self).contains("HTTP/1.1 401 Unauthorized"))

        // 4. Authorized /api/state -> 200 with hostName
        let authResp = await server.processRawHTTPRequest(
            Data("GET /api/state HTTP/1.1\r\nHost: localhost\r\nX-PipiBot-Token: secret_tok_99\r\n\r\n".utf8)
        )
        let authText = String(decoding: authResp, as: UTF8.self)
        #expect(authText.contains("HTTP/1.1 200 OK"))
        #expect(authText.contains("Jimi-Mac"))

        // 5. Media endpoint strictly protected
        let unauthMedia = await server.processRawHTTPRequest(Data("GET /api/media/shot_1 HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8))
        #expect(String(decoding: unauthMedia, as: UTF8.self).contains("HTTP/1.1 401 Unauthorized"))

        let authMedia = await server.processRawHTTPRequest(
            Data("GET /api/media/shot_1?token=secret_tok_99 HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)
        )
        let authMediaHeader = String(decoding: authMedia.prefix(240), as: UTF8.self)
        #expect(authMediaHeader.contains("HTTP/1.1 200 OK"))
        #expect(authMediaHeader.contains("Content-Type: image/png"))

        // 6. Send chat message via POST
        let body = #"{"text":"/screenshot","personaId":"pipi"}"#
        let sendReq = "POST /api/chat/send HTTP/1.1\r\nHost: localhost\r\nX-PipiBot-Token: secret_tok_99\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let sendResp = await server.processRawHTTPRequest(Data(sendReq.utf8))
        let sendText = String(decoding: sendResp, as: UTF8.self)
        #expect(sendText.contains("HTTP/1.1 200 OK"))
        #expect(sendText.contains("conv_new_1"))
    }

    @Test("WeChat iLink 1v1 default mode vs prefix-based group mode routing and formatting")
    func testWeChatILinkRoutingAndFormatting() {
        let bots = [
            PipiWeChatBotCandidate(id: "main", name: "PiPiBot"),
            PipiWeChatBotCandidate(id: "arch", name: "架构师"),
            PipiWeChatBotCandidate(id: "res", name: "研究员")
        ]

        // Default 1v1 routes directly to primary bot with no extra prefix
        let direct = PipiWeChatILinkProtocol.resolveRoute(
            text: "帮我查一下今天日程",
            mode: .directMainBot,
            primaryBotId: "main",
            groupMemberIds: ["main", "arch"],
            allBots: bots
        )
        #expect(direct.targetBotIds == ["main"])
        #expect(direct.cleanedPrompt == "帮我查一下今天日程")
        #expect(
            PipiWeChatILinkProtocol.formatOutboundText("今日无冲突日程。", botName: "PiPiBot", mode: .directMainBot)
                == "今日无冲突日程。"
        )

        // Group mode routes general message to group roster and adds 【BotName】 prefix on replies
        let groupBroadcast = PipiWeChatILinkProtocol.resolveRoute(
            text: "评估一下发布方案",
            mode: .groupPrefixMode,
            primaryBotId: "main",
            groupMemberIds: ["main", "arch"],
            allBots: bots
        )
        #expect(groupBroadcast.targetBotIds == ["main", "arch"])
        #expect(
            PipiWeChatILinkProtocol.formatOutboundText("建议先跑回归测试。", botName: "架构师", mode: .groupPrefixMode)
                == "【架构师】\n建议先跑回归测试。"
        )

        // Explicit @mention routes to specific agent in either mode
        let mention = PipiWeChatILinkProtocol.resolveRoute(
            text: "@研究员 汇总一下 iLink 协议字段",
            mode: .groupPrefixMode,
            primaryBotId: "main",
            groupMemberIds: ["main", "arch"],
            allBots: bots
        )
        #expect(mention.targetBotIds == ["res"])
        #expect(mention.cleanedPrompt == "汇总一下 iLink 协议字段")
        #expect(mention.isExplicitMention == true)
    }

    @Test("WeChat iLink getupdates parser and AES-128-ECB media encryption")
    func testWeChatILinkParserAndCrypto() {
        let json = """
        {
          "ret": 0,
          "get_updates_buf": "cursor_42",
          "msgs": [
            {
              "message_id": "m1",
              "message_type": 1,
              "from_user_id": "wx_user_001",
              "context_token": "ctx_abc",
              "item_list": [{ "type": 1, "text_item": { "text": "截屏发给我" } }]
            },
            {
              "message_id": "m2",
              "message_type": 2,
              "from_user_id": "bot",
              "context_token": "ctx_abc",
              "item_list": [{ "type": 1, "text_item": { "text": "echo" } }]
            }
          ]
        }
        """
        let parsed = PipiWeChatILinkProtocol.parseGetUpdatesResponse(Data(json.utf8))
        #expect(parsed.errCode == 0)
        #expect(parsed.nextCursor == "cursor_42")
        #expect(parsed.messages.count == 1)
        #expect(parsed.messages[0].text == "截屏发给我")
        #expect(parsed.messages[0].contextToken == "ctx_abc")

        let expired = PipiWeChatILinkProtocol.parseGetUpdatesResponse(Data(#"{"errcode":-14}"#.utf8))
        #expect(expired.errCode == -14)

        let key16 = Data(repeating: 0x2A, count: 16)
        let cipher = PipiWeChatILinkProtocol.aes128ECBEncrypt(Data("hello pipibot media".utf8), key16: key16)
        #expect(cipher != nil)
        #expect((cipher?.count ?? 0) % 16 == 0)
        #expect((cipher?.count ?? 0) >= 32)
    }

    @Test("macOS Omnipotent Intent Parser, Deliverable MIME mapping & QR image generation")
    func testOmnipotentIntentAndQRCode() {
        #expect(PipiMacOmnipotentIntentParser.parse("/screenshot") == .screenshot)
        #expect(PipiMacOmnipotentIntentParser.parse("帮我截屏") == .screenshot)
        #expect(PipiMacOmnipotentIntentParser.parse("/record 8") == .recordScreen(seconds: 8))
        #expect(PipiMacOmnipotentIntentParser.parse("查一下最近短信") == .readSMS(limit: 8))
        #expect(PipiMacOmnipotentIntentParser.parse("查一下最近邮件") == .readMail(limit: 8))
        #expect(PipiMacOmnipotentIntentParser.parse("/build swift test") == .runCommand(command: "swift test"))
        #expect(PipiMacOmnipotentIntentParser.parse("/sendfile ~/Desktop/app.zip") == .sendFile(path: "~/Desktop/app.zip"))
        #expect(PipiMacOmnipotentIntentParser.parse("/voiceclip 编译已完成") == .voiceClip(text: "编译已完成"))

        let png = PipiDeliverableArtifact.inferKindAndMime(for: "/tmp/shot.png")
        #expect(png.0 == .image && png.0.iLinkMediaType == 1)
        let mp4 = PipiDeliverableArtifact.inferKindAndMime(for: "/tmp/rec.mp4")
        #expect(mp4.0 == .video && mp4.0.iLinkMediaType == 2)
        let zip = PipiDeliverableArtifact.inferKindAndMime(for: "/tmp/dist.zip")
        #expect(zip.0 == .file && zip.0.iLinkMediaType == 3)
        let m4a = PipiDeliverableArtifact.inferKindAndMime(for: "/tmp/voice.m4a")
        #expect(m4a.0 == .audio && m4a.0.iLinkMediaType == 4)

        let qrImg = PipiQRCodeView.makeCGImage(from: "https://example.trycloudflare.com/?token=test")
        #expect(qrImg != nil)
    }

    @Test("Local model platform discovery parsers for Ollama, OpenAI /v1/models, and MLX cache")
    func testLocalModelPlatformParsers() throws {
        let ollamaJSON = #"{"models":[{"name":"qwen2.5:14b"},{"name":"deepseek-r1:8b"}]}"#
        let ollamaModels = PipiLocalModelPlatformManager.parseOllamaTagsJSON(Data(ollamaJSON.utf8))
        #expect(ollamaModels == ["qwen2.5:14b", "deepseek-r1:8b"])

        let openaiJSON = #"{"data":[{"id":"lmstudio-community/Qwen2.5-7B-Instruct-GGUF"},{"id":"llama-3.2-3b"}]}"#
        let openaiModels = PipiLocalModelPlatformManager.parseOpenAIModelsJSON(Data(openaiJSON.utf8))
        #expect(openaiModels == ["lmstudio-community/Qwen2.5-7B-Instruct-GGUF", "llama-3.2-3b"])

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pipi-mlx-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir.appendingPathComponent("models--mlx-community--Qwen2.5-7B-4bit"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmpDir.appendingPathComponent("models--openai--whisper-small"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let mlxModels = PipiLocalModelPlatformManager.scanLocalMLXModels(in: tmpDir)
        #expect(mlxModels == ["mlx-community/Qwen2.5-7B-4bit"])
    }

    @Test("System telemetry monitor computes TTFT, output latency, throughput, and live hardware snapshot")
    @MainActor
    func testTelemetryMonitorLatencyAndSampling() {
        let t0 = Date(timeIntervalSince1970: 1000.0)
        let tFirst = Date(timeIntervalSince1970: 1000.32)
        let tEnd = Date(timeIntervalSince1970: 1002.32)
        let metrics = PipiSystemTelemetryMonitor.computeMetrics(
            engineLabel: "Ollama · qwen2.5:14b",
            startedAt: t0,
            firstTokenAt: tFirst,
            finishedAt: tEnd,
            inputTokensEstimate: 420,
            outputTokensEstimate: 100,
            succeeded: true
        )
        #expect(metrics.inputLatencyMs == 320)
        #expect(metrics.outputLatencyMs == 2000)
        #expect(metrics.totalLatencyMs == 2320)
        #expect(metrics.tokensPerSecond == 50.0)

        let monitor = PipiSystemTelemetryMonitor()
        monitor.sampleNow()
        #expect(monitor.snapshot.memoryTotalGB >= 1.0)
        #expect(monitor.snapshot.cpuUsagePercent >= 0.0 && monitor.snapshot.cpuUsagePercent <= 100.0)
        #expect(!monitor.cpuHistory.isEmpty)
    }

    @Test("Dynamic sidebar conversation status tracks unread, failed, needsApproval, and clears on select")
    @MainActor
    func testConversationRowDynamicStatus() {
        let store = PipiAppStore(autoConnect: false, enableNativeRuntime: false, seedDemoData: false)
        let conv = store.createConversation(title: "背景任务", activate: false)
        store.currentlyVisibleSessionId = "some_other_conv"

        // Unread status when background conversation updates
        store.unreadConversationCounts[conv.id] = 2
        #expect(store.conversationRowStatus(for: conv) == .unread(2))

        // Selecting clears unread back to idle
        store.selectConversation(conv.id)
        #expect(store.unreadCount(forConversation: conv.id) == 0)
        #expect(store.conversationRowStatus(for: conv) == .idle)

        // Failed state surfaces clearly
        var failedConv = conv
        failedConv.state = .failed
        #expect(store.conversationRowStatus(for: failedConv) == .failed)

        // Needs approval takes precedence over idle/unread
        var approvalConv = conv
        approvalConv.state = .needsYou
        #expect(store.conversationRowStatus(for: approvalConv) == .needsApproval)
    }

    @Test("PiPi built-in engine routes external CLI agents on-demand and resolves hardware-planned local deploy")
    @MainActor
    func testPiPiEngineExternalSubAgentsAndPlannedDeploy() {
        let claude = PipiExternalSubAgentRouter.parseOnDemandInvocation("/claude 修复构建告警")
        #expect(claude?.kind == .claudeCode && claude?.taskPrompt == "修复构建告警")

        let codex = PipiExternalSubAgentRouter.parseOnDemandInvocation("/codex refactor router")
        #expect(codex?.kind == .codex && codex?.taskPrompt == "refactor router")

        let opencode = PipiExternalSubAgentRouter.parseOnDemandInvocation("/opencode audit tests")
        #expect(opencode?.kind == .opencode && opencode?.taskPrompt == "audit tests")

        #expect(PipiExternalSubAgentRouter.parseOnDemandInvocation("普通对话消息") == nil)

        // Hardware-planned model resolves to installed Ollama when PolyStrata is absent
        let plannedEntry = PipiModelAutopilot.catalog.first!
        let installedOnlyOllama = [
            PipiLocalPlatformStatus(kind: .ollama, installed: true, running: true, baseURL: "http://127.0.0.1:11434")
        ]
        let resolved = PipiLocalModelPlatformManager.resolveDeploymentTarget(
            for: plannedEntry,
            preferredPlatform: nil,
            installed: installedOnlyOllama
        )
        #expect(resolved.platform == .ollama)
        #expect(!resolved.modelTag.isEmpty)

        // PiPi label always surfaces PiPi as the built-in execution engine
        let store = PipiAppStore(autoConnect: false, enableNativeRuntime: false, seedDemoData: false)
        let cfg = PipiLLMProviderConfig(
            id: "openai_test",
            name: "OpenAI",
            kind: .openai,
            baseURL: "https://api.openai.com/v1",
            apiKey: "sk-test-1234",
            modelId: "gpt-4o",
            isEnabled: true
        )
        store.upsertLLMProvider(cfg, setAsDefault: true)
        #expect(store.activeEngineDisplayLabel().hasPrefix("PiPi · "))
    }

    @Test("Real TCC file open check, permission onboarding hints, and Guided Setup step re-entry")
    @MainActor
    func testPermissionProbingAndGuidedSetupReentry() throws {
        // Real POSIX open+read returns false for non-existent path and true for readable file
        let missingPath = "/tmp/pipibot-nonexistent-\(UUID().uuidString).db"
        #expect(PipiMacOmnipotentEngine.canActuallyOpenProtectedFile(atPath: missingPath) == false)

        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("pipi-fda-test-\(UUID().uuidString).txt")
        try "ok".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }
        #expect(PipiMacOmnipotentEngine.canActuallyOpenProtectedFile(atPath: tmpFile.path) == true)

        // Onboarding metadata flags & localized action hints
        #expect(PipiMacPermissionKind.fullDiskMessages.requiresManualAddInSettings == true)
        #expect(PipiMacPermissionKind.fullDiskMessages.requiresRelaunchAfterGrant == true)
        #expect(PipiMacPermissionKind.screenRecording.requiresRelaunchAfterGrant == true)
        #expect(PipiMacPermissionKind.accessibility.requiresManualAddInSettings == false)
        for kind in PipiMacPermissionKind.allCases {
            #expect(!kind.onboardingActionHint(.zhHans).isEmpty)
            #expect(!kind.onboardingActionHint(.en).isEmpty)
        }

        // Guided setup step targeting & clamping
        let store = PipiAppStore(autoConnect: false, enableNativeRuntime: false, seedDemoData: false)
        store.completeOnboarding()
        #expect(store.hasCompletedOnboarding == true)
        store.reopenOnboarding(atStep: 2)
        #expect(store.hasCompletedOnboarding == false)
        #expect(store.onboardingInitialStep == 2)
        store.reopenOnboarding(atStep: 99)
        #expect(store.onboardingInitialStep == 3)
    }

    @Test("3D Home Scene presets and multi-room bot assignments persist cleanly across reload")
    @MainActor
    func testHomeScenePresetsAndRoomAssignmentsPersistence() throws {
        let tmpStateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipi-3d-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpStateURL) }

        #expect(PipiHomeScenePreset.allCases.count == 4)
        #expect(PipiHomeRoomKind.allCases.count == 4)

        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            stateFileUrl: tmpStateURL,
            seedDemoData: false,
            saveDebounceMilliseconds: 0
        )
        #expect(store.homeScenePreset == .warmStudio)
        #expect(store.assignedRoom(for: "bot_pipi_coder") == .studio)
        #expect(store.assignedRoom(for: "bot_pipi_general") == .lounge)

        store.setHomeScenePreset(.cyberCommand)
        store.assignBot("bot_pipi_general", to: .lab)
        store.assignBot("bot_pipi_coder", to: .collab)
        store.flush()

        let reloaded = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            stateFileUrl: tmpStateURL,
            seedDemoData: false,
            saveDebounceMilliseconds: 0
        )
        #expect(reloaded.homeScenePreset == .cyberCommand)
        #expect(reloaded.assignedRoom(for: "bot_pipi_general") == .lab)
        #expect(reloaded.assignedRoom(for: "bot_pipi_coder") == .collab)
    }
}
