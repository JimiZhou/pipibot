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
    case openVoice
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
            case "chat", "muse": return .openTab(.chat)
            case "bots", "outcomes": return .openTab(.bots)
            case "tasks", "needs-you", "needsyou": return .openTab(.tasks)
            case "settings", "fleet", "soul": return .openTab(.settings)
            default: return nil
            }

        case "decision":
            guard pathParts.count >= 2,
                  pathParts[1].lowercased() == "approve",
                  !pathParts[0].isEmpty else {
                return nil
            }
            return .approveDecision(decisionId: pathParts[0])

        case "dream":
            return .triggerDream

        case "voice", "call":
            return .openVoice

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
            store.noticeBanner = store.strings.t("已连接到远程地址", "Connected to remote endpoint")
            Task { await store.refreshAllFromDaemon() }

        case .openTab(let tab):
            selectedTab = tab

        case .openVoice:
            selectedTab = .chat
            Task { await store.startVoiceCall(with: store.activePersona.id) }

        case .approveDecision(let decisionId):
            selectedTab = .tasks
            let optionId = store.decisions
                .first(where: { $0.id == decisionId })?
                .recommendedOptionId ?? "approve"
            Task {
                await store.resolveDecision(decisionId, optionId: optionId, note: "Approved via pipibot://")
            }

        case .triggerDream:
            selectedTab = .settings
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
            activeOutcomeTitle: store.activePersona.name(store.resolvedLanguage),
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
        let s = PipiStrings(.system)
        let approveAction = UNNotificationAction(
            identifier: approveActionId,
            title: s.approve,
            options: [.authenticationRequired]
        )
        let steerAction = UNTextInputNotificationAction(
            identifier: steerActionId,
            title: s.t("补充说明", "Reply"),
            options: [.authenticationRequired],
            textInputButtonTitle: s.send,
            textInputPlaceholder: s.chatPlaceholderCompact
        )
        let rejectAction = UNNotificationAction(
            identifier: rejectActionId,
            title: s.reject,
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
            title: s.t("保存到记忆", "Save Memory"),
            options: [.authenticationRequired]
        )
        let openSoul = UNNotificationAction(
            identifier: openSoulActionId,
            title: s.t("查看详情", "Review"),
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
        content.subtitle = "PipiBot · \(decision.category.displayName)"
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

// MARK: - 4. Apple AppIntents (Siri, Shortcuts & Action Button)

#if canImport(AppIntents)
@available(iOS 17.0, macOS 14.0, *)
public struct PipiApproveTopDecisionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Approve Top PipiBot Request"
    public static let description = IntentDescription("Approves the highest-priority pending request in PipiBot.")

    @Parameter(title: "Note")
    public var note: String?

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = await MainActor.run { () -> String in
            let store = PipiAppStore(autoConnect: false, enableNativeRuntime: true)
            guard let top = store.pendingDecisions.first else {
                return store.strings.approvalsEmptyTitle
            }
            Task {
                await store.resolveDecision(top.id, optionId: top.recommendedOptionId, note: note ?? "Approved via Shortcuts")
            }
            return store.strings.t("已批准：\(top.title)", "Approved: \(top.title)")
        }
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}

@available(iOS 17.0, macOS 14.0, *)
public struct PipiTriggerNightlyDreamIntent: AppIntent {
    public static let title: LocalizedStringResource = "Consolidate PipiBot Memory"
    public static let description = IntentDescription("Consolidates your personal PipiBot memory preferences.")

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialogText = await MainActor.run { () -> String in
            let store = PipiAppStore(autoConnect: false, enableNativeRuntime: true)
            Task { await store.runNightlyDreaming() }
            let snapshot = PipiIOSWidgetBridge.snapshot(from: store)
            try? PipiIOSWidgetBridge.saveSnapshot(snapshot)
            return store.strings.t("已开始整理 PipiBot 个人记忆。", "Started PipiBot memory consolidation.")
        }
        return .result(dialog: IntentDialog(stringLiteral: dialogText))
    }
}

@available(iOS 17.0, macOS 14.0, *)
public struct PipiAskHarnessIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ask PipiBot"
    public static let description = IntentDescription("Send a quick message to your active PipiBot persona.")

    @Parameter(title: "Message")
    public var prompt: String

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await MainActor.run { () -> String in
            let store = PipiAppStore(autoConnect: false, enableNativeRuntime: true)
            Task { await store.sendPersonalMessage(prompt) }
            return store.strings.t("已发送给 PipiBot：\(prompt)", "Sent to PipiBot: \(prompt)")
        }
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

@available(iOS 17.0, macOS 14.0, *)
public struct PipiStartVoiceAssistantIntent: AppIntent {
    public static let title: LocalizedStringResource = "Talk to PipiBot"
    public static let description = IntentDescription("Launch PipiBot's ambient voice companion directly from the iPhone Action Button or Siri.")
    public static let openAppWhenRun: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: IntentDialog("Starting PipiBot voice companion."))
    }
}

@available(iOS 17.0, macOS 14.0, *)
public struct PipiIOSShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PipiStartVoiceAssistantIntent(),
            phrases: [
                "Talk to \(.applicationName)",
                "Start voice in \(.applicationName)"
            ],
            shortTitle: "Talk to PipiBot",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: PipiApproveTopDecisionIntent(),
            phrases: [
                "Approve request in \(.applicationName)",
                "Clear pending approvals in \(.applicationName)"
            ],
            shortTitle: "Approve Request",
            systemImageName: "checkmark.seal.fill"
        )
        AppShortcut(
            intent: PipiTriggerNightlyDreamIntent(),
            phrases: [
                "Consolidate memory in \(.applicationName)"
            ],
            shortTitle: "Consolidate Memory",
            systemImageName: "brain"
        )
        AppShortcut(
            intent: PipiAskHarnessIntent(),
            phrases: [
                "Ask \(.applicationName) a question",
                "Chat with \(.applicationName)"
            ],
            shortTitle: "Ask PipiBot",
            systemImageName: "bubble.left.and.bubble.right.fill"
        )
    }
}
#endif
