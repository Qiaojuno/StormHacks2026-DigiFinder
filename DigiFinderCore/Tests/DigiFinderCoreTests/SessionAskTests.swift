// Anything unusual the user says goes to Gemini silently when online; offline paths; "What's around?" (§5.9, §5.11).
import XCTest
@testable import DigiFinderCore

private func isAssist(_ e: Effect) -> Bool { if case .assist = e { return true } else { return false } }

final class SessionAskTests: XCTestCase {
    func testOnlineQuestionAnsweredSilentlyThenResumes() {
        var h = SessionHarness(online: true)
        h.reachShelf()
        h.grab()
        let e = h.send(.routed(.question("is this gluten free")))
        XCTAssertEqual(said(e), [], "no \"Checking.\"")
        XCTAssertTrue(e.contains(.assist("is this gluten free",
                                         context: AssistContext(store: true, goal: "coffee", phase: .confirm, kind: .question))))
        XCTAssertTrue(h.state.askPending)
        XCTAssertEqual(h.state.step, .confirm, "Ask pending is an overlay: the phase is kept")
        XCTAssertEqual(h.state.work, StreamWork(text: .off, yoloFPS: 10))

        let answer = "The label says gluten free. Check with staff to confirm."
        let a = h.send(.assistAnswer(say: answer, find: nil))
        XCTAssertEqual(said(a, .reply), ["The label says gluten free. Check with staff."], "cut to 8 words")
        XCTAssertFalse(h.state.askPending)
        XCTAssertEqual(h.state.step, .confirm)
        XCTAssertEqual(h.state.work, SessionFixtures.holdUpWork)
    }

    func testGeminiCanStartASearch() {
        var h = SessionHarness(online: true)
        let e = h.send(.unmatched("could you help me find my car keys", noisy: false))
        XCTAssertEqual(said(e), [])
        XCTAssertTrue(e.contains(.assist("could you help me find my car keys",
                                         context: AssistContext(store: true, phase: .idle, kind: .unmatched))))
        let keys = Goal(product: "car keys")
        let a = h.send(.assistAnswer(say: "Okay, I'll look for your car keys.", find: keys))
        XCTAssertEqual(said(a), ["Okay, I'll look for your car keys."])
        XCTAssertEqual(h.state.goal, keys)
        XCTAssertEqual(h.state.step, .findAisle)
    }

    func testAssistTimesOutToTheOfflinePathSilently() {
        var h = SessionHarness(online: true)
        h.startGoal(SessionFixtures.coffee)
        h.send(.routed(.question("what does this sign say")))
        XCTAssertEqual(said(h.advance(7.5)), [])
        XCTAssertEqual(said(h.advance(0.5)), ["Can't answer that offline."])
        XCTAssertEqual(h.state.step, .findAisle)
        XCTAssertFalse(h.state.askPending)
        XCTAssertEqual(said(h.send(.assistAnswer(say: "Late.", find: nil))), [], "late answers are dropped")
    }

    func testFailedAssistTakesTheOfflinePath() {
        var h = SessionHarness(online: true)
        h.startGoal(SessionFixtures.coffee)
        h.send(.routed(.question("how much is this")))
        XCTAssertEqual(said(h.send(.assistAnswer(say: nil, find: nil))),
                       ["Can't answer that offline."])
        h.send(.unmatched("blorp", noisy: false))
        XCTAssertEqual(said(h.send(.assistAnswer(say: nil, find: nil))), ["I didn't catch that. Say the product name."])
    }

    func testOfflineQuestionAndUnmatchedWords() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        let e = h.send(.routed(.question("is this gluten free")))
        XCTAssertEqual(said(e), ["Can't answer that offline."])
        XCTAssertFalse(e.contains(where: isAssist))
        XCTAssertEqual(h.state.step, .findAisle)
        XCTAssertEqual(said(h.send(.unmatched("blorp", noisy: false))), ["I didn't catch that. Say the product name."])
        XCTAssertEqual(said(h.send(.unmatched("blorp", noisy: true))), ["Didn't catch that. Too noisy."])
    }

    func testGuidanceWaitsDuringAskAndArrivalReplaysAfter() {
        var h = SessionHarness(online: true)
        h.startGoal(SessionFixtures.coffee)
        h.send(.routed(.question("what does this sign say")))
        XCTAssertEqual(said(h.send(.signs([SessionFixtures.coffeeSign]))), [])
        XCTAssertEqual(said(h.send(.arrivedAtAisle(clock: 9))), [])
        let a = h.send(.assistAnswer(say: "It says coffee and tea.", find: nil))
        XCTAssertEqual(said(a), ["It says coffee and tea.", "Stop. Aisle 6, 9 o'clock."])
        XCTAssertEqual(h.state.step, .findAisle)
    }

    /// Owner spec: Ask pending mid-InAisle returns to InAisle; danger is still handled during it.
    func testAskPendingInTheAisleKeepsThePhaseAndDanger() {
        var h = SessionHarness(online: true)
        h.enterAisle()
        h.send(.routed(.question("what's on this shelf")))
        XCTAssertEqual(h.state.step, .inAisle)
        XCTAssertEqual(h.send(.danger(cutRecording: false)), [], "the safety lane already alerted; nothing gates it")
        XCTAssertNotNil(h.state.dangerSince)
        h.send(.motion(yawDegrees: -90, steps: 4, walking: false))
        XCTAssertFalse(h.state.isWalking, "motion keeps running during Ask")
        h.send(.talkPressed)
        XCTAssertEqual(h.send(.danger(cutRecording: true)), [.say("Say that again.", .reply)], "a danger cut still works")
        h.send(.dangerCleared)
        h.send(.routed(.question("what's on this shelf")))
        h.send(.assistAnswer(say: "Coffee and tea.", find: nil))
        XCTAssertEqual(h.state.step, .inAisle)
        XCTAssertFalse(h.state.askPending)
    }

    func testTalkingDuringAskReplacesTheQuestion() {
        var h = SessionHarness(online: true)
        h.startGoal(SessionFixtures.coffee)
        h.send(.routed(.question("what does this sign say")))
        h.send(.talkPressed)
        XCTAssertFalse(h.state.askPending)
        XCTAssertEqual(h.state.step, .findAisle)
        XCTAssertEqual(said(h.send(.assistAnswer(say: "Too late.", find: nil))), [])
    }

    func testWhatsAroundAnswersThenReturnsToThePhase() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        let e = h.send(.routed(.command(.whatsAround)))
        XCTAssertTrue(e.contains(.describeSurroundings))
        let answer = "Checkout sign at 2 o'clock. Two people ahead. Shelves on both sides."
        XCTAssertEqual(said(h.send(.surroundings(answer)), .reply), [answer])
        XCTAssertEqual(h.state.step, .findAisle)
        XCTAssertEqual(said(h.send(.surroundings("Again."))), [], "only answers a request")
    }
}
