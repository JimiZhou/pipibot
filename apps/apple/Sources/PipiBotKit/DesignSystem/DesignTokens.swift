import SwiftUI

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Theme Mode Preference

public enum PipiThemeMode: String, CaseIterable, Sendable, Identifiable {
    case system
    case dark
    case light

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "Auto"
        case .dark: return "Obsidian"
        case .light: return "Vellum"
        }
    }

    public var colorSchemeOverride: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

// MARK: - Tier 1: Foundations (Raw Immutable Palette)

public enum PipiFoundations {
    // Obsidian Carbon Dark Scale
    public static let obsidian950 = "#08090B"
    public static let obsidian900 = "#0B0C0E"
    public static let obsidian850 = "#121418"
    public static let obsidian800 = "#171A20"
    public static let obsidian750 = "#1E222B"
    public static let obsidian650 = "#262B38"
    public static let obsidian550 = "#363C4F"

    // Warm Vellum Light Scale
    public static let vellum50 = "#FFFFFF"
    public static let vellum100 = "#FDFCF9"
    public static let vellum150 = "#F7F5F0"
    public static let vellum200 = "#F1EDE4"
    public static let vellum250 = "#EBE6DC"

    // Ink Neutrals
    public static let inkDarkPrimary = "#F4F5F7"
    public static let inkDarkSecondary = "#A1A7B3"
    public static let inkDarkMuted = "#6C7382"
    public static let inkLightPrimary = "#171614"
    public static let inkLightSecondary = "#5E5B55"
    public static let inkLightMuted = "#8B867D"

    // Soul & Brand Accents
    public static let violet400 = "#7C6CF6"
    public static let violet600 = "#5B4CE4"
    public static let sky400 = "#38BDF8"
    public static let sky600 = "#0284C7"

    // Harness Identity Accents
    public static let harnessPi = "#10B981"
    public static let harnessClaude = "#D97757"
    public static let harnessCodex = "#3B82F6"
    public static let harnessOpencode = "#A855F7"
    public static let harnessByok = "#F59E0B"

    // Fleet Node Accents
    public static let fleetMac = "#38BDF8"
    public static let fleetIos = "#818CF8"
    public static let fleetVps = "#10B981"
    public static let fleetWindows = "#60A5FA"
    public static let fleetEmbedded = "#F472B6"

    // Semantic Status
    public static let okDark = "#10B981"
    public static let okLight = "#059669"
    public static let warnDark = "#F59E0B"
    public static let warnLight = "#D97706"
    public static let dangerDark = "#EF4444"
    public static let dangerLight = "#DC2626"
    public static let infoDark = "#38BDF8"
    public static let infoLight = "#0284C7"
    public static let evolvePurple = "#C084FC"
    public static let pureWhite = "#FFFFFF"
    public static let pureBlack = "#000000"

    static func rgba(_ hex: String, alpha: Double = 1.0) -> (r: Double, g: Double, b: Double, a: Double) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return (r, g, b, alpha)
    }

    public static func color(_ hex: String, alpha: Double = 1.0) -> Color {
        let parts = rgba(hex, alpha: alpha)
        return Color(.sRGB, red: parts.r, green: parts.g, blue: parts.b, opacity: parts.a)
    }

    static func adaptiveColor(darkHex: String, darkAlpha: Double = 1.0, lightHex: String, lightAlpha: Double = 1.0) -> Color {
        let d = rgba(darkHex, alpha: darkAlpha)
        let l = rgba(lightHex, alpha: lightAlpha)
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            let active = (match == .darkAqua) ? d : l
            return NSColor(srgbRed: active.r, green: active.g, blue: active.b, alpha: active.a)
        })
        #elseif canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            let active = (traits.userInterfaceStyle == .dark) ? d : l
            return UIColor(red: active.r, green: active.g, blue: active.b, alpha: active.a)
        })
        #else
        return Color(.sRGB, red: d.r, green: d.g, blue: d.b, opacity: d.a)
        #endif
    }
}

// MARK: - Tier 2: Adaptive Theme Palettes

public struct PipiThemePalette: Sendable {
    public let bgCanvas: Color
    public let bgElevated: Color
    public let bgSurface: Color
    public let bgSurfaceHover: Color
    public let bgInset: Color
    public let bgGlass: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textMuted: Color
    public let textInverse: Color
    public let borderSubtle: Color
    public let borderStrong: Color
    public let soulPrimary: Color
    public let soulSecondary: Color
    public let stateSuccess: Color
    public let stateWarning: Color
    public let stateError: Color
    public let stateInfo: Color

    public static let obsidianDark = PipiThemePalette(
        bgCanvas: PipiFoundations.color(PipiFoundations.obsidian900),
        bgElevated: PipiFoundations.color(PipiFoundations.obsidian850),
        bgSurface: PipiFoundations.color(PipiFoundations.obsidian800),
        bgSurfaceHover: PipiFoundations.color(PipiFoundations.obsidian750),
        bgInset: PipiFoundations.color(PipiFoundations.obsidian950),
        bgGlass: PipiFoundations.color(PipiFoundations.obsidian800, alpha: 0.78),
        textPrimary: PipiFoundations.color(PipiFoundations.inkDarkPrimary),
        textSecondary: PipiFoundations.color(PipiFoundations.inkDarkSecondary),
        textMuted: PipiFoundations.color(PipiFoundations.inkDarkMuted),
        textInverse: PipiFoundations.color(PipiFoundations.obsidian900),
        borderSubtle: PipiFoundations.color(PipiFoundations.pureWhite, alpha: 0.08),
        borderStrong: PipiFoundations.color(PipiFoundations.pureWhite, alpha: 0.16),
        soulPrimary: PipiFoundations.color(PipiFoundations.violet400),
        soulSecondary: PipiFoundations.color(PipiFoundations.sky400),
        stateSuccess: PipiFoundations.color(PipiFoundations.okDark),
        stateWarning: PipiFoundations.color(PipiFoundations.warnDark),
        stateError: PipiFoundations.color(PipiFoundations.dangerDark),
        stateInfo: PipiFoundations.color(PipiFoundations.infoDark)
    )

    public static let warmVellumLight = PipiThemePalette(
        bgCanvas: PipiFoundations.color(PipiFoundations.vellum150),
        bgElevated: PipiFoundations.color(PipiFoundations.vellum50),
        bgSurface: PipiFoundations.color(PipiFoundations.vellum100),
        bgSurfaceHover: PipiFoundations.color(PipiFoundations.vellum200),
        bgInset: PipiFoundations.color(PipiFoundations.vellum250),
        bgGlass: PipiFoundations.color(PipiFoundations.vellum100, alpha: 0.86),
        textPrimary: PipiFoundations.color(PipiFoundations.inkLightPrimary),
        textSecondary: PipiFoundations.color(PipiFoundations.inkLightSecondary),
        textMuted: PipiFoundations.color(PipiFoundations.inkLightMuted),
        textInverse: PipiFoundations.color(PipiFoundations.vellum50),
        borderSubtle: PipiFoundations.color(PipiFoundations.inkLightPrimary, alpha: 0.09),
        borderStrong: PipiFoundations.color(PipiFoundations.inkLightPrimary, alpha: 0.18),
        soulPrimary: PipiFoundations.color(PipiFoundations.violet600),
        soulSecondary: PipiFoundations.color(PipiFoundations.sky600),
        stateSuccess: PipiFoundations.color(PipiFoundations.okLight),
        stateWarning: PipiFoundations.color(PipiFoundations.warnLight),
        stateError: PipiFoundations.color(PipiFoundations.dangerLight),
        stateInfo: PipiFoundations.color(PipiFoundations.infoLight)
    )
}

// MARK: - Tier 3: Semantic Design Tokens (Referenced by All Views)

public enum PipiTokens {
    // Dynamic Adaptive Surfaces
    public static let bgCanvas = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.obsidian900,
        lightHex: PipiFoundations.vellum150
    )
    public static let bgElevated = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.obsidian850,
        lightHex: PipiFoundations.vellum50
    )
    public static let bgSurface = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.obsidian800,
        lightHex: PipiFoundations.vellum100
    )
    public static let bgSurfaceHover = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.obsidian750,
        lightHex: PipiFoundations.vellum200
    )
    public static let bgInset = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.obsidian950,
        lightHex: PipiFoundations.vellum250
    )
    public static let bgGlass = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.obsidian800,
        darkAlpha: 0.76,
        lightHex: PipiFoundations.vellum100,
        lightAlpha: 0.84
    )

    // Dynamic Adaptive Typography
    public static let textPrimary = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.inkDarkPrimary,
        lightHex: PipiFoundations.inkLightPrimary
    )
    public static let textSecondary = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.inkDarkSecondary,
        lightHex: PipiFoundations.inkLightSecondary
    )
    public static let textMuted = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.inkDarkMuted,
        lightHex: PipiFoundations.inkLightMuted
    )
    public static let textInverse = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.obsidian900,
        lightHex: PipiFoundations.vellum50
    )

    // Dynamic Borders
    public static let borderSubtle = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureWhite,
        darkAlpha: 0.09,
        lightHex: PipiFoundations.inkLightPrimary,
        lightAlpha: 0.09
    )
    public static let borderStrong = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureWhite,
        darkAlpha: 0.17,
        lightHex: PipiFoundations.inkLightPrimary,
        lightAlpha: 0.18
    )
    public static let borderFocus = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.violet400,
        darkAlpha: 0.55,
        lightHex: PipiFoundations.violet600,
        lightAlpha: 0.45
    )

    // Soul & Brand Accents (light mode maintains >= 4.5:1 contrast)
    public static let soulPrimary = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.violet400,
        lightHex: PipiFoundations.violet600
    )
    public static let soulSecondary = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.sky400,
        lightHex: PipiFoundations.sky600
    )
    public static let soulGlow = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.violet400,
        darkAlpha: 0.34,
        lightHex: PipiFoundations.violet600,
        lightAlpha: 0.22
    )

    // Procedural Avatar Shell Surfaces
    public static let avatarShellTop = PipiFoundations.color(PipiFoundations.obsidian550)
    public static let avatarShellMid = PipiFoundations.color(PipiFoundations.obsidian750)
    public static let avatarShellBottom = PipiFoundations.color(PipiFoundations.obsidian950)
    public static let avatarRimHighlight = PipiFoundations.color(PipiFoundations.pureWhite, alpha: 0.22)
    public static let avatarGlint = PipiFoundations.color(PipiFoundations.pureWhite, alpha: 0.90)
    public static let dynamicIslandShell = PipiFoundations.color(PipiFoundations.pureBlack)
    public static let dynamicIslandStroke = PipiFoundations.color(PipiFoundations.pureWhite, alpha: 0.14)
    public static let shadowDark = PipiFoundations.color(PipiFoundations.pureBlack, alpha: 0.36)

    // Semantic Status Colors
    public static let stateSuccess = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.okDark,
        lightHex: PipiFoundations.okLight
    )
    public static let stateSuccessBg = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.okDark,
        darkAlpha: 0.14,
        lightHex: PipiFoundations.okLight,
        lightAlpha: 0.12
    )
    public static let stateWarning = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.warnDark,
        lightHex: PipiFoundations.warnLight
    )
    public static let stateWarningBg = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.warnDark,
        darkAlpha: 0.14,
        lightHex: PipiFoundations.warnLight,
        lightAlpha: 0.12
    )
    public static let stateError = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.dangerDark,
        lightHex: PipiFoundations.dangerLight
    )
    public static let stateErrorBg = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.dangerDark,
        darkAlpha: 0.15,
        lightHex: PipiFoundations.dangerLight,
        lightAlpha: 0.12
    )
    public static let stateInfo = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.infoDark,
        lightHex: PipiFoundations.infoLight
    )
    public static let stateInfoBg = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.infoDark,
        darkAlpha: 0.14,
        lightHex: PipiFoundations.infoLight,
        lightAlpha: 0.12
    )

    // Harness Identity Tokens
    public static let harnessPi = PipiFoundations.color(PipiFoundations.harnessPi)
    public static let harnessClaude = PipiFoundations.color(PipiFoundations.harnessClaude)
    public static let harnessCodex = PipiFoundations.color(PipiFoundations.harnessCodex)
    public static let harnessOpencode = PipiFoundations.color(PipiFoundations.harnessOpencode)
    public static let harnessByok = PipiFoundations.color(PipiFoundations.harnessByok)

    // Fleet Node Tokens
    public static let fleetMac = PipiFoundations.color(PipiFoundations.fleetMac)
    public static let fleetIos = PipiFoundations.color(PipiFoundations.fleetIos)
    public static let fleetVps = PipiFoundations.color(PipiFoundations.fleetVps)
    public static let fleetWindows = PipiFoundations.color(PipiFoundations.fleetWindows)
    public static let fleetEmbedded = PipiFoundations.color(PipiFoundations.fleetEmbedded)
    public static let evolveAccent = PipiFoundations.color(PipiFoundations.evolvePurple)

    // MARK: Semantic Color Resolvers

    public static func color(for provider: HarnessProvider) -> Color {
        switch provider {
        case .pi: return harnessPi
        case .claudeCode: return harnessClaude
        case .codex: return harnessCodex
        case .opencode: return harnessOpencode
        case .byok: return harnessByok
        }
    }

    public static func color(for kind: FleetNodeKind) -> Color {
        switch kind {
        case .mac: return fleetMac
        case .ios: return fleetIos
        case .vps: return fleetVps
        case .windows: return fleetWindows
        case .embedded: return fleetEmbedded
        }
    }

    public static func color(for vitality: DotsVitalityState) -> Color {
        switch vitality {
        case .alive: return stateSuccess
        case .busy: return stateInfo
        case .degraded: return stateWarning
        case .sleeping: return fleetIos
        case .offline: return textMuted
        }
    }

    public static func color(for severity: DecisionSeverity) -> Color {
        switch severity {
        case .info: return stateInfo
        case .warning: return stateWarning
        case .critical: return stateError
        }
    }

    public static func color(for group: AvatarLifecycleGroup) -> Color {
        switch group {
        case .idleAmbient: return soulPrimary
        case .thinkingReasoning: return soulSecondary
        case .toolHarnessExecution: return harnessPi
        case .cueNeedsYouAlert: return stateWarning
        case .selfEvolutionDreaming: return evolveAccent
        }
    }

    public static func color(for domain: OutcomeDomain) -> Color {
        switch domain {
        case .dev: return harnessPi
        case .work: return harnessCodex
        case .dailyLife: return harnessByok
        case .infra: return fleetEmbedded
        }
    }

    public static func color(for state: AvatarState53) -> Color {
        let meta = PipiProceduralAvatarEngine.metadata(for: state)
        switch meta.state {
        case .claudeRouting: return harnessClaude
        case .codexRouting: return harnessCodex
        case .opencodeRouting: return harnessOpencode
        case .byokStreaming, .manusCue, .cueWhispering: return harnessByok
        case .needsYou, .needsYouUrgent: return stateError
        case .fleetDegraded, .tunnelReconnecting, .needsYouApproval: return stateWarning
        case .evolving, .dreamingConsolidating, .skillSynthesizing: return evolveAccent
        case .sleeping, .ambientNightWatch: return fleetIos
        case .iotSignaling: return fleetEmbedded
        case .evolutionProud, .gitCommitting, .piCoding, .piBashRunning, .piFileEditing: return harnessPi
        default: return color(for: meta.group)
        }
    }

    // MARK: 4px Spatial Scale & Canonical OpenPencil Geometry Rules

    public static let spacing4: CGFloat = 4
    public static let spacing8: CGFloat = 8
    public static let spacing12: CGFloat = 12
    public static let spacing16: CGFloat = 16
    public static let spacing20: CGFloat = 20
    public static let spacing24: CGFloat = 24
    public static let spacing32: CGFloat = 32

    public static let radiusXS: CGFloat = 6
    public static let radiusSM: CGFloat = 10
    public static let radiusMD: CGFloat = 14
    public static let radiusLG: CGFloat = 20
    public static let radiusXL: CGFloat = 28
    public static let radius2XL: CGFloat = 36
    public static let radiusPill: CGFloat = 9999

    /// Mobile button geometry rule: height 44pt, icon 18pt, gap 8pt
    public static let buttonHeightMobile: CGFloat = 44
    public static let buttonIconMobile: CGFloat = 18
    public static let buttonGapMobile: CGFloat = 8

    /// Desktop macOS compact button geometry rule: height 32pt, icon 16pt, gap 6pt
    public static let buttonHeightDesktop: CGFloat = 32
    public static let buttonIconDesktop: CGFloat = 16
    public static let buttonGapDesktop: CGFloat = 6

    /// Sheet top edge rule: 54pt or 102pt only (never in between)
    public static let sheetTopEdgeCompact: CGFloat = 54
    public static let sheetTopEdgeExpanded: CGFloat = 102

    /// Icon stroke weight rules: 1.5px (16-18pt) / 1.75px (20-24pt)
    public static let iconStrokeSmall: CGFloat = 1.5
    public static let iconStrokeLarge: CGFloat = 1.75

    // MARK: Typography Hierarchy

    public static let fontHero = Font.system(size: 26, weight: .bold, design: .rounded)
    public static let fontTitle = Font.system(size: 20, weight: .semibold, design: .default)
    public static let fontHeadline = Font.system(size: 16, weight: .semibold, design: .default)
    public static let fontBody = Font.system(size: 14, weight: .regular, design: .default)
    public static let fontSubheadline = Font.system(size: 13, weight: .medium, design: .default)
    public static let fontCaption = Font.system(size: 12, weight: .medium, design: .default)
    public static let fontMicro = Font.system(size: 11, weight: .semibold, design: .default)
    public static let fontMono = Font.system(size: 12, weight: .medium, design: .monospaced)
    public static let fontMonoSmall = Font.system(size: 11, weight: .medium, design: .monospaced)
}
