// Every §5.12 ending: item done, session done, stop, not found, lost.
import XCTest
@testable import DigiFinderCore

final class SessionEndingTests: XCTestCase {
    func testItemDoneThenNext() {
        var h = SessionHarness()
        h.send(.routed(.products([SessionFixtures.coffee, SessionFixtures.milk])))
        h.send(.signs([SessionFixtures.coffeeSign]), .arrivedAtAisle(clock: 9), .motion(yawDegrees: -90, steps: 0, walking: true),
               .signs([SessionFixtures.shelfSign]))
        h.grab()
        let e = h.send(.confirmed(SessionFixtures.darkRoastInfo, isGoal: true))
        XCTAssertEqual(said(e), ["Got it: Starbucks Dark Roast. Put it in your cart.", "Next: milk."])
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
        XCTAssertEqual(h.state.step, .sessionDone)
        XCTAssertEqual(h.state.queue, [])
    }

    func testSessionDoneAfterWhatsNextSilenceAndRunnerFallback() {
        var h = SessionHarness()
        h.reachShelf()
        h.grab()
        h.send(.confirmed(SessionFixtures.darkRoastInfo, isGoal: true))
        XCTAssertEqual(said(h.advance(13)), ["Shopping done. You found 1 item."], "no answer at all")
        XCTAssertEqual(h.state.step, .sessionDone)
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
        h.send(.routed(.products([SessionFixtures.coffee, SessionFixtures.milk])))
        var e = h.send(.routed(.command(.stop)))
        XCTAssertEqual(said(e), ["Stopped.", "Next: milk."])
        XCTAssertTrue(e.contains(.chime(.done)))
        XCTAssertFalse(e.contains(.markDone(SessionFixtures.coffee)))
        XCTAssertEqual(h.state.goal, SessionFixtures.milk)

        e = h.send(.routed(.command(.stop)))
        XCTAssertEqual(said(e), ["Stopped.", "What's next?"])
        XCTAssertTrue(e.contains(.listen(maxSeconds: 5)))
        XCTAssertNil(h.state.goal)
    }

    func testNotFoundAfterNinetySecondsInTheAisle() {
        var h = SessionHarness()
        h.send(.routed(.products([SessionFixtures.coffee, SessionFixtures.milk])))
        h.send(.signs([SessionFixtures.coffeeSign]), .arrivedAtAisle(clock: 9), .motion(yawDegrees: -90, steps: 0, walking: true),
               .signs([SessionFixtures.shelfSign]))
        XCTAssertFalse(said(h.advance(89)).contains(SessionPhrases.notFound))
        let e = h.advance(1)
        XCTAssertEqual(said(e), ["I didn't find it. It may be out of stock. Say 'find staff' for help.", "Next: milk."])
        XCTAssertTrue(e.contains(.chime(.done)))
        XCTAssertEqual(h.state.goal, SessionFixtures.milk)
    }

    func testMatchesRestartTheNotFoundTimer() {
        var h = SessionHarness()
        h.reachShelf()
        h.advance(80)
        h.grab()
        h.send(.confirmed(ProductInfo(code: "2", name: "Blonde Roast"), isGoal: false))   // back to pointing
        XCTAssertFalse(said(h.advance(30)).contains(SessionPhrases.notFound))
    }

    func testNotFoundAfterWalkingTheAisleBothWays() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.signs([SessionFixtures.coffeeSign]), .arrivedAtAisle(clock: 9))
        h.send(.motion(yawDegrees: -90, steps: 0, walking: true))       // turned into the aisle
        h.send(.motion(yawDegrees: -90, steps: 12, walking: true))      // walked to the end
        XCTAssertEqual(said(h.send(.motion(yawDegrees: 90, steps: 13, walking: true))), [], "turned back")
        XCTAssertEqual(said(h.send(.motion(yawDegrees: 90, steps: 20, walking: true))), [])
        let e = h.send(.motion(yawDegrees: 90, steps: 26, walking: true))
        XCTAssertEqual(said(e), ["I didn't find it. It may be out of stock. Say 'find staff' for help.", "What's next?"])
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
        XCTAssertEqual(h.state.step, .paused)
        XCTAssertEqual(said(h.send(.signs([AisleSign(number: "4", words: ["Tahini"], clock: 12)]))), [], "paused until volume up")

        h.send(.talkPressed)
        h.send(.notUnderstood(noisy: false))
        XCTAssertEqual(h.state.step, .findingSignage)
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
