import SwiftUI
import PipiBotKit

#if os(macOS)
import AppKit

@MainActor
@Observable
public final class ManusCuePanelController {
    private var panel: NSPanel?
    public var isVisible: Bool = false

    public init() {}

    public func toggle(store: PipiAppStore) {
        if isVisible {
            hide(store: store)
        } else {
            show(store: store)
        }
    }

    public func show(store: PipiAppStore) {
        if panel == nil {
            let created = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 156),
                styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            created.level = .floating
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            created.isFloatingPanel = true
            created.hidesOnDeactivate = false
            created.backgroundColor = .clear
            created.isOpaque = false
            created.hasShadow = true
            created.isMovableByWindowBackground = true

            let hostView = NSHostingView(
                rootView: ManusCuePillContentView(store: store, onDismiss: { [weak self] in
                    self?.hide(store: store)
                })
            )
            created.contentView = hostView
            panel = created
        }

        if let screen = NSScreen.main ?? NSScreen.screens.first, let panel {
            let frame = screen.visibleFrame
            let x = frame.midX - (panel.frame.width * 0.5)
            let y = frame.maxY - panel.frame.height - 72
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        store.avatarEngine.setState(.manusCue)
        panel?.orderFrontRegardless()
        isVisible = true
        store.isCuePanelVisible = true
    }

    public func hide(store: PipiAppStore) {
        panel?.orderOut(nil)
        isVisible = false
        store.isCuePanelVisible = false
    }
}
#endif

public struct ManusCuePillContentView: View {
    @Bindable public var store: PipiAppStore
    public var onDismiss: () -> Void

    public init(store: PipiAppStore, onDismiss: @escaping () -> Void = {}) {
        self.store = store
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack(spacing: PipiTokens.spacing12) {
                PipiAvatarView(engine: store.avatarEngine, size: 38, compactMode: false)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: PipiTokens.spacing8) {
                        Text("Manus Cue")
                            .font(PipiTokens.fontSubheadline.weight(.semibold))
                            .foregroundStyle(PipiTokens.textPrimary)

                        if let cue = store.latestCue {
                            Text("\(cue.activeAppName) · \(cue.gitBranch ?? "workspace")")
                                .font(PipiTokens.fontMonoSmall)
                                .foregroundStyle(PipiTokens.soulSecondary)
                                .padding(.horizontal, PipiTokens.spacing8)
                                .padding(.vertical, 2)
                                .background(PipiTokens.bgInset)
                                .clipShape(Capsule())
                        }
                    }

                    Text(store.latestCue?.detectedIntent ?? "Scanning active workspace & git branch...")
                        .font(PipiTokens.fontCaption)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: PipiTokens.spacing8)

                PipiActionButton("Refresh", systemImage: "arrow.clockwise", tone: .ghost, density: .desktopCompact) {
                    Task { await store.refreshCueContext() }
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: PipiTokens.buttonIconDesktop, weight: .semibold))
                        .foregroundStyle(PipiTokens.textMuted)
                        .frame(width: PipiTokens.buttonHeightDesktop, height: PipiTokens.buttonHeightDesktop)
                        .background(PipiTokens.bgSurfaceHover)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            if let cue = store.latestCue {
                HStack(spacing: PipiTokens.spacing8) {
                    ForEach(cue.actions) { action in
                        PipiActionButton(
                            action.label,
                            systemImage: "bolt.fill",
                            tone: action.id == cue.actions.first?.id ? .primary : .secondary,
                            density: .desktopCompact
                        ) {
                            Task { await store.executeCueAction(action) }
                        }
                    }
                }
            }
        }
        .padding(PipiTokens.spacing16)
        .frame(width: 560)
        .background(.ultraThinMaterial)
        .background(PipiTokens.bgGlass)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusXL, style: .continuous)
                .stroke(PipiTokens.borderStrong, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusXL, style: .continuous))
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
    }
}
