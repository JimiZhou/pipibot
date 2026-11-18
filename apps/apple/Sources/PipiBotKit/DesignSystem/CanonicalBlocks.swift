import SwiftUI

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

public struct PipiActionButton: View {
    public let title: String
    public let systemImage: String?
    public var tone: PipiButtonTone = .primary
    public var density: PipiButtonDensity = .mobile
    public var fullWidth: Bool = false
    public let action: () -> Void

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
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        switch tone {
        case .primary: return PipiTokens.textInverse
        case .secondary: return PipiTokens.textPrimary
        case .destructive: return PipiTokens.stateError
        case .ghost: return PipiTokens.textSecondary
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch tone {
        case .primary: PipiTokens.soulPrimary
        case .secondary: PipiTokens.bgSurfaceHover
        case .destructive: PipiTokens.stateErrorBg
        case .ghost: Color.clear
        }
    }

    private var borderColor: Color {
        switch tone {
        case .primary: return PipiTokens.soulPrimary.opacity(0.6)
        case .secondary: return PipiTokens.borderSubtle
        case .destructive: return PipiTokens.stateError.opacity(0.35)
        case .ghost: return Color.clear
        }
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
        .background(PipiTokens.bgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous)
                .stroke(PipiTokens.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: PipiTokens.radiusLG, style: .continuous))
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
        .background(PipiTokens.bgGlass)
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

    public init(vitality: DotsVitalityState, color: Color? = nil, size: CGFloat = 10) {
        self.vitality = vitality
        self.color = color
        self.size = size
    }

    public var body: some View {
        let dotColor = color ?? PipiTokens.color(for: vitality)
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
