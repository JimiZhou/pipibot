import Foundation
import Testing
@testable import PipiBotKit

@Suite("Multi-Voice Timbre, Live Phone Call & Autonomous Bot Capability Mesh")
struct PipiBotCapabilityAndVoiceTests {

    @Test("Multi-voice catalog resolves timbres, removes Muse wording, and supports per-agent override")
    @MainActor
    func testMultiVoiceTimbreAndNoMuseCopy() {
        #expect(!PipiVoiceInteractionMode.museHandsFree.label(.zhHans).contains("Muse"))
        #expect(!PipiVoiceInteractionMode.museHandsFree.label(.en).contains("Muse"))
        #expect(PipiVoiceInteractionMode.museHandsFree.label(.zhHans) == "语音通话")
        #expect(PipiVoiceInteractionMode.museHandsFree.label(.en) == "Voice Call")

        let timbres = PipiDailyVoiceEngine.availableVoiceTimbres()
        #expect(timbres.count >= PipiVoiceTimbreOption.builtInPresets.count)

        let store = PipiAppStore(autoConnect: false, enableNativeRuntime: false, enableEmbeddedBridge: false, seedDemoData: false)
        // Default PiPi uses its dedicated voice; custom bot without voice falls back to global config
        var cfg = store.voiceConfig
        cfg.selectedVoiceProfileId = "timbre_calm_zh"
        store.updateVoiceConfig(cfg)

        let customBot = PipiBotPersona(
            id: "bot_custom_voice_test",
            nameZh: "测试助手",
            nameEn: "Test Bot",
            roleZh: "测试",
            roleEn: "Test",
            greetingZh: "你好",
            greetingEn: "Hi",
            systemPrompt: "Test",
            voiceProfileId: nil
        )
        store.upsertPersona(customBot)
        #expect(store.effectiveVoiceProfileId(for: customBot.id) == "timbre_calm_zh")

        var dedicated = customBot
        dedicated.voiceProfileId = "timbre_en_deep"
        store.upsertPersona(dedicated)
        #expect(store.effectiveVoiceProfileId(for: customBot.id) == "timbre_en_deep")
    }

    @Test("Global capability pool inheritance and autonomous bot-to-bot on-demand capability upgrade")
    @MainActor
    func testGlobalSharingAndAutonomousPeerUpgrade() {
        let store = PipiAppStore(autoConnect: false, enableNativeRuntime: false, enableEmbeddedBridge: false, seedDemoData: false)
        // Ensure PiPi starts without terminal_cli / local_git while Coder has them and allows sharing
        guard var pipi = store.personas.first(where: { $0.id == "bot_pipi_general" }) else {
            Issue.record("Missing built-in PiPi persona")
            return
        }
        pipi.enabledTools = [PipiBotToolKind.personalWiki.rawValue]
        pipi.enabledConnectors = []
        pipi.assignedSkillSlugs = ["personal-profile"]
        pipi.sharingPolicy.allowPeerUpgrade = true
        store.upsertPersona(pipi)

        // Effective capabilities inherit global shared pool
        let beforeCaps = store.effectiveCapabilities(for: pipi.id)
        #expect(beforeCaps.connectors.contains(PipiBotConnectorKind.appleCalendar.rawValue))
        #expect(!beforeCaps.tools.contains(PipiBotToolKind.terminalCli.rawValue))

        // On-demand upgrade when PiPi receives a code/git task: autonomously learns from Coder
        let outcome = store.evaluatePeerUpgradeForPrompt(botId: pipi.id, prompt: "帮我检查 git 代码并修复 bug")
        #expect(outcome != nil)
        #expect(!(outcome?.newUpgrades.isEmpty ?? true))

        let upgradedPipi = store.personas.first(where: { $0.id == pipi.id })!
        #expect(upgradedPipi.enabledTools.contains(PipiBotToolKind.terminalCli.rawValue))
        #expect(upgradedPipi.enabledConnectors.contains(PipiBotConnectorKind.localGit.rawValue))
        #expect(upgradedPipi.learnedUpgrades.contains(where: { $0.fromBotId == "bot_pipi_coder" }))

        // Verify sharing opt-out is strictly respected
        guard var writer = store.personas.first(where: { $0.id == "bot_pipi_writer" }) else { return }
        writer.sharingPolicy.shareSkills = false
        store.upsertPersona(writer)

        let pptOutcome = store.evaluatePeerUpgradeForPrompt(botId: pipi.id, prompt: "帮我做一份 PPT 幻灯片汇报")
        let learnedPptxFromWriter = pptOutcome?.newUpgrades.contains(where: { $0.fromBotId == "bot_pipi_writer" && $0.capabilityId == "pptx" }) ?? false
        #expect(!learnedPptxFromWriter)
    }

    @Test("Live Voice Call state transitions cleanly between active, muted, and ended")
    @MainActor
    func testVoiceCallLifecycle() {
        let store = PipiAppStore(autoConnect: false, enableNativeRuntime: false, enableEmbeddedBridge: false, seedDemoData: false)
        store.isVoiceCallActive = true
        store.voiceCallPersonaId = "bot_pipi_coder"
        store.voiceCallStartedAt = Date()
        store.isVoiceCallMuted = false

        store.toggleVoiceCallMute()
        #expect(store.isVoiceCallMuted == true)

        store.endVoiceCall()
        #expect(store.isVoiceCallActive == false)
        #expect(store.voiceCallStartedAt == nil)
        #expect(store.voiceCallPersonaId == nil)
        #expect(store.voiceSessionState == .idle)
    }
}
