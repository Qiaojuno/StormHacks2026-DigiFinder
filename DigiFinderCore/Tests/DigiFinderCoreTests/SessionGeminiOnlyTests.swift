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

    /// Owner decision: within reach does not end the search; the user picks it up and Gemini checks what's held.
    private func atReach() -> SessionHarness {
        var h = SessionHarness(onDevice: false)
        h.startGoal(SessionFixtures.coffee)
        h.send(.motion(yawDegrees: 0, steps: 0, walking: false))
        return h
    }

    func testWithinReachAsksToPickItUp() {
        var h = atReach()
        let e = h.send(.itemSeen(clock: 12, distance: 0.9))
        XCTAssertEqual(said(e), ["Coffee, within reach.", "Pick it up and hold it out."])
        XCTAssertFalse(e.contains(.markDone(SessionFixtures.coffee)), "not done until it's held")
        XCTAssertEqual(h.state.step, .confirm)
        XCTAssertNotNil(h.state.goal)
    }

    func testHoldingTheRightItemEndsTheSearch() {
        var h = atReach()
        h.send(.itemSeen(clock: 12, distance: 0.9))
        let e = h.send(.confirmed(ProductInfo(code: "gemini", name: "Starbucks coffee"), isGoal: true))
        XCTAssertEqual(said(e), ["Got it: coffee.", "Volume up for another item."])
        XCTAssertTrue(e.contains(.markDone(SessionFixtures.coffee)))
        XCTAssertNil(h.state.goal)
    }

    func testWrongItemPutBackAndSearchAgain() {
        var h = atReach()
        h.send(.itemSeen(clock: 12, distance: 0.9))
        let e = h.send(.confirmed(ProductInfo(code: "gemini", name: "green tea"), isGoal: false))
        XCTAssertEqual(said(e), ["That's green tea, not coffee. Put it back."])
        XCTAssertFalse(e.contains(.markDone(SessionFixtures.coffee)))
        XCTAssertNotEqual(h.state.step, .confirm, "back to the search")
        XCTAssertNotNil(h.state.goal)
    }

    func testNotHoldingRemindsAndNeverGivesUp() {
        var h = atReach()
        h.send(.itemSeen(clock: 12, distance: 0.9))
        let lines = said(h.advance(200))
        XCTAssertTrue(lines.contains("Pick it up and hold it out."))
        XCTAssertFalse(lines.contains { $0.contains("couldn't find") })
        XCTAssertEqual(h.state.step, .confirm)
    }

    func testWalkingAwayWithoutItGoesBackToTheSearch() {
        var h = atReach()
        h.send(.itemSeen(clock: 12, distance: 0.9))
        h.send(.motion(yawDegrees: 0, steps: 4, walking: true))
        h.advance(5)
        XCTAssertNotEqual(h.state.step, .confirm)
        XCTAssertNotNil(h.state.goal)
    }

    func testFartherSightingGivesDirection() {
        var h = SessionHarness(onDevice: false)
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(h.send(.itemSeen(clock: 2, distance: 3))).first, "Coffee at 2 o'clock, about 3 meters.")
    }
}
