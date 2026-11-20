import SwiftUI
import PipiBotKit

#if os(macOS)
import AppKit

@MainActor
final class PipiMacAppDelegate: NSObject, NSApplicationDelegate {
    var onGlobalQuickBarHotkey: (@MainActor () -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init() {
        let residentStore = PipiAppStore(
            autoConnect: true,
            enableNativeRuntime: true,
            enableEmbeddedBridge: false,
            seedDemoData: false
        )
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
                    for window in NSApp.windows where window.canBecomeMain {
                        PipiMacAppDelegate.configureNativeWindowChrome(window)
                    }
                }
        }
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
                }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                Text(store.totalNeedsYouCount == 0 ? "PiPiBot" : "PiPiBot (\(store.totalNeedsYouCount))")
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

    private var menuBarPopover: some View {
        let _ = store.uiZoomScale
        return VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack(spacing: PipiTokens.spacing12) {
                PipiBotPersonaGlyph(persona: store.activePersona, size: 36, isSelected: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.activePersona.name(lang))
                        .font(PipiTokens.fontHeadline)
                        .tracking(PipiTokens.trackingHeadline)
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text(store.activeEngineDisplayLabel())
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(store.hasConfiguredEngine ? PipiTokens.stateSuccess : PipiTokens.stateWarning)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    bringMainWindowFront()
                    settingsInitialTab = .general
                    showSettingsSheet = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(PipiTokens.bgSurface)
                        .overlay(Circle().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                        .clipShape(Circle())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.94))
                .help(s.settings)
                .accessibilityLabel(s.settings)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: PipiTokens.spacing8) {
                    TextField(s.chatPlaceholderCompact, text: $menuBarDraft)
                        .textFieldStyle(.plain)
                        .font(PipiTokens.fontBody)
                        .padding(.horizontal, PipiTokens.spacing12)
                        .frame(height: 34)
                        .background(PipiTokens.bgSurface)
                        .overlay(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous).stroke(PipiTokens.borderSubtle, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                        .onSubmit {
                            submitMenuBarPrompt()
                        }

                    PipiActionButton(s.send, systemImage: "arrow.up", tone: .primary, density: .desktopCompact) {
                        submitMenuBarPrompt()
                    }
                    .disabled(menuBarDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text(s.menuBarNewSessionHint)
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(PipiTokens.textMuted)
            }

            if let topDecision = store.pendingDecisions.first {
                PipiListCard(
                    title: topDecision.title,
                    subtitle: topDecision.summary,
                    badgeText: s.approvalsTitle,
                    badgeColor: PipiTokens.stateWarning,
                    footer: {
                        if let rec = topDecision.options.first(where: { $0.id == topDecision.recommendedOptionId }) {
                            PipiActionButton(rec.label, systemImage: "checkmark", tone: .primary, density: .desktopCompact, fullWidth: true) {
                                Task { await store.resolveDecision(topDecision.id, optionId: rec.id) }
                            }
                        }
                    }
                )
            }

            HStack(spacing: PipiTokens.spacing8) {
                PipiActionButton(s.quickBarShortcut, systemImage: "command", tone: .secondary, density: .desktopCompact, fullWidth: true) {
                    toggleQuickBar()
                }
                PipiActionButton(s.openPipiBot, systemImage: "macwindow", tone: .primary, density: .desktopCompact, fullWidth: true) {
                    bringMainWindowFront()
                }
            }
        }
        .padding(PipiTokens.spacing16)
        .frame(width: 372)
        .background {
            if reduceTransparency {
                PipiTokens.bgElevated
            } else {
                Color.clear.background(.thinMaterial)
            }
        }
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
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
