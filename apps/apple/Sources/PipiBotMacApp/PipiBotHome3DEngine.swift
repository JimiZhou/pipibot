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

public enum PipiHomeCameraPreset: String, CaseIterable, Identifiable, Sendable, Equatable {
    case overview
    case topDown
    case closeUp

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .overview: return "cube.transparent"
        case .topDown: return "square.grid.2x2"
        case .closeUp: return "viewfinder"
        }
    }

    public func label(_ lang: PipiResolvedLanguage) -> String {
        switch self {
        case .overview: return lang == .zhHans ? "全景" : "Overview"
        case .topDown: return lang == .zhHans ? "俯视" : "Top View"
        case .closeUp: return lang == .zhHans ? "近景" : "Close-Up"
        }
    }
}

public struct PipiHomeBotSyncItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let accent: PipiPersonaAccent
    public let motif: PipiPersonaMotif
    public let state: PipiHomeBotVisualState
    public let room: PipiHomeRoomKind

    public init(
        id: String,
        displayName: String,
        accent: PipiPersonaAccent,
        motif: PipiPersonaMotif,
        state: PipiHomeBotVisualState,
        room: PipiHomeRoomKind
    ) {
        self.id = id
        self.displayName = displayName
        self.accent = accent
        self.motif = motif
        self.state = state
        self.room = room
    }
}

public struct PipiHomeProjectedBadge: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let accent: PipiPersonaAccent
    public let state: PipiHomeBotVisualState
    public let room: PipiHomeRoomKind
    public let screenPoint: CGPoint
    public let isSelected: Bool
    public let isHovered: Bool
    public let isDragging: Bool

    public init(
        id: String,
        displayName: String,
        accent: PipiPersonaAccent,
        state: PipiHomeBotVisualState,
        room: PipiHomeRoomKind,
        screenPoint: CGPoint,
        isSelected: Bool,
        isHovered: Bool,
        isDragging: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.accent = accent
        self.state = state
        self.room = room
        self.screenPoint = screenPoint
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.isDragging = isDragging
    }
}

public struct PipiHomeProjectedRoomLabel: Sendable, Equatable, Identifiable {
    public let room: PipiHomeRoomKind
    public let screenPoint: CGPoint
    public let occupantCount: Int
    public let isDropTarget: Bool

    public var id: String { room.rawValue }

    public init(
        room: PipiHomeRoomKind,
        screenPoint: CGPoint,
        occupantCount: Int,
        isDropTarget: Bool
    ) {
        self.room = room
        self.screenPoint = screenPoint
        self.occupantCount = occupantCount
        self.isDropTarget = isDropTarget
    }
}

public enum PipiHomeCameraAction: Equatable, Sendable {
    case preset(PipiHomeCameraPreset)
    case focusRoom(PipiHomeRoomKind)
    case focusBot(String)
    case zoomIn
    case zoomOut
    case reset
}

public struct PipiHomeCameraCommand: Equatable, Sendable {
    public let nonce: Int
    public let action: PipiHomeCameraAction

    public init(nonce: Int, action: PipiHomeCameraAction) {
        self.nonce = nonce
        self.action = action
    }
}

@MainActor
@Observable
public final class PipiHomeSceneBridgeState {
    public var projectedBadges: [PipiHomeProjectedBadge] = []
    public var projectedRoomLabels: [PipiHomeProjectedRoomLabel] = []
    public var hoveredBotId: String? = nil
    public var draggingBotId: String? = nil
    public var dragHoverRoom: PipiHomeRoomKind? = nil
    public var activeCameraPreset: PipiHomeCameraPreset = .overview
    var onSelectBot: ((String?) -> Void)?
    var onMoveBotToRoom: ((String, PipiHomeRoomKind) -> Void)?

    public init() {}
}

// MARK: - SceneKit NSViewRepresentable Wrapper

struct PipiHomeSceneRepresentable: NSViewRepresentable {
    let bots: [PipiHomeBotSyncItem]
    let scenePreset: PipiHomeScenePreset
    let selectedBotId: String?
    let pinnedBotId: String?
    let isDark: Bool
    let reduceMotion: Bool
    let cameraCommand: PipiHomeCameraCommand?
    let viewSize: CGSize
    let bridgeState: PipiHomeSceneBridgeState
    let onSelectBot: (String?) -> Void
    let onMoveBotToRoom: (String, PipiHomeRoomKind) -> Void

    func makeCoordinator() -> PipiHomeSceneCoordinator {
        PipiHomeSceneCoordinator(bridgeState: bridgeState)
    }

    func makeNSView(context: Context) -> PipiHomeSCNView {
        bridgeState.onSelectBot = onSelectBot
        bridgeState.onMoveBotToRoom = onMoveBotToRoom
        let scnView = PipiHomeSCNView()
        scnView.coordinator = context.coordinator
        scnView.wantsLayer = true
        scnView.antialiasingMode = .multisampling4X
        scnView.isJitteringEnabled = false
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false
        scnView.rendersContinuously = true
        scnView.preferredFramesPerSecond = 60
        scnView.scene = context.coordinator.scene
        scnView.pointOfView = context.coordinator.cameraNode
        scnView.delegate = context.coordinator
        context.coordinator.updateSnapshot(
            bots: bots,
            scenePreset: scenePreset,
            selectedBotId: selectedBotId,
            pinnedBotId: pinnedBotId,
            isDark: isDark,
            reduceMotion: reduceMotion,
            cameraCommand: cameraCommand,
            viewSize: viewSize
        )
        return scnView
    }

    func updateNSView(_ nsView: PipiHomeSCNView, context: Context) {
        bridgeState.onSelectBot = onSelectBot
        bridgeState.onMoveBotToRoom = onMoveBotToRoom
        context.coordinator.updateSnapshot(
            bots: bots,
            scenePreset: scenePreset,
            selectedBotId: selectedBotId,
            pinnedBotId: pinnedBotId,
            isDark: isDark,
            reduceMotion: reduceMotion,
            cameraCommand: cameraCommand,
            viewSize: viewSize
        )
    }
}

// MARK: - Custom SCNView for Fluid Orbit, Pan, Zoom, Pinch, Rotate, Keyboard & Direct Bot Drag-Drop

final class PipiHomeSCNView: SCNView {
    weak var coordinator: PipiHomeSceneCoordinator?

    private enum DragMode {
        case none
        case orbit
        case pan
        case dragBot(String)
    }

    private var trackingAreaRef: NSTrackingArea?
    private var mouseDownPoint: NSPoint?
    private var lastDragPoint: NSPoint?
    private var pressedBotId: String?
    private var dragMode: DragMode = .none
    private var didDrag: Bool = false

    override var acceptsFirstResponder: Bool { true }

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
        window?.makeFirstResponder(self)
        let pt = convert(event.locationInWindow, from: nil)
        mouseDownPoint = pt
        lastDragPoint = pt
        didDrag = false
        dragMode = .none

        let panModifier = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option)
        if panModifier {
            pressedBotId = nil
            dragMode = .pan
            NSCursor.closedHand.set()
        } else {
            let directHit = hitTestBotId(at: pt)
            pressedBotId = directHit ?? coordinator?.nearestBotId(nearViewPoint: pt, renderer: self, maxRadius: 34.0)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard let last = lastDragPoint, let down = mouseDownPoint else { return }
        let dx = pt.x - last.x
        let dy = pt.y - last.y
        lastDragPoint = pt

        let totalDist = hypot(pt.x - down.x, pt.y - down.y)
        if !didDrag && totalDist > 4.5 {
            didDrag = true
            if case .pan = dragMode {
                // Already panning
            } else if let botId = pressedBotId {
                dragMode = .dragBot(botId)
                NSCursor.closedHand.set()
                if let floorPos = raycastFloorPosition(at: pt) {
                    coordinator?.beginDraggingBot(botId, at: floorPos)
                }
            } else {
                dragMode = .orbit
                NSCursor.closedHand.set()
            }
        }

        switch dragMode {
        case .none:
            break
        case .orbit:
            coordinator?.orbitCamera(deltaX: dx, deltaY: dy)
        case .pan:
            coordinator?.panCamera(deltaX: dx, deltaY: dy)
        case .dragBot(let botId):
            if let floorPos = raycastFloorPosition(at: pt) {
                coordinator?.updateDraggingBot(botId, to: floorPos)
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let currentMode = dragMode
        let wasDragging = didDrag
        let hitPressedBot = pressedBotId

        mouseDownPoint = nil
        lastDragPoint = nil
        pressedBotId = nil
        dragMode = .none
        didDrag = false
        NSCursor.arrow.set()

        if case .dragBot(let botId) = currentMode {
            let floorPos = raycastFloorPosition(at: pt)
            coordinator?.endDraggingBot(botId, at: floorPos)
            return
        }

        guard !wasDragging else { return }

        let hitBot = hitTestBotId(at: pt) ?? hitPressedBot
        if event.clickCount == 2 {
            if let botId = hitBot {
                coordinator?.focusOnBot(botId)
                coordinator?.handleClick(botId: botId)
            } else {
                coordinator?.applyCameraPreset(.overview)
            }
            return
        }
        coordinator?.handleClick(botId: hitBot)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pt = convert(event.locationInWindow, from: nil)
        mouseDownPoint = pt
        lastDragPoint = pt
        dragMode = .pan
        didDrag = true
        NSCursor.closedHand.set()
    }

    override func rightMouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        guard let last = lastDragPoint else { return }
        let dx = pt.x - last.x
        let dy = pt.y - last.y
        lastDragPoint = pt
        coordinator?.panCamera(deltaX: dx, deltaY: dy)
    }

    override func rightMouseUp(with event: NSEvent) {
        mouseDownPoint = nil
        lastDragPoint = nil
        dragMode = .none
        didDrag = false
        NSCursor.arrow.set()
    }

    override func otherMouseDown(with event: NSEvent) {
        rightMouseDown(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        rightMouseDragged(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        rightMouseUp(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        if case .dragBot = dragMode { return }
        let pt = convert(event.locationInWindow, from: nil)
        let directHit = hitTestBotId(at: pt)
        let nearbyBot = directHit ?? coordinator?.nearestBotId(nearViewPoint: pt, renderer: self, maxRadius: 88.0)
        coordinator?.handleHover(botId: nearbyBot)
        if directHit != nil {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        if case .dragBot = dragMode { return }
        coordinator?.handleHover(botId: nil)
        NSCursor.arrow.set()
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) {
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 0.72 : 12.0
            coordinator?.panCamera(deltaX: event.scrollingDeltaX * scale, deltaY: -event.scrollingDeltaY * scale)
            return
        }
        // Trackpad horizontal swipe + Option/normal vertical zoom:
        // On trackpad, pure strong horizontal two-finger scroll pans gently; vertical scrolls zoom cleanly.
        if event.hasPreciseScrollingDeltas && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.45 && abs(event.scrollingDeltaX) > 2.0 {
            coordinator?.orbitCamera(deltaX: event.scrollingDeltaX * 0.55, deltaY: 0)
            return
        }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.042 : event.scrollingDeltaY * 0.34
        coordinator?.zoomCamera(delta: delta)
    }

    override func magnify(with event: NSEvent) {
        coordinator?.zoomCamera(delta: event.magnification * 7.5)
    }

    override func rotate(with event: NSEvent) {
        coordinator?.orbitCamera(deltaX: CGFloat(event.rotation) * 2.2, deltaY: 0)
    }

    override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers?.lowercased() else {
            super.keyDown(with: event)
            return
        }
        switch chars {
        case "w": coordinator?.panCamera(deltaX: 0, deltaY: -36)
        case "s": coordinator?.panCamera(deltaX: 0, deltaY: 36)
        case "a": coordinator?.panCamera(deltaX: 36, deltaY: 0)
        case "d": coordinator?.panCamera(deltaX: -36, deltaY: 0)
        case "q": coordinator?.orbitCamera(deltaX: 28, deltaY: 0)
        case "e": coordinator?.orbitCamera(deltaX: -28, deltaY: 0)
        case "=", "+": coordinator?.zoomCamera(delta: 2.2)
        case "-", "_": coordinator?.zoomCamera(delta: -2.2)
        case "r": coordinator?.applyCameraPreset(.overview)
        case "1": coordinator?.applyCameraPreset(.overview)
        case "2": coordinator?.applyCameraPreset(.topDown)
        case "3": coordinator?.applyCameraPreset(.closeUp)
        default:
            switch event.keyCode {
            case 126: coordinator?.panCamera(deltaX: 0, deltaY: -36)   // Up arrow
            case 125: coordinator?.panCamera(deltaX: 0, deltaY: 36)    // Down arrow
            case 123: coordinator?.panCamera(deltaX: 36, deltaY: 0)    // Left arrow
            case 124: coordinator?.panCamera(deltaX: -36, deltaY: 0)   // Right arrow
            default: super.keyDown(with: event)
            }
        }
    }

    private func raycastFloorPosition(at point: NSPoint) -> SIMD3<Float>? {
        let near = unprojectPoint(SCNVector3(point.x, point.y, 0.0))
        let far = unprojectPoint(SCNVector3(point.x, point.y, 1.0))
        let p0 = SIMD3<Float>(Float(near.x), Float(near.y), Float(near.z))
        let p1 = SIMD3<Float>(Float(far.x), Float(far.y), Float(far.z))
        let dir = p1 - p0
        guard abs(dir.y) > 0.0001 else { return nil }
        let t = -p0.y / dir.y
        guard t > 0 else { return nil }
        let hit = p0 + dir * t
        return SIMD3<Float>(
            Swift.max(-4.95, Swift.min(4.95, hit.x)),
            0,
            Swift.max(-4.30, Swift.min(4.25, hit.z))
        )
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

// MARK: - SceneKit Multi-Room & Preset Theme Engine (60fps Coordinator)

final class PipiHomeSceneCoordinator: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    let scene: SCNScene
    let cameraNode: SCNNode

    private let bridgeState: PipiHomeSceneBridgeState

    // Camera Rig (Interactive Orbit + Pan + Zoom + Presets)
    private let cameraPivotNode = SCNNode()
    private let cameraArmNode = SCNNode()
    private var currentYaw: CGFloat = 0.60
    private var currentPitch: CGFloat = 0.66
    private var currentDistance: CGFloat = 13.8
    private var currentPivot = SIMD3<Float>(0.0, 0.55, 0.0)

    private static let defaultYaw: CGFloat = 0.60
    private static let defaultPitch: CGFloat = 0.66
    private static let defaultDistance: CGFloat = 13.8
    private static let defaultPivot = SIMD3<Float>(0.0, 0.55, 0.0)

    // Room Geometric Bounds & Centers
    private struct RoomZoneSpec {
        let kind: PipiHomeRoomKind
        let minX: Float
        let maxX: Float
        let minZ: Float
        let maxZ: Float
        let center: SIMD3<Float>
        let labelAnchor: SIMD3<Float>
        let waypoints: [SIMD3<Float>]
    }

    private static let roomSpecs: [PipiHomeRoomKind: RoomZoneSpec] = [
        .lounge: RoomZoneSpec(
            kind: .lounge,
            minX: -5.20, maxX: -0.25, minZ: -4.55, maxZ: -0.25,
            center: SIMD3<Float>(-2.75, 0, -2.35),
            labelAnchor: SIMD3<Float>(-2.80, 1.55, -4.15),
            waypoints: [
                SIMD3<Float>(-3.90, 0, -1.55),
                SIMD3<Float>(-2.75, 0, -1.85),
                SIMD3<Float>(-1.45, 0, -1.35),
                SIMD3<Float>(-2.55, 0, -2.55),
                SIMD3<Float>(-4.15, 0, -2.55)
            ]
        ),
        .studio: RoomZoneSpec(
            kind: .studio,
            minX: 0.25, maxX: 5.20, minZ: -4.55, maxZ: -0.25,
            center: SIMD3<Float>(2.75, 0, -2.35),
            labelAnchor: SIMD3<Float>(2.85, 1.55, -4.15),
            waypoints: [
                SIMD3<Float>(3.10, 0, -1.95),
                SIMD3<Float>(1.65, 0, -1.40),
                SIMD3<Float>(1.45, 0, -2.85),
                SIMD3<Float>(4.30, 0, -1.65),
                SIMD3<Float>(2.80, 0, -1.15)
            ]
        ),
        .collab: RoomZoneSpec(
            kind: .collab,
            minX: -5.20, maxX: -0.25, minZ: 0.25, maxZ: 4.45,
            center: SIMD3<Float>(-2.75, 0, 2.35),
            labelAnchor: SIMD3<Float>(-2.75, 1.15, 4.15),
            waypoints: [
                SIMD3<Float>(-1.18, 0, 2.35),
                SIMD3<Float>(-2.75, 0, 3.88),
                SIMD3<Float>(-4.18, 0, 2.35),
                SIMD3<Float>(-2.75, 0, 0.92),
                SIMD3<Float>(-1.45, 0, 3.65)
            ]
        ),
        .lab: RoomZoneSpec(
            kind: .lab,
            minX: 0.25, maxX: 5.20, minZ: 0.25, maxZ: 4.45,
            center: SIMD3<Float>(2.75, 0, 2.35),
            labelAnchor: SIMD3<Float>(2.75, 1.15, 4.15),
            waypoints: [
                SIMD3<Float>(1.55, 0, 1.45),
                SIMD3<Float>(1.65, 0, 3.35),
                SIMD3<Float>(3.10, 0, 1.25),
                SIMD3<Float>(3.10, 0, 3.85),
                SIMD3<Float>(1.95, 0, 2.45)
            ]
        )
    ]

    // Scene Dynamic Nodes (Theme, Preset & State Sensitive)
    private let roomRootNode = SCNNode()
    private let botsContainerNode = SCNNode()
    private let collabArcsNode = SCNNode()
    private let dragGuideNode = SCNNode()
    private let dragGuideRingMaterial = SCNMaterial()
    private let dragGuideBeamMaterial = SCNMaterial()

    private var ambientLightNode = SCNNode()
    private var keyLightNode = SCNNode()
    private var fillLightNode = SCNNode()
    private var windowLightNode = SCNNode()
    private var deskLampLightNode = SCNNode()
    private var monitorGlowLightNode = SCNNode()
    private var labHoloLightNode = SCNNode()

    private var windowBackdropNode = SCNNode()
    private var windowStarsNode = SCNNode()
    private var windowMoonNode = SCNNode()
    private var shojiLatticeNode = SCNNode()
    private var sunBeamNode = SCNNode()
    private var holoCrystalNode = SCNNode()

    private var plinthMaterial = SCNMaterial()
    private var floorPlankMaterials: [SCNMaterial] = []
    private var wallMaterial = SCNMaterial()
    private var baseboardMaterial = SCNMaterial()
    private var partitionBaseMaterial = SCNMaterial()
    private var partitionGlassMaterial = SCNMaterial()
    private var partitionAccentMaterial = SCNMaterial()
    private var windowFrameMaterial = SCNMaterial()
    private var sofaMaterial = SCNMaterial()
    private var deskWoodMaterial = SCNMaterial()
    private var shelfWoodMaterial = SCNMaterial()
    private var tableTopMaterial = SCNMaterial()
    private var rugMaterial = SCNMaterial()
    private var rugTrimMaterial = SCNMaterial()
    private var monitorScreenMaterial = SCNMaterial()
    private var collabTableRingMaterial = SCNMaterial()
    private var holoCrystalMaterial = SCNMaterial()

    // Per-room floor inlays + drop-zone highlight borders
    private var roomPadMaterials: [PipiHomeRoomKind: SCNMaterial] = [:]
    private var roomFrameMaterials: [PipiHomeRoomKind: SCNMaterial] = [:]
    private var roomHighlightAlpha: [PipiHomeRoomKind: CGFloat] = [:]

    // Synchronized Input Snapshot
    private struct InputSnapshot: Sendable {
        var bots: [PipiHomeBotSyncItem] = []
        var scenePreset: PipiHomeScenePreset = .warmStudio
        var selectedBotId: String? = nil
        var pinnedBotId: String? = nil
        var hoveredBotId: String? = nil
        var draggingBotId: String? = nil
        var dragWorldPosition: SIMD3<Float>? = nil
        var dragHoverRoom: PipiHomeRoomKind? = nil
        var isDark: Bool = false
        var reduceMotion: Bool = false
        var needsBotSync: Bool = false
        var needsThemeSync: Bool = false
        var targetYaw: CGFloat = PipiHomeSceneCoordinator.defaultYaw
        var targetPitch: CGFloat = PipiHomeSceneCoordinator.defaultPitch
        var targetDistance: CGFloat = PipiHomeSceneCoordinator.defaultDistance
        var targetPivot: SIMD3<Float> = PipiHomeSceneCoordinator.defaultPivot
        var viewSize: CGSize = .zero
    }

    private let stateLock = OSAllocatedUnfairLock(initialState: InputSnapshot())
    private let projectionLock = OSAllocatedUnfairLock<Bool>(initialState: false)
    private var lastCameraCommandNonce: Int = -1
    private var lastAppliedThemeDark: Bool? = nil
    private var lastAppliedPreset: PipiHomeScenePreset? = nil
    private var lastProjectedBadges: [PipiHomeProjectedBadge] = []
    private var lastProjectedRoomLabels: [PipiHomeProjectedRoomLabel] = []

    // Per-Bot Runtime Simulation State
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
        var assignedRoom: PipiHomeRoomKind
        var position: SIMD3<Float>
        var heading: Float
        var walkTarget: SIMD3<Float>
        var pauseTimer: TimeInterval
        var phaseOffset: Double
        var currentScaleRing: Float = 1.0
        var dragLiftHeight: Float = 0.0
        var landingBouncePhase: Float = 0.0
        var cachedAccentColor: NSColor = NSColor(srgbRed: 0.30, green: 0.52, blue: 0.96, alpha: 1.0)
        var lastRingAlpha: CGFloat = -1.0

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
            assignedRoom: PipiHomeRoomKind,
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
            self.assignedRoom = assignedRoom
            self.position = position
            self.heading = heading
            self.walkTarget = position
            self.pauseTimer = 1.8 + phaseOffset.truncatingRemainder(dividingBy: 2.6)
            self.phaseOffset = phaseOffset
        }
    }

    private var botRigs: [String: BotRig] = [:]
    private var lastFrameTime: TimeInterval?
    private var lastMonitorWorkingState: Bool? = nil
    private var lastCollabActiveState: Bool? = nil
    private var collabArcSegments: [(node: SCNNode, pulseNodes: [SCNNode], start: SIMD3<Float>, end: SIMD3<Float>, accent: PipiPersonaAccent)] = []
    private let cachedEnvLight: NSImage
    private let cachedEnvDark: NSImage
    private let cachedRadialShadow: NSImage

    init(bridgeState: PipiHomeSceneBridgeState) {
        self.scene = SCNScene()
        self.cameraNode = SCNNode()
        self.bridgeState = bridgeState
        self.cachedEnvLight = Self.studioEnvironmentImage(isDark: false)
        self.cachedEnvDark = Self.studioEnvironmentImage(isDark: true)
        self.cachedRadialShadow = Self.radialShadowImage()
        super.init()

        setupCamera()
        setupLights()
        buildMultiRoomDiorama()
        buildDragGuideVisuals()
        scene.rootNode.addChildNode(botsContainerNode)
        scene.rootNode.addChildNode(collabArcsNode)
        applyScenePreset(.warmStudio, isDark: false)
    }

    // MARK: - MainActor -> Render Loop Sync

    @MainActor
    func updateSnapshot(
        bots: [PipiHomeBotSyncItem],
        scenePreset: PipiHomeScenePreset,
        selectedBotId: String?,
        pinnedBotId: String?,
        isDark: Bool,
        reduceMotion: Bool,
        cameraCommand: PipiHomeCameraCommand?,
        viewSize: CGSize
    ) {
        if let cmd = cameraCommand, cmd.nonce != lastCameraCommandNonce {
            lastCameraCommandNonce = cmd.nonce
            executeCameraAction(cmd.action)
        }

        stateLock.withLock { snap in
            let botsChanged = snap.bots != bots
            let themeChanged = (snap.isDark != isDark) || (snap.scenePreset != scenePreset)
            snap.bots = bots
            snap.scenePreset = scenePreset
            snap.selectedBotId = selectedBotId
            snap.pinnedBotId = pinnedBotId
            snap.isDark = isDark
            snap.reduceMotion = reduceMotion
            snap.viewSize = viewSize
            if botsChanged { snap.needsBotSync = true }
            if themeChanged { snap.needsThemeSync = true }
        }
    }

    // MARK: - Camera Ergonomics (Orbit, Pan, Zoom, Presets, Focus)

    func executeCameraAction(_ action: PipiHomeCameraAction) {
        switch action {
        case .preset(let preset):
            applyCameraPreset(preset)
        case .focusRoom(let room):
            focusOnRoom(room)
        case .focusBot(let botId):
            focusOnBot(botId)
        case .zoomIn:
            zoomCamera(delta: 2.8)
        case .zoomOut:
            zoomCamera(delta: -2.8)
        case .reset:
            applyCameraPreset(.overview)
        }
    }

    func applyCameraPreset(_ preset: PipiHomeCameraPreset) {
        stateLock.withLock { snap in
            switch preset {
            case .overview:
                snap.targetYaw = Self.defaultYaw
                snap.targetPitch = Self.defaultPitch
                snap.targetDistance = Self.defaultDistance
                snap.targetPivot = Self.defaultPivot
            case .topDown:
                snap.targetYaw = 0.02
                snap.targetPitch = 1.34
                snap.targetDistance = 15.2
                snap.targetPivot = SIMD3<Float>(0.0, 0.15, 0.05)
            case .closeUp:
                snap.targetYaw = 0.54
                snap.targetPitch = 0.42
                snap.targetDistance = 9.4
                snap.targetPivot = SIMD3<Float>(0.0, 0.62, 0.15)
            }
        }
        let bridge = bridgeState
        Task { @MainActor in
            bridge.activeCameraPreset = preset
        }
    }

    func focusOnRoom(_ room: PipiHomeRoomKind) {
        guard let spec = Self.roomSpecs[room] else { return }
        stateLock.withLock { snap in
            snap.targetPivot = SIMD3<Float>(
                Swift.max(-3.3, Swift.min(3.3, spec.center.x * 0.78)),
                0.48,
                Swift.max(-2.9, Swift.min(2.9, spec.center.z * 0.78))
            )
            snap.targetDistance = 9.6
            snap.targetPitch = clamp(snap.targetPitch, min: 0.48, max: 1.02)
        }
    }

    func focusOnBot(_ botId: String) {
        guard let rig = botRigs[botId] else { return }
        let pos = rig.position
        stateLock.withLock { snap in
            snap.targetPivot = SIMD3<Float>(
                Swift.max(-3.4, Swift.min(3.4, pos.x)),
                0.55,
                Swift.max(-3.0, Swift.min(3.0, pos.z))
            )
            snap.targetDistance = 8.4
            snap.targetPitch = 0.48
        }
    }

    func orbitCamera(deltaX: CGFloat, deltaY: CGFloat) {
        stateLock.withLock { snap in
            // Natural drag direction & generous angular envelope across all 4 rooms (zero back-wall clipping)
            snap.targetYaw = clamp(snap.targetYaw - deltaX * 0.0085, min: -0.45, max: 1.98)
            snap.targetPitch = clamp(snap.targetPitch - deltaY * 0.0068, min: 0.28, max: 1.38)
        }
    }

    func panCamera(deltaX: CGFloat, deltaY: CGFloat) {
        stateLock.withLock { snap in
            let yaw = Float(snap.targetYaw)
            let scale = Float(snap.targetDistance) * 0.00145
            // Camera-aligned right & ground-forward vectors
            let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
            let forward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
            var next = snap.targetPivot
            next -= right * Float(deltaX) * scale
            next -= forward * Float(deltaY) * scale
            next.x = Swift.max(-3.4, Swift.min(3.4, next.x))
            next.z = Swift.max(-3.0, Swift.min(3.0, next.z))
            snap.targetPivot = next
        }
    }

    func zoomCamera(delta: CGFloat) {
        stateLock.withLock { snap in
            snap.targetDistance = clamp(snap.targetDistance - delta * 0.55, min: 6.2, max: 18.2)
        }
    }

    // MARK: - Direct 3D Agent Drag-and-Drop Between Rooms

    func beginDraggingBot(_ botId: String, at floorPos: SIMD3<Float>) {
        let room = Self.roomKind(at: floorPos)
        stateLock.withLock { snap in
            snap.draggingBotId = botId
            snap.dragWorldPosition = floorPos
            snap.dragHoverRoom = room
            snap.hoveredBotId = botId
        }
        let bridge = bridgeState
        Task { @MainActor in
            bridge.draggingBotId = botId
            bridge.dragHoverRoom = room
        }
    }

    func updateDraggingBot(_ botId: String, to floorPos: SIMD3<Float>) {
        let room = Self.roomKind(at: floorPos)
        stateLock.withLock { snap in
            guard snap.draggingBotId == botId else { return }
            snap.dragWorldPosition = floorPos
            snap.dragHoverRoom = room
        }
        let bridge = bridgeState
        Task { @MainActor in
            if bridge.dragHoverRoom != room {
                bridge.dragHoverRoom = room
            }
        }
    }

    func endDraggingBot(_ botId: String, at floorPos: SIMD3<Float>?) {
        let finalState = stateLock.withLock { snap -> (SIMD3<Float>?, PipiHomeRoomKind?) in
            let pos = floorPos ?? snap.dragWorldPosition
            let room = pos.map { Self.roomKind(at: $0) } ?? snap.dragHoverRoom
            snap.draggingBotId = nil
            snap.dragWorldPosition = nil
            snap.dragHoverRoom = nil
            return (pos, room)
        }

        if let room = finalState.1, let rig = botRigs[botId] {
            let safeDropPos = resolveRoomCollisions(finalState.0 ?? Self.roomSpecs[room]!.center)
            rig.assignedRoom = room
            rig.position = safeDropPos
            rig.walkTarget = safeDropPos
            rig.pauseTimer = 4.2
            rig.landingBouncePhase = 1.0

            let bridge = bridgeState
            Task { @MainActor in
                bridge.draggingBotId = nil
                bridge.dragHoverRoom = nil
                bridge.onMoveBotToRoom?(botId, room)
            }
        } else {
            let bridge = bridgeState
            Task { @MainActor in
                bridge.draggingBotId = nil
                bridge.dragHoverRoom = nil
            }
        }
    }

    static func roomKind(at pos: SIMD3<Float>) -> PipiHomeRoomKind {
        if pos.x < 0 && pos.z < 0 { return .lounge }
        if pos.x >= 0 && pos.z < 0 { return .studio }
        if pos.x < 0 && pos.z >= 0 { return .collab }
        return .lab
    }

    func nearestBotId(nearViewPoint pt: NSPoint, renderer: SCNSceneRenderer, maxRadius: CGFloat) -> String? {
        var bestId: String? = nil
        var bestDist: CGFloat = maxRadius
        for (id, rig) in botRigs {
            let worldPos = SCNVector3(rig.position.x, 0.54 + rig.dragLiftHeight, rig.position.z)
            let projected = renderer.projectPoint(worldPos)
            guard projected.z > 0.0 && projected.z < 1.0 else { continue }
            let d = hypot(CGFloat(projected.x) - pt.x, CGFloat(projected.y) - pt.y)
            if d < bestDist {
                bestDist = d
                bestId = id
            }
        }
        return bestId
    }

    func handleClick(botId: String?) {
        let bridge = bridgeState
        Task { @MainActor in
            bridge.onSelectBot?(botId)
        }
    }

    func handleHover(botId: String?) {
        stateLock.withLock { snap in
            if snap.draggingBotId == nil {
                snap.hoveredBotId = botId
            }
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
        cameraPivotNode.position = SCNVector3(currentPivot.x, currentPivot.y, currentPivot.z)
        scene.rootNode.addChildNode(cameraPivotNode)

        let cam = SCNCamera()
        cam.fieldOfView = 35
        cam.zNear = 0.8
        cam.zFar = 54.0
        // Keep HDR disabled for zero auto-exposure flicker and calibrated studio contrast
        cam.wantsHDR = false
        cameraNode.camera = cam

        cameraPivotNode.addChildNode(cameraArmNode)
        cameraArmNode.addChildNode(cameraNode)
        applyCameraTransform()
    }

    private func applyCameraTransform() {
        cameraPivotNode.position = SCNVector3(currentPivot.x, currentPivot.y, currentPivot.z)

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
        ambient.intensity = 185
        ambientLightNode.light = ambient
        scene.rootNode.addChildNode(ambientLightNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 370
        key.castsShadow = true
        key.shadowMode = .forward
        key.shadowBias = 2.6
        key.shadowColor = NSColor(srgbRed: 0.05, green: 0.06, blue: 0.10, alpha: 0.22)
        key.shadowRadius = 2.2
        key.shadowSampleCount = 4
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.orthographicScale = 8.4
        key.zNear = 1.5
        key.zFar = 30.0
        keyLightNode.light = key
        keyLightNode.position = SCNVector3(7.5, 11.0, 7.0)
        keyLightNode.look(at: SCNVector3(0, 0.3, 0))
        scene.rootNode.addChildNode(keyLightNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 100
        fillLightNode.light = fill
        fillLightNode.position = SCNVector3(-8.0, 6.2, 6.5)
        fillLightNode.look(at: SCNVector3(0, 0.4, 0))
        scene.rootNode.addChildNode(fillLightNode)

        let winLight = SCNLight()
        winLight.type = .spot
        winLight.spotInnerAngle = 30
        winLight.spotOuterAngle = 76
        winLight.intensity = 165
        winLight.attenuationStartDistance = 1.5
        winLight.attenuationEndDistance = 10.5
        windowLightNode.light = winLight
        windowLightNode.position = SCNVector3(-5.15, 2.35, -2.45)
        windowLightNode.look(at: SCNVector3(-1.8, 0.0, -1.8))
        scene.rootNode.addChildNode(windowLightNode)

        let lampLight = SCNLight()
        lampLight.type = .omni
        lampLight.intensity = 150
        lampLight.attenuationStartDistance = 0.2
        lampLight.attenuationEndDistance = 4.6
        deskLampLightNode.light = lampLight
        deskLampLightNode.position = SCNVector3(3.95, 1.58, -3.55)
        scene.rootNode.addChildNode(deskLampLightNode)

        let monLight = SCNLight()
        monLight.type = .omni
        monLight.intensity = 100
        monLight.attenuationStartDistance = 0.1
        monLight.attenuationEndDistance = 3.2
        monitorGlowLightNode.light = monLight
        monitorGlowLightNode.position = SCNVector3(3.15, 1.45, -3.45)
        scene.rootNode.addChildNode(monitorGlowLightNode)

        let holoLight = SCNLight()
        holoLight.type = .omni
        holoLight.intensity = 120
        holoLight.attenuationStartDistance = 0.15
        holoLight.attenuationEndDistance = 3.6
        labHoloLightNode.light = holoLight
        labHoloLightNode.position = SCNVector3(3.20, 1.35, 2.60)
        scene.rootNode.addChildNode(labHoloLightNode)
    }

    // MARK: - 4-Room Cutaway Architectural Floorplan (Zero Clipping & Zero Z-Fighting)

    private func buildMultiRoomDiorama() {
        scene.rootNode.addChildNode(roomRootNode)

        // 1. Base Plinth (y = -0.275 .. -0.035, strictly beneath floor planks)
        let plinthGeo = SCNBox(width: 11.48, height: 0.24, length: 10.08, chamferRadius: 0.07)
        plinthMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.22, green: 0.18, blue: 0.15, alpha: 1), roughness: 0.85)
        plinthGeo.materials = [plinthMaterial]
        let plinthNode = SCNNode(geometry: plinthGeo)
        plinthNode.position = SCNVector3(0, -0.155, 0)
        roomRootNode.addChildNode(plinthNode)

        // 2. Staggered Architectural Floor Planks (y = -0.030 .. 0.000)
        buildFloorPlanks()

        // 3. Per-Room Floor Inlays + Interactive Drop-Zone Perimeter Glow Frames
        buildRoomZonesAndHighlightFrames()

        // 4. Outer L-Shaped Cutaway Walls & Baseboards (clean butt-joints)
        wallMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.84, green: 0.82, blue: 0.78, alpha: 1), roughness: 0.86)
        baseboardMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.89, green: 0.87, blue: 0.84, alpha: 1), roughness: 0.65)

        let leftWallGeo = SCNBox(width: 0.24, height: 3.70, length: 10.08, chamferRadius: 0.02)
        leftWallGeo.materials = [wallMaterial]
        let leftWallNode = SCNNode(geometry: leftWallGeo)
        leftWallNode.position = SCNVector3(-5.62, 1.85, 0)
        roomRootNode.addChildNode(leftWallNode)

        let backWallGeo = SCNBox(width: 11.24, height: 3.70, length: 0.24, chamferRadius: 0.02)
        backWallGeo.materials = [wallMaterial]
        let backWallNode = SCNNode(geometry: backWallGeo)
        backWallNode.position = SCNVector3(0.12, 1.85, -4.92)
        roomRootNode.addChildNode(backWallNode)

        let leftBaseGeo = SCNBox(width: 0.05, height: 0.18, length: 9.84, chamferRadius: 0.008)
        leftBaseGeo.materials = [baseboardMaterial]
        let leftBaseNode = SCNNode(geometry: leftBaseGeo)
        leftBaseNode.position = SCNVector3(-5.475, 0.09, 0.12)
        roomRootNode.addChildNode(leftBaseNode)

        let backBaseGeo = SCNBox(width: 11.19, height: 0.18, length: 0.05, chamferRadius: 0.008)
        backBaseGeo.materials = [baseboardMaterial]
        let backBaseNode = SCNNode(geometry: backBaseGeo)
        backBaseNode.position = SCNVector3(0.145, 0.09, -4.775)
        roomRootNode.addChildNode(backBaseNode)

        // 5. Low Architectural Interior Partitions Separating the 4 Rooms (with Wide Open Hallways)
        buildInteriorPartitions()

        // 6. Room 1: Living Lounge (Back-Left) — Window + Sofa + Side Table + Plant + Rug
        buildWindowOnLeftWall()
        buildLoungeRoom()

        // 7. Room 2: Dev Studio (Back-Right) — Workstation Desk + Chair + Lamp + Bookshelf
        buildStudioRoom()

        // 8. Room 3: Collab Hub (Front-Left) — Round Collaboration Table + Briefing Board
        buildCollabRoom()

        // 9. Room 4: Creative Lab (Front-Right) — Floating Holo Plinth + Maker Bench + Planter
        buildLabRoom()
    }

    private func buildFloorPlanks() {
        let plankCount = 16
        let totalWidth: CGFloat = 11.0
        let plankWidth = totalWidth / CGFloat(plankCount)
        let plankLength: CGFloat = 9.6

        floorPlankMaterials = (0..<4).map { idx in
            let delta = CGFloat(idx) * 0.020
            return makePBRMaterial(
                color: NSColor(srgbRed: 0.62 - delta, green: 0.48 - delta * 0.8, blue: 0.34 - delta * 0.6, alpha: 1),
                roughness: 0.58,
                metalness: 0.04
            )
        }

        for i in 0..<plankCount {
            let x = -totalWidth * 0.5 + plankWidth * (CGFloat(i) + 0.5)
            let splitOffset = (i % 2 == 0) ? 0.9 : -0.95
            let lenA = plankLength * 0.5 + splitOffset
            let lenB = plankLength - lenA

            let geoA = SCNBox(width: plankWidth - 0.02, height: 0.03, length: lenA - 0.02, chamferRadius: 0.004)
            geoA.materials = [floorPlankMaterials[i % floorPlankMaterials.count]]
            let nodeA = SCNNode(geometry: geoA)
            nodeA.position = SCNVector3(Float(x), -0.015, Float(-plankLength * 0.5 + lenA * 0.5))
            roomRootNode.addChildNode(nodeA)

            let geoB = SCNBox(width: plankWidth - 0.02, height: 0.03, length: lenB - 0.02, chamferRadius: 0.004)
            geoB.materials = [floorPlankMaterials[(i + 2) % floorPlankMaterials.count]]
            let nodeB = SCNNode(geometry: geoB)
            nodeB.position = SCNVector3(Float(x), -0.015, Float(plankLength * 0.5 - lenB * 0.5))
            roomRootNode.addChildNode(nodeB)
        }
    }

    private func buildRoomZonesAndHighlightFrames() {
        for kind in PipiHomeRoomKind.allCases {
            guard let spec = Self.roomSpecs[kind] else { continue }
            let w = CGFloat(spec.maxX - spec.minX) - 0.24
            let l = CGFloat(spec.maxZ - spec.minZ) - 0.24
            let cx = (spec.minX + spec.maxX) * 0.5
            let cz = (spec.minZ + spec.maxZ) * 0.5

            // Subtle inset zone flooring mat (y = 0.001 .. 0.008)
            let padMat = makePBRMaterial(color: NSColor(srgbRed: 0.78, green: 0.76, blue: 0.72, alpha: 0.28), roughness: 0.88)
            roomPadMaterials[kind] = padMat
            let padGeo = SCNBox(width: w, height: 0.007, length: l, chamferRadius: 0.003)
            padGeo.materials = [padMat]
            let padNode = SCNNode(geometry: padGeo)
            padNode.position = SCNVector3(cx, 0.004, cz)
            roomRootNode.addChildNode(padNode)

            // Crisp 4-bar Drop-Zone Perimeter Frame (y = 0.013, glows when dragging an agent over this room!)
            let frameMat = SCNMaterial()
            frameMat.lightingModel = .constant
            frameMat.diffuse.contents = Self.roomAccentColor(for: kind).withAlphaComponent(0.10)
            frameMat.writesToDepthBuffer = false
            roomFrameMaterials[kind] = frameMat
            roomHighlightAlpha[kind] = 0.10

            let barThickness: CGFloat = 0.08
            let barHeight: CGFloat = 0.010
            let halfW = Float(w) * 0.5
            let halfL = Float(l) * 0.5

            let frameGroup = SCNNode()
            frameGroup.position = SCNVector3(cx, 0.013, cz)
            frameGroup.renderingOrder = 2

            for zSign: Float in [-1, 1] {
                let hBar = SCNNode(geometry: SCNBox(width: w, height: barHeight, length: barThickness, chamferRadius: 0.004))
                hBar.geometry?.materials = [frameMat]
                hBar.position = SCNVector3(0, 0, zSign * (halfL - Float(barThickness) * 0.5))
                frameGroup.addChildNode(hBar)
            }
            for xSign: Float in [-1, 1] {
                let vBar = SCNNode(geometry: SCNBox(width: barThickness, height: barHeight, length: l - barThickness * 2, chamferRadius: 0.004))
                vBar.geometry?.materials = [frameMat]
                vBar.position = SCNVector3(xSign * (halfW - Float(barThickness) * 0.5), 0, 0)
                frameGroup.addChildNode(vBar)
            }
            roomRootNode.addChildNode(frameGroup)
        }
    }

    private func buildInteriorPartitions() {
        partitionBaseMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.82, green: 0.80, blue: 0.76, alpha: 1), roughness: 0.72)
        partitionGlassMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.76, green: 0.86, blue: 0.94, alpha: 0.24), roughness: 0.14, metalness: 0.08)
        partitionGlassMaterial.writesToDepthBuffer = false
        partitionAccentMaterial = SCNMaterial()
        partitionAccentMaterial.lightingModel = .constant
        partitionAccentMaterial.diffuse.contents = NSColor(srgbRed: 0.58, green: 0.52, blue: 0.44, alpha: 1)

        func addPartitionSegment(center: SIMD3<Float>, width: CGFloat, length: CGFloat) {
            let lowerH: CGFloat = 0.82
            let glassH: CGFloat = 0.34

            let lower = SCNNode(geometry: SCNBox(width: width, height: lowerH, length: length, chamferRadius: 0.02))
            lower.geometry?.materials = [partitionBaseMaterial]
            lower.position = SCNVector3(center.x, Float(lowerH * 0.5), center.z)
            roomRootNode.addChildNode(lower)

            let rail = SCNNode(geometry: SCNBox(width: width + 0.02, height: 0.036, length: length + 0.02, chamferRadius: 0.008))
            rail.geometry?.materials = [partitionAccentMaterial]
            rail.position = SCNVector3(center.x, Float(lowerH + 0.018), center.z)
            roomRootNode.addChildNode(rail)

            let glassW = width > length ? width - 0.08 : 0.04
            let glassL = length > width ? length - 0.08 : 0.04
            let glass = SCNNode(geometry: SCNBox(width: glassW, height: glassH, length: glassL, chamferRadius: 0.006))
            glass.geometry?.materials = [partitionGlassMaterial]
            glass.position = SCNVector3(center.x, Float(lowerH + 0.036 + glassH * 0.5), center.z)
            glass.renderingOrder = 4
            roomRootNode.addChildNode(glass)
        }

        // Back center vertical stub (x = 0, z: -4.76 .. -2.30)
        addPartitionSegment(center: SIMD3<Float>(0, 0, -3.53), width: 0.14, length: 2.46)
        // Front center vertical stub (x = 0, z: 2.30 .. 4.60)
        addPartitionSegment(center: SIMD3<Float>(0, 0, 3.45), width: 0.14, length: 2.30)
        // Left center horizontal stub (x: -5.45 .. -2.55, z = 0)
        addPartitionSegment(center: SIMD3<Float>(-4.00, 0, 0), width: 2.90, length: 0.14)
        // Right center horizontal stub (x: 2.55 .. 5.35, z = 0)
        addPartitionSegment(center: SIMD3<Float>(3.95, 0, 0), width: 2.80, length: 0.14)
    }

    private func buildWindowOnLeftWall() {
        let windowGroup = SCNNode()
        windowGroup.position = SCNVector3(-5.45, 2.00, -2.40)
        roomRootNode.addChildNode(windowGroup)

        windowFrameMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.94, green: 0.93, blue: 0.90, alpha: 1), roughness: 0.45)

        let topBar = SCNNode(geometry: SCNBox(width: 0.10, height: 0.10, length: 2.40, chamferRadius: 0.015))
        topBar.geometry?.materials = [windowFrameMaterial]
        topBar.position = SCNVector3(0.03, 0.88, 0)
        windowGroup.addChildNode(topBar)

        let sillBar = SCNNode(geometry: SCNBox(width: 0.22, height: 0.09, length: 2.56, chamferRadius: 0.018))
        sillBar.geometry?.materials = [windowFrameMaterial]
        sillBar.position = SCNVector3(0.08, -0.88, 0)
        windowGroup.addChildNode(sillBar)

        for zOff in [-1.15, 0.0, 1.15] as [Float] {
            let post = SCNNode(geometry: SCNBox(width: 0.09, height: 1.66, length: zOff == 0 ? 0.06 : 0.10, chamferRadius: 0.01))
            post.geometry?.materials = [windowFrameMaterial]
            post.position = SCNVector3(0.03, 0, zOff)
            windowGroup.addChildNode(post)
        }
        let midCross = SCNNode(geometry: SCNBox(width: 0.08, height: 0.06, length: 2.20, chamferRadius: 0.01))
        midCross.geometry?.materials = [windowFrameMaterial]
        midCross.position = SCNVector3(0.035, 0, 0)
        windowGroup.addChildNode(midCross)

        // Optional Shoji Lattice Bars (shown in Zen Study preset)
        shojiLatticeNode = SCNNode()
        for zOff in [-0.75, -0.38, 0.38, 0.75] as [Float] {
            let slat = SCNNode(geometry: SCNBox(width: 0.03, height: 1.64, length: 0.025, chamferRadius: 0.004))
            slat.geometry?.materials = [windowFrameMaterial]
            slat.position = SCNVector3(0.04, 0, zOff)
            shojiLatticeNode.addChildNode(slat)
        }
        for yOff in [-0.42, 0.42] as [Float] {
            let hSlat = SCNNode(geometry: SCNBox(width: 0.03, height: 0.025, length: 2.20, chamferRadius: 0.004))
            hSlat.geometry?.materials = [windowFrameMaterial]
            hSlat.position = SCNVector3(0.04, yOff, 0)
            shojiLatticeNode.addChildNode(hSlat)
        }
        shojiLatticeNode.isHidden = true
        windowGroup.addChildNode(shojiLatticeNode)

        // Sky backdrop
        let skyPlane = SCNPlane(width: 2.20, height: 1.66)
        let skyMat = SCNMaterial()
        skyMat.lightingModel = .constant
        skyPlane.materials = [skyMat]
        windowBackdropNode = SCNNode(geometry: skyPlane)
        windowBackdropNode.eulerAngles = SCNVector3(0, Float.pi * 0.5, 0)
        windowBackdropNode.position = SCNVector3(-0.012, 0, 0)
        windowGroup.addChildNode(windowBackdropNode)

        // Stars + Moon (shown in Dark Mode or Cyber Command preset)
        windowStarsNode = SCNNode()
        let starMat = SCNMaterial()
        starMat.lightingModel = .constant
        starMat.diffuse.contents = NSColor(srgbRed: 0.94, green: 0.97, blue: 1.0, alpha: 0.95)
        let starCoords: [(Float, Float, CGFloat)] = [
            (0.45, -0.72, 0.022), (0.58, 0.35, 0.018), (0.28, 0.78, 0.025),
            (0.64, -0.18, 0.015), (-0.18, 0.55, 0.020), (-0.36, -0.48, 0.016),
            (0.15, -0.82, 0.019), (0.42, 0.88, 0.016), (-0.42, 0.22, 0.015),
            (-0.05, -0.20, 0.018), (0.12, 0.42, 0.016)
        ]
        for (sy, sz, sr) in starCoords {
            let dot = SCNNode(geometry: SCNSphere(radius: sr))
            dot.geometry?.materials = [starMat]
            dot.position = SCNVector3(0.016, sy, sz)
            windowStarsNode.addChildNode(dot)
        }
        windowGroup.addChildNode(windowStarsNode)

        let moonGeo = SCNSphere(radius: 0.14)
        let moonMat = SCNMaterial()
        moonMat.lightingModel = .constant
        moonMat.diffuse.contents = NSColor(srgbRed: 0.99, green: 0.93, blue: 0.76, alpha: 1.0)
        moonGeo.materials = [moonMat]
        windowMoonNode = SCNNode(geometry: moonGeo)
        windowMoonNode.position = SCNVector3(0.020, 0.42, -0.58)
        windowGroup.addChildNode(windowMoonNode)

        // Subtle warm light shaft on lounge floor
        let beamPlane = SCNPlane(width: 2.1, height: 2.7)
        let beamMat = SCNMaterial()
        beamMat.lightingModel = .constant
        beamMat.diffuse.contents = NSColor(srgbRed: 1.0, green: 0.94, blue: 0.80, alpha: 0.07)
        beamMat.isDoubleSided = false
        beamMat.writesToDepthBuffer = false
        beamPlane.materials = [beamMat]
        sunBeamNode = SCNNode(geometry: beamPlane)
        sunBeamNode.position = SCNVector3(-3.8, 0.024, -2.35)
        sunBeamNode.eulerAngles = SCNVector3(-Float.pi * 0.5, 0.12, 0)
        sunBeamNode.renderingOrder = 1
        roomRootNode.addChildNode(sunBeamNode)
    }

    private func buildLoungeRoom() {
        // Woven Lounge Area Rug (strictly stacked strata above room pad y=0.008)
        let rugBorderGeo = SCNBox(width: 2.95, height: 0.009, length: 1.95, chamferRadius: 0.004)
        rugTrimMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.65, green: 0.60, blue: 0.54, alpha: 1), roughness: 0.92)
        rugBorderGeo.materials = [rugTrimMaterial]
        let rugBorderNode = SCNNode(geometry: rugBorderGeo)
        rugBorderNode.position = SCNVector3(-2.85, 0.0125, -1.95)
        roomRootNode.addChildNode(rugBorderNode)

        let rugGeo = SCNBox(width: 2.75, height: 0.009, length: 1.75, chamferRadius: 0.004)
        rugMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.82, green: 0.79, blue: 0.74, alpha: 1), roughness: 0.95)
        rugGeo.materials = [rugMaterial]
        let rugNode = SCNNode(geometry: rugGeo)
        rugNode.position = SCNVector3(-2.85, 0.0215, -1.95)
        roomRootNode.addChildNode(rugNode)

        // Plush Rounded Sofa (Back-Left against back wall)
        let sofaGroup = SCNNode()
        sofaGroup.position = SCNVector3(-3.05, 0, -3.65)
        roomRootNode.addChildNode(sofaGroup)

        sofaMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.36, green: 0.45, blue: 0.56, alpha: 1), roughness: 0.88)
        let legWoodMat = makePBRMaterial(color: NSColor(srgbRed: 0.48, green: 0.34, blue: 0.22, alpha: 1), roughness: 0.55)

        let seatBase = SCNNode(geometry: SCNBox(width: 2.10, height: 0.32, length: 0.92, chamferRadius: 0.12))
        seatBase.geometry?.materials = [sofaMaterial]
        seatBase.position = SCNVector3(0, 0.28, 0)
        sofaGroup.addChildNode(seatBase)

        let backRest = SCNNode(geometry: SCNBox(width: 2.10, height: 0.60, length: 0.26, chamferRadius: 0.10))
        backRest.geometry?.materials = [sofaMaterial]
        backRest.position = SCNVector3(0, 0.58, -0.34)
        sofaGroup.addChildNode(backRest)

        for ax in [-0.93, 0.93] as [Float] {
            let arm = SCNNode(geometry: SCNBox(width: 0.24, height: 0.46, length: 0.92, chamferRadius: 0.10))
            arm.geometry?.materials = [sofaMaterial]
            arm.position = SCNVector3(ax, 0.41, 0)
            sofaGroup.addChildNode(arm)
        }

        let pillowAMat = makePBRMaterial(color: NSColor(srgbRed: 0.88, green: 0.66, blue: 0.36, alpha: 1), roughness: 0.90)
        let pillowA = SCNNode(geometry: SCNBox(width: 0.34, height: 0.30, length: 0.13, chamferRadius: 0.06))
        pillowA.geometry?.materials = [pillowAMat]
        pillowA.position = SCNVector3(-0.62, 0.54, -0.14)
        pillowA.eulerAngles = SCNVector3(-0.22, 0.25, 0.10)
        sofaGroup.addChildNode(pillowA)

        let pillowBMat = makePBRMaterial(color: NSColor(srgbRed: 0.32, green: 0.70, blue: 0.78, alpha: 1), roughness: 0.90)
        let pillowB = SCNNode(geometry: SCNBox(width: 0.32, height: 0.28, length: 0.13, chamferRadius: 0.06))
        pillowB.geometry?.materials = [pillowBMat]
        pillowB.position = SCNVector3(0.64, 0.53, -0.14)
        pillowB.eulerAngles = SCNVector3(-0.20, -0.24, -0.08)
        sofaGroup.addChildNode(pillowB)

        for lx in [-0.85, 0.85] as [Float] {
            for lz in [-0.34, 0.34] as [Float] {
                let leg = SCNNode(geometry: SCNCylinder(radius: 0.038, height: 0.16))
                leg.geometry?.materials = [legWoodMat]
                leg.position = SCNVector3(lx, 0.08, lz)
                sofaGroup.addChildNode(leg)
            }
        }

        // Side Table + Ceramic Coffee Mug
        let sideTableGroup = SCNNode()
        sideTableGroup.position = SCNVector3(-1.35, 0, -3.72)
        roomRootNode.addChildNode(sideTableGroup)

        let tableTop = SCNNode(geometry: SCNCylinder(radius: 0.34, height: 0.045))
        tableTop.geometry?.materials = [legWoodMat]
        tableTop.position = SCNVector3(0, 0.56, 0)
        sideTableGroup.addChildNode(tableTop)

        let tableLeg = SCNNode(geometry: SCNCylinder(radius: 0.038, height: 0.55))
        tableLeg.geometry?.materials = [legWoodMat]
        tableLeg.position = SCNVector3(0, 0.275, 0)
        sideTableGroup.addChildNode(tableLeg)

        let tableFoot = SCNNode(geometry: SCNCylinder(radius: 0.19, height: 0.03))
        tableFoot.geometry?.materials = [legWoodMat]
        tableFoot.position = SCNVector3(0, 0.015, 0)
        sideTableGroup.addChildNode(tableFoot)

        let mugMat = makePBRMaterial(color: NSColor(srgbRed: 0.94, green: 0.93, blue: 0.90, alpha: 1), roughness: 0.22)
        let mugBody = SCNNode(geometry: SCNCylinder(radius: 0.06, height: 0.11))
        mugBody.geometry?.materials = [mugMat]
        mugBody.position = SCNVector3(0.04, 0.635, 0.02)
        sideTableGroup.addChildNode(mugBody)

        // Tall Potted Plant (Back-Left Corner)
        buildPottedPlant(at: SCNVector3(-4.72, 0, -4.08), scale: 1.0)
    }

    private func buildStudioRoom() {
        deskWoodMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.52, green: 0.37, blue: 0.25, alpha: 1), roughness: 0.45)
        shelfWoodMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.56, green: 0.41, blue: 0.28, alpha: 1), roughness: 0.52)
        let metalMat = makePBRMaterial(color: NSColor(srgbRed: 0.22, green: 0.25, blue: 0.30, alpha: 1), roughness: 0.32, metalness: 0.72)
        let aluminumMat = makePBRMaterial(color: NSColor(srgbRed: 0.76, green: 0.79, blue: 0.83, alpha: 1), roughness: 0.28, metalness: 0.78)

        // 1. Developer Workstation Desk (Back-Right)
        let deskGroup = SCNNode()
        deskGroup.position = SCNVector3(3.15, 0, -3.72)
        roomRootNode.addChildNode(deskGroup)

        let top = SCNNode(geometry: SCNBox(width: 2.35, height: 0.08, length: 1.12, chamferRadius: 0.025))
        top.geometry?.materials = [deskWoodMaterial]
        top.position = SCNVector3(0, 0.90, 0)
        deskGroup.addChildNode(top)

        for lx in [-1.05, 1.05] as [Float] {
            for lz in [-0.45, 0.45] as [Float] {
                let leg = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 0.88))
                leg.geometry?.materials = [metalMat]
                leg.position = SCNVector3(lx, 0.44, lz)
                deskGroup.addChildNode(leg)
            }
        }

        // Studio Monitor Stand + Bezel + Screen
        let standFoot = SCNNode(geometry: SCNBox(width: 0.38, height: 0.024, length: 0.26, chamferRadius: 0.01))
        standFoot.geometry?.materials = [aluminumMat]
        standFoot.position = SCNVector3(-0.08, 0.952, -0.22)
        deskGroup.addChildNode(standFoot)

        let standNeck = SCNNode(geometry: SCNBox(width: 0.08, height: 0.28, length: 0.04, chamferRadius: 0.01))
        standNeck.geometry?.materials = [aluminumMat]
        standNeck.position = SCNVector3(-0.08, 1.09, -0.28)
        deskGroup.addChildNode(standNeck)

        let monitorBezel = SCNNode(geometry: SCNBox(width: 1.24, height: 0.68, length: 0.045, chamferRadius: 0.02))
        monitorBezel.geometry?.materials = [metalMat]
        monitorBezel.position = SCNVector3(-0.08, 1.44, -0.24)
        deskGroup.addChildNode(monitorBezel)

        let screenGeo = SCNPlane(width: 1.16, height: 0.60)
        monitorScreenMaterial.lightingModel = .constant
        monitorScreenMaterial.diffuse.contents = NSColor(srgbRed: 0.22, green: 0.36, blue: 0.56, alpha: 1)
        screenGeo.materials = [monitorScreenMaterial]
        let screenNode = SCNNode(geometry: screenGeo)
        screenNode.position = SCNVector3(-0.08, 1.44, -0.208)
        deskGroup.addChildNode(screenNode)

        // Keyboard + Trackpad
        let kb = SCNNode(geometry: SCNBox(width: 0.46, height: 0.018, length: 0.17, chamferRadius: 0.008))
        kb.geometry?.materials = [aluminumMat]
        kb.position = SCNVector3(-0.14, 0.95, 0.14)
        deskGroup.addChildNode(kb)

        let pad = SCNNode(geometry: SCNBox(width: 0.16, height: 0.014, length: 0.15, chamferRadius: 0.008))
        pad.geometry?.materials = [aluminumMat]
        pad.position = SCNVector3(0.24, 0.948, 0.15)
        deskGroup.addChildNode(pad)

        // Warm Desk Lamp
        let lampBase = SCNNode(geometry: SCNCylinder(radius: 0.11, height: 0.03))
        lampBase.geometry?.materials = [metalMat]
        lampBase.position = SCNVector3(0.84, 0.955, -0.24)
        deskGroup.addChildNode(lampBase)

        let lampStem = SCNNode(geometry: SCNCylinder(radius: 0.018, height: 0.46))
        lampStem.geometry?.materials = [aluminumMat]
        lampStem.position = SCNVector3(0.86, 1.17, -0.26)
        lampStem.eulerAngles = SCNVector3(0.18, 0, 0.14)
        deskGroup.addChildNode(lampStem)

        let lampShadeMat = makePBRMaterial(color: NSColor(srgbRed: 0.90, green: 0.76, blue: 0.54, alpha: 1), roughness: 0.42)
        let lampShade = SCNNode(geometry: SCNCone(topRadius: 0.07, bottomRadius: 0.16, height: 0.18))
        lampShade.geometry?.materials = [lampShadeMat]
        lampShade.position = SCNVector3(0.76, 1.40, -0.16)
        lampShade.eulerAngles = SCNVector3(0.22, 0, 0.25)
        deskGroup.addChildNode(lampShade)

        // Tucked Studio Chair
        let chairGroup = SCNNode()
        chairGroup.position = SCNVector3(-0.05, 0, 0.60)
        deskGroup.addChildNode(chairGroup)

        let chairFabric = makePBRMaterial(color: NSColor(srgbRed: 0.26, green: 0.30, blue: 0.38, alpha: 1), roughness: 0.88)
        let chairSeat = SCNNode(geometry: SCNBox(width: 0.58, height: 0.11, length: 0.54, chamferRadius: 0.05))
        chairSeat.geometry?.materials = [chairFabric]
        chairSeat.position = SCNVector3(0, 0.52, 0)
        chairGroup.addChildNode(chairSeat)

        let chairBack = SCNNode(geometry: SCNBox(width: 0.54, height: 0.54, length: 0.10, chamferRadius: 0.045))
        chairBack.geometry?.materials = [chairFabric]
        chairBack.position = SCNVector3(0, 0.83, 0.22)
        chairBack.eulerAngles = SCNVector3(0.08, 0, 0)
        chairGroup.addChildNode(chairBack)

        let chairStem = SCNNode(geometry: SCNCylinder(radius: 0.038, height: 0.42))
        chairStem.geometry?.materials = [metalMat]
        chairStem.position = SCNVector3(0, 0.26, 0)
        chairGroup.addChildNode(chairStem)

        let chairBase = SCNNode(geometry: SCNCylinder(radius: 0.26, height: 0.04))
        chairBase.geometry?.materials = [metalMat]
        chairBase.position = SCNVector3(0, 0.04, 0)
        chairGroup.addChildNode(chairBase)

        // 2. Reference Bookshelf along Back Wall (left side of Studio)
        let shelfGroup = SCNNode()
        shelfGroup.position = SCNVector3(0.95, 0, -4.35)
        roomRootNode.addChildNode(shelfGroup)

        let shelfBack = SCNNode(geometry: SCNBox(width: 1.06, height: 2.15, length: 0.04, chamferRadius: 0.008))
        shelfBack.geometry?.materials = [shelfWoodMaterial]
        shelfBack.position = SCNVector3(0, 1.075, -0.22)
        shelfGroup.addChildNode(shelfBack)

        for sx in [-0.56, 0.56] as [Float] {
            let side = SCNNode(geometry: SCNBox(width: 0.06, height: 2.15, length: 0.44, chamferRadius: 0.008))
            side.geometry?.materials = [shelfWoodMaterial]
            side.position = SCNVector3(sx, 1.075, 0)
            shelfGroup.addChildNode(side)
        }

        for sy in [0.12, 0.78, 1.44, 2.10] as [Float] {
            let plank = SCNNode(geometry: SCNBox(width: 1.056, height: 0.05, length: 0.40, chamferRadius: 0.008))
            plank.geometry?.materials = [shelfWoodMaterial]
            plank.position = SCNVector3(0, sy, 0.01)
            shelfGroup.addChildNode(plank)
        }

        let spineColors: [NSColor] = [
            NSColor(srgbRed: 0.30, green: 0.44, blue: 0.86, alpha: 1),
            NSColor(srgbRed: 0.16, green: 0.64, blue: 0.48, alpha: 1),
            NSColor(srgbRed: 0.86, green: 0.58, blue: 0.18, alpha: 1),
            NSColor(srgbRed: 0.18, green: 0.60, blue: 0.84, alpha: 1),
            NSColor(srgbRed: 0.82, green: 0.28, blue: 0.36, alpha: 1),
            NSColor(srgbRed: 0.82, green: 0.80, blue: 0.74, alpha: 1)
        ]

        for (rowIdx, baseY) in [0.15, 0.81, 1.47].enumerated() {
            var cursorX: Float = -0.46
            for b in 0..<6 {
                let bw: Float = 0.085 + Float((b + rowIdx) % 3) * 0.02
                let bh: Float = 0.32 + Float((b * 2 + rowIdx) % 4) * 0.04
                let book = SCNNode(geometry: SCNBox(width: CGFloat(bw), height: CGFloat(bh), length: 0.28, chamferRadius: 0.008))
                book.geometry?.materials = [makePBRMaterial(color: spineColors[(b + rowIdx * 2) % spineColors.count], roughness: 0.65)]
                book.position = SCNVector3(cursorX + bw * 0.5, Float(baseY) + bh * 0.5, 0.02)
                shelfGroup.addChildNode(book)
                cursorX += bw + 0.014
            }
        }
    }

    private func buildCollabRoom() {
        // 1. Round Collaboration Table (Front-Left Center)
        let tableGroup = SCNNode()
        tableGroup.position = SCNVector3(-2.75, 0, 2.35)
        roomRootNode.addChildNode(tableGroup)

        tableTopMaterial = makePBRMaterial(color: NSColor(srgbRed: 0.82, green: 0.78, blue: 0.73, alpha: 1), roughness: 0.40)
        let legMat = makePBRMaterial(color: NSColor(srgbRed: 0.45, green: 0.33, blue: 0.23, alpha: 1), roughness: 0.50)

        let top = SCNNode(geometry: SCNCylinder(radius: 0.80, height: 0.055))
        top.geometry?.materials = [tableTopMaterial]
        top.position = SCNVector3(0, 0.46, 0)
        tableGroup.addChildNode(top)

        let ringGeo = SCNTorus(ringRadius: 0.42, pipeRadius: 0.018)
        collabTableRingMaterial.lightingModel = .constant
        collabTableRingMaterial.diffuse.contents = NSColor(srgbRed: 0.28, green: 0.56, blue: 0.96, alpha: 0.24)
        ringGeo.materials = [collabTableRingMaterial]
        let ringNode = SCNNode(geometry: ringGeo)
        ringNode.position = SCNVector3(0, 0.492, 0)
        tableGroup.addChildNode(ringNode)

        for i in 0..<3 {
            let angle = Float(i) * (Float.pi * 2.0 / 3.0) + 0.35
            let leg = SCNNode(geometry: SCNCylinder(radius: 0.036, height: 0.46))
            leg.geometry?.materials = [legMat]
            leg.position = SCNVector3(cos(angle) * 0.40, 0.22, sin(angle) * 0.40)
            leg.eulerAngles = SCNVector3(sin(angle) * 0.16, 0, -cos(angle) * 0.16)
            tableGroup.addChildNode(leg)
        }

        // 2. Wall-Mounted Briefing Whiteboard on Left Wall
        let boardGroup = SCNNode()
        boardGroup.position = SCNVector3(-5.36, 1.55, 2.35)
        roomRootNode.addChildNode(boardGroup)

        let frameMat = makePBRMaterial(color: NSColor(srgbRed: 0.26, green: 0.30, blue: 0.36, alpha: 1), roughness: 0.42, metalness: 0.55)
        let boardFrame = SCNNode(geometry: SCNBox(width: 0.06, height: 1.25, length: 2.15, chamferRadius: 0.018))
        boardFrame.geometry?.materials = [frameMat]
        boardGroup.addChildNode(boardFrame)

        let boardSurface = SCNNode(geometry: SCNBox(width: 0.02, height: 1.12, length: 2.02, chamferRadius: 0.008))
        boardSurface.geometry?.materials = [makePBRMaterial(color: NSColor(srgbRed: 0.88, green: 0.90, blue: 0.93, alpha: 1), roughness: 0.32)]
        boardSurface.position = SCNVector3(0.032, 0, 0)
        boardGroup.addChildNode(boardSurface)

        // Sticky note accents on briefing board
        let stickyColors: [NSColor] = [
            NSColor(srgbRed: 0.94, green: 0.78, blue: 0.34, alpha: 1),
            NSColor(srgbRed: 0.42, green: 0.76, blue: 0.92, alpha: 1),
            NSColor(srgbRed: 0.44, green: 0.80, blue: 0.58, alpha: 1),
            NSColor(srgbRed: 0.92, green: 0.54, blue: 0.62, alpha: 1)
        ]
        for i in 0..<4 {
            let note = SCNNode(geometry: SCNBox(width: 0.012, height: 0.20, length: 0.24, chamferRadius: 0.004))
            note.geometry?.materials = [makePBRMaterial(color: stickyColors[i], roughness: 0.75)]
            note.position = SCNVector3(0.048, 0.20 - Float(i % 2) * 0.30, -0.58 + Float(i) * 0.38)
            boardGroup.addChildNode(note)
        }
    }

    private func buildLabRoom() {
        let metalMat = makePBRMaterial(color: NSColor(srgbRed: 0.24, green: 0.28, blue: 0.34, alpha: 1), roughness: 0.35, metalness: 0.68)

        // 1. Floating Holographic Display Plinth (Center of Lab)
        let plinthGroup = SCNNode()
        plinthGroup.position = SCNVector3(3.20, 0, 2.55)
        roomRootNode.addChildNode(plinthGroup)

        let pedBase = SCNNode(geometry: SCNCylinder(radius: 0.54, height: 0.08))
        pedBase.geometry?.materials = [metalMat]
        pedBase.position = SCNVector3(0, 0.04, 0)
        plinthGroup.addChildNode(pedBase)

        let pedCol = SCNNode(geometry: SCNCylinder(radius: 0.34, height: 0.56))
        pedCol.geometry?.materials = [tableTopMaterial]
        pedCol.position = SCNVector3(0, 0.36, 0)
        plinthGroup.addChildNode(pedCol)

        let emitterRing = SCNNode(geometry: SCNTorus(ringRadius: 0.30, pipeRadius: 0.018))
        holoCrystalMaterial.lightingModel = .constant
        holoCrystalMaterial.diffuse.contents = NSColor(srgbRed: 0.32, green: 0.74, blue: 0.98, alpha: 0.85)
        emitterRing.geometry?.materials = [holoCrystalMaterial]
        emitterRing.position = SCNVector3(0, 0.66, 0)
        plinthGroup.addChildNode(emitterRing)

        // Gently hovering geometric holo crystal
        let crystalGeo = SCNBox(width: 0.30, height: 0.30, length: 0.30, chamferRadius: 0.04)
        crystalGeo.materials = [holoCrystalMaterial]
        holoCrystalNode = SCNNode(geometry: crystalGeo)
        holoCrystalNode.position = SCNVector3(0, 1.06, 0)
        holoCrystalNode.eulerAngles = SCNVector3(0.65, 0.45, 0.45)
        plinthGroup.addChildNode(holoCrystalNode)

        // 2. Low Maker Workbench along Right Edge
        let benchGroup = SCNNode()
        benchGroup.position = SCNVector3(4.78, 0, 2.55)
        roomRootNode.addChildNode(benchGroup)

        let benchBody = SCNNode(geometry: SCNBox(width: 0.68, height: 0.72, length: 2.15, chamferRadius: 0.03))
        benchBody.geometry?.materials = [deskWoodMaterial]
        benchBody.position = SCNVector3(0, 0.36, 0)
        benchGroup.addChildNode(benchBody)

        let benchTop = SCNNode(geometry: SCNBox(width: 0.74, height: 0.06, length: 2.22, chamferRadius: 0.02))
        benchTop.geometry?.materials = [tableTopMaterial]
        benchTop.position = SCNVector3(0, 0.75, 0)
        benchGroup.addChildNode(benchTop)

        // 3. Compact Planter at front-right corner of Lab
        buildPottedPlant(at: SCNVector3(4.62, 0, 0.85), scale: 0.72)
    }

    private func buildPottedPlant(at position: SCNVector3, scale: Float) {
        let plantGroup = SCNNode()
        plantGroup.position = position
        plantGroup.scale = SCNVector3(scale, scale, scale)
        roomRootNode.addChildNode(plantGroup)

        let potMat = makePBRMaterial(color: NSColor(srgbRed: 0.78, green: 0.48, blue: 0.36, alpha: 1), roughness: 0.72)
        let woodMat = makePBRMaterial(color: NSColor(srgbRed: 0.46, green: 0.33, blue: 0.22, alpha: 1), roughness: 0.58)
        let pot = SCNNode(geometry: SCNCylinder(radius: 0.26, height: 0.46))
        pot.geometry?.materials = [potMat]
        pot.position = SCNVector3(0, 0.23, 0)
        plantGroup.addChildNode(pot)

        let trunk = SCNNode(geometry: SCNCylinder(radius: 0.030, height: 0.80))
        trunk.geometry?.materials = [woodMat]
        trunk.position = SCNVector3(0, 0.82, 0)
        plantGroup.addChildNode(trunk)

        let leafDark = makePBRMaterial(color: NSColor(srgbRed: 0.18, green: 0.50, blue: 0.35, alpha: 1), roughness: 0.54)
        let leafBright = makePBRMaterial(color: NSColor(srgbRed: 0.28, green: 0.64, blue: 0.43, alpha: 1), roughness: 0.50)
        let clusters: [(Float, Float, Float, CGFloat, Bool)] = [
            (0.0, 1.36, 0.0, 0.25, true),
            (-0.20, 1.18, 0.15, 0.21, false),
            (0.22, 1.20, 0.13, 0.20, true),
            (0.06, 1.08, -0.18, 0.19, false),
            (-0.15, 1.00, -0.13, 0.17, true)
        ]
        for (fx, fy, fz, fr, bright) in clusters {
            let sphere = SCNNode(geometry: SCNSphere(radius: fr))
            sphere.scale = SCNVector3(1.12, 0.88, 1.04)
            sphere.geometry?.materials = [bright ? leafBright : leafDark]
            sphere.position = SCNVector3(fx, fy, fz)
            plantGroup.addChildNode(sphere)
        }
    }

    private func buildDragGuideVisuals() {
        dragGuideRingMaterial.lightingModel = .constant
        dragGuideRingMaterial.diffuse.contents = NSColor(srgbRed: 0.30, green: 0.64, blue: 1.0, alpha: 0.88)
        dragGuideRingMaterial.writesToDepthBuffer = false

        let dropRing = SCNNode(geometry: SCNTorus(ringRadius: 0.44, pipeRadius: 0.022))
        dropRing.geometry?.materials = [dragGuideRingMaterial]
        dropRing.position = SCNVector3(0, 0.025, 0)
        dragGuideNode.addChildNode(dropRing)

        dragGuideBeamMaterial.lightingModel = .constant
        dragGuideBeamMaterial.diffuse.contents = NSColor(srgbRed: 0.30, green: 0.64, blue: 1.0, alpha: 0.38)
        dragGuideBeamMaterial.writesToDepthBuffer = false
        let beam = SCNNode(geometry: SCNCylinder(radius: 0.022, height: 0.60))
        beam.geometry?.materials = [dragGuideBeamMaterial]
        beam.position = SCNVector3(0, 0.32, 0)
        dragGuideNode.addChildNode(beam)

        dragGuideNode.renderingOrder = 5
        dragGuideNode.isHidden = true
        scene.rootNode.addChildNode(dragGuideNode)
    }

    // MARK: - Procedural 3D Bot Characters

    private func syncBotRigs(items: [PipiHomeBotSyncItem], isDark: Bool) {
        let incomingIds = Set(items.map(\.id))

        for (existingId, rig) in botRigs where !incomingIds.contains(existingId) {
            rig.rootNode.removeFromParentNode()
            botRigs.removeValue(forKey: existingId)
        }

        for (idx, item) in items.enumerated() {
            if let rig = botRigs[item.id] {
                let roomChanged = rig.assignedRoom != item.room
                rig.accent = item.accent
                rig.visualState = item.state
                rig.assignedRoom = item.room
                if roomChanged, let spec = Self.roomSpecs[item.room] {
                    // Gently walk the bot to a fresh waypoint inside its newly assigned room
                    let wp = spec.waypoints[idx % spec.waypoints.count]
                    rig.walkTarget = wp
                    rig.pauseTimer = 0.0
                }
                updateRigColors(rig, isDark: isDark)
                updateRigAttachments(rig)
            } else {
                let spec = Self.roomSpecs[item.room] ?? Self.roomSpecs[.lounge]!
                let spawnPos = spec.waypoints[idx % spec.waypoints.count]
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

        // Generous invisible hit capsule for effortless click, hover & drag-pick
        let colliderGeo = SCNCapsule(capRadius: 0.42, height: 1.22)
        let colliderMat = SCNMaterial()
        colliderMat.colorBufferWriteMask = []
        colliderMat.writesToDepthBuffer = false
        colliderMat.readsFromDepthBuffer = false
        colliderGeo.materials = [colliderMat]
        let colliderNode = SCNNode(geometry: colliderGeo)
        colliderNode.position = SCNVector3(0, 0.58, 0)
        root.addChildNode(colliderNode)

        // Contact shadow
        let shadowGeo = SCNPlane(width: 0.84, height: 0.84)
        let shadowMat = SCNMaterial()
        shadowMat.lightingModel = .constant
        shadowMat.diffuse.contents = cachedRadialShadow
        shadowMat.writesToDepthBuffer = false
        shadowMat.isDoubleSided = false
        shadowGeo.materials = [shadowMat]
        let shadowNode = SCNNode(geometry: shadowGeo)
        shadowNode.position = SCNVector3(0, 0.006, 0)
        shadowNode.eulerAngles = SCNVector3(-Float.pi * 0.5, 0, 0)
        shadowNode.renderingOrder = 2
        root.addChildNode(shadowNode)

        // Floor selection / hover ring
        let floorRingGeo = SCNTorus(ringRadius: 0.36, pipeRadius: 0.018)
        let floorRingMat = SCNMaterial()
        floorRingMat.lightingModel = .constant
        floorRingGeo.materials = [floorRingMat]
        let floorRingNode = SCNNode(geometry: floorRingGeo)
        floorRingNode.position = SCNVector3(0, 0.024, 0)
        floorRingNode.renderingOrder = 3
        root.addChildNode(floorRingNode)

        let bodyGroup = SCNNode()
        root.addChildNode(bodyGroup)

        let chassisMat = makePBRMaterial(color: .white, roughness: 0.32, metalness: 0.14)
        let trimMat = makePBRMaterial(color: .gray, roughness: 0.28, metalness: 0.60)
        let visorMat = makePBRMaterial(color: NSColor(srgbRed: 0.05, green: 0.09, blue: 0.16, alpha: 1), roughness: 0.10, metalness: 0.22)
        let leftEyeMat = SCNMaterial()
        leftEyeMat.lightingModel = .constant
        let rightEyeMat = SCNMaterial()
        rightEyeMat.lightingModel = .constant

        let footGeo = SCNCapsule(capRadius: 0.068, height: 0.20)
        footGeo.materials = [trimMat]
        let leftFoot = SCNNode(geometry: footGeo)
        leftFoot.eulerAngles = SCNVector3(Float.pi * 0.5, 0, 0)
        leftFoot.position = SCNVector3(-0.12, 0.08, 0.02)
        bodyGroup.addChildNode(leftFoot)

        let rightFoot = SCNNode(geometry: footGeo)
        rightFoot.eulerAngles = SCNVector3(Float.pi * 0.5, 0, 0)
        rightFoot.position = SCNVector3(0.12, 0.08, 0.02)
        bodyGroup.addChildNode(rightFoot)

        let torso = SCNNode(geometry: SCNBox(width: 0.36, height: 0.32, length: 0.28, chamferRadius: 0.13))
        torso.geometry?.materials = [chassisMat]
        torso.position = SCNVector3(0, 0.31, 0)
        bodyGroup.addChildNode(torso)

        let chestBadge = SCNNode(geometry: SCNBox(width: 0.14, height: 0.045, length: 0.018, chamferRadius: 0.008))
        chestBadge.geometry?.materials = [leftEyeMat]
        chestBadge.position = SCNVector3(0, 0.32, 0.149)
        bodyGroup.addChildNode(chestBadge)

        let headGroup = SCNNode()
        headGroup.position = SCNVector3(0, 0.64, 0)
        bodyGroup.addChildNode(headGroup)

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

        let visor = SCNNode(geometry: SCNBox(width: 0.33, height: 0.20, length: 0.06, chamferRadius: 0.06))
        visor.geometry?.materials = [visorMat]
        visor.position = SCNVector3(0, 0.0, 0.155)
        headGroup.addChildNode(visor)

        let leftEye = SCNNode(geometry: SCNCapsule(capRadius: 0.036, height: 0.095))
        leftEye.geometry?.materials = [leftEyeMat]
        leftEye.position = SCNVector3(-0.072, 0.005, 0.186)
        headGroup.addChildNode(leftEye)

        let rightEye = SCNNode(geometry: SCNCapsule(capRadius: 0.036, height: 0.095))
        rightEye.geometry?.materials = [rightEyeMat]
        rightEye.position = SCNVector3(0.072, 0.005, 0.186)
        headGroup.addChildNode(rightEye)

        let orbitGeo = SCNTorus(ringRadius: 0.34, pipeRadius: 0.012)
        orbitGeo.materials = [leftEyeMat]
        let orbitRing = SCNNode(geometry: orbitGeo)
        orbitRing.position = SCNVector3(0, 0.42, 0)
        orbitRing.eulerAngles = SCNVector3(0.24, 0, 0.18)
        orbitRing.isHidden = true
        bodyGroup.addChildNode(orbitRing)

        let miniHolo = SCNNode()
        miniHolo.position = SCNVector3(0, 0.62, 0.46)
        miniHolo.eulerAngles = SCNVector3(-0.22, 0, 0)
        let holoPlane = SCNPlane(width: 0.38, height: 0.24)
        let holoMat = SCNMaterial()
        holoMat.lightingModel = .constant
        holoMat.diffuse.contents = NSColor(srgbRed: 0.22, green: 0.66, blue: 0.98, alpha: 0.72)
        holoMat.isDoubleSided = true
        holoPlane.materials = [holoMat]
        miniHolo.addChildNode(SCNNode(geometry: holoPlane))
        miniHolo.isHidden = true
        bodyGroup.addChildNode(miniHolo)

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
        bodyGroup.addChildNode(beaconGroup)

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
            assignedRoom: item.room,
            position: startPosition,
            heading: 0,
            phaseOffset: phaseOffset
        )

        updateRigColors(rig, isDark: isDark)
        updateRigAttachments(rig)
        return rig
    }

    private func updateRigColors(_ rig: BotRig, isDark: Bool) {
        let useDarkBody = isDark || (lastAppliedPreset == .cyberCommand)
        if useDarkBody {
            rig.chassisMaterial.diffuse.contents = NSColor(srgbRed: 0.17, green: 0.21, blue: 0.28, alpha: 1)
            rig.chassisMaterial.roughness.contents = 0.34
            rig.chassisMaterial.metalness.contents = 0.34
            rig.trimMaterial.diffuse.contents = NSColor(srgbRed: 0.36, green: 0.42, blue: 0.52, alpha: 1)
            rig.visorMaterial.diffuse.contents = NSColor(srgbRed: 0.04, green: 0.08, blue: 0.12, alpha: 1)
        } else {
            rig.chassisMaterial.diffuse.contents = NSColor(srgbRed: 0.85, green: 0.84, blue: 0.81, alpha: 1)
            rig.chassisMaterial.roughness.contents = 0.35
            rig.chassisMaterial.metalness.contents = 0.06
            rig.trimMaterial.diffuse.contents = NSColor(srgbRed: 0.60, green: 0.58, blue: 0.54, alpha: 1)
            rig.visorMaterial.diffuse.contents = NSColor(srgbRed: 0.09, green: 0.15, blue: 0.32, alpha: 1)
        }

        let eyeColor = Self.srgbEyeNSColor(for: rig.accent)
        let accentColor = Self.srgbAccentNSColor(for: rig.accent, isDark: useDarkBody)
        rig.cachedAccentColor = accentColor
        rig.lastRingAlpha = -1.0
        rig.leftEyeMaterial.diffuse.contents = eyeColor
        rig.rightEyeMaterial.diffuse.contents = eyeColor
        rig.floorRingMaterial.diffuse.contents = accentColor.withAlphaComponent(0.42)
    }

    private func updateRigAttachments(_ rig: BotRig) {
        rig.alertBeaconNode.isHidden = (rig.visualState != .needsYou)
        rig.orbitRingNode.isHidden = (rig.visualState != .working)
        if rig.visualState != .working {
            rig.miniHoloNode.isHidden = true
        }
    }

    // MARK: - 4 Preset Architectural Worlds × Light / Dark Calibrated Studio Lighting

    private func applyScenePreset(_ preset: PipiHomeScenePreset, isDark: Bool) {
        lastAppliedThemeDark = isDark
        lastAppliedPreset = preset
        lastMonitorWorkingState = nil
        lastCollabActiveState = nil

        let effectiveDark = isDark || (preset == .cyberCommand)
        scene.lightingEnvironment.contents = effectiveDark ? cachedEnvDark : cachedEnvLight
        scene.lightingEnvironment.intensity = effectiveDark ? 0.28 : 0.33
        shojiLatticeNode.isHidden = (preset != .zenPavilion)

        switch preset {
        case .warmStudio:
            if isDark {
                scene.background.contents = NSColor(srgbRed: 0.055, green: 0.068, blue: 0.090, alpha: 1)
                setLights(ambient: 135, ambColor: (0.72, 0.78, 0.94), key: 250, keyColor: (0.82, 0.88, 1.0), fill: 85, win: 135, winColor: (0.46, 0.62, 0.94), lamp: 310, lampColor: (1.0, 0.82, 0.54), holo: 130, holoColor: (0.34, 0.74, 0.98))
                setSurfaces(
                    plinth: (0.12, 0.11, 0.12), wall: (0.16, 0.19, 0.25), baseboard: (0.22, 0.25, 0.32),
                    partBase: (0.18, 0.21, 0.27), partAccent: (0.48, 0.38, 0.28),
                    plankBase: (0.24, 0.19, 0.15), plankStep: 0.015,
                    rug: (0.20, 0.23, 0.29), rugTrim: (0.28, 0.32, 0.40),
                    sofa: (0.24, 0.31, 0.42), desk: (0.28, 0.21, 0.15), tableTop: (0.26, 0.28, 0.34),
                    windowSky: (0.06, 0.10, 0.22), stars: true, sunBeam: false,
                    holo: (0.30, 0.72, 0.98)
                )
            } else {
                scene.background.contents = NSColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1)
                setLights(ambient: 185, ambColor: (0.98, 0.96, 0.94), key: 375, keyColor: (1.0, 0.96, 0.90), fill: 100, win: 165, winColor: (0.99, 0.95, 0.87), lamp: 110, lampColor: (1.0, 0.86, 0.64), holo: 95, holoColor: (0.28, 0.66, 0.95))
                setSurfaces(
                    plinth: (0.24, 0.19, 0.15), wall: (0.82, 0.80, 0.76), baseboard: (0.87, 0.85, 0.82),
                    partBase: (0.80, 0.78, 0.74), partAccent: (0.56, 0.42, 0.29),
                    plankBase: (0.61, 0.47, 0.34), plankStep: 0.020,
                    rug: (0.78, 0.75, 0.70), rugTrim: (0.63, 0.58, 0.52),
                    sofa: (0.36, 0.45, 0.56), desk: (0.52, 0.37, 0.25), tableTop: (0.82, 0.78, 0.73),
                    windowSky: (0.52, 0.74, 0.91), stars: false, sunBeam: true,
                    holo: (0.26, 0.64, 0.96)
                )
            }

        case .nordicLoft:
            if isDark {
                scene.background.contents = NSColor(srgbRed: 0.048, green: 0.072, blue: 0.105, alpha: 1)
                setLights(ambient: 140, ambColor: (0.70, 0.84, 0.98), key: 245, keyColor: (0.76, 0.90, 1.0), fill: 95, win: 160, winColor: (0.36, 0.78, 0.88), lamp: 260, lampColor: (0.98, 0.88, 0.70), holo: 145, holoColor: (0.32, 0.86, 0.78))
                setSurfaces(
                    plinth: (0.10, 0.14, 0.18), wall: (0.14, 0.20, 0.26), baseboard: (0.22, 0.28, 0.35),
                    partBase: (0.17, 0.23, 0.29), partAccent: (0.40, 0.58, 0.64),
                    plankBase: (0.24, 0.26, 0.28), plankStep: 0.015,
                    rug: (0.18, 0.26, 0.28), rugTrim: (0.26, 0.36, 0.38),
                    sofa: (0.22, 0.42, 0.38), desk: (0.34, 0.38, 0.42), tableTop: (0.26, 0.32, 0.38),
                    windowSky: (0.05, 0.16, 0.28), stars: true, sunBeam: false,
                    holo: (0.28, 0.84, 0.76)
                )
            } else {
                scene.background.contents = NSColor(srgbRed: 0.89, green: 0.92, blue: 0.95, alpha: 1)
                setLights(ambient: 188, ambColor: (0.95, 0.98, 1.0), key: 355, keyColor: (0.96, 0.98, 1.0), fill: 112, win: 170, winColor: (0.90, 0.96, 1.0), lamp: 95, lampColor: (1.0, 0.92, 0.78), holo: 95, holoColor: (0.18, 0.72, 0.66))
                setSurfaces(
                    plinth: (0.30, 0.34, 0.38), wall: (0.83, 0.86, 0.88), baseboard: (0.89, 0.91, 0.92),
                    partBase: (0.81, 0.84, 0.87), partAccent: (0.62, 0.68, 0.66),
                    plankBase: (0.72, 0.69, 0.63), plankStep: 0.018,
                    rug: (0.74, 0.80, 0.78), rugTrim: (0.56, 0.64, 0.62),
                    sofa: (0.34, 0.54, 0.48), desk: (0.68, 0.63, 0.55), tableTop: (0.84, 0.86, 0.87),
                    windowSky: (0.58, 0.79, 0.94), stars: false, sunBeam: true,
                    holo: (0.16, 0.70, 0.66)
                )
            }

        case .zenPavilion:
            if isDark {
                scene.background.contents = NSColor(srgbRed: 0.068, green: 0.064, blue: 0.058, alpha: 1)
                setLights(ambient: 130, ambColor: (0.90, 0.82, 0.68), key: 225, keyColor: (0.96, 0.85, 0.66), fill: 80, win: 185, winColor: (0.98, 0.82, 0.54), lamp: 320, lampColor: (1.0, 0.78, 0.44), holo: 120, holoColor: (0.48, 0.82, 0.58))
                setSurfaces(
                    plinth: (0.12, 0.10, 0.08), wall: (0.20, 0.18, 0.15), baseboard: (0.16, 0.12, 0.09),
                    partBase: (0.22, 0.19, 0.15), partAccent: (0.36, 0.24, 0.14),
                    plankBase: (0.28, 0.25, 0.18), plankStep: 0.014,
                    rug: (0.22, 0.24, 0.18), rugTrim: (0.16, 0.18, 0.14),
                    sofa: (0.24, 0.30, 0.24), desk: (0.26, 0.18, 0.12), tableTop: (0.30, 0.24, 0.18),
                    windowSky: (0.34, 0.28, 0.18), stars: false, sunBeam: false,
                    holo: (0.46, 0.80, 0.56)
                )
            } else {
                scene.background.contents = NSColor(srgbRed: 0.90, green: 0.89, blue: 0.85, alpha: 1)
                setLights(ambient: 180, ambColor: (0.99, 0.96, 0.90), key: 350, keyColor: (1.0, 0.94, 0.82), fill: 98, win: 185, winColor: (1.0, 0.92, 0.76), lamp: 145, lampColor: (1.0, 0.84, 0.56), holo: 90, holoColor: (0.32, 0.68, 0.46))
                setSurfaces(
                    plinth: (0.22, 0.16, 0.11), wall: (0.82, 0.79, 0.72), baseboard: (0.34, 0.24, 0.16),
                    partBase: (0.78, 0.74, 0.66), partAccent: (0.38, 0.26, 0.16),
                    plankBase: (0.68, 0.64, 0.48), plankStep: 0.016,
                    rug: (0.60, 0.62, 0.46), rugTrim: (0.28, 0.32, 0.24),
                    sofa: (0.32, 0.40, 0.32), desk: (0.42, 0.28, 0.18), tableTop: (0.76, 0.70, 0.58),
                    windowSky: (0.92, 0.87, 0.74), stars: false, sunBeam: true,
                    holo: (0.30, 0.66, 0.44)
                )
            }

        case .cyberCommand:
            scene.background.contents = NSColor(srgbRed: 0.036, green: 0.048, blue: 0.082, alpha: 1)
            setLights(ambient: 138, ambColor: (0.64, 0.76, 0.98), key: 265, keyColor: (0.76, 0.86, 1.0), fill: 98, win: 165, winColor: (0.32, 0.68, 1.0), lamp: 260, lampColor: (0.48, 0.78, 1.0), holo: 220, holoColor: (0.36, 0.86, 1.0))
            setSurfaces(
                plinth: (0.07, 0.09, 0.14), wall: (0.11, 0.14, 0.21), baseboard: (0.16, 0.22, 0.34),
                partBase: (0.13, 0.17, 0.25), partAccent: (0.28, 0.72, 0.98),
                plankBase: (0.15, 0.18, 0.24), plankStep: 0.012,
                rug: (0.12, 0.16, 0.26), rugTrim: (0.24, 0.56, 0.92),
                sofa: (0.18, 0.22, 0.34), desk: (0.16, 0.20, 0.28), tableTop: (0.18, 0.24, 0.34),
                windowSky: (0.03, 0.05, 0.13), stars: true, sunBeam: false,
                holo: (0.30, 0.88, 1.0)
            )
        }

        // Update room pad subtle tints per preset
        for kind in PipiHomeRoomKind.allCases {
            if let padMat = roomPadMaterials[kind] {
                let accent = Self.roomAccentColor(for: kind)
                padMat.diffuse.contents = accent.withAlphaComponent(effectiveDark ? 0.11 : 0.09)
            }
            if let frameMat = roomFrameMaterials[kind] {
                let baseAlpha: CGFloat = (preset == .cyberCommand) ? 0.24 : 0.10
                roomHighlightAlpha[kind] = baseAlpha
                frameMat.diffuse.contents = Self.roomAccentColor(for: kind).withAlphaComponent(baseAlpha)
            }
        }

        for rig in botRigs.values {
            updateRigColors(rig, isDark: isDark)
        }
    }

    private func setLights(
        ambient: CGFloat, ambColor: (CGFloat, CGFloat, CGFloat),
        key: CGFloat, keyColor: (CGFloat, CGFloat, CGFloat),
        fill: CGFloat,
        win: CGFloat, winColor: (CGFloat, CGFloat, CGFloat),
        lamp: CGFloat, lampColor: (CGFloat, CGFloat, CGFloat),
        holo: CGFloat, holoColor: (CGFloat, CGFloat, CGFloat)
    ) {
        ambientLightNode.light?.intensity = ambient
        ambientLightNode.light?.color = NSColor(srgbRed: ambColor.0, green: ambColor.1, blue: ambColor.2, alpha: 1)
        keyLightNode.light?.intensity = key
        keyLightNode.light?.color = NSColor(srgbRed: keyColor.0, green: keyColor.1, blue: keyColor.2, alpha: 1)
        fillLightNode.light?.intensity = fill
        windowLightNode.light?.intensity = win
        windowLightNode.light?.color = NSColor(srgbRed: winColor.0, green: winColor.1, blue: winColor.2, alpha: 1)
        deskLampLightNode.light?.intensity = lamp
        deskLampLightNode.light?.color = NSColor(srgbRed: lampColor.0, green: lampColor.1, blue: lampColor.2, alpha: 1)
        labHoloLightNode.light?.intensity = holo
        labHoloLightNode.light?.color = NSColor(srgbRed: holoColor.0, green: holoColor.1, blue: holoColor.2, alpha: 1)
    }

    private func setSurfaces(
        plinth: (CGFloat, CGFloat, CGFloat),
        wall: (CGFloat, CGFloat, CGFloat),
        baseboard: (CGFloat, CGFloat, CGFloat),
        partBase: (CGFloat, CGFloat, CGFloat),
        partAccent: (CGFloat, CGFloat, CGFloat),
        plankBase: (CGFloat, CGFloat, CGFloat),
        plankStep: CGFloat,
        rug: (CGFloat, CGFloat, CGFloat),
        rugTrim: (CGFloat, CGFloat, CGFloat),
        sofa: (CGFloat, CGFloat, CGFloat),
        desk: (CGFloat, CGFloat, CGFloat),
        tableTop: (CGFloat, CGFloat, CGFloat),
        windowSky: (CGFloat, CGFloat, CGFloat),
        stars: Bool,
        sunBeam: Bool,
        holo: (CGFloat, CGFloat, CGFloat)
    ) {
        plinthMaterial.diffuse.contents = NSColor(srgbRed: plinth.0, green: plinth.1, blue: plinth.2, alpha: 1)
        wallMaterial.diffuse.contents = NSColor(srgbRed: wall.0, green: wall.1, blue: wall.2, alpha: 1)
        baseboardMaterial.diffuse.contents = NSColor(srgbRed: baseboard.0, green: baseboard.1, blue: baseboard.2, alpha: 1)
        partitionBaseMaterial.diffuse.contents = NSColor(srgbRed: partBase.0, green: partBase.1, blue: partBase.2, alpha: 1)
        partitionAccentMaterial.diffuse.contents = NSColor(srgbRed: partAccent.0, green: partAccent.1, blue: partAccent.2, alpha: 1)
        rugMaterial.diffuse.contents = NSColor(srgbRed: rug.0, green: rug.1, blue: rug.2, alpha: 1)
        rugTrimMaterial.diffuse.contents = NSColor(srgbRed: rugTrim.0, green: rugTrim.1, blue: rugTrim.2, alpha: 1)
        sofaMaterial.diffuse.contents = NSColor(srgbRed: sofa.0, green: sofa.1, blue: sofa.2, alpha: 1)
        deskWoodMaterial.diffuse.contents = NSColor(srgbRed: desk.0, green: desk.1, blue: desk.2, alpha: 1)
        shelfWoodMaterial.diffuse.contents = NSColor(srgbRed: desk.0 * 1.04, green: desk.1 * 1.04, blue: desk.2 * 1.04, alpha: 1)
        tableTopMaterial.diffuse.contents = NSColor(srgbRed: tableTop.0, green: tableTop.1, blue: tableTop.2, alpha: 1)
        holoCrystalMaterial.diffuse.contents = NSColor(srgbRed: holo.0, green: holo.1, blue: holo.2, alpha: 0.86)

        for (idx, mat) in floorPlankMaterials.enumerated() {
            let d = CGFloat(idx) * plankStep
            mat.diffuse.contents = NSColor(
                srgbRed: Swift.max(0.04, plankBase.0 - d),
                green: Swift.max(0.04, plankBase.1 - d * 0.85),
                blue: Swift.max(0.04, plankBase.2 - d * 0.7),
                alpha: 1
            )
        }
        windowBackdropNode.geometry?.firstMaterial?.diffuse.contents = NSColor(srgbRed: windowSky.0, green: windowSky.1, blue: windowSky.2, alpha: 1)
        windowStarsNode.isHidden = !stars
        windowMoonNode.isHidden = !stars
        sunBeamNode.isHidden = !sunBeam
    }

    // MARK: - 60fps Render Loop

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

        // Smooth camera interpolation (orbit + pan + zoom)
        let camLerp: CGFloat = snapshot.reduceMotion ? 1.0 : CGFloat(min(1.0, dt * 11.0))
        currentYaw += (snapshot.targetYaw - currentYaw) * camLerp
        currentPitch += (snapshot.targetPitch - currentPitch) * camLerp
        currentDistance += (snapshot.targetDistance - currentDistance) * camLerp
        let pLerp = Float(camLerp)
        currentPivot += (snapshot.targetPivot - currentPivot) * pLerp
        applyCameraTransform()

        if snapshot.needsThemeSync || lastAppliedThemeDark != snapshot.isDark || lastAppliedPreset != snapshot.scenePreset {
            applyScenePreset(snapshot.scenePreset, isDark: snapshot.isDark)
        }
        if snapshot.needsBotSync {
            syncBotRigs(items: snapshot.bots, isDark: snapshot.isDark)
        }

        // Gentle rotating hologram in Creative Lab
        if !snapshot.reduceMotion {
            holoCrystalNode.eulerAngles = SCNVector3(0.65, Float(time * 0.85), 0.45)
            holoCrystalNode.position = SCNVector3(0, 1.06 + Float(sin(time * 2.1)) * 0.05, 0)
        }

        // Animate Room Drop-Zone Perimeter Highlights smoothly
        let baseFrameAlpha: CGFloat = (snapshot.scenePreset == .cyberCommand) ? 0.24 : 0.10
        for kind in PipiHomeRoomKind.allCases {
            let isTarget = (snapshot.draggingBotId != nil && snapshot.dragHoverRoom == kind)
            let targetAlpha: CGFloat
            if isTarget {
                targetAlpha = snapshot.reduceMotion ? 0.88 : (0.76 + 0.18 * CGFloat(sin(time * 6.0)))
            } else if snapshot.draggingBotId != nil {
                targetAlpha = 0.28
            } else {
                targetAlpha = baseFrameAlpha
            }
            let prev = roomHighlightAlpha[kind] ?? baseFrameAlpha
            let next = prev + (targetAlpha - prev) * CGFloat(min(1.0, dt * 12.0))
            if abs(next - prev) > 0.004, let mat = roomFrameMaterials[kind] {
                roomHighlightAlpha[kind] = next
                mat.diffuse.contents = Self.roomAccentColor(for: kind).withAlphaComponent(next)
            }
        }

        // Update room ambient glow states
        let workingBots = snapshot.bots.filter { $0.state == .working }
        let collabBots = snapshot.bots.filter { $0.state == .collaborating }
        let needsBots = snapshot.bots.filter { $0.state == .needsYou }

        let isAnyWorking = !workingBots.isEmpty
        if isAnyWorking {
            let pulse = snapshot.reduceMotion ? 0.8 : (0.76 + 0.20 * sin(time * 2.6))
            monitorScreenMaterial.diffuse.contents = NSColor(srgbRed: 0.20, green: 0.54 * pulse + 0.14, blue: 0.96, alpha: 1)
            monitorGlowLightNode.light?.intensity = 280 * pulse
            monitorGlowLightNode.light?.color = NSColor(srgbRed: 0.25, green: 0.65, blue: 1.0, alpha: 1)
            lastMonitorWorkingState = true
        } else if lastMonitorWorkingState != false {
            monitorScreenMaterial.diffuse.contents = (snapshot.isDark || snapshot.scenePreset == .cyberCommand)
                ? NSColor(srgbRed: 0.12, green: 0.22, blue: 0.36, alpha: 1)
                : NSColor(srgbRed: 0.24, green: 0.36, blue: 0.54, alpha: 1)
            monitorGlowLightNode.light?.intensity = 85
            lastMonitorWorkingState = false
        }

        let isAnyCollab = !collabBots.isEmpty
        if isAnyCollab {
            let pulse = snapshot.reduceMotion ? 0.85 : (0.68 + 0.28 * sin(time * 2.4))
            collabTableRingMaterial.diffuse.contents = NSColor(srgbRed: 0.28, green: 0.72, blue: 1.0, alpha: 0.62 * pulse + 0.24)
            lastCollabActiveState = true
        } else if lastCollabActiveState != false {
            collabTableRingMaterial.diffuse.contents = NSColor(srgbRed: 0.28, green: 0.56, blue: 0.96, alpha: 0.18)
            lastCollabActiveState = false
        }

        // Show / position Drag Drop Guide when user is dragging an agent
        if let dragId = snapshot.draggingBotId, let dragPos = snapshot.dragWorldPosition, let rig = botRigs[dragId] {
            dragGuideNode.isHidden = false
            let guideX = rig.position.x
            let guideZ = rig.position.z
            dragGuideNode.position = SCNVector3(guideX, floorSurfaceY(at: dragPos), guideZ)
            let roomColor = Self.roomAccentColor(for: snapshot.dragHoverRoom ?? .lounge)
            dragGuideRingMaterial.diffuse.contents = roomColor.withAlphaComponent(0.92)
            dragGuideBeamMaterial.diffuse.contents = roomColor.withAlphaComponent(0.40)
        } else {
            dragGuideNode.isHidden = true
        }

        // Step every bot rig
        let workingOrder = Dictionary(uniqueKeysWithValues: workingBots.enumerated().map { ($1.id, $0) })
        let collabOrder = Dictionary(uniqueKeysWithValues: collabBots.enumerated().map { ($1.id, $0) })
        let needsOrder = Dictionary(uniqueKeysWithValues: needsBots.enumerated().map { ($1.id, $0) })

        for bot in snapshot.bots {
            guard let rig = botRigs[bot.id] else { continue }
            let isBeingDragged = (snapshot.draggingBotId == bot.id)
            let isSelected = (snapshot.selectedBotId == bot.id)
            let isHovered = (snapshot.hoveredBotId == bot.id) || (snapshot.pinnedBotId == bot.id)
            let isEngagedByCursor = isSelected || isHovered || isBeingDragged

            if isBeingDragged, let targetDrag = snapshot.dragWorldPosition {
                let lerpDrag = min(1.0, dt * 18.0)
                rig.position += (targetDrag - rig.position) * lerpDrag
                rig.dragLiftHeight += (0.56 - rig.dragLiftHeight) * min(1.0, dt * 14.0)
                rig.walkTarget = rig.position

                let camX = Float(cameraNode.position.x + cameraPivotNode.position.x)
                let camZ = Float(cameraNode.position.z + cameraPivotNode.position.z)
                let faceCam = atan2(camX - rig.position.x, camZ - rig.position.z)
                rig.heading = lerpAngle(from: rig.heading, to: faceCam, t: min(1.0, dt * 10.0))

                let floorY = floorSurfaceY(at: rig.position)
                rig.rootNode.position = SCNVector3(rig.position.x, floorY, rig.position.z)
                rig.rootNode.eulerAngles = SCNVector3(0, rig.heading, 0)
                rig.bodyGroupNode.position = SCNVector3(0, rig.dragLiftHeight, 0)
                rig.bodyGroupNode.eulerAngles = SCNVector3(0.08, 0, Float(sin(time * 6.5)) * 0.08)
                rig.shadowNode.scale = SCNVector3(1.26, 1.26, 1.0)
                rig.floorRingNode.scale = SCNVector3(1.30, 1.0, 1.30)
                continue
            }

            // Smooth drop settle back to ground
            rig.dragLiftHeight += (0.0 - rig.dragLiftHeight) * min(1.0, dt * 16.0)
            rig.bodyGroupNode.eulerAngles = SCNVector3(0, 0, 0)
            rig.shadowNode.scale = SCNVector3(1.0, 1.0, 1.0)
            if rig.landingBouncePhase > 0.001 {
                rig.landingBouncePhase = max(0, rig.landingBouncePhase - dt * 3.8)
            }

            // Target Position & Facing (Room-Aware!)
            var desiredFacing: Float? = nil
            switch rig.visualState {
            case .needsYou:
                let idx = needsOrder[bot.id] ?? 0
                let spread = Float(idx) - Float(max(0, needsBots.count - 1)) * 0.5
                rig.walkTarget = SIMD3<Float>(spread * 1.10, 0, 0.25)
                desiredFacing = 0.0

            case .collaborating:
                let idx = collabOrder[bot.id] ?? 0
                let count = max(1, collabBots.count)
                let angle = (Float(idx) / Float(count)) * Float.pi * 2.0 + 0.45
                let radius: Float = 1.42
                let cx: Float = -2.75
                let cz: Float = 2.35
                let tx = cx + cos(angle) * radius
                let tz = cz + sin(angle) * radius
                rig.walkTarget = SIMD3<Float>(tx, 0, tz)
                desiredFacing = atan2(cx - tx, cz - tz)

            case .working:
                let idx = workingOrder[bot.id] ?? 0
                if idx == 0 {
                    rig.walkTarget = SIMD3<Float>(3.10, 0, -2.18)
                    desiredFacing = Float.pi
                    rig.miniHoloNode.isHidden = true
                } else {
                    let roomWaypoints = Self.roomSpecs[rig.assignedRoom]?.waypoints ?? Self.roomSpecs[.studio]!.waypoints
                    rig.walkTarget = roomWaypoints[idx % roomWaypoints.count]
                    desiredFacing = 0.2
                    rig.miniHoloNode.isHidden = false
                }

            case .idle:
                rig.miniHoloNode.isHidden = true
                if isEngagedByCursor {
                    rig.walkTarget = rig.position
                    rig.pauseTimer = max(rig.pauseTimer, 3.2)
                } else {
                    let distToTarget = length(SIMD2<Float>(rig.walkTarget.x - rig.position.x, rig.walkTarget.z - rig.position.z))
                    if distToTarget < 0.18 {
                        rig.pauseTimer -= TimeInterval(dt)
                        if rig.pauseTimer <= 0 {
                            rig.walkTarget = nextIdleWaypoint(in: rig.assignedRoom, avoiding: rig.position, botId: rig.id)
                            rig.pauseTimer = 5.5 + (rig.phaseOffset * 1.3).truncatingRemainder(dividingBy: 3.8)
                        }
                    }
                }
            }

            // Soft separation from sibling bots
            if !isEngagedByCursor {
                for (otherId, otherRig) in botRigs where otherId != rig.id && snapshot.draggingBotId != otherId {
                    var away = rig.position - otherRig.position
                    away.y = 0
                    let sep = length(away)
                    if sep > 0.001 && sep < 0.84 {
                        let pushScale: Float = (rig.visualState == .idle) ? 1.8 : 1.0
                        rig.position += normalize(away) * (0.84 - sep) * dt * pushScale
                    }
                }
            }

            // Waypoint navigation (route cleanly through central corridor if crossing between rooms!)
            let activeGoal = corridorAwareTarget(from: rig.position, destination: rig.walkTarget)
            var delta = activeGoal - rig.position
            delta.y = 0
            let dist = length(delta)

            let isMoving = !isEngagedByCursor && dist > 0.10
            if isMoving {
                let speed: Float = (rig.visualState == .idle) ? 0.78 : 1.75
                let step = min(dist, speed * dt)
                let desiredDir = delta / dist
                let steeredDir = steerAroundRoomObstacles(from: rig.position, desiredDir: desiredDir)
                rig.position += steeredDir * step
                let targetAngle = atan2(steeredDir.x, steeredDir.z)
                rig.heading = lerpAngle(from: rig.heading, to: targetAngle, t: min(1.0, dt * 8.5))
            } else if isEngagedByCursor {
                let camX = Float(cameraNode.position.x + cameraPivotNode.position.x)
                let camZ = Float(cameraNode.position.z + cameraPivotNode.position.z)
                let faceUserAngle = atan2(camX - rig.position.x, camZ - rig.position.z)
                rig.heading = lerpAngle(from: rig.heading, to: faceUserAngle, t: min(1.0, dt * 9.5))
            } else if let desiredFacing {
                rig.heading = lerpAngle(from: rig.heading, to: desiredFacing, t: min(1.0, dt * 6.5))
            }

            rig.position = resolveRoomCollisions(rig.position)
            let floorY = floorSurfaceY(at: rig.position)
            rig.rootNode.position = SCNVector3(rig.position.x, floorY, rig.position.z)
            rig.rootNode.eulerAngles = SCNVector3(0, rig.heading, 0)

            let t = time + rig.phaseOffset
            let bounceLift = sin(rig.landingBouncePhase * Float.pi) * 0.14
            if snapshot.reduceMotion {
                rig.bodyGroupNode.position = SCNVector3(0, rig.dragLiftHeight, 0)
                rig.headGroupNode.eulerAngles = SCNVector3(0, 0, 0)
                rig.leftFootNode.position = SCNVector3(-0.12, 0.08, 0.02)
                rig.rightFootNode.position = SCNVector3(0.12, 0.08, 0.02)
            } else {
                if isMoving {
                    let stride = Float(sin(t * 11.5))
                    rig.leftFootNode.position = SCNVector3(-0.12, 0.08 + max(0, stride) * 0.04, stride * 0.07)
                    rig.rightFootNode.position = SCNVector3(0.12, 0.08 + max(0, -stride) * 0.04, -stride * 0.07)
                    rig.bodyGroupNode.position = SCNVector3(0, rig.dragLiftHeight + bounceLift + abs(stride) * 0.035, 0)
                    rig.headGroupNode.eulerAngles = SCNVector3(0.05, 0, stride * 0.04)
                } else {
                    rig.leftFootNode.position = SCNVector3(-0.12, 0.08, 0.02)
                    rig.rightFootNode.position = SCNVector3(0.12, 0.08, 0.02)
                    switch rig.visualState {
                    case .idle:
                        let breathe = Float(sin(t * 2.1)) * 0.016
                        let look = Float(sin(t * 0.85)) * 0.14
                        rig.bodyGroupNode.position = SCNVector3(0, rig.dragLiftHeight + bounceLift + breathe, 0)
                        rig.headGroupNode.eulerAngles = SCNVector3(0, look, 0)
                    case .working:
                        let bob = Float(sin(t * 7.5)) * 0.024
                        let tilt = Float(sin(t * 3.8)) * 0.07
                        rig.bodyGroupNode.position = SCNVector3(0, rig.dragLiftHeight + bounceLift + abs(bob), 0)
                        rig.headGroupNode.eulerAngles = SCNVector3(-0.08, tilt, 0)
                        rig.orbitRingNode.eulerAngles = SCNVector3(0.24, Float(t * 2.2), 0.18)
                    case .needsYou:
                        let hop = max(0, Float(sin(t * 4.4))) * 0.12
                        rig.bodyGroupNode.position = SCNVector3(0, rig.dragLiftHeight + bounceLift + hop, 0)
                        rig.headGroupNode.eulerAngles = SCNVector3(-0.06, 0, Float(sin(t * 2.2)) * 0.07)
                        rig.alertBeaconNode.position = SCNVector3(0, 1.12 + Float(sin(t * 5.0)) * 0.04, 0)
                    case .collaborating:
                        let nod = Float(sin(t * 3.1)) * 0.06
                        let bob = Float(sin(t * 2.4)) * 0.018
                        rig.bodyGroupNode.position = SCNVector3(0, rig.dragLiftHeight + bounceLift + bob, 0)
                        rig.headGroupNode.eulerAngles = SCNVector3(nod, Float(sin(t * 1.4)) * 0.10, 0)
                    }
                }
            }

            let targetRingScale: Float = isSelected ? 1.24 : (isHovered ? 1.15 : 1.0)
            rig.currentScaleRing += (targetRingScale - rig.currentScaleRing) * min(1.0, dt * 12.0)
            rig.floorRingNode.scale = SCNVector3(rig.currentScaleRing, 1.0, rig.currentScaleRing)
            let ringAlpha: CGFloat = isSelected ? 0.95 : (isHovered ? 0.82 : 0.42)
            if abs(rig.lastRingAlpha - ringAlpha) > 0.005 {
                rig.lastRingAlpha = ringAlpha
                rig.floorRingMaterial.diffuse.contents = rig.cachedAccentColor.withAlphaComponent(ringAlpha)
            }
        }

        updateCollaboratingArcs(collabBots: collabBots, time: time, isDark: snapshot.isDark, reduceMotion: snapshot.reduceMotion)
    }

    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        let snapshot = stateLock.withLock { $0 }
        let viewBounds = snapshot.viewSize
        guard viewBounds.width > 10 && viewBounds.height > 10 else { return }

        var badges: [PipiHomeProjectedBadge] = []
        badges.reserveCapacity(snapshot.bots.count)
        var roomOccupants: [PipiHomeRoomKind: Int] = [:]

        for bot in snapshot.bots {
            roomOccupants[bot.room, default: 0] += 1
            guard let rig = botRigs[bot.id] else { continue }
            let extraY: Float = ((bot.state == .needsYou) ? 1.38 : 1.04) + rig.dragLiftHeight
            let worldPos = SCNVector3(rig.position.x, extraY, rig.position.z)
            let projected = renderer.projectPoint(worldPos)
            guard projected.z > 0.0 && projected.z < 1.0 else { continue }

            badges.append(
                PipiHomeProjectedBadge(
                    id: bot.id,
                    displayName: bot.displayName,
                    accent: bot.accent,
                    state: bot.state,
                    room: bot.room,
                    screenPoint: CGPoint(x: CGFloat(projected.x), y: viewBounds.height - CGFloat(projected.y)),
                    isSelected: snapshot.selectedBotId == bot.id,
                    isHovered: snapshot.hoveredBotId == bot.id,
                    isDragging: snapshot.draggingBotId == bot.id
                )
            )
        }

        var roomLabels: [PipiHomeProjectedRoomLabel] = []
        roomLabels.reserveCapacity(PipiHomeRoomKind.allCases.count)
        for kind in PipiHomeRoomKind.allCases {
            guard let spec = Self.roomSpecs[kind] else { continue }
            let anchor = spec.labelAnchor
            let projected = renderer.projectPoint(SCNVector3(anchor.x, anchor.y, anchor.z))
            guard projected.z > 0.0 && projected.z < 1.0 else { continue }
            roomLabels.append(
                PipiHomeProjectedRoomLabel(
                    room: kind,
                    screenPoint: CGPoint(x: CGFloat(projected.x), y: viewBounds.height - CGFloat(projected.y)),
                    occupantCount: roomOccupants[kind] ?? 0,
                    isDropTarget: snapshot.draggingBotId != nil && snapshot.dragHoverRoom == kind
                )
            )
        }

        let badgesChanged = hasSignificantBadgeDelta(old: lastProjectedBadges, new: badges)
        let roomsChanged = hasSignificantRoomLabelDelta(old: lastProjectedRoomLabels, new: roomLabels)
        guard badgesChanged || roomsChanged else { return }
        lastProjectedBadges = badges
        lastProjectedRoomLabels = roomLabels

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
            bridge.projectedRoomLabels = roomLabels
            lock.withLock { $0 = false }
        }
    }

    private func hasSignificantBadgeDelta(old: [PipiHomeProjectedBadge], new: [PipiHomeProjectedBadge]) -> Bool {
        guard old.count == new.count else { return true }
        for (a, b) in zip(old, new) {
            if a.id != b.id || a.state != b.state || a.room != b.room || a.displayName != b.displayName
                || a.accent != b.accent || a.isSelected != b.isSelected || a.isHovered != b.isHovered || a.isDragging != b.isDragging {
                return true
            }
            if abs(a.screenPoint.x - b.screenPoint.x) > 0.45 || abs(a.screenPoint.y - b.screenPoint.y) > 0.45 {
                return true
            }
        }
        return false
    }

    private func hasSignificantRoomLabelDelta(old: [PipiHomeProjectedRoomLabel], new: [PipiHomeProjectedRoomLabel]) -> Bool {
        guard old.count == new.count else { return true }
        for (a, b) in zip(old, new) {
            if a.room != b.room || a.occupantCount != b.occupantCount || a.isDropTarget != b.isDropTarget {
                return true
            }
            if abs(a.screenPoint.x - b.screenPoint.x) > 0.6 || abs(a.screenPoint.y - b.screenPoint.y) > 0.6 {
                return true
            }
        }
        return false
    }

    // MARK: - Collaborating Arcs (Centered on Collab Hub Table)

    private func updateCollaboratingArcs(
        collabBots: [PipiHomeBotSyncItem],
        time: TimeInterval,
        isDark: Bool,
        reduceMotion: Bool
    ) {
        let activeIds = Set(collabBots.map(\.id))
        let needsRebuild = collabArcSegments.count != collabBots.count ||
            zip(collabArcSegments, collabBots).contains { $0.node.name != "arc:\($1.id)" }

        let centerTarget = SIMD3<Float>(-2.75, 0.54, 2.35)
        if needsRebuild {
            collabArcsNode.childNodes.forEach { $0.removeFromParentNode() }
            collabArcSegments.removeAll()

            for bot in collabBots where activeIds.contains(bot.id) {
                let container = SCNNode()
                container.name = "arc:\(bot.id)"
                let accentColor = Self.srgbAccentNSColor(for: bot.accent, isDark: isDark)
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
                let start = botRigs[bot.id]?.position ?? centerTarget
                collabArcSegments.append((container, pulses, start, centerTarget, bot.accent))
            }
        }

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

    // MARK: - Collision Geometry, Corridor Routing & Helpers

    private struct CircleObstacle {
        let cx: Float
        let cz: Float
        let radius: Float
    }

    private struct BoxObstacle {
        let minX: Float
        let maxX: Float
        let minZ: Float
        let maxZ: Float
    }

    private static let circleObstacles: [CircleObstacle] = [
        CircleObstacle(cx: -2.75, cz: 2.35, radius: 1.24),   // Collab round table
        CircleObstacle(cx: 3.20, cz: 2.55, radius: 0.96),    // Lab holo display plinth
        CircleObstacle(cx: -1.35, cz: -3.72, radius: 0.74),  // Lounge coffee side table
        CircleObstacle(cx: -4.72, cz: -4.08, radius: 0.72),  // Lounge corner plant
        CircleObstacle(cx: 4.62, cz: 0.85, radius: 0.56)     // Lab planter
    ]

    private static let boxObstacles: [BoxObstacle] = [
        // Room furniture (with 0.40m bot clearance)
        BoxObstacle(minX: 1.62, maxX: 4.68, minZ: -4.45, maxZ: -2.62),   // Studio desk + chair
        BoxObstacle(minX: 0.15, maxX: 1.78, minZ: -4.75, maxZ: -3.82),   // Studio bookshelf
        BoxObstacle(minX: -4.40, maxX: -1.68, minZ: -4.35, maxZ: -2.85), // Lounge sofa
        BoxObstacle(minX: 4.10, maxX: 5.42, minZ: 1.15, maxZ: 3.92),     // Lab workbench
        BoxObstacle(minX: -5.50, maxX: -4.92, minZ: 1.05, maxZ: 3.65),   // Collab briefing board
        // 4 short interior partition wall stubs (leaving huge central atrium & doorways open!)
        BoxObstacle(minX: -0.44, maxX: 0.44, minZ: -4.80, maxZ: -2.02),  // Back vertical divider
        BoxObstacle(minX: -0.44, maxX: 0.44, minZ: 2.02, maxZ: 4.68),    // Front vertical divider
        BoxObstacle(minX: -5.50, maxX: -2.25, minZ: -0.42, maxZ: 0.42),  // Left horizontal divider
        BoxObstacle(minX: 2.25, maxX: 5.42, minZ: -0.42, maxZ: 0.42)     // Right horizontal divider
    ]

    /// Routes bots smoothly through the central open crossroads whenever moving between two different rooms.
    private func corridorAwareTarget(from pos: SIMD3<Float>, destination: SIMD3<Float>) -> SIMD3<Float> {
        let fromRoom = Self.roomKind(at: pos)
        let toRoom = Self.roomKind(at: destination)
        guard fromRoom != toRoom else { return destination }
        // If not yet near the central atrium, head toward center crossroads first
        let distFromCenter = length(SIMD2<Float>(pos.x, pos.z))
        if distFromCenter > 1.75 {
            return SIMD3<Float>(0, 0, 0)
        }
        return destination
    }

    private func floorSurfaceY(at pos: SIMD3<Float>) -> Float {
        // Lounge woven rug occupies x: [-4.33, -1.37], z: [-2.93, -0.97], top y = 0.026
        let onLoungeRug = pos.x >= -4.33 && pos.x <= -1.37 && pos.z >= -2.93 && pos.z <= -0.97
        if onLoungeRug { return 0.027 }
        return 0.009
    }

    private func steerAroundRoomObstacles(from pos: SIMD3<Float>, desiredDir: SIMD3<Float>) -> SIMD3<Float> {
        let lookAhead = pos + desiredDir * 0.55
        var steer = desiredDir

        for obs in Self.circleObstacles {
            let dx = lookAhead.x - obs.cx
            let dz = lookAhead.z - obs.cz
            let distSq = dx * dx + dz * dz
            let safeR = obs.radius + 0.15
            if distSq < safeR * safeR && distSq > 0.0001 {
                let d = sqrt(distSq)
                let nx = dx / d
                let nz = dz / d
                let t1 = SIMD3<Float>(-nz, 0, nx)
                let t2 = SIMD3<Float>(nz, 0, -nx)
                let tangent = (dot(t1, desiredDir) >= dot(t2, desiredDir)) ? t1 : t2
                let weight = (safeR - d) / safeR
                steer += (tangent * 1.4 + SIMD3<Float>(nx, 0, nz) * 0.7) * weight
            }
        }

        for box in Self.boxObstacles {
            let clampedX = Swift.max(box.minX, Swift.min(box.maxX, lookAhead.x))
            let clampedZ = Swift.max(box.minZ, Swift.min(box.maxZ, lookAhead.z))
            let dx = lookAhead.x - clampedX
            let dz = lookAhead.z - clampedZ
            if dx * dx + dz * dz < 0.045 {
                let cx = (box.minX + box.maxX) * 0.5
                let cz = (box.minZ + box.maxZ) * 0.5
                let out = SIMD3<Float>(pos.x - cx, 0, pos.z - cz)
                if length(out) > 0.001 {
                    let n = normalize(out)
                    let t1 = SIMD3<Float>(-n.z, 0, n.x)
                    let t2 = SIMD3<Float>(n.z, 0, -n.x)
                    let tangent = (dot(t1, desiredDir) >= dot(t2, desiredDir)) ? t1 : t2
                    steer += tangent * 1.2 + n * 0.55
                }
            }
        }

        steer.y = 0
        let len = length(steer)
        return len > 0.001 ? (steer / len) : desiredDir
    }

    private func resolveRoomCollisions(_ rawPos: SIMD3<Float>) -> SIMD3<Float> {
        var p = rawPos
        p.y = 0

        for _ in 0..<2 {
            p.x = Swift.max(-4.95, Swift.min(4.95, p.x))
            p.z = Swift.max(-4.30, Swift.min(4.25, p.z))

            for obs in Self.circleObstacles {
                let dx = p.x - obs.cx
                let dz = p.z - obs.cz
                let dSq = dx * dx + dz * dz
                if dSq < obs.radius * obs.radius {
                    let d = max(0.0001, sqrt(dSq))
                    p.x = obs.cx + (dx / d) * obs.radius
                    p.z = obs.cz + (dz / d) * obs.radius
                }
            }

            for box in Self.boxObstacles {
                if p.x > box.minX && p.x < box.maxX && p.z > box.minZ && p.z < box.maxZ {
                    let dLeft = p.x - box.minX
                    let dRight = box.maxX - p.x
                    let dBack = p.z - box.minZ
                    let dFront = box.maxZ - p.z
                    let m = Swift.min(Swift.min(dLeft, dRight), Swift.min(dBack, dFront))
                    if m == dFront {
                        p.z = box.maxZ
                    } else if m == dLeft {
                        p.x = box.minX
                    } else if m == dRight {
                        p.x = box.maxX
                    } else {
                        p.z = box.minZ
                    }
                }
            }
        }
        return p
    }

    private func nextIdleWaypoint(in room: PipiHomeRoomKind, avoiding current: SIMD3<Float>, botId: String) -> SIMD3<Float> {
        let poolAll = Self.roomSpecs[room]?.waypoints ?? Self.roomSpecs[.lounge]!.waypoints
        let candidates = poolAll.filter { length($0 - current) > 0.85 }
        let pool = candidates.isEmpty ? poolAll : candidates
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

    private static func roomAccentColor(for room: PipiHomeRoomKind) -> NSColor {
        switch room {
        case .studio: return NSColor(srgbRed: 0.25, green: 0.56, blue: 0.96, alpha: 1)
        case .lounge: return NSColor(srgbRed: 0.92, green: 0.64, blue: 0.26, alpha: 1)
        case .collab: return NSColor(srgbRed: 0.54, green: 0.44, blue: 0.94, alpha: 1)
        case .lab:    return NSColor(srgbRed: 0.16, green: 0.76, blue: 0.62, alpha: 1)
        }
    }

    private static func srgbAccentNSColor(for accent: PipiPersonaAccent, isDark: Bool) -> NSColor {
        switch (accent, isDark) {
        case (.iris, true):     return NSColor(srgbRed: 0.424, green: 0.557, blue: 0.937, alpha: 1)
        case (.iris, false):    return NSColor(srgbRed: 0.231, green: 0.357, blue: 0.859, alpha: 1)
        case (.emerald, true):  return NSColor(srgbRed: 0.204, green: 0.827, blue: 0.600, alpha: 1)
        case (.emerald, false): return NSColor(srgbRed: 0.020, green: 0.588, blue: 0.412, alpha: 1)
        case (.amber, true):    return NSColor(srgbRed: 0.984, green: 0.749, blue: 0.141, alpha: 1)
        case (.amber, false):   return NSColor(srgbRed: 0.851, green: 0.467, blue: 0.024, alpha: 1)
        case (.sky, true):      return NSColor(srgbRed: 0.220, green: 0.741, blue: 0.973, alpha: 1)
        case (.sky, false):     return NSColor(srgbRed: 0.008, green: 0.518, blue: 0.780, alpha: 1)
        case (.coral, true):    return NSColor(srgbRed: 0.984, green: 0.443, blue: 0.522, alpha: 1)
        case (.coral, false):   return NSColor(srgbRed: 0.882, green: 0.114, blue: 0.282, alpha: 1)
        }
    }

    private static func srgbEyeNSColor(for accent: PipiPersonaAccent) -> NSColor {
        switch accent {
        case .iris:    return NSColor(srgbRed: 0.655, green: 0.545, blue: 0.980, alpha: 1)
        case .emerald: return NSColor(srgbRed: 0.204, green: 0.827, blue: 0.600, alpha: 1)
        case .amber:   return NSColor(srgbRed: 0.984, green: 0.749, blue: 0.141, alpha: 1)
        case .sky:     return NSColor(srgbRed: 0.220, green: 0.741, blue: 0.973, alpha: 1)
        case .coral:   return NSColor(srgbRed: 0.984, green: 0.443, blue: 0.522, alpha: 1)
        }
    }

    private static func makeBitmapImage(width: Int, height: Int, draw: (CGContext) -> Void) -> NSImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(size: NSSize(width: width, height: height))
        }
        draw(ctx)
        if let cgImage = ctx.makeImage() {
            return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        }
        return NSImage(size: NSSize(width: width, height: height))
    }

    private static func radialShadowImage() -> NSImage {
        makeBitmapImage(width: 96, height: 96) { ctx in
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [
                NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.30).cgColor,
                NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.12).cgColor,
                NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.0).cgColor
            ] as CFArray
            let locations: [CGFloat] = [0.0, 0.55, 1.0]
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                let center = CGPoint(x: 48, y: 48)
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 46, options: [])
            }
        }
    }

    private static func studioEnvironmentImage(isDark: Bool) -> NSImage {
        makeBitmapImage(width: 128, height: 64) { ctx in
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let topColor: NSColor
            let midColor: NSColor
            let botColor: NSColor
            if isDark {
                topColor = NSColor(srgbRed: 0.24, green: 0.32, blue: 0.48, alpha: 1.0)
                midColor = NSColor(srgbRed: 0.16, green: 0.19, blue: 0.25, alpha: 1.0)
                botColor = NSColor(srgbRed: 0.22, green: 0.17, blue: 0.12, alpha: 1.0)
            } else {
                topColor = NSColor(srgbRed: 0.84, green: 0.86, blue: 0.89, alpha: 1.0)
                midColor = NSColor(srgbRed: 0.74, green: 0.76, blue: 0.79, alpha: 1.0)
                botColor = NSColor(srgbRed: 0.62, green: 0.54, blue: 0.45, alpha: 1.0)
            }
            let colors = [topColor.cgColor, midColor.cgColor, botColor.cgColor] as CFArray
            let locations: [CGFloat] = [0.0, 0.52, 1.0]
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 64), end: CGPoint(x: 0, y: 0), options: [])
            }
        }
    }
}
