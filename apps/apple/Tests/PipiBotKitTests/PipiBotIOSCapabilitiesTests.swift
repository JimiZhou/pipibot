// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Tests for iPhone/Apple Neural Engine (NPU) Vision OCR, NaturalLanguage NPU, Thermal Governor & Action Button Deep Links.

import Foundation
import CoreGraphics
import Testing
@testable import PipiBotKit
@testable import PipiBotIOSUI

#if os(macOS)
import AppKit
#endif

@Suite("iOS Mobile Capabilities & Apple Neural Engine (NPU): Vision OCR, NaturalLanguage, Thermal Governor & Action Button")
struct PipiBotIOSCapabilitiesTests {

    @Test("Thermal & low-power NPU governor adapts workload tier cleanly across device states")
    func testNPUThermalGovernorAndProfile() async {
        #expect(PipiOnDeviceNPUEngine.evaluateWorkloadTier(thermalState: .nominal, isLowPowerMode: false, physicalMemoryGB: 8.0) == .fullPerformance)
        #expect(PipiOnDeviceNPUEngine.evaluateWorkloadTier(thermalState: .nominal, isLowPowerMode: true, physicalMemoryGB: 8.0) == .powerSaving)
        #expect(PipiOnDeviceNPUEngine.evaluateWorkloadTier(thermalState: .fair, isLowPowerMode: false, physicalMemoryGB: 8.0) == .balanced)
        #expect(PipiOnDeviceNPUEngine.evaluateWorkloadTier(thermalState: .serious, isLowPowerMode: false, physicalMemoryGB: 16.0) == .cloudOffloadRecommended)
        #expect(PipiOnDeviceNPUEngine.evaluateWorkloadTier(thermalState: .critical, isLowPowerMode: false, physicalMemoryGB: 16.0) == .cloudOffloadRecommended)

        let profile = await MainActor.run { PipiOnDeviceNPUEngine.currentProfile() }
        #expect(profile.processorCount >= 1)
        #expect(profile.physicalMemoryGB > 0)
        #expect(profile.supportsVisionNPU)
        #expect(profile.supportsNaturalLanguageNPU)
    }

    @Test("On-device Apple NaturalLanguage NPU detects language, extracts entities, and computes semantic similarity")
    func testNaturalLanguageNPUAnalysis() {
        let zh = PipiOnDeviceNPUEngine.analyzeTextOnDevice("明天下午三点提醒我和 Tim Cook 在上海讨论 PiPiBot 发布计划。")
        #expect(zh.dominantLanguage.hasPrefix("zh"))
        #expect(!zh.keywords.isEmpty)

        let en = PipiOnDeviceNPUEngine.analyzeTextOnDevice("Schedule a review meeting with Sarah in Cupertino tomorrow.")
        #expect(en.dominantLanguage == "en")

        let simSame = PipiOnDeviceNPUEngine.semanticSimilarity("Check my calendar for tomorrow", "Check my calendar for tomorrow")
        let simClose = PipiOnDeviceNPUEngine.semanticSimilarity("Schedule a doctor appointment tomorrow", "Book a medical visit tomorrow")
        let simFar = PipiOnDeviceNPUEngine.semanticSimilarity("Schedule a doctor appointment tomorrow", "Compile Rust kernel module on Linux")
        #expect(simSame == 1.0)
        #expect(simClose > simFar)
    }

    @Test("Real Apple Vision NPU OCR recognizes text rendered onto a synthetic PNG image")
    func testRealAppleVisionNPUOCR() async throws {
        #if os(macOS)
        let size = NSSize(width: 640, height: 180)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 44, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        NSString(string: "PiPiBot NPU 2026").draw(at: NSPoint(x: 40, y: 60), withAttributes: attrs)
        img.unlockFocus()

        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to render synthetic OCR test image")
            return
        }

        let res = await PipiOnDeviceNPUEngine.analyzeImageData(pngData)
        #expect(res.recognizedText.localizedCaseInsensitiveContains("PiPiBot"))
        #expect(res.recognizedText.contains("2026"))
        #expect(res.formattedSummary().contains("Apple Vision NPU"))
        #endif
    }

    @Test("iPhone Action Button voice deep link and native NPU device tools are wired cleanly")
    func testVoiceDeepLinkAndToolboxRegistration() {
        let voiceURL = URL(string: "pipibot://voice")!
        #expect(PipiIOSDeepLinkRouter.parse(voiceURL) == .openVoice)

        let callURL = URL(string: "pipibot://call")!
        #expect(PipiIOSDeepLinkRouter.parse(callURL) == .openVoice)

        let toolNames = Set(PipiAgentToolbox.allTools.map(\.name))
        #expect(toolNames.contains("device_vision_ocr"))
        #expect(toolNames.contains("device_clipboard"))
        #expect(toolNames.contains("device_npu_status"))
    }
}
