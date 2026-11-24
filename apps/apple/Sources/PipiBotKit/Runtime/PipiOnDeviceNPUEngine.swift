// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
//
// Apple Neural Engine (NPU) & Mobile Hardware Capabilities Engine:
// - Real on-device Apple Vision NPU OCR, image scene classification, and barcode/QR decoding
// - Real on-device Apple NaturalLanguage NPU language detection, entity extraction, and sentence similarity
// - Thermal & Low-Power Mode NPU governor (protects iPhone battery & temperature)
// - Native clipboard & device telemetry bridge (iOS + macOS unified)
// - Optional Apple Foundation Models (iOS 26+ / macOS 26+ Apple Intelligence on-device LLM) availability probe

import Foundation
import CoreGraphics

#if canImport(Vision)
import Vision
#endif
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(Speech)
import Speech
#endif
#if canImport(EventKit)
import EventKit
#endif
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - 1. NPU Hardware & Thermal Telemetry

public enum PipiNPUWorkloadTier: String, Codable, Sendable {
    case fullPerformance = "full_performance"
    case balanced = "balanced"
    case powerSaving = "power_saving"
    case cloudOffloadRecommended = "cloud_offload_recommended"

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .fullPerformance: return lang == .zhHans ? "NPU 全速就绪" : "NPU Full Speed"
        case .balanced: return lang == .zhHans ? "NPU 均衡运行" : "NPU Balanced"
        case .powerSaving: return lang == .zhHans ? "省电优先" : "Power Saving"
        case .cloudOffloadRecommended: return lang == .zhHans ? "机身偏热 · 建议云端协同" : "Warm · Prefer Cloud"
        }
    }
}

public struct PipiDeviceNPUProfile: Codable, Sendable, Equatable {
    public let platform: String
    public let physicalMemoryGB: Double
    public let processorCount: Int
    public let thermalState: String
    public let isLowPowerMode: Bool
    public let batteryLevelPercent: Int?
    public let isCharging: Bool
    public let supportsVisionNPU: Bool
    public let supportsOnDeviceSpeechNPU: Bool
    public let supportsNaturalLanguageNPU: Bool
    public let supportsAppleFoundationModels: Bool
    public let recommendedTier: PipiNPUWorkloadTier

    public init(
        platform: String,
        physicalMemoryGB: Double,
        processorCount: Int,
        thermalState: String,
        isLowPowerMode: Bool,
        batteryLevelPercent: Int?,
        isCharging: Bool,
        supportsVisionNPU: Bool,
        supportsOnDeviceSpeechNPU: Bool,
        supportsNaturalLanguageNPU: Bool,
        supportsAppleFoundationModels: Bool,
        recommendedTier: PipiNPUWorkloadTier
    ) {
        self.platform = platform
        self.physicalMemoryGB = physicalMemoryGB
        self.processorCount = processorCount
        self.thermalState = thermalState
        self.isLowPowerMode = isLowPowerMode
        self.batteryLevelPercent = batteryLevelPercent
        self.isCharging = isCharging
        self.supportsVisionNPU = supportsVisionNPU
        self.supportsOnDeviceSpeechNPU = supportsOnDeviceSpeechNPU
        self.supportsNaturalLanguageNPU = supportsNaturalLanguageNPU
        self.supportsAppleFoundationModels = supportsAppleFoundationModels
        self.recommendedTier = recommendedTier
    }
}

public struct PipiVisionAnalysisResult: Codable, Sendable, Equatable {
    public let recognizedText: String
    public let lines: [String]
    public let barcodes: [String]
    public let sceneLabels: [String]
    public let elapsedMs: Int

    public init(
        recognizedText: String,
        lines: [String],
        barcodes: [String],
        sceneLabels: [String],
        elapsedMs: Int
    ) {
        self.recognizedText = recognizedText
        self.lines = lines
        self.barcodes = barcodes
        self.sceneLabels = sceneLabels
        self.elapsedMs = elapsedMs
    }

    public func formattedSummary() -> String {
        var parts: [String] = []
        parts.append("[On-Device Apple Vision NPU Analysis · \(elapsedMs)ms]")
        if !recognizedText.isEmpty {
            parts.append("OCR Text:\n\(recognizedText)")
        } else {
            parts.append("OCR Text: (no text detected)")
        }
        if !barcodes.isEmpty {
            parts.append("Barcodes / QR Codes: \(barcodes.joined(separator: ", "))")
        }
        if !sceneLabels.isEmpty {
            parts.append("Scene Tags: \(sceneLabels.joined(separator: ", "))")
        }
        return parts.joined(separator: "\n\n")
    }
}

public struct PipiNLAnalysisResult: Codable, Sendable, Equatable {
    public let dominantLanguage: String
    public let entities: [String]
    public let keywords: [String]

    public init(dominantLanguage: String, entities: [String], keywords: [String]) {
        self.dominantLanguage = dominantLanguage
        self.entities = entities
        self.keywords = keywords
    }
}

// MARK: - 2. On-Device Apple NPU Engine

public enum PipiOnDeviceNPUEngine {

    /// Determines the optimal on-device NPU workload tier from thermal state, low-power mode, and RAM.
    public static func evaluateWorkloadTier(
        thermalState: ProcessInfo.ThermalState,
        isLowPowerMode: Bool,
        physicalMemoryGB: Double
    ) -> PipiNPUWorkloadTier {
        switch thermalState {
        case .serious, .critical:
            return .cloudOffloadRecommended
        case .fair:
            return isLowPowerMode ? .powerSaving : .balanced
        case .nominal:
            if isLowPowerMode { return .powerSaving }
            return physicalMemoryGB >= 6.0 ? .fullPerformance : .balanced
        @unknown default:
            return .balanced
        }
    }

    /// Probes live Apple Neural Engine, memory, battery, and on-device framework readiness.
    @MainActor
    public static func currentProfile() -> PipiDeviceNPUProfile {
        let pi = ProcessInfo.processInfo
        let ramGB = Double(pi.physicalMemory) / (1024.0 * 1024.0 * 1024.0)
        let thermalStr: String = {
            switch pi.thermalState {
            case .nominal: return "nominal"
            case .fair: return "fair"
            case .serious: return "serious"
            case .critical: return "critical"
            @unknown default: return "unknown"
            }
        }()

        var batteryPct: Int? = nil
        var charging = false
        let platformName: String
        #if os(iOS)
        platformName = UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        UIDevice.current.isBatteryMonitoringEnabled = true
        let rawLevel = UIDevice.current.batteryLevel
        if rawLevel >= 0 {
            batteryPct = Int((rawLevel * 100.0).rounded())
        }
        charging = (UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full)
        #else
        platformName = "macOS"
        charging = true
        #endif

        let visionOK: Bool
        #if canImport(Vision)
        visionOK = true
        #else
        visionOK = false
        #endif

        let nlOK: Bool
        #if canImport(NaturalLanguage)
        nlOK = true
        #else
        nlOK = false
        #endif

        let speechOnDeviceOK: Bool
        #if canImport(Speech)
        speechOnDeviceOK = SFSpeechRecognizer()?.supportsOnDeviceRecognition ?? false
        #else
        speechOnDeviceOK = false
        #endif

        let foundationModelsOK: Bool
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            foundationModelsOK = true
        } else {
            foundationModelsOK = false
        }
        #else
        foundationModelsOK = false
        #endif

        let tier = evaluateWorkloadTier(
            thermalState: pi.thermalState,
            isLowPowerMode: pi.isLowPowerModeEnabled,
            physicalMemoryGB: ramGB
        )

        return PipiDeviceNPUProfile(
            platform: platformName,
            physicalMemoryGB: (ramGB * 10).rounded() / 10,
            processorCount: pi.processorCount,
            thermalState: thermalStr,
            isLowPowerMode: pi.isLowPowerModeEnabled,
            batteryLevelPercent: batteryPct,
            isCharging: charging,
            supportsVisionNPU: visionOK,
            supportsOnDeviceSpeechNPU: speechOnDeviceOK,
            supportsNaturalLanguageNPU: nlOK,
            supportsAppleFoundationModels: foundationModelsOK,
            recommendedTier: tier
        )
    }

    // MARK: - Apple Vision NPU (OCR + Barcodes + Scene Classification)

    /// Runs real on-device Apple Vision Neural Engine OCR and barcode/QR decoding (plus optional scene tagging).
    public static func analyzeImageData(_ data: Data, includeSceneClassification: Bool = false) async -> PipiVisionAnalysisResult {
        let started = Date()
        #if canImport(Vision) && canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return PipiVisionAnalysisResult(recognizedText: "", lines: [], barcodes: [], sceneLabels: [], elapsedMs: 0)
        }
        return await analyzeCGImage(cgImage, includeSceneClassification: includeSceneClassification, startedAt: started)
        #else
        return PipiVisionAnalysisResult(recognizedText: "", lines: [], barcodes: [], sceneLabels: [], elapsedMs: 0)
        #endif
    }

    /// Runs real on-device Apple Vision NPU analysis on a local file path.
    public static func analyzeImageFile(at path: String, includeSceneClassification: Bool = false) async -> PipiVisionAnalysisResult? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return await analyzeImageData(data, includeSceneClassification: includeSceneClassification)
    }

    #if canImport(Vision)
    public static func analyzeCGImage(
        _ cgImage: CGImage,
        includeSceneClassification: Bool = false,
        startedAt: Date = Date()
    ) async -> PipiVisionAnalysisResult {
        await Task.detached(priority: .userInitiated) {
            var lines: [String] = []
            var barcodes: [String] = []
            var sceneLabels: [String] = []

            let textReq = VNRecognizeTextRequest()
            textReq.recognitionLevel = .accurate
            textReq.usesLanguageCorrection = true
            if #available(iOS 16.0, macOS 13.0, *) {
                textReq.automaticallyDetectsLanguage = true
            } else {
                textReq.recognitionLanguages = ["zh-Hans", "en-US"]
            }

            let barcodeReq = VNDetectBarcodesRequest()
            let classifyReq = VNClassifyImageRequest()
            let requests: [VNRequest] = includeSceneClassification ? [textReq, barcodeReq, classifyReq] : [textReq, barcodeReq]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform(requests)
            } catch {
                try? handler.perform([textReq])
            }

            if let textObs = textReq.results {
                for obs in textObs {
                    if let candidate = obs.topCandidates(1).first?.string {
                        let clean = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty { lines.append(clean) }
                    }
                }
            }

            if let barcodeObs = barcodeReq.results {
                for obs in barcodeObs {
                    if let payload = obs.payloadStringValue, !payload.isEmpty, !barcodes.contains(payload) {
                        barcodes.append(payload)
                    }
                }
            }

            if includeSceneClassification, let classObs = classifyReq.results {
                for obs in classObs.prefix(5) where obs.confidence >= 0.35 {
                    sceneLabels.append(obs.identifier.replacingOccurrences(of: "_", with: " "))
                }
            }

            let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
            return PipiVisionAnalysisResult(
                recognizedText: lines.joined(separator: "\n"),
                lines: lines,
                barcodes: barcodes,
                sceneLabels: sceneLabels,
                elapsedMs: elapsed
            )
        }.value
    }
    #endif

    // MARK: - Apple NaturalLanguage NPU (Language Detection, Entities & Semantic Similarity)

    public static func analyzeTextOnDevice(_ text: String) -> PipiNLAnalysisResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PipiNLAnalysisResult(dominantLanguage: "und", entities: [], keywords: [])
        }
        #if canImport(NaturalLanguage)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        let langCode = recognizer.dominantLanguage?.rawValue ?? "und"

        let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
        tagger.string = trimmed
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        var entities: [String] = []
        tagger.enumerateTags(in: trimmed.startIndex..<trimmed.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            if let tag, (tag == .personalName || tag == .placeName || tag == .organizationName) {
                let token = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !token.isEmpty && !entities.contains(token) {
                    entities.append(token)
                }
            }
            return true
        }

        var keywords: [String] = []
        tagger.enumerateTags(in: trimmed.startIndex..<trimmed.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            // English/Latin returns .noun/.verb; CJK word segmentation returns .otherWord
            if let tag, (tag == .noun || tag == .verb || tag == .otherWord) {
                let token = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if token.count >= 2 && !keywords.contains(token) && keywords.count < 12 {
                    keywords.append(token)
                }
            }
            return true
        }

        return PipiNLAnalysisResult(
            dominantLanguage: langCode,
            entities: Array(entities.prefix(12)),
            keywords: keywords
        )
        #else
        return PipiNLAnalysisResult(dominantLanguage: "und", entities: [], keywords: [])
        #endif
    }

    /// Computes on-device semantic similarity (0...1) using Apple's Neural Engine NLEmbedding when installed,
    /// with a deterministic lexical Jaccard fallback for languages without downloaded sentence packs.
    public static func semanticSimilarity(_ a: String, _ b: String) -> Double {
        let cleanA = a.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanB = b.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanA.isEmpty, !cleanB.isEmpty else { return 0 }
        if cleanA.caseInsensitiveCompare(cleanB) == .orderedSame { return 1.0 }

        #if canImport(NaturalLanguage)
        let rec = NLLanguageRecognizer()
        rec.processString(cleanA)
        let lang = rec.dominantLanguage ?? .english
        if let emb = NLEmbedding.sentenceEmbedding(for: lang) {
            let dist = emb.distance(between: cleanA, and: cleanB)
            if dist.isFinite && dist < 2.0 {
                // Cosine distance in NLEmbedding is in [0, 2]; map to [0, 1] similarity
                return max(0.0, min(1.0, 1.0 - (dist / 2.0)))
            }
        }
        #endif

        let setA = Set(cleanA.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let setB = Set(cleanB.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let union = setA.union(setB)
        guard !union.isEmpty else { return 0 }
        return Double(setA.intersection(setB).count) / Double(union.count)
    }

    // MARK: - Unified Clipboard Bridge (iPhone UIPasteboard / Mac NSPasteboard)

    @MainActor
    public static func readClipboardText() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }

    @MainActor
    public static func writeClipboardText(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
