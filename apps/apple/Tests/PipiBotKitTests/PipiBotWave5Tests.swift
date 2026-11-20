import Foundation
import Testing
@testable import PipiBotKit

private final class MockBrowserDriver: PipiBrowserAutomationDriver, @unchecked Sendable {
    private let lock = NSLock()
    private var activeCount = 0
    private(set) var maxConcurrent = 0
    private(set) var events: [String] = []
    let delayNs: UInt64

    init(delayNs: UInt64 = 25_000_000) {
        self.delayNs = delayNs
    }

    func probeSignedInChrome(debugPort: Int) async -> (reachable: Bool, version: String?) {
        (true, "Chrome/142.0")
    }

    func openOrReuseSeat(agentId: String, mode: PipiBrowserSeatMode, debugPort: Int, profilePath: String?) async throws -> (tabId: String, url: String, title: String) {
        ("tab_\(agentId)", "https://mail.example.com/compose", "Compose Mail")
    }

    func executeBrowserAction(seat: PipiChromeBrowserSeat, request: PipiComputerUseActionRequest) async throws -> PipiBrowserExecutionOutput {
        lock.withLock {
            activeCount += 1
            if activeCount > maxConcurrent { maxConcurrent = activeCount }
            events.append("browser:start:\(request.agentId)")
        }
        try? await Task.sleep(nanoseconds: delayNs)
        lock.withLock {
            activeCount -= 1
            events.append("browser:end:\(request.agentId)")
        }

        let snap = PipiSurfaceSnapshot(
            phase: .chromeBrowser,
            appName: "Google Chrome",
            appBundleId: "com.google.Chrome",
            windowTitle: "Compose Mail",
            url: request.targetUrl ?? seat.currentUrl,
            seatId: seat.seatId,
            elements: [
                PipiUIElementNode(ref: "el_body", role: "textbox", label: "Draft Body"),
                PipiUIElementNode(ref: "el_send", role: "button", label: "Send Email", isSubmitAction: true, isExternalEffect: true)
            ]
        )
        return PipiBrowserExecutionOutput(
            summary: "Chrome \(request.actionType.rawValue) ok on \(seat.seatId)",
            snapshot: snap,
            currentUrl: snap.url,
            currentTitle: snap.windowTitle
        )
    }
}

private final class MockDesktopDriver: PipiDesktopAccessibilityDriver, @unchecked Sendable {
    private let lock = NSLock()
    private var frontApp: (String, String, String) = ("Notes", "com.apple.Notes", "Draft")
    private var crashNext = false
    private(set) var physicalClicks = 0
    private var activeCount = 0
    private(set) var maxConcurrent = 0

    func setFrontApp(_ name: String, bundle: String, title: String) {
        lock.withLock { frontApp = (name, bundle, title) }
    }

    func setCrashNext(_ value: Bool) {
        lock.withLock { crashNext = value }
    }

    func checkAccessibilityTrusted() async -> Bool { true }

    func frontmostApplication() async -> (appName: String, bundleId: String, windowTitle: String) {
        lock.withLock { frontApp }
    }

    func captureDesktopSnapshot(targetAppBundleId: String?) async throws -> PipiSurfaceSnapshot {
        let isSys = targetAppBundleId == "com.apple.systempreferences"
        return PipiSurfaceSnapshot(
            phase: .macosDesktop,
            appName: isSys ? "System Settings" : "Notes",
            appBundleId: isSys ? "com.apple.systempreferences" : "com.apple.Notes",
            windowTitle: isSys ? "Privacy & Security" : "Draft",
            elements: isSys
                ? [PipiUIElementNode(ref: "ax_fda", role: "AXCheckBox", label: "Full Disk Access", isSystemPrivacySwitch: true)]
                : [PipiUIElementNode(ref: "ax_save", role: "AXButton", label: "Save Draft")]
        )
    }

    func executeDesktopAction(request: PipiComputerUseActionRequest, resolvedElement: PipiUIElementNode?) async throws -> PipiDesktopExecutionOutput {
        let shouldFail = lock.withLock { crashNext }
        if shouldFail {
            throw NSError(domain: "MockDesktop", code: 500, userInfo: [NSLocalizedDescriptionKey: "AX timeout mid-click"])
        }
        lock.withLock {
            activeCount += 1
            if activeCount > maxConcurrent { maxConcurrent = activeCount }
        }
        try? await Task.sleep(nanoseconds: 15_000_000)
        let count = lock.withLock { () -> Int in
            activeCount -= 1
            physicalClicks += 1
            return physicalClicks
        }
        return PipiDesktopExecutionOutput(summary: "Desktop \(request.actionType.rawValue) #\(count)")
    }
}

@Suite("Wave 5 — #09 Dual-Phase Computer Use (Chrome Seats, macOS AX Lanes, Human Yield & WAL)")
struct PipiBotWave5Tests {

    @Test("#09a Phase A: Parallel per-agent Chrome Seats, preparatory draft allow, external submit guardrail & no page-script eval")
    @MainActor
    func testPhaseAChromeSeatsAndGuardrails() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-wave5-a-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let chrome = MockBrowserDriver(delayNs: 30_000_000)
        let cu = PipiComputerUseCoordinator(rootURL: tmpDir, browserDriver: chrome)

        async let a = cu.executeAction(PipiComputerUseActionRequest(agentId: "bot_coder", phase: .chromeBrowser, actionType: .snapshot))
        async let b = cu.executeAction(PipiComputerUseActionRequest(agentId: "bot_writer", phase: .chromeBrowser, actionType: .snapshot))
        let (r1, r2) = await (a, b)

        #expect(r1.ok == true)
        #expect(r2.ok == true)
        #expect(chrome.maxConcurrent == 2)
        #expect(cu.listSeats().count == 2)
        #expect(r1.seat?.tabId != r2.seat?.tabId)

        // Preparatory draft typing passes smoothly
        let draft = await cu.executeAction(PipiComputerUseActionRequest(
            agentId: "bot_coder",
            phase: .chromeBrowser,
            actionType: .typeText,
            targetElementRef: "el_body",
            textInput: "Drafting reply"
        ))
        #expect(draft.ok == true)
        #expect(draft.status == .committed)

        // Clicking resolved `Send Email` button triggers #08 Guardrail needs_approval
        let send = await cu.executeAction(PipiComputerUseActionRequest(
            agentId: "bot_coder",
            phase: .chromeBrowser,
            actionType: .click,
            targetElementRef: "el_send",
            trustedUserMessages: ["Draft an email reply"]
        ))
        #expect(send.ok == false)
        #expect(send.status == .blockedGuardrail)
        #expect(send.verdict?.decision == .needsApproval)

        // Forbidden javascript: URL execution is hard-blocked
        let jsRes = await cu.executeAction(PipiComputerUseActionRequest(
            agentId: "bot_coder",
            phase: .chromeBrowser,
            actionType: .navigate,
            targetUrl: "javascript:alert(1)"
        ))
        #expect(jsRes.ok == false)
        #expect(jsRes.status == .blockedGuardrail)
    }

    @Test("#09b Phase B: Desktop single lane, Human-Focus Immediate Yield & OS privacy switch protection")
    @MainActor
    func testPhaseBDesktopLaneHumanYieldAndPrivacyGuardrail() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-wave5-b-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let chrome = MockBrowserDriver(delayNs: 20_000_000)
        let desktop = MockDesktopDriver()
        let cu = PipiComputerUseCoordinator(rootURL: tmpDir, browserDriver: chrome, desktopDriver: desktop)

        // Two desktop edits serialize strictly to maxConcurrent == 1
        async let d1 = cu.executeAction(PipiComputerUseActionRequest(
            operationId: "desk_1",
            agentId: "bot_a",
            phase: .macosDesktop,
            actionType: .typeText,
            targetAppName: "Notes",
            targetAppBundleId: "com.apple.Notes",
            textInput: "One"
        ))
        async let d2 = cu.executeAction(PipiComputerUseActionRequest(
            operationId: "desk_2",
            agentId: "bot_b",
            phase: .macosDesktop,
            actionType: .typeText,
            targetAppName: "Notes",
            targetAppBundleId: "com.apple.Notes",
            textInput: "Two"
        ))
        let (res1, res2) = await (d1, d2)
        #expect(res1.ok == true)
        #expect(res2.ok == true)
        #expect(desktop.maxConcurrent == 1)

        // Human switches foreground app to Safari -> immediate yield without touching desktop input!
        desktop.setFrontApp("Safari", bundle: "com.apple.Safari", title: "Banking")
        let yielded = await cu.executeAction(PipiComputerUseActionRequest(
            agentId: "bot_a",
            phase: .macosDesktop,
            actionType: .click,
            targetAppName: "Notes",
            targetAppBundleId: "com.apple.Notes"
        ))
        #expect(yielded.ok == false)
        #expect(yielded.yieldedToHuman == true)
        #expect(yielded.status == .yieldedToHuman)
        #expect(cu.isYieldedToHuman == true)

        // Resume & verify OS privacy switch click is blocked by #08 Guardrail
        desktop.setFrontApp("System Settings", bundle: "com.apple.systempreferences", title: "Privacy & Security")
        cu.resumeFromHumanYield()
        let snapSys = await cu.executeAction(PipiComputerUseActionRequest(
            agentId: "bot_a",
            phase: .macosDesktop,
            actionType: .snapshot,
            targetAppBundleId: "com.apple.systempreferences"
        ))
        #expect(snapSys.ok == true)

        let togglePrivacy = await cu.executeAction(PipiComputerUseActionRequest(
            agentId: "bot_a",
            phase: .macosDesktop,
            actionType: .click,
            targetAppName: "System Settings",
            targetAppBundleId: "com.apple.systempreferences",
            targetElementRef: "ax_fda"
        ))
        #expect(togglePrivacy.ok == false)
        #expect(togglePrivacy.status == .blockedGuardrail)
        #expect(togglePrivacy.verdict?.decision == .needsApproval)
    }

    @Test("#09c WAL & PipiAppStore: Anti-double-click idempotency, unknown_outcome lane lock & human unlock")
    @MainActor
    func testWriteAheadJournalAndStoreIntegration() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-wave5-wal-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let stateFile = tmpDir.appendingPathComponent("resident-state.json")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let desktop = MockDesktopDriver()
        let cu = PipiComputerUseCoordinator(rootURL: tmpDir, desktopDriver: desktop)
        let store = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: false,
            stateFileUrl: stateFile,
            secretStore: PipiInMemorySecretStore(),
            saveDebounceMilliseconds: 0,
            computerUseCoordinator: cu
        )

        // 1. Committed action retried with same operationId never clicks twice
        let first = await store.executeComputerUseAction(PipiComputerUseActionRequest(
            operationId: "op_click_once",
            agentId: "bot_coder",
            phase: .macosDesktop,
            actionType: .click,
            targetAppName: "Notes",
            targetAppBundleId: "com.apple.Notes",
            targetElementRef: "ax_save"
        ))
        #expect(first.ok == true)
        #expect(first.replayedFromJournal == false)
        #expect(desktop.physicalClicks == 1)

        let retry = await store.executeComputerUseAction(PipiComputerUseActionRequest(
            operationId: "op_click_once",
            agentId: "bot_coder",
            phase: .macosDesktop,
            actionType: .click,
            targetAppName: "Notes",
            targetAppBundleId: "com.apple.Notes",
            targetElementRef: "ax_save"
        ))
        #expect(retry.ok == true)
        #expect(retry.replayedFromJournal == true)
        #expect(desktop.physicalClicks == 1)

        // 2. Mid-click failure records unknown_outcome and locks desktop lane
        desktop.setCrashNext(true)
        let crashed = await store.executeComputerUseAction(PipiComputerUseActionRequest(
            operationId: "op_uncertain_click",
            agentId: "bot_coder",
            phase: .macosDesktop,
            actionType: .click,
            targetAppName: "Notes",
            targetAppBundleId: "com.apple.Notes"
        ))
        #expect(crashed.ok == false)
        #expect(crashed.status == .unknownOutcome)

        desktop.setCrashNext(false)
        let blockedNext = await store.executeComputerUseAction(PipiComputerUseActionRequest(
            operationId: "op_after_crash",
            agentId: "bot_coder",
            phase: .macosDesktop,
            actionType: .click,
            targetAppName: "Notes",
            targetAppBundleId: "com.apple.Notes"
        ))
        #expect(blockedNext.ok == false)
        #expect(blockedNext.error == "LANE_LOCKED_UNKNOWN_OUTCOME")

        // 3. Human acknowledges & unlocks lane via PipiAppStore -> subsequent action succeeds!
        let unlocked = store.acknowledgeAndUnlockComputerUseLane(PipiComputerUseCoordinator.desktopLaneId, note: "Verified visually")
        #expect(unlocked == true)

        let resumed = await store.executeComputerUseAction(PipiComputerUseActionRequest(
            operationId: "op_after_unlock",
            agentId: "bot_coder",
            phase: .macosDesktop,
            actionType: .click,
            targetAppName: "Notes",
            targetAppBundleId: "com.apple.Notes"
        ))
        #expect(resumed.ok == true)
        #expect(desktop.physicalClicks == 2)
    }
}
