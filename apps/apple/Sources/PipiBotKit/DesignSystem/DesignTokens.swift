import SwiftUI
import os

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
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    public func localizedLabel(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .system: return lang == .zhHans ? "跟随系统" : "Auto"
        case .dark: return lang == .zhHans ? "深色" : "Dark"
        case .light: return lang == .zhHans ? "浅色" : "Light"
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
    // Neutral Graphite Dark Scale (Codex / Linear Desktop Parity)
    public static let obsidian950 = "#0B0C0E"
    public static let obsidian900 = "#0F1012"
    public static let obsidian850 = "#141518"
    public static let obsidian800 = "#181A1E"
    public static let obsidian750 = "#22242A"
    public static let obsidian650 = "#2C2F36"
    public static let obsidian550 = "#3B3F48"

    // Neutral White-Gray Desktop Light Scale
    public static let vellum50 = "#FFFFFF"
    public static let vellum100 = "#F8F8F9"
    public static let vellum150 = "#F7F7F8"
    public static let vellum200 = "#EFEFF1"
    public static let vellum250 = "#F2F2F4"
    public static let vellumUserBubble = "#F4F4F5"

    // Neutral Ink Tokens
    public static let inkDarkPrimary = "#F4F4F5"
    public static let inkDarkSecondary = "#A1A1AA"
    public static let inkDarkMuted = "#71717A"
    public static let inkLightPrimary = "#171717"
    public static let inkLightSecondary = "#52525B"
    public static let inkLightMuted = "#71717A"

    // Monochrome Primary Control Foundations
    public static let controlLightPrimary = "#171717"
    public static let controlLightHover = "#27272A"
    public static let controlLightSecondaryHover = "#F4F4F5"
    public static let controlDarkPrimary = "#F4F4F5"
    public static let controlDarkHover = "#E4E4E7"

    // Brand Accents (Retained in Foundations for Optional Visual Highlights)
    public static let cobalt400 = "#4C8DF6"
    public static let cobalt600 = "#2563EB"
    public static let violet400 = "#4C8DF6"
    public static let violet600 = "#2563EB"
    public static let sky400 = "#38BDF8"
    public static let sky600 = "#0284C7"

    // Refined Persona Accents (Harmonized for Graphite Dark & Alabaster Light)
    public static let accentIrisDark = "#6C8EEF"
    public static let accentIrisLight = "#3B5BDB"
    public static let accentEmeraldDark = "#34D399"
    public static let accentEmeraldLight = "#059669"
    public static let accentAmberDark = "#FBBF24"
    public static let accentAmberLight = "#D97706"
    public static let accentSkyDark = "#38BDF8"
    public static let accentSkyLight = "#0284C7"
    public static let accentCoralDark = "#FB7185"
    public static let accentCoralLight = "#E11D48"

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

    // Semantic Status (>= 4.5:1 WCAG AA contrast on #FFFFFF in Light mode)
    public static let okDark = "#10B981"
    public static let okLight = "#047857"
    public static let warnDark = "#F59E0B"
    public static let warnLight = "#B45309"
    public static let dangerDark = "#EF4444"
    public static let dangerLight = "#B91C1C"
    public static let infoDark = "#38BDF8"
    public static let infoLight = "#0369A1"
    public static let evolvePurple = "#C084FC"
    public static let pureWhite = "#FFFFFF"
    public static let pureBlack = "#000000"

    // Codex-Designed Original PipiBot Hardware Robot Palette
    // Dark: Obsidian Titanium / Smoked Glass Visor / Luminous Iris-Cyan Lenses
    public static let robotDarkField = "#0A0C0F"
    public static let robotDarkChassisTop = "#2A3038"
    public static let robotDarkChassisBase = "#1A1F26"
    public static let robotDarkChassisBottom = "#0E1217"
    public static let robotDarkChassisRim = "#4A5560"
    public static let robotDarkVisor = "#081418"
    public static let robotDarkVisorRim = "#2E4A4E"
    public static let robotDarkLensRing = "#1FB8B0"
    public static let robotDarkLensIris = "#63F5E6"
    public static let robotDarkLensCore = "#D8FFFB"
    public static let robotDarkStatusWarm = "#FFB86B"

    // Light: Porcelain Ceramic / Deep Sapphire-Indigo Visor / Arctic-Cyan High-Contrast Lenses (>= 10:1)
    public static let robotLightField = "#F7F5F0"
    public static let robotLightChassisTop = "#FFFFFF"
    public static let robotLightChassisBase = "#F2EFE8"
    public static let robotLightChassisBottom = "#D8D2C6"
    public static let robotLightChassisRim = "#B9B2A6"
    public static let robotLightVisor = "#172554"
    public static let robotLightVisorRim = "#3B4A7A"
    public static let robotLightLensRing = "#E8FFFF"
    public static let robotLightLensIris = "#67E8F9"
    public static let robotLightLensCore = "#F7FDFF"
    public static let robotLightStatusWarm = "#B45309"

    // Per-Persona High-Contrast Optical Lens Palettes (All >= 8.9:1 on Dark/Sapphire Visor)
    public static let lensIrisViolet = "#A78BFA"
    public static let lensCoreViolet = "#EDE9FE"
    public static let lensIrisEmerald = "#34D399"
    public static let lensCoreEmerald = "#D1FAE5"
    public static let lensIrisAmber = "#FBBF24"
    public static let lensCoreAmber = "#FEF3C7"
    public static let lensIrisSky = "#38BDF8"
    public static let lensCoreSky = "#E0F2FE"
    public static let lensIrisCoral = "#FB7185"
    public static let lensCoreCoral = "#FFE4E6"

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
    public let bgSidebar: Color
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
        bgSidebar: PipiFoundations.color(PipiFoundations.obsidian850),
        bgElevated: PipiFoundations.color(PipiFoundations.obsidian800),
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
        soulPrimary: PipiFoundations.color(PipiFoundations.controlDarkPrimary),
        soulSecondary: PipiFoundations.color(PipiFoundations.sky400),
        stateSuccess: PipiFoundations.color(PipiFoundations.okDark),
        stateWarning: PipiFoundations.color(PipiFoundations.warnDark),
        stateError: PipiFoundations.color(PipiFoundations.dangerDark),
        stateInfo: PipiFoundations.color(PipiFoundations.infoDark)
    )

    public static let warmVellumLight = PipiThemePalette(
        bgCanvas: PipiFoundations.color(PipiFoundations.vellum50),
        bgSidebar: PipiFoundations.color(PipiFoundations.vellum150),
        bgElevated: PipiFoundations.color(PipiFoundations.vellum50),
        bgSurface: PipiFoundations.color(PipiFoundations.vellum100),
        bgSurfaceHover: PipiFoundations.color(PipiFoundations.vellum200),
        bgInset: PipiFoundations.color(PipiFoundations.vellum250),
        bgGlass: PipiFoundations.color(PipiFoundations.vellum50, alpha: 0.90),
        textPrimary: PipiFoundations.color(PipiFoundations.inkLightPrimary),
        textSecondary: PipiFoundations.color(PipiFoundations.inkLightSecondary),
        textMuted: PipiFoundations.color(PipiFoundations.inkLightMuted),
        textInverse: PipiFoundations.color(PipiFoundations.pureWhite),
        borderSubtle: PipiFoundations.color(PipiFoundations.inkLightPrimary, alpha: 0.08),
        borderStrong: PipiFoundations.color(PipiFoundations.inkLightPrimary, alpha: 0.16),
        soulPrimary: PipiFoundations.color(PipiFoundations.controlLightPrimary),
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
        lightHex: PipiFoundations.vellum50
    )
    public static let bgSidebar = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.obsidian850,
        lightHex: PipiFoundations.vellum150
    )
    public static let bgElevated = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.obsidian800,
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
        darkAlpha: 0.78,
        lightHex: PipiFoundations.vellum50,
        lightAlpha: 0.90
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
        lightHex: PipiFoundations.pureWhite
    )

    // Dynamic Borders
    public static let borderSubtle = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureWhite,
        darkAlpha: 0.08,
        lightHex: PipiFoundations.inkLightPrimary,
        lightAlpha: 0.08
    )
    public static let borderStrong = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureWhite,
        darkAlpha: 0.16,
        lightHex: PipiFoundations.inkLightPrimary,
        lightAlpha: 0.16
    )
    public static let borderFocus = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureWhite,
        darkAlpha: 0.28,
        lightHex: PipiFoundations.inkLightPrimary,
        lightAlpha: 0.28
    )

    // Monochrome Primary Chrome & Secondary Accent (Contrast >15:1)
    public static let soulPrimary = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.controlDarkPrimary,
        lightHex: PipiFoundations.controlLightPrimary
    )
    public static let soulSecondary = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.sky400,
        lightHex: PipiFoundations.sky600
    )
    public static let soulGlow = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureWhite,
        darkAlpha: 0.16,
        lightHex: PipiFoundations.inkLightPrimary,
        lightAlpha: 0.12
    )

    // Procedural Avatar & Adaptive Robot Hardware Surfaces (Dark: Obsidian Titanium / Light: Porcelain Ceramic)
    public static let avatarShellTop = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.robotDarkChassisTop,
        lightHex: PipiFoundations.robotLightChassisTop
    )
    public static let avatarShellMid = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.robotDarkChassisBase,
        lightHex: PipiFoundations.robotLightChassisBase
    )
    public static let avatarShellBottom = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.robotDarkChassisBottom,
        lightHex: PipiFoundations.robotLightChassisBottom
    )
    public static let avatarChassisRim = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.robotDarkChassisRim,
        lightHex: PipiFoundations.robotLightChassisRim
    )
    public static let avatarVisorFill = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.robotDarkVisor,
        lightHex: PipiFoundations.robotLightVisor
    )
    public static let avatarVisorRim = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.robotDarkVisorRim,
        lightHex: PipiFoundations.robotLightVisorRim
    )
    public static let avatarLensRing = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.robotDarkLensRing,
        lightHex: PipiFoundations.robotLightLensRing
    )
    public static let avatarLensIris = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.robotDarkLensIris,
        lightHex: PipiFoundations.robotLightLensIris
    )
    public static let avatarLensCore = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.robotDarkLensCore,
        lightHex: PipiFoundations.robotLightLensCore
    )
    public static let avatarStatusWarm = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.robotDarkStatusWarm,
        lightHex: PipiFoundations.robotLightStatusWarm
    )
    public static let avatarRimHighlight = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureWhite,
        darkAlpha: 0.24,
        lightHex: PipiFoundations.pureWhite,
        lightAlpha: 0.92
    )
    public static let avatarGlint = PipiFoundations.color(PipiFoundations.pureWhite, alpha: 0.94)
    public static let dynamicIslandShell = PipiFoundations.color(PipiFoundations.pureBlack)
    public static let dynamicIslandStroke = PipiFoundations.color(PipiFoundations.pureWhite, alpha: 0.14)
    public static let shadowDark = PipiFoundations.color(PipiFoundations.pureBlack, alpha: 0.36)

    // Apple Liquid Glass Material Tokens (Restrained, High-Craft)
    public static let glassTopHighlight = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureWhite,
        darkAlpha: 0.14,
        lightHex: PipiFoundations.pureWhite,
        lightAlpha: 0.85
    )
    public static let liquidGlassBorder = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureWhite,
        darkAlpha: 0.12,
        lightHex: PipiFoundations.inkLightPrimary,
        lightAlpha: 0.09
    )
    public static let liquidGlassSurface = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.obsidian800,
        darkAlpha: 0.72,
        lightHex: PipiFoundations.vellum50,
        lightAlpha: 0.94
    )
    public static let elevatedShadow = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureBlack,
        darkAlpha: 0.36,
        lightHex: PipiFoundations.inkLightPrimary,
        lightAlpha: 0.08
    )
    public static let subtleShadow = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureBlack,
        darkAlpha: 0.20,
        lightHex: PipiFoundations.inkLightPrimary,
        lightAlpha: 0.045
    )

    // Cohesive Composer & Tactile Button Surfaces (Blends Naturally with bgCanvas in Both Light & Dark)
    public static let composerSurface = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.obsidian800,
        darkAlpha: 1.0,
        lightHex: PipiFoundations.vellum50,
        lightAlpha: 1.0
    )
    public static let userBubbleBg = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.obsidian800,
        darkAlpha: 1.0,
        lightHex: PipiFoundations.vellumUserBubble,
        lightAlpha: 1.0
    )
    public static let composerBorder = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureWhite,
        darkAlpha: 0.12,
        lightHex: PipiFoundations.inkLightPrimary,
        lightAlpha: 0.11
    )
    public static let composerBorderFocused = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureWhite,
        darkAlpha: 0.26,
        lightHex: PipiFoundations.inkLightPrimary,
        lightAlpha: 0.26
    )
    public static let composerShadow = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureBlack,
        darkAlpha: 0.34,
        lightHex: PipiFoundations.inkLightPrimary,
        lightAlpha: 0.05
    )
    public static let buttonSecondaryBg = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.obsidian800,
        darkAlpha: 1.0,
        lightHex: PipiFoundations.vellum50,
        lightAlpha: 1.0
    )
    public static let buttonSecondaryHoverBg = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.obsidian750,
        darkAlpha: 1.0,
        lightHex: PipiFoundations.controlLightSecondaryHover,
        lightAlpha: 1.0
    )
    public static let buttonGhostHoverBg = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureWhite,
        darkAlpha: 0.075,
        lightHex: PipiFoundations.inkLightPrimary,
        lightAlpha: 0.055
    )
    public static let buttonHoverBorder = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.pureWhite,
        darkAlpha: 0.20,
        lightHex: PipiFoundations.inkLightPrimary,
        lightAlpha: 0.16
    )

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

    public static let personaIris = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.accentIrisDark,
        lightHex: PipiFoundations.accentIrisLight
    )
    public static let personaEmerald = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.accentEmeraldDark,
        lightHex: PipiFoundations.accentEmeraldLight
    )
    public static let personaAmber = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.accentAmberDark,
        lightHex: PipiFoundations.accentAmberLight
    )
    public static let personaSky = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.accentSkyDark,
        lightHex: PipiFoundations.accentSkyLight
    )
    public static let personaCoral = PipiFoundations.adaptiveColor(
        darkHex: PipiFoundations.accentCoralDark,
        lightHex: PipiFoundations.accentCoralLight
    )

    public static func color(for accent: PipiPersonaAccent) -> Color {
        switch accent {
        case .iris: return personaIris
        case .emerald: return personaEmerald
        case .amber: return personaAmber
        case .sky: return personaSky
        case .coral: return personaCoral
        }
    }

    /// High-contrast luminous optical lens iris color for each Bot persona (equally vivid in Light & Dark mode on dark visor).
    public static func lensIris(for accent: PipiPersonaAccent) -> Color {
        switch accent {
        case .iris: return PipiFoundations.color(PipiFoundations.lensIrisViolet)
        case .emerald: return PipiFoundations.color(PipiFoundations.lensIrisEmerald)
        case .amber: return PipiFoundations.color(PipiFoundations.lensIrisAmber)
        case .sky: return PipiFoundations.color(PipiFoundations.lensIrisSky)
        case .coral: return PipiFoundations.color(PipiFoundations.lensIrisCoral)
        }
    }

    /// High-contrast optical lens specular core color for each Bot persona.
    public static func lensCore(for accent: PipiPersonaAccent) -> Color {
        switch accent {
        case .iris: return PipiFoundations.color(PipiFoundations.lensCoreViolet)
        case .emerald: return PipiFoundations.color(PipiFoundations.lensCoreEmerald)
        case .amber: return PipiFoundations.color(PipiFoundations.lensCoreAmber)
        case .sky: return PipiFoundations.color(PipiFoundations.lensCoreSky)
        case .coral: return PipiFoundations.color(PipiFoundations.lensCoreCoral)
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
    public static let radiusSM: CGFloat = 8
    public static let radiusMD: CGFloat = 10
    public static let radiusLG: CGFloat = 12
    public static let radiusXL: CGFloat = 16
    public static let radius2XL: CGFloat = 36
    public static let radiusCardDesktop: CGFloat = 10
    public static let radiusComposer: CGFloat = 14
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

    // MARK: Typography Hierarchy & Optical Tracking (Size-Specific, Dynamically Scaled)

    private static let _textScaleLock = OSAllocatedUnfairLock<CGFloat>(initialState: 1.0)

    /// Global UI text scale synced from `PipiAppStore.uiZoomScale` (clamped 0.80...1.40).
    /// Paired with `EnvironmentValues.pipiTextScale` so views re-render cleanly without whole-window `scaleEffect`.
    public static var textScale: CGFloat {
        get { _textScaleLock.withLock { $0 } }
        set {
            let clamped = min(1.40, max(0.80, newValue))
            _textScaleLock.withLock { $0 = clamped }
        }
    }

    public static func scaledPointSize(_ base: CGFloat, scale: CGFloat? = nil) -> CGFloat {
        let s = min(1.40, max(0.80, scale ?? textScale))
        return (base * s * 2.0).rounded() / 2.0
    }

    public static func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        scale: CGFloat? = nil
    ) -> Font {
        Font.system(size: scaledPointSize(size, scale: scale), weight: weight, design: design)
    }

    public static var fontHero: Font { Font.system(size: scaledPointSize(28), weight: .bold, design: .rounded) }
    public static var fontTitle: Font { Font.system(size: scaledPointSize(21), weight: .semibold, design: .default) }
    public static var fontHeadline: Font { Font.system(size: scaledPointSize(16), weight: .semibold, design: .default) }
    public static var fontBody: Font { Font.system(size: scaledPointSize(15), weight: .regular, design: .default) }
    public static var fontSubheadline: Font { Font.system(size: scaledPointSize(14), weight: .medium, design: .default) }
    public static var fontCaption: Font { Font.system(size: scaledPointSize(13), weight: .medium, design: .default) }
    public static var fontMicro: Font { Font.system(size: scaledPointSize(12), weight: .semibold, design: .default) }
    public static var fontMono: Font { Font.system(size: scaledPointSize(13), weight: .medium, design: .monospaced) }
    public static var fontMonoSmall: Font { Font.system(size: scaledPointSize(12), weight: .medium, design: .monospaced) }

    public static let trackingHero: CGFloat = -0.55
    public static let trackingTitle: CGFloat = -0.35
    public static let trackingHeadline: CGFloat = -0.16
    public static let trackingBody: CGFloat = 0.0
    public static let trackingMicro: CGFloat = 0.48
}

// MARK: - Environment Key for Text Scale Invalidation

private struct PipiTextScaleEnvironmentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

public extension EnvironmentValues {
    var pipiTextScale: CGFloat {
        get { self[PipiTextScaleEnvironmentKey.self] }
        set { self[PipiTextScaleEnvironmentKey.self] = newValue }
    }
}

// MARK: - Fluid Motion Curves (Blueprint §7.4 + Reduced-Motion Fallback)

public enum PipiMotion {
    /// Default UI spring: critically damped, zero bounce (response 0.3, damping 1.0).
    public static let smooth = Animation.spring(response: 0.3, dampingFraction: 1.0)

    /// Fast direct-manipulation spring for press, hover, and focus transitions.
    public static let snappy = Animation.spring(response: 0.2, dampingFraction: 1.0)

    /// Spatial panel / drawer / inspector spring (response 0.3, damping 1.0 — no bounce without momentum).
    public static let drawer = Animation.spring(response: 0.3, dampingFraction: 1.0)

    /// Non-bouncy tactile confirmation spring for button/copy feedback.
    public static let tactile = Animation.spring(response: 0.25, dampingFraction: 1.0)

    /// Under-damped spring reserved strictly for momentum-driven gestures (e.g. swipe cards).
    public static let momentum = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// Respects system `accessibilityReduceMotion` by substituting an instant calm cross-fade.
    public static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : animation
    }
}
