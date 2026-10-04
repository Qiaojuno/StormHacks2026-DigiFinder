// Gemini item finder (owner decision): hints where to look while searching; sightings stay `.itemSeen`.
import XCTest
@testable import DigiFinderCore

final class SessionSearchHintTests: XCTestCase {
    private let hintA = "coffee sign at 10 o'clock"
    private let hintB = "Shelves behind you may have it"

    func testHintIsSpokenAsGuidance() {
        var h = SessionHarness(grocery: false)
        h.startGoal(SessionFixtures.coffee)
        let out = h.send(.searchHint(hintA))
        XCTAssertEqual(said(out), ["Coffee sign at 10 o'clock."])
        XCTAssertEqual(said(out, .guidance), ["Coffee sign at 10 o'clock."])
        XCTAssertFalse(out.contains { if case .chime = $0 { return true } else { return false } }, "voice only")
    }

    func testSameHintIsNotRepeated() {
        var h = SessionHarness(grocery: false)
        h.startGoal(SessionFixtures.coffee)
        h.send(.searchHint(hintA))
        h.advance(9)
        XCTAssertEqual(said(h.send(.searchHint("Coffee sign at 10 o'clock."))), [], "same words, other punctuation")
        h.advance(30)
        XCTAssertEqual(said(h.send(.searchHint(hintA))), [])
    }

    func testHintsAreRateLimited() {
        var h = SessionHarness(grocery: false)
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(h.send(.searchHint(hintA))).count, 1)
        h.advance(4)
        XCTAssertEqual(said(h.send(.searchHint(hintB))), [], "within ~8 s")
        h.advance(4.5)
        XCTAssertEqual(said(h.send(.searchHint(hintB))), ["Shelves behind you may have it."])
    }

    func testQuietWhileListeningOrAskPending() {
        var h = SessionHarness(online: true, grocery: false)
        h.startGoal(SessionFixtures.coffee)
        h.send(.talkPressed)
        XCTAssertEqual(said(h.send(.searchHint(hintA))), [], "the user is talking")
        // The hint isn't replayed after the recording.
        XCTAssertFalse(said(h.send(.routed(.command(.repeatLast)))).contains("Coffee sign at 10 o'clock."))

        h.advance(10)
        h.send(.talkPressed)
        h.send(.routed(.question("is this decaf?")))
        XCTAssertTrue(h.state.askPending)
        XCTAssertEqual(said(h.send(.searchHint(hintA))), [], "an Ask answer is pending")
    }

    func testQuietWhenStopped() {
        var h = SessionHarness(grocery: false)
        h.startGoal(SessionFixtures.coffee)
        h.send(.donePressed)
        XCTAssertFalse(h.state.streaming)
        XCTAssertEqual(said(h.send(.searchHint(hintA))), [])
    }

    func testHintsOnlyInSearchPhases() {
        var idle = SessionHarness(grocery: false)
        XCTAssertEqual(idle.state.step, .idle)
        XCTAssertEqual(said(idle.send(.searchHint(hintA))), [], "no goal")

        var store = SessionHarness()
        store.reachShelf()
        XCTAssertEqual(store.state.step, .pick)
        XCTAssertEqual(said(store.send(.searchHint(hintA))), [], "pointing")
        store.grab()
        XCTAssertEqual(store.state.step, .confirm)
        XCTAssertEqual(said(store.send(.searchHint(hintA))), [], "checking the held item")

        var aisle = SessionHarness()
        aisle.enterAisle()
        XCTAssertEqual(aisle.state.step, .inAisle)
        aisle.advance(1)
        XCTAssertEqual(said(aisle.send(.searchHint(hintA))), ["Coffee sign at 10 o'clock."])
    }

    func testNoHintRightAfterASighting() {
        var h = SessionHarness(grocery: false)
        h.startGoal(SessionFixtures.coffee)
        h.send(.itemSeen(clock: 2, distance: 3))
        h.advance(1)
        XCTAssertEqual(said(h.send(.searchHint(hintA))), [], "the item is in view")
        h.advance(3)
        XCTAssertEqual(said(h.send(.searchHint(hintA))), ["Coffee sign at 10 o'clock."])
    }

    func testNewGoalResetsTheDedupe() {
        var h = SessionHarness(grocery: false)
        h.startGoal(SessionFixtures.coffee)
        h.send(.searchHint(hintB))
        h.send(.routed(.product(Goal(product: "tea", category: "tea"), .replace)))
        XCTAssertEqual(said(h.send(.searchHint(hintB))), ["Shelves behind you may have it."])
    }

    /// Tracked sightings arrive as `.itemSeen`: the global item rule is unchanged.
    func testTrackedSightingsKeepTheItemRule() {
        var walking = SessionHarness(grocery: false)
        walking.startGoal(SessionFixtures.coffee)
        walking.send(.motion(yawDegrees: 0, steps: 4, walking: true))
        XCTAssertEqual(said(walking.send(.itemSeen(clock: 12, distance: 1))), ["Stop. Coffee at 12 o'clock."])
        walking.advance(3.5)
        XCTAssertEqual(said(walking.send(.searchHint(hintB))), [], "waiting for Standing after \"Stop.\"")
        walking.send(.itemSeen(clock: 12, distance: 1))
        XCTAssertEqual(said(walking.send(.motion(yawDegrees: 0, steps: 5, walking: false))), ["Point at it with one finger."])
        XCTAssertEqual(walking.state.step, .pick)

        var household = SessionHarness(grocery: false)
        let phone = Goal(product: "phone", visualClass: "Mobile phone")
        household.startGoal(phone)
        XCTAssertEqual(said(household.send(.itemSeen(clock: 3, distance: 2.5))), ["Phone at 3 o'clock, about 3 meters."])
        let reach = household.send(.itemSeen(clock: 12, distance: 0.8))
        XCTAssertEqual(said(reach).first, "Phone is right in front of you, within reach.")
    }
}
