// Every §5.12 ending: item done, session done, stop, not found, lost.
import XCTest
@testable import DigiFinderCore

final class SessionEndingTests: XCTestCase {
    func testItemDoneThenNext() {
        var h = SessionHarness()
        h.send(.routed(.product(SessionFixtures.coffee, .unspecified)))
        h.send(.signs([SessionFixtures.coffeeSign]), .arrivedAtAisle(clock: 9), .motion(yawDegrees: -90, steps: 0, walking: true),
               .signs([SessionFixtures.shelfSign]), .motion(yawDegrees: -90, steps: 2, walking: false))
        h.grab()
        let e = h.send(.confirmed(SessionFixtures.darkRoastInfo, isGoal: true))
        XCTAssertEqual(said(e), ["Got it: Starbucks Dark Roast. Put it in your cart.", "What's next?"], "one item at a time")
        XCTAssertTrue(e.contains(.chime(.done)))
    }

    func testSessionDoneOnThatsAll() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.routed(.product(SessionFixtures.milk, .add)))
        let e = h.send(.routed(.command(.thatsAll)))
        XCTAssertEqual(said(e), ["Shopping done. You found 0 items."])
        XCTAssertTrue(e.contains(.chime(.done)))
        XCTAssertTrue(e.contains(.setTarget(nil, candidates: [], destination: nil)))
        XCTAssertEqual(h.state.step, .idle)
        XCTAssertTrue(h.state.finished)
        XCTAssertEqual(h.state.queue, [])
    }

    func testSessionDoneAfterWhatsNextSilenceAndRunnerFallback() {
        var h = SessionHarness()
        h.reachShelf()
        h.grab()
        h.send(.confirmed(SessionFixtures.darkRoastInfo, isGoal: true))
        XCTAssertEqual(said(h.advance(13)), ["Shopping done. You found 1 item."], "no answer at all")
        XCTAssertEqual(h.state.step, .idle)
        XCTAssertTrue(h.state.finished)
        h.send(.started)
        XCTAssertEqual(h.state.foundCount, 0, "a new trip starts from zero")
    }

    func testDoneOrStopAnswersWhatsNext() {
        var h = SessionHarness()
        h.reachShelf()
        h.grab()
        h.send(.confirmed(SessionFixtures.darkRoastInfo, isGoal: true))
        XCTAssertEqual(said(h.send(.routed(.command(.finishTalking)))), ["Shopping done. You found 1 item."])
    }

    func testStopCancelsTheGoalThenNextOrWhatsNext() {
        var h = SessionHarness()
        h.send(.routed(.product(SessionFixtures.coffee, .unspecified)))
        let e = h.send(.routed(.command(.stop)))
        XCTAssertEqual(said(e), ["Stopped.", "What's next?"])
        XCTAssertTrue(e.contains(.chime(.done)))
        XCTAssertFalse(e.contains(.markDone(SessionFixtures.coffee)))
        XCTAssertFalse(e.contains(.listen))
        XCTAssertNil(h.state.goal)
    }

    func testNotFoundAfterNinetySecondsAtTheShelf() {
        var h = SessionHarness()
        h.send(.routed(.product(SessionFixtures.coffee, .unspecified)))
        h.send(.signs([SessionFixtures.coffeeSign]), .arrivedAtAisle(clock: 9), .motion(yawDegrees: -90, steps: 0, walking: true),
               .signs([SessionFixtures.shelfSign]), .motion(yawDegrees: -90, steps: 2, walking: false))
        XCTAssertEqual(h.state.step, .pick)
        XCTAssertFalse(said(h.advance(89)).contains(SessionPhrases.notFound))
        let e = h.advance(1)
        XCTAssertEqual(said(e), ["I didn't find it. It may be out of stock. Say 'find staff' for help.", "What's next?"])
        XCTAssertTrue(e.contains(.chime(.done)))
        XCTAssertNil(h.state.goal)
    }

    func testMatchesRestartTheNotFoundTimer() {
        var h = SessionHarness()
        h.reachShelf()
        h.advance(80)
        h.grab()
        h.send(.confirmed(ProductInfo(code: "2", name: "Blonde Roast"), isGoal: false))   // back to Pick
        XCTAssertFalse(said(h.advance(30)).contains(SessionPhrases.notFound))
    }

    func testLostThenGuidancePausedThenResumedByTalking() {
        var h = SessionHarness()
        h.send(.routed(.unknownProduct("tahini", .unspecified)))         // word search: no shelf vote
        let early = said(h.advance(29.5))
        XCTAssertEqual(early, ["I can't see any signs. Turn slowly."])
        XCTAssertEqual(said(h.advance(0.5)), ["I've lost track. Walk ahead slowly and I'll look for signs."])
        XCTAssertFalse(said(h.advance(59.5)).contains(SessionPhrases.guidancePaused))
        let e = h.advance(0.5)
        XCTAssertEqual(said(e), ["Guidance paused. Press volume up when you're ready."])
        XCTAssertTrue(e.contains(.chime(.done)))
        XCTAssertEqual(h.state.pause, .lost)
        XCTAssertEqual(h.state.step, .findAisle, "the pause is an overlay: the phase is kept")
        XCTAssertEqual(said(h.send(.signs([AisleSign(number: "4", words: ["Tahini"], clock: 12)]))), [], "paused until volume up")

        h.send(.talkPressed)
        h.send(.notUnderstood(noisy: false))
        XCTAssertNil(h.state.pause)
        XCTAssertEqual(h.state.step, .findAisle)
        XCTAssertFalse(said(h.advance(29)).contains(SessionPhrases.lostTrack), "the lost timer restarts")
    }

    func testGoalEvidenceKeepsTheLostTimerAway() {
        var h = SessionHarness()
        h.send(.routed(.unknownProduct("tahini", .unspecified)))
        h.advance(25)
        h.send(.signs([AisleSign(number: "4", words: ["Tahini"], clock: 12)]))
        XCTAssertFalse(said(h.advance(25)).contains(SessionPhrases.lostTrack))
    }
}
