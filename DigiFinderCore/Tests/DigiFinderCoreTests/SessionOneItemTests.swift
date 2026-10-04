import XCTest
@testable import DigiFinderCore

/// Owner decision: one item at a time. A newly named item always replaces the current one; there is no list.
final class SessionOneItemTests: XCTestCase {
    func testEveryNewItemReplaces() {
        for change in [GoalChange.unspecified, .add, .replace] {
            var h = SessionHarness()
            h.startGoal(SessionFixtures.coffee)
            XCTAssertEqual(said(h.send(.routed(.product(SessionFixtures.milk, change)))), ["Okay, milk instead."])
            XCTAssertEqual(h.state.goal, SessionFixtures.milk)
            XCTAssertEqual(h.state.queue, [])
        }
    }

    func testSeveralItemsSearchesTheFirstOnly() {
        var h = SessionHarness()
        XCTAssertEqual(said(h.send(.routed(.products([SessionFixtures.coffee, SessionFixtures.milk], .unspecified)))),
                       ["Looking for coffee."])
        XCTAssertEqual(h.state.goal, SessionFixtures.coffee)
        XCTAssertEqual(h.state.queue, [])
    }
}
