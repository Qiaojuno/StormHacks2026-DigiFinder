// Main flow (§5.1–5.2): goal → signage → aisle → shelf → pointing → hold up → confirm → next / done.
import XCTest
@testable import DigiFinderCore

final class SessionMainFlowTests: XCTestCase {
    func testOneItemEndToEnd() {
        var h = SessionHarness()
        let coffee = SessionFixtures.coffee

        var e = h.startGoal(coffee)
        XCTAssertEqual(said(e), ["Looking for coffee."])
        XCTAssertTrue(e.contains(.setTarget(coffee, candidates: [], destination: nil)))
        XCTAssertEqual(works(e), [SessionFixtures.signageWork])
        XCTAssertEqual(h.state.step, .findingSignage)

        XCTAssertEqual(said(h.send(.signs([SessionFixtures.coffeeSign]))), ["9 o'clock, aisle 6, coffee and tea."])
        h.advance(3)
        XCTAssertEqual(said(h.send(.signs([SessionFixtures.coffeeSign]))), [], "the same direction isn't repeated")

        e = h.send(.arrivedAtAisle(clock: 9))
        XCTAssertEqual(said(e), ["Stop. Aisle 6 is at 9 o'clock.", "Turn to 9 o'clock."])
        XCTAssertEqual(h.state.step, .walkingAisle)

        e = h.send(.motion(yawDegrees: -90, steps: 0, walking: true))
        XCTAssertEqual(said(e, .guidance), ["This is the coffee aisle."])
        XCTAssertEqual(said(e, .narration), ["Walk through slowly."])

        e = h.send(.signs([SessionFixtures.shelfSign]))
        XCTAssertEqual(said(e), ["Coffee is at 9 o'clock. Turn to the shelf.", "Point at the shelf with one finger. Start at chest height."])
        XCTAssertEqual(works(e), [SessionFixtures.pointingWork], "shelf mode from \"Turn to the shelf\"")
        XCTAssertEqual(h.state.step, .pointing)

        e = h.send(.pointed(PointedProduct(text: "Pike Place", match: 0.5, directionToTarget: "right")))
        XCTAssertEqual(said(e), ["That's Pike Place. Move right."])
        XCTAssertEqual(said(h.send(.pointed(PointedProduct(text: "Pike Place", match: 0.5, directionToTarget: "left")))), [],
                       "at most one hand cue per second")
        h.advance(1)
        XCTAssertEqual(said(h.send(.pointed(PointedProduct(text: "Blonde", match: 0.3)))), ["Not it. Move slowly to the right."])

        e = h.send(.pointed(PointedProduct(text: "Starbucks Dark Roast", match: 0.95)))
        XCTAssertEqual(said(e), ["That's Starbucks Dark Roast. Grab it.", "Hold it up in front of you."])
        XCTAssertEqual(works(e), [SessionFixtures.holdUpWork])
        XCTAssertEqual(h.state.step, .holdUpToCheck)

        let info = SessionFixtures.darkRoastInfo
        e = h.send(.confirmed(info, isGoal: true))
        XCTAssertEqual(said(e), ["Got it: Starbucks Dark Roast. Put it in your cart.", "What's next?"])
        let chime = e.firstIndex(of: .chime(.done)), remember = e.firstIndex(of: .remember(info)), done = e.firstIndex(of: .markDone(coffee))
        XCTAssertNotNil(chime)
        XCTAssertLessThan(chime ?? 99, remember ?? -1)
        XCTAssertLessThan(remember ?? 99, done ?? -1)
        XCTAssertTrue(e.contains(.listen(maxSeconds: 5)))
        XCTAssertTrue(e.contains(.setTarget(nil, candidates: [], destination: nil)))
        XCTAssertEqual(h.state.foundCount, 1)
        XCTAssertEqual(h.state.step, .askingGoal)

        e = h.send(.notUnderstood(noisy: false))                   // silence after "What's next?"
        XCTAssertEqual(said(e), ["Shopping done. You found 1 item."])
        XCTAssertTrue(e.contains(.chime(.done)))
        XCTAssertEqual(h.state.step, .sessionDone)
    }

    func testQueuedGoalsRunInOrder() {
        var h = SessionHarness()
        let e = h.send(.routed(.products([SessionFixtures.coffee, SessionFixtures.milk])))
        XCTAssertEqual(said(e), ["I'll find coffee first, then milk."])
        XCTAssertEqual(h.state.queue, [SessionFixtures.milk])
        h.send(.signs([SessionFixtures.coffeeSign]), .arrivedAtAisle(clock: 9), .motion(yawDegrees: -90, steps: 0, walking: true),
               .signs([SessionFixtures.shelfSign]))
        h.grab()
        let done = h.send(.confirmed(SessionFixtures.darkRoastInfo, isGoal: true))
        XCTAssertEqual(said(done), ["Got it: Starbucks Dark Roast. Put it in your cart.", "Next: milk."])
        XCTAssertTrue(done.contains(.setTarget(SessionFixtures.milk, candidates: [], destination: nil)))
        XCTAssertEqual(works(done), [SessionFixtures.signageWork])
        XCTAssertEqual(h.state.step, .findingSignage)
        XCTAssertEqual(h.state.goal, SessionFixtures.milk)
    }

    func testNextItemInTheSameAisleGoesStraightToTheShelf() {
        var h = SessionHarness()
        h.send(.routed(.products([SessionFixtures.coffee, SessionFixtures.tea])))
        h.send(.signs([SessionFixtures.coffeeSign]), .arrivedAtAisle(clock: 9), .motion(yawDegrees: -90, steps: 0, walking: true),
               .signs([SessionFixtures.shelfSign]))
        h.grab()
        let e = h.send(.confirmed(SessionFixtures.darkRoastInfo, isGoal: true))
        XCTAssertEqual(said(e), ["Got it: Starbucks Dark Roast. Put it in your cart.", "Next: tea.", "Tea is in this aisle too."])
        XCTAssertEqual(h.state.step, .pointing)
        XCTAssertEqual(h.state.work?.shelfMode, true)
    }

    func testWrongItemGoesBackToPointing() {
        var h = SessionHarness()
        h.reachShelf(SessionFixtures.darkRoast)
        h.grab("Starbucks Dark Roast Ground")
        let wrong = ProductInfo(code: "2", name: "Dark Roast Ground", brand: "Starbucks")
        let e = h.send(.confirmed(wrong, isGoal: false))
        XCTAssertEqual(said(e), ["That's Starbucks Dark Roast Ground, not whole bean. Put it back and grab the right one."])
        XCTAssertEqual(h.state.step, .pointing)
        XCTAssertFalse(e.contains(.markDone(SessionFixtures.darkRoast)))
    }

    func testVariantHintAndUnclearHoldUpPrompts() {
        var h = SessionHarness()
        h.reachShelf()
        let e = h.send(.pointed(PointedProduct(text: "Dark Roast, 340 grams", match: 0.9, alternative: "There's also a 680 gram one.")))
        XCTAssertEqual(said(e).first, "This is Dark Roast, 340 grams. There's also a 680 gram one. Grab it.")
        XCTAssertEqual(said(h.send(.confirmed(nil, isGoal: false))), [])
        XCTAssertEqual(said(h.advance(4)), ["Turn it slowly."])
        XCTAssertEqual(said(h.advance(4)), ["Try holding it a little farther away."])
    }

    func testScanPromptThenOutOfViewShelfVote() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(h.advance(3)), ["I can't see any signs. Turn slowly."])
        XCTAssertEqual(said(h.advance(7)), ["Take two steps back.", "Face the shelf at 9 o'clock."])
        XCTAssertEqual(h.state.step, .shelfVote)
        XCTAssertEqual(said(h.advance(4)), ["Now face 3 o'clock."])
        let e = h.send(.aisleVerdict("coffee", evidence: ["coffee", "tea"]))
        XCTAssertEqual(said(e, .guidance), ["This is the coffee aisle."])
        XCTAssertEqual(said(e, .narration), ["I see coffee and tea on both sides."])
        XCTAssertEqual(h.state.step, .walkingAisle)
        XCTAssertEqual(said(h.advance(4)), ["Turn to the shelf.", "Point at the shelf with one finger. Start at chest height."])
        XCTAssertEqual(h.state.step, .pointing)
    }

    func testShelfVoteWithoutVerdictSendsUserToTheAisleEnd() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.advance(10)
        XCTAssertEqual(said(h.advance(8)), ["Now face 3 o'clock.", "Walk to the end of the aisle; the signs are usually there."])
        XCTAssertEqual(h.state.step, .findingSignage)
    }

    func testOtherSignsRememberedSignsAndVerdicts() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        let cereal = AisleSign(number: "3", words: ["Cereal"], clock: 12)
        XCTAssertEqual(said(h.send(.signs([cereal]))), ["Coffee isn't on these signs. Keep turning slowly."])
        XCTAssertEqual(said(h.send(.signs([AisleSign(number: "4", clock: 2)]))), [], "rate limited")
        h.advance(6)
        XCTAssertEqual(said(h.send(.signs([AisleSign(number: "4", clock: 2)]))), ["Aisle sign, 2 o'clock."])

        h.send(.signs([SessionFixtures.coffeeSign]))                  // at 9 o'clock while facing 0°
        h.send(.motion(yawDegrees: 90, steps: 0, walking: false))     // turned to face the other way
        h.advance(6)
        XCTAssertEqual(said(h.send(.signs([cereal]))), ["Coffee was aisle 6, at 6 o'clock behind you."])

        h.advance(11)                                                 // the sign no longer overrides the vote
        XCTAssertEqual(said(h.send(.aisleVerdict("tea", evidence: []))), ["This looks like tea. Coffee is usually nearby. Walk slowly ahead."])
        XCTAssertEqual(said(h.send(.aisleVerdict("pasta", evidence: []))), ["This looks like pasta, not coffee. Go back to the main aisle."])
    }

    func testReadableSignOverridesAConflictingVerdict() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.signs([SessionFixtures.coffeeSign]))
        XCTAssertEqual(said(h.send(.aisleVerdict("pasta", evidence: []))), [])
    }

    func testProduceByVisualClasses() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.bananas)
        let e = h.send(.aisleVerdict("produce", evidence: ["Banana", "Apple"]))
        XCTAssertEqual(said(e), ["This looks like produce: banana and apple ahead."])
    }

    func testBriefDropsCategoryNamesAndNarration() {
        var h = SessionHarness()
        h.send(.routed(.command(.lessDetail)))
        XCTAssertEqual(h.state.verbosity, .brief)
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(h.send(.signs([SessionFixtures.coffeeSign]))), ["9 o'clock, aisle 6."])
        h.send(.arrivedAtAisle(clock: 9))
        let e = h.send(.motion(yawDegrees: -90, steps: 0, walking: true))
        XCTAssertEqual(said(e), ["This is the coffee aisle."])
        XCTAssertEqual(said(e, .narration), [])
    }

    func testDetailedAddsAisleCategoriesAtArrival() {
        var h = SessionHarness()
        h.send(.routed(.command(.moreDetail)))
        h.startGoal(SessionFixtures.coffee)
        h.send(.signs([SessionFixtures.coffeeSign]))
        XCTAssertEqual(said(h.send(.arrivedAtAisle(clock: 9))).first, "Stop. Aisle 6 is at 9 o'clock, coffee and tea.")
    }

    func testTurnCueFallsBackToTimeWithoutMotion() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.signs([SessionFixtures.coffeeSign]), .arrivedAtAisle(clock: 9))
        XCTAssertEqual(said(h.advance(6), .guidance), ["This is the coffee aisle."])
    }
}
