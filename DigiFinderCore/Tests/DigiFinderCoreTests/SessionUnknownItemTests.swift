// Items missing from the offline database: Gemini (then Open Food Facts) online, word search offline (§5.2).
import XCTest
@testable import DigiFinderCore

final class SessionUnknownItemTests: XCTestCase {
    /// Online: Gemini first, silently; no item back → Open Food Facts.
    private func lookUp(_ words: String, _ h: inout SessionHarness) {
        h.send(.routed(.unknownProduct(words, .unspecified)))
        h.send(.assistAnswer(say: "I'm not sure what that is.", find: nil))
    }

    func testOnlineUnknownItemGoesToGeminiSilently() {
        var h = SessionHarness(online: true)
        let e = h.send(.routed(.unknownProduct("kicking horse", .unspecified)))
        XCTAssertEqual(said(e), [], "no \"Checking online.\"")
        XCTAssertTrue(e.contains(.assist("kicking horse", context: AssistContext(store: true, goal: nil, phase: .idle,
                                                                                  kind: .unknownItem))))
        let found = Goal(brand: "Kicking Horse", product: "coffee", category: "coffee")
        let a = h.send(.assistAnswer(say: "Kicking Horse is a coffee brand.", find: found))
        XCTAssertEqual(said(a), ["Kicking Horse is a coffee brand."], "only Gemini's line is spoken")
        XCTAssertTrue(a.contains(.setTarget(found, candidates: [], destination: nil)))
        XCTAssertEqual(h.state.step, .findAisle)
    }

    func testGeminiTimeoutFallsBackToTheOfflineWordSearch() {
        var h = SessionHarness(online: true)
        h.send(.routed(.unknownProduct("tahini", .unspecified)))
        XCTAssertEqual(said(h.advance(7.5)), [])
        XCTAssertEqual(said(h.advance(0.5)), ["I don't have tahini in my list. I'll look for the word on signs and labels."])
        XCTAssertEqual(h.state.goal, Goal(product: "tahini"))
        XCTAssertEqual(said(h.send(.assistAnswer(say: "Late.", find: nil))), [], "late answers are dropped")
    }

    func testOpenFoodFactsFindsAnAisle() {
        var h = SessionHarness(online: true)
        h.send(.routed(.unknownProduct("kicking horse", .unspecified)))
        let e = h.send(.assistAnswer(say: "I'm not sure what that is.", find: nil))
        XCTAssertTrue(e.contains(.lookupProduct("kicking horse")))
        let found = Goal(brand: "Kicking Horse", product: "coffee", category: "coffee")
        let f = h.send(.productLookedUp(found))
        XCTAssertEqual(said(f), ["Found it: Kicking Horse coffee. Looking for the coffee aisle."])
        XCTAssertTrue(f.contains(.setTarget(found, candidates: [], destination: nil)))
        XCTAssertEqual(h.state.step, .findAisle)
    }

    func testOnlineLookupWithoutAisleBecomesAWordSearchWithSignWords() {
        var h = SessionHarness(online: true)
        lookUp("tahini", &h)
        let hit = Goal(product: "tahini", signWords: ["sesame pastes", "spreads"])
        XCTAssertEqual(said(h.send(.productLookedUp(hit))), ["I'll look for the word on signs and labels."])
        XCTAssertEqual(h.state.goal, hit)
        let sign = AisleSign(number: "4", words: ["Spreads", "Honey"], clock: 1)
        XCTAssertEqual(said(h.send(.signs([sign]))), ["1 o'clock, aisle 4, spreads and honey."])
    }

    func testNothingFoundOnlineIsAWordSearch() {
        var h = SessionHarness(online: true)
        lookUp("tahini", &h)
        let e = h.send(.productLookedUp(nil))
        XCTAssertEqual(said(e), ["I'll look for the word on signs and labels."])
        XCTAssertTrue(e.contains(.setTarget(Goal(product: "tahini"), candidates: [], destination: nil)))
    }

    func testLookupTimeoutIsAWordSearch() {
        var h = SessionHarness(online: true)
        lookUp("tahini", &h)
        XCTAssertEqual(said(h.advance(8)), ["I'll look for the word on signs and labels."])
        XCTAssertEqual(h.state.goal, Goal(product: "tahini"))
        XCTAssertEqual(said(h.send(.productLookedUp(nil))), [], "late results are ignored")
    }


    func testOfflineWordSearchEndToEnd() {
        var h = SessionHarness()
        let e = h.send(.routed(.unknownProduct("toothpaste", .unspecified)))
        XCTAssertEqual(said(e), ["I don't have toothpaste in my list. I'll look for the word on signs and labels."])
        let goal = Goal(product: "toothpaste")
        XCTAssertTrue(e.contains(.setTarget(goal, candidates: [], destination: nil)))
        XCTAssertFalse(e.contains(.lookupProduct("toothpaste")))
        XCTAssertEqual(h.state.step, .findAisle)

        let sign = AisleSign(number: "12", words: ["Toothpaste", "Soap"], clock: 1)
        XCTAssertEqual(said(h.send(.signs([sign]))), ["1 o'clock, aisle 12, toothpaste and soap."])
        h.send(.arrivedAtAisle(clock: 3), .motion(yawDegrees: 90, steps: 0, walking: true))
        XCTAssertEqual(h.state.step, .inAisle)
        XCTAssertEqual(said(h.send(.signs([AisleSign(words: ["Toothpaste"], clock: 3)]))),
                       ["Stop here. Turn to the shelf at 3 o'clock."])
        h.send(.motion(yawDegrees: 90, steps: 3, walking: false))
        XCTAssertEqual(h.state.step, .pick)
        h.grab("Colgate toothpaste")
        let label = ProductInfo(code: "", name: "toothpaste", brand: "Colgate")
        let done = h.send(.confirmed(label, isGoal: true))
        XCTAssertEqual(said(done).first, "This says Colgate toothpaste. Put it in your cart.")
        XCTAssertTrue(done.contains(.markDone(goal)))
    }

}
