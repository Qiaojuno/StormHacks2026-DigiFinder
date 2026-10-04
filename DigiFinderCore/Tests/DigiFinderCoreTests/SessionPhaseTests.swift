// Two layers (owner spec): motion state (Walking / Standing) read by the task phases, never set by them;
// the item rule in every search phase; no timer-based guesses.
import XCTest
@testable import DigiFinderCore

final class SessionPhaseTests: XCTestCase {
    /// Name the item while standing in front of it → Pick, without FindAisle prompts.
    func testNamedWhileStandingInFrontOfIt() {
        var h = SessionHarness()
        h.send(.motion(yawDegrees: 0, steps: 0, walking: false))
        h.startGoal(SessionFixtures.coffee)
        let e = h.send(.itemSeen(clock: 12, distance: 0.8))
        XCTAssertEqual(said(e), ["Point at it with one finger."])
        XCTAssertEqual(works(e), [SessionFixtures.pointingWork])
        XCTAssertEqual(h.state.step, .pick)
        let later = said(h.advance(12))
        XCTAssertFalse(later.contains("I can't see any signs. Turn slowly."))
        XCTAssertFalse(later.contains("Take two steps back."))
    }

    /// Walk past the item at 1 m → "Stop. Coffee at 1 o'clock." once; Pick only after Standing.
    func testWalkingPastTheItemSaysStopOnceThenPicksWhenStanding() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.motion(yawDegrees: 0, steps: 10, walking: true))
        XCTAssertEqual(said(h.send(.itemSeen(clock: 1, distance: 1.0))), ["Stop. Coffee at 1 o'clock."])
        h.advance(0.5)
        XCTAssertEqual(said(h.send(.itemSeen(clock: 1, distance: 0.9))), [], "said once")
        XCTAssertEqual(said(h.send(.itemSeen(clock: 12, distance: 0.8), .motion(yawDegrees: 0, steps: 12, walking: true))), [])
        XCTAssertEqual(h.state.step, .findAisle)
        let stop = h.send(.motion(yawDegrees: 0, steps: 13, walking: false))
        XCTAssertEqual(said(stop), ["Point at it with one finger."])
        XCTAssertEqual(h.state.step, .pick)
    }

    func testStandingTooLateAfterTheItemWasLastSeenDoesNotPick() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.motion(yawDegrees: 0, steps: 10, walking: true), .itemSeen(clock: 12, distance: 1.0))
        h.advance(6)                                               // kept walking; the item is gone
        XCTAssertEqual(said(h.send(.motion(yawDegrees: 0, steps: 20, walking: false))), [])
        XCTAssertEqual(h.state.step, .findAisle)
    }

    func testFartherSightingsAreRateLimited() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(h.send(.itemSeen(clock: 2, distance: 3))), ["Coffee at 2 o'clock, about 3 meters."])
        XCTAssertEqual(said(h.send(.itemSeen(clock: 2, distance: 2.8))), [])
        XCTAssertEqual(said(h.send(.itemSeen(clock: 1, distance: 2.5))), ["Coffee at 1 o'clock, about 3 meters."], "direction changed")
        h.advance(3)
        XCTAssertEqual(said(h.send(.itemSeen(clock: 1, distance: 2.0))), ["Coffee at 1 o'clock, about 2 meters."], "~3 s passed")
    }

    /// Enter the target aisle and walk slowly for 10 s with no shelf-sign match → still InAisle.
    func testWalkingTheAisleWithoutAMatchStaysInAisle() {
        var h = SessionHarness()
        h.enterAisle()
        var spoken: [String] = []
        for i in 1...20 {
            spoken += said(h.send(.motion(yawDegrees: -90, steps: i / 2, walking: true)))
            spoken += said(h.advance(0.5))
        }
        XCTAssertEqual(h.state.step, .inAisle)
        XCTAssertEqual(spoken, [], "no timer turns the user to the shelf")
    }

    /// Shelf-sign match while walking → "Stop here. Turn to the shelf…"; Pick only after Standing.
    func testShelfSignWhileWalkingWaitsForStanding() {
        var h = SessionHarness()
        h.enterAisle()
        XCTAssertEqual(said(h.send(.signs([SessionFixtures.shelfSign]))), ["Stop. Shelf at 9 o'clock."])
        XCTAssertEqual(said(h.send(.signs([SessionFixtures.shelfSign]))), [], "said once")
        XCTAssertEqual(said(h.send(.motion(yawDegrees: -90, steps: 1, walking: true))), [])
        XCTAssertEqual(said(h.advance(10)), [])
        XCTAssertEqual(h.state.step, .inAisle)
        XCTAssertEqual(said(h.send(.motion(yawDegrees: -90, steps: 2, walking: false))),
                       ["Point at the shelf, chest height."])
        XCTAssertEqual(h.state.step, .pick)
    }

    func testShelfSignWhileStandingPicksAtOnce() {
        var h = SessionHarness()
        h.enterAisle()
        h.send(.motion(yawDegrees: -90, steps: 1, walking: false))
        XCTAssertEqual(said(h.send(.signs([SessionFixtures.shelfSign]))),
                       ["Stop. Shelf at 9 o'clock.", "Point at the shelf, chest height."])
        XCTAssertEqual(h.state.step, .pick)
    }

    /// In Pick, the user walks away → back to InAisle, silently (no haptics either: the session has none).
    func testWalkingAwayFromPickGoesBackSilently() {
        var h = SessionHarness()
        h.reachShelf()
        XCTAssertEqual(h.state.step, .pick)
        let e = h.send(.motion(yawDegrees: -90, steps: 5, walking: true))
        XCTAssertEqual(said(e), [])
        XCTAssertEqual(works(e), [SessionFixtures.signageWork])
        XCTAssertEqual(h.state.step, .inAisle)
    }

    func testPickFromASightingReturnsToFindAisle() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.itemSeen(clock: 12, distance: 1.0))
        XCTAssertEqual(h.state.step, .pick)
        XCTAssertEqual(said(h.send(.motion(yawDegrees: 0, steps: 3, walking: true))), [])
        XCTAssertEqual(h.state.step, .findAisle)
    }

    func testPhasesNeverSetTheMotionState() {
        var h = SessionHarness()
        h.send(.motion(yawDegrees: 0, steps: 0, walking: true))
        h.startGoal(SessionFixtures.coffee)
        h.send(.itemSeen(clock: 12, distance: 1.0))
        XCTAssertTrue(h.state.isWalking)
        h.send(.signs([SessionFixtures.coffeeSign]), .arrivedAtAisle(clock: 9))
        XCTAssertTrue(h.state.isWalking)
        h.send(.motion(yawDegrees: 0, steps: 1, walking: false))
        XCTAssertFalse(h.state.isWalking)
    }

    // MARK: Aisle end

    func testAisleEndAfterFiveSteps() {
        var h = SessionHarness()
        h.enterAisle()
        h.send(.motion(yawDegrees: -90, steps: 3, walking: true))
        XCTAssertEqual(said(h.send(.aisleEnd)), [], "fewer than 5 steps: the aisle's own entrance")
        h.send(.motion(yawDegrees: -90, steps: 8, walking: true))
        let e = h.send(.aisleEnd)
        XCTAssertEqual(said(e), ["End of aisle. Item not found here.", "Say 'find staff' or 'next'."])
        XCTAssertFalse(e.contains { if case .chime = $0 { return true } else { return false } })
        XCTAssertEqual(h.state.step, .inAisle)
        XCTAssertEqual(said(h.send(.aisleEnd)), [], "once per item")
        XCTAssertEqual(VoiceCommandParser.parse("next"), .stop)
        XCTAssertEqual(said(h.send(.routed(.command(.stop)))), ["Stopped.", "Volume up for another item."])
    }

    func testAisleEndPedometerBackup() {
        var h = SessionHarness()
        h.enterAisle()
        XCTAssertEqual(said(h.send(.motion(yawDegrees: -90, steps: 25, walking: true))), [])
        XCTAssertEqual(said(h.send(.motion(yawDegrees: -90, steps: 29, walking: true))),
                       ["End of aisle. Item not found here.", "Say 'find staff' or 'next'."])
    }

    func testAisleEndIgnoredOutsideTheAisle() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.motion(yawDegrees: 0, steps: 30, walking: true))
        XCTAssertEqual(said(h.send(.aisleEnd)), [])
    }

    func testAisleEndWaitsDuringTalking() {
        var h = SessionHarness()
        h.enterAisle()
        h.send(.motion(yawDegrees: -90, steps: 8, walking: true))
        h.send(.talkPressed)
        XCTAssertEqual(said(h.send(.aisleEnd)), [])
        XCTAssertTrue(said(h.send(.notUnderstood(noisy: false))).contains("End of aisle. Item not found here."))
    }
}
