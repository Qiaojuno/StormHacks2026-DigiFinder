import XCTest
@testable import DigiFinderCore

/// Owner decision: the camera flip follows gravity automatically.
final class OrientationTrackerTests: XCTestCase {
    func testFlipsAfterHoldingUpsideDown() {
        var o = OrientationTracker()
        XCTAssertNil(o.update(gravityY: 0.9, t: 0))
        XCTAssertNil(o.update(gravityY: 0.9, t: 0.5))
        XCTAssertEqual(o.update(gravityY: 0.9, t: 1.0), true)
        XCTAssertTrue(o.upsideDown)
        XCTAssertNil(o.update(gravityY: 0.9, t: 1.5), "no repeat")
    }

    func testSwingDoesNotFlip() {
        var o = OrientationTracker()
        XCTAssertNil(o.update(gravityY: 0.9, t: 0))
        XCTAssertNil(o.update(gravityY: -0.9, t: 0.5))
        XCTAssertNil(o.update(gravityY: 0.9, t: 0.8))
        XCTAssertNil(o.update(gravityY: 0.9, t: 1.5))
        XCTAssertFalse(o.upsideDown)
    }

    func testFlatChangesNothingAndFlipsBack() {
        var o = OrientationTracker(upsideDown: true)
        XCTAssertNil(o.update(gravityY: 0.1, t: 0), "lying flat")
        XCTAssertNil(o.update(gravityY: 0.1, t: 5))
        XCTAssertTrue(o.upsideDown)
        _ = o.update(gravityY: -0.95, t: 6)
        XCTAssertEqual(o.update(gravityY: -0.95, t: 7), false)
    }
}
