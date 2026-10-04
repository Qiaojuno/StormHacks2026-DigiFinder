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
        XCTAssertNil(corridorObstacle(wall(z: 0.5), c: .shelf))        // hand / held item ignored at the shelf
        XCTAssertEqual(corridorObstacle(wall(z: 0.5) + wall(z: 1.2), c: .shelf)?.distance, 1.2)
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
        // Shelf: stepping toward the shelf slowly doesn't alert; something approaching fast does.
        XCTAssertTrue(isEmergency([(t: 0, d: 1.0), (t: 0.5, d: 0.85)], rotationRate: 0))
        XCTAssertFalse(isEmergency([(t: 0, d: 1.0), (t: 0.5, d: 0.85)], rotationRate: 0, shelfMode: true))
        XCTAssertTrue(isEmergency([(t: 0, d: 1.8), (t: 0.5, d: 1.2)], rotationRate: 0, shelfMode: true))
        XCTAssertFalse(isEmergency([(t: 0, d: 1.0), (t: 0.5, d: 0.5)], rotationRate: 0, shelfMode: true))
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
        var shelf = GeometryDangerRule()
        for i in 0..<30 { XCTAssertFalse(shelf.update(t: Double(i) / 30, distance: 0.6 - Float(i) * 0.01, rotationRate: 0, shelfMode: true)) }
    }

    func testSteer() {
        let blockerRight = (0..<40).map { i in Vec3(x: 0.6, y: Float(i % 5) * 0.1 - 0.2, z: 1.2) }
        let blockerLeft = blockerRight.map { Vec3(x: -$0.x, y: $0.y, z: $0.z) }
        let openRight = (0..<40).map { i in Vec3(x: 0.6, y: Float(i % 5) * 0.1 - 0.2, z: 6) }   // beyond 5 m: visible, open
        let openLeft = openRight.map { Vec3(x: -$0.x, y: $0.y, z: $0.z) }
        XCTAssertEqual(steerDirection(blockerRight + openLeft, obstacleX: 0.1, obstacleZ: 1), .left)
        XCTAssertEqual(steerDirection(blockerLeft + openRight, obstacleX: 0.1, obstacleZ: 1), .right)
        XCTAssertEqual(steerDirection(openLeft + openRight, obstacleX: 0.1, obstacleZ: 1), .left)    // away from the obstacle
        XCTAssertEqual(steerDirection(openLeft + openRight, obstacleX: -0.1, obstacleZ: 1), .right)
        XCTAssertEqual(steerDirection(blockerLeft + blockerRight, obstacleX: 0, obstacleZ: 1), .stop)
        XCTAssertEqual(steerDirection([], obstacleX: 0, obstacleZ: 1), .unknown)
        XCTAssertEqual(steerDirection(openLeft, obstacleX: 0, obstacleZ: 1), .left)                   // right lane unseen
    }

    func testAlertPhrase() {
        XCTAssertEqual(alertPhrase(label: "person", steer: .right), "Person ahead, steer right")
        XCTAssertEqual(alertPhrase(label: "Tin can", steer: .stop), "Tin can ahead, stop")
        XCTAssertEqual(alertPhrase(label: "  ", steer: .unknown), "Obstacle ahead")
        XCTAssertEqual(alertPhrase(label: "", steer: .left), "Obstacle ahead, steer left")
    }
}

final class GeometryStairsTests: XCTestCase {
    let floorY: Float = -1.3
    let xs: [Float] = [-0.3, -0.1, 0.1, 0.3]

    /// Floor from 0.5 m, then `steps` risers of `rise` every `run` from `firstRiser`, then a landing to `end`.
    private func staircase(firstRiser: Float = 2.0, run: Float = 0.28, rise: Float = 0.18, steps: Int = 4,
                           end: Float = 3.8) -> [Vec3] {
        var pts: [Vec3] = []
        var z: Float = 0.5
        while z < end {
            let passed = z < firstRiser ? 0 : min(Int((z - firstRiser) / run) + 1, steps)
            for x in xs { pts.append(Vec3(x: x, y: floorY + Float(passed) * rise, z: z)) }
            z += 0.01
        }
        for i in 0..<steps {
            let rz = firstRiser + Float(i) * run
            var h = Float(i) * rise
            while h < Float(i + 1) * rise { for x in xs { pts.append(Vec3(x: x, y: floorY + h, z: rz)) }; h += 0.02 }
        }
        return pts
    }

    private func flat(from: Float, to: Float, h: Float = 0) -> [Vec3] {
        var pts: [Vec3] = []
        var z = from
        while z < to { for x in xs { pts.append(Vec3(x: x, y: floorY + h, z: z)) }; z += 0.01 }
        return pts
    }

    func testStairsUp() {
        let o = detectStairs(staircase(), floorY: floorY)
        XCTAssertEqual(o?.up, true)
        XCTAssertEqual(o?.steps, 4)
        XCTAssertEqual(o?.distance ?? 0, 2.0, accuracy: 0.11)
        XCTAssertEqual(o?.more, false)
    }

    func testStairsUpTopHidden() {
        let o = detectStairs(staircase(steps: 7, end: 4.2), floorY: floorY)   // steps above the waist band are filtered
        XCTAssertEqual(o?.up, true)
        XCTAssertEqual(o?.more, true)
        XCTAssertEqual(o?.steps, 4)
    }

    func testRiserBinsAreDropped() {
        // Explicit straddle bins halfway between treads.
        var pts: [Vec3] = []
        func bin(_ k: Int, _ h: Float) { for j in 0..<10 { for x in xs { pts.append(Vec3(x: x, y: floorY + h, z: Float(k) * 0.1 + 0.005 + Float(j) * 0.009)) } } }
        for k in 5...19 { bin(k, 0) }
        bin(20, 0.09); bin(21, 0.18); bin(22, 0.18); bin(23, 0.27); bin(24, 0.36); bin(25, 0.36); bin(26, 0.45)
        for k in 27...30 { bin(k, 0.54) }
        let o = detectStairs(pts, floorY: floorY)
        XCTAssertEqual(o?.up, true)
        XCTAssertEqual(o?.steps, 3)
        XCTAssertEqual(o?.distance ?? 0, 2.0, accuracy: 1e-5)
    }

    func testStairsDown() {
        let pts = flat(from: 0.5, to: 2.0) + flat(from: 2.3, to: 2.58, h: -0.18) + flat(from: 2.58, to: 2.86, h: -0.36)
            + flat(from: 2.86, to: 3.5, h: -0.54)
        let o = detectStairs(pts, floorY: floorY)
        XCTAssertEqual(o?.up, false)
        XCTAssertEqual(o?.distance ?? 0, 2.0, accuracy: 0.11)
        XCTAssertEqual(o?.steps, 3)
    }

    func testDropOffWithNothingBeyond() {
        let o = detectStairs(flat(from: 0.5, to: 1.8), floorY: floorY)
        XCTAssertEqual(o?.up, false)
        XCTAssertEqual(o?.distance ?? 0, 1.8, accuracy: 1e-4)
        XCTAssertNil(o?.steps)
        // Something standing there hides the floor: not a drop-off.
        let cartEdge = (0..<40).map { i in Vec3(x: Float(i % 4) * 0.2 - 0.3, y: -0.2, z: 2.2) }
        XCTAssertNil(detectStairs(flat(from: 0.5, to: 1.8) + cartEdge, floorY: floorY))
        XCTAssertNil(detectStairs(flat(from: 0.5, to: 4.0), floorY: floorY))     // floor fades out far away
    }

    func testNotStairs() {
        XCTAssertNil(detectStairs([], floorY: floorY))
        XCTAssertNil(detectStairs(staircase(steps: 1), floorY: floorY))           // one curb: the cane's job
        var ramp: [Vec3] = flat(from: 0.5, to: 2.0)
        var z: Float = 2.0
        while z < 4.0 { for x in xs { ramp.append(Vec3(x: x, y: floorY + (z - 2) * 0.15, z: z)) }; z += 0.01 }
        XCTAssertNil(detectStairs(ramp, floorY: floorY))
        let person = (0..<200).map { i in Vec3(x: Float(i % 4) * 0.2 - 0.3, y: floorY + Float(i / 4) * 0.018, z: 2.2) }
        XCTAssertNil(detectStairs(flat(from: 0.5, to: 2.1) + person, floorY: floorY))
        XCTAssertNil(detectStairs(staircase(rise: 0.3), floorY: floorY))          // rises too tall
        XCTAssertNil(detectStairs(staircase(), floorY: .nan))
    }

    func testFloorEstimate() {
        let pts = flat(from: 0.5, to: 2.5)
        XCTAssertEqual(estimateFloorY(pts) ?? 0, floorY, accuracy: 1e-5)
        XCTAssertNil(estimateFloorY(Array(pts.prefix(10))))
        var tracker = GeometryFloorTracker(initial: -1.2, smoothing: 0.5)
        XCTAssertEqual(tracker.update(pts) ?? 0, -1.25, accuracy: 1e-5)
        XCTAssertEqual(tracker.update([]) ?? 0, -1.25, accuracy: 1e-5)     // no estimate → keeps the last one
    }

    func testTrackerConfirmsAndAnnouncesOnce() {
        var tr = GeometryStairsTracker()
        let far = StairsObservation(up: true, distance: 3, steps: 8)
        XCTAssertNil(tr.update(far, yoloStairs: false, t: 0))
        XCTAssertNil(tr.update(far, yoloStairs: false, t: 0.03))
        XCTAssertEqual(tr.update(far, yoloStairs: false, t: 0.06), .first(far))
        XCTAssertNil(tr.update(StairsObservation(up: true, distance: 2.5, steps: 8), yoloStairs: true, t: 0.5))
        XCTAssertNil(tr.walked(steps: 1, t: 1))                                 // 1.8 m left
        guard case .near(let o)? = tr.walked(steps: 1, t: 1.5) else { return XCTFail("expected the 1 meter call") }
        XCTAssertEqual(o.distance, 1.1, accuracy: 1e-4)
        XCTAssertEqual(o.steps, 8)
        XCTAssertNil(tr.update(StairsObservation(up: true, distance: 0.9, steps: 8), yoloStairs: true, t: 2))
        XCTAssertNil(tr.update(nil, yoloStairs: false, t: 3))
        let next = StairsObservation(up: false, distance: 2, steps: nil)
        XCTAssertEqual(tr.update(next, yoloStairs: true, t: 9), .first(next))  // new staircase, YOLO confirms at once
        var close = GeometryStairsTracker()
        let near = StairsObservation(up: true, distance: 1.0, steps: 3)
        XCTAssertEqual(close.update(near, yoloStairs: true, t: 0), .first(near))
        XCTAssertNil(close.update(near, yoloStairs: true, t: 0.1))             // already close: no second line
    }

    func testPhrases() {
        XCTAssertEqual(stairsAnnouncement(StairsObservation(up: true, distance: 3.2, steps: 8)),
                       "Stairs going up, about 8 steps, 3 meters, 12 o'clock.")
        XCTAssertEqual(stairsAnnouncement(StairsObservation(up: true, distance: 2.6, steps: 4, more: true), clock: 1),
                       "Stairs going up, more than 4 steps, 3 meters, 1 o'clock.")
        XCTAssertEqual(stairsAnnouncement(StairsObservation(up: false, distance: 0.4)), "Stairs going down, 1 meter, 12 o'clock.")
        XCTAssertEqual(stairsNearAnnouncement(), "Stairs, 1 meter ahead.")
        XCTAssertEqual(spokenMeters(.nan), "1 meter")
    }
}

final class GeometryDeadReckoningTests: XCTestCase {
    func testArrivalBesideTheUser() {
        var dr = GeometryDeadReckoning(bearingDegreesRight: 30, distance: 10, heading: 0, steps: 100)
        XCTAssertEqual(dr.bearing(heading: 0), 30, accuracy: 1e-9)
        XCTAssertEqual(dr.distance, 10, accuracy: 1e-9)
        dr.update(heading: 0, steps: 106)                               // 4.2 m ahead
        XCTAssertEqual(dr.bearing(heading: 0), 48.3, accuracy: 0.5)
        XCTAssertFalse(dr.hasPassedSide(heading: 0))
        dr.update(heading: 0, steps: 112)                               // 8.4 m: the sign is beside us
        XCTAssertTrue(dr.hasPassedSide(heading: 0))
        XCTAssertEqual(dr.clock(heading: 0), 3)
        XCTAssertEqual(dr.clock(heading: 90), 12)                      // after "Turn to 3 o'clock."
        dr.update(heading: 0, steps: 0)                                 // pedometer reset: no movement
        XCTAssertTrue(dr.hasPassedSide(heading: 0))
    }

    func testLeftSideAndTurns() {
        var dr = GeometryDeadReckoning(bearingDegreesRight: -40, distance: 8, heading: 90, steps: 0)
        for s in stride(from: 2, through: 10, by: 2) { dr.update(heading: 90, steps: s) }
        XCTAssertTrue(dr.hasPassedSide(heading: 90))
        XCTAssertEqual(dr.clock(heading: 90), 9)
        dr.resight(bearingDegreesRight: 0, distance: 5, heading: 0, steps: 10)
        XCTAssertEqual(dr.bearing(heading: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(dr.lastSteps, 10)
    }
}
