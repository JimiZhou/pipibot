import SwiftUI
import PipiBotKit

#if os(macOS)
import AppKit

@main
struct PipiBotMacApp: App {
    @State private var store: PipiAppStore
    @State private var cueController = ManusCuePanelController()
    @Environment(\.openWindow) private var openWindow

    init() {
        let residentStore = PipiAppStore(
            autoConnect: true,
            enableNativeRuntime: true,
            enableEmbeddedBridge: true
        )
        _store = State(initialValue: residentStore)

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                residentStore.stopLiveSync()
            }
        }
    }

    var body: some Scene {
        WindowGroup("PipiBot Outcome Studio", id: "studio") {
            MacOutcomeStudioView(store: store) {
                cueController.toggle(store: store)
            }
            .frame(minWidth: 960, minHeight: 680)
        }
        .commands {
            CommandMenu("PipiBot") {
                Button("Toggle Manus Cue Pill") {
                    cueController.toggle(store: store)
                }
                .keyboardShortcut(.space, modifiers: .option)

                Button("Refresh Native Context & Probes") {
                    store.refreshNativeRuntimeSnapshot()
                    Task { await store.refreshAllFromDaemon() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra {
            menuBarPopover
        } label: {
            HStack(spacing: 4) {
                PipiAvatarView(engine: store.avatarEngine, size: 22, interactive: false, compactMode: true)
                if !store.pendingDecisions.isEmpty {
                    Text("\(store.pendingDecisions.count)")
                        .font(PipiTokens.fontMicro)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarPopover: some View {
        let keepAwakeBinding = Binding<Bool>(
            get: { store.bridgeSupervisor.keepAwakeEnabled },
            set: { store.setKeepAwake($0) }
        )

        return VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack(spacing: PipiTokens.spacing12) {
                PipiAvatarView(engine: store.avatarEngine, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PipiBot Resident")
                        .font(PipiTokens.fontHeadline)
                        .foregroundStyle(PipiTokens.textPrimary)
                    Text(PipiProceduralAvatarEngine.metadata(for: store.avatarEngine.state).label)
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.color(for: store.avatarEngine.state))
                }
                Spacer()
                Text(store.connectionMode == .liveDaemon ? "Bridge Live" : "Native")
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(store.connectionMode == .liveDaemon ? PipiTokens.stateSuccess : PipiTokens.soulSecondary)
                    .padding(.horizontal, PipiTokens.spacing8)
                    .padding(.vertical, 3)
                    .background(PipiTokens.bgInset)
                    .clipShape(Capsule())
            }

            // Native Resident Controls (Keep-Awake + Embedded iOS Bridge)
            HStack(spacing: PipiTokens.spacing8) {
                Toggle(isOn: keepAwakeBinding) {
                    Text("Keep-Awake")
                        .font(PipiTokens.fontCaption.weight(.medium))
                        .foregroundStyle(PipiTokens.textPrimary)
                }
                .toggleStyle(.switch)

                Spacer()

                Text(store.bridgeSupervisor.bridgeState.rawValue)
                    .font(PipiTokens.fontMonoSmall)
                    .foregroundStyle(store.connectionMode == .liveDaemon ? PipiTokens.stateSuccess : PipiTokens.textMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, PipiTokens.spacing12)
            .padding(.vertical, PipiTokens.spacing8)
            .background(PipiTokens.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD))

            // Dots Fleet Vitality Strip
            HStack(spacing: PipiTokens.spacing12) {
                ForEach(store.fleetNodes) { node in
                    HStack(spacing: 4) {
                        PipiDotIndicator(vitality: node.vitality, color: PipiTokens.color(for: node.vitality), size: 7)
                        Text(node.kind.rawValue)
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textSecondary)
                    }
                }
            }
            .padding(PipiTokens.spacing8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PipiTokens.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD))

            if let topDecision = store.pendingDecisions.first {
                PipiListCard(
                    title: topDecision.title,
                    subtitle: topDecision.summary,
                    badgeText: "Needs You",
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
                PipiActionButton("Manus Cue (⌥Space)", systemImage: "sparkles", tone: .secondary, density: .desktopCompact, fullWidth: true) {
                    cueController.toggle(store: store)
                }
                PipiActionButton("Open Studio", systemImage: "macwindow", tone: .primary, density: .desktopCompact, fullWidth: true) {
                    openWindow(id: "studio")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
        }
        .padding(PipiTokens.spacing16)
        .frame(width: 390)
        .background(PipiTokens.bgElevated)
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
    }
}
#endif
