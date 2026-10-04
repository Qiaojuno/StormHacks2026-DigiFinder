// Danger cut-in, stairs, positioning prompts, talk/done presses (§5.3, §5.4, §5.8, §5.10, §5.15).
import XCTest
@testable import DigiFinderCore

final class SessionSafetyTests: XCTestCase {
    func testTalkAndDonePresses() {
        var h = SessionHarness()
        h.send(.notUnderstood(noisy: false))                       // end the opening recording
        XCTAssertEqual(h.send(.donePressed), [], "ignored when not listening")
        XCTAssertEqual(h.send(.talkPressed), [.stopSpeech, .listen(maxSeconds: 10)])
        XCTAssertEqual(h.send(.talkPressed), [.finishListening], "pressed again = done")
        XCTAssertEqual(h.send(.donePressed), [.finishListening])
    }

    func testDangerCutsTheRecordingAndAsksAgain() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.talkPressed)
        let e = h.send(.danger(cutRecording: true))
        XCTAssertEqual(e, [.say("Say that again.", .reply), .listen(maxSeconds: 5)])
        XCTAssertTrue(h.state.isListening)
        XCTAssertEqual(said(h.send(.routed(.product(SessionFixtures.milk, .add)))), ["Added milk to the list."])
    }

    func testGuidanceQuietDuringDangerThenRecalculates() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.signs([SessionFixtures.coffeeSign]))
        XCTAssertEqual(said(h.send(.danger(cutRecording: false))), [], "the safety lane speaks the alert itself")
        h.advance(3)
        XCTAssertEqual(said(h.send(.signs([SessionFixtures.coffeeSign]))), [])
        h.send(.dangerCleared)
        XCTAssertEqual(said(h.send(.signs([SessionFixtures.coffeeSign]))), ["9 o'clock, aisle 6, coffee and tea."],
                       "recalculate clears the de-dupe: a fresh prompt from the next frames")
    }

    func testDangerClearedAtTheShelfRepeatsTheStepPrompt() {
        var h = SessionHarness()
        h.reachShelf()
        h.send(.danger(cutRecording: false))
        XCTAssertEqual(said(h.send(.dangerCleared)), ["Point at the shelf with one finger. Start at chest height."])
    }

    func testStairsAnnouncedOnceWithPedometerCountdown() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.motion(yawDegrees: 0, steps: 100, walking: true))
        let e = h.send(.stairs(StairsObservation(up: true, distance: 3, steps: 8)))
        XCTAssertEqual(said(e, .stairs), ["Stairs going up, about 8 steps, 3 meters, 12 o'clock."])
        XCTAssertEqual(said(h.send(.stairs(StairsObservation(up: true, distance: 2.8, steps: 8)))), [], "once per staircase")
        XCTAssertEqual(said(h.send(.motion(yawDegrees: 0, steps: 102, walking: true))), [])
        XCTAssertEqual(said(h.send(.motion(yawDegrees: 0, steps: 103, walking: true)), .stairs), ["Stairs, 1 meter ahead."])
        XCTAssertEqual(said(h.send(.motion(yawDegrees: 0, steps: 104, walking: true))), [])
    }

    func testStairsLinesIgnoreVerbosityAndCutRecordings() {
        var h = SessionHarness()
        h.send(.routed(.command(.lessDetail)))
        h.send(.talkPressed)
        let e = h.send(.stairs(StairsObservation(up: false, distance: 2, steps: 4)))
        XCTAssertEqual(e, [.cancelListening, .say("Stairs going down, about 4 steps, 2 meters, 12 o'clock.", .stairs),
                           .say("Say that again.", .reply), .listen(maxSeconds: 5)])
    }

    func testNewStaircaseAfterAWhile() {
        var h = SessionHarness()
        h.send(.stairs(StairsObservation(up: true, distance: 3, steps: 8)))
        h.advance(15)
        XCTAssertEqual(said(h.send(.stairs(StairsObservation(up: true, distance: 4, steps: 5)))),
                       ["Stairs going up, about 5 steps, 4 meters, 12 o'clock."])
    }

    func testPositioningPrompts() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(said(h.send(.positioning(.tiltUp))), ["Tilt the phone up."])
        XCTAssertEqual(said(h.send(.positioning(.tiltUp))), [], "rate limited")
        XCTAssertEqual(said(h.send(.positioning(.pointInFront))), [], "only while pointing")
        XCTAssertEqual(said(h.send(.positioning(.phoneFlipped))), ["Phone may be flipped around."])
        h.advance(10)
        XCTAssertEqual(said(h.send(.positioning(.phoneFlipped))), [], "max once per 30 s")
        h.advance(20)
        XCTAssertEqual(said(h.send(.positioning(.phoneFlipped))), ["Phone may be flipped around."])
        XCTAssertEqual(said(h.send(.positioning(.tooDark))), ["It's too dark for me to read here."])
    }

    func testShelfModeSilencesTheFlippedCheck() {
        var h = SessionHarness()
        h.reachShelf()
        XCTAssertEqual(said(h.send(.positioning(.phoneFlipped))), [])
        XCTAssertEqual(said(h.send(.positioning(.pointInFront))), ["Point in front of the phone, at chest height."])
        XCTAssertEqual(said(h.send(.positioning(.stepBack))), ["Step back a little."])
    }

    func testStreamWorkPerStep() {
        var h = SessionHarness()
        XCTAssertEqual(h.state.work, StreamWork(text: .off, yoloFPS: 10))
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(h.state.work, SessionFixtures.signageWork)
        h.send(.signs([SessionFixtures.coffeeSign]), .arrivedAtAisle(clock: 9))
        XCTAssertEqual(h.state.work?.shelfMode, false, "walking the aisle is not shelf mode")
        h.send(.motion(yawDegrees: -90, steps: 0, walking: true), .signs([SessionFixtures.shelfSign]))
        XCTAssertEqual(h.state.work, SessionFixtures.pointingWork)
        h.grab()
        XCTAssertEqual(h.state.work, SessionFixtures.holdUpWork)
    }
}
