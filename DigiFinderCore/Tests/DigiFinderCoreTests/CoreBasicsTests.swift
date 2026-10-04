import XCTest
@testable import DigiFinderCore

final class CoreBasicsTests: XCTestCase {
    func testNormalizeMatchesBuildScript() {
        XCTAssertEqual(normalizeText("Café Dark-Roast, 340g"), "cafe dark roast 340g")
        XCTAssertEqual(normalizeText("Where's the  COFFEE?"), "where s the coffee")
        XCTAssertEqual(normalizeBarcode("0 64200 11677 0"), "0064200116770")
    }

    func testContractsHaveDefaultedInits() {
        XCTAssertEqual(Goal(product: "coffee").variant, [])
        XCTAssertNil(ProductInfo(code: "1", name: "Milk").brand)
        XCTAssertEqual(StreamWork().text, .off)
        XCTAssertEqual(DoorObservation(clock: 12).label, .unknown)
        XCTAssertEqual(StairsObservation(up: true, distance: 3).more, false)
    }

    func testAisleInfoToleratesMissingKeys() throws {
        let json = #"{ "coffee": { "aisleWords": ["coffee", "tea"] } }"#.data(using: .utf8)!
        let aisles = try JSONDecoder().decode([String: AisleInfo].self, from: json)
        XCTAssertEqual(aisles["coffee"]?.aisleWords, ["coffee", "tea"])
        XCTAssertEqual(aisles["coffee"]?.offTags, [])
    }

    func testClock() {
        XCTAssertEqual(clockPosition(degreesRight: 0), 12)
        XCTAssertEqual(clockPosition(degreesRight: 90), 3)
        XCTAssertEqual(clockPosition(degreesRight: -90), 9)
        XCTAssertEqual(clockPosition(degreesRight: 180), 6)
        XCTAssertEqual(clockPosition(degreesRight: 25), 1)
    }

    func testGeometryConverters() {
        let p = Geometry.fromVision(NormPoint(x: 0.25, y: 0.9))
        XCTAssertEqual(p.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0.1, accuracy: 1e-9)
        let r = Geometry.fromVision(NormRect(x: 0.1, y: 0.7, width: 0.2, height: 0.2))
        XCTAssertEqual(r.y, 0.1, accuracy: 1e-9)
        // Sensor row 0 is the portrait image's right edge; column 0 its top edge.
        XCTAssertEqual(Geometry.fromSensorPixels((x: 0, y: 0), width: 1920, height: 1440), NormPoint(x: 1, y: 0))
        XCTAssertEqual(Geometry.fromSensorPixels((x: 1920, y: 1440), width: 1920, height: 1440), NormPoint(x: 0, y: 1))
        let back = Geometry.toSensorPixels(NormPoint(x: 0.3, y: 0.6), width: 1920, height: 1440)
        XCTAssertEqual(Geometry.fromSensorPixels(back, width: 1920, height: 1440).x, 0.3, accuracy: 1e-9)
        let k = Mat3.intrinsics(fx: 1000, fy: 1000, cx: 960, cy: 720)
        XCTAssertEqual(Geometry.degreesRight(portraitX: 0.5, intrinsics: k, sensorHeight: 1440), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(Geometry.degreesRight(portraitX: 0.9, intrinsics: k, sensorHeight: 1440), 0)
    }

    func testCorridorAndAlert() {
        let wall = (0..<50).map { i in Vec3(x: Float(i % 5) * 0.1 - 0.2, y: 0, z: 1.5) }
        XCTAssertEqual(nearestInCorridor(wall), 1.5)
        XCTAssertNil(nearestInCorridor(Array(wall.prefix(39))))
        XCTAssertTrue(isEmergency([(t: 0, d: 1.4), (t: 0.5, d: 0.9)], rotationRate: 0))
        XCTAssertFalse(isEmergency([(t: 0, d: 0.9), (t: 0.5, d: 0.9)], rotationRate: 0))   // stationary rule
        XCTAssertEqual(alertPhrase(label: "cart", steer: .left), "Cart ahead, steer left")
    }

    func testSpeechQueuePreemptsAndDropsStale() {
        var q = SpeechPriorityQueue()
        _ = q.push(SpeechLine(text: "guide", priority: .guidance, createdAt: 0))
        _ = q.next(now: 0)
        XCTAssertTrue(q.push(SpeechLine(text: "Cart ahead", priority: .danger, createdAt: 1)))
        _ = q.push(SpeechLine(text: "old", priority: .narration, createdAt: 1))
        XCTAssertNil(q.next(now: 10))
    }
}
