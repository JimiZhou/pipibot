import SwiftUI

public struct PipiAvatarView: View {
    public let engine: PipiProceduralAvatarEngine
    public var size: CGFloat = 64
    public var accentOverride: Color?
    public var personaAccent: PipiPersonaAccent?
    public var motif: PipiPersonaMotif = .haloPip
    public var interactive: Bool = true
    public var compactMode: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    public init(
        engine: PipiProceduralAvatarEngine,
        size: CGFloat = 64,
        accentOverride: Color? = nil,
        personaAccent: PipiPersonaAccent? = nil,
        motif: PipiPersonaMotif = .haloPip,
        interactive: Bool = true,
        compactMode: Bool = false
    ) {
        self.engine = engine
        self.size = size
        self.accentOverride = accentOverride
        self.personaAccent = personaAccent
        self.motif = motif
        self.interactive = interactive
        self.compactMode = compactMode
    }

    public var body: some View {
        let accent = accentOverride ?? (personaAccent.map { PipiTokens.color(for: $0) } ?? PipiTokens.color(for: engine.state))
        let lensIrisColor = personaAccent.map { PipiTokens.lensIris(for: $0) } ?? PipiTokens.avatarLensIris
        let lensCoreColor = personaAccent.map { PipiTokens.lensCore(for: $0) } ?? PipiTokens.avatarLensCore
        let isLightMode = colorScheme == .light

        TimelineView(.animation(minimumInterval: compactMode ? 1.0 / 30.0 : 1.0 / 60.0)) { context in
            Canvas { graphicsContext, canvasSize in
                let _ = context.date
                let scaleFactor = min(canvasSize.width, canvasSize.height) / 120.0
                let telemetry = engine.telemetrySnapshot()
                let exprSpec = PipiProceduralAvatarEngine.expressionSpec(for: telemetry.expression)

                let cx = 60.0 + telemetry.tracks.x
                let cy = 60.0 + telemetry.tracks.y
                let baseRadius = 37.0
                let squashTotal = PipiAvatarMath.clamp(
                    telemetry.tracks.squash + telemetry.springAmount * 0.12 + exprSpec.squashBias,
                    min: -0.28,
                    max: 0.30
                )
                let sx = (1.0 + squashTotal) * telemetry.tracks.scale
                let sy = (1.0 / max(0.72, 1.0 + squashTotal)) * telemetry.tracks.scale
                let totalRotDeg = telemetry.tracks.rot + telemetry.springSpin + exprSpec.tiltDeg
                let totalRotRad = totalRotDeg * .pi / 180.0

                var scaledContext = graphicsContext
                scaledContext.scaleBy(x: scaleFactor, y: scaleFactor)

                // 1. Persona-Tinted Ambient Radial Halo
                let haloRadius = 53.0 * telemetry.tracks.scale
                let haloRect = CGRect(
                    x: cx - haloRadius,
                    y: cy - haloRadius,
                    width: haloRadius * 2.0,
                    height: haloRadius * 2.0
                )
                scaledContext.fill(
                    Path(ellipseIn: haloRect),
                    with: .radialGradient(
                        Gradient(colors: [
                            accent.opacity(isLightMode ? (compactMode ? 0.16 : 0.22) : (compactMode ? 0.28 : 0.38)),
                            accent.opacity(0.0)
                        ]),
                        center: CGPoint(x: cx, y: cy),
                        startRadius: 4.0,
                        endRadius: haloRadius
                    )
                )

                // 2. Persona-Specific External Silhouette Hardware (Drawn in bodySpace behind chassis)
                var bodySpace = scaledContext
                bodySpace.translateBy(x: cx, y: cy)
                bodySpace.rotate(by: .radians(totalRotRad))
                bodySpace.scaleBy(x: sx, y: sy)

                drawLivingHardwareAttachments(
                    in: &bodySpace,
                    motif: motif,
                    baseRadius: baseRadius,
                    accent: accent,
                    lensIris: lensIrisColor,
                    isLightMode: isLightMode
                )

                // 3. 192-Ray Morphing Machined Hardware Chassis
                let contourCGPath = PipiAvatarMath.buildSmoothContourPath(
                    radii: engine.currentRadii,
                    center: CGPoint(x: cx, y: cy),
                    baseRadius: baseRadius,
                    scaleX: sx,
                    scaleY: sy,
                    rotationRad: totalRotRad
                )
                let contourPath = Path(contourCGPath)

                if !compactMode {
                    var shadowCtx = scaledContext
                    shadowCtx.translateBy(x: 0, y: 4.5)
                    shadowCtx.fill(
                        contourPath,
                        with: .color(PipiTokens.elevatedShadow.opacity(isLightMode ? 0.55 : 0.72))
                    )
                }

                scaledContext.fill(
                    contourPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            PipiTokens.avatarShellTop,
                            PipiTokens.avatarShellMid,
                            PipiTokens.avatarShellBottom
                        ]),
                        startPoint: CGPoint(x: cx - 14, y: cy - baseRadius),
                        endPoint: CGPoint(x: cx + 14, y: cy + baseRadius)
                    )
                )

                scaledContext.stroke(
                    contourPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            accent.opacity(isLightMode ? 0.65 : 0.82),
                            PipiTokens.avatarChassisRim.opacity(isLightMode ? 0.90 : 0.75),
                            accent.opacity(isLightMode ? 0.50 : 0.72)
                        ]),
                        startPoint: CGPoint(x: cx - 32, y: cy - 36),
                        endPoint: CGPoint(x: cx + 32, y: cy + 36)
                    ),
                    lineWidth: compactMode ? 2.4 : 2.1
                )

                // 4. Forehead Persona Crown Sigil + Recessed Glass Visor Capsule
                if !compactMode {
                    drawForeheadSigil(in: &bodySpace, motif: motif, baseRadius: baseRadius, accent: accent, lensIris: lensIrisColor)
                }

                let visorW: CGFloat = baseRadius * (motif == .caret ? 1.44 : 1.50)
                let visorH: CGFloat = baseRadius * 0.74
                let visorRect = CGRect(
                    x: -visorW * 0.5,
                    y: -visorH * 0.46,
                    width: visorW,
                    height: visorH
                )
                let visorCorner: CGFloat = motif == .caret ? visorH * 0.26 : visorH * 0.48
                let visorPath = Path(roundedRect: visorRect, cornerRadius: visorCorner)

                bodySpace.fill(visorPath, with: .color(PipiTokens.avatarVisorFill))
                bodySpace.stroke(
                    visorPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            accent.opacity(isLightMode ? 0.62 : 0.72),
                            PipiTokens.avatarVisorRim.opacity(0.90)
                        ]),
                        startPoint: CGPoint(x: 0, y: visorRect.minY),
                        endPoint: CGPoint(x: 0, y: visorRect.maxY)
                    ),
                    lineWidth: compactMode ? 1.5 : 1.4
                )

                if !compactMode {
                    var visorSpec = Path()
                    visorSpec.move(to: CGPoint(x: visorRect.minX + visorH * 0.40, y: visorRect.minY + 2.3))
                    visorSpec.addLine(to: CGPoint(x: visorRect.maxX - visorH * 0.40, y: visorRect.minY + 2.3))
                    bodySpace.stroke(visorSpec, with: .color(PipiTokens.avatarGlint.opacity(0.24)), lineWidth: 1.0)

                    let slitW: CGFloat = 13.0
                    let slitH: CGFloat = 2.4
                    let slitRect = CGRect(x: -slitW * 0.5, y: visorRect.maxY + 6.5, width: slitW, height: slitH)
                    bodySpace.fill(
                        Path(roundedRect: slitRect, cornerRadius: slitH * 0.5),
                        with: .color(accent.opacity(0.75))
                    )
                }

                // 5. Dual Rodrigues 3D Sphere Optical Lenses in Persona High-Contrast Optics
                let faceSphereRadius = 22.0 * telemetry.tracks.scale
                let lidTotal = PipiAvatarMath.clamp(
                    max(telemetry.tracks.lids, exprSpec.lidTop),
                    min: 0.0,
                    max: 1.0
                )

                drawOpticalLens(
                    in: &scaledContext,
                    v3: telemetry.leftEye3D,
                    cx: cx,
                    cy: cy + 1.0,
                    sphereRadius: faceSphereRadius,
                    expr: exprSpec,
                    lidTop: lidTotal,
                    scaleBonus: 1.0,
                    irisColor: lensIrisColor,
                    coreColor: lensCoreColor,
                    ringColor: accent
                )
                drawOpticalLens(
                    in: &scaledContext,
                    v3: telemetry.rightEye3D,
                    cx: cx,
                    cy: cy + 1.0,
                    sphereRadius: faceSphereRadius,
                    expr: exprSpec,
                    lidTop: lidTotal,
                    scaleBonus: exprSpec.asymmetry > 0 ? 1.0 + exprSpec.asymmetry : 1.0,
                    irisColor: lensIrisColor,
                    coreColor: lensCoreColor,
                    ringColor: accent
                )
            }
            .onChange(of: context.date) { _, now in
                engine.stepIfNeeded(at: now)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture {
            guard interactive else { return }
            engine.poke()
        }
        .onContinuousHover { phase in
            guard interactive && !compactMode else { return }
            switch phase {
            case .active(let location):
                let nx = ((location.x / max(1, size)) - 0.5) * 2.0
                let ny = ((location.y / max(1, size)) - 0.5) * 2.0
                engine.setGazeTarget(nx: nx, ny: ny)
            case .ended:
                break
            }
        }
        .accessibilityLabel("PiPiBot Living Avatar (\(engine.state.rawValue))")
    }

    private func drawLivingHardwareAttachments(
        in bodySpace: inout GraphicsContext,
        motif: PipiPersonaMotif,
        baseRadius: CGFloat,
        accent: Color,
        lensIris: Color,
        isLightMode: Bool
    ) {
        switch motif {
        case .haloPip:
            break

        case .caret:
            // Coder: Twin machined side ear-lugs
            let lugW: CGFloat = 7.5
            let lugH: CGFloat = 22.0
            let left = CGRect(x: -baseRadius - 3.5, y: -lugH * 0.5, width: lugW, height: lugH)
            let right = CGRect(x: baseRadius - 4.0, y: -lugH * 0.5, width: lugW, height: lugH)
            bodySpace.fill(Path(roundedRect: left, cornerRadius: 3.5), with: .color(accent.opacity(isLightMode ? 0.88 : 0.92)))
            bodySpace.fill(Path(roundedRect: right, cornerRadius: 3.5), with: .color(accent.opacity(isLightMode ? 0.88 : 0.92)))

        case .nib:
            // Writer: Sculpted crown nib crest at top center
            var crest = Path()
            crest.move(to: CGPoint(x: 0, y: -baseRadius - 8.5))
            crest.addLine(to: CGPoint(x: 8.5, y: -baseRadius + 2.0))
            crest.addLine(to: CGPoint(x: -8.5, y: -baseRadius + 2.0))
            crest.closeSubpath()
            bodySpace.fill(crest, with: .color(accent.opacity(isLightMode ? 0.88 : 0.92)))
            bodySpace.fill(Path(ellipseIn: CGRect(x: -2.2, y: -baseRadius - 3.5, width: 4.4, height: 4.4)), with: .color(lensIris))

        case .loop:
            // Operator: Elevated horizontal radar bar on dual micro-standoffs
            let railW: CGFloat = 34.0
            let railH: CGFloat = 5.2
            let railY: CGFloat = -baseRadius - 9.0
            for sign in [-1.0, 1.0] {
                bodySpace.fill(
                    Path(CGRect(x: CGFloat(sign) * 9.5 - 1.6, y: railY + railH - 1, width: 3.2, height: 7.0)),
                    with: .color(PipiTokens.avatarChassisRim)
                )
            }
            bodySpace.fill(
                Path(roundedRect: CGRect(x: -railW * 0.5, y: railY, width: railW, height: railH), cornerRadius: railH * 0.5),
                with: .color(accent.opacity(isLightMode ? 0.90 : 0.95))
            )
        }
    }

    private func drawForeheadSigil(
        in bodySpace: inout GraphicsContext,
        motif: PipiPersonaMotif,
        baseRadius: CGFloat,
        accent: Color,
        lensIris: Color
    ) {
        let y = -baseRadius + 8.5
        switch motif {
        case .haloPip:
            let bar = CGRect(x: -8, y: y - 1.6, width: 16, height: 3.2)
            bodySpace.fill(Path(roundedRect: bar, cornerRadius: 1.6), with: .color(PipiTokens.avatarChassisRim.opacity(0.6)))
            bodySpace.fill(Path(roundedRect: CGRect(x: -4, y: y - 1.4, width: 8, height: 2.8), cornerRadius: 1.4), with: .color(lensIris))

        case .caret:
            var left = Path()
            left.move(to: CGPoint(x: -2.5, y: y - 3.2))
            left.addLine(to: CGPoint(x: -6.5, y: y))
            left.addLine(to: CGPoint(x: -2.5, y: y + 3.2))
            var right = Path()
            right.move(to: CGPoint(x: 2.5, y: y - 3.2))
            right.addLine(to: CGPoint(x: 6.5, y: y))
            right.addLine(to: CGPoint(x: 2.5, y: y + 3.2))
            let style = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            bodySpace.stroke(left, with: .color(accent), style: style)
            bodySpace.stroke(right, with: .color(accent), style: style)

        case .nib:
            var diamond = Path()
            diamond.move(to: CGPoint(x: 0, y: y - 4.0))
            diamond.addLine(to: CGPoint(x: 3.6, y: y))
            diamond.addLine(to: CGPoint(x: 0, y: y + 4.0))
            diamond.addLine(to: CGPoint(x: -3.6, y: y))
            diamond.closeSubpath()
            bodySpace.fill(diamond, with: .color(accent))

        case .loop:
            var arc = Path()
            arc.addArc(center: CGPoint(x: 0, y: y), radius: 3.6, startAngle: .degrees(35), endAngle: .degrees(305), clockwise: false)
            bodySpace.stroke(arc, with: .color(accent), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            bodySpace.fill(Path(ellipseIn: CGRect(x: 2.4, y: y - 1.3, width: 2.6, height: 2.6)), with: .color(lensIris))
        }
    }

    private func drawOpticalLens(
        in context: inout GraphicsContext,
        v3: SIMD3<Double>,
        cx: Double,
        cy: Double,
        sphereRadius: Double,
        expr: AvatarExpressionSpec,
        lidTop: Double,
        scaleBonus: Double,
        irisColor: Color,
        coreColor: Color,
        ringColor: Color
    ) {
        let ex = cx + v3.x * sphereRadius
        let ey = cy + v3.y * sphereRadius
        let foreshortenX = max(0.40, v3.z)

        let baseW = expr.eyeW * foreshortenX * scaleBonus
        let rawH = expr.eyeH * scaleBonus
        let openFactor = PipiAvatarMath.clamp(
            1.0 - lidTop * 0.92 - expr.lidBottom * 0.25,
            min: 0.08,
            max: 1.0
        )
        let h = max(1.3, rawH * openFactor)

        let auraRadius = max(baseW, h) * (1.72 * expr.glowBoost)
        let auraRect = CGRect(x: ex - auraRadius, y: ey - auraRadius, width: auraRadius * 2, height: auraRadius * 2)
        context.fill(
            Path(ellipseIn: auraRect),
            with: .radialGradient(
                Gradient(colors: [irisColor.opacity(0.46), irisColor.opacity(0.0)]),
                center: CGPoint(x: ex, y: ey),
                startRadius: 0.6,
                endRadius: auraRadius
            )
        )

        if (expr.happyArc > 0.5 && lidTop < 0.35) || (expr.id == .happy && lidTop < 0.35) {
            let arcW = baseW * 1.15
            let arch = max(2.6, rawH * 0.65)
            var arc = Path()
            arc.move(to: CGPoint(x: ex - arcW, y: ey + 1.4))
            arc.addQuadCurve(to: CGPoint(x: ex + arcW, y: ey + 1.4), control: CGPoint(x: ex, y: ey - arch * 1.6))
            arc.addQuadCurve(to: CGPoint(x: ex - arcW, y: ey + 1.4), control: CGPoint(x: ex, y: ey - arch * 0.55))
            arc.closeSubpath()
            context.fill(arc, with: .color(coreColor))
            return
        }

        if h <= 1.8 {
            let lineW = baseW * 1.12
            let bend = expr.id == .sleepy ? 2.2 : 1.0
            var closed = Path()
            closed.move(to: CGPoint(x: ex - lineW, y: ey))
            closed.addQuadCurve(to: CGPoint(x: ex + lineW, y: ey), control: CGPoint(x: ex, y: ey + bend))
            closed.addQuadCurve(to: CGPoint(x: ex - lineW, y: ey), control: CGPoint(x: ex, y: ey + bend + 1.3))
            closed.closeSubpath()
            context.fill(closed, with: .color(irisColor))
            return
        }

        let eyeW: Double = motif == .nib ? baseW * 0.80 : baseW
        let eyeH: Double = motif == .nib ? h * 1.12 : h
        let eyeRect = CGRect(x: ex - eyeW, y: ey - eyeH, width: eyeW * 2, height: eyeH * 2)
        let cornerRatio: Double = motif == .caret ? 0.30 : 0.92
        let cornerRadius = min(eyeW, eyeH) * cornerRatio
        let lensPath = Path(roundedRect: eyeRect, cornerRadius: cornerRadius)

        if motif == .loop && openFactor > 0.55 {
            context.stroke(lensPath, with: .color(irisColor), lineWidth: max(1.9, min(eyeW, eyeH) * 0.44))
            let dotR = max(1.6, min(eyeW, eyeH) * 0.36)
            context.fill(
                Path(ellipseIn: CGRect(x: ex - dotR, y: ey - dotR, width: dotR * 2, height: dotR * 2)),
                with: .color(coreColor)
            )
        } else {
            context.fill(lensPath, with: .color(irisColor))
            let coreRect = eyeRect.insetBy(dx: eyeW * 0.34, dy: eyeH * 0.34)
            context.fill(
                Path(roundedRect: coreRect, cornerRadius: cornerRadius * 0.62),
                with: .color(coreColor)
            )
            context.stroke(lensPath, with: .color(ringColor.opacity(0.80)), lineWidth: 1.15)
        }

        if openFactor > 0.45 && !compactMode && motif != .loop {
            let glintCenter = CGPoint(x: ex - eyeW * 0.34, y: ey - eyeH * 0.36)
            let glintRect = CGRect(x: glintCenter.x - 1.45, y: glintCenter.y - 1.45, width: 2.9, height: 2.9)
            context.fill(Path(ellipseIn: glintRect), with: .color(PipiTokens.avatarGlint))
        }
    }
}
