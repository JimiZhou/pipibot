import SwiftUI
import CoreGraphics

// MARK: - Codex-Designed Original PipiBot Hardware-Robot Visual Grammar (4 Distinct Silhouettes + High-Contrast Optics)

public enum PipiPersonaMotif: String, CaseIterable, Sendable {
    /// General Assistant ("Halo Pip"): rounded portrait squircle + concave crown notch + iris circular lenses
    case haloPip
    /// Engineering ("Caret"): chamfered terminal chassis + twin side ear-lugs + emerald rounded-square lenses
    case caret
    /// Writing & Research ("Nib"): sculpted pebble dome + top nib crest + warm amber vertical-ellipse lenses
    case nib
    /// Operations & Routines ("Loop"): beveled shield chassis + top machined radar bar + sky concentric ring lenses
    case loop

    public static func resolve(for persona: PipiBotPersona) -> PipiPersonaMotif {
        switch persona.id {
        case "bot_pipi_general": return .haloPip
        case "bot_pipi_coder": return .caret
        case "bot_pipi_writer": return .nib
        case "bot_pipi_operator": return .loop
        default:
            switch persona.avatarShape {
            case .terminal, .bolt: return .caret
            case .cloud, .dream: return .nib
            case .shield, .squircle: return .loop
            case .orb, .spark: return .haloPip
            }
        }
    }
}

public enum PipiRobotGeometry {
    /// Default PiPiBot brand chassis ("PiPi Halo"): portrait squircle with subtle architectural concave crown notch.
    public static func chassisPath(in bounds: CGRect) -> Path {
        chassisPath(in: bounds, motif: .haloPip)
    }

    /// Motif-specific hardware-robot silhouettes so each Bot is immediately recognizable even at 20–24pt.
    public static func chassisPath(in bounds: CGRect, motif: PipiPersonaMotif) -> Path {
        switch motif {
        case .haloPip:
            return buildHaloSquircle(in: bounds)
        case .caret:
            return buildCoderTerminalChassis(in: bounds)
        case .nib:
            return buildWriterNibDome(in: bounds)
        case .loop:
            return buildOperatorShieldChassis(in: bounds)
        }
    }

    private static func buildHaloSquircle(in bounds: CGRect) -> Path {
        let w = bounds.width
        let h = bounds.height
        let x0 = bounds.minX
        let y0 = bounds.minY
        let x1 = bounds.maxX
        let y1 = bounds.maxY
        let cx = bounds.midX

        let r = min(w * 0.28, h * 0.26)
        let sq: CGFloat = r * (1.0 - 0.55228475 * 0.92)
        let notchHalfW = w * 0.175
        let notchDepth = h * 0.042

        var p = Path()
        p.move(to: CGPoint(x: x0 + r, y: y0))
        p.addLine(to: CGPoint(x: cx - notchHalfW, y: y0))
        p.addCurve(
            to: CGPoint(x: cx, y: y0 + notchDepth),
            control1: CGPoint(x: cx - notchHalfW * 0.55, y: y0),
            control2: CGPoint(x: cx - notchHalfW * 0.38, y: y0 + notchDepth)
        )
        p.addCurve(
            to: CGPoint(x: cx + notchHalfW, y: y0),
            control1: CGPoint(x: cx + notchHalfW * 0.38, y: y0 + notchDepth),
            control2: CGPoint(x: cx + notchHalfW * 0.55, y: y0)
        )
        p.addLine(to: CGPoint(x: x1 - r, y: y0))
        p.addCurve(to: CGPoint(x: x1, y: y0 + r), control1: CGPoint(x: x1 - sq, y: y0), control2: CGPoint(x: x1, y: y0 + sq))
        p.addLine(to: CGPoint(x: x1, y: y1 - r))
        p.addCurve(to: CGPoint(x: x1 - r, y: y1), control1: CGPoint(x: x1, y: y1 - sq), control2: CGPoint(x: x1 - sq, y: y1))
        p.addLine(to: CGPoint(x: x0 + r, y: y1))
        p.addCurve(to: CGPoint(x: x0, y: y1 - r), control1: CGPoint(x: x0 + sq, y: y1), control2: CGPoint(x: x0, y: y1 - sq))
        p.addLine(to: CGPoint(x: x0, y: y0 + r))
        p.addCurve(to: CGPoint(x: x0 + r, y: y0), control1: CGPoint(x: x0, y: y0 + sq), control2: CGPoint(x: x0 + sq, y: y0))
        p.closeSubpath()
        return p
    }

    private static func buildCoderTerminalChassis(in bounds: CGRect) -> Path {
        // Precision chamfered compute module (wider, crisper corner bevels; side ear-lugs drawn alongside)
        let inset = bounds.insetBy(dx: bounds.width * 0.06, dy: bounds.height * 0.04)
        let r = min(inset.width, inset.height) * 0.16
        return Path(roundedRect: inset, cornerRadius: r)
    }

    private static func buildWriterNibDome(in bounds: CGRect) -> Path {
        // Sculpted warm-pebble dome with subtle top editorial nib crest
        let w = bounds.width
        let h = bounds.height
        let x0 = bounds.minX + w * 0.03
        let x1 = bounds.maxX - w * 0.03
        let yTop = bounds.minY + h * 0.08
        let yPeak = bounds.minY
        let y1 = bounds.maxY
        let cx = bounds.midX
        let r = (x1 - x0) * 0.34

        var p = Path()
        p.move(to: CGPoint(x: cx, y: yPeak))
        p.addCurve(
            to: CGPoint(x: x1, y: yTop + r * 0.85),
            control1: CGPoint(x: cx + (x1 - cx) * 0.52, y: yPeak + h * 0.02),
            control2: CGPoint(x: x1, y: yTop + h * 0.04)
        )
        p.addLine(to: CGPoint(x: x1, y: y1 - r))
        p.addQuadCurve(to: CGPoint(x: x1 - r, y: y1), control: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x0 + r, y: y1))
        p.addQuadCurve(to: CGPoint(x: x0, y: y1 - r), control: CGPoint(x: x0, y: y1))
        p.addLine(to: CGPoint(x: x0, y: yTop + r * 0.85))
        p.addCurve(
            to: CGPoint(x: cx, y: yPeak),
            control1: CGPoint(x: x0, y: yTop + h * 0.04),
            control2: CGPoint(x: cx - (cx - x0) * 0.52, y: yPeak + h * 0.02)
        )
        p.closeSubpath()
        return p
    }

    private static func buildOperatorShieldChassis(in bounds: CGRect) -> Path {
        // Architectural beveled shield chassis (leaves room at top for horizontal radar rail)
        let w = bounds.width
        let h = bounds.height
        let x0 = bounds.minX + w * 0.02
        let x1 = bounds.maxX - w * 0.02
        let y0 = bounds.minY + h * 0.13
        let y1 = bounds.maxY
        let cx = bounds.midX
        let cut = w * 0.17

        var p = Path()
        p.move(to: CGPoint(x: x0 + cut, y: y0))
        p.addLine(to: CGPoint(x: x1 - cut, y: y0))
        p.addLine(to: CGPoint(x: x1, y: y0 + cut))
        p.addLine(to: CGPoint(x: x1, y: y1 - cut * 1.45))
        p.addQuadCurve(to: CGPoint(x: cx, y: y1), control: CGPoint(x: x1 - w * 0.05, y: y1 - h * 0.02))
        p.addQuadCurve(to: CGPoint(x: x0, y: y1 - cut * 1.45), control: CGPoint(x: x0 + w * 0.05, y: y1 - h * 0.02))
        p.addLine(to: CGPoint(x: x0, y: y0 + cut))
        p.closeSubpath()
        return p
    }
}

// MARK: - Original PipiBot Brand Logo Mark (Dark Obsidian Titanium / Light Porcelain Ceramic)

public struct PipiBotLogoMark: View {
    public var size: CGFloat = 28
    public var accentOverride: Color? = nil

    @Environment(\.colorScheme) private var colorScheme

    public init(size: CGFloat = 28, accentOverride: Color? = nil) {
        self.size = size
        self.accentOverride = accentOverride
    }

    public var body: some View {
        PipiRobotHardwareCanvas(
            size: size,
            motif: .haloPip,
            personaAccent: nil,
            accent: accentOverride ?? PipiTokens.avatarLensIris,
            useBrandIris: accentOverride == nil,
            isLightMode: colorScheme == .light
        )
        .accessibilityLabel("PiPiBot")
    }
}

// MARK: - Unified Adaptive Persona Robot Glyph (Sidebar, Header, Message Avatar, Cards)

public struct PipiBotPersonaGlyph: View {
    public let persona: PipiBotPersona
    public var size: CGFloat = 28
    public var isSelected: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    public init(persona: PipiBotPersona, size: CGFloat = 28, isSelected: Bool = false) {
        self.persona = persona
        self.size = size
        self.isSelected = isSelected
    }

    public var body: some View {
        let accent = PipiTokens.color(for: persona.accent)
        let motif = PipiPersonaMotif.resolve(for: persona)

        PipiRobotHardwareCanvas(
            size: size,
            motif: motif,
            personaAccent: persona.accent,
            accent: accent,
            useBrandIris: false,
            isLightMode: colorScheme == .light,
            emphasized: isSelected
        )
        .accessibilityHidden(true)
    }
}

// MARK: - Shared Precision Vector Canvas Renderer

private struct PipiRobotHardwareCanvas: View {
    let size: CGFloat
    let motif: PipiPersonaMotif
    let personaAccent: PipiPersonaAccent?
    let accent: Color
    let useBrandIris: Bool
    let isLightMode: Bool
    var emphasized: Bool = false

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            let cx = canvasSize.width * 0.5
            let cy = canvasSize.height * 0.5

            let chassisW = s * 0.86
            let chassisH = s * 0.90
            let chassisRect = CGRect(
                x: cx - chassisW * 0.5,
                y: cy - chassisH * 0.5,
                width: chassisW,
                height: chassisH
            )

            let lensIrisColor: Color = {
                if useBrandIris { return PipiTokens.avatarLensIris }
                if let pa = personaAccent { return PipiTokens.lensIris(for: pa) }
                return accent
            }()
            let lensCoreColor: Color = {
                if useBrandIris { return PipiTokens.avatarLensCore }
                if let pa = personaAccent { return PipiTokens.lensCore(for: pa) }
                return PipiTokens.avatarLensCore
            }()

            // 0. Distinct Silhouette Hardware Accessories (Drawn Behind/Integrated with Chassis — Readable at 20pt+!)
            drawSilhouetteAccessories(in: &ctx, motif: motif, rect: chassisRect, accent: accent, lensIris: lensIrisColor, scale: s)

            let chassisPath = PipiRobotGeometry.chassisPath(in: chassisRect, motif: motif)

            // 1. Machined Chassis Fill (Adaptive Dark Obsidian Titanium vs Light Porcelain Ceramic)
            ctx.fill(
                chassisPath,
                with: .linearGradient(
                    Gradient(colors: [
                        PipiTokens.avatarShellTop,
                        PipiTokens.avatarShellMid,
                        PipiTokens.avatarShellBottom
                    ]),
                    startPoint: CGPoint(x: cx, y: chassisRect.minY),
                    endPoint: CGPoint(x: cx, y: chassisRect.maxY)
                )
            )

            // Subtle persona-tinted machined outer rim (stronger differentiation at all sizes)
            let rimWidth = max(0.85, s * 0.04)
            ctx.stroke(
                chassisPath,
                with: .linearGradient(
                    Gradient(colors: [
                        useBrandIris ? PipiTokens.avatarRimHighlight : accent.opacity(emphasized ? 0.90 : (isLightMode ? 0.62 : 0.68)),
                        PipiTokens.avatarChassisRim.opacity(isLightMode ? 0.88 : 0.78)
                    ]),
                    startPoint: CGPoint(x: cx, y: chassisRect.minY),
                    endPoint: CGPoint(x: cx, y: chassisRect.maxY)
                ),
                lineWidth: rimWidth
            )

            // 2. Crown Sigil / Status Indicator (Readable starting at 22pt+ so sidebar & header show persona character!)
            if s >= 22 {
                let sigilY: CGFloat = {
                    switch motif {
                    case .haloPip: return chassisRect.minY + chassisH * 0.195
                    case .caret: return chassisRect.minY + chassisH * 0.195
                    case .nib: return chassisRect.minY + chassisH * 0.22
                    case .loop: return chassisRect.minY + chassisH * 0.255
                    }
                }()
                drawCrownSigil(
                    in: &ctx,
                    motif: motif,
                    center: CGPoint(x: cx, y: sigilY),
                    unit: s * 0.088,
                    color: useBrandIris ? PipiTokens.avatarLensRing : accent
                )
            }

            // 3. Recessed Glass Visor (Shape subtly adapts per Bot hardware grammar)
            let visorW = chassisW * (motif == .caret ? 0.76 : 0.80)
            let visorH = chassisH * (motif == .caret ? 0.36 : 0.37)
            let visorYOffset = motif == .loop ? 0.04 : (motif == .nib ? 0.03 : 0.0)
            let visorRect = CGRect(
                x: cx - visorW * 0.5,
                y: cy - visorH * 0.45 + chassisH * visorYOffset,
                width: visorW,
                height: visorH
            )
            let visorRadius: CGFloat = motif == .caret ? visorH * 0.26 : visorH * 0.5
            let visorPath = Path(roundedRect: visorRect, cornerRadius: visorRadius)

            ctx.fill(visorPath, with: .color(PipiTokens.avatarVisorFill))
            ctx.stroke(
                visorPath,
                with: .color(useBrandIris ? PipiTokens.avatarVisorRim : accent.opacity(isLightMode ? 0.58 : 0.65)),
                lineWidth: max(0.7, s * 0.028)
            )

            // 4. Twin Expressive Optical Lenses (Per-Persona High-Contrast Color + Distinct Geometry)
            let lensOffset = chassisW * 0.195
            let lensD = chassisW * 0.255
            let lensY = visorRect.midY

            for sign in [-1.0, 1.0] {
                let lx = cx + CGFloat(sign) * lensOffset
                drawLens(
                    in: &ctx,
                    center: CGPoint(x: lx, y: lensY),
                    diameter: lensD,
                    motif: motif,
                    irisColor: lensIrisColor,
                    coreColor: lensCoreColor,
                    ringColor: useBrandIris ? PipiTokens.avatarLensRing : accent,
                    canvasScale: s
                )
            }

            // 5. Subtle Machined Chin Micro-Vent (shown at 30pt+)
            if s >= 30 {
                let slitW = chassisW * 0.14
                let slitH = max(1.1, chassisH * 0.02)
                let slitRect = CGRect(
                    x: cx - slitW * 0.5,
                    y: visorRect.maxY + (chassisRect.maxY - visorRect.maxY) * 0.40,
                    width: slitW,
                    height: slitH
                )
                ctx.fill(
                    Path(roundedRect: slitRect, cornerRadius: slitH * 0.5),
                    with: .color((useBrandIris ? PipiTokens.avatarChassisRim : accent).opacity(0.55))
                )
            }
        }
        .frame(width: size, height: size)
        .shadow(
            color: PipiTokens.subtleShadow.opacity(isLightMode ? 0.85 : 0.70),
            radius: max(1.5, size * 0.08),
            y: max(0.8, size * 0.035)
        )
    }

    private func drawSilhouetteAccessories(
        in ctx: inout GraphicsContext,
        motif: PipiPersonaMotif,
        rect: CGRect,
        accent: Color,
        lensIris: Color,
        scale s: CGFloat
    ) {
        switch motif {
        case .haloPip:
            break

        case .caret:
            // Coder: Twin machined side ear-lugs (Teenage Engineering compute-module silhouette!)
            let lugW = max(1.8, rect.width * 0.11)
            let lugH = rect.height * 0.28
            let lugY = rect.midY - lugH * 0.48
            let leftLug = CGRect(x: rect.minX, y: lugY, width: lugW, height: lugH)
            let rightLug = CGRect(x: rect.maxX - lugW, y: lugY, width: lugW, height: lugH)
            ctx.fill(Path(roundedRect: leftLug, cornerRadius: lugW * 0.45), with: .color(accent.opacity(isLightMode ? 0.88 : 0.92)))
            ctx.fill(Path(roundedRect: rightLug, cornerRadius: lugW * 0.45), with: .color(accent.opacity(isLightMode ? 0.88 : 0.92)))

        case .nib:
            // Writer: Subtle glowing editorial crown gem dot nestled right at the nib apex
            let gemR = max(1.1, s * 0.055)
            let gemRect = CGRect(x: rect.midX - gemR, y: rect.minY + rect.height * 0.015, width: gemR * 2, height: gemR * 2)
            ctx.fill(Path(ellipseIn: gemRect), with: .color(lensIris.opacity(0.92)))

        case .loop:
            // Operator: Precision top horizontal radar rail with dual standoffs
            let railW = rect.width * 0.50
            let railH = max(1.6, rect.height * 0.072)
            let railRect = CGRect(x: rect.midX - railW * 0.5, y: rect.minY + rect.height * 0.01, width: railW, height: railH)
            // Dual tiny vertical posts connecting rail to shield body
            let postW = max(1.0, rect.width * 0.065)
            let postH = rect.height * 0.10
            for sign in [-1.0, 1.0] {
                let px = rect.midX + CGFloat(sign) * (railW * 0.30) - postW * 0.5
                ctx.fill(
                    Path(CGRect(x: px, y: railRect.maxY - 0.5, width: postW, height: postH)),
                    with: .color(PipiTokens.avatarChassisRim)
                )
            }
            ctx.fill(Path(roundedRect: railRect, cornerRadius: railH * 0.5), with: .color(accent.opacity(isLightMode ? 0.90 : 0.95)))
        }
    }

    private func drawLens(
        in ctx: inout GraphicsContext,
        center: CGPoint,
        diameter: CGFloat,
        motif: PipiPersonaMotif,
        irisColor: Color,
        coreColor: Color,
        ringColor: Color,
        canvasScale: CGFloat
    ) {
        let r = diameter * 0.5
        let lensRect = CGRect(x: center.x - r, y: center.y - r, width: diameter, height: diameter)

        // Subtle luminous lens aura inside dark visor
        let auraR = r * 1.45
        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - auraR, y: center.y - auraR, width: auraR * 2, height: auraR * 2)),
            with: .radialGradient(
                Gradient(colors: [irisColor.opacity(0.38), irisColor.opacity(0.0)]),
                center: center,
                startRadius: r * 0.2,
                endRadius: auraR
            )
        )

        if canvasScale < 18 {
            ctx.fill(Path(ellipseIn: lensRect), with: .color(irisColor))
            return
        }

        switch motif {
        case .haloPip:
            ctx.fill(Path(ellipseIn: lensRect), with: .color(irisColor))
            let coreR = r * 0.52
            ctx.fill(
                Path(ellipseIn: CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2)),
                with: .color(coreColor)
            )

        case .caret:
            // Rounded-square terminal phosphor lens
            let sqSize = diameter * 0.94
            let sqRect = CGRect(x: center.x - sqSize * 0.5, y: center.y - sqSize * 0.5, width: sqSize, height: sqSize)
            let sqPath = Path(roundedRect: sqRect, cornerRadius: sqSize * 0.24)
            ctx.fill(sqPath, with: .color(irisColor))
            let innerSize = sqSize * 0.50
            let innerRect = CGRect(x: center.x - innerSize * 0.5, y: center.y - innerSize * 0.5, width: innerSize, height: innerSize)
            ctx.fill(Path(roundedRect: innerRect, cornerRadius: innerSize * 0.22), with: .color(coreColor))

        case .nib:
            // Tall vertical-ellipse editorial lens
            let w = diameter * 0.76
            let h = diameter * 1.14
            let ellRect = CGRect(x: center.x - w * 0.5, y: center.y - h * 0.5, width: w, height: h)
            ctx.fill(Path(ellipseIn: ellRect), with: .color(irisColor))
            let cw = w * 0.50
            let ch = h * 0.52
            ctx.fill(
                Path(ellipseIn: CGRect(x: center.x - cw * 0.5, y: center.y - ch * 0.5, width: cw, height: ch)),
                with: .color(coreColor)
            )

        case .loop:
            // Concentric orbital ring lens
            let ringW = max(1.15, diameter * 0.24)
            let ringRect = lensRect.insetBy(dx: ringW * 0.5, dy: ringW * 0.5)
            ctx.stroke(Path(ellipseIn: ringRect), with: .color(irisColor), lineWidth: ringW)
            let centerDot = diameter * 0.28
            ctx.fill(
                Path(ellipseIn: CGRect(x: center.x - centerDot * 0.5, y: center.y - centerDot * 0.5, width: centerDot, height: centerDot)),
                with: .color(coreColor)
            )
        }

        // Crisp upper-left optical specular glint (at 24pt+)
        if canvasScale >= 24 && motif != .loop {
            let glintD = max(1.1, diameter * 0.19)
            let gx = center.x - r * 0.34 - glintD * 0.5
            let gy = center.y - r * 0.34 - glintD * 0.5
            ctx.fill(Path(ellipseIn: CGRect(x: gx, y: gy, width: glintD, height: glintD)), with: .color(PipiTokens.avatarGlint))
        }
    }

    private func drawCrownSigil(in ctx: inout GraphicsContext, motif: PipiPersonaMotif, center: CGPoint, unit u: CGFloat, color: Color) {
        let sigilColor = color.opacity(isLightMode ? 0.92 : 0.95)
        let strokeW = max(0.95, u * 0.26)

        switch motif {
        case .haloPip:
            let barW = u * 1.45
            let barH = max(1.4, u * 0.32)
            let barRect = CGRect(x: center.x - barW * 0.5, y: center.y - barH * 0.5, width: barW, height: barH)
            ctx.fill(Path(roundedRect: barRect, cornerRadius: barH * 0.5), with: .color(sigilColor))

        case .caret:
            var left = Path()
            left.move(to: CGPoint(x: center.x - u * 0.20, y: center.y - u * 0.40))
            left.addLine(to: CGPoint(x: center.x - u * 0.62, y: center.y))
            left.addLine(to: CGPoint(x: center.x - u * 0.20, y: center.y + u * 0.40))
            var right = Path()
            right.move(to: CGPoint(x: center.x + u * 0.20, y: center.y - u * 0.40))
            right.addLine(to: CGPoint(x: center.x + u * 0.62, y: center.y))
            right.addLine(to: CGPoint(x: center.x + u * 0.20, y: center.y + u * 0.40))
            let style = StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
            ctx.stroke(left, with: .color(sigilColor), style: style)
            ctx.stroke(right, with: .color(sigilColor), style: style)

        case .nib:
            var diamond = Path()
            diamond.move(to: CGPoint(x: center.x, y: center.y - u * 0.48))
            diamond.addLine(to: CGPoint(x: center.x + u * 0.40, y: center.y))
            diamond.addLine(to: CGPoint(x: center.x, y: center.y + u * 0.48))
            diamond.addLine(to: CGPoint(x: center.x - u * 0.40, y: center.y))
            diamond.closeSubpath()
            ctx.fill(diamond, with: .color(sigilColor))

        case .loop:
            var arc = Path()
            arc.addArc(center: center, radius: u * 0.42, startAngle: .degrees(35), endAngle: .degrees(305), clockwise: false)
            ctx.stroke(arc, with: .color(sigilColor), style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
            let dotR = max(0.85, u * 0.18)
            ctx.fill(
                Path(ellipseIn: CGRect(x: center.x + u * 0.42 - dotR, y: center.y - dotR, width: dotR * 2, height: dotR * 2)),
                with: .color(sigilColor)
            )
        }
    }
}
