import XCTest
@testable import DigiFinderCore

final class MatchingTextTests: XCTestCase {
    func testNormalizeMatchesPythonNFKD() {
        XCTAssertEqual(normalizeText("Café Dark-Roast, 340g"), "cafe dark roast 340g")
        XCTAssertEqual(normalizeText("  Président's   Choice® "), "president s choice")
        XCTAssertEqual(normalizeText("ﬁne"), "fine")                 // NFKD ligature
        XCTAssertEqual(normalizeText("Straße"), "stra e")            // ß has no decomposition → dropped like the script
        XCTAssertEqual(normalizeText("Øko"), "ko")
        XCTAssertEqual(normalizeText("Crème brûlée"), "creme brulee")
        XCTAssertEqual(normalizeText("１２３"), "123")                 // full-width digits fold to ASCII
        XCTAssertEqual(normalizeText("½ price"), "1 2 price")
        XCTAssertEqual(normalizeText("?!"), "")
        XCTAssertEqual(normalizeText("İstanbul"), "istanbul")
        XCTAssertEqual(normalizeText("Ǆ"), "dz")
    }

    func testBarcodeAndHelpers() {
        XCTAssertEqual(normalizeBarcode("0 64200 11677 0"), "0064200116770")
        XCTAssertEqual(normalizeBarcode("5000159407236"), "5000159407236")
        XCTAssertEqual(normalizeBarcode("½"), "")
        XCTAssertEqual(normalizedWords("Dark-Roast"), ["dark", "roast"])
        XCTAssertTrue(containsPhrase("starbucks dark roast", "dark roast"))
        XCTAssertFalse(containsPhrase("instead", "tea"))
        XCTAssertTrue(containsPhrase("ripe bananas", "banana", allowPlural: true))
        XCTAssertFalse(containsPhrase("as", "a", allowPlural: true))
        XCTAssertTrue(withinEditDistance("starbuck", "starbucks", 1))
        XCTAssertFalse(withinEditDistance("tea", "teapot", 1))
    }

    func testFuzzyContainsIsWholeWord() {
        XCTAssertTrue(fuzzyContains("starbucks dark roast", "dark roast"))
        XCTAssertTrue(fuzzyContains("starbuck dark roast", "starbucks"))      // one OCR edit
        XCTAssertTrue(fuzzyContains("whole beans", "whole bean"))             // plural
        XCTAssertTrue(fuzzyContains("darkroast coffee", "dark roast"))        // OCR dropped a space
        XCTAssertTrue(fuzzyContains("star bucks", "starbucks"))               // OCR added a space
        XCTAssertFalse(fuzzyContains("instead of steak", "tea"))              // no substring hits
        XCTAssertFalse(fuzzyContains("pea soup", "tea"))                      // short words must be exact
        XCTAssertFalse(fuzzyContains("milk", ""))
        XCTAssertFalse(fuzzyContains("", "milk"))
    }
}

final class MatchingScoreTests: XCTestCase {
    let goal = Goal(brand: "Starbucks", product: "coffee", variant: ["dark roast"], form: "whole bean")

    func testScoreBands() {
        XCTAssertEqual(score("STARBUCKS Dark Roast Whole Bean 340g", goal), 1.0, accuracy: 1e-9)
        XCTAssertEqual(score("Starbucks Dark Roast Ground", goal), 0.8, accuracy: 1e-9)        // near miss: form
        XCTAssertEqual(score("Starbucks Pike Place whole bean", goal), 0.7, accuracy: 1e-9)    // near miss: variant
        XCTAssertEqual(score("Folgers Dark Roast whole bean", goal), 0)                         // wrong brand
        XCTAssertEqual(score("", goal), 0)
    }

    func testUnsaidDetailsCountAsMatched() {
        XCTAssertEqual(score("Dairyland 2% milk 4 L", Goal(product: "milk")), 1.0, accuracy: 1e-9)
        XCTAssertEqual(score("Cheerios", Goal(product: "milk")), 0)                              // nothing of the goal
        XCTAssertEqual(score("Kraft smooth", Goal(product: "peanut butter", synonyms: ["peanut spread"])), 0)
        XCTAssertGreaterThanOrEqual(score("Kraft peanut spread", Goal(product: "peanut butter", synonyms: ["peanut spread"])),
                                    MatchingThresholds.pointMatch)
    }

    func testCandidatesAndSynonymsAnchor() {
        let candidates = [ProductInfo(code: "1", name: "Pike Place Roast", brand: "Starbucks")]
        XCTAssertEqual(score("Starbucks Pike Place Roast", Goal(product: "coffee")), 0)
        XCTAssertEqual(score("Starbucks Pike Place Roast", Goal(product: "coffee"), candidates: candidates), 1.0, accuracy: 1e-9)
        let syn = MatchingSynonyms(["whole bean": ["beans", "wb"]])
        let g = Goal(product: "coffee", form: "whole bean")
        XCTAssertEqual(score("dark roast coffee beans", g), 0.8, accuracy: 1e-9)
        XCTAssertEqual(score("dark roast coffee beans", g, candidates: [], synonyms: syn), 1.0, accuracy: 1e-9)
    }
}

final class MatchingConfirmTests: XCTestCase {
    let dark340 = ProductInfo(code: "0012345678905", name: "Dark Roast Whole Bean", brand: "Starbucks", quantity: "340 g")
    let dark680 = ProductInfo(code: "0012345678912", name: "Dark Roast Whole Bean", brand: "Starbucks", quantity: "680 g")
    let ground = ProductInfo(code: "3", name: "Dark Roast Ground", brand: "Starbucks", quantity: "340 g")
    let plain = ProductInfo(code: "4", name: "Dark Roast", brand: "Starbucks", quantity: "340 g")

    func testSizeBreaksTies() {
        let r680 = confirmFromLabel("STARBUCKS DARK ROAST WHOLE BEAN 680 g", candidates: [dark340, dark680])
        XCTAssertEqual(r680?.0, dark680)
        XCTAssertEqual(r680?.1 ?? 0, 1.0, accuracy: 1e-9)
        let r340 = confirmFromLabel("Starbucks Dark Roast Whole Bean 12 OZ (340g)", candidates: [dark680, dark340])
        XCTAssertEqual(r340?.0, dark340)
    }

    func testSpecificNameWinsAndWrongFormLoses() {
        XCTAssertEqual(confirmFromLabel("Starbucks Dark Roast Whole Bean", candidates: [plain, dark340])?.0, dark340)
        let r = confirmFromLabel("Starbucks Dark Roast Ground coffee", candidates: [dark340, ground])
        XCTAssertEqual(r?.0, ground)
        XCTAssertGreaterThanOrEqual(r?.1 ?? 0, MatchingThresholds.confirm)
        XCTAssertLessThan(confirmFromLabel("Folgers Classic", candidates: [dark340])?.1 ?? 1, MatchingThresholds.confirm)
        XCTAssertNil(confirmFromLabel("", candidates: [dark340]))
        XCTAssertNil(confirmFromLabel("anything", candidates: []))
    }

    func testBarcodeWins() {
        XCTAssertEqual(confirmFromBarcode("012345678912", candidates: [dark340, dark680]), dark680)   // UPC-A padded
        XCTAssertNil(confirmFromBarcode("999", candidates: [dark340]))
        let r = confirmHeldItem(label: "Starbucks Dark Roast Whole Bean 340 g", barcode: "0012345678912", candidates: [dark340, dark680])
        XCTAssertEqual(r?.0, dark680)
        XCTAssertEqual(r?.1, 1)
        XCTAssertEqual(confirmHeldItem(label: "Starbucks Dark Roast Ground", barcode: nil, candidates: [dark340, ground])?.0, ground)
    }

    func testWrongItemLine() {
        let g = Goal(brand: "Starbucks", product: "coffee", variant: ["dark roast"], form: "whole bean")
        XCTAssertEqual(wrongItemLine(found: ground, goal: g), "That's ground, not whole bean.")
        let tea = ProductInfo(code: "5", name: "Earl Grey", brand: "Twinings")
        XCTAssertEqual(wrongItemLine(found: tea, goal: Goal(product: "coffee")), "That's Twinings Earl Grey, not coffee.")
    }
}

final class MatchingPriceTests: XCTestCase {
    func testPriceTags() {
        for t in ["$4.99", "3.99", "12,99", "99¢", "1.29/lb", "$12.99/kg", "2 for 5.00", "4.99 each", "unit price 1.2",
                  "0.89 / 100 g", "3 99"] {
            XCTAssertTrue(isPriceTag(t), t)
        }
        for t in ["Starbucks Dark Roast 340 g", "Peach yogurt", "2% milk", "Heinz Beans 398 mL", "1.36 kg", "Pike Place",
                  "100% juice", "", "Kirkland Signature 2.25 oz"] {
            XCTAssertFalse(isPriceTag(t), t)
        }
    }
}

final class MatchingQuantityTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(MatchingQuantity.parse("340 g"), MatchingQuantity(value: 340, unit: .gram))
        XCTAssertEqual(MatchingQuantity.parse("1.36 kg"), MatchingQuantity(value: 1.36, unit: .kilogram))
        XCTAssertEqual(MatchingQuantity.parse("1,5 L"), MatchingQuantity(value: 1.5, unit: .liter))
        XCTAssertEqual(MatchingQuantity.parse("1,000 g")?.value, 1000)
        XCTAssertEqual(MatchingQuantity.parse("16.9 fl. oz (500 mL)"), MatchingQuantity(value: 16.9, unit: .fluidOunce))
        XCTAssertEqual(MatchingQuantity.parse("6 x 355 ml"), MatchingQuantity(value: 355, unit: .milliliter, packCount: 6))
        XCTAssertEqual(MatchingQuantity.parse("24 ct")?.unit, .count)
        XCTAssertEqual(MatchingQuantity.parse("Dark Roast 680g")?.value, 680)
        XCTAssertEqual(MatchingQuantity.all(in: "12 OZ (340g)").count, 2)
        XCTAssertNil(MatchingQuantity.parse("Aisle 6"))
        XCTAssertNil(MatchingQuantity.parse(""))
    }

    func testCompareAndSpeak() {
        let oz = MatchingQuantity(value: 12, unit: .ounce), g = MatchingQuantity(value: 340, unit: .gram)
        XCTAssertTrue(oz.isSameAmount(as: g))
        XCTAssertFalse(g.isSameAmount(as: MatchingQuantity(value: 680, unit: .gram)))
        XCTAssertFalse(g.isSameAmount(as: MatchingQuantity(value: 340, unit: .milliliter)))
        XCTAssertEqual(g.spoken(), "340 grams")
        XCTAssertEqual(g.spoken(plural: false), "340 gram")
        XCTAssertEqual(MatchingQuantity(value: 1, unit: .liter).spoken(), "1 liter")
        XCTAssertEqual(MatchingQuantity(value: 1.36, unit: .kilogram).spoken(), "1.36 kilograms")
        XCTAssertEqual(MatchingQuantity(value: 6, unit: .count, packCount: nil).spoken(), "6 count")
        XCTAssertEqual(MatchingQuantity(value: 800, unit: .gram).article, "an")
        XCTAssertEqual(MatchingQuantity(value: 11, unit: .ounce).article, "an")
        XCTAssertEqual(MatchingQuantity(value: 680, unit: .gram).article, "a")
    }

    func testAlternativeAndSpokenProduct() {
        let a = ProductInfo(code: "1", name: "Dark Roast", brand: "Starbucks", quantity: "340 g")
        let b = ProductInfo(code: "2", name: "Dark Roast", brand: "Starbucks", quantity: "680 g")
        let c = ProductInfo(code: "3", name: "Pike Place", brand: "Starbucks", quantity: "800 g")
        let d = ProductInfo(code: "4", name: "Dark Roast 12 oz", brand: "Starbucks")
        let pack = ProductInfo(code: "5", name: "Dark Roast", brand: "Starbucks", quantity: "6 x 340 g")
        XCTAssertEqual(variantAlternativeLine(current: a, candidates: [a, c, b]), "There's also a 680 gram one.")
        XCTAssertNil(variantAlternativeLine(current: a, candidates: [a, c, d]))      // 12 oz is the same size
        XCTAssertEqual(variantAlternativeLine(current: a, candidates: [pack]), "There's also a 6 pack.")
        XCTAssertNil(variantAlternativeLine(current: ProductInfo(code: "6", name: "Dark Roast"), candidates: [b]))
        XCTAssertEqual(spokenProduct(a), "Starbucks Dark Roast, 340 grams")
        XCTAssertEqual(spokenProduct(a, brand: false), "Dark Roast, 340 grams")
        XCTAssertEqual(spokenProduct(ProductInfo(code: "", name: "Starbucks Dark Roast", brand: "Starbucks")), "Starbucks Dark Roast")
    }
}

final class MatchingSynonymTests: XCTestCase {
    let syn = MatchingSynonyms(["whole bean": ["beans", "wb"], "peanut butter": ["pb", "peanut spread"]])

    func testGroups() {
        XCTAssertEqual(syn.canonical(for: "PB"), "peanut butter")
        XCTAssertNil(syn.canonical(for: "milk"))
        XCTAssertEqual(syn.alternatives(for: "pb"), ["pb", "peanut butter", "peanut spread"])
        XCTAssertEqual(syn.alternatives(for: "crunchy pb"), ["crunchy pb", "crunchy peanut butter", "crunchy peanut spread"])
        XCTAssertEqual(syn.alternatives(for: "milk"), ["milk"])
        XCTAssertEqual(syn.canonicalize("crunchy pb and wb coffee"), "crunchy peanut butter and whole bean coffee")
        XCTAssertEqual(MatchingSynonyms.none.alternatives(for: "x"), ["x"])
        XCTAssertTrue(MatchingSynonyms([:]).groups.isEmpty)
    }
}

final class MatchingAisleTests: XCTestCase {
    let catalog: [String: AisleInfo] = [
        "coffee": AisleInfo(aisleWords: ["coffee", "tea"], productWords: ["dark roast", "starbucks", "great value", "latte"],
                            visualClasses: ["Coffee"], adjacent: ["tea", "breakfast"]),
        "tea": AisleInfo(aisleWords: ["tea", "coffee"], productWords: ["twinings", "earl grey", "great value", "latte"],
                         adjacent: ["coffee"]),
        "produce": AisleInfo(aisleWords: ["produce", "fruit"], productWords: ["banana"], visualClasses: ["Banana", "Apple"]),
        "breakfast": AisleInfo(aisleWords: ["cereal"], productWords: ["cheerios"], adjacent: ["coffee"]),
    ]

    func testMaps() {
        let words = AisleVote.wordToAisle(catalog)
        XCTAssertEqual(words["coffee"], "coffee")
        XCTAssertEqual(words["tea"], "tea")
        XCTAssertEqual(words["starbucks"], "coffee")
        XCTAssertEqual(words["earl grey"], "tea")
        XCTAssertNil(words["great value"])          // listed by two aisles → no vote
        XCTAssertNil(words["latte"])
        XCTAssertEqual(words["cereal"], "breakfast")
        XCTAssertNil(AisleVote.wordToAisle(catalog, includeAisleWords: false)["cereal"])
        let classes = AisleVote.classToAisle(catalog)
        XCTAssertEqual(classes["Banana"], "produce")
        XCTAssertEqual(classes["Coffee"], "coffee")
    }

    func testVoteIsWholeWordSpecificAndOnce() {
        let words = AisleVote.wordToAisle(catalog)
        var v = AisleVote()
        v.addText("Starbucks Dark Roast", wordToAisle: words)
        v.addText("STARBUCKS dark-roast", wordToAisle: words)     // same label again
        v.addText("Instead", wordToAisle: words)                   // "tea" inside a word doesn't vote
        v.addText("Twinings Earl Grey", wordToAisle: words)
        v.addText("Ripe bananas", wordToAisle: words)              // plural
        XCTAssertEqual(v.counts, ["coffee": 1, "tea": 1, "produce": 1])
        XCTAssertEqual(v.evidence(for: "coffee"), ["dark roast"])   // longest match wins (ties alphabetical)
        v.addVisual(trackID: 7, yoloClass: "banana", classToAisle: AisleVote.classToAisle(catalog))   // case-insensitive
        v.addVisual(trackID: 7, yoloClass: "Banana", classToAisle: AisleVote.classToAisle(catalog))   // same object
        XCTAssertEqual(v.counts["produce"], 2)
        XCTAssertEqual(v.total, 4)
        XCTAssertEqual(v.share(of: "produce"), 0.5, accuracy: 1e-9)
        XCTAssertNil(v.verdict())
        v.reset()
        XCTAssertEqual(v.total, 0)
    }

    func testVerdictAndRelation() {
        var v = AisleVote()
        let classes = AisleVote.classToAisle(catalog)
        for i in 0..<5 { v.addVisual(trackID: i, yoloClass: "Banana", classToAisle: classes) }
        v.addText("Earl Grey", wordToAisle: AisleVote.wordToAisle(catalog))
        XCTAssertEqual(v.verdict(), "produce")                     // 5 of 6 ≥ 60 %
        XCTAssertNil(v.verdict(minVotes: 7))
        XCTAssertEqual(aisleRelation(verdict: "coffee", target: "coffee", catalog: catalog), .target)
        XCTAssertEqual(aisleRelation(verdict: "tea", target: "coffee", catalog: catalog), .adjacent)
        XCTAssertEqual(aisleRelation(verdict: "coffee", target: "breakfast", catalog: catalog), .adjacent)
        XCTAssertEqual(aisleRelation(verdict: "produce", target: "coffee", catalog: catalog), .different)
        XCTAssertEqual(aisleRelation(verdict: nil, target: "coffee", catalog: catalog), .unsure)
        XCTAssertEqual(aisleRelation(verdict: "coffee", target: nil, catalog: catalog), .unsure)
    }

    func testSignsAndWordSearch() {
        let coffee = Goal(product: "coffee", category: "coffee")
        XCTAssertTrue(signMatches(AisleSign(number: "6", words: ["Coffee", "Tea"], clock: 9), goal: coffee, catalog: catalog))
        XCTAssertFalse(signMatches(AisleSign(words: ["Cereal"], clock: 12), goal: coffee, catalog: catalog))
        XCTAssertEqual(signMatchedTerms(["Coffee & Tea"], goal: coffee, catalog: catalog), ["coffee", "tea"])
        let tahini = Goal(product: "tahini", signWords: ["sesame pastes", "spreads"])
        XCTAssertEqual(signTerms(for: tahini, catalog: catalog), ["tahini", "sesame pastes", "spreads"])
        XCTAssertEqual(signMatchedTerms(["Aisle 4", "Spreads", "Honey"], goal: tahini, catalog: catalog), ["spreads"])
        XCTAssertEqual(signMatchedTerms(["Tahinni"], goal: tahini, catalog: catalog), ["tahini"])   // OCR typo, 5+ letters
        XCTAssertTrue(signMatchedTerms([], goal: tahini, catalog: catalog).isEmpty)
        XCTAssertEqual(aisleForSign(["Coffee", "Tea"], catalog: catalog), "coffee")
        XCTAssertEqual(aisleForSign(["Tea", "Coffee"], catalog: catalog), "tea")
        XCTAssertEqual(aisleForSign(["Fresh Fruit"], catalog: catalog), "produce")
        XCTAssertNil(aisleForSign(["Exit"], catalog: catalog))
        XCTAssertTrue(wordSearchLabelMatches("Cedar's Tahini 454 g", goal: tahini))
        XCTAssertFalse(wordSearchLabelMatches("Kraft Peanut Butter", goal: tahini))
        let syn = MatchingSynonyms(["peanut butter": ["pb"]])
        XCTAssertTrue(wordSearchLabelMatches("Kraft Peanut Butter", goal: Goal(product: "pb"), synonyms: syn))
    }

    func testDestinationSigns() {
        let dest: [Destination: [String]] = [.customerService: ["customer service", "information", "service desk", "help"],
                                             .checkout: ["checkout", "self checkout", "express", "lane", "cash"]]
        XCTAssertEqual(destinationForSign(["Customer Service"], destinations: dest), .customerService)
        XCTAssertEqual(destinationForSign(["Information"], destinations: dest), .customerService)
        XCTAssertEqual(destinationForSign(["Self Checkout"], destinations: dest), .checkout)
        XCTAssertEqual(destinationForSign(["Lane 4", "Express"], destinations: dest), .checkout)
        XCTAssertNil(destinationForSign(["Nutrition information per serving size"], destinations: dest))
        XCTAssertNil(destinationForSign(["Cashews"], destinations: dest))
    }
}
