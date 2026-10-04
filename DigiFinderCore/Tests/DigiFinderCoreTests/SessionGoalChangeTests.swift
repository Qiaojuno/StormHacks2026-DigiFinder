// Change of mind, additions, switch-or-add, multiple products (§5.2, §5.10).
import XCTest
@testable import DigiFinderCore

final class SessionGoalChangeTests: XCTestCase {
    let coffee = SessionFixtures.coffee, milk = SessionFixtures.milk

    func testActuallyReplacesTheGoal() {
        var h = SessionHarness()
        h.startGoal(coffee)
        let e = h.send(.routed(.product(SessionFixtures.peanutButter, .replace)))
        XCTAssertEqual(said(e), ["Okay, peanut butter instead."])
        XCTAssertTrue(e.contains(.setTarget(SessionFixtures.peanutButter, candidates: [], destination: nil)))
        XCTAssertEqual(h.state.goal, SessionFixtures.peanutButter)
        XCTAssertEqual(h.state.queue, [])
    }


    func testChangeWordsWithNoActiveGoalJustStart() {
        var h = SessionHarness()
        XCTAssertEqual(said(h.send(.routed(.product(milk, .add)))), ["Looking for milk."])
        XCTAssertEqual(h.state.goal, milk)
    }


    func testActuallyStillReplaces() {
        var h = SessionHarness()
        h.startGoal(coffee)
        XCTAssertEqual(said(h.send(.routed(.product(milk, .replace)))), ["Okay, milk instead."])
        XCTAssertEqual(h.state.goal, milk)
    }


    func testAskingForTheCurrentGoalAgainDoesntQueueIt() {
        var h = SessionHarness()
        h.startGoal(coffee)
        XCTAssertEqual(said(h.startGoal(coffee)), ["Looking for coffee."])
        XCTAssertEqual(h.state.queue, [])
        XCTAssertNil(h.state.pendingChoice)
    }

    func testEventsWhileTalkingWaitForTheRecording() {
        var h = SessionHarness()
        h.startGoal(coffee)
        h.send(.signs([SessionFixtures.coffeeSign]))
        h.send(.talkPressed)
        XCTAssertEqual(said(h.send(.arrivedAtAisle(clock: 9))), [], "guidance is held while recording")
        let e = h.send(.routed(.product(milk, .add)))
        XCTAssertEqual(said(e), ["Okay, milk instead."], "a new item replaces; the held coffee arrival is dropped")
        XCTAssertEqual(h.state.goal, milk)
    }

    func testHeldArrivalIsDroppedWhenTheGoalChanges() {
        var h = SessionHarness()
        h.startGoal(coffee)
        h.send(.talkPressed, .arrivedAtAisle(clock: 9))
        let e = h.send(.routed(.product(SessionFixtures.peanutButter, .replace)))
        XCTAssertEqual(said(e), ["Okay, peanut butter instead."])
        XCTAssertEqual(h.state.step, .findAisle)
    }

}
