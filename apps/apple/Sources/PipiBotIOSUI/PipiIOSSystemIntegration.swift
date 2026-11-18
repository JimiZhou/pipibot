import Foundation
import PipiBotKit

#if canImport(AppIntents)
import AppIntents
#endif

#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - 1. Deep-Link Routing (`pipibot://`)

public enum PipiIOSDeepLinkAction: Equatable, Sendable {
    case pairTunnel(urlString: String)
    case openTab(PipiIOSTab)
    case approveDecision(decisionId: String)
    case triggerDream
}

public enum PipiIOSDeepLinkRouter {
    public static func parse(_ url: URL) -> PipiIOSDeepLinkAction? {
        guard url.scheme?.lowercased() == "pipibot" else { return nil }
        let host = (url.host ?? "").lowercased()
        let pathParts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }

        switch host {
        case "pair":
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let tunnel = comps.queryItems?.first(where: { $0.name == "tunnel" })?.value,
               !tunnel.isEmpty {
                return .pairTunnel(urlString: tunnel)
            }
            return nil

        case "tab":
            guard let target = pathParts.first?.lowercased() else { return nil }
            switch target {
            case "outcomes": return .openTab(.outcomes)
            case "needs-you", "needsyou": return .openTab(.needsYou)
            case "muse": return .openTab(.muse)
            case "fleet", "soul": return .openTab(.fleetSoul)
            default: return nil
            }

        case "decision":
            // pipibot://decision/<id>/approve
            guard pathParts.count >= 2,
                  pathParts[1].lowercased() == "approve",
                  !pathParts[0].isEmpty else {
                return nil
            }
            return .approveDecision(decisionId: pathParts[0])

        case "dream":
            return .triggerDream

        default:
            return nil
        }
    }

    @MainActor
    public static func apply(
        _ action: PipiIOSDeepLinkAction,
        to store: PipiAppStore,
        selectedTab: inout PipiIOSTab
    ) {
        switch action {
        case .pairTunnel(let urlString):
            store.daemonEndpoint = urlString
            store.noticeBanner = "Paired with Cloudflare Tunnel: \(urlString)"
            Task { await store.refreshAllFromDaemon() }

        case .openTab(let tab):
            selectedTab = tab
            store.noticeBanner = "Opened \(tab.title) via deep link"

        case .approveDecision(let decisionId):
            selectedTab = .needsYou
            let optionId = store.decisions
                .first(where: { $0.id == decisionId })?
                .recommendedOptionId ?? "approve"
            Task {
                await store.resolveDecision(decisionId, optionId: optionId, note: "Approved via pipibot:// deep link")
            }

        case .triggerDream:
            selectedTab = .fleetSoul
            Task { await store.runNightlyDreaming() }
        }
    }
}

// MARK: - 2. Dynamic Island / Live Activity & Widget Snapshot Bridge

public struct PipiIOSLiveActivitySnapshot: Codable, Sendable, Equatable {
    public let avatarState: AvatarState53
    public let expression: AvatarExpression9
    public let activeHarness: HarnessProvider
    public let activeOutcomeTitle: String
    public let pendingDecisionsCount: Int
    public let tunnelRttMs: Int
    public let understandingScorePct: Double
    public let onlineNodesCount: Int
    public let updatedAt: String

    public init(
        avatarState: AvatarState53,
        expression: AvatarExpression9,
        activeHarness: HarnessProvider,
        activeOutcomeTitle: String,
        pendingDecisionsCount: Int,
        tunnelRttMs: Int,
        understandingScorePct: Double,
        onlineNodesCount: Int,
        updatedAt: String
    ) {
        self.avatarState = avatarState
        self.expression = expression
        self.activeHarness = activeHarness
        self.activeOutcomeTitle = activeOutcomeTitle
        self.pendingDecisionsCount = pendingDecisionsCount
        self.tunnelRttMs = tunnelRttMs
        self.understandingScorePct = understandingScorePct
        self.onlineNodesCount = onlineNodesCount
        self.updatedAt = updatedAt
    }
}

public enum PipiIOSWidgetBridge {
    public static func defaultSnapshotUrl() -> URL {
        PipiNativeMacRuntime.stateFileUrl()
            .deletingLastPathComponent()
            .appendingPathComponent("ios-live-activity-snapshot.json", isDirectory: false)
    }

    @MainActor
    public static func snapshot(from store: PipiAppStore) -> PipiIOSLiveActivitySnapshot {
        let meta = PipiProceduralAvatarEngine.metadata(for: store.avatarEngine.state)
        return PipiIOSLiveActivitySnapshot(
            avatarState: store.avatarEngine.state,
            expression: meta.expression,
            activeHarness: store.activeHarness,
            activeOutcomeTitle: store.outcomes.first?.title ?? "Autonomous Fleet",
            pendingDecisionsCount: store.pendingDecisions.count,
            tunnelRttMs: store.tunnelStatus.tunnelRttMs,
            understandingScorePct: store.understandingScore.overall,
            onlineNodesCount: store.onlineFleetCount,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    public static func saveSnapshot(
        _ snapshot: PipiIOSLiveActivitySnapshot,
        to url: URL = defaultSnapshotUrl()
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    public static func loadSnapshot(
        from url: URL = defaultSnapshotUrl()
    ) -> PipiIOSLiveActivitySnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PipiIOSLiveActivitySnapshot.self, from: data)
    }
}

// MARK: - 3. Actionable Lock-Screen Notifications (UNUserNotificationCenter)

#if canImport(UserNotifications)
public enum PipiIOSNotificationManager {
    public static let needsYouCategory = "NEEDS_YOU_DECISION"
    public static let evolutionDigestCategory = "EVOLUTION_DIGEST"

    public static let approveActionId = "APPROVE_ACTION"
    public static let steerActionId = "STEER_ACTION"
    public static let rejectActionId = "REJECT_ACTION"
    public static let approveDiffActionId = "APPROVE_DIFF_ACTION"
    public static let openSoulActionId = "OPEN_SOUL_ACTION"

    public static func buildNotificationCategories() -> Set<UNNotificationCategory> {
        let approveAction = UNNotificationAction(
            identifier: approveActionId,
            title: "Approve",
            options: [.authenticationRequired]
        )
        let steerAction = UNTextInputNotificationAction(
            identifier: steerActionId,
            title: "Steer",
            options: [.authenticationRequired],
            textInputButtonTitle: "Send Steer",
            textInputPlaceholder: "Guide sub-session..."
        )
        let rejectAction = UNNotificationAction(
            identifier: rejectActionId,
            title: "Reject",
            options: [.destructive]
        )
        let needsYouCat = UNNotificationCategory(
            identifier: needsYouCategory,
            actions: [approveAction, steerAction, rejectAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        let approveDiff = UNNotificationAction(
            identifier: approveDiffActionId,
            title: "Commit to USER.md",
            options: [.authenticationRequired]
        )
        let openSoul = UNNotificationAction(
            identifier: openSoulActionId,
            title: "Review Soul Diff",
            options: [.foreground]
        )
        let digestCat = UNNotificationCategory(
            identifier: evolutionDigestCategory,
            actions: [approveDiff, openSoul],
            intentIdentifiers: [],
            options: []
        )

        return [needsYouCat, digestCat]
    }

    @MainActor
    public static func configureCategoriesIfSupported() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().setNotificationCategories(buildNotificationCategories())
    }

    @MainActor
    public static func requestAuthorizationIfNeeded() async -> Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories(buildNotificationCategories())
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    @MainActor
    public static func scheduleNeedsYouNotification(for decision: NeedsYouDecision) async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = decision.title
        content.subtitle = "Needs You · \(decision.category.displayName)"
        content.body = decision.summary
        content.categoryIdentifier = needsYouCategory
        content.sound = .default
        content.userInfo = [
            "decisionId": decision.id,
            "recommendedOptionId": decision.recommendedOptionId
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(
            identifier: "pipibot.decision.\(decision.id)",
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(req)
    }
}
#endif

// MARK: - 4. Apple AppIntents (Siri, Shortcuts & iPhone Action Button)

#if canImport(AppIntents)
@available(iOS 17.0, macOS 14.0, *)
public struct PipiApproveTopDecisionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Approve Top PipiBot Decision"
    public static let description = IntentDescription("Approves the highest-priority pending Needs You escalation across your PipiBot fleet.")

    @Parameter(title: "Approval Note")
    public var note: String?

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = await MainActor.run { () -> String in
            let store = PipiAppStore(autoConnect: false, enableNativeRuntime: true)
            guard let top = store.pendingDecisions.first else {
                return "All Needs You decisions are already clear."
            }
            Task {
                await store.resolveDecision(top.id, optionId: top.recommendedOptionId, note: note ?? "Approved via Siri / Action Button")
            }
            return "Approved \(top.title) across \(store.onlineFleetCount) fleet nodes."
        }
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}

@available(iOS 17.0, macOS 14.0, *)
public struct PipiTriggerNightlyDreamIntent: AppIntent {
    public static let title: LocalizedStringResource = "Run PipiBot Nightly Dreaming"
    public static let description = IntentDescription("Triggers L0-L3 memory consolidation and computes the updated Understanding Score.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialogText = await MainActor.run { () -> String in
            let store = PipiAppStore(autoConnect: false, enableNativeRuntime: true)
            Task { await store.runNightlyDreaming() }
            let snapshot = PipiIOSWidgetBridge.snapshot(from: store)
            try? PipiIOSWidgetBridge.saveSnapshot(snapshot)
            return String(format: "Nightly Dreaming started. Understanding Score %.1f%%.", store.understandingScore.overall)
        }
        return .result(dialog: IntentDialog(stringLiteral: dialogText))
    }
}

@available(iOS 17.0, macOS 14.0, *)
public struct PipiAskHarnessIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ask PipiBot Harness"
    public static let description = IntentDescription("Routes an instruction to Pi, Claude Code, Codex, OpenCode, or BYOK.")

    @Parameter(title: "Instruction")
    public var prompt: String

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await MainActor.run { () -> String in
            let store = PipiAppStore(autoConnect: false, enableNativeRuntime: true)
            Task { await store.sendChatMessage(prompt) }
            return "Routed via \(store.activeHarness.displayName): \(prompt)"
        }
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

@available(iOS 17.0, macOS 14.0, *)
public struct PipiIOSShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PipiApproveTopDecisionIntent(),
            phrases: [
                "Approve decision with \(.applicationName)",
                "Clear Needs You inbox in \(.applicationName)"
            ],
            shortTitle: "Approve Decision",
            systemImageName: "checkmark.seal.fill"
        )
        AppShortcut(
            intent: PipiTriggerNightlyDreamIntent(),
            phrases: [
                "Run nightly dream in \(.applicationName)",
                "Consolidate memory with \(.applicationName)"
            ],
            shortTitle: "Nightly Dream",
            systemImageName: "moon.stars.fill"
        )
        AppShortcut(
            intent: PipiAskHarnessIntent(),
            phrases: [
                "Ask \(.applicationName) to inspect my fleet",
                "Route task with \(.applicationName)"
            ],
            shortTitle: "Ask Harness",
            systemImageName: "sparkles"
        )
    }
}
#endif
