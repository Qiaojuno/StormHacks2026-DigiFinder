// Main flow (§5.1–5.2): Idle → FindAisle → InAisle → Pick → Confirm → next / Idle.
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
        XCTAssertEqual(h.state.step, .findAisle)

        XCTAssertEqual(said(h.send(.signs([SessionFixtures.coffeeSign]))), ["9 o'clock, aisle 6, coffee and tea."])
        h.advance(3)
        XCTAssertEqual(said(h.send(.signs([SessionFixtures.coffeeSign]))), [], "the same direction isn't repeated")

        e = h.send(.arrivedAtAisle(clock: 9))
        XCTAssertEqual(said(e), ["Stop. Aisle 6 is at 9 o'clock."])
        XCTAssertEqual(h.state.step, .findAisle, "InAisle only once the user walks into it")

        e = h.send(.motion(yawDegrees: -90, steps: 0, walking: true))
        XCTAssertEqual(said(e, .guidance), ["This is the coffee aisle."])
        XCTAssertEqual(said(e, .narration), ["Walk through slowly."])
        XCTAssertEqual(h.state.step, .inAisle)

        e = h.send(.signs([SessionFixtures.shelfSign]))
        XCTAssertEqual(said(e), ["Stop here. Turn to the shelf at 9 o'clock."])
        XCTAssertEqual(h.state.step, .inAisle, "Pick waits for Standing")
        XCTAssertEqual(works(e), [])

        e = h.send(.motion(yawDegrees: -90, steps: 2, walking: false))
        XCTAssertEqual(said(e), ["Point at the shelf with one finger. Start at chest height."])
        XCTAssertEqual(works(e), [SessionFixtures.pointingWork])
        XCTAssertEqual(h.state.step, .pick)

        e = h.send(.pointed(PointedProduct(text: "Pike Place", match: 0.5, directionToTarget: "right")))
        XCTAssertEqual(said(e), ["That's Pike Place. Move right."])
        XCTAssertEqual(said(h.send(.pointed(PointedProduct(text: "Pike Place", match: 0.5, directionToTarget: "left")))), [],
                       "at most one hand cue per second")
        h.advance(1)
        XCTAssertEqual(said(h.send(.pointed(PointedProduct(text: "Blonde", match: 0.3)))), ["Not it. Move slowly to the right."])
        h.advance(4)
        XCTAssertEqual(said(h.send(.pointed(PointedProduct(text: "Dark Roast", match: 0.85)))), ["Not it. Move slowly to the right."],
                       "below 0.9 is not the goal")

        e = h.send(.pointed(PointedProduct(text: "Starbucks Dark Roast", match: 0.95)))
        XCTAssertEqual(said(e), ["That's Starbucks Dark Roast. Grab it.", "Hold it up in front of you."])
        XCTAssertEqual(works(e), [SessionFixtures.holdUpWork])
        XCTAssertEqual(h.state.step, .confirm)

        let info = SessionFixtures.darkRoastInfo
        e = h.send(.confirmed(info, isGoal: true))
        XCTAssertEqual(said(e), ["Got it: Starbucks Dark Roast. Put it in your cart.", "What's next?"])
        let chime = e.firstIndex(of: .chime(.done)), remember = e.firstIndex(of: .remember(info)), done = e.firstIndex(of: .markDone(coffee))
        XCTAssertNotNil(chime)
        XCTAssertLessThan(chime ?? 99, remember ?? -1)
        XCTAssertLessThan(remember ?? 99, done ?? -1)
        XCTAssertFalse(e.contains(.listen), "no auto-listen: the user presses volume up to answer")
        XCTAssertTrue(e.contains(.setTarget(nil, candidates: [], destination: nil)))
        XCTAssertEqual(h.state.foundCount, 1)
        XCTAssertEqual(h.state.step, .idle)

        e = h.send(.talkPressed, .notUnderstood(noisy: false))       // nothing said after "What's next?"
        XCTAssertEqual(said(e), ["Shopping done. You found 1 item."])
        XCTAssertTrue(e.contains(.chime(.done)))
        XCTAssertEqual(h.state.step, .idle)
        XCTAssertTrue(h.state.finished)
    }

    func testWhatsNextSilenceFinishesAfterItsTimeout() {
        var h = SessionHarness()
        h.reachShelf()
        h.grab()
        h.send(.confirmed(SessionFixtures.darkRoastInfo, isGoal: true))
        XCTAssertEqual(said(h.advance(11.5)), [])
        XCTAssertEqual(said(h.advance(0.5)), ["Shopping done. You found 1 item."])
    }



    func testWrongItemGoesBackToPick() {
        var h = SessionHarness()
        h.reachShelf(SessionFixtures.darkRoast)
        h.grab("Starbucks Dark Roast Ground")
        let wrong = ProductInfo(code: "2", name: "Dark Roast Ground", brand: "Starbucks")
        let e = h.send(.confirmed(wrong, isGoal: false))
        XCTAssertEqual(said(e), ["That's ground, not whole bean. Put it back."])
        XCTAssertEqual(h.state.step, .pick)
        XCTAssertFalse(e.contains(.markDone(SessionFixtures.darkRoast)))
        XCTAssertFalse(e.contains(.chime(.done)))
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

    func testScanPromptThenShelfVoteOnceStanding() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.motion(yawDegrees: 0, steps: 0, walking: false))
        XCTAssertEqual(said(h.advance(3)), ["I can't see any signs. Turn slowly."])
        XCTAssertEqual(said(h.advance(7)), ["Take two steps back."])
        XCTAssertNotNil(h.state.vote)
        XCTAssertEqual(h.state.step, .findAisle, "the vote is a sub-state of FindAisle")
        XCTAssertEqual(said(h.advance(3)), [], "waits for the user to step back")
        XCTAssertEqual(said(h.send(.motion(yawDegrees: 0, steps: 2, walking: true))), [])
        XCTAssertEqual(said(h.send(.motion(yawDegrees: 0, steps: 2, walking: false))), ["Face the shelf at 9 o'clock."])
        h.send(.motion(yawDegrees: -90, steps: 2, walking: false))
        XCTAssertEqual(said(h.advance(4)), ["Now face 3 o'clock."])
        let e = h.send(.aisleVerdict("coffee", evidence: ["coffee", "tea"]))
        XCTAssertEqual(said(e, .guidance), ["This is the coffee aisle."])
        XCTAssertEqual(said(e, .narration), ["I see coffee and tea on both sides.", "Walk through slowly."])
        XCTAssertEqual(h.state.step, .inAisle)
        XCTAssertEqual(said(h.advance(10)), [], "no timer sends the user to the shelf")
        XCTAssertEqual(h.state.step, .inAisle)
    }

    func testAnySignResetsTheNoSignWait() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.advance(8)
        h.send(.signs([AisleSign(number: "3", words: ["Cereal"], clock: 12)]))
        XCTAssertFalse(said(h.advance(8)).contains("Take two steps back."))
        XCTAssertTrue(said(h.advance(2.5)).contains("Take two steps back."))
    }

    func testShelfVoteWithoutVerdictSendsUserToTheAisleEnd() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(h.advance(10)).last, "Take two steps back.")
        XCTAssertEqual(said(h.advance(0.5)), ["Face the shelf at 9 o'clock."], "no motion data: at once")
        XCTAssertEqual(said(h.advance(4)), ["Now face 3 o'clock."])
        XCTAssertEqual(said(h.advance(4)), ["Walk to the end of the aisle; the signs are usually there."])
        XCTAssertNil(h.state.vote)
        XCTAssertEqual(h.state.step, .findAisle)
    }

    func testTargetSignEndsTheVote() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.advance(10.5)
        XCTAssertNotNil(h.state.vote)
        XCTAssertEqual(said(h.send(.signs([SessionFixtures.coffeeSign]))), ["9 o'clock, aisle 6, coffee and tea."])
        XCTAssertNil(h.state.vote)
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
        XCTAssertEqual(said(e, .guidance), ["This looks like produce: banana and apple ahead."])
        XCTAssertEqual(h.state.step, .inAisle)
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

    /// No timer turns the user into the aisle: only walking toward its bearing (or the vote) does.
    func testEnteringTheAisleNeedsWalkingTowardIt() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.signs([SessionFixtures.coffeeSign]), .arrivedAtAisle(clock: 9))
        XCTAssertFalse(said(h.advance(10)).contains("This is the coffee aisle."))
        XCTAssertEqual(h.state.step, .findAisle)
        XCTAssertEqual(said(h.send(.motion(yawDegrees: -60, steps: 0, walking: false))), [], "standing: not yet")
        XCTAssertEqual(said(h.send(.motion(yawDegrees: 60, steps: 1, walking: true))), [], "walking the other way")
        XCTAssertEqual(said(h.send(.motion(yawDegrees: -60, steps: 2, walking: true)), .guidance), ["This is the coffee aisle."])
        XCTAssertEqual(h.state.step, .inAisle)
    }
}
