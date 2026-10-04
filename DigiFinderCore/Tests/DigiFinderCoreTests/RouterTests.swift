// Fake catalog: no SQLite, so `swift test` runs anywhere. Include speech-recognizer quirks
// (no punctuation, "um", "I'd like", apostrophes) and both sides of each tricky pair.
// The fake only matches exact names, so a passing row also proves the filler words were stripped.
import XCTest
@testable import DigiFinderCore

enum Kind: Equatable { case start(String), replace(String), add(String), goals, unknown(String), question, destination, command, none }

func kind(_ r: Request?) -> Kind {
    switch r {
    case .product(let g, .replace)?: return .replace(g.product)
    case .product(let g, .add)?: return .add(g.product)
    case .product(let g, .unspecified)?: return .start(g.product)
    case .products?: return .goals
    case .unknownProduct(let w, _)?: return .unknown(w)
    case .question?: return .question
    case .destination?: return .destination
    case .command?: return .command
    case nil: return .none
    }
}

final class RouterTests: XCTestCase {
    let router = RequestRouter(
        productSearch: { q in ["coffee", "milk", "peanut butter", "mac and cheese", "no name peanut butter"].contains(q) ? [Goal(product: q)] : [] },
        destinations: [.checkout: ["checkout"], .customerService: ["customer service", "help", "information"]])

    let cases: [(String, Kind)] = [
        ("coffee", .start("coffee")), ("where's the coffee", .start("coffee")),
        ("is there peanut butter", .start("peanut butter")), ("what aisle is the coffee in", .start("coffee")),
        ("um I'd like some milk", .start("milk")), ("help me find peanut butter", .start("peanut butter")),
        ("mac and cheese", .start("mac and cheese")), ("No Name peanut butter", .start("no name peanut butter")),
        ("actually peanut butter", .replace("peanut butter")), ("no milk instead", .replace("milk")),
        ("also milk", .add("milk")), ("coffee and milk", .goals),
        ("toothpaste", .unknown("toothpaste")), ("where is the bathroom", .unknown("bathroom")),
        ("is this peanut butter crunchy", .question),     // product words, but a question about the held item
        ("is this gluten free", .question), ("how much is this", .question),
        ("what does this sign say", .question), ("read the label", .question),
        ("bring me to checkout", .destination), ("find staff", .destination), ("help", .destination),
        ("repeat", .command), ("what's around me", .command), ("where am I", .command), ("skip item", .command),
        ("quieter", .command), ("more detail", .command), ("switch", .command), ("add it", .command),
        ("okay", .none), ("", .none),
    ]

    func testEveryPhrase() {
        for (phrase, expected) in cases {
            XCTAssertEqual(kind(router.route(phrase)), expected, "\"\(phrase)\"")
        }
    }

    // Wider phrasing: politeness, hesitations, more change-of-mind / addition forms, list separators,
    // built-in destination phrases, and both sides of the new tricky pairs.
    let moreCases: [(String, Kind)] = [
        ("um is this gluten free", .question), ("okay what does this say", .question),
        ("reading glasses", .unknown("reading glasses")),          // "read" only as a whole word
        ("ready to pay", .destination), ("where's the checkout", .destination), ("where do I pay", .destination),
        ("I need help", .destination), ("help me", .destination), ("can someone help me please", .destination),
        ("where is the information desk", .destination), ("I need to talk to someone who works here", .destination),
        ("help me find peanut butter please", .start("peanut butter")),
        ("which aisle has coffee", .start("coffee")), ("could you tell me where the coffee is", .start("coffee")),
        ("find me some coffee please", .start("coffee")), ("are there any coffee", .start("coffee")),
        ("do you have toothpaste", .unknown("toothpaste")), ("I'm looking for milk", .start("milk")),
        ("switch to milk", .replace("milk")), ("change it to coffee", .replace("coffee")),
        ("never mind get milk", .replace("milk")), ("I'd rather have milk", .replace("milk")),
        ("no, peanut butter", .replace("peanut butter")), ("actually I want coffee", .replace("coffee")),
        ("also get milk", .add("milk")), ("add milk to my list", .add("milk")), ("milk too", .add("milk")),
        ("can you also find coffee", .add("coffee")),
        ("coffee then milk", .goals), ("I'd like coffee and milk please", .goals), ("coffee and also milk", .goals),
        ("coffee and toothpaste", .unknown("coffee and toothpaste")),   // every part must match
        ("can you repeat that", .command), ("stop please", .command), ("um repeat", .command),
        ("skip the coffee", .command), ("nothing else", .command), ("I'm outside", .command), ("what do you see", .command),
        ("thank you", .none), ("no", .none), ("um", .none), ("yes", .none),
    ]

    func testMorePhrases() {
        for (phrase, expected) in moreCases {
            XCTAssertEqual(kind(router.route(phrase)), expected, "\"\(phrase)\"")
        }
    }

    func testCommandsAreSpecific() {
        XCTAssertEqual(router.route("repeat"), .command(.repeatLast))
        XCTAssertEqual(router.route("I'm inside"), .command(.outside(false)))
        XCTAssertEqual(router.route("I'm outside"), .command(.outside(true)))
        XCTAssertEqual(router.route("that's all"), .command(.thatsAll))
        XCTAssertEqual(router.route("add it"), .command(.addGoal))
        XCTAssertEqual(router.route("switch"), .command(.switchGoal))
        XCTAssertEqual(router.route("bring me to checkout"), .destination(.checkout))
        XCTAssertEqual(router.route("find staff"), .destination(.customerService))
        XCTAssertEqual(router.route("Is this gluten-free?"), .question("Is this gluten-free?"))   // raw transcript kept
    }

    func testSynonymFallback() {
        let r = RequestRouter(productSearch: { ["peanut butter", "milk"].contains($0) ? [Goal(product: $0)] : [] },
                              destinations: [:], synonyms: ["peanut butter": ["pb", "peanut spread"]])
        XCTAssertEqual(kind(r.route("pb")), .start("peanut butter"))
        XCTAssertEqual(kind(r.route("where's the peanut spread")), .start("peanut butter"))
        XCTAssertEqual(kind(r.route("also pb")), .add("peanut butter"))
        XCTAssertEqual(kind(r.route("pb and milk")), .goals)
        XCTAssertEqual(kind(router.route("pb")), .unknown("pb"))   // no synonyms → unknown item
    }

    func testRouteWithChangeKeepsMultiProductChange() {
        XCTAssertEqual(router.routeWithChange("actually coffee and milk").change, .replace)
        XCTAssertEqual(router.routeWithChange("also coffee and milk").change, .add)
        XCTAssertEqual(router.routeWithChange("coffee and milk").change, .unspecified)
        XCTAssertEqual(kind(router.routeWithChange("actually coffee and milk").request), .goals)
        XCTAssertEqual(router.routeWithChange("toothpaste instead").request, .unknownProduct("toothpaste", .replace))
        XCTAssertNil(router.routeWithChange("um").request)
    }

    func testDestinationsAreDeterministicAndAloneOnly() {
        let r = RequestRouter(productSearch: { _ in [] }, destinations: [
            .checkout: ["checkout", "self checkout", "express", "lane", "cash"],
            .customerService: ["customer service", "information", "service desk", "help"]])
        XCTAssertEqual(r.route("take me to self checkout"), .destination(.checkout))
        XCTAssertEqual(r.route("where is the service desk"), .destination(.customerService))
        XCTAssertEqual(r.route("information"), .destination(.customerService))
        XCTAssertNotEqual(r.route("help with cashews"), .destination(.checkout))   // whole words: "cash" ≠ "cashews"
        XCTAssertEqual(r.route("help with cashews"), .unknownProduct("with cashews", .unspecified))
    }
}
