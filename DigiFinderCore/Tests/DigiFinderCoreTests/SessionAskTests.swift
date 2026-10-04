// Questions: Ask online, refusal offline; "What's around?" (§5.9, §5.11).
import XCTest
@testable import DigiFinderCore

final class SessionAskTests: XCTestCase {
    func testOnlineQuestionAnsweredThenResumes() {
        var h = SessionHarness(online: true)
        h.reachShelf()
        h.grab()
        let e = h.send(.routed(.question("is this gluten free")))
        XCTAssertEqual(said(e), ["Checking."])
        XCTAssertTrue(e.contains(.ask("is this gluten free")))
        XCTAssertEqual(h.state.step, .asking)
        XCTAssertEqual(h.state.work, StreamWork(text: .off, yoloFPS: 10, shelfMode: true), "shelf mode stays on for the held item")

        let answer = "The label says gluten free. Check with staff to confirm."
        let a = h.send(.askAnswer(answer))
        XCTAssertEqual(said(a, .reply), [answer])
        XCTAssertEqual(a.firstIndex(of: .chime(.done)), 1, "answer, then chime")
        XCTAssertEqual(h.state.step, .holdUpToCheck)
        XCTAssertEqual(h.state.work, SessionFixtures.holdUpWork)
    }

    func testAskTimesOutAfterSixSeconds() {
        var h = SessionHarness(online: true)
        h.startGoal(SessionFixtures.coffee)
        h.send(.routed(.question("what does this sign say")))
        XCTAssertEqual(said(h.advance(5.5)), [])
        XCTAssertEqual(said(h.advance(0.5)), ["I couldn't get an answer. Try again later."])
        XCTAssertEqual(h.state.step, .findingSignage)
        XCTAssertEqual(said(h.send(.askAnswer("Late."))), [], "late answers are dropped")
    }

    func testFailedAskSaysNoAnswer() {
        var h = SessionHarness(online: true)
        h.startGoal(SessionFixtures.coffee)
        h.send(.routed(.question("how much is this")))
        XCTAssertEqual(said(h.send(.askAnswer(nil))), ["I couldn't get an answer. Try again later."])
    }

    func testOfflineQuestionIsRefused() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        let e = h.send(.routed(.question("is this gluten free")))
        XCTAssertEqual(said(e), ["I can't answer that offline. I can still find products, checkout, or staff."])
        XCTAssertFalse(e.contains(.ask("is this gluten free")))
        XCTAssertEqual(h.state.step, .findingSignage)
    }

    func testGuidanceWaitsDuringAskAndArrivalReplaysAfter() {
        var h = SessionHarness(online: true)
        h.startGoal(SessionFixtures.coffee)
        h.send(.routed(.question("what does this sign say")))
        XCTAssertEqual(said(h.send(.signs([SessionFixtures.coffeeSign]))), [])
        XCTAssertEqual(said(h.send(.arrivedAtAisle(clock: 9))), [])
        let a = h.send(.askAnswer("It says coffee and tea."))
        XCTAssertEqual(said(a), ["It says coffee and tea.", "Stop. Aisle 6 is at 9 o'clock.", "Turn to 9 o'clock."])
        XCTAssertEqual(h.state.step, .walkingAisle)
    }

    func testTalkingDuringAskReplacesTheQuestion() {
        var h = SessionHarness(online: true)
        h.startGoal(SessionFixtures.coffee)
        h.send(.routed(.question("what does this sign say")))
        h.send(.talkPressed)
        XCTAssertEqual(h.state.step, .findingSignage)
        XCTAssertEqual(said(h.send(.askAnswer("Too late."))), [])
    }

    func testWhatsAroundAnswersThenReturnsToTheStep() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        let e = h.send(.routed(.command(.whatsAround)))
        XCTAssertTrue(e.contains(.describeSurroundings))
        let answer = "Checkout sign at 2 o'clock. Two people ahead. Shelves on both sides."
        XCTAssertEqual(said(h.send(.surroundings(answer)), .reply), [answer])
        XCTAssertEqual(h.state.step, .findingSignage)
        XCTAssertEqual(said(h.send(.surroundings("Again."))), [], "only answers a request")
    }
}
