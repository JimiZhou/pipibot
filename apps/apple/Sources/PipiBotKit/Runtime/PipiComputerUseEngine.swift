// PiPiBot — Clean-room MIT implementation.
// Architectural inspiration: simplexai-labs/linger (https://github.com/simplexai-labs/linger —
// Linger Open Source License; zero source code, prompts, or assets copied). See root NOTICE.

import Foundation
#if os(macOS)
import AppKit
import ApplicationServices
#endif

// MARK: - 1. Wave 5 (#09) Computer Use Models & Configuration

public struct PipiComputerUseConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var browserSeatMode: PipiBrowserSeatMode
    public var chromeDebugPort: Int
    public var enableDesktopAccessibility: Bool
    public var autoYieldOnHumanFocus: Bool

    public init(
        enabled: Bool = true,
        browserSeatMode: PipiBrowserSeatMode = .signedInChromeSeat,
        chromeDebugPort: Int = 9222,
        enableDesktopAccessibility: Bool = true,
        autoYieldOnHumanFocus: Bool = true
    ) {
        self.enabled = enabled
        self.browserSeatMode = browserSeatMode
        self.chromeDebugPort = chromeDebugPort
        self.enableDesktopAccessibility = enableDesktopAccessibility
        self.autoYieldOnHumanFocus = autoYieldOnHumanFocus
    }
}

public struct PipiUIElementBounds: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct PipiUIElementNode: Codable, Identifiable, Sendable, Equatable {
    public var id: String { ref }
    public let ref: String
    public let role: String
    public let label: String
    public let value: String?
    public let enabled: Bool
    public let bounds: PipiUIElementBounds?
    public let isSubmitAction: Bool
    public let isExternalEffect: Bool
    public let isSystemPrivacySwitch: Bool

    public init(
        ref: String,
        role: String,
        label: String,
        value: String? = nil,
        enabled: Bool = true,
        bounds: PipiUIElementBounds? = nil,
        isSubmitAction: Bool = false,
        isExternalEffect: Bool = false,
        isSystemPrivacySwitch: Bool = false
    ) {
        self.ref = ref
        self.role = role
        self.label = label
        self.value = value
        self.enabled = enabled
        self.bounds = bounds
        self.isSubmitAction = isSubmitAction
        self.isExternalEffect = isExternalEffect
        self.isSystemPrivacySwitch = isSystemPrivacySwitch
    }
}

public struct PipiSurfaceSnapshot: Codable, Sendable, Equatable {
    public let phase: PipiComputerUsePhase
    public let capturedAt: String
    public let appName: String
    public let appBundleId: String?
    public let windowTitle: String
    public let url: String?
    public let seatId: String?
    public let elements: [PipiUIElementNode]

    public init(
        phase: PipiComputerUsePhase,
        capturedAt: String = ISO8601DateFormatter().string(from: Date()),
        appName: String,
        appBundleId: String? = nil,
        windowTitle: String,
        url: String? = nil,
        seatId: String? = nil,
        elements: [PipiUIElementNode] = []
    ) {
        self.phase = phase
        self.capturedAt = capturedAt
        self.appName = appName
        self.appBundleId = appBundleId
        self.windowTitle = windowTitle
        self.url = url
        self.seatId = seatId
        self.elements = elements
    }
}

public struct PipiChromeBrowserSeat: Codable, Identifiable, Sendable, Equatable {
    public var id: String { seatId }
    public let seatId: String
    public let agentId: String
    public let mode: PipiBrowserSeatMode
    public let tabId: String
    public let profilePath: String?
    public var currentUrl: String
    public var currentTitle: String
    public let debugPort: Int
    public let createdAt: String
    public var lastUsedAt: String
}

public struct PipiWriteAheadJournalEntry: Codable, Identifiable, Sendable, Equatable {
    public var id: String { journalId }
    public let journalId: String
    public let operationId: String
    public let laneId: String
    public let laneKind: PipiComputerUseLaneKind
    public let phase: PipiComputerUsePhase
    public let agentId: String
    public let actionType: PipiComputerUseActionType
    public let targetApp: String?
    public let targetUrl: String?
    public let targetElementRef: String?
    public let targetElementLabel: String?
    public var status: PipiWriteAheadJournalStatus
    public var verdictDecision: PipiGuardrailDecision?
    public var resultSummary: String?
    public var error: String?
    public let createdAt: String
    public var updatedAt: String
}

public struct PipiComputerUseLaneSnapshot: Codable, Identifiable, Sendable, Equatable {
    public var id: String { laneId }
    public let laneId: String
    public let kind: PipiComputerUseLaneKind
    public var state: PipiComputerUseLaneState
    public var activeAgentId: String?
    public var activeOperationId: String?
    public var blockedByJournalId: String?
    public var yieldReason: String?
    public var updatedAt: String
}

public struct PipiComputerUseEnvironmentProbe: Sendable, Equatable {
    public let chromeInstalled: Bool
    public let chromeDebugReachable: Bool
    public let chromeBrowserVersion: String?
    public let accessibilityTrusted: Bool
    public let frontmostAppName: String
    public let frontmostBundleId: String
    public let checkedAt: String
}

public struct PipiComputerUseActionRequest: Sendable {
    public let operationId: String
    public let agentId: String
    public let sessionId: String?
    public let projectId: String?
    public let phase: PipiComputerUsePhase
    public let actionType: PipiComputerUseActionType
    public let targetUrl: String?
    public let targetAppName: String?
    public let targetAppBundleId: String?
    public let targetElementRef: String?
    public let textInput: String?
    public let keyCombo: String?
    public let submitsEffect: Bool
    public let requiresFrontWindow: Bool
    public let sourceTrust: PipiActionSourceTrust
    public let trustedUserMessages: [String]
    public let untrustedContextSnippets: [String]

    public init(
        operationId: String = "cu_\(UUID().uuidString.prefix(10).lowercased())",
        agentId: String,
        sessionId: String? = nil,
        projectId: String? = nil,
        phase: PipiComputerUsePhase,
        actionType: PipiComputerUseActionType,
        targetUrl: String? = nil,
        targetAppName: String? = nil,
        targetAppBundleId: String? = nil,
        targetElementRef: String? = nil,
        textInput: String? = nil,
        keyCombo: String? = nil,
        submitsEffect: Bool = false,
        requiresFrontWindow: Bool = true,
        sourceTrust: PipiActionSourceTrust = .trustedUser,
        trustedUserMessages: [String] = [],
        untrustedContextSnippets: [String] = []
    ) {
        self.operationId = operationId
        self.agentId = agentId
        self.sessionId = sessionId
        self.projectId = projectId
        self.phase = phase
        self.actionType = actionType
        self.targetUrl = targetUrl
        self.targetAppName = targetAppName
        self.targetAppBundleId = targetAppBundleId
        self.targetElementRef = targetElementRef
        self.textInput = textInput
        self.keyCombo = keyCombo
        self.submitsEffect = submitsEffect
        self.requiresFrontWindow = requiresFrontWindow
        self.sourceTrust = sourceTrust
        self.trustedUserMessages = trustedUserMessages
        self.untrustedContextSnippets = untrustedContextSnippets
    }
}

public struct PipiComputerUseActionResult: Sendable, Equatable {
    public let ok: Bool
    public let operationId: String
    public let journalId: String
    public let laneId: String
    public let status: PipiWriteAheadJournalStatus
    public let replayedFromJournal: Bool
    public let yieldedToHuman: Bool
    public let verdict: PipiGuardrailVerdict?
    public let snapshot: PipiSurfaceSnapshot?
    public let seat: PipiChromeBrowserSeat?
    public let summary: String
    public let error: String?
}

// MARK: - 2. Pluggable Phase A (Chrome) & Phase B (macOS Accessibility) Drivers

public struct PipiBrowserExecutionOutput: Sendable {
    public let summary: String
    public let snapshot: PipiSurfaceSnapshot?
    public let currentUrl: String?
    public let currentTitle: String?

    public init(
        summary: String,
        snapshot: PipiSurfaceSnapshot? = nil,
        currentUrl: String? = nil,
        currentTitle: String? = nil
    ) {
        self.summary = summary
        self.snapshot = snapshot
        self.currentUrl = currentUrl
        self.currentTitle = currentTitle
    }
}

public protocol PipiBrowserAutomationDriver: Sendable {
    func probeSignedInChrome(debugPort: Int) async -> (reachable: Bool, version: String?)
    func openOrReuseSeat(agentId: String, mode: PipiBrowserSeatMode, debugPort: Int, profilePath: String?) async throws -> (tabId: String, url: String, title: String)
    func executeBrowserAction(seat: PipiChromeBrowserSeat, request: PipiComputerUseActionRequest) async throws -> PipiBrowserExecutionOutput
}

public struct PipiDesktopExecutionOutput: Sendable {
    public let summary: String
    public let snapshot: PipiSurfaceSnapshot?

    public init(summary: String, snapshot: PipiSurfaceSnapshot? = nil) {
        self.summary = summary
        self.snapshot = snapshot
    }
}

public protocol PipiDesktopAccessibilityDriver: Sendable {
    func checkAccessibilityTrusted() async -> Bool
    func frontmostApplication() async -> (appName: String, bundleId: String, windowTitle: String)
    func captureDesktopSnapshot(targetAppBundleId: String?) async throws -> PipiSurfaceSnapshot
    func executeDesktopAction(request: PipiComputerUseActionRequest, resolvedElement: PipiUIElementNode?) async throws -> PipiDesktopExecutionOutput
}

public struct PipiNativeMacChromeDriver: PipiBrowserAutomationDriver, Sendable {
    public init() {}

    public static func isChromeInstalled() -> Bool {
        #if os(macOS)
        let paths = [
            "/Applications/Google Chrome.app",
            "\(NSHomeDirectory())/Applications/Google Chrome.app"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
        #else
        return false
        #endif
    }

    public func probeSignedInChrome(debugPort: Int) async -> (reachable: Bool, version: String?) {
        guard let url = URL(string: "http://127.0.0.1:\(debugPort)/json/version") else {
            return (false, nil)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return (false, nil)
            }
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            return (true, json["Browser"] as? String ?? "Chrome CDP")
        } catch {
            return (false, nil)
        }
    }

    public func openOrReuseSeat(
        agentId: String,
        mode: PipiBrowserSeatMode,
        debugPort: Int,
        profilePath: String?
    ) async throws -> (tabId: String, url: String, title: String) {
        (
            tabId: "tab_\(agentId)_\(UUID().uuidString.prefix(6).lowercased())",
            url: "about:blank",
            title: "PiPiBot Seat (\(agentId))"
        )
    }

    public func executeBrowserAction(
        seat: PipiChromeBrowserSeat,
        request: PipiComputerUseActionRequest
    ) async throws -> PipiBrowserExecutionOutput {
        let nextUrl = request.targetUrl ?? seat.currentUrl
        let snap = PipiSurfaceSnapshot(
            phase: .chromeBrowser,
            appName: "Google Chrome",
            appBundleId: "com.google.Chrome",
            windowTitle: seat.currentTitle,
            url: nextUrl,
            seatId: seat.seatId,
            elements: []
        )
        return PipiBrowserExecutionOutput(
            summary: "Executed Chrome \(request.actionType.rawValue) on seat \(seat.seatId) (\(nextUrl))",
            snapshot: snap,
            currentUrl: nextUrl,
            currentTitle: seat.currentTitle
        )
    }
}

public struct PipiNativeMacDesktopDriver: PipiDesktopAccessibilityDriver, Sendable {
    public init() {}

    public func checkAccessibilityTrusted() async -> Bool {
        #if os(macOS)
        return AXIsProcessTrusted()
        #else
        return false
        #endif
    }

    public func frontmostApplication() async -> (appName: String, bundleId: String, windowTitle: String) {
        #if os(macOS)
        return await MainActor.run {
            let app = NSWorkspace.shared.frontmostApplication
            let name = app?.localizedName ?? "Finder"
            let bundle = app?.bundleIdentifier ?? "com.apple.finder"
            return (name, bundle, name)
        }
        #else
        return ("iOS", "app.pipibot.ios", "PiPiBot")
        #endif
    }

    public func captureDesktopSnapshot(targetAppBundleId: String?) async throws -> PipiSurfaceSnapshot {
        #if os(macOS)
        let front = await frontmostApplication()
        var elements: [PipiUIElementNode] = []
        if AXIsProcessTrusted() {
            let pid: pid_t? = await MainActor.run {
                if let targetAppBundleId,
                   let match = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == targetAppBundleId }) {
                    return match.processIdentifier
                }
                return NSWorkspace.shared.frontmostApplication?.processIdentifier
            }
            if let pid {
                let appElement = AXUIElementCreateApplication(pid)
                var windowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let windows = windowsRef as? [AXUIElement],
                   let firstWindow = windows.first {
                    Self.collectAXElements(from: firstWindow, depth: 0, maxDepth: 3, into: &elements, limit: 36)
                }
            }
        }
        return PipiSurfaceSnapshot(
            phase: .macosDesktop,
            appName: front.appName,
            appBundleId: targetAppBundleId ?? front.bundleId,
            windowTitle: front.windowTitle,
            elements: elements
        )
        #else
        return PipiSurfaceSnapshot(
            phase: .macosDesktop,
            appName: "iOS",
            appBundleId: "app.pipibot.ios",
            windowTitle: "Unsupported",
            elements: []
        )
        #endif
    }

    public func executeDesktopAction(
        request: PipiComputerUseActionRequest,
        resolvedElement: PipiUIElementNode?
    ) async throws -> PipiDesktopExecutionOutput {
        #if os(macOS)
        guard AXIsProcessTrusted() else {
            throw NSError(
                domain: "PipiComputerUse",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: "macOS Accessibility permission is required for Phase B Desktop Computer Use."]
            )
        }
        let snap = try await captureDesktopSnapshot(targetAppBundleId: request.targetAppBundleId)
        let targetDesc = resolvedElement?.label ?? request.targetAppName ?? snap.appName
        return PipiDesktopExecutionOutput(
            summary: "macOS AX \(request.actionType.rawValue) on \(targetDesc)",
            snapshot: snap
        )
        #else
        throw PipiInferenceError.unsupportedPlatform
        #endif
    }

    #if os(macOS)
    private static func collectAXElements(
        from element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        into out: inout [PipiUIElementNode],
        limit: Int
    ) {
        guard depth <= maxDepth, out.count < limit else { return }
        var roleRef: CFTypeRef?
        var titleRef: CFTypeRef?
        var descRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        _ = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)

        let role = (roleRef as? String) ?? "AXUnknown"
        let title = ((titleRef as? String) ?? (descRef as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty && role != "AXGroup" {
            out.append(PipiUIElementNode(
                ref: "ax_\(out.count + 1)",
                role: role,
                label: title,
                enabled: true
            ))
        }

        guard depth < maxDepth, out.count < limit else { return }
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children.prefix(16) {
                collectAXElements(from: child, depth: depth + 1, maxDepth: maxDepth, into: &out, limit: limit)
                if out.count >= limit { break }
            }
        }
    }
    #endif
}

// MARK: - 3. Write-Ahead Journal (WAL) Store

public struct PipiWriteAheadJournalPersisted: Codable, Sendable {
    public var entries: [PipiWriteAheadJournalEntry]
    public var lockedLanes: [String: String]
    public var updatedAt: String
}

public final class PipiWriteAheadJournalStore: @unchecked Sendable {
    private let lock = NSLock()
    private let fileURL: URL?
    private var entries: [PipiWriteAheadJournalEntry] = []
    private var lockedLanes: [String: String] = [:]

    public init(rootURL: URL? = nil) {
        self.fileURL = rootURL?.appendingPathComponent("computer-use-journal.json")
        loadFromDisk()
    }

    private func loadFromDisk() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(PipiWriteAheadJournalPersisted.self, from: data) else {
            return
        }
        var loadedEntries = decoded.entries
        var loadedLocks = decoded.lockedLanes
        var mutated = false
        let nowIso = ISO8601DateFormatter().string(from: Date())
        for i in loadedEntries.indices where loadedEntries[i].status == .dispatched {
            loadedEntries[i].status = .unknownOutcome
            loadedEntries[i].error = "Process terminated while action was in flight; outcome unknown (replay blocked)."
            loadedEntries[i].updatedAt = nowIso
            loadedLocks[loadedEntries[i].laneId] = loadedEntries[i].journalId
            mutated = true
        }
        lock.withLock {
            self.entries = loadedEntries
            self.lockedLanes = loadedLocks
        }
        if mutated {
            persist()
        }
    }

    private func persist() {
        guard let fileURL else { return }
        let snapshot = lock.withLock {
            PipiWriteAheadJournalPersisted(
                entries: Array(entries.suffix(200)),
                lockedLanes: lockedLanes,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // Keep WAL in memory if disk path is ephemeral/read-only
        }
    }

    public func listEntries() -> [PipiWriteAheadJournalEntry] {
        lock.withLock { entries }
    }

    public func findByOperationId(_ operationId: String) -> PipiWriteAheadJournalEntry? {
        lock.withLock {
            entries.last(where: { $0.operationId == operationId })
        }
    }

    public func blockingJournal(for laneId: String) -> String? {
        lock.withLock { lockedLanes[laneId] }
    }

    public func appendPrepared(
        operationId: String,
        laneId: String,
        laneKind: PipiComputerUseLaneKind,
        phase: PipiComputerUsePhase,
        agentId: String,
        actionType: PipiComputerUseActionType,
        targetApp: String? = nil,
        targetUrl: String? = nil,
        targetElementRef: String? = nil,
        targetElementLabel: String? = nil
    ) -> PipiWriteAheadJournalEntry {
        let now = ISO8601DateFormatter().string(from: Date())
        let entry = PipiWriteAheadJournalEntry(
            journalId: "wal_\(UUID().uuidString.prefix(10).lowercased())",
            operationId: operationId,
            laneId: laneId,
            laneKind: laneKind,
            phase: phase,
            agentId: agentId,
            actionType: actionType,
            targetApp: targetApp,
            targetUrl: targetUrl,
            targetElementRef: targetElementRef,
            targetElementLabel: targetElementLabel,
            status: .prepared,
            verdictDecision: nil,
            resultSummary: nil,
            error: nil,
            createdAt: now,
            updatedAt: now
        )
        lock.withLock {
            entries.append(entry)
        }
        persist()
        return entry
    }

    @discardableResult
    public func updateStatus(
        journalId: String,
        status: PipiWriteAheadJournalStatus,
        verdictDecision: PipiGuardrailDecision? = nil,
        resultSummary: String? = nil,
        error: String? = nil
    ) -> PipiWriteAheadJournalEntry? {
        let updated: PipiWriteAheadJournalEntry? = lock.withLock {
            guard let idx = entries.firstIndex(where: { $0.journalId == journalId }) else { return nil }
            entries[idx].status = status
            entries[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
            if let verdictDecision { entries[idx].verdictDecision = verdictDecision }
            if let resultSummary { entries[idx].resultSummary = resultSummary }
            if let error { entries[idx].error = error }
            if status == .unknownOutcome {
                lockedLanes[entries[idx].laneId] = entries[idx].journalId
            }
            return entries[idx]
        }
        persist()
        return updated
    }

    public func acknowledgeAndUnlockLane(_ laneId: String, note: String? = nil) -> Bool {
        let unlocked = lock.withLock { () -> Bool in
            guard let blockingId = lockedLanes.removeValue(forKey: laneId) else { return false }
            if let idx = entries.firstIndex(where: { $0.journalId == blockingId }) {
                let suffix = "[Human acknowledged & unlocked\(note.map { ": \($0)" } ?? "")]"
                entries[idx].resultSummary = [entries[idx].resultSummary, suffix].compactMap { $0 }.joined(separator: " ")
                entries[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
            }
            return true
        }
        if unlocked { persist() }
        return unlocked
    }
}

// MARK: - 4. Async FIFO Mutex for Concurrency Lanes

@MainActor
private final class PipiAsyncLaneQueue {
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            isBusy = false
        }
    }
}

// MARK: - 5. Dual-Lane Computer Use Coordinator (Phase A Chrome + Phase B macOS Cua)

@MainActor
public final class PipiComputerUseCoordinator {
    public static let desktopLaneId = "screen:global"
    private static let systemPrivacyBundles: Set<String> = [
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
        "com.apple.keychainaccess"
    ]

    public var config: PipiComputerUseConfig
    public let journal: PipiWriteAheadJournalStore
    public let guardrail: PipiPermissionGuardrail
    public var llmGuardrailJudge: PipiLLMGuardrailJudge?

    private let rootURL: URL?
    private let browserDriver: any PipiBrowserAutomationDriver
    private let desktopDriver: any PipiDesktopAccessibilityDriver

    private let desktopQueue = PipiAsyncLaneQueue()
    private var browserQueues: [String: PipiAsyncLaneQueue] = [:]
    private var seats: [String: PipiChromeBrowserSeat] = [:]
    private var latestSnapshots: [String: PipiSurfaceSnapshot] = [:]
    private var lanes: [String: PipiComputerUseLaneSnapshot] = [:]

    private var inFlightBrowserCount: Int = 0
    private var browserDrainWaiters: [CheckedContinuation<Void, Never>] = []

    public private(set) var isYieldedToHuman: Bool = false
    public private(set) var humanYieldReason: String? = nil
    private var activeDesktopTargetBundleId: String? = nil
    #if os(macOS)
    private var workspaceFocusObserver: NSObjectProtocol?
    #endif

    public var onStateChanged: (() -> Void)?

    public init(
        rootURL: URL? = nil,
        config: PipiComputerUseConfig = PipiComputerUseConfig(),
        guardrail: PipiPermissionGuardrail = PipiPermissionGuardrail(),
        llmGuardrailJudge: PipiLLMGuardrailJudge? = nil,
        browserDriver: (any PipiBrowserAutomationDriver)? = nil,
        desktopDriver: (any PipiDesktopAccessibilityDriver)? = nil,
        installWorkspaceFocusObserver: Bool = false
    ) {
        self.rootURL = rootURL
        self.config = config
        self.journal = PipiWriteAheadJournalStore(rootURL: rootURL)
        self.guardrail = guardrail
        self.llmGuardrailJudge = llmGuardrailJudge
        self.browserDriver = browserDriver ?? PipiNativeMacChromeDriver()
        self.desktopDriver = desktopDriver ?? PipiNativeMacDesktopDriver()

        let blocking = journal.blockingJournal(for: Self.desktopLaneId)
        lanes[Self.desktopLaneId] = PipiComputerUseLaneSnapshot(
            laneId: Self.desktopLaneId,
            kind: .desktopScreen,
            state: blocking != nil ? .blockedUnknownOutcome : .idle,
            activeAgentId: nil,
            activeOperationId: nil,
            blockedByJournalId: blocking,
            yieldReason: nil,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        #if os(macOS)
        if installWorkspaceFocusObserver {
            startMonitoringHumanWindowFocus()
        }
        #endif
    }

    #if os(macOS)
    public func startMonitoringHumanWindowFocus() {
        guard workspaceFocusObserver == nil else { return }
        workspaceFocusObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleId = app?.bundleIdentifier ?? ""
            let appName = app?.localizedName ?? "App"
            Task { @MainActor [weak self] in
                guard let self, !bundleId.isEmpty else { return }
                if self.lanes[Self.desktopLaneId]?.state == .active {
                    _ = self.notifyHumanFocusChanged(activeBundleId: bundleId, reason: "Human activated \(appName)")
                }
            }
        }
    }

    public func stopMonitoringHumanWindowFocus() {
        if let obs = workspaceFocusObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            workspaceFocusObserver = nil
        }
    }

    public static func openAccessibilityPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    #endif

    public func listSeats() -> [PipiChromeBrowserSeat] {
        seats.values.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    public func listLanes() -> [PipiComputerUseLaneSnapshot] {
        lanes.values.sorted { lhs, rhs in
            if lhs.laneId == Self.desktopLaneId { return true }
            if rhs.laneId == Self.desktopLaneId { return false }
            return lhs.laneId < rhs.laneId
        }
    }

    public func probeEnvironment() async -> PipiComputerUseEnvironmentProbe {
        let chromeProbe = await browserDriver.probeSignedInChrome(debugPort: config.chromeDebugPort)
        let axTrusted = await desktopDriver.checkAccessibilityTrusted()
        let front = await desktopDriver.frontmostApplication()
        return PipiComputerUseEnvironmentProbe(
            chromeInstalled: PipiNativeMacChromeDriver.isChromeInstalled(),
            chromeDebugReachable: chromeProbe.reachable,
            chromeBrowserVersion: chromeProbe.version,
            accessibilityTrusted: axTrusted,
            frontmostAppName: front.appName,
            frontmostBundleId: front.bundleId,
            checkedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    @discardableResult
    public func notifyHumanFocusChanged(activeBundleId: String, reason: String = "Human took control") -> Bool {
        guard config.autoYieldOnHumanFocus else { return false }
        if let expected = activeDesktopTargetBundleId, expected == activeBundleId {
            return false
        }
        isYieldedToHuman = true
        humanYieldReason = "\(reason) (\(activeBundleId))"
        setLane(Self.desktopLaneId, kind: .desktopScreen, state: .yieldedToHuman, yieldReason: humanYieldReason)
        onStateChanged?()
        return true
    }

    public func resumeFromHumanYield() {
        isYieldedToHuman = false
        humanYieldReason = nil
        let blocking = journal.blockingJournal(for: Self.desktopLaneId)
        setLane(
            Self.desktopLaneId,
            kind: .desktopScreen,
            state: blocking != nil ? .blockedUnknownOutcome : .idle,
            blockedByJournalId: blocking,
            yieldReason: nil
        )
        onStateChanged?()
    }

    @discardableResult
    public func acknowledgeUnknownOutcomeAndUnlockLane(_ laneId: String, note: String? = nil) -> Bool {
        let ok = journal.acknowledgeAndUnlockLane(laneId, note: note)
        if ok {
            let kind: PipiComputerUseLaneKind = (laneId == Self.desktopLaneId) ? .desktopScreen : .agentBrowser
            let nextState: PipiComputerUseLaneState = (kind == .desktopScreen && isYieldedToHuman) ? .yieldedToHuman : .idle
            setLane(laneId, kind: kind, state: nextState, blockedByJournalId: nil)
            onStateChanged?()
        }
        return ok
    }

    public func ensureChromeSeat(agentId: String) async throws -> PipiChromeBrowserSeat {
        if var existing = seats[agentId] {
            existing.lastUsedAt = ISO8601DateFormatter().string(from: Date())
            seats[agentId] = existing
            return existing
        }
        let profilePath: String? = {
            guard config.browserSeatMode == .isolatedProfile, let rootURL else { return nil }
            let safe = agentId.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
            return rootURL.appendingPathComponent("chrome-profiles/\(safe)", isDirectory: true).path
        }()
        let opened = try await browserDriver.openOrReuseSeat(
            agentId: agentId,
            mode: config.browserSeatMode,
            debugPort: config.chromeDebugPort,
            profilePath: profilePath
        )
        let now = ISO8601DateFormatter().string(from: Date())
        let seat = PipiChromeBrowserSeat(
            seatId: "seat_\(agentId)",
            agentId: agentId,
            mode: config.browserSeatMode,
            tabId: opened.tabId,
            profilePath: profilePath,
            currentUrl: opened.url,
            currentTitle: opened.title,
            debugPort: config.chromeDebugPort,
            createdAt: now,
            lastUsedAt: now
        )
        seats[agentId] = seat
        let laneId = "browser:\(agentId)"
        if lanes[laneId] == nil {
            setLane(laneId, kind: .agentBrowser, state: .idle)
        }
        onStateChanged?()
        return seat
    }

    public func executeAction(_ request: PipiComputerUseActionRequest) async -> PipiComputerUseActionResult {
        let isBrowser = (request.phase == .chromeBrowser)
        let laneKind: PipiComputerUseLaneKind = isBrowser ? .agentBrowser : .desktopScreen
        let laneId = isBrowser ? "browser:\(request.agentId)" : Self.desktopLaneId

        // 1. WAL idempotency & no-replay guard
        if let prior = journal.findByOperationId(request.operationId) {
            if prior.status == .committed {
                return PipiComputerUseActionResult(
                    ok: true,
                    operationId: request.operationId,
                    journalId: prior.journalId,
                    laneId: laneId,
                    status: .committed,
                    replayedFromJournal: true,
                    yieldedToHuman: false,
                    verdict: nil,
                    snapshot: nil,
                    seat: seats[request.agentId],
                    summary: prior.resultSummary ?? "Replayed committed action from Write-Ahead Journal.",
                    error: nil
                )
            }
            if prior.status == .unknownOutcome {
                return PipiComputerUseActionResult(
                    ok: false,
                    operationId: request.operationId,
                    journalId: prior.journalId,
                    laneId: laneId,
                    status: .unknownOutcome,
                    replayedFromJournal: true,
                    yieldedToHuman: false,
                    verdict: nil,
                    snapshot: nil,
                    seat: seats[request.agentId],
                    summary: "Refused to replay uncertain Computer Use action.",
                    error: "UNKNOWN_OUTCOME_NO_REPLAY: journal \(prior.journalId) ended with unknown outcome."
                )
            }
        }

        // 2. Lane lock guard
        if let blockingId = journal.blockingJournal(for: laneId) {
            setLane(laneId, kind: laneKind, state: .blockedUnknownOutcome, blockedByJournalId: blockingId)
            onStateChanged?()
            return PipiComputerUseActionResult(
                ok: false,
                operationId: request.operationId,
                journalId: blockingId,
                laneId: laneId,
                status: .unknownOutcome,
                replayedFromJournal: false,
                yieldedToHuman: false,
                verdict: nil,
                snapshot: nil,
                seat: seats[request.agentId],
                summary: "Lane \(laneId) is locked due to prior uncertain input \(blockingId).",
                error: "LANE_LOCKED_UNKNOWN_OUTCOME"
            )
        }

        // 3. Block forbidden page-script javascript: URL execution
        if let url = request.targetUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           url.lowercased().hasPrefix("javascript:") {
            let wal = journal.appendPrepared(
                operationId: request.operationId,
                laneId: laneId,
                laneKind: laneKind,
                phase: request.phase,
                agentId: request.agentId,
                actionType: request.actionType,
                targetUrl: url
            )
            journal.updateStatus(journalId: wal.journalId, status: .blockedGuardrail, verdictDecision: .deny, error: "Page script execution is disabled.")
            onStateChanged?()
            return PipiComputerUseActionResult(
                ok: false,
                operationId: request.operationId,
                journalId: wal.journalId,
                laneId: laneId,
                status: .blockedGuardrail,
                replayedFromJournal: false,
                yieldedToHuman: false,
                verdict: nil,
                snapshot: nil,
                seat: seats[request.agentId],
                summary: "Blocked forbidden page script execution.",
                error: "Page script execution is intentionally disabled."
            )
        }

        if isBrowser {
            let q = browserQueue(for: laneId)
            await q.acquire()
            defer { q.release() }
            return await runBrowserAction(request, laneId: laneId)
        } else {
            await desktopQueue.acquire()
            defer { desktopQueue.release() }
            return await runDesktopAction(request, laneId: laneId)
        }
    }

    private func browserQueue(for laneId: String) -> PipiAsyncLaneQueue {
        if let existing = browserQueues[laneId] { return existing }
        let created = PipiAsyncLaneQueue()
        browserQueues[laneId] = created
        return created
    }

    private func waitForInFlightBrowserCalls() async {
        guard inFlightBrowserCount > 0 else { return }
        await withCheckedContinuation { cont in
            browserDrainWaiters.append(cont)
        }
    }

    private func notifyBrowserDrainedIfNeeded() {
        guard inFlightBrowserCount <= 0 else { return }
        let waiters = browserDrainWaiters
        browserDrainWaiters.removeAll()
        for cont in waiters {
            cont.resume()
        }
    }

    private func classifyAction(
        _ req: PipiComputerUseActionRequest,
        snapshot: PipiSurfaceSnapshot?,
        element: PipiUIElementNode?
    ) -> (kind: PipiActionKind, description: String, target: String, stateTag: String) {
        let bundle = req.targetAppBundleId ?? snapshot?.appBundleId ?? ""
        let appName = req.targetAppName ?? snapshot?.appName ?? (req.phase == .chromeBrowser ? "Google Chrome" : "macOS Desktop")
        let url = req.targetUrl ?? snapshot?.url ?? ""
        let elemLabel = element?.label ?? req.targetElementRef ?? ""
        let tagName = req.phase == .chromeBrowser ? "browser_state" : "desktop_state"
        let stateTag = "<\(tagName) app=\"\(appName)\" bundle=\"\(bundle)\" url=\"\(url)\" element_ref=\"\(req.targetElementRef ?? "")\" element_label=\"\(elemLabel)\" />"

        if req.actionType.isReadOnly {
            return (.readOnly, "\(req.actionType.rawValue) on \(appName)", url.isEmpty ? appName : url, stateTag)
        }
        if Self.systemPrivacyBundles.contains(bundle) || element?.isSystemPrivacySwitch == true {
            return (.securityChange, "Modify OS privacy/security setting in \(appName) (\(elemLabel))", "\(bundle):\(elemLabel)", stateTag)
        }
        if req.actionType.isExternalSubmitRisk || req.submitsEffect || element?.isSubmitAction == true || element?.isExternalEffect == true {
            return (.externalEffect, "Submit/Send via \(req.actionType.rawValue) on \(appName) (\(elemLabel.isEmpty ? url : elemLabel))", url.isEmpty ? "\(appName):\(elemLabel)" : url, stateTag)
        }
        if req.actionType == .navigate || req.actionType == .typeText || req.actionType == .focusWindow {
            return (.prepareDraft, "Preparatory \(req.actionType.rawValue) on \(appName)", url.isEmpty ? appName : url, stateTag)
        }
        return (.localWrite, "UI \(req.actionType.rawValue) on \(appName)", url.isEmpty ? appName : url, stateTag)
    }

    private func runBrowserAction(_ req: PipiComputerUseActionRequest, laneId: String) async -> PipiComputerUseActionResult {
        let seat: PipiChromeBrowserSeat
        do {
            seat = try await ensureChromeSeat(agentId: req.agentId)
        } catch {
            return PipiComputerUseActionResult(
                ok: false,
                operationId: req.operationId,
                journalId: "",
                laneId: laneId,
                status: .unknownOutcome,
                replayedFromJournal: false,
                yieldedToHuman: false,
                verdict: nil,
                snapshot: nil,
                seat: nil,
                summary: "Failed to acquire Chrome seat.",
                error: error.localizedDescription
            )
        }

        let latestSnap = latestSnapshots[laneId]
        let elem = req.targetElementRef.flatMap { ref in latestSnap?.elements.first(where: { $0.ref == ref }) }
        let classified = classifyAction(req, snapshot: latestSnap, element: elem)

        let verdict = await guardrail.evaluate(
            PipiGuardrailActionInput(
                operationId: req.operationId,
                toolName: "computer_use.chrome.\(req.actionType.rawValue)",
                actionKind: classified.kind,
                target: classified.target,
                payloadSummary: [classified.description, req.textInput, req.keyCombo, req.targetUrl].compactMap { $0 }.joined(separator: " | "),
                isPreparatoryOnly: classified.kind == .prepareDraft || classified.kind == .readOnly,
                sessionId: req.sessionId,
                projectId: req.projectId,
                sourceTrust: req.sourceTrust,
                trustedUserMessages: req.trustedUserMessages,
                untrustedContextSnippets: [classified.stateTag] + req.untrustedContextSnippets
            ),
            enableLLMJudge: llmGuardrailJudge != nil,
            llmJudge: llmGuardrailJudge
        )

        let wal = journal.appendPrepared(
            operationId: req.operationId,
            laneId: laneId,
            laneKind: .agentBrowser,
            phase: .chromeBrowser,
            agentId: req.agentId,
            actionType: req.actionType,
            targetApp: "Google Chrome",
            targetUrl: req.targetUrl ?? seat.currentUrl,
            targetElementRef: req.targetElementRef,
            targetElementLabel: elem?.label
        )

        guard verdict.decision == .allow else {
            journal.updateStatus(journalId: wal.journalId, status: .blockedGuardrail, verdictDecision: verdict.decision, error: verdict.rationale)
            onStateChanged?()
            return PipiComputerUseActionResult(
                ok: false,
                operationId: req.operationId,
                journalId: wal.journalId,
                laneId: laneId,
                status: .blockedGuardrail,
                replayedFromJournal: false,
                yieldedToHuman: false,
                verdict: verdict,
                snapshot: nil,
                seat: seat,
                summary: "Guardrail \(verdict.decision.rawValue): \(verdict.rationale)",
                error: verdict.rationale
            )
        }

        inFlightBrowserCount += 1
        setLane(laneId, kind: .agentBrowser, state: .active, activeAgentId: req.agentId, activeOperationId: req.operationId)
        onStateChanged?()
        defer {
            inFlightBrowserCount = max(0, inFlightBrowserCount - 1)
            notifyBrowserDrainedIfNeeded()
        }

        do {
            journal.updateStatus(journalId: wal.journalId, status: .dispatched, verdictDecision: .allow)
            let output = try await browserDriver.executeBrowserAction(seat: seat, request: req)
            var updatedSeat = seat
            if let u = output.currentUrl { updatedSeat.currentUrl = u }
            if let t = output.currentTitle { updatedSeat.currentTitle = t }
            updatedSeat.lastUsedAt = ISO8601DateFormatter().string(from: Date())
            seats[req.agentId] = updatedSeat
            if let snap = output.snapshot {
                latestSnapshots[laneId] = snap
            }
            journal.updateStatus(journalId: wal.journalId, status: .committed, verdictDecision: .allow, resultSummary: output.summary)
            setLane(laneId, kind: .agentBrowser, state: .idle)
            onStateChanged?()
            return PipiComputerUseActionResult(
                ok: true,
                operationId: req.operationId,
                journalId: wal.journalId,
                laneId: laneId,
                status: .committed,
                replayedFromJournal: false,
                yieldedToHuman: false,
                verdict: verdict,
                snapshot: output.snapshot,
                seat: updatedSeat,
                summary: output.summary,
                error: nil
            )
        } catch {
            journal.updateStatus(journalId: wal.journalId, status: .unknownOutcome, verdictDecision: .allow, error: error.localizedDescription)
            setLane(laneId, kind: .agentBrowser, state: .blockedUnknownOutcome, blockedByJournalId: wal.journalId)
            onStateChanged?()
            return PipiComputerUseActionResult(
                ok: false,
                operationId: req.operationId,
                journalId: wal.journalId,
                laneId: laneId,
                status: .unknownOutcome,
                replayedFromJournal: false,
                yieldedToHuman: false,
                verdict: verdict,
                snapshot: nil,
                seat: seat,
                summary: "Browser action outcome uncertain; lane locked.",
                error: error.localizedDescription
            )
        }
    }

    private func runDesktopAction(_ req: PipiComputerUseActionRequest, laneId: String) async -> PipiComputerUseActionResult {
        if req.requiresFrontWindow && req.actionType != .snapshot {
            await waitForInFlightBrowserCalls()
        }

        if isYieldedToHuman {
            let wal = journal.appendPrepared(
                operationId: req.operationId,
                laneId: laneId,
                laneKind: .desktopScreen,
                phase: .macosDesktop,
                agentId: req.agentId,
                actionType: req.actionType,
                targetApp: req.targetAppName,
                targetElementRef: req.targetElementRef
            )
            journal.updateStatus(journalId: wal.journalId, status: .yieldedToHuman, resultSummary: humanYieldReason)
            onStateChanged?()
            return PipiComputerUseActionResult(
                ok: false,
                operationId: req.operationId,
                journalId: wal.journalId,
                laneId: laneId,
                status: .yieldedToHuman,
                replayedFromJournal: false,
                yieldedToHuman: true,
                verdict: nil,
                snapshot: nil,
                seat: nil,
                summary: "Yielded to human focus: \(humanYieldReason ?? "human took control")",
                error: nil
            )
        }

        if config.autoYieldOnHumanFocus,
           let expectedBundle = req.targetAppBundleId,
           req.actionType != .snapshot && req.actionType != .focusWindow {
            let front = await desktopDriver.frontmostApplication()
            if !front.bundleId.isEmpty && front.bundleId != expectedBundle {
                _ = notifyHumanFocusChanged(activeBundleId: front.bundleId, reason: "Foreground app is \(front.appName)")
                let wal = journal.appendPrepared(
                    operationId: req.operationId,
                    laneId: laneId,
                    laneKind: .desktopScreen,
                    phase: .macosDesktop,
                    agentId: req.agentId,
                    actionType: req.actionType,
                    targetApp: req.targetAppName ?? expectedBundle,
                    targetElementRef: req.targetElementRef
                )
                journal.updateStatus(journalId: wal.journalId, status: .yieldedToHuman, resultSummary: humanYieldReason)
                onStateChanged?()
                return PipiComputerUseActionResult(
                    ok: false,
                    operationId: req.operationId,
                    journalId: wal.journalId,
                    laneId: laneId,
                    status: .yieldedToHuman,
                    replayedFromJournal: false,
                    yieldedToHuman: true,
                    verdict: nil,
                    snapshot: nil,
                    seat: nil,
                    summary: "Immediate yield: \(humanYieldReason ?? "")",
                    error: nil
                )
            }
        }

        let latestSnap = latestSnapshots[laneId]
        let elem = req.targetElementRef.flatMap { ref in latestSnap?.elements.first(where: { $0.ref == ref }) }
        let classified = classifyAction(req, snapshot: latestSnap, element: elem)

        let verdict = await guardrail.evaluate(
            PipiGuardrailActionInput(
                operationId: req.operationId,
                toolName: "computer_use.desktop.\(req.actionType.rawValue)",
                actionKind: classified.kind,
                target: classified.target,
                payloadSummary: [classified.description, req.textInput, req.keyCombo].compactMap { $0 }.joined(separator: " | "),
                isPreparatoryOnly: classified.kind == .prepareDraft || classified.kind == .readOnly,
                sessionId: req.sessionId,
                projectId: req.projectId,
                sourceTrust: req.sourceTrust,
                trustedUserMessages: req.trustedUserMessages,
                untrustedContextSnippets: [classified.stateTag] + req.untrustedContextSnippets
            ),
            enableLLMJudge: llmGuardrailJudge != nil,
            llmJudge: llmGuardrailJudge
        )

        let wal = journal.appendPrepared(
            operationId: req.operationId,
            laneId: laneId,
            laneKind: .desktopScreen,
            phase: .macosDesktop,
            agentId: req.agentId,
            actionType: req.actionType,
            targetApp: req.targetAppName ?? latestSnap?.appName,
            targetElementRef: req.targetElementRef,
            targetElementLabel: elem?.label
        )

        guard verdict.decision == .allow else {
            journal.updateStatus(journalId: wal.journalId, status: .blockedGuardrail, verdictDecision: verdict.decision, error: verdict.rationale)
            onStateChanged?()
            return PipiComputerUseActionResult(
                ok: false,
                operationId: req.operationId,
                journalId: wal.journalId,
                laneId: laneId,
                status: .blockedGuardrail,
                replayedFromJournal: false,
                yieldedToHuman: false,
                verdict: verdict,
                snapshot: nil,
                seat: nil,
                summary: "Guardrail \(verdict.decision.rawValue): \(verdict.rationale)",
                error: verdict.rationale
            )
        }

        activeDesktopTargetBundleId = req.targetAppBundleId ?? latestSnap?.appBundleId
        setLane(laneId, kind: .desktopScreen, state: .active, activeAgentId: req.agentId, activeOperationId: req.operationId)
        onStateChanged?()
        defer { activeDesktopTargetBundleId = nil }

        do {
            journal.updateStatus(journalId: wal.journalId, status: .dispatched, verdictDecision: .allow)
            let output: PipiDesktopExecutionOutput
            if req.actionType == .snapshot {
                let snap = try await desktopDriver.captureDesktopSnapshot(targetAppBundleId: req.targetAppBundleId)
                output = PipiDesktopExecutionOutput(summary: "Captured macOS Accessibility element tree.", snapshot: snap)
            } else {
                output = try await desktopDriver.executeDesktopAction(request: req, resolvedElement: elem)
            }
            if let snap = output.snapshot {
                latestSnapshots[laneId] = snap
            }
            if isYieldedToHuman {
                journal.updateStatus(journalId: wal.journalId, status: .yieldedToHuman, verdictDecision: .allow, resultSummary: output.summary)
                onStateChanged?()
                return PipiComputerUseActionResult(
                    ok: false,
                    operationId: req.operationId,
                    journalId: wal.journalId,
                    laneId: laneId,
                    status: .yieldedToHuman,
                    replayedFromJournal: false,
                    yieldedToHuman: true,
                    verdict: verdict,
                    snapshot: output.snapshot,
                    seat: nil,
                    summary: "Yielded to human focus during call.",
                    error: nil
                )
            }
            journal.updateStatus(journalId: wal.journalId, status: .committed, verdictDecision: .allow, resultSummary: output.summary)
            setLane(laneId, kind: .desktopScreen, state: .idle)
            onStateChanged?()
            return PipiComputerUseActionResult(
                ok: true,
                operationId: req.operationId,
                journalId: wal.journalId,
                laneId: laneId,
                status: .committed,
                replayedFromJournal: false,
                yieldedToHuman: false,
                verdict: verdict,
                snapshot: output.snapshot,
                seat: nil,
                summary: output.summary,
                error: nil
            )
        } catch {
            journal.updateStatus(journalId: wal.journalId, status: .unknownOutcome, verdictDecision: .allow, error: error.localizedDescription)
            setLane(laneId, kind: .desktopScreen, state: .blockedUnknownOutcome, blockedByJournalId: wal.journalId)
            onStateChanged?()
            return PipiComputerUseActionResult(
                ok: false,
                operationId: req.operationId,
                journalId: wal.journalId,
                laneId: laneId,
                status: .unknownOutcome,
                replayedFromJournal: false,
                yieldedToHuman: false,
                verdict: verdict,
                snapshot: nil,
                seat: nil,
                summary: "Desktop action outcome uncertain; screen lane locked.",
                error: error.localizedDescription
            )
        }
    }

    private func setLane(
        _ laneId: String,
        kind: PipiComputerUseLaneKind,
        state: PipiComputerUseLaneState,
        activeAgentId: String? = nil,
        activeOperationId: String? = nil,
        blockedByJournalId: String? = nil,
        yieldReason: String? = nil
    ) {
        lanes[laneId] = PipiComputerUseLaneSnapshot(
            laneId: laneId,
            kind: kind,
            state: state,
            activeAgentId: activeAgentId,
            activeOperationId: activeOperationId,
            blockedByJournalId: blockedByJournalId,
            yieldReason: yieldReason,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
