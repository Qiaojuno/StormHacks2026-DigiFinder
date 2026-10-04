// Motion state (layer 1): hysteresis over a 1.5 s window of steps and acceleration spread; aisle end from LiDAR.
import XCTest
@testable import DigiFinderCore

final class MotionTests: XCTestCase {
    /// 30 Hz acceleration around 0.1 g with the given spread (alternating ±spread).
    private func feed(_ m: inout MotionStateTracker, from t0: Double, seconds: Double, spread: Double) -> Double {
        var t = t0
        var i = 0
        while t < t0 + seconds {
            m.addAcceleration(t: t, magnitude: 0.1 + (i % 2 == 0 ? spread : -spread))
            t += 1.0 / 30
            i += 1
        }
        return t
    }

    func testStandingTraceStaysStanding() {
        var m = MotionStateTracker()
        let t = feed(&m, from: 0, seconds: 3, spread: 0.005)
        XCTAssertEqual(m.update(now: t), .standing)
    }

    func testWalkingTraceBecomesWalkingThenStandingWhenStill() {
        var m = MotionStateTracker()
        var t = feed(&m, from: 0, seconds: 2, spread: 0.15)
        XCTAssertEqual(m.update(now: t), .walking)
        t = feed(&m, from: t, seconds: 2, spread: 0.004)
        XCTAssertEqual(m.update(now: t), .standing)
    }

    func testStepsAloneMeanWalkingUnlessThePhoneIsStill() {
        var m = MotionStateTracker()
        m.addSteps(t: 0, total: 0)
        var t = feed(&m, from: 0, seconds: 1.5, spread: 0.04)          // in between: no decision from acceleration
        m.addSteps(t: t, total: 3)
        XCTAssertEqual(m.update(now: t), .walking)
        // A late pedometer batch while the phone is clearly still doesn't make it walking.
        var s = MotionStateTracker()
        s.addSteps(t: 0, total: 0)
        t = feed(&s, from: 0, seconds: 2, spread: 0.003)
        s.addSteps(t: t, total: 4)
        XCTAssertEqual(s.update(now: t), .standing)
    }

    func testInBetweenHoldsThePreviousState() {
        var m = MotionStateTracker()
        var t = feed(&m, from: 0, seconds: 2, spread: 0.15)
        XCTAssertEqual(m.update(now: t), .walking)
        t = feed(&m, from: t, seconds: 2, spread: 0.04)                // between 0.02 and 0.06
        XCTAssertEqual(m.update(now: t), .walking, "hold")
        t = feed(&m, from: t, seconds: 2, spread: 0.004)
        XCTAssertEqual(m.update(now: t), .standing)
        t = feed(&m, from: t, seconds: 2, spread: 0.04)
        XCTAssertEqual(m.update(now: t), .standing, "hold")
    }

    func testSensorDropoutHolds() {
        var m = MotionStateTracker()
        let t = feed(&m, from: 0, seconds: 2, spread: 0.15)
        XCTAssertEqual(m.update(now: t), .walking)
        XCTAssertNil(m.movement(at: t + 1).accelStd, "no fresh samples")
        XCTAssertEqual(m.update(now: t + 1), .walking, "dropout: hold")
        XCTAssertEqual(m.update(now: t + 10), .walking)
        var empty = MotionStateTracker(initial: .standing)
        XCTAssertEqual(empty.update(now: 5), .standing, "no sensor at all: hold")
    }

    func testDecisionThresholds() {
        XCTAssertEqual(MotionStateTracker.decide(MotionMovement(accelStd: 0.01, steps: 0)), .standing)
        XCTAssertEqual(MotionStateTracker.decide(MotionMovement(accelStd: 0.08, steps: 0)), .walking)
        XCTAssertNil(MotionStateTracker.decide(MotionMovement(accelStd: 0.04, steps: 1)))
        XCTAssertEqual(MotionStateTracker.decide(MotionMovement(accelStd: 0.04, steps: 2)), .walking)
        XCTAssertNil(MotionStateTracker.decide(MotionMovement(accelStd: nil, steps: 0)))
        XCTAssertEqual(MotionStateTracker.decide(MotionMovement(accelStd: nil, steps: 3)), .walking)
    }

    // MARK: Aisle end (LiDAR)

    /// Shelf-like points at lateral x, along the forward band.
    private func wall(_ x: Float) -> [Vec3] {
        stride(from: Float(1.0), through: 3.0, by: 0.1).flatMap { z in
            stride(from: Float(-0.8), through: 0.3, by: 0.1).map { y in Vec3(x: x, y: y, z: z) }
        }
    }

    func testAisleSides() {
        XCTAssertEqual(aisleSides(wall(-1) + wall(1)), AisleSides(left: true, right: true))
        XCTAssertEqual(aisleSides(wall(1)), AisleSides(left: false, right: true))
        XCTAssertEqual(aisleSides([Vec3(x: 0, y: -1.3, z: 2)]), AisleSides(left: false, right: false))
    }

    func testAisleEndFiresOnceAfterShelvesStopOnBothSides() {
        var a = AisleEndTracker()
        let both = AisleSides(left: true, right: true), open = AisleSides(left: false, right: false)
        XCTAssertFalse(a.update(t: 0, sides: open, walking: true), "open space before any aisle")
        var t = 0.0
        while t < 1.5 { XCTAssertFalse(a.update(t: t, sides: both, walking: true)); t += 0.1 }
        XCTAssertTrue(a.betweenShelves)
        XCTAssertFalse(a.update(t: t, sides: AisleSides(left: true, right: false), walking: true), "one side: a gap")
        XCTAssertFalse(a.update(t: t + 0.1, sides: open, walking: false), "standing: no")
        var fired = 0
        for i in 0..<10 where a.update(t: t + 0.2 + Double(i) * 0.1, sides: open, walking: true) { fired += 1 }
        XCTAssertEqual(fired, 1)
        XCTAssertFalse(a.betweenShelves)
    }
}
