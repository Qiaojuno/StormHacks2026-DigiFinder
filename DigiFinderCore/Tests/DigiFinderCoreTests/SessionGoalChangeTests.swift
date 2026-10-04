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

    func testAlsoAddsToTheList() {
        var h = SessionHarness()
        h.startGoal(coffee)
        XCTAssertEqual(said(h.send(.routed(.product(milk, .add)))), ["Added milk to the list."])
        XCTAssertEqual(h.state.goal, coffee)
        XCTAssertEqual(h.state.queue, [milk])
    }

    func testChangeWordsWithNoActiveGoalJustStart() {
        var h = SessionHarness()
        XCTAssertEqual(said(h.send(.routed(.product(milk, .add)))), ["Looking for milk."])
        XCTAssertEqual(h.state.goal, milk)
    }

    func testBareProductWhileFindingAsksSwitchOrAdd() {
        var h = SessionHarness()
        h.startGoal(coffee)
        let e = h.send(.routed(.product(milk, .unspecified)))
        XCTAssertEqual(said(e), ["Switch to milk, or add it?"])
        XCTAssertTrue(e.contains(.listen(maxSeconds: 5)))
        XCTAssertEqual(h.state.pendingChoice, milk)
        XCTAssertTrue(h.state.isListening)

        let sw = h.send(.routed(.command(.switchGoal)))
        XCTAssertEqual(said(sw), ["Okay, milk instead."])
        XCTAssertEqual(h.state.goal, milk)
        XCTAssertEqual(h.state.queue, [])
        XCTAssertNil(h.state.pendingChoice)
    }

    func testAddItAnswerQueues() {
        var h = SessionHarness()
        h.startGoal(coffee)
        h.send(.routed(.product(milk, .unspecified)))
        XCTAssertEqual(said(h.send(.routed(.command(.addGoal)))), ["Added milk to the list."])
        XCTAssertEqual(h.state.goal, coffee)
        XCTAssertEqual(h.state.queue, [milk])
    }

    func testNoClearAnswerAddsIt() {
        var h = SessionHarness()
        h.startGoal(coffee)
        h.send(.routed(.product(milk, .unspecified)))
        XCTAssertEqual(said(h.send(.notUnderstood(noisy: false))), ["I'll add milk to the list."])
        XCTAssertEqual(h.state.queue, [milk])
        XCTAssertEqual(h.state.goal, coffee)
    }

    func testAnotherRequestAddsThePendingItemThenRuns() {
        var h = SessionHarness()
        h.startGoal(coffee)
        h.send(.routed(.product(milk, .unspecified)))
        let e = h.send(.routed(.command(.repeatLast)))
        XCTAssertEqual(said(e).first, "I'll add milk to the list.")
        XCTAssertEqual(h.state.queue, [milk])
    }

    func testSilentRunnerFallsBackToAdding() {
        var h = SessionHarness()
        h.startGoal(coffee)
        h.send(.routed(.product(milk, .unspecified)))
        XCTAssertEqual(said(h.advance(13)), ["I'll add milk to the list."])
        XCTAssertEqual(h.state.queue, [milk])
    }

    func testNeverMindKeepsTheCurrentGoal() {
        var h = SessionHarness()
        h.startGoal(coffee)
        h.send(.routed(.product(milk, .unspecified)))
        XCTAssertEqual(said(h.send(.routed(.command(.stop)))), ["Okay, still looking for coffee."])
        XCTAssertEqual(h.state.goal, coffee)
        XCTAssertEqual(h.state.queue, [])
    }

    func testMultipleProducts() {
        var h = SessionHarness()
        XCTAssertEqual(said(h.send(.routed(.products([coffee, milk, SessionFixtures.tea])))), ["I'll find coffee first, then milk, then tea."])
        XCTAssertEqual(h.state.goal, coffee)
        XCTAssertEqual(h.state.queue, [milk, SessionFixtures.tea])

        var busy = SessionHarness()
        busy.startGoal(coffee)
        XCTAssertEqual(said(busy.send(.routed(.products([milk, SessionFixtures.tea])))), ["Added milk and tea to the list."])
        XCTAssertEqual(busy.state.queue, [milk, SessionFixtures.tea])
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
        XCTAssertEqual(said(e), ["Added milk to the list.", "Stop. Aisle 6 is at 9 o'clock.", "Turn to 9 o'clock."])
        XCTAssertEqual(h.state.step, .walkingAisle)
    }

    func testHeldArrivalIsDroppedWhenTheGoalChanges() {
        var h = SessionHarness()
        h.startGoal(coffee)
        h.send(.talkPressed, .arrivedAtAisle(clock: 9))
        let e = h.send(.routed(.product(SessionFixtures.peanutButter, .replace)))
        XCTAssertEqual(said(e), ["Okay, peanut butter instead."])
        XCTAssertEqual(h.state.step, .findingSignage)
    }
}
