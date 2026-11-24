// PiPiBot — Clean-room MIT implementation.
// Copyright (c) 2026 JimiZhou & PipiBot Contributors. Licensed under the MIT License.
// Comprehensive unit + live Chrome CDP integration tests for Web CUA Driver & Browser Subagent.

import Foundation
import Testing
@testable import PipiBotKit

@Suite("Web CUA: Native Chrome CDP Driver, Safety Guardrails, Vision Compaction & Interactive DOM Execution")
struct PipiBotBrowserCUATests {

    @Test("Safety policy validates URLs, blocks local/chrome/javascript schemes, and gates payment/destructive/password actions")
    func testBrowserCUASafetyPolicy() {
        // Public http/https allowed
        let okX = PipiBrowserCUASafetyPolicy.validateNavigationURL("https://x.com/sarahfim/status/123")
        #expect(okX.allowed && okX.assessment == nil)

        let autoHttps = PipiBrowserCUASafetyPolicy.validateNavigationURL("example.com/docs")
        #expect(autoHttps.allowed && autoHttps.normalizedURL == "https://example.com/docs")

        // Dangerous local/browser schemes hard-denied
        let fileURL = PipiBrowserCUASafetyPolicy.validateNavigationURL("file:///etc/passwd")
        #expect(!fileURL.allowed && (fileURL.assessment?.isHardDenied == true))

        let jsURL = PipiBrowserCUASafetyPolicy.validateNavigationURL("javascript:alert(1)")
        #expect(!jsURL.allowed && (jsURL.assessment?.isHardDenied == true))

        // Payment checkout hosts require human approval (not hard denied)
        let stripe = PipiBrowserCUASafetyPolicy.validateNavigationURL("https://checkout.stripe.com/pay/cs_test_123")
        #expect(!stripe.allowed && stripe.assessment?.requiresApproval == true && stripe.assessment?.isHardDenied == false)

        // Read-only / benign button click auto-allowed
        let showMoreBtn = PipiBrowserCUAElement(ref: "e1", tag: "button", role: "button", label: "Show more", x: 100, y: 200, width: 80, height: 32)
        let benignRisk = PipiBrowserCUASafetyPolicy.evaluateAction(
            request: PipiBrowserCUAActionRequest(action: .click, ref: "e1"),
            targetElement: showMoreBtn,
            currentURL: "https://x.com/post"
        )
        #expect(benignRisk == nil)

        // Payment / destructive click gated for human confirmation
        let payBtn = PipiBrowserCUAElement(ref: "e2", tag: "button", role: "button", label: "立即支付 ¥99", x: 120, y: 260, width: 120, height: 40)
        let payRisk = PipiBrowserCUASafetyPolicy.evaluateAction(
            request: PipiBrowserCUAActionRequest(action: .click, ref: "e2"),
            targetElement: payBtn,
            currentURL: "https://shop.example.com"
        )
        #expect(payRisk?.requiresApproval == true && payRisk?.isHardDenied == false)

        // Password field input gated for human confirmation
        let pwdField = PipiBrowserCUAElement(ref: "e3", tag: "input", role: "input", label: "Password", inputType: "password", x: 200, y: 300, width: 220, height: 36)
        let pwdRisk = PipiBrowserCUASafetyPolicy.evaluateAction(
            request: PipiBrowserCUAActionRequest(action: .type, ref: "e3", text: "secret"),
            targetElement: pwdField,
            currentURL: "https://accounts.example.com/login"
        )
        #expect(pwdRisk?.requiresApproval == true)

        // Toolbox registration & risk evaluator checks
        let toolNames = Set(PipiAgentToolbox.allTools.map(\.name))
        #expect(toolNames.contains("browser_browse"))
        #expect(toolNames.contains("browser_open"))
        #expect(toolNames.contains("browser_act"))
        #expect(toolNames.contains("browser_snapshot"))
    }

    @Test("VisionContextCompactor keeps only the most recent N screenshots so multi-step CUA loops stay lean")
    func testVisionContextCompactor() {
        let img = PipiEncodedImagePart(mimeType: "image/jpeg", base64: "AAAA")
        let messages: [PipiAgentWireMessage] = [
            .system("sys"),
            .user(text: "Frame 1", images: [img]),
            .assistant(text: "scrolling", toolCalls: []),
            .user(text: "Frame 2", images: [img]),
            .assistant(text: "clicking", toolCalls: []),
            .user(text: "Frame 3", images: [img]),
            .assistant(text: "reading", toolCalls: []),
            .user(text: "Frame 4", images: [img])
        ]

        let compacted = PipiVisionContextCompactor.compact(messages: messages, maxRetainedImages: 2)
        #expect(compacted.count == messages.count)

        var imageBearingFrames: [String] = []
        for msg in compacted {
            if case .user(let text, let imgs) = msg, !imgs.isEmpty {
                imageBearingFrames.append(text)
            }
        }
        #expect(imageBearingFrames == ["Frame 3", "Frame 4"])
    }

    @Test("Live headless Chrome CDP navigates a JS-rendered page, extracts [e1] refs, clicks interactive button, mutates DOM, and captures real JPEG screenshot")
    func testLiveHeadlessChromeCDPNavigationAndInteraction() async throws {
        guard PipiBrowserCUADriver.detectChromeBinary() != nil else {
            // Skip gracefully on headless CI runners without Chrome installed
            return
        }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipi-cua-test-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let html = """
        <!doctype html><html><head><title>PiPi CUA Live Test</title></head>
        <body style="font-family:sans-serif;padding:24px;">
          <main>
            <h1>PiPiBot Live CUA Demo</h1>
            <p id="status">Initial JS hydration pending</p>
            <button id="expand-btn" onclick="document.getElementById('status').innerText='Revealed secret note: CUA_CLICK_VERIFIED_42'">Show more</button>
          </main>
          <script>
            document.getElementById('status').innerText = 'Hydrated ready state';
          </script>
        </body></html>
        """
        let encodedHTML = html.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let dataURL = "data:text/html;charset=utf-8,\(encodedHTML)"

        let driver = PipiBrowserCUADriver()
        defer {
            Task { await driver.close() }
        }

        // 1. Navigate & verify JS hydration + structured element extraction + JPEG screenshot
        let snap1 = try await driver.navigate(
            url: dataURL,
            useSignedInSession: false,
            deliverablesDirectory: tmpDir,
            allowDataHTML: true,
            settleMilliseconds: 300
        )
        #expect(snap1.title == "PiPi CUA Live Test")
        #expect(snap1.visibleText.contains("Hydrated ready state"))
        #expect(!snap1.elements.isEmpty)
        let btnEl = snap1.elements.first(where: { $0.label.contains("Show more") })
        #expect(btnEl != nil)
        #expect((snap1.screenshotBase64?.count ?? 0) > 1000)
        if let shotPath = snap1.screenshotPath {
            #expect(FileManager.default.fileExists(atPath: shotPath))
        }

        // 2. Click the extracted [e1] ref and verify real DOM mutation in the next snapshot
        let (snap2, blocked) = try await driver.perform(
            request: PipiBrowserCUAActionRequest(action: .click, ref: btnEl!.ref),
            deliverablesDirectory: tmpDir
        )
        #expect(blocked == nil)
        #expect(snap2.visibleText.contains("CUA_CLICK_VERIFIED_42"))
        #expect((snap2.screenshotBase64?.count ?? 0) > 1000)

        await driver.close()
    }
}
