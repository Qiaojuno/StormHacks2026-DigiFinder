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
        XCTAssertEqual(said(e), ["Got it: Starbucks Dark Roast.", "Volume up for another item."], "one item at a time")
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

    /// Owner decision: after an item (found or not) there's no "What's next?" and no follow-up line; the stream stays on.
    func testNoFollowUpAfterAnItem() {
        var h = SessionHarness()
        h.reachShelf()
        h.grab()
        let e = h.send(.confirmed(SessionFixtures.darkRoastInfo, isGoal: true))
        XCTAssertFalse(said(e).contains("What's next?"))
        XCTAssertFalse(e.contains(.listen))
        XCTAssertFalse(e.contains(.setStreaming(false)))
        XCTAssertEqual(said(h.advance(30)), [], "nothing more until volume up")
        XCTAssertEqual(h.state.step, .idle)
        XCTAssertTrue(h.state.streaming)
    }

    func testStopCancelsTheGoalThenNextOrWhatsNext() {
        var h = SessionHarness()
        h.send(.routed(.product(SessionFixtures.coffee, .unspecified)))
        let e = h.send(.routed(.command(.stop)))
        XCTAssertEqual(said(e), ["Stopped.", "Volume up for another item."])
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
        XCTAssertEqual(said(e), ["I couldn't find it.", "Volume up for another item."])
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
        XCTAssertEqual(said(h.advance(0.5)), ["Lost track. Walk slowly ahead."])
        XCTAssertFalse(said(h.advance(59.5)).contains(SessionPhrases.guidancePaused))
        let e = h.advance(0.5)
        XCTAssertEqual(said(e), ["Paused. Volume up when ready."])
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

/// Owner decision: obstacle detection (YOLO) runs whenever the stream is on, with or without a search.
final class DetectionAlwaysOnTests: XCTestCase {
    func testYOLORunsInEveryPhaseWhileStreaming() {
        var h = SessionHarness()
        XCTAssertGreaterThan(h.session.currentWork().yoloFPS, 0, "idle, no search")
        h.reachShelf()
        XCTAssertGreaterThan(h.session.currentWork().yoloFPS, 0, "pick")
        h.grab()
        XCTAssertGreaterThan(h.session.currentWork().yoloFPS, 0, "confirm")
        h.send(.confirmed(SessionFixtures.darkRoastInfo, isGoal: true))
        XCTAssertGreaterThan(h.session.currentWork().yoloFPS, 0, "after the item: idle again")
        XCTAssertTrue(h.state.streaming, "the stream stays on after an item")
    }
}
