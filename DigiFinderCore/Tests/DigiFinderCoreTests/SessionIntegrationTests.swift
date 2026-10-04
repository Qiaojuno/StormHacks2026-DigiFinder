// Contract additions applied in integration: products change slot, entrance clocks, shelf distance, setup settings.
import XCTest
@testable import DigiFinderCore

final class SessionIntegrationTests: XCTestCase {
    func testActuallyTwoProductsReplacesTheCurrentGoal() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.peanutButter)
        let e = h.send(.routed(.products([SessionFixtures.coffee, SessionFixtures.milk], .replace)))
        XCTAssertEqual(said(e), ["Okay, coffee instead."], "one item at a time: the first named item")
        XCTAssertEqual(h.state.goal, SessionFixtures.coffee)
        XCTAssertEqual(h.state.queue, [])
    }


    func testEntranceClockFromTheRunnerWins() {
        var h = SessionHarness(online: true)
        h.send(.outside(true))
        h.startGoal(SessionFixtures.coffee)
        let p = h.send(.entrancePicked(EntrancePick(x: 0.9, kind: .automatic, cartCorralX: 0.1, clock: 2, cartCorralClock: 10)))
        XCTAssertEqual(said(p), ["Entrance at 2 o'clock. Automatic door.", "Cart corral at 10 o'clock."])
    }

    func testShelfDistanceIsSpokenOncePerPointingStep() {
        var h = SessionHarness()
        h.reachShelf()
        XCTAssertEqual(h.state.step, .pick)
        XCTAssertEqual(said(h.send(.shelfDistance(0.75))), ["The shelf is about one step ahead."])
        XCTAssertEqual(said(h.send(.shelfDistance(0.75))), [])
        XCTAssertEqual(said(h.send(.shelfDistance(1.4))), [])
    }

    func testShelfDistanceIgnoredOutsidePick() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(h.send(.shelfDistance(0.8))), [])
    }

    func testWithoutOnlineHelpQuestionsAndEntranceStayOffline() {
        var h = SessionHarness(online: true, started: false)
        h.session.setOnlineHelp(false)
        let s = h.send(.started)
        XCTAssertFalse(s.contains(.classifyPlace))
        let q = h.send(.routed(.question("is this gluten free")))
        XCTAssertEqual(said(q), ["Online help isn't set up."])
        XCTAssertFalse(q.contains { if case .assist = $0 { return true } else { return false } })
        h.send(.outside(true))
        let e = h.startGoal(SessionFixtures.coffee)
        XCTAssertFalse(e.contains(.pickEntrance))
    }

    func testDistancesInSteps() {
        var h = SessionHarness(started: false)
        h.session.setDistanceInSteps(true)
        h.send(.started)
        let s = h.send(.stairs(StairsObservation(up: true, distance: 2.8, steps: 8)))
        XCTAssertEqual(said(s).first, "Stairs going up, about 8 steps, 4 steps away, 12 o'clock.")
    }

    func testVerbositySetting() {
        var h = SessionHarness()
        h.session.setVerbosity(.brief)
        XCTAssertEqual(h.state.verbosity, .brief)
        h.send(.started)
        XCTAssertEqual(h.state.verbosity, .brief, "kept across a new session")
    }
}
