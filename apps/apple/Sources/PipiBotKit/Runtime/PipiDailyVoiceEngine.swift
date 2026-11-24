// PiPiBot — Clean-room MIT implementation.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Speech)
import Speech
#endif

// MARK: - 0. Voice Timbre / Multi-Voice Catalog

public struct PipiVoiceTimbreOption: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let nameZh: String
    public let nameEn: String
    public let language: String
    public let systemVoiceIdentifier: String?
    public let cloudVoiceName: String?
    public let pitchMultiplier: Float
    public let rateMultiplier: Float
    public let isCloud: Bool

    public init(
        id: String,
        nameZh: String,
        nameEn: String,
        language: String = "zh-CN",
        systemVoiceIdentifier: String? = nil,
        cloudVoiceName: String? = nil,
        pitchMultiplier: Float = 1.0,
        rateMultiplier: Float = 1.0,
        isCloud: Bool = false
    ) {
        self.id = id
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.language = language
        self.systemVoiceIdentifier = systemVoiceIdentifier
        self.cloudVoiceName = cloudVoiceName
        self.pitchMultiplier = pitchMultiplier
        self.rateMultiplier = rateMultiplier
        self.isCloud = isCloud
    }

    public func displayName(_ lang: PipiResolvedLanguage) -> String {
        lang == .zhHans ? nameZh : nameEn
    }

    public static let defaultProfileId = "timbre_clear_zh"

    public static let builtInPresets: [PipiVoiceTimbreOption] = [
        PipiVoiceTimbreOption(
            id: "timbre_clear_zh",
            nameZh: "清澈女声（中文）",
            nameEn: "Clear Female (ZH)",
            language: "zh-CN",
            cloudVoiceName: "nova",
            pitchMultiplier: 1.06,
            rateMultiplier: 1.02
        ),
        PipiVoiceTimbreOption(
            id: "timbre_warm_zh",
            nameZh: "沉稳男声（中文）",
            nameEn: "Warm Male (ZH)",
            language: "zh-CN",
            cloudVoiceName: "onyx",
            pitchMultiplier: 0.84,
            rateMultiplier: 0.96
        ),
        PipiVoiceTimbreOption(
            id: "timbre_lively_zh",
            nameZh: "轻快助手（中文）",
            nameEn: "Lively Assistant (ZH)",
            language: "zh-CN",
            cloudVoiceName: "coral",
            pitchMultiplier: 1.14,
            rateMultiplier: 1.08
        ),
        PipiVoiceTimbreOption(
            id: "timbre_calm_zh",
            nameZh: "温和知性（中文）",
            nameEn: "Calm Narrator (ZH)",
            language: "zh-CN",
            cloudVoiceName: "sage",
            pitchMultiplier: 0.95,
            rateMultiplier: 0.92
        ),
        PipiVoiceTimbreOption(
            id: "timbre_taiwan_zh",
            nameZh: "柔和女声（台湾腔）",
            nameEn: "Soft Female (zh-TW)",
            language: "zh-TW",
            cloudVoiceName: "shimmer",
            pitchMultiplier: 1.04,
            rateMultiplier: 0.98
        ),
        PipiVoiceTimbreOption(
            id: "timbre_cantonese_zh",
            nameZh: "粤语女声（香港）",
            nameEn: "Cantonese (zh-HK)",
            language: "zh-HK",
            cloudVoiceName: "alloy",
            pitchMultiplier: 1.02,
            rateMultiplier: 1.0
        ),
        PipiVoiceTimbreOption(
            id: "timbre_en_clear",
            nameZh: "英文清晰女声 (US)",
            nameEn: "Clear Female (en-US)",
            language: "en-US",
            cloudVoiceName: "nova",
            pitchMultiplier: 1.04,
            rateMultiplier: 1.0
        ),
        PipiVoiceTimbreOption(
            id: "timbre_en_deep",
            nameZh: "英文沉稳男声 (UK)",
            nameEn: "Deep Male (en-GB)",
            language: "en-GB",
            cloudVoiceName: "echo",
            pitchMultiplier: 0.86,
            rateMultiplier: 0.96
        )
    ]

    public static let cloudVoiceNames: [String] = [
        "alloy", "coral", "nova", "shimmer", "sage", "echo", "onyx", "fable"
    ]
}

// MARK: - 1. Personal Daily Voice Configuration & Structured Routing (Wave 4 · #10)

public struct PipiCloudVoiceEndpointConfig: Codable, Sendable, Equatable {
    public var provider: PipiVoiceEngineProvider
    public var baseURL: String
    public var modelId: String
    public var voiceName: String
    /// Keychain account reference inside `PipiSecretStore`; raw API key is NEVER persisted to disk.
    public var keychainAccount: String

    public init(
        provider: PipiVoiceEngineProvider = .openaiByok,
        baseURL: String = "https://api.openai.com/v1",
        modelId: String = "gpt-4o-mini-transcribe",
        voiceName: String = "alloy",
        keychainAccount: String = "voice_cloud_stt"
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.modelId = modelId
        self.voiceName = voiceName
        self.keychainAccount = keychainAccount
    }
}

public struct PipiVoiceConfig: Codable, Sendable, Equatable {
    public var defaultMode: PipiVoiceInteractionMode
    public var privacyPolicy: PipiVoicePrivacyPolicy
    public var preferredSttProvider: PipiVoiceEngineProvider
    public var preferredTtsProvider: PipiVoiceEngineProvider
    public var localeIdentifier: String
    public var selectedVoiceProfileId: String
    public var speechRate: Double
    public var vadSensitivity: Double
    public var echoGateMultiplier: Double
    public var bargeInConsecutiveFrames: Int
    public var autoSpeakMuseReplies: Bool
    public var cloudStt: PipiCloudVoiceEndpointConfig
    public var cloudTts: PipiCloudVoiceEndpointConfig

    private enum CodingKeys: String, CodingKey {
        case defaultMode, privacyPolicy, preferredSttProvider, preferredTtsProvider
        case localeIdentifier, selectedVoiceProfileId, speechRate, vadSensitivity
        case echoGateMultiplier, bargeInConsecutiveFrames, autoSpeakMuseReplies
        case cloudStt, cloudTts
    }

    public init(
        defaultMode: PipiVoiceInteractionMode = .dictation,
        privacyPolicy: PipiVoicePrivacyPolicy = .onDeviceFirst,
        preferredSttProvider: PipiVoiceEngineProvider = .appleOnDevice,
        preferredTtsProvider: PipiVoiceEngineProvider = .appleOnDevice,
        localeIdentifier: String = "auto",
        selectedVoiceProfileId: String = PipiVoiceTimbreOption.defaultProfileId,
        speechRate: Double = 1.0,
        vadSensitivity: Double = 0.55,
        echoGateMultiplier: Double = 2.6,
        bargeInConsecutiveFrames: Int = 3,
        autoSpeakMuseReplies: Bool = true,
        cloudStt: PipiCloudVoiceEndpointConfig = PipiCloudVoiceEndpointConfig(
            provider: .openaiByok,
            baseURL: "https://api.openai.com/v1",
            modelId: "gpt-4o-mini-transcribe",
            voiceName: "alloy",
            keychainAccount: "voice_cloud_stt"
        ),
        cloudTts: PipiCloudVoiceEndpointConfig = PipiCloudVoiceEndpointConfig(
            provider: .openaiByok,
            baseURL: "https://api.openai.com/v1",
            modelId: "gpt-4o-mini-tts",
            voiceName: "nova",
            keychainAccount: "voice_cloud_tts"
        )
    ) {
        self.defaultMode = defaultMode
        self.privacyPolicy = privacyPolicy
        self.preferredSttProvider = preferredSttProvider
        self.preferredTtsProvider = preferredTtsProvider
        self.localeIdentifier = localeIdentifier
        self.selectedVoiceProfileId = selectedVoiceProfileId
        self.speechRate = speechRate
        self.vadSensitivity = vadSensitivity
        self.echoGateMultiplier = echoGateMultiplier
        self.bargeInConsecutiveFrames = bargeInConsecutiveFrames
        self.autoSpeakMuseReplies = autoSpeakMuseReplies
        self.cloudStt = cloudStt
        self.cloudTts = cloudTts
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultMode = try c.decodeIfPresent(PipiVoiceInteractionMode.self, forKey: .defaultMode) ?? .dictation
        self.privacyPolicy = try c.decodeIfPresent(PipiVoicePrivacyPolicy.self, forKey: .privacyPolicy) ?? .onDeviceFirst
        self.preferredSttProvider = try c.decodeIfPresent(PipiVoiceEngineProvider.self, forKey: .preferredSttProvider) ?? .appleOnDevice
        self.preferredTtsProvider = try c.decodeIfPresent(PipiVoiceEngineProvider.self, forKey: .preferredTtsProvider) ?? .appleOnDevice
        self.localeIdentifier = try c.decodeIfPresent(String.self, forKey: .localeIdentifier) ?? "auto"
        self.selectedVoiceProfileId = try c.decodeIfPresent(String.self, forKey: .selectedVoiceProfileId) ?? PipiVoiceTimbreOption.defaultProfileId
        self.speechRate = try c.decodeIfPresent(Double.self, forKey: .speechRate) ?? 1.0
        self.vadSensitivity = try c.decodeIfPresent(Double.self, forKey: .vadSensitivity) ?? 0.55
        self.echoGateMultiplier = try c.decodeIfPresent(Double.self, forKey: .echoGateMultiplier) ?? 2.6
        self.bargeInConsecutiveFrames = try c.decodeIfPresent(Int.self, forKey: .bargeInConsecutiveFrames) ?? 3
        self.autoSpeakMuseReplies = try c.decodeIfPresent(Bool.self, forKey: .autoSpeakMuseReplies) ?? true
        self.cloudStt = try c.decodeIfPresent(PipiCloudVoiceEndpointConfig.self, forKey: .cloudStt) ?? PipiCloudVoiceEndpointConfig()
        self.cloudTts = try c.decodeIfPresent(PipiCloudVoiceEndpointConfig.self, forKey: .cloudTts) ?? PipiCloudVoiceEndpointConfig(
            provider: .openaiByok,
            baseURL: "https://api.openai.com/v1",
            modelId: "gpt-4o-mini-tts",
            voiceName: "nova",
            keychainAccount: "voice_cloud_tts"
        )
    }
}

public enum PipiVoiceIntentAction: String, Codable, Sendable, Equatable {
    case dictationInsert = "dictation_insert"
    case museReply = "muse_reply"
    case delegateAlterEgo = "delegate_alter_ego"
    case appendPocketNote = "append_pocket_note"
    case createTrackingItem = "create_tracking_item"

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .dictationInsert: return lang == .zhHans ? "填入输入框" : "Insert into Draft"
        case .museReply: return lang == .zhHans ? "语音通话回复" : "Voice Call Reply"
        case .delegateAlterEgo: return lang == .zhHans ? "后台任务执行" : "Run in Background"
        case .appendPocketNote: return lang == .zhHans ? "写入今日笔记" : "Append to Daily Note"
        case .createTrackingItem: return lang == .zhHans ? "添加待办事项" : "Add To-Do"
        }
    }
}

public struct PipiVoiceUtteranceRoute: Sendable, Equatable {
    public let action: PipiVoiceIntentAction
    public let transcript: String
    public let cleanedPayload: String
    public let confidence: Double
    public let rationale: String

    public init(
        action: PipiVoiceIntentAction,
        transcript: String,
        cleanedPayload: String,
        confidence: Double,
        rationale: String
    ) {
        self.action = action
        self.transcript = transcript
        self.cleanedPayload = cleanedPayload
        self.confidence = confidence
        self.rationale = rationale
    }
}

public struct PipiVadFrameTelemetry: Sendable, Equatable {
    public let rmsEnergy: Double
    public let zeroCrossingRate: Double
    public let noiseFloor: Double
    public let activeThreshold: Double
    public let isSpeech: Bool
    public let bargeInTriggered: Bool
    public let consecutiveSpeechFrames: Int
}

public struct PipiVoiceTranscriptionResult: Sendable, Equatable {
    public let text: String
    public let providerUsed: PipiVoiceEngineProvider
    public let usedOnDevice: Bool
    public let durationMs: Int
}

public enum PipiVoiceEngineError: LocalizedError, Sendable {
    case privacyPolicyBlockedCloud(PipiVoicePrivacyPolicy)
    case noEligibleProvider(String)
    case speechAuthorizationDenied
    case audioEngineUnavailable(String)
    case httpError(Int, String)

    public var errorDescription: String? {
        switch self {
        case .privacyPolicyBlockedCloud(let policy):
            return "Cloud voice provider blocked by privacy policy '\(policy.rawValue)'."
        case .noEligibleProvider(let detail):
            return "No eligible voice provider available: \(detail)"
        case .speechAuthorizationDenied:
            return "Speech recognition permission was not granted."
        case .audioEngineUnavailable(let detail):
            return "Audio capture unavailable: \(detail)"
        case .httpError(let code, let detail):
            return "Voice API HTTP \(code): \(detail)"
        }
    }
}

// MARK: - 2. Local Echo-Gated VAD & Barge-In Processor (Pure, Deterministic, Sendable)

public struct PipiEchoGatedVAD: Sendable {
    public private(set) var noiseFloor: Double = 0.012
    public private(set) var consecutiveSpeechFrames: Int = 0
    private let baseThreshold: Double
    private let echoGateMultiplier: Double
    private let bargeInFramesRequired: Int

    public init(
        sensitivity: Double = 0.55,
        echoGateMultiplier: Double = 2.6,
        bargeInConsecutiveFrames: Int = 3
    ) {
        let clampedSens = min(1.0, max(0.1, sensitivity))
        self.baseThreshold = 0.018 + (1.0 - clampedSens) * 0.045
        self.echoGateMultiplier = max(1.5, echoGateMultiplier)
        self.bargeInFramesRequired = max(2, bargeInConsecutiveFrames)
    }

    public mutating func reset() {
        consecutiveSpeechFrames = 0
    }

    public mutating func processFrame(
        _ samples: [Float],
        isAssistantSpeaking: Bool,
        playbackReferenceRms: Double = 0.0
    ) -> PipiVadFrameTelemetry {
        let count = samples.count
        guard count > 0 else {
            return PipiVadFrameTelemetry(
                rmsEnergy: 0,
                zeroCrossingRate: 0,
                noiseFloor: noiseFloor,
                activeThreshold: baseThreshold,
                isSpeech: false,
                bargeInTriggered: false,
                consecutiveSpeechFrames: consecutiveSpeechFrames
            )
        }

        var sumSq: Double = 0
        var zeroCrossings = 0
        for i in 0..<count {
            let s = Double(samples[i])
            sumSq += s * s
            if i > 0 {
                let prev = Double(samples[i - 1])
                if (prev >= 0 && s < 0) || (prev < 0 && s >= 0) {
                    zeroCrossings += 1
                }
            }
        }
        let rms = sqrt(sumSq / Double(count))
        let zcr = Double(zeroCrossings) / Double(count)
        let naturalVoiceZcr = zcr >= 0.015 && zcr <= 0.42
        let ambientThreshold = max(baseThreshold, noiseFloor * 2.2)

        let ref = max(0, playbackReferenceRms)
        let activeThreshold = isAssistantSpeaking
            ? max(ambientThreshold * echoGateMultiplier, ref * 1.45 + 0.03)
            : ambientThreshold

        let isSpeech = rms >= activeThreshold && naturalVoiceZcr
        if isSpeech {
            consecutiveSpeechFrames += 1
        } else {
            consecutiveSpeechFrames = 0
            if !isAssistantSpeaking {
                noiseFloor = noiseFloor * 0.92 + rms * 0.08
            }
        }

        let bargeIn = isAssistantSpeaking && consecutiveSpeechFrames >= bargeInFramesRequired
        return PipiVadFrameTelemetry(
            rmsEnergy: (rms * 10_000).rounded() / 10_000,
            zeroCrossingRate: (zcr * 10_000).rounded() / 10_000,
            noiseFloor: (noiseFloor * 10_000).rounded() / 10_000,
            activeThreshold: (activeThreshold * 10_000).rounded() / 10_000,
            isSpeech: isSpeech,
            bargeInTriggered: bargeIn,
            consecutiveSpeechFrames: consecutiveSpeechFrames
        )
    }
}

// MARK: - 3. On-Device-First Voice Engine (Apple Speech / AVSpeech + BYOK Cloud APIs)

@MainActor
public final class PipiDailyVoiceEngine {
    public typealias CloudHTTPTransport = @Sendable (URLRequest) async throws -> (Data, Int)

    public var config: PipiVoiceConfig {
        didSet {
            vad = PipiEchoGatedVAD(
                sensitivity: config.vadSensitivity,
                echoGateMultiplier: config.echoGateMultiplier,
                bargeInConsecutiveFrames: config.bargeInConsecutiveFrames
            )
        }
    }

    public private(set) var state: PipiVoiceSessionState = .idle
    public private(set) var liveTranscript: String = ""
    public private(set) var lastInputRms: Double = 0
    public private(set) var lastProviderUsed: PipiVoiceEngineProvider = .appleOnDevice
    public private(set) var lastError: String? = nil

    private var vad: PipiEchoGatedVAD
    private let secretStore: any PipiSecretStore
    private let cloudTransport: CloudHTTPTransport?

    public var onStateChanged: ((PipiVoiceSessionState) -> Void)?
    public var onTranscriptUpdated: ((String, Bool) -> Void)?
    public var onInputLevelUpdated: ((Double) -> Void)?
    public var onBargeInInterrupt: (() -> Void)?
    public var onSpeakingFinished: (() -> Void)?

    #if canImport(AVFoundation)
    private let synthesizer = AVSpeechSynthesizer()
    private var synthesizerDelegateProxy: PipiSpeechSynthesizerDelegateProxy?
    private var audioEngine: AVAudioEngine?
    #endif
    #if canImport(Speech)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    #endif

    public init(
        config: PipiVoiceConfig = PipiVoiceConfig(),
        secretStore: any PipiSecretStore = PipiKeychainSecretStore(),
        cloudTransport: CloudHTTPTransport? = nil
    ) {
        self.config = config
        self.secretStore = secretStore
        self.cloudTransport = cloudTransport
        self.vad = PipiEchoGatedVAD(
            sensitivity: config.vadSensitivity,
            echoGateMultiplier: config.echoGateMultiplier,
            bargeInConsecutiveFrames: config.bargeInConsecutiveFrames
        )
        #if canImport(AVFoundation)
        let proxy = PipiSpeechSynthesizerDelegateProxy { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.state == .speaking {
                    self.setState(.idle)
                }
                self.onSpeakingFinished?()
            }
        }
        self.synthesizerDelegateProxy = proxy
        self.synthesizer.delegate = proxy
        #endif
    }

    // MARK: Multi-Voice Timbre Discovery & Lookup

    public static func availableVoiceTimbres() -> [PipiVoiceTimbreOption] {
        var list = PipiVoiceTimbreOption.builtInPresets
        #if canImport(AVFoundation)
        let preferredLangPrefixes = ["zh-CN", "zh-TW", "zh-HK", "en-US", "en-GB"]
        let systemVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                preferredLangPrefixes.contains(where: { voice.language.hasPrefix($0) })
            }
            .sorted { lhs, rhs in
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name < rhs.name
            }
        var seenNames = Set<String>()
        for voice in systemVoices.prefix(12) {
            let dedupKey = "\(voice.name)_\(voice.language)"
            guard seenNames.insert(dedupKey).inserted else { continue }
            let qualityTagZh = voice.quality == .enhanced ? " · 增强" : ""
            let qualityTagEn = voice.quality == .enhanced ? " · Enhanced" : ""
            list.append(
                PipiVoiceTimbreOption(
                    id: "sys_\(voice.identifier)",
                    nameZh: "\(voice.name)（\(voice.language)\(qualityTagZh)）",
                    nameEn: "\(voice.name) (\(voice.language)\(qualityTagEn))",
                    language: voice.language,
                    systemVoiceIdentifier: voice.identifier,
                    pitchMultiplier: 1.0,
                    rateMultiplier: 1.0,
                    isCloud: false
                )
            )
        }
        #endif
        return list
    }

    public static func resolveTimbre(id: String?) -> PipiVoiceTimbreOption {
        let all = availableVoiceTimbres()
        if let id, !id.isEmpty, let matched = all.first(where: { $0.id == id }) {
            return matched
        }
        return PipiVoiceTimbreOption.builtInPresets[0]
    }

    // MARK: Candidate Resolution (Privacy-Policy Enforced)

    public static func resolveSttCandidateOrder(config: PipiVoiceConfig) -> [PipiVoiceEngineProvider] {
        let onDevice: [PipiVoiceEngineProvider] = [.appleOnDevice, .whisperKit, .mlxAudio]
        let cloud: [PipiVoiceEngineProvider] = [.openaiByok, .deepgramByok, .customByok]
        let pref = config.preferredSttProvider

        var list: [PipiVoiceEngineProvider] = []
        switch config.privacyPolicy {
        case .onDeviceOnly:
            if pref.isOnDevice { list.append(pref) }
            list.append(contentsOf: onDevice)
        case .cloudPreferred:
            if !pref.isOnDevice { list.append(pref) }
            list.append(contentsOf: cloud)
            list.append(contentsOf: onDevice)
        case .onDeviceFirst:
            list.append(pref)
            list.append(contentsOf: onDevice)
            list.append(contentsOf: cloud)
        }
        var seen = Set<PipiVoiceEngineProvider>()
        return list.filter { seen.insert($0).inserted }
    }

    public static func resolveTtsCandidateOrder(config: PipiVoiceConfig) -> [PipiVoiceEngineProvider] {
        let onDevice: [PipiVoiceEngineProvider] = [.appleOnDevice, .mlxAudio]
        let cloud: [PipiVoiceEngineProvider] = [.openaiByok, .elevenlabsByok, .customByok]
        let pref = config.preferredTtsProvider

        var list: [PipiVoiceEngineProvider] = []
        switch config.privacyPolicy {
        case .onDeviceOnly:
            if pref.isOnDevice { list.append(pref) }
            list.append(contentsOf: onDevice)
        case .cloudPreferred:
            if !pref.isOnDevice { list.append(pref) }
            list.append(contentsOf: cloud)
            list.append(contentsOf: onDevice)
        case .onDeviceFirst:
            list.append(pref)
            list.append(contentsOf: onDevice)
            list.append(contentsOf: cloud)
        }
        var seen = Set<PipiVoiceEngineProvider>()
        return list.filter { seen.insert($0).inserted }
    }

    public func setState(_ next: PipiVoiceSessionState) {
        state = next
        onStateChanged?(next)
    }

    // MARK: Echo-Gated VAD Ingestion & Barge-In

    public func ingestAudioFrame(_ samples: [Float], playbackReferenceRms: Double = 0.0) -> PipiVadFrameTelemetry {
        let isSpeaking = (state == .speaking)
        let telemetry = vad.processFrame(
            samples,
            isAssistantSpeaking: isSpeaking,
            playbackReferenceRms: playbackReferenceRms
        )
        lastInputRms = telemetry.rmsEnergy
        onInputLevelUpdated?(telemetry.rmsEnergy)

        if telemetry.bargeInTriggered {
            interruptPlaybackImmediately()
        }
        return telemetry
    }

    public func interruptPlaybackImmediately() {
        #if canImport(AVFoundation)
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        #endif
        if state == .speaking {
            setState(.interrupted)
            onBargeInInterrupt?()
        }
    }

    // MARK: Live Apple On-Device Capture (macOS & iOS)

    public func startLiveCapture(localeOverride: String? = nil) async throws {
        #if canImport(Speech) && canImport(AVFoundation)
        stopLiveCapture()
        lastError = nil
        liveTranscript = ""

        #if os(iOS)
        // Request iPhone microphone permission and configure hardware AEC (.voiceChat) + AirPods/speaker routing
        let micGranted: Bool = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micGranted else {
            setState(.error)
            lastError = PipiVoiceEngineError.microphoneAuthorizationDenied.localizedDescription
            throw PipiVoiceEngineError.microphoneAuthorizationDenied
        }
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .duckOthers]
        )
        try audioSession.setPreferredIOBufferDuration(0.01)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let authStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard authStatus == .authorized else {
            setState(.error)
            lastError = PipiVoiceEngineError.speechAuthorizationDenied.localizedDescription
            throw PipiVoiceEngineError.speechAuthorizationDenied
        }

        let resolvedLocaleId: String = {
            let candidate = localeOverride ?? config.localeIdentifier
            if candidate == "auto" || candidate.isEmpty {
                return Locale.preferredLanguages.first ?? "en-US"
            }
            return candidate
        }()
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: resolvedLocaleId)) ?? SFSpeechRecognizer() else {
            let err = PipiVoiceEngineError.noEligibleProvider("Apple SFSpeechRecognizer unavailable for \(resolvedLocaleId)")
            setState(.error)
            lastError = err.localizedDescription
            throw err
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 16.0, macOS 13.0, *) {
            request.addsPunctuation = true
        }
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else if config.privacyPolicy == .onDeviceOnly {
            let err = PipiVoiceEngineError.privacyPolicyBlockedCloud(.onDeviceOnly)
            setState(.error)
            lastError = err.localizedDescription
            throw err
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            if let channel = buffer.floatChannelData?[0] {
                let frameLen = min(Int(buffer.frameLength), 512)
                let slice = Array(UnsafeBufferPointer(start: channel, count: frameLen))
                Task { @MainActor [weak self] in
                    _ = self?.ingestAudioFrame(slice, playbackReferenceRms: self?.state == .speaking ? 0.08 : 0.0)
                }
            }
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.recognitionRequest = request
        self.lastProviderUsed = .appleOnDevice
        setState(.listening)

        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.liveTranscript = text
                    self.onTranscriptUpdated?(text, result.isFinal)
                }
                if let error {
                    // Ignore normal cancellation noise on stop
                    if self.state == .listening || self.state == .transcribing {
                        self.lastError = error.localizedDescription
                    }
                }
            }
        }
        #else
        throw PipiVoiceEngineError.audioEngineUnavailable("Speech framework not available on this platform.")
        #endif
    }

    public func stopLiveCapture() {
        #if canImport(AVFoundation)
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            audioEngine = nil
        }
        #endif
        #if canImport(Speech)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        #endif
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        vad.reset()
        if state == .listening || state == .transcribing || state == .interrupted {
            setState(.idle)
        }
    }

    // MARK: Native On-Device TTS (with Multi-Voice Timbre & Instant Barge-In Support)

    public func speakOnDevice(
        _ text: String,
        voiceProfileId: String? = nil,
        localeIdentifier: String? = nil
    ) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let timbre = Self.resolveTimbre(id: voiceProfileId ?? config.selectedVoiceProfileId)
        #if canImport(AVFoundation)
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: cleaned)
        if let sysId = timbre.systemVoiceIdentifier,
           let sysVoice = AVSpeechSynthesisVoice(identifier: sysId) {
            utterance.voice = sysVoice
        } else {
            let resolvedLocale = (localeIdentifier ?? (timbre.language.isEmpty ? config.localeIdentifier : timbre.language))
            if resolvedLocale != "auto" && !resolvedLocale.isEmpty {
                utterance.voice = AVSpeechSynthesisVoice(language: resolvedLocale)
            } else if cleaned.range(of: "\\p{Han}", options: .regularExpression) != nil {
                utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            }
        }
        let combinedRate = Float(min(1.5, max(0.6, config.speechRate * Double(timbre.rateMultiplier))))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * combinedRate
        utterance.pitchMultiplier = min(1.5, max(0.65, timbre.pitchMultiplier))
        lastProviderUsed = .appleOnDevice
        setState(.speaking)
        synthesizer.speak(utterance)
        #else
        setState(.speaking)
        #endif
    }

    public func previewVoice(profileId: String, lang: PipiResolvedLanguage) {
        let timbre = Self.resolveTimbre(id: profileId)
        let sample: String
        if timbre.language.hasPrefix("en") {
            sample = "Hello, this is a voice preview for your PiPiBot assistant."
        } else if lang == .en {
            sample = "Hello, this is a voice preview for your assistant."
        } else {
            sample = "你好，这是当前选中音色的实时试听效果。"
        }
        speakOnDevice(sample, voiceProfileId: timbre.id, localeIdentifier: timbre.language)
    }

    // MARK: Batch Transcription (On-Device-First + Privacy-Gated BYOK Cloud API)

    public func transcribeAudioBuffer(
        _ wavData: Data,
        localFallbackTranscriber: (@Sendable (Data) async throws -> String)? = nil
    ) async throws -> PipiVoiceTranscriptionResult {
        let started = Date()
        setState(.transcribing)
        let candidates = Self.resolveSttCandidateOrder(config: config)
        var errors: [String] = []

        for candidate in candidates {
            if candidate.isOnDevice {
                if let localFallbackTranscriber {
                    do {
                        let text = try await localFallbackTranscriber(wavData)
                        let ms = max(1, Int(Date().timeIntervalSince(started) * 1000))
                        lastProviderUsed = candidate
                        setState(.idle)
                        return PipiVoiceTranscriptionResult(
                            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                            providerUsed: candidate,
                            usedOnDevice: true,
                            durationMs: ms
                        )
                    } catch {
                        errors.append("\(candidate.rawValue): \(error.localizedDescription)")
                    }
                }
                continue
            }

            // Hard privacy wall: NEVER transmit audio to cloud when onDeviceOnly
            if config.privacyPolicy == .onDeviceOnly {
                continue
            }

            guard candidate == config.cloudStt.provider || candidate == .openaiByok || candidate == .deepgramByok || candidate == .customByok else {
                continue
            }
            guard let apiKey = secretStore.secret(for: config.cloudStt.keychainAccount),
                  !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            do {
                let text = try await callCloudSttAPI(wavData: wavData, apiKey: apiKey)
                let ms = max(1, Int(Date().timeIntervalSince(started) * 1000))
                lastProviderUsed = config.cloudStt.provider
                setState(.idle)
                return PipiVoiceTranscriptionResult(
                    text: text,
                    providerUsed: config.cloudStt.provider,
                    usedOnDevice: false,
                    durationMs: ms
                )
            } catch {
                errors.append("\(candidate.rawValue): \(error.localizedDescription)")
            }
        }

        setState(.error)
        if config.privacyPolicy == .onDeviceOnly {
            let err = PipiVoiceEngineError.privacyPolicyBlockedCloud(.onDeviceOnly)
            lastError = err.localizedDescription
            throw err
        }
        let err = PipiVoiceEngineError.noEligibleProvider(errors.joined(separator: "; "))
        lastError = err.localizedDescription
        throw err
    }

    private func callCloudSttAPI(wavData: Data, apiKey: String) async throws -> String {
        let base = config.cloudStt.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let urlString: String
        if config.cloudStt.provider == .deepgramByok {
            let model = config.cloudStt.modelId.isEmpty ? "nova-2" : config.cloudStt.modelId
            urlString = "\(base)/listen?model=\(model)&smart_format=true"
        } else {
            urlString = base.hasSuffix("/audio/transcriptions") ? base : "\(base)/audio/transcriptions"
        }
        guard let url = URL(string: urlString) else {
            throw PipiInferenceError.invalidEndpoint(urlString)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        if config.cloudStt.provider == .deepgramByok {
            req.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
            req.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
            req.httpBody = wavData
        } else {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: Any] = [
                "model": config.cloudStt.modelId.isEmpty ? "gpt-4o-mini-transcribe" : config.cloudStt.modelId,
                "audio_base64": wavData.base64EncodedString()
            ]
            if config.localeIdentifier != "auto" && !config.localeIdentifier.isEmpty {
                body["language"] = config.localeIdentifier
            }
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, statusCode): (Data, Int)
        if let cloudTransport {
            (data, statusCode) = try await cloudTransport(req)
        } else {
            let (d, resp) = try await URLSession.shared.data(for: req)
            data = d
            statusCode = (resp as? HTTPURLResponse)?.statusCode ?? 0
        }

        guard (200...299).contains(statusCode) else {
            throw PipiVoiceEngineError.httpError(statusCode, String(decoding: data, as: UTF8.self))
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let text = json["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let results = json["results"] as? [String: Any],
           let channels = results["channels"] as? [[String: Any]],
           let alts = channels.first?["alternatives"] as? [[String: Any]],
           let transcript = alts.first?["transcript"] as? String {
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    // MARK: Structured Daily Voice-to-Task Intent Routing

    public static func routeUtterance(
        transcript: String,
        mode: PipiVoiceInteractionMode,
        explicitAction: PipiVoiceIntentAction? = nil
    ) -> PipiVoiceUtteranceRoute {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicitAction {
            return PipiVoiceUtteranceRoute(
                action: explicitAction,
                transcript: cleaned,
                cleanedPayload: cleaned,
                confidence: 1.0,
                rationale: "Explicit structured action selection."
            )
        }
        switch mode {
        case .dictation:
            return PipiVoiceUtteranceRoute(
                action: .dictationInsert,
                transcript: cleaned,
                cleanedPayload: cleaned,
                confidence: 0.98,
                rationale: "Dictation inserts transcript into composer."
            )
        case .museHandsFree:
            return PipiVoiceUtteranceRoute(
                action: .museReply,
                transcript: cleaned,
                cleanedPayload: cleaned,
                confidence: 0.95,
                rationale: "Voice call routes to active assistant with spoken response."
            )
        case .voiceToTask:
            return PipiVoiceUtteranceRoute(
                action: .delegateAlterEgo,
                transcript: cleaned,
                cleanedPayload: cleaned,
                confidence: 0.92,
                rationale: "Voice-to-Task dispatches a background task."
            )
        }
    }
}

#if canImport(AVFoundation)
private final class PipiSpeechSynthesizerDelegateProxy: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let onFinish: @Sendable () -> Void

    init(onFinish: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }
}
#endif
