import PipiBotKit
import SwiftUI

public struct PipiBotHomeSceneView: View {
    @Bindable public var store: PipiAppStore
    public var collaboratingBotIds: Set<String>
    public var showTopHUD: Bool
    public var onOpenBotChat: (PipiBotPersona) -> Void
    public var onQuickSendToBot: (PipiBotPersona, String) -> Void
    public var onCreateBot: () -> Void
    public var onEditBot: (PipiBotPersona) -> Void
    public var onCreateGroupChat: (String?) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.pipiTextScale) private var textScale

    @State private var bridgeState = PipiHomeSceneBridgeState()
    @State private var selectedBotId: String? = nil
    @State private var resetCameraTrigger: Int = 0
    @State private var quickPromptDraft: String = ""
    @FocusState private var isQuickPromptFocused: Bool

    public init(
        store: PipiAppStore,
        collaboratingBotIds: Set<String> = [],
        showTopHUD: Bool = true,
        onOpenBotChat: @escaping (PipiBotPersona) -> Void = { _ in },
        onQuickSendToBot: @escaping (PipiBotPersona, String) -> Void = { _, _ in },
        onCreateBot: @escaping () -> Void = {},
        onEditBot: @escaping (PipiBotPersona) -> Void = { _ in },
        onCreateGroupChat: @escaping (String?) -> Void = { _ in }
    ) {
        self.store = store
        self.collaboratingBotIds = collaboratingBotIds
        self.showTopHUD = showTopHUD
        self.onOpenBotChat = onOpenBotChat
        self.onQuickSendToBot = onQuickSendToBot
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
                state: resolvedVisualState(for: persona)
            )
        }
    }

    private var selectedPersona: PipiBotPersona? {
        guard let selectedBotId else { return nil }
        return store.personas.first(where: { $0.id == selectedBotId })
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
                // Layer 1: 100% Procedural SceneKit 3D Cozy Home
                PipiHomeSceneRepresentable(
                    bots: botSyncItems,
                    selectedBotId: selectedBotId,
                    isDark: isDark,
                    reduceMotion: reduceMotion,
                    resetCameraTrigger: resetCameraTrigger,
                    viewSize: geo.size,
                    bridgeState: bridgeState,
                    onSelectBot: { tappedId in
                        withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                            selectedBotId = tappedId
                            if tappedId != nil {
                                quickPromptDraft = ""
                            }
                        }
                    }
                )
                .ignoresSafeArea(.container, edges: .bottom)

                // Layer 2: Crisp Projected 2D Name + State Pills
                projectedBadgesLayer(in: geo.size)

                // Layer 3: Clean Minimal HUD + Floating Selected Bot Card
                VStack(spacing: 0) {
                    if showTopHUD {
                        topHUDBar
                            .padding(.horizontal, PipiTokens.spacing20)
                            .padding(.top, PipiTokens.spacing16)
                    } else {
                        HStack {
                            Spacer()
                            resetCameraButton
                        }
                        .padding(.horizontal, PipiTokens.spacing20)
                        .padding(.top, PipiTokens.spacing16)
                    }

                    Spacer()

                    if let persona = selectedPersona {
                        selectedBotCard(for: persona)
                            .padding(.horizontal, PipiTokens.spacing20)
                            .padding(.bottom, PipiTokens.spacing20)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity
                                    )
                            )
                    } else {
                        bottomCameraHint
                            .padding(.horizontal, PipiTokens.spacing20)
                            .padding(.bottom, PipiTokens.spacing16)
                    }
                }
            }
        }
        .background(PipiTokens.bgCanvas)
        .onChange(of: store.personas.map(\.id)) { _, newIds in
            if let selectedBotId, !newIds.contains(selectedBotId) {
                self.selectedBotId = nil
            }
        }
    }

    // MARK: - Projected 2D Floating Pills

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
        let isEmphasized = badge.isSelected || badge.isHovered

        Button {
            withAnimation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion)) {
                selectedBotId = badge.id
            }
        } label: {
            HStack(spacing: 5) {
                badgeStateDot(state: badge.state, accent: accentColor)

                Text(badge.displayName)
                    .font(PipiTokens.scaledFont(size: 11.5, weight: isEmphasized ? .semibold : .medium, scale: textScale))
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)

                if let tag = shortStateTag(for: badge.state) {
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
            .scaleEffect(isEmphasized && !reduceMotion ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
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

    // MARK: - Top Minimal HUD Overlay

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

            Spacer()

            HStack(spacing: PipiTokens.spacing8) {
                hudActionButton(
                    title: s.t("新建 Bot", "New Bot"),
                    systemImage: "plus",
                    isPrimary: true
                ) {
                    onCreateBot()
                }

                hudActionButton(
                    title: s.t("群聊协作", "New Group"),
                    systemImage: "person.2.fill",
                    isPrimary: false
                ) {
                    onCreateGroupChat(nil)
                }

                resetCameraButton
            }
        }
    }

    private var resetCameraButton: some View {
        Button {
            resetCameraTrigger &+= 1
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PipiTokens.textSecondary)
                .frame(width: PipiTokens.buttonHeightDesktop, height: PipiTokens.buttonHeightDesktop)
                .background {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                            .fill(PipiTokens.bgElevated)
                    } else {
                        RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                            .fill(.thinMaterial)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                        .stroke(PipiTokens.liquidGlassBorder, lineWidth: 1)
                )
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.94))
        .help(s.t("重置视角 (或双击空白处)", "Reset Camera (or Double-Click Room)"))
        .accessibilityLabel(s.t("重置视角", "Reset Camera"))
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

    private var bottomCameraHint: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "hand.draw")
                    .font(.system(size: 11, weight: .medium))
                Text(s.t("拖拽旋转 · 滚轮缩放 · 点击 Bot 互动 · 双击复位", "Drag to orbit · Scroll to zoom · Click a Bot · Double-click to reset"))
                    .font(PipiTokens.scaledFont(size: 11, weight: .medium, scale: textScale))
            }
            .foregroundStyle(PipiTokens.textMuted)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background {
                if reduceTransparency {
                    Capsule().fill(PipiTokens.bgElevated)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .overlay(
                Capsule().stroke(PipiTokens.borderSubtle, lineWidth: 0.75)
            )

            Spacer()
        }
    }

    // MARK: - Selected Bot Floating Interaction Card

    @ViewBuilder
    private func selectedBotCard(for bot: PipiBotPersona) -> some View {
        let visualState = resolvedVisualState(for: bot)
        let accentColor = PipiTokens.color(for: bot.accent)
        let engineLabel = store.activeEngineDisplayLabel(for: bot)

        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            // Header: Glyph + Name + Role + Live Badge + Dismiss
            HStack(alignment: .top, spacing: PipiTokens.spacing12) {
                PipiBotPersonaGlyph(persona: bot, size: 42, isSelected: true)

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
                        .lineLimit(2)

                    HStack(spacing: 5) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10.5, weight: .medium))
                        Text(engineLabel)
                            .font(PipiTokens.scaledFont(size: 11, weight: .medium, scale: textScale))
                    }
                    .foregroundStyle(PipiTokens.textMuted)
                    .padding(.top, 1)
                }

                Spacer(minLength: 4)

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

            // Quick Inline Prompt Bar
            HStack(spacing: PipiTokens.spacing8) {
                TextField(
                    s.t("直接对 \(compactBotDisplayName(bot.name(lang))) 说点什么...", "Ask \(compactBotDisplayName(bot.name(lang))) anything..."),
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
                .background(PipiTokens.bgInset.opacity(0.75), in: RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PipiTokens.radiusSM, style: .continuous)
                        .stroke(isQuickPromptFocused ? accentColor.opacity(0.6) : PipiTokens.borderSubtle, lineWidth: 1)
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
                cardActionButton(
                    title: s.t("打开对话", "Open Chat"),
                    systemImage: "bubble.left.and.bubble.right.fill",
                    accent: accentColor,
                    isPrimary: true
                ) {
                    onOpenBotChat(bot)
                }

                cardActionButton(
                    title: s.t("拉入群聊", "Group Chat"),
                    systemImage: "person.2.fill",
                    accent: accentColor,
                    isPrimary: false
                ) {
                    onCreateGroupChat(bot.id)
                }

                cardActionButton(
                    title: s.t("编辑人设", "Edit Bot"),
                    systemImage: "slider.horizontal.3",
                    accent: accentColor,
                    isPrimary: false
                ) {
                    onEditBot(bot)
                }
            }
        }
        .padding(PipiTokens.spacing16)
        .frame(maxWidth: 480)
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
        if hasPendingApproval {
            return .needsYou
        }
        if collaboratingBotIds.contains(persona.id) {
            return .collaborating
        }
        if store.isPersonaRunning(persona.id) {
            return .working
        }
        return .idle
    }

    private var summaryText: String {
        let total = store.personas.count
        var parts: [String] = [
            s.t("\(total) 位智能体", "\(total) \(total == 1 ? "Agent" : "Agents")")
        ]
        if workingCount > 0 {
            parts.append(s.t("\(workingCount) 工作中", "\(workingCount) Working"))
        }
        if needsYouCount > 0 {
            parts.append(s.t("\(needsYouCount) 待确认", "\(needsYouCount) Needs You"))
        }
        if workingCount == 0 && needsYouCount == 0 {
            parts.append(s.t("居家待命中", "All Cozy & Ready"))
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
        case .needsYou: return s.needsYouInboxTitle
        case .collaborating: return s.t("协作中", "Collab")
        }
    }

    private func stateLabel(for state: PipiHomeBotVisualState) -> String {
        switch state {
        case .idle: return s.t("休闲待命中", "Idle at Home")
        case .working: return s.t("正在工作中", "Working")
        case .needsYou: return s.t("等待你确认", "Needs Approval")
        case .collaborating: return s.t("群聊协作中", "Collaborating")
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
