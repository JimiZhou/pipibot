import XCTest
@testable import PipiBotKit
@testable import PipiBotIOSUI

final class PipiBotKitTests: XCTestCase {

    @MainActor
    func testCanonical53AvatarStatesAnd9ExpressionsAnd8Shapes() {
        XCTAssertEqual(AvatarState53.allCases.count, 53)
        XCTAssertEqual(AvatarExpression9.allCases.count, 9)
        XCTAssertEqual(AvatarShape.allCases.count, 8)

        var groupCounts: [AvatarLifecycleGroup: Int] = [:]
        for state in AvatarState53.allCases {
            let meta = PipiProceduralAvatarEngine.metadata(for: state)
            groupCounts[meta.group, default: 0] += 1
        }
        XCTAssertEqual(groupCounts[.idleAmbient], 10)
        XCTAssertEqual(groupCounts[.thinkingReasoning], 11)
        XCTAssertEqual(groupCounts[.toolHarnessExecution], 14)
        XCTAssertEqual(groupCounts[.cueNeedsYouAlert], 10)
        XCTAssertEqual(groupCounts[.selfEvolutionDreaming], 8)
    }

    func test192RaySamplingAndInterpolationAndContourPath() {
        let orb = PipiAvatarMath.sampleShape192(.orb)
        let spark = PipiAvatarMath.sampleShape192(.spark)
        XCTAssertEqual(orb.count, 192)
        XCTAssertEqual(spark.count, 192)

        let mid = PipiAvatarMath.interpolateRays192(from: orb, to: spark, t: 0.5)
        XCTAssertEqual(mid.count, 192)
        XCTAssertEqual(mid[0], (orb[0] + spark[0]) * 0.5, accuracy: 1e-6)

        let path = PipiAvatarMath.buildSmoothContourPath(
            radii: mid,
            center: CGPoint(x: 60, y: 60),
            baseRadius: 36,
            scaleX: 1,
            scaleY: 1,
            rotationRad: 0
        )
        XCTAssertFalse(path.isEmpty)
    }

    func testRodrigues3DRotationPreservesUnitLength() {
        let v = PipiProceduralAvatarEngine.leftEyeSphereBase
        let axis = SIMD3<Double>(0.2, 0.9, -0.3)
        let rotated = PipiAvatarMath.rodriguesRotate(v, axis: axis, theta: 0.42)
        let norm = (rotated.x * rotated.x + rotated.y * rotated.y + rotated.z * rotated.z).squareRoot()
        XCTAssertEqual(norm, 1.0, accuracy: 1e-6)
        XCTAssertNotEqual(rotated.x, v.x)
    }

    func testCubicBezierBoundariesAndOvershoot() {
        XCTAssertEqual(PipiAvatarMath.cubicBezier(p1x: 0.34, p1y: 1.56, p2x: 0.64, p2y: 1.0, t: 0.0), 0.0, accuracy: 1e-6)
        XCTAssertEqual(PipiAvatarMath.cubicBezier(p1x: 0.34, p1y: 1.56, p2x: 0.64, p2y: 1.0, t: 1.0), 1.0, accuracy: 1e-6)
        let peak = PipiAvatarMath.cubicBezier(p1x: 0.34, p1y: 1.56, p2x: 0.64, p2y: 1.0, t: 0.55)
        XCTAssertGreaterThan(peak, 1.0)
    }

    @MainActor
    func test120HzPhysicsBlinkPeakAt45PercentAndStateTransitions() {
        let engine = PipiProceduralAvatarEngine(initialState: .idle)
        engine.autoBlink = false
        engine.blink()

        // Step right up to 45% of 0.26s = 0.117s (14 fixed steps of 1/120s = 0.1167s)
        engine.step(deltaSec: 0.117)
        XCTAssertTrue(engine.blinkActive)
        XCTAssertGreaterThan(engine.blinkClosure, 0.92)

        // Complete blink cycle
        engine.step(deltaSec: 0.20)
        XCTAssertFalse(engine.blinkActive)
        XCTAssertEqual(engine.blinkClosure, 0.0, accuracy: 1e-6)

        // Transition to claude-routing triggers morph & springs
        engine.setState(.claudeRouting)
        engine.step(deltaSec: 0.05)
        let snap = engine.telemetrySnapshot()
        XCTAssertEqual(snap.state, .claudeRouting)
        XCTAssertEqual(snap.shape, .squircle)
        XCTAssertGreaterThan(snap.springSwap, 0.0)
    }

    func testDesignGovernanceMetricConstants() {
        XCTAssertEqual(PipiTokens.buttonHeightMobile, 44)
        XCTAssertEqual(PipiTokens.buttonIconMobile, 18)
        XCTAssertEqual(PipiTokens.buttonGapMobile, 8)
        XCTAssertEqual(PipiTokens.buttonHeightDesktop, 32)
        XCTAssertEqual(PipiTokens.buttonIconDesktop, 16)
        XCTAssertEqual(PipiTokens.buttonGapDesktop, 6)
        XCTAssertEqual(PipiTokens.sheetTopEdgeCompact, 54)
        XCTAssertEqual(PipiTokens.sheetTopEdgeExpanded, 102)
    }

    @MainActor
    func testAppStoreOfflineLifecycleAndProtocolCodableRoundTrip() async throws {
        let store = PipiAppStore(autoConnect: false)
        XCTAssertEqual(store.outcomes.count, 4)
        XCTAssertEqual(store.pendingDecisions.count, 3)
        XCTAssertEqual(store.fleetNodes.count, 5)

        // Create and evaluate outcome
        await store.createOutcome(
            title: "Nightly Backup Guard",
            domain: .infra,
            goal: "Verify encrypted SQLite backup uploaded to R2",
            preferredHarness: .pi,
            dailyBudgetUsd: 1.0
        )
        XCTAssertEqual(store.outcomes.count, 5)
        let newOutcome = try XCTUnwrap(store.outcomes.first)
        await store.evaluateOutcome(newOutcome.id)
        XCTAssertEqual(store.outcomes.first?.status, .achieved)

        // Resolve Needs You decision
        let pending = try XCTUnwrap(store.pendingDecisions.first)
        await store.resolveDecision(pending.id, optionId: pending.recommendedOptionId)
        XCTAssertEqual(store.pendingDecisions.count, 2)

        // Run Nightly Dreaming & approve diff
        let scoreBefore = store.understandingScore.overall
        await store.runNightlyDreaming()
        XCTAssertGreaterThan(store.understandingScore.overall, scoreBefore)
        if let firstDiff = store.lastDigest?.diffs.first {
            await store.reviewEvolutionDiff(diffId: firstDiff.diffId, approve: true)
            XCTAssertEqual(store.lastDigest?.diffs.first?.reviewStatus, .approved)
        }

        // Codable round-trip verification matching daemon JSON schema
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let encoded = try encoder.encode(store.tunnelStatus)
        let decoded = try decoder.decode(CloudflareTunnelStatus.self, from: encoded)
        XCTAssertEqual(decoded.tunnelUrl, store.tunnelStatus.tunnelUrl)
        XCTAssertEqual(decoded.freeTierQuota.monthlyCostUsd, 0.0)
    }

    @MainActor
    func testNativeMacRuntimeProbesTelemetryCueAndPersistence() async throws {
        // 1. Harness binary probing across macOS search paths
        let probes = PipiNativeMacRuntime.probeInstalledHarnesses()
        XCTAssertEqual(probes.count, 5)
        XCTAssertTrue(probes.contains(where: { $0.provider == .pi && $0.installed }))
        XCTAssertTrue(probes.contains(where: { $0.provider == .byok }))

        // 2. Host telemetry reading live OS metrics
        let host = PipiNativeMacRuntime.sampleHostTelemetry(activeSessionsCount: 2)
        XCTAssertEqual(host.nodeId, "mac-resident")
        XCTAssertEqual(host.kind, .mac)
        XCTAssertEqual(host.vitality, .busy)
        XCTAssertGreaterThan(host.cpuLoadPct, 0.0)
        XCTAssertGreaterThan(host.memoryUsedPct, 0.0)

        // 3. Frontmost app & git branch Cue detection
        let cue = PipiNativeMacRuntime.detectFrontmostAppContext(
            workspacePath: "/Users/jimizhou/Desktop/Projects/pipibot"
        )
        XCTAssertFalse(cue.activeAppName.isEmpty)
        XCTAssertEqual(cue.actions.count, 3)

        // 4. All-in-one persistence round-trip in isolated temp file
        let tempUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipibot-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempUrl) }

        let storeA = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            enableEmbeddedBridge: false,
            stateFileUrl: tempUrl
        )
        XCTAssertEqual(storeA.connectionMode, .nativeResident)
        await storeA.createOutcome(
            title: "All-in-One Persist Check",
            domain: .work,
            goal: "Verify resident-state.json reloads across restarts",
            preferredHarness: .claudeCode,
            dailyBudgetUsd: 1.5
        )
        storeA.setKeepAwake(true)
        XCTAssertTrue(storeA.bridgeSupervisor.keepAwakeEnabled)
        storeA.setKeepAwake(false)

        let storeB = PipiAppStore(
            autoConnect: false,
            enableNativeRuntime: true,
            enableEmbeddedBridge: false,
            stateFileUrl: tempUrl
        )
        XCTAssertTrue(storeB.outcomes.contains(where: { $0.title == "All-in-One Persist Check" }))
        XCTAssertFalse(storeB.bridgeSupervisor.keepAwakeEnabled)
    }
}
