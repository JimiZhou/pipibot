import AppKit
import CoreGraphics
import PipiBotKit
import SceneKit
import SwiftUI
import os

// MARK: - Snapshot Types Crossing MainActor <-> SceneKit Render Loop

public enum PipiHomeBotVisualState: String, Sendable, Equatable {
    case idle
    case working
    case needsYou
    case collaborating
}

public struct PipiHomeBotSyncItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let accent: PipiPersonaAccent
    public let motif: PipiPersonaMotif
    public let state: PipiHomeBotVisualState

    public init(
        id: String,
        displayName: String,
        accent: PipiPersonaAccent,
        motif: PipiPersonaMotif,
        state: PipiHomeBotVisualState
    ) {
        self.id = id
        self.displayName = displayName
        self.accent = accent
        self.motif = motif
        self.state = state
    }
}

public struct PipiHomeProjectedBadge: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let accent: PipiPersonaAccent
    public let state: PipiHomeBotVisualState
    public let screenPoint: CGPoint
    public let isSelected: Bool
    public let isHovered: Bool

    public init(
        id: String,
        displayName: String,
        accent: PipiPersonaAccent,
        state: PipiHomeBotVisualState,
        screenPoint: CGPoint,
        isSelected: Bool,
        isHovered: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.accent = accent
        self.state = state
        self.screenPoint = screenPoint
        self.isSelected = isSelected
        self.isHovered = isHovered
    }
}

@MainActor
@Observable
public final class PipiHomeSceneBridgeState {
    public var projectedBadges: [PipiHomeProjectedBadge] = []
    public var hoveredBotId: String? = nil
    var onSelectBot: ((String?) -> Void)?

    public init() {}
}

// MARK: - SceneKit NSViewRepresentable Wrapper

struct PipiHomeSceneRepresentable: NSViewRepresentable {
    let bots: [PipiHomeBotSyncItem]
    let selectedBotId: String?
    let isDark: Bool
    let reduceMotion: Bool
    let resetCameraTrigger: Int
    let viewSize: CGSize
    let bridgeState: PipiHomeSceneBridgeState
    let onSelectBot: (String?) -> Void

    func makeCoordinator() -> PipiHomeSceneCoordinator {
        PipiHomeSceneCoordinator(bridgeState: bridgeState)
    }

    func makeNSView(context: Context) -> PipiHomeSCNView {
        bridgeState.onSelectBot = onSelectBot
        let scnView = PipiHomeSCNView()
        scnView.coordinator = context.coordinator
        scnView.wantsLayer = true
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        scnView.rendersContinuously = true
        scnView.preferredFramesPerSecond = 60
        scnView.scene = context.coordinator.scene
        scnView.pointOfView = context.coordinator.cameraNode
        scnView.delegate = context.coordinator
        context.coordinator.updateSnapshot(
            bots: bots,
            selectedBotId: selectedBotId,
            isDark: isDark,
            reduceMotion: reduceMotion,
            resetCameraTrigger: resetCameraTrigger,
            viewSize: viewSize
        )
        return scnView
    }

    func updateNSView(_ nsView: PipiHomeSCNView, context: Context) {
        bridgeState.onSelectBot = onSelectBot
        context.coordinator.updateSnapshot(
            bots: bots,
            selectedBotId: selectedBotId,
            isDark: isDark,
            reduceMotion: reduceMotion,
            resetCameraTrigger: resetCameraTrigger,
            viewSize: viewSize
        )
    }
}

// MARK: - Custom SCNView for Orbit, Zoom, Hover, and Hit Testing

final class PipiHomeSCNView: SCNView {
    weak var coordinator: PipiHomeSceneCoordinator?

    private var trackingAreaRef: NSTrackingArea?
    private var mouseDownPoint: NSPoint?
    private var lastDragPoint: NSPoint?
    private var didDrag: Bool = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        mouseDownPoint = pt
        lastDragPoint = pt
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard let last = lastDragPoint, let down = mouseDownPoint else { return }
        let dx = pt.x - last.x
        let dy = pt.y - last.y
        lastDragPoint = pt

        let totalDist = hypot(pt.x - down.x, pt.y - down.y)
        if totalDist > 3.5 {
            didDrag = true
        }
        coordinator?.orbitCamera(deltaX: dx, deltaY: dy)
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        defer {
            mouseDownPoint = nil
            lastDragPoint = nil
            didDrag = false
        }
        guard !didDrag else { return }

        if event.clickCount == 2 {
            let hitBot = hitTestBotId(at: pt)
            if hitBot == nil {
                coordinator?.resetCameraAnimated()
                return
            }
        }
        let hitBot = hitTestBotId(at: pt)
        coordinator?.handleClick(botId: hitBot)
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let hitBot = hitTestBotId(at: pt)
        coordinator?.handleHover(botId: hitBot)
        if hitBot != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        coordinator?.handleHover(botId: nil)
        NSCursor.arrow.set()
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.035 : event.scrollingDeltaY * 0.25
        coordinator?.zoomCamera(delta: delta)
    }

    override func magnify(with event: NSEvent) {
        coordinator?.zoomCamera(delta: event.magnification * 6.0)
    }

    private func hitTestBotId(at point: NSPoint) -> String? {
        let options: [SCNHitTestOption: Any] = [
            .searchMode: SCNHitTestSearchMode.all.rawValue,
            .ignoreHiddenNodes: true
        ]
        let results = hitTest(point, options: options)
        for result in results {
            var current: SCNNode? = result.node
            while let node = current {
                if let name = node.name, name.hasPrefix("bot_rig:") {
                    return String(name.dropFirst("bot_rig:".count))
                }
                current = node.parent
            }
        }
        return nil
    }
}

// MARK: - SceneKit Procedural Engine & 60fps Locomotion Coordinator

final class PipiHomeSceneCoordinator: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    let scene: SCNScene
    let cameraNode: SCNNode

    private let bridgeState: PipiHomeSceneBridgeState

    // Camera Rig
    private let cameraPivotNode = SCNNode()
    private let cameraArmNode = SCNNode()
    private var currentYaw: CGFloat = 0.58       // ~33 deg isometric angle
    private var currentPitch: CGFloat = 0.61     // ~35 deg elevation
    private var currentDistance: CGFloat = 11.4

    private static let defaultYaw: CGFloat = 0.58
    private static let defaultPitch: CGFloat = 0.61
    private static let defaultDistance: CGFloat = 11.4

    // Scene Dynamic Nodes (Theme & State Sensitive)
    private let roomRootNode = SCNNode()
    private let botsContainerNode = SCNNode()
    private let collabArcsNode = SCNNode()

    private var ambientLightNode = SCNNode()
    private var keyLightNode = SCNNode()
    private var fillLightNode = SCNNode()
    private var windowLightNode = SCNNode()
    private var deskLampLightNode = SCNNode()
    private var monitorGlowLightNode = SCNNode()

    private var windowBackdropNode = SCNNode()
    private var windowStarsNode = SCNNode()
    private var windowMoonNode = SCNNode()
    private var sunBeamNode = SCNNode()
    private var monitorScreenMaterial = SCNMaterial()
    private var collabTableRingMaterial = SCNMaterial()
    private var floorPlankMaterials: [SCNMaterial] = []
    private var wallMaterial = SCNMaterial()
    private var baseboardMaterial = SCNMaterial()
    private var rugMaterial = SCNMaterial()
    private var rugTrimMaterial = SCNMaterial()
    private var sofaMaterial = SCNMaterial()

    // Synchronized Input Snapshot
    private struct InputSnapshot: Sendable {
        var bots: [PipiHomeBotSyncItem] = []
        var selectedBotId: String? = nil
        var hoveredBotId: String? = nil
        var isDark: Bool = false
        var reduceMotion: Bool = false
        var needsBotSync: Bool = false
        var needsThemeSync: Bool = false
        var targetYaw: CGFloat = PipiHomeSceneCoordinator.defaultYaw
        var targetPitch: CGFloat = PipiHomeSceneCoordinator.defaultPitch
        var targetDistance: CGFloat = PipiHomeSceneCoordinator.defaultDistance
        var viewSize: CGSize = .zero
    }

    private let stateLock = OSAllocatedUnfairLock(initialState: InputSnapshot())
    private let projectionLock = OSAllocatedUnfairLock<Bool>(initialState: false)
    private var lastResetTrigger: Int = 0
    private var lastAppliedThemeDark: Bool? = nil
    private var lastProjectedSummary: [PipiHomeProjectedBadge] = []

    // Per-Bot Runtime Simulation State (accessed on render loop)
    private final class BotRig {
        let id: String
        let rootNode: SCNNode
        let bodyGroupNode: SCNNode
        let headGroupNode: SCNNode
        let leftFootNode: SCNNode
        let rightFootNode: SCNNode
        let leftEyeMaterial: SCNMaterial
        let rightEyeMaterial: SCNMaterial
        let chassisMaterial: SCNMaterial
        let trimMaterial: SCNMaterial
        let visorMaterial: SCNMaterial
        let floorRingNode: SCNNode
        let floorRingMaterial: SCNMaterial
        let shadowNode: SCNNode
        let alertBeaconNode: SCNNode
        let miniHoloNode: SCNNode
        let orbitRingNode: SCNNode

        var accent: PipiPersonaAccent
        var motif: PipiPersonaMotif
        var visualState: PipiHomeBotVisualState
        var position: SIMD3<Float>
        var heading: Float
        var walkTarget: SIMD3<Float>
        var pauseTimer: TimeInterval
        var phaseOffset: Double
        var currentScaleRing: Float = 1.0

        init(
            id: String,
            rootNode: SCNNode,
            bodyGroupNode: SCNNode,
            headGroupNode: SCNNode,
            leftFootNode: SCNNode,
            rightFootNode: SCNNode,
            leftEyeMaterial: SCNMaterial,
            rightEyeMaterial: SCNMaterial,
            chassisMaterial: SCNMaterial,
            trimMaterial: SCNMaterial,
            visorMaterial: SCNMaterial,
            floorRingNode: SCNNode,
            floorRingMaterial: SCNMaterial,
            shadowNode: SCNNode,
            alertBeaconNode: SCNNode,
            miniHoloNode: SCNNode,
            orbitRingNode: SCNNode,
            accent: PipiPersonaAccent,
            motif: PipiPersonaMotif,
            visualState: PipiHomeBotVisualState,
            position: SIMD3<Float>,
            heading: Float,
            phaseOffset: Double
        ) {
            self.id = id
            self.rootNode = rootNode
            self.bodyGroupNode = bodyGroupNode
            self.headGroupNode = headGroupNode
            self.leftFootNode = leftFootNode
            self.rightFootNode = rightFootNode
            self.leftEyeMaterial = leftEyeMaterial
            self.rightEyeMaterial = rightEyeMaterial
            self.chassisMaterial = chassisMaterial
            self.trimMaterial = trimMaterial
            self.visorMaterial = visorMaterial
            self.floorRingNode = floorRingNode
            self.floorRingMaterial = floorRingMaterial
            self.shadowNode = shadowNode
            self.alertBeaconNode = alertBeaconNode
            self.miniHoloNode = miniHoloNode
            self.orbitRingNode = orbitRingNode
            self.accent = accent
            self.motif = motif
            self.visualState = visualState
            self.position = position
            self.heading = heading
            self.walkTarget = position
            self.pauseTimer = 1.5 + phaseOffset.truncatingRemainder(dividingBy: 2.5)
            self.phaseOffset = phaseOffset
        }
    }

    private var botRigs: [String: BotRig] = [:]
    private var lastFrameTime: TimeInterval?
    private var collabArcSegments: [(node: SCNNode, pulseNodes: [SCNNode], start: SIMD3<Float>, end: SIMD3<Float>, accent: PipiPersonaAccent)] = []

    // Curated Idle Waypoints across the cozy living room (avoiding furniture collision)
    private let idleWaypoints: [SIMD3<Float>] = [
        SIMD3<Float>(-1.75, 0, -0.35), // Near sofa & rug
        SIMD3<Float>(-2.85, 0, 0.85),  // Near sunlit window
        SIMD3<Float>(-1.45, 0, 2.25),  // Front-left lounge rug
        SIMD3<Float>(0.15, 0, 2.55),   // Front-center greeting area
        SIMD3<Float>(1.85, 0, 2.15),   // Front-right studio area
        SIMD3<Float>(2.95, 0, 0.65),   // Right side open floor
        SIMD3<Float>(0.35, 0, -1.85),  // Near bookshelf
        SIMD3<Float>(-0.95, 0, -1.35)  // Between sofa and bookshelf
    ]

    init(bridgeState: PipiHomeSceneBridgeState) {
        self.scene = SCNScene()
        self.cameraNode = SCNNode()
        self.bridgeState = bridgeState
        super.init()

        setupCamera()
        setupLights()
        buildCozyHomeDiorama()
        scene.rootNode.addChildNode(botsContainerNode)
        scene.rootNode.addChildNode(collabArcsNode)
        applyTheme(isDark: false)
    }

    // MARK: - MainActor -> Render Loop Sync

    @MainActor
    func updateSnapshot(
        bots: [PipiHomeBotSyncItem],
        selectedBotId: String?,
        isDark: Bool,
        reduceMotion: Bool,
        resetCameraTrigger: Int,
        viewSize: CGSize
    ) {
        if resetCameraTrigger != lastResetTrigger {
            lastResetTrigger = resetCameraTrigger
            resetCameraAnimated()
        }

        stateLock.withLock { snap in
            let botsChanged = snap.bots != bots
            let themeChanged = snap.isDark != isDark
            snap.bots = bots
            snap.selectedBotId = selectedBotId
            snap.isDark = isDark
            snap.reduceMotion = reduceMotion
            snap.viewSize = viewSize
            if botsChanged { snap.needsBotSync = true }
            if themeChanged { snap.needsThemeSync = true }
        }
    }

    func orbitCamera(deltaX: CGFloat, deltaY: CGFloat) {
        stateLock.withLock { snap in
            snap.targetYaw = clamp(snap.targetYaw - deltaX * 0.0065, min: -0.22, max: 1.32)
            snap.targetPitch = clamp(snap.targetPitch + deltaY * 0.0055, min: 0.34, max: 1.15)
        }
    }

    func zoomCamera(delta: CGFloat) {
        stateLock.withLock { snap in
            snap.targetDistance = clamp(snap.targetDistance - delta * 0.45, min: 6.8, max: 16.5)
        }
    }

    func resetCameraAnimated() {
        stateLock.withLock { snap in
            snap.targetYaw = Self.defaultYaw
            snap.targetPitch = Self.defaultPitch
            snap.targetDistance = Self.defaultDistance
        }
    }

    func handleClick(botId: String?) {
        let bridge = bridgeState
        Task { @MainActor in
            bridge.onSelectBot?(botId)
        }
    }

    func handleHover(botId: String?) {
        stateLock.withLock { snap in
            snap.hoveredBotId = botId
        }
        let bridge = bridgeState
        Task { @MainActor in
            if bridge.hoveredBotId != botId {
                bridge.hoveredBotId = botId
            }
        }
    }

    // MARK: - Camera & Lighting Setup

    private func setupCamera() {
        cameraPivotNode.position = SCNVector3(0.0, 0.72, -0.35)
        scene.rootNode.addChildNode(cameraPivotNode)

        let cam = SCNCamera()
        cam.fieldOfView = 34
        cam.zNear = 0.5
        cam.zFar = 60.0
        cam.wantsHDR = true
        cam.bloomIntensity = 0.28
        cam.bloomThreshold = 0.85
        cam.bloomBlurRadius = 8.0
        cameraNode.camera = cam

        cameraPivotNode.addChildNode(cameraArmNode)
        cameraArmNode.addChildNode(cameraNode)
        applyCameraTransform()
    }

    private func applyCameraTransform() {
        let yaw = Float(currentYaw)
        let pitch = Float(currentPitch)
        let dist = Float(currentDistance)

        let x = dist * cos(pitch) * sin(yaw)
        let y = dist * sin(pitch)
        let z = dist * cos(pitch) * cos(yaw)

        cameraNode.position = SCNVector3(x, y, z)
        cameraNode.look(at: SCNVector3(0, 0, 0))
    }

    private func setupLights() {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 420
        ambientLightNode.light = ambient
        scene.rootNode.addChildNode(ambientLightNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 920
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowColor = NSColor(srgbRed: 0.05, green: 0.06, blue: 0.10, alpha: 0.28)
        key.shadowRadius = 4.5
        key.shadowSampleCount = 8
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.orthographicScale = 7.5
        key.zNear = 1.0
        key.zFar = 28.0
        keyLightNode.light = key
        keyLightNode.position = SCNVector3(6.5, 9.5, 6.0)
        keyLightNode.look(at: SCNVector3(0, 0.3, -0.3))
        scene.rootNode.addChildNode(keyLightNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 280
        fillLightNode.light = fill
        fillLightNode.position = SCNVector3(-7.0, 5.5, 5.5)
        fillLightNode.look(at: SCNVector3(0, 0.5, 0))
        scene.rootNode.addChildNode(fillLightNode)

        // Window directional/spot accent light
        let winLight = SCNLight()
        winLight.type = .spot
        winLight.spotInnerAngle = 28
        winLight.spotOuterAngle = 72
        winLight.intensity = 700
        winLight.attenuationStartDistance = 1.5
        winLight.attenuationEndDistance = 10.0
        windowLightNode.light = winLight
        windowLightNode.position = SCNVector3(-4.2, 2.35, -0.7)
        windowLightNode.look(at: SCNVector3(-0.8, 0.0, 0.35))
        scene.rootNode.addChildNode(windowLightNode)

        // Desk lamp pool light
        let lampLight = SCNLight()
        lampLight.type = .omni
        lampLight.intensity = 450
        lampLight.attenuationStartDistance = 0.2
        lampLight.attenuationEndDistance = 4.2
        deskLampLightNode.light = lampLight
        deskLampLightNode.position = SCNVector3(3.15, 1.58, -2.45)
        scene.rootNode.addChildNode(deskLampLightNode)

        // Monitor cobalt/cyan glow light (intensified when a bot is working)
        let monLight = SCNLight()
        monLight.type = .omni
        monLight.intensity = 140
        monLight.attenuationStartDistance = 0.1
        monLight.attenuationEndDistance = 3.0
        monitorGlowLightNode.light = monLight
        monitorGlowLightNode.position = SCNVector3(2.35, 1.45, -2.35)
        scene.rootNode.addChildNode(monitorGlowLightNode)
    }

    // MARK: - 100% Procedural Cozy Home Diorama

    private func buildCozyHomeDiorama() {
        scene.rootNode.addChildNode(roomRootNode)

        // 1. Floor Base Plinth + Wood Floor Planks
        let plinthGeo = SCNBox(width: 9.44, height: 0.26, length: 8.64, chamferRadius: 0.08)
        let plinthMat = makePBRMaterial(color: NSColor(srgbRed: 0.22, green: 0.18, blue: 0.15, alpha: 1), roughness: 0.85)
        plinthGeo.materials = [plinthMat]
        let plinthNode = SCNNode(geometry: plinthGeo)
        plinthNode.position = SCNVector3(0, -0.14, 0)
        roomRootNode.addChildNode(plinthNode)

        buildWoodFloorPlanks()

        // 2. Soft Woven Area Rug (Center-Front)
        let rugGeo = SCNBox(width: 4.5, height: 0.024, length: 3.5, chamferRadius: 0.012)
        rugMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.90, green: 0.87, blue: 0.82, alpha: 1), roughness: 0.95)
        rugGeo.materials = [rugMaterial]
        let rugNode = SCNNode(geometry: rugGeo)
        rugNode.position = SCNVector3(0.0, 0.012, 0.85)
        roomRootNode.addChildNode(rugNode)

        let rugBorderGeo = SCNBox(width: 4.66, height: 0.018, length: 3.66, chamferRadius: 0.01)
        rugTrimMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.72, green: 0.67, blue: 0.60, alpha: 1), roughness: 0.92)
        rugBorderGeo.materials = [rugTrimMaterial]
        let rugBorderNode = SCNNode(geometry: rugBorderGeo)
        rugBorderNode.position = SCNVector3(0.0, 0.009, 0.85)
        roomRootNode.addChildNode(rugBorderNode)

        // 3. Architectural L-Shaped Walls + Baseboards
        wallMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.93, green: 0.91, blue: 0.88, alpha: 1), roughness: 0.88)
        baseboardMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.97, green: 0.96, blue: 0.94, alpha: 1), roughness: 0.65)

        // Back wall (z = -4.2)
        let backWallGeo = SCNBox(width: 9.44, height: 3.65, length: 0.24, chamferRadius: 0.03)
        backWallGeo.materials = [wallMaterial]
        let backWallNode = SCNNode(geometry: backWallGeo)
        backWallNode.position = SCNVector3(0, 1.825, -4.2)
        roomRootNode.addChildNode(backWallNode)

        // Back baseboard
        let backBaseGeo = SCNBox(width: 9.20, height: 0.18, length: 0.05, chamferRadius: 0.01)
        backBaseGeo.materials = [baseboardMaterial]
        let backBaseNode = SCNNode(geometry: backBaseGeo)
        backBaseNode.position = SCNVector3(0.1, 0.09, -4.06)
        roomRootNode.addChildNode(backBaseNode)

        // Left wall (x = -4.6)
        let leftWallGeo = SCNBox(width: 0.24, height: 3.65, length: 8.64, chamferRadius: 0.03)
        leftWallGeo.materials = [wallMaterial]
        let leftWallNode = SCNNode(geometry: leftWallGeo)
        leftWallNode.position = SCNVector3(-4.6, 1.825, 0)
        roomRootNode.addChildNode(leftWallNode)

        // Left baseboard
        let leftBaseGeo = SCNBox(width: 0.05, height: 0.18, length: 8.40, chamferRadius: 0.01)
        leftBaseGeo.materials = [baseboardMaterial]
        let leftBaseNode = SCNNode(geometry: leftBaseGeo)
        leftBaseNode.position = SCNVector3(-4.46, 0.09, 0.1)
        roomRootNode.addChildNode(leftBaseNode)

        // 4. Window on Left Wall (Daylight / Starry Twilight)
        buildWindowOnLeftWall()

        // 5. Workstation Desk Zone (Back-Right)
        buildWorkstationDesk()

        // 6. Cozy Lounge Zone (Back-Left: Sofa, Side Table with Mug, Tall Potted Plant, Bookshelf)
        buildCozyLounge()

        // 7. Swarm Collaboration Round Table (Center-Front Rug Zone)
        buildCollaborationTable()
    }

    private func buildWoodFloorPlanks() {
        let plankCount = 14
        let totalWidth: CGFloat = 9.2
        let plankWidth = totalWidth / CGFloat(plankCount)
        let plankLength: CGFloat = 8.4

        floorPlankMaterials = (0..<4).map { idx in
            let delta = CGFloat(idx) * 0.025
            return makePBRMaterial(
                color: NSColor(srgbRed: 0.72 - delta, green: 0.56 - delta * 0.8, blue: 0.40 - delta * 0.6, alpha: 1),
                roughness: 0.58,
                metalness: 0.04
            )
        }

        for i in 0..<plankCount {
            let x = -totalWidth * 0.5 + plankWidth * (CGFloat(i) + 0.5)
            // Split each column into 2 staggered planks for authentic parquet/plank seams
            let splitOffset = (i % 2 == 0) ? 0.8 : -0.9
            let lenA = plankLength * 0.5 + splitOffset
            let lenB = plankLength - lenA

            let geoA = SCNBox(width: plankWidth - 0.022, height: 0.03, length: lenA - 0.02, chamferRadius: 0.005)
            geoA.materials = [floorPlankMaterials[i % floorPlankMaterials.count]]
            let nodeA = SCNNode(geometry: geoA)
            nodeA.position = SCNVector3(Float(x), -0.015, Float(-plankLength * 0.5 + lenA * 0.5))
            roomRootNode.addChildNode(nodeA)

            let geoB = SCNBox(width: plankWidth - 0.022, height: 0.03, length: lenB - 0.02, chamferRadius: 0.005)
            geoB.materials = [floorPlankMaterials[(i + 2) % floorPlankMaterials.count]]
            let nodeB = SCNNode(geometry: geoB)
            nodeB.position = SCNVector3(Float(x), -0.015, Float(plankLength * 0.5 - lenB * 0.5))
            roomRootNode.addChildNode(nodeB)
        }
    }

    private func buildWindowOnLeftWall() {
        let windowGroup = SCNNode()
        windowGroup.position = SCNVector3(-4.46, 1.95, -0.7)
        roomRootNode.addChildNode(windowGroup)

        let frameMat = makePBRMaterial(color: NSColor(srgbRed: 0.96, green: 0.95, blue: 0.93, alpha: 1), roughness: 0.45)

        // Outer frame
        let topBar = SCNNode(geometry: SCNBox(width: 0.14, height: 0.10, length: 2.30, chamferRadius: 0.015))
        topBar.geometry?.materials = [frameMat]
        topBar.position = SCNVector3(0, 0.85, 0)
        windowGroup.addChildNode(topBar)

        let sillBar = SCNNode(geometry: SCNBox(width: 0.24, height: 0.09, length: 2.46, chamferRadius: 0.018))
        sillBar.geometry?.materials = [frameMat]
        sillBar.position = SCNVector3(0.05, -0.85, 0)
        windowGroup.addChildNode(sillBar)

        for zOff in [-1.10, 0.0, 1.10] as [Float] {
            let post = SCNNode(geometry: SCNBox(width: 0.12, height: 1.70, length: zOff == 0 ? 0.06 : 0.10, chamferRadius: 0.01))
            post.geometry?.materials = [frameMat]
            post.position = SCNVector3(0, 0, zOff)
            windowGroup.addChildNode(post)
        }
        let midCross = SCNNode(geometry: SCNBox(width: 0.10, height: 0.06, length: 2.20, chamferRadius: 0.01))
        midCross.geometry?.materials = [frameMat]
        windowGroup.addChildNode(midCross)

        // Sky backdrop panel inside window
        let skyPlane = SCNPlane(width: 2.12, height: 1.62)
        let skyMat = SCNMaterial()
        skyMat.lightingModel = .constant
        skyPlane.materials = [skyMat]
        windowBackdropNode = SCNNode(geometry: skyPlane)
        windowBackdropNode.eulerAngles = SCNVector3(0, Float.pi * 0.5, 0)
        windowBackdropNode.position = SCNVector3(-0.02, 0, 0)
        windowGroup.addChildNode(windowBackdropNode)

        // Procedural stars + crescent moon for Dark Mode twilight
        windowStarsNode = SCNNode()
        let starMat = SCNMaterial()
        starMat.lightingModel = .constant
        starMat.diffuse.contents = NSColor(srgbRed: 0.95, green: 0.97, blue: 1.0, alpha: 0.95)
        let starCoords: [(Float, Float, CGFloat)] = [
            (0.45, -0.65, 0.022), (0.55, 0.35, 0.018), (0.28, 0.72, 0.025),
            (0.62, -0.18, 0.015), (-0.18, 0.55, 0.020), (-0.35, -0.45, 0.016),
            (0.15, -0.78, 0.019), (0.42, 0.85, 0.016), (-0.42, 0.22, 0.015)
        ]
        for (sy, sz, sr) in starCoords {
            let dot = SCNNode(geometry: SCNSphere(radius: sr))
            dot.geometry?.materials = [starMat]
            dot.position = SCNVector3(0.01, sy, sz)
            windowStarsNode.addChildNode(dot)
        }
        windowGroup.addChildNode(windowStarsNode)

        let moonGeo = SCNSphere(radius: 0.13)
        let moonMat = SCNMaterial()
        moonMat.lightingModel = .constant
        moonMat.diffuse.contents = NSColor(srgbRed: 0.99, green: 0.93, blue: 0.76, alpha: 1.0)
        moonGeo.materials = [moonMat]
        windowMoonNode = SCNNode(geometry: moonGeo)
        windowMoonNode.position = SCNVector3(0.01, 0.42, -0.58)
        windowGroup.addChildNode(windowMoonNode)

        // Subtle warm light shaft on floor (visible in Light Mode)
        let beamPlane = SCNPlane(width: 2.1, height: 3.1)
        let beamMat = SCNMaterial()
        beamMat.lightingModel = .constant
        beamMat.diffuse.contents = NSColor(srgbRed: 1.0, green: 0.95, blue: 0.82, alpha: 0.16)
        beamMat.isDoubleSided = true
        beamMat.writesToDepthBuffer = false
        beamPlane.materials = [beamMat]
        sunBeamNode = SCNNode(geometry: beamPlane)
        sunBeamNode.position = SCNVector3(-3.0, 0.02, -0.65)
        sunBeamNode.eulerAngles = SCNVector3(-Float.pi * 0.5, 0.15, 0)
        roomRootNode.addChildNode(sunBeamNode)

        // Tiny succulent pot on the window sill
        let miniPot = SCNNode(geometry: SCNCylinder(radius: 0.09, height: 0.13))
        miniPot.geometry?.materials = [makePBRMaterial(color: NSColor(srgbRed: 0.82, green: 0.48, blue: 0.36, alpha: 1), roughness: 0.75)]
        miniPot.position = SCNVector3(0.05, -0.74, 0.65)
        windowGroup.addChildNode(miniPot)

        let succulentMat = makePBRMaterial(color: NSColor(srgbRed: 0.25, green: 0.62, blue: 0.42, alpha: 1), roughness: 0.6)
        for angle in stride(from: 0.0, to: Double.pi * 2.0, by: Double.pi / 3.0) {
            let leaf = SCNNode(geometry: SCNSphere(radius: 0.055))
            leaf.scale = SCNVector3(1.0, 0.55, 1.45)
            leaf.geometry?.materials = [succulentMat]
            leaf.position = SCNVector3(0.05 + Float(cos(angle)) * 0.045, -0.65, 0.65 + Float(sin(angle)) * 0.045)
            leaf.eulerAngles = SCNVector3(0, Float(-angle), 0)
            windowGroup.addChildNode(leaf)
        }
    }

    private func buildWorkstationDesk() {
        let deskGroup = SCNNode()
        deskGroup.position = SCNVector3(2.35, 0, -2.55)
        roomRootNode.addChildNode(deskGroup)

        let woodMat = makePBRMaterial(color: NSColor(srgbRed: 0.52, green: 0.37, blue: 0.25, alpha: 1), roughness: 0.45)
        let metalMat = makePBRMaterial(color: NSColor(srgbRed: 0.22, green: 0.25, blue: 0.30, alpha: 1), roughness: 0.32, metalness: 0.75)
        let aluminumMat = makePBRMaterial(color: NSColor(srgbRed: 0.78, green: 0.81, blue: 0.85, alpha: 1), roughness: 0.28, metalness: 0.80)

        // Tabletop
        let top = SCNNode(geometry: SCNBox(width: 2.50, height: 0.08, length: 1.18, chamferRadius: 0.025))
        top.geometry?.materials = [woodMat]
        top.position = SCNVector3(0, 0.90, 0)
        deskGroup.addChildNode(top)

        // 4 Desk Legs
        for lx in [-1.12, 1.12] as [Float] {
            for lz in [-0.48, 0.48] as [Float] {
                let leg = SCNNode(geometry: SCNCylinder(radius: 0.036, height: 0.88))
                leg.geometry?.materials = [metalMat]
                leg.position = SCNVector3(lx, 0.44, lz)
                deskGroup.addChildNode(leg)
            }
        }

        // Studio Monitor Stand & Bezel
        let standFoot = SCNNode(geometry: SCNBox(width: 0.38, height: 0.024, length: 0.26, chamferRadius: 0.01))
        standFoot.geometry?.materials = [aluminumMat]
        standFoot.position = SCNVector3(-0.08, 0.952, -0.24)
        deskGroup.addChildNode(standFoot)

        let standNeck = SCNNode(geometry: SCNBox(width: 0.08, height: 0.28, length: 0.04, chamferRadius: 0.01))
        standNeck.geometry?.materials = [aluminumMat]
        standNeck.position = SCNVector3(-0.08, 1.09, -0.30)
        deskGroup.addChildNode(standNeck)

        let monitorBezel = SCNNode(geometry: SCNBox(width: 1.18, height: 0.68, length: 0.045, chamferRadius: 0.02))
        monitorBezel.geometry?.materials = [metalMat]
        monitorBezel.position = SCNVector3(-0.08, 1.44, -0.26)
        deskGroup.addChildNode(monitorBezel)

        // Glowing Dual-Tone Monitor Screen
        let screenGeo = SCNPlane(width: 1.10, height: 0.60)
        monitorScreenMaterial.lightingModel = .constant
        monitorScreenMaterial.diffuse.contents = NSColor(srgbRed: 0.18, green: 0.38, blue: 0.72, alpha: 1)
        screenGeo.materials = [monitorScreenMaterial]
        let screenNode = SCNNode(geometry: screenGeo)
        screenNode.position = SCNVector3(-0.08, 1.44, -0.236)
        deskGroup.addChildNode(screenNode)

        // Keyboard + Trackpad
        let kb = SCNNode(geometry: SCNBox(width: 0.48, height: 0.018, length: 0.18, chamferRadius: 0.008))
        kb.geometry?.materials = [aluminumMat]
        kb.position = SCNVector3(-0.14, 0.95, 0.14)
        deskGroup.addChildNode(kb)

        let pad = SCNNode(geometry: SCNBox(width: 0.16, height: 0.014, length: 0.15, chamferRadius: 0.008))
        pad.geometry?.materials = [aluminumMat]
        pad.position = SCNVector3(0.24, 0.948, 0.15)
        deskGroup.addChildNode(pad)

        // Warm Desk Lamp
        let lampBase = SCNNode(geometry: SCNCylinder(radius: 0.12, height: 0.03))
        lampBase.geometry?.materials = [metalMat]
        lampBase.position = SCNVector3(0.88, 0.955, -0.26)
        deskGroup.addChildNode(lampBase)

        let lampStem = SCNNode(geometry: SCNCylinder(radius: 0.018, height: 0.48))
        lampStem.geometry?.materials = [aluminumMat]
        lampStem.position = SCNVector3(0.90, 1.18, -0.28)
        lampStem.eulerAngles = SCNVector3(0.18, 0, 0.14)
        deskGroup.addChildNode(lampStem)

        let lampShadeMat = makePBRMaterial(color: NSColor(srgbRed: 0.92, green: 0.78, blue: 0.56, alpha: 1), roughness: 0.42)
        let lampShade = SCNNode(geometry: SCNCone(topRadius: 0.07, bottomRadius: 0.17, height: 0.19))
        lampShade.geometry?.materials = [lampShadeMat]
        lampShade.position = SCNVector3(0.80, 1.42, -0.18)
        lampShade.eulerAngles = SCNVector3(0.22, 0, 0.25)
        deskGroup.addChildNode(lampShade)

        let bulbMat = SCNMaterial()
        bulbMat.lightingModel = .constant
        bulbMat.diffuse.contents = NSColor(srgbRed: 1.0, green: 0.90, blue: 0.66, alpha: 1)
        let bulb = SCNNode(geometry: SCNSphere(radius: 0.055))
        bulb.geometry?.materials = [bulbMat]
        bulb.position = SCNVector3(0.79, 1.35, -0.17)
        deskGroup.addChildNode(bulb)

        // Ergonomic Studio Chair (tucked slightly in front of desk)
        let chairGroup = SCNNode()
        chairGroup.position = SCNVector3(-0.05, 0, 0.85)
        deskGroup.addChildNode(chairGroup)

        let chairFabric = makePBRMaterial(color: NSColor(srgbRed: 0.26, green: 0.30, blue: 0.38, alpha: 1), roughness: 0.88)
        let chairSeat = SCNNode(geometry: SCNBox(width: 0.62, height: 0.11, length: 0.58, chamferRadius: 0.05))
        chairSeat.geometry?.materials = [chairFabric]
        chairSeat.position = SCNVector3(0, 0.52, 0)
        chairGroup.addChildNode(chairSeat)

        let chairBack = SCNNode(geometry: SCNBox(width: 0.58, height: 0.56, length: 0.10, chamferRadius: 0.045))
        chairBack.geometry?.materials = [chairFabric]
        chairBack.position = SCNVector3(0, 0.84, 0.24)
        chairBack.eulerAngles = SCNVector3(0.08, 0, 0)
        chairGroup.addChildNode(chairBack)

        let chairStem = SCNNode(geometry: SCNCylinder(radius: 0.04, height: 0.42))
        chairStem.geometry?.materials = [metalMat]
        chairStem.position = SCNVector3(0, 0.26, 0)
        chairGroup.addChildNode(chairStem)

        let chairBase = SCNNode(geometry: SCNCylinder(radius: 0.28, height: 0.04))
        chairBase.geometry?.materials = [metalMat]
        chairBase.position = SCNVector3(0, 0.04, 0)
        chairGroup.addChildNode(chairBase)
    }

    private func buildCozyLounge() {
        // 1. Soft Rounded Sofa (Back-Left)
        let sofaGroup = SCNNode()
        sofaGroup.position = SCNVector3(-2.55, 0, -2.55)
        sofaGroup.eulerAngles = SCNVector3(0, 0.24, 0)
        roomRootNode.addChildNode(sofaGroup)

        sofaMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.38, green: 0.46, blue: 0.56, alpha: 1), roughness: 0.90)
        let legWoodMat = makePBRMaterial(color: NSColor(srgbRed: 0.48, green: 0.34, blue: 0.22, alpha: 1), roughness: 0.55)

        let seatBase = SCNNode(geometry: SCNBox(width: 2.15, height: 0.32, length: 0.96, chamferRadius: 0.12))
        seatBase.geometry?.materials = [sofaMaterial]
        seatBase.position = SCNVector3(0, 0.28, 0)
        sofaGroup.addChildNode(seatBase)

        let backRest = SCNNode(geometry: SCNBox(width: 2.15, height: 0.62, length: 0.28, chamferRadius: 0.11))
        backRest.geometry?.materials = [sofaMaterial]
        backRest.position = SCNVector3(0, 0.60, -0.35)
        sofaGroup.addChildNode(backRest)

        for ax in [-0.95, 0.95] as [Float] {
            let arm = SCNNode(geometry: SCNBox(width: 0.26, height: 0.48, length: 0.96, chamferRadius: 0.10))
            arm.geometry?.materials = [sofaMaterial]
            arm.position = SCNVector3(ax, 0.42, 0)
            sofaGroup.addChildNode(arm)
        }

        // Accent throw pillows
        let pillowAMat = makePBRMaterial(color: NSColor(srgbRed: 0.90, green: 0.68, blue: 0.38, alpha: 1), roughness: 0.92)
        let pillowA = SCNNode(geometry: SCNBox(width: 0.36, height: 0.32, length: 0.14, chamferRadius: 0.06))
        pillowA.geometry?.materials = [pillowAMat]
        pillowA.position = SCNVector3(-0.66, 0.56, -0.14)
        pillowA.eulerAngles = SCNVector3(-0.22, 0.28, 0.10)
        sofaGroup.addChildNode(pillowA)

        let pillowBMat = makePBRMaterial(color: NSColor(srgbRed: 0.34, green: 0.72, blue: 0.80, alpha: 1), roughness: 0.92)
        let pillowB = SCNNode(geometry: SCNBox(width: 0.34, height: 0.30, length: 0.14, chamferRadius: 0.06))
        pillowB.geometry?.materials = [pillowBMat]
        pillowB.position = SCNVector3(0.68, 0.55, -0.14)
        pillowB.eulerAngles = SCNVector3(-0.20, -0.25, -0.08)
        sofaGroup.addChildNode(pillowB)

        for lx in [-0.88, 0.88] as [Float] {
            for lz in [-0.36, 0.36] as [Float] {
                let leg = SCNNode(geometry: SCNCylinder(radius: 0.04, height: 0.16))
                leg.geometry?.materials = [legWoodMat]
                leg.position = SCNVector3(lx, 0.08, lz)
                sofaGroup.addChildNode(leg)
            }
        }

        // 2. Side Table + Ceramic Mug
        let sideTableGroup = SCNNode()
        sideTableGroup.position = SCNVector3(-1.05, 0, -2.75)
        roomRootNode.addChildNode(sideTableGroup)

        let tableTop = SCNNode(geometry: SCNCylinder(radius: 0.36, height: 0.045))
        tableTop.geometry?.materials = [legWoodMat]
        tableTop.position = SCNVector3(0, 0.56, 0)
        sideTableGroup.addChildNode(tableTop)

        let tableLeg = SCNNode(geometry: SCNCylinder(radius: 0.04, height: 0.55))
        tableLeg.geometry?.materials = [legWoodMat]
        tableLeg.position = SCNVector3(0, 0.275, 0)
        sideTableGroup.addChildNode(tableLeg)

        let tableFoot = SCNNode(geometry: SCNCylinder(radius: 0.20, height: 0.03))
        tableFoot.geometry?.materials = [legWoodMat]
        tableFoot.position = SCNVector3(0, 0.015, 0)
        sideTableGroup.addChildNode(tableFoot)

        let mugMat = makePBRMaterial(color: NSColor(srgbRed: 0.96, green: 0.95, blue: 0.92, alpha: 1), roughness: 0.22)
        let mugBody = SCNNode(geometry: SCNCylinder(radius: 0.065, height: 0.12))
        mugBody.geometry?.materials = [mugMat]
        mugBody.position = SCNVector3(0.04, 0.64, 0.02)
        sideTableGroup.addChildNode(mugBody)

        let coffeeTop = SCNNode(geometry: SCNCylinder(radius: 0.056, height: 0.01))
        coffeeTop.geometry?.materials = [makePBRMaterial(color: NSColor(srgbRed: 0.32, green: 0.18, blue: 0.10, alpha: 1), roughness: 0.15)]
        coffeeTop.position = SCNVector3(0.04, 0.70, 0.02)
        sideTableGroup.addChildNode(coffeeTop)

        // 3. Tall Potted Plant (Back-Left Corner)
        let plantGroup = SCNNode()
        plantGroup.position = SCNVector3(-3.88, 0, -3.45)
        roomRootNode.addChildNode(plantGroup)

        let potMat = makePBRMaterial(color: NSColor(srgbRed: 0.80, green: 0.49, blue: 0.37, alpha: 1), roughness: 0.72)
        let pot = SCNNode(geometry: SCNCylinder(radius: 0.27, height: 0.48))
        pot.geometry?.materials = [potMat]
        pot.position = SCNVector3(0, 0.24, 0)
        plantGroup.addChildNode(pot)

        let soil = SCNNode(geometry: SCNCylinder(radius: 0.24, height: 0.04))
        soil.geometry?.materials = [makePBRMaterial(color: NSColor(srgbRed: 0.24, green: 0.17, blue: 0.12, alpha: 1), roughness: 0.95)]
        soil.position = SCNVector3(0, 0.47, 0)
        plantGroup.addChildNode(soil)

        let leafDark = makePBRMaterial(color: NSColor(srgbRed: 0.18, green: 0.52, blue: 0.36, alpha: 1), roughness: 0.52)
        let leafBright = makePBRMaterial(color: NSColor(srgbRed: 0.28, green: 0.66, blue: 0.44, alpha: 1), roughness: 0.48)
        let trunk = SCNNode(geometry: SCNCylinder(radius: 0.032, height: 0.85))
        trunk.geometry?.materials = [legWoodMat]
        trunk.position = SCNVector3(0, 0.88, 0)
        plantGroup.addChildNode(trunk)

        let foliageClusters: [(Float, Float, Float, CGFloat, Bool)] = [
            (0.0, 1.42, 0.0, 0.26, true),
            (-0.22, 1.24, 0.16, 0.22, false),
            (0.24, 1.26, 0.14, 0.21, true),
            (0.08, 1.12, -0.20, 0.20, false),
            (-0.16, 1.02, -0.14, 0.18, true),
            (0.18, 1.48, -0.08, 0.17, false)
        ]
        for (fx, fy, fz, fr, bright) in foliageClusters {
            let sphere = SCNNode(geometry: SCNSphere(radius: fr))
            sphere.scale = SCNVector3(1.15, 0.88, 1.05)
            sphere.geometry?.materials = [bright ? leafBright : leafDark]
            sphere.position = SCNVector3(fx, fy, fz)
            plantGroup.addChildNode(sphere)
        }

        // 4. Bookshelf with Colorful Book Spines (Center-Back Wall)
        let shelfGroup = SCNNode()
        shelfGroup.position = SCNVector3(0.08, 0, -3.72)
        roomRootNode.addChildNode(shelfGroup)

        let shelfWood = makePBRMaterial(color: NSColor(srgbRed: 0.56, green: 0.41, blue: 0.28, alpha: 1), roughness: 0.52)
        let shelfBack = SCNNode(geometry: SCNBox(width: 1.56, height: 2.25, length: 0.04, chamferRadius: 0.01))
        shelfBack.geometry?.materials = [shelfWood]
        shelfBack.position = SCNVector3(0, 1.125, -0.22)
        shelfGroup.addChildNode(shelfBack)

        for sx in [-0.75, 0.75] as [Float] {
            let side = SCNNode(geometry: SCNBox(width: 0.06, height: 2.25, length: 0.46, chamferRadius: 0.01))
            side.geometry?.materials = [shelfWood]
            side.position = SCNVector3(sx, 1.125, 0)
            shelfGroup.addChildNode(side)
        }

        let shelfLevels: [Float] = [0.12, 0.80, 1.48, 2.20]
        for sy in shelfLevels {
            let plank = SCNNode(geometry: SCNBox(width: 1.50, height: 0.055, length: 0.46, chamferRadius: 0.01))
            plank.geometry?.materials = [shelfWood]
            plank.position = SCNVector3(0, sy, 0)
            shelfGroup.addChildNode(plank)
        }

        let spineColors: [NSColor] = [
            NSColor(PipiTokens.color(for: .iris)),
            NSColor(PipiTokens.color(for: .emerald)),
            NSColor(PipiTokens.color(for: .amber)),
            NSColor(PipiTokens.color(for: .sky)),
            NSColor(PipiTokens.color(for: .coral)),
            NSColor(srgbRed: 0.88, green: 0.86, blue: 0.80, alpha: 1),
            NSColor(srgbRed: 0.30, green: 0.36, blue: 0.48, alpha: 1)
        ]

        // Populate shelves 1 and 2 with varied colorful books
        for (rowIdx, baseY) in [0.15, 0.83, 1.51].enumerated() {
            var cursorX: Float = -0.64
            for b in 0..<9 {
                if (rowIdx == 1 && b == 4) || (rowIdx == 2 && b >= 6) {
                    cursorX += 0.14
                    continue
                }
                let bw: Float = 0.075 + Float((b + rowIdx) % 3) * 0.022
                let bh: Float = 0.34 + Float((b * 2 + rowIdx) % 4) * 0.045
                let bd: Float = 0.30
                let book = SCNNode(geometry: SCNBox(width: CGFloat(bw), height: CGFloat(bh), length: CGFloat(bd), chamferRadius: 0.008))
                book.geometry?.materials = [makePBRMaterial(color: spineColors[(b + rowIdx * 2) % spineColors.count], roughness: 0.65)]
                book.position = SCNVector3(cursorX + bw * 0.5, Float(baseY) + bh * 0.5, 0.02)
                shelfGroup.addChildNode(book)
                cursorX += bw + 0.012
            }
        }
    }

    private func buildCollaborationTable() {
        let tableGroup = SCNNode()
        tableGroup.position = SCNVector3(0.0, 0, 0.85)
        roomRootNode.addChildNode(tableGroup)

        let topMat = makePBRMaterial(color: NSColor(srgbRed: 0.86, green: 0.82, blue: 0.76, alpha: 1), roughness: 0.38)
        let legMat = makePBRMaterial(color: NSColor(srgbRed: 0.45, green: 0.33, blue: 0.23, alpha: 1), roughness: 0.50)

        let top = SCNNode(geometry: SCNCylinder(radius: 0.82, height: 0.055))
        top.geometry?.materials = [topMat]
        top.position = SCNVector3(0, 0.46, 0)
        tableGroup.addChildNode(top)

        // Glowing central collaboration inlay ring
        let ringGeo = SCNTorus(ringRadius: 0.42, pipeRadius: 0.018)
        collabTableRingMaterial.lightingModel = .constant
        collabTableRingMaterial.diffuse.contents = NSColor(srgbRed: 0.28, green: 0.56, blue: 0.96, alpha: 0.22)
        ringGeo.materials = [collabTableRingMaterial]
        let ringNode = SCNNode(geometry: ringGeo)
        ringNode.position = SCNVector3(0, 0.492, 0)
        tableGroup.addChildNode(ringNode)

        // 3 splayed architectural legs
        for i in 0..<3 {
            let angle = Float(i) * (Float.pi * 2.0 / 3.0) + 0.35
            let leg = SCNNode(geometry: SCNCylinder(radius: 0.036, height: 0.46))
            leg.geometry?.materials = [legMat]
            leg.position = SCNVector3(cos(angle) * 0.42, 0.22, sin(angle) * 0.42)
            leg.eulerAngles = SCNVector3(sin(angle) * 0.16, 0, -cos(angle) * 0.16)
            tableGroup.addChildNode(leg)
        }
    }

    // MARK: - Procedural 3D Bot Characters

    private func syncBotRigs(items: [PipiHomeBotSyncItem], isDark: Bool) {
        let incomingIds = Set(items.map(\.id))

        // Remove deleted bots
        for (existingId, rig) in botRigs where !incomingIds.contains(existingId) {
            rig.rootNode.removeFromParentNode()
            botRigs.removeValue(forKey: existingId)
        }

        // Add or update bots
        for (idx, item) in items.enumerated() {
            if let rig = botRigs[item.id] {
                rig.accent = item.accent
                rig.visualState = item.state
                updateRigColors(rig, isDark: isDark)
                updateRigAttachments(rig, isDark: isDark)
            } else {
                let spawnPos = idleWaypoints[idx % idleWaypoints.count]
                let rig = createBotRig(item: item, startPosition: spawnPos, phaseOffset: Double(idx) * 1.37, isDark: isDark)
                botRigs[item.id] = rig
                botsContainerNode.addChildNode(rig.rootNode)
            }
        }
    }

    private func createBotRig(
        item: PipiHomeBotSyncItem,
        startPosition: SIMD3<Float>,
        phaseOffset: Double,
        isDark: Bool
    ) -> BotRig {
        let root = SCNNode()
        root.name = "bot_rig:\(item.id)"
        root.position = SCNVector3(startPosition.x, startPosition.y, startPosition.z)

        // Invisible generous capsule collider for effortless clicking & hovering
        let colliderGeo = SCNCapsule(capRadius: 0.38, height: 1.15)
        let colliderMat = SCNMaterial()
        colliderMat.colorBufferWriteMask = []
        colliderMat.writesToDepthBuffer = false
        colliderMat.readsFromDepthBuffer = false
        colliderGeo.materials = [colliderMat]
        let colliderNode = SCNNode(geometry: colliderGeo)
        colliderNode.position = SCNVector3(0, 0.56, 0)
        root.addChildNode(colliderNode)

        // Soft Contact Shadow on Floor
        let shadowGeo = SCNPlane(width: 0.82, height: 0.82)
        let shadowMat = SCNMaterial()
        shadowMat.lightingModel = .constant
        shadowMat.diffuse.contents = Self.radialShadowImage()
        shadowMat.writesToDepthBuffer = false
        shadowMat.isDoubleSided = true
        shadowGeo.materials = [shadowMat]
        let shadowNode = SCNNode(geometry: shadowGeo)
        shadowNode.position = SCNVector3(0, 0.028, 0)
        shadowNode.eulerAngles = SCNVector3(-Float.pi * 0.5, 0, 0)
        root.addChildNode(shadowNode)

        // Interactive Hover/Selection Floor Ring
        let floorRingGeo = SCNTorus(ringRadius: 0.36, pipeRadius: 0.018)
        let floorRingMat = SCNMaterial()
        floorRingMat.lightingModel = .constant
        floorRingGeo.materials = [floorRingMat]
        let floorRingNode = SCNNode(geometry: floorRingGeo)
        floorRingNode.position = SCNVector3(0, 0.036, 0)
        root.addChildNode(floorRingNode)

        // Body & Head Hierarchy
        let bodyGroup = SCNNode()
        root.addChildNode(bodyGroup)

        let chassisMat = makePBRMaterial(color: .white, roughness: 0.28, metalness: 0.18)
        let trimMat = makePBRMaterial(color: .gray, roughness: 0.25, metalness: 0.65)
        let visorMat = makePBRMaterial(color: NSColor(srgbRed: 0.05, green: 0.09, blue: 0.16, alpha: 1), roughness: 0.08, metalness: 0.22)
        let leftEyeMat = SCNMaterial()
        leftEyeMat.lightingModel = .constant
        let rightEyeMat = SCNMaterial()
        rightEyeMat.lightingModel = .constant

        // Tiny feet
        let footGeo = SCNCapsule(capRadius: 0.068, height: 0.20)
        footGeo.materials = [trimMat]
        let leftFoot = SCNNode(geometry: footGeo)
        leftFoot.eulerAngles = SCNVector3(Float.pi * 0.5, 0, 0)
        leftFoot.position = SCNVector3(-0.12, 0.08, 0.02)
        root.addChildNode(leftFoot)

        let rightFoot = SCNNode(geometry: footGeo)
        rightFoot.eulerAngles = SCNVector3(Float.pi * 0.5, 0, 0)
        rightFoot.position = SCNVector3(0.12, 0.08, 0.02)
        root.addChildNode(rightFoot)

        // Rounded Capsule Torso
        let torso = SCNNode(geometry: SCNBox(width: 0.36, height: 0.32, length: 0.28, chamferRadius: 0.13))
        torso.geometry?.materials = [chassisMat]
        torso.position = SCNVector3(0, 0.31, 0)
        bodyGroup.addChildNode(torso)

        // Chest accent badge strip
        let chestBadge = SCNNode(geometry: SCNBox(width: 0.14, height: 0.045, length: 0.02, chamferRadius: 0.01))
        chestBadge.geometry?.materials = [leftEyeMat]
        chestBadge.position = SCNVector3(0, 0.32, 0.142)
        bodyGroup.addChildNode(chestBadge)

        // Head Group
        let headGroup = SCNNode()
        headGroup.position = SCNVector3(0, 0.64, 0)
        bodyGroup.addChildNode(headGroup)

        // Motif-distinctive head silhouette
        switch item.motif {
        case .haloPip:
            let head = SCNNode(geometry: SCNBox(width: 0.44, height: 0.38, length: 0.34, chamferRadius: 0.14))
            head.geometry?.materials = [chassisMat]
            headGroup.addChildNode(head)

            let halo = SCNNode(geometry: SCNTorus(ringRadius: 0.14, pipeRadius: 0.016))
            halo.geometry?.materials = [leftEyeMat]
            halo.position = SCNVector3(0, 0.23, 0)
            headGroup.addChildNode(halo)

        case .caret:
            let head = SCNNode(geometry: SCNBox(width: 0.46, height: 0.36, length: 0.34, chamferRadius: 0.08))
            head.geometry?.materials = [chassisMat]
            headGroup.addChildNode(head)

            for ex in [-0.24, 0.24] as [Float] {
                let earLug = SCNNode(geometry: SCNCylinder(radius: 0.06, height: 0.05))
                earLug.geometry?.materials = [trimMat]
                earLug.eulerAngles = SCNVector3(0, 0, Float.pi * 0.5)
                earLug.position = SCNVector3(ex, 0.0, 0)
                headGroup.addChildNode(earLug)
            }

        case .nib:
            let head = SCNNode(geometry: SCNSphere(radius: 0.22))
            head.scale = SCNVector3(1.06, 0.96, 0.88)
            head.geometry?.materials = [chassisMat]
            headGroup.addChildNode(head)

            let crest = SCNNode(geometry: SCNCone(topRadius: 0.008, bottomRadius: 0.045, height: 0.10))
            crest.geometry?.materials = [trimMat]
            crest.position = SCNVector3(0, 0.23, 0)
            headGroup.addChildNode(crest)

        case .loop:
            let head = SCNNode(geometry: SCNBox(width: 0.44, height: 0.37, length: 0.32, chamferRadius: 0.11))
            head.geometry?.materials = [chassisMat]
            headGroup.addChildNode(head)

            let radarBar = SCNNode(geometry: SCNBox(width: 0.24, height: 0.04, length: 0.06, chamferRadius: 0.015))
            radarBar.geometry?.materials = [trimMat]
            radarBar.position = SCNVector3(0, 0.20, 0)
            headGroup.addChildNode(radarBar)
        }

        // Dark Glossy Visor
        let visor = SCNNode(geometry: SCNBox(width: 0.33, height: 0.20, length: 0.06, chamferRadius: 0.06))
        visor.geometry?.materials = [visorMat]
        visor.position = SCNVector3(0, 0.0, 0.155)
        headGroup.addChildNode(visor)

        // Glowing Optical Eyes / Lenses
        let leftEye = SCNNode(geometry: SCNCapsule(capRadius: 0.036, height: 0.095))
        leftEye.geometry?.materials = [leftEyeMat]
        leftEye.position = SCNVector3(-0.072, 0.005, 0.186)
        headGroup.addChildNode(leftEye)

        let rightEye = SCNNode(geometry: SCNCapsule(capRadius: 0.036, height: 0.095))
        rightEye.geometry?.materials = [rightEyeMat]
        rightEye.position = SCNVector3(0.072, 0.005, 0.186)
        headGroup.addChildNode(rightEye)

        // Working Orbiting Accent Ring
        let orbitGeo = SCNTorus(ringRadius: 0.34, pipeRadius: 0.012)
        orbitGeo.materials = [leftEyeMat]
        let orbitRing = SCNNode(geometry: orbitGeo)
        orbitRing.position = SCNVector3(0, 0.42, 0)
        orbitRing.eulerAngles = SCNVector3(0.24, 0, 0.18)
        orbitRing.isHidden = true
        bodyGroup.addChildNode(orbitRing)

        // Working Mini Floating Holographic Screen (shown if desk is occupied by another bot)
        let miniHolo = SCNNode()
        miniHolo.position = SCNVector3(0, 0.62, 0.46)
        miniHolo.eulerAngles = SCNVector3(-0.22, 0, 0)
        let holoPlane = SCNPlane(width: 0.38, height: 0.24)
        let holoMat = SCNMaterial()
        holoMat.lightingModel = .constant
        holoMat.diffuse.contents = NSColor(srgbRed: 0.22, green: 0.66, blue: 0.98, alpha: 0.72)
        holoMat.isDoubleSided = true
        holoPlane.materials = [holoMat]
        let holoScreen = SCNNode(geometry: holoPlane)
        miniHolo.addChildNode(holoScreen)
        miniHolo.isHidden = true
        bodyGroup.addChildNode(miniHolo)

        // NeedsYou Floating Amber `!` Beacon
        let beaconGroup = SCNNode()
        beaconGroup.position = SCNVector3(0, 1.12, 0)
        let amberMat = SCNMaterial()
        amberMat.lightingModel = .constant
        amberMat.diffuse.contents = NSColor(srgbRed: 0.98, green: 0.66, blue: 0.12, alpha: 1.0)
        let exBar = SCNNode(geometry: SCNCapsule(capRadius: 0.035, height: 0.17))
        exBar.geometry?.materials = [amberMat]
        exBar.position = SCNVector3(0, 0.09, 0)
        beaconGroup.addChildNode(exBar)
        let exDot = SCNNode(geometry: SCNSphere(radius: 0.036))
        exDot.geometry?.materials = [amberMat]
        exDot.position = SCNVector3(0, -0.04, 0)
        beaconGroup.addChildNode(exDot)
        beaconGroup.isHidden = true
        root.addChildNode(beaconGroup)

        let rig = BotRig(
            id: item.id,
            rootNode: root,
            bodyGroupNode: bodyGroup,
            headGroupNode: headGroup,
            leftFootNode: leftFoot,
            rightFootNode: rightFoot,
            leftEyeMaterial: leftEyeMat,
            rightEyeMaterial: rightEyeMat,
            chassisMaterial: chassisMat,
            trimMaterial: trimMat,
            visorMaterial: visorMat,
            floorRingNode: floorRingNode,
            floorRingMaterial: floorRingMat,
            shadowNode: shadowNode,
            alertBeaconNode: beaconGroup,
            miniHoloNode: miniHolo,
            orbitRingNode: orbitRing,
            accent: item.accent,
            motif: item.motif,
            visualState: item.state,
            position: startPosition,
            heading: 0,
            phaseOffset: phaseOffset
        )

        updateRigColors(rig, isDark: isDark)
        updateRigAttachments(rig, isDark: isDark)
        return rig
    }

    private func updateRigColors(_ rig: BotRig, isDark: Bool) {
        if isDark {
            rig.chassisMaterial.diffuse.contents = NSColor(srgbRed: 0.16, green: 0.19, blue: 0.25, alpha: 1)
            rig.chassisMaterial.roughness.contents = 0.28
            rig.chassisMaterial.metalness.contents = 0.42
            rig.trimMaterial.diffuse.contents = NSColor(srgbRed: 0.34, green: 0.39, blue: 0.48, alpha: 1)
            rig.visorMaterial.diffuse.contents = NSColor(srgbRed: 0.04, green: 0.08, blue: 0.11, alpha: 1)
        } else {
            rig.chassisMaterial.diffuse.contents = NSColor(srgbRed: 0.96, green: 0.95, blue: 0.92, alpha: 1)
            rig.chassisMaterial.roughness.contents = 0.22
            rig.chassisMaterial.metalness.contents = 0.06
            rig.trimMaterial.diffuse.contents = NSColor(srgbRed: 0.72, green: 0.70, blue: 0.66, alpha: 1)
            rig.visorMaterial.diffuse.contents = NSColor(srgbRed: 0.09, green: 0.15, blue: 0.33, alpha: 1)
        }

        let eyeColor = Self.resolveNSColor(PipiTokens.lensIris(for: rig.accent), isDark: isDark)
        let accentColor = Self.resolveNSColor(PipiTokens.color(for: rig.accent), isDark: isDark)

        rig.leftEyeMaterial.diffuse.contents = eyeColor
        rig.rightEyeMaterial.diffuse.contents = eyeColor
        rig.floorRingMaterial.diffuse.contents = accentColor.withAlphaComponent(0.60)
    }

    private func updateRigAttachments(_ rig: BotRig, isDark: Bool) {
        rig.alertBeaconNode.isHidden = (rig.visualState != .needsYou)
        rig.orbitRingNode.isHidden = (rig.visualState != .working)
        if rig.visualState != .working {
            rig.miniHoloNode.isHidden = true
        }
        _ = isDark
    }

    // MARK: - Theme Adaptation (Light Daylight vs Dark Starry Twilight)

    private func applyTheme(isDark: Bool) {
        lastAppliedThemeDark = isDark
        scene.lightingEnvironment.contents = Self.studioEnvironmentImage(isDark: isDark)
        scene.lightingEnvironment.intensity = isDark ? 0.58 : 0.88

        if isDark {
            scene.background.contents = NSColor(srgbRed: 0.055, green: 0.068, blue: 0.090, alpha: 1.0)
            ambientLightNode.light?.intensity = 240
            ambientLightNode.light?.color = NSColor(srgbRed: 0.72, green: 0.78, blue: 0.95, alpha: 1)
            keyLightNode.light?.intensity = 420
            keyLightNode.light?.color = NSColor(srgbRed: 0.80, green: 0.86, blue: 1.0, alpha: 1)
            fillLightNode.light?.intensity = 180
            windowLightNode.light?.intensity = 260
            windowLightNode.light?.color = NSColor(srgbRed: 0.45, green: 0.60, blue: 0.95, alpha: 1)
            deskLampLightNode.light?.intensity = 720
            deskLampLightNode.light?.color = NSColor(srgbRed: 1.0, green: 0.82, blue: 0.54, alpha: 1)

            wallMaterial.diffuse.contents = NSColor(srgbRed: 0.16, green: 0.19, blue: 0.25, alpha: 1)
            baseboardMaterial.diffuse.contents = NSColor(srgbRed: 0.22, green: 0.25, blue: 0.32, alpha: 1)
            rugMaterial.diffuse.contents = NSColor(srgbRed: 0.20, green: 0.23, blue: 0.29, alpha: 1)
            rugTrimMaterial.diffuse.contents = NSColor(srgbRed: 0.28, green: 0.32, blue: 0.40, alpha: 1)
            for (idx, mat) in floorPlankMaterials.enumerated() {
                let d = CGFloat(idx) * 0.016
                mat.diffuse.contents = NSColor(srgbRed: 0.24 - d, green: 0.19 - d * 0.7, blue: 0.15 - d * 0.5, alpha: 1)
            }
            windowBackdropNode.geometry?.firstMaterial?.diffuse.contents = NSColor(srgbRed: 0.06, green: 0.10, blue: 0.22, alpha: 1)
            windowStarsNode.isHidden = false
            windowMoonNode.isHidden = false
            sunBeamNode.isHidden = true
        } else {
            scene.background.contents = NSColor(srgbRed: 0.955, green: 0.962, blue: 0.978, alpha: 1.0)
            ambientLightNode.light?.intensity = 460
            ambientLightNode.light?.color = NSColor(srgbRed: 1.0, green: 0.98, blue: 0.95, alpha: 1)
            keyLightNode.light?.intensity = 960
            keyLightNode.light?.color = NSColor(srgbRed: 1.0, green: 0.96, blue: 0.89, alpha: 1)
            fillLightNode.light?.intensity = 320
            windowLightNode.light?.intensity = 760
            windowLightNode.light?.color = NSColor(srgbRed: 1.0, green: 0.95, blue: 0.84, alpha: 1)
            deskLampLightNode.light?.intensity = 320
            deskLampLightNode.light?.color = NSColor(srgbRed: 1.0, green: 0.86, blue: 0.62, alpha: 1)

            wallMaterial.diffuse.contents = NSColor(srgbRed: 0.94, green: 0.92, blue: 0.88, alpha: 1)
            baseboardMaterial.diffuse.contents = NSColor(srgbRed: 0.98, green: 0.97, blue: 0.95, alpha: 1)
            rugMaterial.diffuse.contents = NSColor(srgbRed: 0.91, green: 0.88, blue: 0.83, alpha: 1)
            rugTrimMaterial.diffuse.contents = NSColor(srgbRed: 0.74, green: 0.69, blue: 0.62, alpha: 1)
            for (idx, mat) in floorPlankMaterials.enumerated() {
                let d = CGFloat(idx) * 0.024
                mat.diffuse.contents = NSColor(srgbRed: 0.74 - d, green: 0.58 - d * 0.8, blue: 0.41 - d * 0.6, alpha: 1)
            }
            windowBackdropNode.geometry?.firstMaterial?.diffuse.contents = NSColor(srgbRed: 0.62, green: 0.83, blue: 0.98, alpha: 1)
            windowStarsNode.isHidden = true
            windowMoonNode.isHidden = true
            sunBeamNode.isHidden = false
        }

        for rig in botRigs.values {
            updateRigColors(rig, isDark: isDark)
        }
    }

    // MARK: - 60fps Render Loop Delegate

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt: Float
        if let prev = lastFrameTime {
            dt = Float(min(0.05, max(0.001, time - prev)))
        } else {
            dt = 1.0 / 60.0
        }
        lastFrameTime = time

        let snapshot = stateLock.withLock { snap -> InputSnapshot in
            let copy = snap
            snap.needsBotSync = false
            snap.needsThemeSync = false
            return copy
        }

        // Smooth camera interpolation
        let camLerp: CGFloat = snapshot.reduceMotion ? 1.0 : CGFloat(min(1.0, dt * 10.0))
        currentYaw += (snapshot.targetYaw - currentYaw) * camLerp
        currentPitch += (snapshot.targetPitch - currentPitch) * camLerp
        currentDistance += (snapshot.targetDistance - currentDistance) * camLerp
        applyCameraTransform()

        if snapshot.needsThemeSync || lastAppliedThemeDark != snapshot.isDark {
            applyTheme(isDark: snapshot.isDark)
        }
        if snapshot.needsBotSync {
            syncBotRigs(items: snapshot.bots, isDark: snapshot.isDark)
        }

        // Update room ambient glow states (monitor & collaboration table)
        let workingBots = snapshot.bots.filter { $0.state == .working }
        let collabBots = snapshot.bots.filter { $0.state == .collaborating }
        let needsBots = snapshot.bots.filter { $0.state == .needsYou }

        if !workingBots.isEmpty {
            let pulse = snapshot.reduceMotion ? 0.8 : (0.72 + 0.28 * sin(time * 3.2))
            monitorScreenMaterial.diffuse.contents = NSColor(srgbRed: 0.20, green: 0.56 * pulse + 0.12, blue: 0.98, alpha: 1)
            monitorGlowLightNode.light?.intensity = 340 * pulse
            monitorGlowLightNode.light?.color = NSColor(srgbRed: 0.25, green: 0.65, blue: 1.0, alpha: 1)
        } else {
            monitorScreenMaterial.diffuse.contents = snapshot.isDark
                ? NSColor(srgbRed: 0.12, green: 0.20, blue: 0.34, alpha: 1)
                : NSColor(srgbRed: 0.24, green: 0.36, blue: 0.54, alpha: 1)
            monitorGlowLightNode.light?.intensity = 90
        }

        if !collabBots.isEmpty {
            let pulse = snapshot.reduceMotion ? 0.85 : (0.65 + 0.35 * sin(time * 2.6))
            collabTableRingMaterial.diffuse.contents = NSColor(srgbRed: 0.28, green: 0.72, blue: 1.0, alpha: 0.65 * pulse + 0.25)
        } else {
            collabTableRingMaterial.diffuse.contents = NSColor(srgbRed: 0.28, green: 0.56, blue: 0.96, alpha: 0.16)
        }

        // Assign targets and step each bot rig
        let workingOrder = Dictionary(uniqueKeysWithValues: workingBots.enumerated().map { ($1.id, $0) })
        let collabOrder = Dictionary(uniqueKeysWithValues: collabBots.enumerated().map { ($1.id, $0) })
        let needsOrder = Dictionary(uniqueKeysWithValues: needsBots.enumerated().map { ($1.id, $0) })

        for bot in snapshot.bots {
            guard let rig = botRigs[bot.id] else { continue }
            let isSelected = (snapshot.selectedBotId == bot.id)
            let isHovered = (snapshot.hoveredBotId == bot.id)

            // Target Position & Facing
            var desiredFacing: Float? = nil
            switch rig.visualState {
            case .needsYou:
                let idx = needsOrder[bot.id] ?? 0
                let spread = Float(idx) - Float(max(0, needsBots.count - 1)) * 0.5
                rig.walkTarget = SIMD3<Float>(spread * 1.15, 0, 2.35)
                desiredFacing = 0.0 // face forward toward user

            case .collaborating:
                let idx = collabOrder[bot.id] ?? 0
                let count = max(1, collabBots.count)
                let angle = (Float(idx) / Float(count)) * Float.pi * 2.0 + 0.45
                let radius: Float = 1.38
                let cx: Float = 0.0
                let cz: Float = 0.85
                let tx = cx + cos(angle) * radius
                let tz = cz + sin(angle) * radius
                rig.walkTarget = SIMD3<Float>(tx, 0, tz)
                desiredFacing = atan2(cx - tx, cz - tz)

            case .working:
                let idx = workingOrder[bot.id] ?? 0
                if idx == 0 {
                    // Primary desk station
                    rig.walkTarget = SIMD3<Float>(2.28, 0, -1.48)
                    desiredFacing = Float.pi // face -Z toward monitor
                    rig.miniHoloNode.isHidden = true
                } else {
                    // Secondary studio workstation with floating mini holographic screen
                    let offsetAngle = Float(idx - 1) * 0.7
                    let sx = 1.15 + Float(idx - 1) * 1.25
                    let sz = -0.55 + sin(offsetAngle) * 0.45
                    rig.walkTarget = SIMD3<Float>(min(3.55, sx), 0, sz)
                    desiredFacing = Float.pi * 0.85
                    rig.miniHoloNode.isHidden = false
                }

            case .idle:
                rig.miniHoloNode.isHidden = true
                let distToTarget = length(rig.walkTarget - rig.position)
                if distToTarget < 0.14 {
                    rig.pauseTimer -= TimeInterval(dt)
                    if rig.pauseTimer <= 0 {
                        rig.walkTarget = nextIdleWaypoint(avoiding: rig.position, botId: rig.id)
                        rig.pauseTimer = 2.6 + (rig.phaseOffset * 1.3).truncatingRemainder(dividingBy: 3.2)
                    }
                }
            }

            // Move toward walkTarget
            var delta = rig.walkTarget - rig.position
            delta.y = 0
            let dist = length(delta)

            // Soft separation from other bots when idle
            if rig.visualState == .idle {
                for (otherId, otherRig) in botRigs where otherId != rig.id {
                    var away = rig.position - otherRig.position
                    away.y = 0
                    let sep = length(away)
                    if sep > 0.001 && sep < 0.82 {
                        rig.position += normalize(away) * (0.82 - sep) * dt * 1.8
                    }
                }
            }

            let isMoving = dist > 0.08
            if isMoving {
                let speed: Float = (rig.visualState == .idle) ? 0.92 : 1.75
                let step = min(dist, speed * dt)
                let dir = delta / dist
                rig.position += dir * step
                let targetAngle = atan2(dir.x, dir.z)
                rig.heading = lerpAngle(from: rig.heading, to: targetAngle, t: min(1.0, dt * 8.5))
            } else if let desiredFacing {
                rig.heading = lerpAngle(from: rig.heading, to: desiredFacing, t: min(1.0, dt * 6.5))
            }

            rig.rootNode.position = SCNVector3(rig.position.x, 0, rig.position.z)
            rig.rootNode.eulerAngles = SCNVector3(0, rig.heading, 0)

            // Procedural Locomotion & State Animations
            let t = time + rig.phaseOffset
            if snapshot.reduceMotion {
                rig.bodyGroupNode.position = SCNVector3(0, 0, 0)
                rig.headGroupNode.eulerAngles = SCNVector3(0, 0, 0)
                rig.leftFootNode.position = SCNVector3(-0.12, 0.08, 0.02)
                rig.rightFootNode.position = SCNVector3(0.12, 0.08, 0.02)
            } else {
                if isMoving {
                    let stride = Float(sin(t * 11.5))
                    rig.leftFootNode.position = SCNVector3(-0.12, 0.08 + max(0, stride) * 0.04, stride * 0.07)
                    rig.rightFootNode.position = SCNVector3(0.12, 0.08 + max(0, -stride) * 0.04, -stride * 0.07)
                    rig.bodyGroupNode.position = SCNVector3(0, abs(stride) * 0.035, 0)
                    rig.headGroupNode.eulerAngles = SCNVector3(0.05, 0, stride * 0.04)
                } else {
                    rig.leftFootNode.position = SCNVector3(-0.12, 0.08, 0.02)
                    rig.rightFootNode.position = SCNVector3(0.12, 0.08, 0.02)

                    switch rig.visualState {
                    case .idle:
                        let breathe = Float(sin(t * 2.1)) * 0.016
                        let look = Float(sin(t * 0.85)) * 0.14
                        rig.bodyGroupNode.position = SCNVector3(0, breathe, 0)
                        rig.headGroupNode.eulerAngles = SCNVector3(0, look, 0)

                    case .working:
                        let bob = Float(sin(t * 7.5)) * 0.024
                        let tilt = Float(sin(t * 3.8)) * 0.07
                        rig.bodyGroupNode.position = SCNVector3(0, abs(bob), 0)
                        rig.headGroupNode.eulerAngles = SCNVector3(-0.08, tilt, 0)
                        rig.orbitRingNode.eulerAngles = SCNVector3(0.24, Float(t * 2.2), 0.18)

                    case .needsYou:
                        let hop = max(0, Float(sin(t * 4.4))) * 0.12
                        rig.bodyGroupNode.position = SCNVector3(0, hop, 0)
                        rig.headGroupNode.eulerAngles = SCNVector3(-0.06, 0, Float(sin(t * 2.2)) * 0.07)
                        rig.alertBeaconNode.position = SCNVector3(0, 1.12 + hop + Float(sin(t * 5.0)) * 0.04, 0)

                    case .collaborating:
                        let nod = Float(sin(t * 3.1)) * 0.06
                        let bob = Float(sin(t * 2.4)) * 0.018
                        rig.bodyGroupNode.position = SCNVector3(0, bob, 0)
                        rig.headGroupNode.eulerAngles = SCNVector3(nod, Float(sin(t * 1.4)) * 0.10, 0)
                    }
                }
            }

            // Hover / Selection Floor Ring Highlight
            let targetRingScale: Float = isSelected ? 1.24 : (isHovered ? 1.15 : 1.0)
            rig.currentScaleRing += (targetRingScale - rig.currentScaleRing) * min(1.0, dt * 12.0)
            rig.floorRingNode.scale = SCNVector3(rig.currentScaleRing, 1.0, rig.currentScaleRing)
            let ringAlpha: CGFloat = isSelected ? 0.95 : (isHovered ? 0.82 : 0.42)
            let baseAccent = Self.resolveNSColor(PipiTokens.color(for: rig.accent), isDark: snapshot.isDark)
            rig.floorRingMaterial.diffuse.contents = baseAccent.withAlphaComponent(ringAlpha)
        }

        // Rebuild / animate collaborating luminous energy arcs
        updateCollaboratingArcs(collabBots: collabBots, time: time, isDark: snapshot.isDark, reduceMotion: snapshot.reduceMotion)
    }

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        let snapshot = stateLock.withLock { $0 }
        let viewBounds = snapshot.viewSize
        guard viewBounds.width > 10 && viewBounds.height > 10 else { return }

        var badges: [PipiHomeProjectedBadge] = []
        badges.reserveCapacity(snapshot.bots.count)

        for bot in snapshot.bots {
            guard let rig = botRigs[bot.id] else { continue }
            let extraY: Float = (bot.state == .needsYou) ? 1.38 : 1.04
            let worldPos = SCNVector3(rig.position.x, extraY, rig.position.z)
            let projected = renderer.projectPoint(worldPos)

            guard projected.z > 0.0 && projected.z < 1.0 else { continue }
            let swiftUIY = viewBounds.height - CGFloat(projected.y)
            let swiftUIX = CGFloat(projected.x)

            badges.append(
                PipiHomeProjectedBadge(
                    id: bot.id,
                    displayName: bot.displayName,
                    accent: bot.accent,
                    state: bot.state,
                    screenPoint: CGPoint(x: swiftUIX, y: swiftUIY),
                    isSelected: snapshot.selectedBotId == bot.id,
                    isHovered: snapshot.hoveredBotId == bot.id
                )
            )
        }

        // Only push to MainActor if positions moved meaningfully or state changed
        let changed = hasSignificantBadgeDelta(old: lastProjectedSummary, new: badges)
        guard changed else { return }
        lastProjectedSummary = badges

        let alreadyScheduled = projectionLock.withLock { scheduled -> Bool in
            if scheduled { return true }
            scheduled = true
            return false
        }
        guard !alreadyScheduled else { return }

        let bridge = bridgeState
        let lock = projectionLock
        Task { @MainActor in
            bridge.projectedBadges = badges
            lock.withLock { $0 = false }
        }
    }

    private func hasSignificantBadgeDelta(old: [PipiHomeProjectedBadge], new: [PipiHomeProjectedBadge]) -> Bool {
        guard old.count == new.count else { return true }
        for (a, b) in zip(old, new) {
            if a.id != b.id || a.state != b.state || a.displayName != b.displayName || a.accent != b.accent || a.isSelected != b.isSelected || a.isHovered != b.isHovered {
                return true
            }
            if abs(a.screenPoint.x - b.screenPoint.x) > 0.45 || abs(a.screenPoint.y - b.screenPoint.y) > 0.45 {
                return true
            }
        }
        return false
    }

    // MARK: - Collaborating Luminous Energy Arcs

    private func updateCollaboratingArcs(
        collabBots: [PipiHomeBotSyncItem],
        time: TimeInterval,
        isDark: Bool,
        reduceMotion: Bool
    ) {
        let activeIds = Set(collabBots.map(\.id))
        let needsRebuild = collabArcSegments.count != collabBots.count ||
            zip(collabArcSegments, collabBots).contains { $0.node.name != "arc:\($1.id)" }

        if needsRebuild {
            collabArcsNode.childNodes.forEach { $0.removeFromParentNode() }
            collabArcSegments.removeAll()

            for bot in collabBots where activeIds.contains(bot.id) {
                let container = SCNNode()
                container.name = "arc:\(bot.id)"
                let accentColor = Self.resolveNSColor(PipiTokens.color(for: bot.accent), isDark: isDark)
                let beadMat = SCNMaterial()
                beadMat.lightingModel = .constant
                beadMat.diffuse.contents = accentColor.withAlphaComponent(0.88)

                var pulses: [SCNNode] = []
                for p in 0..<7 {
                    let r: CGFloat = (p % 2 == 0) ? 0.028 : 0.020
                    let bead = SCNNode(geometry: SCNSphere(radius: r))
                    bead.geometry?.materials = [beadMat]
                    container.addChildNode(bead)
                    pulses.append(bead)
                }
                collabArcsNode.addChildNode(container)
                let start = botRigs[bot.id]?.position ?? SIMD3<Float>(0, 0, 0.85)
                collabArcSegments.append((container, pulses, start, SIMD3<Float>(0, 0.52, 0.85), bot.accent))
            }
        }

        let centerTarget = SIMD3<Float>(0.0, 0.54, 0.85)
        for idx in collabArcSegments.indices {
            let botId = String(collabArcSegments[idx].node.name?.dropFirst("arc:".count) ?? "")
            guard let rig = botRigs[botId] else { continue }
            let start = SIMD3<Float>(rig.position.x, 0.58, rig.position.z)
            let pulses = collabArcSegments[idx].pulseNodes
            let count = Float(pulses.count)

            for (pIdx, bead) in pulses.enumerated() {
                let baseT = Float(pIdx) / count
                let flow = reduceMotion ? baseT : (baseT + Float(time * 0.65)).truncatingRemainder(dividingBy: 1.0)
                let pos = simd_mix(start, centerTarget, SIMD3<Float>(repeating: flow))
                let arcLift = sin(flow * Float.pi) * 0.34
                bead.position = SCNVector3(pos.x, pos.y + arcLift, pos.z)
                let scale = 0.7 + 0.45 * sin(flow * Float.pi)
                bead.scale = SCNVector3(scale, scale, scale)
            }
        }
    }

    // MARK: - Helpers

    private func nextIdleWaypoint(avoiding current: SIMD3<Float>, botId: String) -> SIMD3<Float> {
        let candidates = idleWaypoints.filter { length($0 - current) > 1.2 }
        let pool = candidates.isEmpty ? idleWaypoints : candidates
        let hash = abs(botId.hashValue) + Int((lastFrameTime ?? 1.0) * 10.0)
        return pool[hash % pool.count]
    }

    private func lerpAngle(from: Float, to: Float, t: Float) -> Float {
        var diff = (to - from).truncatingRemainder(dividingBy: Float.pi * 2)
        if diff > Float.pi { diff -= Float.pi * 2 }
        if diff < -Float.pi { diff += Float.pi * 2 }
        return from + diff * t
    }

    private func clamp(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        Swift.max(minVal, Swift.min(maxVal, value))
    }

    private func makePBRMaterial(color: NSColor, roughness: CGFloat, metalness: CGFloat = 0.0) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.diffuse.contents = color
        mat.roughness.contents = roughness
        mat.metalness.contents = metalness
        return mat
    }

    private static func resolveNSColor(_ color: Color, isDark: Bool) -> NSColor {
        let ns = NSColor(color)
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        var resolved = ns
        appearance?.performAsCurrentDrawingAppearance {
            resolved = ns.usingColorSpace(.sRGB) ?? ns
        }
        return resolved
    }

    private static func radialShadowImage() -> NSImage {
        let size = NSSize(width: 96, height: 96)
        let image = NSImage(size: size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.34).cgColor,
                NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.14).cgColor,
                NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.0).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.55, 1.0]
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                ctx.drawRadialGradient(
                    gradient,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: size.width * 0.48,
                    options: []
                )
            }
        }
        image.unlockFocus()
        return image
    }

    private static func studioEnvironmentImage(isDark: Bool) -> NSImage {
        let size = NSSize(width: 128, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let topColor: NSColor
            let midColor: NSColor
            let botColor: NSColor
            if isDark {
                topColor = NSColor(srgbRed: 0.24, green: 0.32, blue: 0.48, alpha: 1.0)
                midColor = NSColor(srgbRed: 0.16, green: 0.19, blue: 0.25, alpha: 1.0)
                botColor = NSColor(srgbRed: 0.22, green: 0.17, blue: 0.12, alpha: 1.0)
            } else {
                topColor = NSColor(srgbRed: 0.98, green: 0.99, blue: 1.00, alpha: 1.0)
                midColor = NSColor(srgbRed: 0.90, green: 0.91, blue: 0.94, alpha: 1.0)
                botColor = NSColor(srgbRed: 0.78, green: 0.68, blue: 0.56, alpha: 1.0)
            }
            let colors = [topColor.cgColor, midColor.cgColor, botColor.cgColor] as CFArray
            let locations: [CGFloat] = [0.0, 0.52, 1.0]
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: size.height),
                    end: CGPoint(x: 0, y: 0),
                    options: []
                )
            }
        }
        image.unlockFocus()
        return image
    }
}
