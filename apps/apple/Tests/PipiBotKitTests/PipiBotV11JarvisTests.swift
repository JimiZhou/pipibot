// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Comprehensive tests for v0.11.0 Jarvis Personal Butler upgrade.

import Foundation
import Testing
@testable import PipiBotKit

@Suite("v0.11.0 Jarvis Butler: AES-GCM Vault, Native Tool Loop, Workspace Guardrail, CLI Error Recovery & WeChat Dual-Track")
struct PipiBotV11JarvisTests {

    @Test("Local AES-256-GCM secret vault encrypts on disk with 0600 permissions, blocks tampering, and migrates legacy secrets manually")
    func testLocalEncryptedSecretVault() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipi-vault-test-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vaultURL = tmpDir.appendingPathComponent("vault.enc")
        let vault1 = PipiLocalEncryptedSecretStore(fileURL: vaultURL, machineSeedOverride: "test-mac-seed-alpha")
        vault1.setSecret("sk-super-secret-value-999", for: "llm_primary")
        vault1.setSecret("{\"botToken\":\"wx-tok-777\"}", for: "wechat_ilink_bot_credentials_v1")

        // Verify file exists, has 0600 permissions, and does NOT contain plaintext secret
        let rawBytes = try Data(contentsOf: vaultURL)
        let rawLossy = String(decoding: rawBytes, as: UTF8.self)
        #expect(!rawLossy.contains("sk-super-secret-value-999"))
        #expect(!rawLossy.contains("wx-tok-777"))

        let attrs = try FileManager.default.attributesOfItem(atPath: vaultURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600)

        // Reload with same seed decrypts cleanly
        let vault2 = PipiLocalEncryptedSecretStore(fileURL: vaultURL, machineSeedOverride: "test-mac-seed-alpha")
        #expect(vault2.secret(for: "llm_primary") == "sk-super-secret-value-999")
        #expect(vault2.secret(for: "wechat_ilink_bot_credentials_v1") == "{\"botToken\":\"wx-tok-777\"}")

        // Reload with wrong machine seed cannot decrypt
        let wrongSeedVault = PipiLocalEncryptedSecretStore(fileURL: vaultURL, machineSeedOverride: "different-machine-seed")
        #expect(wrongSeedVault.secret(for: "llm_primary") == nil)

        // Manual migration imports only missing entries from legacy store
        let legacyMock = PipiInMemorySecretStore(initial: [
            "llm_primary": "old-should-not-overwrite",
            "voice_cloud_stt": "sk-voice-imported"
        ])
        let imported = vault2.migrateFromLegacyKeychain(accounts: ["llm_primary", "voice_cloud_stt"], legacyStore: legacyMock)
        #expect(imported == 1)
        #expect(vault2.secret(for: "llm_primary") == "sk-super-secret-value-999")
        #expect(vault2.secret(for: "voice_cloud_stt") == "sk-voice-imported")
    }

    @Test("Workspace-wide autonomous execution guardrail auto-allows workspace writes/read/media and gates outside/destructive/push actions")
    func testWorkspaceWideGuardrailPolicy() {
        let workspace = "/Users/tester/Projects/pipibot"

        // Read-only & media & butler control -> auto-allow
        let listRisk = PipiJarvisToolRiskEvaluator.evaluate(
            toolCall: PipiLLMToolCall(id: "1", name: "list_directory", argumentsJSON: "{\"path\":\"~/Desktop/Projects/FSD\"}"),
            workspaceDirectory: workspace
        )
        #expect(!listRisk.requiresApproval && !listRisk.isHardDenied)

        let voiceRisk = PipiJarvisToolRiskEvaluator.evaluate(
            toolCall: PipiLLMToolCall(id: "2", name: "synthesize_voice", argumentsJSON: "{\"text\":\"早安\"}"),
            workspaceDirectory: workspace
        )
        #expect(!voiceRisk.requiresApproval)

        // Write INSIDE workspace -> auto-allow
        let insideWrite = PipiJarvisToolRiskEvaluator.evaluate(
            toolCall: PipiLLMToolCall(id: "3", name: "write_file", argumentsJSON: "{\"path\":\"/Users/tester/Projects/pipibot/README.md\",\"content\":\"ok\"}"),
            workspaceDirectory: workspace
        )
        #expect(!insideWrite.requiresApproval)

        // Write OUTSIDE workspace -> requires confirmation
        let outsideWrite = PipiJarvisToolRiskEvaluator.evaluate(
            toolCall: PipiLLMToolCall(id: "4", name: "write_file", argumentsJSON: "{\"path\":\"/etc/hosts\",\"content\":\"bad\"}"),
            workspaceDirectory: workspace
        )
        #expect(outsideWrite.requiresApproval && !outsideWrite.isHardDenied)

        // git push & rm -rf -> requires confirmation
        let pushRisk = PipiJarvisToolRiskEvaluator.evaluate(
            toolCall: PipiLLMToolCall(id: "5", name: "run_shell", argumentsJSON: "{\"command\":\"git push origin main\"}"),
            workspaceDirectory: workspace
        )
        #expect(pushRisk.requiresApproval)

        // Catastrophic rm -rf / -> hard denied
        let nukeRisk = PipiJarvisToolRiskEvaluator.evaluate(
            toolCall: PipiLLMToolCall(id: "6", name: "run_shell", argumentsJSON: "{\"command\":\"rm -rf /\"}"),
            workspaceDirectory: workspace
        )
        #expect(nukeRisk.isHardDenied)

        // External outbound mail/SMS -> requires confirmation
        let mailRisk = PipiJarvisToolRiskEvaluator.evaluate(
            toolCall: PipiLLMToolCall(id: "7", name: "send_mail_or_sms", argumentsJSON: "{\"channel\":\"mail\",\"recipient\":\"boss@example.com\",\"body\":\"hi\"}"),
            workspaceDirectory: workspace
        )
        #expect(mailRisk.requiresApproval)
    }

    @Test("Native Jarvis toolbox executes real file/search/shell/visual-card operations and parses inline <pipi_tool> tags")
    func testNativeToolboxAndVisualCard() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipi-toolbox-test-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let deliverablesDir = tmpDir.appendingPathComponent("deliverables", isDirectory: true)
        try FileManager.default.createDirectory(at: deliverablesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try "# FSD Autonomous Driving\nEnd-to-end planner module.\n".write(
            to: tmpDir.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let noopCallbacks = PipiAgentHostCallbacks(
            captureScreenshot: { PipiMacOmnipotentCommandResult(succeeded: true, summary: "ok") },
            recordScreen: { _ in PipiMacOmnipotentCommandResult(succeeded: true, summary: "ok") },
            synthesizeVoice: { _ in PipiMacOmnipotentCommandResult(succeeded: true, summary: "ok") },
            prepareLocalFile: { _ in PipiMacOmnipotentCommandResult(succeeded: true, summary: "ok") },
            registerArtifact: { _ in },
            delegateCLIAgent: { _, _, _, _ in (true, "ok") },
            readCalendarAndReminders: { "none" },
            createRoutineOrReminder: { title, _, _, _ in "created \(title)" },
            readMailOrSMS: { _, _ in "none" },
            sendMailOrSMS: { _, _, _, _ in PipiMacOmnipotentCommandResult(succeeded: true, summary: "ok") },
            showControlMenu: { "menu" },
            listOrSwitchBot: { _ in "bots" },
            createBot: { name, _, _ in "created \(name)" },
            switchSessionOrProject: { _, _ in "switched" },
            configureGroupMode: { _, _ in "group" },
            updateSettings: { _, _ in "updated" },
            checkUpdates: { "up to date" }
        )

        let listRes = await PipiAgentToolbox.execute(
            toolCall: PipiLLMToolCall(id: "t1", name: "list_directory", argumentsJSON: "{\"path\":\"\(tmpDir.path)\"}"),
            workspaceDirectory: tmpDir.path,
            llmConfig: nil,
            deliverablesDirectory: deliverablesDir,
            callbacks: noopCallbacks
        )
        #expect(!listRes.isError)
        #expect(listRes.output.contains("README.md"))

        let readRes = await PipiAgentToolbox.execute(
            toolCall: PipiLLMToolCall(id: "t2", name: "read_file", argumentsJSON: "{\"path\":\"README.md\"}"),
            workspaceDirectory: tmpDir.path,
            llmConfig: nil,
            deliverablesDirectory: deliverablesDir,
            callbacks: noopCallbacks
        )
        #expect(!readRes.isError)
        #expect(readRes.output.contains("End-to-end planner module"))

        let searchRes = await PipiAgentToolbox.execute(
            toolCall: PipiLLMToolCall(id: "t3", name: "search_files", argumentsJSON: "{\"query\":\"planner\"}"),
            workspaceDirectory: tmpDir.path,
            llmConfig: nil,
            deliverablesDirectory: deliverablesDir,
            callbacks: noopCallbacks
        )
        #expect(searchRes.output.contains("README.md"))

        let cardRes = await PipiAgentToolbox.execute(
            toolCall: PipiLLMToolCall(id: "t4", name: "render_visual_card", argumentsJSON: "{\"title\":\"FSD 项目架构\",\"body\":\"• 感知模块\\n• 端到端规划器\"}"),
            workspaceDirectory: tmpDir.path,
            llmConfig: nil,
            deliverablesDirectory: deliverablesDir,
            callbacks: noopCallbacks
        )
        #expect(!cardRes.isError)
        #expect(cardRes.artifacts.count == 1)
        let pngData = try Data(contentsOf: URL(fileURLWithPath: cardRes.artifacts[0].filePath))
        #expect(pngData.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47])) // PNG magic bytes

        // Inline `<pipi_tool>` parser
        let inlineText = "我去看看目录 <pipi_tool name=\"list_directory\">{\"path\":\"~/Desktop/Projects/FSD\"}</pipi_tool>"
        let extracted = PipiAgentToolbox.extractInlineToolCalls(from: inlineText)
        #expect(extracted.calls.count == 1)
        #expect(extracted.calls[0].name == "list_directory")
        #expect(extracted.calls[0].string("path") == "~/Desktop/Projects/FSD")
    }

    @Test("WeChat fuzzy menu recognition, dual-track voice trigger, lively narration, CLI error filtering, and proactive schedule parsing")
    func testWeChatAndButlerHelpers() async {
        // Fuzzy menu match ("菜单给我看看") without false-positiving on design prompts
        #expect(PipiWeChatIntentParser.parse("菜单给我看看") == .showMenu)
        #expect(PipiWeChatIntentParser.parse("你有什么功能") == .showMenu)
        #expect(PipiWeChatIntentParser.parse("帮我用HTML设计一个餐厅菜单页面") == nil)
        #expect(PipiWeChatIntentParser.parse("有没有新版本") == .checkUpdate)

        // Voice reply detection
        #expect(PipiWeChatILinkManager.userRequestedVoiceReply("那你主动发一条语音给我"))
        #expect(PipiWeChatILinkManager.userRequestedVoiceReply("用语音告诉我今天的安排"))
        #expect(!PipiWeChatILinkManager.userRequestedVoiceReply("帮我看看 FSD 目录"))

        // Lively companion progress narrator
        let ack = PipiLivelyProgressNarrator.initialAck(for: "桌面上的Projects里面的FSD目录你帮我研究一下", lang: .zhHans)
        #expect(ack.contains("👀"))
        let stepNote = PipiLivelyProgressNarrator.narrateToolStep(
            PipiLLMToolCall(id: "s1", name: "list_directory", argumentsJSON: "{\"path\":\"~/Desktop/Projects/FSD\"}"),
            stepIndex: 1,
            lang: .zhHans
        )
        #expect(stepNote.contains("FSD"))

        // CLI stderr noise filtering
        let noisyStderr = """
        Reading additional input from stdin...
        OpenAI Codex v0.45.0
        workdir: /tmp
        ERROR: upstream MCP connection timed out
        """
        let cleanErr = PipiInferenceEngine.extractMeaningfulCLIError(stdout: "", stderr: noisyStderr)
        #expect(!cleanErr.contains("Reading additional input from stdin"))
        #expect(cleanErr.contains("upstream MCP connection timed out"))

        // Natural-language schedule parser & briefing builder
        let oneShot = PipiScheduleParser.parseIntervalMinutes(from: "30分钟后提醒我开会")
        #expect(oneShot.minutes == 30 && oneShot.isOneShot)
        let daily = PipiScheduleParser.parseIntervalMinutes(from: "每天早上9点发早报")
        #expect(daily.minutes == 1440 && !daily.isOneShot)
        let briefing = await PipiProactiveButler.buildDailyBriefing(
            calendarSummary: "• 10:00 产品评审",
            workspaceDirectory: FileManager.default.temporaryDirectory.path,
            recentFailedRunsCount: 0
        )
        #expect(briefing.contains("10:00 产品评审"))
    }
}
