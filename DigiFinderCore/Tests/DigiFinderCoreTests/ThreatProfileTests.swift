import XCTest
@testable import DigiFinderCore

/// Owner decision: grocery store alerts are sensitive; everywhere else (schools, campus, crowds) they stay calm.
final class ThreatProfileTests: XCTestCase {
    /// A person 2 m ahead, standing user, closing at `closing` m/s.
    private func person(distance: Float = 2, x: Float = 0, closing: Float, lateral: Float? = nil,
                        people: Int = 0) -> ThreatInput {
        ThreatInput(distance: distance, x: x, closing: closing, walking: false, grounded: true, label: "Person",
                    lateralSpeed: lateral, peopleInView: people)
    }

    func testStoreAlertsOnASlowApproachGeneralDoesNot() {
        let slow = person(distance: 1.5, closing: 0.7)                       // TTC ≈ 2.1 s
        XCTAssertEqual(assessThreat(slow, profile: .store).kind, .approaching)
        XCTAssertEqual(assessThreat(slow, profile: .general).kind, .none)
    }

    func testGeneralAlertsOnAFastCloseApproach() {
        let fast = person(distance: 1.5, closing: 1.2)                       // TTC 1.25 s
        XCTAssertEqual(assessThreat(fast, profile: .general).kind, .approaching)
    }

    func testGeneralIgnoresSomeoneCrossingInFront() {
        // Straight ahead now, but moving sideways 1 m/s: 1.25 m off to the side by contact.
        let crossing = person(distance: 1.5, closing: 1.2, lateral: 1.0)
        XCTAssertEqual(assessThreat(crossing, profile: .general).reason, "not on a collision course")
        XCTAssertEqual(assessThreat(crossing, profile: .store).kind, .approaching, "store ignores sideways motion")
    }

    func testGeneralAlertsOnSomeoneCuttingIntoThePath() {
        // Off to the side now, heading into the path.
        let cutting = person(distance: 1.5, x: 0.6, closing: 1.2, lateral: -0.5)
        XCTAssertEqual(assessThreat(cutting, profile: .general).kind, .approaching)
        XCTAssertEqual(assessThreat(cutting, profile: .store).kind, .none, "store only looks at where it is now")
    }

    func testCrowdOnlyAlertsWhenImminent() {
        let soon = person(distance: 1.5, closing: 1.2, people: 5)            // TTC 1.25 s
        XCTAssertEqual(assessThreat(soon, profile: .general).reason, "crowd: not imminent")
        let now = person(distance: 1.0, closing: 1.2, people: 5)             // TTC 0.83 s
        XCTAssertEqual(assessThreat(now, profile: .general).reason, "crowd: imminent collision")
    }

    func testCrowdDampingIsGeneralOnly() {
        let soon = person(distance: 1.5, closing: 1.2, people: 5)
        XCTAssertEqual(assessThreat(soon, profile: .store).kind, .approaching)
    }

    func testGeneralIsSlowerToAlertAndQuieterAfter() {
        XCTAssertGreaterThan(ThreatProfile.general.consecutiveFrames, ThreatProfile.store.consecutiveFrames)
        XCTAssertGreaterThan(ThreatProfile.general.cooldown, ThreatProfile.store.cooldown)
    }
}

/// Owner decision: a table in the path buzzes once at 0.8 m while walking; standing still never.
final class TableAlertTests: XCTestCase {
    /// Walking toward a table: one frame per 0.1 s at these distances. Returns the alert count.
    private func approach(_ r: inout TableAlertRule, from t0: Double, distances: [Float?], x: Float = 0,
                          label: String = "Table", walking: Bool = true) -> Int {
        distances.enumerated().filter { i, d in
            r.update(t: t0 + Double(i) * 0.1, walking: walking, rotating: false,
                     obstacle: d.map { GeometryObstacle(distance: $0, x: x) }, label: d == nil ? nil : label)
        }.count
    }

    func testBuzzesOnceAtPointEightMeters() {
        var r = TableAlertRule()
        XCTAssertEqual(approach(&r, from: 0, distances: [1.5, 1.3, 1.1, 0.9]), 0, "not yet")
        XCTAssertEqual(approach(&r, from: 0.4, distances: [0.8, 0.75]), 1)
        XCTAssertEqual(approach(&r, from: 0.6, distances: [0.7, 0.6, 0.5, nil, 0.6]), 0, "once per table")
    }

    func testTabletopDroppingBelowTheViewStillBuzzes() {
        var r = TableAlertRule()
        XCTAssertEqual(approach(&r, from: 0, distances: [1.4, 1.2, 1.0, nil]), 1)
    }

    func testNextTableAfterAPause() {
        var r = TableAlertRule()
        XCTAssertEqual(approach(&r, from: 0, distances: [0.8, 0.8]), 1)
        XCTAssertEqual(approach(&r, from: 0.2, distances: Array(repeating: nil, count: 35)), 0)
        XCTAssertEqual(approach(&r, from: 4, distances: [1.2, 0.8, 0.8]), 1, "re-armed after 3 s without a table")
    }

    func testStandingStillNeverAlerts() {
        var r = TableAlertRule()
        XCTAssertEqual(approach(&r, from: 0, distances: [1.2, 0.8, 0.6, 0.5, nil], walking: false), 0)
    }

    func testOnlyTablesInThePath() {
        var r = TableAlertRule()
        XCTAssertEqual(approach(&r, from: 0, distances: [0.8, 0.7, 0.6], label: "Chair"), 0)
        XCTAssertEqual(approach(&r, from: 1, distances: [0.8, 0.7, 0.6], label: "Vegetable"), 0)
        XCTAssertEqual(approach(&r, from: 2, distances: [0.8, 0.7, 0.6], x: 0.6), 0, "off to the side")
        XCTAssertEqual(approach(&r, from: 3, distances: [0.8, 0.7], label: "Kitchen & dining room table"), 1)
    }

    func testTableCorridorReachesTabletopHeight() {
        let c = TableAlertRule.corridor(floorY: -1.3)
        XCTAssertTrue(c.contains(Vec3(x: 0, y: -0.55, z: 1)), "75 cm tabletop")
        XCTAssertFalse(c.contains(Vec3(x: 0, y: -1.25, z: 1)), "not the floor")
    }
}

/// Fences and barricades from LiDAR shape: across the path at waist height, open above.
final class BarrierAlertTests: XCTestCase {
    /// A grid of points on a vertical plane at `z`, from `yFrom` to `yTo` (phone at y = 0, floor at -1.3).
    private func wall(z: Float, yFrom: Float, yTo: Float, xFrom: Float = -0.6, xTo: Float = 0.6) -> [Vec3] {
        var pts: [Vec3] = []
        var x = xFrom
        while x <= xTo {
            var y = yFrom
            while y <= yTo { pts.append(Vec3(x: x, y: y, z: z)); y += 0.05 }
            x += 0.03
        }
        return pts
    }

    func testWaistHighFenceIsABarrier() {
        let fence = wall(z: 1.2, yFrom: -1.0, yTo: -0.25)
        let b = BarrierAlertRule.find(fence, floorY: -1.3)
        XCTAssertNotNil(b)
        XCTAssertEqual(b?.distance ?? 0, 1.2, accuracy: 0.01)
    }

    func testFenceWithASignOnTopAndSparseRailsIsStillABarrier() {
        // Two rails only (top and bottom), plus a small sign sticking up above the phone.
        let rails = wall(z: 1.4, yFrom: -0.95, yTo: -0.9) + wall(z: 1.4, yFrom: -0.35, yTo: -0.3)
        let sign = wall(z: 1.4, yFrom: 0.1, yTo: 0.2, xFrom: -0.05, xTo: 0.05)
        let r = BarrierAlertRule.check(rails + sign, floorY: -1.3)
        XCTAssertNotNil(r.barrier, r.reason)
    }

    func testReasonSaysWhy() {
        XCTAssertTrue(BarrierAlertRule.check(wall(z: 1.2, yFrom: -1.2, yTo: 0.8), floorY: -1.3).reason.contains("above"))
        XCTAssertTrue(BarrierAlertRule.check([], floorY: -1.3).reason.contains("columns"))
    }

    func testFenceThreeMetersAwayCounts() {
        XCTAssertEqual(BarrierAlertRule.find(wall(z: 2.9, yFrom: -1.0, yTo: -0.25), floorY: -1.3)?.distance ?? 0, 2.9,
                       accuracy: 0.01)
    }

    func testWallIsNot() {
        XCTAssertNil(BarrierAlertRule.find(wall(z: 1.2, yFrom: -1.2, yTo: 0.8), floorY: -1.3), "fills the space above")
    }

    func testNarrowPostOrFarFenceIsNot() {
        XCTAssertNil(BarrierAlertRule.find(wall(z: 1.2, yFrom: -1.0, yTo: -0.25, xFrom: -0.1, xTo: 0.1), floorY: -1.3))
        XCTAssertNil(BarrierAlertRule.find(wall(z: 3.6, yFrom: -1.0, yTo: -0.25), floorY: -1.3))
    }

    func testAlertsOnceWhileWalking() {
        var r = BarrierAlertRule()
        let b = GeometryObstacle(distance: 1.2, x: 0)
        XCTAssertEqual((0..<3).filter { r.update(t: Double($0) * 0.1, walking: false, rotating: false, barrier: b) }.count, 0)
        XCTAssertEqual((0..<40).filter { r.update(t: 1 + Double($0) * 0.1, walking: true, rotating: false, barrier: b) }.count, 1)
        XCTAssertEqual((0..<3).filter { r.update(t: 30 + Double($0) * 0.1, walking: true, rotating: false, barrier: b) }.count, 1)
    }
}

/// Owner decision: a barrier alert always gives a clock direction, toward the side with the most room.
final class BarrierSteerTests: XCTestCase {
    private func plane(z: Float, xFrom: Float, xTo: Float) -> [Vec3] {
        var pts: [Vec3] = []
        var x = xFrom
        while x <= xTo {
            var y: Float = -0.7
            while y <= 0.5 { pts.append(Vec3(x: x, y: y, z: z)); y += 0.05 }
            x += 0.03
        }
        return pts
    }

    func testBarrierAcrossTheWholeViewStillGetsAClock() {
        // Barrier across the view, ending a bit sooner on the right; nothing fully open anywhere.
        let pts = plane(z: 2.0, xFrom: -1.5, xTo: 0.9) + plane(z: 2.6, xFrom: 0.9, xTo: 1.5)
        XCTAssertEqual(steerDirection(pts, obstacleX: 0, obstacleZ: 2, corridor: Corridor(below: 0.75)), .stop)
        let s = steerDirection(pts, obstacleX: 0, obstacleZ: 2, corridor: Corridor(below: 0.75), alwaysClock: true)
        guard case .clock(let h) = s else { return XCTFail("\(s)") }
        XCTAssertTrue((1...3).contains(h), "toward the right, where there's more room: \(h)")
    }
}
