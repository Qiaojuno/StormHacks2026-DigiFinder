import XCTest
@testable import DigiFinderCore

/// The app's setting (owner decision): on-device item search is off; Gemini finds items, YOLO is only for obstacles.
final class SessionGeminiOnlyTests: XCTestCase {
    func testNoSignPromptsEvenInAGroceryStore() {
        var h = SessionHarness(grocery: true, onDevice: false)
        h.startGoal(SessionFixtures.coffee)
        let lines = said(h.advance(12))
        XCTAssertFalse(lines.contains("I can't see any signs. Turn slowly."))
        XCTAssertFalse(lines.contains("Take two steps back."))
    }

    func testWithinReachEndsTheSearchForAnyItem() {
        var h = SessionHarness(onDevice: false)
        h.startGoal(SessionFixtures.coffee)
        h.send(.motion(yawDegrees: 0, steps: 0, walking: false))
        let e = h.send(.itemSeen(clock: 12, distance: 0.9))
        XCTAssertEqual(said(e).first, "Coffee, within reach.")
        XCTAssertTrue(e.contains(.markDone(SessionFixtures.coffee)))
        XCTAssertNotEqual(h.state.step, .pick, "no pointing step without on-device label checks")
    }

    func testFartherSightingGivesDirection() {
        var h = SessionHarness(onDevice: false)
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(h.send(.itemSeen(clock: 2, distance: 3))).first, "Coffee at 2 o'clock, about 3 meters.")
    }
}
