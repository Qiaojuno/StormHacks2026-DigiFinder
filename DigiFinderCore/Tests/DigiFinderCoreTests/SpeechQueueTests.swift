import XCTest
@testable import DigiFinderCore

final class SpeechQueueTests: XCTestCase {
    private func line(_ text: String, _ p: SpeechPriority, _ t: Double = 0) -> SpeechLine {
        SpeechLine(text: text, priority: p, createdAt: t)
    }

    func testSpeaksImmediatelyWhenIdle() {
        var q = SpeechPriorityQueue()
        let a = line("What are you looking for?", .guidance)
        XCTAssertEqual(q.enqueue(a), .speakNow(a))
        XCTAssertEqual(q.current, a)
        XCTAssertTrue(q.isSpeaking)
        XCTAssertNil(q.finished(now: 1))
        XCTAssertFalse(q.isSpeaking)
    }

    func testInterruptQueueAndOrder() {
        var q = SpeechPriorityQueue()
        _ = q.enqueue(line("Okay, peanut butter instead.", .reply))
        XCTAssertEqual(q.enqueue(line("Turn to 9 o'clock.", .guidance)), .queued)
        XCTAssertEqual(q.enqueue(line("This is the coffee aisle.", .guidance)), .queued)
        XCTAssertEqual(q.enqueue(line("Walk through slowly.", .narration)), .queued)
        XCTAssertEqual(q.enqueue(line("Got it.", .reply)), .queued)
        XCTAssertEqual(q.pendingLines.map(\.text),
                       ["Got it.", "Turn to 9 o'clock.", "This is the coffee aisle.", "Walk through slowly."])   // FIFO per priority
        let danger = line("Cart ahead, steer left", .danger)
        XCTAssertEqual(q.enqueue(danger), .interrupt(danger))
        XCTAssertEqual(q.finished(now: 1)?.text, "Okay, peanut butter instead.")   // interrupted reply comes back first
        XCTAssertEqual(q.finished(now: 1)?.text, "Got it.")
        XCTAssertEqual(q.finished(now: 1)?.text, "Turn to 9 o'clock.")
        XCTAssertEqual(q.finished(now: 1)?.text, "This is the coffee aisle.")
        XCTAssertEqual(q.finished(now: 1)?.text, "Walk through slowly.")
        XCTAssertNil(q.finished(now: 1))
    }

    func testStaleLowerLinesDropButStairsAndDangerWait() {
        var q = SpeechPriorityQueue()
        _ = q.enqueue(line("Person ahead, stop", .danger, 0))
        _ = q.enqueue(line("Coffee is at 9 o'clock.", .guidance, 0))
        _ = q.enqueue(line("Stairs, 1 meter ahead.", .stairs, 0))
        XCTAssertEqual(q.finished(now: 10)?.text, "Stairs, 1 meter ahead.")
        XCTAssertNil(q.finished(now: 10))                                  // guidance went stale
    }

    func testDropsDuplicatesAndBriefNarration() {
        var q = SpeechPriorityQueue(verbosity: .brief)
        XCTAssertEqual(q.enqueue(line("Walk through slowly.", .narration)), .dropped)
        _ = q.enqueue(line("Turn to 9 o'clock.", .guidance))
        XCTAssertEqual(q.enqueue(line("Turn to 9 o'clock.", .guidance)), .dropped)
        let reply = line("Next: milk.", .reply)
        XCTAssertEqual(q.enqueue(reply), .interrupt(reply))                 // the guidance line is dropped
        XCTAssertEqual(q.enqueue(line("Next: milk.", .reply)), .dropped)
        q.verbosity = .normal
        XCTAssertEqual(q.enqueue(line("Walk through slowly.", .narration)), .queued)
        XCTAssertEqual(q.enqueue(line("Coffee is at 9 o'clock.", .guidance)), .queued)
        q.verbosity = .brief
        XCTAssertEqual(q.finished(now: 0)?.text, "Coffee is at 9 o'clock.")
        XCTAssertNil(q.finished(now: 0))                                    // narration skipped at brief
    }

    func testInterruptedStairsAndRepliesComeBack() {
        var q = SpeechPriorityQueue()
        let stairs = line("Stairs going up, about 8 steps, 3 meters, 12 o'clock.", .stairs)
        _ = q.enqueue(stairs)
        _ = q.enqueue(line("Danger first", .danger))
        XCTAssertEqual(q.finished(now: 20), stairs)                        // never stale, replayed after the alert
        XCTAssertNil(q.finished(now: 20))
        let answer = line("It says gluten free. Check with staff to confirm.", .reply, 20)
        XCTAssertEqual(q.enqueue(answer), .speakNow(answer))
        let near = line("Stairs, 1 meter ahead.", .stairs, 20)
        XCTAssertEqual(q.enqueue(near), .interrupt(near))                  // stairs outrank replies
        XCTAssertEqual(q.finished(now: 21), answer)
        XCTAssertNil(q.finished(now: 21))
        _ = q.enqueue(line("Turn to 9 o'clock.", .guidance, 21))
        _ = q.enqueue(line("Person ahead, stop", .danger, 21))
        XCTAssertNil(q.finished(now: 22))                                   // interrupted guidance isn't replayed
    }

    func testNewestDangerSupersedesWaitingDanger() {
        var q = SpeechPriorityQueue()
        _ = q.enqueue(line("Cart ahead, steer left", .danger))
        XCTAssertEqual(q.enqueue(line("Person ahead, steer right", .danger)), .queued)   // never cut a danger line
        XCTAssertEqual(q.enqueue(line("Obstacle ahead, stop", .danger)), .queued)
        XCTAssertEqual(q.pendingLines.map(\.text), ["Obstacle ahead, stop"])
    }

    func testTalkHoldsGuidanceButNotDangerOrStairs() {
        var q = SpeechPriorityQueue()
        _ = q.enqueue(line("Turn to 9 o'clock.", .guidance))
        _ = q.enqueue(line("Walk through slowly.", .narration))
        XCTAssertTrue(q.holdForListening())
        XCTAssertNil(q.current)
        XCTAssertTrue(q.pendingLines.isEmpty)
        _ = q.enqueue(line("Stairs going up, about 8 steps, 3 meters, 12 o'clock.", .stairs))
        _ = q.enqueue(line("Coffee is at 9 o'clock.", .guidance))
        _ = q.enqueue(line("Person ahead, stop", .danger, 0))
        XCTAssertFalse(q.holdForListening())                                // the danger line plays out
        XCTAssertEqual(q.pendingLines.map(\.priority), [.stairs])
        XCTAssertFalse(q.clear(below: .danger))
        XCTAssertTrue(q.pendingLines.isEmpty)
        q.stopAll()
        XCTAssertNil(q.current)
        XCTAssertFalse(q.holdForListening())                                // nothing playing
    }

    func testOriginalPushPathUnchanged() {
        var q = SpeechPriorityQueue()
        XCTAssertFalse(q.push(line("a", .guidance)))                       // idle: waits for next(now:)
        XCTAssertNil(q.current)
        XCTAssertEqual(q.next(now: 0)?.text, "a")
        XCTAssertTrue(q.push(line("b", .reply)))
        XCTAssertFalse(q.push(line("c", .reply)))
        XCTAssertEqual(q.next(now: 0)?.text, "c")
    }

    func testChannel() {
        XCTAssertEqual(speechChannel(for: .danger, voiceOverRunning: true), .synthesizer)
        XCTAssertEqual(speechChannel(for: .stairs, voiceOverRunning: true), .voiceOverAnnouncement)
        XCTAssertEqual(speechChannel(for: .guidance, voiceOverRunning: false), .synthesizer)
    }
}
