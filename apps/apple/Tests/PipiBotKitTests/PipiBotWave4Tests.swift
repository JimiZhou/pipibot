import Foundation
import Testing
@testable import PipiBotKit

@Suite("Wave 4 — #07 Hardware Autopilot + PolyStrata + Loopback Gateway + #10 Personal Daily Voice")
struct PipiBotWave4Tests {

    private func makeSineFrame(amplitude: Float, freqHz: Double = 280, sampleRate: Double = 16_000, count: Int = 320) -> [Float] {
        (0..<count).map { i in
            amplitude * Float(sin((2.0 * Double.pi * freqHz * Double(i)) / sampleRate))
        }
    }

    @Test("#07a: 5-layer Model Autopilot, 12+ PolyStrata MoE catalog & Real-QA self-test gate")
    func testModelAutopilotAndQAGate() async throws {
        // Must provide >= 12 PolyStrata MoE models covering Apple Silicon beta & PipiFleet Linux/Win
        #expect(PipiModelAutopilot.polyStrataMoECatalog.count >= 12)
        #expect(PipiModelAutopilot.catalog.count >= 15)

        // 1. Apple Silicon 16 GB -> 64K Spark-X2.6-4B
        let mac16 = PipiHardwareProfile(
            platformClass: .macosAppleSilicon,
            cpuModel: "Apple M4",
            cpuCores: 10,
            totalRamGb: 16,
            availableRamGb: 11,
            gpuVramGb: 12,
            unifiedMemory: true,
            freeDiskGb: 120,
            isAppleSilicon: true,
            isFleetNode: false
        )
        let plan16 = PipiModelAutopilot.plan(hardware: mac16)
        #expect(plan16.primaryModel.id == "spark-x2.6-4b-q4_k_m")
        #expect(plan16.plannedContextWindow >= 65_536)
        #expect(plan16.companionBudget.canRunOnDeviceVoiceModel == true)

        // 2. Apple Silicon 32 GB -> Qwen3.8-27B 128K
        let mac32 = PipiHardwareProfile(
            platformClass: .macosAppleSilicon,
            cpuModel: "Apple M4 Pro",
            cpuCores: 14,
            totalRamGb: 32,
            availableRamGb: 24,
            gpuVramGb: 24,
            unifiedMemory: true,
            freeDiskGb: 256,
            isAppleSilicon: true,
            isFleetNode: false
        )
        let plan32 = PipiModelAutopilot.plan(hardware: mac32)
        #expect(plan32.primaryModel.id == "qwen3.8-27b-ud-q4_k_m")
        #expect(plan32.plannedContextWindow == 131_072)

        // 3. Apple Silicon 64 GB -> unlocks PolyStrata Metal+SSD beta MoE
        let mac64 = PipiHardwareProfile(
            platformClass: .macosAppleSilicon,
            cpuModel: "Apple M4 Max",
            cpuCores: 16,
            totalRamGb: 64,
            availableRamGb: 52,
            gpuVramGb: 48,
            unifiedMemory: true,
            freeDiskGb: 500,
            isAppleSilicon: true,
            isFleetNode: false
        )
        let plan64 = PipiModelAutopilot.plan(hardware: mac64, enableMacPolyStrataBeta: true)
        #expect(plan64.selectedEngine == .polystrata)
        #expect(plan64.polyStrataMode == .appleMetalSsdBeta)
        let spec64 = PipiModelAutopilot.buildLaunchSpec(plan: plan64, modelArtifactPath: "/models/moe.gguf")
        #expect(spec64.commandLine.contains("--metal-ssd-prefetch"))

        // 4. PipiFleet Linux NVIDIA 12 GB + 32 GB -> PolyStrata Qwen3.8-Flash-Next
        let fleet12 = PipiHardwareProfile(
            platformClass: .linuxNvidia,
            cpuModel: "AMD Ryzen 9",
            cpuCores: 16,
            totalRamGb: 32,
            availableRamGb: 26,
            gpuVramGb: 12,
            unifiedMemory: false,
            freeDiskGb: 300,
            isAppleSilicon: false,
            isFleetNode: true
        )
        let planFleet = PipiModelAutopilot.plan(hardware: fleet12)
        #expect(planFleet.selectedEngine == .polystrata)
        #expect(planFleet.primaryModel.id == "qwen3.8-flash-next-polystrata")
        #expect(planFleet.polyStrataMode == .cudaSsdPaging || planFleet.polyStrataMode == .cudaRamExpertOffload)

        // 5. Real-QA self-test verification gate (deterministic offline transport)
        let qaPass = await PipiModelAutopilot.verifyModelWithQA(
            endpointUrl: "http://127.0.0.1:11438/v1",
            modelId: plan32.primaryModel.id
        ) { _ in
            let body: [String: Any] = [
                "choices": [["message": ["content": "PIPI_QA_42 -> 42"]]],
                "usage": ["completion_tokens": 12]
            ]
            let data = try JSONSerialization.data(withJSONObject: body)
            return (data, 200)
        }
        #expect(qaPass.verified == true)
        #expect(qaPass.status == .verified)
        #expect(qaPass.estimatedTokPerSec > 0)

        let qaFail = await PipiModelAutopilot.verifyModelWithQA(
            endpointUrl: "http://127.0.0.1:11438/v1",
            modelId: plan32.primaryModel.id
        ) { _ in
            let body: [String: Any] = [
                "choices": [["message": ["content": "garbage response without nonce"]]]
            ]
            return (try JSONSerialization.data(withJSONObject: body), 200)
        }
        #expect(qaFail.verified == false)
        #expect(qaFail.status == .failed)
    }

    @Test("#07b: Loopback Gateway (OpenAI <-> Anthropic JSON/SSE) + Isolated CLI Reverse-Injection")
    func testLoopbackGatewayAndIsolatedOverlays() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-wave4-gw-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let upstream = PipiGatewayUpstreamTarget(
            sourceMode: .localModel,
            dialect: .openai,
            baseURL: "http://127.0.0.1:11438/v1",
            modelId: "qwen3.8-27b-ud-q4_k_m",
            contextWindow: 131_072
        )

        let gateway = PipiLocalLLMGateway(upstream: upstream, gatewayToken: "pipi_gw_test_secret") { req in
            let reqBody = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any]) ?? [:]
            let msgs = (reqBody["messages"] as? [[String: Any]]) ?? []
            let lastContent = (msgs.last?["content"] as? String) ?? ""
            let reply: [String: Any] = [
                "id": "cmpl_mock",
                "object": "chat.completion",
                "model": "qwen3.8-27b-ud-q4_k_m",
                "choices": [[
                    "index": 0,
                    "message": ["role": "assistant", "content": "UpstreamEcho:\(lastContent)"],
                    "finish_reason": "stop"
                ]],
                "usage": ["prompt_tokens": 10, "completion_tokens": 8, "total_tokens": 18]
            ]
            return (try JSONSerialization.data(withJSONObject: reply), 200)
        }

        let status = try await gateway.start(port: 0)
        defer { Task { await gateway.stop() } }
        #expect(status.isRunning == true)
        #expect(status.origin.hasPrefix("http://127.0.0.1:"))

        // 1. Unauthorized call returns 401
        var unauthReq = URLRequest(url: URL(string: "\(status.origin)/v1/models")!)
        unauthReq.httpMethod = "GET"
        let (_, unauthResp) = try await URLSession.shared.data(for: unauthReq)
        #expect((unauthResp as? HTTPURLResponse)?.statusCode == 401)

        // 2. Anthropic /anthropic/v1/messages (Claude Code CLI format) translated cleanly to OpenAI upstream
        var antReq = URLRequest(url: URL(string: "\(status.origin)/anthropic/v1/messages")!)
        antReq.httpMethod = "POST"
        antReq.setValue("pipi_gw_test_secret", forHTTPHeaderField: "x-api-key")
        antReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        antReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-sonnet-4",
            "system": "Be crisp",
            "messages": [["role": "user", "content": "ping-claude-via-local"]]
        ])
        let (antData, antResp) = try await URLSession.shared.data(for: antReq)
        #expect((antResp as? HTTPURLResponse)?.statusCode == 200)
        let antJson = try JSONSerialization.jsonObject(with: antData) as? [String: Any]
        #expect(antJson?["type"] as? String == "message")
        let antText = PipiGatewayProtocolTranslator.flattenContent(antJson?["content"])
        #expect(antText == "UpstreamEcho:ping-claude-via-local")

        // 3. Anthropic SSE stream mode
        var sseReq = antReq
        sseReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-sonnet-4",
            "stream": true,
            "messages": [["role": "user", "content": "sse-ok"]]
        ])
        let (sseData, sseResp) = try await URLSession.shared.data(for: sseReq)
        #expect((sseResp as? HTTPURLResponse)?.statusCode == 200)
        let sseText = String(decoding: sseData, as: UTF8.self)
        #expect(sseText.contains("event: content_block_delta"))
        #expect(sseText.contains("UpstreamEcho:sse-ok"))

        // 4. Isolated CLI Reverse-Injection overlays never touch ~/.claude or ~/.codex
        let claudeOverlay = try await gateway.prepareOverlay(dataRootURL: tmpDir, cli: .claudeCode, profileId: "conv_1")
        #expect(claudeOverlay.environment["CLAUDE_CONFIG_DIR"]?.hasPrefix(tmpDir.path) == true)
        #expect(claudeOverlay.environment["ANTHROPIC_BASE_URL"] == "\(status.origin)/anthropic")
        #expect(claudeOverlay.environment["ANTHROPIC_AUTH_TOKEN"] == "pipi_gw_test_secret")

        let codexOverlay = try await gateway.prepareOverlay(dataRootURL: tmpDir, cli: .codex, profileId: "conv_1")
        #expect(codexOverlay.environment["CODEX_HOME"]?.hasPrefix(tmpDir.path) == true)
        let codexToml = try String(contentsOf: codexOverlay.configFilesWritten[0], encoding: .utf8)
        #expect(codexToml.contains("base_url = \"\(status.origin)/v1\""))

        let piOverlay = try await gateway.prepareOverlay(dataRootURL: tmpDir, cli: .pi, profileId: "conv_1")
        #expect(piOverlay.environment["PI_CODING_AGENT_DIR"]?.hasPrefix(tmpDir.path) == true)
    }

    @Test("#10: Echo-Gated VAD barge-in, on_device_only privacy wall, BYOK fallback & Voice-to-Task dispatch")
    @MainActor
    func testPersonalDailyVoiceEngine() async throws {
        // 1. Echo-Gated VAD rejects speaker echo while speaking, then fires barge-in on sustained user voice
        var vad = PipiEchoGatedVAD(sensitivity: 0.6, echoGateMultiplier: 2.5, bargeInConsecutiveFrames: 3)
        let echoFrame = makeSineFrame(amplitude: 0.09, freqHz: 260)
        for _ in 0..<4 {
            let t = vad.processFrame(echoFrame, isAssistantSpeaking: true, playbackReferenceRms: 0.08)
            #expect(t.bargeInTriggered == false)
        }
        let loudUserFrame = makeSineFrame(amplitude: 0.45, freqHz: 300)
        #expect(vad.processFrame(loudUserFrame, isAssistantSpeaking: true, playbackReferenceRms: 0.08).bargeInTriggered == false)
        #expect(vad.processFrame(loudUserFrame, isAssistantSpeaking: true, playbackReferenceRms: 0.08).bargeInTriggered == false)
        #expect(vad.processFrame(loudUserFrame, isAssistantSpeaking: true, playbackReferenceRms: 0.08).bargeInTriggered == true)

        // 2. Hard privacy wall: on_device_only MUST refuse cloud BYOK even when API key is present
        let secrets = PipiInMemorySecretStore(initial: ["voice_cloud_stt": "sk-test-voice"])
        let voice = PipiDailyVoiceEngine(
            config: PipiVoiceConfig(
                defaultMode: .museHandsFree,
                privacyPolicy: .onDeviceOnly,
                preferredSttProvider: .appleOnDevice
            ),
            secretStore: secrets
        ) { _ in
            let data = try JSONSerialization.data(withJSONObject: ["text": "Cloud BYOK transcript"])
            return (data, 200)
        }

        do {
            _ = try await voice.transcribeAudioBuffer(Data([1, 2, 3, 4]), localFallbackTranscriber: nil)
            Issue.record("Expected on_device_only to block cloud fallback")
        } catch {
            #expect(error.localizedDescription.contains("on_device_only"))
        }

        // 3. Switching to on_device_first allows BYOK cloud fallback when local transcriber is absent
        voice.config.privacyPolicy = .onDeviceFirst
        let cloudRes = try await voice.transcribeAudioBuffer(Data([1, 2, 3, 4]), localFallbackTranscriber: nil)
        #expect(cloudRes.usedOnDevice == false)
        #expect(cloudRes.providerUsed == .openaiByok)
        #expect(cloudRes.text == "Cloud BYOK transcript")

        // 4. When on-device transcriber is available, on_device_first prefers local zero-egress
        let localRes = try await voice.transcribeAudioBuffer(Data([5, 6, 7])) { _ in
            "Apple On-Device transcript"
        }
        #expect(localRes.usedOnDevice == true)
        #expect(localRes.providerUsed == .appleOnDevice)
        #expect(localRes.text == "Apple On-Device transcript")

        // 5. PipiAppStore integration: Voice-to-Task creates Tracking Item & Dictation populates draft
        let stateFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-wave4-store-\(UUID().uuidString.prefix(8))", isDirectory: true)
            .appendingPathComponent("resident-state.json")
        defer { try? FileManager.default.removeItem(at: stateFile.deletingLastPathComponent()) }

        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            stateFileUrl: stateFile,
            secretStore: secrets,
            saveDebounceMilliseconds: 0,
            voiceEngine: voice
        )

        let todoRoute = await store.dispatchVoiceUtterance(
            "Replace kitchen RO filter cartridge",
            mode: .voiceToTask,
            explicitAction: .createTrackingItem
        )
        #expect(todoRoute.action == .createTrackingItem)
        #expect(store.pocketTrackingItems.contains(where: { $0.title.contains("RO filter") }))

        let dictRoute = await store.dispatchVoiceUtterance("Hello from daily dictation", mode: .dictation)
        #expect(dictRoute.action == .dictationInsert)
        #expect(store.voicePendingDictationText == "Hello from daily dictation")

        // 6. Barge-in transitions voice session from speaking -> interrupted and updates Avatar
        voice.setState(.speaking)
        for _ in 0..<3 {
            _ = voice.ingestAudioFrame(loudUserFrame, playbackReferenceRms: 0.06)
        }
        #expect(store.voiceSessionState == .interrupted)
    }
}
