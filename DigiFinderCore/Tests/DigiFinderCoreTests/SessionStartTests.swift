import XCTest
@testable import DigiFinderCore

/// Owner decisions: the app opens stopped and silent apart from one hint; the first volume up starts the stream,
/// records, and runs the grocery check; the place line follows the request recorded with it, once per app open.
final class SessionStartTests: XCTestCase {
    private let coffee = Goal(product: "coffee", category: "coffee")

    func testAppOpensStoppedWithOneHint() {
        var s = ShoppingSession(catalog: [:])
        let e = s.handle(.started)
        XCTAssertEqual(said(e), ["Press volume up to start."])
        XCTAssertTrue(e.contains(.setStreaming(false)), "camera, danger and checks stay off")
        XCTAssertFalse(e.contains(.classifyPlace), "no photos until the user starts")
        XCTAssertFalse(e.contains(.listen))
        XCTAssertFalse(s.state.streaming)
        XCTAssertEqual(s.state.step, .idle)
        for i in 1...60 { XCTAssertEqual(said(s.handle(.tick(Double(i)))), []) }
    }

    func testFirstVolumeUpStartsTheStreamRecordsAndChecksThePlace() {
        var s = ShoppingSession(catalog: [:])
        _ = s.handle(.started)
        let up = s.handle(.talkPressed)
        XCTAssertTrue(up.contains(.setStreaming(true)))
        XCTAssertTrue(up.contains(.listen))
        XCTAssertTrue(up.contains(.classifyPlace), "photos go to Gemini while the user talks")
        XCTAssertTrue(s.state.streaming)
        let a = s.handle(.placeClassified(PlaceAnswer(grocery: true, confidence: 0.92, scene: "supermarket aisle")))
        XCTAssertEqual(said(a), [], "held until the request is handled")
        XCTAssertEqual(s.state.place, .store)
        let r = s.handle(.routed(.product(coffee, .unspecified)))
        XCTAssertEqual(said(r).first, "Looking for coffee.")
        XCTAssertFalse(said(r).contains("You're in a grocery store."), "the place is never announced")
    }

    /// Owner decision: a request made while the check runs gets "Loading.", then "Okay, now looking for X.".
    func testLoadingThenNowLookingFor() {
        var s = ShoppingSession(catalog: [:])
        _ = s.handle(.started)
        _ = s.handle(.talkPressed)
        XCTAssertEqual(said(s.handle(.routed(.product(coffee, .unspecified)))).first, "Loading.")
        let a = s.handle(.placeClassified(PlaceAnswer(grocery: false, confidence: 0.8, scene: "University library")))
        XCTAssertEqual(said(a).first, "Okay, now looking for coffee.")
        XCTAssertFalse(said(a).contains { $0.contains("library") || $0.contains("grocery") }, "never says where")
        XCTAssertEqual(s.state.place, .general)
    }

    func testCheckedOncePerAppOpen() {
        var s = ShoppingSession(catalog: [:])
        _ = s.handle(.started)
        _ = s.handle(.talkPressed)
        _ = s.handle(.placeClassified(PlaceAnswer(grocery: true, confidence: 0.9, scene: "supermarket")))
        _ = s.handle(.notUnderstood(noisy: false))
        _ = s.handle(.donePressed)                                         // stop
        XCTAssertFalse(s.handle(.talkPressed).contains(.classifyPlace), "not again after a stop")
        XCTAssertEqual(s.state.place, .store)
    }

    func testLowConfidenceAsksOnceMoreThenUsesGeneral() {
        var s = ShoppingSession(catalog: [:])
        _ = s.handle(.started)
        _ = s.handle(.talkPressed)
        let first = s.handle(.placeClassified(PlaceAnswer(grocery: false, confidence: 0.5, scene: "hallway")))
        XCTAssertEqual(first, [.classifyPlace], "3 new photos, quietly")
        _ = s.handle(.placeClassified(PlaceAnswer(grocery: false, confidence: 0.6, scene: "hallway")))
        XCTAssertEqual(s.state.place, .general)
        XCTAssertEqual(s.state.placeTries, 2)
        XCTAssertEqual(said(s.handle(.routed(.product(coffee, .unspecified)))).first, "Looking for coffee.")
    }

    func testNoGeminiUsesGeneral() {
        var s = ShoppingSession(catalog: [:])
        s.setOnlineHelp(false)
        _ = s.handle(.started)
        XCTAssertFalse(s.handle(.talkPressed).contains(.classifyPlace))
        XCTAssertEqual(s.state.place, .general)
        XCTAssertEqual(said(s.handle(.routed(.product(coffee, .unspecified)))).first, "Looking for coffee.")
    }

    func testNoAnswerInTimeUsesGeneral() {
        var s = ShoppingSession(catalog: [:])
        _ = s.handle(.tick(0))
        _ = s.handle(.started)
        _ = s.handle(.talkPressed)
        _ = s.handle(.notUnderstood(noisy: false))
        var lines: [String] = []
        for i in 1...40 { lines += said(s.handle(.tick(Double(i) * 0.5))) }
        XCTAssertFalse(lines.contains("I couldn't tell if this is a grocery store."), "never announced")
        XCTAssertEqual(s.state.place, .general)
        XCTAssertEqual(said(s.handle(.placeClassified(PlaceAnswer(grocery: true, confidence: 1)))), [], "late answers dropped")
    }

    func testManualSettingSkipsTheCheck() {
        var m = ShoppingSession(catalog: [:])
        _ = m.setNearbyMode(true)
        _ = m.handle(.started)
        XCTAssertFalse(m.handle(.talkPressed).contains(.classifyPlace))
        XCTAssertEqual(m.state.placeOverride, .general)
    }

    func testMotionAndOnlineUpdateState() {
        var s = ShoppingSession(catalog: [:])
        _ = s.handle(.motion(yawDegrees: 12, steps: 3, walking: true))
        _ = s.handle(.system(.online(true)))
        XCTAssertTrue(s.state.isWalking)
        XCTAssertTrue(s.state.online)
    }
}
