// Danger cut-in, stairs, positioning prompts, talk/done presses (§5.3, §5.4, §5.8, §5.10, §5.15).
import XCTest
@testable import DigiFinderCore

final class SessionSafetyTests: XCTestCase {
    /// Owner decision: volume up starts a recording (it ends on silence, in the runner); volume down / stop ends the
    /// whole stream at once — recording discarded, item and list cleared, nothing spoken.
    func testTalkAndStop() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.routed(.product(SessionFixtures.milk, .unspecified)))
        XCTAssertEqual(h.send(.talkPressed), [.stopSpeech, .listen])
        XCTAssertEqual(h.send(.talkPressed), [], "ignored while recording")
        let stop = h.send(.donePressed)
        XCTAssertTrue(stop.contains(.cancelListening))
        XCTAssertTrue(stop.contains(.setStreaming(false)))
        XCTAssertEqual(said(stop), [], "stopping is silent")
        XCTAssertFalse(h.state.isListening)
        XCTAssertFalse(h.state.streaming)
        XCTAssertNil(h.state.goal)
        XCTAssertEqual(h.state.queue, [])
        XCTAssertEqual(h.state.step, .idle)
        XCTAssertEqual(said(h.advance(30)), [], "no prompts or timers while stopped")
        XCTAssertEqual(said(h.send(.signs([SessionFixtures.coffeeSign]))), [])
        XCTAssertEqual(h.send(.donePressed), [], "stop again: nothing")
        let start = h.send(.talkPressed)
        XCTAssertEqual(start, [.setStreaming(true), .stopSpeech, .listen], "volume up restarts the stream and records")
        XCTAssertTrue(h.state.streaming)
    }

    func testDangerCutsTheRecordingAndAsksAgain() {
        var h = SessionHarness()
        h.startGoal(SessionFixtures.coffee)
        h.send(.talkPressed)
        let e = h.send(.danger(cutRecording: true))
        XCTAssertEqual(e, [.say("Say that again.", .reply)], "no auto-recording: volume up to answer")
        XCTAssertFalse(h.state.isListening)
        h.send(.talkPressed)
        XCTAssertEqual(said(h.send(.routed(.product(SessionFixtures.milk, .add)))), ["Okay, milk instead."])
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
                           .say("Say that again.", .reply)])
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
        XCTAssertEqual(said(h.send(.positioning(.phoneFlipped))), [], "standing still: flipped stays quiet")
        h.send(.motion(yawDegrees: 0, steps: 2, walking: true))
        XCTAssertEqual(said(h.send(.positioning(.tiltUp))), [], "never: lanyard")
        XCTAssertEqual(said(h.send(.positioning(.tiltDown))), [])
        XCTAssertEqual(said(h.send(.positioning(.slowDown))), ["Slow down."])
        XCTAssertEqual(said(h.send(.positioning(.slowDown))), [], "rate limited")
        XCTAssertEqual(said(h.send(.positioning(.pointInFront))), [], "only in Pick")
        XCTAssertEqual(said(h.send(.positioning(.phoneFlipped))), ["Phone may be flipped around."])
        h.advance(10)
        XCTAssertEqual(said(h.send(.positioning(.phoneFlipped))), [], "max once per 30 s")
        h.advance(20)
        XCTAssertEqual(said(h.send(.positioning(.phoneFlipped))), ["Phone may be flipped around."])
        XCTAssertEqual(said(h.send(.positioning(.tooDark))), ["It's too dark for me to read here."])
    }

    func testStandingAtTheShelfSilencesTheFlippedCheck() {
        var h = SessionHarness()
        h.reachShelf()
        XCTAssertEqual(said(h.send(.positioning(.phoneFlipped))), [], "standing: Safety doesn't check, the session ignores it")
        XCTAssertEqual(said(h.send(.positioning(.pointInFront))), ["Point in front of the phone, at chest height."])
        XCTAssertEqual(said(h.send(.positioning(.stepBack))), ["Step back a little."])
    }

    /// Perception work per phase. StreamWork carries no alert flag: alerts follow the motion state only.
    func testStreamWorkPerPhase() {
        var h = SessionHarness()
        XCTAssertEqual(h.state.work, StreamWork(text: .off, yoloFPS: 10))
        h.startGoal(SessionFixtures.coffee)
        XCTAssertEqual(h.state.work, SessionFixtures.signageWork)
        h.send(.signs([SessionFixtures.coffeeSign]), .arrivedAtAisle(clock: 9), .motion(yawDegrees: -90, steps: 0, walking: true))
        XCTAssertEqual(h.state.step, .inAisle)
        XCTAssertEqual(h.state.work, SessionFixtures.signageWork)
        h.send(.signs([SessionFixtures.shelfSign]), .motion(yawDegrees: -90, steps: 2, walking: false))
        XCTAssertEqual(h.state.work, SessionFixtures.pointingWork)
        h.grab()
        XCTAssertEqual(h.state.work, SessionFixtures.holdUpWork)
    }

    /// Nothing in Core gates alerts by phase: a danger is handled the same way in every phase and overlay.
    func testDangerHandlingIsTheSameInEveryPhase() {
        func check(_ h: inout SessionHarness, _ label: String) {
            XCTAssertEqual(h.send(.danger(cutRecording: false)), [], label)
            XCTAssertNotNil(h.state.dangerSince, label)
            h.send(.dangerCleared)
            XCTAssertNil(h.state.dangerSince, label)
        }
        var h = SessionHarness(online: true)
        check(&h, "idle")
        h.enterAisle()
        check(&h, "in aisle")
        h.send(.signs([SessionFixtures.shelfSign]), .motion(yawDegrees: -90, steps: 2, walking: false))
        XCTAssertEqual(h.state.step, .pick)
        h.send(.danger(cutRecording: false))
        XCTAssertNotNil(h.state.dangerSince, "pick")
        h.send(.dangerCleared)
        h.grab()
        check(&h, "confirm")
        h.send(.routed(.question("is this decaf")))
        XCTAssertTrue(h.state.askPending)
        check(&h, "ask pending")
    }

    /// A cancelled recording (no transcript) must not leave the session "recording": volume up works again.
    func testCancelledRecordingDoesNotBlockVolumeUp() {
        var h = SessionHarness()
        XCTAssertTrue(h.send(.talkPressed).contains(.listen))
        XCTAssertEqual(said(h.send(.recordingCancelled)), [], "silent")
        XCTAssertFalse(h.state.isListening)
        XCTAssertTrue(h.send(.talkPressed).contains(.listen))
    }

    /// Safety net: a recording nobody answered is cleared after ~30 s.
    func testStuckRecordingIsCleared() {
        var h = SessionHarness()
        h.send(.talkPressed)
        let e = h.advance(31)
        XCTAssertTrue(e.contains(.cancelListening))
        XCTAssertFalse(h.state.isListening)
        XCTAssertTrue(h.send(.talkPressed).contains(.listen))
    }
}
