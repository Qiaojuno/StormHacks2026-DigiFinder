// Owner decision: Gemini answers and hints wait for an alert to end; a new alert keeps them waiting.
import XCTest
@testable import DigiFinderCore

final class AfterDangerTests: XCTestCase {
    private let hint = "coffee sign at 10 o'clock"

    func testHintDuringAlertPlaysWhenItClears() {
        var h = SessionHarness(grocery: false)
        h.startGoal(SessionFixtures.coffee)
        h.send(.danger(cutRecording: false))
        XCTAssertEqual(said(h.send(.searchHint(hint))), [], "waits for the alert")
        XCTAssertTrue(said(h.send(.dangerCleared)).contains("Coffee sign at 10 o'clock."))
    }

    func testNewAlertKeepsItWaiting() {
        var h = SessionHarness(grocery: false)
        h.startGoal(SessionFixtures.coffee)
        h.send(.danger(cutRecording: false))
        h.send(.searchHint(hint))
        h.send(.danger(cutRecording: false))
        XCTAssertEqual(said(h.send(.searchHint("shelves behind you"))), [])
        XCTAssertEqual(said(h.send(.dangerCleared)).filter { $0.contains("10 o'clock") || $0.contains("behind") },
                       ["Shelves behind you."], "newest hint only")
    }

    func testStopDropsWaitingLines() {
        var h = SessionHarness(grocery: false)
        h.startGoal(SessionFixtures.coffee)
        h.send(.danger(cutRecording: false))
        h.send(.searchHint(hint))
        h.send(.donePressed)
        XCTAssertFalse(said(h.send(.dangerCleared)).contains("Coffee sign at 10 o'clock."))
    }

    func testReplyInterruptedByAlertPlaysAfterIt() {
        var q = SpeechPriorityQueue()
        _ = q.enqueue(SpeechLine(text: "The coffee is on your left.", priority: .reply, createdAt: 0))
        XCTAssertEqual(q.enqueue(SpeechLine(text: "Person ahead", priority: .danger, createdAt: 1)),
                       .interrupt(SpeechLine(text: "Person ahead", priority: .danger, createdAt: 1)))
        _ = q.enqueue(SpeechLine(text: "Cart ahead", priority: .danger, createdAt: 2.5))
        XCTAssertEqual(q.finished(now: 3)?.text, "Cart ahead")
        XCTAssertEqual(q.finished(now: 6)?.text, "The coffee is on your left.", "not stale: it waited for the alerts")
    }

    func testGuidanceStillGoesStaleAfterAnAlert() {
        var q = SpeechPriorityQueue()
        _ = q.enqueue(SpeechLine(text: "Person ahead", priority: .danger, createdAt: 0))
        _ = q.enqueue(SpeechLine(text: "Walk ahead.", priority: .guidance, createdAt: -5))
        XCTAssertNil(q.finished(now: 2))
    }
}
