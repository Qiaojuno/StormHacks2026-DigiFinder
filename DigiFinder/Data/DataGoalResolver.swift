import Foundation
import DigiFinderCore

/// The router's product search (§5.2): spoken product phrase → goal, and goal → candidates for the shelf.
///
/// Goal fields come only from the user's words (§3.3): `product` is the phrase as said, `brand` is set only when the
/// user said a database brand, `form` and `variant` are other words they said. The database supplies the aisle
/// (`category`, a vote over the best matches) and the candidates. Without the database, `extraProducts` stand in
/// (and, last, the aisle words in categories.json).
///
/// Wire it as `RequestRouter(productSearch: resolver.goals(for:), destinations: catalog.destinations)`.
final class DataGoalResolver {
    let products: ProductDatabase?
    let catalog: Catalog

    /// A database brand counts only if at least this share of the products mentioning it carry it as their brand
    /// ("starbucks", "no name"), so product words that happen to be brands somewhere ("milk", "organic") don't.
    static let minBrandShare = 0.3
    /// "x and y" stays one product ("mac and cheese", "salt and vinegar chips") only if the phrase is common next to
    /// its sides; otherwise there is no match and the router splits it ("coffee and milk").
    static let minCompoundShare = 0.1
    static let minCompoundCount = 3
    /// Best matches sampled for the aisle vote.
    static let aisleVoteSample = 50
    /// Words that describe the form of a product rather than a variant.
    static let formPhrases: Set<String> = [
        "whole bean", "ground", "instant", "pods", "k cups", "capsules", "single serve", "bags", "tea bags", "loose leaf",
        "sliced", "shredded", "grated", "block", "powder", "liquid", "concentrate", "bottle", "can", "jar", "carton",
    ]

    private enum PhraseKind: Equatable { case form, synonym(String) }

    private struct Unit {
        enum Kind: Equatable { case word, phrase, synonym(String), compound(String, String) }
        let said: String
        let kind: Kind
        /// Any one of these phrases must match.
        let alternatives: [String]
    }

    private struct Parsed {
        var brand: (name: String, phrase: String)?
        var units: [Unit]

        func query(dropping skip: Int? = nil) -> DataSearchQuery {
            var q = DataSearchQuery()
            if let brand { q.add([brand.phrase]) }
            for (i, unit) in units.enumerated() where i != skip { q.add(unit.alternatives) }
            return q
        }
    }

    private struct Match { let query: DataSearchQuery; let products: [ProductInfo]; let dropped: Int? }

    private let phrases: [String: PhraseKind]
    private let maxPhraseWords: Int

    init(products: ProductDatabase?, catalog: Catalog) {
        self.products = products
        self.catalog = catalog
        var table: [String: PhraseKind] = [:]
        for form in Self.formPhrases { table[form] = .form }
        for canonical in catalog.synonyms.keys.sorted() {
            table[canonical] = .synonym(canonical)
            for alias in catalog.synonyms[canonical] ?? [] { table[alias] = .synonym(canonical) }
        }
        phrases = table
        maxPhraseWords = max(1, table.keys.map { $0.split(separator: " ").count }.max() ?? 1)
    }

    // MARK: Router search

    /// Goals for the already-normalized product phrase ("starbucks dark roast"); [] when nothing matches.
    /// Also [] for a leading "no" that isn't part of a brand ("no milk") and for "x and y" that isn't a known
    /// compound, so the router drops the "no" or splits the phrase (§5.2 rule 3).
    func goals(for query: String) -> [Goal] {
        let grocery = groceryGoals(for: query)
        // Household objects (owner decision): "my phone", "the remote", "mug" → found by their camera class.
        // An exact household word wins, keeping a database aisle when there is one ("bottle" in a store).
        let stripped = Self.words(query).drop { ["my", "the", "a", "an"].contains($0) }.joined(separator: " ")
        if let cls = MatchingHousehold.classes[stripped] {
            return [Goal(product: stripped, category: grocery.first?.category, visualClass: cls)]
        }
        if var g = grocery.first {
            if g.visualClass == nil { g.visualClass = groceryClass(for: g) }
            return [g] + grocery.dropFirst()
        }
        if let cls = MatchingHousehold.visualClass(for: query) { return [Goal(product: stripped, visualClass: cls)] }
        return []
    }

    private func groceryGoals(for query: String) -> [Goal] {
        let words = Self.words(query)
        guard !words.isEmpty, let parsed = parse(words, strict: true) else { return [] }
        guard let match = findMatch(parsed, aisle: nil, limit: Self.aisleVoteSample) else { return catalogFallback(words) }
        return [goal(words: words, parsed: parsed, match: match)]
    }

    /// A catalog visual class named like the product ("banana" → "Banana", "milk" → "Milk"), if any.
    private func groceryClass(for g: Goal) -> String? {
        let product = normalizeText(g.product)
        let classes = catalog.aisles.values.flatMap(\.visualClasses)
        return classes.first { normalizeText($0) == product }
            ?? classes.first { c in product.split(separator: " ").last.map { normalizeText(c) == String($0) } ?? false }
    }

    /// Products in the goal's aisle matching the user's words (hand-added products first). [] without a category
    /// (word-search goals have no candidates).
    func candidates(for goal: Goal, limit: Int = 30) -> [ProductInfo] {
        guard let aisle = goal.category, limit > 0 else { return [] }
        var words = Self.words(goal.product)
        if let brand = goal.brand.map(normalizeText), !brand.isEmpty,
           !" \(words.joined(separator: " ")) ".contains(" \(brand) ") {
            words = Self.words(brand) + words
        }
        let inAisle = catalog.extraProducts.filter { $0.aisle == aisle }
        guard !words.isEmpty, let parsed = parse(words, strict: false),
              let match = findMatch(parsed, aisle: aisle, limit: limit) else {
            return products == nil ? Array(inAisle.prefix(limit)) : []   // no database: the aisle's own extras
        }
        return Self.unique(extras(match.query, aisle: aisle) + match.products, limit: limit)
    }

    // MARK: Parsing

    /// Splits the words into brand + units. nil = can't be one product (see `goals(for:)`); `strict` only for goals.
    private func parse(_ words: [String], strict: Bool) -> Parsed? {
        let brand = findBrand(words)
        let inBrand: (Int) -> Bool = { brand?.range.contains($0) ?? false }
        if strict, words.first == "no", brand?.range.lowerBound != 0 { return nil }

        var compounds: [Int: (String, String)] = [:]                  // start index of "x" → (x, y)
        for k in words.indices where words[k] == "and" && !inBrand(k) {
            guard k > 0, k + 1 < words.count, !inBrand(k - 1), !inBrand(k + 1),
                  words[k - 1] != "and", words[k + 1] != "and" else { continue }   // stray "and"
            if strict, !isCompound(words, and: k, inBrand: inBrand) { return nil }
            compounds[k - 1] = (words[k - 1], words[k + 1])
        }

        var units: [Unit] = []
        var i = 0
        while i < words.count {
            if inBrand(i) || words[i] == "and" { i += 1; continue }
            if let pair = compounds[i] {
                let (x, y) = pair
                units.append(Unit(said: "\(x) and \(y)", kind: .compound(x, y), alternatives: ["\(x) \(y)", "\(x) and \(y)"]))
                i += 3
                continue
            }
            let blocked: (Int) -> Bool = { inBrand($0) || words[$0] == "and" || ($0 != i && compounds[$0] != nil) }
            let unit = phraseUnit(words, at: i, blocked: blocked)
            units.append(unit.unit)
            i += unit.length
        }
        return Parsed(brand: brand.map { (name: $0.name, phrase: $0.phrase) }, units: units)
    }

    /// Longest known phrase (synonym or form) starting at `i`, else the single word.
    private func phraseUnit(_ words: [String], at i: Int, blocked: (Int) -> Bool) -> (unit: Unit, length: Int) {
        let longest = min(maxPhraseWords, words.count - i)
        for length in stride(from: longest, through: 1, by: -1) {
            guard !(i..<(i + length)).contains(where: blocked) else { continue }
            let said = words[i..<(i + length)].joined(separator: " ")
            let kind = phrases[said] ?? (length == 1 ? Self.inflections(said).lazy.compactMap { self.phrases[$0] }.first : nil)
            switch kind {
            case .synonym(let canonical)?:
                let alternatives = [said, canonical] + (catalog.synonyms[canonical] ?? []) + Self.phraseInflections(said)
                return (Unit(said: said, kind: .synonym(canonical), alternatives: alternatives), length)
            case .form?:
                return (Unit(said: said, kind: .phrase, alternatives: [said] + Self.phraseInflections(said)), length)
            case nil:
                continue
            }
        }
        let word = words[i]
        return (Unit(said: word, kind: .word, alternatives: [word] + Self.inflections(word)), 1)
    }

    /// Longest (then leftmost) run of up to 4 words that is a brand.
    private func findBrand(_ words: [String]) -> (name: String, phrase: String, range: Range<Int>)? {
        for length in stride(from: min(4, words.count), through: 1, by: -1) {
            for start in 0...(words.count - length) {
                let run = words[start..<(start + length)]
                guard run.first != "and", run.last != "and", !run.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { continue }
                let phrase = run.joined(separator: " ")
                if let name = brandName(phrase) { return (name, phrase, start..<(start + length)) }
            }
        }
        return nil
    }

    /// The brand's display name if `phrase` is a hand-added brand, or a database brand that passes the share test.
    private func brandName(_ phrase: String) -> String? {
        if let extra = catalog.extraProducts.first(where: { normalizeText($0.brand ?? "") == phrase }) { return extra.brand }
        guard let db = products, let brand = db.brand(phrase) else { return nil }
        let mentions = db.count(DataSearchQuery().adding([phrase]))
        return Double(db.brandFamilyCount(phrase)) >= Self.minBrandShare * Double(max(mentions, 1)) ? brand.name : nil
    }

    /// "x and y" at `k`: is "x y" / "x and y" common compared with the sides on their own?
    private func isCompound(_ words: [String], and k: Int, inBrand: (Int) -> Bool) -> Bool {
        let x = words[k - 1], y = words[k + 1]
        let found = matchCount(DataSearchQuery().adding(["\(x) \(y)", "\(x) and \(y)"]), aisle: nil)
        guard found >= (products == nil ? 1 : Self.minCompoundCount) else { return false }
        func side(_ range: [Int]) -> Int {
            let text = range.filter { !inBrand($0) }.map { words[$0] }.joined(separator: " ")
            return matchCount(DataSearchQuery(words: text), aisle: nil)
        }
        var left: [Int] = [], right: [Int] = []
        var j = k - 1
        while j >= 0, words[j] != "and" { left.insert(j, at: 0); j -= 1 }
        j = k + 1
        while j < words.count, words[j] != "and" { right.append(j); j += 1 }
        return Double(found) >= Self.minCompoundShare * Double(min(side(left), side(right)))
    }

    // MARK: Matching

    /// All the user's words; if nothing matches and a brand was said, drop the one other unit that leaves the most
    /// matches ("starbucks dark roast pods" → Starbucks dark roast).
    private func findMatch(_ parsed: Parsed, aisle: String?, limit: Int) -> Match? {
        let query = parsed.query()
        let found = lookup(query, aisle: aisle, limit: limit)
        if !found.isEmpty { return Match(query: query, products: found, dropped: nil) }
        guard parsed.brand != nil, parsed.units.count >= 2 else { return nil }
        var best: (index: Int, count: Int)?
        for i in parsed.units.indices {
            let n = matchCount(parsed.query(dropping: i), aisle: aisle)
            if n > (best?.count ?? 0) { best = (i, n) }
        }
        guard let best else { return nil }
        let relaxed = parsed.query(dropping: best.index)
        let products = lookup(relaxed, aisle: aisle, limit: limit)
        return products.isEmpty ? nil : Match(query: relaxed, products: products, dropped: best.index)
    }

    /// Database matches, or hand-added products when the database has none (or is missing).
    private func lookup(_ query: DataSearchQuery, aisle: String?, limit: Int) -> [ProductInfo] {
        let found = products?.search(query, aisle: aisle, limit: limit) ?? []
        return found.isEmpty ? extras(query, aisle: aisle) : found
    }

    private func matchCount(_ query: DataSearchQuery, aisle: String?) -> Int {
        (products?.count(query, aisle: aisle) ?? 0) + extras(query, aisle: aisle).count
    }

    private func extras(_ query: DataSearchQuery, aisle: String?) -> [ProductInfo] {
        catalog.extraProducts.filter { (aisle == nil || $0.aisle == aisle) && query.matches(normalized: Self.text(of: $0)) }
    }

    // MARK: Goal

    private func goal(words: [String], parsed: Parsed, match: Match) -> Goal {
        let category = aisleVote(match)
        let inAisle = category.map { lookup(match.query, aisle: $0, limit: Self.aisleVoteSample) } ?? match.products
        let sample = inAisle.map(Self.text(of:))
        let info = category.flatMap { catalog.aisles[$0] }

        // Head words name the aisle itself ("coffee", "milk", "peanut butter"): not a variant.
        var heads = Set(([category].compactMap { $0 } + (info?.aisleWords ?? [])).map(normalizeText))
        heads.formUnion(heads.flatMap(Self.inflections))
        func isHead(_ s: String) -> Bool { heads.contains(s) || Self.inflections(s).contains(where: heads.contains) }
        // Multi-word descriptors from categories.json ("dark roast") stay together.
        let descriptors = Set((info?.productWords ?? []).map(normalizeText).filter { $0.contains(" ") })
        // A synonym stands for its canonical phrase only if that phrase is on the matched products
        // ("beans" → "whole bean" for Starbucks dark roast, but not for canned beans).
        func resolved(_ unit: Unit) -> String? {
            guard case .synonym(let canonical) = unit.kind else { return nil }
            if unit.said == canonical || sample.contains(where: { " \($0) ".contains(" \(canonical) ") }) { return canonical }
            return nil
        }

        var form: String?, formIndex: Int?
        for (i, unit) in parsed.units.enumerated() {
            switch unit.kind {
            case .synonym:
                if let canonical = resolved(unit), Self.isForm(canonical) { form = canonical }
            case .word, .phrase:
                if Self.isForm(unit.said) { form = unit.said }
            case .compound:
                break
            }
            if form != nil { formIndex = i; break }
        }

        var variant: [String] = []
        func add(_ s: String) { if !s.isEmpty, !isHead(s), !variant.contains(s) { variant.append(s) } }
        var i = 0
        while i < parsed.units.count {
            if i == formIndex { i += 1; continue }
            if let length = descriptorRun(parsed.units, at: i, skip: formIndex, descriptors: descriptors) {
                add(parsed.units[i..<(i + length)].map(\.said).joined(separator: " "))
                i += length
                continue
            }
            let unit = parsed.units[i]
            switch unit.kind {
            case .compound(let x, let y): add(x); add(y)
            case .synonym: if !isHead(unit.said) { add(resolved(unit) ?? unit.said) }
            case .word, .phrase: add(unit.said)
            }
            i += 1
        }

        var synonyms: [String] = []
        for unit in parsed.units {
            guard let canonical = resolved(unit) else { continue }
            for s in [canonical] + (catalog.synonyms[canonical] ?? []) where s != unit.said && !synonyms.contains(s) {
                synonyms.append(s)
            }
        }

        return Goal(brand: parsed.brand?.name, product: words.joined(separator: " "), variant: variant, form: form,
                    category: category, synonyms: synonyms)
    }

    /// Length (2–3) of a run of plain words at `i` that spells a multi-word descriptor of the aisle.
    private func descriptorRun(_ units: [Unit], at i: Int, skip: Int?, descriptors: Set<String>) -> Int? {
        guard !descriptors.isEmpty else { return nil }
        for length in stride(from: min(3, units.count - i), through: 2, by: -1) {
            let run = units[i..<(i + length)]
            guard !run.indices.contains(where: { $0 == skip }), run.allSatisfy({ $0.kind == .word }) else { continue }
            if descriptors.contains(run.map(\.said).joined(separator: " ")) { return length }
        }
        return nil
    }

    /// No database: a phrase that names an aisle in categories.json still gets the aisle.
    private func catalogFallback(_ words: [String]) -> [Goal] {
        guard products == nil, !catalog.aisles.isEmpty else { return [] }
        let phrase = words.joined(separator: " ")
        var canonical: String?
        if case .synonym(let c)? = phrases[phrase] { canonical = c }
        let keys = catalog.aisles.keys.sorted()
        for p in [phrase, canonical].compactMap({ $0 }) {
            guard let hit = aisleNamed(Set([p] + Self.inflections(p)), keys: keys) else { continue }
            let group = canonical ?? phrase
            let synonyms = ([group] + (catalog.synonyms[group] ?? [])).filter { $0 != phrase }
            return [Goal(product: phrase, category: hit, synonyms: synonyms)]
        }
        return []
    }

    /// Aisle key, then first aisle word, then any aisle word, then a product word unique to one aisle.
    private func aisleNamed(_ forms: Set<String>, keys: [String]) -> String? {
        func words(_ k: String) -> [String] { (catalog.aisles[k]?.aisleWords ?? []).map(normalizeText) }
        if let k = keys.first(where: forms.contains) { return k }
        if let k = keys.first(where: { words($0).first.map(forms.contains) ?? false }) { return k }
        if let k = keys.first(where: { words($0).contains(where: forms.contains) }) { return k }
        let byProductWords = keys.filter { k in
            (catalog.aisles[k]?.productWords ?? []).map(normalizeText).contains(where: forms.contains)
        }
        return byProductWords.count == 1 ? byProductWords[0] : nil
    }

    // MARK: Helpers

    private static func words(_ s: String) -> [String] {
        normalizeText(s).split(separator: " ").map(String.init)
    }

    /// Same text as the database's `search` column.
    private static func text(of p: ProductInfo) -> String {
        normalizeText("\(p.brand ?? "") \(p.name) \(p.quantity ?? "")")
    }

    /// The aisle holding most of the matched products (all of them, not just the best-ranked page);
    /// ties go to the aisle of the better-ranked match.
    private func aisleVote(_ match: Match) -> String? {
        var counts = products?.aisleCounts(match.query) ?? [:]
        for p in extras(match.query, aisle: nil) { if let a = p.aisle { counts[a, default: 0] += 1 } }
        if counts.isEmpty { for p in match.products { if let a = p.aisle { counts[a, default: 0] += 1 } } }
        var first: [String: Int] = [:]
        for (i, p) in match.products.enumerated() { if let a = p.aisle, first[a] == nil { first[a] = i } }
        return counts.max { a, b in
            a.value != b.value ? a.value < b.value : (first[a.key] ?? .max) > (first[b.key] ?? .max)
        }?.key
    }

    private static func unique(_ list: [ProductInfo], limit: Int) -> [ProductInfo] {
        var seen = Set<String>(), out: [ProductInfo] = []
        for p in list where out.count < limit && seen.insert(text(of: p)).inserted { out.append(p) }
        return out
    }

    private static func isForm(_ s: String) -> Bool {
        formPhrases.contains(s) || phraseInflections(s).contains(where: formPhrases.contains)
    }

    /// Singular/plural spellings of the last word ("whole beans" → "whole bean").
    private static func phraseInflections(_ phrase: String) -> [String] {
        var parts = phrase.split(separator: " ").map(String.init)
        guard let last = parts.popLast() else { return [] }
        let head = parts.joined(separator: " ")
        return inflections(last).map { head.isEmpty ? $0 : "\(head) \($0)" }
    }

    /// Singular/plural spellings of one word ("beans" → "bean", "cookie" → "cookies"); none for numbers or short words.
    static func inflections(_ w: String) -> [String] {
        guard w.count > 2, w.contains(where: \.isLetter), w.allSatisfy({ $0.isLetter }) else { return [] }
        let consonantY = w.hasSuffix("y") && !"aeiou".contains(w.dropLast().last ?? "a")
        if w.hasSuffix("ies") { return [String(w.dropLast(3)) + "y", String(w.dropLast())] }
        if ["oes", "ches", "shes", "xes", "sses"].contains(where: w.hasSuffix) { return [String(w.dropLast(2)), String(w.dropLast())] }
        if w.hasSuffix("s"), !w.hasSuffix("ss") { return [String(w.dropLast())] }
        if consonantY { return [String(w.dropLast()) + "ies"] }
        if ["ch", "sh", "x", "ss", "o"].contains(where: w.hasSuffix) { return [w + "es", w + "s"] }
        return [w + "s"]
    }
}
