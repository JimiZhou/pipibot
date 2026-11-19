import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Canonical Action Button (Enforces 44pt Mobile / 32pt Desktop Geometry)

public enum PipiButtonDensity: Sendable {
    case mobile
    case desktopCompact

    var height: CGFloat {
        switch self {
        case .mobile: return PipiTokens.buttonHeightMobile
        case .desktopCompact: return PipiTokens.buttonHeightDesktop
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .mobile: return PipiTokens.buttonIconMobile
        case .desktopCompact: return PipiTokens.buttonIconDesktop
        }
    }

    var gap: CGFloat {
        switch self {
        case .mobile: return PipiTokens.buttonGapMobile
        case .desktopCompact: return PipiTokens.buttonGapDesktop
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .mobile: return PipiTokens.radiusMD
        case .desktopCompact: return PipiTokens.radiusSM
        }
    }
}

public enum PipiButtonTone: Sendable {
    case primary
    case secondary
    case destructive
    case ghost
}

// MARK: - Restrained Apple Liquid Glass & Structural Material Modifiers

public struct PipiLiquidGlassModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var borderColor: Color?
    public var borderWidth: CGFloat
    public var shadowRadius: CGFloat
    public var shadowY: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        cornerRadius: CGFloat = PipiTokens.radiusLG,
        borderColor: Color? = nil,
        borderWidth: CGFloat = 1,
        shadowRadius: CGFloat = 16,
        shadowY: CGFloat = 6
    ) {
        self.cornerRadius = cornerRadius
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let resolvedBorder = borderColor ?? (reduceTransparency ? PipiTokens.borderStrong : PipiTokens.borderSubtle)
        Group {
            if reduceTransparency {
                content
                    .background(PipiTokens.bgElevated, in: shape)
            } else {
                content
                    .background(.ultraThinMaterial, in: shape)
                    .background(PipiTokens.liquidGlassSurface, in: shape)
            }
        }
        .overlay(
            shape.stroke(resolvedBorder, lineWidth: borderWidth)
        )
        .clipShape(shape)
        .shadow(color: PipiTokens.elevatedShadow, radius: shadowRadius, y: shadowY)
    }
}

public struct PipiStructuralMaterialModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public func body(content: Content) -> some View {
        let _ = reduceTransparency
        content.background(PipiTokens.bgSidebar)
    }
}

public extension View {
    func pipiLiquidGlass(
        cornerRadius: CGFloat = PipiTokens.radiusLG,
        borderColor: Color? = nil,
        borderWidth: CGFloat = 1,
        shadowRadius: CGFloat = 16,
        shadowY: CGFloat = 6
    ) -> some View {
        modifier(
            PipiLiquidGlassModifier(
                cornerRadius: cornerRadius,
                borderColor: borderColor,
                borderWidth: borderWidth,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }

    /// Structural sidebar/navigation background: heavier than floating glass panels, single layer, solid fallback when Reduce Transparency is enabled.
    func pipiStructuralMaterial() -> some View {
        modifier(PipiStructuralMaterialModifier())
    }
}

// MARK: - Tactile Instant-Response Button Style (Responds on Pointer-Down)

public struct PipiPressButtonStyle: ButtonStyle {
    public var pressedScale: CGFloat
    public var pressedOpacity: Double

    public init(pressedScale: CGFloat = 0.97, pressedOpacity: Double = 0.88) {
        self.pressedScale = pressedScale
        self.pressedOpacity = pressedOpacity
    }

    public func makeBody(configuration: Configuration) -> some View {
        PipiPressButtonBody(
            configuration: configuration,
            pressedScale: pressedScale,
            pressedOpacity: pressedOpacity
        )
    }
}

private struct PipiPressButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let pressedScale: CGFloat
    let pressedOpacity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

public struct PipiActionButton: View {
    public let title: String
    public let systemImage: String?
    public var tone: PipiButtonTone = .primary
    public var density: PipiButtonDensity = .mobile
    public var fullWidth: Bool = false
    public let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pipiTextScale) private var textScale
    @State private var isHovered: Bool = false

    public init(
        _ title: String,
        systemImage: String? = nil,
        tone: PipiButtonTone = .primary,
        density: PipiButtonDensity = .mobile,
        fullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.density = density
        self.fullWidth = fullWidth
        self.action = action
    }

    public var body: some View {
        let _ = textScale
        Button(action: action) {
            HStack(spacing: density.gap) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: density.iconSize, weight: .semibold))
                        .frame(width: density.iconSize, height: density.iconSize)
                }
                Text(title)
                    .font(density == .mobile ? PipiTokens.fontSubheadline.weight(.semibold) : PipiTokens.fontCaption.weight(.semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, density == .mobile ? PipiTokens.spacing16 : PipiTokens.spacing12)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: density.height)
            .foregroundStyle(foregroundColor)
            .background(backgroundView)
            .overlay(
                RoundedRectangle(cornerRadius: density.cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: density.cornerRadius, style: .continuous))
            .shadow(
                color: tone == .ghost ? Color.clear : PipiTokens.subtleShadow.opacity(isHovered ? 0.65 : 0.45),
                radius: isHovered ? 3 : 1,
                y: 1
            )
            .opacity(isHovered && tone == .primary ? 0.88 : 1.0)
            .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: isHovered)
        }
        .buttonStyle(PipiPressButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var foregroundColor: Color {
        switch tone {
        case .primary: return PipiTokens.textInverse
        case .secondary: return PipiTokens.textPrimary
        case .destructive: return PipiTokens.stateError
        case .ghost: return isHovered ? PipiTokens.textPrimary : PipiTokens.textSecondary
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch tone {
        case .primary: PipiTokens.soulPrimary
        case .secondary: isHovered ? PipiTokens.buttonSecondaryHoverBg : PipiTokens.buttonSecondaryBg
        case .destructive: PipiTokens.stateErrorBg.opacity(isHovered ? 1.3 : 1.0)
        case .ghost: isHovered ? PipiTokens.buttonGhostHoverBg : Color.clear
        }
    }

    private var borderColor: Color {
        switch tone {
        case .primary: return PipiTokens.soulPrimary
        case .secondary: return isHovered ? PipiTokens.buttonHoverBorder : PipiTokens.borderSubtle
        case .destructive: return PipiTokens.stateError.opacity(isHovered ? 0.5 : 0.35)
        case .ghost: return Color.clear
        }
    }
}

// MARK: - Quiet Hover-Responsive Toolbar Icon Button (Machined Ghost Chrome)

public struct PipiGhostIconButton: View {
    public let systemImage: String
    public var isActive: Bool = false
    public var activeColor: Color = PipiTokens.soulPrimary
    public var size: CGFloat = 28
    public var iconSize: CGFloat = 12.5
    public var cornerRadius: CGFloat = PipiTokens.radiusSM
    public var accessibilityLabelText: String? = nil
    public let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    public init(
        systemImage: String,
        isActive: Bool = false,
        activeColor: Color = PipiTokens.soulPrimary,
        size: CGFloat = 28,
        iconSize: CGFloat = 12.5,
        cornerRadius: CGFloat = PipiTokens.radiusSM,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.isActive = isActive
        self.activeColor = activeColor
        self.size = size
        self.iconSize = iconSize
        self.cornerRadius = cornerRadius
        self.accessibilityLabelText = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(isActive ? activeColor : (isHovered ? PipiTokens.textPrimary : PipiTokens.textSecondary))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(isActive ? activeColor.opacity(0.14) : (isHovered ? PipiTokens.buttonGhostHoverBg : Color.clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .animation(PipiMotion.adaptive(PipiMotion.snappy, reduceMotion: reduceMotion), value: isHovered)
        }
        .buttonStyle(PipiPressButtonStyle(pressedScale: 0.92))
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(accessibilityLabelText ?? systemImage)
    }
}

// MARK: - Block 1: PipiListCard (`list-card`)

public struct PipiListCard<Leading: View, Trailing: View, Footer: View>: View {
    public let title: String
    public let subtitle: String
    public var badgeText: String?
    public var badgeColor: Color = PipiTokens.soulPrimary
    private let leading: Leading
    private let trailing: Trailing
    private let footer: Footer
    @Environment(\.pipiTextScale) private var textScale

    public init(
        title: String,
        subtitle: String,
        badgeText: String? = nil,
        badgeColor: Color = PipiTokens.soulPrimary,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badgeText = badgeText
        self.badgeColor = badgeColor
        self.leading = leading()
        self.trailing = trailing()
        self.footer = footer()
    }

    public var body: some View {
        let _ = textScale
        VStack(alignment: .leading, spacing: PipiTokens.spacing12) {
            HStack(alignment: .top, spacing: PipiTokens.spacing12) {
                leading

                VStack(alignment: .leading, spacing: PipiTokens.spacing4) {
                    HStack(spacing: PipiTokens.spacing8) {
                        Text(title)
                            .font(PipiTokens.fontHeadline)
                            .foregroundStyle(PipiTokens.textPrimary)
                            .lineLimit(2)

                        if let badgeText {
                            Text(badgeText)
                                .font(PipiTokens.fontMicro)
                                .foregroundStyle(badgeColor)
                                .padding(.horizontal, PipiTokens.spacing8)
                                .padding(.vertical, 3)
                                .background(badgeColor.opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }

                    Text(subtitle)
                        .font(PipiTokens.fontBody)
                        .foregroundStyle(PipiTokens.textSecondary)
                        .lineLimit(3)
                }

                Spacer(minLength: PipiTokens.spacing8)
                trailing
            }

            footer
        }
        .padding(PipiTokens.spacing16)
        .background(PipiTokens.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusMD, style: .continuous))
    }
}

// MARK: - Block 2: PipiSheet (`sheet`, Top Edge Strictly 54pt or 102pt)

public enum PipiSheetDetent: Sendable {
    case compact   // 54pt top edge
    case expanded  // 102pt top edge

    public var topEdgeOffset: CGFloat {
        switch self {
        case .compact: return PipiTokens.sheetTopEdgeCompact
        case .expanded: return PipiTokens.sheetTopEdgeExpanded
        }
    }
}

public struct PipiSheet<Content: View>: View {
    public let title: String
    public var subtitle: String?
    public var detent: PipiSheetDetent = .expanded
    public let onClose: () -> Void
    private let content: Content

    public init(
        title: String,
        subtitle: String? = nil,
        detent: PipiSheetDetent = .expanded,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detent = detent
        self.onClose = onClose
        self.content = content()
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            PipiTokens.shadowDark
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                Capsule()
                    .fill(PipiTokens.borderStrong)
                    .frame(width: 36, height: 4)
                    .padding(.top, PipiTokens.spacing8)
                    .padding(.bottom, PipiTokens.spacing12)

                HStack(alignment: .center, spacing: PipiTokens.spacing12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(PipiTokens.fontTitle)
                            .foregroundStyle(PipiTokens.textPrimary)
                        if let subtitle {
                            Text(subtitle)
                                .font(PipiTokens.fontCaption)
                                .foregroundStyle(PipiTokens.textSecondary)
                        }
                    }

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: PipiTokens.buttonIconDesktop, weight: .semibold))
                            .foregroundStyle(PipiTokens.textSecondary)
                            .frame(width: PipiTokens.buttonHeightDesktop, height: PipiTokens.buttonHeightDesktop)
                            .background(PipiTokens.bgSurfaceHover)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, PipiTokens.spacing20)
                .padding(.bottom, PipiTokens.spacing16)

                Divider()
                    .overlay(PipiTokens.borderSubtle)

                ScrollView {
                    content
                        .padding(PipiTokens.spacing20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(PipiTokens.bgElevated)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: PipiTokens.radiusXL,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: PipiTokens.radiusXL,
                    style: .continuous
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: PipiTokens.radiusXL,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: PipiTokens.radiusXL,
                    style: .continuous
                )
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
            )
            .padding(.top, detent.topEdgeOffset)
        }
    }
}

// MARK: - Block 3: PipiFormSheet (`form-sheet`: Fields + Full-Width 44pt Primary CTA)

public struct PipiFormSheet<Fields: View>: View {
    public let title: String
    public var subtitle: String?
    public var detent: PipiSheetDetent = .compact
    public let submitLabel: String
    public var submitIcon: String = "checkmark.circle.fill"
    public let onCancel: () -> Void
    public let onSubmit: () -> Void
    private let fields: Fields

    public init(
        title: String,
        subtitle: String? = nil,
        detent: PipiSheetDetent = .compact,
        submitLabel: String,
        submitIcon: String = "checkmark.circle.fill",
        onCancel: @escaping () -> Void,
        onSubmit: @escaping () -> Void,
        @ViewBuilder fields: () -> Fields
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detent = detent
        self.submitLabel = submitLabel
        self.submitIcon = submitIcon
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        self.fields = fields()
    }

    public var body: some View {
        PipiSheet(title: title, subtitle: subtitle, detent: detent, onClose: onCancel) {
            VStack(alignment: .leading, spacing: PipiTokens.spacing16) {
                fields

                PipiActionButton(
                    submitLabel,
                    systemImage: submitIcon,
                    tone: .primary,
                    density: .mobile,
                    fullWidth: true,
                    action: onSubmit
                )
                .padding(.top, PipiTokens.spacing8)
            }
        }
    }
}

// MARK: - Block 4: PipiDock (`dock`: Avatar + Summary Left, Primary Action Right)

public struct PipiDock: View {
    public let avatarEngine: PipiProceduralAvatarEngine
    public let title: String
    public let subtitle: String
    public let actionTitle: String
    public var actionIcon: String = "bolt.fill"
    public var density: PipiButtonDensity = .mobile
    public let onAction: () -> Void
    @Environment(\.pipiTextScale) private var textScale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        avatarEngine: PipiProceduralAvatarEngine,
        title: String,
        subtitle: String,
        actionTitle: String,
        actionIcon: String = "bolt.fill",
        density: PipiButtonDensity = .mobile,
        onAction: @escaping () -> Void
    ) {
        self.avatarEngine = avatarEngine
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.actionIcon = actionIcon
        self.density = density
        self.onAction = onAction
    }

    public var body: some View {
        let _ = textScale
        HStack(spacing: PipiTokens.spacing12) {
            PipiAvatarView(engine: avatarEngine, size: 42, compactMode: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PipiTokens.fontSubheadline.weight(.semibold))
                    .foregroundStyle(PipiTokens.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(PipiTokens.fontCaption)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: PipiTokens.spacing8)

            PipiActionButton(
                actionTitle,
                systemImage: actionIcon,
                tone: .primary,
                density: density,
                action: onAction
            )
        }
        .padding(.horizontal, PipiTokens.spacing16)
        .padding(.vertical, PipiTokens.spacing12)
        .background(reduceTransparency ? PipiTokens.bgElevated : PipiTokens.bgGlass)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous))
    }
}

// MARK: - Block 5: PipiBottomBar (`bottom-bar`: Grounded Bottom Bar, Never Box-in-Box)

public struct PipiBottomBar<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(PipiTokens.borderSubtle)
                .frame(height: 1)

            content
                .padding(.horizontal, PipiTokens.spacing12)
                .padding(.top, PipiTokens.spacing8)
                .padding(.bottom, PipiTokens.spacing12)
                .frame(maxWidth: .infinity)
                .background(PipiTokens.bgElevated)
        }
    }
}

// MARK: - Block 6: PipiEmptyState (`empty-state`: 1 Icon, 1 Title, 1 Sentence, 1 Button Max)

public struct PipiEmptyState: View {
    public let systemImage: String
    public let title: String
    public let message: String
    public var buttonTitle: String?
    public var buttonAction: (() -> Void)?
    @Environment(\.pipiTextScale) private var textScale

    public init(
        systemImage: String,
        title: String,
        message: String,
        buttonTitle: String? = nil,
        buttonAction: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
        self.buttonAction = buttonAction
    }

    public var body: some View {
        let _ = textScale
        VStack(spacing: PipiTokens.spacing16) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(PipiTokens.soulPrimary)
                .frame(width: 60, height: 60)
                .background(PipiTokens.soulPrimary.opacity(0.12))
                .clipShape(Circle())

            VStack(spacing: PipiTokens.spacing8) {
                Text(title)
                    .font(PipiTokens.fontTitle)
                    .foregroundStyle(PipiTokens.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(PipiTokens.fontBody)
                    .foregroundStyle(PipiTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            if let buttonTitle, let buttonAction {
                PipiActionButton(
                    buttonTitle,
                    systemImage: "plus",
                    tone: .primary,
                    density: .mobile,
                    action: buttonAction
                )
            }
        }
        .padding(PipiTokens.spacing24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared Dots Vitality Pulse Indicator

public struct PipiDotIndicator: View {
    public let vitality: DotsVitalityState
    public var color: Color?
    public var size: CGFloat = 10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(vitality: DotsVitalityState, color: Color? = nil, size: CGFloat = 10) {
        self.vitality = vitality
        self.color = color
        self.size = size
    }

    public var body: some View {
        let dotColor = color ?? PipiTokens.color(for: vitality)
        if reduceMotion {
            Circle()
                .fill(dotColor.opacity(vitality == .offline ? 0.45 : 0.92))
                .frame(width: size, height: size)
                .frame(width: size * 2.2, height: size * 2.2)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let period = vitality == .busy ? 1.1 : (vitality == .degraded ? 0.85 : 2.4)
                let phase = (sin((t / period) * .pi * 2.0) + 1.0) * 0.5
                let scale = vitality == .offline ? 0.86 : (0.88 + 0.22 * phase)
                let opacity = vitality == .offline ? 0.45 : (0.72 + 0.28 * phase)

                ZStack {
                    if vitality == .alive || vitality == .busy || vitality == .degraded {
                        Circle()
                            .stroke(dotColor.opacity(0.45 * (1.0 - phase)), lineWidth: 1.5)
                            .frame(width: size * (1.2 + phase * 0.9), height: size * (1.2 + phase * 0.9))
                    }
                    Circle()
                        .fill(dotColor.opacity(opacity))
                        .frame(width: size * scale, height: size * scale)
                }
                .frame(width: size * 2.2, height: size * 2.2)
            }
        }
    }
}

public extension View {
    /// Renders a macOS `Menu` with its exact custom SwiftUI `label` view intact
    /// (preserving shapes, avatars, backgrounds, borders, and trailing chevrons)
    /// without `NSPopUpButton` label-stripping or duplicate system indicators.
    @ViewBuilder
    func pipiPlainMenu() -> some View {
        #if os(macOS)
        self
            .contentShape(Rectangle())
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        #else
        self
            .menuStyle(.button)
        #endif
    }

    /// Suppresses visible scrollbars on macOS even when "Show scroll bars: Always" is enabled,
    /// while preserving smooth trackpad and mouse-wheel scrolling.
    @ViewBuilder
    func pipiHideScrollbars() -> some View {
        modifier(PipiHideScrollbarsModifier())
    }
}

public struct PipiHideScrollbarsModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden)
            #if os(macOS) && !targetEnvironment(macCatalyst)
            .background(
                PipiScrollbarHiderRepresentable()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            )
            #endif
    }
}

#if os(macOS) && !targetEnvironment(macCatalyst)
private struct PipiScrollbarHiderRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> PipiScrollbarHiderNSView {
        PipiScrollbarHiderNSView()
    }

    func updateNSView(_ nsView: PipiScrollbarHiderNSView, context: Context) {
        nsView.scheduleHide()
    }
}

private final class PipiScrollbarHiderNSView: NSView {
    private weak var observedScrollView: NSScrollView?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeObservers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleHide()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleHide()
    }

    override func layout() {
        super.layout()
        scheduleHide()
    }

    func scheduleHide() {
        DispatchQueue.main.async { [weak self] in
            self?.applyHide()
        }
    }

    private func applyHide() {
        guard let scrollView = findTargetScrollView() else { return }
        if observedScrollView !== scrollView {
            removeObservers()
            observedScrollView = scrollView
            installObservers(for: scrollView)
        }
        Self.suppressScrollbars(on: scrollView)
    }

    private static func suppressScrollbars(on scrollView: NSScrollView) {
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
        if !scrollView.autohidesScrollers {
            scrollView.autohidesScrollers = true
        }
        scrollView.verticalScroller?.alphaValue = 0
        scrollView.horizontalScroller?.alphaValue = 0
    }

    private func findTargetScrollView() -> NSScrollView? {
        if let direct = enclosingScrollView {
            return direct
        }
        var current = superview
        var depth = 0
        while let container = current, depth < 4 {
            if container is NSSplitView {
                break
            }
            if let found = firstDescendantScrollView(in: container, maxDepth: 4) {
                return found
            }
            current = container.superview
            depth += 1
        }
        return nil
    }

    private func firstDescendantScrollView(in root: NSView, maxDepth: Int) -> NSScrollView? {
        guard maxDepth >= 0 else { return nil }
        for sub in root.subviews {
            if let sv = sub as? NSScrollView {
                return sv
            }
        }
        guard maxDepth > 0 else { return nil }
        for sub in root.subviews {
            if let sv = firstDescendantScrollView(in: sub, maxDepth: maxDepth - 1) {
                return sv
            }
        }
        return nil
    }

    private func installObservers(for scrollView: NSScrollView) {
        let nc = NotificationCenter.default
        let names: [Notification.Name] = [
            NSScrollView.willStartLiveScrollNotification,
            NSScrollView.didLiveScrollNotification,
            NSScrollView.didEndLiveScrollNotification
        ]
        for name in names {
            let token = nc.addObserver(forName: name, object: scrollView, queue: .main) { [weak scrollView] _ in
                guard let scrollView else { return }
                MainActor.assumeIsolated {
                    Self.suppressScrollbars(on: scrollView)
                }
            }
            observers.append(token)
        }
        let styleToken = nc.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak scrollView] _ in
            guard let scrollView else { return }
            MainActor.assumeIsolated {
                Self.suppressScrollbars(on: scrollView)
            }
        }
        observers.append(styleToken)
    }

    nonisolated private func removeObservers() {
        let nc = NotificationCenter.default
        for token in observers {
            nc.removeObserver(token)
        }
        observers.removeAll()
    }
}
#endif
