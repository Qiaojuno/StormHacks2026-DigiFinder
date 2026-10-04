// Grocery store or anywhere else (`general`): the place decides the search, never the alerts.
import XCTest
@testable import DigiFinderCore

final class SessionNearbyTests: XCTestCase {
    func testHouseholdWords() {
        XCTAssertEqual(MatchingHousehold.visualClass(for: "my phone"), "Mobile phone")
        XCTAssertEqual(MatchingHousehold.visualClass(for: "the TV remote"), "Remote control")
        XCTAssertEqual(MatchingHousehold.visualClass(for: "the black mug"), "Mug")
        XCTAssertNil(MatchingHousehold.visualClass(for: "keys"))              // no camera class: labels only
    }

    /// Owner spec: placeClassified(false) → no sign prompts, no step-back vote, no aisle flow.
    func testGeneralPlaceHasNoSignPrompts() {
        var h = SessionHarness(grocery: false)
        XCTAssertEqual(h.state.place, .general)
        let start = h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(start), ["Looking for coffee.", "Turn slowly."])
        let quiet = said(h.advance(15))
        XCTAssertFalse(quiet.contains("I can't see any signs. Turn slowly."))
        XCTAssertFalse(quiet.contains("Take two steps back."))
        XCTAssertEqual(said(h.send(.signs([SessionFixtures.coffeeSign]))), [])
        XCTAssertEqual(said(h.send(.arrivedAtAisle(clock: 9))), [])
        XCTAssertEqual(said(h.send(.aisleVerdict("coffee", evidence: ["coffee"]))), [])
        XCTAssertEqual(h.state.step, .findAisle)
        XCTAssertEqual(said(h.send(.itemSeen(clock: 2, distance: 3))), ["Coffee at 2 o'clock, about 3 meters."])
    }

    /// General is the default (owner decision): only a confident "grocery" answer runs the store flow.
    func testOnlyAGroceryYesRunsTheStoreFlow() {
        var store = SessionHarness(grocery: true)
        store.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(store.advance(3)), ["I can't see any signs. Turn slowly."])

        var unknown = SessionHarness(grocery: nil)
        unknown.send(.placeClassified(nil))
        XCTAssertEqual(unknown.state.place, .general)
        unknown.startGoal(SessionFixtures.coffee)
        XCTAssertFalse(said(unknown.advance(3)).contains("I can't see any signs. Turn slowly."), "no sign prompts")
    }

    func testWaitingForTheAnswerIsQuietButSignsAreRead() {
        var h = SessionHarness(grocery: nil)
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(h.advance(5)), [], "quiet while the place check runs")
        XCTAssertEqual(said(h.send(.signs([SessionFixtures.coffeeSign]))), [], "general until a grocery yes: no sign directions")
        let a = h.send(.placeClassified(PlaceAnswer(grocery: false, confidence: 0.9, scene: "home kitchen")))
        XCTAssertEqual(said(a), ["Okay, now looking for coffee.", "Turn slowly."], "no place line: the search runs")
        XCTAssertEqual(h.state.place, .general)
    }

    func testGeneralPlaceFindsAHouseholdObject() {
        var h = SessionHarness(grocery: false)
        let phone = Goal(product: "phone", visualClass: "Mobile phone")
        h.send(.routed(.product(phone, .unspecified)))
        h.advance(10)
        XCTAssertEqual(h.state.step, .findAisle)
        let found = h.send(.itemSeen(clock: 1, distance: 0.8))
        XCTAssertEqual(said(found).first, "Phone, within reach.")
        XCTAssertTrue(found.contains(.chime(.done)))
        XCTAssertTrue(found.contains(.markDone(phone)))
    }

    /// Owner decision: no search gives up, in a store or anywhere else.
    func testGeneralPlaceNeverGivesUp() {
        var h = SessionHarness()
        _ = h.session.setNearbyMode(true)
        h.send(.routed(.product(Goal(product: "phone", visualClass: "Mobile phone"), .unspecified)))
        let e = said(h.advance(300))
        XCTAssertTrue(e.contains("Stop and look around. I need context."))
        XCTAssertFalse(e.contains { $0.contains("couldn't find") })
        XCTAssertNotNil(h.state.goal)
    }

    func testManualOverridesWin() {
        var h = SessionHarness(grocery: true)
        h.startGoal(SessionFixtures.coffee)
        let e = h.send(.routed(.command(.nearby(true))))
        XCTAssertTrue(said(e).contains("Okay, looking nearby."))
        XCTAssertEqual(h.state.placeOverride, .general)
        XCTAssertFalse(said(h.advance(15)).contains("I can't see any signs. Turn slowly."))
        h.send(.routed(.command(.nearby(false))))
        XCTAssertEqual(h.state.placeOverride, .store)
        XCTAssertEqual(said(h.advance(3.5)), ["I can't see any signs. Turn slowly."])
        XCTAssertEqual(VoiceCommandParser.parse("it s nearby"), .nearby(true))
        XCTAssertEqual(VoiceCommandParser.parse("store mode"), .nearby(false))
    }
}

/// Owner decisions: a grocery search never gives up; context is asked for with "Stop and look around…", then "Keep going."
final class SessionContextTests: XCTestCase {
    func testGroceryStoreNeverGivesUp() {
        var h = SessionHarness(grocery: true, onDevice: false)
        h.send(.motion(yawDegrees: 0, steps: 0, walking: true))
        h.startGoal(SessionFixtures.coffee)
        let lines = said(h.advance(300))
        XCTAssertFalse(lines.contains { $0.contains("couldn't find") }, "\(lines)")
        XCTAssertNotNil(h.state.goal)
    }

    func testStopLookAroundThenKeepGoing() {
        var h = SessionHarness(grocery: true, onDevice: false)
        h.send(.motion(yawDegrees: 0, steps: 0, walking: true))
        h.startGoal(SessionFixtures.coffee)
        XCTAssertTrue(said(h.advance(15)).contains("Stop and look around. I need context."))
        XCTAssertFalse(said(h.advance(5)).contains("Keep going."), "still walking")
        h.send(.motion(yawDegrees: 0, steps: 0, walking: false))
        XCTAssertFalse(said(h.advance(3)).contains("Keep going."), "not long enough")
        XCTAssertTrue(said(h.advance(1.5)).contains("Keep going."))
    }

    func testASightingAnswersInsteadOfKeepGoing() {
        var h = SessionHarness(grocery: true, onDevice: false)
        h.send(.motion(yawDegrees: 0, steps: 0, walking: true))
        h.startGoal(SessionFixtures.coffee)
        h.advance(15)
        h.send(.itemSeen(clock: 2, distance: 4))
        h.send(.motion(yawDegrees: 0, steps: 0, walking: false))
        XCTAssertFalse(said(h.advance(6)).contains("Keep going."))
    }

    func testNeverSaysTurnAround() {
        var h = SessionHarness(grocery: true, onDevice: false)
        h.send(.motion(yawDegrees: 0, steps: 0, walking: true))
        h.startGoal(SessionFixtures.coffee)
        XCTAssertFalse(said(h.advance(120)).contains { $0.lowercased().contains("turn") })
    }
}
