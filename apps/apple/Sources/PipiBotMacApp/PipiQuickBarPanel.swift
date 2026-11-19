import SwiftUI
import PipiBotKit

#if os(macOS)
import AppKit
import Carbon.HIToolbox

// MARK: - System-Wide Carbon Global Hotkey (⌥Space)

@MainActor
public final class PipiGlobalHotkeyManager {
    public static let shared = PipiGlobalHotkeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onTrigger: (@MainActor () -> Void)?

    private init() {}

    public func registerOptionSpace(_ handler: @escaping @MainActor () -> Void) {
        unregister()
        onTrigger = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard err == noErr, hotKeyID.signature == 0x50495049, hotKeyID.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                Task { @MainActor in
                    PipiGlobalHotkeyManager.shared.fire()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        guard status == noErr else { return }

        let hotKeyID = EventHotKeyID(signature: 0x50495049, id: 1) // 'PIPI'
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func fire() {
        onTrigger?()
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}

// MARK: - Key-Capable Borderless NSPanel Subclass

private final class PipiQuickBarKeyPanel: NSPanel {
    var onEscapePressed: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscapePressed?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onEscapePressed?()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Quick Bar Window Controller

@MainActor
@Observable
public final class PipiQuickBarController: NSObject, NSWindowDelegate {
    private var panel: PipiQuickBarKeyPanel?
    private weak var boundStore: PipiAppStore?
    private var anchorTopY: CGFloat = 0
    private var anchorCenterX: CGFloat = 0
    private let panelWidth: CGFloat = 600

    public var isVisible: Bool = false
    public var activeSessionId: String? = nil
    public var focusGeneration: Int = 0

    public override init() {
        super.init()
    }

    public func toggle(store: PipiAppStore, onOpenMainWindow: @escaping () -> Void = {}) {
        if isVisible {
            hide(store: store)
        } else {
            show(store: store, onOpenMainWindow: onOpenMainWindow)
        }
    }

    public func show(store: PipiAppStore, onOpenMainWindow: @escaping () -> Void = {}) {
        boundStore = store

        if panel == nil {
            let created = PipiQuickBarKeyPanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 132),
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
            created.hasShadow = false
            created.isMovableByWindowBackground = true
            created.delegate = self
            created.onEscapePressed = { [weak self] in
                guard let self, let store = self.boundStore else { return }
                self.hide(store: store)
            }

            let rootView = PipiQuickBarContentView(
                store: store,
                controller: self,
                onContinueInMainWindow: { [weak self] sessionId in
                    guard let self else { return }
                    if let sessionId {
                        store.selectConversation(sessionId)
                    }
                    self.hide(store: store, resetSession: false)
                    onOpenMainWindow()
                },
                onDismiss: { [weak self] in
                    self?.hide(store: store)
                }
            )
            created.contentView = NSHostingView(rootView: rootView)
            panel = created
        }

        guard let panel else { return }
        if let activeSessionId, !store.isRunning(conversationId: activeSessionId) {
            self.activeSessionId = nil
        }

        let targetScreen = currentCursorScreen() ?? NSScreen.main ?? NSScreen.screens.first
        if let screen = targetScreen {
            let frame = screen.visibleFrame
            anchorCenterX = frame.midX
            anchorTopY = frame.maxY - 88
            let currentHeight = max(120, min(520, panel.frame.height))
            let targetX = anchorCenterX - (panelWidth * 0.5)
            let targetY = anchorTopY - currentHeight

            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if reduceMotion {
                panel.setFrame(NSRect(x: targetX, y: targetY, width: panelWidth, height: currentHeight), display: true)
                panel.alphaValue = 1
            } else {
                panel.setFrame(NSRect(x: targetX, y: targetY + 14, width: panelWidth, height: currentHeight), display: true)
                panel.alphaValue = 0
            }

            store.avatarEngine.setState(.manusCue)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()

            if !reduceMotion {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.22
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().setFrame(NSRect(x: targetX, y: targetY, width: panelWidth, height: currentHeight), display: true)
                    panel.animator().alphaValue = 1
                }
            }
        }

        isVisible = true
        store.isCuePanelVisible = true
        focusGeneration += 1
    }

    public func hide(store: PipiAppStore, resetSession: Bool = true) {
        guard isVisible || panel?.isVisible == true else { return }
        isVisible = false
        store.isCuePanelVisible = false
        if resetSession, let sid = activeSessionId, !store.isRunning(conversationId: sid) {
            activeSessionId = nil
        }

        guard let panel else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.orderOut(nil)
            return
        }

        let targetFrame = NSRect(
            x: panel.frame.origin.x,
            y: panel.frame.origin.y + 14,
            width: panel.frame.width,
            height: panel.frame.height
        )
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isVisible else { return }
                self.panel?.orderOut(nil)
                self.panel?.alphaValue = 1
            }
        }
    }

    public func updateContentHeight(_ rawHeight: CGFloat) {
        guard let panel, anchorTopY > 0 else { return }
        let clamped = max(116, min(520, ceil(rawHeight)))
        guard abs(panel.frame.height - clamped) > 1.5 else { return }
        let x = anchorCenterX - (panelWidth * 0.5)
        let y = anchorTopY - clamped
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: clamped), display: true, animate: false)
    }

    public func windowDidResignKey(_ notification: Notification) {
        guard isVisible, let store = boundStore else { return }
        hide(store: store)
    }

    private func currentCursorScreen() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
    }
}
#endif

// MARK: - Quick Bar Content View (Inline New-Session Streaming + ⌘↩ Continue)

public struct PipiQuickBarContentView: View {
    @Bindable public var store: PipiAppStore
    #if os(macOS)
    public var controller: PipiQuickBarController
    #endif
    public var onContinueInMainWindow: (String?) -> Void
    public var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pipiTextScale) private var textScale
    @State private var quickInput: String = ""
    @State private var selectedBotId: String? = nil
    @FocusState private var isInputFocused: Bool

    #if os(macOS)
    public init(
        store: PipiAppStore,
        controller: PipiQuickBarController,
        onContinueInMainWindow: @escaping (String?) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) {
        self.store = store
        self.controller = controller
        self.onContinueInMainWindow = onContinueInMainWindow
        self.onDismiss = onDismiss
    }
    #else
    public init(
        store: PipiAppStore,
        onContinueInMainWindow: @escaping (String?) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onContinueInMainWindow = onContinueInMainWindow
        self.onDismiss = onDismiss
    }
    #endif

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }

    private var targetPersona: PipiBotPersona {
        if let selectedBotId, let found = store.personas.first(where: { $0.id == selectedBotId }) {
            return found
        }
        return store.activePersona
    }

    private var activeSession: PipiConversation? {
        #if os(macOS)
        guard let sid = controller.activeSessionId else { return nil }
        return store.conversations.first(where: { $0.id == sid })
        #else
        return nil
        #endif
    }

    public var body: some View {
        let _ = textScale
        let _ = store.uiZoomScale
        let accent = PipiTokens.color(for: targetPersona.accent)
        let session = activeSession
        let isRunning = session.map { store.isRunning(conversationId: $0.id) } ?? false

        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            // Top Input Bar
            HStack(spacing: PipiTokens.spacing12) {
                Menu {
                    ForEach(store.personas) { persona in
                        Button {
                            selectedBotId = persona.id
                        } label: {
                            HStack {
                                Text(persona.name(lang))
                                if persona.id == targetPersona.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    PipiBotPersonaGlyph(persona: targetPersona, size: 32, isSelected: true)
                }
                .pipiPlainMenu()
                .fixedSize()
                .help(targetPersona.name(lang))
                .accessibilityLabel(s.t("切换提问 Bot（当前：\(targetPersona.name(lang))）", "Switch bot (current: \(targetPersona.name(lang)))"))

                TextField(s.quickBarInputPlaceholder, text: $quickInput)
                    .textFieldStyle(.plain)
                    .font(PipiTokens.fontBody)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .focused($isInputFocused)
                    .onSubmit {
                        sendQuickPrompt()
                    }

                if isRunning, let session {
                    Button {
                        store.stopGenerating(conversationId: session.id)
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(PipiTokens.textInverse)
                            .frame(width: 28, height: 28)
                            .background(PipiTokens.stateError)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                    .help(s.stop)
                    .accessibilityLabel(s.stop)
                } else {
                    Button(action: sendQuickPrompt) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(quickInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? PipiTokens.textMuted : PipiTokens.textInverse)
                            .frame(width: 28, height: 28)
                            .background(quickInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? PipiTokens.bgSurfaceHover : PipiTokens.soulPrimary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                    .disabled(quickInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help(s.send)
                    .accessibilityLabel(s.send)
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PipiTokens.textMuted)
                        .frame(width: 26, height: 26)
                        .background(PipiTokens.bgSurfaceHover)
                        .clipShape(Circle())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                .help(s.close)
                .accessibilityLabel(s.close)
            }

            // Inline Streaming Answer Drawer
            if let session, !session.messages.isEmpty {
                Rectangle()
                    .fill(PipiTokens.borderSubtle)
                    .frame(height: 1)

                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
                        ForEach(session.messages) { msg in
                            if msg.role == .user {
                                HStack(spacing: PipiTokens.spacing8) {
                                    Text(s.youLabel)
                                        .font(PipiTokens.fontMicro)
                                        .foregroundStyle(PipiTokens.textMuted)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(PipiTokens.bgSurfaceHover)
                                        .clipShape(Capsule())
                                    Text(msg.content)
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(PipiTokens.textSecondary)
                                        .lineLimit(2)
                                }
                            } else if msg.isError {
                                Text(msg.content)
                                    .font(PipiTokens.fontCaption)
                                    .foregroundStyle(PipiTokens.stateWarning)
                                    .padding(PipiTokens.spacing8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(PipiTokens.stateWarningBg)
                                    .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                            } else if isRunning && msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                HStack(spacing: PipiTokens.spacing8) {
                                    PipiDotIndicator(vitality: .busy, color: accent, size: 6)
                                    Text(store.activeRuns[session.id]?.statusText ?? s.thinkingStatus)
                                        .font(PipiTokens.fontCaption)
                                        .foregroundStyle(PipiTokens.textSecondary)
                                    Spacer()
                                    if let startedAt = store.runStartedAt(for: session.id) {
                                        PipiElapsedTimerLabel(startedAt: startedAt, color: accent)
                                    }
                                }
                            } else {
                                PipiMarkdownView(
                                    content: msg.content,
                                    strings: s,
                                    accent: accent,
                                    isStreaming: isRunning && msg.id == session.messages.last?.id
                                )
                            }

                            if let approvalId = msg.approvalId,
                               let approval = session.approvals.first(where: { $0.id == approvalId }) {
                                PipiInlineApprovalCard(approval: approval, strings: s) { optionId in
                                    Task { await store.resolveApproval(approval.id, optionId: optionId) }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 280)
            }

            // Bottom Context & Action Rail
            HStack(spacing: PipiTokens.spacing8) {
                Text(targetPersona.name(lang))
                    .font(PipiTokens.fontMicro)
                    .foregroundStyle(accent)
                    .padding(.horizontal, PipiTokens.spacing8)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.14))
                    .clipShape(Capsule())

                if session == nil, let cue = store.latestCue {
                    Text("\(s.detectedContext): \(cue.activeAppName)")
                        .font(PipiTokens.fontMicro)
                        .foregroundStyle(PipiTokens.textMuted)
                        .lineLimit(1)
                } else if let session, isRunning, let startedAt = store.runStartedAt(for: session.id) {
                    HStack(spacing: 4) {
                        PipiDotIndicator(vitality: .busy, color: accent, size: 5)
                        PipiElapsedTimerLabel(startedAt: startedAt, color: accent)
                    }
                }

                Spacer()

                if let session {
                    #if os(macOS)
                    Button {
                        controller.activeSessionId = nil
                        quickInput = ""
                        isInputFocused = true
                    } label: {
                        Text(s.newQuickChat)
                            .font(PipiTokens.fontMicro)
                            .foregroundStyle(PipiTokens.textSecondary)
                            .padding(.horizontal, PipiTokens.spacing8)
                            .padding(.vertical, 4)
                            .background(PipiTokens.bgSurface)
                            .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                    #endif

                    Button {
                        onContinueInMainWindow(session.id)
                    } label: {
                        HStack(spacing: 5) {
                            Text(s.continueInMainWindow)
                            Text("⌘↩")
                                .font(PipiTokens.fontMonoSmall)
                                .opacity(0.8)
                        }
                        .font(PipiTokens.fontMicro.weight(.semibold))
                        .foregroundStyle(PipiTokens.textInverse)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(PipiTokens.soulPrimary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                    .keyboardShortcut(.return, modifiers: .command)
                } else if let cue = store.latestCue, let first = cue.actions.first {
                    Button {
                        sendPromptText(first.promptTemplate)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text(first.label)
                                .font(PipiTokens.fontMicro)
                        }
                        .foregroundStyle(PipiTokens.textSecondary)
                        .padding(.horizontal, PipiTokens.spacing8)
                        .padding(.vertical, 4)
                        .background(PipiTokens.bgSurface)
                        .overlay(Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                }
            }
        }
        .padding(PipiTokens.spacing16)
        .frame(width: 600)
        .pipiLiquidGlass(cornerRadius: PipiTokens.radiusXL, shadowRadius: 28, shadowY: 12)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        #if os(macOS)
                        controller.updateContentHeight(geo.size.height)
                        #endif
                    }
                    .onChange(of: geo.size.height) { _, newHeight in
                        #if os(macOS)
                        controller.updateContentHeight(newHeight)
                        #endif
                    }
            }
        )
        .preferredColorScheme(store.themeMode.colorSchemeOverride)
        .onExitCommand {
            onDismiss()
        }
        #if os(macOS)
        .onAppear {
            isInputFocused = true
        }
        .onChange(of: controller.focusGeneration) { _, _ in
            isInputFocused = true
        }
        #endif
    }

    private func sendQuickPrompt() {
        let trimmed = quickInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        quickInput = ""
        sendPromptText(trimmed)
    }

    private func sendPromptText(_ text: String) {
        if !store.hasCompletedOnboarding {
            store.completeOnboarding(selectedPersonaId: targetPersona.id)
        }
        let targetId: String
        #if os(macOS)
        if let existingId = controller.activeSessionId,
           store.conversations.contains(where: { $0.id == existingId }) {
            targetId = existingId
        } else {
            let newConv = store.createConversation(for: targetPersona.id, activate: false)
            controller.activeSessionId = newConv.id
            targetId = newConv.id
        }
        #else
        let newConv = store.createConversation(for: targetPersona.id, activate: false)
        targetId = newConv.id
        #endif

        Task {
            await store.sendPersonalMessage(
                text,
                conversationId: targetId,
                personaId: targetPersona.id,
                activateTargetConversation: false
            )
        }
    }
}
