// Destinations, entrance, controls and system events (§5.2 entrance, §5.6, §5.9, §5.10, §5.16).
import XCTest
@testable import DigiFinderCore

final class SessionSystemTests: XCTestCase {
    // MARK: Destinations

    func testFindStaff() {
        var h = SessionHarness()
        let e = h.send(.routed(.destination(.customerService)))
        XCTAssertEqual(said(e), ["I'll take you to customer service. You can also ask anyone nearby."])
        XCTAssertTrue(e.contains(.setTarget(nil, candidates: [], destination: .customerService)))
        XCTAssertEqual(h.state.step, .findingDestination)
        XCTAssertEqual(said(h.send(.signs([AisleSign(words: ["Customer Service"], clock: 12)]))), ["Customer service desk, 12 o'clock."])
        let a = h.send(.arrivedAtDestination)
        XCTAssertEqual(said(a), ["You're at customer service."])
        XCTAssertTrue(a.contains(.chime(.done)))
        XCTAssertEqual(h.state.step, .idle)
    }

    func testCheckoutKeepsItemsOnTheList() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.routed(.product(SessionFixtures.milk, .add)))
        let e = h.send(.routed(.destination(.checkout)))
        XCTAssertEqual(said(e), ["Going to checkout. You still have coffee and milk on your list."])
        XCTAssertEqual(h.state.queue, [SessionFixtures.coffee, SessionFixtures.milk])
        let s = h.send(.signs([AisleSign(words: ["Self Checkout"], clock: 12)]))
        XCTAssertEqual(said(s, .guidance), ["Checkouts ahead, 12 o'clock."])
        XCTAssertEqual(said(s, .narration), ["A cashier can help you scan and pay."])
        XCTAssertEqual(said(h.send(.arrivedAtDestination)), ["You're at the checkout.", "You still have coffee and milk on your list."])
        XCTAssertEqual(said(h.startGoal(SessionFixtures.milk)), ["Looking for milk."], "queued items start when asked for")
        XCTAssertEqual(h.state.queue, [SessionFixtures.coffee])
    }

    func testDestinationNotFound() {
        var h = SessionHarness()
        h.send(.routed(.destination(.checkout)))
        XCTAssertEqual(said(h.send(.routed(.destination(.checkout)))), ["Going to checkout."])
        let e = h.advance(45)
        XCTAssertEqual(said(e), ["I can't see any signs. Turn slowly.", "I can't find it. Ask anyone nearby for help."])
    }

    // MARK: Entrance (P1)

    func testOnlineEntrancePickAndArrival() {
        var h = SessionHarness(online: true)
        h.send(.routed(.command(.outside(true))))
        let e = h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(e), ["Looking for coffee.", "Looking for the entrance."])
        XCTAssertTrue(e.contains(.pickEntrance))
        XCTAssertEqual(h.state.step, .findingEntrance)

        let p = h.send(.entrancePicked(EntrancePick(x: 0.9, kind: .revolving, cartCorralX: 0.5)))
        XCTAssertEqual(said(p), ["Entrance at 1 o'clock. It's a revolving door. Go slowly.", "Cart corral at 12 o'clock."])
        XCTAssertEqual(said(h.send(.doors([DoorObservation(clock: 1, distance: 12)]))), [])
        XCTAssertEqual(said(h.send(.doors([DoorObservation(clock: 1, distance: 7.2)]))), ["Entrance ahead, about 7 meters, 1 o'clock."])
        XCTAssertEqual(said(h.send(.doors([DoorObservation(clock: 12, distance: 6)]))), [], "announced once")

        let inside = h.send(.outside(false))
        XCTAssertEqual(said(inside), ["You're inside."])
        XCTAssertEqual(h.state.step, .findingSignage)
    }

    func testEntranceNotVisibleAsksAgainAfterTurning() {
        var h = SessionHarness(online: true)
        h.send(.outside(true))
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(h.send(.entrancePicked(nil))), ["I can't see the entrance. Turn slowly."])
        h.advance(5)
        XCTAssertFalse(h.send(.motion(yawDegrees: 30, steps: 0, walking: false)).contains(.pickEntrance))
        XCTAssertTrue(h.send(.motion(yawDegrees: 65, steps: 0, walking: false)).contains(.pickEntrance))
    }

    func testOfflineDoorsWithoutSigns() {
        var h = SessionHarness()
        h.send(.outside(true))
        let e = h.startGoal(SessionFixtures.coffee)
        XCTAssertFalse(e.contains(.pickEntrance))
        let doors = [DoorObservation(clock: 1, distance: 8), DoorObservation(clock: 11, distance: 15)]
        XCTAssertEqual(said(h.send(.doors(doors))), ["Door at 1 o'clock, about 8 meters. I can't see an entrance sign."])

        var exit = SessionHarness()
        exit.send(.outside(true))
        exit.startGoal(SessionFixtures.coffee)
        let labeled = [DoorObservation(clock: 12, distance: 3, label: .exit), DoorObservation(clock: 10, distance: 6)]
        XCTAssertEqual(said(exit.send(.doors(labeled))), ["This door says exit. Another door at 10 o'clock."])
        XCTAssertEqual(said(exit.send(.doors([DoorObservation(clock: 10, distance: 5, label: .entrance)]))),
                       ["Entrance ahead, about 5 meters, 10 o'clock."])
    }

    func testNoDoorForThirtySeconds() {
        var h = SessionHarness()
        h.send(.outside(true))
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(h.advance(30)), ["I can't find a door. Ask someone nearby."])
    }

    // MARK: Controls

    func testQuieterMoreDetailAndRepeat() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.signs([SessionFixtures.coffeeSign]))
        XCTAssertEqual(said(h.send(.routed(.command(.lessDetail)))), ["Shorter now."])
        XCTAssertEqual(said(h.send(.routed(.command(.repeatLast)))), ["9 o'clock, aisle 6, coffee and tea."])
        XCTAssertEqual(said(h.send(.routed(.command(.moreDetail)))), ["More detail."])
        h.send(.routed(.command(.moreDetail)))
        XCTAssertEqual(h.state.verbosity, .detailed)
    }

    func testNotUnderstoodLines() {
        var h = SessionHarness()
        XCTAssertEqual(said(h.send(.notUnderstood(noisy: false))), ["I didn't catch that. Say the product name."])
        h.send(.talkPressed)
        XCTAssertEqual(said(h.send(.notUnderstood(noisy: true))), ["Sorry, I didn't catch that. It's noisy here."])
    }

    func testStartIsIgnoredWhileRunning() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(h.send(.started), [])
        XCTAssertEqual(h.state.goal, SessionFixtures.coffee)
    }

    // MARK: System events (§5.16)

    func testLockAndUnlock() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.talkPressed)
        let e = h.send(.system(.backgrounded))
        XCTAssertEqual(said(e), ["Guidance paused, camera off."])
        XCTAssertTrue(e.contains(.cancelListening))
        XCTAssertEqual(h.state.step, .paused)
        let f = h.send(.system(.foregrounded))
        XCTAssertEqual(said(f), ["Back. Danger detection is on."])
        XCTAssertEqual(h.state.step, .findingSignage)
    }

    func testBatteryThermalRouteAndPermissions() {
        var h = SessionHarness()
        h.send(.notUnderstood(noisy: false))
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(h.send(.system(.batteryLow(20)))), ["Battery low, 20 percent."])
        XCTAssertEqual(said(h.send(.system(.batteryLow(20)))), [], "once each")
        XCTAssertEqual(said(h.send(.system(.batteryLow(10)))), ["Battery low, 10 percent."])

        let hot = h.send(.system(.thermal(.serious)))
        XCTAssertEqual(said(hot), ["Phone is getting hot. Guidance may slow down."])
        XCTAssertEqual(works(hot), [StreamWork(text: .fast, yoloFPS: 5)])
        let tooHot = h.send(.system(.thermal(.critical)))
        XCTAssertEqual(said(tooHot), ["Phone is too hot. Only danger alerts are on."])
        XCTAssertEqual(works(tooHot), [StreamWork(text: .off, yoloFPS: 5)])
        XCTAssertEqual(said(h.send(.signs([SessionFixtures.coffeeSign]))), [], "only danger and stairs")
        XCTAssertEqual(said(h.send(.stairs(StairsObservation(up: true, distance: 3, steps: 6)))).count, 1)
        h.send(.system(.thermal(.nominal)))
        XCTAssertEqual(h.state.work, SessionFixtures.signageWork)

        h.send(.signs([SessionFixtures.coffeeSign]))
        XCTAssertEqual(said(h.send(.system(.audioRouteChanged))), ["9 o'clock, aisle 6, coffee and tea."])
        XCTAssertEqual(said(h.send(.system(.cameraDenied))), ["Camera access is off. Ask someone to turn it on in Settings."])
        XCTAssertEqual(said(h.send(.system(.cameraDenied))), [])
    }

    func testNoticesWaitForTheRecording() {
        var h = SessionHarness()
        XCTAssertEqual(said(h.send(.system(.batteryLow(20)))), [], "held while the opening recording runs")
        XCTAssertEqual(said(h.send(.routed(.product(SessionFixtures.coffee, .unspecified)))), ["Looking for coffee.", "Battery low, 20 percent."])
    }
}
