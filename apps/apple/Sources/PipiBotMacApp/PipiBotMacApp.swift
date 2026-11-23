import SwiftUI
import PipiBotKit

#if os(macOS)
import AppKit

@MainActor
final class PipiMacAppDelegate: NSObject, NSApplicationDelegate {
    var onGlobalQuickBarHotkey: (@MainActor () -> Void)?
    var onOpenExternalURL: (@MainActor (URL) -> Void)?
    private var queuedExternalURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let handler = onOpenExternalURL {
                handler(url)
            } else {
                queuedExternalURLs.append(url)
            }
        }
    }

    func flushQueuedExternalURLs() {
        guard let handler = onOpenExternalURL, !queuedExternalURLs.isEmpty else { return }
        let pending = queuedExternalURLs
        queuedExternalURLs.removeAll()
        for url in pending {
            handler(url)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: prevent two PiPiBot copies from coexisting simultaneously
        if let bundleId = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let existing = others.first {
                existing.activate(options: [.activateAllWindows])
                NSApp.terminate(nil)
                return
            }
        }
        NSApp.setActivationPolicy(.regular)
        if let iconUrl = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconUrl) {
            NSApplication.shared.applicationIconImage = iconImage
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            PipiGlobalScrollbarSuppressor.shared.install()
            for window in NSApp.windows where window.canBecomeMain {
                Self.configureNativeWindowChrome(window)
                window.makeKeyAndOrderFront(nil)
            }
        }
        PipiGlobalHotkeyManager.shared.registerOptionSpace { [weak self] in
            self?.onGlobalQuickBarHotkey?()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        for window in NSApp.windows where window.canBecomeMain {
            Self.configureNativeWindowChrome(window)
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    static func configureNativeWindowChrome(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.toolbarStyle = .unified
    }
}

@main
struct PipiBotMacApp: App {
    @NSApplicationDelegateAdaptor(PipiMacAppDelegate.self) private var appDelegate
    @State private var store: PipiAppStore
    @State private var quickBarController = PipiQuickBarController()
    @State private var showSettingsSheet = false
    @State private var showAboutSheet = false
    @State private var settingsInitialTab: PipiSettingsTab = .general
    @State private var menuBarDraft = ""
    @State private var lastHandledURLString: String?
    @State private var lastHandledURLTimestamp: Date = .distantPast
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init() {
        if PipiShowcaseScreenshotExporter.exportIfRequested() {
            Darwin.exit(0)
        }
        let residentStore = PipiAppStore(
            autoConnect: true,
            enableNativeRuntime: true,
            enableEmbeddedBridge: false,
            seedDemoData: false
        )
        if !residentStore.personas.contains(where: { $0.id == PipiBotPersona.securityAuditorId }) {
            residentStore.personas.append(PipiBotPersona.securityAuditorDefault)
        }
        _store = State(initialValue: residentStore)

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                PipiGlobalHotkeyManager.shared.unregister()
                residentStore.stopLiveSync()
                residentStore.stopRemoteTunnel()
                residentStore.disconnectWeChatILink(forgetBinding: false)
                residentStore.localModelPlatformManager.stopAllManagedServers()
                residentStore.telemetryMonitor.stopPolling()
                residentStore.bridgeSupervisor.stopBridge()
                residentStore.flush()
            }
        }
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    var body: some Scene {
        WindowGroup("PiPiBot", id: "main") {
            mainRootView
                .frame(minWidth: 960, minHeight: 660)
                .onAppear {
                    PipiGlobalScrollbarSuppressor.shared.install()
                    appDelegate.onGlobalQuickBarHotkey = {
                        toggleQuickBar()
                    }
                    appDelegate.onOpenExternalURL = { url in
                        handleIncomingURL(url)
                    }
                    appDelegate.flushQueuedExternalURLs()
                    for window in NSApp.windows where window.canBecomeMain {
                        PipiMacAppDelegate.configureNativeWindowChrome(window)
                    }
                    // Auto-restore unified account session & connect E2EE relay on launch
                    Task {
                        await store.syncAccountAndAutoConnectRelay()
                    }
                }
                .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
                    store.e2eeRelayClient.handleSystemWake()
                    Task {
                        await store.syncAccountAndAutoConnectRelay()
                    }
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
        .handlesExternalEvents(matching: Set(["pipibot"]))
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .appInfo) {
                Button(s.aboutTitle) {
                    showAboutSheet = true
                }
            }

            CommandGroup(replacing: .newItem) {
                Button(s.newChat) {
                    if store.hasCompletedOnboarding {
                        _ = store.createConversation()
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(replacing: .appSettings) {
                Button(s.settings) {
                    settingsInitialTab = .general
                    showSettingsSheet = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("PiPiBot") {
                Button(s.openCommandPalette) {
                    if store.hasCompletedOnboarding {
                        store.isCommandPalettePresented.toggle()
                    }
                }
                .keyboardShortcut("k", modifiers: .command)

                Button(s.quickBarShortcut) {
                    toggleQuickBar()
                }

                Button(s.stop) {
                    store.stopGenerating()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!store.isGeneratingReply)

                Divider()

                ForEach(Array(store.personas.prefix(4).enumerated()), id: \.element.id) { index, persona in
                    Button(persona.name(lang)) {
                        if let existing = store.conversations
                            .filter({ $0.personaId == persona.id && !$0.isArchived })
                            .sorted(by: { $0.updatedAt > $1.updatedAt })
                            .first {
                            store.selectPersona(persona.id)
                            store.selectConversation(existing.id)
                        } else {
                            _ = store.createConversation(for: persona.id, activate: true)
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }

                Divider()

                Button(s.rescanAgents) {
                    Task { await store.refreshLocalAgents() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button(s.zoomIn) {
                    store.zoomIn()
                }
                .keyboardShortcut("=", modifiers: .command)

                Button(s.zoomIn) {
                    store.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button(s.zoomOut) {
                    store.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button(s.zoomReset) {
                    store.resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }

        MenuBarExtra {
            menuBarPopover
                .environment(\.pipiTextScale, store.uiZoomScale)
                .onAppear {
                    appDelegate.onGlobalQuickBarHotkey = {
                        toggleQuickBar()
                    }
                    if store.accountClient.isSignedIn {
                        Task { await store.accountClient.refreshProfile() }
                    }
                }
        } label: {
            if let icon = Self.menuBarAppIconImage {
                Image(nsImage: icon)
            } else {
                Image(systemName: "circle.hexagongrid.fill")
            }
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var mainRootView: some View {
        ZStack(alignment: .top) {
            ZStack {
                if !store.hasCompletedOnboarding {
                    PipiOnboardingView(store: store, initialStep: store.onboardingInitialStep)
                        .transition(.opacity)
                } else {
                    PipiWorkspaceView(
                        store: store,
                        onToggleQuickBar: { toggleQuickBar() },
                        onOpenSettings: { tab in
                            settingsInitialTab = tab
                            showSettingsSheet = true
                        }
                    )
                    .transition(.opacity)
                }
            }
            .environment(\.pipiTextScale, store.uiZoomScale)
            .animation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion), value: store.hasCompletedOnboarding)

            if store.showZoomHUD {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                    Text(store.uiZoomPercentLabel)
                        .font(PipiTokens.fontMono.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(PipiTokens.textPrimary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .pipiLiquidGlass(cornerRadius: PipiTokens.radiusPill, shadowRadius: 12, shadowY: 4)
                .padding(.top, 16)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
                .allowsHitTesting(false)
            }
        }
        .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: store.showZoomHUD)
        .sheet(isPresented: $showSettingsSheet) {
            PipiSettingsView(
                store: store,
                initialTab: settingsInitialTab,
                onClose: { showSettingsSheet = false },
                onToggleQuickBar: { toggleQuickBar() }
            )
            .environment(\.pipiTextScale, store.uiZoomScale)
            .frame(minWidth: 800, minHeight: 560)
        }
        .sheet(isPresented: $showAboutSheet) {
            PipiAboutSheetView(
                store: store,
                onClose: { showAboutSheet = false }
            )
            .environment(\.pipiTextScale, store.uiZoomScale)
            .frame(minWidth: 580, minHeight: 560)
        }
    }

    private static let menuBarAppIconImage: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let raw = NSImage(contentsOf: url) else {
            return nil
        }
        let targetSize = NSSize(width: 18, height: 18)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        raw.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .sourceOver, fraction: 1.0)
        resized.unlockFocus()
        resized.isTemplate = false
        return resized
    }()

    private var menuBarPopover: some View {
        let _ = store.uiZoomScale
        let snap = store.telemetryMonitor.snapshot
        let onlineNodes = 1 + store.enrolledRemoteDevices.filter(\.isOnline).count
        return VStack(alignment: .leading, spacing: 10) {
            // 1. Compact Status Header
            HStack(spacing: 10) {
                if let icon = Self.menuBarAppIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    PipiBotPersonaGlyph(persona: store.activePersona, size: 28, isSelected: true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.localHost.displayName(lang))
                        .font(PipiTokens.fontBody.weight(.semibold))
                        .foregroundStyle(PipiTokens.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(PipiTokens.stateSuccess)
                            .frame(width: 6, height: 6)
                        Text(store.accountClient.isSignedIn
                             ? s.t("在线 · \(onlineNodes) 台节点就绪", "Online · \(onlineNodes) nodes ready")
                             : s.t("本机运行中", "Running locally"))
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if !store.accountClient.isSignedIn {
                    Button(s.t("登录", "Sign In")) {
                        Task {
                            await store.accountClient.startBrowserOAuthLogin {
                                Task { await store.syncAccountAndAutoConnectRelay() }
                            }
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }

            // 2. Compact Telemetry & Enrolled Nodes Card
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text(String(format: "CPU %.0f%%", snap.cpuUsagePercent))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(PipiTokens.textSecondary)
                    Text("·")
                        .foregroundStyle(PipiTokens.textMuted)
                    Text(String(format: s.t("内存 %.1f/%.0f GB", "RAM %.1f/%.0f GB"), snap.memoryUsedGB, snap.memoryTotalGB))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(PipiTokens.textSecondary)
                    Spacer()
                    if let email = store.accountClient.currentUser?.email {
                        Text(email)
                            .font(.system(size: 10.5))
                            .foregroundStyle(PipiTokens.textMuted)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                if !store.enrolledRemoteDevices.isEmpty {
                    Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.enrolledRemoteDevices.prefix(4)) { dev in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(dev.isOnline ? PipiTokens.stateSuccess : PipiTokens.textMuted.opacity(0.45))
                                    .frame(width: 6, height: 6)
                                Text(dev.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(PipiTokens.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(dev.capabilities.isEmpty ? dev.platform : "\(dev.capabilities.count) Harness")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(PipiTokens.textMuted)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }

                Rectangle().fill(PipiTokens.borderSubtle).frame(height: 1)
                HStack {
                    Text(s.keepAwakeTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PipiTokens.textPrimary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { store.bridgeSupervisor.keepAwakeEnabled },
                        set: { store.setKeepAwake($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .background(PipiTokens.bgSurface)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if store.totalNeedsYouCount > 0 {
                Button {
                    bringMainWindowFront()
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(PipiTokens.stateWarning).frame(width: 6, height: 6)
                        Text(s.t("有 \(store.totalNeedsYouCount) 项待确认审批", "\(store.totalNeedsYouCount) pending approvals"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(PipiTokens.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PipiTokens.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(PipiTokens.stateWarning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // 3. Clean Quick Actions
            VStack(alignment: .leading, spacing: 2) {
                menuBarRowButton(icon: "macwindow", title: s.openPipiBot) {
                    bringMainWindowFront()
                }
                menuBarRowButton(icon: "globe", title: s.t("打开云端工作台", "Open Cloud WebUI")) {
                    if let url = URL(string: "\(store.accountClient.relayOrigin)/app") {
                        NSWorkspace.shared.open(url)
                    }
                }
                menuBarRowButton(icon: "command", title: s.quickBarShortcut) {
                    toggleQuickBar()
                }
                menuBarRowButton(icon: "gearshape", title: s.settings) {
                    bringMainWindowFront()
                    settingsInitialTab = .general
                    showSettingsSheet = true
                }
                Divider().padding(.vertical, 3)
                menuBarRowButton(icon: "power", title: s.t("退出 PiPiBot", "Quit PiPiBot"), isDestructive: true) {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 288)
        .background {
            if reduceTransparency {
                PipiTokens.bgElevated
            } else {
                Color.clear.background(.thinMaterial)
            }
        }
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
    }

    private func menuBarRowButton(icon: String, title: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isDestructive ? Color.red : PipiTokens.textSecondary)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(isDestructive ? Color.red : PipiTokens.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "pipibot" else { return }
        let now = Date()
        if lastHandledURLString == url.absoluteString,
           now.timeIntervalSince(lastHandledURLTimestamp) < 1.5 {
            return
        }
        lastHandledURLString = url.absoluteString
        lastHandledURLTimestamp = now

        let host = (url.host ?? "").lowercased()
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryMap = Dictionary(
            (comps?.queryItems ?? []).compactMap { item in
                item.value.map { (item.name.lowercased(), $0) }
            },
            uniquingKeysWith: { _, last in last }
        )
        if host == "notify" {
            let title = queryMap["title"] ?? "PiPiBot 通知"
            let body = queryMap["body"] ?? ""
            Task { @MainActor in
                await store.deliverSystemAndWeChatNotification(title: title, body: body)
            }
        } else if host == "check-updates" {
            Task { @MainActor in
                _ = await store.updateManager.checkForUpdates(currentVersion: store.appDisplayVersion, silent: false)
            }
        }
    }

    private func toggleQuickBar() {
        quickBarController.toggle(store: store) {
            bringMainWindowFront()
        }
    }

    private func bringMainWindowFront() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func submitMenuBarPrompt() {
        let text = menuBarDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        menuBarDraft = ""
        if !store.hasCompletedOnboarding {
            store.completeOnboarding()
        }
        let newConv = store.createConversation(for: store.activePersona.id, activate: true)
        bringMainWindowFront()
        Task {
            await store.sendPersonalMessage(
                text,
                conversationId: newConv.id,
                personaId: store.activePersona.id,
                activateTargetConversation: true
            )
        }
    }
}
#endif
