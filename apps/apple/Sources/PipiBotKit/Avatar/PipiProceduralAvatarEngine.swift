import Foundation
import CoreGraphics
import Observation

// MARK: - Math & Procedural Geometry Constants

public enum PipiAvatarMath {
    public static let rayCount: Int = 192
    public static let fixedHz: Double = 120.0
    public static let fixedDt: Double = 1.0 / 120.0
    public static let blinkDuration: Double = 0.26
    public static let blinkPeakRatio: Double = 0.45

    public static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    public static func normalize(_ v: SIMD3<Double>) -> SIMD3<Double> {
        let len = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
        guard len > 1e-8 else { return SIMD3<Double>(0, 0, 1) }
        return v / len
    }

    public static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    public static func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
    }

    /// Rodrigues' rotation formula on a unit sphere:
    /// v_rot = v*cos(theta) + (k x v)*sin(theta) + k*(k . v)*(1 - cos(theta))
    public static func rodriguesRotate(
        _ v: SIMD3<Double>,
        axis k: SIMD3<Double>,
        theta: Double
    ) -> SIMD3<Double> {
        let axis = normalize(k)
        let cosT = cos(theta)
        let sinT = sin(theta)
        let kCrossV = cross(axis, v)
        let kDotV = dot(axis, v)
        let factor = 1.0 - cosT
        return v * cosT + kCrossV * sinT + axis * (kDotV * factor)
    }

    /// Evaluates cubic-bezier(p1x, p1y, p2x, p2y) at u in [0, 1], supporting overshoot y values.
    public static func cubicBezier(
        p1x: Double,
        p1y: Double,
        p2x: Double,
        p2y: Double,
        t: Double
    ) -> Double {
        let u = clamp(t, min: 0.0, max: 1.0)
        if u <= 0.0 { return 0.0 }
        if u >= 1.0 { return 1.0 }

        func sampleX(_ s: Double) -> Double {
            let inv = 1.0 - s
            return 3.0 * inv * inv * s * p1x + 3.0 * inv * s * s * p2x + s * s * s
        }

        func sampleDX(_ s: Double) -> Double {
            let inv = 1.0 - s
            return 3.0 * inv * inv * p1x + 6.0 * inv * s * (p2x - p1x) + 3.0 * s * s * (1.0 - p2x)
        }

        func sampleY(_ s: Double) -> Double {
            let inv = 1.0 - s
            return 3.0 * inv * inv * s * p1y + 3.0 * inv * s * s * p2y + s * s * s
        }

        var s = u
        for _ in 0..<6 {
            let err = sampleX(s) - u
            if abs(err) < 1e-5 { return sampleY(s) }
            let dx = sampleDX(s)
            if abs(dx) < 1e-5 { break }
            s = clamp(s - err / dx, min: 0.0, max: 1.0)
        }

        var lo = 0.0
        var hi = 1.0
        s = u
        for _ in 0..<12 {
            let x = sampleX(s)
            if abs(x - u) < 1e-5 { break }
            if u > x { lo = s } else { hi = s }
            s = 0.5 * (lo + hi)
        }
        return sampleY(s)
    }

    /// Polar radius evaluation across the 8 canonical PipiAvatar body shapes.
    public static func sampleShape192(_ shape: AvatarShape) -> [Double] {
        var radii = [Double](repeating: 0.98, count: rayCount)
        for i in 0..<rayCount {
            let theta = (Double.pi * 2.0 * Double(i)) / Double(rayCount)
            switch shape {
            case .orb:
                radii[i] = 0.98
            case .squircle:
                let c = abs(cos(theta))
                let s = abs(sin(theta))
                radii[i] = pow(pow(c, 4.0) + pow(s, 4.0), -0.25) * 0.94
            case .cloud:
                radii[i] = 0.87 + 0.115 * cos(5.0 * theta - Double.pi / 2.0) + 0.038 * cos(10.0 * theta)
            case .spark:
                radii[i] = 0.70 + 0.34 * pow(abs(cos(2.0 * theta)), 1.65)
            case .bolt:
                radii[i] = 0.85 + 0.13 * cos(2.0 * theta - 0.65) + 0.10 * cos(6.0 * theta + 0.25)
            case .shield:
                let s = sin(theta)
                let c2 = cos(theta) * cos(theta)
                let base = pow(pow(abs(cos(theta)), 3.2) + pow(abs(s), 3.2), -1.0 / 3.2) * 0.94
                if s > 0 {
                    radii[i] = base * (1.0 - 0.28 * s * c2 + 0.11 * pow(s, 4.0))
                } else {
                    radii[i] = base * (1.0 - 0.05 * pow(-s, 3.0))
                }
            case .dream:
                radii[i] = 0.90 + 0.10 * sin(2.0 * theta - 0.4) + 0.07 * cos(3.0 * theta + 0.6) - 0.04 * cos(theta)
            case .terminal:
                let rx = abs(cos(theta)) / 1.07
                let ry = abs(sin(theta)) / 0.89
                radii[i] = pow(pow(rx, 6.0) + pow(ry, 6.0), -1.0 / 6.0)
            }
        }
        return radii
    }

    public static func interpolateRays192(from: [Double], to: [Double], t: Double) -> [Double] {
        var result = [Double](repeating: 0.98, count: rayCount)
        for i in 0..<rayCount {
            result[i] = from[i] + (to[i] - from[i]) * t
        }
        return result
    }

    public static func buildSmoothContourPath(
        radii: [Double],
        center: CGPoint,
        baseRadius: Double,
        scaleX: Double,
        scaleY: Double,
        rotationRad: Double
    ) -> CGPath {
        var points = [CGPoint](repeating: .zero, count: rayCount)
        let cosR = cos(rotationRad)
        let sinR = sin(rotationRad)

        for i in 0..<rayCount {
            let theta = (Double.pi * 2.0 * Double(i)) / Double(rayCount)
            let r = radii[i] * baseRadius
            let lx = cos(theta) * r * scaleX
            let ly = sin(theta) * r * scaleY
            points[i] = CGPoint(
                x: center.x + lx * cosR - ly * sinR,
                y: center.y + lx * sinR + ly * cosR
            )
        }

        let path = CGMutablePath()
        let last = points[rayCount - 1]
        let first = points[0]
        path.move(to: CGPoint(x: (last.x + first.x) * 0.5, y: (last.y + first.y) * 0.5))
        for i in 0..<rayCount {
            let next = points[(i + 1) % rayCount]
            let mid = CGPoint(x: (points[i].x + next.x) * 0.5, y: (points[i].y + next.y) * 0.5)
            path.addQuadCurve(to: mid, control: points[i])
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Seeded Mulberry32 PRNG

public struct SeededMulberryRng: Sendable {
    private var state: UInt32

    public init(seed: UInt32 = 20261118) {
        self.state = seed
    }

    public mutating func next() -> Double {
        state = state &+ 0x6D2B79F5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}

// MARK: - 120 Hz Semi-Implicit Euler Spring Channel

public struct EulerSpringChannel: Sendable, Equatable {
    public var value: Double
    public var target: Double
    public var velocity: Double
    public var stiffness: Double
    public var damping: Double

    public init(
        value: Double = 0.0,
        target: Double = 0.0,
        stiffness: Double = 240.0,
        damping: Double = 18.0
    ) {
        self.value = value
        self.target = target
        self.velocity = 0.0
        self.stiffness = stiffness
        self.damping = damping
    }

    @discardableResult
    public mutating func step(dt: Double = PipiAvatarMath.fixedDt) -> Double {
        let acc = (target - value) * stiffness - velocity * damping
        velocity += acc * dt
        value += velocity * dt
        return value
    }

    public mutating func impulse(_ deltaVelocity: Double) {
        velocity += deltaVelocity
    }

    public mutating func setTarget(_ target: Double, stiffness: Double? = nil, damping: Double? = nil) {
        self.target = target
        if let stiffness { self.stiffness = stiffness }
        if let damping { self.damping = damping }
    }

    public mutating func snap(_ newValue: Double) {
        value = newValue
        target = newValue
        velocity = 0.0
    }
}

// MARK: - 9 Core Expressions & 6-Track Keyframe Choreography

public struct AvatarExpressionSpec: Sendable, Equatable {
    public let id: AvatarExpression9
    public let eyeW: Double
    public let eyeH: Double
    public let tiltDeg: Double
    public let squashBias: Double
    public let lidTop: Double
    public let lidBottom: Double
    public let happyArc: Double
    public let asymmetry: Double
    public let glowBoost: Double
}

public struct KeyframePoint: Sendable, Equatable {
    public let t: Double
    public let v: Double
    public let ease: SIMD4<Double>

    public init(_ t: Double, _ v: Double, ease: SIMD4<Double> = SIMD4<Double>(0.34, 1.56, 0.64, 1.0)) {
        self.t = t
        self.v = v
        self.ease = ease
    }
}

public struct TrackClip6: Sendable, Equatable {
    public let periodSec: Double
    public let x: [KeyframePoint]
    public let y: [KeyframePoint]
    public let rot: [KeyframePoint]
    public let squash: [KeyframePoint]
    public let scale: [KeyframePoint]
    public let lids: [KeyframePoint]

    static func evaluate(_ keyframes: [KeyframePoint], phase: Double) -> Double {
        guard !keyframes.isEmpty else { return 0.0 }
        if keyframes.count == 1 { return keyframes[0].v }
        let u = phase.truncatingRemainder(dividingBy: 1.0)
        let normalized = u < 0 ? u + 1.0 : u
        for i in 0..<(keyframes.count - 1) {
            let a = keyframes[i]
            let b = keyframes[i + 1]
            if normalized >= a.t && normalized <= b.t {
                let span = Swift.max(1e-5, b.t - a.t)
                let localT = (normalized - a.t) / span
                let curved = PipiAvatarMath.cubicBezier(
                    p1x: b.ease.x,
                    p1y: b.ease.y,
                    p2x: b.ease.z,
                    p2y: b.ease.w,
                    t: localT
                )
                return PipiAvatarMath.lerp(a.v, b.v, curved)
            }
        }
        return keyframes.last?.v ?? 0.0
    }
}

public struct AvatarStateDescriptor: Sendable, Equatable {
    public let state: AvatarState53
    public let label: String
    public let group: AvatarLifecycleGroup
    public let preset: AvatarPresetKind
    public let shape: AvatarShape
    public let expression: AvatarExpression9
}

public struct AvatarTracksSnapshot: Sendable, Equatable {
    public var x: Double = 0
    public var y: Double = 0
    public var rot: Double = 0
    public var squash: Double = 0
    public var scale: Double = 1
    public var lids: Double = 0
}

public struct AvatarTelemetrySnapshot: Sendable, Equatable {
    public let state: AvatarState53
    public let shape: AvatarShape
    public let expression: AvatarExpression9
    public let elapsed: Double
    public let springAmount: Double
    public let springSwap: Double
    public let springSpin: Double
    public let tracks: AvatarTracksSnapshot
    public let gazeX: Double
    public let gazeY: Double
    public let gazeThetaRad: Double
    public let leftEye3D: SIMD3<Double>
    public let rightEye3D: SIMD3<Double>
    public let blinkActive: Bool
    public let blinkProgress: Double
    public let blinkClosure: Double
}

// MARK: - PipiProceduralAvatarEngine

@MainActor
@Observable
public final class PipiProceduralAvatarEngine {
    nonisolated public static let leftEyeSphereBase = PipiAvatarMath.normalize(SIMD3<Double>(-0.31, -0.04, 0.95))
    nonisolated public static let rightEyeSphereBase = PipiAvatarMath.normalize(SIMD3<Double>(0.31, -0.04, 0.95))

    public private(set) var state: AvatarState53 = .idle
    public private(set) var shape: AvatarShape = .orb
    public private(set) var expression: AvatarExpression9 = .neutral
    public private(set) var preset: AvatarPresetKind = .idle
    public private(set) var elapsed: Double = 0.0

    public private(set) var currentRadii: [Double]
    private var fromRadii: [Double]
    private var toRadii: [Double]

    private var amountSpring = EulerSpringChannel(value: 0, target: 0, stiffness: 360, damping: 18)
    private var swapSpring = EulerSpringChannel(value: 1, target: 1, stiffness: 210, damping: 19)
    private var spinSpring = EulerSpringChannel(value: 0, target: 0, stiffness: 240, damping: 17)
    private var gazeXSpring = EulerSpringChannel(value: 0, target: 0, stiffness: 150, damping: 16)
    private var gazeYSpring = EulerSpringChannel(value: 0, target: 0, stiffness: 150, damping: 16)

    public private(set) var tracks = AvatarTracksSnapshot()
    public private(set) var leftEye3D: SIMD3<Double> = PipiProceduralAvatarEngine.leftEyeSphereBase
    public private(set) var rightEye3D: SIMD3<Double> = PipiProceduralAvatarEngine.rightEyeSphereBase
    public private(set) var gazeThetaRad: Double = 0.0
    public private(set) var blinkActive: Bool = false
    public private(set) var blinkClosure: Double = 0.0
    private var blinkElapsed: Double = 0.0
    private var nextAutoBlinkAt: Double = 2.6

    private var pointerGaze: CGPoint = .zero
    private var lastPointerMoveTime: Double = -10.0
    private var accumulator: Double = 0.0
    private var rng = SeededMulberryRng()

    public var autoBlink: Bool = true
    public var cursorTrack: Bool = true

    public init(initialState: AvatarState53 = .idle) {
        let initialRadii = PipiAvatarMath.sampleShape192(.orb)
        self.fromRadii = initialRadii
        self.toRadii = initialRadii
        self.currentRadii = initialRadii
        self.setState(initialState, immediate: true)
    }

    public func setState(_ newState: AvatarState53, immediate: Bool = false) {
        let desc = Self.metadata(for: newState)
        state = desc.state
        preset = desc.preset
        expression = desc.expression
        setShape(desc.shape, immediate: immediate)

        if !immediate {
            amountSpring.impulse(2.8)
            spinSpring.impulse(newState == .needsYou || newState == .needsYouUrgent ? -140.0 : 110.0)
        }
    }

    public func setShape(_ newShape: AvatarShape, immediate: Bool = false) {
        if newShape == shape && !immediate { return }
        shape = newShape
        fromRadii = currentRadii
        toRadii = PipiAvatarMath.sampleShape192(newShape)
        if immediate {
            currentRadii = toRadii
            swapSpring.snap(1.0)
        } else {
            swapSpring.snap(0.0)
            swapSpring.setTarget(1.0, stiffness: 210.0, damping: 19.0)
            amountSpring.impulse(1.9)
        }
    }

    public func setExpression(_ newExpression: AvatarExpression9) {
        expression = newExpression
    }

    public func setGazeTarget(nx: Double, ny: Double) {
        pointerGaze = CGPoint(
            x: PipiAvatarMath.clamp(nx, min: -1.0, max: 1.0),
            y: PipiAvatarMath.clamp(ny, min: -1.0, max: 1.0)
        )
        lastPointerMoveTime = elapsed
    }

    public func blink() {
        blinkActive = true
        blinkElapsed = 0.0
    }

    public func poke() {
        blink()
        amountSpring.impulse(4.8)
        let dir = rng.next() > 0.5 ? 1.0 : -1.0
        spinSpring.impulse(dir * 185.0)
    }

    public func step(deltaSec: Double) {
        guard deltaSec > 0 else { return }
        accumulator += deltaSec
        while accumulator >= PipiAvatarMath.fixedDt {
            stepFixed(dt: PipiAvatarMath.fixedDt)
            accumulator -= PipiAvatarMath.fixedDt
        }
    }

    private func stepFixed(dt: Double) {
        elapsed += dt

        // 1. Auto-blink scheduler (0.26s cycle, closed at 45%)
        if autoBlink && !blinkActive && elapsed >= nextAutoBlinkAt {
            blink()
            let isDouble = rng.next() < 0.14
            nextAutoBlinkAt = elapsed + (isDouble ? 0.36 : 2.6 + rng.next() * 3.4)
        }

        var currentClosure = 0.0
        if blinkActive {
            blinkElapsed += dt
            let u = blinkElapsed / PipiAvatarMath.blinkDuration
            if u >= 1.0 {
                blinkActive = false
                blinkElapsed = 0.0
                currentClosure = 0.0
            } else if u <= PipiAvatarMath.blinkPeakRatio {
                currentClosure = pow(u / PipiAvatarMath.blinkPeakRatio, 1.55)
            } else {
                let reopen = (u - PipiAvatarMath.blinkPeakRatio) / (1.0 - PipiAvatarMath.blinkPeakRatio)
                currentClosure = pow(1.0 - reopen, 2.2)
            }
        }
        blinkClosure = currentClosure

        // 2. Idle gaze drift vs pointer gaze
        if !cursorTrack || (elapsed - lastPointerMoveTime) > 2.4 {
            let lookPhase = elapsed * 0.72
            let ax = sin(lookPhase) * 0.34 + sin(lookPhase * 2.1) * 0.14
            let ay = cos(lookPhase * 0.85) * 0.20
            gazeXSpring.setTarget(ax, stiffness: 85.0, damping: 13.0)
            gazeYSpring.setTarget(ay, stiffness: 85.0, damping: 13.0)
        } else {
            gazeXSpring.setTarget(pointerGaze.x, stiffness: 180.0, damping: 18.0)
            gazeYSpring.setTarget(pointerGaze.y, stiffness: 180.0, damping: 18.0)
        }

        // 3. Step 120 Hz Euler springs
        amountSpring.step(dt: dt)
        swapSpring.step(dt: dt)
        spinSpring.step(dt: dt)
        gazeXSpring.step(dt: dt)
        gazeYSpring.step(dt: dt)

        // 4. Evaluate 6-track keyframe choreography
        let clip = Self.clip(for: preset)
        let period = Swift.max(0.5, clip.periodSec)
        let phase = elapsed.truncatingRemainder(dividingBy: period) / period
        tracks.x = TrackClip6.evaluate(clip.x, phase: phase)
        tracks.y = TrackClip6.evaluate(clip.y, phase: phase)
        tracks.rot = TrackClip6.evaluate(clip.rot, phase: phase)
        tracks.squash = TrackClip6.evaluate(clip.squash, phase: phase)
        tracks.scale = TrackClip6.evaluate(clip.scale, phase: phase)
        tracks.lids = PipiAvatarMath.clamp(
            Swift.max(TrackClip6.evaluate(clip.lids, phase: phase), currentClosure),
            min: 0.0,
            max: 1.0
        )

        // 5. Update 192-ray radial contour interpolation
        currentRadii = PipiAvatarMath.interpolateRays192(from: fromRadii, to: toRadii, t: swapSpring.value)

        // 6. Rodrigues 3D sphere eye rotations
        let gx = gazeXSpring.value
        let gy = gazeYSpring.value
        let gazeMag = PipiAvatarMath.clamp((gx * gx + gy * gy).squareRoot(), min: 0.0, max: 1.0)
        let axis = gazeMag > 1e-4 ? PipiAvatarMath.normalize(SIMD3<Double>(-gy, gx, 0.0)) : SIMD3<Double>(0, 1, 0)
        let theta = gazeMag * 0.46
        gazeThetaRad = theta
        leftEye3D = PipiAvatarMath.rodriguesRotate(Self.leftEyeSphereBase, axis: axis, theta: theta)
        rightEye3D = PipiAvatarMath.rodriguesRotate(Self.rightEyeSphereBase, axis: axis, theta: theta)
    }

    public func telemetrySnapshot() -> AvatarTelemetrySnapshot {
        AvatarTelemetrySnapshot(
            state: state,
            shape: shape,
            expression: expression,
            elapsed: elapsed,
            springAmount: amountSpring.value,
            springSwap: swapSpring.value,
            springSpin: spinSpring.value,
            tracks: tracks,
            gazeX: gazeXSpring.value,
            gazeY: gazeYSpring.value,
            gazeThetaRad: gazeThetaRad,
            leftEye3D: leftEye3D,
            rightEye3D: rightEye3D,
            blinkActive: blinkActive,
            blinkProgress: blinkActive ? PipiAvatarMath.clamp(blinkElapsed / PipiAvatarMath.blinkDuration, min: 0, max: 1) : 0,
            blinkClosure: blinkClosure
        )
    }

    nonisolated public static func expressionSpec(for expr: AvatarExpression9) -> AvatarExpressionSpec {
        switch expr {
        case .neutral:
            return AvatarExpressionSpec(id: .neutral, eyeW: 5.2, eyeH: 6.4, tiltDeg: 0, squashBias: 0, lidTop: 0, lidBottom: 0, happyArc: 0, asymmetry: 0, glowBoost: 1.0)
        case .happy:
            return AvatarExpressionSpec(id: .happy, eyeW: 5.6, eyeH: 5.2, tiltDeg: 0, squashBias: 0.04, lidTop: 0, lidBottom: 0.42, happyArc: 1.0, asymmetry: 0, glowBoost: 1.25)
        case .focused:
            return AvatarExpressionSpec(id: .focused, eyeW: 5.8, eyeH: 4.3, tiltDeg: 4, squashBias: -0.02, lidTop: 0.24, lidBottom: 0.14, happyArc: 0, asymmetry: 0, glowBoost: 1.3)
        case .curious:
            return AvatarExpressionSpec(id: .curious, eyeW: 5.6, eyeH: 7.2, tiltDeg: -7, squashBias: 0.02, lidTop: 0, lidBottom: 0, happyArc: 0, asymmetry: 0.18, glowBoost: 1.15)
        case .alert:
            return AvatarExpressionSpec(id: .alert, eyeW: 6.0, eyeH: 7.8, tiltDeg: 0, squashBias: -0.06, lidTop: 0, lidBottom: 0, happyArc: 0, asymmetry: 0, glowBoost: 1.55)
        case .proud:
            return AvatarExpressionSpec(id: .proud, eyeW: 5.8, eyeH: 4.6, tiltDeg: -3, squashBias: 0.05, lidTop: 0.08, lidBottom: 0.45, happyArc: 0.85, asymmetry: 0, glowBoost: 1.4)
        case .sleepy:
            return AvatarExpressionSpec(id: .sleepy, eyeW: 5.4, eyeH: 2.8, tiltDeg: 0, squashBias: 0.07, lidTop: 0.68, lidBottom: 0.12, happyArc: 0, asymmetry: 0, glowBoost: 0.65)
        case .evolving:
            return AvatarExpressionSpec(id: .evolving, eyeW: 5.8, eyeH: 6.8, tiltDeg: 0, squashBias: 0.02, lidTop: 0.05, lidBottom: 0.10, happyArc: 0.3, asymmetry: 0, glowBoost: 1.65)
        case .listening:
            return AvatarExpressionSpec(id: .listening, eyeW: 5.9, eyeH: 7.0, tiltDeg: -4, squashBias: 0.03, lidTop: 0, lidBottom: 0, happyArc: 0, asymmetry: 0, glowBoost: 1.35)
        }
    }

    nonisolated public static func clip(for preset: AvatarPresetKind) -> TrackClip6 {
        let gentle = SIMD4<Double>(0.42, 0.0, 0.58, 1.0)
        let snappy = SIMD4<Double>(0.22, 1.0, 0.36, 1.0)
        let overshoot = SIMD4<Double>(0.34, 1.56, 0.64, 1.0)

        switch preset {
        case .idle:
            return TrackClip6(
                periodSec: 4.2,
                x: [KeyframePoint(0, 0), KeyframePoint(0.5, 1.4, ease: gentle), KeyframePoint(1, 0, ease: gentle)],
                y: [KeyframePoint(0, 0), KeyframePoint(0.5, -3.2, ease: gentle), KeyframePoint(1, 0, ease: gentle)],
                rot: [KeyframePoint(0, -1.5), KeyframePoint(0.5, 1.5, ease: gentle), KeyframePoint(1, -1.5, ease: gentle)],
                squash: [KeyframePoint(0, 0), KeyframePoint(0.5, -0.025, ease: gentle), KeyframePoint(1, 0, ease: gentle)],
                scale: [KeyframePoint(0, 0.99), KeyframePoint(0.5, 1.025, ease: gentle), KeyframePoint(1, 0.99, ease: gentle)],
                lids: [KeyframePoint(0, 0), KeyframePoint(1, 0)]
            )
        case .thinking:
            return TrackClip6(
                periodSec: 2.6,
                x: [KeyframePoint(0, -2.2), KeyframePoint(0.5, 2.2, ease: overshoot), KeyframePoint(1, -2.2, ease: overshoot)],
                y: [KeyframePoint(0, -1.5), KeyframePoint(0.35, -5.2, ease: overshoot), KeyframePoint(0.7, 1.0, ease: gentle), KeyframePoint(1, -1.5, ease: gentle)],
                rot: [KeyframePoint(0, -5), KeyframePoint(0.5, 6, ease: overshoot), KeyframePoint(1, -5, ease: overshoot)],
                squash: [KeyframePoint(0, 0.02), KeyframePoint(0.5, -0.04, ease: overshoot), KeyframePoint(1, 0.02, ease: gentle)],
                scale: [KeyframePoint(0, 0.98), KeyframePoint(0.5, 1.04, ease: gentle), KeyframePoint(1, 0.98, ease: gentle)],
                lids: [KeyframePoint(0, 0.06), KeyframePoint(0.5, 0.16, ease: gentle), KeyframePoint(1, 0.06, ease: gentle)]
            )
        case .piCoding:
            return TrackClip6(
                periodSec: 1.5,
                x: [KeyframePoint(0, -1.4), KeyframePoint(0.25, 1.6, ease: snappy), KeyframePoint(0.5, -1.2, ease: snappy), KeyframePoint(0.75, 1.4, ease: snappy), KeyframePoint(1, -1.4, ease: snappy)],
                y: [KeyframePoint(0, 0), KeyframePoint(0.25, -2.4, ease: overshoot), KeyframePoint(0.5, 0.6, ease: gentle), KeyframePoint(0.75, -2.0, ease: overshoot), KeyframePoint(1, 0, ease: gentle)],
                rot: [KeyframePoint(0, -1.5), KeyframePoint(0.5, 1.5, ease: snappy), KeyframePoint(1, -1.5, ease: snappy)],
                squash: [KeyframePoint(0, 0.03), KeyframePoint(0.5, -0.03, ease: overshoot), KeyframePoint(1, 0.03, ease: overshoot)],
                scale: [KeyframePoint(0, 1.0), KeyframePoint(0.5, 1.03, ease: snappy), KeyframePoint(1, 1.0, ease: snappy)],
                lids: [KeyframePoint(0, 0.12), KeyframePoint(1, 0.12)]
            )
        case .claudeRouting:
            return TrackClip6(
                periodSec: 2.1,
                x: [KeyframePoint(0, 0), KeyframePoint(0.5, 1.8), KeyframePoint(1, 0)],
                y: [KeyframePoint(0, 0), KeyframePoint(0.5, -3.5, ease: overshoot), KeyframePoint(1, 0)],
                rot: [KeyframePoint(0, -2), KeyframePoint(0.5, 3), KeyframePoint(1, -2)],
                squash: [KeyframePoint(0, 0.01), KeyframePoint(0.5, -0.04), KeyframePoint(1, 0.01)],
                scale: [KeyframePoint(0, 0.99), KeyframePoint(0.5, 1.035), KeyframePoint(1, 0.99)],
                lids: [KeyframePoint(0, 0.08), KeyframePoint(1, 0.08)]
            )
        case .codexRouting:
            return TrackClip6(
                periodSec: 1.35,
                x: [KeyframePoint(0, -2), KeyframePoint(0.5, 2, ease: snappy), KeyframePoint(1, -2)],
                y: [KeyframePoint(0, 0), KeyframePoint(0.35, -4.2, ease: overshoot), KeyframePoint(1, 0)],
                rot: [KeyframePoint(0, -4), KeyframePoint(0.5, 4), KeyframePoint(1, -4)],
                squash: [KeyframePoint(0, 0.04), KeyframePoint(0.5, -0.05), KeyframePoint(1, 0.04)],
                scale: [KeyframePoint(0, 0.98), KeyframePoint(0.5, 1.045), KeyframePoint(1, 0.98)],
                lids: [KeyframePoint(0, 0.14), KeyframePoint(1, 0.14)]
            )
        case .opencodeRouting:
            return TrackClip6(
                periodSec: 1.9,
                x: [KeyframePoint(0, 0), KeyframePoint(0.5, -1.8), KeyframePoint(1, 0)],
                y: [KeyframePoint(0, 0), KeyframePoint(0.5, -4.0, ease: overshoot), KeyframePoint(1, 0)],
                rot: [KeyframePoint(0, -3), KeyframePoint(0.5, 5), KeyframePoint(1, -3)],
                squash: [KeyframePoint(0, 0), KeyframePoint(0.5, -0.04), KeyframePoint(1, 0)],
                scale: [KeyframePoint(0, 0.98), KeyframePoint(0.5, 1.04), KeyframePoint(1, 0.98)],
                lids: [KeyframePoint(0, 0), KeyframePoint(1, 0)]
            )
        case .byokStreaming:
            return TrackClip6(
                periodSec: 1.7,
                x: [KeyframePoint(0, -1), KeyframePoint(0.5, 1), KeyframePoint(1, -1)],
                y: [KeyframePoint(0, 0), KeyframePoint(0.5, -3.0), KeyframePoint(1, 0)],
                rot: [KeyframePoint(0, -2), KeyframePoint(0.5, 2), KeyframePoint(1, -2)],
                squash: [KeyframePoint(0, 0.02), KeyframePoint(0.5, -0.03), KeyframePoint(1, 0.02)],
                scale: [KeyframePoint(0, 0.99), KeyframePoint(0.5, 1.05), KeyframePoint(1, 0.99)],
                lids: [KeyframePoint(0, 0), KeyframePoint(1, 0)]
            )
        case .manusCue:
            return TrackClip6(
                periodSec: 2.0,
                x: [KeyframePoint(0, 0), KeyframePoint(0.3, 2.8, ease: overshoot), KeyframePoint(1, 0)],
                y: [KeyframePoint(0, 0), KeyframePoint(0.4, -4.8, ease: overshoot), KeyframePoint(1, 0)],
                rot: [KeyframePoint(0, -6), KeyframePoint(0.45, 4, ease: overshoot), KeyframePoint(1, -6)],
                squash: [KeyframePoint(0, 0.04), KeyframePoint(0.4, -0.05), KeyframePoint(1, 0.04)],
                scale: [KeyframePoint(0, 0.98), KeyframePoint(0.4, 1.06), KeyframePoint(1, 0.98)],
                lids: [KeyframePoint(0, 0), KeyframePoint(1, 0)]
            )
        case .needsYou:
            return TrackClip6(
                periodSec: 1.15,
                x: [KeyframePoint(0, 0), KeyframePoint(0.18, -2.4, ease: overshoot), KeyframePoint(0.36, 2.4, ease: overshoot), KeyframePoint(0.55, 0, ease: snappy), KeyframePoint(1, 0)],
                y: [KeyframePoint(0, 0), KeyframePoint(0.25, -5.6, ease: overshoot), KeyframePoint(0.6, 0.5, ease: gentle), KeyframePoint(1, 0)],
                rot: [KeyframePoint(0, 0), KeyframePoint(0.2, -5), KeyframePoint(0.4, 5), KeyframePoint(0.65, 0), KeyframePoint(1, 0)],
                squash: [KeyframePoint(0, 0.06), KeyframePoint(0.28, -0.07, ease: overshoot), KeyframePoint(0.65, 0.02), KeyframePoint(1, 0.06)],
                scale: [KeyframePoint(0, 1.0), KeyframePoint(0.28, 1.07, ease: overshoot), KeyframePoint(1, 1.0)],
                lids: [KeyframePoint(0, 0), KeyframePoint(1, 0)]
            )
        case .evolving:
            return TrackClip6(
                periodSec: 3.0,
                x: [KeyframePoint(0, 0), KeyframePoint(0.5, 1.6), KeyframePoint(1, 0)],
                y: [KeyframePoint(0, 0), KeyframePoint(0.5, -6.0, ease: overshoot), KeyframePoint(1, 0)],
                rot: [KeyframePoint(0, -4), KeyframePoint(0.5, 4, ease: gentle), KeyframePoint(1, -4)],
                squash: [KeyframePoint(0, 0.02), KeyframePoint(0.5, -0.05), KeyframePoint(1, 0.02)],
                scale: [KeyframePoint(0, 0.97), KeyframePoint(0.5, 1.06, ease: overshoot), KeyframePoint(1, 0.97)],
                lids: [KeyframePoint(0, 0), KeyframePoint(1, 0)]
            )
        case .sleeping:
            return TrackClip6(
                periodSec: 5.2,
                x: [KeyframePoint(0, -0.8), KeyframePoint(0.5, 0.8), KeyframePoint(1, -0.8)],
                y: [KeyframePoint(0, 2.0), KeyframePoint(0.5, 4.5, ease: gentle), KeyframePoint(1, 2.0)],
                rot: [KeyframePoint(0, 4), KeyframePoint(0.5, 8, ease: gentle), KeyframePoint(1, 4)],
                squash: [KeyframePoint(0, 0.06), KeyframePoint(0.5, 0.10, ease: gentle), KeyframePoint(1, 0.06)],
                scale: [KeyframePoint(0, 0.97), KeyframePoint(0.5, 1.01, ease: gentle), KeyframePoint(1, 0.97)],
                lids: [KeyframePoint(0, 0.78), KeyframePoint(1, 0.78)]
            )
        }
    }

    nonisolated public static func metadata(for state: AvatarState53) -> AvatarStateDescriptor {
        switch state {
        // Group 1: Idle & Ambient (10)
        case .idle: return AvatarStateDescriptor(state: .idle, label: "Idle Breathe", group: .idleAmbient, preset: .idle, shape: .orb, expression: .neutral)
        case .ambientBreathe: return AvatarStateDescriptor(state: .ambientBreathe, label: "Ambient Pulse", group: .idleAmbient, preset: .idle, shape: .orb, expression: .happy)
        case .ambientWander: return AvatarStateDescriptor(state: .ambientWander, label: "Gaze Wander", group: .idleAmbient, preset: .idle, shape: .squircle, expression: .curious)
        case .ambientCuriousGlance: return AvatarStateDescriptor(state: .ambientCuriousGlance, label: "Curious Glance", group: .idleAmbient, preset: .idle, shape: .squircle, expression: .curious)
        case .ambientCoffeeBreak: return AvatarStateDescriptor(state: .ambientCoffeeBreak, label: "Coffee Break", group: .idleAmbient, preset: .idle, shape: .cloud, expression: .happy)
        case .ambientNightWatch: return AvatarStateDescriptor(state: .ambientNightWatch, label: "Night Watch", group: .idleAmbient, preset: .idle, shape: .shield, expression: .focused)
        case .ambientBatterySaver: return AvatarStateDescriptor(state: .ambientBatterySaver, label: "Eco Standby", group: .idleAmbient, preset: .sleeping, shape: .orb, expression: .sleepy)
        case .ambientStandby: return AvatarStateDescriptor(state: .ambientStandby, label: "MenuBar Docked", group: .idleAmbient, preset: .idle, shape: .squircle, expression: .neutral)
        case .ambientWarmWelcome: return AvatarStateDescriptor(state: .ambientWarmWelcome, label: "Warm Welcome", group: .idleAmbient, preset: .evolving, shape: .orb, expression: .happy)
        case .ambientZen: return AvatarStateDescriptor(state: .ambientZen, label: "Zen Flow", group: .idleAmbient, preset: .idle, shape: .dream, expression: .proud)

        // Group 2: Thinking & Reasoning (11)
        case .thinking: return AvatarStateDescriptor(state: .thinking, label: "Deep Thinking", group: .thinkingReasoning, preset: .thinking, shape: .cloud, expression: .curious)
        case .deepReasoning: return AvatarStateDescriptor(state: .deepReasoning, label: "Chain of Thought", group: .thinkingReasoning, preset: .thinking, shape: .cloud, expression: .focused)
        case .memoryRecall: return AvatarStateDescriptor(state: .memoryRecall, label: "Memory Recall", group: .thinkingReasoning, preset: .thinking, shape: .orb, expression: .curious)
        case .contextScanning: return AvatarStateDescriptor(state: .contextScanning, label: "Context Scanning", group: .thinkingReasoning, preset: .thinking, shape: .terminal, expression: .focused)
        case .planStructuring: return AvatarStateDescriptor(state: .planStructuring, label: "Plan Structuring", group: .thinkingReasoning, preset: .thinking, shape: .squircle, expression: .focused)
        case .hypothesisBranching: return AvatarStateDescriptor(state: .hypothesisBranching, label: "Branch Exploring", group: .thinkingReasoning, preset: .thinking, shape: .spark, expression: .curious)
        case .crossChecking: return AvatarStateDescriptor(state: .crossChecking, label: "Cross Checking", group: .thinkingReasoning, preset: .thinking, shape: .shield, expression: .focused)
        case .costRouting: return AvatarStateDescriptor(state: .costRouting, label: "Harness Cost Route", group: .thinkingReasoning, preset: .thinking, shape: .bolt, expression: .focused)
        case .diffAnalyzing: return AvatarStateDescriptor(state: .diffAnalyzing, label: "Diff Analyzing", group: .thinkingReasoning, preset: .piCoding, shape: .terminal, expression: .focused)
        case .voiceTranscribing: return AvatarStateDescriptor(state: .voiceTranscribing, label: "Voice Listening", group: .thinkingReasoning, preset: .byokStreaming, shape: .orb, expression: .listening)
        case .synthesizing: return AvatarStateDescriptor(state: .synthesizing, label: "Outcome Synthesis", group: .thinkingReasoning, preset: .evolving, shape: .spark, expression: .proud)

        // Group 3: Tool & Harness Execution (14)
        case .piCoding: return AvatarStateDescriptor(state: .piCoding, label: "Pi Core Active", group: .toolHarnessExecution, preset: .piCoding, shape: .terminal, expression: .focused)
        case .piBashRunning: return AvatarStateDescriptor(state: .piBashRunning, label: "Pi Bash Shell", group: .toolHarnessExecution, preset: .piCoding, shape: .terminal, expression: .focused)
        case .piFileEditing: return AvatarStateDescriptor(state: .piFileEditing, label: "Pi File Patching", group: .toolHarnessExecution, preset: .piCoding, shape: .squircle, expression: .focused)
        case .claudeRouting: return AvatarStateDescriptor(state: .claudeRouting, label: "Claude Code CLI", group: .toolHarnessExecution, preset: .claudeRouting, shape: .squircle, expression: .focused)
        case .codexRouting: return AvatarStateDescriptor(state: .codexRouting, label: "Codex Harness", group: .toolHarnessExecution, preset: .codexRouting, shape: .bolt, expression: .focused)
        case .opencodeRouting: return AvatarStateDescriptor(state: .opencodeRouting, label: "OpenCode ACP", group: .toolHarnessExecution, preset: .opencodeRouting, shape: .spark, expression: .curious)
        case .byokStreaming: return AvatarStateDescriptor(state: .byokStreaming, label: "BYOK Streaming", group: .toolHarnessExecution, preset: .byokStreaming, shape: .orb, expression: .listening)
        case .mcpBridging: return AvatarStateDescriptor(state: .mcpBridging, label: "Routed MCP Bridge", group: .toolHarnessExecution, preset: .piCoding, shape: .bolt, expression: .focused)
        case .subsessionSpawning: return AvatarStateDescriptor(state: .subsessionSpawning, label: "Child Bot Spawning", group: .toolHarnessExecution, preset: .opencodeRouting, shape: .spark, expression: .happy)
        case .browserEvaluating: return AvatarStateDescriptor(state: .browserEvaluating, label: "Layout Evaluator", group: .toolHarnessExecution, preset: .thinking, shape: .squircle, expression: .curious)
        case .vpsDeploying: return AvatarStateDescriptor(state: .vpsDeploying, label: "VPS Deploying", group: .toolHarnessExecution, preset: .codexRouting, shape: .bolt, expression: .focused)
        case .macAutomating: return AvatarStateDescriptor(state: .macAutomating, label: "Mac UI Automating", group: .toolHarnessExecution, preset: .piCoding, shape: .squircle, expression: .focused)
        case .iotSignaling: return AvatarStateDescriptor(state: .iotSignaling, label: "IoT MQTT Signal", group: .toolHarnessExecution, preset: .byokStreaming, shape: .spark, expression: .happy)
        case .gitCommitting: return AvatarStateDescriptor(state: .gitCommitting, label: "PR Shipping", group: .toolHarnessExecution, preset: .evolving, shape: .shield, expression: .proud)

        // Group 4: Cue & Needs-You Alert (10)
        case .manusCue: return AvatarStateDescriptor(state: .manusCue, label: "Manus Cue Ready", group: .cueNeedsYouAlert, preset: .manusCue, shape: .spark, expression: .curious)
        case .cueWhispering: return AvatarStateDescriptor(state: .cueWhispering, label: "Cue Whispering", group: .cueNeedsYouAlert, preset: .manusCue, shape: .cloud, expression: .happy)
        case .cueWindowMatched: return AvatarStateDescriptor(state: .cueWindowMatched, label: "Window Context Lock", group: .cueNeedsYouAlert, preset: .manusCue, shape: .squircle, expression: .listening)
        case .needsYou: return AvatarStateDescriptor(state: .needsYou, label: "Needs You Inbox", group: .cueNeedsYouAlert, preset: .needsYou, shape: .shield, expression: .alert)
        case .needsYouUrgent: return AvatarStateDescriptor(state: .needsYouUrgent, label: "Urgent Escalation", group: .cueNeedsYouAlert, preset: .needsYou, shape: .bolt, expression: .alert)
        case .needsYouApproval: return AvatarStateDescriptor(state: .needsYouApproval, label: "Approve PR / Deploy", group: .cueNeedsYouAlert, preset: .needsYou, shape: .shield, expression: .curious)
        case .needsYouDiffReady: return AvatarStateDescriptor(state: .needsYouDiffReady, label: "R2 Evidence Ready", group: .cueNeedsYouAlert, preset: .manusCue, shape: .terminal, expression: .proud)
        case .fleetDegraded: return AvatarStateDescriptor(state: .fleetDegraded, label: "Fleet Node Degraded", group: .cueNeedsYouAlert, preset: .needsYou, shape: .bolt, expression: .alert)
        case .tunnelReconnecting: return AvatarStateDescriptor(state: .tunnelReconnecting, label: "Cloudflare Reconnect", group: .cueNeedsYouAlert, preset: .thinking, shape: .cloud, expression: .curious)
        case .voiceInterrupted: return AvatarStateDescriptor(state: .voiceInterrupted, label: "Voice Interrupt", group: .cueNeedsYouAlert, preset: .byokStreaming, shape: .orb, expression: .listening)

        // Group 5: Self-Evolution & Dreaming (8)
        case .evolving: return AvatarStateDescriptor(state: .evolving, label: "Self-Evolving", group: .selfEvolutionDreaming, preset: .evolving, shape: .spark, expression: .evolving)
        case .sleeping: return AvatarStateDescriptor(state: .sleeping, label: "Nightly Sleep", group: .selfEvolutionDreaming, preset: .sleeping, shape: .dream, expression: .sleepy)
        case .dreamingConsolidating: return AvatarStateDescriptor(state: .dreamingConsolidating, label: "Dream Consolidate", group: .selfEvolutionDreaming, preset: .sleeping, shape: .dream, expression: .sleepy)
        case .skillSynthesizing: return AvatarStateDescriptor(state: .skillSynthesizing, label: "Skill Synthesis", group: .selfEvolutionDreaming, preset: .evolving, shape: .terminal, expression: .evolving)
        case .personaUpdating: return AvatarStateDescriptor(state: .personaUpdating, label: "USER.md Refining", group: .selfEvolutionDreaming, preset: .evolving, shape: .orb, expression: .happy)
        case .memoryPruning: return AvatarStateDescriptor(state: .memoryPruning, label: "Memory Superseding", group: .selfEvolutionDreaming, preset: .thinking, shape: .dream, expression: .focused)
        case .r2BackingUp: return AvatarStateDescriptor(state: .r2BackingUp, label: "R2 Encrypted Sync", group: .selfEvolutionDreaming, preset: .idle, shape: .shield, expression: .neutral)
        case .evolutionProud: return AvatarStateDescriptor(state: .evolutionProud, label: "Understanding +1%", group: .selfEvolutionDreaming, preset: .evolving, shape: .spark, expression: .proud)
        }
    }
}
