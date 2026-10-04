import XCTest
@testable import DigiFinderCore

final class GeometryClockTests: XCTestCase {
    func testClockWrapsAndRounds() {
        XCTAssertEqual(clockPosition(degreesRight: 400), 1)
        XCTAssertEqual(clockPosition(degreesRight: -400), 11)
        XCTAssertEqual(clockPosition(degreesRight: 360), 12)
        XCTAssertEqual(clockPosition(degreesRight: .nan), 12)
        XCTAssertEqual(clockPosition(degreesRight: 165), 6)
        XCTAssertEqual(clockPosition(degreesRight: -165), 6)
        XCTAssertEqual(clockPosition(degreesRight: -30), 11)
        XCTAssertEqual(clockPosition(degreesRight: 270), 9)
    }

    func testClockHelpers() {
        XCTAssertEqual(clockDegrees(12), 0); XCTAssertEqual(clockDegrees(3), 90)
        XCTAssertEqual(clockDegrees(9), -90); XCTAssertEqual(clockDegrees(6), 180); XCTAssertEqual(clockDegrees(1), 30)
        for c in 1...12 { XCTAssertEqual(clockPosition(degreesRight: clockDegrees(c)), c) }
        XCTAssertEqual(normalizedClock(0), 12); XCTAssertEqual(normalizedClock(13), 1); XCTAssertEqual(normalizedClock(-1), 11)
        XCTAssertEqual(clockPhrase(9), "9 o'clock")
        XCTAssertEqual(clockTurnCue(9), "Turn to 9 o'clock.")
        XCTAssertEqual(clockRelativeWords(12), "ahead")
        XCTAssertEqual(clockRelativeWords(1), "slightly right")
        XCTAssertEqual(clockRelativeWords(11), "slightly left")
        XCTAssertEqual(clockRelativeWords(3), "right")
        XCTAssertEqual(clockRelativeWords(9), "left")
        XCTAssertEqual(clockRelativeWords(6), "behind")
    }

    func testRelativeWordsToClock() {
        XCTAssertEqual(clockPosition(relative: "slightly right"), 1)
        XCTAssertEqual(clockPosition(relative: "a little to the left"), 11)
        XCTAssertEqual(clockPosition(relative: "on your right"), 3)
        XCTAssertEqual(clockPosition(relative: "on your left"), 9)
        XCTAssertEqual(clockPosition(relative: "behind you"), 6)
        XCTAssertEqual(clockPosition(relative: "straight ahead"), 12)
        XCTAssertEqual(clockPosition(relative: "at 2 o'clock"), 2)
        XCTAssertNil(clockPosition(relative: "aisle six"))
    }

    func testClockFromImage() {
        let k = Mat3.intrinsics(fx: 1000, fy: 1000, cx: 960, cy: 720)
        XCTAssertEqual(clockPosition(portraitX: 0.5, intrinsics: k, sensorHeight: 1440), 12)
        XCTAssertEqual(clockPosition(portraitX: 0.5, horizontalFOV: 100), 12)
        XCTAssertEqual(clockPosition(portraitX: 1.0, horizontalFOV: 100), 2)    // 50° right
        XCTAssertEqual(clockPosition(portraitX: 0.0, horizontalFOV: 100), 10)
        XCTAssertEqual(Geometry.degreesRight(portraitX: 0.9, horizontalFOV: 0), 0)
    }
}

final class GeometryHelperTests: XCTestCase {
    func testAngles() {
        XCTAssertEqual(Geometry.normalizeDegrees(190), -170, accuracy: 1e-9)
        XCTAssertEqual(Geometry.normalizeDegrees(-180), 180, accuracy: 1e-9)
        XCTAssertEqual(Geometry.normalizeDegrees(.infinity), 0)
        XCTAssertEqual(Geometry.relativeDegreesRight(heading: 350, target: 10), 20, accuracy: 1e-9)
        XCTAssertEqual(Geometry.relativeDegreesRight(heading: 10, target: 350), -20, accuracy: 1e-9)
    }

    func testPinhole() {
        let k = Mat3.intrinsics(fx: 500, fy: 500, cx: 160, cy: 120)
        let p = Geometry.unproject(u: 260, v: 70, depth: 2, intrinsics: k)
        XCTAssertEqual(p.x, 0.4, accuracy: 1e-5); XCTAssertEqual(p.y, -0.2, accuracy: 1e-5); XCTAssertEqual(p.z, 2)
        let back = Geometry.project(p, intrinsics: k)
        XCTAssertEqual(back?.x ?? 0, 260, accuracy: 1e-3); XCTAssertEqual(back?.y ?? 0, 70, accuracy: 1e-3)
        XCTAssertNil(Geometry.project(Vec3(x: 0, y: 0, z: -1), intrinsics: k))
        XCTAssertEqual(Geometry.distanceFromBoxHeight(normalizedHeight: 0.5, intrinsics: Mat3.intrinsics(fx: 1000, fy: 1000, cx: 960, cy: 720),
                                                      sensorWidth: 1920) ?? 0, 2.1875, accuracy: 1e-9)
        XCTAssertNil(Geometry.distanceFromBoxHeight(normalizedHeight: 0, intrinsics: k, sensorWidth: 1920))
        XCTAssertEqual(Geometry.timeToContact(previousHeight: 0.1, currentHeight: 0.11, dt: 0.1) ?? 0, 1.1, accuracy: 1e-9)
        XCTAssertNil(Geometry.timeToContact(previousHeight: 0.11, currentHeight: 0.1, dt: 0.1))   // shrinking
    }

    func testMatrixSafety() {
        let bad = Mat3(m: [1, 2])
        XCTAssertFalse(bad.isValid)
        XCTAssertEqual(bad.fx, 1)
        XCTAssertEqual(bad.apply(Vec3(x: 1, y: 2, z: 3)), Vec3(x: 1, y: 2, z: 3))
        let k = Mat3.intrinsics(fx: 2, fy: 3, cx: 4, cy: 5)
        XCTAssertEqual(k * .identity, k)
        XCTAssertEqual(k.transposed[0, 2], 0); XCTAssertEqual(k.transposed[2, 0], 4)
        XCTAssertEqual(k.scaled(x: 0.5, y: 0.5).cx, 2)
    }

    func testPointingAndShapes() {
        let spot = Geometry.pointedSpot(tip: NormPoint(x: 0.5, y: 0.5), dip: NormPoint(x: 0.5, y: 0.6), extend: 1.5)
        XCTAssertEqual(spot.y, 0.35, accuracy: 1e-9)                 // finger points up (toward smaller y)
        let target = NormRect(x: 0.7, y: 0.3, width: 0.1, height: 0.1)
        XCTAssertEqual(Geometry.pointingDirection(from: NormPoint(x: 0.5, y: 0.35), to: target), "right")
        XCTAssertEqual(Geometry.pointingDirection(from: NormPoint(x: 0.75, y: 0.9), to: target), "up")
        XCTAssertEqual(Geometry.pointingDirection(from: NormPoint(x: 0.75, y: 0.1), to: target), "down")
        XCTAssertNil(Geometry.pointingDirection(from: NormPoint(x: 0.75, y: 0.35), to: target))
        let u = NormRect(x: 0, y: 0, width: 0.2, height: 0.2).union(NormRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1))
        XCTAssertEqual(u.maxX, 0.6, accuracy: 1e-9)
        let c = NormRect(x: -0.1, y: 0.9, width: 0.3, height: 0.3).clamped()
        XCTAssertEqual(c.x, 0); XCTAssertEqual(c.width, 0.2, accuracy: 1e-9); XCTAssertEqual(c.height, 0.1, accuracy: 1e-9)
        XCTAssertEqual(NormPoint(x: 0, y: 0).distance(to: NormPoint(x: 0.3, y: 0.4)), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Vec3(x: 3, y: 9, z: 4).horizontalDistance, 5, accuracy: 1e-6)
        XCTAssertEqual(Vec3(x: 1, y: 1, z: 1).distance(to: .zero), Float(3).squareRoot(), accuracy: 1e-6)
    }

    func testPhoneFlipped() {
        XCTAssertTrue(Geometry.depthLooksBlocked([Float](repeating: 0.05, count: 100)))
        XCTAssertFalse(Geometry.depthLooksBlocked([Float](repeating: 0.05, count: 50) + [Float](repeating: 2, count: 50)))
        XCTAssertFalse(Geometry.depthLooksBlocked([0.05, 0.05]))     // too few samples
    }
}

final class GeometryDangerTests: XCTestCase {
    private func wall(z: Float, x: Float = 0, count: Int = 60) -> [Vec3] {
        (0..<count).map { i in Vec3(x: x + Float(i % 5) * 0.04 - 0.08, y: Float(i % 7) * 0.1 - 0.3, z: z) }
    }

    func testCorridorObstacle() {
        let pts = wall(z: 1.5, count: 100) + wall(z: 1.0, x: 0.2, count: 50)
        let o = corridorObstacle(pts)
        XCTAssertEqual(o?.distance, 1.0)
        XCTAssertEqual(o?.x ?? 0, 0.2, accuracy: 0.05)
        XCTAssertEqual(o?.points.count, 50)
        XCTAssertEqual(o?.corridorCount, 150)
        XCTAssertEqual(nearestInCorridor(pts), 1.0)
        // Standing (the DangerDetector's corridor while not walking): hand / held item within 0.8 m ignored.
        let standing = Corridor(minForward: ThreatTuning.stillMinDistance)
        XCTAssertNil(corridorObstacle(wall(z: 0.5), c: standing))
        XCTAssertEqual(corridorObstacle(wall(z: 0.5) + wall(z: 1.2), c: standing)?.distance, 1.2)
        XCTAssertNil(corridorObstacle(wall(z: 1, x: 1.0)))             // outside the corridor
        XCTAssertNil(corridorObstacle([Vec3(x: .nan, y: 0, z: 1)] + wall(z: 1, count: 39)))
    }

    func testClosingSpeedAndTTC() {
        let h: [(t: Double, d: Float)] = [(0, 2.0), (0.1, 1.92), (0.2, 1.79), (0.3, 1.71), (0.4, 1.6)]
        XCTAssertEqual(closingSpeed(h) ?? 0, 1.0, accuracy: 0.05)
        XCTAssertNil(closingSpeed([(0, 2.0)]))
        XCTAssertNil(closingSpeed([(0, 2.0), (0.01, 1.9)]))             // < 50 ms of history
        XCTAssertEqual(timeToContact(distance: 1.5, closingSpeed: 1) ?? 0, 1.5, accuracy: 1e-6)
        XCTAssertNil(timeToContact(distance: 1.5, closingSpeed: -0.5))
        var hist = GeometryDistanceHistory()
        for i in 0..<30 { hist.add(t: Double(i) / 30, distance: 3 - Float(i) / 30) }
        XCTAssertEqual(hist.closingSpeed ?? 0, 1, accuracy: 0.01)
        XCTAssertLessThanOrEqual(hist.samples.count, 16)                 // 0.5 s window at 30 Hz
        XCTAssertEqual(hist.timeToContact ?? 0, 2.03, accuracy: 0.05)
        hist.add(t: 1.0, distance: 0.8)                                  // a different object: restart
        XCTAssertEqual(hist.samples.count, 1)
        hist.add(t: 1.1, distance: nil)
        XCTAssertTrue(hist.samples.isEmpty)
    }

    func testEmergencyRule() {
        XCTAssertTrue(isEmergency([(t: 0, d: 1.4), (t: 0.5, d: 0.9)], rotationRate: 0))
        XCTAssertFalse(isEmergency([(t: 0, d: 1.4), (t: 0.5, d: 0.9)], rotationRate: 2))          // lanyard swing
        XCTAssertFalse(isEmergency([(t: 0, d: 1.4), (t: 0.5, d: 0.9)], rotationRate: -2))
        XCTAssertTrue(isEmergency([(t: 0, d: 2.9), (t: 0.5, d: 2.0)], rotationRate: 0))            // TTC ≈ 1.1 s
        XCTAssertFalse(isEmergency([(t: 0, d: 3.5), (t: 0.5, d: 3.1)], rotationRate: 0))           // too far
        XCTAssertTrue(isEmergency([(t: 0, d: 1.0), (t: 0.5, d: 0.85)], rotationRate: 0))
    }

    func testDangerRuleNeedsTwoFrames() {
        var rule = GeometryDangerRule()
        var firedAt: Float?
        for i in 0..<90 {
            let t = Double(i) / 30, d = Float(2.5 - t)                   // walking into something at 1 m/s
            if rule.update(t: t, distance: d, rotationRate: 0) { firedAt = d; break }
        }
        XCTAssertNotNil(firedAt)
        XCTAssertEqual(firedAt ?? 0, 1.45, accuracy: 0.1)
        var still = GeometryDangerRule()
        for i in 0..<60 { XCTAssertFalse(still.update(t: Double(i) / 30, distance: 0.9, rotationRate: 0)) }   // stationary rule
        var one = GeometryDangerRule()
        _ = one.update(t: 0, distance: 1.4, rotationRate: 0)
        XCTAssertFalse(one.update(t: 0.5, distance: 0.9, rotationRate: 0))   // first emergency frame
        XCTAssertTrue(one.update(t: 0.6, distance: 0.8, rotationRate: 0))    // second in a row
        XCTAssertFalse(one.update(t: 0.65, distance: 0.78, rotationRate: 3)) // rotating: streak broken
    }

    /// Points along x (step 5 cm) at depth z, three heights in the waist-to-head band.
    private func strip(_ x0: Float, _ x1: Float, z: Float) -> [Vec3] {
        stride(from: x0, through: x1, by: 0.05).flatMap { x in [-0.2, 0, 0.2].map { Vec3(x: x, y: Float($0), z: z) } }
    }

    func testSteerToClock() {
        let far = strip(-3, 3, z: 6)                               // open space, ~±26° visible
        let post = strip(-0.15, 0.15, z: 1.5)                       // narrow obstacle ahead
        let leftWall = strip(-0.6, -0.4, z: 1.5)
        XCTAssertEqual(steerDirection(far + post, obstacleX: 0.05, obstacleZ: 1.5), .clock(11))   // away from its side
        XCTAssertEqual(steerDirection(far + post, obstacleX: -0.05, obstacleZ: 1.5), .clock(1))
        XCTAssertEqual(steerDirection(far + post + leftWall, obstacleX: 0.05, obstacleZ: 1.5), .clock(1))
        XCTAssertEqual(steerDirection(far + strip(-3, 3, z: 1.5), obstacleX: 0, obstacleZ: 1.5), .stop)
        XCTAssertEqual(steerDirection([], obstacleX: 0, obstacleZ: 1), .unknown)
        XCTAssertEqual(steerClock(degreesRight: 10), 1)
        XCTAssertEqual(steerClock(degreesRight: -10), 11)
        XCTAssertEqual(steerClock(degreesRight: 60), 2)
    }

    func testAlertPhrase() {
        XCTAssertEqual(alertPhrase(label: "person", steer: .clock(1), distance: 2), "Person ahead, 2 meters, steer to 1 o'clock")
        XCTAssertEqual(alertPhrase(label: "cart", steer: .stop, distance: 0.6), "Cart ahead, under 1 meter, stop. Turn slowly.")
        XCTAssertEqual(alertPhrase(label: "  ", steer: .unknown), "Obstacle ahead")
        XCTAssertEqual(alertPhrase(label: "person", steer: .clock(11), distance: 1.4, inSteps: true), "Person ahead, 2 steps, steer to 11 o'clock")
        XCTAssertEqual(clearPathPhrase(meters: 3.2), "Clear ahead, about 3 meters. Walk straight.")
        XCTAssertEqual(clearPathPhrase(meters: nil), "Clear ahead. Walk straight.")
    }

    func testThreatOnlyForRealRisks() {
        func k(_ i: ThreatInput) -> ThreatKind { assessThreat(i).kind }
        // Person walking toward a still user: high threat.
        XCTAssertEqual(k(ThreatInput(distance: 2, x: 0, closing: 1.2, walking: false, grounded: true, label: "Person")), .approaching)
        // Rolling cart while the user walks: closing 1.0 (user) + 0.8 (cart).
        XCTAssertEqual(k(ThreatInput(distance: 3, x: 0.1, closing: 1.8, walking: true, grounded: true, label: "Cart")), .approaching)
        // Unknown shape needs more approach speed than a person.
        XCTAssertEqual(k(ThreatInput(distance: 1.4, x: 0, closing: 0.6, walking: false, grounded: true, label: nil)), .none)
        XCTAssertEqual(k(ThreatInput(distance: 1.4, x: 0, closing: 0.6, walking: false, grounded: true, label: "Person")), .approaching)
        // Walking into a shelf / wall / standing person: the cane finds it.
        XCTAssertEqual(k(ThreatInput(distance: 1.2, x: 0, closing: 1.0, walking: true, grounded: true, label: "Shelf")), .none)
        // Sitting at a table: everything within reach is ignored, static things never alert.
        XCTAssertEqual(k(ThreatInput(distance: 0.5, x: 0, closing: 0.9, walking: false, grounded: true)), .none)
        XCTAssertEqual(k(ThreatInput(distance: 1.5, x: 0, closing: 0.1, walking: false, grounded: true)), .none)
        // Off to the side: not in the path.
        XCTAssertEqual(k(ThreatInput(distance: 1.5, x: 0.5, closing: 1.5, walking: false, grounded: true, label: "Person")), .none)
        // Head-height, not reaching the floor, walking toward it: low threat (spoken, no vibration).
        XCTAssertEqual(k(ThreatInput(distance: 1.5, x: 0, closing: 1.0, walking: true, grounded: false)), .overhead)
        // Standing at the shelf (motion state only, no task phase): the hand and held item within 0.8 m never
        // alert, even moving toward the phone; a cart rolling in still does.
        XCTAssertEqual(k(ThreatInput(distance: 0.5, x: 0, closing: 1.2, walking: false, grounded: true, label: "Cart")), .none)
        XCTAssertEqual(k(ThreatInput(distance: 0.9, x: 0, closing: 0.3, walking: false, grounded: true)), .none)
        XCTAssertEqual(k(ThreatInput(distance: 1.5, x: 0, closing: 0.9, walking: false, grounded: true, label: "Cart")), .approaching)
    }

    func testGrounded() {
        let o = GeometryObstacle(distance: 1.5, x: 0)
        let legs = (0..<20).map { i in Vec3(x: 0, y: -0.6 - Float(i) * 0.03, z: 1.5) }
        XCTAssertTrue(isGrounded(legs, obstacle: o, floorY: -1.3))
        XCTAssertFalse(isGrounded([], obstacle: o, floorY: -1.3))
    }

    /// Floor points 0.5–2 m ahead (10 cm bins, 10 points each) at `height(z)` relative to the floor.
    private func floorStrip(to end: Float, height: (Float) -> Float = { _ in 0 }) -> [Vec3] {
        stride(from: Float(0.55), to: end, by: 0.1).flatMap { z in
            (0..<10).map { i in Vec3(x: Float(i) * 0.06 - 0.27, y: -1.3 + height(z), z: z) }
        }
    }

    func testFloorThatFadesOutIsNotStairs() {
        // Shiny floor: no LiDAR returns past 2 m. Used to read as "stairs going down".
        XCTAssertNil(detectStairs(floorStrip(to: 2.0), floorY: -1.3))
    }

    func testGentleSlopeIsNotStairs() {
        // A slightly leaning phone makes the far floor look lower bit by bit: no sharp edge, no stairs.
        XCTAssertNil(detectStairs(floorStrip(to: 4.0) { z in -0.07 * (z - 0.5) }, floorY: -1.3))
    }

    func testSharpDropIsStairsDown() {
        let near = floorStrip(to: 1.6)
        let lower = stride(from: Float(1.65), to: 2.5, by: 0.1).flatMap { z in
            (0..<10).map { i in Vec3(x: Float(i) * 0.06 - 0.27, y: -1.3 - 0.36, z: z) }
        }
        XCTAssertEqual(detectStairs(near + lower, floorY: -1.3)?.up, false)
    }
}
