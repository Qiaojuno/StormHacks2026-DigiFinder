import XCTest
@testable import DigiFinderCore

final class SessionStartTests: XCTestCase {
    func testSessionStartAsksForGoal() {
        var s = ShoppingSession(catalog: [:])
        let e = s.handle(.started)
        XCTAssertTrue(e.contains(.say("What are you looking for?", .guidance)))
        XCTAssertEqual(s.state.step, .askingGoal)
        XCTAssertEqual(e.last, .listen(maxSeconds: 10), "records right after the question")
        XCTAssertTrue(e.contains(.setWork(StreamWork(text: .off, yoloFPS: 10))))
        XCTAssertEqual(s.state.lastLine, "What are you looking for?")
        XCTAssertTrue(s.state.isListening)
    }

    func testMotionAndOnlineUpdateState() {
        var s = ShoppingSession(catalog: [:])
        _ = s.handle(.motion(yawDegrees: 12, steps: 3, walking: true))
        _ = s.handle(.system(.online(true)))
        XCTAssertTrue(s.state.isWalking)
        XCTAssertTrue(s.state.online)
    }
}
