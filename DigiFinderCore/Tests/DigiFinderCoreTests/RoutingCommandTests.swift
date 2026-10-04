import XCTest
@testable import DigiFinderCore

final class RoutingCommandTests: XCTestCase {
    private func parse(_ s: String) -> VoiceCommand? { VoiceCommandParser.parse(normalizeText(s)) }

    func testPhraseCoverage() {
        let cases: [(String, VoiceCommand)] = [
            ("stop", .stop), ("skip item", .stop), ("cancel that", .stop), ("never mind", .stop), ("next item", .stop),
            ("that's all", .thatsAll), ("I'm done", .thatsAll), ("nothing else", .thatsAll), ("no thanks", .thatsAll),
            ("that's it", .thatsAll), ("done shopping", .thatsAll),
            ("repeat", .repeatLast), ("say that again", .repeatLast), ("what was that", .repeatLast), ("sorry?", .repeatLast),
            ("quieter", .lessDetail), ("less detail", .lessDetail), ("shorter", .lessDetail), ("keep it short", .lessDetail),
            ("more detail", .moreDetail), ("tell me more", .moreDetail), ("more info", .moreDetail),
            ("what's around?", .whatsAround), ("where am I", .whatsAround), ("what do you see", .whatsAround),
            ("what's nearby", .whatsAround), ("where are we", .whatsAround),
            ("I'm outside", .outside(true)), ("we're outside", .outside(true)),
            ("I'm inside", .outside(false)), ("I'm in the store", .outside(false)), ("already inside", .outside(false)),
            ("done", .finishTalking), ("finished", .finishTalking),
            ("switch", .switchGoal), ("switch to it", .switchGoal), ("replace it", .switchGoal), ("swap", .switchGoal),
            ("add it", .addGoal), ("add it to my list", .addGoal), ("keep both", .addGoal), ("both", .addGoal),
        ]
        for (phrase, expected) in cases { XCTAssertEqual(parse(phrase), expected, "\"\(phrase)\"") }
    }

    func testPolitenessAtTheEdges() {
        XCTAssertEqual(parse("um, repeat that please"), .repeatLast)
        XCTAssertEqual(parse("can you repeat that"), .repeatLast)
        XCTAssertEqual(parse("okay stop"), .stop)
        XCTAssertEqual(parse("yes switch"), .switchGoal)
        XCTAssertEqual(parse("yeah add it"), .addGoal)
        XCTAssertEqual(parse("what's around me now"), .whatsAround)
        XCTAssertEqual(parse("quieter please"), .lessDetail)
    }

    func testStopNamingTheItem() {
        XCTAssertEqual(parse("skip the coffee"), .stop)
        XCTAssertEqual(parse("stop looking for milk"), .stop)
        XCTAssertEqual(parse("cancel peanut butter"), .stop)
        XCTAssertNil(parse("forget the coffee get milk instead"))   // change of mind, not a plain stop
        XCTAssertNil(parse("skip to milk"))
    }

    func testNotCommands() {
        for phrase in ["", "okay", "yes", "thank you", "coffee", "help", "is this gluten free", "milk please",
                       "add milk", "switch to milk", "where's the coffee", "more milk", "describe this"] {
            XCTAssertNil(parse(phrase), "\"\(phrase)\"")
        }
    }
}
