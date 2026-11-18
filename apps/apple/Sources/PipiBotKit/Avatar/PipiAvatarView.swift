import SwiftUI

public struct PipiAvatarView: View {
    public let engine: PipiProceduralAvatarEngine
    public var size: CGFloat = 64
    public var accentOverride: Color?
    public var interactive: Bool = true
    public var compactMode: Bool = false

    @State private var lastTick: Date?

    public init(
        engine: PipiProceduralAvatarEngine,
        size: CGFloat = 64,
        accentOverride: Color? = nil,
        interactive: Bool = true,
        compactMode: Bool = false
    ) {
        self.engine = engine
        self.size = size
        self.accentOverride = accentOverride
        self.interactive = interactive
        self.compactMode = compactMode
    }

    public var body: some View {
        let accent = accentOverride ?? PipiTokens.color(for: engine.state)

        TimelineView(.animation(minimumInterval: compactMode ? 1.0 / 30.0 : 1.0 / 120.0)) { context in
            Canvas { graphicsContext, canvasSize in
                let scaleFactor = min(canvasSize.width, canvasSize.height) / 120.0
                let telemetry = engine.telemetrySnapshot()
                let exprSpec = PipiProceduralAvatarEngine.expressionSpec(for: telemetry.expression)

                let cx = 60.0 + telemetry.tracks.x
                let cy = 60.0 + telemetry.tracks.y
                let baseRadius = 36.0
                let squashTotal = PipiAvatarMath.clamp(
                    telemetry.tracks.squash + telemetry.springAmount * 0.14 + exprSpec.squashBias,
                    min: -0.32,
                    max: 0.35
                )
                let sx = (1.0 + squashTotal) * telemetry.tracks.scale
                let sy = (1.0 / max(0.68, 1.0 + squashTotal)) * telemetry.tracks.scale
                let totalRotDeg = telemetry.tracks.rot + telemetry.springSpin + exprSpec.tiltDeg
                let totalRotRad = totalRotDeg * .pi / 180.0

                var scaledContext = graphicsContext
                scaledContext.scaleBy(x: scaleFactor, y: scaleFactor)

                // 1. Ambient Radial Halo Glow
                let haloRadius = 50.0 * telemetry.tracks.scale
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
                            accent.opacity(compactMode ? 0.35 : 0.42),
                            accent.opacity(0.0)
                        ]),
                        center: CGPoint(x: cx, y: cy),
                        startRadius: 2.0,
                        endRadius: haloRadius
                    )
                )

                // 2. 192-Ray Interpolated Contour Path
                let contourCGPath = PipiAvatarMath.buildSmoothContourPath(
                    radii: engine.currentRadii,
                    center: CGPoint(x: cx, y: cy),
                    baseRadius: baseRadius,
                    scaleX: sx,
                    scaleY: sy,
                    rotationRad: totalRotRad
                )
                let contourPath = Path(contourCGPath)

                scaledContext.fill(
                    contourPath,
                    with: .radialGradient(
                        Gradient(colors: [
                            PipiTokens.avatarShellTop,
                            PipiTokens.avatarShellMid,
                            PipiTokens.avatarShellBottom
                        ]),
                        center: CGPoint(x: cx - 10, y: cy - 15),
                        startRadius: 4,
                        endRadius: baseRadius * 1.45
                    )
                )

                scaledContext.stroke(
                    contourPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            accent.opacity(0.92),
                            PipiTokens.avatarRimHighlight,
                            accent.opacity(0.65)
                        ]),
                        startPoint: CGPoint(x: cx - 32, y: cy - 32),
                        endPoint: CGPoint(x: cx + 32, y: cy + 32)
                    ),
                    lineWidth: compactMode ? 2.8 : 2.1
                )

                // 3. Subtle Crown Specular Reflection
                if !compactMode {
                    var crownContext = scaledContext
                    crownContext.translateBy(x: cx - 9, y: cy - 21)
                    crownContext.rotate(by: .degrees(-16))
                    let crownRect = CGRect(x: -16, y: -7, width: 32, height: 14)
                    crownContext.fill(
                        Path(ellipseIn: crownRect),
                        with: .color(PipiTokens.avatarRimHighlight.opacity(0.35))
                    )
                }

                // 4. Dual Rodrigues 3D Sphere Eyes + Orthographic Projection + Glow
                let faceSphereRadius = 25.0 * telemetry.tracks.scale
                let lidTotal = PipiAvatarMath.clamp(
                    max(telemetry.tracks.lids, exprSpec.lidTop),
                    min: 0.0,
                    max: 1.0
                )

                drawEye(
                    in: &scaledContext,
                    v3: telemetry.leftEye3D,
                    cx: cx,
                    cy: cy,
                    sphereRadius: faceSphereRadius,
                    expr: exprSpec,
                    lidTop: lidTotal,
                    scaleBonus: 1.0,
                    accent: accent
                )
                drawEye(
                    in: &scaledContext,
                    v3: telemetry.rightEye3D,
                    cx: cx,
                    cy: cy,
                    sphereRadius: faceSphereRadius,
                    expr: exprSpec,
                    lidTop: lidTotal,
                    scaleBonus: exprSpec.asymmetry > 0 ? 1.0 + exprSpec.asymmetry : 1.0,
                    accent: accent
                )
            }
            .onChange(of: context.date) { _, now in
                let rawDt = lastTick.map { now.timeIntervalSince($0) } ?? PipiAvatarMath.fixedDt
                let dt = min(0.05, max(0.0, rawDt))
                lastTick = now
                engine.step(deltaSec: dt)
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
        .accessibilityLabel("PipiBot Living Avatar (\(engine.state.rawValue))")
    }

    private func drawEye(
        in context: inout GraphicsContext,
        v3: SIMD3<Double>,
        cx: Double,
        cy: Double,
        sphereRadius: Double,
        expr: AvatarExpressionSpec,
        lidTop: Double,
        scaleBonus: Double,
        accent: Color
    ) {
        let ex = cx + v3.x * sphereRadius
        let ey = cy + v3.y * sphereRadius
        let foreshortenX = max(0.36, v3.z)

        let w = expr.eyeW * foreshortenX * scaleBonus
        let rawH = expr.eyeH * scaleBonus
        let openFactor = PipiAvatarMath.clamp(
            1.0 - lidTop * 0.92 - expr.lidBottom * 0.25,
            min: 0.08,
            max: 1.0
        )
        let h = max(1.2, rawH * openFactor)

        // Subtle luminous outer eye aura
        let auraRadius = max(w, h) * (1.7 * expr.glowBoost)
        let auraRect = CGRect(x: ex - auraRadius, y: ey - auraRadius, width: auraRadius * 2, height: auraRadius * 2)
        context.fill(
            Path(ellipseIn: auraRect),
            with: .radialGradient(
                Gradient(colors: [accent.opacity(0.45), accent.opacity(0.0)]),
                center: CGPoint(x: ex, y: ey),
                startRadius: 0.5,
                endRadius: auraRadius
            )
        )

        // Happy / proud upward crescent arc
        if (expr.happyArc > 0.5 && lidTop < 0.35) || (expr.id == .happy && lidTop < 0.35) {
            let arcW = w * 1.15
            let arch = max(2.6, rawH * 0.65)
            var arc = Path()
            arc.move(to: CGPoint(x: ex - arcW, y: ey + 1.5))
            arc.addQuadCurve(
                to: CGPoint(x: ex + arcW, y: ey + 1.5),
                control: CGPoint(x: ex, y: ey - arch * 1.65)
            )
            arc.addQuadCurve(
                to: CGPoint(x: ex - arcW, y: ey + 1.5),
                control: CGPoint(x: ex, y: ey - arch * 0.6)
            )
            arc.closeSubpath()
            context.fill(arc, with: .color(accent))
            return
        }

        // Closed blink or sleepy arc
        if h <= 1.75 {
            let lineW = w * 1.12
            let bend = expr.id == .sleepy ? 2.2 : 1.0
            var closed = Path()
            closed.move(to: CGPoint(x: ex - lineW, y: ey))
            closed.addQuadCurve(
                to: CGPoint(x: ex + lineW, y: ey),
                control: CGPoint(x: ex, y: ey + bend)
            )
            closed.addQuadCurve(
                to: CGPoint(x: ex - lineW, y: ey),
                control: CGPoint(x: ex, y: ey + bend + 1.4)
            )
            closed.closeSubpath()
            context.fill(closed, with: .color(accent))
            return
        }

        // Standard capsule / squircle eye
        let eyeRect = CGRect(x: ex - w, y: ey - h, width: w * 2, height: h * 2)
        let cornerRadius = min(w, h) * 0.92
        context.fill(
            Path(roundedRect: eyeRect, cornerRadius: cornerRadius),
            with: .color(accent)
        )

        if openFactor > 0.45 && !compactMode {
            let glintCenter = CGPoint(x: ex - w * 0.34, y: ey - h * 0.36)
            let glintRect = CGRect(x: glintCenter.x - 1.45, y: glintCenter.y - 1.45, width: 2.9, height: 2.9)
            context.fill(Path(ellipseIn: glintRect), with: .color(PipiTokens.avatarGlint))
        }
    }
}
