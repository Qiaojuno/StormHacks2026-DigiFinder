// Items missing from the offline database: Open Food Facts online, word search offline (§5.2).
import XCTest
@testable import DigiFinderCore

final class SessionUnknownItemTests: XCTestCase {
    func testOnlineLookupFindsAnAisle() {
        var h = SessionHarness(online: true)
        let e = h.send(.routed(.unknownProduct("kicking horse", .unspecified)))
        XCTAssertEqual(said(e), ["I don't have kicking horse in my list. Checking online."])
        XCTAssertTrue(e.contains(.lookupProduct("kicking horse")))

        let found = Goal(brand: "Kicking Horse", product: "coffee", category: "coffee")
        let f = h.send(.productLookedUp(found))
        XCTAssertEqual(said(f), ["Found it: Kicking Horse coffee. Looking for the coffee aisle."])
        XCTAssertTrue(f.contains(.setTarget(found, candidates: [], destination: nil)))
        XCTAssertEqual(h.state.step, .findingSignage)
    }

    func testOnlineLookupWithoutAisleBecomesAWordSearchWithSignWords() {
        var h = SessionHarness(online: true)
        h.send(.routed(.unknownProduct("tahini", .unspecified)))
        let hit = Goal(product: "tahini", signWords: ["sesame pastes", "spreads"])
        XCTAssertEqual(said(h.send(.productLookedUp(hit))), ["I'll look for the word on signs and labels."])
        XCTAssertEqual(h.state.goal, hit)
        let sign = AisleSign(number: "4", words: ["Spreads", "Honey"], clock: 1)
        XCTAssertEqual(said(h.send(.signs([sign]))), ["1 o'clock, aisle 4, spreads and honey."])
    }

    func testNothingFoundOnlineIsAWordSearch() {
        var h = SessionHarness(online: true)
        h.send(.routed(.unknownProduct("tahini", .unspecified)))
        let e = h.send(.productLookedUp(nil))
        XCTAssertEqual(said(e), ["I'll look for the word on signs and labels."])
        XCTAssertTrue(e.contains(.setTarget(Goal(product: "tahini"), candidates: [], destination: nil)))
    }

    func testLookupTimeoutIsAWordSearch() {
        var h = SessionHarness(online: true)
        h.send(.routed(.unknownProduct("tahini", .unspecified)))
        XCTAssertEqual(said(h.advance(8)), ["I'll look for the word on signs and labels."])
        XCTAssertEqual(h.state.goal, Goal(product: "tahini"))
        XCTAssertEqual(said(h.send(.productLookedUp(nil))), [], "late results are ignored")
    }

    func testOnlineLookupWhileFindingAsksSwitchOrAdd() {
        var h = SessionHarness(online: true)
        h.startGoal(SessionFixtures.coffee)
        h.send(.routed(.unknownProduct("kicking horse", .unspecified)))
        let found = Goal(brand: "Kicking Horse", product: "coffee", category: "coffee")
        XCTAssertEqual(said(h.send(.productLookedUp(found))), ["Found it: Kicking Horse coffee.", "Switch to Kicking Horse coffee, or add it?"])
        XCTAssertEqual(h.state.pendingChoice, found)
    }

    func testOfflineWordSearchEndToEnd() {
        var h = SessionHarness()
        let e = h.send(.routed(.unknownProduct("toothpaste", .unspecified)))
        XCTAssertEqual(said(e), ["I don't have toothpaste in my list. I'll look for the word on signs and labels."])
        let goal = Goal(product: "toothpaste")
        XCTAssertTrue(e.contains(.setTarget(goal, candidates: [], destination: nil)))
        XCTAssertFalse(e.contains(.lookupProduct("toothpaste")))
        XCTAssertEqual(h.state.step, .findingSignage)

        let sign = AisleSign(number: "12", words: ["Toothpaste", "Soap"], clock: 1)
        XCTAssertEqual(said(h.send(.signs([sign]))), ["1 o'clock, aisle 12, toothpaste and soap."])
        h.send(.arrivedAtAisle(clock: 3), .motion(yawDegrees: 90, steps: 0, walking: true))
        XCTAssertEqual(said(h.send(.signs([AisleSign(words: ["Toothpaste"], clock: 3)]))).first,
                       "Toothpaste is at 3 o'clock. Turn to the shelf.")
        h.grab("Colgate toothpaste")
        let label = ProductInfo(code: "", name: "toothpaste", brand: "Colgate")
        let done = h.send(.confirmed(label, isGoal: true))
        XCTAssertEqual(said(done).first, "This says Colgate toothpaste. Put it in your cart.")
        XCTAssertTrue(done.contains(.markDone(goal)))
    }

    func testOfflineAdditionOfAnUnknownItem() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        let e = h.send(.routed(.unknownProduct("batteries", .add)))
        XCTAssertEqual(said(e), ["I don't have batteries in my list. I'll look for the word on signs and labels.",
                                 "Added batteries to the list."])
        XCTAssertEqual(h.state.queue, [Goal(product: "batteries")])
    }
}
