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
}
