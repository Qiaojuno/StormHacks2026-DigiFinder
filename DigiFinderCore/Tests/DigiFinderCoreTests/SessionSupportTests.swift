// Shared fixtures and a harness for the Session*Tests files, plus tests of the spoken-name helpers.
import XCTest
@testable import DigiFinderCore

enum SessionFixtures {
    /// Coffee and tea share a sign; breakfast is next to coffee; produce is recognized by YOLO classes.
    static let catalog: [String: AisleInfo] = [
        "coffee": AisleInfo(aisleWords: ["coffee", "tea"], productWords: ["dark roast"], visualClasses: ["Coffee"],
                            adjacent: ["tea", "breakfast"]),
        "tea": AisleInfo(aisleWords: ["tea", "coffee"], adjacent: ["coffee"]),
        "breakfast": AisleInfo(aisleWords: ["cereal", "breakfast"], adjacent: ["spreads", "coffee"]),
        "spreads": AisleInfo(aisleWords: ["peanut butter", "jam", "spreads"], adjacent: ["breakfast"]),
        "dairy": AisleInfo(aisleWords: ["dairy", "milk", "cheese"]),
        "produce": AisleInfo(aisleWords: ["produce", "fruit"], visualClasses: ["Banana", "Apple"]),
        "pasta": AisleInfo(aisleWords: ["pasta", "sauce"], adjacent: ["canned"]),
    ]
    static let coffee = Goal(product: "coffee", category: "coffee")
    static let darkRoast = Goal(brand: "Starbucks", product: "dark roast", form: "whole bean", category: "coffee")
    static let tea = Goal(product: "tea", category: "tea")
    static let milk = Goal(product: "milk", category: "dairy")
    static let peanutButter = Goal(product: "peanut butter", category: "spreads")
    static let bananas = Goal(product: "bananas", category: "produce")
    static let coffeeSign = AisleSign(number: "6", words: ["Coffee", "Tea"], clock: 9)
    static let shelfSign = AisleSign(words: ["Coffee"], clock: 9)
    static let darkRoastInfo = ProductInfo(code: "0762111206230", name: "Dark Roast", brand: "Starbucks", aisle: "coffee")

    static let signageWork = StreamWork(text: .fast, yoloFPS: 10)
    static let pointingWork = StreamWork(text: .fast, hands: true, yoloFPS: 10, shelfMode: true)
    static let holdUpWork = StreamWork(text: .accurate, barcodes: true, yoloFPS: 10, shelfMode: true)
}

/// Drives a session with an absolute tick clock (0.5 s ticks).
struct SessionHarness {
    var session: ShoppingSession
    private(set) var clock: Double = 1000

    init(online: Bool = false, started: Bool = true) {
        session = ShoppingSession(catalog: SessionFixtures.catalog)
        _ = session.handle(.tick(clock))
        if online { _ = session.handle(.system(.online(true))) }
        if started { _ = session.handle(.started) }
    }

    var state: SessionState { session.state }

    @discardableResult
    mutating func send(_ events: SessionEvent...) -> [Effect] { events.flatMap { session.handle($0) } }

    @discardableResult
    mutating func advance(_ seconds: Double) -> [Effect] {
        var effects: [Effect] = []
        var left = seconds
        while left > 1e-9 {
            let dt = min(0.5, left)
            clock += dt
            left -= dt
            effects += session.handle(.tick(clock))
        }
        return effects
    }

    @discardableResult
    mutating func startGoal(_ g: Goal) -> [Effect] { send(.routed(.product(g, .unspecified))) }

    /// From the opening question to "Point at the shelf…" via sign → arrival → turn → shelf sign.
    mutating func reachShelf(_ g: Goal = SessionFixtures.coffee) {
        startGoal(g)
        send(.signs([SessionFixtures.coffeeSign]))
        send(.arrivedAtAisle(clock: 9))
        send(.motion(yawDegrees: -90, steps: 0, walking: true))
        send(.signs([SessionFixtures.shelfSign]))
    }

    /// From the shelf to the hold-up check.
    mutating func grab(_ text: String = "Starbucks Dark Roast") {
        send(.pointed(PointedProduct(text: text, match: 0.95)))
    }
}

func said(_ effects: [Effect]) -> [String] {
    effects.compactMap { if case .say(let text, _) = $0 { return text } else { return nil } }
}

func said(_ effects: [Effect], _ priority: SpeechPriority) -> [String] {
    effects.compactMap { if case .say(let text, let p) = $0, p == priority { return text } else { return nil } }
}

func works(_ effects: [Effect]) -> [StreamWork] {
    effects.compactMap { if case .setWork(let w) = $0 { return w } else { return nil } }
}

final class SessionSupportTests: XCTestCase {
    func testGoalNamesComeFromTheUsersWords() {
        let s = ShoppingSession(catalog: SessionFixtures.catalog)
        XCTAssertEqual(s.name(SessionFixtures.darkRoast), "Starbucks dark roast, whole bean")
        XCTAssertEqual(s.name(Goal(brand: "Kicking Horse", product: "coffee")), "Kicking Horse coffee")
        XCTAssertEqual(s.name(Goal(brand: "No Name", product: "No Name peanut butter")), "No Name peanut butter")
        XCTAssertEqual(s.aisleName(SessionFixtures.darkRoast), "coffee")
        XCTAssertEqual(s.aisleName(SessionFixtures.peanutButter), "peanut butter")
        XCTAssertEqual(s.aisleName(Goal(product: "tahini")), "tahini")
    }

    func testPhraseHelpers() {
        XCTAssertEqual(SessionPhrases.list(["coffee", "tea", "milk"]), "coffee, tea and milk")
        XCTAssertEqual(SessionPhrases.findFirst(["coffee", "milk", "tea"]), "I'll find coffee first, then milk, then tea.")
        XCTAssertEqual(SessionPhrases.meters(0.8), "1 meter")
        XCTAssertEqual(SessionPhrases.stairs(StairsObservation(up: false, distance: 2.6)), "Stairs going down, 3 meters, 12 o'clock.")
        XCTAssertEqual(SessionPhrases.stairs(StairsObservation(up: true, distance: 4, steps: 10, more: true)),
                       "Stairs going up, more than 10 steps, 4 meters, 12 o'clock.")
        XCTAssertEqual(SessionGeometry.degrees(forClock: 9), -90)
        XCTAssertEqual(SessionGeometry.angle(-90, from: 90), 180)
    }

    func testFirstTickOnlySetsTheReference() {
        var s = ShoppingSession(catalog: [:])
        _ = s.handle(.tick(5000))
        XCTAssertEqual(s.state.now, 0)
        _ = s.handle(.tick(5000.5))
        XCTAssertEqual(s.state.now, 0.5)
        _ = s.handle(.tick(9000))                      // a long gap counts as at most 5 s
        XCTAssertEqual(s.state.now, 5.5)
    }
}
