import PipiBotKit
import SwiftUI

public struct PipiBotHomeSceneView: View {
    @Bindable public var store: PipiAppStore
    public var collaboratingBotIds: Set<String>
    public var showTopHUD: Bool
    public var externalResetTrigger: Int
    public var onOpenBotChat: (PipiBotPersona) -> Void
    public var onQuickSendToBot: (PipiBotPersona, String) -> Void
    public var onStartVoiceCall: (PipiBotPersona) -> Void
    public var onCreateBot: () -> Void
    public var onEditBot: (PipiBotPersona) -> Void
    public var onCreateGroupChat: (String?) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.pipiTextScale) private var textScale

    @State private var bridgeState = PipiHomeSceneBridgeState()
    @State private var selectedBotId: String? = nil
    @State private var pinnedHoverBotId: String? = nil
    @State private var cameraCommand: PipiHomeCameraCommand? = nil
    @State private var cameraNonce: Int = 0
    @State private var quickPromptDraft: String = ""
    @State private var roomMoveToast: String? = nil
    @State private var toastClearTask: Task<Void, Never>? = nil
    @FocusState private var isQuickPromptFocused: Bool

    public init(
        store: PipiAppStore,
        collaboratingBotIds: Set<String> = [],
        showTopHUD: Bool = true,
        externalResetTrigger: Int = 0,
        onOpenBotChat: @escaping (PipiBotPersona) -> Void = { _ in },
        onQuickSendToBot: @escaping (PipiBotPersona, String) -> Void = { _, _ in },
        onStartVoiceCall: @escaping (PipiBotPersona) -> Void = { _ in },
        onCreateBot: @escaping () -> Void = {},
        onEditBot: @escaping (PipiBotPersona) -> Void = { _ in },
        onCreateGroupChat: @escaping (String?) -> Void = { _ in }
    ) {
        self.store = store
        self.collaboratingBotIds = collaboratingBotIds
        self.showTopHUD = showTopHUD
        self.externalResetTrigger = externalResetTrigger
        self.onOpenBotChat = onOpenBotChat
        self.onQuickSendToBot = onQuickSendToBot
        self.onStartVoiceCall = onStartVoiceCall
        self.onCreateBot = onCreateBot
        self.onEditBot = onEditBot
        self.onCreateGroupChat = onCreateGroupChat
    }

    private var s: PipiStrings { store.strings }
    private var lang: PipiResolvedLanguage { store.resolvedLanguage }
    private var isDark: Bool { colorScheme == .dark }

    private var botSyncItems: [PipiHomeBotSyncItem] {
        store.personas.map { persona in
            PipiHomeBotSyncItem(
                id: persona.id,
                displayName: compactBotDisplayName(persona.name(lang)),
                accent: persona.accent,
                motif: PipiPersonaMotif.resolve(for: persona),
                state: resolvedVisualState(for: persona),
                room: store.assignedRoom(for: persona.id)
            )
        }
    }

    private var selectedPersona: PipiBotPersona? {
        guard let selectedBotId else { return nil }
        return store.personas.first(where: { $0.id == selectedBotId })
    }

    private var draggingPersonaName: String? {
        guard let dragId = bridgeState.draggingBotId,
              let persona = store.personas.first(where: { $0.id == dragId }) else { return nil }
        return compactBotDisplayName(persona.name(lang))
    }

    private var workingCount: Int {
        botSyncItems.filter { $0.state == .working || $0.state == .collaborating }.count
    }

    private var needsYouCount: Int {
        botSyncItems.filter { $0.state == .needsYou }.count
    }

    public var body: some View {
        let _ = textScale

        GeometryReader { geo in
            ZStack {
                // Layer 1: Multi-Room Procedural 3D Space with 4 Switchable Scenes & Direct Drag-Drop
                PipiHomeSceneRepresentable(
                    bots: botSyncItems,
                    scenePreset: store.homeScenePreset,
                    selectedBotId: selectedBotId,
                    pinnedBotId: pinnedHoverBotId,
                    isDark: isDark,
                    reduceMotion: reduceMotion,
                    cameraCommand: cameraCommand,
                    viewSize: geo.size,
                    bridgeState: bridgeState,
                    onSelectBot: { tappedId in
                        withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                            selectedBotId = tappedId
                            if tappedId != nil {
                                quickPromptDraft = ""
                            }
                        }
                    },
                    onMoveBotToRoom: { botId, targetRoom in
                        handleBotRoomAssigned(botId: botId, to: targetRoom)
                    }
                )
                .ignoresSafeArea(.container, edges: .bottom)

                // Layer 2: Projected 2D Room Zone Pills (clickable to focus camera; bright drop targets while dragging)
                projectedRoomLabelsLayer(in: geo.size)

                // Layer 3: Projected 2D Bot Name, State & Instant Hover Action Pills
                projectedBadgesLayer(in: geo.size)

                // Layer 4: Clean Minimal HUD + Drag/Toast Banner + Camera Dock + Selected Bot Card
                VStack(spacing: 0) {
                    if showTopHUD {
                        topHUDBar
                            .padding(.horizontal, PipiTokens.spacing20)
                            .padding(.top, PipiTokens.spacing16)
                    } else {
                        embeddedControlBar
                            .padding(.horizontal, PipiTokens.spacing20)
                            .padding(.top, PipiTokens.spacing12)
                    }

                    // Active Drag Feedback or Brief Room Assignment Toast
                    if let dragName = draggingPersonaName {
                        dragStatusBanner(botName: dragName, targetRoom: bridgeState.dragHoverRoom)
                            .padding(.top, PipiTokens.spacing12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if let toast = roomMoveToast {
                        roomMovedToastPill(toast)
                            .padding(.top, PipiTokens.spacing12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer()

                    HStack(alignment: .bottom, spacing: PipiTokens.spacing12) {
                        if let persona = selectedPersona {
                            selectedBotCard(for: persona)
                                .transition(
                                    reduceMotion
                                        ? .opacity
                                        : .asymmetric(
                                            insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity
                                        )
                                )
                        }

                        Spacer(minLength: PipiTokens.spacing12)

                        cameraControlsDock
                    }
                    .padding(.horizontal, PipiTokens.spacing20)
                    .padding(.bottom, PipiTokens.spacing16)
                }
            }
        }
        .background(PipiTokens.bgCanvas)
        .onChange(of: externalResetTrigger) { _, _ in
            sendCamera(.reset)
        }
        .onChange(of: store.personas.map(\.id)) { _, newIds in
            if let selectedBotId, !newIds.contains(selectedBotId) {
                self.selectedBotId = nil
            }
        }
    }

    // MARK: - Projected 2D Room Zone Pills

    @ViewBuilder
    private func projectedRoomLabelsLayer(in size: CGSize) -> some View {
        let isDragging = bridgeState.draggingBotId != nil
        ZStack {
            ForEach(bridgeState.projectedRoomLabels) { label in
                if label.screenPoint.x > 40,
                   label.screenPoint.x < size.width - 40,
                   label.screenPoint.y > 56,
                   label.screenPoint.y < size.height - 44 {
                    Button {
                        sendCamera(.focusRoom(label.room))
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: label.room.iconName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(label.isDropTarget ? PipiTokens.textInverse : roomTintColor(label.room))

                            Text(
                                label.isDropTarget
                                    ? s.t("松开移入 · \(label.room.title(lang))", "Drop in \(label.room.title(lang))")
                                    : label.room.title(lang)
                            )
                            .font(PipiTokens.scaledFont(size: label.isDropTarget ? 11.5 : 10.5, weight: .semibold, scale: textScale))
                            .foregroundStyle(label.isDropTarget ? PipiTokens.textInverse : PipiTokens.textSecondary)

                            if label.occupantCount > 0 && !label.isDropTarget {
                                Text("\(label.occupantCount)")
                                    .font(PipiTokens.fontMonoSmall.weight(.semibold))
                                    .foregroundStyle(roomTintColor(label.room))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(roomTintColor(label.room).opacity(0.14), in: Capsule())
                            }
                        }
                        .padding(.horizontal, label.isDropTarget ? 11 : 8)
                        .padding(.vertical, label.isDropTarget ? 5 : 3.5)
                        .background {
                            if label.isDropTarget {
                                Capsule().fill(roomTintColor(label.room))
                            } else if reduceTransparency {
                                Capsule().fill(PipiTokens.bgElevated.opacity(0.92))
                            } else {
                                Capsule().fill(.ultraThinMaterial)
                            }
                        }
                        .overlay(
                            Capsule()
                                .stroke(
                                    label.isDropTarget
                                        ? roomTintColor(label.room)
                                        : (isDragging ? roomTintColor(label.room).opacity(0.55) : PipiTokens.liquidGlassBorder),
                                    lineWidth: label.isDropTarget ? 1.5 : 0.85
                                )
                        )
                        .shadow(color: PipiTokens.subtleShadow, radius: label.isDropTarget ? 12 : 4, y: 2)
                        .scaleEffect(label.isDropTarget && !reduceMotion ? 1.08 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(!isDragging)
                    .position(x: label.screenPoint.x, y: label.screenPoint.y)
                    .help(s.t("点击聚焦至「\(label.room.title(lang))」", "Focus camera on \(label.room.title(lang))"))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: bridgeState.dragHoverRoom)
    }

    // MARK: - Projected 2D Floating Bot Pills

    @ViewBuilder
    private func projectedBadgesLayer(in size: CGSize) -> some View {
        ZStack {
            ForEach(bridgeState.projectedBadges) { badge in
                if badge.screenPoint.x > 28,
                   badge.screenPoint.x < size.width - 28,
                   badge.screenPoint.y > 52,
                   badge.screenPoint.y < size.height - 28 {
                    projectedBadgePill(badge)
                        .position(x: badge.screenPoint.x, y: badge.screenPoint.y)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func projectedBadgePill(_ badge: PipiHomeProjectedBadge) -> some View {
        let accentColor = PipiTokens.color(for: badge.accent)
        let isHoveredOrPinned = !badge.isDragging && (badge.isHovered || pinnedHoverBotId == badge.id)
        let isEmphasized = badge.isSelected || isHoveredOrPinned || badge.isDragging
        let matchedPersona = store.personas.first(where: { $0.id == badge.id })

        VStack(spacing: 5) {
            Button {
                withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                    selectedBotId = badge.id
                    isQuickPromptFocused = true
                }
            } label: {
                HStack(spacing: 5) {
                    if badge.isDragging {
                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(accentColor)
                    } else {
                        badgeStateDot(state: badge.state, accent: accentColor)
                    }

                    Text(badge.displayName)
                        .font(PipiTokens.scaledFont(size: 11.5, weight: isEmphasized ? .semibold : .medium, scale: textScale))
                        .foregroundStyle(PipiTokens.textPrimary)
                        .lineLimit(1)

                    if let tag = shortStateTag(for: badge.state), !badge.isDragging {
                        Text(tag)
                            .font(PipiTokens.scaledFont(size: 10, weight: .semibold, scale: textScale))
                            .foregroundStyle(stateColor(for: badge.state, accent: accentColor))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(stateColor(for: badge.state, accent: accentColor).opacity(0.14), in: Capsule())
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background {
                    if reduceTransparency {
                        Capsule().fill(PipiTokens.bgElevated)
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    Capsule()
                        .stroke(
                            isEmphasized ? accentColor.opacity(0.85) : PipiTokens.liquidGlassBorder,
                            lineWidth: isEmphasized ? 1.25 : 0.85
                        )
                )
                .shadow(color: PipiTokens.subtleShadow, radius: isEmphasized ? 10 : 5, y: 2)
                .scaleEffect(isEmphasized && !reduceMotion ? 1.04 : 1.0)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(bridgeState.draggingBotId == nil)

            // Instant Hover Action Pill (hidden during drag so dragging feels crisp and uninterrupted)
            if isHoveredOrPinned && !badge.isSelected && bridgeState.draggingBotId == nil, let persona = matchedPersona {
                HStack(spacing: 4) {
                    Button {
                        withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                            selectedBotId = persona.id
                            quickPromptDraft = ""
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            isQuickPromptFocused = true
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 10, weight: .semibold))
                            Text(s.t("输入", "Type"))
                                .font(PipiTokens.fontMicro.weight(.semibold))
                        }
                        .foregroundStyle(PipiTokens.textPrimary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(PipiTokens.buttonSecondaryBg, in: Capsule())
                        .overlay(Capsule().strokeBorder(PipiTokens.composerBorder, lineWidth: 0.8))
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.94))

                    Button {
                        pinnedHoverBotId = nil
                        onStartVoiceCall(persona)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text(s.t("语音通话", "Call"))
                                .font(PipiTokens.fontMicro.weight(.semibold))
                        }
                        .foregroundStyle(PipiTokens.textInverse)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(PipiTokens.stateSuccess, in: Capsule())
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.94))
                }
                .padding(4)
                .pipiLiquidGlass(cornerRadius: PipiTokens.radiusPill, shadowRadius: 10, shadowY: 3)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .onHover { hovering in
            if hovering {
                pinnedHoverBotId = badge.id
            } else if pinnedHoverBotId == badge.id {
                pinnedHoverBotId = nil
            }
        }
        .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: isHoveredOrPinned)
        .accessibilityLabel("\(badge.displayName), \(stateLabel(for: badge.state))")
    }

    @ViewBuilder
    private func badgeStateDot(state: PipiHomeBotVisualState, accent: Color) -> some View {
        switch state {
        case .idle:
            Circle()
                .fill(accent)
                .frame(width: 6.5, height: 6.5)
        case .working:
            if reduceMotion {
                Circle()
                    .fill(PipiTokens.soulPrimary)
                    .frame(width: 7, height: 7)
            } else {
                PipiDotIndicator(vitality: .busy, color: accent, size: 6.5)
            }
        case .needsYou:
            ZStack {
                Circle()
                    .fill(PipiTokens.stateWarning)
                    .frame(width: 12, height: 12)
                Text("!")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(PipiTokens.textInverse)
            }
        case .collaborating:
            Image(systemName: "link")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(PipiTokens.soulSecondary)
        }
    }

    // MARK: - Top HUD Bars & 4-Preset Scene Switcher

    private var topHUDBar: some View {
        HStack(alignment: .center, spacing: PipiTokens.spacing12) {
            HStack(spacing: PipiTokens.spacing12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.botHome)
                        .font(PipiTokens.scaledFont(size: 16, weight: .semibold, scale: textScale))
                        .tracking(PipiTokens.trackingHeadline)
                        .foregroundStyle(PipiTokens.textPrimary)

                    Text(summaryText)
                        .font(PipiTokens.scaledFont(size: 11.5, weight: .medium, scale: textScale))
                        .foregroundStyle(PipiTokens.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .pipiLiquidGlass(cornerRadius: PipiTokens.radiusMD, shadowRadius: 10, shadowY: 3)

            scenePresetSwitcher

            Spacer()

            HStack(spacing: PipiTokens.spacing8) {
                hudActionButton(title: s.newBot, systemImage: "plus", isPrimary: true) {
                    onCreateBot()
                }
                hudActionButton(title: s.newGroupChat, systemImage: "person.2.fill", isPrimary: false) {
                    onCreateGroupChat(nil)
                }
                controlsHelpButton
            }
        }
    }

    private var embeddedControlBar: some View {
        HStack(spacing: PipiTokens.spacing8) {
            scenePresetSwitcher
            Spacer()
            controlsHelpButton
        }
    }

    private var scenePresetSwitcher: some View {
        HStack(spacing: 3) {
            ForEach(PipiHomeScenePreset.allCases) { preset in
                let isActive = store.homeScenePreset == preset
                Button {
                    withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                        store.setHomeScenePreset(preset)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: preset.iconName)
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(preset.title(lang))
                            .font(PipiTokens.scaledFont(size: 11.5, weight: isActive ? .semibold : .medium, scale: textScale))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isActive ? PipiTokens.textInverse : PipiTokens.textSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(
                        isActive ? PipiTokens.soulPrimary : Color.clear,
                        in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    )
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
                .help(preset.subtitle(lang))
            }
        }
        .padding(3)
        .pipiLiquidGlass(cornerRadius: PipiTokens.radiusMD, shadowRadius: 8, shadowY: 2)
    }

    private var controlsHelpButton: some View {
        PipiInfoHelpButton(
            title: s.t("3D 空间交互指南", "3D Space Controls"),
            message: s.t(
                "• 拖拽智能体：直接跨房间拖放智能体至目标房间\n• 左键拖空白处：自由旋转视角\n• 右键 / Shift+拖拽：在房间之间平移\n• 滚轮 / 双指捏合：平滑缩放\n• 点击房间标签 / 双击智能体：镜头自动聚焦\n• 快捷键：WASD/方向键平移，Q/E 旋转，1/2/3 切换视角，R 复位",
                "• Drag an Agent: Move directly between rooms\n• Left-drag floor: Orbit smoothly\n• Right-drag or Shift+drag: Pan across rooms\n• Scroll / Pinch: Zoom in & out\n• Click room pill or double-click agent: Focus camera\n• Keys: WASD/Arrows pan, Q/E orbit, 1/2/3 views, R reset"
            )
        )
    }

    // MARK: - Bottom-Right Camera Controls Dock

    private var cameraControlsDock: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(PipiHomeCameraPreset.allCases) { preset in
                    let isSelected = bridgeState.activeCameraPreset == preset
                    Button {
                        sendCamera(.preset(preset))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: preset.iconName)
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(preset.label(lang))
                                .font(PipiTokens.scaledFont(size: 11, weight: isSelected ? .semibold : .medium, scale: textScale))
                        }
                        .foregroundStyle(isSelected ? PipiTokens.textInverse : PipiTokens.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(
                            isSelected ? PipiTokens.soulPrimary : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.95))
                }
            }

            Rectangle()
                .fill(PipiTokens.borderSubtle)
                .frame(width: 1, height: 16)

            cameraDockIconButton(systemImage: "minus", help: s.t("缩小视角", "Zoom Out")) {
                sendCamera(.zoomOut)
            }
            cameraDockIconButton(systemImage: "plus", help: s.t("放大视角", "Zoom In")) {
                sendCamera(.zoomIn)
            }
            cameraDockIconButton(systemImage: "arrow.counterclockwise", help: s.t("复位全景视角 (R)", "Reset Overview (R)")) {
                sendCamera(.reset)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .pipiLiquidGlass(cornerRadius: PipiTokens.radiusMD, shadowRadius: 12, shadowY: 4)
    }

    private func cameraDockIconButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(PipiTokens.textSecondary)
                .frame(width: 26, height: 26)
                .background(PipiTokens.buttonGhostHoverBg.opacity(0.65), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - Drag Status Banner & Move Confirmation Toast

    private func dragStatusBanner(botName: String, targetRoom: PipiHomeRoomKind?) -> some View {
        let roomTitle = targetRoom?.title(lang) ?? s.t("选择房间", "Select Room")
        let tint = targetRoom.map(roomTintColor) ?? PipiTokens.soulPrimary
        return HStack(spacing: 8) {
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(s.t("正在移动「\(botName)」→ 松开移入：\(roomTitle)", "Moving \(botName) → Drop into \(roomTitle)"))
                .font(PipiTokens.fontCaption.weight(.semibold))
                .foregroundStyle(PipiTokens.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .pipiLiquidGlass(cornerRadius: PipiTokens.radiusPill, shadowRadius: 12, shadowY: 4)
        .overlay(Capsule().stroke(tint.opacity(0.65), lineWidth: 1.25))
    }

    private func roomMovedToastPill(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PipiTokens.stateSuccess)
            Text(text)
                .font(PipiTokens.fontCaption.weight(.medium))
                .foregroundStyle(PipiTokens.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .pipiLiquidGlass(cornerRadius: PipiTokens.radiusPill, shadowRadius: 10, shadowY: 3)
    }

    private func hudActionButton(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(PipiTokens.scaledFont(size: 12.5, weight: .semibold, scale: textScale))
            }
            .foregroundStyle(isPrimary ? PipiTokens.textInverse : PipiTokens.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: PipiTokens.buttonHeightDesktop)
            .background {
                if isPrimary {
                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                        .fill(PipiTokens.soulPrimary)
                } else if reduceTransparency {
                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                        .fill(PipiTokens.bgElevated)
                } else {
                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                        .fill(.thinMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .stroke(isPrimary ? PipiTokens.soulPrimary.opacity(0.25) : PipiTokens.liquidGlassBorder, lineWidth: 1)
            )
            .shadow(color: PipiTokens.subtleShadow, radius: 6, y: 2)
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.96))
    }

    // MARK: - Selected Bot Floating Interaction Card (with Room Assignment Pills)

    @ViewBuilder
    private func selectedBotCard(for bot: PipiBotPersona) -> some View {
        let visualState = resolvedVisualState(for: bot)
        let accentColor = PipiTokens.color(for: bot.accent)
        let engineLabel = store.activeEngineDisplayLabel(for: bot)
        let currentRoom = store.assignedRoom(for: bot.id)

        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack(alignment: .top, spacing: PipiTokens.spacing12) {
                PipiBotPersonaGlyph(persona: bot, size: 40, isSelected: true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: PipiTokens.spacing8) {
                        Text(bot.name(lang))
                            .font(PipiTokens.scaledFont(size: 15, weight: .semibold, scale: textScale))
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            badgeStateDot(state: visualState, accent: accentColor)
                            Text(stateLabel(for: visualState))
                                .font(PipiTokens.scaledFont(size: 11, weight: .semibold, scale: textScale))
                                .foregroundStyle(stateColor(for: visualState, accent: accentColor))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(stateColor(for: visualState, accent: accentColor).opacity(0.13), in: Capsule())
                    }

                    Text(bot.role(lang))
                        .font(PipiTokens.scaledFont(size: 12, weight: .regular, scale: textScale))
                        .foregroundStyle(PipiTokens.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10, weight: .medium))
                        Text(engineLabel)
                            .font(PipiTokens.scaledFont(size: 11, weight: .medium, scale: textScale))
                    }
                    .foregroundStyle(PipiTokens.textMuted)
                }

                Spacer(minLength: 4)

                Button {
                    sendCamera(.focusBot(bot.id))
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(PipiTokens.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(PipiTokens.buttonGhostHoverBg, in: Circle())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                .help(s.t("镜头聚焦此助手", "Focus camera on assistant"))

                Button {
                    withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                        selectedBotId = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(PipiTokens.textMuted)
                        .frame(width: 26, height: 26)
                        .background(PipiTokens.buttonGhostHoverBg, in: Circle())
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
                .accessibilityLabel(s.close)
            }

            // Room Assignment Row (drag in 3D OR click here to reassign room)
            HStack(spacing: 6) {
                Text(s.t("所在房间", "Room"))
                    .font(PipiTokens.fontMicro.weight(.semibold))
                    .foregroundStyle(PipiTokens.textMuted)

                ForEach(PipiHomeRoomKind.allCases) { room in
                    let isHere = currentRoom == room
                    let tint = roomTintColor(room)
                    Button {
                        handleBotRoomAssigned(botId: bot.id, to: room)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: room.iconName)
                                .font(.system(size: 9.5, weight: .semibold))
                            Text(room.shortTitle(lang))
                                .font(PipiTokens.fontMicro.weight(isHere ? .semibold : .medium))
                        }
                        .foregroundStyle(isHere ? PipiTokens.textInverse : PipiTokens.textSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(isHere ? tint : PipiTokens.bgInset, in: Capsule())
                        .overlay(Capsule().stroke(isHere ? tint : PipiTokens.borderSubtle, lineWidth: 0.8))
                    }
                    .buttonStyle(PipiPressButtonStyle(pressedScale: 0.95))
                    .help(s.t("将助手移至「\(room.title(lang))」（也可在 3D 画面中直接拖放）", "Move to \(room.title(lang)) (or drag directly in 3D)"))
                }
                Spacer(minLength: 0)
            }

            // Quick Inline Prompt Bar
            HStack(spacing: PipiTokens.spacing8) {
                TextField(
                    s.t("向 \(compactBotDisplayName(bot.name(lang))) 发送消息", "Message \(compactBotDisplayName(bot.name(lang)))"),
                    text: $quickPromptDraft
                )
                .textFieldStyle(.plain)
                .font(PipiTokens.scaledFont(size: 13, weight: .regular, scale: textScale))
                .foregroundStyle(PipiTokens.textPrimary)
                .focused($isQuickPromptFocused)
                .onSubmit {
                    submitQuickPrompt(to: bot)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(PipiTokens.composerSurface, in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                        .strokeBorder(isQuickPromptFocused ? PipiTokens.composerBorderFocused : PipiTokens.composerBorder, lineWidth: isQuickPromptFocused ? 1.25 : 1)
                )

                Button {
                    submitQuickPrompt(to: bot)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PipiTokens.textInverse)
                        .frame(width: 34, height: 34)
                        .background(
                            quickPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? PipiTokens.textMuted.opacity(0.45)
                                : accentColor,
                            in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                        )
                }
                .buttonStyle(PipiPressButtonStyle(pressedScale: 0.94))
                .disabled(quickPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(s.send)
            }

            // Action Buttons Row
            HStack(spacing: PipiTokens.spacing8) {
                cardActionButton(title: s.t("打开对话", "Open Chat"), systemImage: "bubble.left.and.bubble.right.fill", accent: accentColor, isPrimary: true) {
                    onOpenBotChat(bot)
                }
                cardActionButton(title: s.t("语音通话", "Voice Call"), systemImage: "phone.fill", accent: PipiTokens.stateSuccess, isPrimary: false) {
                    onStartVoiceCall(bot)
                }
                cardActionButton(title: s.t("发起群聊", "Group Chat"), systemImage: "person.2.fill", accent: accentColor, isPrimary: false) {
                    onCreateGroupChat(bot.id)
                }
                cardActionButton(title: s.t("编辑助手", "Edit"), systemImage: "slider.horizontal.3", accent: accentColor, isPrimary: false) {
                    onEditBot(bot)
                }
            }
        }
        .padding(PipiTokens.spacing16)
        .frame(maxWidth: 488)
        .pipiLiquidGlass(cornerRadius: PipiTokens.radiusLG, shadowRadius: 20, shadowY: 8)
    }

    private func cardActionButton(
        title: String,
        systemImage: String,
        accent: Color,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(PipiTokens.scaledFont(size: 12.5, weight: .semibold, scale: textScale))
                    .lineLimit(1)
            }
            .foregroundStyle(isPrimary ? PipiTokens.textInverse : PipiTokens.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: PipiTokens.buttonHeightDesktop)
            .background(
                isPrimary ? accent : PipiTokens.buttonSecondaryBg,
                in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                    .stroke(isPrimary ? accent.opacity(0.2) : PipiTokens.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.97))
    }

    // MARK: - Helpers

    private func sendCamera(_ action: PipiHomeCameraAction) {
        cameraNonce &+= 1
        cameraCommand = PipiHomeCameraCommand(nonce: cameraNonce, action: action)
    }

    private func handleBotRoomAssigned(botId: String, to room: PipiHomeRoomKind) {
        let previous = store.assignedRoom(for: botId)
        store.assignBot(botId, to: room)
        guard let persona = store.personas.first(where: { $0.id == botId }) else { return }
        let name = compactBotDisplayName(persona.name(lang))
        let msg = previous == room
            ? s.t("「\(name)」已在 \(room.title(lang))", "\(name) is in \(room.title(lang))")
            : s.t("已将「\(name)」移至 \(room.title(lang))", "Moved \(name) to \(room.title(lang))")
        withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
            roomMoveToast = msg
        }
        toastClearTask?.cancel()
        toastClearTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation(PipiMotion.adaptive(PipiMotion.smooth, reduceMotion: reduceMotion)) {
                roomMoveToast = nil
            }
        }
    }

    private func roomTintColor(_ room: PipiHomeRoomKind) -> Color {
        switch room {
        case .studio: return PipiTokens.color(for: .sky)
        case .lounge: return PipiTokens.color(for: .amber)
        case .collab: return PipiTokens.color(for: .iris)
        case .lab:    return PipiTokens.color(for: .emerald)
        }
    }

    private func submitQuickPrompt(to bot: PipiBotPersona) {
        let trimmed = quickPromptDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        quickPromptDraft = ""
        onQuickSendToBot(bot, trimmed)
    }

    private func resolvedVisualState(for persona: PipiBotPersona) -> PipiHomeBotVisualState {
        let hasPendingApproval = store.conversations.contains { conv in
            conv.personaId == persona.id &&
            (conv.state == .needsYou || conv.approvals.contains { $0.status == .pending })
        }
        if hasPendingApproval { return .needsYou }
        if collaboratingBotIds.contains(persona.id) { return .collaborating }
        if store.isPersonaRunning(persona.id) { return .working }
        return .idle
    }

    private var summaryText: String {
        let total = store.personas.count
        var parts: [String] = [
            s.t("\(total) 位智能体 · 4 房间", "\(total) \(total == 1 ? "Agent" : "Agents") · 4 Rooms")
        ]
        if workingCount > 0 {
            parts.append(s.t("\(workingCount) 工作中", "\(workingCount) Working"))
        }
        if needsYouCount > 0 {
            parts.append(s.t("\(needsYouCount) 待确认", "\(needsYouCount) Needs You"))
        }
        if workingCount == 0 && needsYouCount == 0 {
            parts.append(s.t("拖放可换房间", "Drag to Move Rooms"))
        }
        return parts.joined(separator: " · ")
    }

    private func compactBotDisplayName(_ raw: String) -> String {
        if let range = raw.range(of: " · ") {
            return String(raw[..<range.lowerBound])
        }
        return raw
    }

    private func shortStateTag(for state: PipiHomeBotVisualState) -> String? {
        switch state {
        case .idle: return nil
        case .working: return s.t("工作中", "Working")
        case .needsYou: return s.needsYouLabel
        case .collaborating: return s.t("协作中", "Collab")
        }
    }

    private func stateLabel(for state: PipiHomeBotVisualState) -> String {
        switch state {
        case .idle: return s.t("空闲", "Idle")
        case .working: return s.t("工作中", "Working")
        case .needsYou: return s.t("待确认", "Needs Approval")
        case .collaborating: return s.t("协作中", "Collaborating")
        }
    }

    private func stateColor(for state: PipiHomeBotVisualState, accent: Color) -> Color {
        switch state {
        case .idle: return accent
        case .working: return PipiTokens.soulPrimary
        case .needsYou: return PipiTokens.stateWarning
        case .collaborating: return PipiTokens.soulSecondary
        }
    }
}
