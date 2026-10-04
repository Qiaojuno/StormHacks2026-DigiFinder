// Owner decision: wet floor signs from the on-device text reader: one vibration + the line, walking only, 20 s cooldown.
import XCTest
@testable import DigiFinderCore

final class WetFloorSignTests: XCTestCase {
    func testWords() {
        XCTAssertTrue(isWetFloorSignText(["CAUTION"]))
        XCTAssertTrue(isWetFloorSignText(["WET", "FLOOR"]))
        XCTAssertTrue(isWetFloorSignText(["Piso Mojado"]))
        XCTAssertFalse(isWetFloorSignText(["Floor 2", "Exit"]))
    }

    func testBuzzAndLineOnceWhileWalking() {
        var h = SessionHarness(grocery: false)
        h.startGoal(SessionFixtures.coffee)
        h.send(.motion(yawDegrees: 0, steps: 10, walking: true))
        let out = h.send(.wetFloorSign(clock: 1))
        XCTAssertTrue(out.contains(.buzz))
        XCTAssertTrue(said(out).contains("Wet floor sign, 1 o'clock."))
        XCTAssertFalse(h.send(.wetFloorSign(clock: 12)).contains(.buzz), "cooldown")
    }

    func testNothingWhileStanding() {
        var h = SessionHarness(grocery: false)
        h.startGoal(SessionFixtures.coffee)
        h.send(.motion(yawDegrees: 0, steps: 0, walking: false))
        XCTAssertEqual(h.send(.wetFloorSign(clock: 12)), [])
    }
}

/// Owner decision: Gemini reports a crowd on every scan; the warning is spoken once in a while and waits for alerts.
final class CrowdWarningTests: XCTestCase {
    func testOnceInAWhile() {
        var h = SessionHarness(grocery: false)
        h.startGoal(SessionFixtures.coffee)
        XCTAssertTrue(said(h.send(.crowded)).contains("Crowded here, be careful."))
        XCTAssertEqual(said(h.send(.crowded)), [], "not every scan")
    }

    func testWaitsForAnAlert() {
        var h = SessionHarness(grocery: false)
        h.startGoal(SessionFixtures.coffee)
        h.send(.danger(cutRecording: false))
        XCTAssertEqual(said(h.send(.crowded)), [])
        XCTAssertTrue(said(h.send(.dangerCleared)).contains("Crowded here, be careful."))
    }
}
